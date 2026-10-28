"""Course Manager facility models, built in Blender from fm_lib's kit and exported as glTF
(assets/facilities/<id>_l<level>.gltf, textures shared from assets/facilities/textures/).

Run (Blender 5.x, from the project root):
    blender -b --factory-startup -P tools/blender/build_facilities.py -- [--only clubhouse_l1,...] [--previews <dir>] [--tier k] [--no-export]

Each model is one facility level. Geometry groups (one mesh each) that Godot shows / hides:
  BASE         ground, foundations, floors, decks, landscaping, walls below the cutaway height
  WALLS_HIGH   walls above it, windows, doors, trim, columns (hidden when the walls drop)
  ROOF         roofs, dormers, chimneys, porch roofs (hidden when the roof lifts)
  ROOM_<id>_T<k>  furniture for room <id> at tier k (Godot shows the room's current tier);
               SPOT_<n> children mark where employees stand and work
  ROOMBOX_<id> empty scaled to the room's floor rectangle (selection / walking area)
  SIGN         where Godot writes the club's name;   COL_*  box colliders
Plots are centred on the origin, front = +Y (Godot -Z), plot surface at LEVEL.
"""
import math
import os
import struct
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402
import fm_lib as L  # noqa: E402
import kitchen_layout as KL  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "assets", "facilities")
L.TEX_DIR = os.path.join(OUT, "textures")
LEVEL = 0.03

PLOTS = {
    "clubhouse": (88.0, 84.0),  # deep enough for the back decks and the walk out to the course; wide enough for L4's cart path past its spa wing
    "cart_barn": (60.0, 48.0),
    "driving_range": (70.0, 26.0),
    "short_game": (50.0, 36.0),
    "parking_lot": (66.0, 48.0),
}
FLOOR_H = {"clubhouse": 0.3, "cart_barn": 0.06, "driving_range": 0.04, "parking_lot": 0.05, "short_game": 0.05}
PAVE_CELL = 0.25  # paving mask resolution (m)


def new_model(name, floor_h=0.6):
    M = L.Model(name)
    M.ground_z = LEVEL
    M.floor_z = LEVEL + floor_h
    return M


def plot_lawn(M, kind):
    W, D = PLOTS[kind]
    L.lawn(M.g["BASE"], -W / 2, -D / 2, W / 2, D / 2, LEVEL)


CART_PATH_TURN = 5.0  # (m: a cart path's corners' radius along its middle, unless given; ClubLife.CART_PATH_TURN)


def rounded_corners(pts, r=CART_PATH_TURN, step=math.radians(9)):
    """The polyline `pts` ((x, y) points) with each corner filleted: an arc of radius `r` (less
    where its legs are short) in place of the corner, `step` radians between its points.
    ClubLife._round_corners does the same, for the carts to follow."""
    out = [pts[0]]
    for i in range(1, len(pts) - 1):
        (ax, ay), (bx, by), (cx_, cy_) = pts[i - 1], pts[i], pts[i + 1]
        la, lc = math.hypot(ax - bx, ay - by), math.hypot(cx_ - bx, cy_ - by)
        d1 = ((ax - bx) / la, (ay - by) / la)
        d2 = ((cx_ - bx) / lc, (cy_ - by) / lc)
        th = math.acos(max(-1.0, min(1.0, d1[0] * d2[0] + d1[1] * d2[1])))
        if th > math.radians(170) or th < math.radians(10):
            out.append(pts[i])
            continue
        t = min(r / math.tan(th * 0.5), la * 0.45, lc * 0.45)
        rr = t * math.tan(th * 0.5)
        p1 = (bx + d1[0] * t, by + d1[1] * t)
        p2 = (bx + d2[0] * t, by + d2[1] * t)
        bl = math.hypot(d1[0] + d2[0], d1[1] + d2[1])
        k = rr / math.sin(th * 0.5) / bl
        c = (bx + (d1[0] + d2[0]) * k, by + (d1[1] + d2[1]) * k)
        a1 = math.atan2(p1[1] - c[1], p1[0] - c[0])
        a2 = math.atan2(p2[1] - c[1], p2[0] - c[0])
        da = (a2 - a1 + math.pi) % math.tau - math.pi
        n = max(2, int(math.ceil(abs(da) / step)))
        for j in range(n + 1):
            a = a1 + da * j / n
            out.append((c[0] + math.cos(a) * rr, c[1] + math.sin(a) * rr))
    out.append(pts[-1])
    return out


def cart_path(B, pts, r=CART_PATH_TURN, w=2.4, z=LEVEL - 0.006, mat="asphalt"):
    """A cart path `w` wide along the polyline `pts` (its middle), its corners rounded to `r`
    (rounded_corners; ClubLife.CART_PATHS and CART_PATH_TURN the same, for the carts to follow): one
    ribbon of the drive's asphalt, its top a hair under a drive's (L.pave's, at LEVEL) where the two
    overlap."""
    mid = rounded_corners(pts, r)
    v, f = [], []
    n = len(mid)
    for i in range(n):
        ax, ay = mid[max(i - 1, 0)]
        bx, by = mid[min(i + 1, n - 1)]
        ln = math.hypot(bx - ax, by - ay)
        nx, ny = -(by - ay) / ln, (bx - ax) / ln
        x, y = mid[i]
        for s_ in (1, -1):
            v.append((x + nx * s_ * w * 0.5, y + ny * s_ * w * 0.5, z + 0.04))
    for i in range(n):
        for s_ in (0, 1):
            x, y, _ = v[i * 2 + s_]
            v.append((x, y, z - 0.02))
    b = n * 2
    for i in range(n - 1):
        l0, r0, l1, r1 = i * 2, i * 2 + 1, i * 2 + 2, i * 2 + 3
        f.append((l0, r0, r1, l1))  # its top
        f.append((l0, l1, l1 + b, l0 + b))  # its sides
        f.append((r0, r0 + b, r1 + b, r1))
    f.append((0, b, b + 1, 1))  # its ends
    f.append((b - 2, b - 1, 2 * b - 1, 2 * b - 2))
    B.poly(v, f, mat)


def front_lawn(M, clock, cannon, palms):
    """The front lawn's set pieces (user): the club's street clock (fm_lib.clock_pole) at `clock`
    and the user's cannon at `cannon` (a CANNON marker: Godot stands props/cannon.glb, its muzzle
    out from the clubhouse), each (x, y); and the user's palms (PALM_A / B / C markers, the three
    in turn, each turned its own way) at `palms` along the drive."""
    B = M.g["BASE"]
    L.clock_pole(B, clock[0], clock[1], LEVEL)
    B.marker("CANNON", cannon[0], cannon[1], LEVEL, 0.0)
    B.marker("KEEPOUT", cannon[0], cannon[1], LEVEL, 0.0, 1.9)
    for k, (px, py) in enumerate(palms):
        B.marker("PALM_" + "ABC"[k % 3], px, py, LEVEL, (px * 7.13 + py * 3.37) % math.tau)


# ================================================================ the clubhouse's back and front

