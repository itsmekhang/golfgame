"""Trace turf/water outlines from the Augusta hole paintings.

Reads Augusta_Claude_Handoff/hole_blueprints.json (routes, scale, bunkers) and the
hole-map-N.jpg paintings, segments them by colour, and writes
assets/course/augusta_traced.json with, per hole (all in metres in the hole's local
frame: origin = route start (tee), +x = image right = direction of play, +y = image
down = golfer's right):
  route            polyline
  fairway_profile  [along, left_half_width, right_half_width] every PROFILE_STEP m
  fairway_polys    traced mown-fairway outlines
  green            {center, polygon, radial (RADIAL_BINS radii from centre)}
  tees             [{center, dir, half:[across, along]}] back tee first
  water            [{name, polygon}]
  bunkers          [{id, role, polygon}] (from the handoff JSON, smoothed)
Also writes a debug overlay PNG per hole into build/trace_debug/ for eyeballing.

Run: python tools/trace_augusta.py
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage
import contourpy

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HANDOFF = os.path.join(ROOT, "Augusta_Claude_Handoff")
DIAGRAMS = os.path.join(HANDOFF, "hole diagrams")
OUT_JSON = os.path.join(ROOT, "assets", "course", "augusta_traced.json")
DEBUG_DIR = os.path.join(ROOT, "build", "trace_debug")

DOWN = 4  # downsample factor for segmentation
# Hand corrections where the painting's shading misleads the colour trace:
# hole -> [(along_m, min_left_half_width, min_right_half_width), ...] interpolated
# between entries; the traced widths are raised to at least these values.
MIN_WIDTH_OVERRIDES = {
    1: [(130.0, 30.0, 14.0), (260.0, 30.0, 14.0), (295.0, 18.0, 14.0)],
    2: [(200.0, 0.0, 10.0), (240.0, 0.0, 45.0), (330.0, 0.0, 70.0), (500.0, 0.0, 70.0), (545.0, 0.0, 45.0)],
    # a left foot: narrow heel at the tee, widening, then the body swings right (dogleg)
    3: [(0.0, 28.0, 20.0), (40.0, 42.0, 26.0), (150.0, 44.0, 44.0), (200.0, 30.0, 62.0), (260.0, 24.0, 52.0), (300.0, 20.0, 26.0)],
    4: [(100.0, 22.0, 22.0), (150.0, 30.0, 30.0), (219.0, 30.0, 30.0)],
    5: [(110.0, 0.0, 30.0), (140.0, 0.0, 45.0), (240.0, 0.0, 45.0), (270.0, 0.0, 25.0)],
    7: [(0.0, 28.0, 28.0), (60.0, 45.0, 40.0), (130.0, 62.0, 40.0), (240.0, 62.0, 40.0), (260.0, 45.0, 40.0), (380.0, 45.0, 40.0), (411.0, 35.0, 35.0)],
    9: [(0.0, 40.0, 40.0), (60.0, 75.0, 50.0), (110.0, 80.0, 70.0), (190.0, 100.0, 60.0), (300.0, 110.0, 45.0), (380.0, 60.0, 30.0), (421.0, 30.0, 30.0)],
    8: [(0.0, 30.0, 30.0), (40.0, 30.0, 48.0), (120.0, 55.0, 48.0), (140.0, 55.0, 75.0), (240.0, 55.0, 75.0), (265.0, 26.0, 40.0), (340.0, 24.0, 24.0), (365.0, 24.0, 72.0), (475.0, 24.0, 72.0), (492.0, 24.0, 30.0), (511.0, 30.0, 45.0)],
    6: [(60.0, 20.0, 26.0), (100.0, 26.0, 28.0), (164.0, 28.0, 28.0)],
    10: [(50.0, 0.0, 40.0), (75.0, 0.0, 58.0), (130.0, 0.0, 58.0), (155.0, 0.0, 40.0), (320.0, 0.0, 20.0), (340.0, 0.0, 42.0), (405.0, 0.0, 42.0), (420.0, 0.0, 20.0)],
    11: [(20.0, 26.0, 26.0), (60.0, 30.0, 30.0), (290.0, 30.0, 30.0)],
    14: [(0.0, 0.0, 48.0), (100.0, 0.0, 48.0), (125.0, 0.0, 34.0)],
    15: [(110.0, 0.0, 40.0), (140.0, 0.0, 62.0), (470.0, 0.0, 62.0), (495.0, 0.0, 40.0)],
    16: [(30.0, 0.0, 40.0), (45.0, 0.0, 52.0), (80.0, 0.0, 52.0), (95.0, 0.0, 40.0)],
    17: [(160.0, 0.0, 40.0), (180.0, 0.0, 60.0), (390.0, 0.0, 60.0), (405.0, 0.0, 34.0)],
    # a fairway block left of the tee chute, then the whole dogleg/landing/green area mown
    18: [(0.0, 90.0, 20.0), (160.0, 90.0, 20.0), (190.0, 45.0, 30.0), (210.0, 80.0, 90.0), (425.0, 80.0, 90.0), (460.0, 40.0, 40.0)],
}
# hole -> [([(along_m, lateral_m), ...], width_m)]: hand-authored streams the painting
# only hints at
EXTRA_CREEKS = {
    13: [([(280.0, -30.0), (340.0, -28.0), (400.0, -26.0), (450.0, -24.0), (466.0, -22.0), (472.0, -10.0), (476.0, 4.0), (474.0, 16.0)], 3.5)],
}
# hole -> [(along_m, max_left_half_width, max_right_half_width), ...]: the traced widths
# are clamped down to these (rough pushed in), interpolated between entries
MAX_WIDTH_OVERRIDES = {
    7: [(0.0, 99.0, 15.0), (50.0, 99.0, 15.0), (65.0, 99.0, 40.0), (195.0, 99.0, 40.0)],
    5: [(55.0, 99.0, 22.0), (120.0, 99.0, 22.0), (150.0, 99.0, 30.0), (215.0, 99.0, 45.0)],
    # hole 10: the mown band shifts right past the branching bunker (rough pushed in on the left)
    10: [(320.0, 24.0, 99.0), (340.0, 14.0, 99.0), (405.0, 14.0, 99.0), (420.0, 24.0, 99.0)],
}
# hole -> [(along0_m, along1_m, lateral_m (+ = golfer's right), radius_m)]: capsule
# islands of rough with trees left standing inside the fairway
ROUGH_ISLANDS = {
    2: [(455.0, 465.0, 40.0, 14.0)],
    3: [(40.0, 145.0, -30.0, 10.0), (150.0, 172.0, 30.0, 10.0)],
    7: [(190.0, 370.0, -13.0, 15.0)],
    8: [(75.0, 97.0, 22.0, 8.0)],
    9: [(96.0, 299.0, -35.0, -65.0, 14.0), (212.0, 292.0, 20.0, 15.0)],
    10: [(90.0, 110.0, 37.0, 12.0)],
    15: [(262.0, 366.0, 33.0, 15.0), (412.0, 460.0, 31.0, 12.0)],
    17: [(190.0, 235.0, 42.0, 8.0), (250.0, 370.0, 44.0, 11.0)],
}
# small dark blobs this close to the tee are cast shadows on the tee clearing, not trees
TEE_BLOB_RADIUS_M = 60.0
TEE_BLOB_MAX_M2 = 350.0
PROFILE_STEP = 4.0  # metres between fairway width samples
RADIAL_BINS = 72
MAX_FAIRWAY_HALF = 70.0
MAX_GREEN_RADIUS = 40.0


def rgb_to_hsv(arr):
    arr = arr.astype(np.float32) / 255.0
    r, g, b = arr[..., 0], arr[..., 1], arr[..., 2]
    mx = arr.max(axis=-1)
    mn = arr.min(axis=-1)
    d = mx - mn
    h = np.zeros_like(mx)
    nz = d > 1e-6
    rc = np.where(nz, (mx - r) / np.maximum(d, 1e-6), 0)
    gc = np.where(nz, (mx - g) / np.maximum(d, 1e-6), 0)
    bc = np.where(nz, (mx - b) / np.maximum(d, 1e-6), 0)
    h = np.where(mx == r, bc - gc, np.where(mx == g, 2.0 + rc - bc, 4.0 + gc - rc))
    h = (h / 6.0) % 1.0
    h = np.where(nz, h, 0.0) * 360.0
    s = np.where(mx > 1e-6, d / np.maximum(mx, 1e-6), 0.0)
    return h, s, mx


def clean(mask, open_px=2, close_px=3):
    if open_px > 0:
        mask = ndimage.binary_opening(mask, iterations=open_px)
    if close_px > 0:
        mask = ndimage.binary_closing(mask, iterations=close_px)
    return mask


def components(mask, min_area):
    lab, n = ndimage.label(mask)
    out = []
    for i in range(1, n + 1):
        m = lab == i
        a = int(m.sum())
        if a >= min_area:
            out.append((a, m))
    out.sort(key=lambda t: -t[0])
    return [m for _, m in out]


def outline(mask):
    """Largest outer contour of a boolean mask as an (N,2) array of (x, y) pixels."""
    f = mask.astype(np.float32)
    f = np.pad(f, 1)
    gen = contourpy.contour_generator(z=f)
    lines = gen.lines(0.5)
    best = None
    best_area = 0.0
    for ln in lines:
        pts = np.asarray(ln) - 1.0
        if len(pts) < 4:
            continue
        x, y = pts[:, 0], pts[:, 1]
        a = abs(0.5 * np.sum(x * np.roll(y, -1) - np.roll(x, -1) * y))
        if a > best_area:
            best_area = a
            best = pts
    return best


def simplify(pts, tol):
    """Douglas-Peucker on a closed polyline."""
    pts = np.asarray(pts, dtype=np.float64)
    if len(pts) < 4:
        return pts
    n = len(pts)
    keep = np.zeros(n, dtype=bool)
    # anchor at two far-apart points so the closed loop is split into two chains
    i0 = 0
    d = np.linalg.norm(pts - pts[i0], axis=1)
    i1 = int(np.argmax(d))
    keep[i0] = keep[i1] = True

    def rec(a, b):
        if b - a < 2:
            return
        seg = pts[b] - pts[a]
        L = np.linalg.norm(seg)
        sub = pts[a + 1:b]
        if L < 1e-9:
            dist = np.linalg.norm(sub - pts[a], axis=1)
        else:
            dist = np.abs(np.cross(seg, sub - pts[a])) / L
        k = int(np.argmax(dist))
        if dist[k] > tol:
            keep[a + 1 + k] = True
            rec(a, a + 1 + k)
            rec(a + 1 + k, b)

    lo, hi = sorted((i0, i1))
    rec(lo, hi)
    # wrap chain: hi -> n-1 -> 0 -> lo
    if hi < n - 1 or lo > 0:
        wrapped = np.concatenate([pts[hi:], pts[:lo + 1]])
        wk = np.zeros(len(wrapped), dtype=bool)
        wk[0] = wk[-1] = True
        stack = [(0, len(wrapped) - 1)]
        while stack:
            a, b = stack.pop()
            if b - a < 2:
                continue
            seg = wrapped[b] - wrapped[a]
            L = np.linalg.norm(seg)
            sub = wrapped[a + 1:b]
            dist = np.linalg.norm(sub - wrapped[a], axis=1) if L < 1e-9 else np.abs(np.cross(seg, sub - wrapped[a])) / L
            k = int(np.argmax(dist))
            if dist[k] > tol:
                wk[a + 1 + k] = True
                stack.append((a, a + 1 + k))
                stack.append((a + 1 + k, b))
        for j in range(len(wrapped)):
            if wk[j]:
                keep[(hi + j) % n] = True
    return pts[keep]


def ray_extent(mask, origin, direction, max_px, gap_px, need_within_px):
    """Distance (px) along `direction` from `origin` to the far edge of the mask,
    ignoring gaps shorter than gap_px. 0 when the mask is not met within need_within_px."""
    h, w = mask.shape
    last_inside = -1.0
    gap = 0
    seen = False
    step = 0.5
    t = 0.0
    while t <= max_px:
        x = int(round(origin[0] + direction[0] * t))
        y = int(round(origin[1] + direction[1] * t))
        inside = 0 <= x < w and 0 <= y < h and mask[y, x]
        if inside:
            seen = True
            last_inside = t
            gap = 0
        else:
            if seen:
                gap += 1
                if gap * step > gap_px:
                    break
            elif t > need_within_px:
                break
        t += step
    return max(last_inside, 0.0)


def _min_width_profile(hole, alongs, table=None):
    """[(along, left, right)] from an override table, linearly interpolated."""
    table = MIN_WIDTH_OVERRIDES.get(hole) if table is None else table
    if not table:
        return []
    out = []
    for a in alongs:
        if a < table[0][0] or a > table[-1][0]:
            continue
        for (a0, l0, r0), (a1, l1, r1) in zip(table, table[1:]):
            if a0 <= a <= a1:
                t = (a - a0) / max(a1 - a0, 1e-6)
                out.append((a, l0 + (l1 - l0) * t, r0 + (r1 - r0) * t))
                break
    return out


def pca_box(mask, dir_vec):
    ys, xs = np.nonzero(mask)
    pts = np.stack([xs, ys], axis=1).astype(np.float64)
    c = pts.mean(axis=0)
    d = np.asarray(dir_vec, dtype=np.float64)
    d /= np.linalg.norm(d)
    r = np.array([-d[1], d[0]])
    along = (pts - c) @ d
    across = (pts - c) @ r
    return c, (float(across.max() - across.min()) * 0.5, float(along.max() - along.min()) * 0.5)


def chaikin(pts, iters=1):
    pts = np.asarray(pts, dtype=np.float64)
    for _ in range(iters):
        n = len(pts)
        out = []
        for i in range(n):
            a = pts[i]
            b = pts[(i + 1) % n]
            out.append(a * 0.75 + b * 0.25)
            out.append(a * 0.25 + b * 0.75)
        pts = np.asarray(out)
    return pts


def poly_area(p):
    x, y = p[:, 0], p[:, 1]
    return 0.5 * np.sum(x * np.roll(y, -1) - np.roll(x, -1) * y)


def rnd(v, nd=2):
    return [[round(float(a), nd) for a in p] for p in v]


def trace_hole(spec):
    n = spec["hole"]
    img = Image.open(os.path.join(DIAGRAMS, f"hole {n}", f"hole-map-{n}.jpg")).convert("RGB")
    W, H = img.size
    small = img.resize((W // DOWN, H // DOWN), Image.BILINEAR)
    arr = np.asarray(small).astype(np.float32)
    arr = np.stack([ndimage.gaussian_filter(arr[..., c], 1.2) for c in range(3)], axis=-1)
    hh, s, v = rgb_to_hsv(arr)
    m_per_px = spec["initial_plan_scale_m_per_original_pixel_proposed"] * DOWN

    def uv2px(uv):
        return np.array([uv[0] * W / DOWN, uv[1] * H / DOWN])

    route_px = np.array([uv2px(p) for p in spec["route_uv_approx"]])
    tee_px = route_px[0]

    def px2m(p):
        return (np.asarray(p, dtype=np.float64) - tee_px) * m_per_px

    green_hue = (hh > 80) & (hh < 140)
    pale = (hh > 60) & (hh < 140) & (s > 0.13) & (s < 0.41) & (v > 0.5)
    fairway = green_hue & (s >= 0.36) & (s < 0.478) & (v > 0.61)
    water = (hh > 185) & (hh < 235) & (s > 0.35) & (v > 0.18) & (v < 0.7)
    white = (s < 0.12) & (v > 0.8)

    pale_c = clean(pale, 1, 2)
    fair_c = clean(fairway | pale_c, 2, int(2.5 / m_per_px))
    water_c = clean(water, 1, 2)

    px_per_m = 1.0 / m_per_px
    result = {
        "hole": n, "name": spec["name"], "par": spec["par"], "yards": spec["yards_from_supplied_info"],
        "image_size_px": [W, H], "m_per_px_full": m_per_px / DOWN,
        "route": rnd([px2m(p) for p in route_px]),
        "profile": spec["terrain_profile_proposed"]["samples_s_height_m"],
        "green_relief": spec["green_proposed"]["internal_relief_range_m"],
        "green_envelope": [spec["green_proposed"]["width_across_approach_m"], spec["green_proposed"]["depth_along_approach_m"]],
        "landforms": spec["named_landforms_proposed"],
    }

    # ---- green: pale component containing / nearest the green locator
    gc_px = uv2px(spec["green_center_uv_approx"])
    green_mask = None
    best_d = 1e9
    for comp in components(pale_c, int(40 * px_per_m * px_per_m)):
        ys, xs = np.nonzero(comp)
        d = np.min((xs - gc_px[0]) ** 2 + (ys - gc_px[1]) ** 2)
        if d < best_d:
            best_d = d
            green_mask = comp
    if green_mask is None:
        raise RuntimeError(f"hole {n}: no green found")
    green_mask = ndimage.binary_fill_holes(green_mask)
    ys, xs = np.nonzero(green_mask)
    gcen = np.array([xs.mean(), ys.mean()])
    gpoly = simplify(outline(green_mask), 1.0)
    radial = []
    for i in range(RADIAL_BINS):
        a = 2 * math.pi * i / RADIAL_BINS
        d = (math.cos(a), math.sin(a))
        r = ray_extent(green_mask, gcen, d, MAX_GREEN_RADIUS * px_per_m, 1.5 * px_per_m, 2.0 * px_per_m)
        radial.append(round(float(r * m_per_px), 2))
    result["green"] = {"center": rnd([px2m(gcen)])[0], "polygon": rnd(px2m(gpoly)), "radial": radial}

    # ---- tees: other pale components, boxy, near the first route segment
    tees = []
    seg_dir = route_px[1] - route_px[0]
    seg_dir /= np.linalg.norm(seg_dir)
    for comp in components(pale_c & ~green_mask, int(25 * px_per_m * px_per_m)):
        ys, xs = np.nonzero(comp)
        c = np.array([xs.mean(), ys.mean()])
        # distance to the routing polyline (must be a tee-side feature)
        rel = c - route_px[0]
        along = rel @ seg_dir
        across = abs(rel[0] * -seg_dir[1] + rel[1] * seg_dir[0])
        total = np.sum(np.linalg.norm(np.diff(route_px, axis=0), axis=1))
        if along < -40 * px_per_m or along > 0.45 * total or across > 25 * px_per_m:
            continue
        cen, half = pca_box(comp, seg_dir)
        if half[0] < 2.0 * px_per_m or half[1] < 2.0 * px_per_m:
            continue
        fill = comp.sum() / (4.0 * half[0] * half[1])
        aspect = max(half) / min(half)
        sx, sy = int(route_px[0][0]), int(route_px[0][1])
        holds_start = ndimage.binary_dilation(comp, iterations=int(4 * px_per_m))[sy, sx]
        if not holds_start and (fill < 0.7 or aspect < 1.3):
            continue
        if holds_start and fill < 0.7:
            # merged/L-shaped tee complex: keep only the box around the route start
            half = (min(half[0], 6.0), min(half[1], 12.0))
            cen = route_px[0]
        tees.append({"center": rnd([px2m(cen)])[0], "dir": [round(float(seg_dir[0]), 4), round(float(seg_dir[1]), 4)],
                     "half": [round(float(half[0] * m_per_px), 2), round(float(half[1] * m_per_px), 2)],
                     "along": float(along)})
    tees.sort(key=lambda t: t["along"])
    for t in tees:
        del t["along"]
    result["tees"] = tees

    # ---- water
    waters = []
    for k, comp in enumerate(components(water_c, int(60 * px_per_m * px_per_m))):
        comp = ndimage.binary_fill_holes(comp)
        poly = simplify(outline(comp), 1.2)
        waters.append({"name": f"h{n:02d}_water_{k}", "polygon": rnd(px2m(poly))})
    result["water"] = waters

    # ---- fairway: mown components touching the route, minus the green itself
    fair_only = fair_c & ~ndimage.binary_dilation(green_mask, iterations=int(1.0 * px_per_m))
    fair_only &= ~ndimage.binary_dilation(water_c, iterations=2)
    keep = np.zeros_like(fair_only)
    route_mask = np.zeros_like(fair_only)
    # rasterise the route polyline thickly
    for i in range(len(route_px) - 1):
        a, b = route_px[i], route_px[i + 1]
        L = np.linalg.norm(b - a)
        for t in np.linspace(0, 1, int(L) + 1):
            p = a + (b - a) * t
            x, y = int(p[0]), int(p[1])
            if 0 <= x < route_mask.shape[1] and 0 <= y < route_mask.shape[0]:
                route_mask[y, x] = True
    route_mask = ndimage.binary_dilation(route_mask, iterations=int(12 * px_per_m))
    fpolys = []
    for comp in components(fair_only, int(300 * px_per_m * px_per_m)):
        if not (comp & route_mask).any():
            continue
        keep |= comp
        comp = ndimage.binary_fill_holes(comp)
        fpolys.append(rnd(px2m(simplify(outline(comp), 1.5))))
    result["fairway_polys"] = fpolys

    # width profile along the route
    profile = []
    acc = 0.0
    step_px = PROFILE_STEP * px_per_m
    for i in range(len(route_px) - 1):
        a, b = route_px[i], route_px[i + 1]
        L = np.linalg.norm(b - a)
        d = (b - a) / L
        nrm = np.array([-d[1], d[0]])  # image-down-ish = golfer's right
        t = 0.0
        while t < L:
            p = a + d * t
            right = ray_extent(keep, p, nrm, MAX_FAIRWAY_HALF * px_per_m, 4.0 * px_per_m, 14.0 * px_per_m)
            left = ray_extent(keep, p, -nrm, MAX_FAIRWAY_HALF * px_per_m, 4.0 * px_per_m, 14.0 * px_per_m)
            profile.append([float((acc + t) * m_per_px), float(left * m_per_px), float(right * m_per_px)])
            t += step_px
        acc += L
    # Mown turf behind the green (aprons, collars, the surrounds a painting shows as
    # short grass) continues the profile past the route end, until the mowing stops.
    a, b = route_px[-2], route_px[-1]
    d = (b - a) / np.linalg.norm(b - a)
    nrm = np.array([-d[1], d[0]])
    keep_ext = keep | green_mask
    t = 0.0
    misses = 0
    while t < 45.0 * px_per_m:
        p = b + d * t
        right = ray_extent(keep_ext, p, nrm, MAX_FAIRWAY_HALF * px_per_m, 4.0 * px_per_m, 6.0 * px_per_m)
        left = ray_extent(keep_ext, p, -nrm, MAX_FAIRWAY_HALF * px_per_m, 4.0 * px_per_m, 6.0 * px_per_m)
        if (left + right) * m_per_px < 4.0:
            misses += 1
            if misses >= 2:
                break
        else:
            misses = 0
        profile.append([float((acc + t) * m_per_px), float(left * m_per_px), float(right * m_per_px)])
        t += step_px
    while profile and profile[-1][1] + profile[-1][2] < 4.0:
        profile.pop()
    # Bridge gaps the painting's shading opens in the mown surface: a zero-width run
    # shorter than BRIDGE_MAX_M between two mown stretches is interpolated (dark tonal
    # bands are slopes, not rough), and a gap running into the green is the apron.
    # Gaps from the tee (rough carries) and long interior gaps (tee chutes) stay.
    BRIDGE_MAX_M = 45.0
    APRON_MAX_M = 50.0
    mown = [p[1] + p[2] >= 2.0 for p in profile]
    i = 0
    n_p = len(profile)
    while i < n_p:
        if mown[i]:
            i += 1
            continue
        j = i
        while j < n_p and not mown[j]:
            j += 1
        gap_m = profile[min(j, n_p - 1)][0] - profile[i][0]
        if j < n_p and profile[-1][0] - profile[j][0] < 12.0:
            j = n_p  # only a sliver of mown turf left before the green: this is the apron
        if i > 0 and j < n_p and gap_m <= BRIDGE_MAX_M:
            a, b = profile[i - 1], profile[j]
            for k in range(i, j):
                t = (profile[k][0] - a[0]) / max(b[0] - a[0], 1e-6)
                profile[k][1] = a[1] + (b[1] - a[1]) * t
                profile[k][2] = a[2] + (b[2] - a[2]) * t
        elif i > 0 and j >= n_p and gap_m <= APRON_MAX_M:
            a = profile[i - 1]
            apron = max(np.mean(radial) * 0.9, 8.0)
            for k in range(i, n_p):
                t = (profile[k][0] - a[0]) / max(profile[-1][0] - a[0], 1e-6)
                profile[k][1] = a[1] + (apron - a[1]) * t
                profile[k][2] = a[2] + (apron - a[2]) * t
        i = j
    # Smooth the ray extents: a median pass removes the isolated dips the painting's
    # shading stripes punch into an otherwise mown band, then a wide mean pass rounds
    # the edge so fairway/rough transitions are gentle curves, not jagged teeth. Done
    # before the bunker enclosure and hand overrides so those keep their exact values.
    for col in (1, 2):
        vals = np.array([p[col] for p in profile])
        med = ndimage.median_filter(vals, size=5, mode="nearest")
        sm = np.convolve(np.pad(med, 3, mode="edge"), np.ones(7) / 7.0, mode="valid")
        for p, val in zip(profile, sm):
            p[col] = val
    # Every bunker sits in mown turf (fairway bunkers in the fairway, greenside ones in
    # the apron): widen the mown band on their side to enclose the sand outline
    # (+ margin) wherever the painting's shaded flanks around the sand pinched the mask.
    BUNKER_MARGIN_M = 4.0
    for b in spec["bunkers"]:
        need = {}  # profile index -> (left, right) required
        for uv in b["outline_uv"]:
            q = uv2px(uv)
            best = None
            acc2 = 0.0
            for i in range(len(route_px) - 1):
                a, bb = route_px[i], route_px[i + 1]
                L = np.linalg.norm(bb - a)
                d = (bb - a) / L
                nrm = np.array([-d[1], d[0]])
                t = float(np.clip((q - a) @ d, 0.0, L))
                dist = np.linalg.norm(q - (a + d * t))
                if best is None or dist < best[0]:
                    best = (dist, (acc2 + t) * m_per_px, float((q - a) @ nrm) * m_per_px)
                acc2 += L
            along_m, lat_m = best[1], best[2]
            for k, p in enumerate(profile):
                if abs(p[0] - along_m) <= PROFILE_STEP * 1.5:
                    l, r = need.get(k, (0.0, 0.0))
                    if lat_m < 0:
                        l = max(l, -lat_m + BUNKER_MARGIN_M)
                    else:
                        r = max(r, lat_m + BUNKER_MARGIN_M)
                    need[k] = (l, r)
        if not need:
            continue
        k0, k1 = min(need), max(need)
        for k in range(max(k0 - 2, 0), min(k1 + 3, len(profile))):
            l, r = need.get(k, (0.0, 0.0))
            # taper the widening over the two samples either side of the sand
            fade = 1.0 if k0 <= k <= k1 else 0.5
            profile[k][1] = max(profile[k][1], max(need[kk][0] for kk in need) * fade if k < k0 or k > k1 else l)
            profile[k][2] = max(profile[k][2], max(need[kk][1] for kk in need) * fade if k < k0 or k > k1 else r)
    for along_m, lmin, rmin in _min_width_profile(n, [p[0] for p in profile]):
        for p in profile:
            if abs(p[0] - along_m) < 1e-6:
                p[1] = max(p[1], lmin)
                p[2] = max(p[2], rmin)
    for along_m, lmax, rmax in _min_width_profile(n, [p[0] for p in profile], MAX_WIDTH_OVERRIDES.get(n, [])):
        for p in profile:
            if abs(p[0] - along_m) < 1e-6:
                p[1] = min(p[1], lmax)
                p[2] = min(p[2], rmax)
    # a final gentle pass so hand overrides and bunker enclosures never leave a step
    # in the edge (an override that starts abruptly made a sharp rough corner on hole 2)
    for col in (1, 2):
        vals = np.array([p[col] for p in profile])
        sm = np.convolve(np.pad(vals, 2, mode="edge"), np.ones(5) / 5.0, mode="valid")
        for p, val in zip(profile, sm):
            p[col] = val
    result["fairway_profile"] = [[round(p[0], 1), round(p[1], 1), round(p[2], 1)] for p in profile]
    def route_offset_m(along_m, lat_m):
        acc2 = 0.0
        for i in range(len(route_px) - 1):
            a, bb = route_px[i], route_px[i + 1]
            L = np.linalg.norm(bb - a) * m_per_px
            if acc2 + L >= along_m or i == len(route_px) - 2:
                d = (bb - a) / np.linalg.norm(bb - a)
                nrm = np.array([-d[1], d[0]])
                q = a + d * ((along_m - acc2) / m_per_px) + nrm * (lat_m / m_per_px)
                return [round(float(v), 2) for v in px2m(q)]
            acc2 += L
    islands = []
    for entry in ROUGH_ISLANDS.get(n, []):
        # (along0, along1, lateral, r) or (along0, along1, lateral0, lateral1, r)
        along0, along1 = entry[0], entry[1]
        lat0, lat1, r_m = (entry[2], entry[2], entry[3]) if len(entry) == 4 else (entry[2], entry[3], entry[4])
        islands.append(route_offset_m(along0, lat0) + route_offset_m(along1, lat1) + [r_m])
    result["rough_islands"] = islands
    result["creek_paths"] = [{"path": [route_offset_m(a, l) for a, l in pts], "width": w} for pts, w in EXTRA_CREEKS.get(n, [])]

    # ---- woodland: tree canopy (dark saturated green) and pine straw (brown), closed
    # generously so a tree group reads as one footprint, minus open turf
    trees = (hh > 60) & (hh < 170) & (s > 0.42) & (v < 0.5)
    straw = (hh > 8) & (hh < 50) & (s > 0.18) & (v > 0.3) & (v < 0.85)
    canopy = trees | straw
    canopy = ndimage.binary_closing(canopy, iterations=int(3.0 * px_per_m))
    canopy = ndimage.binary_opening(canopy, iterations=int(1.5 * px_per_m))
    canopy &= ~ndimage.binary_dilation(keep | green_mask | water_c, iterations=int(1.0 * px_per_m))
    # the mown corridor from the (gap-bridged) width profile: shading bands on the
    # fairway are dark enough to pass as canopy, and must never become woodland
    corridor = Image.new("1", (small.size[0], small.size[1]), 0)
    cdraw = ImageDraw.Draw(corridor)
    acc = 0.0
    seg_pts = []
    for i in range(len(route_px) - 1):
        a, b = route_px[i], route_px[i + 1]
        L = np.linalg.norm(b - a)
        d = (b - a) / L
        nrm = np.array([-d[1], d[0]])
        for p in profile:
            if acc <= p[0] < acc + L or (i == len(route_px) - 2 and p[0] >= acc + L):
                q = a + d * (p[0] - acc)
                seg_pts.append((q, nrm, p[1] / m_per_px, p[2] / m_per_px))
        acc += L
    for (q, nrm, lw, rw) in seg_pts:
        if lw + rw < 3.0 / m_per_px:
            continue
        p0 = q - nrm * (lw + 3.0 / m_per_px)
        p1 = q + nrm * (rw + 3.0 / m_per_px)
        cdraw.line([tuple(p0), tuple(p1)], fill=1, width=int(PROFILE_STEP / m_per_px) + 2)
    canopy &= ~np.asarray(corridor, dtype=bool)
    # the illustration's white margin is not woodland
    canopy &= ~ndimage.binary_dilation(white, iterations=int(2.0 * px_per_m))
    woods = []
    for comp in components(canopy, int(120 * px_per_m * px_per_m)):
        comp = ndimage.binary_fill_holes(comp)
        area_m2 = comp.sum() * m_per_px * m_per_px
        ys_c, xs_c = np.nonzero(comp)
        near_tee = np.min((xs_c - tee_px[0]) ** 2 + (ys_c - tee_px[1]) ** 2) < (TEE_BLOB_RADIUS_M * px_per_m) ** 2
        if near_tee and area_m2 < TEE_BLOB_MAX_M2:
            continue
        woods.append(rnd(px2m(simplify(outline(comp), 1.5))))
    result["woods"] = woods
    # painted extent of the hole (everything outside the white margin), so the planter
    # knows where the painting is authoritative and where it must fill in itself
    painted = ~white
    painted = ndimage.binary_fill_holes(ndimage.binary_closing(painted, iterations=int(4.0 * px_per_m)))
    pcomp = components(painted, 1)[0]
    result["painted_extent"] = rnd(px2m(simplify(outline(pcomp), 3.0)))

    # ---- bunkers from the handoff JSON (image uv -> local metres), lightly smoothed
    bunkers = []
    for b in spec["bunkers"]:
        poly = np.array([uv2px(p) for p in b["outline_uv"]])
        poly = chaikin(poly, 1)
        bunkers.append({"id": b["id"], "role": b["role"], "polygon": rnd(px2m(poly))})
    result["bunkers"] = bunkers

    # ---- debug overlay
    os.makedirs(DEBUG_DIR, exist_ok=True)
    dbg = small.copy()
    ov = Image.new("RGBA", dbg.size, (0, 0, 0, 0))
    ovarr = np.zeros((dbg.size[1], dbg.size[0], 4), dtype=np.uint8)
    ovarr[keep] = (255, 255, 0, 70)
    ovarr[canopy] = (0, 60, 0, 120)
    ovarr[green_mask] = (255, 0, 255, 110)
    ovarr[water_c] = (0, 80, 255, 110)
    ov = Image.fromarray(ovarr)
    dbg = Image.alpha_composite(dbg.convert("RGBA"), ov)
    dr = ImageDraw.Draw(dbg)
    dr.line([tuple(p) for p in route_px], fill=(255, 0, 0, 255), width=2)
    for t in tees:
        c = np.array(t["center"]) / m_per_px + tee_px
        dr.ellipse([c[0] - 4, c[1] - 4, c[0] + 4, c[1] + 4], outline=(255, 128, 0, 255), width=2)
    for b in bunkers:
        pts = [tuple(np.array(p) / m_per_px + tee_px) for p in b["polygon"]]
        dr.polygon(pts, outline=(0, 0, 0, 255))
    for w in waters:
        pts = [tuple(np.array(p) / m_per_px + tee_px) for p in w["polygon"]]
        dr.polygon(pts, outline=(255, 255, 255, 255))
    pts = [tuple(np.array(p) / m_per_px + tee_px) for p in result["green"]["polygon"]]
    dr.polygon(pts, outline=(255, 255, 255, 255))
    for i in range(0, len(profile), 3):
        pass
    dbg.convert("RGB").save(os.path.join(DEBUG_DIR, f"hole{n:02d}.png"))

    print(f"hole {n:2d} {spec['name']:<22} green r~{np.mean(radial):5.1f} m  tees {len(tees)}  water {len(waters)}  fairway polys {len(fpolys)}  woods {len(woods)} ({canopy.mean() * 100:.0f}% canopy)  bunkers {len(bunkers)}")
    return result


def main():
    bp = json.load(open(os.path.join(HANDOFF, "hole_blueprints.json")))
    only = [int(a) for a in sys.argv[1:]]
    holes = []
    for spec in bp["holes"]:
        if only and spec["hole"] not in only:
            continue
        holes.append(trace_hole(spec))
    if only:
        return
    os.makedirs(os.path.dirname(OUT_JSON), exist_ok=True)
    with open(OUT_JSON, "w") as f:
        json.dump({"frame": "local metres: origin = route start, +x = play direction (image right), +y = golfer's right (image down)",
                   "profile_step_m": PROFILE_STEP, "radial_bins": RADIAL_BINS, "holes": holes}, f, separators=(",", ":"))
    print("wrote", OUT_JSON, os.path.getsize(OUT_JSON) // 1024, "KB")
    # contact sheet of the debug overlays
    cols, cw = 3, 640
    tiles = []
    for h in holes:
        im = Image.open(os.path.join(DEBUG_DIR, f"hole{h['hole']:02d}.png"))
        im = im.resize((cw, int(im.size[1] * cw / im.size[0])))
        tiles.append(im)
    rows = (len(tiles) + cols - 1) // cols
    rh = max(t.size[1] for t in tiles)
    sheet = Image.new("RGB", (cols * cw, rows * rh), (40, 40, 40))
    for i, t in enumerate(tiles):
        sheet.paste(t, ((i % cols) * cw, (i // cols) * rh))
    sheet.save(os.path.join(DEBUG_DIR, "contact_sheet.png"))


if __name__ == "__main__":
    main()
