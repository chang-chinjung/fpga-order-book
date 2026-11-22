# SPEC — LOB Core v1（限價訂單簿核心）

| 項目 | 內容 |
|---|---|
| 文件版本 | 0.1（草案，2026-11-21） |
| 狀態 | 待審 |
| 範圍 | 單一商品、order-by-order 限價訂單簿硬體核心 |
| 不在範圍 | 撮合引擎、策略、風控、下單、多商品路由 |

---

## 1. 目的

在 FPGA 上維護一份**與交易所一致的限價訂單簿**，並在固定且可預測的延遲內輸出最佳買賣價與深度，供下游策略與風控使用。

本核心只回答三個問題：

1. 現在最佳買價／賣價與其數量是多少？
2. 前 N 檔深度長什麼樣子？
3. 某張訂單還在不在？在哪個價位、排第幾？

**它不做撮合。** 撮合是交易所的事；本核心是「重建交易所已公布的狀態」。

## 2. 名詞

| 名詞 | 定義 |
|---|---|
| event | 一筆市場資料事件：ADD / CANCEL / REDUCE / TRADE |
| level | 價格階梯上的一個價位（tick index），不是價格本身 |
| queue position | 某張訂單在同價位 FIFO 中的序號（0 = 最前面） |
| seq | 交易所事件序號，用於偵測漏包 |
| snapshot | 某一時刻的完整簿狀態 |
| delta | 一次事件造成的變化 |

## 3. 功能需求

編號規則：`REQ-F-xxx` 功能、`REQ-N-xxx` 非功能、`REQ-I-xxx` 介面。

### 3.1 事件處理

| ID | 需求 | 優先級 |
|---|---|---|
| REQ-F-001 | 核心**必須**支援 ADD：給定 order_id、side、tick_index、qty，插入該價位 FIFO 尾端 | Must |
| REQ-F-002 | 核心**必須**支援 CANCEL：依 order_id 移除整張訂單 | Must |
| REQ-F-003 | 核心**必須**支援 REDUCE：依 order_id 減量，減到 0 視同移除 | Must |
| REQ-F-004 | 核心**必須**支援 TRADE：依 tick_index 從該價位 FIFO **頭端**扣量（價格優先、時間優先） | Must |
| REQ-F-005 | 同一 cycle **必須**能接受一筆事件；`ready` 為低時上游**必須**保留事件 | Must |
| REQ-F-006 | 未知 order_id 的 CANCEL/REDUCE **必須**丟棄並計數，不得改變簿狀態 | Must |
| REQ-F-007 | 重複 order_id 的 ADD **必須**依 `dup_policy` 設定處理（reject 或 replace），預設 reject | Should |
| REQ-F-008 | 同價位訂單**必須**維持 FIFO 順序；TRADE 只能從頭端扣 | Must |

### 3.2 輸出

| ID | 需求 | 優先級 |
|---|---|---|
| REQ-F-010 | 每次事件後，若最佳價或最佳量改變，**必須**在 `LATENCY_CYCLES` 內輸出 delta | Must |
| REQ-F-011 | 核心**必須**提供 5 檔深度查詢（每檔：tick_index、總量、訂單數） | Must |
| REQ-F-012 | 核心**必須**提供 order_id 查詢：存在與否、所在 tick_index、queued qty、queue position | Must |
| REQ-F-013 | 深度輸出**必須**標記 `valid` 與 `side`；空簿時 `valid=0` | Must |
| REQ-F-014 | 核心**必須**輸出累計事件計數與錯誤計數（per type） | Should |

### 3.3 錯誤與復原

| ID | 需求 | 優先級 |
|---|---|---|
| REQ-F-020 | 核心**必須**檢查 `seq` 連續性；跳號時**必須**設定 `gap_sticky` 並遞增 `err_seq_gap` | Must |
| REQ-F-021 | `gap_sticky` 為 1 時，所有輸出 delta **必須**標記 `stale=1`，直到收到 snapshot 重載 | Must |
| REQ-F-022 | 核心**必須**支援 snapshot 載入模式：連續寫入 level/order 狀態後，以 `snapshot_done` 原子切換 | Must |
| REQ-F-023 | 佇列滿（order store 或 level FIFO 滿）時**必須**丟棄新事件、遞增 `err_overflow`，不得覆寫既有訂單 | Must |
| REQ-F-024 | 所有丟棄事件**必須**可透過 AXI4-Lite 讀取原因計數器 | Should |

## 4. 非功能需求

| ID | 需求 | 目標值 | 驗證方式 |
|---|---|---|---|
| REQ-N-001 | 事件到最佳價輸出的延遲 | ≤ 10 cycles，**固定**（data-independent）；v1 實測 2 cycles | 模擬量測 |
| REQ-N-002 | 吞吐 | v1：1 event / 2 cycles（兩級管線）；v1.1 目標 1 event/cycle | 背靠背隨機事件 |
| REQ-N-003 | 時脈 | **150 MHz on LFE5U-85F (CABGA381)**；nextpnr 實測 154.58 MHz | nextpnr / Vivado |
| REQ-N-004 | 資源 | ≤ 40k LUT4、≤ 48 BRAM36；v1 實測 1,962 LUT4 / 512 FF / 0 BRAM | 合成報告 |
| REQ-N-005 | 容量 | 1,024 price levels、8,192 張活動訂單（可組態至 32,768） | 組態參數 |
| REQ-N-006 | 時脈域 | 核心單一時脈域；對外 CDC 只在 AXI-Stream 邊界 | 設計審查 |
| REQ-N-007 | 重置 | 同步重置，≤ 100 cycles 完成；支援 soft reset（不清組態） | 模擬 |
| REQ-N-008 | 確定性 | 相同輸入序列必得相同輸出，與時序無關 | 重跑比對 |

