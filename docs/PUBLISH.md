# PUBLISH — 公開 repo 的檢查清單

## 1. 公開前先確認

- [ ] 沒有任何交易所原始資料（`ticks/`、行情 CSV）被放進 repo
- [ ] 沒有任何公司／客戶的程式碼或合約內容
- [ ] `LICENSE` 已選定（目前 MIT）
- [ ] 作者名稱與 email 是你願意公開的
- [ ] `docs/HANDOFF.md` 是純技術的進度紀錄（已移除私人內容），可保留

## 2. 建議的 repo 結構（已符合）

```
fpga-order-book/
├── README.md            # 入口：這是什麼、不是什麼、量測數字
├── LICENSE
├── .gitignore
├── rtl/
├── tb/
├── model/
├── tools/
├── constraints/
└── docs/
```

## 3. 三個必須在 README 出現的東西

1. **一句話說明**（給誰、解決什麼）
2. **量測數字**（Fmax、延遲、突變分數、覆蓋率）——這是履歷
3. **它不是什麼**（誠實聲明：不是完整訂單簿、沒有 FIFO）

## 4. 發文管道（按投報率）

| 管道 | 語言 | 內容角度 |
|---|---|---|
| Hacker News（Show HN） | 英文 | 「我用 Verilator + 突變測試驗證訂單簿，量到 95→154 MHz」 |
| Reddit r/FPGA、r/chipdesign | 英文 | 架構取捨（為什麼切管線反而變慢） |
| PTT（Soft_Job / Tech_Job） | 中文 | 驗證方法與踩坑 |
| 方格子 / Medium / 知乎 | 中文 | `docs/ARTICLE.md` 的完整版 |
| X（Twitter） | 英文 | 一張 Fmax vs 延遲的表 + 一句教訓 |

**原則：每篇都要有「一個具體的技術洞見」，不是「我做了這個，請看」。**

## 5. 一週節奏（可選）

| 天 | 動作 |
|---|---|
| D1 | 完成 README、LICENSE、.gitignore，push |
| D2 | 發 HN + Reddit（英文） |
| D3 | 回覆 Issue / 留言 |
| D4 | 發 PTT + 方格子（中文） |
| D5~7 | 整理回饋，決定要不要做 v1.0 |

## 6. 不要做的事

- 不要買 star、不要洗版
- 不要在標題寫「HFT」卻沒有交易系統（會被打）
- 不要貼沒有量測根據的數字（nextpnr 估計 vs 官方 STA 要標清楚）
- 不要把 AI 生成的內容偽裝成手寫（讀者會問細節）

## 7. 現成文案（可直接用）

### GitHub repo 描述（About，英文）

> A level-indexed limit order book prototype in SystemVerilog, verified with a
> Python golden model, invariants and mutation testing. Measurements on ECP5:
> 222-step differential test, 100% mutation score, 100% RTL line coverage,
> 95–155 MHz. Includes a write-up of what went wrong.

### Topics

```
fpga systemverilog verilator ecp5 hardware-verification mutation-testing
limit-order-book low-latency rtl
```

### 第一個 commit message

```
v0.1: level-indexed FPGA order book with mutation-tested verification

- rtl: single-stage and two-stage pipelined price ladder
- tb: 222-step differential test (22 directed + 200 random) plus invariants
- model: Python golden model and stimulus generator
- tools: mutation testing (30 mutants) and per-file coverage report
- docs: spec, architecture, DV plan, timing analysis, versions
- measured on ECP5 LFE5U-85F: 95.65 MHz single-stage, 154.58 MHz two-stage
```

### Show HN（英文，標題 ≤ 80 字元）

標題：
```
Show HN: An FPGA order book verified with mutation testing
```

內文：
```
I built a small limit order book prototype in SystemVerilog and spent most of
the effort on verification rather than features.

What is in it: a price ladder, best bid/ask, a Python golden model, invariants
in the testbench, and a mutation-testing script (30 mutants, 100% score after
fixing two real gaps in the tests).

What is not in it: per-order FIFO, queue position, market data parsing. It is a
block, not a trading system.

Two results worth reading about:
- Pipelining raised Fmax from 95 to 155 MHz but made latency and throughput
  worse (10.45 ns -> 12.94 ns). Fmax is not latency.
- A 1,024-level bitmap only reached 81 MHz, and moving the ladder to BRAM blew
  up to 122% LUTs because the read-modify-write is asynchronous.

Numbers are post-route estimates from Yosys + nextpnr, not sign-off.
```

### Reddit r/FPGA（英文）

標題：
```
Pipelining raised Fmax 62% but made latency worse — an ECP5 order book case study
```

內文：用 `docs/ARTICLE_EN.md` 的 §3、§4 為主，附 repo 連結。

## 7.1 最終版文案（建議直接用這組）

### Show HN

標題：
```
Show HN: An FPGA order book verified with mutation testing
```

內文：
```
I built a small limit order book prototype in SystemVerilog and spent most of
the time on verification rather than features.

It has a price ladder, best bid/ask, a Python reference model, invariants in the
testbench, and a mutation-testing script (30 mutants, 100% after fixing two real
gaps the tests had).

Not included: per-order FIFO, queue position, feed parsing. It is one block, not
a trading system.

Two things I did not expect:

- Pipelining raised Fmax from 95 to 155 MHz and made latency and throughput
  worse (10.45 ns -> 12.94 ns).
- At 1,024 levels a bitmap only reached 81 MHz, and moving the ladder to BRAM
  blew up to 122% LUTs because the read-modify-write is asynchronous.

All Fmax numbers are post-route estimates from Yosys + nextpnr, not sign-off.
Feedback on the verification approach is welcome.

https://github.com/chang-chinjung/fpga-order-book
```

### Reddit r/FPGA

標題：
```
Pipelining raised Fmax 62% but made latency worse - an ECP5 order book case study
```

內文：
```
Small case study, numbers from Yosys + nextpnr on an ECP5-85F.

A level-indexed order book core: 95.65 MHz single-stage (10.45 ns latency),
154.58 MHz two-stage (12.94 ns), 155.86 MHz three-stage (19.25 ns). Each
pipeline split shortened the critical path less than the cycle count grew, so
latency and throughput both got worse. Placement seeds varied by only a few MHz,
so it is logic depth, not placement luck.

A second experiment: an occupancy bitmap with a 4-4-4 priority tree only reached
81 MHz at 1,024 levels. The bottleneck was the wide mux that selects one word,
not the scan. Moving the ladder to BRAM made it worse (122% LUTs) because the
read-modify-write needs a combinational read, which prevents inference.

Repo with the RTL, testbench, mutation script and the write-up:
https://github.com/chang-chinjung/fpga-order-book
```

### 發文時機

- HN：美東 08:00~10:00（台北 21:00~23:00）
- Reddit r/FPGA：任何時間都可以，但週間白天效果好
- 發完 2 小時內回覆每一則留言，演算法會推

## 8. Push 指令（範例）

```bash
cd fpga/order-book
git init
git add .
git commit -m "v0.1: level-indexed FPGA order book with mutation-tested verification"
git branch -M main
git remote add origin <your-repo-url>
git push -u origin main
```
