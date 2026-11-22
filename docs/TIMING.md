# TIMING — 第一次 STA（2026-11-22）

## 量測環境

| 項目 | 值 |
|---|---|
| 工具 | Yosys 0.52 + nextpnr-ecp5 0.9 |
| 元件 | LFE5U-85F，CABGA381 |
| 約束 | 300 MHz（3.333 ns），SDC 見 `constraints/order_book.sdc` |
| 設計 | `order_book_top`（depth 輸出不接腳，只保留邏輯） |
| 規模 | 1,914 LUT4、512 FF、0 BRAM |

## 為什麼要 wrapper

完整 `order_book` 把 `bid_levels`/`ask_levels` 拉成埠：16 級 × 16 bit × 2 = **512 根**，
加上其他訊號共 **580 根 I/O**，但 CABGA381 只有 **365** 根 → nextpnr 直接失敗：

```
ERROR: Unable to place cell 'bid_levels[170]$tr_io', no BELs remaining
```

`rtl/order_book_top.sv` 把 depth 埠留空，合成會移除未使用的輸出邏輯，
但保留所有餵給最佳價的暫存器（critical path 仍在）。修正後 I/O 降到 68 根。

## 結果

```
Info: Max frequency for clock 'clk': 95.65 MHz (FAIL at 300.00 MHz)
```

**實測 95.65 MHz，目標 300 MHz，差 3.1 倍。**

## 診斷

Critical path 是「16 級優先編碼掃描 + 16-bit 加法/比較」的**純組合路徑**，
在 ECP5（40nm）上約 10.4 ns。

這正是 ARCH §6 決策 D3 預期的問題：**掃描式最佳價無法隨 LEVELS 擴展**。
16 級已經只有 95 MHz，1024 級的延遲會更糟。

## 下一步（依效果排序）

1. **把 best_bid/best_ask 輸出打一拍**（+1 cycle）：切斷組合路徑，預期可到 150~200 MHz。
2. **掃描拆成兩級**（4 組 × 4 級 → 4 選 1）：邏輯深度從 16 降到 8，再加一拍。
3. **改用 bitmap + 兩層樹**（ARCH 原定方案）：O(log N) 深度，才有機會接近 300 MHz。
4. 若要 300 MHz 以上，最終仍需把比較/加法與選擇分成不同 pipeline stage。

## 實驗一：兩級管線（2026-11-22）

原本的 prototype 把「讀取當前價位量 → 比較/加減 → 寫回」全放在一個 cycle，
critical path 是 **mux 樹 + 16-bit 進位鏈串聯**（10.4 ns）。

`rtl/order_book_pipe2.sv` 把它拆成：

- **S1**：解碼命令、讀出 `cur_q`（只有 mux）
- **S2**：比較/加減、寫回（只有進位鏈）

| 版本 | Fmax | 說明 |
|---|---|---|
| `order_book`（單級） | **95.65 MHz** | mux + carry 串聯 |
| `order_book_pipe2`（兩級） | **154.58 MHz** | 拆開後 +62% |

三個 seed 的變異：95.82 / 91.75 / 93.43 MHz → **不是佈局運氣，是邏輯深度**。

### 新的瓶頸

拆開後 critical path 只剩 **16-bit 進位鏈**（CCU2C ×16，約 6.4 ns）。
在 ECP5（40nm）上，單一時脈內做完 16-bit 加減就是這個速度。

## 結論修正

- **300 MHz 在 ECP5 上不現實**：即使拆成兩級也只有 155 MHz。
- 同樣的 RTL 在 28nm FPGA（Kintex-7）預期可到 250~300 MHz——**但這是推測，沒有量測**。
- 若要真的 300 MHz，需要：(a) 更快的元件，或 (b) 把算術再切一級（會犧牲吞吐）。

## 實驗二：算術再切一級（2026-11-22）

