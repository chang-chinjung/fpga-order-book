# ARCH — LOB Core v1 架構設計

對應文件：[SPEC.md](SPEC.md)。本文說明「怎麼做」與「為什麼這樣做」。

---

## 1. 架構總覽

```
                 ┌──────────────────────────────────────────────────────────┐
  AXI-Stream     │  S0      S1        S2        S3        S4        S5      │   AXI-Stream
  events  ──────▶│ decode  ord_rd   resolve   ladder   bitmap   emit      ├──────▶ deltas
  (64b)          │  +seq   (BRAM)   hit/miss  RMW      update   +best     │  (64b)
                 │   │        │        │        │        │        │        │
                 └───┼────────┼────────┼────────┼────────┼────────┼────────┘
                     │        │        │        │        │        │
                ┌────▼────────▼────────▼────────▼────────▼────────▼────┐
                │  order store (8192 × 72b)   price ladder (1024 × 54b) │
                │  direct-mapped by order_id  qty/count/head/tail        │
                │                             summary bitmap (1024b)     │
                └─────────────────────────────────────────────────────────┘
                     ▲
                AXI4-Lite（計數器、組態、snapshot 模式、soft reset）
```

- **單一時脈域**：`aclk` 300 MHz。對外 CDC 只在 AXI-Stream 邊界（非同步 FIFO）。
- **固定延遲管線**：7 級，無資料相依分支。
- **無仲裁、無佇列**：上游 `tready` 只在管線真的滿時拉低（正常情況恆為 1）。

## 2. 資料結構

### 2.1 Order record（8192 × 72 bits，BRAM）

| 欄位 | 寬度 | 說明 |
|---|---|---|
| `order_id` | 16 | 交易所訂單編號（驗證用） |
| `price_idx` | 12 | 價位索引（0~1023） |
| `qty` | 16 | 剩餘量 |
| `side` | 1 | 0=bid, 1=ask |
| `prev` | 13 | 同價位前一張（FIFO 雙向鏈結） |
| `next` | 13 | 同價位下一張 |
| `valid` | 1 | 佔用旗標 |

**為何用直接映射而非 hash？** 見 §6 決策 D1。v1 假設上游已把 order_id remap 到 `[0, 8192)`（多數交易所的訂單號在單日內是遞增且稠密的；稀疏的情況由 upstream remap 表吸收）。這讓查表變成「一次 BRAM 讀」，延遲固定、無碰撞。

### 2.2 Price ladder（1024 × 54 bits，BRAM）

| 欄位 | 寬度 | 說明 |
|---|---|---|
| `total_qty` | 16 | 該價位總量 |
| `order_count` | 12 | 該價位訂單數 |
| `head` | 13 | FIFO 頭（queue position 0） |
| `tail` | 13 | FIFO 尾 |

### 2.3 Summary bitmap（1024 bits + 兩層樹）

- Level 0：1024 個「該價位是否非空」位元。
- Level 1：64 個 16-bit word，每個 word 是 16 個 level 的 OR。
- Level 2：64-bit summary，每個 bit 表示對應 word 是否非空。

**最佳買價**：對 summary 做「最高非零位」優先編碼 → 得 word index → 在該 word 內找最高位 → 得 level。
**最佳賣價**：同理取最低位。

更新成本：只有當某價位 **0↔非 0 轉換**時才需要動 bitmap（O(1)），不需要每次掃 1024 個 level。

### 2.4 深度輸出（5 檔）

不維護獨立結構：發出 delta 時，順便用 bitmap 走訪相鄰非空價位，補齊 5 檔。走訪最差 5 次優先編碼，但只在 delta 事件發生時做，且可與下一筆事件重疊（輸出端有 skid buffer）。

## 3. 管線

| 級 | 工作 | 關鍵路徑 | 資源 |
|---|---|---|---|
| S0 | 輸入暫存、op 解碼、seq 連續性檢查 | 比較器 + 加法 | FF |
| S1 | order store 讀（CANCEL/REDUCE/TRADE） | BRAM 讀 | BRAM |
| S2 | hit/miss 判定、新 qty 計算、slot 配置/釋放 | 加減法 + 飽和 | LUT |
| S3 | ladder 讀 | BRAM 讀 | BRAM |
| S4 | ladder 寫（total/count/head/tail）、bitmap 更新 | 加減法 + 位元運算 | LUT/FF |
| S5 | 最佳價優先編碼、delta 組裝 | 6 級 LUT | LUT |
| S6 | 輸出暫存（AXI-Stream） | — | FF |