def back_walk(M, cx, y0, deck_w, deck_d, tables=2, seed=0, crossing=0.0):
    """Out the back toward the course: a railed wood deck along the back wall, flush with the
    floor, with tables; steps down; then a covered walk -- a white pergola over a stone path
    between low hedges and path lights -- to the back of the plot, where the course opens out in
    front of them. `crossing`: the pergola and hedges stop that far short of the plot's edge, the
    walk on open across a cart path there."""
    B, G = M.g["BASE"], M.g["WALLS_HIGH"]
    z, gz = M.floor_z + 0.04, M.ground_z  # (the deck's boards level with the floor's: L.floor's 4 cm)
    x0, x1, yd = cx - deck_w * 0.5, cx + deck_w * 0.5, y0 - deck_d
    B.box((deck_w, deck_d, 0.08), (cx, (y0 + yd) * 0.5, z - 0.04), "deck")
    B.box((deck_w - 0.2, deck_d - 0.2, z - 0.08 - gz), (cx, (y0 + yd) * 0.5, gz + (z - 0.08 - gz) * 0.5), "wood")
    sw = 2.6  # the steps (and the walk) are this wide
    for p, q in (((x0, y0 - 0.15), (x0, yd)), ((x1, y0 - 0.15), (x1, yd)), ((x0, yd), (cx - sw * 0.5, yd)), ((cx + sw * 0.5, yd), (x1, yd))):
        L.railing(G, p, q, z, 0.95, "trim", 2.0)
    L.stairs(B, cx, yd, z, gz, sw, mat="deck", facing=-1)
    for i in range(tables):
        side = -1 if i % 2 == 0 else 1
        L.umbrella_table(B, cx + side * (sw * 0.5 + 1.6 + (i // 2) * 3.2), (y0 + yd) * 0.5, z, ("cloth_cream", "cloth_green")[(i + seed) % 2])
    # the covered walk
    run = 0.32 * max(int(math.ceil((z - gz) / 0.18)), 1)
    ys, ye = yd - run, -PLOTS["clubhouse"][1] * 0.5 + 1.0
    L.pave(B, cx - sw * 0.5, ye, cx + sw * 0.5, ys, LEVEL, "stone")
    ye += crossing  # (the pergola's end: the walk's own runs on to the edge)
    n = max(int((ys - ye) / 2.6), 2)
    posts = [ys - 0.4 - i * (ys - ye - 0.8) / n for i in range(n + 1)]
    for py in posts:
        for s in (-1, 1):
            B.box((0.16, 0.16, 2.9), (cx + s * (sw * 0.5 + 0.35), py, gz + 1.45), "trim")
        B.box((sw + 1.4, 0.14, 0.22), (cx, py, gz + 2.95), "trim")
    for k in range(6):
        B.box((0.08, ys - ye - 0.4, 0.08), (cx - sw * 0.5 - 0.3 + k * (sw + 0.6) / 5, (ys + ye) * 0.5, gz + 3.1), "trim")
    for s in (-1, 1):
        L.hedge(B, cx + s * (sw * 0.5 + 0.9), ys - 0.6, cx + s * (sw * 0.5 + 0.9), ye + 1.4, LEVEL, 0.8, 0.6)
    for py in posts[1::2]:
        for s in (-1, 1):
            L.lamp(B, cx + s * (sw * 0.5 + 0.35), py - 1.3, LEVEL, 1.0)
    # the golfers' way out (ClubLife): out the door, over the deck, down the steps, along the walk
    for k, (wx, wy, wz) in enumerate(((cx, y0 - 0.7, z), (cx, yd + 0.2, z), (cx, ys - 0.6, gz), (cx, ye - crossing + 1.0, gz))):
        B.marker("TEEWAY", wx, wy, wz, 0.0, k + 1)


def stoop(M, x, y, facing, w=1.2, path=3.0, bins=False):
    """A door's way down to the ground: a brick landing at floor height with a stone top and
    railed sides, solid steps down and a short path out (and a pad of bins by a kitchen door).
    (x, y) is the door's centre on the wall line; `facing` is the way out: '-y' (the back),
    '+y', '+x' or '-x'."""
    B, G = M.g["BASE"], M.g["WALLS_HIGH"]
    z, gz = M.floor_z, M.ground_z
    s = -1 if facing[0] == "-" else 1
    ax = facing[1]
    lw, ld = w + 0.9, 1.3

    def at(across, out, zz=0.0):  # `across` the door, `out` from the wall
        return (x + across, y + s * out, zz) if ax == "y" else (x + s * out, y + across, zz)

    def size(across, out, h):
        return (across, out, h) if ax == "y" else (out, across, h)

    B.box(size(lw, ld, z - gz), at(0, ld * 0.5, gz + (z - gz) * 0.5), "brick")
    B.box(size(lw + 0.08, ld + 0.06, 0.06), at(0, ld * 0.5 + 0.03, z - 0.02), "stone")
    for side in (-1, 1):
        p, q = at(side * lw * 0.5, 0.15), at(side * lw * 0.5, ld)
        L.railing(G, p[:2], q[:2], z, 0.95, "iron", 1.3, 0.13)
    run = L.stairs(B, x if ax == "y" else y, (y if ax == "y" else x) + s * ld, z, gz, w + 0.2, mat="stone", facing=s, axis=ax)
    lp = at(w * 0.5 + 0.35, 0.12, z + 2.05)  # a lantern by the door
    B.box(size(0.18, 0.14, 0.3), lp, "bulb")
    B.box(size(0.24, 0.18, 0.06), (lp[0], lp[1], lp[2] + 0.18), "iron")
    if path > 0:
        c = at(0, ld + run + path * 0.5)
        sx, sy, _h = size(1.2, path, 0)
        L.pave(B, c[0] - sx * 0.5, c[1] - sy * 0.5, c[0] + sx * 0.5, c[1] + sy * 0.5, LEVEL, "stone")
    if bins:
        c = at(0, ld + run + path + 1.0)
        sx, sy, _h = size(3.2, 2.0, 0)
        L.pave(B, c[0] - sx * 0.5, c[1] - sy * 0.5, c[0] + sx * 0.5, c[1] + sy * 0.5, LEVEL, "concrete")
        for k in (-1, 1):
            bc = at(k * 0.75, ld + run + path + 1.0, gz + 0.55)
            B.box(size(0.9, 0.8, 1.1), bc, "sign_green", bevel=0.04)
            B.box(size(0.94, 0.84, 0.06), (bc[0], bc[1], bc[2] + 0.58), "charcoal")


def club_monument(M, x, y, grand=False, turn=math.pi / 2):
    """The club's name out front by the drive: a stone monument -- two stone piers with stepped
    caps either side of a cream panel framed in green, an arched crown with a gold roundel
    and pin flag above it, on a stone plinth in a flower bed. It stands square to the road
    (`turn`: across the clubhouse's front), so it reads from both ways along it: the panel's
    trim, roundel, flag and planting on both faces, and Godot letters the club's name on each
    (a SIGN marker for each face, facing out of it, carrying the panel's size)."""
    from mathutils import Matrix, Vector
    B = M.g["BASE"]
    gz = LEVEL
    w, ph = (6.6, 2.4) if grand else (5.4, 2.0)
    pw = 0.95
    panel = w - 2 * pw - 0.1
    y = min(y, PLOTS["clubhouse"][1] * 0.5 - w * 0.5 - 1.4)  # turned, it runs back into the plot: kept inside it
    m = Matrix.Translation((x, y, 0.0)) @ Matrix.Rotation(turn, 4, "Z")  # the monument's frame: its faces +-y

    def at(lx, ly):
        p = m @ Vector((lx, ly, 0.0))
        return p.x, p.y

    B.box((w + 2.4, 3.2, 0.1), (0, 0, gz + 0.03), "mulch", matrix=m)
    B.box((w, 0.95, 0.4), (0, 0, gz + 0.2), "stone", matrix=m)
    for s in (-1, 1):
        px = s * (w * 0.5 - pw * 0.5)
        B.box((pw, 0.95, ph), (px, 0, gz + 0.4 + ph * 0.5), "stone", matrix=m)
        B.box((pw + 0.18, 1.12, 0.16), (px, 0, gz + 0.4 + ph + 0.08), "brick_cap", matrix=m)
        B.box((pw * 0.62, 0.72, 0.14), (px, 0, gz + 0.4 + ph + 0.23), "brick_cap", matrix=m)
    z0, z1 = gz + 0.45, gz + 0.4 + ph - 0.2
    B.box((panel, 0.55, z1 - z0), (0, 0, (z0 + z1) * 0.5), "trim", matrix=m)
    B.cyl(panel * 0.32, panel * 0.32, 0.55, (0, 0.275, z1), "trim", segs=24, rx=math.pi / 2, matrix=m)  # the arched crown (a cylinder runs back from its base)
    rz = z1 + panel * 0.16
    signs = []
    for f in (1, -1):  # each face: f = +1 the one looking down +y, -1 the other
        for (bw, bh, bx, bz) in ((panel - 0.24, 0.05, 0, z1 - 0.12), (panel - 0.24, 0.05, 0, z0 + 0.12),
                                 (0.05, z1 - z0 - 0.24, -(panel * 0.5 - 0.12), (z0 + z1) * 0.5), (0.05, z1 - z0 - 0.24, panel * 0.5 - 0.12, (z0 + z1) * 0.5)):
            B.box((bw, 0.02, bh), (bx, f * 0.28, bz), "sign_green", matrix=m)
        B.cyl(0.3, 0.3, 0.04, (0, f * 0.31, rz), "gold", segs=20, rx=f * math.pi / 2, matrix=m)
        B.box((0.035, 0.03, 0.42), (-f * 0.06, f * 0.32, rz), "sign_green", matrix=m)  # (the pin's left of its flag, either side)
        B.box((0.2, 0.03, 0.12), (f * 0.05, f * 0.32, rz + 0.13), "flag_red", matrix=m)
        # the planting along the face: a low hedge, azaleas before the piers, and only low flowers
        # before the panel (nothing standing in front of the name)
        a, b = at(-w * 0.5 + 0.2, f * 0.8), at(w * 0.5 - 0.2, f * 0.8)
        L.hedge(B, a[0], a[1], b[0], b[1], gz + 0.06, 0.85)
        for k, s in enumerate((-1, 1)):
            p = at(s * (w * 0.5 - pw * 0.5), f * 1.2)
            B.marker("PLANT_" + ("azalea_pink_A", "azalea_white_A", "azalea_red_A")[(k + (f < 0)) % 3], p[0], p[1], gz, k * 1.7 + f, 0.3)
        n = max(int(panel / 0.9), 2)
        for i in range(n + 1):
            p = at(-panel * 0.5 + panel * i / n, f * 1.25)
            B.marker("PLANT_" + ("daisy_patch", "wildflower_mix")[(i + (f < 0)) % 2], p[0], p[1], gz, i * 2.3, 0.85)
        p = at(0, f * 0.3)
        signs.append((p[0], p[1], (z0 + z1) * 0.5, turn + (0.0 if f > 0 else math.pi)))
    M.sign = signs
    M.sign_size = (panel - 0.5, z1 - z0 - 0.3)


# ================================================================ rooms against their walls

def furnished_last(fn):
    """A room is furnished once the whole building's walls are up (main() runs M.deferred after
    the level's builder), so what it hangs on a wall or stands by one can keep clear of every
    window and door (M.openings) -- whichever order the level builds its walls and rooms in."""
    def later(M, *args, **kw):
        M.deferred.append(lambda: fn(M, *args, **kw))
    later.__doc__ = fn.__doc__
    return later


def openings_on(M, p, q, lo, hi, pad=0.2):
    """The stretches (metres along the wall from p toward q -- two XY points on its inner face)
    where a window or door is between lo and hi above the floor, each grown by `pad`: where a
    piece hung there would cover it."""
    ux, uy = q[0] - p[0], q[1] - p[1]
    ln = math.hypot(ux, uy)
    ux, uy = ux / ln, uy / ln
    out = []
    for o in M.openings:
        dx, dy = o["c"][0] - p[0], o["c"][1] - p[1]
        if abs(dx * uy - dy * ux) > 0.45 or abs(o["u"][0] * ux + o["u"][1] * uy) < 0.9:
            continue  # on another wall
        if o["z1"] <= M.floor_z + lo or o["z0"] >= M.floor_z + hi:
            continue  # above or below the piece
        along = dx * ux + dy * uy
        out.append((along - o["w"] * 0.5 - pad, along + o["w"] * 0.5 + pad))
    return sorted(out)


def free_spans(M, p, q, s0, s1, lo, hi, minimum=0.7):
    """The stretches (start, end; metres along the wall from p toward q) between s0 and s1 that
    are clear of the wall's windows and doors from lo to hi above the floor, at least `minimum`
    long."""
    free, cur = [], s0
    for b0, b1 in openings_on(M, p, q, lo, hi):
        if b1 <= cur:
            continue
        if b0 >= s1:
            break
        if b0 > cur:
            free.append((cur, b0))
        cur = max(cur, b1)
    if cur < s1:
        free.append((cur, s1))
    return [(a, b) for a, b in free if b - a >= minimum]


def _without(s0, s1, spans):
    """The stretches of s0..s1 that none of `spans` ((a, b) along the same wall) covers."""
    out, at = [], s0
    for a, b in sorted(spans):
        if b <= at or a >= s1:
            continue
        if a > at:
            out.append((at, min(a, s1)))
        at = max(at, b)
    if at < s1:
        out.append((at, s1))
    return out


def clear_span(M, p, q, s0, s1, want, lo, hi, minimum=0.7, prefer=None):
    """Where a piece `want` wide (or narrower, down to `minimum`), lo..hi above the floor, can go
    on the wall from p to q between s0 and s1 metres along it, clear of its windows and doors:
    (centre, width) in the free stretch that fits it best nearest `prefer` (the middle of s0..s1
    unless given), or None."""
    free = free_spans(M, p, q, s0, s1, lo, hi, minimum)
    if not free:
        return None
    mid = (s0 + s1) * 0.5 if prefer is None else prefer
    a, b = min(free, key=lambda f: (f[1] - f[0] < want, abs(min(max(mid, f[0]), f[1]) - mid)))
    w = min(want, b - a)
    return min(max(mid, a + w * 0.5), b - w * 0.5), w


def doorways(M, r, depth=1.6):
    """The floor inside room `r` (x0, y0, x1, y1) in front of each of its doorways, `depth` deep
    and half a metre wider each side: rects to keep furniture out of."""
    x0, y0, x1, y1 = r
    out = []
    for o in M.openings:
        if not o["pass"]:
            continue
        cx, cy = o["c"]
        hw = o["w"] * 0.5 + 0.5
        if abs(o["u"][0]) > 0.9 and x0 - 0.5 <= cx <= x1 + 0.5:  # on a wall along x
            if abs(cy - y0) < 0.45:
                out.append((cx - hw, y0, cx + hw, y0 + depth))
            elif abs(cy - y1) < 0.45:
                out.append((cx - hw, y1 - depth, cx + hw, y1))
        elif abs(o["u"][1]) > 0.9 and y0 - 0.5 <= cy <= y1 + 0.5:  # on a wall along y
            if abs(cx - x0) < 0.45:
                out.append((x0, cy - hw, x0 + depth, cy + hw))
            elif abs(cx - x1) < 0.45:
                out.append((x1 - depth, cy - hw, x1, cy + hw))
    return out


def _clear_of(px, py, radius, rects):
    for a, b, c, d in rects:
        nx, ny = min(max(px, a), c), min(max(py, b), d)
        if math.hypot(px - nx, py - ny) < radius:
            return False
    return True


# ================================================================ rooms (furniture per tier)
# Each takes the room's floor rectangle (x0, y0, x1, y1) and where its door is ("+x", "-x",
# "+y", "-y" = which wall), and fills tiers 1..3. Spots are where staff work.

@furnished_last
def room_pro_shop(M, r, door):
    """Clear central entry aisle, wall apparel, shoe display and ordered club departments."""
    F = L.RoomFrame(r, door)
    W, D, z = F.W, F.D, M.floor_z
    near, far = -D / 2, D / 2
    M.roomboxes.append(("pro_shop", (*r, z)))
    for t in (1, 2, 3):
        B = M.room("pro_shop", t)
        x, y = F.p(W / 2 - 1.0, near + 1.25)
        cw, crz = 1.8 if t == 1 else 2.2, F.rz(math.pi / 2)
        L.pro_counter(B, x, y, z, cw, crz, 0.0)
        # the clerk square on the till (L.pro_counter's iMac, 0.3 of the counter along from its
        # middle), behind the counter facing over it: not off to its side (user)
        lx, ly = -cw * 0.3, -0.55
        M.spot("pro_shop", t, x + math.cos(crz) * lx - math.sin(crz) * ly, y + math.sin(crz) * lx + math.cos(crz) * ly, z, crz, "shop_clerk")
        # wall pieces only where the wall is clear of windows and doorways
        far_wall = (F.p(-W / 2, far), F.p(W / 2, far))
        side_wall = (F.p(-W / 2, near), F.p(-W / 2, far))
        fit = clear_span(M, *far_wall, .45, W * .58, W * .51, 0.1, 2.5, 1.0)
        apparel_lb = -W * .25
        if fit:
            apparel_lb = -W / 2 + fit[0]
            x, y = F.p(-W / 2 + fit[0], far - .08)
            L.slat_wall(B, x, y, z, fit[1], F.rz(math.pi), seed=t)
        # Shoulder-to-shoulder beside the bag riser, fronts angled slightly
        # outward into the shop. Keep the pair compact without touching sleeves.
        bag_count = 2 if t == 1 else 3
        display_lb = -W * .25 + (bag_count * .62 + .4) / 2 + .75
        display_la = .40
        for i, side in enumerate((-1, 1)):
            x, y = F.p(display_lb + side * .32, display_la)
            L.mannequin(B, x, y, z + .065, rz=F.rz(math.pi + side * math.radians(25)), seed=i)
        fit = clear_span(M, *far_wall, W * .6, W - .45, W * .35, 0.1, 2.5, 1.0)
        if fit:
            x, y = F.p(-W / 2 + fit[0], far - .08)
            L.slat_wall(B, x, y, z, fit[1], F.rz(math.pi), shirts=False, shoes=True)
        fit = clear_span(M, *side_wall, 1.4, 3.15, 1.5, 0.5, 2.2, 0.9)
        if fit:
            x, y = F.p(-W / 2 + .08, near + fit[0])
            L.hat_wall(B, x, y, z, fit[1], F.rz(-math.pi / 2), 3, t)
        if t >= 2:
            # Thin carpet lies above the retained timber floor.
            m = L.Matrix.Translation((F.cx, F.cy, z)) @ L.Matrix.Rotation(F.rz(), 4, "Z")
            B.box((W - 1.8, min(D - 3.0, 3.2), .018), (0, .2, .05), "carpet", matrix=m)
        x, y = F.p(-W * .25, .40)
        L.bag_display(B, x, y, z, F.rz(), 2 if t == 1 else 3, 0)
        if t >= 2:
            x, y = F.p(-W * .25, near + 2.1)
            L.promo_table(B, x, y, z, 1.3, .65, F.rz(), t)
        # Each rack has a single club family and a consistent model line.
        families = ("driver", "iron") if t == 1 else (("driver", "fairway", "iron", "putter") if t == 2 else ("driver", "fairway", "hybrid", "iron", "wedge", "putter"))
        # Reserve room for the single ball-sleeve endcap and a metre to the wall.
        left, right = 1.2, W / 2 - (2.0 if t >= 2 else 1.6)
        columns = max(1, int((right - left) / 1.0) + 1)
        stations = math.ceil(len(families) / 2)
        columns = min(columns, stations)
        rows = math.ceil(stations / columns)
        for i, family in enumerate(families):
            station = i // 2
            col, row = station % columns, station // columns
            lb = (left + right) / 2 if columns == 1 else left + col * (right - left) / (columns - 1)
            la = .25 if rows == 1 else near + 3.2 + row * (D - 4.9) / (rows - 1)
            la += .23 if i % 2 == 0 else -.23
            x, y = F.p(lb, la)
            L.club_rack(B, x, y, z, family, F.rz(0 if i % 2 == 0 else math.pi), n=6 if t < 3 else 8)
        x, y = F.p(-1.8, near + .7)
        L.ball_bin(B, x, y, z, .5)
        if t >= 2:
            # Dozen boxes stay on the wall (clear of its windows); the single sleeve stand caps
            # the far end of the club aisle, away from the counter
            fit = clear_span(M, *side_wall, 3.25, D - .75, 2.0, 0.0, 2.0, 1.0)
            if fit:
                x, y = F.p(-W / 2 + .08, near + fit[0])
                L.ball_cubby_wall(B, x, y, z, fit[1], F.rz(-math.pi / 2), t)
            first_lb = (left + right) / 2 if columns == 1 else left
            first_la = .25 if rows == 1 else near + 3.2
            x, y = F.p(first_lb - .72, first_la)
            L.ball_sleeve_tower(B, x, y, z, F.rz(math.pi / 2), t)
        M.spot("pro_shop", t, F.cx, F.cy, z, F.rz())

@furnished_last
def room_lockers(M, r, door, split_x=None, spa=True):
    """Restrooms (T1) -> Member Lockers (T2) -> VIP Spa Lockers (T3); two halves (men's and
    women's) split at split_x (along the door wall: x for a door on a y wall, y for one on an x
    wall), each entered at the middle of its door wall. From T2: lockers down the outer wall, a
    vanity on the back wall beside them, a bank of glass-fronted showers in the back corner by the
    dividing wall and a padded bench; T3 adds a sauna (one side) and a steam room (the other) in
    the front corner by the dividing wall, clear of the door -- unless not `spa`: the toilet
    stalls there instead."""
    z = M.floor_z
    M.roomboxes.append(("locker_rooms", (*r, z)))
    # laid out in the room's own frame -- u along the door wall, v toward it (door on a y wall: x
    # and y) -- and P() turns it onto the plan, rz + turn
    turn = {"-x": math.pi / 2, "+x": -math.pi / 2}.get(door, 0.0)
    c, s = math.cos(turn), math.sin(turn)

    def P(u, v):
        return (u * c - v * s, u * s + v * c)

    us = [r[0] * c + r[1] * s, r[2] * c + r[3] * s]
    vs = [-r[0] * s + r[1] * c, -r[2] * s + r[3] * c]
    x0, y0, x1, y1 = min(us), min(vs), max(us), max(vs)
    if door in ("-x", "+x"):
        door = "+y"
    sx = (split_x if turn >= 0.0 else -split_x) if split_x is not None else (x0 + x1) * 0.5
    halves = ((x0, sx), (sx, x1))
    back = y0 if door != "-y" else y1
    front = y1 if door != "-y" else y0
    sgn = 1 if door != "-y" else -1
    face = 0.0 if sgn > 0 else math.pi  # back to the back wall
    depth = abs(front - back)
    for t in (1, 2, 3):
        B = M.room("locker_rooms", t)
        spot_x = (x0 + sx) * 0.5
        for hi, (a, b) in enumerate(halves):
            hw = b - a
            outer, inner, toward = (a, b, 1) if hi == 0 else (b, a, -1)
            # each wall from the outer corner (or the dividing wall's), metres along it; every piece
            # on a wall goes only where the wall is clear of windows and doors
            back_wall = (P(outer, back), P(inner, back))
            side_wall = (P(outer, back), P(outer, front))
            front_wall = (P(inner, front), P(outer, front))
            side_rz = -math.pi / 2 if hi == 0 else math.pi / 2
            divide = (P(inner, back), P(inner, front))
            outer_front = (P(outer, front), P(inner, front))
            m = L.Matrix.Translation((*P((a + b) * 0.5, (y0 + y1) * 0.5), z + 0.05)) @ L.Matrix.Rotation(turn, 4, "Z")
            B.box((hw - 0.1, y1 - y0 - 0.1, 0.02), (0, 0, 0), "tile", matrix=m)

            def stalls(first, side_to, divide_from, divide_to):
                """The toilet stalls (one at least, every room: user): along the door wall in from
                the outer corner (from `first` m, short of the sauna or steam room; else right in
                the corner); else at the front end of the outer wall (past `side_to` m along it,
                where the door wall's clear of a doorway beside it); else on the dividing wall
                (`divide_from`..`divide_to` m along it). Where the last went on the dividing wall
                (m along it), or None."""
                fit = clear_span(M, *outer_front, first, hw - max(cabin, 0.3), 2.0, 0.0, 2.0, 1.0, first if spa else hw - 0.3)
                if not fit:
                    fit = clear_span(M, *outer_front, 0.05, hw - max(cabin, 0.3), 2.0, 0.0, 2.0, 1.0, 0.05)
                if fit:
                    in_corner[0] = fit[0] - fit[1] * 0.5 < 1.4
                    for i in range(max(1, int(fit[1] + 0.01))):
                        L.toilet_stall(B, *P(outer + toward * (fit[0] - fit[1] * 0.5 + 0.5 + i), front - sgn * 0.77), z, math.pi - face + turn)
                    return None
                fit = clear_span(M, *side_wall, side_to, depth - 0.05, 1.0, 0.0, 2.0, 1.0, depth - 0.55)
                if fit and free_spans(M, *outer_front, 0.0, 1.6, 0.0, 2.0, 1.6):
                    in_corner[0] = True
                    L.toilet_stall(B, *P(outer + toward * 0.77, back + sgn * fit[0]), z, side_rz + turn)
                    return None
                fit = clear_span(M, *divide, divide_from, divide_to, 1.0, 0.0, 2.0, 1.0, divide_to - 0.5)
                if fit:
                    L.toilet_stall(B, *P(inner - toward * 0.77, back + sgn * fit[0]), z, side_rz + math.pi + turn)
                    return fit[0] - 0.5
                return None

            cabin = 0.0
            in_corner = [False]  # stalls by the door wall in the outer corner
            if t == 1:
                fit = clear_span(M, *back_wall, 0.3, hw - 0.3, min(hw - 1.6, 2.0), 0.0, 2.2, 1.0, hw * 0.5 + 0.4)
                if fit:
                    L.vanity(B, *P(outer + toward * fit[0], back + sgn * 0.35), z, fit[1], face + turn)
                fit = clear_span(M, *side_wall, 0.3, depth - 0.3, 1.5, 0.0, 2.0, 1.5)
                if fit:
                    L.toilet_stall(B, *P(outer + toward * 0.6, back + sgn * fit[0]), z, side_rz + turn)
                else:
                    stalls(0.3, 0.3, 1.2, depth - 0.3)
                continue
            if t == 3 and spa and depth >= 6.0 and hw >= 3.6:  # (none in a room too small for one: L1's)
                fit = clear_span(M, *front_wall, 0.05, hw * 0.6, 1.9, 0.0, 2.3, 1.5, 0.0)
                if fit:
                    L.spa_cabin(B, *P(inner - toward * fit[0], front - sgn * 0.81), z, "SAUNA" if hi == 0 else "STEAM", math.pi - face + turn, w=fit[1], d=1.6)
                    cabin = fit[0] + fit[1] * 0.5 + 0.15
            # (short of the sauna or steam room's door, or of the stalls' doors by the door wall)
            divide_to = depth - (3.3 if cabin > 0.0 else 2.9)
            on_divide = stalls(0.7, depth - 1.85, 1.4, divide_to)
            if on_divide is not None:
                divide_to = on_divide
            # lockers down the outer wall, stopping short of the toilet stalls by the door wall (none
            # tucked in behind them), and down the dividing wall between the showers at its back
            # end and the sauna or steam room at its front (clear of its door): every door reachable
            # (full height down the whole of it, over its windows too -- clear only of its doors --
            # the stalls' doors kept clear by room to stand at them)
            wood = "wood" if t == 2 else "wood_dark"
            tall = 1.9 if t == 2 else 2.2  # (the spa's, taller: user)
            # (else on down to the door wall's corner, where the doorway's clear of it)
            side_from, side_to = 0.7, depth - 2.7
            if not in_corner[0] and free_spans(M, *outer_front, 0.0, 0.9, 0.0, 2.0, 0.9):
                side_to = depth - 0.05
            elif not in_corner[0]:
                # (the doorway in that corner, not stalls: the bank slid along to the middle of the
                # wall, over its window if need be, short of room to step in at the doorway: user)
                slide = min(max(depth * 0.5 - (side_from + side_to) * 0.5, 0.0), 1.1)
                side_from, side_to = side_from + slide, side_to + slide
            for s0, s1 in free_spans(M, *side_wall, side_from, side_to, 0.0, 0.8, 1.0):
                L.lockers(B, *P(outer + toward * 0.35, back + sgn * (s0 + s1) * 0.5), z, s1 - s0, side_rz + turn, wood, tall)
            # (short of the sauna or steam room by room to stand at its door: its 1.6 m and 1.5 more)
            # (from clear of the showers' doors at its back end: their 1.05 m and room to step out)
            for s0, s1 in free_spans(M, *divide, 1.05 + 1.3, divide_to, 0.0, 0.8, 1.0):
                L.lockers(B, *P(inner - toward * 0.35, back + sgn * (s0 + s1) * 0.5), z, s1 - s0, side_rz + math.pi + turn, wood, tall)
            vw = min(2.0, max(1.2, hw - 3.0))
            n = max(1, min(3, int((hw - 0.75 - vw - 0.3) / 0.95)))
            # the showers in the clear stretch of the back wall nearest the dividing wall
            shower_from = hw
            spans = free_spans(M, *back_wall, 0.75, hw - 0.02, 0.0, 2.2, 0.95)
            if spans:
                s0, s1 = max(spans, key=lambda f: f[1])
                n = min(n, int((s1 - s0) / 0.95))
                shower_from = s1 - n * 0.95
                L.shower_stalls(B, *P(outer + toward * (s1 - n * 0.475), back), z, n * 0.95, n, face + turn)
            fit = clear_span(M, *back_wall, 0.75, shower_from - 0.3, vw, 0.0, 2.2, 1.0, 0.75)
            if fit:
                vx = outer + toward * fit[0]
                L.vanity(B, *P(vx, back + sgn * 0.35), z, fit[1], face + turn, lights=t == 3)
                if hi == 0:
                    spot_x = vx
            if hw >= 5.0 and depth >= 6.0:
                # (down the room, from the showers toward the door: user)
                L.locker_bench(B, *P((a + b) * 0.5, (back + front) * 0.5 + sgn * 0.3), z, min(2.0, depth * 0.3), math.pi / 2 + turn)
            else:
                # (a smaller room: no bench out in the middle of it, one against the dividing wall
                # where the lockers have left it clear, else none)
                taken = free_spans(M, *divide, 1.05 + 1.3, divide_to, 0.0, 0.8, 1.0)
                for s0, s1 in _without(1.05 + 0.4, depth - 1.9, taken):
                    if s1 - s0 >= 1.4:
                        L.locker_bench(B, *P(inner - toward * 0.3, back + sgn * (s0 + s1) * 0.5), z, min(s1 - s0 - 0.2, 1.6), math.pi / 2 + turn)  # (along the wall)
                        break
            if t == 3:
                # the VIP tier changes the room, sauna or not (user): dark wood panelling to dado
                # height on the outer, dividing and door walls (clear of their doorways and
                # windows) and a carpet runner down the middle from the showers to the stalls
                for (u0, v0), (u1, v1), face_off, thick in (((outer, back), (outer, front), -0.03, 0.08),
                                                            ((inner, back), (inner, front), 0.1, 0.05),
                                                            ((outer, front), (inner, front), -0.03, 0.08)):
                    ln = math.hypot(u1 - u0, v1 - v0)
                    du, dv = (u1 - u0) / ln, (v1 - v0) / ln
                    nu, nv = (toward if u0 == outer else -toward, 0.0) if u0 == u1 else (0.0, -sgn)  # (into the room)
                    for s0, s1 in free_spans(M, P(u0, v0), P(u1, v1), 0.0, ln, 0.0, 1.1, 0.3):
                        mid = (s0 + s1) * 0.5
                        m = L.Matrix.Translation((*P(u0 + du * mid + nu * face_off, v0 + dv * mid + nv * face_off), z)) @ L.Matrix.Rotation(math.atan2(dv, du) + turn, 4, "Z")
                        B.box((s1 - s0, thick, 1.08), (0, 0, 0.6), "wood_dark", matrix=m)
                        B.box((s1 - s0, thick + 0.03, 0.05), (0, 0, 1.16), "wood_dark", bevel=0.01, matrix=m)  # (its cap rail)
                r0, r1 = back + sgn * (1.05 + 0.5), front - sgn * 1.7
                if abs(r1 - r0) >= 1.0:
                    m = L.Matrix.Translation((*P((a + b) * 0.5, (r0 + r1) * 0.5), z + 0.068)) @ L.Matrix.Rotation(turn, 4, "Z")
                    B.box((min(0.9, hw - 2.4), abs(r1 - r0), 0.012), (0, 0, 0), "carpet", matrix=m)
        M.spot("locker_rooms", t, *P(spot_x, back + sgn * 1.15), z, math.pi - face + turn)


@furnished_last
def room_lobby(M, r, door, rug=True, desk="right"):
    """Front Desk (T1) -> Members' Lobby (T2) -> Guest Reception (T3); from T2 a carpet over the
    floor, unless `rug` is False. The front desk on the back wall at its `desk` ("right" / "left")
    end, slid in toward the middle off a doorway's floor."""
    x0, y0, x1, y1 = r
    z = M.floor_z
    M.roomboxes.append(("lobby", (x0, y0, x1, y1, z)))
    cx = (x0 + x1) * 0.5
    keep = doorways(M, r, 1.8)
    for t in (1, 2, 3):
        B = M.room("lobby", t)
        if t >= 2 and rug:
            L.rug(B, x0 + 0.8, y0 + 0.8, x1 - 0.8, y1 - 0.8, z, "carpet")
        # the front desk by the right-hand wall (or the left), slid in toward the middle off a
        # doorway's floor
        desk_w = 1.8 if t == 1 else 2.6
        side = 1 if desk == "right" else -1
        dx = cx + side * ((x1 - x0) * 0.5 - 2.0)
        while side * (dx - cx) - desk_w * 0.5 > 0 and not _clear_of(dx + side * desk_w * 0.5, y0 + 1.1, 0.45, keep):
            dx -= side * 0.25
        L.counter(B, dx, y0 + 1.1, z, desk_w, body="wood_dark" if t == 3 else "wood")
        L.imac(B, dx, y0 + 1.08, z + 1.0, math.pi)  # the receptionist's computer, facing them
        M.spot("lobby", t, dx, y0 + 0.5, z, 0.0, "receptionist")
        if _clear_of(x1 - 0.6, y1 - 0.6, .3, keep):
            L.plant(B, x1 - 0.6, y1 - 0.6, z)
        if t == 1:
            if _clear_of(x0 + 1.0, (y0 + y1) * .5, .8, keep):
                L.bench(B, x0 + 1.0, (y0 + y1) * .5, z, -math.pi / 2)
        else:
            mat = "leather_green" if t == 2 else "leather"
            for sy in (y1 - 1.0, y1 - 2.6):
                if _clear_of(x0 + 1.0, sy, .7, keep):
                    L.armchair(B, x0 + 1.0, sy, z, mat, -math.pi / 2)
            if _clear_of(x0 + 2.1, y1 - 1.8, .6, keep):
                L.table(B, x0 + 2.1, y1 - 1.8, z, .8, .6, .45)
            # (on the wall the desk's end is: the other side may be open onto the next room)
            case_x = x1 - 0.5 if desk == "right" else x0 + 0.5
            if _clear_of(case_x, (y0 + y1) * 0.5, .4, keep):
                L.display_case(B, case_x, (y0 + y1) * 0.5, z, 1.2, 0.5, 1.1, math.pi / 2 * side)
            if t == 3:
                if _clear_of(x0 + 0.6, y1 - 0.6, .3, keep):
                    L.plant(B, x0 + 0.6, y1 - 0.6, z)
                L.chandelier(B, cx, (y0 + y1) * 0.5, z + 3.2)


# ================================================================ clubhouse levels

def clubhouse_l1(M):
    """Serviceable: a Cape Cod with a gabled entry portico, two dormers, pro shop, restrooms
    and a members' lobby; a brick side patio and a gravel cart pad."""
    plot_lawn(M, "clubhouse")
    L.us_flag(M.g["BASE"], -3.0, 0.0, LEVEL, 9.0)
    B, G, R = M.g["BASE"], M.g["WALLS_HIGH"], M.g["ROOF"]
    x0, x1, y0, y1 = -8.0, 8.0, -24.0, -14.0
    H = 3.2
    z = M.floor_z

    def win(at, w=1.0):
        return {"at": at, "w": w, "sill": 0.85, "head": 2.35, "kind": "window"}

    L.foundation(M, x0, y0, x1, y1)
    L.floor(M, x0, y0, x1, y1, "wood_floor")
    # front runs from x1 toward x0 ("at" measured from x1)
    L.shell(M, x0, y0, x1, y1, H,
            front_openings=[win(2.4), win(4.7), door(8.0, 1.8, 2.4, mat="entry_glass", double=True), win(11.3), win(13.6)],
            back_openings=[french(3.0, 1.6)],  # none behind the restrooms
            left_openings=[win(3.0), win(7.0)],
            right_openings=[win(5.0), french(7.0, 1.6)])
    stoop(M, x1, -17.0, "+x", 1.6, path=0)  # down to the side patio
    # partitions: pro shop | lobby; restrooms behind the lobby
    L.wall(M, (-1.6, y0), (-1.6, y1), H, openings=[{"at": 6.8, "w": 2.2, "kind": "open", "head": 2.6}], thick=0.15)
    L.wall(M, (-1.6, -20.0), (x1, -20.0), H, openings=[{"at": 2.4, "w": 0.95, "kind": "door", "head": 2.2, "door": "door_wood"}, {"at": 7.2, "w": 0.95, "kind": "door", "head": 2.2, "door": "door_wood"}], thick=0.15)
    L.wall(M, (3.2, y0), (3.2, -20.0), H, thick=0.15)
    # roof, gables, dormers
    L.gable_wall(R, 16.0, 10.0, 5.4, (0, -19.0), z + H, "shingle")
    L.gable_roof(R, 16.0, 10.0, 5.4, (0, -19.0), z + H, over=0.5)
    for dx in (-4.0, 4.0):
        L.dormer(M, dx, y1 - 1.6, z + H + 0.5)
    # gabled entry portico
    for dx in (-1.25, 1.25):
        L.column(G, dx, y1 + 2.0, z, 2.9, 0.16)
    B.box((3.4, 2.4, z - M.ground_z), (0, y1 + 1.2, M.ground_z + (z - M.ground_z) * 0.5), "brick")
    B.box((3.5, 2.5, 0.06), (0, y1 + 1.2, z - 0.02), "stone")
    R.box((3.4, 2.6, 0.3), (0, y1 + 1.2, z + 3.05), "trim")
    L.gable_wall(R, 2.6, 3.4, 1.3, (0, y1 + 1.2), z + 3.2, "trim", ridge="y")
    L.gable_roof(R, 2.8, 3.4, 1.3, (0, y1 + 1.3), z + 3.2, ridge="y", over=0.25)
    steps_end = y1 + 2.4 + L.stairs(B, 0, y1 + 2.4, z, M.ground_z, 2.6)
    # rooms
    room_pro_shop(M, (x0 + 0.15, y0 + 0.15, -1.7, y1 - 0.15), "+x")
    room_lockers(M, (-1.5, y0 + 0.15, x1 - 0.15, -20.1), "+y", split_x=3.2)
    room_lobby(M, (-1.5, -19.9, x1 - 0.15, y1 - 0.15), "+y")
    # grounds: beds, walk, patio, cart pad
    L.flower_bed(B, x0 + 0.3, -1.9, y1 + 0.8, M.ground_z, seed=1)
    L.flower_bed(B, 1.9, x1 - 0.3, y1 + 0.8, M.ground_z, seed=3)
    L.pave(B, -1.2, steps_end - 0.05, 1.2, 42.0, LEVEL, "stone")  # the walk from the foot of the front steps
    L.pave(B, x1, -22.5, x1 + 8.0, -15.5, LEVEL, "patio_brick")
    back_walk(M, -5.0, y0, 6.4, 3.0, 2, 1)
    cart_line(M, 3.4, -0.6, [-39.4, -36.4, -33.4, -30.4], -28.4)  # (its head the left row, by the cart path: taken from first, user)
    club_monument(M, 5.2, 37.0)
    for i, (px, py) in enumerate(((10.9, -21.0), (14.1, -20.6), (13.5, -17.3))):
        L.umbrella_table(B, px, py, LEVEL, ("cloth_cream", "cloth_green", "cloth_cream")[i])
    for p, q in (((x1, -15.5), (x1 + 8, -15.5)), ((x1 + 8, -15.5), (x1 + 8, -22.5))):
        L.railing(G, p, q, LEVEL, 0.85, "white", 2.0, 0.6)
    # (no cart parking out front: the club's carts wait in the line behind it; user)
    # the cart boy's shortcut (user): a cart path from the line behind the clubhouse, along its back,
    # down the patio side outside its rail, and along the front to the walk
    # (ClubLife.FRONT_DRIVE[1] keeps to it)
    cart_path(B, [(4.7, -39.8), (18.4, -39.8), (18.4, -1.7), (1.2, -1.7)], 14.0)  # (bends swept wide as a running track's: user)
    L.shrub(B, x0 - 1.2, y1 + 0.2, LEVEL, 0.9)
    L.shrub(B, x0 - 1.5, y0 + 1.0, LEVEL, 1.0)
    for dx in (-3.0, 3.0):
        L.lamp(B, dx, 2.0, LEVEL)
    front_lawn(M, (-6.0, 8.0), (7.0, 14.0), [(s_ * 2.6, py) for py in (8.0, 15.0, 22.0, 29.0) for s_ in (-1, 1)])  # (palms along the walk)
    M.cols += [("main", (16.6, 10.6, 9.0), (0, -19.0, z + 4.5)), ("portico", (3.4, 2.4, 3.2), (0, y1 + 1.2, z + 1.6))]


@furnished_last
def room_restaurant(M, r, kitchen, back_doors=()):
    """A back-wall bar, a separate dining row and a continuous service aisle; the kitchen behind it
    (back_doors: [(x, width)] of doors in its back wall, kept clear)."""
    x0, y0, x1, y1 = r
    k0, ky0, k1, ky1 = kitchen
    z = M.floor_z
    M.roomboxes += [("restaurant", (*r, z)), ("restaurant__kitchen", (*kitchen, z))]
    w, d, kw, kd = x1-x0, y1-y0, k1-k0, ky1-ky0
    for t in (1, 2, 3):
        B = M.room("restaurant", t)
        B.box((kw-.1, kd-.1, .02), ((k0+k1)/2, (ky0+ky1)/2, z+.05), "tile")
        # the Altesheim kitchen pieces (tools/blender/kitchen_layout.py: Godot swaps each marker for
        # its model in assets/facilities/props/altesheim)
        fixtures, chefs = KL.layout(kitchen, t, back_doors)
        for kind, kx, ky, krz in fixtures:
            B.marker("KITCHEN_" + kind, kx, ky, z, krz, 1.0)
        for cx, cy, face in chefs:
            M.spot("restaurant", t, cx, cy, z, face, "chef")
        # A continuous bar replaces the cramped row of dining tables.
        bw = w - 3.5
        bx, by = x0 + 1.75 + bw/2, y0 + 1.65
        L.bar_counter(B, bx, by, z, bw, stools=True)
        B.marker("BAR_LENGTH", bx, by, z, 0, bw)
        n = int(bw / 0.75)  # (L.bar_counter's stools)
        for i in range(n):  # golfers in after their round: up on a stool, facing the bar
            M.spot("restaurant", t, bx - bw * 0.5 + (i + 0.5) * bw / n, by + 0.75, z + 0.2, math.pi, "guest_bar")
        # the bar TVs: as big as fits (up to 1.3 m across) between the top of the bottle shelves
        # (L.bar_counter's: 2.80 m up) and the top of the wall
        tv_b = 0.015
        tv_w = min(1.3, (M.eave - 0.05 - 2.84 - 2 * tv_b) * 16.0 / 9.0 + 2 * tv_b)
        tv_z = z + 2.84 + L.tv_height(tv_w, tv_b) * 0.5
        for i in range(2 if bw>7 else 1):
            px = bx + (i-.5)*(bw*.5) if bw>7 else bx
            L.tv(B, px, y0+.14, tv_z, tv_w, on=False, b=tv_b)  # (its picture is Godot's: no screen of its own to fight it)
            if i == 0:  # the user's golf on the first (TV_CLIP: Godot plays it on the screen's face)
                B.marker("TV_CLIP", px, y0+.14+.015, tv_z, 0.0, tv_w-2*tv_b)  # (on the screen's face, inside the bezel: L.tv)
            else:  # and the user's video on the other (TV_VIDEO)
                B.marker("TV_VIDEO", px, y0+.14+.015, tv_z, 0.0, tv_w-2*tv_b)
        M.spot("restaurant", t, bx, by-.8, z, 0, "bartender")
        L.rug(B, x0+.6, y0+3.15, x1-.6, y1-.35, z, "carpet")
        # Short high tables on the piers between the front windows. Stools stay
        # on their sides, keeping the supplied stools clear of the continuous bar aisle.
        window_gaps = {
            "clubhouse_l2": [-13.5, -10.4, -7.4],
            "clubhouse_l3": [9.5, 12.5, 15.5, 18.4],
            "clubhouse_l4": [10.75, 13.85, 16.95, 20.05],
        }.get(M.C.name, [])
        depth = min(1.55, y1 - (by + 0.99) - 1.15 - 0.03)
        if depth >= 0.75:
            count = min(len(window_gaps), t + (1 if len(window_gaps) >= 4 else 0))
            for px in window_gaps[:count]:
                cy = y1 - 0.05 - depth / 2
                # Rounded oak top, central steel pedestal and broad stable foot.
                B.box((0.90, depth, 0.07), (px, cy, z + 1.045), "bar_oak", bevel=0.035)
                B.cyl(0.055, 0.055, 1.01, (px, cy, z + 0.03), "chrome", segs=12)
                B.cyl(0.36, 0.38, 0.055, (px, cy, z + 0.065), "chrome", segs=32)
                B.marker("HIGH_TABLE", px, cy, z, 0.0, depth)
                # Two compact stools on each side; their feet stay within the
                # table's depth so neither end projects into the service aisle.
                pitch = min(0.88, depth - 0.46)
                for side in (-1, 1):
                    sx = px + side * 0.77
                    for along in (-0.5, 0.5):
                        sy = cy + along * pitch
                        L.restaurant_wood_stool(B, sx, sy, z, side * math.pi / 2)
                        M.spot("restaurant", t, sx, sy, z + 0.265, side * math.pi / 2, "guest_bar")
        # Keep both ends of the counter open for service and through traffic.
        M.spot("restaurant", t, x0+1.1, y0+3.5, z, 0, "waiter")
        for i in range(max(2,int(bw/3.0))):
            px = bx-bw*.38+i*bw*.76/max(1,max(2,int(bw/3.0))-1)
            L.chandelier(B, px, by+1.25, z+3.5)
        L.plant(B, x1-.5, y1-.5, z, 1.1)


@furnished_last
def room_office(M, r):
    """Desk zone at the rear, entry aisle clear, meeting area only where it fits."""
    x0,y0,x1,y1=r;z=M.floor_z;w,d=x1-x0,y1-y0
    M.roomboxes.append(("office", (*r,z)))
    for t in (1,2,3):
        B=M.room("office",t)
        dx=(x0+x1)/2 if w<5 else x1-1.65
        # (the desk's sitter, its screen and drawers at its local -Y: toward the chair -- its modesty
        # panel out to the room)
        L.desk(B,dx,y0+1.35,z,1.6 if w<5 or t<3 else 2.1,0.0,top="wood_dark" if t==3 else "wood")
        L.office_chair(B,dx,y0+.55,z)
        M.spot("office",t,dx,y0+.55,z,0.0)
        M.spot("office",t,dx,y0+.55,z,0.0,"golf_pro_desk")  # a golf pro sat at the desk, facing it (the bookings)
        if t>=2:
            if w>=5 and d>5.5:
                L.table(B,x1-1.65,y1-1.5,z,1.8,.7)
                for sx in (-.5,.5):
                    for sy in (-.68,.68):
                        L.chair(B,x1-1.65+sx,y1-1.5+sy,z,math.pi if sy<0 else 0,"black","black")
            else:
                for sx in (-.78,.78):
                    L.chair(B,dx+sx,y0+2.65,z,math.pi,"black","black")
            L.bookshelf(B,x0+.25,y0+1.15,z,1.4,2.0,-math.pi/2)
        B.box((.5,.6,1.3),(x0+.45,y1-.5,z+.65),"grey")
        if t==3:
            L.rug(B,x0+.8,y0+.8,x1-.8,y1-.8,z)

@furnished_last
def room_ballroom(M, r):
    """Function Room (T1) -> Ballroom (T2) -> Grand Convention Center (T3)."""
    x0, y0, x1, y1 = r
    z = M.floor_z
    M.roomboxes.append(("ballroom", (x0, y0, x1, y1, z)))
    w, d = x1 - x0, y1 - y0
    for t in (1, 2, 3):
        B = M.room("ballroom", t)
        sw = min(w * 0.4, 6.0 + t)
        L.stage(B, (x0 + x1) * 0.5 - sw * 0.5, y0 + 0.3, (x0 + x1) * 0.5 + sw * 0.5, y0 + 2.2, z, 0.5 + 0.1 * t)
        M.spot("ballroom", t, (x0 + x1) * 0.5, y0 + 1.2, z + 0.5 + 0.1 * t, 0.0)
        if t == 1:
            for j in range(max(int((d - 3.5) / 1.8), 1)):
                if M.name == "clubhouse_l3" and y1-5.2 < y0+3.6+j*1.8 < y1-1.4:
                    continue
                if abs(y0 + 3.6 + j * 1.8 - (y0+y1)/2) < 1.1:
                    continue
                L.table(B, (x0 + x1) * 0.5, y0 + 3.6 + j * 1.8, z, min(w - 2.0, 8.0), 0.8, cloth=True)
        else:
            # Banquet seating in rows behind the dance floor; full chair
            # footprints retain broad aisles, including the door on the side.
            dance = (x0+x1)*.5
            B.box((4.4,3.4,.025),(dance,y0+4.2,z+.055),"wood_light")
            keep = [(dance-sw/2,y0,dance+sw/2,y0+2.6),
                    (dance-2.2,y0+2.5,dance+2.2,y0+5.9)]
            if t==3:
                keep.append((x1-3.7,y0+.4,x1,y0+5.7))
            keep += doorways(M,r,1.2)
            if M.name == "clubhouse_l3":
                # A continuous public corridor between reception and the west shop.
                keep.append((x0,y1-4.85,x1,y1-1.85))
            cols = max(1,int((w-4.0)/4.3)+1)
            rows = max(1,int((d-9.2)/4.3)+1)
            gx = (x0+x1-(cols-1)*4.3)*.5
            # Fill the available rear half rather than rejecting an entire
            # sparse room-wide grid around the stage and dance floor.
            y_start = y0+7.35
            y_end = y1-2.0
            if M.name == "clubhouse_l3":
                # Two tables beside the stage keep the cross-room shop corridor open.
                seating = [(x0+2.85,y0+2.35),(x0+2.85,y0+6.75)]
            else:
                seating = [(gx+i*4.3,(y_start+y_end)*.5 if rows==1 else y_start+j*(y_end-y_start)/(rows-1)) for j in range(rows) for i in range(cols)]
            for px,py in seating:
                if not _clear_of(px,py,1.55,keep):
                    continue
                L.round_table(B,px,py,z,.85,True,8,"brass","cloth_cream")
                B.marker("BANQUET_TABLE",px,py,z,0,1.0)
                # A deep green runner, gold chargers and floral centre.
                B.box((.36,1.55,.009),(px,py,z+.748),"cloth_green")
                for side in (-1,1):
                    B.cyl(.045,.045,.19,(px+side*.32,py,z+.75),"brass",segs=10)
                    B.ball(.025,(px+side*.32,py,z+.96),"bulb",subdiv=1)
            # A short reception bar fits beside the stage, freeing the rear
            # seating area; its back bar sits against the side wall.
            if t==3:
                L.bar_counter(B,x1-1.75,y0+3.4,z,3.2,math.pi/2,stools=False)
                M.spot("ballroom",t,x1-.85,y0+3.4,z,math.pi/2)
            for i in range(3):
                for j in range(2):
                    L.chandelier(B,x0+w*(.22+i*.28),y0+d*(.37+j*.38),z+3.4)
        # Presentation stage: framed retractable screen, curtains and AV gear.
        screen_w = min(4.6,sw-.65)
        screen_h = screen_w*9/16
        stage_h = .5+.1*t
        screen_bottom = z+stage_h+.23
        scx = (x0+x1)/2
        scz = screen_bottom+screen_h/2
        B.box((sw+.3,.10,3.35),(scx,y0+.19,z+1.675),"cloth_navy")
        for side in (-1,1):
            # Folded side curtains stay outside the projection surface.
            for fold in range(4):
                B.cyl(.07,.07,3.35,(scx+side*(sw/2-.05-fold*.13),y0+.30,z),"cloth_navy",segs=8)
        B.box((screen_w+.16,.10,screen_h+.16),(scx,y0+.38,scz),"black")
        B.box((screen_w,.025,screen_h),(scx,y0+.445,scz),"cloth_white")
        B.box((screen_w+.25,.19,.14),(scx,y0+.38,screen_bottom+screen_h+.13),"white",bevel=.025)
        B.marker("PROJECTOR_SCREEN",scx,y0+.45,scz,0,screen_w)
        # Lens faces the screen from the suspended projector.
        B.box((.06,.06,.35),(scx,y0+7.0,z+3.6),"steel")
        B.box((.5,.36,.18),(scx,y0+7.0,z+3.35),"white",bevel=.025)
        B.cyl(.065,.065,.04,(scx+.13,y0+6.79,z+3.35),"tv",segs=14,rx=math.pi/2)
        for side in (-1,1):
            px=scx+side*(sw/2+.55)
            B.box((.48,.42,1.2),(px,y0+.85,z+1.1),"charcoal",bevel=.025)
            for speaker_z in (.82,1.30):
                B.cyl(.13,.13,.025,(px,y0+1.075,z+speaker_z),"black",segs=16,rx=math.pi/2)
            L.plant(B,px,y0+2.0,z,1.8,"brass")
        # Small corner foliage and wall art dress the perimeter, not the aisles.
        for px in (x0+.55,x1-.55):
            L.plant(B,px,y1-.55,z,1.6,"brass")
        for a,b in free_spans(M,(x0,y1),(x1,y1),.7,w-.7,.8,2.7,1.5):
            L.picture(B,x0+(a+b)/2,y1-.16,z+1.95,min(1.5,b-a-.2),.85,"-y","cloth_green")
        M.spot("ballroom", t, (x0 + x1) * 0.5 + 2.0, (y0 + y1) * 0.5, z, 0.0)


@furnished_last
def room_lounge(M, r):
    """Display Case (T1) -> Trophy Lounge (T2) -> Hall of Fame Gallery (T3)."""
    x0, y0, x1, y1 = r
    z = M.floor_z
    M.roomboxes.append(("lounge", (x0, y0, x1, y1, z)))
    w, d = x1 - x0, y1 - y0
    keep = doorways(M, r, 1.8)  # the floor in front of each doorway stays clear
    for t in (1, 2, 3):
        B = M.room("lounge", t)
        # the trophy case on the back wall, in a stretch clear of its doors and windows
        fit = clear_span(M, (x0, y0), (x1, y0), 0.4, w - 0.4, min(w - 2.0, 2.4), 0.0, 2.2, 1.2)
        cx = x0 + fit[0] if fit else (x0 + x1) * 0.5
        if fit:
            L.display_case(B, cx, y0 + 0.5, z, fit[1], 0.6, 1.3)
            n = min(3 + t, int(fit[1] / 0.4))
            for i in range(n):
                L.trophy(B, cx - (n - 1) * 0.2 + i * 0.4, y0 + 0.5, z + 1.31, 1.2)
        for ax, rz in ((x0 + 1.2, -math.pi / 2), (x1 - 1.2, math.pi / 2)):
            if _clear_of(ax, (y0 + y1) * 0.5, 0.6, keep):
                L.armchair(B, ax, (y0 + y1) * 0.5, z, "leather", rz)
                lounge_seat(M, t, ax, (y0 + y1) * 0.5, z, rz, 0.0)
        if _clear_of((x0 + x1) * 0.5, (y0 + y1) * 0.5, 0.7, keep):
            L.table(B, (x0 + x1) * 0.5, (y0 + y1) * 0.5, z, 1.0, 0.7, 0.45)
        M.spot("lounge", t, cx + 1.0, y0 + 1.3, z, 0.0)
        if t >= 2:
            L.rug(B, x0 + 0.7, y0 + 1.2, x1 - 0.7, y1 - 0.7, z, "carpet")
            fit = clear_span(M, (x0, y0), (x0, y1), 1.0, d - 1.0, 1.8, 0.0, 1.6, 1.8)
            if fit:
                L.fireplace(B, x0 + 0.05, y0 + fit[0], z, "+x")
            if _clear_of(x1 - 1.0, y1 - 2.0, 1.3, keep):
                L.sofa(B, x1 - 1.0, y1 - 2.0, z, 2.4, "leather_green", math.pi / 2)
                for px in (-0.667, 0.0, 0.667):  # (its three cushions)
                    lounge_seat(M, t, x1 - 1.0, y1 - 2.0, z, math.pi / 2, px)
            fit = clear_span(M, (x1, y0), (x1, y1), 0.3, d * 0.55, min(d * 0.4, 2.4), 0.0, 2.3, 1.0)
            if fit:
                L.bookshelf(B, x1 - 0.2, y0 + fit[0], z, fit[1], 2.2, math.pi / 2, 2)
        if t == 3:
            gaps = openings_on(M, (x0, y1), (x1, y1), 1.3, 2.5)
            for i in range(int((w - 1.0) / 1.2)):
                s = 0.9 + i * 1.2
                if any(s + 0.45 > b0 and s - 0.45 < b1 for b0, b1 in gaps):
                    continue  # a doorway or window there: no picture in mid-air
                L.picture(B, x0 + s, y1 - 0.15, z + 1.7, 0.8, 0.6, "-y", ("cloth_tan", "cloth_sky", "cloth_green")[i % 3])
                B.ball(0.06, (x0 + s, y1 - 0.35, z + 2.4), "bulb", subdiv=1)
            for px in (x0+1.0, x1-1.0):
                if _clear_of(px, y0 + 1.0, 0.4, keep):
                    B.box((0.5, 0.5, 1.0), (px, y0+1.0, z + 0.5), "white")
                    L.trophy(B, px, y0+1.0, z + 1.0, 2.0)


def lounge_seat(M, t, x, y, z, rz, along, room="lounge", role="guest_seat"):
    """A seat on an L.sofa / L.armchair at (x, y) turned rz, in `room`, for `role` (a guest's by
    default): on the cushion `along` its width, facing out the way it does."""
    c, s = math.cos(rz), math.sin(rz)
    M.spot(room, t, x + along * c - 0.1 * s, y + along * s + 0.1 * c, z, rz, role)


# a gym member's place on each kind of machine: how they use it, and how high they stand
GYM_USE = {"treadmill": ("guest_gym_run", 0.2), "elliptical": ("guest_gym_elliptical", 0.35), "spin_bike": ("guest_gym_ride", 0.45),
           "bench_flat": ("guest_gym_sit", 0.0), "bench_incline": ("guest_gym_sit", 0.0), "mat": ("guest_gym_stretch", 0.02)}


@furnished_last
def room_spa(M, r):
    """Gym (T1) -> Wellness Studio (T2) -> Day Spa (T3)."""
    x0, y0, x1, y1 = r
    z = M.floor_z
    M.roomboxes.append(("spa_fitness", (x0, y0, x1, y1, z)))
    w, d = x1 - x0, y1 - y0
    # the gym (the user's machines, L.gym_piece): cardio facing the mirrored back wall, the
    # bench racks behind them, the dumbbell rack against the right wall, all on rubber flooring;
    # the door in from the clubhouse (left wall, mid-room) kept clear
    for t in (1, 2, 3):
        B = M.room("spa_fitness", t)
        deep = d if t == 1 else d * 0.45  # the gym's rubber floor: the whole room, later the back
        B.box((w - 0.1, deep, 0.02), ((x0 + x1) * 0.5, y0 + deep * 0.5, z + 0.05), "charcoal")
        def at(pid, a, b, rz=0.0):  # on the rubber where it's laid, else on the floor
            zz = z + 0.06 if b < deep else z
            L.gym_piece(B, pid, x0 + a, y0 + b, zz, rz)
            if pid in GYM_USE:  # a member's place on it, facing its front
                M.spot("spa_fitness", t, x0 + a, y0 + b, zz + GYM_USE[pid][1], rz, GYM_USE[pid][0])

        B.box((w - 0.4, 0.03, 1.8), ((x0 + x1) * 0.5, y0 + 0.015, z + 1.3), "mirror")  # (flat on the back wall)
        for pid, a, b in (("treadmill", 0.9, 1.45), ("treadmill", 2.15, 1.45), ("elliptical", 3.45, 1.35),
                          ("spin_bike", 4.75, 1.05), ("spin_bike", 5.65, 1.05)):
            at(pid, a, b, math.pi)
        at("bench_flat", 1.5, 4.35)
        at("bench_incline", 4.4, 4.35)
        at("plate_tree", 6.3, 3.6)
        L.weight_rack(B, x1 - 0.36, y0 + 3.4, z + 0.06, math.pi / 2)  # back to the wall
        for k in range(3):
            at("kettlebell", 8.55 + k * 0.28, 5.0, k * 0.7)
        # members' places for the weights (user: dumbbell work by the dumbbell rack, kettlebell
        # swings by the kettlebells -- the mats only for sit-ups): stood in front of the rack, and
        # beside the kettlebells, facing the mirror on the back wall
        for b in (2.9, 3.9):
            M.spot("spa_fitness", t, x1 - 1.25, y0 + b, z + 0.06, math.pi, "guest_gym_weights")
        M.spot("spa_fitness", t, x0 + 8.8, y0 + 5.75, z + 0.06, math.pi, "guest_gym_kettlebell")
        M.spot("spa_fitness", t, x1 - 1.7, y0 + 4.5, z, math.pi / 2)
        if t == 1:
            # the front of the room is gym too: a stretching corner (yoga mats, yoga balls and
            # kettlebells), the adjustable rack, the preacher bench and cable station
            at("mat", 1.25, 9.7)
            at("mat", 2.85, 9.7)
            at("mat", 4.45, 9.7)
            at("gym_ball", 1.0, 11.75)
            at("gym_ball", 2.0, 11.7)
            for k in range(2):
                at("kettlebell", 3.3 + k * 0.3, 11.8, k * 0.9)
            at("bench_adjustable", 4.6, 7.95)
            at("preacher_curl", 7.2, 8.0)
            at("cable_station", 8.85, 10.9, math.pi / 2)
        if t >= 2:
            # a stretching studio up front: mats clear of the door
            for i in range(6):
                B.box((0.7, 1.8, 0.02), (x0 + 0.9 + i * 1.2, y0 + 9.0, z + 0.05), ("cloth_sky", "cloth_green", "cloth_tan")[i % 3])
                M.spot("spa_fitness", t, x0 + 0.9 + i * 1.2, y0 + 9.0, z + 0.07, 0.0, "guest_gym_stretch")  # (a member's, working out on it)
        if t == 2:
            at("gym_ball", 8.4, 9.2)
            at("gym_ball", 9.0, 10.0)
            at("gym_ball", 8.5, 10.9)
            for k in range(2):
                at("kettlebell", 8.3 + k * 0.3, 11.9, k * 0.9)
            at("cable_station", 8.85, 8.2, math.pi / 2)
        if t == 3:
            L.massage_table(B, x0 + 1.2, y1 - 1.6, z)
            L.massage_table(B, x0 + 2.6, y1 - 1.6, z)
            L.jacuzzi(B, x1 - 1.16, y1 - 1.16, z)  # the user's hot tub, tight into the front corner
            L.plant(B, (x0 + x1) * 0.5, y1 - 0.6, z)
            M.spot("spa_fitness", t, x0 + 1.9, y1 - 2.8, z, math.pi)


@furnished_last
def room_simulator(M, r):
    """Simulator Bay (T1) -> Swing Studio (T2) -> Golf Academy (T3)."""
    x0, y0, x1, y1 = r
    z = M.floor_z
    M.roomboxes.append(("simulator", (x0, y0, x1, y1, z)))
    w, d = x1 - x0, y1 - y0
    for t in (1, 2, 3):
        B = M.room("simulator", t)
        n = min(t, max(int(d / 4.4), 1))
        for i in range(n):
            L.sim_bay(B, x0 + 2.6, y0 + 2.2 + i * 4.4, z, 4.0, -math.pi / 2)
            # a member's place: the ball on the bay's mat, hit at its screen (ClubLife "guest_sim")
            M.spot("simulator", t, x0 + 3.2, y0 + 2.2 + i * 4.4, z, -math.pi / 2, "guest_sim")
            # its screen on its post behind the mat (every bay its own: user), turned to the pro's side
            L.tv_post(B, x0 + 4.4, y0 + 3.9 + i * 4.4, z, 0.0)
        # the golf pro running the first bay from its screen, on its far side from the bay (user)
        # (the pros: ClubLife, the first at the office desk, the next here, the last on the sofa)
        M.spot("simulator", t, x0 + 4.4, y0 + 4.55, z, math.pi, "golf_pro")
        L.sofa(B, x1 - 1.0, y0 + 2.2, z, 2.0, "leather", math.pi / 2)
        lounge_seat(M, t, x1 - 1.0, y0 + 2.2, z, math.pi / 2, 0.45, "simulator", "golf_pro_sit")
        if t == 3:
            B.box((1.6, d - 2.0, 0.03), (x1 - 0.9, (y0 + y1) * 0.5 + 1.0, z + 0.05), "turf")
            for k in range(3):
                B.cyl(0.06, 0.06, 0.04, (x1 - 0.9, y0 + 4.0 + k * 2.5, z + 0.05), "black", segs=10)


@furnished_last
def room_valet(M, r):
    """Three upgrades: mobile podium, Capri shade, then a nine-bag rack."""
    z = M.ground_z + 0.12
    M.roomboxes.append(("valet", (-7.5, -10.2, -1.5, -2.0, z)))
    L.PALETTE["valet_ebony"] = ("242725", 0.48, 0.12, 0, 1)
    L.PALETTE["valet_oak"] = ("756452", 0.72, 0.0, 0, 1)
    for t in (1, 2, 3):
        B = M.room("valet", t)
        x, y = -6.65, -3.6
        # A narrow wheeled podium with open shelves, sloping side cheeks and a writing lip.
        for dx in (-.43,.43):
            for dy in (-.28,.28):
                B.cyl(.065,.065,.055,(x+dx,y+dy,z+.065),"rubber",segs=12,rx=math.pi/2)
                B.box((.035,.04,.10),(x+dx,y+dy,z+.14),"steel")
        for height in (.19,.62):
            B.box((1.0,.72,.055),(x,y,z+height),"valet_ebony",bevel=.012)
        B.box((1.0,.055,1.01),(x,y+.34,z+.695),"valet_ebony",bevel=.012)
        for dx in (-.48,.48):
            B.box((.055,.7,.82),(x+dx,y,z+.60),"valet_ebony")
            B.box((.055,.73,.22),(x+dx,y,z+1.07),"valet_ebony",rx=.24)
        B.box((1.09,.83,.065),(x,y,z+1.13),"valet_ebony",rx=.24,bevel=.012)
        B.box((1.08,.035,.045),(x,y+.39,z+1.24),"steel")
        B.box((.64,.018,.19),(x,y+.375,z+.84),"black",bevel=.005)
        M.spot("valet",t,x,-4.85,z,math.pi)
        M.spot("valet",t,x-0.8,-4.85,z,math.pi)
        if t == 3:
            # Lengthwise along the side of the canopy, clear of the central door corridor.
            existing = set(B.bm.verts)
            rx, ry = -3.15, -8.85
            for dy in (-.34,-.17,0,.17,.34):
                B.box((4.5,.145,.065),(rx,ry+dy,z+.035),"valet_oak",bevel=.008)
            for dx in (-2.25,2.25):
                B.box((.10,.88,1.15),(rx+dx,ry,z+.575),"valet_oak",bevel=.01)
            B.box((4.6,.10,.16),(rx,ry-.36,z+1.08),"valet_oak",bevel=.015)
            B.box((4.6,.06,.045),(rx,ry+.34,z+.88),"iron")
            for i in range(10):
                bx=rx-2.25+i*.5
                B.box((.035,.70,.035),(bx,ry,z+.88),"iron")
                B.box((.035,.035,.86),(bx,ry-.34,z+.45),"iron")
            # Rotate the rack 90 degrees so its length runs beside, rather than across, the entrance.
            for v in B.bm.verts:
                if v not in existing:
                    dx, dy = v.co.x-rx, v.co.y-ry
                    v.co.x = -4.45+dy
                    v.co.y = -6.7-dx


def valet_forecourt(M):
    """One continuous asphalt surface: circle, flared entrance, and ten spaces by the porch."""
    B=M.g["BASE"]
    top=LEVEL+.04
    def rounded_box(x,y,cx,cy,hx,hy,r):
        qx,qy=abs(x-cx)-hx+r,abs(y-cy)-hy+r
        return math.hypot(max(qx,0),max(qy,0))+min(max(qx,qy),0)-r
    def merge(a,b,k=1.3):
        h=max(k-abs(a-b),0)/k
        return min(a,b)-h*h*k*.25
    def field(x,y):
        circle=math.hypot(x,y-8.5)-12
        lot=rounded_box(x,y,-27.5,-.4,14.8,6.4,1.1)
        # A curved, flared throat joins the parking aisle to the circle.
        ax,ay,bx,by=-9.3,8.5,-16,2.5
        t=max(0,min(1,((x-ax)*(bx-ax)+(y-ay)*(by-ay))/((bx-ax)**2+(by-ay)**2)))
        throat=math.hypot(x-ax-t*(bx-ax),y-ay-t*(by-ay))-3.0
        road=rounded_box(x,y,0,29,3.6,13,0.5)
        return max(merge(merge(merge(circle,lot),throat),road,.9),6.6-math.hypot(x,y-8.5))
    # Marching triangles yields a single mesh with a smooth outline and no overlapping slabs.
    verts,faces,ids=[],[],{}
    def vertex(p):
        key=(round(p[0],6),round(p[1],6))
        if key not in ids:ids[key]=len(verts);verts.append((p[0],p[1],top))
        return ids[key]
    step=.35
    for i in range(168):
        for j in range(149):
            x,y=-44+i*step,-9+j*step
            corners=[(x,y),(x+step,y),(x+step,y+step),(x,y+step)]
            for tri in [(0,1,2),(0,2,3)]:
                src=[corners[k] for k in tri];poly=[]
                for a,b in zip(src,src[1:]+src[:1]):
                    da,db=field(*a),field(*b)
                    if da<=0:poly.append(a)
                    if (da<0)!=(db<0):
                        t=da/(da-db);poly.append((a[0]+t*(b[0]-a[0]),a[1]+t*(b[1]-a[1])))
                if len(poly)>=3:
                    f=[vertex(p) for p in poly]
                    if len(set(f))>=3:faces.append(tuple(f))
    B.poly(verts,faces,"asphalt")
    L.annulus(B,0,8.5,6.6,6.35,LEVEL-.04,LEVEL+.12,"concrete",96)
    # Low perimeter kerb follows the parking contour; the driveway mouth stays open.
    edges={}
    for f in faces:
        for a,b in zip(f,f[1:]+f[:1]):
            key=tuple(sorted((a,b)));edges[key]=edges.get(key,0)+1
    for (a,b),count in edges.items():
        if count!=1:continue
        p,q=verts[a],verts[b];x,y=(p[0]+q[0])/2,(p[1]+q[1])/2
        length=math.hypot(q[0]-p[0],q[1]-p[1])
        if x<-13 and length>.02:
            B.box((length+.015,.14,.13),(x,y,top+.055),"concrete",rz=math.atan2(q[1]-p[1],q[0]-p[0]))
    # One row only, with a generous clear manoeuvring aisle in front.
    for i in range(11):
        B.box((.055,5.4,.012),(-13.625-i*2.75,-3.25,top+.009),"line")
    for i in range(10):
        x=-15-i*2.75
        B.box((1.65,.17,.11),(x,-5.65,top+.055),"concrete",bevel=.025)
    L.pave(B,-41.2,-8.0,-13.7,-7.0,LEVEL+.035,"stone",h=.08)
    for y in (-4.5,.5,4.5):
        L.shrub(B,-43.0,y,LEVEL,r=.48,seed=int(y*10+60))



def wing(M, x0, x1, y0, y1, H, ridge="x", rise=None, front=(), back=(), left=(), right=(), floor_mat="wood_floor", roof=True):
    """A shingle block: foundation, floor, four walls with openings and a gable roof."""
    z = M.floor_z
    L.foundation(M, x0, y0, x1, y1)
    L.floor(M, x0, y0, x1, y1, floor_mat)
    L.shell(M, x0, y0, x1, y1, H, front, back, left, right)
    if roof:
        R = M.g["ROOF"]
        if ridge == "x":
            r = rise if rise is not None else (y1 - y0) * 0.55
            L.gable_wall(R, x1 - x0, y1 - y0, r, ((x0 + x1) * 0.5, (y0 + y1) * 0.5), z + H, "shingle")
            L.gable_roof(R, x1 - x0, y1 - y0, r, ((x0 + x1) * 0.5, (y0 + y1) * 0.5), z + H)
        else:
            r = rise if rise is not None else (x1 - x0) * 0.55
            L.gable_wall(R, y1 - y0, x1 - x0, r, ((x0 + x1) * 0.5, (y0 + y1) * 0.5), z + H, "shingle", ridge="y")
            L.gable_roof(R, y1 - y0, x1 - x0, r, ((x0 + x1) * 0.5, (y0 + y1) * 0.5), z + H, ridge="y")


def win(at, w=1.0, sill=0.85, head=2.4):
    return {"at": at, "w": w, "sill": sill, "head": head, "kind": "window"}


def door(at, w=1.5, head=2.4, mat="door_white", double=False):
    """A doorway with its door: one leaf, or (double) a pair meeting in the middle."""
    return {"at": at, "w": w, "sill": 0, "head": head, "kind": "door", "door": mat, "double": double}


def french(at, w=1.6, head=2.5):
    """A pair of glazed garden doors, down to the floor: no sill (L.wall would build a kerb of wall
    and baseboard across the doorway, for people to wade through)."""
    return {"at": at, "w": w, "sill": 0.0, "head": head, "kind": "french"}


def openings_along(length, every, skip=(), w=1.0, kind=win):
    out = []
    n = int(length / every)
    for i in range(n):
        at = (i + 0.5) * length / n
        if any(abs(at - s) < 1.4 for s in skip):
            continue
        out.append(kind(at, w))
    return out


def cross_gable(M, x, y_face, w, h, depth=4.0, windows=2):
    """A wall gable flush with the front wall, rising from the eave (ridge along y)."""
    R = M.g["ROOF"]
    z = M.floor_z + M.eave
    R.box((w, depth, h), (x, y_face - depth * 0.5, z + h * 0.5), "shingle")
    for s in (-1, 1):
        R.box((0.26, 0.26, h), (x + s * w * 0.5, y_face, z + h * 0.5), "trim")
    rise = w * 0.6
    L.gable_wall(R, depth, w, rise, (x, y_face - depth * 0.5), z + h, "shingle", ridge="y")
    L.gable_roof(R, depth + 0.2, w, rise, (x, y_face - depth * 0.5 + 0.2), z + h, ridge="y", over=0.4)
    from mathutils import Vector
    F = L.frame_matrix(Vector((-1, 0, 0)), Vector((0, 1, 0)), (x, y_face, 0))
    for i in range(windows):
        wx = (i - (windows - 1) * 0.5) * 1.5
        R.fbox(F, (wx, 0.03, z + h * 0.55), (1.0, 0.05, 1.5), "glass")
        R.fbox(F, (wx, 0.07, z + h * 0.55 + 0.82), (1.36, 0.08, 0.14), "trim")
        R.fbox(F, (wx, 0.09, z + h * 0.55 - 0.8), (1.36, 0.14, 0.1), "trim")
        for s in (-1, 1):
            R.fbox(F, (wx + s * 0.58, 0.07, z + h * 0.55), (0.16, 0.08, 1.62), "trim")
        R.fbox(F, (wx, 0.06, z + h * 0.55), (1.0, 0.06, 0.04), "trim")
    R.fbox(F, (0, 0.06, z + h + rise * 0.42), (0.6, 0.06, 0.6), "trim")
    R.fbox(F, (0, 0.08, z + h + rise * 0.42), (0.45, 0.04, 0.45), "glass")


def clubhouse_l2(M):
    """Expanded: a long shingle clubhouse with three wall gables, a wrap-around colonnaded porch,
    three chimneys, a parking lot and flagpole; adds the restaurant + kitchen and an office."""
    plot_lawn(M, "clubhouse")
    B, G, R = M.g["BASE"], M.g["WALLS_HIGH"], M.g["ROOF"]
    x0, x1, y0, y1 = -18.0, 18.0, -27.0, -15.0
    H = M.eave = 3.4
    z = M.floor_z
    front = [win(2.0), win(4.4), win(7.4), win(10.0), win(12.8), door(18.0, 1.8, mat="entry_glass", double=True), win(21.4), win(24.0), win(26.8), win(30.0), win(33.0)]
    back = openings_along(36, 3.0, skip=(8.0, 29.0)) + [door(8.0, 1.2, 2.3, "door_wood"), french(29.0, 2.0)]
    # (its right wall shared with the locker wing's: a door into each half, where the wing's walls
    # open -- "at" from y0, -27, here; from -26 there)
    wing(M, x0, x1, y0, y1, H, "x", 5.8, front, back, [win(3.0), win(6.0), win(9.0)], [door(2.35, 1.0, 2.3, "door_wood"), door(8.65, 1.0, 2.3, "door_wood")])
    # rooms: restaurant + kitchen | lobby + office | pro shop; locker wing on the right
    L.wall(M, (-4.0, y0), (-4.0, y1), H, openings=[{"at": 9.0, "w": 1.6, "kind": "open"}], thick=0.15)
    L.wall(M, (x0, -22.0), (-4.0, -22.0), H, openings=[{"at": 7.0, "w": 1.2, "kind": "open"}], thick=0.15)
    L.wall(M, (-4.0, -22.0), (4.0, -22.0), H, openings=[{"at": 4.0, "w": 1.0, "kind": "door", "door": "door_wood", "head": 2.2}], thick=0.15)
    L.wall(M, (4.0, y0), (4.0, y1), H, openings=[{"at": 9.0, "w": 2.8, "head": 2.7, "kind": "open"}], thick=0.15)
    for gx in (-10.5, 0.0, 10.5):
        cross_gable(M, gx, y1 + 0.05, 5.0, 2.6, 4.5)
    for dx in (-15.0, -5.4, 5.4, 15.0):
        L.dormer(M, dx, y1 - 1.8, z + H + 0.6)
    for cx_ in (-14.0, 5.0):
        L.chimney(M, cx_, -21.0, z + H + 6.6)
    # locker-room wing (lower, gable to the front)
    # (its own wall on the clubhouse's side opens where the clubhouse's does: the way in)
    # (split across, men's | women's, each with its own way in from the clubhouse; the far wall
    # blank behind their showers)
    ways_in = [{"at": 1.35, "w": 1.0, "kind": "open"}, {"at": 7.65, "w": 1.0, "kind": "open"}]  # (room by the dividing wall for a pair of stalls)
    wing(M, 18.0, 26.0, -26.0, -17.0, 3.2, "y", 4.2, [win(2.0), win(6.0)], [], ways_in, [], floor_mat="tile")
    L.wall(M, (18.0, -26.0), (18.0, -17.0), 3.2, openings=ways_in, thick=0.28)  # (over both shells' faces: no shingle showing in the pro shop)
    L.wall(M, (18.1, -21.5), (25.9, -21.5), 3.2, thick=0.15)
    # wrap-around porch: front + west side
    cols = [x0 + 0.3 + i * (x1 - x0 - 0.6) / 11 for i in range(12)]  # (an even dozen: the front door, at x 0, between the middle pair)
    L.porch(M, x0, x1, y1, y1 + 3.6, z + 3.0, y1 + 3.3, cols, steps=((0.0, 3.2),))
    L.porch(M, x0 - 3.6, x0, y0 + 1.0, y1 + 3.6, z + 3.0, x0 - 3.3, [], rail=False, facing="-x")  # (its roof down to the west)
    for py in [y0 + 1.3 + i * 3.0 for i in range(5)]:
        L.column(G, x0 - 3.3, py, z, 3.0)
    L.railing(G, (x0 - 3.3, y0 + 1.3), (x0 - 3.3, y1 + 3.3), z, 0.9, post=False)
    room_restaurant(M, (x0 + 0.15, -21.9, -4.1, y1 - 0.15), (x0 + 0.15, y0 + 0.15, -4.1, -22.1), [(-10.0, 1.2)])  # (the kitchen door: stoop below)
    room_lobby(M, (-3.9, -21.9, 3.9, y1 - 0.15), "+y")
    room_office(M, (-3.9, y0 + 0.15, 3.9, -22.1))
    room_pro_shop(M, (4.1, y0 + 0.15, x1 - 0.15, y1 - 0.15), "-x")
    room_lockers(M, (18.15, -25.85, 25.85, -17.15), "-x", split_x=-21.5, spa=False)  # (more stalls instead: user)
    # grounds
    L.flower_bed(B, x0 + 0.4, -2.0, y1 + 4.3, M.ground_z, seed=2)
    L.flower_bed(B, 2.0, x1 - 0.4, y1 + 4.3, M.ground_z, seed=4)
    # the walk from the foot of the porch steps (L.porch: L.stairs' 0.32 m treads, 0.18 m risers)
    porch_steps = 0.32 * max(math.ceil((z - M.ground_z) / 0.18), 1)
    L.pave(B, -1.6, y1 + 3.6 + porch_steps - 0.05, 1.6, -4.0, LEVEL, "stone")
    # a drop-off forecourt at the foot of the walk, the drive up the middle to it, both on the front
    # door (no parking of its own: the parking lot's a facility; user): the bag-drop curb on its
    # near side (ClubLife.FRONT_DRIVE[2]), a stone apron from it up to the walk, the drive's two
    # lanes dashed down the middle
    L.pave(B, -7.0, 0.0, 7.0, 9.0, LEVEL, "asphalt")
    L.pave(B, -3.0, 9.0, 3.0, 42.0, LEVEL, "asphalt")
    L.pave(B, -1.6, -4.0, 1.6, 0.0, LEVEL, "stone")
    for i in range(11):
        B.box((0.12, 1.2, 0.01), (0.0, 10.5 + i * 3.0, LEVEL + 0.045), "line")  # (on the asphalt: L.pave's top is LEVEL + 0.04)
    # the cart boy's shortcut (user): a cart path from the line behind the clubhouse, along its back,
    # down the patio side outside its rail and along the front into the forecourt -- not all the
    # way round by the lawn (ClubLife.FRONT_DRIVE[2] keeps to it)
    cart_path(B, [(7.7, -39.8), (37.8, -39.8), (37.8, 1.2), (7.0, 1.2)], 14.0)  # (bends swept wide as a running track's: user)
    back_walk(M, 11.0, y0, 10.0, 3.2, 4, 2, crossing=3.2)  # (open at its end for the cart path)
    cart_line(M, 6.4, 2.4, [-39.4, -36.4, -33.4], -31.4)
    stoop(M, -10.0, y0, "-y", 1.2, path=2.0, bins=True)  # the kitchen door
    stoop(M, 26.0, -21.5, "+x", 1.6, path=0)  # lockers out to the patio
    club_monument(M, -6.6, 37.0)  # (beside the drive)
    L.us_flag(B, -3.4, -2.0, LEVEL, 9.0)  # (beside the walk)
    L.flower_bed(B, -4.9, -1.9, -2.0, LEVEL, 2.4, 5)
    L.pave(B, 26.0, -26.0, 36.0, -16.0, LEVEL, "patio_brick")
    for i, (px, py) in enumerate(((30.4, -23.6), (34.0, -23.6), (30.4, -18.8), (34.0, -18.8))):
        L.umbrella_table(B, px, py, LEVEL, ("cloth_cream", "cloth_green")[i % 2])
    for p, q in (((26, -16), (36, -16)), ((36, -16), (36, -26)), ((26, -26), (36, -26))):
        L.railing(G, p, q, LEVEL, 0.85, "white", 2.0, 0.6)
    for i in range(2):
        L.cart(B, 22.0 + i * 2.2, -13.0, LEVEL, math.pi)
    # the lamps along the drive, in pairs either side (short of the club's sign), and at the
    # forecourt's corners -- none out on the lawn (user)
    for px, py in [(-7.6, 0.4), (7.6, 3.4)] + [(s * 3.6, dy) for dy in (12.0, 20.0, 28.0) for s in (-1, 1)]:  # (off the cart path)
        L.lamp(B, px, py, LEVEL)
    front_lawn(M, (-11.0, 6.0), (15.0, 12.0), [(s_ * 5.2, py) for py in (16.0, 24.0, 32.0) for s_ in (-1, 1)] + [(5.2, 38.0)])
    M.cols += [("main", (36.6, 12.6, 10.0), (0, -21.0, z + 5.0)), ("wing", (8.4, 9.4, 7.0), (22.0, -21.5, z + 3.5))]


def clubhouse_l3(M):
    """Prestige: a grand two-storey pedimented centre with a columned portico and balcony,
    side gables, a wrap porch, an upper deck terrace, a circle drive with a flag island; adds the
    ballroom and the trophy lounge."""
    plot_lawn(M, "clubhouse")
    B, G, R = M.g["BASE"], M.g["WALLS_HIGH"], M.g["ROOF"]
    x0, x1, y0, y1 = -22.0, 22.0, -28.0, -14.0
    H = M.eave = 3.6
    z = M.floor_z
    front = [win(2.2), win(5.0), win(8.0), win(11.0), win(14.0)] + [win(30.0), win(33.0), win(36.0), win(39.0), win(41.8)]
    back = [o for o in openings_along(44, 3.2, skip=(10.0, 20.0)) if not 13.0 < x0 + o["at"] < 22.6]  # none behind the lockers
    back += [door(10.0, 1.4, 2.3, "door_wood"), french(20.0, 2.4)]
    # (the grand centre's front: no wall between the lobby in it and the trophy lounge behind)
    cx0, cx1, cy1 = -6.5, 6.5, -10.0
    lobby_gap = {"at": 22.0, "w": cx1 - cx0, "head": H, "kind": "gap"}
    wing(M, x0, x1, y0, y1, H, "x", 6.4, front + [lobby_gap], back, [win(3.5), {"at": 6.5, "w": 3.2, "head": 2.8, "kind": "open"}, win(10.5)], [])
    # grand centre, two storeys, front-facing gable
    L.foundation(M, cx0, y1, cx1, cy1)
    L.floor(M, cx0, y1, cx1, cy1, "wood_floor")
    H2 = 7.2
    L.wall(M, (cx1, cy1), (cx0, cy1), H2, "shingle", "plaster", [win(2.2, 1.1), win(4.4, 1.1), door(6.5, 2.0, 2.7, mat="entry_glass", double=True), win(8.6, 1.1), win(10.8, 1.1)], 0.25, (0, 1))
    # garden doors out of the lobby onto the porch either side
    L.wall(M, (cx0, cy1), (cx0, y1), H2, "shingle", "plaster", [french((cy1 - y1) * 0.5)], 0.25, (-1, 0))
    L.wall(M, (cx1, y1), (cx1, cy1), H2, "shingle", "plaster", [french((cy1 - y1) * 0.5)], 0.25, (1, 0))
    from mathutils import Vector
    F = L.frame_matrix(Vector((-1, 0, 0)), Vector((0, 1, 0)), (0, cy1 + 0.13, z))
    for wx in (-3.4, -1.15, 1.15, 3.4):
        G.fbox(F, (wx, 0.0, 5.3), (1.2, 0.06, 2.0), "glass")
        G.fbox(F, (wx, 0.05, 6.4), (1.5, 0.1, 0.16), "trim")
        G.fbox(F, (wx, 0.06, 4.25), (1.5, 0.14, 0.1), "trim")
        G.fbox(F, (wx, 0.04, 5.3), (0.04, 0.06, 2.0), "trim")
    for (px, py) in ((cx0, cy1), (cx1, cy1)):
        L.split_box(M, (0.32, 0.32, H2), (px, py, z + H2 * 0.5), mat="trim")
    L.gable_wall(R, y1 - y0 + 4.0, cx1 - cx0, 4.6, (0, (y0 + cy1) * 0.5), z + H2, "shingle", ridge="y")
    L.gable_roof(R, y1 - y0 + 4.0, cx1 - cx0, 4.6, (0, (y0 + cy1) * 0.5), z + H2, ridge="y", over=0.55)
    R.box((2.6, 0.08, 1.2), (0, cy1 + 0.18, z + H2 + 1.7), "glass")
    # portico with balcony over it
    B.box((cx1 - cx0 + 1.0, 3.6, z - M.ground_z), (0, cy1 + 1.8, M.ground_z + (z - M.ground_z) * 0.5), "brick")
    B.box((cx1 - cx0 + 1.1, 3.7, 0.06), (0, cy1 + 1.8, z - 0.02), "stone")
    for px in (-6.2, -3.7, -1.25, 1.25, 3.7, 6.2):
        L.column(G, px, cy1 + 3.3, z, 3.4, 0.22)
    R.box((cx1 - cx0 + 1.2, 4.0, 0.35), (0, cy1 + 1.8, z + 3.55), "trim")
    L.railing(R, (-6.8, cy1 + 3.6), (6.8, cy1 + 3.6), z + 3.72, 0.95, "trim", 2.2, 0.16)
    # steps all the way round the platform -- across its front and down both sides, turning the
    # corners -- each tread a ring a step lower and a tread wider than the one above it
    rise = z - M.ground_z
    n = max(int(math.ceil(rise / 0.18)), 1)
    for k in range(1, n):
        h, out = rise * (n - k) / n, 0.32 * k
        B.box((cx1 - cx0 + 1.0 + 2 * out, 3.6 + out, h), (0, cy1 + (3.6 + out) * 0.5, M.ground_z + h * 0.5), "stone")
    for gx in (-15.0, 15.0):
        cross_gable(M, gx, y1 + 0.05, 5.6, 2.8, 4.5)
    for dx in (-19.0, -10.0, 10.0, 19.0):
        L.dormer(M, dx, y1 - 1.9, z + H + 0.6)
    for cx_ in (-17.5, 17.5):
        L.chimney(M, cx_, -22.0, z + H + 7.4, 1.3, 1.0)
    # wrap porch: front either side of the portico, both ends
    for (a, b) in ((x0, cx0), (cx1, x1)):
        L.porch(M, a, b, y1, y1 + 3.4, z + 3.1, y1 + 3.1, [a + 0.3 + i * (b - a - 0.6) / 5 for i in range(6)], steps=(((a + b) * 0.5, 2.4),))
    # pro shop wing on the west, upper deck terrace on the east
    wing(M, -30.0, -22.0, -26.0, -15.0, 3.3, "y", 4.4, [win(2.0), door(4.0, 1.4), win(6.0)], [win(4.0)], [win(3.0), win(8.0)], [{"at": 5.5, "w": 3.2, "head": 2.8, "kind": "open"}])
    L.wall(M, (-22.0, -26.0), (-22.0, -15.0), 3.3, openings=[{"at": 5.5, "w": 3.2, "head": 2.8, "kind": "open"}], thick=0.2)
    B.box((10.0, 10.0, z + 3.3 - M.ground_z), (27.0, -21.0, M.ground_z + (z + 3.3 - M.ground_z) * 0.5), "brick")
    B.box((10.2, 10.2, 0.1), (27.0, -21.0, z + 3.3), "deck")
    for p, q in (((22.2, -16.0), (32.0, -16.0)), ((32.0, -17.5), (32.0, -26.0)), ((22.2, -26.0), (32.0, -26.0))):
        L.railing(G, p, q, z + 3.35, 0.95, "trim", 2.0)
    for i, (px, py) in enumerate(((25.0, -23.5), (29.4, -23.5), (25.0, -18.7), (29.4, -18.7))):
        L.umbrella_table(B, px, py, z + 3.35, ("cloth_green", "cloth_cream")[i % 2])
    L.stairs(B, 33.2, -16.1, z + 3.35, M.ground_z, 2.0, mat="deck", facing=-1)  # off the deck's east end, down to the lawn
    room_ballroom(M, (x0 + 0.15, y0 + 0.15, -6.6, y1 - 0.15))
    L.wall(M, (-6.5, y0), (-6.5, y1), H, openings=[{"at": 10.5, "w": 3.0, "head": 2.8, "kind": "open"}], thick=0.2)
    room_lobby(M, (-6.35, y1 + 0.1, 6.35, cy1 - 0.15), "+y", rug=False)  # (its wood floor bare)
    L.wall(M, (-6.5, -21.0), (6.5, -21.0), H, openings=[{"at": 4.0, "w": 1.6, "kind": "open"}, {"at": 10.5, "w": 1.0, "kind": "door", "door": "door_wood", "head": 2.2}], thick=0.15)
    L.wall(M, (2.5, y0), (2.5, -21.0), H, thick=0.15)
    room_lounge(M, (-6.35, -20.9, 6.35, y1 - 0.1))
    room_office(M, (2.6, y0 + 0.15, 6.35, -21.1))
    # east of the lounge: the restaurant in front; behind it a hallway (y -21 .. -19.35) off the
    # lounge, with the kitchen and the men's and women's locker rooms opening onto it
    L.wall(M, (6.5, y0), (6.5, y1), H, openings=[{"at": 10.0, "w": 2.0, "kind": "open"}, {"at": 7.85, "w": 1.3, "kind": "open"}], thick=0.2)
    L.wall(M, (6.5, -19.35), (x1, -19.35), H, openings=[{"at": 3.0, "w": 1.4, "kind": "open"}], thick=0.15)
    L.wall(M, (6.5, -21.0), (x1, -21.0), H, openings=[{"at": 3.0, "w": 1.0, "kind": "door", "door": "door_wood", "head": 2.2},
                                                       {"at": 8.9, "w": 1.0, "kind": "door", "door": "door_wood", "head": 2.2},
                                                       {"at": 13.7, "w": 1.0, "kind": "door", "door": "door_wood", "head": 2.2}], thick=0.15)
    L.wall(M, (13.5, y0), (13.5, -21.0), H, thick=0.15)
    L.wall(M, (17.8, y0), (17.8, -21.0), H, thick=0.15)  # men's | women's
    room_restaurant(M, (6.65, -19.25, x1 - 0.15, y1 - 0.15), (6.65, y0 + 0.15, 13.4, -21.1))
    room_lockers(M, (13.6, y0 + 0.15, x1 - 0.15, -21.1), "+y", split_x=17.8, spa=False)  # (too busy with them: user)
    room_pro_shop(M, (-29.85, -25.85, -22.15, -15.15), "+x")
    # grounds: circle drive with a flag island, cart parking, fencing
    L.ring_drive(B, 0.0, 10.0, 10.5, 5.6, LEVEL)
    L.pave(B, -3.0, -6.4, 3.0, 0.4, LEVEL, "asphalt")
    L.pave(B, -3.2, 20.0, 3.2, 42.0, LEVEL, "asphalt")
    L.us_flag(B, 0.0, 10.0, LEVEL + 0.18, 10.0)
    back_walk(M, -2.0, y0, 14.0, 4.0, 4, 3)
    cart_line(M, 11.0, 7.0, [-39.4, -36.4, -33.4], -31.4)  # (its head the left row, by the cart path: taken from first, user)
    stoop(M, -12.0, y0, "-y", 1.4, path=2.5)  # the ballroom's back door
    stoop(M, -26.0, -15.0, "+y", 1.4, path=2.0)  # the pro shop wing's door
    club_monument(M, 8.2, 40.3, grand=True)
    L.flower_bed(B, -2.5, 2.5, 12.6, LEVEL + 0.18, 1.0, 1)
    # (no cart parking out front: the club's carts wait in the line behind it; user)
    # the cart boy's shortcut (user): a cart path from the line behind the clubhouse, along its back,
    # down the deck side past its stair, and along the front into the circle at the porte-cochère
    # (ClubLife.FRONT_DRIVE[3] keeps to it)
    cart_path(B, [(12.3, -39.8), (36.2, -39.8), (36.2, 0.2), (3.0, 0.2)], 12.0)  # (on into the circle's band; bends swept wide, clear of the deck's stair)
    # (along the front of its site, not out past it to the plot's edge)
    L.split_rail(B, (-31.0, 40.5), (-4.0, 40.5), LEVEL)
    L.split_rail(B, (12.0, 40.5), (38.5, 40.5), LEVEL)  # the monument stands in the fence line
    for (a, b) in ((x0 + 0.4, -8.8), (8.8, x1 - 0.4)):  # clear of the platform's side steps
        L.flower_bed(B, a, b, y1 + 4.1, M.ground_z, seed=int(a))
    L.hedge(B, -38.0, -6.0, -12.0, -6.0, LEVEL, 1.0, 0.9)
    for dx in (-14.0, 14.0):
        L.lamp(B, dx, 6.0, LEVEL)
    front_lawn(M, (-19.0, 9.0), (21.0, 12.0), [(s_ * 5.2, py) for py in (25.0, 31.0, 37.0) for s_ in (-1, 1)])
    M.cols += [("main", (44.6, 14.6, 11.0), (0, -21.0, z + 5.5)), ("centre", (13.0, 4.0, 11.0), (0, -12.0, z + 5.5)),
               ("west", (8.4, 11.4, 7.0), (-26.0, -20.5, z + 3.5)), ("deck", (10.0, 10.0, z + 3.3), (27.0, -21.0, (z + 3.3) * 0.5))]


def clubhouse_l4(M):
    """Grand: a 60 m shingle clubhouse with a two-storey pavilion and porte-cochère valet
    entrance, gabled wings for the simulator and the spa, a terraced patio deck, a fountain
    circle drive with flags, formal gardens and cart parking."""
    plot_lawn(M, "clubhouse")
    B, G, R = M.g["BASE"], M.g["WALLS_HIGH"], M.g["ROOF"]
    x0, x1, y0, y1 = -30.0, 30.0, -29.0, -14.0
    H = M.eave = 3.8
    z = M.floor_z
    front = [win(2.2 + i * 3.1) for i in range(7)] + [win(39.0 + i * 3.1) for i in range(7)]
    back = [o for o in openings_along(60, 3.4, skip=(14.0, 30.0, 46.0)) if not 14.6 < x0 + o["at"] < 30.6]  # none behind the lockers
    back += [door(14.0, 1.4, 2.3, "door_wood"), french(30.0, 2.6), door(46.0, 1.4, 2.3, "door_wood")]
    # (the pavilion's front: no wall between it and the lobby -- one room, wood-floored throughout)
    cx0, cx1, cy1 = -7.0, 7.0, -10.5
    lobby_gap = {"at": 30.0, "w": cx1 - cx0, "head": H, "kind": "gap"}
    # (the way into the simulator wing through its own left wall too: user, no way in)
    wing(M, x0, x1, y0, y1, H, "x", 6.8, front + [lobby_gap], back, [{"at": 7.5, "w": 2.0, "kind": "open"}], [door(8.85, 1.6, 2.4, "entry_glass", double=True)])  # glazed entrance from the hallway into the spa
    # pavilion + porte-cochère
    L.foundation(M, cx0, y1, cx1, cy1)
    L.floor(M, cx0, y1, cx1, cy1, "wood_floor")
    H2 = 7.6
    L.wall(M, (cx1, cy1), (cx0, cy1), H2, "shingle", "plaster", [win(2.0, 1.1), win(4.4, 1.1), door(7.0, 2.4, 2.9, mat="entry_glass", double=True), win(9.6, 1.1), win(12.0, 1.1)], 0.25, (0, 1))
    # garden doors out of the lobby onto the porch either side
    L.wall(M, (cx0, cy1), (cx0, y1), H2, "shingle", "plaster", [french((cy1 - y1) * 0.5)], 0.25, (-1, 0))
    L.wall(M, (cx1, y1), (cx1, cy1), H2, "shingle", "plaster", [french((cy1 - y1) * 0.5)], 0.25, (1, 0))
    from mathutils import Vector
    F = L.frame_matrix(Vector((-1, 0, 0)), Vector((0, 1, 0)), (0, cy1 + 0.13, z))
    for wx in (-3.9, -1.3, 1.3, 3.9):
        G.fbox(F, (wx, 0.0, 5.5), (1.3, 0.06, 2.2), "glass")
        G.fbox(F, (wx, 0.05, 6.7), (1.6, 0.1, 0.16), "trim")
        G.fbox(F, (wx, 0.06, 4.35), (1.6, 0.14, 0.1), "trim")
        G.fbox(F, (wx, 0.04, 5.5), (0.04, 0.06, 2.2), "trim")
    L.gable_wall(R, y1 - y0 + 4.5, cx1 - cx0, 5.0, (0, (y0 + cy1) * 0.5), z + H2, "shingle", ridge="y")
    L.gable_roof(R, y1 - y0 + 4.5, cx1 - cx0, 5.0, (0, (y0 + cy1) * 0.5), z + H2, ridge="y", over=0.55)
    pc0, pc1 = cy1, cy1 + 7.5
    for px in (-5.4, 5.4):
        for py in (pc0 + 1.0, pc1 - 0.4):
            L.column(G, px, py, M.ground_z, 4.6, 0.3)
    R.box((11.6, 7.8, 0.5), (0, (pc0 + pc1) * 0.5, M.ground_z + 4.85), "trim")
    L.gable_wall(R, 7.4, 11.4, 2.6, (0, (pc0 + pc1) * 0.5), M.ground_z + 5.1, "shingle", ridge="y")
    L.gable_roof(R, 7.8, 11.6, 2.6, (0, (pc0 + pc1) * 0.5 + 0.2), M.ground_z + 5.1, ridge="y", over=0.4)
    B.box((11.0, pc1 - pc0, 0.1), (0, (pc0 + pc1) * 0.5, LEVEL + 0.05), "stone")
    # the front door's landing and steps down to the porte-cochere's paving
    B.box((2.8, 1.2, z - LEVEL - 0.1), (0, cy1 + 0.6, LEVEL + 0.1 + (z - LEVEL - 0.1) * 0.5), "brick")
    B.box((2.9, 1.25, 0.06), (0, cy1 + 0.62, z - 0.02), "stone")
    L.stairs(B, 0, cy1 + 1.2, z, LEVEL + 0.1, 2.6, mat="stone", facing=1)
    for gx in (-14.5, -23.0, 14.5, 23.0):
        cross_gable(M, gx, y1 + 0.05, 5.4, 2.8, 4.5)
    for dx in (-27.0, -18.8, -10.2, 10.2, 18.8, 27.0):
        L.dormer(M, dx, y1 - 1.9, z + H + 0.6)
    for cx_ in (-11.5, -20.5, 11.5, 20.5):
        L.chimney(M, cx_, -23.5, z + H + 7.8, 1.3, 1.0)
    for (a, b) in ((x0, cx0), (cx1, x1)):
        n = 8
        L.porch(M, a, b, y1, y1 + 3.6, z + 3.2, y1 + 3.3, [a + 0.3 + i * (b - a - 0.6) / (n - 1) for i in range(n)], steps=(((a + b) * 0.5, 2.6),))
    # simulator wing (west, glass doors) and spa wing (east, flat roof terrace)
    wing(M, -40.0, -30.0, -28.0, -15.0, 4.0, "y", 5.4, [french(2.0, 1.8, 3.0), french(5.0, 1.8, 3.0), french(8.0, 1.8, 3.0)], [win(5.0)], [win(3.0), win(6.5), win(10.0)], [{"at": 6.5, "w": 2.0, "kind": "open"}], floor_mat="carpet")
    L.wall(M, (-30.0, -28.0), (-30.0, -15.0), 4.0, openings=[{"at": 6.5, "w": 2.0, "kind": "open"}], thick=0.3)  # (over both shells' faces)
    # the windows by the hot tub's corner clear its 0.95 m rim
    wing(M, 30.0, 40.0, -28.0, -15.0, 4.0, front=[win(2.0, sill=1.15), win(5.0), win(8.0)], back=[], left=[{"at": 6.5, "w": 13.0, "head": 4.0, "kind": "gap", "backed": True}], right=[win(3.0), win(6.5), win(9.5)], floor_mat="tile", roof=False)
    B.box((10.0, 3.6, z - M.ground_z), (-35.0, -13.2, M.ground_z + (z - M.ground_z) * 0.5), "brick")  # the simulator's terrace, on to the porch
    B.box((10.1, 3.7, 0.08), (-35.0, -13.2, z - 0.04), "deck")
    for p, q in (((-40.0, -15.0), (-40.0, -11.4)), ((-40.0, -11.4), (-36.4, -11.4)), ((-33.6, -11.4), (-30.0, -11.4))):
        L.railing(G, p, q, z, 0.95, "trim", 2.0)
    L.stairs(B, -35.0, -11.4, z, M.ground_z, 2.6)
    # The main wing supplies the shared wall and doorway; no second solid wall over it.
    G.box((0.25, 13.0, 0.2), (30.0, -21.5, z + 3.9), "plaster")
    R.box((10.4, 13.4, 0.3), (35.0, -21.5, z + 4.15), "concrete")
    for p, q in (((29.8, -14.8), (40.2, -14.8)), ((40.2, -14.8), (40.2, -29.6)), ((29.8, -28.2), (38.6, -28.2)), ((38.6, -29.6), (40.2, -29.6))):
        L.railing(R, p, q, z + 4.3, 1.0, "trim", 2.2)
    # up to the roof terrace: a stair along the spa's back from a landing at the corner
    B.box((1.6, 1.4, z + 4.3 - M.ground_z), (39.4, -28.9, M.ground_z + (z + 4.3 - M.ground_z) * 0.5), "concrete")
    L.stairs(B, -28.9, 38.6, z + 4.3, M.ground_z, 1.4, run=0.3, mat="concrete", facing=-1, axis="x")
    for i in range(3):
        L.umbrella_table(R, 32.4 + i * 3.0, -21.5, z + 4.3, "cloth_cream", chairs=2)
    # rooms
    L.wall(M, (-14.0, y0), (-14.0, y1), H, openings=[{"at": 7.5, "w": 2.2, "kind": "open"}], thick=0.2)
    room_ballroom(M, (x0 + 0.15, y0 + 0.15, -14.1, y1 - 0.15))
    L.wall(M, (cx0, y0), (cx0, y1), H, openings=[{"at": 11.5, "w": 3.0, "head": 2.8, "kind": "open"}], thick=0.2)
    room_pro_shop(M, (-13.9, y0 + 0.15, cx0 - 0.1, y1 - 0.15), "+x")
    L.wall(M, (cx0, -20.5), (cx1, -20.5), H, openings=[{"at": 7.0, "w": 2.0, "kind": "open"}], thick=0.15)
    room_lobby(M, (cx0 + 0.15, -20.4, cx1 - 0.15, cy1 - 0.15), "+y", rug=False, desk="left")  # (its wood floor bare; the desk the far side from the restaurant: user)
    room_lounge(M, (cx0 + 0.15, y0 + 0.15, cx1 - 0.15, -20.6))
    # east of the lounge: the restaurant and the office in front; behind them a hallway (y -21 ..
    # -19.35) from the lobby through to the spa wing, the kitchen, both locker rooms and the
    # office opening onto it
    # (lounge | kitchen and hallway only, on to the lobby's back wall: the lobby open onto the
    # restaurant and the hallway -- no wall between; user)
    L.wall(M, (cx1, y0), (cx1, -20.5), H, thick=0.2)
    # (no way through behind the bar: user -- the hallway's reached from the lobby)
    L.wall(M, (cx1, -19.35), (x1, -19.35), H, openings=[{"at": 19.0, "w": 0.95, "kind": "door", "door": "door_wood", "head": 2.2}], thick=0.15)
    L.wall(M, (cx1, -21.0), (x1, -21.0), H, openings=[{"at": 4.0, "w": 1.0, "kind": "door", "door": "door_wood", "head": 2.2},
                                                       {"at": 11.8, "w": 1.0, "kind": "door", "door": "door_wood", "head": 2.2},
                                                       {"at": 19.25, "w": 1.0, "kind": "door", "door": "door_wood", "head": 2.2}], thick=0.15)
    L.wall(M, (15.0, y0), (15.0, -21.0), H, thick=0.15)
    L.wall(M, (22.5, y0), (22.5, -21.0), H, thick=0.15)  # men's | women's
    L.wall(M, (22.0, -19.35), (22.0, y1), H, thick=0.15)
    room_restaurant(M, (cx1 + 0.15, -19.25, 21.9, y1 - 0.15), (cx1 + 0.15, y0 + 0.15, 14.9, -21.1))
    room_lockers(M, (15.1, y0 + 0.15, x1 - 0.15, -21.1), "+y", split_x=22.5)
    room_office(M, (22.1, -19.25, x1 - 0.15, y1 - 0.15))
    room_simulator(M, (-39.85, -27.85, -30.15, -15.15))
    room_spa(M, (30.15, -27.85, 39.85, -15.15))
    room_valet(M, (-5.2, pc0 + 0.3, 5.2, pc1 - 0.3))
    # a raised wood patio deck east of the porte-cochère, with steps down its side by the drive
    B.box((16.0, 7.0, 0.08), (19.0, -7.0, LEVEL + 0.46), "deck")
    B.box((15.8, 6.8, 0.42), (19.0, -7.0, LEVEL + 0.21), "wood")
    L.stairs(B, -6.3, 11.0, LEVEL + 0.5, LEVEL, 2.4, mat="deck", facing=-1, axis="x")
    for i, (px, py) in enumerate(((13.0, -8.8), (16.6, -8.8), (20.2, -8.8), (23.8, -8.8), (13.0, -5.2), (16.6, -5.2), (20.2, -5.2), (23.8, -5.2))):
        L.umbrella_table(B, px, py, LEVEL + 0.5, ("cloth_cream", "cloth_green")[i % 2])
    for p, q in (((11.0, -3.5), (27.0, -3.5)), ((27.0, -3.5), (27.0, -10.5))):
        L.railing(G, p, q, LEVEL + 0.5, 0.9, "trim", 2.0)
    # fountain circle drive, flags, gardens, cart parking, fence
    valet_forecourt(M)
    B.marker("FOUNTAIN", 0.0, 8.5, LEVEL)  # the user's granite fountain (props/fountain.glb), stood by Godot
    L.pave(B, -3.4, pc1 - 0.5, 3.4, -3.0, LEVEL, "asphalt")
    L.us_flag(B, -14.0, 15.0, LEVEL, 9.5)  # (out on the lawn west of the circle, away from the drive's palms: user)
    back_walk(M, 0.0, y0, 22.0, 4.2, 6, 4)
    cart_line(M, 24.0, 20.0, [-39.4, -36.4, -33.4], -31.4)  # (its head the left row, by the cart path: taken from first, user)
    stoop(M, -16.0, y0, "-y", 1.4, path=2.5)  # the ballroom's back door
    stoop(M, 16.0, y0, "-y", 1.4, path=2.5)  # the locker rooms' back door
    club_monument(M, 9.2, 40.3, grand=True)
    # Keep the forecourt lawn open beside the fountain and walking path.
    # Open lawn: the detached slab and decorative cart lot are removed.
    L.split_rail(B, (-40.0, 40.5), (-4.5, 40.5), LEVEL)
    L.split_rail(B, (13.0, 40.5), (40.0, 40.5), LEVEL)  # the monument stands in the fence line
    for (a, b) in ((x0 + 0.4, -16.0), (9.0, x1 - 0.4)):
        L.flower_bed(B, a, b, y1 + 4.3, M.ground_z, seed=int(b))
    for dx in (-16.0, -8.0, 8.0, 16.0):
        L.lamp(B, dx, 21.0, LEVEL)
    # the cart boy's shortcut (user): a cart path from the line behind the clubhouse, along its back,
    # down the spa side outside its railing and stair, and along the front outside the patio deck's
    # railing to the fountain circle at the porte-cochere (ClubLife.FRONT_DRIVE[4] keeps to it)
    # (on into the circle's band; bends swept wide, clear of the spa wing) -- and, the other way,
    # on along the back past the cart line to the back door's walk, where the delivered carts wait
    # for their golfers (user; ClubLife.CART_PATH_MEET)
    # Clear the last parked row and cross beyond the covered back-door walk.
    L.pave(B, -1.3, -47.2, 1.3, -41.0, LEVEL, "stone")
    cart_path(B, [(-3.4, -46.0), (41.8, -46.0), (41.8, -1.9), (4.0, -1.9)], 12.0)
    front_lawn(M, (-35.0, 25.0), (22.0, 12.0), [(s_ * 5.6, py) for py in (24.0, 31.0, 37.0) for s_ in (-1, 1)])
    M.cols += [("main", (60.6, 15.6, 11.5), (0, -21.5, z + 5.8)), ("pavilion", (14.0, 4.0, 12.0), (0, -12.0, z + 6.0)),
               ("west", (10.4, 13.4, 9.0), (-35.0, -21.5, z + 4.5)), ("east", (10.4, 13.4, 4.5), (35.0, -21.5, z + 2.2))]


def garage(at, w=3.6, head=2.6):
    """Cart-barn overhead doors stay fully raised, clear of every cart lane."""
    return {"at": at, "w": w, "sill": 0, "head": head, "kind": "garage", "open": True}


def barn_block(M, x0, x1, y0, y1, H, bays, rise, right=(), left=(), back=(), chargers=True, carts_per_bay=1):
    """A shingle cart barn: open bays across the front, chargers on the back wall, carts inside."""
    z = M.floor_z
    L.foundation(M, x0, y0, x1, y1, "concrete")
    L.floor(M, x0, y0, x1, y1, "concrete")
    front = [garage(x1 - bx, bw, head) for (bx, bw, head) in bays]
    L.shell(M, x0, y0, x1, y1, H, front, list(back), list(left), list(right))
    L.gable_wall(M.g["ROOF"], x1 - x0, y1 - y0, rise, ((x0 + x1) * 0.5, (y0 + y1) * 0.5), z + H, "shingle")
    L.gable_roof(M.g["ROOF"], x1 - x0, y1 - y0, rise, ((x0 + x1) * 0.5, (y0 + y1) * 0.5), z + H)
    B = M.g["BASE"]
    for (bx, bw, _h) in bays:
        for k in range(carts_per_bay):
            off = (k - (carts_per_bay - 1) * 0.5) * 1.5
            L.cart(B, bx + off, (y0 + y1) * 0.5 - 0.3, z + .04, math.pi)
        if chargers:
            L.wall_charger(M.g["WALLS_HIGH"], bx - bw * 0.3, y0 + 0.2, z)
            L.wall_charger(M.g["WALLS_HIGH"], bx + bw * 0.3, y0 + 0.2, z)
        B.box((0.12, 1.2, 0.01), (bx - bw * 0.5 + 0.2, y1 + 0.8, LEVEL + 0.012), "line_yellow")
        # just inside its door, short of the carts parked further in: where the cart boy drives one
        # in to put it away, and out of again (ClubLife's washing)
        B.marker("BARN_BAY", bx, y1 - 1.7, z + 0.04, 0.0)
    M.cols.append(("barn%d" % len(M.cols), (x1 - x0, y1 - y0, H + rise), ((x0 + x1) * 0.5, (y0 + y1) * 0.5, z + (H + rise) * 0.5)))


def cart_pickups(B, xs, y):
    """Temporary pickup positions for carts being collected by arriving flights."""
    for k, x in enumerate(xs):
        B.marker("CARTPICK", x, y, LEVEL, 0.0, k + 1)


def cart_line(M, x0, x1, ys, turn_y):
    """Behind the clubhouse by the end of the walk: the carts waiting for the golfers, single file
    and nose to tail in a two-row snake on a concrete pad. The head is at the plot's back edge on
    row x0 -- they drive straight off it onto the course -- the line runs up row x0, round the
    turn at turn_y and back down row x1 to the tail, where the cart boy brings more in from the
    course side. A CARTLINE marker at each cart's middle, head first, facing the way the line
    moves (toward the head); CARTTURN at the turn. `ys` run from the head up the row."""
    B = M.g["BASE"]
    lo, hi = min(x0, x1) - 1.3, max(x0, x1) + 1.3
    L.pave(B, lo, min(ys) - 1.6, hi, turn_y + 1.4, LEVEL, "concrete")
    top = LEVEL + 0.045
    mid = (x0 + x1) * 0.5
    B.box((0.12, turn_y - 0.8 - (min(ys) - 1.4), 0.01), (mid, (turn_y - 0.8 + min(ys) - 1.4) * 0.5, top), "line")  # between the rows
    for x in (lo + 0.15, hi - 0.15):
        B.box((0.12, turn_y + 1.2 - (min(ys) - 1.4), 0.01), (x, (turn_y + 1.2 + min(ys) - 1.4) * 0.5, top), "line")
    L.arrow(B, x0, ys[0] - 0.2 + (ys[1] - ys[0]) * 0.5, top - 0.012, math.pi, s=0.6)  # toward the head
    L.arrow(B, x1, ys[0] - 0.2 + (ys[1] - ys[0]) * 0.5, top - 0.012, 0.0, s=0.6)
    L.ground_text(B, "CARTS", x0, min(ys) - 1.1, top, 0.42, "line", math.pi)
    k = 0
    for x, rz, order in ((x0, math.pi, list(ys)), (x1, 0.0, list(reversed(ys)))):
        for y in order:
            B.marker("CARTLINE", x, y, LEVEL, rz, k + 1)
            k += 1
    B.marker("CARTTURN", mid, turn_y, LEVEL, 0.0, 1.0)


def yard_props(B, x, y, z, tires=2, pallets=1):
    for i in range(tires):
        L.tires(B, x + i * 0.9, y, z, 3 + i % 2)
    for i in range(pallets):
        L.pallet(B, x + 0.6, y + 1.5 + i * 0.2, z + i * 0.15, 0.2)


def barn_approach(M, x0, x1, front):
    # Two metres at ~6 degrees: garage floor to the ground-level entrance apron.
    high, low = M.floor_z + .04, .013
    verts=[(x0,front,high),(x1,front,high),(x1,front+2,low),(x0,front+2,low),
           (x0,front,-.07),(x1,front,-.07),(x1,front+2,-.07),(x0,front+2,-.07)]
    M.g["BASE"].poly(verts,[(0,1,2,3),(4,7,6,5),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)],"concrete")


def cart_barn_l1(M):
    """Two indoor cart bays with a small gravel entrance apron."""
    # The surrounding lawn is the actual graded course terrain.
    B, G = M.g["BASE"], M.g["WALLS_HIGH"]
    M.eave = 2.9
    L.pave(B, -6.0, -4.0, 9.0, 1.2, -.03, "gravel", h=.06)
    barn_block(M, -5.5, 5.5, -12.0, -4.0, 2.9,
               [(-2.6, 3.6, 2.5), (2.6, 3.6, 2.5)], 3.4,
               back=[garage(5.5, 3.6, 2.5)], left=[garage(4.0, 3.0, 2.5)])
    G.box((0.5, 0.25, 0.7), (5.65, -6.0, M.floor_z + 1.4), "electric")
    for reel_x in (-4.95, 0.0, 4.95):
        L.hose_reel(G, reel_x, -3.87, M.floor_z)  # (on the front wall's pier by the row it washes the carts in)
    B.marker("SPOT", 0.0, -2.0, LEVEL, 0.0)
    B.marker("SPOT", 4.0, -6.5, M.floor_z, -math.pi / 2)
    barn_approach(M, -5.5, 5.5, -4.0)
    cart_pickups(B, [2.6, 5.0, 7.4], -0.6)


def cart_barn_l2(M):
    """Four indoor charging bays; open garage frontage and a compact return apron."""
    # The surrounding lawn is the actual graded course terrain.
    B, G = M.g["BASE"], M.g["WALLS_HIGH"]
    M.eave = 3.6
    L.pave(B, -12.5, -5.5, 12.5, 1.4, -.03, "asphalt", h=.06)
    barn_block(M, -12.0, 12.0, -15.0, -5.5, 3.6,
               [(-8.4, 4.2, 3.0), (-2.8, 4.2, 3.0), (2.8, 4.2, 3.0), (8.4, 4.2, 3.0)], 4.6,
               right=[door(4.75, 1.0, 2.2), garage(7.8, 2.0, 2.8)],
               back=[garage(6.0, 4.0, 3.0), garage(18.0, 4.0, 3.0)], carts_per_bay=2)
    G.box((0.12, 3.0, 0.7), (12.2, -7.8, M.floor_z + 2.9), "sign_green")
    G.text("CART BARN", "+x", (12.26, -7.8, M.floor_z + 2.9), 0.42, "gold")
    for reel_x in (-5.6, 0.0, 5.6):
        L.hose_reel(G, reel_x, -5.37, M.floor_z)  # (on the front wall's middle pier, behind the row)
    for x in (-8.4, 2.8):
        B.marker("SPOT", x + 1.2, -6.4, M.floor_z, math.pi)
    B.marker("SPOT", 9.0, -2.0, LEVEL, 0.0)
    barn_approach(M, -12.0, 12.0, -5.5)
    cart_pickups(B, [-6.0, -3.6, -1.2, 1.2, 3.6, 6.0], -1.0)


def cart_barn_l3(M):
    """Expanded indoor garage, with raised doors and a small side service room."""
    # The surrounding lawn is the actual graded course terrain.
    B, G, R = M.g["BASE"], M.g["WALLS_HIGH"], M.g["ROOF"]
    M.eave = 3.8
    L.pave(B, -14.5, -6.0, 22.5, 1.0, -.03, "asphalt", h=.06)
    barn_block(M, -14.0, 14.0, -16.0, -6.0, 3.8,
               [(-10.4, 4.4, 3.1), (-3.5, 4.4, 3.1), (3.5, 4.4, 3.1), (10.4, 4.4, 3.1)], 5.4,
               left=[garage(5.0, 4.0, 3.1)],
               back=[], carts_per_bay=2)  # Solid rear wall; no rear garage doors at level 3.
    cross_gable(M, 0.0, -5.95, 8.0, 2.4, 4.6, windows=0)
    R.box((5.0, 0.16, 0.8), (0, -5.85, M.floor_z + 5.1), "sign_green")
    R.text("CART BARN", "+y", (0, -5.78, M.floor_z + 5.1), 0.52, "gold")
    for reel_x in (-6.95, 0.0, 6.95):
        L.hose_reel(G, reel_x, -5.87, M.floor_z)  # (on the front wall's middle pier, behind the row)
    for dx in (-9.0, 9.0):
        L.dormer(M, dx, -7.6, M.floor_z + 4.4)
    wing(M, 14.0, 22.0, -15.0, -7.0, 3.2, "y", 4.2,
         [door(2.0, 1.0, 2.2), garage(5.4, 3.6, 2.8)],
         [garage(4.0, 3.6, 2.8)], [], [garage(4.0, 3.6, 2.8)], floor_mat="concrete")
    L.cart(B, 16.6, -11.0, M.floor_z + .04, math.pi)
    for x in (-10.4, 3.5):
        B.marker("SPOT", x + 1.4, -6.8, M.floor_z, math.pi)
    B.marker("SPOT", 18.5, -8.6, M.floor_z, 0.0)
    barn_approach(M, -14.0, 14.0, -6.0)
    cart_pickups(B, [-6.0, -3.6, -1.2, 1.2, 3.6, 6.0], -2.4)


def cart_barn_l4(M):
    """Fire-station style operations barn: all stored carts are inside the main building."""
    # The surrounding lawn is the actual graded course terrain.
    B, G, R = M.g["BASE"], M.g["WALLS_HIGH"], M.g["ROOF"]
    M.eave = 6.2
    x0, x1, y0, y1 = -6.0, 22.0, -21.0, -9.0
    z = M.floor_z
    bays = [-3.2, 2.0, 7.2, 12.4, 17.6]
    front = [garage(x1 - x, 4.2, 3.3) for x in bays]
    back = []  # Solid rear wall; no rear garage doors at level 4.
    wing(M, x0, x1, y0, y1, 6.2, "x", 5.2, front, back,
         [garage(3.3, 3.3, 3.0), garage(8.7, 3.3, 3.0)],
         [door(6.0, 1.2, 2.3)], floor_mat="concrete")
    from mathutils import Vector
    F = L.frame_matrix(Vector((-1, 0, 0)), Vector((0, 1, 0)), (0, y1 + 0.13, z))
    for at in (2.0, 9.2, 13.4, 18.0, 24.5):
        wx = x1 - at
        G.fbox(F, (-wx, 0.0, 4.6), (1.1, 0.06, 1.4), "glass")
        G.fbox(F, (-wx, 0.05, 5.37), (1.4, 0.1, 0.14), "trim")
        G.fbox(F, (-wx, 0.07, 3.83), (1.4, 0.14, 0.1), "trim")
    for gx in (3.0, 15.0):
        cross_gable(M, gx, y1 + 0.05, 6.0, 1.6, 4.0)
    for dx in (-2.0, 9.0, 19.5):
        L.dormer(M, dx, y1 - 1.9, z + 6.8)
    G.box((6.0, 0.16, 0.55), (7.8, y1 + .2, z + 3.6), "sign_green")
    G.text("CART OPERATIONS", "+y", (7.8, y1 + .28, z + 3.6), .32, "gold")
    for reel_x in (-0.6, 4.6, 9.8):
        L.hose_reel(G, reel_x, y1 + 0.13, z)  # (on the pier between the middle doors, behind the row)
    # Three carts deep in each charging lane, fully within the main garage walls.
    for x in bays:
        for y in (-18.6, -15.5, -12.4):
            L.cart(B, x, y, z + .04, math.pi)
        for dx in (-1.2, 1.2):
            B.box((.07, 9.2, .006), (x + dx, -15.6, z + .044), "line_yellow")
        L.wall_charger(G, x + 2.0, y0 + .2, z)
        B.marker("SPOT", x + 1.7, -10.2, z + .04, math.pi)
        B.marker("BARN_BAY", x, y1 - 1.0, z + .04, 0.0)
    # Only the short pickup apron remains outside; no canopy, porch or parking lot.
    L.pave(B, -6.5, -9.0, 22.5, -3.3, -.03, "asphalt", h=.06)
    B.marker("SPOT", 20.6, -5.0, LEVEL, math.pi)
    barn_approach(M, x0, x1, y1)
    cart_pickups(B, [-2.0, 2.0, 6.0, 10.0, 14.0, 18.0], -5.1)



def range_bays(M, x0, x1, y, z, n, grass=False, dividers=True, tvs=False, rz=0.0):
    B = M.g["BASE"]
    step = (x1 - x0) / n
    for i in range(n):
        x = x0 + (i + 0.5) * step
        L.mat_bay(B, x, y, z, rz, grass)
        B.marker("RANGE_BAY", x, y, z, rz, 1.0)  # a golfer's bay (FacilityBuilder rig "range_bays")
        if dividers and i > 0:
            L.divider(B, x - step * 0.5, y - 0.2, z)
        if tvs and i % 1 == 0:
            # Rotate the display's +Y face toward the golfer on this bay's mat.
            L.tv_post(B, x + step * 0.35, y - 0.45, z, math.atan2(step * 0.35, 0.45))
        # The visiting golfer brings and removes their own bag for this bay.


def driving_range_l1(M):
    """Minimalist Tee: a concrete walk and turf strip of mats, black dividers, bag stands,
    a caged ball dispenser and a bench."""
    plot_lawn(M, "driving_range")
    B = M.g["BASE"]
    L.pave(B, -26.0, 4.0, 26.0, 12.5, LEVEL, "turf")
    L.pave(B, -26.0, 2.0, 26.0, 5.0, LEVEL, "concrete")
    range_bays(M, -24.0, 24.0, 9.4, LEVEL + 0.03, 10)
    L.ball_dispenser(B, -28.5, 6.0, LEVEL, math.pi)
    for x in (-12.0, 6.0):
        L.bench(B, x, 2.6, LEVEL, 0.0)
    for x in (-26.0, 26.0):
        L.chainlink(B, (x, 2.0), (x, 12.5), LEVEL, 1.6, 2.5)
    B.marker("SPOT", -27.0, 4.0, LEVEL, 0.0)


def driving_range_l2(M):
    """Modern Covered Bays: a black steel canopy with wood-clad ends, screens at each bay,
    a glass reception pavilion, a ball kiosk and a lot."""
    plot_lawn(M, "driving_range")
    B, G, R = M.g["BASE"], M.g["WALLS_HIGH"], M.g["ROOF"]
    z = LEVEL + 0.04
    L.pave(B, -21.0, 2.5, 21.0, 12.5, LEVEL, "concrete", h=0.06)
    # twelve bays under the canopy (two more than the tee line below it): a post at every other
    # bay divider, a bench behind each pair
    bays = 12
    for x in [-20.0 + i * 40.0 / (bays // 2) for i in range(bays // 2 + 1)]:
        for y in (3.0, 8.2):
            L.steel_post(G, x, y, z, 3.6, 0.28)
    L.flat_roof(R, -20.8, 2.8, 20.8, 12.2, z + 3.6, 0.4, 0.6)
    for x in (-20.8, 20.8):
        L.clad_wall(G, (x, 2.8), (x, 7.0), z, 3.6)
    range_bays(M, -20.0, 20.0, 10.4, z, bays, tvs=True)
    for i in range(bays // 2):
        L.bench(B, -20.0 + (i + 0.5) * 40.0 / (bays // 2), 4.6, z, 0.0)
    # glass reception pavilion
    px0, px1, py0, py1 = -30.0, -22.0, 1.0, 9.0
    L.pave(B, px0, py0, px1, py1, LEVEL, "concrete", h=0.06)
    L.glass_wall(G, (px0, py1), (px1, py1), z, 3.2)
    L.glass_wall(G, (px1, py1), (px1, py0), z, 3.2)
    L.clad_wall(G, (px0, py0), (px1, py0), z, 3.2)
    L.clad_wall(G, (px0, py0), (px0, py1), z, 3.2, "charcoal")
    L.flat_roof(R, px0, py0, px1, py1, z + 3.2, 0.35, 0.4)
    L.counter(B, (px0 + px1) * 0.5, py0 + 2.0, z, 3.0, body="wood_light")
    L.ball_dispenser(B, -24.0, -0.5, LEVEL, math.pi, cage=False)
    L.pave(B, -24.6, -13.0, 24.6, 0.5, LEVEL, "asphalt")  # (centred on the bays, the ball machine on it)
    L.parking_lines(B, -21.6, 21.6, -13.0, -8.0, LEVEL)
    B.marker("SPOT", (px0 + px1) * 0.5, py0 + 1.0, z, 0.0)
    B.marker("SPOT", -2.0, 6.0, z, 0.0)
    M.cols += [("pavilion", (px1 - px0, py1 - py0, 3.6), ((px0 + px1) * 0.5, (py0 + py1) * 0.5, z + 1.8))]


def range_lounge_level(M, x0, x1, y0, y1, z_floor, h, n_lounges, deck=False, doors=None):
    """Open-front upper hitting bays, with seating behind the swing and shot corridors. `doors`
    ({x0 or x1: y}): an open corridor in that end wall at y from the stair's
    landing or bridge (built by the level) into the walk behind the mats, kept clear inside."""
    doors = doors or {}
    B, G, R = M.g["BASE"], M.g["WALLS_HIGH"], M.g["ROOF"]
    B.box((x1 - x0 + 0.4, y1 - y0 + 0.4, 0.35), ((x0 + x1) * 0.5, (y0 + y1) * 0.5, z_floor - 0.17), "concrete")
    B.box((x1 - x0 + 0.42, y1 - y0 + 0.42, 0.06), ((x0 + x1) * 0.5, (y0 + y1) * 0.5, z_floor - 0.37), "wood_light")
    B.box((x1 - x0, y1 - y0, 0.03), ((x0 + x1) * 0.5, (y0 + y1) * 0.5, z_floor + 0.015), "wood_floor")
    front = y1 + (2.0 if deck else 0.0)
    for x in (x0, x1):
        if x in doors:
            range_lounge_door(M, x, doors[x], y0, y1, z_floor, h, 1 if x == x1 else -1)
        else:
            L.clad_wall(G, (x, y0), (x, y1), z_floor, h, "charcoal")
    L.clad_wall(G, (x0, y0), (x1, y0), z_floor, h, "wood_light")
    L.flat_roof(R, x0, y0, x1, front, z_floor + h, 0.4, 0.8)
    step = (x1 - x0) / n_lounges
    # the privacy panels end behind the hitting area, a walk wide enough for two between them and
    # the bays' dividers; the roof's posts stand at their ends, out of it
    end = min(y1 - 2.8, front - 3.6)
    post_y = min(front - 3.0, end)
    for i in range(n_lounges + 1):
        if all(abs(x0 + i * step - d) > 0.01 for d in doors):  # (none in front of a doorway: the wall holds the roof there)
            L.steel_post(G, x0 + i * step, post_y, z_floor, h, 0.16)
    G.box((x1 - x0, 0.20, 0.20), ((x0 + x1) * 0.5, post_y, z_floor + h - 0.10), "iron")
    for i in range(n_lounges):
        cx = x0 + (i + 0.5) * step
        L.sofa(B, cx - 0.9, (y0 + y1) * 0.5 - 0.6, z_floor, 1.6, "leather", 0.0)
        L.table(B, cx - 0.9, (y0 + y1) * 0.5 + 0.6, z_floor, 1.0, 0.6, 0.45)
        L.mat_bay(B, cx, front - 1.0, z_floor)
        B.marker("RANGE_BAY_UP", cx, front - 1.0, z_floor, 0.0, 1.0)  # a golfer's bay upstairs (FacilityBuilder rig "range_bays_up")
        tv = min(step * .35, 2.0) * (-1 if i == n_lounges - 1 and x1 in doors else 1)  # (clear of a doorway by it)
        L.tv_post(B, cx + tv, front - 1.45, z_floor, math.atan2(tv, .45))
        if i > 0:
            # Privacy panels end behind the hitting area; low dividers run alongside it.
            B.box((0.06, end - y0, 2.2), (x0 + i * step, (y0 + end) * 0.5, z_floor + 1.1), "charcoal")
            L.divider(B, x0 + i * step, front - 1.0, z_floor, h=0.9, d=1.6)
    if deck:
        B.box((x1 - x0, 2.0, 0.12), ((x0 + x1) * 0.5, y1 + 1.0, z_floor - 0.06), "deck")
        for x in (x0, x1):
            L.railing(G, (x, y1), (x, front), z_floor, 1.05, "iron", 2.0, 0.5)
    # A low edge strip leaves each bay's front entirely open for shots.
    B.box((x1 - x0, 0.12, 0.06), ((x0 + x1) * 0.5, front - 0.06, z_floor + 0.03), "rubber")
    B.box((x1-x0, 0.12, 0.012), ((x0+x1)*0.5, front-0.06, z_floor+0.066), "line_yellow")
    range_safety_net(B, x0, x1, front, z_floor, n_lounges)


def range_lounge_door(M, x, yc, y0, y1, z_floor, h, out, w=2.2, head=2.4):
    """A range lounge's end wall along x (y0..y1) with a doorway at yc: the wall either side and
    over it, with an open corridor through to the landing; `out`
    (+1 / -1): which way along x is outside."""
    from mathutils import Vector
    G = M.g["WALLS_HIGH"]
    d0, d1 = yc - w * 0.5, yc + w * 0.5
    L.clad_wall(G, (x, y0), (x, d0), z_floor, h, "charcoal")
    L.clad_wall(G, (x, d1), (x, y1), z_floor, h, "charcoal")
    L.clad_wall(G, (x, d0), (x, d1), z_floor + head, h - head, "charcoal")
    for y in (d0, d1):
        G.box((0.3, 0.1, head), (x, y, z_floor + head * 0.5), "trim")
    G.box((0.3, w + 0.2, 0.1), (x, yc, z_floor + head), "trim")
    # Open connecting passage: no door leaves across the upper-floor walking route.


def range_stair_up(M, sx, y_foot, z, z_top, lx, y_front, idx, rail_sides=(), rail_back=()):
    """An outside stair from the ground at y_foot up toward +y to a range's upper floor, and a
    landing (or a bridge between two pavilions) from its top on to y_front, across lx (x0, x1):
    railed along x = each of `rail_sides`, its front and the stretches `rail_back` ((x0, x1)) of
    its back edge by the stair, on posts. Markers for the people: RANGE_STAIR at its foot and
    RANGE_STAIRTOP on the landing, `idx` pairing them."""
    B, G = M.g["BASE"], M.g["WALLS_HIGH"]
    top = y_foot + L.ext_stairs(B, sx, y_foot, z, z_top, 1.4, 1)
    B.box((lx[1] - lx[0], y_front - top, 0.3), ((lx[0] + lx[1]) * 0.5, (top + y_front) * 0.5, z_top - 0.15), "deck")
    for x in rail_sides:
        L.railing(G, (x, top), (x, y_front), z_top, 1.05, "iron", 2.0, 0.5)
    L.railing(G, (lx[0], y_front), (lx[1], y_front), z_top, 1.05, "iron", 2.0, 0.5)
    for a, b in rail_back:
        L.railing(G, (a, top), (b, top), z_top, 1.05, "iron", 2.0, 0.5)
    for x in (lx[0] + 0.12, lx[1] - 0.12):
        L.steel_post(G, x, y_front - 0.12, z, z_top - z - 0.3, 0.16)
    B.marker("RANGE_STAIR", sx, y_foot - 0.5, z, 0.0, idx)
    B.marker("RANGE_STAIRTOP", sx, top + 0.6, z_top, 0.0, idx)


def range_safety_net(G, x0, x1, front, z_floor, bays, reach=1.0, drop=0.18):
    """Open rope catch pockets below the deck, on padded arms at each bay divider."""
    from mathutils import Vector
    verts, faces = [], []
    def rope(points, radius):
        base = len(verts)
        for i, point in enumerate(points):
            p = Vector(point)
            tangent = Vector(points[min(i+1,len(points)-1)])-Vector(points[max(i-1,0)])
            tangent.normalize()
            side = tangent.cross(Vector((0,0,1))).normalized()
            up = tangent.cross(side).normalized()
            for j in range(4):
                q = p + radius*(side*math.cos(j*math.pi/2)+up*math.sin(j*math.pi/2))
                verts.append(tuple(q))
        for i in range(len(points)-1):
            for j in range(4):
                a=base+i*4+j; b=base+i*4+(j+1)%4
                faces.append((a,b,b+4,a+4))
    width=(x1-x0)/bays
    nu=max(2,math.ceil(width/.16)); nv=7
    for panel in range(bays):
        xa=x0+panel*width
        def p(u,v):
            return (xa+width*u, front+reach*v,
                    z_floor-.12-drop*v-.22*math.sin(math.pi*u)*math.sin(math.pi*v)-.07*math.sin(math.pi*u)*v)
        for i in range(nu+1):rope([p(i/nu,j/nv) for j in range(nv+1)],.007)
        for j in range(nv+1):rope([p(i/nu,j/nv) for i in range(nu+1)],.007)
        for v in (0,1):rope([p(i/nu,v) for i in range(nu+1)],.016)
    G.poly(verts,faces,"rubber")
    tilt=math.atan2(drop,reach)
    for i in range(bays+1):
        x=x0+i*width
        G.box((.14,math.hypot(reach,drop)+.10,.11),(x,front+reach*.5,z_floor-.12-drop*.5),"rubber",rx=-tilt)
        G.box((.08,.15,.30),(x,front-.02,z_floor-.25),"iron")


def driving_range_l3(M):
    """High-Tech Range: two storeys -- open bays below, open lounge bays above -- with
    a wood soffit, an outside stair, a glass kiosk and visitor golf carts. Below, nothing but
    the posts holding the lounge up: open at the back as well as the front."""
    plot_lawn(M, "driving_range")
    B, G = M.g["BASE"], M.g["WALLS_HIGH"]
    z = LEVEL + 0.04
    x0, x1, y0, y1 = -22.0, 22.0, 2.0, 12.0
    L.pave(B, x0 - 1.0, y0, x1 + 1.0, y1 + 0.5, LEVEL, "concrete", h=0.06)
    # Fourteen bays on the ground floor (two more than the level below); its posts line up with
    # every other bay divider.
    bays = 14
    for x in [x0 + 0.5 + i * (x1 - x0 - 1.0) / (bays // 2) for i in range(bays // 2 + 1)]:
        for y in (y0 + 0.2, y1 - 3.6):
            L.steel_post(G, x, y, z, 3.8, 0.32)
    range_bays(M, x0 + 0.5, x1 - 0.5, y1 - 1.4, z, bays, tvs=True)
    # the lounge bays above, up the stair at the east end and over its landing into them
    range_lounge_level(M, x0, x1, y0, y1, z + 4.0, 3.4, 8, doors={x1: y1 - 2.0})
    range_stair_up(M, x1 + 1.6, y0 + 0.4, z, z + 4.0, (x1, x1 + 2.3), y1, 1, rail_sides=(x1 + 2.3,), rail_back=((x1, x1 + 0.85),))
    kx0, kx1, ky0, ky1 = -31.0, -25.0, -7.0, -1.0
    L.pave(B, kx0, ky0, kx1, ky1, LEVEL, "concrete", h=0.06)
    L.glass_wall(G, (kx0, ky1), (kx1, ky1), z, 3.0)
    L.glass_wall(G, (kx1, ky1), (kx1, ky0), z, 3.0)
    L.clad_wall(G, (kx0, ky0), (kx1, ky0), z, 3.0)
    L.clad_wall(G, (kx0, ky0), (kx0, ky1), z, 3.0)
    L.flat_roof(M.g["ROOF"], kx0, ky0, kx1, ky1, z + 3.0, 0.35, 0.4)
    L.counter(B, (kx0 + kx1) * 0.5, ky0 + 1.4, z, 2.6, body="wood_light")
    L.ball_dispenser(B, kx1 + 1.6, (ky0 + ky1) * 0.5, LEVEL, -math.pi / 2)  # by the kiosk, its chute to the range
    for x in (-18.0, -15.5, -13.0):
        L.cart(B, x, -5.0, LEVEL, math.pi)
    L.pave(B, -35.0, -13.0, 20.0, -1.5, LEVEL, "asphalt")
    L.parking_lines(B, -12.0, 18.0, -13.0, -8.0, LEVEL)
    # the catch net down the right-hand side is FacilityBuilder's (like the top level's)
    B.marker("SPOT", (kx0 + kx1) * 0.5, ky0 + 0.6, z, 0.0)
    B.marker("SPOT", 0.0, 6.0, z + 4.0, 0.0)
    B.marker("SPOT", -8.0, 7.0, z, 0.0)
    M.cols += [("range", (x1 - x0, 0.6, 3.4), ((x0 + x1) * 0.5, y0 + 0.2, z + 5.7)), ("kiosk", (kx1 - kx0, ky1 - ky0, 3.4), ((kx0 + kx1) * 0.5, (ky0 + ky1) * 0.5, z + 1.7))]


def driving_range_l4(M):
    """Ultra-Prestige Complex: three linked two-storey glass pavilions with wood decks and
    outside stairs, lounge bays above, heated bays below (open front and back: only the posts
    hold the lounges up) and visitor golf cart parking.
    Terrain-following perimeter nets are supplied by FacilityBuilder at runtime."""
    plot_lawn(M, "driving_range")
    B, G = M.g["BASE"], M.g["WALLS_HIGH"]
    z = LEVEL + 0.04
    L.pave(B, -33.0, 1.0, 33.0, 13.0, LEVEL, "concrete", h=0.06)
    for (x0, x1, h) in ((-32.0, -12.0, 3.4), (-10.0, 10.0, 3.9), (12.0, 32.0, 3.4)):
        for x in [x0 + 0.4 + i * (x1 - x0 - 0.8) / 5 for i in range(6)]:
            for y in (2.2, 8.2):
                L.steel_post(G, x, y, z, 3.8, 0.3)
        range_bays(M, x0 + 0.4, x1 - 0.4, 10.4, z, 5, tvs=True)
        for i in range(5):
            B.cyl(0.2, 0.2, 0.35, (x0 + (i + 0.5) * (x1 - x0) / 5, 9.0, z + 3.3), "fire", segs=10)
        # (a doorway at each end by a stair up between it and its neighbour)
        range_lounge_level(M, x0, x1, 2.0, 11.6, z + 4.0, h, 5, deck=True, doors={x: 10.0 for x in (x0, x1) if abs(x) < 20.0})
    # the stairs up from the back between the pavilions, each to a bridge on to both decks
    for k, sx in enumerate((-11.0, 11.0)):
        range_stair_up(M, sx, 2.4, z, z + 4.0, (sx - 1.0, sx + 1.0), 13.6, k + 1, rail_back=((sx - 1.0, sx - 0.72), (sx + 0.72, sx + 1.0)))
    L.pave(B, -35.0, -13.0, 35.0, 0.0, LEVEL, "asphalt")
    L.ball_dispenser(B, -6.0, -0.8, LEVEL, math.pi)  # its chute toward the car park, where they come from
    L.parking_lines(B, -30.0, 30.0, -13.0, -8.5, LEVEL)
    for x in (-29.0, -26.5, -24.0, 24.0, 26.5, 29.0):
        L.cart(B, x, -5.0, LEVEL, math.pi)
    for x in (-22.0, 0.0, 22.0):
        B.marker("SPOT", x, 6.0, z + 4.0, 0.0)
        B.marker("SPOT", x + 3.0, 7.0, z, 0.0)
    M.cols += [("pavilions", (66.0, 0.6, 3.6), (0.0, 2.0, z + 5.8))]


# ================================================================ parking lot
# Stalls 2.6 m wide and 5.4 m deep off 6.6 m aisles, in rows along x; the entrance is on the
# front (+y) edge. Spaces per level match data/economy.json: 24, 48, 64, 80.

STALL_W, STALL_D, AISLE = 2.6, 5.4, 6.6


def stall_row(B, x0, n, y_mouth, d, z, lines=True, stop="concrete", ada=0):
    """`n` stalls side by side from x0 along +x, open onto the aisle at y_mouth and running
    `d` (+1 / -1) away from it: painted bay lines and a wheel stop at the head of each, and an
    AUTO marker where a car parks nose in (Godot fills a share of them). The first `ada` are
    accessible spaces: the symbol painted in by the aisle (ADA_PAINT) and the sign at the head
    (ADA_SIGN: props/ada_sign.glb, tools/blender/build_ada_sign.py), both facing the aisle."""
    if lines:
        for i in range(n + 1):
            B.box((0.12, STALL_D - 0.4, 0.01), (x0 + i * STALL_W, y_mouth + d * (STALL_D - 0.4) * 0.5, z + 0.005), "line")
    for i in range(n):
        x = x0 + (i + 0.5) * STALL_W
        B.box((1.8, 0.16, 0.12), (x, y_mouth + d * (STALL_D - 0.7), z + 0.06), stop, bevel=0.02)
        B.marker("AUTO", x, y_mouth + d * STALL_D * 0.47, z, 0.0 if d > 0 else math.pi)
        if i < ada:
            B.marker("ADA_PAINT", x, y_mouth + d * 1.1, z, 0.0 if d > 0 else math.pi)
            B.marker("ADA_SIGN", x, y_mouth + d * (STALL_D + 0.6), LEVEL, 0.0 if d > 0 else math.pi)


def kerb(B, x0, y0, x1, y1, z, h=0.15, w=0.22, skip=None, west_exit=None):
    """A concrete kerb round the rectangle, broken along the front wherever `skip` -- an (x0, x1)
    gap, or a list of them (the driveways in and out) -- crosses it."""
    edges=[((x0,y0),(x1,y0)),((x1,y0),(x1,y1))]
    if west_exit:
        edges += [((x0,y0),(x0,west_exit[0])),((x0,west_exit[1]),(x0,y1))]
    else:edges.append(((x0,y0),(x0,y1)))
    for a,b in edges:
        L.pave(B,min(a[0],b[0])-w*.5,min(a[1],b[1])-w*.5,max(a[0],b[0])+w*.5,max(a[1],b[1])+w*.5,z,"concrete",h)
    gaps = [] if not skip else ([skip] if isinstance(skip[0], (int, float)) else sorted(skip))
    cut = x0
    for g0, g1 in gaps + [(x1, x1)]:
        if g0 - cut > 0.3:
            L.pave(B, cut - w * 0.5, y1 - w * 0.5, g0 + w * 0.5, y1 + w * 0.5, z, "concrete", h)
        cut = max(cut, g1)


def island(B, x0, y0, x1, y1, z, tree=None):
    """A planted island: a kerb with mulch inside, a tree or a shrub in it."""
    L.pave(B, x0, y0, x1, y1, z, "concrete", 0.17)
    L.pave(B, x0 + 0.2, y0 + 0.2, x1 - 0.2, y1 - 0.2, z + 0.02, "mulch", 0.17)
    cx, cy = (x0 + x1) * 0.5, (y0 + y1) * 0.5
    if tree:
        B.marker("PLANT_" + tree, cx, cy, z + 0.15, (cx * 12.9898 + cy * 78.233) % math.tau, 0.6)
    else:
        L.shrub(B, cx, cy, z + 0.15, min(x1 - x0, y1 - y0) * 0.4)


def light_pole(B, x, y, z, h=7.0, heads=2):
    """A parking-lot light: a tall steel pole with one or two box heads."""
    B.cyl(0.25, 0.25, 0.5, (x, y, z), "concrete", segs=10)
    B.cyl(0.08, 0.1, h, (x, y, z + 0.5), "iron", segs=8)
    for k in range(heads):
        s = 1 if k == 0 else -1
        B.box((0.9, 0.12, 0.08), (x + s * 0.45, y, z + h + 0.5), "iron")
        B.box((0.55, 0.32, 0.12), (x + s * 0.85, y, z + h + 0.44), "iron")
        B.box((0.45, 0.24, 0.02), (x + s * 0.85, y, z + h + 0.37), "bulb")


def parking_sign(B, x, y, z, facing="+y"):
    """A blue 'P' sign on a post."""
    B.cyl(0.05, 0.05, 2.3, (x, y, z), "iron", segs=8)
    B.box((0.7, 0.06, 0.7), (x, y, z + 2.55), "sign_blue")
    B.text("P", facing, (x, y + (0.04 if facing == "+y" else -0.04), z + 2.55), 0.55, "white", 0.02)


def lot_way(B, x, y, word, z=LEVEL):
    """A driveway's sign by the road: IN or OUT in white on a green panel on a post."""
    B.cyl(0.05, 0.05, 1.5, (x, y, z), "iron", segs=8)
    B.box((0.9, 0.06, 0.42), (x, y, z + 1.7), "sign_green", bevel=0.01)
    B.text(word, "+y", (x, y + 0.04, z + 1.7), 0.26, "white", 0.02)


ARROW = 2.5  # an L.arrow's length (m), tail to tip


def lot_ways(B, x_in, x_out, y_from, y_to, z):
    """The driveways' markings: arrows into the lot on the way in, out of it on the way out -- two
    along a drive long enough to keep them apart, else one in its middle -- and their IN / OUT
    signs at the road (the drive in on the right, out on the left)."""
    span = y_to - y_from
    for f in ((0.3, 0.7) if span * 0.4 >= ARROW + 0.8 else (0.5,)):
        y = y_from + span * f
        L.arrow(B, x_in, y, z, math.pi)  # toward the stalls
        L.arrow(B, x_out, y, z, 0.0)  # toward the road
    lot_way(B, x_in + AISLE * 0.5 + 0.7, y_to - 0.6, "IN")
    lot_way(B, x_out - AISLE * 0.5 - 0.7, y_to - 0.6, "OUT")


def lot_rows(B, x0, n, ys, z, lines=True, stop="concrete", ada=0):
    """Rows of stalls: ys = [(y_mouth, d), ...], the front row (by the road and the walk) last;
    returns how many spaces. Its first `ada` stalls are the accessible ones (stall_row)."""
    for k, (ym, d) in enumerate(ys):
        stall_row(B, x0, n, ym, d, z, lines, stop, ada if k == len(ys) - 1 else 0)
    return n * len(ys)


def starter_lot_paving(B):
    """One rounded gravel outline; both six-metre roads meet the circulation aisle cleanly."""
    outline=[(-22.4,-9.2),(22.6,-9.2),(22.6,24),(16.6,24),(16.6,9.2),(-16.2,9.2),(-16.2,24),(-22.4,24)]
    path=[]
    for i,p in enumerate(outline):
        prev,nxt=outline[i-1],outline[(i+1)%len(outline)]
        da,db=math.dist(p,prev),math.dist(p,nxt)
        radius=min(1.25,da*.25,db*.25)
        a=(p[0]+(prev[0]-p[0])*radius/da,p[1]+(prev[1]-p[1])*radius/da)
        b=(p[0]+(nxt[0]-p[0])*radius/db,p[1]+(nxt[1]-p[1])*radius/db)
        for j in range(7):
            t=j/6
            path.append(((1-t)**2*a[0]+2*t*(1-t)*p[0]+t*t*b[0],(1-t)**2*a[1]+2*t*(1-t)*p[1]+t*t*b[1]))
    top=LEVEL+.04
    verts=[(x,y,top) for x,y in path]+[(x,y,LEVEL-.02) for x,y in path]
    n=len(path);faces=[tuple(range(n))]
    for i in range(n):faces.append((i,(i+1)%n,(i+1)%n+n,i+n))
    B.poly(verts,faces,"gravel")
    # Low edging contains the gravel; the two road mouths remain open.
    for a,b in zip(path,path[1:]+path[:1]):
        if min(a[1],b[1])>23.9:continue
        length=math.dist(a,b)
        B.box((length+.02,.12,.07),((a[0]+b[0])/2,(a[1]+b[1])/2,top+.015),"wood_dark",rz=math.atan2(b[1]-a[1],b[0]-a[0]))


def lot_side_exit(B,xa,med,z):
    """Second exit at the outer end of the rear aisle, within the original plot footprint."""
    y=-med*.5-STALL_D-AISLE*.5
    L.pave(B,-33.0,y-AISLE*.5,xa+.2,y+AISLE*.5,LEVEL,"asphalt",.06)
    for edge in (-1,1):
        L.pave(B,-33.0,y+edge*AISLE*.5-.11,xa-.05,y+edge*AISLE*.5+.11,LEVEL,"concrete",.15)
    L.arrow(B,xa+AISLE*.6,y,z,math.pi*.5)
    B.marker("LOT_EXIT",-32.8,y,z,math.pi*.5)


def parking_lot_l1(M):
    """Gravel Lot: 24 spaces on a gravel pad (two rows off one aisle) with timber wheel stops,
    a gravel drive in from the front, a split-rail fence along the road and a P sign."""
    B = M.g["BASE"]
    z = LEVEL + 0.04
    starter_lot_paving(B)
    n = lot_rows(B, -15.6, 12, [(-3.3, -1), (3.3, 1)], z, lines=False, stop="wood", ada=1)  # (accessible: one in 25)
    assert n == 24
    L.split_rail(B, (-32.5, 23.4), (-23.2, 23.4), LEVEL)
    L.split_rail(B, (-15.4, 23.4), (15.8, 23.4), LEVEL)
    lot_ways(B, 19.6, -19.3, 9.2, 24.0, z)
    parking_sign(B, 15.4, 22.6, LEVEL)
    for x in (-12.0, 4.0):
        L.lamp(B, x, 9.9, LEVEL)
    L.shrub(B, 24.6, 20.5, LEVEL, 1.0)
    L.shrub(B, 14.2, 18.0, LEVEL, 0.8)


def parking_lot_l2(M):
    """Paved Lot: 48 spaces in four rows on asphalt with painted bays, concrete wheel stops and
    kerbs, a raised median with two light poles, and a paved drive in from the front."""
    B = M.g["BASE"]
    z = LEVEL + 0.04
    run, med = 12 * STALL_W, 0.6
    x0 = -run * 0.5
    hy = 2 * STALL_D + AISLE + med * 0.5
    xa, xb = x0 - AISLE, -x0 + AISLE
    L.pave(B, xa, -hy - 0.2, xb, hy + 0.2, LEVEL, "asphalt", 0.06)
    L.pave(B, xb - AISLE, hy, xb, 24.0, LEVEL, "asphalt", 0.06)
    L.pave(B, xa, hy, xa + AISLE, 24.0, LEVEL, "asphalt", 0.06)  # the way out
    kerb(B, xa - 0.1, -hy - 0.3, xb + 0.1, hy + 0.3, LEVEL, skip=[(xa - 0.2, xa + AISLE), (xb - AISLE, xb + 0.2)], west_exit=(-med*.5-STALL_D-AISLE,-med*.5-STALL_D))
    lot_side_exit(B,xa,med,z)
    L.pave(B, x0, -med * 0.5, x0 + run, med * 0.5, LEVEL, "concrete", 0.16)
    m = med * 0.5
    n = lot_rows(B, x0, 12, [(-hy + STALL_D, -1), (-m - STALL_D, 1), (m + STALL_D, -1), (hy - STALL_D, 1)], z, ada=2)
    assert n == 48
    for x in (-8.0, 8.0):
        light_pole(B, x, 0.0, LEVEL + 0.14)
    lot_ways(B, xb - AISLE * 0.5, xa + AISLE * 0.5, hy, 24.0, z + 0.01)
    parking_sign(B, xb - AISLE - 0.8, 23.0, LEVEL)
    L.split_rail(B, (-32.5, 23.4), (xa - 1.4, 23.4), LEVEL)
    L.split_rail(B, (xa + AISLE + 1.4, 23.4), (xb - AISLE - 1.2, 23.4), LEVEL)
    for x in (-27.0, -11.0, -4.0, 3.0):
        L.shrub(B, x, 21.0, LEVEL, 0.9)


def parking_lot_l3(M):
    """Landscaped Lot: 64 spaces in four rows of sixteen, each row broken by a tree island in
    the middle and ended with planted islands; a hedge median with light poles, kerbs, a
    monument sign at the entrance and a shrub border along the road."""
    B = M.g["BASE"]
    z = LEVEL + 0.04
    half_n, med = 8, 2.0
    run = 2 * half_n * STALL_W + STALL_W  # with the middle island
    x0 = -run * 0.5
    hy = 2 * STALL_D + AISLE + med * 0.5
    xa, xb = x0 - 2.0 - AISLE, -x0 + 2.0 + AISLE
    L.pave(B, xa, -hy - 0.2, xb, hy + 0.2, LEVEL, "asphalt", 0.06)
    L.pave(B, xb - AISLE, hy, xb, 24.0, LEVEL, "asphalt", 0.06)
    L.pave(B, xa, hy, xa + AISLE, 24.0, LEVEL, "asphalt", 0.06)  # the way out
    kerb(B, xa - 0.1, -hy - 0.3, xb + 0.1, hy + 0.3, LEVEL, skip=[(xa - 0.2, xa + AISLE), (xb - AISLE, xb + 0.2)], west_exit=(-med*.5-STALL_D-AISLE,-med*.5-STALL_D))
    lot_side_exit(B,xa,med,z)
    rows = [(-hy + STALL_D, -1), (-med * 0.5 - STALL_D, 1), (med * 0.5 + STALL_D, -1), (hy - STALL_D, 1)]
    n = lot_rows(B, x0, half_n, rows, z, ada=3) + lot_rows(B, x0 + (half_n + 1) * STALL_W, half_n, rows, z)
    assert n == 64
    # islands: the middle of each row, and both ends
    for ym, d in rows:
        y0, y1 = sorted((ym, ym + d * STALL_D))
        island(B, x0 + half_n * STALL_W + 0.15, y0 + 0.15, x0 + (half_n + 1) * STALL_W - 0.15, y1 - 0.15, LEVEL, "red_maple_A")
        for xe in (x0 - 2.0, x0 + run):
            island(B, xe + 0.15, y0 + 0.15, xe + 1.85, y1 - 0.15, LEVEL)
    # the median: kerbed, a low hedge and the light poles
    L.pave(B, x0, -med * 0.5, x0 + run, med * 0.5, LEVEL, "concrete", 0.16)
    L.pave(B, x0 + 0.2, -med * 0.5 + 0.2, x0 + run - 0.2, med * 0.5 - 0.2, LEVEL + 0.02, "mulch", 0.16)
    L.hedge(B, x0 + 0.6, 0.0, x0 + run * 0.5 - 2.4, 0.0, LEVEL + 0.15, 0.8, 0.7)
    L.hedge(B, x0 + run * 0.5 + 2.4, 0.0, x0 + run - 0.6, 0.0, LEVEL + 0.15, 0.8, 0.7)
    for x in (-run * 0.5 + 1.2, 0.0, run * 0.5 - 1.2):
        light_pole(B, x, 0.0, LEVEL + 0.14)
    lot_ways(B, xb - AISLE * 0.5, xa + AISLE * 0.5, hy, 24.0, z + 0.01)
    for x in (-20.0, -12.0, -4.0, 4.0, 12.0):
        L.shrub(B, x, 21.6, LEVEL, 1.0)


def parking_roof_panel(R, x0, x1, ya, yb, za, zb, seams=0.72):
    """Folded standing-seam zinc: a pitched skin, deep edge flashing and visible ribs.
    Everything is batched into ROOF, including the underside purlins."""
    L.PALETTE.setdefault("canopy_zinc", ("687975", 0.55, 0.55, 0, 1))
    L.PALETTE.setdefault("canopy_flashing", ("424f4d", 0.48, 0.55, 0, 1))
    length = math.hypot(yb - ya, zb - za)
    slope = math.atan2(zb - za, yb - ya)
    cx, cy, cz = (x0 + x1) * 0.5, (ya + yb) * 0.5, (za + zb) * 0.5
    R.box((x1 - x0, length, 0.075), (cx, cy, cz), "canopy_zinc", rx=slope)
    # Raised folds run down the fall of the roof, not across the drainage path.
    count = max(1, math.ceil((x1 - x0) / seams))
    for i in range(count + 1):
        x = x0 + (x1 - x0) * i / count
        R.box((0.035, length, 0.052), (x, cy, cz + 0.055), "canopy_flashing", rx=slope)
    for y, z in ((ya, za), (yb, zb)):
        R.box((x1 - x0 + 0.04, 0.08, 0.19), (cx, y, z - 0.055), "canopy_flashing")
    for x in (x0, x1):
        R.box((0.09, length + 0.06, 0.19), (x, cy, cz - 0.055), "canopy_flashing", rx=slope)
    for t in (0.12, 0.4, 0.7, 0.94):
        R.box((x1 - x0 - 0.08, 0.09, 0.12),
              (cx, ya + (yb - ya) * t, za + (zb - za) * t - 0.12), "iron")


def parking_roof_member(G, x, ya, za, yb, zb, width=0.16, depth=0.22):
    G.box((width, math.hypot(yb - ya, zb - za), depth),
          (x, (ya + yb) * 0.5, (za + zb) * 0.5), "iron",
          rx=math.atan2(zb - za, yb - ya))


def parking_roof_gutter(R, x0, x1, y, z):
    """Open U-section gutter, end caps and a rolled upper lip."""
    cx = (x0 + x1) * 0.5
    R.box((x1 - x0, 0.19, 0.025), (cx, y, z - 0.12), "canopy_flashing")
    for side in (-1, 1):
        R.box((x1 - x0, 0.025, 0.13), (cx, y + side * 0.085, z - 0.065), "canopy_flashing")
        R.box((x1 - x0, 0.035, 0.025), (cx, y + side * 0.085, z), "canopy_zinc")
    for x in (x0, x1):
        R.box((0.025, 0.19, 0.13), (x, y, z - 0.065), "canopy_flashing")


def carport(M, x0, n, y_mouth, d, z, every=4):
    """Rear-supported cantilever canopies: pitched metal, steel frames and drainage.
    Posts stay behind the wheel stops and between the bays; the aisle remains open."""
    G, R = M.g["WALLS_HIGH"], M.g["ROOF"]
    x1 = x0 + n * STALL_W
    head = y_mouth + d * (STALL_D + 0.25)
    front, rear = y_mouth - d * 0.4, head + d * 0.35
    high, low = z + 3.88, z + 3.12
    parking_roof_panel(R, x0 - 0.3, x1 + 0.3, front, rear, high, low)
    # A rear girder and pitched cantilever rafters actually carry the roof.
    girder = low - 0.21
    G.box((x1 - x0 + 0.16, 0.26, 0.30), ((x0 + x1) * 0.5, head, girder), "iron")
    for i in range(0, n + 1, every):
        x = x0 + i * STALL_W
        L.steel_post(G, x, head, z, girder - z, 0.22)
        G.box((0.42, 0.42, 0.055), (x, head, z + 0.0275), "canopy_flashing")
        parking_roof_member(R, x, rear, low - 0.25, front, high - 0.25, depth=0.28)
        # Triangular knee braces support the six-metre cantilever above car height.
        arm_y = rear + (front - rear) * 0.7
        arm_z = low + (high - low) * 0.7 - 0.39
        parking_roof_member(R, x, head, z + 2.48, arm_y, arm_z, width=0.12, depth=0.14)
    # Intermediate rafters divide the long row into believable structural bays.
    for i in range(every // 2, n, every):
        parking_roof_member(R, x0 + i * STALL_W, rear, low - 0.22, front, high - 0.22, width=0.11, depth=0.18)
    gutter_y = rear + d * 0.12
    parking_roof_gutter(R, x0 - 0.3, x1 + 0.3, gutter_y, low - 0.03)
    for i in (0, 8, 16, n):
        if i > n:
            continue
        x = x0 + i * STALL_W + (0.16 if i < n else -0.16)
        R.cyl(0.045, 0.045, low - z - 0.22, (x, gutter_y, z + 0.08), "canopy_flashing", segs=8)
        for h in (0.6, 2.1):
            R.box((0.13, 0.07, 0.035), (x, gutter_y, z + h), "iron")


def parking_lot_l4(M):
    """Valet Plaza: 80 spaces in four rows of twenty with a hedged median, every row under a
    carport, a covered valet drop-off on a stone-paved front lane with its booth, EV chargers,
    light poles and a monument sign at the entrance."""
    B, G, R = M.g["BASE"], M.g["WALLS_HIGH"], M.g["ROOF"]
    z = LEVEL + 0.04
    n_side, med = 20, 2.4
    run = n_side * STALL_W
    x0 = -run * 0.5
    hy = 2 * STALL_D + AISLE + med * 0.5
    xa, xb = x0 - AISLE, -x0 + AISLE
    L.pave(B, xa, -hy - 0.2, xb, hy + 0.2, LEVEL, "asphalt", 0.06)
    # the front: a drop-off lane in from the right, a stone walk along the road
    lane0, lane1 = hy + 0.2, 21.6
    L.pave(B, -16.0, lane0, xb, lane1, LEVEL, "asphalt", 0.06)
    L.pave(B, xb - AISLE, lane1, xb, 24.0, LEVEL, "asphalt", 0.06)
    L.pave(B, xa + AISLE + 0.2, lane1, xb - AISLE - 0.2, 23.9, LEVEL, "stone", 0.12)
    L.pave(B, xa + AISLE + 0.2, lane0, -16.2, lane1, LEVEL, "stone", 0.12)
    L.pave(B, xa, hy, xa + AISLE, 24.0, LEVEL, "asphalt", 0.06)  # the way out
    kerb(B, xa - 0.1, -hy - 0.3, xb + 0.1, hy + 0.3, LEVEL, skip=[(xa - 0.2, xa + AISLE), (-16.0, xb + 0.2)], west_exit=(-med*.5-STALL_D-AISLE,-med*.5-STALL_D))
    lot_side_exit(B,xa,med,z)
    rows = [(-hy + STALL_D, -1), (-med * 0.5 - STALL_D, 1), (med * 0.5 + STALL_D, -1), (hy - STALL_D, 1)]
    n = lot_rows(B, x0, n_side, rows, z, ada=4)  # (by the stone walk to the valet stand)
    assert n == 80
    for ym, d in rows:
        carport(M, x0, n_side, ym, d, LEVEL)  # (the cars under cover, not a roof off to one side: user)
    # the median: a low hedge along it (no trees: they stood up through the carports; user), light poles
    L.pave(B, x0, -med * 0.5, x0 + run, med * 0.5, LEVEL, "concrete", 0.16)
    L.pave(B, x0 + 0.2, -med * 0.5 + 0.2, x0 + run - 0.2, med * 0.5 - 0.2, LEVEL + 0.02, "mulch", 0.16)
    for a, b in ((x0 + 1.0, -run * 0.25 - 1.0), (-run * 0.25 + 1.0, run * 0.25 - 1.0), (run * 0.25 + 1.0, x0 + run - 1.0)):  # (broken at the light poles)
        L.hedge(B, a, 0.0, b, 0.0, LEVEL + 0.15, 0.7, 0.6)
    for x in (-run * 0.25, run * 0.25):
        light_pole(B, x, 0.0, LEVEL + 0.14)
    for x in (xa + 1.0, xb - 1.0):
        for y in (-hy + 3.0, hy - 3.0):
            light_pole(B, x, y, LEVEL, heads=1)
    # the valet canopy over the drop-off lane, its booth and the key stand
    cz = LEVEL + 0.04
    for x in (-12.0, -3.0, 6.0):
        for y in (lane0 + 0.4, lane1 - 0.2):
            L.steel_post(G, x, y, cz, 4.2, 0.24)
    # A separate pitched arrival pavilion, with a ridge cap and framed soffit.
    eave0, eave1 = lane0 - 0.28, lane1 + 0.48
    ridge_y = (eave0 + eave1) * 0.5
    eave_z, ridge_z = cz + 4.34, cz + 5.25
    parking_roof_panel(R, -12.9, 6.9, eave0, ridge_y, eave_z, ridge_z)
    parking_roof_panel(R, -12.9, 6.9, ridge_y, eave1, ridge_z, eave_z)
    R.box((19.95, 0.28, 0.10), (-3.0, ridge_y, ridge_z + 0.09), "canopy_flashing")
    for y in (lane0 + 0.4, lane1 - 0.2):
        G.box((18.4, 0.22, 0.26), (-3.0, y, cz + 4.10), "iron")
    for x in (-12.0, -3.0, 6.0):
        for y, edge in ((lane0 + 0.4, eave0), (lane1 - 0.2, eave1)):
            parking_roof_member(R, x, edge, eave_z - 0.24, ridge_y, ridge_z - 0.24, depth=0.24)
    parking_roof_gutter(R, -12.9, 6.9, eave0 - 0.1, eave_z - 0.02)
    parking_roof_gutter(R, -12.9, 6.9, eave1 + 0.1, eave_z - 0.02)
    B.box((2.4, 1.8, 2.6), (-14.4, 22.6, LEVEL + 1.3), "wood_light", bevel=0.03)
    B.box((2.6, 2.0, 0.18), (-14.4, 22.6, LEVEL + 2.68), "charcoal")
    L.hip_roof(R, 2.4, 1.8, 0.38, (-14.4, 22.6), LEVEL + 2.92, mat="canopy_zinc", over=0.16, t=0.08)
    B.box((1.4, 0.04, 0.9), (-14.4, 21.68, LEVEL + 1.6), "glass")
    B.marker("SPOT", -12.6, 21.2, z, 0.0)
    # EV chargers at the heads of the front row's end bays
    for i in range(4):
        x = x0 + (n_side - 4 + i + 0.5) * STALL_W
        B.box((0.32, 0.26, 1.4), (x, hy + 0.55, LEVEL + 0.7), "white", bevel=0.03)
        B.box((0.22, 0.03, 0.3), (x, hy + 0.41, LEVEL + 1.15), "bulb")
    lot_ways(B, xb - AISLE * 0.5, xa + AISLE * 0.5, hy, 24.0, z + 0.01)  # (the way in runs on through the drop-off lane)


# ================================================================ the short game area
# The hardscape round the practice turf: paths, hitting mats, benches, a shade shelter, signs,
# walls and plantings. The greens, their collars, the bunkers and the cups and flags are the
# course's own -- Godot paints them onto the course with its brushes (FacilityBuilder
# PRACTICE_TURF, whose greens and bunkers sit where these leave room) -- and PRACTICE_CHIP
# markers are the mats golfers chip from.


def chip_mats(M, x0, y, count, target, gap=2.6):
    """Chipping spots in a row: PRACTICE_CHIP markers facing `target` (x, y), played off the
    grass itself -- no mats, no ball buckets."""
    B = M.g["BASE"]
    for i in range(count):
        x = x0 + i * gap
        tx, ty = target
        B.marker("PRACTICE_CHIP", x, y, LEVEL + 0.07, math.atan2(-(tx - x), ty - y), max(math.hypot(tx - x, ty - y), 1.0))


def practice_sign(M, x, y, text, w=2.6):
    B = M.g["BASE"]
    for dx in (-w * 0.42, w * 0.42):
        B.box((0.1, 0.1, 1.5), (x + dx, y, LEVEL + 0.75), "wood_dark")
    B.box((w, 0.07, 0.6), (x, y, LEVEL + 1.35), "sign_green", bevel=0.015)
    B.box((w + 0.1, 0.09, 0.05), (x, y, LEVEL + 1.67), "trim")
    B.text(text, "+y", (x, y + 0.045, LEVEL + 1.35), 0.26, "white", 0.02)


def shade_shelter(M, x, y, w, d, benches=2):
    """An open timber shelter on a stone floor: four posts, a pitched shingle roof, benches
    facing the greens (-y)."""
    B, R = M.g["BASE"], M.g["ROOF"]
    L.pave(B, x - w * 0.5 - 0.3, y - d * 0.5 - 0.3, x + w * 0.5 + 0.3, y + d * 0.5 + 0.3, LEVEL, "stone")
    for sx in (-1, 1):
        for sy in (-1, 1):
            B.box((0.18, 0.18, 2.6), (x + sx * (w * 0.5 - 0.15), y + sy * (d * 0.5 - 0.15), LEVEL + 1.3), "wood_dark")
    B.box((w, 0.16, 0.22), (x, y - d * 0.5 + 0.15, LEVEL + 2.6), "wood_dark")
    B.box((w, 0.16, 0.22), (x, y + d * 0.5 - 0.15, LEVEL + 2.6), "wood_dark")
    L.gable_wall(R, w, d, 0.9, (x, y), LEVEL + 2.7, "trim")
    L.gable_roof(R, w, d, 0.9, (x, y), LEVEL + 2.7, over=0.35)
    for i in range(benches):
        L.bench(B, x - w * 0.5 + w * (i + 0.5) / benches, y + 0.2, LEVEL + 0.06, math.pi)


def short_game_l1(M):
    """An open practice green, with no ornamental frontage or shelter."""
    M.g["BASE"].marker("SPOT", 0, 11.8, LEVEL)


def short_game_l2(M):
    """Putting and chipping greens with simple ground-level mats."""
    chip_mats(M, 10.4, 11.8, 3, (13.0, -5.5))
    M.g["BASE"].marker("SPOT", 0, 12.0, LEVEL)


def short_game_l3(M):
    """Open short-game practice, without a pavilion or raised landscaping."""
    chip_mats(M, 9.8, 12.4, 4, (14.0, -5.5))
    M.g["BASE"].marker("SPOT", 0, 12.0, LEVEL)


def short_game_l4(M):
    """Greens, bunkers and six simple hitting mats; an open grass frontage."""
    chip_mats(M, 8.0, 12.8, 6, (14.5, -5.0))
    M.g["BASE"].marker("SPOT", 0, 12.0, LEVEL)


MODELS = {
    "parking_lot_l1": ("parking_lot", parking_lot_l1),
    "parking_lot_l2": ("parking_lot", parking_lot_l2),
    "parking_lot_l3": ("parking_lot", parking_lot_l3),
    "parking_lot_l4": ("parking_lot", parking_lot_l4),
    "cart_barn_l1": ("cart_barn", cart_barn_l1),
    "cart_barn_l2": ("cart_barn", cart_barn_l2),
    "cart_barn_l3": ("cart_barn", cart_barn_l3),
    "cart_barn_l4": ("cart_barn", cart_barn_l4),
    "driving_range_l1": ("driving_range", driving_range_l1),
    "driving_range_l2": ("driving_range", driving_range_l2),
    "driving_range_l3": ("driving_range", driving_range_l3),
    "driving_range_l4": ("driving_range", driving_range_l4),
    "short_game_l1": ("short_game", short_game_l1),
    "short_game_l2": ("short_game", short_game_l2),
    "short_game_l3": ("short_game", short_game_l3),
    "short_game_l4": ("short_game", short_game_l4),
    "clubhouse_l1": ("clubhouse", clubhouse_l1),
    "clubhouse_l2": ("clubhouse", clubhouse_l2),
    "clubhouse_l3": ("clubhouse", clubhouse_l3),
    "clubhouse_l4": ("clubhouse", clubhouse_l4),
}


# ================================================================ export / preview

def export(M, path):
    # nudging one face can leave it level with another that moved: repeat until nothing clashes
    for k in range(5):
        moved = L.defight(list(M.C.all_objects))
        print("  pass %d: nudged %d faces out of z-fighting" % (k + 1, moved))
        if moved == 0:
            break
    bpy.ops.object.select_all(action="DESELECT")
    for ob in M.C.all_objects:
        ob.select_set(True)
    kw = dict(filepath=path, export_format="GLTF_SEPARATE", use_selection=True, export_apply=True, export_yup=True)
    try:
        bpy.ops.export_scene.gltf(export_keep_originals=True, **kw)
    except TypeError:
        bpy.ops.export_scene.gltf(**kw)


def plot_size(M, kind):
    return (88.0, 96.0) if M.name == "clubhouse_l4" else PLOTS[kind]


def paving_mask(M, kind, path):
    """Where the plot is built on -- paving, floors, decks, steps and beds -- traced straight down
    through the ground-level geometry (BASE and the walls) on a PAVE_CELL grid, as an 8-bit grey
    PNG (255 = built on). The rest of the plot is the course's own rough, which Godot grows its
    grass on. Pixel (i, j) is the cell centred on Godot-local x = -W/2 + (i + 0.5) * PAVE_CELL,
    z = -D/2 + (j + 0.5) * PAVE_CELL (row 0 along the front; Blender y = -z)."""
    from mathutils import Vector
    from mathutils.bvhtree import BVHTree
    W, D = plot_size(M, kind)
    dg = bpy.context.evaluated_depsgraph_get()
    trees = []
    for ob in M.C.all_objects:
        if ob.type == "MESH" and ob.name.split(".")[0] in ("BASE", "WALLS_HIGH"):
            trees.append((BVHTree.FromObject(ob, dg), ob.matrix_world.inverted(), ob.matrix_world))
    nx, nz = int(round(W / PAVE_CELL)), int(round(D / PAVE_CELL))
    top = LEVEL + 1.2
    rows = []
    built = 0
    for j in range(nz):
        y = D / 2 - (j + 0.5) * PAVE_CELL
        row = bytearray(nx)
        for i in range(nx):
            x = -W / 2 + (i + 0.5) * PAVE_CELL
            for t, inv, mw in trees:
                o = inv @ Vector((x, y, top))
                d = (inv.to_3x3() @ Vector((0, 0, -1))).normalized()
                hit = t.ray_cast(o, d, 1.5)
                if hit[0] is not None and (mw @ hit[0]).z > LEVEL - 0.25:
                    row[i] = 255
                    built += 1
                    break
        rows.append(bytes(row))
    raw = b"".join(b"\x00" + r for r in rows)

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", nx, nz, 8, 0, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)
    print("  paving: %d of %d cells built on" % (built, nx * nz))


WALK_STEP = 0.02  # m per grey level of a walk map
STEP_UP = 0.2  # a step's rise at most (m): walk_map lifts a cell over a step's edge onto the step
# What people stand on: floors, decks, steps, porches and paving (not furniture, railings,
# canopies, lamps or beds, which a ray down passes through to what's under them).
WALK_MATS = {"brick", "patio_brick", "stone", "wood_floor", "deck", "carpet", "tile", "gravel", "asphalt", "concrete",
             "wood", "wood_dark", "wood_light", "rubber", "mat_green", "turf", "grass"}


def walk_map(M, kind, path):
    """How high people stand across the plot -- on floors, decks, porches, steps and paving --
    traced straight down through BASE on the paving mask's grid, as an 8-bit grey PNG: 0 = the
    course's own ground, else the surface's height above the model's origin in WALK_STEP levels.
    Anything else in the way (furniture, railings, canopies, lamps, beds) is looked through.
    A cell over a step's edge takes the higher step (anything within STEP_UP above what's under its
    middle, just inside its edges): a step is narrower than a cell, and stood on the lower one
    people's feet go into the step above; a deck's or floor's edge, higher than that, doesn't
    lift the ground beside it."""
    from mathutils import Vector
    from mathutils.bvhtree import BVHTree
    W, D = plot_size(M, kind)
    dg = bpy.context.evaluated_depsgraph_get()
    trees = []
    for ob in M.C.all_objects:
        if ob.type == "MESH" and ob.name.split(".")[0] == "BASE":
            walk = [s.material is not None and s.material.name.split(".")[0] in WALK_MATS for s in ob.material_slots]
            mi = [p.material_index for p in ob.data.polygons]
            trees.append((BVHTree.FromObject(ob, dg), ob.matrix_world.inverted(), ob.matrix_world, walk, mi))
    nx, nz = int(round(W / PAVE_CELL)), int(round(D / PAVE_CELL))
    top = LEVEL + 6.0

    def surface(x, y):
        best = None
        for t, inv, mw, walk, mi in trees:
            o = inv @ Vector((x, y, top))
            d = (inv.to_3x3() @ Vector((0, 0, -1))).normalized()
            for _k in range(16):
                hit = t.ray_cast(o, d, 8.0)
                if hit[0] is None:
                    break
                wz = (mw @ hit[0]).z
                if wz < LEVEL - 0.25 or (best is not None and wz <= best):
                    break
                n = (mw.to_3x3() @ hit[1]).normalized()
                if n.z > 0.7 and hit[2] < len(mi) and walk[mi[hit[2]]]:
                    best = wz
                    break
                o = hit[0] + d * 0.003
        return best

    edge = PAVE_CELL * 0.45
    rows = []
    for j in range(nz):
        y = D / 2 - (j + 0.5) * PAVE_CELL
        row = bytearray(nx)
        for i in range(nx):
            x = -W / 2 + (i + 0.5) * PAVE_CELL
            best = surface(x, y)
            under = best if best is not None else LEVEL
            for dx, dy in ((edge, 0), (-edge, 0), (0, edge), (0, -edge)):
                h = surface(x + dx, y + dy)
                if h is not None and under < h <= under + STEP_UP and (best is None or h > best):
                    best = h
            if best is not None:
                row[i] = max(1, min(255, int(round(max(best, 0.0) / WALK_STEP))))
        rows.append(bytes(row))
    raw = b"".join(b"\x00" + r for r in rows)

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", nx, nz, 8, 0, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def door_check(M, name):
    """Every walk-through door and garden door: the walkable surface (walk_map's) a stride either
    side of it; a drop of more than a step with nothing to step down on is reported."""
    from mathutils import Vector
    from mathutils.bvhtree import BVHTree
    dg = bpy.context.evaluated_depsgraph_get()
    trees = []
    for ob in M.C.all_objects:
        if ob.type == "MESH" and ob.name.split(".")[0] == "BASE":
            walk = [s.material is not None and s.material.name.split(".")[0] in WALK_MATS for s in ob.material_slots]
            trees.append((BVHTree.FromObject(ob, dg), walk, [p.material_index for p in ob.data.polygons]))

    def surface(x, y):
        best = LEVEL
        for t, walk, mi in trees:
            o, d = Vector((x, y, M.floor_z + 1.0)), Vector((0, 0, -1))
            for _k in range(12):
                hit = t.ray_cast(o, d, 3.0)
                if hit[0] is None:
                    break
                if hit[1].z > 0.7 and hit[2] < len(mi) and walk[mi[hit[2]]]:
                    best = max(best, hit[0].z)
                    break
                o = hit[0] + d * 0.003
        return best
    bad = 0
    for op in M.openings:
        if not op["pass"]:
            continue
        cx, cy = op["c"]
        nx, ny = -op["u"][1], op["u"][0]
        for side in (surface(cx + nx * 0.55, cy + ny * 0.55), surface(cx - nx * 0.55, cy - ny * 0.55)):
            if op["z0"] - side > 0.25:
                print("DOOR %s: at (%.1f, %.1f) %.2f m above what's outside it" % (name, cx, cy, op["z0"] - side))
                bad += 1
                break
    print("DOORCHECK %s: %d doors, %d without a way down" % (name, sum(1 for o in M.openings if o["pass"]), bad))


def setup_preview():
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x = 1400
    sc.render.resolution_y = 820
    w = bpy.data.worlds.new("sky")
    w.use_nodes = True
    bg = w.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.5, 0.64, 0.82, 1)
    bg.inputs["Strength"].default_value = 0.7
    sc.world = w
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 4.0
    sun.data.angle = math.radians(2.0)
    sun.rotation_euler = (math.radians(48), math.radians(12), math.radians(150))
    sc.collection.objects.link(sun)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.lens = 40
    sc.collection.objects.link(cam)
    sc.camera = cam
    try:
        sc.view_settings.view_transform = "AgX"
    except Exception:
        pass
    return cam


TIER_PREVIEW = 2
_ASSETS = {}
_CATALOG = None


def _asset_mesh(kind):
    """The real asset behind a marker, for previews only: the club cart or a nature pack plant
    (its lightest LOD), imported once and joined into a single mesh."""
    global _CATALOG
    if kind in _ASSETS:
        return _ASSETS[kind]
    if kind.startswith("CLUB_") or kind == "SPOT":
        _ASSETS[kind] = None
        return None
    if kind.startswith("HEDGE_"):
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=os.path.join(OUT, "props", "hedge_tiles.glb"))
        for o in [o for o in bpy.data.objects if o not in before]:
            if o.type == "MESH" and o.name.split(".")[0].startswith("HEDGE_"):
                o.data.transform(o.matrix_world)
                _ASSETS[o.name.split(".")[0]] = o.data
            bpy.data.objects.remove(o)
        return _ASSETS.get(kind)
    if kind == "CART":
        path = os.path.join(OUT, "props", "golf_cart.glb")
    elif kind.startswith("MANNEQUIN_"):
        path = os.path.join(OUT, "props", "store_mannequin_" + kind[10:].lower() + ".glb")
    elif kind.startswith("SHIRT_"):
        path = os.path.join(OUT, "props", "hanging_" + kind[6:].lower() + ".glb")
    elif kind == "BAG":
        path = os.path.join(OUT, "props", "bags", "golf_bag_tour_navy.glb")
    elif kind == "FOUNTAIN":
        path = os.path.join(OUT, "props", "fountain.glb")
    elif kind in ("ADA_SIGN", "ADA_PAINT"):
        path = os.path.join(OUT, "props", kind.lower() + ".glb")
    else:
        if _CATALOG is None:
            import json
            with open(os.path.join(ROOT, "nature_pack", "catalog.json")) as f:
                _CATALOG = {a["id"]: a for a in json.load(f)["assets"]}
        a = _CATALOG.get(kind[len("PLANT_"):])
        if a is None:
            _ASSETS[kind] = None
            return None
        rel = a["lods"][-1]["path"] if a.get("lods") else a["path"]
        path = os.path.join(ROOT, "nature_pack", rel)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == "MESH"]
    me = None
    if meshes:
        for o in meshes:
            o.data = o.data.copy()
            o.data.transform(o.matrix_world)
            o.matrix_world.identity()
        bpy.ops.object.select_all(action="DESELECT")
        for o in meshes:
            o.select_set(True)
        bpy.context.view_layer.objects.active = meshes[0]
        if len(meshes) > 1:
            bpy.ops.object.join()
        me = bpy.context.view_layer.objects.active.data
    for o in new:
        if o.name in bpy.data.objects:
            bpy.data.objects.remove(o)
    _ASSETS[kind] = me
    return me


def populate_preview(M):
    for e in list(M.C.all_objects):
        if e.type != "EMPTY" or "marker" not in e:
            continue
        me = _asset_mesh(e["marker"])
        if me is None:
            continue
        ob = bpy.data.objects.new("PREV_" + e.name, me)
        M.C.objects.link(ob)
        ob.parent = e
        ob.matrix_parent_inverse.identity()


def render_views(name, M, kind, cam, out_dir):
    from mathutils import Vector
    sc = bpy.context.scene
    for lc in bpy.context.view_layer.layer_collection.children:
        lc.exclude = lc.name != name
    W, D = PLOTS[kind]
    target = Vector((0, -D * 0.22, 2.0))
    r = {"clubhouse": 30.0 if name.endswith("l1") else 48.0, "cart_barn": 34.0, "driving_range": 44.0, "parking_lot": 46.0, "short_game": 36.0}[kind]
    views = {"ext": (Vector((r * 0.8, -D * 0.22 + r * 1.0, r * 0.62)), target, ()),
             "cut": (Vector((r * 0.35, -D * 0.22 + r * 0.55, r * 0.9)), target + Vector((0, 0, -1.5)), ("ROOF", "WALLS_HIGH")),
             "back": (Vector((-r * 0.75, -D * 0.22 - r * 1.0, r * 0.5)), target + Vector((0, -D * 0.12, -1.0)), ())}
    if name == "cart_barn_l4":
        views["ext"] = (Vector((38, 30, 23)), Vector((8, -14, 3)), ())
        views["cut"] = (Vector((17, 7, 27)), Vector((8, -14, 0)), ("ROOF", "WALLS_HIGH"))
    def top(ob):
        while ob.parent is not None:
            ob = ob.parent
        return ob.name.split(".")[0]

    for rid, (rx0, ry0, rx1, ry1, rz_) in M.roomboxes:
        if rid in ("pro_shop", "restaurant") and "--rooms" in sys.argv:
            c = Vector(((rx0 + rx1) * 0.5, (ry0 + ry1) * 0.5, rz_))
            span = max(rx1 - rx0, ry1 - ry0)
            views["room_" + rid] = (c + Vector((span * 0.35, span * 0.55, span * 0.75 + 2.0)), c, ("ROOF", "WALLS_HIGH"))
    for vname, (eye, tgt, hide) in views.items():
        for ob in M.C.all_objects:
            base = top(ob)
            hidden = base in hide or base.startswith("COL_")
            if base.startswith("ROOM_"):
                hidden = not base.endswith("_T%d" % TIER_PREVIEW)
            ob.hide_render = hidden
        cam.location = eye
        cam.rotation_euler = (tgt - eye).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = os.path.join(out_dir, "%s_%s_t%d.png" % (name, vname, TIER_PREVIEW))
        bpy.ops.render.render(write_still=True)


def main():
    global TIER_PREVIEW
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = argv[argv.index("--only") + 1].split(",") if "--only" in argv else list(MODELS)
    previews = argv[argv.index("--previews") + 1] if "--previews" in argv else ""
    if "--tier" in argv:
        TIER_PREVIEW = int(argv[argv.index("--tier") + 1])
    do_export = "--no-export" not in argv
    bpy.ops.wm.read_factory_settings(use_empty=True)
    os.makedirs(OUT, exist_ok=True)
    if "--bucket" in argv:
        # the range's ball bucket on its own (props/range_bucket.glb): the one a golfer carries
        # from the ball dispenser to their bay, its foot at the origin, its bail across x
        M = new_model("range_bucket", 0.0)
        L.range_bucket(M.g["BASE"], 0.0, 0.0, 0.0)
        M.finish()
        bpy.ops.object.select_all(action="DESELECT")
        for ob in M.C.all_objects:
            ob.select_set(True)
        bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "props", "range_bucket.glb"), export_format="GLB", use_selection=True, export_apply=True, export_yup=True)
        print("BUILT range_bucket")
        return
    built = []
    for name in only:
        kind, fn = MODELS[name]
        M = new_model(name, FLOOR_H.get(kind, 0.6))
        fn(M)
        for furnish in M.deferred:
            furnish()
        M.finish()
        if "--check-doors" in argv:
            door_check(M, name)
        if do_export:
            export(M, os.path.join(OUT, name + ".gltf"))
            paving_mask(M, kind, os.path.join(OUT, name + "_paving.png"))
            walk_map(M, kind, os.path.join(OUT, name + "_walk.png"))
        tris = sum(len(p.vertices) - 2 for ob in M.C.all_objects if ob.type == "MESH" for p in ob.data.polygons)
        print("BUILT %s: %d tris" % (name, tris))
        built.append((name, M, kind))
    if previews:
        os.makedirs(previews, exist_ok=True)
        cam = setup_preview()
        for name, M, kind in built:
            populate_preview(M)
            render_views(name, M, kind, cam, previews)
    if do_export and set(only) == set(MODELS):
        src = os.path.join(OUT, "source")
        os.makedirs(src, exist_ok=True)
        open(os.path.join(src, ".gdignore"), "w").close()
        for lc in bpy.context.view_layer.layer_collection.children:
            lc.exclude = False
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(src, "facilities.blend"), compress=True)
    print("DONE")


main()

