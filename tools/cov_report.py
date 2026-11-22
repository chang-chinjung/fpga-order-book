#!/usr/bin/env python3
"""Report line coverage per file from an lcov .info file.

Verilator's combined total mixes RTL and testbench coverage, which hides the
fact that the DUT can be fully covered while the TB's error-reporting branches
(by design, never executed) drag the number down. This script separates them
and gates only on RTL coverage.
"""

from __future__ import annotations

import argparse
import pathlib
import sys


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("info", type=pathlib.Path)
    ap.add_argument("--min-rtl", type=float, default=95.0)
    args = ap.parse_args()

    stats: dict[str, list[int]] = {}
    current = None
    for line in args.info.read_text(encoding="utf-8").splitlines():
        if line.startswith("SF:"):
            current = line[3:]
            stats.setdefault(current, [0, 0])
        elif line.startswith("DA:") and current is not None:
            _, count = line[3:].split(",")[:2]
            stats[current][1] += 1
            if int(count) > 0:
                stats[current][0] += 1

    ok = True
    for path, (hit, total) in sorted(stats.items()):
        pct = 100.0 * hit / max(total, 1)
        is_rtl = "/rtl/" in path.replace("\\", "/") or path.startswith("rtl/")
        tag = "RTL" if is_rtl else "TB "
        print(f"{tag} {hit:5d}/{total:<5d} {pct:5.1f}%  {path}")
        if is_rtl and pct < args.min_rtl:
            ok = False

    print("RESULT:", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
