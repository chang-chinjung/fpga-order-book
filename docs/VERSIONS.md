# VERSIONS — 版本定義

之前的文件把「兩級管線版」叫 v1，是錯的標籤。以功能完整度來看，
目前所有程式碼都只是 **v0.1**。以下是正式定義。

## v0.1 — 價位聚合原型（現在）

**有**：level-indexed 價格階梯、最佳價、ADD/CANCEL/TRADE 的價位層級語意、
兩級管線變體、1,024 級 bitmap 實驗。

**沒有**：訂單、佇列、queue position、order_id 查詢、AXI-Stream、seq gap、snapshot。

**已達成的驗收**（16 級單級版）：222 steps 對拍、30 mutants 100%、RTL 覆蓋率 100%、
ECP5 95.65 MHz；兩級版 154.58 MHz。

**價值**：把「規格 → RTL → 對拍 → 突變 → 覆蓋率 → 時序」的流程走通。
功能上它不是訂單簿，是價格階梯。

## v1.0 — 真正的訂單簿（SPEC 定義的目標）

**要新增**：

| 需求 | 內容 |
|---|---|
| REQ-F-001/002/003 | ADD / CANCEL / REDUCE，以 order_id 為鍵 |
| REQ-F-004/008 | TRADE 從同價位 FIFO 頭端扣量，可跨多張 |
| REQ-F-012 | order_id 查詢：所在價位、剩餘量、queue position |
| REQ-F-010/013 | 最佳價與 delta 輸出（AXI-Stream） |
| REQ-F-020/021/022 | seq gap 偵測、stale 標記、snapshot 原子重載 |
| REQ-F-023 | 溢出策略與計數器 |

**儲存結構**：order store（order_id → slot）、每價位雙向鏈結 FIFO、price ladder。
**預估**：1,500~2,500 行 RTL。
**延遲目標**：≤ 10 cycles（SPEC REQ-N-001），先求正確再求快。

## v1.1 — bitmap 最佳價整合

把 `/rtl/bitmap_best.sv` 接到 v1.0 的 ladder 上，支援 1,024 級。

**前置**：通用化 bitmap（目前樹狀索引寫死 W=64）、BRAM 化 ladder（S1/S2/S3 管線）。

## v2 — 系統化

多商品、1 event/cycle @ 1,024 級、K7/Vivado 時序簽核、真實 feed parser。

## 命名規則

- 檔案內的 `_pipe2` / `_pipe3` 是**時序實驗**，不是版本。
- 文件裡的「v1」一律指 v1.0；效能變體用「v0.1 + 兩級管線」描述。
