"""Textures for the driver liveries on the Driver460 head (tools/freecad/export_driver_460_head.py).

    python tools/make_driver_textures.py

Writes assets/Driver_460_Head/textures/ (Godot ignores that folder; the exporter embeds the images in
each head's GLB) and textures.json. Crown and sole art each cover the whole head seen from above, in
right-handed model mm (toe -X, face -Y), mapped u = (x - x0) / (x1 - x0), v = (y - y0) / (y1 - y0)
over BOX. masks/{crown,sole}_mask.png (tools/freecad/driver_460_masks.py) say where each one shows, so
trim lines, panels and fades follow the head's real outline.

Designed like current premium drivers (TaylorMade Qi / Stealth, Callaway Paradym / Elyte, Cobra
Darkspeed / LTDx, Ping G4xx, Titleist GT): a clean dark crown with one accent, and a sole of angular
faceted panels (bevel highlights, carbon-weave inserts, chrome trims along the facet edges), one bold
accent colour, a coloured ring round the weight screw, big model lettering and small tech callouts, a
thin accent line round the skirt. The cheaper clubs are older and humbler (silver and flake paint,
bare titanium). Each club follows its catalog identity (finish and accent colours, rarity, its tell):

  loaner_driver      clubhouse rental (common): worn silver crown, brushed titanium sole with grey facets,
                     a RENTAL No. 07 property label, chips and scuffs
  thrift_titan_460   late-2000s oversize titanium (common): slate-blue flake crown, polished titanium sole
                     with a paint-filled TITAN wordmark and a 460 badge, sticker residue (its tell)
  slice_slayer       game improvement (common): navy crown with a white aim arrow, a black sole of navy and
                     ice-blue facets driving at the heel weight (draw), OFFSET callouts
  rocket_boomer_lt   low-spin cannon (rare): candy-red crown with a black-carbon V, a black sole of red
                     facets, chrome trims and flame licks, a red weight ring
  hollow_point_tour  stealth tour (epic): matte black crown with a gloss black-carbon rear panel and gold
                     lines, gunmetal faceted sole, carbon centre, gold weight track and an engraved serial
  meteor_xr_proto    prototype (legendary): forged-carbon crown fading to orange at the back, forged-carbon
                     sole with an orange meteor trail and a chrome-edged XR, PROTOTYPE stamps, the loft
                     hand-written on masking tape (its tell)
  grenade_driver     admin-sandbox novelty (mythic): olive-drab grenade segments, a yellow pin band, hazard
                     stripes and stencils

The loft mark (and the sole lettering) read from the leading edge back with the glyph tops toward the
heel: upright with the club held toe down. Each *_rough.png is a glTF metallic-roughness map
(G = roughness, B = metallic). Colours are sRGB.
"""
import json
import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.environ.get("DRIVER_TEX_DIR", os.path.join(ROOT, "assets", "Driver_460_Head", "textures"))
FONTS = "C:/Windows/Fonts/"
F = {"tech": "AGENCYB.TTF", "sport": "FRADMIT.TTF", "heavy": "ariblk.ttf", "stencil": "STENCIL.TTF",
     "serial": "OCRAEXT.TTF", "classy": "COPRGTB.TTF", "hand": "Inkfree.ttf", "clean": "bahnschrift.ttf",
     "italic": "TCBI____.TTF", "impact": "impact.ttf"}

BOX = (-76.0, 60.0, -8.0, 116.0)  # x0, x1, y0, y1 (mm): the whole head from above
PPM = 10.0                        # px per mm
LOFT = "10.5°"
MARK = {"centre": (-50.0, 30.0), "length": 17.0, "width": 8.0, "turn": 90.0}
SCREW = (12.0, 28.0)              # the sole screw (build_hybrid_driver.py PORT_AT): its accent ring
SOLE_TURN = 90.0                  # sole lettering reads upright with the toe down, like the loft


# ---- canvas helpers ------------------------------------------------------------------------------
def size():
    x0, x1, y0, y1 = BOX
    return round((x1 - x0) * PPM), round((y1 - y0) * PPM)


def px(x, y):
    x0, _, y0, _ = BOX
    return (x - x0) * PPM, (y - y0) * PPM


def grid():
    """Model mm (x, y) of every pixel."""
    w, h = size()
    x0, _, y0, _ = BOX
    return np.meshgrid(x0 + (np.arange(w) + 0.5) / PPM, y0 + (np.arange(h) + 0.5) / PPM)


class Layer:
    """Colour (sRGB 0..255) + roughness + metallic (0..255) canvases, built up by blending."""

    def __init__(self, rgb, rough, metal):
        w, h = size()
        self.c = np.ones((h, w, 3)) * np.array(rgb, float)
        self.r = np.full((h, w), float(rough))
        self.m = np.full((h, w), float(metal))

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
        """Lighten (k > 0) or darken (k < 0) the colour where alpha says."""
        a = np.clip(alpha, 0, 1)[..., None]
        target = 255.0 if k > 0 else 0.0
        self.c = self.c + (target - self.c) * a * abs(k)

    def images(self):
        col = Image.fromarray(np.clip(self.c, 0, 255).astype(np.uint8), "RGB")
        mr = np.stack([np.full(self.r.shape, 255.0), np.clip(self.r, 0, 255), np.clip(self.m, 0, 255)], -1)
        return col, Image.fromarray(mr.astype(np.uint8), "RGB")


