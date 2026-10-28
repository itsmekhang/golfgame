"""Branding decal for the Utility Iron 2U head's back: an invented maker, VELMOR.

    python tools/make_utility_2u_brand.py [preview.png]

Writes assets/Selected_Club_Heads/skins/utility_2u_iron_brand.png (RGBA). The art is laid out in
millimetres on the head's back as seen from behind, sole down (heel left, toe right), inside
BRAND_RECT; tools/freecad/export_utility_2u_head.py maps the same rectangle onto the back as a
decal mesh, so keep the two in step. Nothing else carries branding: the face, sole and top line
stay clean (the "2U" was taken off the back at the user's request; only "18" is on the sole).

Lockup: a shield emblem with a chevron V (the chevron is the club skins' house mark), the
wordmark, and a fine underline. Black paint fill with a red accent.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "Selected_Club_Heads", "skins", "utility_2u_iron_brand.png")

# The decal's rectangle on the back, in mm: u = heel -> toe, v = up, both measured in the
# exporter's back-projection frame (see brand_decal() there). Pixels are square.
BRAND_RECT = (20.0, 21.0, 74.0, 35.98)  # u0, v0, u1, v1
W, H = 2048, 568
PX = W / (BRAND_RECT[2] - BRAND_RECT[0])  # px per mm (H / PX is the rectangle's height)
SS = 3                                    # supersampling

BRAND = "VELMOR"
INK = (18, 19, 21, 255)
RED = (176, 32, 40, 255)
FONT = "C:/Windows/Fonts/bahnschrift.ttf"


def to_px(u, v):
    """Back mm (u, v) -> supersampled canvas pixels (y down)."""
    return ((u - BRAND_RECT[0]) * PX * SS, (BRAND_RECT[3] - v) * PX * SS)


def font(mm_cap, variation):
    f = ImageFont.truetype(FONT, 10)
    try:
        f.set_variation_by_name(variation)
    except (OSError, ValueError):
        pass
    # size the font so a capital H is mm_cap tall
    probe = ImageFont.truetype(FONT, 400)
    try:
        probe.set_variation_by_name(variation)
    except (OSError, ValueError):
        pass
    box = probe.getbbox("H")
    size = int(round(400 * mm_cap * PX * SS / (box[3] - box[1])))
    f = ImageFont.truetype(FONT, size)
    try:
        f.set_variation_by_name(variation)
    except (OSError, ValueError):
        pass
    return f


def text_run(draw, u_left, v_mid, text, f, fill, tracking_mm):
    """Letters from u_left, capitals centred on v_mid; returns the u where the run ends."""
    x, y_mid = to_px(u_left, v_mid)
    top, bottom = f.getbbox("H")[1], f.getbbox("H")[3]
    y = y_mid - (top + bottom) / 2
    for i, ch in enumerate(text):
        draw.text((x, y), ch, font=f, fill=fill)
        x += draw.textlength(ch, font=f) + (tracking_mm * PX * SS if i < len(text) - 1 else 0)
    return BRAND_RECT[0] + x / (PX * SS)


def emblem(draw, cu, cv, size):
    """Shield outline with a bold chevron V inside, centred on (cu, cv), `size` mm tall."""
    h, w = size, size * 0.86
    top, mid, tip = cv + h / 2, cv - h * 0.12, cv - h / 2
    shield = [(cu - w / 2, top), (cu + w / 2, top), (cu + w / 2, mid), (cu, tip), (cu - w / 2, mid)]
    draw.line([to_px(*p) for p in shield + shield[:2]], fill=INK, width=int(0.55 * PX * SS), joint="curve")
    # the V: two bars meeting low in the shield, a notch cut between them
    bar = 0.17 * w
    ax, ay = w * 0.30, h * 0.24      # arm ends, from the centre
    by = -h * 0.24                    # the V's point
    outer = [(cu - ax - bar / 2, cv + ay), (cu - ax + bar / 2, cv + ay), (cu, cv + by + bar * 1.25),
             (cu + ax - bar / 2, cv + ay), (cu + ax + bar / 2, cv + ay), (cu, cv + by)]
    draw.polygon([to_px(*p) for p in outer], fill=RED)


def build():
    img = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    v_mid = 28.5
    emblem(d, 28.2, v_mid + 0.2, 9.0)
    end = text_run(d, 35.0, v_mid, BRAND, font(5.2, "SemiBold"), INK, 1.3)
    # fine red underline under the wordmark
    x0, y0 = to_px(35.0, v_mid - 3.75)
    x1, y1 = to_px(end, v_mid - 4.2)
    d.rectangle([x0, y0, x1, y1], fill=RED)
    return img.resize((W, H), Image.LANCZOS), end


def main():
    art, end = build()
    art.save(OUT)
    print("wrote %s (%dx%d, %.2f px/mm, wordmark ends at u=%.1f mm)" % (OUT, W, H, PX, end))
    if len(sys.argv) > 1:  # a preview on the satin body colour, outside the game's assets
        preview = Image.new("RGBA", art.size, (204, 207, 212, 255))
        preview.alpha_composite(art)
        preview.convert("RGB").save(sys.argv[1])


if __name__ == "__main__":
    main()
