"""Parametric 2-iron utility head, unbranded: a hollow body with a Callaway Apex UT-like face
and toe that rolls round toward the back, and a back after the Mizuno Pro Fli-Hi: thick along
the sole up to a crisp ridge, then dropping into a thin blade-like top, a round weight plug
low on the toe, and the loft, "18°", stamped on the sole by the toe.
(The Apex-style back with plate, screws and slot is archived in v2_apex_plate/.)

Headless:  freecadcmd -c "exec(open(r'C:/Users/willi/Documents/FreeCAD/GolfHead/build_utility_iron.py').read())"
GUI:       open this file in FreeCAD and run it as a macro (or exec() it through the FreeCAD
           MCP); in the GUI the parts are coloured and the view is fitted.

Units are mm. Address position, right-handed: ground plane z = 0, the face points at the
target (-Y), the toe is -X and the shaft rises toward +X at the lie angle. (Everything is
drawn left-handed - toe +X - and build() mirrors it at the end.)

The whole head - blade, heel and hosel - is ONE loft, so the hosel grows out of the heel
with no seam: the blade's cross-sections run from the toe to the heel, then morph into the
round hosel along two guide curves (the top line sweeping up into the hosel's toe side, the
heel's bottom edge sweeping up into its underside), then continue up the hosel to its top.
The toe is rounded by trimming with the face silhouette.

The blade cross-sections are drawn in "face coordinates" (the face is the plane y = 0 standing
upright, x heel -> toe, z up the face; the ground there is the line z = y * tan(loft)) and laid
back by the loft into address. Every section has the same number of points, segment by
segment, so the loft maps face to face, sole to sole and top line to top line.
"""
import math
import os

import FreeCAD as App
import Part
from FreeCAD import Vector as V

OUT_DIR = os.environ.get("GOLFHEAD_OUT", r"C:\Users\willi\Documents\FreeCAD\GolfHead")
DOC_NAME = "UtilityIron2U"

# ---- parameters ----------------------------------------------------------------------
LOFT = 18.0        # deg
LIE = 60.0         # deg, shaft to ground
HEEL_H = 35.0      # face height at the heel end of the top line (along the face)
TOE_H = 49.5       # face height toward the toe
SOLE_W = 22.0      # sole width mid-blade
SOLE_W_HEEL = 17.0
SOLE_W_TOE = 19.0
TOP_T = 5.5        # top line thickness: a thin, blade-like top over a thick lower body
BLADE_TAPER = 2.2  # how fast the back falls in above the lower body (1 = an even wedge)
# Toward the heel the back fills out, so the neck grows out of a full section into the round
# hosel instead of leaving a dent between the thin upper blade and the hosel: from HEEL_FILL_X
# to NECK_X the shelf and the hollow above it fill in up to a line from the lower body to the
# top line, bowed out by HEEL_BULGE, and the ridge's crease fades away.
HEEL_FILL_X = 32.0
HEEL_BULGE = 0.6
OFFSET = 3.0       # leading edge behind the front of the hosel
HOSEL_R = 6.9      # hosel outer radius where it turns round (tapers 0.35 to the top)
HOSEL_TOP_Z = 72.0 # hosel top height above the ground
HOSEL_GROUND_X = 10.0  # where the shaft axis would meet the ground plane
HOSEL_ROUND_Z = 40.0   # the neck is fully round from this height up
NECK_X = 16.0      # the blade's own sections run heel-ward to here, then the neck morph starts
                   # (from 16, the heel sweeps up into the hosel instead of turning a corner)
NECK_PULL = 0.55   # how tightly the neck's guide curves hug their corners (smaller = rounder)
BORE_R = 4.7       # 0.370" parallel tip bore
BORE_DEPTH = 38.0
FERRULE_H = 13.0
GROOVE_PITCH = 3.5
GROOVE_W = 0.8
GROOVE_D = 0.4
WALL = 2.6         # hollow body wall / face thickness
EDGE_R = 0.6       # rounding on the toe edges
R_LE, R_TF, R_TB = 1.2, 0.8, 1.6  # leading edge, top-face and top-back corner radii
STEEL_DENSITY = 7.85e-3  # g / mm^3

# points per segment of every cross-section, starting at the leading edge, going round
# counter-clockwise seen from the toe (along the sole, up the back, over the top, down the face)
SEGMENTS = (("le", 4), ("sole", 16), ("back_lo", 8), ("back_hi", 11), ("tb", 4), ("top", 5), ("tf", 4),
            ("face", 14))
