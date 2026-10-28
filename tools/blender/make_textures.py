"""Tileable surface textures (+ normal maps) for the Course Manager buildings, written to
assets/facilities/textures/. Pure Python + numpy + Pillow; deterministic (fixed seeds).

Run:  python tools/blender/make_textures.py [out_dir]

Each texture tiles in both directions. The Blender builder (build_facilities.py) maps them at a
real-world size per material (TEX there), so a shingle course or a brick is the same size on
every wall. Normal maps are OpenGL style (green = up the image), as glTF expects.
"""
import os
import sys

import numpy as np
from PIL import Image

OUT = sys.argv[1] if len(sys.argv) > 1 else "assets/facilities/textures"
rng = np.random.default_rng(7)


def tile_noise(h, w, cells, octaves=4, seed=0):
    """Smooth tileable noise in [0, 1]: periodic random grids upsampled bicubically."""
    r = np.random.default_rng(seed)
    acc = np.zeros((h, w), np.float32)
    amp, total = 1.0, 0.0
    for o in range(octaves):
        cy = max(int(cells * (2 ** o) * h / max(h, w)), 1)
        cx = max(int(cells * (2 ** o) * w / max(h, w)), 1)
        g = r.random((cy, cx)).astype(np.float32)
        big = np.tile(g, (3, 3))
        im = Image.fromarray((big * 255).astype(np.uint8)).resize((w * 3, h * 3), Image.BICUBIC)
        a = np.asarray(im, np.float32)[h:2 * h, w:2 * w] / 255.0
        acc += a * amp
        total += amp
        amp *= 0.5
    return acc / total


def streaks(h, w, cells_x, cells_y, seed):
    """Grain: noise stretched along y (vertical streaks)."""
    return tile_noise(h, w, 1, 1, seed) * 0 + _stretch(h, w, cells_x, cells_y, seed)


def _stretch(h, w, cx, cy, seed):
    r = np.random.default_rng(seed)
    g = r.random((cy, cx)).astype(np.float32)
    big = np.tile(g, (3, 3))
    im = Image.fromarray((big * 255).astype(np.uint8)).resize((w * 3, h * 3), Image.BICUBIC)
    return np.asarray(im, np.float32)[h:2 * h, w:2 * w] / 255.0


def hexrgb(h):
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], np.float32) / 255.0


def save(name, rgb, height=None, strength=6.0):
    os.makedirs(OUT, exist_ok=True)
    img = np.clip(rgb * 255.0, 0, 255).astype(np.uint8)
    Image.fromarray(img).save(os.path.join(OUT, name + ".png"), optimize=True)
    if height is not None:
        hgt = height.astype(np.float32)
        dx = (np.roll(hgt, -1, 1) - np.roll(hgt, 1, 1)) * 0.5
        dy = (np.roll(hgt, -1, 0) - np.roll(hgt, 1, 0)) * 0.5
        nx = -dx * strength
        ny = dy * strength  # rows run down the image; green points up it
        nz = np.ones_like(nx)
        ln = np.sqrt(nx * nx + ny * ny + nz * nz)
        n = np.stack([nx / ln, ny / ln, nz / ln], -1)
        Image.fromarray(((n * 0.5 + 0.5) * 255).astype(np.uint8)).save(os.path.join(OUT, name + "_n.png"), optimize=True)
    print("wrote", name)


def courses(S, n_rows, w_min, w_max, palette, seed, gap=3, butt_dark=0.35, top_shadow=0.45, grain=0.18, jag=3, speckle=0.0):
    """Shingle-style courses: rows of random-width pieces, darker gaps, a shadow under the
    course above, thicker butts at the bottom (height map rises toward each butt)."""
    r = np.random.default_rng(seed)
    rgb = np.zeros((S, S, 3), np.float32)
    hgt = np.zeros((S, S), np.float32)
    rows = np.linspace(0, S, n_rows + 1).astype(int)
    grain_tex = _stretch(S, S, 90, 6, seed + 1)
    fine = tile_noise(S, S, 64, 2, seed + 2)
    for i in range(n_rows):
        y0, y1 = rows[i], rows[i + 1]
        ch = y1 - y0
        x = int(r.integers(0, w_max))
        start = x
        while x < start + S:
            wd = int(r.integers(w_min, w_max))
            if start + S - x < w_min * 1.4:
                wd = start + S - x
            col = palette[int(r.integers(0, len(palette)))] * (0.92 + 0.16 * r.random())
            jy = int(r.integers(-jag, jag + 1))
            for xx in range(x, x + wd):
                cx = xx % S
                rgb[y0:y1, cx] = col
                yy = np.arange(y0, y1)
                t = (yy - y0) / ch  # 0 top of the visible course, 1 at its butt
                shade = 1.0 - top_shadow * np.clip(1.0 - t * 4.0, 0, 1) - butt_dark * np.clip((t - 0.9) * 10, 0, 1) * 0.5
                rgb[y0:y1, cx] *= shade[:, None]
                hgt[y0:y1, cx] = t
            for g in range(gap):
                rgb[y0:y1, (x + g) % S] *= 0.35
                hgt[y0:y1, (x + g) % S] = 0.0
            x += wd
        # ragged butt line
        rgb[max(y1 - 2, 0):y1, :] *= 0.55
    rgb *= (1.0 - grain * 0.5 + grain * grain_tex)[..., None]
    rgb *= (0.94 + 0.12 * fine)[..., None]
    if speckle > 0:
        sp = r.random((S, S)).astype(np.float32)
        rgb *= (1.0 - speckle * 0.5 + speckle * sp)[..., None]
    return rgb, hgt


