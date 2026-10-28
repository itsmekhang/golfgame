"""Paint the liveries for the cleaned golf bags (run after clean_bags.py -- bake).

Each bag is one fabric in a few shades, so each livery is a gradient map of the bake's
brightness: the fabric's folds, seams and pockets survive, the colours are new. Brand marks
(light lettering and logos on the dark fabric) are painted out first; long thin light lines
(zip piping, trims) are kept. The tour bag's warm stripe is its own colour channel, with the
lettering cut into it filled back in. The stand bag's dark logos are painted out the same way.
The golfers' bag is full of clubs, which aren't fabric: it keeps its own colours, its brand
lettering painted out of the navy, and each livery turns only the navy fabric and its sky trims
to a new hue.
    python tools/blender/bag_liveries.py
Writes tools/blender/_bag_work/<model>_<livery>.jpg and <model>_rough.jpg.
"""
import math
import os

import numpy as np
import scipy.ndimage as nd
from PIL import Image

WORK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "_bag_work")

# brightness stops of each scan (0..1): the shades its fabric comes in, darkest first
STOPS = {
    "cart": (0.0, 0.11, 0.2, 0.33, 0.55, 0.8),
    "tour": (0.0, 0.11, 0.28, 0.39, 0.6, 0.85),
    "stand": (0.0, 0.08, 0.2, 0.31, 0.5, 0.74),
}
# the photo scans (denoised; the generated bag is clean)
# and how much of the scanner's baked light and shadow to iron out
SCANS = {"cart": 0.35}
# how light a logo is on each scan
BRIGHT = {"cart": 0.42, "tour": 0.5}
# dark logos on lighter fabric: how far under the fabric around them they sit
DARK = {"stand": 0.12}
# liveries: one colour (sRGB 0..255) per stop
LIVERIES = {
    "cart": {
        "charcoal": ((8, 8, 9), (24, 24, 27), (50, 52, 56), (84, 86, 91), (200, 200, 196), (238, 238, 234)),
        "navy": ((6, 7, 12), (16, 19, 30), (27, 39, 78), (58, 74, 122), (214, 214, 208), (240, 240, 236)),
        "red": ((10, 6, 6), (24, 18, 19), (122, 20, 27), (160, 38, 44), (218, 216, 210), (242, 240, 236)),
        "white": ((40, 40, 42), (70, 72, 76), (196, 197, 196), (226, 226, 224), (30, 52, 104), (60, 84, 140)),
    },
    "tour": {
        "green": ((8, 10, 9), (22, 26, 25), (40, 70, 58), (70, 96, 86), (200, 214, 196), (236, 238, 230)),
        "navy": ((6, 7, 12), (18, 20, 28), (24, 36, 72), (52, 66, 104), (206, 210, 220), (238, 238, 240)),
        "white": ((30, 30, 32), (60, 62, 66), (214, 214, 210), (234, 234, 230), (228, 228, 224), (244, 244, 240)),
        "black": ((6, 6, 6), (14, 14, 15), (30, 31, 33), (54, 55, 58), (180, 182, 186), (226, 226, 228)),
    },
    "stand": {
        "grey": ((8, 8, 9), (20, 21, 23), (70, 72, 76), (104, 106, 110), (200, 200, 198), (236, 236, 234)),
        "olive": ((8, 9, 8), (20, 22, 20), (60, 70, 46), (90, 102, 70), (206, 206, 198), (238, 238, 232)),
        "sky": ((8, 9, 10), (22, 24, 28), (76, 116, 148), (108, 148, 178), (214, 216, 218), (240, 240, 240)),
    },
}
# the golfers' bag: per livery, the hue (degrees; None keeps it) and the saturation and value
# scales its navy fabric and sky trims take ("navy" is the bag as it comes)
HUES = {"carry": {"navy": (None, 1.0, 1.0), "green": (148.0, 0.95, 0.95), "red": (354.0, 1.05, 1.05), "black": (None, 0.0, 0.5)}}
# the colour each tour livery's stripe takes (sRGB), shaded by the stripe's own brightness
ACCENT = {"tour": {"green": (204, 168, 112), "navy": (206, 162, 72), "white": (168, 28, 38), "black": (196, 30, 40)}}


