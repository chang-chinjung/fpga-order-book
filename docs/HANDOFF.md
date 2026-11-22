# HANDOFF — v0.1 狀態與後續工作

> 純技術紀錄。範圍：`fpga/order-book/`。最後更新：2026-11-22。

## 目前狀態

| 項目 | 結果 |
|---|---|
| 功能 RTL | level-indexed 價格階梯（無 FIFO、無 queue position） |
| 對拍 | 222 steps（22 directed + 200 隨機）全過 |
| 突變 | 30 mutants：29 killed / 1 equivalent / 0 survived = **100%** |
| 行覆蓋率 | RTL **100%（35/35）**；TB 66.4%（錯誤分支未執行，預期） |
| 合成 | ECP5：1,914 LUT4 / 512 FF |
| STA | 95.65 MHz（單級）、154.58 MHz（兩級管線） |
| 延遲 | 10.45 ns（單級）、12.94 ns（兩級） |

## 時間線（2026-11-21 夜間 ~ 11-22）

| 工作 | 結果 |
|---|---|
| 加 22 筆 directed corner case（含 ask 側回繞） | 222 steps pass |
| 加 INV1~INV4 不變量（獨立於 Python 模型） | 0 violation |
| `tools/mutate.py`：10 → 20 → 30 個 mutant | 兩次存活暴露測試缺口，修正後 100% |
| 發現 TB 從未插入閒置週期 | 加 idle 檢查後 `cmd_valid` gate mutant 被殺 |
| 發現 ask 側從未測大數量 | 加 65535+2 回繞 case 後殺掉 8-bit 截斷 mutant |
| 覆蓋率統計 | 合計 41% 是 RTL+TB 混算；分檔後 RTL 100% |
| `tools/cov_report.py` | 只對 RTL 設 95% 門檻 |
| 兩級管線 + TB | 222 steps pass、突變 100%、覆蓋率 100% |
| 三級管線（切算術） | 155.86 MHz，延遲 19.25 ns → **不採用** |
| 1,024 級 bitmap | 線性 66.49 MHz → 樹狀 81.45 MHz，仍未達標 |
| v1.1 整合（bitmap + ladder） | 功能 400 steps pass；合成 122% LUT，失敗 |

## 關鍵發現

1. **突變測試抓到的是測試的洞，不是 RTL 的 bug。**
   移除 `cmd_valid` gate 後測試全綠，因為 TB 每個 cycle 都送命令。補 idle 檢查才抓到。

2. **Fmax 不是延遲。**
   兩級管線 Fmax +62%，但延遲（10.45 → 12.94 ns）與吞吐都變差。

3. **非同步讀會殺死 BRAM 推論。**
   `cur_q = bid_q[cmd_level]` 讓 2×1,024×16 變成暫存器，LUT 爆到 102k。

## 可執行指令

```bash
make sim                   # 單級版 222 steps
make sim-pipe2             # 兩級版 222 steps
python3 tools/mutate.py    # 單級版突變（30 mutants）
python3 tools/mutate_pipe2.py
make coverage              # 分檔覆蓋率報告
make pnr                   # ECP5 P&R + Fmax（需 nextpnr-ecp5）
make pnr-bitmap            # 1,024 級 bitmap 實驗
```

## 下一步

1. 通用化 `bitmap_best`（目前樹狀索引寫死 W=64，只支援 1,024 級）。
2. 把命令處理拆成 S1（BRAM 讀）/ S2（算）/ S3（寫回），讓 1,024 級放得進 ECP5。
3. 迭代用 256 級（合成約 1 分鐘），最後才跑 1,024 級（P&R > 20 分鐘）。
4. 之後才是 v1.0：order store + FIFO + queue position（見 docs/VERSIONS.md）。

## 約束

- 不改 `fpga/order-book/` 以外的檔案。
- 不為了讓測試變綠而改 RTL 行為；要改先改 SPEC。
- 不把 `-Wno-fatal` 當成通過。

## 已知缺口

- prototype 的 TRADE 語意與 SPEC REQ-F-004（FIFO 頭端扣量）不同，是已知缺口，不是 bug。
- 所有 Fmax 都是 nextpnr 佈局後估計，不是 Lattice Diamond 簽核數字。
- 沒有真實交易所資料 replay。
