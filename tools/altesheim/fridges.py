"""The kitchen's two upright reach-in fridges, modelled clean (crisp cabinets, inset doors with
gaskets, louvred vents and a condenser duct, chrome handles, a lit display) after the two
AI-generated reference fridges the user supplied, which were too lumpy to use as they were; the
doors close on safe-style edge-mount latches.

usage (project root): python3 -I tools/altesheim/fridges.py assets/facilities/props/altesheim
writes fridge_a.glb (two half doors, on casters) and fridge_b.glb (one full door, on feet).
Front faces -Z; centred on the footprint; floor at y = 0; metres.
"""
import io
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from brushed import box_uv, textures  # noqa: E402
from glb_lib import write_glb  # noqa: E402

STEEL, DARK, CHROME, RUBBER, SCREEN, PLASTIC = range(6)


class Mesh:
    def __init__(self):
        self.soup = {k: [] for k in range(6)}

    def _quad(self, mat, a, b, c, d, n, uv=None):
        P = np.array([a, b, c, a, c, d], float)
        N = np.repeat(np.array([n], float), 6, 0)
        self.soup[mat].append((P, N, None if uv is None else np.array([uv[0], uv[1], uv[2], uv[0], uv[2], uv[3]], float)))

    def box(self, mat, lo, hi, xf=None, skip=()):
        """Axis box lo..hi (optionally through a 3x4 transform); `skip` drops faces ('-z', '+y', ...)."""
        x0, y0, z0 = lo
        x1, y1, z1 = hi
        faces = {
            "-z": ([x1, y0, z0], [x0, y0, z0], [x0, y1, z0], [x1, y1, z0], [0, 0, -1]),
            "+z": ([x0, y0, z1], [x1, y0, z1], [x1, y1, z1], [x0, y1, z1], [0, 0, 1]),
            "-x": ([x0, y0, z0], [x0, y0, z1], [x0, y1, z1], [x0, y1, z0], [-1, 0, 0]),
            "+x": ([x1, y0, z1], [x1, y0, z0], [x1, y1, z0], [x1, y1, z1], [1, 0, 0]),
            "-y": ([x0, y0, z1], [x0, y0, z0], [x1, y0, z0], [x1, y0, z1], [0, -1, 0]),
            "+y": ([x0, y1, z0], [x0, y1, z1], [x1, y1, z1], [x1, y1, z0], [0, 1, 0]),
        }
        for k, (a, b, c, d, n) in faces.items():
            if k in skip:
                continue
            if xf is not None:
                R, t = xf[:, :3], xf[:, 3]
                a, b, c, d = (R @ np.array(v, float) + t for v in (a, b, c, d))
                n = R @ np.array(n, float)
            self._quad(mat, a, b, c, d, n)

    def cyl(self, mat, c, r, h, axis="y", seg=16, caps=True):
        c = np.array(c, float)
        ax = {"x": 0, "y": 1, "z": 2}[axis]
        u, v = [i for i in range(3) if i != ax]
        for i in range(seg):
            a0, a1 = 2 * math.pi * i / seg, 2 * math.pi * (i + 1) / seg
            p = []
            for a, s in ((a0, 0), (a1, 0), (a1, 1), (a0, 1)):
                q = c.copy(); q[u] += r * math.cos(a); q[v] += r * math.sin(a); q[ax] += s * h
                p.append(q)
            n0 = np.zeros(3); n0[u], n0[v] = math.cos((a0 + a1) / 2), math.sin((a0 + a1) / 2)
            self._quad(mat, p[0], p[3], p[2], p[1], n0) if (u, v) == (0, 2) else self._quad(mat, p[0], p[1], p[2], p[3], n0)
            if caps:
                for s, sign in ((0, -1), (1, 1)):
                    top = c.copy(); top[ax] += s * h
                    e0, e1 = p[3 * s if s else 0], p[2 if s else 1]
                    nn = np.zeros(3); nn[ax] = sign
                    tri = [top, e0, e1] if (sign > 0) == ((u, v) != (0, 2)) else [top, e1, e0]
                    self.soup[mat].append((np.array(tri), np.repeat([nn], 3, 0), None))

    def louvres(self, x0, x1, y0, y1, z, pitch=0.018, depth=0.03, tilt=35, frame=0.012):
        """A louvred vent in a front face at z: a dark cavity behind angled steel slats, framed."""
        self.box(DARK, (x0, y0, z), (x1, y1, z + depth), skip=("-z",))  # the cavity
        for lo, hi in (((x0 - frame, y0 - frame), (x1 + frame, y0)), ((x0 - frame, y1), (x1 + frame, y1 + frame)),
                       ((x0 - frame, y0), (x0, y1)), ((x1, y0), (x1 + frame, y1))):
            self.box(STEEL, (lo[0], lo[1], z - 0.004), (hi[0], hi[1], z + 0.004))
        y = y0 + pitch / 2
        t = math.radians(tilt)
        R = np.array([[1, 0, 0], [0, math.cos(t), -math.sin(t)], [0, math.sin(t), math.cos(t)]])
        while y < y1 - pitch / 3:
            xf = np.hstack([R, np.array([[0], [y], [z + 0.008]])])
            self.box(STEEL, (x0, -pitch * 0.42, -0.0015), (x1, pitch * 0.42, 0.0015), xf=xf)
            y += pitch

    def grille_side(self, x, y0, y1, z0, z1, side, pitch=0.022):
        """Slots in a side panel (x = the panel face), for the condenser to breathe."""
        y = y0
        while y + pitch * 0.45 < y1:
            self.box(DARK, (x - 0.003 if side > 0 else x - 0.0005, y, z0), (x + 0.0005 if side > 0 else x + 0.003, y + pitch * 0.45, z1))
            y += pitch

    def door(self, x0, x1, y0, y1, z, t=0.05, gap=0.006, panel_line=0.035):
        """A door standing proud of the cabinet face at z: rubber gasket round it, a pressed panel."""
        self.box(RUBBER, (x0 - gap, y0 - gap, z - 0.012), (x1 + gap, y1 + gap, z))  # the gasket ring behind
        self.box(STEEL, (x0, y0, z - t), (x1, y1, z - 0.012))
        # the pressed panel: a shallow raised field inside a groove
        g = 0.004
        self.box(DARK, (x0 + panel_line - g, y0 + panel_line - g, z - t - 0.0015), (x1 - panel_line + g, y1 - panel_line + g, z - t + 0.001))
        self.box(STEEL, (x0 + panel_line, y0 + panel_line, z - t - 0.004), (x1 - panel_line, y1 - panel_line, z - t))

    def bar_handle(self, a, b, z, off=0.045, r=0.012, post=0.009):
        """A chrome pull bar from a to b (x, y on the face) on two posts standing `off` proud of z."""
        a, b = np.array(a, float), np.array(b, float)
        axis = "x" if abs(b[0] - a[0]) > abs(b[1] - a[1]) else "y"
        lo, hi = np.minimum(a, b), np.maximum(a, b)
        self.cyl(CHROME, [lo[0], lo[1], z - off], r, float(np.max(hi - lo)), axis)
        step = np.array([0.03, 0.0]) if axis == "x" else np.array([0.0, 0.03])
        for p in (lo + step, hi - step):
            self.cyl(CHROME, [p[0], p[1], z - off], post, off, "z")

    def latch(self, x_edge, y, cab_z, door_t=0.05, reach=0.17, plate=False):
        """A safe-style edge-mount latch on a door's opening edge (+X): the chrome housing wrapping
        the edge, the keeper on the cabinet frame beside it, a pivot boss and a horizontal lever
        with a rounded grip reaching in across the door."""
        zf = cab_z - door_t  # the door's front face
        self.box(CHROME, (x_edge - 0.012, y - 0.034, zf - 0.012), (x_edge + 0.006, y + 0.034, cab_z - 0.012))  # housing on the edge
        self.box(CHROME, (x_edge + 0.012, y - 0.036, cab_z - 0.026), (x_edge + 0.026, y + 0.036, cab_z + 0.002))  # keeper on the stile
        self.cyl(CHROME, [x_edge - 0.02, y + 0.0, zf - 0.008], 0.008, 0.008, "z", seg=12)  # key lock
        self.box(DARK, (x_edge - 0.022, y - 0.004, zf - 0.0085), (x_edge - 0.018, y + 0.004, zf - 0.008))  # its key slot
        px = x_edge - 0.05  # the pivot
        self.cyl(CHROME, [px, y, zf - 0.03], 0.014, 0.03, "z", seg=16)  # pivot boss
        self.box(CHROME, (px - reach, y - 0.011, zf - 0.045), (px, y + 0.011, zf - 0.03))  # lever
        self.cyl(CHROME, [px - reach, y, zf - 0.046], 0.013, 0.017, "z", seg=16)  # rounded grip end
        if plate:  # the teardrop escutcheon the lever sweeps over: a pressed, tapering plate
            n = 7
            for i in range(n):
                f0, f1 = i / n, (i + 1) / n
                xa, xb = x_edge - 0.03 - f0 * reach * 0.62, x_edge - 0.03 - f1 * reach * 0.62  # (from by the pivot inwards)
                h = 0.05 * (1 - 0.75 * (f0 + f1) / 2)
                self.box(STEEL, (xb, y - h, zf - 0.006), (xa, y + h, zf))

    def hinge(self, x, y0, y1, z):
        self.cyl(CHROME, [x, y0, z - 0.03], 0.011, y1 - y0, "y")

    def screen(self, x0, x1, y0, y1, z):
        self.screen_aspect = (x1 - x0) / (y1 - y0)
        self.box(PLASTIC, (x0 - 0.008, y0 - 0.008, z - 0.004), (x1 + 0.008, y1 + 0.008, z + 0.001))
        P = np.array([[x1, y0, z - 0.0045], [x0, y0, z - 0.0045], [x0, y1, z - 0.0045], [x1, y0, z - 0.0045], [x0, y1, z - 0.0045], [x1, y1, z - 0.0045]])
        # seen from the front (looking +Z) world +X is on the left: x1 is the screen's left edge
        uv = np.array([[0, 1], [1, 1], [1, 0], [0, 1], [1, 0], [0, 0]], float)
        self.soup[SCREEN].append((P, np.repeat([[0, 0, -1.0]], 6, 0), uv))

    def button(self, x, y, z, r=0.011, mat=PLASTIC):
        self.cyl(CHROME, [x, y, z - 0.004], r + 0.003, 0.004, "z", seg=14)
        self.cyl(mat, [x, y, z - 0.008], r, 0.006, "z", seg=14)