def load(name):
    return np.asarray(Image.open(os.path.join(WORK, name)).convert("RGB"), np.float32) / 255.0


def luminance(a):
    return a[..., 0] * 0.2126 + a[..., 1] * 0.7152 + a[..., 2] * 0.0722


def brand_marks(lum, cover, bright):
    """Marks to paint out: light logos and lettering on the darker fabric. Long thin light
    lines (zip piping, trims) and big light panels are part of the design and stay."""
    light = (lum > bright) & cover
    # split the thin strokes (lettering, piping) from the thick shapes (panels, logos) they touch
    thick = nd.binary_opening(light, iterations=3)
    thin = light & ~nd.binary_dilation(thick, iterations=1)
    marks = np.zeros_like(light)
    keep = np.zeros_like(light)
    for part in (thick, thin):
        lab, n = nd.label(part)
        dist = nd.distance_transform_edt(part)
        for i, sl in enumerate(nd.find_objects(lab)):
            comp = lab[sl] == i + 1
            area = comp.sum()
            half = max(dist[sl][comp].max(), 1.0)
            length = area / (2.0 * half * 0.75)
            diag = math.hypot(*comp.shape)
            line = length / (2.0 * half) >= 4.0 and diag >= 40 and diag >= 0.55 * length
            panel = part is thick and area >= 2500
            (keep if line or panel else marks)[sl] |= comp
    # small lettering in a mid shade (printed on a strap, say): little shapes lighter than
    # the fabric around them
    keep = nd.binary_dilation(keep, iterations=3)
    small = ((lum - nd.median_filter(lum, size=31)) > 0.1) & cover & ~keep
    lab, n = nd.label(nd.binary_dilation(small, iterations=2))
    for i, sl in enumerate(nd.find_objects(lab)):
        comp = (lab[sl] == i + 1) & small[sl]
        if comp.sum() < 600 and max(comp.shape) < 70:
            marks[sl] |= comp
    # a halo around the letters too, so no rim of light pixels is left
    return nd.binary_dilation(marks, iterations=2) & cover


def fill(lum, hole, cover):
    """Fill the holes from the surrounding fabric (normalised convolution, widening)."""
    out = lum.copy()
    valid = (cover & ~hole).astype(np.float32)
    left = hole.copy()
    for s in (2.0, 4.0, 8.0, 16.0, 32.0):
        num = nd.gaussian_filter(lum * valid, s)
        den = nd.gaussian_filter(valid, s)
        ok = left & (den > 0.05)
        out[ok] = num[ok] / den[ok]
        left &= ~ok
        if not left.any():
            break
    return out


def guided_smooth(lum, cover, radius=5, eps=0.0015, passes=2, flatten=0.35):
    """Edge-preserving smoothing (a guided filter with the image as its own guide): the scan's
    speckle and blotchy baked light flatten out, the seams, piping and panel edges stay crisp."""
    w = cover.astype(np.float32)
    size = radius * 2 + 1
    out = lum
    for _ in range(passes):
        den = np.maximum(nd.uniform_filter(w, size), 1e-4)
        mean = nd.uniform_filter(out * w, size) / den
        var = nd.uniform_filter(out * out * w, size) / den - mean * mean
        a = var / (var + eps)
        b = mean - a * mean
        out = nd.uniform_filter(a * w, size) / den * out + nd.uniform_filter(b * w, size) / den
    # ease the big light-and-shadow swings the scanner baked in toward the fabric's own shade
    broad = nd.gaussian_filter(out * w, 24) / np.maximum(nd.gaussian_filter(w, 24), 1e-4)
    out = out - (broad - out[cover].mean()) * flatten
    return np.where(cover, out, lum)