**延遲 = 7 cycles ≈ 23.3 ns @ 300 MHz**（不含 PHY/網路，符合 REQ-N-001 ≤ 10 cycles）。

### 3.1 資料危障（back-to-back 同價位）

連續兩筆事件打到同一價位時，S3 讀到的 ladder 可能是 S4 尚未寫回的舊值。解法：

- **bypass 路徑**：S4 的寫入資料在 S3 讀取時比對 `price_idx`，相同則直接用 S4 的 forwarding 值。
- 成本：一組 54-bit 比較器 + mux，約 200 LUT。
- 這是**必須**的，否則高流量時簿會算錯（也是突變測試最該抓的 bug 之一）。

### 3.2 佇列操作

- ADD：`tail` 後接新節點，更新 `tail`、`count++`、`total += qty`。
- CANCEL：雙向鏈結移除，更新前後鄰居、`count--`、`total -= qty`。
- TRADE：從 `head` 扣量；`qty` 歸零則移除節點。
- 空價位：`head = tail = INVALID`，`count = 0`，`total = 0`。

所有指標操作都是 O(1)，沒有搜尋。

## 4. 延遲預算

| 區段 | cycles | ns @300MHz |
|---|---|---|
| S0 輸入+seq | 1 | 3.3 |
| S1 order BRAM 讀 | 1 | 3.3 |
| S2 resolve | 1 | 3.3 |
| S3 ladder BRAM 讀 | 1 | 3.3 |
| S4 ladder 寫+bitmap | 1 | 3.3 |
| S5 best + delta | 1 | 3.3 |
| S6 輸出暫存 | 1 | 3.3 |
| **合計** | **7** | **23.3** |

對照：軟體（CPU + kernel bypass）同等功能約 150~400 ns；FPGA 的價值在**確定性**，不只是平均值。

## 5. 資源估算

以 7 系列 / UltraScale 中階元件為基準（**估算值，需合成驗證**）：

| 區塊 | LUT | FF | BRAM36 | DSP |
|---|---|---|---|---|
| order store 8192×72 | ~200 | ~100 | 16 | 0 |
| price ladder 1024×54 | ~200 | ~100 | 2 | 0 |
| summary bitmap + 優先編碼 | ~1,200 | ~1,100 | 0 | 0 |
| 管線控制 + bypass | ~2,500 | ~3,000 | 0 | 0 |
| AXI-Stream / Lite | ~3,000 | ~3,500 | 0 | 0 |
| 計數器 / 錯誤處理 | ~500 | ~800 | 0 | 0 |
| **合計** | **~7,600** | **~8,600** | **18** | **0** |

餘裕很大，`MAX_ORDERS` 拉到 32,768 時 BRAM 約 66 顆，仍在多數中階元件範圍內。

## 6. 關鍵設計決策

| # | 決策 | 替代方案 | 為什麼選它 |
|---|---|---|---|
| D1 | order_id **直接映射** slot | hash table / CAM | hash 有碰撞→延遲不定或需要多次探測；CAM 面積爆炸。直接映射延遲固定 1 cycle，代價是要求上游 remap |
| D2 | 每價位**雙向鏈結 FIFO** | 環形緩衝 / 陣列搬移 | 鏈結 O(1) 插入/移除；環形緩衝無法 O(1) 移除中間訂單 |
| D3 | **bitmap + 兩層樹** 找最佳價 | 每次掃 1024 level | 掃描是 O(N) 且 critical path 長；bitmap 更新 O(1)、查詢 O(log N)，且 0↔非0 轉換才更新 |
| D4 | 深度輸出**用 delta + 走訪** | 維護 5 檔獨立 FIFO | 少一份狀態要同步，錯誤來源少一半 |
| D5 | **單一時脈域** | 多時脈域 | CDC 是 bug 溫床；只有在 AXI 邊界做 CDC |
| D6 | 錯誤**丟棄並計數**，不阻斷 | stall 等復原 | 交易系統不能停；`stale` 旗標讓下游自己決定 |

## 7. 錯誤與復原

### 7.1 seq gap

