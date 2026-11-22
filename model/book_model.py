#!/usr/bin/env python3
"""Bit-exact reference model for rtl/order_book.sv.

Generates:
  stim.txt  - N command lines: op side level qty
  exp.txt   - N expected lines: bid_valid best_bid best_bid_qty ask_valid best_ask best_ask_qty
"""

from __future__ import annotations

import argparse
import random
from pathlib import Path

LEVELS = 16
QTY_W = 16
QTY_MASK = (1 << QTY_W) - 1


class Book:
    def __init__(self) -> None:
        self.bid = [0] * LEVELS
        self.ask = [0] * LEVELS

    def apply(self, op: int, side: int, level: int, qty: int) -> None:
        book = self.ask if side else self.bid
        if op == 0:  # ADD wraps on 16 bits, like the RTL adder
            book[level] = (book[level] + qty) & QTY_MASK
        else:  # CANCEL / TRADE subtract with saturate-at-zero
            book[level] = book[level] - qty if book[level] > qty else 0

    def best(self) -> tuple[int, int, int, int, int, int]:
        bid_valid = best_bid = best_bid_qty = 0
        for i in range(LEVELS):
            if self.bid[i] != 0:
                bid_valid, best_bid, best_bid_qty = 1, i, self.bid[i]

        ask_valid = best_ask = best_ask_qty = 0
        for i in range(LEVELS - 1, -1, -1):
            if self.ask[i] != 0:
                ask_valid, best_ask, best_ask_qty = 1, i, self.ask[i]

        return bid_valid, best_bid, best_bid_qty, ask_valid, best_ask, best_ask_qty


# Directed corner cases, replayed before the random stimulus.
# Covers: empty-level cancel, exact-quantity cancel, over-cancel saturation,
# 16-bit ADD wrap, boundary levels 0 and 15, and max quantity.
DIRECTED: list[tuple[int, int, int, int]] = [
    (0, 0, 0, 10),        # add bid L0
    (0, 0, 0, 20),        # accumulate same level -> 30
    (0, 0, 15, 5),        # boundary level 15
    (0, 1, 15, 7),
    (0, 1, 14, 3),
    (1, 0, 0, 40),        # over-cancel -> saturate to 0
    (1, 0, 15, 5),        # exact cancel -> 0
    (0, 0, 7, 65535),     # max quantity
    (0, 0, 7, 2),         # 16-bit wrap -> 1
    (1, 1, 14, 1),
    (2, 1, 15, 100),      # TRADE over-cancel -> saturate
    (0, 1, 0, 1),         # ask at lowest level
    (1, 1, 0, 1),
    (0, 0, 3, 1),
    (1, 0, 3, 2),         # over-cancel on qty 1
    (0, 0, 8, 100),
    (2, 0, 8, 50),        # TRADE partial
    (1, 0, 8, 50),        # exact cancel of remainder
    (0, 1, 9, 10),
    (1, 1, 9, 10),
    (0, 1, 11, 65535),    # ask-side max quantity
    (0, 1, 11, 2),        # 16-bit wrap on ask side -> 1
]


def gen(n: int, seed: int) -> tuple[list[tuple[int, int, int, int]], list[tuple[int, ...]]]:
    rng = random.Random(seed)
    book = Book()
    cmds: list[tuple[int, int, int, int]] = []
    exps: list[tuple[int, ...]] = []

    for op, side, level, qty in DIRECTED:
        book.apply(op, side, level, qty)
        cmds.append((op, side, level, qty))
        exps.append(book.best() + (sum(book.bid) + sum(book.ask),))

    for _ in range(n):
        op = rng.choices([0, 1, 2], weights=[6, 3, 1])[0]
        side = rng.randint(0, 1)
        level = rng.randint(0, LEVELS - 1)
        qty = rng.randint(1, 50)
        book.apply(op, side, level, qty)
        cmds.append((op, side, level, qty))
        exps.append(book.best() + (sum(book.bid) + sum(book.ask),))

    return cmds, exps


def write(path: Path, header: int, rows: list[tuple[int, ...]]) -> None:
    with path.open("w", encoding="utf-8") as fh:
        fh.write(f"{header}\n")
        for row in rows:
            fh.write(" ".join(str(v) for v in row) + "\n")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=200)
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--dir", type=Path, default=Path("."))
    args = ap.parse_args()

    cmds, exps = gen(args.n, args.seed)
    write(args.dir / "stim.txt", len(cmds), cmds)
    write(args.dir / "exp.txt", len(exps), exps)
    print(f"wrote {len(cmds)} commands (seed={args.seed}) to {args.dir}")


if __name__ == "__main__":
    main()
