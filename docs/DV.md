# DV — 驗證計畫與現況

> 原則：**測試從 SPEC 長出來，不是從程式碼長出來。**
> 突變分數是「測試有沒有牙齒」的量化指標，不是「設計正確」的證明。
> 最後更新：2026-11-22 00:20

## 1. 目前證據

| 項目 | 內容 | 結果 |
|---|---|---|
| Directed corner cases | 22 筆，見 §2 | pass |
| 隨機對拍 | 200 筆（ADD 60% / CANCEL 30% / TRADE 10%） | pass |
| 每步比對欄位 | best_bid/ask、qty、valid、全簿 checksum | 222 × 7 = 1,554 次 |
| 不變量檢查 | INV1~INV4（見 §3），每 cycle 檢查 | pass |
| 閒置週期檢查 | 每 5 步插入 2 個 idle cycle，狀態不得改變 | pass |
| 突變測試 | 30 個 mutant | **29 killed / 1 equivalent / 0 survived（100%）** |
| Lint | Verilator `-Wall` | 0 warning |
| 行覆蓋率 | `--coverage-line` + lcov 分檔 | **RTL 100%（35/35）；TB 66.4%（錯誤分支未執行，預期）** |

## 2. Corner case 清單

| # | 案例 | 為什麼重要 |
|---|---|---|
| 1 | 同價位連續 ADD 累加 | 加法與 total 更新 |
| 2 | boundary level 0 / 15 | 索引邊界 |
| 3 | over-cancel（取消量大於存量） | 飽和到 0，不得回繞 |
| 4 | exact cancel（剛好等於存量） | 移除後 `valid` 必須歸零 |
| 5 | bid 側 65535 再加 2 | 16-bit 回繞 |
| 6 | **ask 側 65535 再加 2** | 回繞（這個 case 是被突變測試逼出來的，見 §4） |
| 7 | TRADE 大量扣抵 | 與 CANCEL 共用路徑 |
| 8 | ask 在最低 level、bid 在最高 level | 掃描方向錯誤 |
| 9 | 空簿查詢 | `valid=0`，不得殘留 |
| 10 | 閒置週期（cmd_valid=0） | 狀態不得漂移 |

## 3. 不變量（獨立於 Python 模型）

| ID | 內容 |
|---|---|
| INV1 | `bid_valid == (bid_levels != 0)`；ask 同理 |
| INV2 | `best_bid_qty == bid_levels[best_bid]`；ask 同理 |
| INV3 | best bid 之上不得有非空 level |
| INV4 | best ask 之下不得有非空 level |

這四條只讀 DUT 輸出，不參考 model，所以能抓到「實作與模型共同誤解」的部分錯誤。

## 4. 突變測試：它真的抓到測試的洞

| 階段 | 結果 | 發現 |
|---|---|---|
| 初版 10 個 | 9 killed / 1 equivalent | 表面 100%，但樣本太小 |
| 擴到 20 個 | 18 killed / 1 survived | **`cmd_valid` gate 被移除卻存活** → TB 從未插入閒置週期 |
| 加 idle 檢查 | 19 killed / 0 survived | 補上「無命令時狀態不得改變」 |
| 擴到 30 個 | 28 killed / 1 survived | **ask 側 8-bit 截斷存活** → ask 側從未測大數量 |
| 加 ask 回繞 case | **29 killed / 1 equivalent / 0 survived** | 100%（等值突變不計分） |

**結論：突變測試的價值不在分數，在於它指出「測試沒想過的情境」。**
兩次存活都對應到真實的測試缺口，補完後才得到 100%。

## 5. 已知限制

1. **同作者盲點**：RTL 與 Python model 由同一人撰寫。
2. **無形式驗證**：沒有 SVA、沒有 BMC/induction。
3. **覆蓋率統計要分檔看**：Verilator 的「Total coverage」把 RTL 與 TB 混在一起（44%），會誤導。分檔後 RTL 是 100%，TB 是 66.4% —— 後者未執行的都是 `$display` 錯誤分支，本來就不該被觸發。`tools/cov_report.py` 會分開印，並且只對 RTL 設門檻（95%）。
4. **語意缺口**：prototype 沒有 FIFO / queue position，SPEC 的 REQ-F-004/008/012 無對應測試。
5. **突變樣本 30 個**：100% 只代表「這 29 個非等值 mutant 都抓得到」。
6. **無真實資料**：沒有交易所 replay。

## 6. 下一步

| 優先 | 工作 | 驗收 |
|---|---|---|
| P0 | 突變擴到 50 個（含時序、重置、溢位路徑） | score ≥ 90% |
| P1 | 形式：SymbiYosys BMC 深度 20 | 無反例 |
| P2 | 真實 tick replay | 與交易所最佳價一致 |

## 7. 執行方式

```bash
make sim                    # directed + random + invariants + idle
make coverage               # 行覆蓋率 + annotated 原始碼
python3 tools/mutate.py     # 突變測試，exit 0 = score ≥ 90%
```
