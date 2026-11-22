# Verifying an FPGA order book with Verilator: the numbers, and the parts that went wrong

> A technical log, not a tutorial. Every number below is reproducible from this
> repository, and every failure is kept in the history — failures carry more
> information than successes.

## 0. Why build this at all

I started from a simple observation about day trading in Taiwan: the cost
structure (27.6 bps round trip: fees plus transaction tax) dominates, not
hardware speed. A 10 ns order book behind a 10–50 ms broker API is meaningless.

So this project is not a trading product. It is an answer to an engineering
question:

> **If the broker API did not exist, where would an FPGA order book core top out?**

## 1. Scope of v0.1

Deliberately small: a level-indexed price ladder, best bid/ask, and the
ADD/CANCEL/TRADE semantics at the *price level* granularity. No per-order
storage, no FIFO, no queue position.

The point of this version is not features. It is to establish a verification
flow and leave behind numbers.

## 2. Verification: three layers, none optional

### 2.1 Python golden model

`model/book_model.py` re-implements the semantics with lists and arbitrary
precision integers, and generates both stimulus and expected outputs. The
testbench replays `stim.txt` / `exp.txt` and compares seven fields per step
(valid flags, level, quantity for both sides, plus a full-book checksum).

- 222 commands (22 directed + 200 random) × 7 fields = **1,554 comparisons**

**Limitation**: the golden model and the RTL were written by the same person.
A shared misunderstanding of the spec passes both.

### 2.2 Invariants

The testbench also checks properties that do not depend on the model:
`bid_valid` must equal "depth is nonzero", `best_*_qty` must equal the quantity
stored at that level, and no occupied level may sit above the best bid or below
the best ask.

This layer catches structural errors that both the model and the RTL missed.

### 2.3 Mutation testing: proving the tests have teeth

`tools/mutate.py` corrupts key strings in the RTL and checks whether the suite
notices:

```
mutants       : 30
killed        : 29
equivalent    : 1
survived      : 0
mutation score: 100.0%
```

The interesting part is the two mutants that **survived** along the way.

#### Story one: removing the `cmd_valid` gate changed nothing

Replacing `else if (s1_valid)` with `else` kept the suite green.

Because the testbench issued a command on *every* cycle, it never exercised an
idle cycle. The gate had never run.

The fix was not in the RTL. It was inserting two idle cycles every five steps
and asserting that the book does not move.

#### Story two: an 8-bit truncation on the ask side survived

Truncating the ask-side adder to 8 bits went undetected — the ask side had never
been tested with large quantities. A directed case (65535 plus 2, wrapping to 1)
killed it.

**The lesson: mutation testing found gaps in the tests, not bugs in the RTL.**

## 3. Timing: Fmax is not latency

| Version | Stages | Fmax | Latency | Throughput |
|---|---|---|---|---|
| Single-stage | 1 | 95.65 MHz | **10.45 ns** | **95.7 M/s** |
| Two-stage | 2 | 154.58 MHz | 12.94 ns | 77.3 M/s |
| Three-stage (split adder) | 3 | 155.86 MHz | 19.25 ns | 51.9 M/s |

Frequency went up 62%, while latency and throughput both got worse. Each stage
only shortened the critical path by 1.6×, but the cycle count doubled.

Three placement seeds gave 95.82 / 91.75 / 93.43 MHz, so this is logic depth,
not placement luck.

The three-stage version, which splits the 16-bit add/subtract into two 8-bit
halves, gained 0.8% frequency for one extra cycle of latency. The critical path
report showed why: after splitting, only 3.1 ns was logic and 3.3 ns was
routing. On ECP5 the bottleneck had moved from logic to wires.

## 4. The bitmap experiment: O(log N) is not free

To reach 1,024 levels I tried an occupancy bitmap with priority encoding.

| Version | Fmax | LUT4 |
|---|---|---|
| Linear scan (64-way + 16-way chains) | 66.49 MHz | 4,490 |
| Tree (4→4→4) | 81.45 MHz | 4,510 |

Only 22% faster, not the 2× I expected. The critical path moved to the wide mux
that selects one word out of 64, not the scan itself.

### The BRAM trap

Moving the 1,024 × 16 quantity array to block RAM hit this:

```systemverilog
wire cur_q = bid_q[cmd_level];   // asynchronous read
```

Read-modify-write needs a combinational read, so Yosys could not infer BRAM. The
2 × 1,024 × 16 array became 32,768 flip-flops plus write decoders and read muxes:
102k LUT4 (122% of the device), and place-and-route did not finish in 20 minutes.

The fix is architectural: split command processing into S1 (issue read), S2
(compute), S3 (write back) — the pipeline the spec called for from the start.

## 5. Tooling reality

- **Yosys + nextpnr**: free and scriptable, but no retiming and weaker
  delay-driven optimization than commercial tools.
- **Vivado**: 50–100 GB install, and the 325T part may need a paid license.
- **Lattice Diamond**: free and small; it is the official STA for ECP5.

All Fmax numbers here are post-route *estimates* from nextpnr, not sign-off
numbers. Expect 10–20% error.

## 6. Ten lessons

1. **Fmax is not the goal.** Latency in ns and throughput in events/s are.
2. Pipelining increases latency unless every stage shrinks proportionally.
3. Mutation testing finds holes in the tests, not bugs in the RTL.
4. Equivalent mutants must be excluded or the score lies.
5. Synthesis cannot fix architecture. It will not add a register or change an
   algorithm.
6. An asynchronous read kills BRAM inference.
7. A 1,024-way mux is more expensive than it looks.
8. Place-and-route time destroys iteration speed on large designs; iterate small.
9. When the golden model and the RTL share an author, invariants and mutation
   testing are not optional.
10. **Ask what it is for before asking how to make it faster.**

## 7. If you want to build one

- Start with the smallest verifiable thing, not 1,024 levels.
- Write the golden model before the RTL.
- Add mutation testing early; it changes what "tested" means.
- Measure latency, not just frequency.
- Keep the failures: the three-stage variant, the 66 MHz bitmap, the 122% LUT
  blow-up. They are more convincing than the successes.