N_PTS = sum(n for _, n in SEGMENTS)
SOLE_SPLIT = (2, 3, 3, 3, 3, 2)  # points per key-point interval along the sole (sums to "sole")
BACK_LO_SPLIT = (2, 3, 3)        # ... up the lower body to the ridge (sums to "back_lo")
BACK_HI_SPLIT = (2, 3, 3, 3)     # ... from the ridge up the blade (sums to "back_hi")
# every ring's loft curves start at the ridge point, the first point of "back_hi", with a
# corner there, so the loft has a crisp crease along the ridge; they are split again mid-face,
# where the surface is flat and the join cannot show
SEAM = 4 + 16 + 8
FACE_SPLIT = N_PTS - 7
# toe -> heel, evenly spaced: the loft spaces its sections evenly in its own parameter, so
# uneven gaps made the sole and back wave by +-0.25 mm between sections
BLADE_X = [92.0 - 4.0 * k for k in range(20)]
assert BLADE_X[-1] == NECK_X
NECK_T = [k / 9 for k in range(1, 9)]

G = math.tan(math.radians(LOFT))  # ground slope in face coordinates
CL, SL = math.cos(math.radians(LOFT)), math.sin(math.radians(LOFT))
AXIS = V(-math.cos(math.radians(LIE)), 0, math.sin(math.radians(LIE)))  # up the shaft
ACROSS = V(math.sin(math.radians(LIE)), 0, math.cos(math.radians(LIE)))  # across it, toe-up


