# Pipelining raised Fmax 62% but made latency worse

A short case study from an FPGA limit order book prototype. All numbers are
post-route estimates from Yosys + nextpnr on a Lattice ECP5 (LFE5U-85F), not
vendor sign-off.

## The trap: Fmax is a proxy, not a goal

I kept optimizing for Fmax because that was the number in my acceptance
criteria. Then I computed the actual latency:

| Version | Stages | Fmax | Latency | Throughput |
|---|---|---|---|---|
| Single-stage | 1 | 95.65 MHz | **10.45 ns** | **95.7 M/s** |
| Two-stage | 2 | 154.58 MHz | 12.94 ns | 77.3 M/s |
| Three-stage | 3 | 155.86 MHz | 19.25 ns | 51.9 M/s |

Frequency went up 62%. Latency and throughput both got worse.

The reason is simple arithmetic: latency = stages × period. Splitting the logic
shortened the critical path by 1.6x, but the cycle count doubled. 2 / 154.58 MHz
= 12.94 ns, which is worse than 1 / 95.65 MHz = 10.45 ns.

Placement seeds varied by only a few MHz (95.82 / 91.75 / 93.43), so this is
logic depth, not placement luck.

## What I would do instead

Split only if every stage shrinks by more than the stage count grows. Otherwise
you are trading latency for a number that does not matter.

The three-stage version was especially instructive: after splitting the 16-bit
adder into two 8-bit halves, the critical path report showed 3.1 ns of logic and
3.3 ns of routing. On this device the bottleneck had moved from logic to wires.

## Second finding: O(log N) is not free

To reach 1,024 price levels I tried an occupancy bitmap with priority encoding.

| Version | Fmax | LUT4 |
|---|---|---|
| Linear scan (64-way + 16-way chains) | 66.49 MHz | 4,490 |
| Tree (4-4-4) | 81.45 MHz | 4,510 |

Only 22% faster. The critical path moved to the wide mux that selects one word
out of 64 — not the scan itself.

## Third finding: an asynchronous read kills BRAM inference

Moving the 1,024 x 16 quantity array to block RAM looked obvious. It did not
work:

```systemverilog
wire cur_q = bid_q[cmd_level];  // asynchronous read for read-modify-write
```

Because the read has to be combinational, synthesis could not infer BRAM. The
array became 32,768 flip-flops plus write decoders and read muxes: 102k LUT4,
122% of the device, and place-and-route did not finish in 20 minutes.

The fix is architectural: split command processing into S1 (issue the memory
read), S2 (compute), S3 (write back). That is the pipeline the spec asked for
from the beginning.

## What this project is (and is not)

It is a level-indexed price ladder with best bid/ask, a Python reference model,
invariants in the testbench, and a mutation-testing script. 30 mutants, 100%
score after fixing two real gaps in the tests.

It is not a trading system: no per-order FIFO, no queue position, no feed
parsing.

The verification part was more interesting than the RTL. Two mutants survived
during development, and both pointed at holes in the *tests*, not the design:

- Removing the `cmd_valid` gate changed nothing, because the testbench had never
  issued an idle cycle.
- An 8-bit truncation on the ask side survived, because the ask side had never
  been tested with large quantities.

Mutation testing is the only technique I have found that measures whether tests
have teeth.

## Links

- Repository: https://github.com/chang-chinjung/fpga-order-book
- Longer write-up: https://github.com/chang-chinjung/fpga-order-book/blob/main/docs/ARTICLE_EN.md

If you have done timing closure on small ECP5 designs and disagree with the
routing numbers, I would like to hear it.
