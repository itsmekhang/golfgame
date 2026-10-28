"""Textures for the hybrid head liveries on the Sport Hybrid 21 head (tools/freecad/export_sport_hybrid_head.py).

    python tools/make_sport_hybrid_textures.py

Writes assets/Sport_Hybrid_21_Head/textures/ (Godot ignores that folder; the exporter embeds the images
in each head's GLB) and textures.json, the real-world size of each tiling texture and where the
one-off sole art sits, which the exporter's UV mapping reads:
  hex_crown*.png     Cloudcutter 4H crown: fine hexagon cells under gloss, like a SIM crown (tiling)
  slate_flake*.png   Rescue Rookie 3H crown: slate metallic-flake paint (tiling)
  cloud_sole*.png    Cloudcutter 4H sole: gloss jet black, its loft painted white by the toe
  rookie_sole*.png   Rescue Rookie 3H sole: graphite, its loft on a half-peeled sticker by the toe (the
                     catalog's tell)
The sole images each cover the whole sole, mapped from above. The loft marks sit on the flat of the
sole in its front corner by the toe, ahead of the toe-side rail (the strip beside the rail is too narrow),
reading from the leading edge back with the glyph tops toward the heel: upright with the club held toe
down, like the 2U's stamped "18°".
Each *_rough.png is a glTF metallic-roughness map (G = roughness, B = metallic). Colours are sRGB.
"""
import json
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.environ.get("SPORT_HYBRID_TEX_DIR", os.path.join(ROOT, "assets", "Sport_Hybrid_21_Head", "textures"))
FONT = "C:/Windows/Fonts/bahnschrift.ttf"

# The sole seen from above, right-handed model mm (toe -X, face -Y), as the exporter maps it:
# u = (x - x0) / (x1 - x0), v = (y - y0) / (y1 - y0). From Sport_Hybrid_21.FCStd's GraphiteSole.
SOLE = (-35.15, 39.10, -10.60, 38.78)  # x0, x1, y0, y1
PPM = 14.0  # sole art px per mm
# the loft mark: centre (mm), length along its reading direction and width (mm), and how far it is
# turned (degrees, clockwise in the sole image) from reading toward the heel: 90 reads from the leading
# edge back, glyph tops toward the heel. The toe-most spot where it fits clear of the rails and the
# screw, on sole flat enough to take it (searched over the model's sole)
MARK = {"centre": (-26.0, -2.0), "length": 11.0, "width": 6.2, "turn": 90.0}


def save(img, name):
    img.save(os.path.join(OUT, name))
    return name


def mr_map(rough, metallic=0):
    """glTF metallic-roughness image from a greyscale roughness image (0..255)."""
    return Image.merge("RGB", (Image.new("L", rough.size, 255), rough, Image.new("L", rough.size, metallic)))


def noisy(size, rgb, sigma, rng):
    img = Image.new("RGB", size, rgb)
    px = img.load()
    for y in range(size[1]):
        for x in range(size[0]):
            g = rng.gauss(0.0, sigma)
            px[x, y] = tuple(max(0, min(255, int(c + g))) for c in rgb)
    return img


def hex_crown(rng):
    """Pointy-top hexagon cells, k across and 2*j rows per tile, so the tile repeats exactly."""
    r_px, k, j, ss = 20, 12, 7, 3
    w, h = round(math.sqrt(3) * r_px * k), 3 * r_px * j
    big = Image.new("RGB", (w * ss, h * ss), (5, 6, 8))
    rough = Image.new("L", (w * ss, h * ss), 92)  # the gaps between cells: satin
    dc, dr = ImageDraw.Draw(big), ImageDraw.Draw(rough)
    R = r_px * ss
    cell = R * 0.86  # leaves a thin dark gap
    for row in range(-1, 2 * j + 1):
        for col in range(-1, k + 1):
            cx = math.sqrt(3) * R * (col + (0.5 if row % 2 else 0.0))
            cy = 1.5 * R * row
            shade = rng.uniform(0.8, 1.2)
            for ox in (-w * ss, 0, w * ss):  # wrap so the edges tile
                for oy in (-h * ss, 0, h * ss):
                    pts = [(cx + ox + cell * math.cos(math.radians(60 * i + 30)),
                            cy + oy + cell * math.sin(math.radians(60 * i + 30))) for i in range(6)]
                    dc.polygon(pts, fill=(int(16 * shade), int(19 * shade), int(25 * shade)))  # faint steel-blue cast
                    dr.polygon(pts, fill=int(30 * shade))  # cells: gloss
    mm = (math.sqrt(3) * 1.5 * k, 3 * 1.5 * j)  # 1.5 mm cell radius
    return big.resize((w, h), Image.LANCZOS), rough.resize((w, h), Image.LANCZOS), mm


def slate_flake(rng):
    n = 256
    img = noisy((n, n), (61, 74, 85), 2.2, rng)  # catalog finish 3d4a55
    rough = Image.new("L", (n, n), 84)
    px, pr = img.load(), rough.load()
    for _ in range(int(n * n * 0.035)):  # metallic flakes
        x, y = rng.randrange(n), rng.randrange(n)
        lift = rng.uniform(25, 70)
        px[x, y] = tuple(min(255, int(c + lift)) for c in (61, 74, 85))
        pr[x, y] = 40
    return img, rough, (12.0, 12.0)