def smooth(t):
    t = min(max(t, 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


TOP_RUN = 62.0  # the top line rises from x = 8 to x = 70, easing level into the toe


def top_h(x):
    """Top line height along the face at x (face coordinates), slope-continuous throughout."""
    rise = TOE_H - HEEL_H
    if x < 8.0:
        return HEEL_H - (8.0 - x) * rise * math.pi / (2.0 * TOP_RUN)
    if x > 8.0 + TOP_RUN:
        return TOE_H
    return HEEL_H + rise * math.sin(math.pi / 2.0 * (x - 8.0) / TOP_RUN)


def heel_fill(x):
    """How far the back has filled out at x: 0 along the blade, 1 at NECK_X."""
    return 1.0 - smooth((x - NECK_X) / (HEEL_FILL_X - NECK_X))


def sole_w(x):
    if x < 30.0:
        return SOLE_W_HEEL + (SOLE_W - SOLE_W_HEEL) * smooth((x - 4.0) / 26.0)
    if x <= 55.0:
        return SOLE_W
    return SOLE_W - (SOLE_W - SOLE_W_TOE) * smooth((x - 55.0) / 25.0)


def camber(x):
    """Heel-to-toe sole camber: the sole rises a little toward heel and toe."""
    return 0.0006 * (x - 40.0) ** 2


def bezier2(a, c, b, n):
    """n points of the quadratic Bezier a-c-b, start included, end excluded."""
    return [a * (1 - t) ** 2 + c * (2 * t * (1 - t)) + b * (t * t) for t in (k / n for k in range(n))]


def bezier3(p0, p1, p2, p3, t):
    s = 1 - t
    return p0 * (s ** 3) + p1 * (3 * s * s * t) + p2 * (3 * s * t * t) + p3 * (t ** 3)


def counts():
    return dict(SEGMENTS)


# ---- blade cross-sections (face coordinates) ---------------------------------------------
def blade_points(x, back_shift=0.0):
    """N_PTS points round the blade's cross-section at x. back_shift moves the back (not the
    sole or face) straight back, for the detail layers: a number, or f(x, z) giving the shift
    at each height z up the back (face coordinates)."""
    n = counts()
    H = top_h(x)
    sw = sole_w(x)
    c = camber(x)

    def sole(y, lift):
        return G * y + lift + c

    z_le = 1.6 + c
    key = [(0.0, z_le), (1.0, sole(1.0, 0.22))]
    for f, lift in ((0.19, 0.35), (0.43, 0.05), (0.62, 0.0), (0.81, 0.35)):
        key.append((sw * f, sole(sw * f, lift)))
    key += [(sw - 1.2, sole(sw - 1.2, 1.1)), (sw, sole(sw, 2.6))]
    i_te = len(key) - 1
    zb = sole(sw, 2.6)
    shift = back_shift if callable(back_shift) else (lambda _x, _z: back_shift)
    # the back, thick at the bottom and blade-like at the top, after the Mizuno Pro Fli-Hi: a
    # full lower body bulging past the sole, leaning in up to the ridge; there the surface
    # breaks (a crisp crease), drops in steeply (the shelf), and curves concavely into a thin
    # upper blade that tapers (BLADE_TAPER) into the top line
    yr, zr = ridge_point(x, sw, zb)
    lower = [(sw + 1.0, zb + 3.8), (sw - 0.6, zb + 8.5), (yr, zr)]
    y1, z1 = yr - RIDGE_DROP, zr + RIDGE_SHELF_H
    upper = [(yr, zr), (y1, z1)]
    for t in (0.35, 0.7):
        f = 1.0 - (1.0 - t) ** BLADE_TAPER
        upper.append((y1 + (TOP_T - y1) * f, z1 + (H - z1) * t))
    upper.append((TOP_T, H))
    # toward the heel (heel_fill) the hollows fill in: every back point from where the lower body
    # leans in up to the top line moves out (never in) toward the line between those two, bowed
    # out by HEEL_BULGE, so by the neck the shelf is gone and the back is one full curve
    fill = heel_fill(x)
    (ya, za), (yt, zt) = lower[1], upper[-1]

    def filled(y, z):
        s = (z - za) / (zt - za)
        return y + max(ya + (yt - ya) * s + HEEL_BULGE * 4.0 * s * (1.0 - s) - y, 0.0) * fill

    lower[2] = upper[0] = (filled(yr, zr), zr)
    upper[1:-1] = [(filled(y, z), z) for y, z in upper[1:-1]]
    key += [(y + shift(x, z), z) for y, z in lower]
    upper = [(y + shift(x, z), z) for y, z in upper]

    # the two curves meet at the ridge with their directions pinned there (the lower body's
    # lean arriving, the shelf's drop leaving): left free, the lower one swung in and back out
    # to the ridge point, leaving a fin the loft could not close
    def tan(a, b):
        return (V(x, b[0], b[1]) - V(x, a[0], a[1])).normalize()

    # (unit tangents, unscaled: the default chord-length parameters run at unit speed; FreeCAD's
    # own tangent scaling looped the lower curve 7 mm under the sole)
    lo = Part.BSplineCurve()  # leading edge, sole, lower body, up to the ridge
    lo.interpolate(Points=[V(x, y, z) for y, z in key], InitialTangent=tan(key[0], key[1]),
                   FinalTangent=tan(key[-2], key[-1]), Scale=False)
    hi = Part.BSplineCurve()  # from the ridge up the blade to the top line
    hi.interpolate(Points=[V(x, y, z) for y, z in upper], InitialTangent=tan(upper[0], upper[1]),
                   FinalTangent=tan(upper[-2], upper[-1]), Scale=False)
    lo_knots, hi_knots = lo.getKnots(), hi.getKnots()  # the parameter of every key point
    assert len(lo_knots) == len(key) and len(hi_knots) == len(upper)
    u0 = lo.FirstParameter
    hi_len = hi.length()

    def chain(curve, us, ks):
        """Samples locked to the key points: ks[i] points over each span us[i] -> us[i + 1],
        evenly by arc length within the span, so no sample slides past a feature from one
        section to the next (that made the loft lumpy)."""
        out = []
        for ua, ub, k in zip(us, us[1:], ks):
            span = curve.length(ua, ub)
            out += [curve.value(curve.parameterAtDistance(span * i / k, ua)) for i in range(k)]
        return out

    def line(a, b, k):
        return [a + (b - a) * (i / k) for i in range(k)]

    yt = upper[-1][0]
    u_le = lo.parameterAtDistance(R_LE, u0)
    u_tb = hi.parameterAtDistance(hi_len - R_TB, hi.FirstParameter)
    pts = bezier2(V(x, 0, z_le + R_LE), V(x, 0, z_le), lo.value(u_le), n["le"])
    pts += chain(lo, [u_le] + lo_knots[2:i_te + 1], SOLE_SPLIT)  # past key 1: it sits inside R_LE
    pts += chain(lo, lo_knots[i_te:], BACK_LO_SPLIT)
    pts += chain(hi, hi_knots[:-1] + [u_tb], BACK_HI_SPLIT)       # its first point is the ridge
    pts += bezier2(hi.value(u_tb), V(x, yt, H), V(x, yt - R_TB, H), n["tb"])
    pts += line(V(x, yt - R_TB, H), V(x, R_TF, H), n["top"])
    pts += bezier2(V(x, R_TF, H), V(x, 0, H), V(x, 0, H - R_TF), n["tf"])
    pts += line(V(x, 0, H - R_TF), V(x, 0, z_le + R_LE), n["face"])
    return pts


def to_addr_pt(p, drop):
    """Face coordinates -> address: lay back by the loft, sole on the ground."""
    return V(p.x, p.y * CL + p.z * SL, -p.y * SL + p.z * CL - drop)


def to_address(shape, drop):
    shape = shape.copy()
    shape.rotate(V(0, 0, 0), V(1, 0, 0), -LOFT)
    shape.translate(V(0, 0, -drop))
    return shape


def ground_drop():
    return min(-p.y * SL + p.z * CL for x in BLADE_X for p in blade_points(x))


def leading_edge_y(drop):
    return min(to_addr_pt(p, drop).y for x in (30, 39, 48) for p in blade_points(x)[:6])


def meet(p, dp, q, dq):
    """Where the lines p + a*dp and q + b*dq cross, in the XZ plane."""
    det = dp.x * (-dq.z) - dp.z * (-dq.x)
    rx, rz = q.x - p.x, q.z - p.z
    a = (rx * (-dq.z) - rz * (-dq.x)) / det
    return V(p.x + a * dp.x, 0, p.z + a * dp.z)


# ---- the one loft: blade, neck, hosel -------------------------------------------------------
def head_sections(drop, axis_y, back_shift=0.0):
    """Point rings from the toe to the hosel top, address coordinates."""
    rings = [[to_addr_pt(p, drop) for p in blade_points(x, back_shift)] for x in BLADE_X]
    s0 = rings[-1]  # the heel-most blade section, at NECK_X
    s0b = [to_addr_pt(p, drop) for p in blade_points(NECK_X + 6.0)]  # for the guide tangents

    def ends(ring):
        lo = min(ring, key=lambda p: p.z)
        hi = max(ring, key=lambda p: p.z)
        return V(lo.x, 0, lo.z), V(hi.x, 0, hi.z)

    b0, p0 = ends(s0)
    b0b, p0b = ends(s0b)
    ground = V(HOSEL_GROUND_X, axis_y, 0)

    def on_axis(z):
        return ground + AXIS * (z / AXIS.z)

    c1 = on_axis(HOSEL_ROUND_Z)
    c1_flat = V(c1.x, 0, c1.z)
    b1, p1 = c1_flat - ACROSS * HOSEL_R, c1_flat + ACROSS * HOSEL_R

    # guide curves: the top line into the hosel's toe side, the heel's bottom into its underside
    def guide(start, start_dir, end):
        corner = meet(start, start_dir, end, -AXIS)
        return (start, start + start_dir * (NECK_PULL * (corner - start).Length),
                end - AXIS * (NECK_PULL * (corner - end).Length), end)

    top_guide = guide(p0, (p0 - p0b).normalize(), p1)
    bottom_guide = guide(b0, (b0 - b0b).normalize(), b1)

    # each point's place on the round hosel: its angle round the heel section
    ys = [p.y for p in s0]
    yc, wy = (max(ys) + min(ys)) / 2, (max(ys) - min(ys)) / 2
    h0 = p0.z - b0.z
    f0 = [(p.z - b0.z) / h0 for p in s0]
    phi = [math.atan2((f - 0.5) / 0.5, (p.y - yc) / wy) for p, f in zip(s0, f0)]
    yr = [axis_y + HOSEL_R * math.cos(a) for a in phi]
    fr = [(1 + math.sin(a)) / 2 for a in phi]

    crease = [1.0 - heel_fill(x) for x in BLADE_X]  # how crisp each ring's ridge crease is: full
    # along the blade, fading with the shelf toward the heel
    for t in NECK_T:
        b = bezier3(*bottom_guide, t)
        p = bezier3(*top_guide, t)
        s = smooth(t)
        rings.append([b + (p - b) * (f0[i] + (fr[i] - f0[i]) * s) + V(0, s0[i].y + (yr[i] - s0[i].y) * s, 0)
                      for i in range(N_PTS)])
        crease.append(crease[len(BLADE_X) - 1] * (1.0 - s))  # ... easing out through the neck ...
    # up the hosel in even steps: the loft spaces its sections evenly, so uneven gaps overshoot
    steps = max(1, round((HOSEL_TOP_Z - HOSEL_ROUND_Z) / 4.0))
    for z in [HOSEL_ROUND_Z + (HOSEL_TOP_Z - HOSEL_ROUND_Z) * k / steps for k in range(steps + 1)]:
        r = HOSEL_R - 0.35 * (z - HOSEL_ROUND_Z) / (HOSEL_TOP_Z - HOSEL_ROUND_Z)
        c = on_axis(z)
        rings.append([c + V(0, r * math.cos(a), 0) + ACROSS * (r * math.sin(a)) for a in phi])
        crease.append(0.0)  # ... to a smooth round hosel
    return rings, on_axis, crease


def chord_params(rows):
    """One parameter list for many point rows with the same structure: the rows' normalized
    chord lengths, averaged. Interpolated with it, every row's curve has the same knots, so
    the loft does not have to merge them (that ran to ~1900 poles and broke the surface)."""
    acc = [0.0] * len(rows[0])
    for pts in rows:
        d = [0.0]
        for a, b in zip(pts, pts[1:]):
            d.append(d[-1] + (b - a).Length)
        acc = [s + v / d[-1] for s, v in zip(acc, d)]
    return [v / len(rows) for v in acc]


def loft_rings(rings, crease=None, seam=0, split=None):
    """A solid lofted through closed point rings, outward-facing: if it comes out inside out,
    loft again with every ring wound the other way (same start point).

    Without crease: one smooth periodic curve per ring. With crease (a weight per ring, 0..1):
    each ring is two curves, from its point `seam` to its point `split` and back. At the seam
    they leave and arrive along the neighbouring points' directions, blended by 1 - crease
    toward the smooth direction through it: a crisp corner at 1 (the ridge), smooth at 0 (the
    hosel). At the split they share one tangent (put it where the surface is flat)."""
    for flip in (False, True):
        rows = []
        for ring in rings:
            pts = ring[seam:] + ring[:seam]
            rows.append([pts[0]] + pts[:0:-1] if flip else pts)
        if crease is None:
            wires = []
            for pts in rows:
                curve = Part.BSplineCurve()
                curve.interpolate(pts, PeriodicFlag=True)
                wires.append(Part.Wire(curve.toShape()))
        else:
            k = (split - seam) % len(rings[0])
            k = len(rings[0]) - k if flip else k
            firsts = [pts[:k + 1] for pts in rows]
            seconds = [pts[k:] + [pts[0]] for pts in rows]
            par_a, par_b = chord_params(firsts), chord_params(seconds)
            def chord(pts):
                return sum((q - p).Length for p, q in zip(pts, pts[1:]))

            wires = []
            for pts, w, a_pts, b_pts in zip(rows, crease, firsts, seconds):
                through = (pts[1] - pts[-1]).normalize()
                t_out = ((pts[1] - pts[0]).normalize() * w + through * (1.0 - w)).normalize()
                t_in = ((pts[0] - pts[-1]).normalize() * w + through * (1.0 - w)).normalize()
                t_split = (pts[k + 1] - pts[k - 1]).normalize()
                # the parameters run 0..1, so a unit-speed tangent is as long as the curve;
                # unscaled, as FreeCAD's own tangent scaling makes loops
                la, lb = chord(a_pts), chord(b_pts)
                a = Part.BSplineCurve()
                a.interpolate(Points=a_pts, Parameters=par_a, InitialTangent=t_out * la,
                              FinalTangent=t_split * la, Scale=False)
                b = Part.BSplineCurve()
                b.interpolate(Points=b_pts, Parameters=par_b, InitialTangent=t_split * lb,
                              FinalTangent=t_in * lb, Scale=False)
                wires.append(Part.Wire([a.toShape(), b.toShape()]))
        loft = Part.makeLoft(wires, True, False)
        if loft.Volume > 0:
            return loft
    raise RuntimeError("loft is inside out both ways")


def head_loft(drop, axis_y, back_shift=0.0):
    rings, on_axis, crease = head_sections(drop, axis_y, back_shift)
    return loft_rings(rings, crease, SEAM, FACE_SPLIT), on_axis


TOE_C = (58.0, 22.0)  # centre of the toe's rounded outline (face coordinates, x, z)
TOE_REACH = 24.5      # the toe tip sits this far toe-ward of the centre
TOE_LOW = -1.5        # the outline's lowest point, under the leading edge (z ~ 1.8 there): it
                      # leaves the leading edge at ~30 deg, no sliver of leading edge at the toe
TOE_HIGH = TOE_H + 1.5  # its highest point, above the top line, so it crosses it cleanly
TOE_N_TOP, TOE_N_BOT = 2.6, 2.0  # superellipse exponents: 2 = elliptic, larger = squarer


def toe_outline():
    """The toe seen face-on, like the Apex UT: an elliptic sweep up from the leading edge
    (which it leaves at ~30 deg, so the lower toe reads as one big curve)
    round the toe tip, then a tighter turn into the top line, which it crosses at ~17 deg
    (no grazing sliver)."""
    pts = [(48.0, TOE_LOW - 2.0)]
    for k in range(-8, 9):
        a = math.radians(11.25 * k)
        n, b = (TOE_N_TOP, TOE_HIGH - TOE_C[1]) if a > 0 else (TOE_N_BOT, TOE_C[1] - TOE_LOW)
        pts.append((TOE_C[0] + TOE_REACH * abs(math.cos(a)) ** (2 / n),
                    TOE_C[1] + b * math.copysign(abs(math.sin(a)) ** (2 / n), a)))
    pts.append((48.0, TOE_HIGH + 1.0))
    return pts


TOE_ROLL = 11.0     # how far the toe rolls in toward the back, at most (mm)
TOE_ROLL_L = 16.0   # the depth behind the face over which it rolls in
ROLL_Y = [-1.5, 0.0, 2.0, 4.0, 6.0, 8.0, 10.0, 12.0, 14.0, 17.0, 20.0, 24.0, 30.0, 40.0]


def toe_roll(y):
    """How far the toe outline slides heel-ward at depth y behind the face: 0 at the face,
    leaving it square to the face there (a crisp face edge), then curling in toward the back."""
    return TOE_ROLL * (1.0 - math.exp(-(max(y, 0.0) / TOE_ROLL_L) ** 2))


def toe_trim(drop, inset=0.0):
    """Everything heel-side of the toe: the toe outline straight back from the face, then
    sliding heel-ward by toe_roll() with depth, so the toe is round seen from the toe, top and
    sole too, not a flat cut. It slides along x rather than along the outline's normal: where
    the outline crosses the top line and the leading edge at a shallow angle, a normal offset
    would cut 3-8x further along those edges (a scoop); a slide moves their ends by exactly
    the roll, giving a round nose in plan view. (inset: the outline pulled in from the toe
    by that much, for the cavity.)"""
    curve = Part.BSplineCurve()
    curve.interpolate([V(x, 0, z) for x, z in toe_outline()])
    edge = curve.toShape()
    a, b = edge.Vertexes[0].Point, edge.Vertexes[-1].Point
    poly = Part.makePolygon([b, V(b.x, 0, 170), V(-160, 0, 170), V(-160, 0, -60), V(a.x + 10, 0, -60), a])
    face = Part.Face(Part.Wire([edge] + poly.Edges))
    if inset:
        face = face.makeOffset2D(-inset, 0).Faces[0]

    def wire(y):
        return face.translated(V(-toe_roll(y), y, 0)).OuterWire

    front = face.translated(V(0, ROLL_Y[0], 0)).extrude(V(0, -60, 0))
    rolled = None
    for ys in (ROLL_Y, ROLL_Y[::-1]):
        rolled = Part.makeLoft([wire(y) for y in ys], True, False)
        if rolled.Volume > 0:
            break
    return to_address(front.fuse(rolled).removeSplitter(), drop)


CAVITY_X = [21, 27, 33, 40, 48, 57, 66, 74, 80]  # clear of the neck morph (from NECK_X)


def cavity_solid(drop):
    """The hollow, in the thick lower body only: every blade section cut off WALL below the
    ridge (address height), inset by WALL, lofted, and kept WALL clear of the toe. Cutting
    before insetting keeps each section compact: inset whole, the thin blade left a long thin
    tail, different at every station, and the loft through them folded over itself."""
    rings = []
    for x in CAVITY_X:
        outer = blade_points(x)
        section = Part.Face(Part.makePolygon(outer + [outer[0]]))
        cut = ridge_z(x) - WALL + drop  # face z = (address z + drop + y sin) / cos

        def below(y):
            return V(x, y, (cut + y * SL) / CL)
        low = Part.Face(Part.makePolygon([below(-50.0), below(100.0), V(x, 100.0, -100.0),
                                          V(x, -50.0, -100.0), below(-50.0)]))
        inset = max(section.common(low).Faces, key=lambda f: f.Area).makeOffset2D(-WALL, 0)
        inner = max(inset.Faces, key=lambda f: f.Area).OuterWire
        ring = inner.discretize(Number=N_PTS + 1)[:-1]

        def area(r):
            return sum(r[i - 1].y * r[i].z - r[i].y * r[i - 1].z for i in range(len(r)))

        if (area(ring) > 0) != (area(outer) > 0):
            ring.reverse()
        start = outer[0] + V(0, WALL, WALL)  # near the leading edge, like the outer rings
        k = min(range(len(ring)), key=lambda i: (ring[i] - start).Length)
        rings.append([to_addr_pt(p, drop) for p in ring[k:] + ring[:k]])
    return loft_rings(rings).common(toe_trim(drop, WALL))


# ---- details --------------------------------------------------------------------------------
def face_grooves(drop):
    cuts = []
    z = 5.0
    while z <= 40.0:
        x_start = NECK_X + 4.0  # clear of the neck morph
        while top_h(x_start) < z + 4.0:  # keep clear of the top line at the heel
            x_start += 0.5
        r = GROOVE_W / 2  # a slot with round ends, cut square to the face
        x0, x1 = x_start + r, 67.0 - r
        slot = Part.makeBox(x1 - x0, 1.0 + GROOVE_D, GROOVE_W, V(x0, -1.0, z - r))
        for xe in (x0, x1):
            slot = slot.fuse(Part.makeCylinder(r, 1.0 + GROOVE_D, V(xe, -1.0, z), V(0, 1, 0)))
        cuts.append(slot.removeSplitter())
        z += GROOVE_PITCH
    return to_address(Part.makeCompound(cuts), drop)


# The back, after the user's Mizuno Pro Fli-Hi reference (photographed head-up; turned the
# right way up): a thick lower body along the sole side up to a crisp ridge running heel to
# toe, rising a little toward the toe; above it the back drops in and curves up into a thin
# blade-like top (all in the cross-section, blade_points(), so the back is one clean surface
# with the ridge as a crease); a round weight plug low on the toe. The loft, "18°", is stamped
# on the sole by the toe. Laid out at address, left-handed (before build() mirrors it), as seen
# from behind; heights are address heights.
REAR_Y0 = 15.5          # the rear prisms start here: behind the face wherever the details sit
RIDGE_Z = (14.0, 21.0)  # the ridge's height (address) at x = 10 (heel) and x = 75 (toe)
RIDGE_LEAN = 3.0        # the ridge sits this far in from the sole's trailing edge (face depth)
RIDGE_DROP = 3.5        # the shelf: just above the ridge the back falls in this much ...
RIDGE_SHELF_H = 2.5     # ... over this height, before curving up into the blade
PORT_AT = (65.0, 8.5)   # the toe weight plug: centre (x, z)
PORT_R = 2.3
PORT_D = 0.5            # how deep the plug's dark fill goes
PORT_GAP = 0.25         # the shadow ring round it: this wide and deep
NUMBER = "%d°" % round(LOFT)  # "18°": the loft, stamped like the "22°" on the Apex UT sole
NUMBER_AT = (63.0, 11.0)  # on the sole by the toe: centre (x, y)
NUMBER_SIZE = 5.0
NUMBER_D = 0.35         # stamp depth, paint-filled


def ridge_z(x):
    return RIDGE_Z[0] + (RIDGE_Z[1] - RIDGE_Z[0]) * (x - 10.0) / 65.0


def ridge_point(x, sw, zb):
    """The ridge crease in the section at x (face coordinates): RIDGE_LEAN in from the
    trailing edge, at the height that puts it on the straight ridge line at address."""
    yr = sw - RIDGE_LEAN
    zr = (ridge_z(x) + yr * SL) / CL  # address z = -y sin(loft) + z cos(loft) (drop ~ 0)
    return yr, max(zr, zb + 10.0)


def sole_number():
    """NUMBER standing on the ground plane under the toe, as a prism up through the sole. It is
    laid out so that once build() mirrors the head right-handed it reads upright with the
    shaft level and the toe hanging down: seen from below, glyphs pointing at the heel (+X),
    reading from the leading edge toward the trailing edge (+Y)."""
    wires = None
    for font in ("bahnschrift.ttf", "arialbd.ttf"):
        try:
            wires = Part.makeWireString(NUMBER, "C:/Windows/Fonts/", font, NUMBER_SIZE, 0.4)
            break
        except Exception:
            continue
    shape = Part.makeCompound([Part.makeFace(ch, "Part::FaceMakerBullseye") for ch in wires if ch])
    shape.rotate(V(0, 0, 0), V(0, 0, 1), 90)  # baseline +Y, glyphs -X (+Y, +X once mirrored)
    bb = shape.BoundBox
    shape.translate(V(NUMBER_AT[0] - bb.Center.x, NUMBER_AT[1] - bb.Center.y, -3.0))
    return shape.extrude(V(0, 0, 6.0))


def build():
    drop = ground_drop()
    le_y = leading_edge_y(drop)
    axis_y = le_y - OFFSET + HOSEL_R
    trim = toe_trim(drop)
    loft, on_axis = head_loft(drop, axis_y)
    shell = loft.common(trim)
    top = on_axis(HOSEL_TOP_Z)

    body = shell
    rounded = False
    for radius in (EDGE_R, 0.4, 0.25):  # soften the toe edge if OCC can
        try:
            r = shell.makeFillet(radius, [e for e in shell.Edges if e.BoundBox.XMin > 50.0])
            if r.isValid():
                body, rounded = r, radius
                break
        except Exception:  # OCC raises OCCError or ValueError when it cannot
            continue

    def on_top_rim(e):  # the hosel's top rim: edges lying in the top plane, round its centre
        return all(abs((p - top).dot(AXIS)) < 1e-3 and (p - top).Length < HOSEL_R
                   for p in e.discretize(5))

    try:  # ease the hosel's top edge
        c = body.makeChamfer(0.5, [e for e in body.Edges if on_top_rim(e)])
        if c.isValid() and c.Volume < body.Volume:
            body = c
    except Exception:
        pass
    body = body.cut(Part.makeCylinder(BORE_R, BORE_DEPTH + 1.0, top + AXIS * 1.0, -AXIS))
    body = body.cut(face_grooves(drop))

    # hollow body: a sealed cavity WALL inside the thick lower body, clear of the neck and hosel;
    # it stops WALL under the ridge, so the thin upper blade is solid
    hollow = False
    try:
        below = [(-20.0, -20.0), (110.0, -20.0), (110.0, ridge_z(110.0) - WALL), (-20.0, ridge_z(-20.0) - WALL)]
        low = Part.Face(Part.makePolygon([V(x, -50.0, z) for x, z in below + [below[0]]])).extrude(V(0, 150, 0))
        cavity = cavity_solid(drop).common(low)
        if cavity.isValid() and 0.1 * shell.Volume < cavity.Volume < 0.7 * shell.Volume:
            hollowed = body.cut(cavity)
            if hollowed.isValid() and len(hollowed.Shells) == 2:  # sealed inside
                body, hollow = hollowed, True
    except Exception:
        pass

    # the round weight plug low on the toe, flush with the lower body, in a fine shadow ring
    def skin(radius, depth):
        disc = Part.makeCylinder(radius, 40.0, V(PORT_AT[0], REAR_Y0, PORT_AT[1]), V(0, 1, 0))
        return disc.common(loft).cut(loft.translated(V(0, -depth, 0)))
    plug = skin(PORT_R, PORT_D)
    body = body.cut(skin(PORT_R + PORT_GAP, PORT_GAP))
    body = body.cut(plug)

    # the club number on the sole by the toe, paint-filled: the bottom NUMBER_D of the sole
    mark = sole_number().common(loft).cut(loft.translated(V(0, 0, NUMBER_D)))
    body = body.cut(mark)

    ferrule = Part.makeCone(HOSEL_R - 0.35, 5.0, FERRULE_H, top, AXIS)
    ferrule = ferrule.cut(Part.makeCylinder(BORE_R, FERRULE_H + 2, top - AXIS, AXIS))

    parts = {"Body": body.removeSplitter(), "PortPlug": plug, "MarkFill": mark, "Ferrule": ferrule}

    # everything above is drawn left-handed (toe +X); mirror it right-handed like the refs
    # (toe -X, the shaft rising toward +X), then set the sole exactly on the ground: the
    # sampled ground_drop() misses the spline's true lowest point by a fraction of a mm
    parts = {n: s.mirror(V(0, 0, 0), V(1, 0, 0)) for n, s in parts.items()}
    ground = parts["Body"].optimalBoundingBox().ZMin
    parts = {n: s.translated(V(0, 0, -ground)) for n, s in parts.items()}
    top = V(-top.x, top.y, top.z - ground)
    return parts, {"le_y": le_y, "axis_y": axis_y, "top": top, "hollow": hollow, "rounded": rounded,
                   "drop": drop, "ground": ground}


def main(parts=None, info=None):
    """Build (unless handed a finished build), show, save the .FCStd, .step and stl/."""
    if parts is None:
        parts, info = build()
    if App.listDocuments().get(DOC_NAME):
        App.closeDocument(DOC_NAME)
    doc = App.newDocument(DOC_NAME)
    group = doc.addObject("App::DocumentObjectGroup", "UtilityIron2U")
    colors = {"Body": (0.72, 0.74, 0.77), "PortPlug": (0.10, 0.10, 0.11),
              "MarkFill": (0.03, 0.03, 0.035), "Ferrule": (0.04, 0.04, 0.045)}
    total = 0.0
    for name, shape in parts.items():
        obj = doc.addObject("Part::Feature", name)
        obj.Shape = shape
        group.addObject(obj)
        if name != "Ferrule":
            total += shape.Volume
        if App.GuiUp:
            shiny = name in ("Body", "PortPlug", "Ferrule")
            try:
                mat = App.Material()
                mat.DiffuseColor = colors[name]
                mat.SpecularColor = (0.9, 0.9, 0.9) if shiny else (0.1, 0.1, 0.1)
                mat.Shininess = 0.6 if shiny else 0.1
                obj.ViewObject.ShapeAppearance = [mat]
            except Exception:
                obj.ViewObject.ShapeColor = colors[name]
            # a fine display mesh: FreeCAD's default one shows these B-spline surfaces as facets
            # and wrinkles (it reads as bumps that are not in the geometry)
            obj.ViewObject.Deviation = 0.02
            obj.ViewObject.AngularDeflection = 5
            # shaded, no edge lines: "Flat Lines" draws every patch boundary, e.g. the smooth
            # seams across the face and up the hosel, as if they were creases
            obj.ViewObject.DisplayMode = "Shaded"
    doc.recompute()
    stl_dir = os.path.join(OUT_DIR, "stl")
    os.makedirs(stl_dir, exist_ok=True)
    for old in os.listdir(stl_dir):  # parts dropped from the design must not linger
        if old.lower().endswith(".stl"):
            os.remove(os.path.join(stl_dir, old))
    doc.saveAs(os.path.join(OUT_DIR, "utility_iron_2u.FCStd"))
    import Import
    Import.export([group], os.path.join(OUT_DIR, "utility_iron_2u.step"))
    import MeshPart
    for name, shape in parts.items():
        mesh = MeshPart.meshFromShape(Shape=shape, LinearDeflection=0.02, AngularDeflection=0.15)
        mesh.write(os.path.join(OUT_DIR, "stl", name + ".stl"))
    if App.GuiUp:
        import FreeCADGui as Gui
        Gui.activeDocument().activeView().viewIsometric()
        Gui.SendMsgToActiveView("ViewFit")

    bb = parts["Body"].optimalBoundingBox()
    print("VALID", {n: s.isValid() for n, s in parts.items()})
    print("BBOX mm  x %.1f..%.1f  y %.1f..%.1f  z %.2f..%.1f" % (bb.XMin, bb.XMax, bb.YMin, bb.YMax, bb.ZMin, bb.ZMax))
    print("LEADING EDGE y %.2f, hosel axis y %.2f (offset %.1f), hosel top %s" % (info["le_y"], info["axis_y"], OFFSET, info["top"]))
    print("TOE EDGES ROUNDED", info["rounded"], "| body shells (outer + sealed cavity):", len(parts["Body"].Shells))
    print("%s STEEL MASS %.0f g (volume %.0f mm^3)" % ("HOLLOW" if info["hollow"] else "SOLID", total * STEEL_DENSITY, total))


if os.environ.get("GOLFHEAD_NO_MAIN") != "1":
    main()