def shape_alpha(draw_fn, ss=3):
    """Antialiased 0..1 mask from PIL drawing at ss x; draw_fn(d, sc, ss), sc maps mm -> px."""
    w, h = size()
    img = Image.new("L", (w * ss, h * ss), 0)

    def sc(x, y):
        a, b = px(x, y)
        return a * ss, b * ss
    draw_fn(ImageDraw.Draw(img), sc, ss)
    return np.asarray(img.resize((w, h), Image.LANCZOS), float) / 255.0


def poly(points):
    return shape_alpha(lambda d, sc, ss: d.polygon([sc(*p) for p in points], fill=255))


def outline(points, width_mm):
    return shape_alpha(lambda d, sc, ss: d.line([sc(*p) for p in points] + [sc(*points[0])], fill=255,
                                                width=max(1, int(width_mm * PPM * ss)), joint="curve"))


def polyline(points, width_mm):
    return shape_alpha(lambda d, sc, ss: d.line([sc(*p) for p in points], fill=255,
                                                width=max(1, int(width_mm * PPM * ss)), joint="curve"))


def disc(c, r):
    return shape_alpha(lambda d, sc, ss: d.ellipse([*sc(c[0] - r, c[1] - r), *sc(c[0] + r, c[1] + r)], fill=255))


def ring(c, r, width_mm):
    return np.clip(disc(c, r) - disc(c, r - width_mm), 0, 1)


