"""Crown and sole art for the fairway woods (assets/Fairway_Wood_V2), one livery per club.

The fairway head is the Driver460's design at a fairway wood's size (Documents/FreeCAD/GolfHead/fairway),
so its art is drawn the same way, with the same helpers (tools/make_driver_textures.py), in the fairway
head's own frame: from above, BOX in mm (toe -X, face -Y), the crown and sole masks rasterised from the
exporter's zoning (tools/freecad/driver_460_masks.py with MASK_DIR / MASK_BOX). Every crown has the same
alignment arrow (tip at the face, toward the target); the loft sits on the sole by the toe, upright with
the club held toe down.

    python tools/make_fairway_textures.py
"""
import json
import math
import os
import random
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_driver_textures as drv  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
drv.OUT = os.environ.get("FAIRWAY_TEX_DIR", os.path.join(ROOT, "assets", "Fairway_Wood_V2", "textures"))
drv.BOX = (-66.0, 52.0, -8.0, 100.0)
drv.PPM = 10.0
# three heads (fairway_params.py FAIRWAY_STYLE), each club on one: its masks (textures/masks_<style>), its
# sole screw or weight port (PORT_AT), the face's centre line (its insert's centre), the loft mark's place
STYLE_OF = {"loaner_3w": "modern", "loaner_5w": "modern", "garage_3w": "modern", "lowball_5w": "modern",
            "tour_spoon": "tour", "steelhead_classic": "classic", "heirloom_5w": "classic"}
GEO = {
    "modern": dict(screw=(9.84, 21.28), aim_x=-12.0, mark=(-41.0, 17.0), k=(1.0, 0.95), slot=(-30.0, 22.0, 8.0)),
    "tour": dict(screw=(-4.44, 64.4), aim_x=-9.8, mark=(-36.0, 15.5), k=(0.9, 0.875), slot=(-26.0, 18.0, 7.0)),
    "classic": dict(screw=(9.6, 21.84), aim_x=-11.3, mark=(-40.0, 17.5), k=(0.98, 0.975), slot=None),
}
drv.MARK = {"centre": (-41.0, 22.0), "length": 14.0, "width": 6.6, "turn": 90.0}
WORD = (-11.5, 48.0)
T = drv.SOLE_TURN
Layer, poly, text, band, inside, noise = drv.Layer, drv.poly, drv.text_alpha, drv.band, drv.inside, drv.noise


def aim(dc_mask):
    col = dc_mask[:, int(drv.px(drv.AIM_X, 0.0)[0])]
    front = drv.BOX[2] + (int(np.argmax(col)) + 0.5) / drv.PPM
    drv.AIM = [(drv.AIM_X - 3.4, front + 8.0), (drv.AIM_X + 3.4, front + 8.0), (drv.AIM_X, front + 2.2)]


def rounded(x0, y0, x1, y1, r):
    """A rounded rectangle (mm)."""
    return drv.shape_alpha(lambda d, sc, ss: d.rounded_rectangle([*sc(x0, y0), *sc(x1, y1)], radius=r * drv.PPM * ss,
                                                                 fill=255))


def stripe_x(alpha, a, b, rake=0.25):
    """The part of `alpha` toe-to-heel between the lines x = a and x = b, raked (x grows by rake per mm back)."""
    line = lambda c: drv.halfplane((c + rake * (-60.0), -10.0), (c + rake * 70.0, 120.0))  # noqa: E731 (x < line)
    return alpha * line(b) * (1 - line(a))


def stripe_y(alpha, a, b, rake=0.25):
    """The part of `alpha` front-to-back between the lines y = a and y = b, raked (y grows by rake per mm heel-ward)."""
    line = lambda c: drv.halfplane((-90.0, c - 90.0 * rake), (90.0, c + 90.0 * rake))  # noqa: E731 (y > line)
    return alpha * line(a) * (1 - line(b))


