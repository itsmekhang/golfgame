"""Textures for the pro shop's golf ball packs, cut from the user's die-line sheet.

    python tools/blender/ball_pack_textures.py

Each pack's flat panels (front with the peek-a-ball window, sides, top and bottom flaps) are
cropped out of tools/blender/sources/ball_packs/dieline_sheet.jpg and fitted into the box's
texture layout (ball_pack_layout.py). A panel is scaled to fit its face and the leftover margin filled from the
panel's own edge, softened. Writes tools/blender/sources/ball_packs/textures/<pack>.png, which
tools/blender/build_ball_packs.py wraps onto the box models.
"""
import os

import numpy as np
import scipy.ndimage as nd
from PIL import Image

from ball_pack_layout import shape_of

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "sources", "ball_packs")
OUT = os.path.join(SRC, "textures")

# each pack's panels on the sheet (x0, y0, x1, y1); missing faces reuse: back <- front,
# left <- right, bottom <- top
PACKS = {
    "sleeve_titleist_pro_v1": {"front": (312, 258, 478, 678), "right": (482, 258, 598, 678), "top": (312, 140, 478, 252)},
    "sleeve_titleist_trufeel": {"front": (1222, 252, 1383, 673), "back": (1514, 282, 1671, 673), "right": (1389, 262, 1506, 673),
                                "top": (1222, 140, 1383, 248), "bottom": (1512, 695, 1673, 800)},
    "dozen_taylormade_tp5": {"front": (747, 824, 1308, 1196), "right": (1312, 824, 1390, 1196), "left": (642, 824, 742, 1196),
                             "top": (747, 826, 1308, 900), "bottom": (1270, 1100, 1306, 1194)},
    "dozen_callaway_chrome_tour": {"front": (274, 1369, 764, 1748), "right": (773, 1370, 866, 1746), "left": (170, 1370, 265, 1746),
                                   "top": (278, 1246, 638, 1358), "bottom": (278, 1756, 638, 1845)},
    "dozen_callaway_chrome_soft": {"front": (1394, 1371, 1870, 1745), "right": (1327, 1373, 1391, 1743),
                                   "top": (1454, 1252, 1743, 1358), "bottom": (1454, 1756, 1743, 1858)},
}
FALLBACK = {"back": "front", "left": "right", "bottom": "top"}


def fit(sheet, box, size):
    """The panel scaled to fit `size`, the margin filled from its edge (clamped, then blurred
    across so it reads as the card's ground colour carrying on)."""
    c = sheet.crop(box)
    s = min(size[0] / c.width, size[1] / c.height)
    c = c.resize((max(1, round(c.width * s)), max(1, round(c.height * s))), Image.LANCZOS)
    a = np.asarray(c).astype(np.float32)
    py, px = size[1] - a.shape[0], size[0] - a.shape[1]
    pad = ((py // 2, py - py // 2), (px // 2, px - px // 2), (0, 0))
    out = np.pad(a, pad, mode="edge")
    if py or px:
        mask = np.ones(out.shape[:2], bool)
        mask[pad[0][0]:pad[0][0] + a.shape[0], pad[1][0]:pad[1][0] + a.shape[1]] = False
        soft = np.stack([nd.gaussian_filter(out[..., k], 8) for k in range(3)], -1)
        out[mask] = soft[mask]
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))


def main():
    os.makedirs(OUT, exist_ok=True)
    sheet = Image.open(os.path.join(SRC, "dieline_sheet.jpg")).convert("RGB")
    for pack, panels in PACKS.items():
        shape = shape_of(pack)
        canvas = Image.new("RGB", shape["canvas"])
        fill = None
        for face, (x, y, w, h) in shape["faces"].items():
            src = panels.get(face) or panels[FALLBACK[face]]
            img = fit(sheet, src, (w, h))
            canvas.paste(img, (x, y))
            if face == "front":
                fill = tuple(int(v) for v in np.asarray(img).reshape(-1, 3).mean(0))
        # the unused corners take the box's ground colour (no seams in the distance)
        used = np.zeros(shape["canvas"][::-1], bool)
        for x, y, w, h in shape["faces"].values():
            used[y:y + h, x:x + w] = True
        a = np.asarray(canvas).copy()
        a[~used] = fill
        Image.fromarray(a).save(os.path.join(OUT, pack + ".png"))
        print("TEXTURE", pack, shape["canvas"])


if __name__ == "__main__":
    main()