## 5. 介面需求

### 5.1 事件輸入：AXI4-Stream Slave（64-bit）

| 欄位 | 寬度 | 說明 |
|---|---|---|
| `tdata[63:0]` | 64 | 見下表 |
| `tvalid` / `tready` | 1 / 1 | 標準握手 |
| `tlast` | 1 | 保留（單筆事件 = 一個 beat） |

`tdata` 編碼：

| bits | 欄位 | 說明 |
|---|---|---|
| 63:62 | `op` | 0=ADD, 1=CANCEL, 2=REDUCE, 3=TRADE |
| 61 | `side` | 0=bid, 1=ask |
| 60:48 | `seq[12:0]` | 事件序號 |
| 47:32 | `order_id[15:0]` | TRADE 時可為 0 |
| 31:16 | `qty[15:0]` | 0 視為非法 |
| 15:0 | `tick_index[15:0]` | 價格階梯索引 |

### 5.2 深度輸出：AXI4-Stream Master（64-bit）

| 欄位 | 寬度 | 說明 |
|---|---|---|
| `op` | 2 | 0=best, 1=depth_delta, 2=stale |
| `side` | 1 | 0=bid, 1=ask |
| `tick_index` | 16 | 價位 |
| `qty` | 16 | 該價位總量 |
| `order_count` | 16 | 該價位訂單數（可選） |
| `stale` | 1 | 資料已不可信 |

### 5.3 控制與狀態：AXI4-Lite Slave

- 讀：計數器、組態、`gap_sticky`、版本號
- 寫：`dup_policy`、`snapshot_mode`、`soft_reset`、`snapshot_done`

### 5.4 時脈與重置

- `aclk`：核心時脈，300 MHz 目標
- `aresetn`：同步、低態有效
- 對外 CDC：輸入端非同步 FIFO（若 feed 時脈不同）；輸出端同理

## 6. 容量與組態參數

| 參數 | 預設 | 範圍 | 影響 |
|---|---|---|---|
| `NUM_LEVELS` | 1024 | 256~4096 | 價格階梯大小、bitmap 深度 |
| `MAX_ORDERS` | 8192 | 2048~32768 | order store 深度、直接映射範圍 |
| `QTY_W` | 16 | 16~24 | 數量上限 |
| `OID_W` | 16 | 16~24 | order_id 寬度 |
| `DEPTH_OUT` | 5 | 1~10 | 輸出檔數 |

## 7. 效能預算

| 項目 | 預算 | 說明 |
|---|---|---|
| 事件處理 | v1：1 event / 2 cycles（兩級管線） | 全管線化；v1.1 目標 1/cycle |
| 延遲 | 2 cycles | 見 ARCH §4 |
| 150 MHz 下延遲 | 13.3 ns | 不含 PHY 與網路 |
| 最大持續事件率 | 75 M events/s | 單一商品遠低於此 |

## 8. 驗收標準

全部通過才叫 v1：

1. **功能**：REQ-F-001~024 全部有對應測試。
2. **對拍**：10 萬筆隨機事件，與 Python 參考模型逐步一致（最佳價、深度、計數器）。
3. **突變測試**：注入 20 個已知 bug，測試套件**至少抓到 18 個**（存活率 ≤ 10%）。
4. **吞吐**：背靠背 1,000 萬筆事件，無氣泡、無遺失。
5. **時序**：300 MHz 下 WNS ≥ 0（Vivado/Quartus 報告）。
6. **資源**：符合 REQ-N-004。
7. **確定性**：同一序列跑 10 次，輸出 bit-identical。
8. **復原**：注入 seq gap → `stale` 拉高 → snapshot 重載 → 恢復正常，全程 ≤ 1,000 cycles。

## 9. 假設與限制

- 假設上游已把交易所協定正規化成 64-bit 事件；**協定解析不在本核心**。
- 假設單一商品；多商品用多個 instance 或加 instrument_id 擴充（v2）。
- 假設價格階梯已固定（tick size 不變）；變動 tick 需重載。
- **不處理**：改單（modify）以 cancel+add 表示；隱藏單；冰山單的顯示量與實際量差異。

## 10. 未決問題

| # | 問題 | 影響 | 建議 |
|---|---|---|---|
| Q1 | TRADE 事件沒有 order_id 時，如何處理「部分成交」與「跨價位」？ | 佇列正確性 | v1 只支援單價位 FIFO 扣量 |
| Q2 | 是否需要輸出「自己的 queue position」而非全市場？ | 策略介面 | v1 提供全市場，v2 加私有佇列 |
| Q3 | snapshot 來源是交易所或本地重建？ | 復原時間 | 假設外部提供 |
| Q4 | 多商品要不要共用 order store？ | 資源 | v2 再議 |