```
S0 偵測 seq != expected
   → gap_sticky <= 1
   → err_seq_gap++
   → 所有輸出 delta 帶 stale=1
   → 進入 snapshot 模式：寫入 level/order → snapshot_done
   → 原子切換指標 → gap_sticky <= 0
```

**原子切換**：用 double-buffer（兩份 ladder 指標）或「先寫影子區、done 時 swap base address」。v1 用後者，成本最低。

### 7.2 溢出

- order store 滿：丟棄 ADD，`err_overflow++`。
- 價位 FIFO 滿：理論上不會（受 order store 限制），但仍計數。

### 7.3 重置

- `aresetn`：全清（含組態）。
- `soft_reset`：清簿與計數器，保留組態與 `dup_policy`。

## 8. 驗證架構

| 層級 | 方法 | 工具 | 通過標準 |
|---|---|---|---|
| L1 單元 | directed test（每條 REQ 至少一個） | Verilator + SV TB | 全綠 |
| L2 對拍 | 10 萬筆隨機事件 vs Python 模型 | Verilator + `model/` | 0 mismatch |
| L3 突變 | 注入 20 個 bug | 腳本 + 既有 TB | 抓到 ≥ 18 |
| L4 形式 | SVA：佇列不變量、bitmap 一致性 | SymbiYosys（可選） | 無反例 |
| L5 壓力 | 背靠背 1,000 萬筆、同價位連續事件 | Verilator | 無氣泡、無錯誤 |
| L6 時序 | 300 MHz 合成 | Vivado/Quartus | WNS ≥ 0 |

### 8.1 SVA 不變量（草案）

```systemverilog
// 總量守恆：所有 level 的 total_qty 總和 == 所有活動訂單 qty 總和
// bitmap 一致：total_qty[i] != 0  <=>  bitmap[i] == 1
// 佇列一致：count == 鏈結長度
// 買賣不交叉：best_bid_idx < best_ask_idx
// 空簿：bid_valid == 0 && ask_valid == 0
```

**這四條不變量比任何 directed test 都值錢**，因為它們抓的是「實作與規格都沒想到」的錯。

## 9. 風險

| 風險 | 影響 | 緩解 |
|---|---|---|
| 300 MHz 收斂不了（優先編碼 critical path） | 延遲變大或降頻 | 把 S5 拆成兩級；或用 carry-chain 特化 |
| order_id 不稠密，直接映射失效 | 容量不足 | 上游 remap；或 v2 加 hash |
| back-to-back 同價位 hazard 漏掉 | 簿錯但不報錯 | 專屬壓力測試 + 突變測試 |
| snapshot 非原子 | 重建期間資料撕裂 | double-buffer + done 旗標 |
| TRADE 跨價位（一筆吃多檔） | 佇列扣量錯誤 | v1 假設單價位；v2 支援 |

## 10. 與現有 prototype 的差距

`rtl/order_book.sv` 目前是**最小可驗證版本**（level-indexed、無佇列）：

| 能力 | prototype | v1 目標 |
|---|---|---|
| 價位聚合 | ✅ | ✅ |
| 最佳價 | ✅（全掃） | ✅（bitmap 樹） |
| order-by-order 佇列 | ❌ | ✅ |
| queue position 查詢 | ❌ | ✅ |
| seq gap 偵測 | ❌ | ✅ |
| snapshot 重載 | ❌ | ✅ |
| 深度 5 檔輸出 | ❌ | ✅ |
| 延遲量測 | ❌ | ✅（7 cycles） |

**prototype 的價值是先把「lint → 對拍 → 波形」的流程打通**，不是它的功能。v1 會沿用同一套驗證骨架，把 RTL 換掉。

## 11. 實作順序（建議）

1. 把 prototype 的 `LEVELS=16` 擴到 1024 + bitmap 樹，量 fmax（先驗證 critical path）。
2. 加 order store 與雙向鏈結，先做 ADD/TRADE，再做 CANCEL/REDUCE。
3. 加 bypass 與壓力測試（同價位連續 1,000 筆）。
4. 加 seq gap + snapshot。
5. 加 5 檔輸出。
6. 突變測試補到 ≥ 18/20。
7. 合成、量資源與延遲，回頭修 SPEC 的預算表。

**每一步都要有對應的驗收測試，沒有測試的步驟不算完成。**
