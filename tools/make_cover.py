#!/usr/bin/env python3
"""Generate cover images from the measured numbers.

Outputs:
  docs/cover.png        1200x630 (general purpose, GitHub/social)
  docs/cover_devto.png  1000x420 (dev.to recommended cover aspect)

Run: python3 tools/make_cover.py
"""

from __future__ import annotations

from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parent.parent

STAGES = ["1 stage", "2 stages", "3 stages"]
FMAX = [95.65, 154.58, 155.86]
LATENCY = [10.45, 12.94, 19.25]
THROUGHPUT = [95.7, 77.3, 51.9]

BG = "#0d1117"
FG = "#e6edf3"
MUTED = "#8b949e"
BLUE = "#58a6ff"
ORANGE = "#f78166"


def draw(width_in: float, height_in: float, scale: float, out: Path) -> None:
    small = scale < 0.9
    ax_h = 0.44 if small else 0.50
    sub_y = 0.77 if small else 0.80
    pad = 6 if small else 10
    fig = plt.figure(figsize=(width_in, height_in), dpi=100, facecolor=BG)

    fig.text(0.05, 0.86, "Fmax is not latency", color=FG,
             fontsize=30 * scale, fontweight="bold")
    fig.text(0.05, sub_y,
             "Pipelining raised Fmax 62% but made latency and throughput worse",
             color=MUTED, fontsize=14 * scale)

    ax1 = fig.add_axes([0.06, 0.18, 0.40, ax_h], facecolor=BG)
    ax2 = fig.add_axes([0.56, 0.18, 0.40, ax_h], facecolor=BG)

    for ax in (ax1, ax2):
        ax.spines["top"].set_visible(False)
        ax.spines["right"].set_visible(False)
        ax.spines["left"].set_color(MUTED)
        ax.spines["bottom"].set_color(MUTED)
        ax.tick_params(colors=MUTED, labelsize=11 * scale)
        ax.set_xticks(range(len(STAGES)))
        ax.set_xticklabels(STAGES, color=FG, fontsize=12 * scale)

    bars1 = ax1.bar(range(len(STAGES)), FMAX, color=BLUE, width=0.55)
    ax1.set_title("Fmax (MHz)", color=FG, fontsize=14 * scale, pad=pad, loc="left")
    ax1.set_ylim(0, max(FMAX) * 1.25)
    for b, v in zip(bars1, FMAX):
        ax1.text(b.get_x() + b.get_width() / 2, v + 3, f"{v:.2f}",
                 ha="center", color=FG, fontsize=12 * scale, fontweight="bold")

    bars2 = ax2.bar(range(len(STAGES)), LATENCY, color=ORANGE, width=0.55)
    ax2.set_title("Latency (ns)", color=FG, fontsize=14 * scale, pad=pad, loc="left")
    ax2.set_ylim(0, max(LATENCY) * 1.3)
    for b, v in zip(bars2, LATENCY):
        ax2.text(b.get_x() + b.get_width() / 2, v + 0.35, f"{v:.2f}",
                 ha="center", color=FG, fontsize=12 * scale, fontweight="bold")

    fig.text(0.05, 0.05,
             "Throughput: " + " / ".join(f"{t:.1f}" for t in THROUGHPUT) +
             " M events/s   |   ECP5 LFE5U-85F, Yosys + nextpnr post-route estimates",
             color=MUTED, fontsize=10 * scale)

    fig.savefig(out, facecolor=BG, dpi=100)
    plt.close(fig)
    print(f"wrote {out}")


def main() -> None:
    draw(12, 6.3, 1.0, ROOT / "docs" / "cover.png")
    draw(10, 4.2, 0.82, ROOT / "docs" / "cover_devto.png")


if __name__ == "__main__":
    main()