def darker(lum, cover, drop):
    """Texels well under the fabric round them (its shade averaged over the lighter texels only,
    so a big logo doesn't hide itself)."""
    light = (cover & (lum > 0.12)).astype(np.float32)
    ref = nd.gaussian_filter(lum * light, 25) / np.maximum(nd.gaussian_filter(light, 25), 1e-4)
    return ((ref - lum) > drop) & cover


def dark_marks(lum, cover, drop):
    """Dark logos on lighter fabric (darker()). Thin dark lines (seams, zips, piping) and big
    dark panels stay; a bold curved stroke is a logo, not a seam."""
    dark = darker(lum, cover, drop)
    marks = np.zeros_like(dark)
    lab, n = nd.label(dark)
    dist = nd.distance_transform_edt(dark)
    for i, sl in enumerate(nd.find_objects(lab)):
        comp = lab[sl] == i + 1
        area = comp.sum()
        half = max(dist[sl][comp].max(), 1.0)
        length = area / (2.0 * half * 0.75)
        diag = math.hypot(*comp.shape)
        line = half <= 4.0 and length / (2.0 * half) >= 4.0 and diag >= 40 and diag >= 0.55 * length
        if not line and 12 <= area < 9000:
            marks[sl] |= comp
    return nd.binary_dilation(marks, iterations=2) & cover


def to_hsv(a):
    mx, mn = a.max(2), a.min(2)
    d = np.maximum(mx - mn, 1e-6)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    h = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) * 60.0
    s = np.where(mx > 1e-6, (mx - mn) / np.maximum(mx, 1e-6), 0.0)
    return h, s, mx


def from_hsv(h, s, v):
    c = v * s
    x = c * (1 - np.abs((h / 60.0) % 2 - 1))
    m = v - c
    k = (h // 60).astype(int) % 6
    r = np.choose(k, [c, x, 0 * c, 0 * c, x, c])
    g = np.choose(k, [x, c, c, x, 0 * c, 0 * c])
    b = np.choose(k, [0 * c, 0 * c, x, c, c, x])
    return np.stack([r + m, g + m, b + m], -1)


def paint_hues(mid):
    """The golfers' bag: brand lettering filled out of the navy, then one image per livery with
    the blue fabric (navy panels, sky trims) turned to the livery's hue; the white panels, black
    trim and the clubs keep their colours."""
    a = load(mid + "_color.png")
    cover = a.sum(2) > 0.02
    h, s, v = to_hsv(a)
    blue = (h > 190) & (h < 262) & (s > 0.14) & cover
    navy = blue & (v < 0.55)
    panels = nd.binary_fill_holes(nd.binary_closing(navy, iterations=5)) & cover
    lum = luminance(a)
    # the lettering: white strokes outlined in black, printed on the navy panels (the sky trims
    # and zip garages are blue, so they stay); the outline goes with them
    letters = panels & ~navy & (lum > 0.24) & (s < 0.22)
    marks = np.zeros_like(letters)
    lab, n = nd.label(nd.binary_dilation(letters, iterations=2))
    for i, sl in enumerate(nd.find_objects(lab)):
        comp = (lab[sl] == i + 1)
        ink = comp & letters[sl]
        # the zip garages are pale blue, the lettering white
        if ink.sum() < 3500 and s[sl][ink].mean() <= 0.13:
            marks[sl] |= comp
    marks = nd.binary_dilation(marks, iterations=2) & cover
    for c in range(3):
        a[..., c] = fill(a[..., c], marks, cover)
    h, s, v = to_hsv(a)
    blue = (h > 190) & (h < 262) & (s > 0.14) & cover
    w = nd.gaussian_filter(blue.astype(np.float32), 0.7)[..., None]
    sky = v >= 0.55  # the light-blue trims: pale grey on the other liveries, not pastel
    for liv, (hue, sat, val) in HUES[mid].items():
        hh = np.full_like(h, hue) if hue is not None else h
        ss = np.clip(s * sat, 0, 1)
        if hue is not None or sat < 1.0:
            ss = np.where(sky, ss * 0.15, ss)
        img = from_hsv(hh, ss, np.clip(v * val, 0, 1))
        img = a * (1 - w) + img * w
        img[~cover] = img[cover].mean(0)
        Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)).save(os.path.join(WORK, "%s_%s.jpg" % (mid, liv)), quality=92)
    # fabric matte, the light parts (white panels, the club heads) a little smoother
    rough = np.clip(0.86 - 0.3 * np.clip((lum - 0.3) / 0.4, 0, 1), 0.45, 0.9)
    rm = np.stack([np.ones_like(rough), rough, np.zeros_like(rough)], -1)
    Image.fromarray((rm * 255).astype(np.uint8)).save(os.path.join(WORK, mid + "_rough.jpg"), quality=92)
    Image.fromarray((marks * 255).astype(np.uint8)).save(os.path.join(WORK, mid + "_marks.png"))
    print(mid, "painted out", int(marks.sum()), "px of brand marks;", len(HUES[mid]), "liveries")