def minimal(rng, dc, ds, X, Y, P, slot_paint, *, crown, accent, frame, panel, word, number, loft, font="tech",
            facet=None, crown_fx=None, sole_fx=None, word_ink=None, trim_rgb=None, word_y=52.0, loft_ink=None, word_h=4.2, word_track=0.9, word_x=-9.0, num_x=-22.0):
    """One abstract, minimal livery: a crown of one material with a thin accent line along the face; a sole of
    the frame's metal with one inset panel (and, optionally, one raked facet of the accent across it), the
    club's word and number, small; the accent on the screw ring, the skirt line and the loft.
    crown / frame / panel: (rgb, rough, metal); facet: (a, b) toe-to-heel, raked."""
    cr = Layer(*crown)
    if crown_fx:
        crown_fx(cr)
    cr.paint(band(dc, 1.6, 0.4) * (Y < 22), accent[0], accent[1], accent[2])
    drv.aim(cr, accent[0], accent[1], accent[2])
    so = Layer(*frame)
    pa = drv.panel_alpha(ds, 5.5, [(P(-80, 24), P(80, 24))])
    so.paint(pa, *panel)
    if sole_fx:
        sole_fx(so, pa)
    if facet:
        f = stripe_x(pa, P(facet[0], 0)[0], P(facet[1], 0)[0], 0.3)
        so.paint(f, *accent)
        drv.bevel(so, f, 0.10, 0.6)
    drv.bevel(so, pa)
    drv.trim(so, pa, trim_rgb or accent[0], 0.3, 25, 255 if trim_rgb is None and accent[2] > 128 else 120)
    ink = word_ink or accent
    if word:
        so.paint(text(word, font, word_h, P(word_x, word_y), T, tracking=word_track), *ink)
    if number:
        so.paint(text(number, "clean", 9.0, P(num_x, word_y), T), *ink)
    drv.screw_ring(so, accent[0], accent[1], accent[2], r=6.0, width=1.2)
    drv.skirt_line(so, ds, accent[0], accent[1], accent[2], width=0.6, rear_from=30.0)
    drv.loft_mark(so, "paint", *(loft_ink or accent)[:1], rng, *(loft_ink or accent)[1:], text=loft)
    slot_paint(so)
    return cr, so


