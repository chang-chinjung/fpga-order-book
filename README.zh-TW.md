# fpga-order-book · v0.1

[English](README.md) | 繁體中文 | [简体中文](README.zh-CN.md)

一個用 Verilator 驗證的 FPGA 限價訂單簿原型（**價位聚合層級**），
重點不是功能多，而是把「規格 → RTL → 對拍 → 突變 → 覆蓋率 → 時序」的流程走完並且留下數字。

> **v0.1 的範圍**：價位總量 + 最佳價。**沒有**訂單、佇列、queue position。
> 版本定義見 [docs/VERSIONS.md](docs/VERSIONS.md)。

## 量測結果（16 級，ECP5 LFE5U-85F，nextpnr）

| 指標 | 單級 | 兩級管線 |
|---|---|---|
| 功能對拍 | 222 steps ✅ | 222 steps ✅ |
| 突變分數 | 100%（29 killed / 1 equivalent） | 100%（同上） |
| RTL 行覆蓋率 | 100%（35/35） | 100%（44/44） |
| Fmax | 95.65 MHz | 154.58 MHz |
| **延遲** | **10.45 ns** | 12.94 ns |
| 吞吐 | 95.7 M events/s | 77.3 M events/s |

**注意**：兩級管線的 Fmax 較高，但延遲與吞吐都較差。**Fmax 不是目標，延遲與吞吐才是。**
完整分析見 [docs/TIMING.md](docs/TIMING.md)。

## 這是什麼／不是什麼

| 是 | 不是 |
|---|---|
| 價位聚合與最佳價的硬體原型 | 完整的訂單簿（沒有 FIFO / queue position） |
| 一套可重複的驗證流程（golden model + 突變 + 覆蓋率） | 交易系統（沒有行情解析、風控、下單） |
| 時序量測與 PPA 分析的範例 | 可直接上線的 IP |

## 目錄

```
rtl/         order_book.sv（單級）、order_book_pipe2.sv（兩級）、bitmap_best.sv（實驗）
tb/          testbench（讀 stim/exp 逐筆比對）
model/       Python golden model + 刺激產生器
tools/       突變測試、覆蓋率報告
docs/        SPEC / ARCH / DV / TIMING / VERSIONS / PLAN / HANDOFF
constraints/ XDC / SDC
```

## 快速開始

需要 Verilator ≥ 5.0、Python 3、Yosys、nextpnr-ecp5。

```bash
make sim          # 單級版：222 steps 對拍
make sim-pipe2    # 兩級版：222 steps 對拍
python3 tools/mutate.py        # 單級版突變測試
python3 tools/mutate_pipe2.py  # 兩級版突變測試
make coverage     # RTL 覆蓋率（分檔報告）
make pnr          # ECP5 place & route + Fmax
```

在 Windows 上可透過 WSL 執行：

```powershell
wsl -e bash -lc 'cd /mnt/d/.../fpga/order-book && make sim'
```

## 驗證方法（三層）

| 層 | 抓什麼 | 抓不到什麼 |
|---|---|---|
| Python golden model 對拍 | 實作層錯誤（位寬、邊界、順序） | 共同誤解規格 |
| 不變量（valid/qty 一致、範圍） | 結構性矛盾 | 同上 |
| 突變測試 | 「測試有沒有牙齒」 | 同上 |

突變測試抓到的兩個真缺口（詳見 docs/ARTICLE.md）：

1. 移除 `cmd_valid` gate 後測試全綠 → TB 從未插入閒置週期。
2. ask 側 8-bit 截斷存活 → ask 側從未測過大數量。

## 文件

- [docs/VERSIONS.md](docs/VERSIONS.md) — v0.1 / v1.0 的界線
- [docs/SPEC.md](docs/SPEC.md) — 需求規格（v1.0 目標）
- [docs/ARCH.md](docs/ARCH.md) — 架構設計
- [docs/DV.md](docs/DV.md) — 驗證計畫與結果
- [docs/TIMING.md](docs/TIMING.md) — 時序量測與分析
- [docs/ARTICLE.md](docs/ARTICLE.md) — 技術文章草稿（中文）
- [docs/ARTICLE_EN.md](docs/ARTICLE_EN.md) — 技術文章（英文，HN/Reddit 用）
- [docs/PUBLISH.md](docs/PUBLISH.md) — 公開 repo 的檢查清單

## 授權

MIT，見 [LICENSE](LICENSE)。

## 已知限制

- 只有 16 級的 prototype 有完整驗證；1,024 級 bitmap 仍是實驗。
- `order_book_pipe3.sv` 是失敗的時序實驗（沒有價值，保留作為紀錄）。
- 所有 Fmax 都是 nextpnr 估計，不是 Lattice Diamond 簽核數字。
- 沒有真實交易所資料 replay。