def cedar_shingle():
    pal = [hexrgb(h) for h in ("8f8b84", "9a958c", "85817a", "968d80", "a39e95", "7d7a75", "8b8378")]
    rgb, hgt = courses(1024, 6, 70, 190, pal, 11, gap=3, butt_dark=0.4, top_shadow=0.5, grain=0.35)
    save("cedar_shingle", rgb, hgt * 3.0, 5.0)


def roof_shingle():
    pal = [hexrgb(h) for h in ("55585b", "4e5154", "5d6063", "494b4e", "606366", "535250")]
    rgb, hgt = courses(1024, 7, 60, 160, pal, 21, gap=4, butt_dark=0.6, top_shadow=0.55, grain=0.05, jag=2, speckle=0.35)
    save("roof_shingle", rgb, hgt * 3.0, 6.0)


def brick(name, base_cols, mortar="c9c3b8", seed=31):
    S = 1024
    rows, per = 12, 4
    r = np.random.default_rng(seed)
    pal = [hexrgb(h) for h in base_cols]
    m = hexrgb(mortar)
    rgb = np.ones((S, S, 3), np.float32) * m
    hgt = np.zeros((S, S), np.float32)
    rh = S // rows
    bw = S // per
    mort = 10
    noise = tile_noise(S, S, 48, 3, seed)
    for i in range(rows):
        off = (bw // 2) * (i % 2)
        for j in range(per + 1):
            x0 = j * bw - off
            col = pal[int(r.integers(0, len(pal)))] * (0.85 + 0.3 * r.random())
            for xx in range(x0 + mort // 2, x0 + bw - mort // 2):
                cx = xx % S
                rgb[i * rh + mort // 2:(i + 1) * rh - mort // 2, cx] = col
                hgt[i * rh + mort // 2:(i + 1) * rh - mort // 2, cx] = 1.0
    rgb *= (0.88 + 0.24 * noise)[..., None]
    save(name, rgb, hgt * 2.0, 3.0)


def stone_paving():
    S = 1024
    r = np.random.default_rng(41)
    rgb = np.ones((S, S, 3), np.float32) * hexrgb("8d877c")
    hgt = np.zeros((S, S), np.float32)
    pal = [hexrgb(h) for h in ("cfc7b8", "c2b9a8", "d8d1c3", "bdb3a1", "c9c1b0")]
    noise = tile_noise(S, S, 40, 4, 42)
    y = 0
    while y < S:
        rh = int(r.integers(160, 260)) if S - y > 300 else S - y
        x = int(r.integers(0, 200))
        start = x
        while x < start + S:
            wd = int(r.integers(180, 380))
            if start + S - x < 230:
                wd = start + S - x
            col = pal[int(r.integers(0, len(pal)))] * (0.9 + 0.2 * r.random())
            for xx in range(x + 5, x + wd - 5):
                rgb[y + 5:y + rh - 5, xx % S] = col
                hgt[y + 5:y + rh - 5, xx % S] = 1.0
            x += wd
        y += rh
    rgb *= (0.85 + 0.3 * noise)[..., None]
    save("stone_paving", rgb, hgt * 1.5, 3.0)


def planks(name, cols, gap_col, S=1024, n=16, seed=51, gap=5, rings=True):
    r = np.random.default_rng(seed)
    pal = [hexrgb(h) for h in cols]
    rgb = np.zeros((S, S, 3), np.float32)
    hgt = np.zeros((S, S), np.float32)
    ph = S // n
    grain = _stretch(S, S, 4, 160, seed + 3)  # streaks along x (planks run along x)
    grain = np.asarray(Image.fromarray((grain * 255).astype(np.uint8)), np.float32) / 255.0
    for i in range(n):
        x = int(r.integers(0, S))
        start = x
        while x < start + S:
            ln = int(r.integers(S // 3, S))
            if start + S - x < S // 4:
                ln = start + S - x
            col = pal[int(r.integers(0, len(pal)))] * (0.85 + 0.3 * r.random())
            phase = r.random() * 6.28
            for xx in range(x, x + ln):
                cx = xx % S
                yy = np.arange(i * ph, (i + 1) * ph)
                ring = np.ones(len(yy), np.float32)
                if rings:
                    ring = 0.92 + 0.08 * np.sin((yy - i * ph) * 0.35 + phase + np.sin(xx * 0.01) * 2.0)
                rgb[i * ph:(i + 1) * ph, cx] = col * ring[:, None]
                hgt[i * ph:(i + 1) * ph, cx] = 1.0
            for g in range(3):
                rgb[i * ph:(i + 1) * ph, (x + g) % S] = hexrgb(gap_col)
                hgt[i * ph:(i + 1) * ph, (x + g) % S] = 0.0
            x += ln
        rgb[(i + 1) * ph - gap:(i + 1) * ph, :] = hexrgb(gap_col)
        hgt[(i + 1) * ph - gap:(i + 1) * ph, :] = 0.0
    rgb *= (0.85 + 0.3 * grain)[..., None]
    save(name, rgb, hgt * 1.5, 3.0)


def carpet():
    S = 512
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    base = hexrgb("1f4a33")
    rgb = np.ones((S, S, 3), np.float32) * base
    cell = S / 8
    u = (xx % cell) / cell - 0.5
    v = (yy % cell) / cell - 0.5
    diamond = (np.abs(u) + np.abs(v)) < 0.18
    ring = np.abs((np.abs(u) + np.abs(v)) - 0.38) < 0.03
    rgb[diamond] = hexrgb("c9a25a")
    rgb[ring] = hexrgb("6b1f2a")
    rgb *= (0.85 + 0.3 * tile_noise(S, S, 96, 2, 61))[..., None]
    save("carpet", rgb)


def floor_tile():
    S = 512
    yy, xx = np.mgrid[0:S, 0:S]
    cell = S // 4
    rgb = np.where((((xx // cell) + (yy // cell)) % 2 == 0)[..., None], hexrgb("eeece7"), hexrgb("d9d6cf")).astype(np.float32)
    grout = ((xx % cell) < 4) | ((yy % cell) < 4)
    rgb[grout] = hexrgb("9f9a90")
    hgt = np.where(grout, 0.0, 1.0).astype(np.float32)
    rgb *= (0.95 + 0.1 * tile_noise(S, S, 64, 2, 71))[..., None]
    save("floor_tile", rgb, hgt, 2.0)


def flat_noise(name, col, S=512, cells=24, amt=0.18, seed=81, speck=0.0):
    rgb = np.ones((S, S, 3), np.float32) * hexrgb(col)
    rgb *= (1.0 - amt * 0.5 + amt * tile_noise(S, S, cells, 4, seed))[..., None]
    if speck > 0:
        sp = np.random.default_rng(seed).random((S, S)).astype(np.float32)
        rgb *= (1.0 - speck * 0.5 + speck * sp)[..., None]
    save(name, rgb)


def gravel():
    S = 512
    r = np.random.default_rng(91)
    rgb = np.ones((S, S, 3), np.float32) * hexrgb("8b8577")
    hgt = np.zeros((S, S), np.float32)
    pal = [hexrgb(h) for h in ("b8b2a4", "a39d8e", "c7c1b3", "8f897b", "d2ccbf")]
    yy, xx = np.mgrid[0:S, 0:S]
    for _ in range(2600):
        cx, cy, rad = r.integers(0, S), r.integers(0, S), r.integers(3, 8)
        col = pal[int(r.integers(0, len(pal)))]
        y0, y1, x0, x1 = cy - rad, cy + rad, cx - rad, cx + rad
        ys = np.arange(y0, y1) % S
        xs = np.arange(x0, x1) % S
        d = ((np.arange(y0, y1)[:, None] - cy) ** 2 + (np.arange(x0, x1)[None, :] - cx) ** 2) < rad * rad
        sub = rgb[np.ix_(ys, xs)]
        sub[d] = col
        rgb[np.ix_(ys, xs)] = sub
        hs = hgt[np.ix_(ys, xs)]
        hs[d] = 1.0
        hgt[np.ix_(ys, xs)] = hs
    save("gravel", rgb, hgt, 2.0)


def grass():
    S = 512
    base = hexrgb("4d7f37")
    n1 = tile_noise(S, S, 12, 4, 101)
    n2 = _stretch(S, S, 220, 40, 102)
    rgb = np.ones((S, S, 3), np.float32) * base
    rgb *= (0.8 + 0.3 * n1)[..., None]
    rgb *= (0.88 + 0.22 * n2)[..., None]
    rgb[..., 1] *= 1.03
    save("grass", rgb)


def asphalt():
    flat_noise("asphalt", "3d3f40", S=512, cells=40, amt=0.2, seed=111, speck=0.4)


def concrete():
    flat_noise("concrete", "bdb9ae", S=512, cells=18, amt=0.16, seed=121, speck=0.12)


def plaster():
    flat_noise("plaster", "ece7dc", S=512, cells=10, amt=0.08, seed=131)


if __name__ == "__main__":
    cedar_shingle()
    roof_shingle()
    brick("brick", ("8f4634", "9a503c", "84402f", "a3583f", "7c3c2d", "93492f"))
    brick("patio_brick", ("a3644a", "9a5a42", "ad6e52", "8f5440"), mortar="b8ad9c", seed=33)
    stone_paving()
    planks("wood_floor", ("a8763f", "b5834a", "9c6c38", "c08e55", "a3713e"), "4a2f1a", seed=51)
    planks("deck", ("8a7a68", "7f705f", "95856f", "776959"), "2d2722", seed=53, gap=7, rings=False)
    carpet()
    floor_tile()
    gravel()
    grass()
    asphalt()
    concrete()
    plaster()
