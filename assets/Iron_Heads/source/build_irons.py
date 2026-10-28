"""Parametric iron heads, unbranded, one family from the 2-iron utility (IRON_VARIANT):

  2u     the Utility Iron 2U: a hollow body with a Callaway Apex UT-like face and toe that rolls
         round toward the back, a round weight plug low on the toe, "18°" on the sole by the toe
  blade  a forged muscle back (after the Titleist 716 MB), solid, 28°
  mb     a forged muscle back (after the Callaway Apex MB), 28°: a fuller, lower muscle, and a
         raised badge bar across the upper back held by two screws
  cb     a forged cavity back (after the Titleist 716 CB), 28°: a muscle bar along the sole, a
         cavity over it framed by a top rail and the toe, a badge in the cavity

All three share the 2U's face, toe, top line, neck and hosel, and one back: a thick lower muscle
leaning in from the trailing edge up to a crisp ridge (the muscle line, after the Takomo 101U)
running straight from the toe all the way to the heel, where it sweeps up into the neck; above
it the back steps in and rises as one flat plane to the top line, which thickens toward the
heel. The heel's outline is the hosel's own line, straight down into a tight heel radius, so the
heel never flares out past the hosel.

Headless:  set IRON_VARIANT=blade, then
           freecadcmd -c "exec(open(r'C:/Users/willi/Documents/FreeCAD/GolfHead/irons/build_irons.py').read())"
GUI:       open this file in FreeCAD and run it as a macro (or exec() it through the FreeCAD
           MCP); in the GUI the parts are coloured and the view is fitted.

Units are mm. Address position, right-handed: ground plane z = 0, the face points at the
target (-Y), the toe is -X and the shaft rises toward +X at the lie angle. (Everything is
drawn left-handed - toe +X - and build() mirrors it at the end.)

The whole head - blade, heel and hosel - is ONE loft, so the hosel grows out of the heel
with no seam: the blade's cross-sections run from the toe to the heel, then morph into the
round hosel along two guide curves (the top line sweeping up into the hosel's toe side, the
heel's bottom edge running up the hosel's underside line), then continue up the hosel to its
top. The toe is rounded by trimming with the face silhouette.

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

VARIANT = os.environ.get("IRON_VARIANT", "2u")
OUT_DIR = os.environ.get("GOLFHEAD_OUT", os.path.join(r"C:\Users\willi\Documents\FreeCAD\GolfHead\irons", VARIANT))

# ---- parameters (the 2U's; VARIANTS below overrides them per head) --------------------------
LOFT = 18.0        # deg
LIE = 60.0         # deg, shaft to ground
HEEL_H = 35.0      # face height at the heel end of the top line (along the face)
TOE_H = 49.5       # face height toward the toe
SOLE_W = 22.0      # sole width mid-blade
SOLE_W_HEEL = 17.0
SOLE_W_TOE = 19.0
TOP_T = 6.0        # top line thickness along the blade ...
TOP_T_HEEL = 8.5   # ... thickening to this at NECK_X, over TOP_T_RUN, so the upper back meets the
TOP_T_RUN = 28.0   # neck full instead of thin (no dent between the blade and the hosel)
# the back, in face coordinates (y back from the face, z up it): from the trailing edge (sw, zb)
# the lower muscle rounds out by TE_ROUND, then leans in to the ridge RIDGE_IN in from the
# trailing edge, bowed out by LOWER_BOW; at the ridge (a crisp crease) the back steps in by
# STEP_IN over STEP_H, then a COVE_R round turns it into the flat upper plane up to the top line
RIDGE_Z = (14.0, 21.0)  # the ridge's height (address) at x = 10 (heel) and x = 75 (toe)
TE_ROUND = (1.0, 3.6)
RIDGE_IN = 2.0
LOWER_BOW = 0.45
STEP_IN = 3.0
STEP_H = 1.75
COVE_R = 5.0
OFFSET = 3.0       # leading edge behind the front of the hosel
HOSEL_R = 6.9      # hosel outer radius where it turns round (tapers 0.35 to the top)
HOSEL_TOP_Z = 72.0 # hosel top height above the ground
HOSEL_GROUND_X = 10.0  # where the shaft axis would meet the ground plane
HOSEL_ROUND_Z = 40.0   # the neck is fully round from this height up
NECK_X = 16.0      # the blade's own sections run heel-ward to here, then the neck morph starts
NECK_PULL = 0.55   # how tightly the top line's guide hugs its corner into the hosel (smaller = rounder)
HEEL_R = 9.0       # the heel's radius from the sole into the hosel's underside line
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
HOLLOW = True      # the 2U's sealed cavity in the lower body
PORT = True        # the 2U's round weight plug low on the toe
CAVITY = False     # the cb's open cavity
MB_BADGE = False   # (an earlier mb: a badge bar on the upper back)
MB_WEIGHT = False  # the mb's weight bar with two screws, on the thick muscle pad near the sole
CAVITY_PANEL = True  # the cb's raised panel in its dish
NUMBER = "18°"     # stamped on the sole by the toe
SECTION = "shelf"  # the back's design: "shelf" (the 2U's) or "bar" (the blade's muscle bar)
TOP_LINE = "eased" # "eased" (the 2U's) or "straight" (a blade's, to TOP_TOE_X, easing level over TOP_EASE)
TOP_TOE_X = 66.0
TOP_EASE = 14.0
TOP_X0 = 8.0       # the straight top line is HEEL_H here (12 mm heel-ward of where the neck starts)
BAR_PAD = 13.0       # the blade's pad: this far behind the face
BAR_UP = 7.0         # the upper plate's thickness at the bevel's top (more toward the heel)
BAR_CREASE_Z = 12.0  # the muscle line's height at address (level)
BAR_BEVEL_H = 9.0    # the bevel's height up the face
BAR_COVE_R = 3.0
BAR_TE_R = 4.0       # trailing edge round
BAR_RELIEF = 1.4     # the sole lifts this much toward the trailing edge
DOC_NAME = "UtilityIron2U"
FILE_NAME = "utility_iron_2u"

VARIANTS = {
    "2u": {},
    # the blade: the user's Blade Runner (its back, its straight top line and round toe), fuller
    "blade": dict(LOFT=28.0, HEEL_H=32.0, TOE_H=50.0, TOP_LINE="straight", TOP_TOE_X=66.0, TOP_EASE=14.0,
                  TOP_T=6.0, TOP_T_HEEL=7.5, SECTION="bar", BAR_PAD=13.0, BAR_UP=7.0, BAR_CREASE_Z=12.0,
                  BAR_BEVEL_H=9.0, BAR_COVE_R=3.0, BAR_TE_R=4.0, BAR_RELIEF=1.4,
                  TOE_C=(60.0, 23.5), TOE_REACH=22.0, TOE_LOW=-1.5, TOE_N_TOP=2.3, TOE_N_BOT=2.1,
                  TOE_ROLL=4.5, TOE_ROLL_L=9.0, SOLE_W=13.0, SOLE_W_HEEL=13.0, SOLE_W_TOE=13.0,
                  HOLLOW=False, PORT=False, NUMBER="7", HEEL_R=20.0, HOSEL_GROUND_X=24.0, NECK_X=28.0, TOP_X0=16.0, DOC_NAME="ForgedBlade", FILE_NAME="forged_blade"),
    # the muscle back, after the Callaway Apex MB: compact, a squarer toe, a straight top line, a
    # flat wedge of muscle leaning in from the trailing edge to a crisp line rising toward the toe,
    # a short step to the upper plate, and the badge bar with two screws across it
    # the muscle back: between the blade and the cavity back - the blade's muscle bar, taller,
    # carrying a weight bar held by two screws low on the thick part near the sole, and over it a
    # shallow cavity (shallower than the cavity back's) framed by the top rail and the toe; compact,
    # with a squarer toe and a straight top line
    "mb": dict(LOFT=28.0, HEEL_H=33.5, TOE_H=51.0, TOP_LINE="straight", TOP_TOE_X=64.0, TOP_EASE=12.0,
               TOP_T=6.5, TOP_T_HEEL=8.0, SECTION="bar", BAR_PAD=14.5, BAR_UP=8.0, BAR_CREASE_Z=13.0,
               BAR_BEVEL_H=3.0, BAR_COVE_R=1.8, BAR_TE_R=4.0, BAR_RELIEF=1.4,
               SOLE_W=14.5, SOLE_W_HEEL=14.5, SOLE_W_TOE=14.5,
               TOE_C=(60.5, 24.5), TOE_REACH=21.5, TOE_LOW=-1.5, TOE_N_TOP=3.0, TOE_N_BOT=2.3,
               TOE_ROLL=5.5, TOE_ROLL_L=10.0, CAVITY=True, CAVITY_PANEL=False, POCKET_DEPTH=1.5, RAIL_W=3.2, POCKET_LIP=0.6, POCKET_HEEL_X=29.0,
               TOE_WALL=3.6, TOE_ROLL_AT=6.0, CORNER_R=3.0,
               HOLLOW=False, PORT=False, MB_WEIGHT=True, NUMBER="7",
               HEEL_R=20.0, HOSEL_GROUND_X=24.0, NECK_X=28.0, TOP_X0=16.0, DOC_NAME="ForgedMuscleBack", FILE_NAME="forged_mb"),
    # the cavity back, after the Titleist 620 CB and Wilson Staff Model CB: a longer blade, a rounder
    # toe, a thick top rail; an angular muscle bar along the sole (a flat pad, a crisp line, a
    # bevel) and over it a deep cavity framed by the rail, the toe and the heel, a panel inside
    "cb": dict(LOFT=28.0, HEEL_H=33.0, TOE_H=51.5, TOP_LINE="straight", TOP_TOE_X=65.0, TOP_EASE=14.0,
               TOP_T=7.0, TOP_T_HEEL=8.0, SECTION="bar", BAR_PAD=15.5, BAR_UP=9.0, BAR_CREASE_Z=6.5,
               BAR_BEVEL_H=3.0, BAR_COVE_R=1.8, BAR_TE_R=4.5, BAR_RELIEF=1.6,
               SOLE_W=15.5, SOLE_W_HEEL=15.5, SOLE_W_TOE=15.5,
               TOE_C=(59.0, 24.0), TOE_REACH=23.0, TOE_LOW=-1.5, TOE_N_TOP=2.5, TOE_N_BOT=2.2,
               TOE_ROLL=6.0, TOE_ROLL_L=12.0,
               HOLLOW=False, PORT=False, CAVITY=True, NUMBER="7",
               HEEL_R=20.0, HOSEL_GROUND_X=24.0, NECK_X=28.0, TOP_X0=16.0, DOC_NAME="ForgedCavityBack", FILE_NAME="forged_cb"),
    # the game improver: the cavity back, its sole as wide as a spatula, a thicker top, a deeper dish
    "gi": dict(LOFT=28.0, HEEL_H=33.0, TOE_H=53.0, TOP_LINE="straight", TOP_TOE_X=65.0, TOP_EASE=14.0,
               TOP_T=7.5, TOP_T_HEEL=8.0, SECTION="bar", BAR_PAD=20.0, BAR_UP=9.0, BAR_CREASE_Z=6.5,
               BAR_BEVEL_H=3.0, BAR_COVE_R=1.8, BAR_TE_R=6.0, BAR_RELIEF=1.6,
               SOLE_W=20.0, SOLE_W_HEEL=20.0, SOLE_W_TOE=20.0,
               TOE_C=(59.0, 24.0), TOE_REACH=23.0, TOE_LOW=-1.5, TOE_N_TOP=2.5, TOE_N_BOT=2.2,
               TOE_ROLL=6.0, TOE_ROLL_L=12.0,
               HOLLOW=False, PORT=False, CAVITY=True, NUMBER="7",
               HEEL_R=20.0, HOSEL_GROUND_X=24.0, NECK_X=28.0, TOP_X0=16.0, POCKET_DEPTH=3.5, DOC_NAME="GameImproverCavityBack", FILE_NAME="game_improver_cb"),
}
globals().update(VARIANTS[VARIANT])

# points per segment of every cross-section, starting at the leading edge, going round
# counter-clockwise seen from the toe (along the sole, up the back, over the top, down the face)
SEGMENTS = (("le", 4), ("sole", 16), ("back_lo", 8), ("back_hi", 11), ("tb", 4), ("top", 5), ("tf", 4),
            ("face", 14))
N_PTS = sum(n for _, n in SEGMENTS)
SOLE_SPLIT = (2, 3, 3, 3, 3, 2)  # points per key-point interval along the sole (sums to "sole")
BACK_LO_SPLIT = (2, 3, 3)        # ... up the lower body to the ridge (sums to "back_lo")
BACK_HI_SPLIT = (3, 3, 5)        # ... the step, the cove and the upper plane (sums to "back_hi")
# every ring's loft curves start at the ridge point, the first point of "back_hi", with a
# corner there, so the loft has a crisp crease along the ridge; they are split again mid-face,
# where the surface is flat and the join cannot show
SEAM = 4 + 16 + 8
FACE_SPLIT = N_PTS - 7
# toe -> heel, evenly spaced: the loft spaces its sections evenly in its own parameter, so
# uneven gaps made the sole and back wave by +-0.25 mm between sections
BLADE_X = [92.0 - 4.0 * k for k in range(round((92.0 - NECK_X) / 4.0) + 1)]
assert abs(BLADE_X[-1] - NECK_X) < 1e-9
NECK_T = [k / 13 for k in range(1, 13)]

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
    if TOP_LINE == "straight":  # a blade's: straight from the heel, easing level just before the toe
        slope = (TOE_H - HEEL_H) / (TOP_TOE_X - TOP_X0 - TOP_EASE / 2)
        if x < TOP_TOE_X - TOP_EASE:
            return HEEL_H + slope * (x - TOP_X0)
        u = min(x - (TOP_TOE_X - TOP_EASE), TOP_EASE)
        return HEEL_H + slope * (TOP_TOE_X - TOP_EASE - TOP_X0) + slope * (u - u * u / (2 * TOP_EASE))
    rise = TOE_H - HEEL_H
    if x < 8.0:
        return HEEL_H - (8.0 - x) * rise * math.pi / (2.0 * TOP_RUN)
    if x > 8.0 + TOP_RUN:
        return TOE_H
    return HEEL_H + rise * math.sin(math.pi / 2.0 * (x - 8.0) / TOP_RUN)


def top_t(x):
    """Top line thickness at x: TOP_T along the blade, thickening smoothly to TOP_T_HEEL at NECK_X."""
    return TOP_T + (TOP_T_HEEL - TOP_T) * (1.0 - smooth((x - NECK_X) / TOP_T_RUN))


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
def shelf_points(x, back_shift=0.0):
    """The 2U's back: N_PTS points round the blade's cross-section at x. back_shift moves the back (not the
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
    # the lower muscle: out round the trailing edge, then leaning in to the ridge, bowed out a little
    yr, zr = ridge_point(x, sw, zb)
    l0 = (sw + TE_ROUND[0], zb + TE_ROUND[1])
    dy, dz = yr - l0[0], zr - l0[1]
    dl = math.hypot(dy, dz)
    mid = ((l0[0] + yr) / 2 + dz / dl * LOWER_BOW, (l0[1] + zr) / 2 - dy / dl * LOWER_BOW)
    lower = [l0, mid, (yr, zr)]
    # above the ridge: the step in, a cove, and one flat plane up to the top line's back corner,
    # laid out exactly (lines and a circular arc) and sampled densely for the curve
    yt0 = top_t(x)
    st = (yr - STEP_IN, zr + STEP_H)
    d1 = V(0, st[0] - yr, st[1] - zr).normalize()
    d2 = V(0, yt0 - st[0], H - st[1]).normalize()
    turn = math.acos(max(-1.0, min(1.0, d1.dot(d2))))
    reach = COVE_R * math.tan(turn / 2)
    assert reach < 0.8 * math.hypot(STEP_IN, STEP_H), (x, reach)
    S = V(0, st[0], st[1])
    c1, c2 = S - d1 * reach, S + d2 * reach
    centre = c1 + V(0, d1.z, -d1.y) * COVE_R  # on the back side: the cove is concave
    a1 = math.atan2((c1 - centre).z, (c1 - centre).y)
    a2 = math.atan2((c2 - centre).z, (c2 - centre).y)
    if a2 - a1 > math.pi:
        a2 -= 2 * math.pi
    elif a1 - a2 > math.pi:
        a2 += 2 * math.pi
    R0, TB = V(0, yr, zr), V(0, yt0, H)
    spans = [(R0 - c1).Length, abs(a2 - a1) * COVE_R, (TB - c2).Length]
    dense = [R0 + (c1 - R0) * (i / 4) for i in range(4)]
    dense += [centre + V(0, math.cos(a1 + (a2 - a1) * i / 8), math.sin(a1 + (a2 - a1) * i / 8)) * COVE_R
              for i in range(9)]
    k_plane = max(3, int(spans[2] / 2.0))
    dense += [c2 + (TB - c2) * (i / k_plane) for i in range(1, k_plane + 1)]
    upper = [(q.y, q.z) for q in dense]
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
    hi.interpolate(Points=[V(x, y, z) for y, z in upper], InitialTangent=d1,
                   FinalTangent=d2, Scale=False)
    lo_knots = lo.getKnots()  # the parameter of every key point
    assert len(lo_knots) == len(key)
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
    u_hi = [hi.FirstParameter, hi.parameterAtDistance(spans[0], hi.FirstParameter),
            hi.parameterAtDistance(spans[0] + spans[1], hi.FirstParameter), u_tb]
    pts += chain(hi, u_hi, BACK_HI_SPLIT)                          # its first point is the ridge
    pts += bezier2(hi.value(u_tb), V(x, yt, H), V(x, yt - R_TB, H), n["tb"])
    pts += line(V(x, yt - R_TB, H), V(x, R_TF, H), n["top"])
    pts += bezier2(V(x, R_TF, H), V(x, 0, H), V(x, 0, H - R_TF), n["tf"])
    pts += line(V(x, 0, H - R_TF), V(x, 0, z_le + R_LE), n["face"])
    return pts


def blade_points(x, back_shift=0.0):
    """N_PTS points round the head's cross-section at x, in this head's own back design."""
    return bar_points(x, back_shift) if SECTION == "bar" else shelf_points(x, back_shift)


def corner_arc(p, d_in, d_out, r, n, convex):
    """Round the corner at p (face coordinates, V(x, y, z)) between the directions d_in and d_out:
    the two tangent points and n points of the arc from the first (included) toward the second
    (excluded). Convex corners turn about a centre inside the section (left of the way round)."""
    turn = math.acos(max(-1.0, min(1.0, d_in.dot(d_out))))
    reach = r * math.tan(turn / 2)
    t1, t2 = p - d_in * reach, p + d_out * reach
    side = V(0, -d_in.z, d_in.y) if convex else V(0, d_in.z, -d_in.y)
    centre = t1 + side * r
    a1 = math.atan2((t1 - centre).z, (t1 - centre).y)
    a2 = math.atan2((t2 - centre).z, (t2 - centre).y)
    if a2 - a1 > math.pi:
        a2 -= 2 * math.pi
    elif a1 - a2 > math.pi:
        a2 += 2 * math.pi
    arc = [centre + V(0, math.cos(a1 + (a2 - a1) * i / n), math.sin(a1 + (a2 - a1) * i / n)) * r for i in range(n)]
    return t1, t2, arc, reach


def bar_points(x, back_shift=0.0):
    """The blade's section at x, after the user's Blade Runner back, fuller (face coordinates, the
    same segments as shelf_points): the sole turns up round BAR_TE_R into a flat pad BAR_PAD
    behind the face, parallel to it, up to the muscle line - a crisp crease, level at address,
    straight from the toe into the neck; there a bevel steps in BAR_BEVEL_H up to the thin upper
    plate (a BAR_COVE_R cove), which rises flat to the top line."""
    n = counts()
    H = top_h(x)
    c = camber(x)
    shift = back_shift if callable(back_shift) else (lambda _x, _z: back_shift)
    tp = BAR_PAD
    tt = top_t(x)
    tu = BAR_UP + (tt - TOP_T)  # the plate thickens toward the heel with the top line
    zc = (BAR_CREASE_Z + tp * SL) / CL
    zq = zc + BAR_BEVEL_H
    z_le = 1.6 + c

    def sole_z(y, lift):
        return G * y + lift + c

    # sole -> trailing edge -> pad
    ys = tp * 0.62
    k = V(x, tp, sole_z(tp, BAR_RELIEF))
    d_in = (k - V(x, ys, sole_z(ys, 0.0))).normalize()
    te1, te2, te_arc, _ = corner_arc(k, d_in, V(0, 0, 1), BAR_TE_R, 4, True)
    key = [V(x, 0.0, z_le), V(x, 1.0, sole_z(1.0, 0.22))]
    for f, lift in ((0.3, 0.3), (0.6, 0.05)):
        key.append(V(x, te1.y * f, sole_z(te1.y * f, lift)))
    key.append(te1)
    lo = Part.BSplineCurve()
    lo.interpolate(Points=key, InitialTangent=(key[1] - key[0]).normalize(), FinalTangent=d_in, Scale=False)
    u_le = lo.parameterAtDistance(R_LE, lo.FirstParameter)
    sole_len = lo.length(u_le, lo.LastParameter)

    def line(a, b, m):
        return [a + (b - a) * (i / m) for i in range(m)]

    pts = bezier2(V(x, 0, z_le + R_LE), V(x, 0, z_le), lo.value(u_le), n["le"])
    pts += [lo.value(lo.parameterAtDistance(sole_len * i / n["sole"], u_le)) for i in range(n["sole"])]
    crease = V(x, tp, zc)
    back = te_arc + line(te2, crease, n["back_lo"] - 4)
    # bevel -> cove -> plate
    q = V(x, tu, zq)
    tb = V(x, tt, H)
    d1 = (q - crease).normalize()
    d2 = (tb - q).normalize()
    c1, c2, cove, reach = corner_arc(q, d1, d2, BAR_COVE_R, 3, False)
    assert reach < 0.6 * min((q - crease).Length, (tb - q).Length), (x, reach)
    plate_end = tb - d2 * R_TB
    back += line(crease, c1, 3) + cove + line(c2, plate_end, 5)
    pts += [V(p.x, p.y + shift(x, p.z), p.z) for p in back]
    yt = tt + shift(x, H)
    pe = V(x, plate_end.y + shift(x, plate_end.z), plate_end.z)
    pts += bezier2(pe, V(x, yt, H), V(x, yt - R_TB, H), n["tb"])
    pts += line(V(x, yt - R_TB, H), V(x, R_TF, H), n["top"])
    pts += bezier2(V(x, R_TF, H), V(x, 0, H), V(x, 0, H - R_TF), n["tf"])
    pts += line(V(x, 0, H - R_TF), V(x, 0, z_le + R_LE), n["face"])
    assert len(pts) == N_PTS, len(pts)
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

    # guide curves: the top line into the hosel's toe side (a Bezier hugging the corner by
    # NECK_PULL), and the heel's bottom edge: along the sole, round HEEL_R, then straight up the
    # hosel's own underside line, so seen face-on or from behind the heel's outline IS the
    # hosel's line (a long sweep there flared the heel out past the hosel and pinched the neck)
    def guide(start, start_dir, end):
        corner = meet(start, start_dir, end, -AXIS)
        return (start, start + start_dir * (NECK_PULL * (corner - start).Length),
                end - AXIS * (NECK_PULL * (corner - end).Length), end)

    def heel_guide(start, start_dir, end):
        corner = meet(start, start_dir, end, -AXIS)
        turn = math.acos(max(-1.0, min(1.0, start_dir.dot(AXIS))))
        reach = HEEL_R * math.tan(turn / 2)
        t1, t2 = corner - start_dir * reach, corner + AXIS * reach
        n = V(start_dir.z, 0, -start_dir.x)
        if n.dot(AXIS) < 0:
            n = -n
        centre = t1 + n * HEEL_R
        a1 = math.atan2((t1 - centre).z, (t1 - centre).x)
        a2 = math.atan2((t2 - centre).z, (t2 - centre).x)
        if a2 - a1 > math.pi:
            a2 -= 2 * math.pi
        elif a1 - a2 > math.pi:
            a2 += 2 * math.pi
        legs = [(t1 - start).Length, abs(a2 - a1) * HEEL_R, (end - t2).Length]
        assert legs[0] > 0 and legs[2] > 0, legs

        def at(t):
            d = t * sum(legs)
            if d <= legs[0]:
                return start + start_dir * d
            d -= legs[0]
            if d <= legs[1]:
                a = a1 + (a2 - a1) * d / legs[1]
                return centre + V(math.cos(a), 0, math.sin(a)) * HEEL_R
            return t2 + AXIS * (d - legs[1])
        return at

    top_guide = guide(p0, (p0 - p0b).normalize(), p1)
    heel_at = heel_guide(b0, (b0 - b0b).normalize(), b1)

    # each point's place on the round hosel: its angle round the heel section
    ys = [p.y for p in s0]
    yc, wy = (max(ys) + min(ys)) / 2, (max(ys) - min(ys)) / 2
    h0 = p0.z - b0.z
    f0 = [(p.z - b0.z) / h0 for p in s0]
    phi = [math.atan2((f - 0.5) / 0.5, (p.y - yc) / wy) for p, f in zip(s0, f0)]
    yr = [axis_y + HOSEL_R * math.cos(a) for a in phi]
    fr = [(1 + math.sin(a)) / 2 for a in phi]

    crease = [1.0 for x in BLADE_X]  # how crisp each ring's ridge crease is: full along the blade,
    # right to the heel
    # the depth of every point eases from the heel section's onto the hosel's, leaving at the
    # blade's own rate (one ring step on): starting it from rest stalled the back for a ring at
    # NECK_X and then dropped it, a crease across the back at the heel (the "dent")
    prev = rings[len(BLADE_X) - 2]
    steps_t = 1.0 / NECK_T[0]
    for t in NECK_T:
        b = heel_at(t)
        p = bezier3(*top_guide, t)
        s = smooth(t)
        h00, h10, h01 = 2 * t ** 3 - 3 * t * t + 1, t ** 3 - 2 * t * t + t, 3 * t * t - 2 * t ** 3
        rings.append([b + (p - b) * (f0[i] + (fr[i] - f0[i]) * s)
                      + V(0, h00 * s0[i].y + h10 * (s0[i].y - prev[i].y) * steps_t + h01 * yr[i], 0)
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


def toe_face():
    """Everything heel-side of the toe outline, as a face in the face plane (y = 0)."""
    curve = Part.BSplineCurve()
    curve.interpolate([V(x, 0, z) for x, z in toe_outline()])
    edge = curve.toShape()
    a, b = edge.Vertexes[0].Point, edge.Vertexes[-1].Point
    poly = Part.makePolygon([b, V(b.x, 0, 170), V(-160, 0, 170), V(-160, 0, -60), V(a.x + 10, 0, -60), a])
    return Part.Face(Part.Wire([edge] + poly.Edges))


def toe_trim(drop, inset=0.0):
    """Everything heel-side of the toe: the toe outline straight back from the face, then
    sliding heel-ward by toe_roll() with depth, so the toe is round seen from the toe, top and
    sole too, not a flat cut. It slides along x rather than along the outline's normal: where
    the outline crosses the top line and the leading edge at a shallow angle, a normal offset
    would cut 3-8x further along those edges (a scoop); a slide moves their ends by exactly
    the roll, giving a round nose in plan view. (inset: the outline pulled in from the toe
    by that much, for the cavity.)"""
    face = toe_face()
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


# The cb's cavity, after the Titleist 716 CB: a pocket cut square into the back down to a floor
# FLOOR_T behind the face, its corners rounded (CORNER_R) and its floor rounded into the walls
# (FLOOR_R). It sits on the muscle bar (its lip POCKET_LIP above the ridge, so the ridge and the
# shelf run along under it and on into the neck), under a top rail RAIL_W deep, inside a toe wall
# TOE_WALL thick where the toe has rolled in at the back, and ends at the heel on a line parallel
# to the hosel. A badge plate sits on the floor.
POCKET_HEEL_X = 31.0
POCKET_LIP = 1.0
POCKET_DEPTH = 3.0  # a shallow dish (Mizuno Pro 243, Stix): its floor follows the back, this far in
RAIL_W = 5.5
TOE_WALL = 6.0
TOE_ROLL_AT = 8.0  # the toe wall is measured where the toe has rolled in at this depth
CORNER_R = 7.0
BADGE_T = 1.6      # the panel: raised this much off the dish's floor,
BADGE_GAP = 1.6    # this far in from the dish's wall, its top edge an angular line: level from the
BADGE_TOP = (0.40, 0.58, 0.78)  # heel, kinking up toward the toe (fractions of the dish's height
                                # at its heel end, the kink at BADGE_KINK across, and the toe end)
BADGE_KINK = 0.52


def lip_z(x):
    """The muscle's top at x (face z): the shelf's ridge, or the top of the bar's bevel."""
    if SECTION == "bar":
        return (BAR_CREASE_Z + BAR_PAD * SL) / CL + BAR_BEVEL_H
    sw = sole_w(x)
    return ridge_point(x, sw, G * sw + 2.6 + camber(x))[1]


def pocket_outline():
    """The cavity's outline seen face-on (face coordinates, x and z), as 240 points evenly round
    it, counter-clockwise: the band between the lip and the rail, inside the toe wall, cut off at
    the heel on the hosel's slope, its corners rounded by CORNER_R. (Fitted again as one closed
    curve: straight from the 2D offsets it was ~50 pieces that would not offset again.)"""
    def z_bot(x):
        return lip_z(x) + POCKET_LIP

    lean = math.cos(math.radians(LIE)) / math.sin(math.radians(LIE)) / CL  # the hosel's slope, face-on
    z0 = z_bot(POCKET_HEEL_X)
    x_top = POCKET_HEEL_X
    for _ in range(20):  # the heel end's top corner: on the lean line, RAIL_W under the top line
        x_top = POCKET_HEEL_X - (top_h(x_top) - RAIL_W - z0) * lean
    xs = [POCKET_HEEL_X + (115.0 - POCKET_HEEL_X) * k / 40 for k in range(41)]
    xt = [x_top + (115.0 - x_top) * k / 40 for k in range(41)]
    lo = Part.BSplineCurve()
    lo.interpolate([V(x, 0, z_bot(x)) for x in xs])
    hi = Part.BSplineCurve()
    hi.interpolate([V(x, 0, top_h(x) - RAIL_W) for x in reversed(xt)])
    a, b = lo.EndPoint, hi.StartPoint
    c, d = hi.EndPoint, lo.StartPoint
    band = Part.Face(Part.Wire([lo.toShape(), Part.makeLine(a, b), hi.toShape(), Part.makeLine(c, d)]))
    toe = toe_face().translated(V(-toe_roll(TOE_ROLL_AT), 0, 0)).makeOffset2D(-TOE_WALL, 0).Faces[0]
    face = band.common(toe).Faces[0]
    face = face.makeOffset2D(-CORNER_R, 0).Faces[0].makeOffset2D(CORNER_R, 0).Faces[0]
    pts = face.OuterWire.discretize(Distance=0.5)
    curve = Part.BSplineCurve()
    curve.interpolate(pts[:-1] if (pts[0] - pts[-1]).Length < 1e-6 else pts, PeriodicFlag=True)
    out = [curve.value(curve.parameterAtDistance(curve.length() * k / 240, curve.FirstParameter))
           for k in range(240)]
    area = sum(out[k - 1].x * out[k].z - out[k].x * out[k - 1].z for k in range(240))
    return out if area > 0 else out[::-1]


def closed_curve(pts):
    curve = Part.BSplineCurve()
    curve.interpolate(pts, PeriodicFlag=True)
    return Part.Wire(curve.toShape())


def pocket_face():
    return Part.Face(closed_curve(pocket_outline()))


def above_lip(d):
    """A back shift of d over the upper back only, fading in up the bevel below the dish: moving the
    whole back pulled the trailing edge's round off the sole and broke the loft."""
    return lambda x, z: d * smooth((z - (lip_z(x) - 3.0)) / 3.8)


def cb_pocket(drop, axis_y):
    """The cavity tool (address): inside the outline, everything behind the back moved in by
    POCKET_DEPTH - a shallow dish whose floor is the back's own surface, offset."""
    face = Part.Face(closed_curve(pocket_outline()))  # (from inside the metal: a tool reaching the
    prism = to_address(face.translated(V(0, 1.0, 0)).extrude(V(0, 90.0, 0)), drop)  # face shared it and broke the cut)
    inner, _ = head_loft(drop, axis_y, above_lip(-POCKET_DEPTH))
    return prism.cut(inner)


def cb_badge(drop, axis_y):
    """A panel raised off the dish's floor, BADGE_GAP inside its wall, filling the dish below an
    angular line (level from the heel, then kinking up toward the toe), after the Mizuno Pro 243."""
    pts = pocket_outline()
    n = len(pts)
    inset = []
    for k in range(n):
        t = pts[(k + 1) % n] - pts[k - 1]
        inset.append(pts[k] + V(-t.z, 0, t.x).normalize() * BADGE_GAP)
    panel = Part.Face(closed_curve(inset))
    x0, x1 = min(p.x for p in pts), max(p.x for p in pts)

    def height_at(x, f):
        lo = lip_z(x) + POCKET_LIP
        return lo + (top_h(x) - RAIL_W - lo) * f

    xk = x0 + (x1 - x0) * BADGE_KINK
    line = [V(x0 - 5.0, 0, height_at(x0, BADGE_TOP[0])), V(xk, 0, height_at(xk, BADGE_TOP[1])),
            V(x1 + 5.0, 0, height_at(x1, BADGE_TOP[2]))]
    below = Part.Face(Part.makePolygon(line + [V(x1 + 5.0, 0, -50.0), V(x0 - 5.0, 0, -50.0), line[0]]))
    panel = panel.common(below).Faces[0]
    return back_layer(panel, drop, axis_y, above_lip(-POCKET_DEPTH - 0.3), above_lip(-POCKET_DEPTH + BADGE_T))


# The mb's badge, after the Callaway Apex MB: a bar across the upper back, parallel to the top
# line, its ends square to the hosel's slope at the heel and leaning with the toe, raised
# MB_BADGE_LIFT off the back (it follows the back's own surface), with a screw at each end.
MB_BADGE_X = (25.0, 72.0)  # heel and toe ends (face coordinates, along the bottom edge)
MB_BADGE_TOP = 6.5         # its top edge this far under the top line
MB_BADGE_H = 9.5
MB_BADGE_R = 2.5           # corner rounding
MB_BADGE_LIFT = 1.1
MB_BADGE_GAP = 3.5         # its bottom edge stays this far above the muscle line
SCREW_R = 2.3
SCREW_LIFT = 0.5           # the screw heads stand this far proud of the badge
SCREW_IN = 5.5             # screw centres this far in from the badge's ends
HEX_R = 1.0


def mb_badge_outline():
    """The badge bar seen face-on, as 200 points evenly round it, counter-clockwise."""
    x0, x1 = MB_BADGE_X
    lean = math.cos(math.radians(LIE)) / math.sin(math.radians(LIE)) / CL

    def top(x):
        return top_h(x) - MB_BADGE_TOP

    def bottom(x):  # under the top line by its height, but always clear of the muscle line
        return max(top(x) - MB_BADGE_H, lip_z(x) + MB_BADGE_GAP)

    while top(x0) - bottom(x0) < 0.8 * MB_BADGE_H:  # the heel end: where it still has its height
        x0 += 0.5
    pts = [V(x0 + (x1 - x0) * k / 30, 0, bottom(x0 + (x1 - x0) * k / 30)) for k in range(31)]
    x1t = x1 + MB_BADGE_H * 0.35  # the toe end leans out toward the top, with the toe
    x0t = x0 - MB_BADGE_H * lean  # the heel end leans heel-ward, with the hosel
    pts += [V(x1t + (x0t - x1t) * k / 30, 0, top(x1t + (x0t - x1t) * k / 30)) for k in range(31)]
    face = Part.Face(Part.makePolygon(pts + [pts[0]]))
    face = face.makeOffset2D(-MB_BADGE_R, 0).Faces[0].makeOffset2D(MB_BADGE_R, 0).Faces[0]
    edge_pts = face.OuterWire.discretize(Distance=0.4)
    curve = Part.BSplineCurve()
    curve.interpolate(edge_pts[:-1] if (edge_pts[0] - edge_pts[-1]).Length < 1e-6 else edge_pts, PeriodicFlag=True)
    out = [curve.value(curve.parameterAtDistance(curve.length() * k / 200, curve.FirstParameter)) for k in range(200)]
    area = sum(out[k - 1].x * out[k].z - out[k].x * out[k - 1].z for k in range(200))
    return out if area > 0 else out[::-1]


def mb_screws():
    """The two screw centres (face coordinates x, z), SCREW_IN in from the bar's ends, mid-height."""
    pts = mb_badge_outline()
    x0 = min(p.x for p in pts) + SCREW_IN + 1.5
    x1 = max(p.x for p in pts) - SCREW_IN - 1.0
    return [(x, top_h(x) - MB_BADGE_TOP - MB_BADGE_H / 2) for x in (x0, x1)]


def back_layer(face, drop, axis_y, lo, hi):
    """What `face` (face coordinates, y = 0) covers of the back between the back moved out by
    lo and by hi: a skin that follows the back's own surface, its sides square to the face."""
    prism = to_address(face.translated(V(0, 0.5, 0)).extrude(V(0, 80.0, 0)), drop)
    outer, _ = head_loft(drop, axis_y, hi)
    inner, _ = head_loft(drop, axis_y, lo)
    return prism.common(outer).cut(inner)


def mb_badge(drop, axis_y):
    bar = Part.Face(closed_curve(mb_badge_outline()))
    badge = back_layer(bar, drop, axis_y, 0.0, MB_BADGE_LIFT)
    discs = [Part.Face(Part.Wire(Part.makeCircle(SCREW_R, V(x, 0, z), V(0, 1, 0)))) for x, z in mb_screws()]
    hexes = [Part.Face(Part.makePolygon([V(x + HEX_R * math.cos(math.pi / 3 * k), 0, z + HEX_R * math.sin(math.pi / 3 * k))
                                         for k in range(7)])) for x, z in mb_screws()]
    screws = None
    for disc, hx in zip(discs, hexes):
        head = back_layer(disc, drop, axis_y, MB_BADGE_LIFT - 0.2, MB_BADGE_LIFT + SCREW_LIFT)
        head = head.cut(back_layer(hx, drop, axis_y, MB_BADGE_LIFT + SCREW_LIFT - 0.6, MB_BADGE_LIFT + SCREW_LIFT + 1.0))
        screws = head if screws is None else screws.fuse(head)
    badge = badge.cut(back_layer(discs[0].fuse(discs[1]), drop, axis_y, 0.0, MB_BADGE_LIFT + 1.0))
    return badge, screws


# The mb's weight bar: a plate WEIGHT_T proud of the muscle pad (the thick part near the sole),
# WEIGHT_GAP inside the pad's band (between the trailing edge's round and the muscle line), its
# corners rounded, held by two screws.
WEIGHT_X = (33.0, 70.0)
WEIGHT_GAP = 1.4
WEIGHT_T = 0.9
WEIGHT_R = 3.0


def pad_band(x):
    """The muscle pad's band at x (face z): from the top of the trailing edge's round to the crease."""
    tp, c = BAR_PAD, camber(x)
    kz = G * tp + BAR_RELIEF + c
    ys = tp * 0.62
    d_in = (V(0, tp, kz) - V(0, ys, G * ys + c)).normalize()
    reach = BAR_TE_R * math.tan(math.acos(max(-1.0, min(1.0, d_in.z))) / 2)
    return kz + reach, (BAR_CREASE_Z + tp * SL) / CL


def weight_outline():
    x0, x1 = WEIGHT_X
    xs = [x0 + (x1 - x0) * k / 30 for k in range(31)]
    lo = [V(x, 0, pad_band(x)[0] + WEIGHT_GAP) for x in xs]
    hi = [V(x, 0, pad_band(x)[1] - WEIGHT_GAP) for x in reversed(xs)]
    face = Part.Face(Part.makePolygon(lo + hi + [lo[0]]))
    return face.makeOffset2D(-WEIGHT_R, 0).Faces[0].makeOffset2D(WEIGHT_R, 0).Faces[0]


def mb_weight(drop, loft):
    """The weight bar and its two screws (address), as layers over the pad: the loft moved out
    along the face's normal (the pad is parallel to the face)."""
    out = V(0, CL, -SL)

    def layer(face, lo, hi):
        prism = to_address(face.translated(V(0, 0.5, 0)).extrude(V(0, 80.0, 0)), drop)
        return prism.common(loft.translated(out * hi)).cut(loft.translated(out * lo))

    bar_face = weight_outline()
    bar = layer(bar_face, 0.0, WEIGHT_T)
    bb = bar_face.BoundBox
    screws = None
    for xs in (bb.XMin + SCREW_IN + 1.0, bb.XMax - SCREW_IN - 1.0):
        lo_z, hi_z = pad_band(xs)
        zs = (lo_z + hi_z) / 2
        disc = Part.Face(Part.Wire(Part.makeCircle(SCREW_R, V(xs, 0, zs), V(0, 1, 0))))
        hexa = Part.Face(Part.makePolygon([V(xs + HEX_R * math.cos(math.pi / 3 * k), 0, zs + HEX_R * math.sin(math.pi / 3 * k))
                                           for k in range(7)]))
        head = layer(disc, WEIGHT_T - 0.2, WEIGHT_T + SCREW_LIFT).cut(layer(hexa, WEIGHT_T + SCREW_LIFT - 0.6, WEIGHT_T + SCREW_LIFT + 1.0))
        screws = head if screws is None else screws.fuse(head)
    return bar, screws


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
PORT_AT = (65.0, 8.5)   # the toe weight plug: centre (x, z)
PORT_R = 2.3
PORT_D = 0.5            # how deep the plug's dark fill goes
PORT_GAP = 0.25         # the shadow ring round it: this wide and deep
NUMBER_AT = (63.0, 11.0)  # on the sole by the toe: centre (x, y)
NUMBER_SIZE = 5.0
NUMBER_D = 0.35         # stamp depth, paint-filled


def ridge_z(x):
    return RIDGE_Z[0] + (RIDGE_Z[1] - RIDGE_Z[0]) * (x - 10.0) / 65.0


def ridge_point(x, sw, zb):
    """The ridge crease in the section at x (face coordinates): RIDGE_IN in from the
    trailing edge, at the height that puts it on the straight ridge line at address."""
    yr = sw - RIDGE_IN
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
        if not HOLLOW:
            raise StopIteration
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
    plug = None
    if PORT:
        plug = skin(PORT_R, PORT_D)
        body = body.cut(skin(PORT_R + PORT_GAP, PORT_GAP))
        body = body.cut(plug)

    badge = screws = None
    if MB_BADGE:
        badge, screws = mb_badge(drop, axis_y)
    if CAVITY:
        body = body.cut(cb_pocket(drop, axis_y))
        if CAVITY_PANEL:
            badge = cb_badge(drop, axis_y)
    if MB_WEIGHT:
        badge, screws = mb_weight(drop, loft)

    # the club number on the sole by the toe, paint-filled: the bottom NUMBER_D of the sole
    mark = sole_number().common(loft).cut(loft.translated(V(0, 0, NUMBER_D)))
    body = body.cut(mark)

    ferrule = Part.makeCone(HOSEL_R - 0.35, 5.0, FERRULE_H, top, AXIS)
    ferrule = ferrule.cut(Part.makeCylinder(BORE_R, FERRULE_H + 2, top - AXIS, AXIS))

    parts = {"Body": body.removeSplitter(), "PortPlug": plug, "Badge": badge, "Screws": screws, "MarkFill": mark,
             "Ferrule": ferrule}
    parts = {n: v for n, v in parts.items() if v is not None}

    # everything above is drawn left-handed (toe +X); mirror it right-handed like the refs
    # (toe -X, the shaft rising toward +X), then set the sole exactly on the ground: the
    # sampled ground_drop() misses the spline's true lowest point by a fraction of a mm
    parts = {n: s.mirror(V(0, 0, 0), V(1, 0, 0)) for n, s in parts.items()}
    ground = parts["Body"].optimalBoundingBox().ZMin
    parts = {n: s.translated(V(0, 0, -ground)) for n, s in parts.items()}
    top = V(-top.x, top.y, top.z - ground)
    return parts, {"le_y": le_y, "axis_y": axis_y, "top": top, "hollow": hollow, "rounded": rounded,
                   "drop": drop, "ground": ground}


def write_obj(shape, path, tol=0.02):
    """A preview mesh like the game's: every face meshed on its own (to an angle as well as a
    distance, so narrow curved strips like the shelf get enough triangles), its vertex normals
    averaged over that face's triangles only - so the ridge (a face boundary) shades as an edge
    however soft it gets, and smooth faces stay smooth. (STL left the renderer to split normals
    by angle, which zig-zagged along the ridge where its crease fades into the neck.)"""
    import MeshPart
    import numpy as np
    out, base = [], 1
    for face in shape.Faces:
        m = MeshPart.meshFromShape(Shape=face, LinearDeflection=tol, AngularDeflection=0.08, Relative=False)
        if not m.CountFacets:
            continue
        pts = np.array([(q.x, q.y, q.z) for q in m.Points])
        tri = np.array([f.PointIndices for f in m.Facets])
        fn = np.cross(pts[tri[:, 1]] - pts[tri[:, 0]], pts[tri[:, 2]] - pts[tri[:, 0]])
        # wind the face's triangles outward: check one against the true surface normal
        k = int(np.argmax(np.linalg.norm(fn, axis=1)))
        c = V(*pts[tri[k]].mean(axis=0))
        u, v = face.Surface.parameter(c)
        if V(*fn[k]).dot(face.normalAt(u, v)) < 0:
            tri = tri[:, [0, 2, 1]]
            fn = -fn
        vn = np.zeros_like(pts)
        for j in range(3):
            np.add.at(vn, tri[:, j], fn)
        vn /= np.maximum(np.linalg.norm(vn, axis=1, keepdims=True), 1e-12)
        out += ["v %.5f %.5f %.5f" % tuple(q) for q in pts]
        out += ["vn %.5f %.5f %.5f" % tuple(q) for q in vn]
        out += ["f %d//%d %d//%d %d//%d" % (a + base, a + base, b + base, b + base, c + base, c + base)
                for a, b, c in tri]
        base += len(pts)
    with open(path, "w") as f:
        f.write(chr(10).join(out) + chr(10))


def main(parts=None, info=None):
    """Build (unless handed a finished build), show, save the .FCStd, .step and stl/."""
    if parts is None:
        parts, info = build()
    if App.listDocuments().get(DOC_NAME):
        App.closeDocument(DOC_NAME)
    doc = App.newDocument(DOC_NAME)
    group = doc.addObject("App::DocumentObjectGroup", DOC_NAME)
    colors = {"Body": (0.72, 0.74, 0.77), "PortPlug": (0.10, 0.10, 0.11), "Badge": (0.12, 0.12, 0.13), "Screws": (0.75, 0.76, 0.78),
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
        if old.lower().endswith((".stl", ".obj")):
            os.remove(os.path.join(stl_dir, old))
    doc.saveAs(os.path.join(OUT_DIR, FILE_NAME + ".FCStd"))
    import Import
    Import.export([group], os.path.join(OUT_DIR, FILE_NAME + ".step"))
    import MeshPart
    for name, shape in parts.items():
        mesh = MeshPart.meshFromShape(Shape=shape, LinearDeflection=0.02, AngularDeflection=0.15)
        mesh.write(os.path.join(OUT_DIR, "stl", name + ".stl"))
        write_obj(shape, os.path.join(OUT_DIR, "stl", name + ".obj"))
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


# the variant again, over the toe and detail constants defined since, and what derives from them
globals().update(VARIANTS[VARIANT])
G = math.tan(math.radians(LOFT))
CL, SL = math.cos(math.radians(LOFT)), math.sin(math.radians(LOFT))
if "TOE_HIGH" not in VARIANTS[VARIANT]:
    TOE_HIGH = TOE_H + 1.5

if os.environ.get("GOLFHEAD_NO_MAIN") != "1":
    main()