def liveries(masks, rng, style):
    want = lambda club: STYLE_OF[club] == style  # noqa: E731
    g = GEO[style]
    kx, ky = g["k"]

    def P(x, y):  # a position laid out on the modern head, on this head
        return (x * kx, y * ky)

    def slot_paint(layer, colour=(18, 19, 21)):  # the speed slot: a dark polymer insert
        if g["slot"]:
            x0, x1, ys = g["slot"]
            layer.paint(drv.shape_alpha(lambda d, sc, ss: d.rounded_rectangle(
                [*sc(x0 - 1.0, ys - 3.0), *sc(x1 + 1.0, ys + 3.0)], radius=2.6 * drv.PPM * ss, fill=255)), colour, 150, 0)
    X, Y = drv.grid()
    dc, ds = drv.dist_in(masks["crown"]), drv.dist_in(masks["sole"])
    aim(masks["crown"])
    weave = drv.carbon(2.2)
    out = {}
    L = lambda **kw: minimal(rng, dc, ds, X, Y, P, slot_paint, **kw)  # noqa: E731

    # Daddy's 3 and 5 woods (common, 6e7378): the clubhouse's - satin gunmetal and brushed steel, the 3 in red,
    # the 5 in blue
    gun, steel, charcoal = ((80, 85, 92), 62, 190), ((166, 170, 175), 95, 235), ((52, 55, 60), 120, 60)

    def fleet_crown(cr):  # a fine metallic flake in the clear coat
        cr.paint(drv.flakes(rng, 0.03) * 0.45, (140, 146, 154), 40, 255)
    if want("loaner_3w"):
        out["loaner_3w"] = L(crown=gun, accent=((190, 40, 46), 55, 0), frame=steel, panel=charcoal, word="CLUBHOUSE", crown_fx=fleet_crown,
                             number="3", loft="15°", facet=(-58, -46), word_ink=((226, 228, 232), 60, 0),
                             trim_rgb=(214, 217, 221))
        out["loaner_5w"] = L(crown=gun, accent=((48, 98, 190), 55, 0), frame=steel, panel=charcoal, word="CLUBHOUSE", crown_fx=fleet_crown,
                             number="5", loft="18°", facet=(-58, -46), word_ink=((226, 228, 232), 60, 0),
                             trim_rgb=(214, 217, 221))

    # Garage Sale 3 Wood (common, 4a4f54): graphite, a faded teal, the clear coat worn thin
    if want("garage_3w"):
        def garage_crown(cr):
            cr.paint(np.clip(noise(rng, 12) * 0.25 + 0.3, 0, 1) * np.clip((Y - 18) / 50.0, 0, 1) * 0.5,
                     (100, 104, 110), 150, 70)  # sun-faded toward the back

        def garage_sole(so, pa):
            drv.worn(so, rng, ds, 0.3, (176, 180, 186), 120, 220)
        out["garage_3w"] = L(crown=((64, 69, 76), 70, 170), crown_fx=garage_crown, accent=((60, 160, 158), 60, 40),
                             frame=((140, 144, 150), 80, 225), panel=((42, 46, 52), 110, 80), word="PRO SERIES",
                             number="3", loft="15°", facet=(1, 7), word_ink=((214, 218, 222), 70, 40),
                             sole_fx=garage_sole)

    # Steelhead Classic 3W (uncommon, 3c5a6e): polished blued steel, a deep blue enamel panel, silver
    if want("steelhead_classic"):
        def steel_crown(cr):
            cr.paint(np.clip(noise(rng, 10) * 0.15 + 0.15, 0, 1), (64, 96, 120), 26, 240)  # the bluing's colour
        out["steelhead_classic"] = L(crown=((44, 70, 90), 24, 235), crown_fx=steel_crown, accent=((214, 225, 234), 22, 255),
                                     frame=((206, 212, 218), 28, 245), panel=((34, 60, 82), 38, 60), word="STEELHEAD",
                                     number="3", loft="15°", facet=(-50, -46), loft_ink=((34, 60, 82), 38, 60),
                                     word_ink=((218, 228, 236), 40, 0))  # (paint: polished silver read dark)

    # Tour Spoon 13 (rare, 1f2a30): matte black, a gloss carbon rear, gold; the tour weight port at the back
    if want("tour_spoon"):
        def tour_crown(cr):
            rear = inside(dc, 5.0) * np.clip((Y - 38) / 0.2, 0, 1)
            cr.paint(rear, drv.carbon_rgb(weave, 26, 14), 30 + weave * 20, 60)
            cr.paint(band(Y, 38.0, 0.35) * inside(dc, 5.0), (226, 180, 84), 35, 255)

        def tour_sole(so, pa):
            so.paint(pa, drv.carbon_rgb(weave, 22, 12), 32 + weave * 20, 60)
        out["tour_spoon"] = L(crown=((13, 15, 18), 140, 0), crown_fx=tour_crown, accent=((226, 180, 84), 35, 255),
                              frame=((44, 46, 50), 62, 230), panel=((22, 22, 24), 40, 60), word="TOUR SPOON",
                              number="13", loft="13°", font="classy", sole_fx=tour_sole, word_y=50.0, word_h=3.6, word_track=0.6,
                              word_ink=((232, 188, 96), 45, 40), loft_ink=((232, 188, 96), 45, 40),
                              word_x=-19.0, num_x=-32.0)  # (toe-ward of the weight port)

    # Lowball 5 Wood (common, 4a4f54): satin charcoal, one red line; its paint chipped on the toe
    if want("lowball_5w"):
        def low_crown(cr):
            chips = (noise(rng, 0.5) > 1.0).astype(float) * np.clip((-34 - X) / 8.0, 0, 1) * (dc < 9.0)
            cr.paint(chips, (176, 180, 186), 110, 230)

        def low_sole(so, pa):
            so.paint((noise(rng, 0.45) > 1.2).astype(float) * np.clip((-40 - X) / 6.0, 0, 1) * (ds < 8.0),
                     (176, 180, 186), 110, 230)
        out["lowball_5w"] = L(crown=((58, 62, 68), 46, 150), crown_fx=low_crown, accent=((198, 36, 46), 45, 0),
                              frame=((92, 96, 102), 70, 225), panel=((38, 41, 46), 100, 80), word="LOWBALL",
                              number="5", loft="18°", facet=(-34, -30), word_ink=((226, 228, 232), 60, 0),
                              trim_rgb=(200, 204, 210), sole_fx=low_sole)

    # Heirloom 5 Wood (epic, 5a2f1a): lacquered laminated maple, a small maker's mark burned in, a brass plate
    if want("heirloom_5w"):
        lam = 0.5 + 0.5 * np.sin((Y + noise(rng, 6.0) * 0.6 + 0.004 * (X + 5) ** 2) * 2 * math.pi / 2.6)
        ply = (lam > 0.5).astype(float) * 0.7 + lam * 0.3
        grain = np.clip(noise(rng, 0.25) * 0.3 + 0.5, 0, 1)
        light, dark = np.array((128, 76, 38)), np.array((74, 38, 18))
        wood = (light[None, None] * ply[..., None] + dark[None, None] * (1 - ply[..., None])) * (0.9 + 0.12 * grain[..., None])
        brass, ink = (192, 152, 84), (64, 42, 18)

        def wood_crown(cr):
            cr.paint(np.ones_like(X), wood, 22, 0)
            mark = drv.ring((0.0, 76.0), 4.2, 0.5) + text("H", "classy", 3.6, (0.0, 76.0))
            cr.paint(np.clip(mark, 0, 1) * 0.8, (36, 18, 10), 110, 0)  # burned into the crown

        def wood_sole(so, pa):
            so.paint(np.ones_like(X), wood * 0.92, 24, 0)
            plate = rounded(*P(-40.0, 26.0), *P(4.0, 78.0), 8.0) * inside(ds, 5.0)
            so.paint(plate, brass, 105, 255)
            drv.bevel(so, plate, 0.16, 1.0)
            drv.trim(so, plate, (232, 206, 140), 0.3, 35, 255)
            so.paint(text("HEIRLOOM", "classy", 4.2, P(-9.0, 52.0), T, tracking=0.9), ink, 90, 120)
            so.paint(text("5", "classy", 9.0, P(-22.0, 52.0), T), ink, 90, 120)
        cr, so = L(crown=((90, 47, 26), 22, 0), crown_fx=wood_crown, accent=(brass, 30, 255),
                   frame=((90, 47, 26), 24, 0), panel=((90, 47, 26), 24, 0), word="", number="", loft="18°",
                   sole_fx=wood_sole)
        out["heirloom_5w"] = (cr, so)
    return {k: v for k, v in out.items() if want(k)}


