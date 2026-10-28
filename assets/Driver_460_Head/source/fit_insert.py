"""Fit a left-right symmetric face insert inside the flat face's edge (flat top and bottom, round ends).

The shape: two superellipse halves sharing centre (cx, cz) and half-width a: the top half
(|dx/a|^NT + |dz/bt|^NT = 1) flatter, the bottom half (exponent NB, half-height bb) rounder,
like the head's own face-on outline (flat crown line, deeper sole line). Its ends are round
and convex. Chosen as large as fits MARGIN inside the face edge everywhere.

usage: fit_insert.py face_edge.json out.json [margin] [nt] [nb]
"""
import json
import sys

import numpy as np
from matplotlib.path import Path

edge = np.array(json.load(open(sys.argv[1])))
MARGIN = float(sys.argv[3]) if len(sys.argv) > 3 else 3.0
WIDTH_W = float(sys.argv[6]) if len(sys.argv) > 6 else 40.0  # how much width counts against area
NT = float(sys.argv[4]) if len(sys.argv) > 4 else 3.0
NB = float(sys.argv[5]) if len(sys.argv) > 5 else 2.4
poly = Path(edge)
seg_a, seg_b = edge, np.roll(edge, -1, axis=0)


def outline(cx, cz, a, bt, bb, n=240, nt=None, nb=None):
    """|dx/a|^NT + (dz/bt)^2 = 1 above the centre line, |dx/a|^NB + (dz/bb)^2 = 1 below: flat top
    and bottom, round arc ends (end radius ~2 b^2 / (NT a))."""
    t = np.linspace(0, 2 * np.pi, n, endpoint=False)
    c, s = np.cos(t), np.sin(t)
    top = s >= 0
    nt, nb = nt or NT, nb or NB
    x = cx + a * np.sign(c) * np.abs(c) ** np.where(top, 2 / nt, 2 / nb)
    z = cz + np.where(top, bt, bb) * s
    return np.stack([x, z], axis=1)


def clearance(pts):
    """Signed distance of every point to the face edge (positive inside)."""
    d = seg_b - seg_a
    w = pts[:, None, :] - seg_a[None, :, :]
    t = np.clip((w * d[None]).sum(-1) / ((d * d).sum(-1)[None] + 1e-12), 0, 1)
    dist = np.linalg.norm(w - t[..., None] * d[None], axis=-1).min(axis=1)
    return np.where(poly.contains_points(pts), dist, -dist)


def feasible(q):
    cx, cz, a, bt, bb, nt, nb = q
    if a < 5 or bt < 3 or bb < 3 or not (2.0 <= nt <= 4.5) or not (2.0 <= nb <= 4.5):
        return False
    return clearance(outline(cx, cz, a, bt, bb, 160, nt, nb)).min() >= MARGIN


def area(q):
    return q[2] * (q[3] + q[4])


# a global search (the hill-climb got stuck small): the widest symmetric insert that keeps
# MARGIN inside the face everywhere (its ends almost at the toe and heel edges), then the largest
from scipy.optimize import differential_evolution

xs, zs = edge[:, 0], edge[:, 1]
bounds = [(xs.min(), xs.max()), (zs.min(), zs.max()), (10.0, (xs.max() - xs.min()) / 2),
          (5.0, zs.max() - zs.min()), (5.0, zs.max() - zs.min()), (2.0, 4.5), (2.0, 4.5)]


def cost(q):
    cx, cz, a, bt, bb, nt, nb = q
    gap = clearance(outline(cx, cz, a, bt, bb, 160, nt, nb)).min() - MARGIN
    penalty = 0.0 if gap >= 0 else 1e5 * (1.0 - gap)
    return -(a * WIDTH_W + area(q)) + penalty


res = differential_evolution(cost, bounds, seed=1, popsize=40, maxiter=400, tol=1e-8, polish=False)
q = res.x
for _ in range(60):  # back off any residual infeasibility by shrinking about the centre
    if feasible(q):
        break
    q = q * np.array([1, 1, 0.995, 0.995, 0.995, 1, 1])
cx, cz, a, bt, bb, NT, NB = q
pts = outline(cx, cz, a, bt, bb, 240)
print("insert: centre x %.1f z %.1f, half-width %.1f, top %.1f, bottom %.1f, squareness top %.2f bottom %.2f (z %.1f..%.1f, x %.1f..%.1f), min clearance %.2f"
      % (cx, cz, a, bt, bb, NT, NB, cz - bb, cz + bt, cx - a, cx + a, clearance(pts).min()))
json.dump({"params": {"cx": cx, "cz": cz, "a": a, "bt": bt, "bb": bb, "nt": NT, "nb": NB, "margin": MARGIN},
           "outline": pts.tolist()}, open(sys.argv[2], "w"))
