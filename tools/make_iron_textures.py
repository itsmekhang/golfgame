"""Back art for the forged iron sets (tools/freecad/export_iron_heads.py), one livery per set.

Each set's back is drawn face-on as seen from behind (x heel -> toe left to right, z up the face, mm;
the frame and the head outlines come from assets/Iron_Heads/geo/<head>/art.json and back_mask.png,
written by the exporter's geo stage), as a colour map and a glTF metal/rough map (G = roughness,
B = metallic). The art's ground is the body's own finish: the exporter projects it square to the face
over the whole head but the face, so the sole, top line, toe and hosel take the plain finish.

    python tools/make_iron_textures.py
"""
import json
import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE = os.environ.get("IRON_ASSET_DIR", os.path.join(ROOT, "assets", "Iron_Heads"))
GEO, OUT = os.path.join(BASE, "geo"), os.path.join(BASE, "textures")
FONTS = "C:/Windows/Fonts/"
F = {"tech": "AGENCYB.TTF", "sport": "FRADMIT.TTF", "heavy": "ariblk.ttf", "stencil": "STENCIL.TTF",
     "serial": "OCRAEXT.TTF", "classy": "COPRGTB.TTF", "hand": "Inkfree.ttf", "clean": "bahnschrift.ttf",
     "italic": "TCBI____.TTF", "impact": "impact.ttf", "script": "BRUSHSCI.TTF"}
HEAD_UP = 180.0  # every lettering turned half round: it reads with the head up and the grip down,
                 # as irons are made to be read (in the bag, held up), not at address
SETS = {"loaner_irons": "cb", "thrift_cavity_backs": "cb", "game_improver_xl": "gi", "mustard_muscle": "mb",
        "blade_runner_forged": "blade", "tour_forged_cb": "cb", "combo_proto": "mb", "utility_2u": "2u"}