def display_png(text, colour, aspect):
    """A seven-segment readout for a screen `aspect` times as wide as it is tall: digits keep their
    own proportions, right-aligned, like a controller's display."""
    h = 96
    w = int(round(h * aspect))
    im = Image.new("RGB", (w, h), (6, 10, 8))
    d = ImageDraw.Draw(im)
    segs = {"0": "abcdef", "1": "bc", "2": "abdeg", "3": "abcdg", "4": "bcfg", "5": "acdfg", "6": "acdefg",
            "7": "abc", "8": "abcdefg", "9": "abcdfg", "-": "g", "C": "adef", "F": "aefg"}
    ch_h = h - 30
    cw, t, gap = ch_h * 0.5, max(5, ch_h * 0.11), ch_h * 0.16
    advance = {".": t * 2.2, "°": cw * 0.62}
    width = sum(advance.get(c, cw + gap) for c in text)
    x, y = w - 14 - width, 15
    for ch in text:
        if ch == ".":
            d.rectangle([x, y + ch_h - t, x + t, y + ch_h], fill=colour)
        elif ch == "°":
            r = cw * 0.38  # a small ring up at the top of the line
            d.ellipse([x, y, x + r, y + r], outline=colour, width=max(3, int(t * 0.55)))
        elif ch == "+":
            d.rectangle([x, y + ch_h / 2 - t / 2, x + cw, y + ch_h / 2 + t / 2], fill=colour)
            d.rectangle([x + cw / 2 - t / 2, y + ch_h * 0.22, x + cw / 2 + t / 2, y + ch_h * 0.78], fill=colour)
        else:
            box = {"a": (x, y, x + cw, y + t), "g": (x, y + ch_h / 2 - t / 2, x + cw, y + ch_h / 2 + t / 2), "d": (x, y + ch_h - t, x + cw, y + ch_h),
                   "f": (x, y, x + t, y + ch_h / 2), "b": (x + cw - t, y, x + cw, y + ch_h / 2), "e": (x, y + ch_h / 2, x + t, y + ch_h), "c": (x + cw - t, y + ch_h / 2, x + cw, y + ch_h)}
            for sgm in segs.get(ch, ""):
                d.rectangle(box[sgm], fill=colour)
        x += advance.get(ch, cw + gap)
    b = io.BytesIO(); im.save(b, "PNG"); return b.getvalue()