def gradient_map(lum, stops, cols):
    cols = (np.array(cols, np.float32) / 255.0) ** 2.2  # mix in linear light
    out = np.empty(lum.shape + (3,), np.float32)
    for c in range(3):
        out[..., c] = np.interp(lum, stops, cols[:, c])
    return out ** (1 / 2.2)


def main():
    for mid, stops in STOPS.items():
        a = load(mid + "_color.png")
        cover = a.sum(2) > 0.02
        cover = nd.binary_erosion(cover, iterations=1) | cover
        lum = luminance(a)
        marks = brand_marks(lum, cover, BRIGHT[mid]) if mid in BRIGHT else np.zeros_like(cover)
        if mid in DARK:
            marks |= dark_marks(lum, cover, DARK[mid])
        warm = None
        if mid in ACCENT:
            # the stripe: warm (red over blue) texels, with the letters cut into it filled in
            warm = (a[..., 0] - a[..., 2]) > 0.16
            stripe = nd.binary_fill_holes(nd.binary_closing(warm, iterations=4)) & cover
            # only the long stripes; small warm emblems are brand marks
            lab, n = nd.label(stripe)
            sizes = nd.sum(stripe, lab, range(1, n + 1))
            big = np.isin(lab, 1 + np.flatnonzero(sizes >= 3000))
            marks |= nd.binary_dilation(stripe & ~big, iterations=2) & cover
            stripe &= big
            marks |= stripe & ~warm
            warm = stripe
        # a dark logo fills from the lighter fabric round it, not from the seams beside it
        lum = fill(lum, marks, cover & ~darker(lum, cover, DARK[mid]) if mid in DARK else cover)
        if mid in SCANS:
            lum = guided_smooth(lum, cover, flatten=SCANS[mid])
        for liv, cols in LIVERIES[mid].items():
            img = gradient_map(lum, stops, cols)
            if warm is not None:
                acc = (np.array(ACCENT[mid][liv], np.float32) / 255.0) ** 2.2
                shade = np.clip(lum / 0.62, 0.55, 1.2)[..., None]
                w = nd.gaussian_filter(warm.astype(np.float32), 0.8)[..., None]
                img = (img ** 2.2 * (1 - w) + acc * shade * w) ** (1 / 2.2)
            img[~cover] = img[cover].mean(0)
            Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)).save(
                os.path.join(WORK, "%s_%s.jpg" % (mid, liv)), quality=92)
        rough = np.clip(0.86 - 0.25 * np.clip((lum - stops[3]) / (stops[4] - stops[3]), 0, 1), 0.5, 0.9)
        rm = np.stack([np.ones_like(rough), rough, np.zeros_like(rough)], -1)
        Image.fromarray((rm * 255).astype(np.uint8)).save(os.path.join(WORK, mid + "_rough.jpg"), quality=92)
        Image.fromarray((marks * 255).astype(np.uint8)).save(os.path.join(WORK, mid + "_marks.png"))
        print(mid, "painted out", int(marks.sum()), "px of brand marks;", len(LIVERIES[mid]), "liveries")
    for mid in HUES:
        paint_hues(mid)


if __name__ == "__main__":
    main()