把 16-bit 加減拆成兩個 8-bit 半（低半先算，carry/borrow 寄存，高半再加）：

| 版本 | 級數 | 延遲 | Fmax |
|---|---|---|---|
| `order_book` | 1 | 1 cycle | 95.65 MHz |
| `order_book_pipe2` | 2 | 2 cycles | 154.58 MHz |
| `order_book_pipe3` | 3 | 3 cycles | **155.86 MHz** |

**幾乎沒有進步（+0.8%），但多了一拍延遲。**

critical path 仍然走 CCU2C 進位鏈，但拆成 8 bit 後邏輯只佔約 3.1 ns，
其餘 3.3 ns 是 routing。也就是說：**在 ECP5 上，這個結構的瓶頸已經從邏輯變成繞線**。

結論：**不要用 pipe3。** 多一拍換不到頻率。

## 實驗三：Kintex-7（28nm）評估

沒有 Vivado，無法量測。/ 用 Yosys `synth_xilinx -family xc7` 先估資源：

| 資源 | 數量 |
|---|---|
| LUT（LUT1~LUT6 合計） | **787** |
| FDCE（正反器） | 594 |
| CARRY4 | 11 |
| BUFG / IBUF / OBUF | 1 / 26 / 42 |

以 xc7k325t（326k logic cells）來說，面積佔用不到 1%。
**瓶頸不會是資源，只會是時序**，而時序需要 Vivado 才能量。

已備好 `scripts/vivado_timing.tcl`，在有 Vivado 的機器上執行即可得到 WNS：

```
vivado -mode batch -source scripts/vivado_timing.tcl
```

## 結論修正

- **ECP5 上這個結構的天花板約 155 MHz**，再加管線只會增加延遲，不會增加頻率。
- **300 MHz 在 ECP5 上不現實**；要嘛換元件（K7/Vivado），要嘛改結構（bitmap 樹、減少 mux 深度）。
- 若要用 ECP5，建議 SPEC 改成 **150 MHz**；若要用 K7，先量到 WNS 再定目標。

## 兩級管線變體（v0.1）的決策（2026-11-22）

- **兩級管線 + ECP5 150 MHz**。`order_book_pipe2` 已用同一組 222 筆刺激驗證通過
  （`make sim-pipe2`，0 warning），實測 154.58 MHz，符合 150 MHz 目標。
- 驗證已補齊：`tools/mutate_pipe2.py` **30 mutants / 29 killed / 1 equivalent / 0 survived**；
  `make coverage-pipe2` **RTL 44/44 = 100%**。
- **K7 / Vivado 暫緩**：完整 Vivado 安裝需要數十至上百 GB，且 325T 可能需要付費授權。
  量測腳本 `scripts/vivado_timing.tcl` 已備好，等有環境再跑。
- **300 MHz 不在 v1 範圍**：ECP5 的極限約 155 MHz（繞線主導），要更快得換元件或改結構。

## v1.1 方向：bitmap 樹

v1 的 critical path 有兩個來源：16-way 掃描（mux 樹）與 16-bit 算術（進位鏈）。
v1.1 要把掃描換成 bitmap + 兩層樹，把 O(N) 深度換成 O(log N)，
同時讓吞吐回到 1 event/cycle。詳見 `docs/PLAN.md`。

## 誠實註記

- `order_book_pipe2` 已通過 222 筆功能對拍，但**尚未做突變測試**（現有 30 個 mutant 是針對單級版）。
- `order_book_pipe3` 仍是**未驗證的時序實驗**，且量測顯示沒有價值，不建議使用。
- 95.65 / 154.58 / 155.86 MHz 都是 nextpnr 佈局後估計，不是 Vivado 簽核數字。
- K7 的 250~300 MHz 是**推測**，本文件沒有任何 K7 時序量測。
- 每次改動都應重跑 `make pnr` / `make pnr-pipe2` / `make sim-pipe2`，並把結果記回本文件。
