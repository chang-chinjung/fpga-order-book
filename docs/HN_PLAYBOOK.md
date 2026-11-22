# HN 參與 Playbook（發 Show HN 之前）

目標不是導流，是讓帳號有「有內容的歷史」。HN 擋的是新帳號的自我推銷，不是你的專案。

## 1. 找討論（每天 10 分鐘）

用 Algolia 搜尋，按時間排序：

```
https://hn.algolia.com/?q=fpga&sort=byDate
https://hn.algolia.com/?q=verilator&sort=byDate
https://hn.algolia.com/?q=%22low%20latency%22&sort=byDate
https://hn.algolia.com/?q=asic&sort=byDate
https://hn.algolia.com/?q=%22order%20book%22&sort=byDate
```

規則：只回**一天內**、有真實技術內容的討論。冷門舊帖沒人看。

## 2. 什麼樣的留言有用

| 做 | 不做 |
|---|---|
| 回答具體技術問題，附數字 | 「推」「+1」「同意」 |
| 承認自己踩過的坑 | 「我們公司做得更好」 |
| 指出 tradeoff，不給絕對答案 | 貼連結（除非別人問） |
| 80~150 字，一段就好 | 長篇大論 |

## 3. 四種可重複使用的留言類型

### A. 關於「為什麼不全部切管線」

> The pipeline/latency tradeoff bites when the stages do not shrink
> proportionally. On an ECP5 design I measured 95.65 MHz single-stage (10.45 ns)
> vs 154.58 MHz two-stage (12.94 ns): Fmax up 62%, latency up 24%. Latency is
> stages x period, so a 1.6x path reduction does not pay for a 2x cycle count.
> Worth checking the critical path report before adding a stage.

### B. 關於 nextpnr / 免費工具鏈的可信度

> nextpnr's timing numbers are post-route estimates, not sign-off. On a small
> ECP5 design I saw 95.8 / 91.8 / 93.4 MHz across three placement seeds, so
> seed variance is small but the model is still approximate. For anything you
> would tape out or ship, cross-check with Diamond's STA.

### C. 關於 BRAM 推論的陷阱

> An asynchronous read quietly prevents BRAM inference. A read-modify-write on a
> 1024 x 16 array (`q[addr]` in a combinational path) turned into 32k flip-flops
> plus decode logic: 122% LUT utilization, and place-and-route never finished.
> The fix was architectural, not a synthesis attribute: split the read into a
> registered stage before the compute.

### D. 關於測試品質

> Coverage tells you a line ran, not that anyone checked the result. Mutation
> testing is the only cheap way I have found to measure whether a test suite has
> teeth. In one case, deleting a valid-gate changed nothing because the
> testbench never issued an idle cycle; the mutant survived and exposed the
> gap, not the RTL.

## 4. 發 Show HN 的時機

- 帳號至少有一週歷史、3~5 則有內容的留言
- 美東週二到週四 08:00~10:00（台北 21:00~23:00）
- 標題用 `Show HN: ...`，內文照 `docs/PUBLISH.md` §7.1

## 5. 不要做的事

- 在別人的討論裡貼自己的 repo（除非有人問「有開源嗎」）
- 用多個帳號推自己的文
- 標題誇大（HN 會直接 flag）
- 被 flag 後重複貼同一篇
