"""Plot holes dumped by tools/dump_hole_features.gd, one PNG per hole, in the hole's own
frame (tee at the bottom, green at the top, golfer's right to the right), with a metre grid
so features can be authored in CourseBuilder's local coordinates.

    python tools/plot_hole_features.py build/holes.json build/holemap
"""
import json
import sys

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.colors import ListedColormap

SURF = {0: 1, 1: 1, 2: 0, 3: 0, 4: 3, 5: 4, 100: 4, 101: 5, 102: 2, 103: 1, 104: 3, 105: 6}
COLS = ["#2f5a2a", "#6fbf4a", "#9ad06e", "#b8f08a", "#f0e2b0", "#3a7bd5", "#1e3d1a"]


def main(path, prefix):
    data = json.load(open(path))
    for n, h in data.items():
        g = h["grid"]
        xs = sorted({c[0] for c in g})
        ys = sorted({c[1] for c in g})
        xi = {v: i for i, v in enumerate(xs)}
        yi = {v: i for i, v in enumerate(ys)}
        img = [[0] * len(ys) for _ in xs]
        hgt = [[0.0] * len(ys) for _ in xs]
        for ax, ay, s, z in g:
            img[xi[ax]][yi[ay]] = SURF.get(s, 0)
            hgt[xi[ax]][yi[ay]] = z
        span_x = xs[-1] - xs[0]
        span_y = ys[-1] - ys[0]
        fig, axs = plt.subplots(1, 2, figsize=(20, 10 * span_x / span_y + 1.5))
        for k, ax in enumerate(axs):
            ext = [ys[0] - 2, ys[-1] + 2, xs[0] - 2, xs[-1] + 2]
            if k == 0:
                ax.imshow(img, origin="lower", extent=ext, cmap=ListedColormap(COLS), vmin=0, vmax=6, interpolation="nearest")
            else:
                im = ax.imshow(hgt, origin="lower", extent=ext, cmap="terrain", interpolation="bilinear")
                cs = ax.contour([[hgt[i][j] for j in range(len(ys))] for i in range(len(xs))], levels=24, colors="k", linewidths=0.4, extent=ext, origin="lower")
                ax.clabel(cs, fontsize=6, fmt="%.1f")
                plt.colorbar(im, ax=ax, fraction=0.03)
            for w in h["water"]:
                p = w["poly"] + [w["poly"][0]]
                ax.plot([q[1] for q in p], [q[0] for q in p], color="cyan" if k else "navy", lw=1.0)
                ax.text(p[0][1], p[0][0], w["name"], fontsize=6, color="navy")
            for b in h["bunkers"]:
                p = b["poly"] + [b["poly"][0]]
                ax.plot([q[1] for q in p], [q[0] for q in p], color="#a08040", lw=0.8)
            for wd in h["woods"]:
                p = wd + [wd[0]]
                ax.plot([q[1] for q in p], [q[0] for q in p], color="#0a2a0a", lw=0.6, ls="--")
            for t in h["trees"]:
                ax.plot(t[2], t[1], "o", color="darkgreen", ms=3)
            for isl in h["islands"]:
                a, b, r, veg = isl
                ax.plot([a[1], b[1]], [a[0], b[0]], color="orange" if veg else "gray", lw=1.5)
            r = h["route"]
            ax.plot([q[1] for q in r], [q[0] for q in r], "w--", lw=0.8)
            for t in h["tees"]:
                ax.plot(t[1], t[0], "s", color="white", ms=6, mec="k")
            gc = h["green_center"]
            ax.plot(gc[1], gc[0], "r+", ms=10)
            ax.set_xticks(range(-150, 151, 25))
            ax.set_xticks(range(-150, 151, 5), minor=True)
            ax.set_yticks(range(int(xs[0]) // 25 * 25, int(xs[-1]) + 1, 25))
            ax.set_yticks(range(int(xs[0]) // 5 * 5, int(xs[-1]) + 1, 5), minor=True)
            ax.grid(which="both", lw=0.2, color="k", alpha=0.35)
            ax.set_xlabel("y (golfer's right +)")
            ax.set_ylabel("x (along, from back tee)")
            ax.set_title("Hole %s %s" % (n, "surfaces" if k == 0 else "height (m)"))
            ax.set_xlim(ys[0] - 2, ys[-1] + 2)
            ax.set_ylim(xs[0] - 2, xs[-1] + 2)
            ax.set_aspect("equal")
        out = "%s_%s.png" % (prefix, n)
        fig.tight_layout()
        fig.savefig(out, dpi=110)
        plt.close(fig)
        print("wrote", out)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