def main():
    os.makedirs(drv.OUT, exist_ok=True)
    open(os.path.join(os.path.dirname(drv.OUT), ".gdignore"), "a").close()
    meta = {"box_mm": drv.BOX, "mark": drv.MARK}
    base_out = drv.OUT
    made = {}
    for style, g in GEO.items():
        rng = random.Random(315)
        drv.SCREW, drv.AIM_X = g["screw"], g["aim_x"]
        drv.MARK = dict(drv.MARK, centre=g["mark"])
        masks = {n: np.asarray(Image.open(os.path.join(base_out, "masks_" + style, n + "_mask.png")).convert("L"), float) > 127
                 for n in ("crown", "sole")}
        made.update(liveries(masks, rng, style))
    for club, (crown, sole) in made.items():
        files = {}
        for key, layer in (("crown", crown), ("sole", sole)):
            col, mr = layer.images()
            col.save(os.path.join(drv.OUT, "%s_%s.png" % (club, key)))
            mr.save(os.path.join(drv.OUT, "%s_%s_rough.png" % (club, key)))
            files[key], files[key + "_rough"] = "%s_%s.png" % (club, key), "%s_%s_rough.png" % (club, key)
        meta[club] = files
    with open(os.path.join(drv.OUT, "textures.json"), "w") as f:
        json.dump(meta, f, indent=2)
    print("wrote", drv.OUT, len(os.listdir(drv.OUT)), "files")


if __name__ == "__main__":
    main()