def cabinet(m, w, h0, h1, d, front_z):
    """The cabinet shell: square, folded-steel edges."""
    x0, x1 = -w / 2, w / 2
    m.box(STEEL, (x0, h0, front_z), (x1, h1, front_z + d))
    # folded front edge: a slim proud frame round the opening
    for lo, hi in (((x0, h0), (x0 + 0.018, h1)), ((x1 - 0.018, h0), (x1, h1))):
        m.box(STEEL, (lo[0], lo[1], front_z - 0.004), (hi[0], hi[1], front_z))


def condenser(m, w, y0, y1, front_z, d):
    """The top-mounted condenser housing: louvred front, slotted sides, a duct out the back."""
    x0, x1 = -w / 2, w / 2
    m.box(STEEL, (x0 + 0.005, y0, front_z + 0.006), (x1 - 0.005, y1, front_z + d - 0.01))
    m.box(STEEL, (x0, y1 - 0.004, front_z), (x1, y1 + 0.012, front_z + d))  # lid lip
    m.grille_side(x1 - 0.005, y0 + 0.03, y1 - 0.03, front_z + 0.12, front_z + d - 0.12, 1)
    m.grille_side(x0 + 0.005, y0 + 0.03, y1 - 0.03, front_z + 0.12, front_z + d - 0.12, -1)
    duct(m, y1 + 0.012, front_z + d)


