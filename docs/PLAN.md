# PLAN — v1 與 v1.1

## 兩級管線變體（v0.1）：ECP5、150 MHz

**目標**：把已驗證的兩級管線版本變成 v0.1 的效能變體，並補齊驗證。

| 項目 | 現況 | 狀態 |
|---|---|---|
| RTL | `rtl/order_book_pipe2.sv` | ✅ |
| 功能驗證 | `make sim-pipe2` 222 steps 通過、0 warning | ✅ |
| 突變測試 | `tools/mutate_pipe2.py`：30 mutants、29 killed、1 equivalent、0 survived | ✅ 100% |
| 覆蓋率 | `make coverage-pipe2`：RTL 44/44 = **100%** | ✅ |
| 時序 | 154.58 MHz（nextpnr，ECP5 85F） | ✅ |
| 延遲 | 2 cycles | ✅ |
| 吞吐 | 1 event / 2 cycles | v1.1 再回到 1/cycle |

**v1 驗收全部達成**（模擬、突變、覆蓋率、Fmax ≥ 150 MHz）。

## v1.1：bitmap 樹

**動機**：v1 的 critical path 是「16-way 掃描 mux + 16-bit 算術」串聯；
其中掃描的深度隨 LEVELS 線性成長，1,024 級時不可行。

**結構**：

```
level occupancy bitmap (LEVELS bits)
        │
        ├── word summary (LEVELS/16 words, 16 bits each)
        │        │
        │        └── 64-bit top summary
        │
        └── 兩級優先編碼：top summary → word → bit → level index
```

- **更新**：只有 level 由 0→非 0（或反之）時才動 bitmap，O(1)。
- **查詢**：兩級優先編碼，深度 O(log16 N)，1,024 級約 3 級。
- **qty 讀取**：用算出的 level index 去 ladder RAM 讀（BRAM 1 cycle），
  與 bitmap 計算重疊，不增加延遲。

**預期**：1,024 級下掃描延遲從 ~10 ns 降到 ~2 ns；
算術仍是 16-bit 進位鏈，需要另一級管線（v1.1 目標 3 級、1 event/cycle）。

**進度（2026-11-22 稍晚）**：

- `rtl/order_book_v11.sv`（1,024 級、bitmap + 階梯）**功能 400 steps 通過**。
- **但放不進 ECP5**：價位陣列的 read-modify-write 是非同步讀，
  Yosys 無法推論 BRAM，2×1,024×16 全部變暫存器 → ~102k LUT4（122%）。
- 試著改成同步讀 + 輸出暫存，仍然一樣（非同步 `cur_q` 是根因）。
- **bitmap_best 不是可參數化的**：樹狀選擇器的索引寫死為 W=64（1,024 級），
  降到 256 級會出現 out-of-bounds 警告，結果不可用。
- P&R 時間：1,024 級 nextpnr 超過 20 分鐘未完成，不適合迭代。

**下一步（依序）**：

1. 把命令處理拆成 S1（發 BRAM 讀）/ S2（算新值）/ S3（寫回 + bitmap），
   這是 ARCH §3 原本的設計，也是 BRAM 能推論的前提。延遲 3~4 cycles。
2. 把 bitmap_best 的樹改成以 `$clog2(W)` 分層的通用版本，讓 256/1,024 都能用。
3. 迭代用 256 級（合成 ~1 分鐘），最後才跑 1,024 級。

**風險**：

| 風險 | 緩解 |
|---|---|
| BRAM 讀寫埠不足（同時讀 qty、寫更新） | 用 true dual-port，讀寫分埠 |
| back-to-back 同價位危障 | bypass/forwarding（ARCH §3.1 已規劃） |
| bitmap 與 ladder 不一致 | 不變量檢查（INV：total_qty≠0 ⇔ bitmap=1） |
| 1 event/cycle 與 3 級管線衝突 | 使用 skid buffer 與 forwarding，必要時接受 1/2 cycle |

**驗收**：1,024 級、1 event/cycle、Fmax ≥ 150 MHz on ECP5、突變分數 ≥ 90%。

## 順序

1. v1 收尾：mutant 清單改寫、覆蓋率、SPEC/ARCH 數字同步。
2. v1.1 設計：先寫 bitmap 模組 + 單獨 TB（不接 ladder），量 Fmax。
3. v1.1 整合：bitmap + ladder + 管線，跑同一組 222 筆對拍 + 新的 1,024 級隨機測試。
4. 之後才考慮 K7 / Vivado（需數十 GB 安裝空間）。