class Canvas:
    """The frame of one head's art: BOX (x0, x1, z0, z1) mm at PPM px/mm, row 0 at z1."""

    def __init__(self, box, ppm):
        self.box, self.ppm = box, ppm
        x0, x1, z0, z1 = box
        self.w, self.h = round((x1 - x0) * ppm), round((z1 - z0) * ppm)
        self.X, self.Z = np.meshgrid(x0 + (np.arange(self.w) + 0.5) / ppm, z1 - (np.arange(self.h) + 0.5) / ppm)

    def px(self, x, z):
        x0, _, _, z1 = self.box
        return (x - x0) * self.ppm, (z1 - z) * self.ppm

    def shape(self, draw_fn, ss=3):
        img = Image.new("L", (self.w * ss, self.h * ss), 0)

        def sc(x, z):
            a, b = self.px(x, z)
            return a * ss, b * ss
        draw_fn(ImageDraw.Draw(img), sc, ss)
        return np.asarray(img.resize((self.w, self.h), Image.LANCZOS), float) / 255.0

    def poly(self, pts):
        return self.shape(lambda d, sc, ss: d.polygon([sc(*p) for p in pts], fill=255))

    def line(self, pts, width):
        return self.shape(lambda d, sc, ss: d.line([sc(*p) for p in pts], fill=255,
                                                   width=max(1, int(width * self.ppm * ss)), joint="curve"))

    def disc(self, c, r):
        return self.shape(lambda d, sc, ss: d.ellipse([*sc(c[0] - r, c[1] + r), *sc(c[0] + r, c[1] - r)], fill=255))

    def text(self, text, font, height, centre, turn=0.0, tracking=0.0, skew=0.0):
        """Antialiased text, cap height ~height mm, centred, turned anticlockwise by `turn` degrees."""
        ss = 3
        f = ImageFont.truetype(FONTS + F[font], int(height * self.ppm * ss * 1.35))
        widths = [f.getlength(ch) for ch in text]
        total = sum(widths) + tracking * self.ppm * ss * max(len(text) - 1, 0)
        box = f.getbbox(text)
        tw, th = int(total + 8 + abs(skew) * (box[3] - box[1])), int(box[3] - box[1] + 8)
        img = Image.new("L", (tw, th), 0)
        d = ImageDraw.Draw(img)
        x = 4
        for ch, wd in zip(text, widths):
            d.text((x - box[0] * (x == 4), 4 - box[1]), ch, font=f, fill=255)
            x += wd + tracking * self.ppm * ss
        if skew:
            img = img.transform(img.size, Image.AFFINE, (1, skew, -skew * th / 2, 0, 1, 0), Image.BICUBIC)
        img = img.resize((max(1, tw // ss), max(1, th // ss)), Image.LANCZOS)
        turn += HEAD_UP
        if turn:
            img = img.rotate(turn, resample=Image.BICUBIC, expand=True)
        out = Image.new("L", (self.w, self.h), 0)
        cx, cy = self.px(*centre)
        out.paste(img, (int(round(cx - img.width / 2)), int(round(cy - img.height / 2))))
        return np.asarray(out, float) / 255.0

    def noise(self, rng, sx, sz=None):
        g = np.random.default_rng(rng.randint(0, 10 ** 9)).standard_normal((self.h, self.w))
        g = ndimage.gaussian_filter(g, (max((sz if sz is not None else sx) * self.ppm, 0.3), max(sx * self.ppm, 0.3)))
        return g / (g.std() + 1e-9)

    def dist_in(self, mask):
        return ndimage.distance_transform_edt(mask > 0.5) / self.ppm


class Layer:
    def __init__(self, cv, rgb, rough, metal):
        self.c = np.ones((cv.h, cv.w, 3)) * np.array(rgb, float)
        self.r = np.full((cv.h, cv.w), float(rough))
        self.m = np.full((cv.h, cv.w), float(metal))

    def paint(self, alpha, rgb=None, rough=None, metal=None):
        a = np.clip(alpha, 0, 1)
        if rgb is not None:
            rgb = np.asarray(rgb, float)
            self.c = self.c * (1 - a[..., None]) + (rgb if rgb.ndim == 3 else rgb[None, None]) * a[..., None]
        if rough is not None:
            self.r = self.r * (1 - a) + np.asarray(rough, float) * a
        if metal is not None:
            self.m = self.m * (1 - a) + np.asarray(metal, float) * a

    def shade(self, alpha, k):
        a = np.clip(alpha, 0, 1)[..., None]
        self.c = self.c + ((255.0 if k > 0 else 0.0) - self.c) * a * abs(k)

    def save(self, club):
        Image.fromarray(np.clip(self.c, 0, 255).astype(np.uint8)).save(os.path.join(OUT, club + "_back.png"))
        mr = np.stack([np.full(self.r.shape, 255.0), np.clip(self.r, 0, 255), np.clip(self.m, 0, 255)], -1)
        Image.fromarray(mr.astype(np.uint8)).save(os.path.join(OUT, club + "_back_rough.png"))


class Head:
    """One head's outlines (mm, face coordinates) and masks on its canvas."""

    def __init__(self, name):
        d = os.path.join(GEO, name)
        self.info = json.load(open(os.path.join(d, "info.json")))
        self.art = json.load(open(os.path.join(d, "art.json")))
        self.cv = Canvas(tuple(self.info["box"]), self.info["ppm"])
        self.back = np.asarray(Image.open(os.path.join(d, "back_mask.png")).convert("L"), float) / 255.0
        a = self.art
        self.pocket = self.cv.poly(a["pocket"]) if "pocket" in a else None
        self.panel = self.cv.poly(a["panel"]) if "panel" in a else None
        self.weight = self.cv.poly(a["weight"]) if "weight" in a else None
        X, Z = self.cv.X, self.cv.Z
        xs = np.array([p[0] for p in a["top"]])
        self.top_z = np.interp(X, xs, [p[1] for p in a["top"]])
        if "crease" in a:
            self.crease_z = np.interp(X, xs, [p[1] for p in a["crease"]])
            self.lip_z = np.interp(X, xs, [p[1] for p in a["lip"]])
        if "pad" in a:
            self.pad_lo = np.interp(X, xs, [p[1] for p in a["pad"]])
        else:
            self.pad_lo = None

    def band(self, lo, hi, soft=0.1):
        Z = self.cv.Z
        return np.clip((Z - lo) / soft + 0.5, 0, 1) * np.clip((hi - Z) / soft + 0.5, 0, 1)

    def x_range(self, a, b, soft=0.1):
        X = self.cv.X
        return np.clip((X - a) / soft + 0.5, 0, 1) * np.clip((b - X) / soft + 0.5, 0, 1)

    def plate(self):
        """The upper back: from the muscle's top (the bevel's top) up to the top line."""
        return self.band(self.lip_z, self.top_z) * self.back

    def pad(self, lo_pad=1.0):
        """The muscle pad: from the trailing edge's round up to the crease."""
        lo = self.pad_lo if self.pad_lo is not None else self.crease_z - 9.0
        return self.band(lo + lo_pad, self.crease_z) * self.back

    def bevel(self):
        return self.band(self.crease_z, self.lip_z) * self.back

    def mid_x(self):
        xs = [p[0] for p in self.art["top"]]
        return (min(xs) + 10 + 78) / 2


def inner(cv, mask, x_from=-1e9, x_to=1e9):
    """The point deepest inside mask (between x_from and x_to): (x, z, its distance to the edge, mm)."""
    d = cv.dist_in(mask) * ((cv.X >= x_from) & (cv.X <= x_to))
    i = np.unravel_index(int(np.argmax(d)), d.shape)
    return float(cv.X[i]), float(cv.Z[i]), float(d[i])


def fit(cv, mask, text, font, height, centre=None, tracking=0.0, skew=0.0, turn=0.0, margin=0.6):
    """Lettering inside mask: at centre (default: the deepest point), shrunk until it all lies at
    least `margin` mm inside. Returns (alpha, its bounding box in mm or None)."""
    room = cv.dist_in(mask) >= margin
    if centre is None:
        x, z, _ = inner(cv, mask)
        centre = (x, z)
    h = height
    while h > 0.6:
        a = cv.text(text, font, h, centre, turn=turn, tracking=tracking, skew=skew)
        if (a * (1 - room)).sum() <= 0.01 * max(a.sum(), 1e-9):
            ys, xs = np.nonzero(a > 0.3)
            return a, (cv.X[0, xs.min()], cv.X[0, xs.max()], cv.Z[ys.max(), 0], cv.Z[ys.min(), 0])
        h *= 0.92
    return np.zeros_like(cv.X), None


def without(cv, mask, box, pad=1.2):
    """mask with the box (x0, x1, z0, z1) and pad mm round it taken out."""
    if box is None:
        return mask
    x0, x1, z0, z1 = box
    return mask * ~((cv.X > x0 - pad) & (cv.X < x1 + pad) & (cv.Z > z0 - pad) & (cv.Z < z1 + pad))


def centroid(cv, mask):
    w = mask > 0.5
    return float(cv.X[w].mean()), float(cv.Z[w].mean())


def between_screws(cv, h, clear=3.0):
    """The weight bar without its screw heads (and a little round them)."""
    m = h.weight.copy()
    for x, z in h.art["screws"]:
        m = m * (np.hypot(cv.X - x, cv.Z - z) > clear)
    xs = [p[0] for p in h.art["screws"]]
    return m * ((cv.X > min(xs) + clear) & (cv.X < max(xs) - clear))


def hosel_point(h, z):
    """Where the hosel's axis is at height z up the face (face coordinates, as built)."""
    cl, sl = math.cos(math.radians(h.info["loft"])), math.sin(math.radians(h.info["loft"]))
    lie = math.radians(h.info["lie"])
    tx, ty, tz = h.info["top"]
    za = (z - ty * sl) / cl - h.info["ground"] - h.info["drop"]  # address height (y ~ the axis's)
    xa = tx - (tz - za) / math.tan(lie)                          # the axis rises heel-ward
    return -xa


def brushed(cv, layer, rng, spread=14.0, along=10.0):
    """Machined grain heel to toe: roughness streaks, a faint shimmer in the colour."""
    g = cv.noise(rng, along * 1.6, 0.12)
    layer.r = np.clip(layer.r + g * spread * 0.3, 0, 255)
    layer.shade(np.clip(g, 0, 2) * 0.012, 0.5)


def trim(cv, layer, mask, rgb, width=0.35, rough=30, metal=255):
    d = cv.dist_in(mask)
    layer.paint(np.clip((width - d) / 0.08 + 0.5, 0, 1) * (mask > 0.5), rgb, rough, metal)


def scratches(cv, rng, n, length=(3, 18)):
    img = Image.new("L", (cv.w, cv.h), 0)
    d = ImageDraw.Draw(img)
    for _ in range(n):
        x, y = rng.uniform(0, cv.w), rng.uniform(0, cv.h)
        a, L = rng.uniform(-0.5, 0.5), rng.uniform(*length) * cv.ppm
        d.line([(x, y), (x + math.cos(a) * L, y + math.sin(a) * L)], fill=rng.randint(60, 200), width=1)
    return np.asarray(img, float) / 255.0


def hex_rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


# ---- the liveries ------------------------------------------------------------------------------------
def blade_runner_forged(h, rng):
    """Rare. 3a3f45 / eaeaea, "satin finish, raw leading edge": a satin blade, a milled pad, a white
    paint-filled wordmark, a gunmetal line along the muscle."""
    cv = h.cv
    slate, white = hex_rgb("3a3f45"), hex_rgb("eaeaea")
    L = Layer(cv, (200, 203, 207), 72, 255)
    brushed(cv, L, rng)
    pad = h.pad(1.2)
    mill = 0.5 + 0.5 * np.sin((cv.X * 0.86 + cv.Z * 0.5) * 2 * math.pi / 0.55)  # fly-cut milling
    L.paint(pad * 0.6, None, 92 + mill * 26, 255)
    L.shade(pad * mill * 0.05, -0.6)
    L.paint(cv.line([(x, z - 0.6) for x, z in zip(cv.X[0], h.crease_z[0])], 0.45) * h.back, slate, 50, 120)
    tip = max(p[0] for p in h.art["toe"])
    xm = tip - 31.0
    zc = float(np.interp(xm, cv.X[0], h.crease_z[0]))
    lo = float(np.interp(xm, cv.X[0], h.pad_lo[0])) if h.pad_lo is not None else zc - 9
    zp = (zc + lo) / 2 - 0.9
    L.paint(cv.text("BLADE RUNNER", "classy", 3.0, (xm, zp), tracking=0.55) * pad, white, 45, 0)
    L.paint(cv.text("FORGED  ·  1025 CARBON", "clean", 1.5, (xm, zp + 3.1), tracking=0.35) * pad, slate, 60, 100)
    bx = tip - 13.0
    top = float(np.interp(bx, cv.X[0], h.top_z[0]))
    lip = float(np.interp(bx, cv.X[0], h.lip_z[0]))
    mono = cv.text("BR", "classy", 4.2, (bx, (top + lip) / 2 - 1.0), tracking=-0.2)
    L.paint(mono * h.plate(), slate, 50, 120)
    L.paint(cv.line([(bx - 5.5, (top + lip) / 2 + 2.4), (bx + 5.5, (top + lip) / 2 + 2.4)], 0.3) * h.plate(), slate, 50, 120)
    return L


def mustard_muscle(h, rng):
    """Uncommon. 8a6a2a / e8d09a, "yellowed ferrules and butter-soft forging; forged stamp on the
    hosel": a mustard-gold forging, a cream-lined satin cavity, an espresso weight bar."""
    cv = h.cv
    gold, cream, esp = (164, 128, 56), hex_rgb("e8d09a"), (58, 40, 24)
    L = Layer(cv, gold, 78, 255)
    brushed(cv, L, rng, 16)
    pk = h.pocket * h.back
    L.paint(pk, (196, 166, 102), 150, 220)  # blasted floor
    L.paint(np.clip(cv.noise(rng, 0.15) * 0.3 + 0.3, 0, 1) * pk, (214, 186, 124), 170, 200)
    trim(cv, L, h.pocket, cream, 0.45, 60, 0)
    wt = h.weight
    L.paint(wt, esp, 70, 120)
    trim(cv, L, wt, (210, 176, 104), 0.3, 40, 255)
    b = between_screws(cv, h)
    a, _ = fit(cv, b, "MUSTARD", "classy", 2.6, centre=centroid(cv, b), tracking=0.45, margin=0.3)
    L.paint(a, cream, 60, 0)
    cav_c = np.array(h.art["pocket"]).mean(axis=0)
    L.paint(cv.text("M", "italic", 9.0, (cav_c[0] + 6, cav_c[1] - 1)) * pk, cream, 70, 0)
    L.paint(cv.text("FORGED  ·  SOFT CARBON", "clean", 1.6, (cav_c[0] + 6, cav_c[1] + 5.0), tracking=0.3) * pk,
            (120, 92, 40), 120, 120)
    # "FORGED" stamped on the hosel's back, running up it
    L.paint(cv.text("FORGED", "classy", 2.0, (hosel_point(h, 44.0), 44.0), turn=-57.0, tracking=0.5) * h.back,
            (96, 72, 30), 110, 140)
    return L


def combo_proto(h, rng):
    """Legendary. 1e2430 / ff8c3a, "hand-stamped PROTO in each cavity": a navy PVD prototype, a raw
    blasted cavity with an uneven hand stamp, an orange-anodised weight bar."""
    cv = h.cv
    navy, orange = (32, 38, 52), hex_rgb("ff8c3a")
    L = Layer(cv, navy, 64, 210)
    brushed(cv, L, rng, 12)
    pk = h.pocket * h.back
    L.paint(pk, (150, 152, 156), 150, 235)  # raw blasted steel
    L.paint(np.clip(cv.noise(rng, 0.12) * 0.35 + 0.3, 0, 1) * pk, (176, 178, 182), 170, 220)
    trim(cv, L, h.pocket, orange, 0.5, 40, 0)
    cav = np.array(h.art["pocket"])
    cx, cz = cav[:, 0].mean() + 4, cav[:, 1].mean() + 0.5
    for k, ch in enumerate("PROTO"):  # hand-struck letters: each its own tilt, depth and offset
        g = cv.text(ch, "stencil", 4.2 + rng.uniform(-0.3, 0.3), (cx + 10 - k * 5.0 + rng.uniform(-0.3, 0.3),
                                                                cz + rng.uniform(-0.5, 0.5)), turn=rng.uniform(-7, 7))
        L.paint(g * pk * rng.uniform(0.75, 1.0), (44, 44, 48), 190, 120)
    L.paint(cv.text("CP-07", "serial", 1.6, (cx - 13, cz + 5.2)) * pk, (70, 70, 74), 160, 150)
    wt = h.weight
    L.paint(wt, orange, 40, 160)
    trim(cv, L, wt, (255, 196, 150), 0.25, 30, 255)
    b = between_screws(cv, h)
    a, _ = fit(cv, b, "COMBO", "tech", 3.2, centre=centroid(cv, b), tracking=0.9, margin=0.3)
    L.paint(a, (24, 28, 38), 50, 60)
    L.paint(cv.text("PROTOTYPE  ·  NOT FOR RETAIL", "clean", 1.1, (cx + 4.0, cz + 4.6), tracking=0.3) * pk,
            (96, 98, 104), 150, 180)
    return L


def tour_forged_cb(h, rng):
    """Epic. 2a2d30 / e8c25a, "tour-van engraving under the grime": black PVD, a gloss black panel with
    gold, a hand engraving on the toe, grime in the corners."""
    cv = h.cv
    black, gold = (40, 42, 46), hex_rgb("e8c25a")
    L = Layer(cv, black, 80, 190)
    brushed(cv, L, rng, 12)
    pk = h.pocket * h.back
    L.paint(pk, (30, 31, 34), 120, 160)
    trim(cv, L, h.pocket, gold, 0.4, 35, 255)
    pn = h.panel
    L.paint(pn, (18, 18, 20), 26, 230)  # black chrome
    trim(cv, L, pn, gold, 0.3, 30, 255)
    a, box = fit(cv, pn, "CB", "heavy", 4.2, margin=0.5)
    L.paint(a, gold, 30, 255)
    a, box2 = fit(cv, without(cv, pn, box, 1.0), "TOUR FORGED", "classy", 2.0, tracking=0.4, margin=0.4)
    L.paint(a, gold, 30, 255)
    above = pk * (1 - ndimage.binary_dilation(pn > 0.5, iterations=10))
    a, _ = fit(cv, above, "Tour Van", "script", 2.8, turn=4)
    L.paint(a, (150, 130, 80), 140, 160)
    grime = np.clip(cv.noise(rng, 1.2) * 0.5 + 0.2, 0, 1) * np.clip(1.6 - cv.dist_in(h.pocket) / 2.0, 0, 1) * pk
    L.paint(grime * 0.7, (52, 44, 32), 200, 40)
    return L


def loaner_irons(h, rng):
    """Common. 7d8388 / b3b9bd, a mixed rental set: worn satin chrome, a chipped black cavity, a faded
    red panel stamped RENTAL, bag chatter."""
    cv = h.cv
    L = Layer(cv, (176, 180, 184), 112, 230)
    brushed(cv, L, rng, 18)
    pk = h.pocket * h.back
    L.paint(pk, (36, 38, 40), 150, 30)
    chips = (cv.noise(rng, 0.18) > 2.1).astype(float) * pk
    L.paint(chips, (150, 154, 158), 120, 220)
    pn = h.panel
    L.paint(pn, (150, 54, 46), 140, 20)
    L.paint((cv.noise(rng, 0.25) > 1.7).astype(float) * pn * 0.8, (176, 180, 184), 120, 220)  # worn through
    a, box = fit(cv, pn, "RENTAL", "stencil", 3.2, tracking=0.4)
    L.paint(a, (236, 230, 216), 150, 0)
    a, _ = fit(cv, without(cv, pn, box), "No. 07", "serial", 1.4)
    L.paint(a, (236, 230, 216), 150, 0)
    above = pk * (1 - ndimage.binary_dilation(pn > 0.5, iterations=8))
    a, _ = fit(cv, above, "CLUBHOUSE PROPERTY", "clean", 1.5, tracking=0.3)
    L.paint(a, (150, 152, 156), 140, 160)
    L.paint(scratches(cv, rng, 380) * 0.6 * h.back, (214, 216, 219), 160, 200)
    return L


def thrift_cavity_backs(h, rng):
    """Common. 6f7a82 / d2d8dc, "chunky, forgiving": satin steel, a faded blue cavity, a silver panel,
    a scraped-off price sticker."""
    cv = h.cv
    blue = (96, 140, 200)
    L = Layer(cv, (168, 174, 180), 96, 235)
    brushed(cv, L, rng, 15)
    pk = h.pocket * h.back
    L.paint(pk, blue, 82, 0)
    L.paint(np.clip(cv.noise(rng, 3.0) * 0.25 + 0.25, 0, 1) * pk, (152, 182, 220), 96, 0)  # sun-faded
    trim(cv, L, h.pocket, hex_rgb("d2d8dc"), 0.35, 60, 0)
    pn = h.panel
    L.paint(pn, (196, 202, 208), 60, 255)
    trim(cv, L, pn, blue, 0.3, 60, 0)
    a, box = fit(cv, pn, "THRIFT", "italic", 3.6, skew=-0.15)
    L.paint(a, blue, 60, 0)
    a, _ = fit(cv, without(cv, pn, box, 0.6), "CAVITY BACK  ·  4-9", "clean", 1.3, tracking=0.3)
    L.paint(a, (90, 100, 112), 70, 100)
    toe_x = max(p[0] for p in h.art["toe"]) - 13.0
    tz = float(np.interp(toe_x, cv.X[0], h.top_z[0])) - 9.0
    sticker = cv.poly([(toe_x - 5, tz - 3), (toe_x + 5, tz - 3.4), (toe_x + 5.3, tz + 3), (toe_x - 4.8, tz + 3.3)])
    L.paint(sticker * (0.5 + 0.5 * np.clip(cv.noise(rng, 0.35) * 0.5 + 0.5, 0, 1)) * h.back * (1 - pk),
            (214, 206, 182), 210, 0)
    return L


def game_improver_xl(h, rng):
    """Uncommon. 50606e / e6ecf0, "wide soles, strong lofts": a bright chrome frame, a blue-grey dish,
    a big panel with XL."""
    cv = h.cv
    slate, ice = hex_rgb("50606e"), hex_rgb("e6ecf0")
    L = Layer(cv, (214, 217, 222), 68, 255)
    brushed(cv, L, rng, 8)
    pk = h.pocket * h.back
    L.paint(pk, slate, 90, 120)
    trim(cv, L, h.pocket, ice, 0.4, 40, 0)
    pn = h.panel
    grad = np.clip((cv.X - pk.max() * 0 - 30) / 50.0, 0, 1)[..., None]
    L.paint(pn, np.array((70, 88, 104)) * (1 - grad) + np.array((120, 140, 158)) * grad, 50, 180)
    trim(cv, L, pn, ice, 0.3, 30, 255)
    a, box = fit(cv, pn, "XL", "heavy", 4.6, skew=-0.2)
    L.paint(a, ice, 30, 0)
    dish = pk * (1 - ndimage.binary_dilation(pn > 0.5, iterations=10))
    a, box2 = fit(cv, dish, "GAME IMPROVER", "tech", 2.6, tracking=0.6)
    L.paint(a, ice, 40, 0)
    a, _ = fit(cv, without(cv, dish, box2, 0.4), "WIDE SOLE  ·  STRONG LOFT", "clean", 1.3, tracking=0.25)
    L.paint(a, (190, 202, 214), 50, 60)
    return L


def utility_2u(h, rng):
    """Rare. 2b2e31 / d8d8d8, "driving iron for windy days": plain metal - brushed satin steel all over, no
    livery - and only the maker's brand on the upper plate (VELMOR, dark paint-fill, its red V and rule)."""
    cv = h.cv
    ink, red = (34, 36, 40), (196, 40, 44)
    L = Layer(cv, (200, 203, 207), 72, 255)  # satin steel
    brushed(cv, L, rng, 10)
    plate = h.plate()
    a, box = fit(cv, plate, "VELMOR", "clean", 2.4, tracking=0.9)
    L.paint(a, ink, 60, 40)
    if box is not None:
        x0, x1, z0, z1 = box
        vx, vz = x1 + 3.2, (z0 + z1) / 2  # the red V beside it (head up: before the name)
        L.paint(cv.poly([(vx - 1.6, vz + 1.4), (vx + 1.6, vz + 1.4), (vx, vz - 1.6)]) * plate, red, 40, 60)
        L.paint(cv.line([(x0, z1 + 0.9), (x1, z1 + 0.9)], 0.25) * plate, red, 40, 60)
    return L


LIVERY = {"loaner_irons": loaner_irons, "utility_2u": utility_2u, "thrift_cavity_backs": thrift_cavity_backs, "game_improver_xl": game_improver_xl,
          "mustard_muscle": mustard_muscle, "blade_runner_forged": blade_runner_forged, "tour_forged_cb": tour_forged_cb,
          "combo_proto": combo_proto}


def main():
    os.makedirs(OUT, exist_ok=True)
    open(os.path.join(BASE, ".gdignore"), "a").close()
    heads = {}
    rng = random.Random(4)
    for club, head in SETS.items():
        if head not in heads:
            heads[head] = Head(head)
        LIVERY[club](heads[head], rng).save(club)
        print("wrote", club)


if __name__ == "__main__":
    main()