def duct(m, y, zb):
    """The condenser exhaust: a short rectangular stack on top at the back, a slatted outlet."""
    y1 = y - 0.012
    m.box(STEEL, (-0.17, y1 + 0.012, zb - 0.22), (0.17, y1 + 0.10, zb - 0.04))
    m.box(DARK, (-0.15, y1 + 0.10, zb - 0.20), (0.15, y1 + 0.103, zb - 0.06))
    for i in range(9):
        x = -0.15 + 0.0375 * i
        m.box(STEEL, (x - 0.003, y1 + 0.100, zb - 0.20), (x + 0.003, y1 + 0.106, zb - 0.06))
    m.box(STEEL, (-0.17, y1 + 0.103, zb - 0.135), (0.17, y1 + 0.108, zb - 0.125))


def fridge_a():
    """Two half doors on casters, after the user's reference photo of a two half-door reach-in:
    full-height side stiles, three big louvres over a control strip, chrome hinge blocks on the
    right, safe-style lever latches on the left by the split, a bottom rail on swivel casters."""
    m = Mesh()
    W, D, F = 0.73, 0.78, -0.39  # width, cabinet depth, cabinet front z
    base, top = 0.13, 2.0
    stile = 0.085  # each side
    xl, xr = W / 2 - stile, -(W / 2 - stile)  # the opening between the stiles (+X is the viewer's left)
    m.box(STEEL, (-W / 2, base, F + 0.01), (W / 2, top, F + D))  # the cabinet
    for x0, x1 in ((W / 2 - stile, W / 2), (-W / 2, -W / 2 + stile)):  # the stiles, full height
        m.box(STEEL, (x0, base - 0.01, F - 0.004), (x1, top, F + 0.01))
    # the head: three big angled louvres in a recess, the control strip under them
    m.box(DARK, (xr, 1.765, F + 0.01), (xl, top - 0.008, F + 0.06), skip=("-z",))
    m.box(STEEL, (xr, top - 0.012, F - 0.004), (xl, top, F + 0.01))
    t = math.radians(28)
    R = np.array([[1, 0, 0], [0, math.cos(t), -math.sin(t)], [0, math.sin(t), math.cos(t)]])
    for i in range(3):
        y = top - 0.045 - i * 0.075
        m.box(STEEL, (xr + 0.004, -0.036, -0.004), (xl - 0.004, 0.036, 0.004), xf=np.hstack([R, np.array([[0], [y], [F + 0.022]])]))
    m.box(STEEL, (xr, 1.645, F - 0.006), (xl, 1.765, F + 0.01))  # control strip
    m.screen(0.175, 0.255, 1.725, 1.75, F - 0.006)
    for i in range(3):
        m.button(0.24 - i * 0.022, 1.705, F - 0.006, r=0.004, mat=PLASTIC)
    m.box(CHROME, (-0.04, 1.672, F - 0.009), (0.04, 1.692, F - 0.006))  # the name plate (left blank)
    # the half doors between the stiles, the bottom rail under them
    for y0, y1 in ((0.915, 1.64), (0.178, 0.905)):
        m.door(xr + 0.006, xl - 0.006, y0, y1, F, panel_line=0.0)
    m.box(STEEL, (xr, base, F - 0.006), (xl, 0.172, F + 0.01))
    # hinges: tall chrome blocks proud of the right edge, top and bottom of each door
    for y0, y1 in ((1.50, 1.60), (0.95, 1.05), (0.80, 0.89), (0.20, 0.30)):
        m.box(CHROME, (xr - 0.012, y0, F - 0.058), (xr + 0.018, y1, F - 0.008))
        m.box(DARK, (xr - 0.013, (y0 + y1) / 2 - 0.002, F - 0.059), (xr + 0.019, (y0 + y1) / 2 + 0.002, F - 0.05))
    # safe-style lever latches on the left, close by the split
    for y in (1.02, 0.80):
        m.latch(xl - 0.006, y, F, reach=0.22, plate=True)
    duct(m, top, F + D)
    # swivel casters
    for x in (-W / 2 + 0.07, W / 2 - 0.07):
        for z in (F + 0.08, F + D - 0.08):
            m.box(STEEL, (x - 0.045, base - 0.014, z - 0.045), (x + 0.045, base, z + 0.045))  # swivel plate
            m.box(CHROME, (x - 0.02, 0.06, z - 0.028), (x - 0.012, base - 0.014, z + 0.028))  # fork
            m.box(CHROME, (x + 0.012, 0.06, z - 0.028), (x + 0.02, base - 0.014, z + 0.028))
            m.cyl(RUBBER, [x - 0.012, 0.058, z], 0.058, 0.024, "x", seg=20)  # wheel
            m.cyl(CHROME, [x - 0.014, 0.058, z], 0.02, 0.028, "x", seg=12)  # hub
    return m


