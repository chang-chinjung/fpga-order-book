#!/usr/bin/env python3
"""Mutation testing for the two-stage design (v1).

Same methodology as tools/mutate.py, but the mutant patterns target
rtl/order_book_pipe2.sv and the testbench is tb/tb_order_book_pipe2.sv.

Usage: python3 tools/mutate_pipe2.py [--timeout 240]
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RTL = ROOT / "rtl" / "order_book_pipe2.sv"
TB = ROOT / "tb" / "tb_order_book_pipe2.sv"
WORK = ROOT / "build" / "mut_pipe2"

# (name, old, new, equivalent?)
MUTATIONS = [
    ("s1_valid_stuck_low",
     "            s1_valid <= cmd_valid;",
     "            s1_valid <= 1'b0;", False),
    ("s1_level_off_by_one",
     "            s1_level <= cmd_level;",
     "            s1_level <= cmd_level + 1'b1;", False),
    ("s1_qty_plus_one",
     "            s1_qty   <= cmd_qty;",
     "            s1_qty   <= cmd_qty + 1'b1;", False),
    ("s1_cur_forced_zero",
     "            s1_cur   <= rd_cur;",
     "            s1_cur   <= '0;", False),
    ("s1_side_inverted",
     "            s1_side  <= cmd_side;",
     "            s1_side  <= ~cmd_side;", False),
    ("s1_op_forced_add",
     "            s1_op    <= cmd_op;",
     "            s1_op    <= 2'd0;", False),
    ("rd_cur_side_swapped",
     "cmd_side ? ask_q[cmd_level] : bid_q[cmd_level]",
     "cmd_side ? bid_q[cmd_level] : ask_q[cmd_level]", False),
    ("add_becomes_subtract",
     "if (s1_op == 2'd0) wr_val = s1_cur + s1_qty;",
     "if (s1_op == 2'd0) wr_val = s1_cur - s1_qty;", False),
    ("compare_ge_equivalent",
     "(s1_cur > s1_qty)",
     "(s1_cur >= s1_qty)", True),
    ("compare_inverted",
     "(s1_cur > s1_qty) ? (s1_cur - s1_qty) : '0;",
     "(s1_cur < s1_qty) ? (s1_cur - s1_qty) : '0;", False),
    ("saturate_to_one",
     "(s1_cur - s1_qty) : '0;",
     "(s1_cur - s1_qty) : 1'b1;", False),
    ("no_saturation_wrap",
     "else               wr_val = (s1_cur > s1_qty) ? (s1_cur - s1_qty) : '0;",
     "else               wr_val = s1_cur - s1_qty;", False),
    ("write_ask_into_bid",
     "if (s1_side) ask_q[s1_level] <= wr_val;",
     "if (s1_side) bid_q[s1_level] <= wr_val;", False),
    ("write_bid_into_ask",
     "else         bid_q[s1_level] <= wr_val;",
     "else         ask_q[s1_level] <= wr_val;", False),
    ("valid_gate_removed",
     "end else if (s1_valid) begin",
     "end else begin", False),
    ("write_index_plus_one",
     "if (s1_side) ask_q[s1_level] <= wr_val;",
     "if (s1_side) ask_q[s1_level + 1'b1] <= wr_val;", False),
    ("reset_bid_to_one",
     "                bid_q[i] <= '0;",
     "                bid_q[i] <= 1'b1;", False),
    ("reset_ask_to_one",
     "                ask_q[i] <= '0;",
     "                ask_q[i] <= 1'b1;", False),
    ("reset_inverted",
     "    always_ff @(posedge clk or negedge rst_n) begin\n        if (!rst_n) begin\n            for (int i = 0; i < LEVELS; i++) begin",
     "    always_ff @(posedge clk or negedge rst_n) begin\n        if (rst_n) begin\n            for (int i = 0; i < LEVELS; i++) begin", False),
    ("bid_valid_stuck_low",
     "                bid_valid    = 1'b1;",
     "                bid_valid    = 1'b0;", False),
    ("best_bid_index_plus_one",
     "                best_bid     = LVL_W'(i);",
     "                best_bid     = LVL_W'(i + 1'b1);", False),
    ("best_bid_qty_from_level0",
     "                best_bid_qty = bid_q[i];",
     "                best_bid_qty = bid_q[0];", False),
    ("bid_scan_ignores_qty_one",
     "            if (bid_q[i] != '0) begin",
     "            if (bid_q[i] > 1) begin", False),
    ("bid_scan_skips_top_level",
     "        for (int i = 0; i < LEVELS; i++) begin\n            if (bid_q[i] != '0) begin",
     "        for (int i = 0; i < LEVELS - 1; i++) begin\n            if (bid_q[i] != '0) begin", False),
    ("ask_valid_stuck_low",
     "                ask_valid    = 1'b1;",
     "                ask_valid    = 1'b0;", False),
    ("best_ask_index_minus_one",
     "                best_ask     = LVL_W'(i);",
     "                best_ask     = LVL_W'(i - 1'b1);", False),
    ("best_ask_qty_from_top_level",
     "                best_ask_qty = ask_q[i];",
     "                best_ask_qty = ask_q[LEVELS-1];", False),
    ("ask_scan_inverted",
     "            if (ask_q[i] != '0) begin",
     "            if (ask_q[i] == '0) begin", False),
    ("ask_scan_skips_top_level",
     "        for (int i = LEVELS - 1; i >= 0; i--) begin",
     "        for (int i = LEVELS - 2; i >= 0; i--) begin", False),
    ("ask_scan_reads_bid_array",
     "            if (ask_q[i] != '0) begin",
     "            if (bid_q[i] != '0) begin", False),
]


def run(cmd: list[str], cwd: Path, timeout: int) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, cwd=cwd, timeout=timeout,
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--timeout", type=int, default=240)
    args = ap.parse_args()

    src = RTL.read_text(encoding="utf-8")
    WORK.mkdir(parents=True, exist_ok=True)

    killed = survived = equivalent = 0
    survivors: list[str] = []
    invalid: list[str] = []

    for name, old, new, is_equiv in MUTATIONS:
        count = src.count(old)
        if count != 1:
            invalid.append(f"{name} (pattern found {count}x)")
            continue

        (WORK / "order_book_pipe2.sv").write_text(src.replace(old, new), encoding="utf-8")

        build = run(
            ["verilator", "--binary", "--timing", "--assert", "-j", "0",
             "-Wno-fatal", "--top-module", "tb_order_book_pipe2",
             "--Mdir", str(WORK / "obj"),
             str(WORK / "order_book_pipe2.sv"), str(TB)],
            ROOT, args.timeout,
        )
        if build.returncode != 0:
            invalid.append(f"{name} (build failed)")
            continue

        sim = run([str(WORK / "obj" / "Vtb_order_book_pipe2")], ROOT, args.timeout)
        out = sim.stdout

        if sim.returncode != 0 or "FAILED" in out or "ALL TESTS PASS" not in out:
            if is_equiv:
                equivalent += 1
                print(f"EQUIV    {name}")
            else:
                killed += 1
                print(f"KILLED   {name}")
        else:
            if is_equiv:
                equivalent += 1
                print(f"EQUIV    {name} (expected)")
            else:
                survived += 1
                survivors.append(name)
                print(f"SURVIVED {name}")

    total = killed + survived
    score = (killed / total * 100) if total else 0.0

    print()
    print(f"mutants      : {len(MUTATIONS)}")
    print(f"killed       : {killed}")
    print(f"survived     : {survived}")
    print(f"equivalent   : {equivalent}")
    print(f"invalid      : {len(invalid)}")
    print(f"mutation score: {score:.1f}%  (target >= 90%)")
    if invalid:
        print("invalid:", *invalid, sep="\n  ")
    if survivors:
        print("survivors:", *survivors, sep="\n  ")
    return 0 if score >= 90 else 1


if __name__ == "__main__":
    sys.exit(main())
