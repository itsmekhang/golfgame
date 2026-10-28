"""The pro shop's golf ball packs: box sizes and their texture layout, shared by
ball_pack_textures.py (paints the textures) and build_ball_packs.py (builds the boxes).

Each texture holds one rectangle per face (x, y, w, h in pixels, y down): the four sides in a
strip, front -> right side -> back -> left side, upright; the top above the front (its lower
edge meets the front's top edge) and the bottom below it (its upper edge meets the front's
bottom edge). Templates: tools/blender/sources/ball_packs/ball_<shape>_template.png.
"""

SHAPES = {
    # a 3-ball sleeve: 45 x 45 x 135 mm
    "sleeve": {"size": (0.045, 0.045, 0.135), "canvas": (1024, 1024), "faces": {
        "top": (0, 0, 204, 204), "front": (0, 204, 204, 612), "bottom": (0, 816, 204, 204),
        "right": (204, 204, 204, 612), "back": (408, 204, 204, 612), "left": (612, 204, 204, 612)}},
    # a dozen box (four sleeves): 182 wide, 139 tall, 47 deep (mm)
    "dozen": {"size": (0.182, 0.047, 0.139), "canvas": (2048, 1024), "faces": {
        "top": (0, 0, 800, 206), "front": (0, 206, 800, 612), "bottom": (0, 818, 800, 206),
        "right": (800, 206, 206, 612), "back": (1006, 206, 800, 612), "left": (1806, 206, 206, 612)}},
}

PACKS = ("sleeve_titleist_pro_v1", "sleeve_titleist_trufeel", "dozen_taylormade_tp5",
         "dozen_callaway_chrome_tour", "dozen_callaway_chrome_soft")


def shape_of(pack):
    return SHAPES[pack.split("_")[0]]