def fridge_b():
    """One full door on adjustable feet, a control head with display and vent across the top."""
    m = Mesh()
    W, D, F = 0.73, 0.86, -0.43
    base = 0.09
    cabinet(m, W, base, 1.69, D, F)
    condenser(m, W, 1.69, 1.985, F, D)
    m.box(STEEL, (-W / 2 + 0.01, 1.70, F - 0.012), (W / 2 - 0.01, 1.975, F + 0.006))  # the control fascia
    m.screen(0.12, 0.29, 1.79, 1.87, F - 0.012)
    for i, mat in enumerate((STEEL, PLASTIC, PLASTIC)):
        m.button(0.065 - i * 0.052, 1.83, F - 0.012, r=0.013, mat=mat)
    m.louvres(-0.33, -0.10, 1.76, 1.92, F - 0.012)
    m.box(DARK, (-W / 2 + 0.02, 1.688, F - 0.004), (W / 2 - 0.02, 1.695, F))
    m.door(-0.345, 0.345, 0.12, 1.67, F)
    m.latch(0.345, 1.05, F)  # the safe-style latch on the opening edge
    for y0, y1 in ((1.52, 1.64), (0.15, 0.27)):
        m.hinge(-0.352, y0, y1, F)
    m.box(STEEL, (-W / 2, base - 0.02, F + 0.03), (W / 2, base, F + D - 0.02))
    m.louvres(-0.30, 0.30, 0.10, 0.115, F - 0.001, pitch=0.008, tilt=20)
    for x in (-W / 2 + 0.05, W / 2 - 0.05):
        for z in (F + 0.07, F + D - 0.07):
            m.cyl(STEEL, [x, 0.012, z], 0.016, base - 0.02 - 0.012, "y", seg=12)
            m.cyl(RUBBER, [x, 0.0, z], 0.024, 0.012, "y", seg=14)
    return m