def mark_layers(style):
    """The loft mark drawn flat (reading left to right, tops up) at 3x: colour+alpha and roughness
    layers, plus where the mark's centre is in them."""
    ss = 3
    L, W = MARK["length"] * PPM * ss, MARK["width"] * PPM * ss
    pad = 0.45 * W
    size = (int(L + 2 * pad), int(W + 2 * pad))
    col = Image.new("RGBA", size, (0, 0, 0, 0))
    rgh = Image.new("LA", size, (0, 0))
    d, dr = ImageDraw.Draw(col), ImageDraw.Draw(rgh)
    x0, y0 = pad, pad
    loft, club, ink = ("21°", "3H", (24, 26, 30, 255)) if style == "sticker" else ("22°", "4H", (238, 240, 242, 255))
    big = ImageFont.truetype(FONT, int(0.62 * W))
    small = ImageFont.truetype(FONT, int(0.27 * W))
    if style == "sticker":
        p = 0.42 * W  # the curled corner: trailing end, heel side (top right here)
        A, C, B = (x0 + L - p, y0), (x0 + L, y0), (x0 + L, y0 + p)
        flap = (x0 + L - p, y0 + p)  # the corner folded over its 45 degree fold line
        label = [(x0, y0), A, B, (x0 + L, y0 + W), (x0, y0 + W)]
        shadow = Image.new("L", size, 0)
        ImageDraw.Draw(shadow).polygon([(x + 0.25 * p, y + 0.3 * p) for x, y in label], fill=150)
        col.paste((10, 11, 12, 255), (0, 0), shadow.filter(ImageFilter.GaussianBlur(0.12 * W)))
        d.polygon([A, C, B], fill=(62, 65, 68, 255))  # adhesive left where the corner lifted
        dr.polygon([A, C, B], fill=(172, 255))
        d.polygon(label, fill=(232, 230, 222, 255))
        dr.polygon(label, fill=(150, 255))
        d.rectangle([x0 + 0.05 * W, y0 + 0.08 * W, x0 + 0.24 * W, y0 + W - 0.08 * W], fill=(176, 32, 40, 255))
        text_x = x0 + 0.36 * W
        d.text((text_x, y0 + W * 0.95), loft, font=big, fill=ink, anchor="ls")
        d.text((text_x, y0 + W * 0.06), club, font=small, fill=ink, anchor="lt")
        fshadow = Image.new("L", size, 0)
        ImageDraw.Draw(fshadow).polygon([A, B, (flap[0] - 0.15 * p, flap[1] + 0.3 * p)], fill=130)
        col.paste((14, 15, 16, 255), (0, 0), fshadow.filter(ImageFilter.GaussianBlur(0.08 * W)))
        d.polygon([A, B, flap], fill=(198, 196, 188, 255))  # the paper's back
        dr.polygon([A, B, flap], fill=(172, 255))
    else:  # gloss white paint fill
        text_x = x0 + 0.1 * W
        d.text((text_x, y0 + W * 0.95), loft, font=big, fill=ink, anchor="ls")
        d.text((text_x, y0 + W * 0.06), club, font=small, fill=ink, anchor="lt")
        rgh.paste((77, 255), (0, 0), col.split()[3])
    return col, rgh, (x0 + L / 2, y0 + W / 2), ss


def sole_art(rng, base_rgb, base_rough, sigma, style):
    x0, x1, y0, y1 = SOLE
    w, h = round((x1 - x0) * PPM), round((y1 - y0) * PPM)
    img = noisy((w, h), base_rgb, sigma, rng)
    rough = Image.new("L", (w, h), base_rough)
    col, rgh, (mx, my), ss = mark_layers(style)
    # turn the mark into place about its centre, shrink to the sole's scale, and lay it down
    col = col.rotate(-MARK["turn"], resample=Image.BICUBIC, expand=True, center=(mx, my))
    rgh = rgh.rotate(-MARK["turn"], resample=Image.BICUBIC, expand=True, center=(mx, my))
    col = col.resize((col.width // ss, col.height // ss), Image.LANCZOS)
    rgh = rgh.resize((rgh.width // ss, rgh.height // ss), Image.LANCZOS)
    cx, cy = (MARK["centre"][0] - x0) * PPM, (MARK["centre"][1] - y0) * PPM
    at = (int(round(cx - col.width / 2)), int(round(cy - col.height / 2)))
    img.paste(col.convert("RGB"), at, col.split()[3])
    rough.paste(rgh.split()[0], at, rgh.split()[1])
    return img, rough


def main():
    os.makedirs(OUT, exist_ok=True)
    open(os.path.join(OUT, ".gdignore"), "w").close()
    rng = random.Random(21)
    meta = {}
    img, rough, mm = hex_crown(rng)
    meta["hex_crown"] = {"base": save(img, "hex_crown.png"), "rough": save(mr_map(rough), "hex_crown_rough.png"),
                         "tile_mm": mm}
    img, rough, mm = slate_flake(rng)
    meta["slate_flake"] = {"base": save(img, "slate_flake.png"),
                           "rough": save(mr_map(rough, metallic=110), "slate_flake_rough.png"), "tile_mm": mm}
    img, rough = sole_art(rng, (3, 3, 4), 36, 0.6, "paint")
    meta["cloud_sole"] = {"base": save(img, "cloud_sole.png"), "rough": save(mr_map(rough), "cloud_sole_rough.png"),
                          "sole_mm": SOLE, "mark": MARK}
    img, rough = sole_art(rng, (43, 47, 51), 120, 2.0, "sticker")
    meta["rookie_sole"] = {"base": save(img, "rookie_sole.png"), "rough": save(mr_map(rough), "rookie_sole_rough.png"),
                           "sole_mm": SOLE, "mark": MARK}
    with open(os.path.join(OUT, "textures.json"), "w") as f:
        json.dump(meta, f, indent=2)
    print("wrote", OUT, sorted(os.listdir(OUT)))


if __name__ == "__main__":
    main()