def text_alpha(text, font, height_mm, centre_mm, turn=0.0, tracking=0.0, skew=0.0):
    """Antialiased text mask, cap height ~height_mm, centred, turned clockwise by `turn`."""
    ss = 3
    if font == "serial":  # the stamp font has no middle dot (it drew a box)
        text = text.replace("·", "-")
    f = ImageFont.truetype(FONTS + F[font], int(height_mm * PPM * ss * 1.35))
    widths = [f.getlength(ch) for ch in text]
    total = sum(widths) + tracking * PPM * ss * max(len(text) - 1, 0)
    box = f.getbbox(text)
    tw, th = int(total + 8 + abs(skew) * (box[3] - box[1])), int(box[3] - box[1] + 8)
    img = Image.new("L", (tw, th), 0)
    d = ImageDraw.Draw(img)
    x = 4
    for ch, wd in zip(text, widths):
        d.text((x - box[0] * (x == 4), 4 - box[1]), ch, font=f, fill=255)
        x += wd + tracking * PPM * ss
    if skew:
        img = img.transform(img.size, Image.AFFINE, (1, skew, -skew * th / 2, 0, 1, 0), Image.BICUBIC)
    img = img.resize((max(1, tw // ss), max(1, th // ss)), Image.LANCZOS)
    if turn:
        img = img.rotate(-turn, resample=Image.BICUBIC, expand=True)
    w, h = size()
    out = Image.new("L", (w, h), 0)
    cx, cy = px(*centre_mm)
    out.paste(img, (int(round(cx - img.width / 2)), int(round(cy - img.height / 2))))
    return np.asarray(out, float) / 255.0


def band(dist, at_mm, width_mm, soft=0.08):
    return np.clip((width_mm / 2 - np.abs(dist - at_mm)) / soft + 0.5, 0, 1)


def inside(dist, at_mm, soft=0.08):
    return np.clip((dist - at_mm) / soft + 0.5, 0, 1)


def noise(rng, sigma_mm):
    w, h = size()
    g = np.random.default_rng(rng.randint(0, 10 ** 9)).standard_normal((h, w))
    g = ndimage.gaussian_filter(g, sigma_mm * PPM)
    return g / (g.std() + 1e-9)


def flakes(rng, density):
    w, h = size()
    g = np.random.default_rng(rng.randint(0, 10 ** 9)).random((h, w))
    return ndimage.gaussian_filter((g > 1 - density).astype(float), 0.5)


def carbon(cell_mm=3.0, angle=45.0):
    """2x2 twill weave shading, -1..1 (each tow lit along its length)."""
    X, Y = grid()
    a = math.radians(angle)
    u = (X * math.cos(a) + Y * math.sin(a)) / cell_mm
    v = (-X * math.sin(a) + Y * math.cos(a)) / cell_mm
    k = (np.floor(u) + np.floor(v)) % 4
    weft = k < 2
    along = np.where(weft, u % 1.0, v % 1.0)
    across = np.where(weft, v % 1.0, u % 1.0)
    s = 0.55 * np.sin(across * math.pi) + 0.45 * np.cos((along - 0.5) * math.pi) - 0.5
    return np.where(weft, s, -0.6 * s)


def forged(rng, chunk_mm=6.0):
    """Forged carbon: chopped-fibre chunks of their own sheen, -1..1."""
    w, h = size()
    n = int((w / PPM) * (h / PPM) / (chunk_mm ** 2) * 2.5)
    img = Image.new("L", (w, h), 128)
    d = ImageDraw.Draw(img)
    for _ in range(n):
        cx, cy = rng.uniform(0, w), rng.uniform(0, h)
        r = rng.uniform(0.4, 1.0) * chunk_mm * PPM
        a0 = rng.uniform(0, math.pi)
        d.polygon([(cx + math.cos(a0 + k * 1.26 + rng.uniform(-0.3, 0.3)) * r * rng.uniform(0.3, 1.0),
                    cy + math.sin(a0 + k * 1.26 + rng.uniform(-0.3, 0.3)) * r * rng.uniform(0.3, 1.0))
                   for k in range(5)], fill=rng.randint(30, 235))
    return ndimage.gaussian_filter(np.asarray(img, float), 0.8) / 127.5 - 1.0


def dist_in(mask):
    return ndimage.distance_transform_edt(mask) / PPM


def load_masks():
    return {n: np.asarray(Image.open(os.path.join(OUT, "masks", n + "_mask.png")).convert("L"), float) > 127
            for n in ("crown", "sole")}


def facet(layer, points, rgb, rough, metal, edge_rgb=None, edge_w=0.35, bevel=0.10, clip=None):
    """An angular sole panel: filled, bevel-lit (lighter toward its upper-left edges, darker
    lower-right), with an optional bright trim along its edges."""
    a = poly(points)
    if clip is not None:
        a = a * clip
    layer.paint(a, rgb, rough, metal)
    if bevel:
        inner = ndimage.binary_erosion(a > 0.5, iterations=int(0.8 * PPM))
        rim = np.clip(a - inner, 0, 1)
        gy, gx = np.gradient(ndimage.gaussian_filter(a, 3))
        light = np.clip((gx + gy) * 25, -1, 1)  # edges facing up-left catch the light
        layer.shade(rim * np.clip(light, 0, 1), bevel)
        layer.shade(rim * np.clip(-light, 0, 1), -bevel)
    if edge_rgb is not None:
        e = outline(points, edge_w)
        if clip is not None:
            e = e * clip
        layer.paint(e, edge_rgb, 25, 255)
    return a


AIM_X = -10.5  # the face's centre line (the face insert's centre: fit_insert.py, hybrid_h2/insert.json)
AIM = [(AIM_X - 4.0, 21.0), (AIM_X + 4.0, 21.0), (AIM_X, 14.0)]  # the crown's alignment arrow (set from the crown mask)


def aim(layer, colour, rough=30, metal=0):
    """The alignment arrow on the crown: the same solid triangle on every driver, its tip at the face
    pointing at the target, where the ball goes."""
    layer.paint(poly(AIM), colour, rough, metal)


def loft_mark(layer, style, ink, rng, rough=60, metal=0, text=None):
    """The loft by the toe on the sole, upright with the club held toe down."""
    c = MARK["centre"]
    loft = text or LOFT
    if style == "tape":  # masking tape, hand-written in marker
        L, W = MARK["length"] * 1.25, MARK["width"] * 1.45
        jig = [rng.uniform(-0.6, 0.6) for _ in range(18)]
        x0, x1, y0, y1 = c[0] - W / 2, c[0] + W / 2, c[1] - L / 2, c[1] + L / 2
        pts = [(x0 + (x1 - x0) * k / 8, y0 + jig[k]) for k in range(9)] + \
              [(x1 - (x1 - x0) * k / 8, y1 + jig[9 + k]) for k in range(9)]
        layer.paint(poly(pts) * 0.96, (214, 198, 156), 205, 0)
        layer.paint(text_alpha(loft.rstrip("°"), "hand", MARK["width"] * 0.95, c, MARK["turn"]), (24, 20, 34), 200, 0)
    else:
        layer.paint(text_alpha(loft, "clean", MARK["width"] * 0.9, c, MARK["turn"]), ink, rough, metal)


def skirt_line(layer, dist, colour, rough=40, metal=0, width=1.2, at=0.9, rear_from=38.0):
    X, Y = grid()
    layer.paint(band(dist, at, width) * np.clip((Y - rear_from) / 6.0, 0, 1), colour, rough, metal)


def screw_ring(layer, colour, rough=30, metal=0, r=7.2, width=1.6):
    layer.paint(ring(SCREW, r, width), colour, rough, metal)


def worn(layer, rng, dist, amount, colour, rough, metal):
    """Chipped paint along the edges (dist small) and scattered scuffs."""
    chips = (noise(rng, 0.9) > 2.2 - amount) * (dist < 5.0)
    layer.paint(chips.astype(float), colour, rough, metal)


def scratches(rng, n, length=(4, 26)):
    w, h = size()
    img = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(img)
    for _ in range(n):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        a, L = rng.uniform(0, math.pi), rng.uniform(*length) * PPM
        d.line([(x, y), (x + math.cos(a) * L, y + math.sin(a) * L)], fill=rng.randint(60, 200), width=1)
    return np.asarray(img, float) / 255.0


# sole layout (mm, from above: toe -X, face -Y, heel +X, back +Y). Seen toe down, as the sole is read:
# Y runs left (leading edge) to right (trailing edge), X bottom (toe) to top (heel). The sole spans
# X -67..52, Y 1..112, widest across X -40..20; WORD is the centre of the main wordmark.
WORD = (-14.0, 60.0)


def halfplane(p, q, soft=0.08):
    """1 on the left of the directed line p -> q (seen from above), smooth edge."""
    X, Y = grid()
    dx, dy = q[0] - p[0], q[1] - p[1]
    L = math.hypot(dx, dy)
    s = ((X - p[0]) * dy - (Y - p[1]) * dx) / L  # signed distance (mm)
    return np.clip(-s / soft + 0.5, 0, 1)


def panel_alpha(ds, inset, cuts=()):
    """A sole panel: the sole's own outline pulled in by `inset` mm, cut by half-planes."""
    a = inside(ds, inset)
    for p, q in cuts:
        a = a * halfplane(p, q)
    return a


def bevel(layer, alpha, k=0.14, width=0.9):
    """Light the panel's edge like a machined bevel: lit on its heel/leading side, shaded opposite."""
    d = ndimage.distance_transform_edt(alpha > 0.5) / PPM
    rim = np.clip((width - d) / width, 0, 1) * (alpha > 0.5)
    gy, gx = np.gradient(ndimage.gaussian_filter(alpha, 4))
    light = np.clip((gx - gy) * 30, -1, 1)
    layer.shade(rim * np.clip(light, 0, 1), k)
    layer.shade(rim * np.clip(-light, 0, 1), -k)


def trim(layer, alpha, rgb, width=0.35, rough=22, metal=255):
    """A bright line along a panel's edge."""
    d = ndimage.distance_transform_edt(alpha > 0.5) / PPM
    layer.paint(np.clip((width - d) / 0.08 + 0.5, 0, 1) * (alpha > 0.5), rgb, rough, metal)


def carbon_rgb(weave, base, spread):
    return np.clip(base + weave * spread, 0, 255)[..., None] * np.ones(3)


def liveries(masks, rng):
    global AIM
    X, Y = grid()
    dc, ds = dist_in(masks["crown"]), dist_in(masks["sole"])
    # the arrow starts just behind the crown paint's real front edge on the centre line
    col = masks["crown"][:, int(px(AIM_X, 0.0)[0])]
    front = BOX[2] + (int(np.argmax(col)) + 0.5) / PPM
    AIM = [(AIM_X - 4.0, front + 9.5), (AIM_X + 4.0, front + 9.5), (AIM_X, front + 2.5)]  # tip toward the target
    weave = carbon(2.6)
    out = {}

    # --- Daddy's Driver (common; 6e7378 / 9aa1a6): clubhouse rental ------------------------------------
    cr = Layer((150, 155, 160), 70, 200)  # silver
    cr.paint(flakes(rng, 0.03) * 0.6, (200, 205, 210), 40, 255)
    cr.paint(np.clip((X + 30) / -30.0, 0, 1) * 0.9 * (Y > 10), (90, 95, 100), 70, 160)  # dark toe sweep
    cr.paint(scratches(rng, 360) * 0.55, (205, 208, 212), 150, 80)
    worn(cr, rng, dc, 0.6, (70, 72, 74), 120, 240)
    aim(cr, (40, 42, 46), 60, 0)
    so = Layer((168, 172, 176), 95, 235)  # brushed titanium frame
    pa = panel_alpha(ds, 7.0, [((-80, 40), (80, 40)), ((40, -10), (40, 130))])
    so.paint(pa, (92, 96, 102), 120, 60)
    bevel(so, pa)
    trim(so, pa, (210, 213, 217))
    so.paint(poly([(-24, 40), (-4, 40), (-4, 80), (-24, 80)]), (238, 235, 224), 170, 0)  # property label
    so.paint(poly([(-24, 40), (-20, 40), (-20, 80), (-24, 80)]), (176, 34, 40), 170, 0)
    so.paint(text_alpha("RENTAL", "tech", 8.0, (-12, 60), SOLE_TURN), (28, 30, 34), 170, 0)
    so.paint(text_alpha("No. 07", "serial", 2.8, (-7.0, 60), SOLE_TURN), (176, 34, 40), 170, 0)
    so.paint(text_alpha("CLUBHOUSE PROPERTY", "clean", 2.2, (-32, 60), SOLE_TURN, tracking=0.2),
             (215, 218, 222), 120, 60)
    so.paint(scratches(rng, 420, (3, 18)) * 0.6, (214, 216, 219), 150, 200)
    worn(so, rng, ds, 0.2, (70, 72, 74), 140, 220)
    screw_ring(so, (210, 213, 217), 60, 200)
    skirt_line(so, ds, (210, 213, 217), 60, 200)
    loft_mark(so, "paint", (240, 242, 245), rng)
    out["loaner_driver"] = (cr, so)

    # --- Thrift Titan 460 (common; 3f4a52 / d0d5d8): late-2000s oversize titanium -----------------------
    slate = (44, 58, 76)
    cr = Layer((44, 58, 76), 40, 170)
    cr.paint(np.clip(noise(rng, 18) * 0.1 + 0.12, 0, 1), (70, 92, 120), 40, 170)
    cr.paint(flakes(rng, 0.06) * 0.85, (140, 165, 195), 20, 255)
    cr.paint(band(dc, 3.0, 0.6) * (Y > 18), (208, 213, 216), 30, 230)
    aim(cr, (208, 213, 216), 30, 230)
    so = Layer((206, 210, 216), 100, 235)  # satin-polished titanium (a mirror read black in-game)
    so.paint(np.clip(noise(rng, 6.0) * 0.12 + 0.12, 0, 1), (172, 178, 186), 110, 235)
    so.paint(band(ds, 5.0, 0.7), slate, 45, 40)  # a paint-filled line following the outline
    so.paint(text_alpha("TITAN", "italic", 13.0, (-12, 56), SOLE_TURN, skew=-0.2), slate, 45, 40)
    so.paint(ring((-12, 88), 6.0, 1.0), slate, 45, 40)
    so.paint(text_alpha("460", "heavy", 4.5, (-12, 88), SOLE_TURN), slate, 45, 40)
    so.paint(text_alpha("FORGED TITANIUM  ·  OVERSIZE  ·  460cc", "clean", 2.1, (-30, 60), SOLE_TURN), (78, 88, 102), 55, 140)
    residue = poly([(4, 46), (20, 44), (22, 58), (6, 60)])  # a price sticker, scraped off
    so.paint(residue * (0.55 + 0.45 * np.clip(noise(rng, 0.35) * 0.5 + 0.5, 0, 1)), (210, 202, 178), 210, 0)
    screw_ring(so, slate, 45, 40)
    skirt_line(so, ds, slate, 40, 40)
    loft_mark(so, "paint", slate, rng, 45, 40)
    out["thrift_titan_460"] = (cr, so)

    # --- Slice Slayer Offset (common; 2f3a5a / c9d3e8): game improvement, draw bias ---------------------
    ice, mid = (201, 211, 232), (104, 146, 214)
    cr = Layer((24, 36, 70), 26, 60)
    cr.paint(np.clip(noise(rng, 14) * 0.1 + 0.1, 0, 1), (46, 66, 116), 26, 60)
    cr.paint(band(dc, 2.4, 0.55) * (Y > 14), (236, 241, 248), 25, 0)
    aim(cr, (236, 241, 248), 25, 0)
    so = Layer((182, 188, 198), 30, 235)  # satin silver frame
    pa = panel_alpha(ds, 5.5)
    so.paint(pa, carbon_rgb(weave, 22, 10), 40 + weave * 15, 60)  # black carbon
    navy = pa * halfplane((4, 130), (4, -10))  # the heel half (top, seen toe down) in navy
    so.paint(navy, (30, 44, 88), 32, 40)
    bevel(so, pa)
    trim(so, pa, (228, 232, 240))
    for k, col in enumerate((ice, mid, ice)):  # chevrons pointing at the heel weight: draw
        xb = 8 + 9 * k
        so.paint(poly([(xb, 70), (xb + 4, 70), (xb + 11, 80), (xb + 4, 90), (xb, 90), (xb + 7, 80)]) * navy, col, 32, 0)
    so.paint(text_alpha("SLICE SLAYER", "sport", 6.5, (-14, 56), SOLE_TURN), (240, 244, 250), 32, 0)
    so.paint(text_alpha("OFFSET  ·  DRAW BIAS", "tech", 3.2, (-24, 56), SOLE_TURN, tracking=0.25), mid, 32, 0)
    so.paint(disc((26, 52), 5.5), (182, 188, 198), 28, 240)
    so.paint(text_alpha("D", "heavy", 6.0, (26, 52), SOLE_TURN), (30, 44, 88), 28, 0)
    screw_ring(so, mid, 30, 0)
    skirt_line(so, ds, mid, 30, 0)
    loft_mark(so, "paint", (240, 244, 250), rng)
    out["slice_slayer"] = (cr, so)

    # --- Rocket Boomer LT (rare; b3352a / f2e4c0): low-spin cannon, hot-rod red -----------------------
    red, cream = (196, 30, 24), (242, 228, 192)
    cr = Layer((150, 20, 18), 20, 140)
    cr.paint(np.clip(noise(rng, 16) * 0.12 + 0.2, 0, 1), (196, 36, 28), 20, 140)
    cr.paint(flakes(rng, 0.06) * 0.85, (255, 120, 90), 12, 255)
    cr.paint(poly([(-62, 118), (0, 40), (62, 118)]), carbon_rgb(weave, 16, 10), 30 + weave * 20, 60)
    cr.paint(outline([(-62, 118), (0, 40), (62, 118)], 0.5), cream, 25, 0)
    cr.paint(band(dc, 1.8, 0.45) * (Y < 24), cream, 25, 0)
    aim(cr, cream, 25, 0)
    so = Layer((226, 228, 232), 12, 255)  # chrome frame
    pa = panel_alpha(ds, 5.0)
    so.paint(pa, carbon_rgb(weave, 14, 9), 30 + weave * 15, 60)
    for a, b in ((14.0, 26.0), (34.0, 40.0)):  # two red stripes raked across the sole, toe-front to heel-back
        st = pa * halfplane((-80, a - 30), (60, a + 40)) * (1 - halfplane((-80, b - 30), (60, b + 40)))
        so.paint(st, red, 22, 120)
        bevel(so, st, 0.12, 0.6)
    flame = np.zeros_like(X)
    for k in range(6):  # flame licks off the trailing edge
        xc, L = -50 + 13 * k, 14 + 6 * (k % 3)
        flame = np.maximum(flame, poly([(xc - 5, 112), (xc + 5, 112), (xc + 2, 112 - L * 0.55),
                                        (xc + 6, 112 - L), (xc - 1, 112 - L * 0.62), (xc - 4, 112 - L * 0.8)]))
    heat = np.clip((112 - Y) / 22.0, 0, 1)[..., None]
    so.paint(flame * pa, np.array((205, 34, 26)) * (1 - heat) + np.array((255, 200, 90)) * heat, 22, 60)
    trim(so, pa, (240, 242, 246))
    so.paint(text_alpha("ROCKET BOOMER", "impact", 6.5, (-14, 60), SOLE_TURN, skew=-0.15), cream, 25, 0)
    so.paint(text_alpha("LT", "heavy", 9.0, (-1, 60), SOLE_TURN), red, 22, 120)
    so.paint(text_alpha("LOW SPIN  ·  HOT FACE", "tech", 2.8, (-24, 60), SOLE_TURN, tracking=0.3), (215, 205, 190), 30, 0)
    screw_ring(so, red, 22, 120)
    skirt_line(so, ds, red, 20, 120)
    loft_mark(so, "paint", cream, rng)
    out["rocket_boomer_lt"] = (cr, so)

    # --- Hollow Point Tour (epic; 1d1f22 / e8c25a): stealth tour ------------------------------------
    gold = (232, 194, 90)
    cr = Layer((14, 15, 17), 125, 0)  # matte black (rougher read grey in-game)
    cp = inside(dc, 8.0) * np.clip((Y - 44) / 0.2, 0, 1)
    cr.paint(cp, carbon_rgb(weave, 28, 16), 30 + weave * 22, 60)  # gloss black carbon rear panel
    cr.paint(band(Y, 44.0, 0.45) * inside(dc, 8.0), gold, 35, 255)
    cr.paint(band(dc, 1.5, 0.4) * (Y < 26), gold, 35, 255)
    aim(cr, gold, 35, 255)
    so = Layer((56, 58, 62), 70, 230)  # gunmetal PVD frame
    so.paint(np.clip(noise(rng, 0.2) * 0.2 + 0.2, 0, 1), (66, 68, 72), 60, 230)
    pa = panel_alpha(ds, 7.0, [((-80, 30), (80, 30)), ((80, 84), (-80, 84))])
    so.paint(pa, carbon_rgb(weave, 22, 12), 32 + weave * 20, 60)
    bevel(so, pa)
    trim(so, pa, gold, 0.3, 30, 255)
    track = panel_alpha(ds, 4.0, [((-80, 88), (80, 88)), ((80, 95), (-80, 95))])
    so.paint(track, (12, 12, 14), 80, 100)
    trim(so, track, (110, 112, 116), 0.25)
    for wx in (-30.0, 10.0):  # two gold weights in the track
        so.paint(shape_alpha(lambda d, sc, ss, wx=wx: d.rounded_rectangle([*sc(wx - 4.5, 88.2), *sc(wx + 4.5, 94.8)],
                                                                         radius=1.4 * PPM * ss, fill=255)), gold, 28, 255)
    so.paint(text_alpha("HOLLOW POINT", "classy", 3.9, (-14, 56), SOLE_TURN, tracking=0.35), gold, 35, 255)
    so.paint(text_alpha("TOUR ISSUE  ·  HP-0417", "serial", 2.3, (-6, 57), SOLE_TURN), (150, 150, 152), 90, 200)
    so.paint(text_alpha("FORGED FACE  ·  TUNGSTEN", "tech", 2.2, (-36, 57), SOLE_TURN, tracking=0.3), (120, 122, 126), 80, 200)
    screw_ring(so, gold, 30, 255, width=1.0)
    skirt_line(so, ds, gold, 35, 255, width=0.6)
    loft_mark(so, "paint", gold, rng, 35, 255)
    out["hollow_point_tour"] = (cr, so)

    # --- Meteor XR Prototype (legendary; 2a1f3d / ff8c3a): forged carbon prototype ------------------
    orange, pink = (255, 140, 58), (255, 70, 150)
    fc = forged(rng, 5.0)
    marble = np.array((34, 26, 50))[None, None] + fc[..., None] * np.array((26, 22, 38))[None, None]
    cr = Layer((34, 26, 50), 28, 90)
    cr.paint(np.ones_like(X), marble, 26 + fc * 12, 90 + fc * 40)
    cr.paint(np.clip((Y - 66) / 44.0, 0, 1) ** 1.5 * inside(dc, 0.5) * 0.9, np.array(orange) * np.ones((1, 1, 3)), 28, 140)
    cr.paint(band(dc, 1.8, 0.45) * (Y < 24), orange, 25, 60)
    aim(cr, orange, 25, 60)
    so = Layer((96, 92, 104), 30, 235)  # titanium frame
    pa = panel_alpha(ds, 3.5)
    so.paint(pa, marble * 0.85, 30 + fc * 10, 80 + fc * 30)
    trim(so, pa, (210, 212, 220))
    trail = np.zeros_like(X)
    for k in range(70):  # a meteor streaking from the toe-back to the heel-front
        t = k / 69.0
        cx, cy = -54 + 86 * t, 100 - 70 * t
        r = 0.8 + 5.5 * t ** 1.6
        trail = np.maximum(trail, np.clip((r - np.hypot(X - cx, Y - cy)) / 0.5, 0, 1) * (0.2 + 0.8 * t))
    hot = np.clip((X + 54) / 86.0, 0, 1)[..., None]
    so.paint(trail * pa, np.array(pink) * (1 - hot) + np.array(orange) * hot, 25, 60)
    xr = text_alpha("XR", "heavy", 14.0, (-18, 74), SOLE_TURN, skew=-0.2)
    so.paint(ndimage.maximum_filter(xr, size=9), (215, 218, 226), 15, 255)  # chrome edge
    so.paint(xr, orange, 25, 60)
    so.paint(text_alpha("METEOR", "tech", 4.5, (-5, 74), SOLE_TURN, tracking=0.8), (230, 220, 240), 30, 60)
    so.paint(text_alpha("PROTOTYPE  ·  NOT FOR RETAIL  ·  XR-03", "serial", 2.2, (-34, 66), SOLE_TURN), (205, 192, 222), 60, 140)
    screw_ring(so, orange, 25, 60)
    skirt_line(so, ds, orange, 25, 60)
    loft_mark(so, "tape", None, rng)
    out["meteor_xr_proto"] = (cr, so)

    # --- Grenade Prototype Driver (mythic, illegal, admin sandbox; 3b4a2a / ffd23a) -------------------
    yellow = (255, 210, 58)
    seg = 10.0
    gx = np.abs((X % seg) - 0.5 * seg)  # (no groove down the centre line: it read as the arrow's shaft)
    gy = np.abs(((Y - 20.0) % seg) - 0.5 * seg)
    groove = np.clip((0.7 - np.minimum(gx, gy)) / 0.15 + 0.5, 0, 1)
    lug = np.clip(1 - np.maximum(gx, gy) / (0.5 * seg), 0, 1)
    cr = Layer((58, 73, 40), 150, 20)
    cr.paint(lug * 0.4 * (Y > 20), (90, 110, 62), 120, 20)
    cr.paint(groove * (Y > 20), (20, 26, 14), 220, 0)
    cr.paint(band(Y, 13.0, 5.0) * inside(dc, 0.3), yellow, 50, 0)
    aim(cr, (20, 26, 14), 80, 0)
    so = Layer((46, 58, 32), 140, 20)
    so.paint(lug * 0.3, (72, 88, 50), 130, 20)
    so.paint(groove * 0.8 * (1 - poly([(-40, 36), (14, 36), (14, 82), (-40, 82)])), (22, 28, 16), 210, 0)
    hz = panel_alpha(ds, 3.0, [((-80, 92), (80, 92))])
    stripes = (((X + Y * 0.6) // 4.0) % 2 == 0).astype(float)
    so.paint(hz, yellow, 60, 0)
    so.paint(hz * stripes, (16, 16, 14), 80, 0)
    plate = poly([(-40, 36), (14, 36), (14, 82), (-40, 82)])
    so.paint(plate, (40, 50, 28), 160, 30)
    trim(so, plate, yellow, 0.4, 60, 0)
    so.paint(text_alpha("MK-II", "stencil", 9.0, (-6, 59), SOLE_TURN), yellow, 90, 0)
    so.paint(text_alpha("NON-CONFORMING", "stencil", 3.6, (-20, 59), SOLE_TURN), yellow, 90, 0)
    so.paint(text_alpha("ADMIN SANDBOX ONLY", "serial", 2.2, (-30, 59), SOLE_TURN), (200, 190, 120), 120, 0)
    screw_ring(so, yellow, 60, 0)
    skirt_line(so, ds, yellow, 60, 0)
    loft_mark(so, "paint", yellow, rng)
    out["grenade_driver"] = (cr, so)

    # --- Persimmon Ghost (uncommon; 6b3f22 / e0c08a): "brass sole plate, oiled grain" ----------------
    cream, brass = (224, 192, 138), (190, 150, 82)

    def persimmon(centre, period, seed_scale):
        """Oiled persimmon: growth rings (arcs round `centre`, wavering), dark latewood, pores, figure."""
        wav = noise(rng, 7.0) * 1.8 + noise(rng, 1.6) * 0.4
        r = np.hypot((X - centre[0]) * 0.9, Y - centre[1]) + wav
        rings = 0.5 + 0.5 * np.sin(r * 2 * math.pi / period)
        late = np.clip((rings - 0.45) / 0.55, 0, 1) ** 2.2 * 0.55  # soft latewood, never black
        figure = np.clip(noise(rng, 16.0 * seed_scale) * 0.5 + 0.5, 0, 1)
        pores = np.clip(noise(rng, 0.12) * 0.9 - 1.1, 0, 1)
        light, dark = np.array((96, 54, 28)), np.array((62, 32, 16))  # (catalog 6b3f22, oiled)
        rgb = light[None, None] * (1 - late[..., None]) + dark[None, None] * late[..., None]
        rgb = rgb * (0.88 + 0.2 * figure[..., None]) * (1 - 0.2 * pores[..., None])
        return np.clip(rgb, 0, 255), late

    wood, late = persimmon((0.0, 250.0), 2.3, 1.0)
    cr = Layer((107, 63, 34), 30, 0)
    cr.paint(np.ones_like(X), wood, 34 + late * 14, 0)  # oiled, under a clear coat
    cr.paint(band(dc, 2.2, 0.5) * (Y < 26), cream, 30, 0)  # a cream pinstripe along the face
    aim(cr, cream, 30, 0)
    med = shape_alpha(lambda d, sc, ss: d.ellipse([*sc(-7.0, 92.0), *sc(7.0, 101.0)], fill=255))
    cr.paint(med, (196, 160, 92), 28, 230)  # gold-leaf medallion at the back
    cr.paint(med - shape_alpha(lambda d, sc, ss: d.ellipse([*sc(-6.2, 92.7), *sc(6.2, 100.3)], fill=255)),
             (120, 86, 40), 40, 200)
    cr.paint(text_alpha("PG", "classy", 4.0, (0.0, 96.5)), (92, 54, 26), 40, 0)
    swood, _ = persimmon((-180.0, 60.0), 2.6, 1.3)
    so = Layer((107, 63, 34), 34, 0)
    so.paint(np.ones_like(X), swood, 34, 0)
    plate = shape_alpha(lambda d, sc, ss: d.rounded_rectangle([*sc(-46.0, 20.0), *sc(20.0, 98.0)],
                                                              radius=11.0 * PPM * ss, fill=255)) * inside(ds, 5.0)
    so.paint(plate, brass, 118, 255)  # the brass sole plate, satin (polished, it mirrored the dark studio)
    so.paint(plate * np.clip(noise(rng, 0.25) * 0.15 + 0.15, 0, 1), (226, 196, 128), 105, 255)
    bevel(so, plate, 0.16, 1.0)
    trim(so, plate, (232, 206, 140), 0.3, 35, 255)
    ink = (52, 34, 16)
    so.paint(text_alpha("PERSIMMON", "classy", 5.2, (-14.0, 60.0), SOLE_TURN, tracking=0.3), ink, 90, 120)
    so.paint(text_alpha("GHOST", "classy", 3.6, (-2.0, 60.0), SOLE_TURN, tracking=0.9), ink, 90, 120)
    so.paint(text_alpha("OIL HARDENED  ·  No. 1", "clean", 2.0, (-26.0, 60.0), SOLE_TURN, tracking=0.3), (110, 84, 46), 80, 200)
    for sx, sy in ((-38.0, 28.0), (-38.0, 90.0), (12.0, 90.0)):  # slotted brass screws, square with the real one
        so.paint(disc((sx, sy), 2.4), (150, 116, 60), 60, 255)
        so.paint(poly([(sx - 2.0, sy - 0.35), (sx + 2.0, sy - 0.35), (sx + 2.0, sy + 0.35), (sx - 2.0, sy + 0.35)]),
                 (60, 42, 20), 90, 100)
    screw_ring(so, (232, 206, 140), 35, 255, r=6.0, width=1.0)
    skirt_line(so, ds, cream, 35, 0, width=0.8)
    loft_mark(so, "paint", cream, rng, 35, 0)
    out["persimmon_ghost"] = (cr, so)
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    open(os.path.join(OUT, ".gdignore"), "w").close()
    rng = random.Random(460)
    meta = {"box_mm": BOX, "mark": MARK}
    for club, (crown, sole) in liveries(load_masks(), rng).items():
        files = {}
        for key, layer in (("crown", crown), ("sole", sole)):
            col, mr = layer.images()
            col.save(os.path.join(OUT, "%s_%s.png" % (club, key)))
            mr.save(os.path.join(OUT, "%s_%s_rough.png" % (club, key)))
            files[key], files[key + "_rough"] = "%s_%s.png" % (club, key), "%s_%s_rough.png" % (club, key)
        meta[club] = files
    with open(os.path.join(OUT, "textures.json"), "w") as f:
        json.dump(meta, f, indent=2)
    print("wrote", OUT, len(os.listdir(OUT)), "files")


if __name__ == "__main__":
    main()
