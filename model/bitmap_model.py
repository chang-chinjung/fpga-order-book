#!/usr/bin/env python3
"""Reference model for rtl/bitmap_best.sv.

Generates:
  stim_bitmap.txt  - N command lines: set|clr index
  exp_bitmap.txt   - N expected lines: hi_valid hi lo_valid lo
"""

from __future__ import annotations

import argparse
import random
from pathlib import Path

LEVELS = 1024


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=500)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--dir", type=Path, default=Path("."))
    args = ap.parse_args()

    rng = random.Random(args.seed)
    occupied = [False] * LEVELS

    cmds: list[tuple[str, int]] = []
    exps: list[tuple[int, int, int, int]] = []

    for _ in range(args.n):
        idx = rng.randrange(LEVELS)
        # Bias toward setting early, then mix.
        op = "set" if (rng.random() < 0.55) else "clr"
        occupied[idx] = (op == "set")

        hi_valid, hi = 0, 0
        for i in range(LEVELS - 1, -1, -1):
            if occupied[i]:
                hi_valid, hi = 1, i
                break
        lo_valid, lo = 0, 0
        for i in range(LEVELS):
            if occupied[i]:
                lo_valid, lo = 1, i
                break

        cmds.append((op, idx))
        exps.append((hi_valid, hi, lo_valid, lo))

    with (args.dir / "stim_bitmap.txt").open("w", encoding="utf-8") as fh:
        fh.write(f"{len(cmds)}\n")
        for op, idx in cmds:
            fh.write(f"{op} {idx}\n")

    with (args.dir / "exp_bitmap.txt").open("w", encoding="utf-8") as fh:
        fh.write(f"{len(exps)}\n")
        for row in exps:
            fh.write(" ".join(str(v) for v in row) + "\n")

    print(f"wrote {len(cmds)} bitmap commands (seed={args.seed})")


if __name__ == "__main__":
    main()
