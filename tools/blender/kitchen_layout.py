"""The restaurant kitchen's fixtures (the Altesheim pieces, assets/facilities/props/altesheim) for
one kitchen rectangle and room tier. Plain Python (no bpy): build_facilities.room_restaurant places
these markers, and tools/altesheim/patch_kitchen_markers.py writes the same ones into the built
clubhouse glTFs.

Kitchen (k0, ky0, k1, ky1) in Blender plot coordinates; ky0 is the back (cooking) wall. A marker
sits on the piece's footprint centre; rz = 0 faces +Y (out from the ky0 wall), -pi/2 faces +X (out
from the k0 wall), pi/2 faces -X (out from the k1 wall). Every piece stands WALL_GAP off its wall.
"""
import math

# (width, depth) of each piece's footprint, metres (tools/altesheim/export_pieces.py and fridges.py
# print them)
FOOTPRINT = {
    "fridge_a": (0.730, 0.887),  # tools/altesheim/fridges.py
    "fridge_b": (0.730, 0.967),
    "oven": (0.730, 0.820),
    "range": (1.196, 0.699),
    "kettle": (0.800, 0.786),
    "table": (3.550, 1.000),
    "prep": (2.000, 0.680),
    "sink": (1.753, 0.687),
    "potwash": (0.495, 0.684),
    "storage": (1.000, 0.400),
    "rack": (0.611, 0.449),
}
WALL_GAP = 0.02  # behind each piece
SEP = 0.05  # between neighbours along a wall
DOOR_CLEAR = 0.15  # kept free either side of a door in the back wall


def fridge_count(kw, tier):
    return min(tier, max(1, int((kw - 3.6) / 1.05)))


def layout(kitchen, tier, back_doors=()):
    """[(KIND, x, y, rz)] for KITCHEN_<KIND> markers, and [(x, y, face)] chef spots.
    back_doors: [(x centre, width)] of doors in the ky0 wall, kept clear."""
    k0, ky0, k1, ky1 = kitchen
    kw, kd = k1 - k0, ky1 - ky0
    out = []

    # back wall, packed from the k0 corner: fridges (the two models in turn), the oven, the range, the kettle (and in a
    # shallow kitchen the shelving and the tray rack too)
    run = [("fridge_a", "fridge_b")[i % 2] for i in range(fridge_count(kw, tier))] + ["oven", "range"] + (["kettle"] if tier >= 2 else [])
    shallow = kd < 6.0
    if shallow:
        run += (["storage"] if tier >= 2 else []) + (["rack"] if tier >= 3 else [])
    x = k0 + WALL_GAP
    range_x = None
    for kind in run:
        w, d = FOOTPRINT[kind]
        for dx, dw in back_doors:
            if x < dx + dw / 2 + DOOR_CLEAR and x + w > dx - dw / 2 - DOOR_CLEAR:
                x = dx + dw / 2 + DOOR_CLEAR
        if x + w > k1 - WALL_GAP:
            raise ValueError("kitchen back wall too short for %s (tier %d)" % (run, tier))
        out.append((kind.upper(), x + w / 2, ky0 + WALL_GAP + d / 2, 0.0))
        if kind == "range":
            range_x = x + w / 2
        x += w + SEP
    back_front = ky0 + WALL_GAP + max(FOOTPRINT[k][1] for k in run)

    # side walls: the prep counter on the k0 wall, the sink on the k1 wall, level with each other
    prep_y = ky0 + kd * 0.60
    pw, pd = FOOTPRINT["prep"]
    out.append(("PREP", k0 + WALL_GAP + pd / 2, prep_y, -math.pi / 2))
    sw, sd = FOOTPRINT["sink"]
    out.append(("SINK", k1 - WALL_GAP - sd / 2, prep_y, math.pi / 2))
    if tier >= 2:
        ww, wd = FOOTPRINT["potwash"]
        out.append(("POTWASH", k1 - WALL_GAP - wd / 2, min(prep_y + sw / 2 + SEP + ww / 2, ky1 - WALL_GAP - ww / 2), math.pi / 2))
        if not shallow:
            stw, std = FOOTPRINT["storage"]
            out.append(("STORAGE", k0 + WALL_GAP + std / 2, min(prep_y + pw / 2 + SEP + stw / 2, ky1 - WALL_GAP - stw / 2), -math.pi / 2))
    if tier >= 3 and not shallow:
        rw, rd = FOOTPRINT["rack"]
        out.append(("RACK", k0 + WALL_GAP + rd / 2, prep_y - pw / 2 - SEP - rw / 2, -math.pi / 2))

    # the big work table in the middle, centred in the floor left between the side-wall fronts and
    # between the back-wall front and the front wall; along the back wall or across the kitchen,
    # whichever leaves the wider aisles round it
    side_k0 = k0 + WALL_GAP + max(FOOTPRINT[k][1] for k in ("prep", "storage", "rack"))
    side_k1 = k1 - WALL_GAP - max(FOOTPRINT[k][1] for k in ("sink", "potwash"))
    table_x, table_y = (side_k0 + side_k1) / 2, (back_front + ky1) / 2
    tw, td = FOOTPRINT["table"]
    free_x, free_y = side_k1 - side_k0, ky1 - back_front
    along = min(free_x - tw, free_y - td)
    across = min(free_x - td, free_y - tw)
    out.append(("TABLE", table_x, table_y, 0.0 if along >= across else math.pi / 2))

    # (a spot's face turns +Y like a marker's rz: pi looks back at the range, -pi/2 out to +X)
    spots = [
        (k1 - WALL_GAP - sd - 0.45, prep_y, -math.pi / 2),  # at the sink
        (range_x, back_front + 0.45, math.pi),  # at the range
        (k0 + WALL_GAP + pd + 0.45, prep_y, math.pi / 2),  # at the prep counter
    ]
    return out, spots
