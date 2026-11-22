#!/usr/bin/env python3
"""Mutation testing for rtl/order_book.sv.

Each mutation is a single textual edit that should break behaviour. The test
suite is considered to have "teeth" when it kills most mutants. A survivor is
either a test gap or an equivalent mutant (behaviour unchanged); the latter is
marked explicitly so it does not pollute the score.

Usage: python3 tools/mutate.py [--timeout 240]
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RTL = ROOT / "rtl" / "order_book.sv"
TB = ROOT / "tb" / "tb_order_book.sv"
WORK = ROOT / "build" / "mut"

# (name, old, new, equivalent?)
MUTATIONS = [
    (
        "bid_valid_stuck_low",
        "                bid_valid    = 1'b1;",
        "                bid_valid    = 1'b0;",
        False,
    ),
    (
        "ask_scan_inverted",
        "            if (ask_q[i] != '0) begin",
        "            if (ask_q[i] == '0) begin",
        False,
    ),
    (
        "cancel_saturate_off_by_one",
        "if (cmd_side) ask_q[cmd_level] <= (cur_q > cmd_qty) ? (cur_q - cmd_qty) : '0;",
        "if (cmd_side) ask_q[cmd_level] <= (cur_q >= cmd_qty) ? (cur_q - cmd_qty) : '0;",
        True,  # at equality both branches yield 0
    ),
    (
        "add_increments_by_one",
        "ask_q[cmd_level] <= ask_q[cmd_level] + cmd_qty;",
        "ask_q[cmd_level] <= ask_q[cmd_level] + cmd_qty + 1'b1;",
        False,
    ),
    (
        "bid_scan_ignores_qty_one",
        "            if (bid_q[i] != '0) begin",
        "            if (bid_q[i] > 1) begin",
        False,
    ),
    (
        "best_ask_qty_from_level0",
        "                best_ask_qty = ask_q[i];",
        "                best_ask_qty = ask_q[0];",
        False,
    ),
    (
        "reset_only_partial_levels",
        "for (int i = 0; i < LEVELS; i++) begin\n                bid_q[i] <= '0;",
        "for (int i = 0; i < LEVELS; i++) begin\n                bid_q[i] <= 1'b1;",
        False,
    ),
    (
        "ask_index_off_by_one",
        "                best_ask     = LVL_W'(i);",
        "                best_ask     = LVL_W'(i + 1);",
        False,
    ),
    (
        "saturate_to_one",
        "if (cmd_side) ask_q[cmd_level] <= (cur_q > cmd_qty) ? (cur_q - cmd_qty) : '0;",
        "if (cmd_side) ask_q[cmd_level] <= (cur_q > cmd_qty) ? (cur_q - cmd_qty) : 1'b1;",
        False,
    ),
    (
        "side_select_swapped",
        "cmd_side ? ask_q[cmd_level] : bid_q[cmd_level]",
        "cmd_side ? bid_q[cmd_level] : ask_q[cmd_level]",
        False,
    ),
    (
        "add_op_decode_wrong",
        "                2'd0: begin  // ADD",
        "                2'd3: begin  // ADD",
        False,
    ),
    (
        "cancel_adds_instead",
        "if (cmd_side) ask_q[cmd_level] <= (cur_q > cmd_qty) ? (cur_q - cmd_qty) : '0;",
        "if (cmd_side) ask_q[cmd_level] <= (cur_q > cmd_qty) ? (cur_q + cmd_qty) : '0;",
        False,
    ),
    (
        "best_bid_index_plus_one",
        "                best_bid     = LVL_W'(i);",
        "                best_bid     = LVL_W'(i + 1);",
        False,
    ),
    (
        "best_bid_qty_from_level0",
        "                best_bid_qty = bid_q[i];",
        "                best_bid_qty = bid_q[0];",
        False,
    ),
    (
        "reset_bid_to_one",
        "                bid_q[i] <= '0;",
        "                bid_q[i] <= 1'b1;",
        False,
    ),
    (
        "bid_add_doubles_qty",
        "else          bid_q[cmd_level] <= bid_q[cmd_level] + cmd_qty;",
        "else          bid_q[cmd_level] <= bid_q[cmd_level] + (cmd_qty << 1);",
        False,
    ),
    (
        "ask_add_uses_bid_array",
        "if (cmd_side) ask_q[cmd_level] <= ask_q[cmd_level] + cmd_qty;",
        "if (cmd_side) ask_q[cmd_level] <= bid_q[cmd_level] + cmd_qty;",
        False,
    ),
    (
        "cmd_valid_gate_removed",
        "        end else if (cmd_valid) begin",
        "        end else begin",
        False,
    ),
    (
        "ask_scan_skips_top_level",
        "for (int i = LEVELS - 1; i >= 0; i--) begin",
        "for (int i = LEVELS - 2; i >= 0; i--) begin",
        False,
    ),
    (
        "depth_flatten_swapped",
        "bid_levels[i*QTY_W +: QTY_W] = bid_q[i];",
        "bid_levels[i*QTY_W +: QTY_W] = ask_q[i];",
        False,
    ),
    (
        "cur_q_side_swapped",
        "assign cur_q = cmd_side ? ask_q[cmd_level] : bid_q[cmd_level];",
        "assign cur_q = cmd_side ? bid_q[cmd_level] : ask_q[cmd_level];",
        False,
    ),
    (
        "best_ask_index_minus_one",
        "                best_ask     = LVL_W'(i);",
        "                best_ask     = LVL_W'(i - 1);",
        False,
    ),
    (
        "best_ask_qty_from_top_level",
        "                best_ask_qty = ask_q[i];",
        "                best_ask_qty = ask_q[LEVELS-1];",
        False,
    ),
    (
        "reset_ask_to_one",
        "                ask_q[i] <= '0;",
        "                ask_q[i] <= 1'b1;",
        False,
    ),
    (
        "reset_condition_inverted",
        "        if (!rst_n) begin",
        "        if (rst_n) begin",
        False,
    ),
    (
        "ask_add_truncated_8bit",
        "if (cmd_side) ask_q[cmd_level] <= ask_q[cmd_level] + cmd_qty;",
        "if (cmd_side) ask_q[cmd_level] <= (ask_q[cmd_level] + cmd_qty) & 8'hFF;",
        False,
    ),
    (
        "cancel_compare_inverted",
        "if (cmd_side) ask_q[cmd_level] <= (cur_q > cmd_qty) ? (cur_q - cmd_qty) : '0;",
        "if (cmd_side) ask_q[cmd_level] <= (cur_q < cmd_qty) ? (cur_q - cmd_qty) : '0;",
        False,
    ),
    (
        "trade_op_falls_through",
        "                default: begin  // CANCEL / TRADE: subtract, saturate at zero",
        "                2'd1: begin  // CANCEL / TRADE: subtract, saturate at zero",
        False,
    ),
    (
        "depth_ask_flatten_swapped",
        "ask_levels[i*QTY_W +: QTY_W] = ask_q[i];",
        "ask_levels[i*QTY_W +: QTY_W] = bid_q[i];",
        False,
    ),
    (
        "bid_add_ignores_qty",
        "else          bid_q[cmd_level] <= bid_q[cmd_level] + cmd_qty;",
        "else          bid_q[cmd_level] <= bid_q[cmd_level];",
        False,
    ),
]


def run(cmd: list[str], cwd: Path, timeout: int) -> subprocess.CompletedProcess:
    return subprocess.run(
        cmd,
        cwd=cwd,
        timeout=timeout,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--timeout", type=int, default=240)
    args = ap.parse_args()

    src = RTL.read_text(encoding="utf-8")
    WORK.mkdir(parents=True, exist_ok=True)

    killed = 0
    survived: list[str] = []
    invalid: list[str] = []
    equivalent = 0

    for name, old, new, is_equiv in MUTATIONS:
        count = src.count(old)
        if count != 1:
            invalid.append(f"{name} (pattern found {count}x)")
            continue

        (WORK / "order_book.sv").write_text(src.replace(old, new), encoding="utf-8")

        build = run(
            [
                "verilator", "--binary", "--timing", "--assert", "-j", "0",
                "-Wno-fatal", "--top-module", "tb_order_book",
                "--Mdir", str(WORK / "obj"),
                str(WORK / "order_book.sv"), str(TB),
            ],
            ROOT,
            args.timeout,
        )

        if build.returncode != 0:
            # A mutant that does not build is killed but uninformative; count it
            # separately so the score is not inflated by syntax errors.
            invalid.append(f"{name} (build failed)")
            continue

        sim = run([str(WORK / "obj" / "Vtb_order_book")], ROOT, args.timeout)
        out = sim.stdout

        if sim.returncode != 0 or "FAILED" in out or "ALL TESTS PASS" not in out:
            if is_equiv:
                survived.append(f"{name} (equivalent mutant, expected)")
                equivalent += 1
            else:
                killed += 1
                print(f"KILLED   {name}")
        else:
            if is_equiv:
                survived.append(f"{name} (equivalent mutant, expected)")
                equivalent += 1
            else:
                survived.append(name)
                print(f"SURVIVED {name}")

    total = killed + len([s for s in survived if "equivalent" not in s])
    score = (killed / total * 100) if total else 0.0

    print()
    print(f"mutants      : {len(MUTATIONS)}")
    print(f"killed       : {killed}")
    print(f"survived     : {len([s for s in survived if 'equivalent' not in s])}")
    print(f"equivalent   : {equivalent}")
    print(f"invalid      : {len(invalid)}")
    print(f"mutation score: {score:.1f}%  (target >= 90%)")
    if invalid:
        print("invalid:", *invalid, sep="\n  ")
    if [s for s in survived if "equivalent" not in s]:
        print("survivors:", *[s for s in survived if "equivalent" not in s], sep="\n  ")
    return 0 if score >= 90 else 1


if __name__ == "__main__":
    sys.exit(main())
