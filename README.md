# fpga-order-book · v0.1

English | [繁體中文](README.zh-TW.md) | [简体中文](README.zh-CN.md)

A level-indexed limit order book prototype in SystemVerilog, verified with a
Python golden model, invariants and mutation testing. The point is not feature
count — it is that the full loop from spec to RTL to differential test to
mutation testing to timing measurement was carried out, and the numbers are
recorded.

> **Scope of v0.1**: price-level aggregation and best bid/ask. **No** per-order
> storage, no FIFO, no queue position. See [docs/VERSIONS.md](docs/VERSIONS.md)
> for the version boundaries.

## Measurements (16 levels, ECP5 LFE5U-85F, nextpnr)

| Metric | Single-stage | Two-stage pipeline |
|---|---|---|
| Differential test | 222 steps ✅ | 222 steps ✅ |
| Mutation score | 100% (29 killed / 1 equivalent) | 100% (same) |
| RTL line coverage | 100% (35/35) | 100% (44/44) |
| Fmax | 95.65 MHz | 154.58 MHz |
| **Latency** | **10.45 ns** | 12.94 ns |
| Throughput | 95.7 M events/s | 77.3 M events/s |

**Note**: the two-stage pipeline has a higher Fmax but worse latency and
throughput. **Fmax is not the goal.** Full analysis in
[docs/TIMING.md](docs/TIMING.md) (Chinese).

## What it is / is not

| Is | Is not |
|---|---|
| A hardware prototype of price-level aggregation and best price | A complete order book (no FIFO, no queue position) |
| A repeatable verification flow (golden model + mutation + coverage) | A trading system (no feed parsing, risk, order entry) |
| A timing and PPA measurement example | Production IP |

## Layout

```
rtl/         order_book.sv (single-stage), order_book_pipe2.sv (two-stage), bitmap_best.sv (experiment)
tb/          testbenches (replay stim/exp, compare every step)
model/       Python golden models and stimulus generators
tools/       mutation testing, per-file coverage report
docs/        SPEC / ARCH / DV / TIMING / VERSIONS / PLAN / HANDOFF
constraints/ XDC / SDC
```

## Quick start

Requires Verilator ≥ 5.0, Python 3, Yosys, nextpnr-ecp5.

```bash
make sim          # single-stage: 222-step differential test
make sim-pipe2    # two-stage: same stimulus
python3 tools/mutate.py         # mutation testing (30 mutants)
python3 tools/mutate_pipe2.py
make coverage     # RTL line coverage, reported per file
make pnr          # ECP5 place & route + Fmax
```

On Windows, run through WSL:

```powershell
wsl -e bash -lc 'cd /mnt/d/.../fpga/order-book && make sim'
```

## Verification approach (three layers)

| Layer | Catches | Misses |
|---|---|---|
| Python golden model | Implementation mistakes (width, bounds, ordering) | Shared misunderstanding of the spec |
| Invariants | Structural contradictions (valid vs quantity, range) | Same |
| Mutation testing | Whether the tests have teeth | Same |

Two real gaps found by mutation testing (details in
[docs/ARTICLE_EN.md](docs/ARTICLE_EN.md)):

1. Removing the `cmd_valid` gate left the suite green — the testbench had never
   issued an idle cycle.
2. An 8-bit truncation on the ask side survived — the ask side had never been
   tested with large quantities.

## Documentation

The design documents are written in Traditional Chinese. The English article
covers the findings and numbers.

- [docs/ARTICLE_EN.md](docs/ARTICLE_EN.md) — technical write-up (English)
- [docs/ARTICLE.md](docs/ARTICLE.md) — technical write-up (Chinese)
- [docs/VERSIONS.md](docs/VERSIONS.md) — v0.1 / v1.0 boundaries
- [docs/SPEC.md](docs/SPEC.md) — requirements (v1.0 target)
- [docs/ARCH.md](docs/ARCH.md) — architecture
- [docs/DV.md](docs/DV.md) — verification plan and results
- [docs/TIMING.md](docs/TIMING.md) — timing measurements and analysis
- [docs/PLAN.md](docs/PLAN.md) — v0.1 / v1.1 plan
- [docs/PUBLISH.md](docs/PUBLISH.md) — publishing checklist

## License

MIT — see [LICENSE](LICENSE).

## Known limitations

- Only the 16-level prototype is fully verified; the 1,024-level bitmap is still
  an experiment.
- `order_book_pipe3.sv` is a failed timing experiment, kept as a record.
- All Fmax numbers are nextpnr post-route estimates, not Lattice Diamond
  sign-off numbers.
- No real exchange data replay yet.