def write(m, path, name, display):
    alb, mr = textures()
    images = [(alb, "image/png"), (mr, "image/png"), (display_png(*display, m.screen_aspect), "image/png")]
    mats = [
        {"name": "brushed_steel", "baseColorTexture": 0, "mrTexture": 1,
         "pbrMetallicRoughness": {"baseColorFactor": [0.80, 0.805, 0.82, 1], "metallicFactor": 0.9, "roughnessFactor": 1.0}},
        {"name": "vent_dark", "pbrMetallicRoughness": {"baseColorFactor": [0.03, 0.03, 0.035, 1], "metallicFactor": 0.0, "roughnessFactor": 0.85}},
        {"name": "chrome", "pbrMetallicRoughness": {"baseColorFactor": [0.92, 0.93, 0.95, 1], "metallicFactor": 1.0, "roughnessFactor": 0.12}},
        {"name": "gasket", "pbrMetallicRoughness": {"baseColorFactor": [0.06, 0.06, 0.065, 1], "metallicFactor": 0.0, "roughnessFactor": 0.9}},
        {"name": "display", "baseColorTexture": 2, "emissiveTexture": 2, "emissiveFactor": [1, 1, 1],
         "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0.0, "roughnessFactor": 0.2}},
        {"name": "black_plastic", "pbrMetallicRoughness": {"baseColorFactor": [0.05, 0.05, 0.055, 1], "metallicFactor": 0.0, "roughnessFactor": 0.45}},
    ]
    # centre the footprint (handles included) on the origin, floor at y = 0, like the cut-out pieces
    allP = np.concatenate([p for lst in m.soup.values() for p, _, _ in lst])
    lo, hi = allP.min(0), allP.max(0)
    shift = np.array([-(lo[0] + hi[0]) / 2, -lo[1], -(lo[2] + hi[2]) / 2])
    for lst in m.soup.values():
        for i, (p, n, uv) in enumerate(lst):
            lst[i] = (p + shift, n, uv)
    parts, used = [], []
    for mi in range(6):
        if not m.soup[mi]:
            continue
        P = np.concatenate([p for p, _, _ in m.soup[mi]])
        N = np.concatenate([n for _, n, _ in m.soup[mi]])
        N = N / np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-9)
        if mi == SCREEN:
            UV = np.concatenate([uv for _, _, uv in m.soup[mi]])
        elif mi == STEEL:
            UV = box_uv(P, N, tile=0.5)
        else:
            UV = None
        cols = [P, N] + ([UV] if UV is not None else [])
        _, first, inv = np.unique(np.round(np.concatenate(cols, 1), 5), axis=0, return_index=True, return_inverse=True)
        used.append(mats[mi])
        parts.append((len(used) - 1, P[first], N[first], None if UV is None else UV[first], inv.ravel().astype(np.uint32)))
    for mt in used:
        mt["doubleSided"] = True
        if "emissiveTexture" in mt:
            mt["emissiveTexture"] = {"index": mt["emissiveTexture"]}
    write_glb(path, name, parts, used, images)
    allP = np.concatenate([p[1] for p in parts])
    print("%s: %d triangles, size %s, %d KB" % (os.path.basename(path), sum(len(p[4]) // 3 for p in parts),
                                                 np.round(allP.max(0) - allP.min(0), 3), os.path.getsize(path) // 1024))


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    write(fridge_a(), os.path.join(out, "fridge_a.glb"), "Kitchen_fridge_a", ("36.3°F", (255, 80, 60)))  # (as on the reference: 2.4 C)
    write(fridge_b(), os.path.join(out, "fridge_b.glb"), "Kitchen_fridge_b", ("+3°C", (90, 255, 150)))
