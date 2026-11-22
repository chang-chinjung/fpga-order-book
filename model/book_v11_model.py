#!/usr/bin/env python3
"""Reference model for rtl/order_book_v11.sv (1,024-level book).

Writes stim_v11.txt / exp_v11.txt:
  stim: op side level qty
  exp : bid_valid bid_index bid_qty ask_valid ask_index ask_qty
"""

from __future__ import annotations

import argparse
import random
from pathlib import Path

LEVELS = 1024
QTY_MASK = (1 << 16) - 1


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=400)
    ap.add_argument("--seed", type=int, default=11)
    ap.add_argument("--dir", type=Path, default=Path("."))
    args = ap.parse_args()

    rng = random.Random(args.seed)
    bid = [0] * LEVELS
    ask = [0] * LEVELS

    cmds: list[tuple[int, int, int, int]] = []
    exps: list[tuple[int, int, int, int, int, int]] = []

    for _ in range(args.n):
        op = rng.choices([0, 1, 2], weights=[6, 3, 1])[0]
        side = rng.randint(0, 1)
        level = rng.randrange(LEVELS)
        qty = rng.randint(1, 50)

        book = ask if side else bid
        if op == 0:
            book[level] = (book[level] + qty) & QTY_MASK
        else:
            book[level] = book[level] - qty if book[level] > qty else 0

        bv = bb = bq = 0
        for i in range(LEVELS - 1, -1, -1):
            if bid[i]:
                bv, bb, bq = 1, i, bid[i]
                break
        av = aa = aq = 0
        for i in range(LEVELS):
            if ask[i]:
                av, aa, aq = 1, i, ask[i]
                break

        cmds.append((op, side, level, qty))
        exps.append((bv, bb, bq, av, aa, aq))

    with (args.dir / "stim_v11.txt").open("w", encoding="utf-8") as fh:
        fh.write(f"{len(cmds)}\n")
        for row in cmds:
            fh.write(" ".join(str(v) for v in row) + "\n")

    with (args.dir / "exp_v11.txt").open("w", encoding="utf-8") as fh:
        fh.write(f"{len(exps)}\n")
        for row in exps:
            fh.write(" ".join(str(v) for v in row) + "\n")

    print(f"wrote {len(cmds)} v11 commands (seed={args.seed})")


if __name__ == "__main__":
    main()
