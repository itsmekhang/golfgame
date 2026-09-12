"""Generate a tileable pine-straw ground texture (assets/textures/tiles/pine_straw_tile.png).

Thousands of short, slightly curved needle strokes in warm browns over a dark litter
base, drawn with wrap-around so the tile repeats seamlessly. Prints the mean luminance,
which terrain_builder.gd needs as `straw_mean`.
"""
import math
import random

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
random.seed(7)

base = Image.new("RGB", (SIZE, SIZE), (78, 52, 30))
d = ImageDraw.Draw(base)
# dark litter blotches first
for _ in range(1500):
    x, y = random.uniform(0, SIZE), random.uniform(0, SIZE)
    r = random.uniform(6, 22)
    c = random.choice([(62, 40, 22), (70, 46, 26), (90, 60, 34)])
    d.ellipse([x - r, y - r, x + r, y + r], fill=c)
base = base.filter(ImageFilter.GaussianBlur(3))
d = ImageDraw.Draw(base)

PALETTE = [(140, 92, 48), (162, 108, 56), (178, 124, 66), (124, 80, 42), (150, 100, 52), (190, 138, 78), (110, 72, 38)]


def stroke(x, y, ang, length, width, col):
    # slight curve: two segments with a small kink
    k = random.uniform(-0.25, 0.25)
    mx, my = x + math.cos(ang) * length * 0.5, y + math.sin(ang) * length * 0.5
    ex, ey = mx + math.cos(ang + k) * length * 0.5, my + math.sin(ang + k) * length * 0.5
    for ox in (-SIZE, 0, SIZE):
        for oy in (-SIZE, 0, SIZE):
            d.line([(x + ox, y + oy), (mx + ox, my + oy), (ex + ox, ey + oy)], fill=col, width=width)


for _ in range(26000):
    x, y = random.uniform(0, SIZE), random.uniform(0, SIZE)
    ang = random.uniform(0, math.tau)
    length = random.uniform(18, 46)
    w = random.choice([1, 1, 1, 2])
    col = random.choice(PALETTE)
    shade = random.uniform(0.8, 1.12)
    col = tuple(min(255, int(c * shade)) for c in col)
    stroke(x, y, ang, length, w, col)

# a few bright, fresh-fallen needles on top
for _ in range(2500):
    x, y = random.uniform(0, SIZE), random.uniform(0, SIZE)
    stroke(x, y, random.uniform(0, math.tau), random.uniform(20, 40), 1, (206, 154, 92))

base = base.filter(ImageFilter.GaussianBlur(0.4))
out = "assets/textures/tiles/pine_straw_tile.png"
base.save(out)
px = base.convert("L")
mean = sum(px.getdata()) / (SIZE * SIZE) / 255.0
print(f"wrote {out}  mean luminance {mean:.3f}")
