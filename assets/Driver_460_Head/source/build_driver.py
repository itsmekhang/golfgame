"""Parametric 460 cc driver head, unbranded.

The shape idea is a Prince Rupert's drop: a bulb (the body) whose surface all flows back into
one tail (the hosel). Face-on it is a wide-open eye - a flat crown line over a deep, round sole
line - and the face fills that whole front view, running from the round toe right up to the
hosel. From the toe the crown is a wedge (tall at the face, sloping down to a low rear), not a
balloon. The hosel sits forward, its front in line with the face; crown and heel climb into it
and the sole rounds up its heel side, never bulging past it.

How it is built:
- The BODY alone (no hosel) is a loft through vertical cross-sections across the head (x =
  const, seen from the toe), each one smooth closed curve - four superellipse quarters round a
  centre (squarer at the front, the crown quarter a tensioned cubic for the wedge) - sized by the
  head's outlines at that x and closing elliptically on a tip at the toe and inside the hosel at
  the heel. Its front stands FACE_PROUD proud of where the face will be.
- The HEAD is that body united with the hosel tube - a tapered tube on the shaft axis, run down
  to the sole line and trimmed there with a round corner - and cut by the face surface (a 12"
  bulge-and-roll sphere at the loft, easing forward off the head toward the heel), all as round
  blends (true fillets of fixed radius) in a signed distance field: the body's from its sampled
  surface, the tube's and face's analytic. The head's sections are found in that field along
  rays from each section's centre and lofted, so the result is one smooth B-spline surface.
- The face is then cut once more along the exact face surface (flat and flush: the loft only
  approximates it), the hosel top squared to the shaft and bored, and the details added: a heel
  weight port with a screw-in weight where the sole turns up into the hosel, and painted score
  lines in two groups.

Headless:  freecadcmd -c "exec(open(r'C:/Users/willi/Documents/FreeCAD/GolfHead/driver/build_driver.py').read())"
GUI:       run it as a macro, or exec() it through the FreeCAD MCP.

Units are mm. Address position, right-handed: ground plane z = 0, the face points at the target
(-Y), the toe is -X and the shaft rises toward +X at the lie angle. The face centre is x = 0,
y = 0 at FACE_CZ above the ground.
"""
import math
import os

import FreeCAD as App
import Part
from FreeCAD import Vector as V

OUT_DIR = os.environ.get("GOLFHEAD_OUT", r"C:\Users\willi\Documents\FreeCAD\GolfHead\driver")
DOC_NAME = "Driver460"

# ---- parameters ----------------------------------------------------------------------------
LOFT = 10.5
LIE = 60.0
BULGE_R = 304.8      # 12" face bulge and roll: the face is a sphere of this radius ...
FACE_CZ = 31.0       # ... through the face centre at this height (the front-most line of the
                     # sections)
# the face is cut: the body's rounded front stands FACE_PROUD proud of the face sphere and is
# planed off by it, so the face is wherever the body reaches past the sphere - an eye, rounded
# at both ends, with a crisp edge all round - and the body round it stays soft (corners crisp
# enough for a face edge, faded out toward the toe tip and the hosel, creased the toe)
FACE_PROUD = 12.0    # at the face's middle, easing to nothing at the eye's corners:
FACE_EYE = (-400.0, 400.0)  # the eye's corners (x) ...
FACE_EYE_Q = 1.4     # ... and how the proud depth falls toward them (bigger = pointier; 1.8
                     # read as a literal almond eye, 1 as a rounded rectangle)
# toward the heel the face runs flat right up to the hosel and stops there at a crisp fold: the
# cut spares the hosel tube, whose round front stands up off the flat face (faded out instead,
# the face left a warped, accidental-looking bend between itself and the hosel)
FACE_FADE_X = (40.0, 54.0)   # by the hosel the cut eases forward off the head - but only up
FACE_FADE_Z = (40.0, 52.0)   # high, where it would shave the hosel's front; low down it stays,
FACE_FADE = 0.0               # planing everything there flat and flush with the face (unused now:
                              # the fold plane below spares the hosel)
FACE_HEEL_END = (200.0, 210.0)  # the body's front stops standing proud of the face over this x, so
                              # the face ends short of the hosel in a round curve, like the toe ...
HEEL_RECEDE = 0.0             # ... and falls on back this far behind it, so the hosel stands
                              # clear in front and blends in with a clean concave sweep (level
                              # with the hosel's front, the two swelled into a lump)
FOLD_COLLAR = 1.0    # the cut spares a tube this much bigger than the hosel (sparing the hosel's
                     # own surface, the two coincided and wrinkled it): a collar step at the fold
FOLD_THETA = 40.0    # the face is cut flat right up to the hosel and stops on a plane laid
FOLD_CLEAR = 0.2     # tangent to it this far round from its front toward the toe (and this clear
                     # of it): a crisp, deliberate fold between face and plane, the plane running
                     # smoothly into the hosel, which the cut never touches
FACE_FILLET = (2.5, 2.0, 1.5, 1.0)  # round the face's edge (not the fold): first that OCC manages
FOLD_FILLET = (9.0, 7.0, 5.0, 3.5)  # and fill the fold's valley with a concave round, which also
                                    # rounds the face's top-heel corner into the hosel
FACE_EDGE_R = 2.0    # the face's edge is rounded this much - in the head's distance field, as
                     # OCC could not fillet it (it took ~100 s failing) - widening toward the
FACE_EDGE_R_TOE = 7.0    # toe and much more toward the heel, where the face softens into the
FACE_EDGE_R_HEEL = 7.0   # hosel rather than ending on an edge
FACE_EDGE_TOE_X = (-62.0, -40.0)
FACE_EDGE_HEEL_X = (18.0, 40.0)
FACE_TRUE = 0.0      # the lofted face only follows the face surface to within the sections'
                     # sampling (it rippled): it is cut once more along the true surface this far
                     # behind it, so the face is exactly flat (12" bulge and roll) and flush

# face-on, the eye: the crown's top line ...
CROWN_TOP = 60.0     # crown apex height at its highest, a little toe-ward of centre
CROWN_PEAK_X = -6.0
CROWN_FALL_TOE = 0.0012  # z drop per mm^2 toward the toe ...
CROWN_FALL_HEEL = 0.0016  # ... and toward the heel: a flat top line
# ... and the sole line: heel-toe camber from the low point, much rounder than the crown line -
# face-on the head is a wide-open eye, flat on top and deep underneath
CAMBER_TOE = 0.0042
CAMBER_HEEL = 0.0050
SOLE_LOW_X = -8.0
APEX_BACK = 18.0     # crown apex (and the sole's low point) this far behind the face
FRONT_Z = 22.0       # height of the body's front-most line (below the face centre: the face
                     # lies back, so it sits further forward low down)
REAR_Z = 26.0        # height of the rearmost point of each section

# from above: the rear outline (x, y), toe to heel (the toe cap closes it in further)
REAR_PTS = [(-80.0, 86.0), (-50.0, 100.0), (-28.0, 108.0), (-8.0, 112.0), (10.0, 108.5),
            (22.0, 100.0), (32.0, 87.5), (40.0, 73.0), (47.0, 57.0), (53.0, 40.0), (58.0, 26.0),
            (64.0, 12.0)]

# the toe: every outline closes in elliptically from CAP_X to the tip, and the quarters turn
# elliptic on the way, so the toe is a smooth dome
TOE_TIP = (-74.0, 30.0, 34.0)
CAP_X = -28.0
CAP_FRONT_X = -44.0  # ... the front (the face) only from here, so the face runs out into its
                     # eye corner before the toe pulls it back

# the quarters' squareness (2 = elliptic): the front ones squarer across the face, from
# DETAIL_TOE[1] to DETAIL_HEEL[0], easing off toward the toe tip and the heel
N_FRONT_TOP = 4.5    # the face's top: the face cut leaves a defined crown edge
N_FRONT_BOT = 3.5    # a rolled leading edge
N_BACK_TOP = 2.05    # crown to rear (unused while CROWN_TENSION is set)
CROWN_TENSION = 0.36 # the crown from its apex to the rear: a cubic whose end handles are this
                     # fraction of the way to the corner (0.55 is an ellipse, a balloon; lower
                     # runs the crown down to the rear in a long straight-ish wedge, like a
                     # real driver seen from the toe)
N_BACK_BOT = 2.8     # a flat sole with a full rear skirt
N_SOFT = 2.5         # the front quarters where the detail has faded ...
N_SOFT_HEEL_TOP = 3.0  # ... except the face's top-heel corner, which stays fuller until the
                       # hosel's round section takes over (rounded early, it left a valley in
                       # front of the hosel)
DETAIL_TOE = (-68.0, -40.0)
DETAIL_HEEL = (16.0, 40.0)

# the heel: the body's own sections close in on a heel tip tucked inside the hosel's base, as
# the toe does on its tip; the hosel - a tapered tube on the shaft axis - is then merged on with
# a smooth union (sampled section by section, see head_rings), so crown, heel and sole all run
# up into it like the drop's tail, with no seam, twist or dent
HEEL_TIP = (54.0, 13.0, 44.0)  # inside the hosel (on its axis) high up: the body's heel
                                # climbs into the hosel itself, crown and sole both rising
HEEL_CAP_X = 20.0
# the blends are round (a true fillet of this radius where two surfaces meet), not smooth
# minima, which also swelled the surfaces wherever the body and hosel merely ran close (blobs)
JOIN_R = 9.0         # fillet where crown, heel and sole meet the hosel (20 mm stretched a
                     # balloon-like web between the crown and the hosel)
HEEL_R = 24.0        # the hosel runs down to the sole line, its bottom corner rounded this much:
                     # the heel is one curve from the sole up the back of the hosel
N_RAYS = 192         # points round each section (fine enough for the face's rounded edge)
UNION_FROM_X = -999.0 # toe-ward of here the hosel is too far off to touch the body, and the
                     # sections are the body's own (exact: the sampled surface is unreliable at
                     # the toe tip, where its normals are undefined)

# the hosel screw: like an adjustable hosel's, it goes in from the sole up into the head under
# the hosel's base, square to the sole so its head sits flat and flush (down the hosel's own axis
# it came out at the very edge of the heel at a grazing angle, and broke the heel; parallel to
# the hosel it sat deep in a slanted hole)
PORT_AT = (24.0, 15.0)  # where (x, y) its axis meets the sole, roughly
PORT_R = 5.2         # pocket radius ...
PORT_DEPTH = 2.6     # ... and depth below the spot face
PORT_SPOT = 1.5      # the spot face reaches this far past the pocket
PORT_GAP = 0.45      # the weight sits this far in from the pocket's wall ...
PORT_SINK = 0.6      # ... and this far below the surface

# score lines, after a modern tour face: two groups of short painted lines, toe and heel, the
# middle of the face left clear; each a long line with a dash outboard of it. Rows (height up
# the face from the ground, toe line (x0, x1), toe dash (x0, x1), heel line, heel dash), mm
SCORE_ROWS = [
    (20.0, (-34.0, -18.0), (-40.0, -37.5), (13.0, 26.0), (29.0, 31.5)),
    (25.5, (-38.0, -18.0), (-44.0, -41.5), (13.0, 29.0), (32.0, 34.5)),
    (31.0, (-40.0, -18.0), (-46.0, -43.5), (13.0, 30.0), (33.0, 35.5)),
    (36.5, (-39.0, -18.0), (-45.0, -42.5), (13.0, 29.0), (32.0, 34.5)),
    (42.0, (-36.0, -18.0), (-42.0, -39.5), (13.0, 26.5), (29.5, 32.0)),
]
SCORE_W = 0.8        # groove width ...
SCORE_D = 0.35       # ... and depth; the paint fill sits this far down in it:
SCORE_PAINT_SINK = 0.08

# the hosel: a tube on the shaft axis, tapering like the drop's tail
HOSEL_GROUND_X = 29.0  # where the shaft axis meets the ground plane
HOSEL_FRONT_AT = (40.0, 40.0)  # its front lines up with the face plane at this (x, z) ...
HOSEL_SETBACK = 1.5  # ... this far behind it
HOSEL_R = 7.3        # radius low down ...
HOSEL_R_TOP = 6.6    # ... tapering to this at the top
HOSEL_TOP_Z = 74.0   # height of the hosel top (on the axis)
BORE_R = 4.3         # 0.335" tip
BORE_DEPTH = 40.0
FERRULE_H = 14.0
# merging the outlines into the hosel's: smooth-max widths (bigger = a broader blend)
K_CROWN = 20.0       # crown line into the hosel's toe side (fills the corner: no notch)
K_HEEL = 28.0        # sole into the hosel's heel side (rounds the heel)
K_PLAN = 20.0        # heel side into the back of the hosel, seen from above
FRONT_BLEND = (40.0, 54.0)  # the face's heel end eases back onto the hosel's front over this x
HOSEL_BLEND = (30.0, 58.0)  # ... and the section's centre and shape onto the hosel's

N_QUARTER = 16       # points per quarter
X_STEP = 2.5         # ring spacing
X_END = 80.0         # the loft runs on past the hosel top (trimmed square to the shaft)

TL = math.tan(math.radians(LOFT))
AXIS = V(math.cos(math.radians(LIE)), 0, math.sin(math.radians(LIE)))      # up the shaft
ACROSS = V(-math.sin(math.radians(LIE)), 0, math.cos(math.radians(LIE)))   # across it, toe-up


def smooth(t):
    t = min(max(t, 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def smax(a, b, k):
    """Smooth maximum: max(a, b), rounded over where they are within k of each other."""
    h = max(k - abs(a - b), 0.0) / k
    return max(a, b) + h * h * k / 4.0


def pchip(pts):
    """A shape-preserving cubic through (x, y) points (no overshoot between them)."""
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    n = len(pts)
    h = [xs[i + 1] - xs[i] for i in range(n - 1)]
    d = [(ys[i + 1] - ys[i]) / h[i] for i in range(n - 1)]
    m = [d[0]] + [0.0] * (n - 2) + [d[-1]]
    for i in range(1, n - 1):
        if d[i - 1] * d[i] > 0:
            w1, w2 = 2 * h[i] + h[i - 1], h[i] + 2 * h[i - 1]
            m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])

    def f(x):
        x = min(max(x, xs[0]), xs[-1])  # held level past the ends
        i = max(0, min(n - 2, next((j for j in range(n - 1) if x < xs[j + 1]), n - 2)))
        t = (x - xs[i]) / h[i]
        return ((2 * t ** 3 - 3 * t ** 2 + 1) * ys[i] + (t ** 3 - 2 * t ** 2 + t) * h[i] * m[i]
                + (-2 * t ** 3 + 3 * t ** 2) * ys[i + 1] + (t ** 3 - t ** 2) * h[i] * m[i + 1])
    return f


rear_y = pchip(REAR_PTS)


# ---- the hosel ------------------------------------------------------------------------------
def axis_y():
    x, z = HOSEL_FRONT_AT
    face = (x * x + (z - FACE_CZ) ** 2) / (2 * BULGE_R) + (z - FACE_CZ) * TL
    return face + HOSEL_SETBACK + HOSEL_R


def on_axis(z):
    return V(HOSEL_GROUND_X, axis_y(), 0) + AXIS * (z / AXIS.z)


def hosel_r(s):
    """Radius at s mm up the axis from the ground: HOSEL_R low down, tapering to the top."""
    s_top = HOSEL_TOP_Z / AXIS.z
    t = min(max((s - 30.0) / (s_top - 30.0), 0.0), 1.0)
    return HOSEL_R + (HOSEL_R_TOP - HOSEL_R) * t


def hosel_box(x):
    """The hosel's x-section - an ellipse r wide and 2r tall round the axis - as (front, rear,
    bottom, top, centre height)."""
    s = (x - HOSEL_GROUND_X) / AXIS.x
    r = hosel_r(s)
    zc = s * AXIS.z
    ay = axis_y()
    return ay - r, ay + r, zc - r / AXIS.x, zc + r / AXIS.x, zc


# ---- sections -------------------------------------------------------------------------------
def eye(x):
    """1 - u^2 along the face: 1 mid-face (u = 0), 0 at the eye's corners (u = -1 toe, 1 heel),
    negative beyond them."""
    a, b = FACE_EYE
    u = (2.0 * x - (a + b)) / (b - a)
    return 1.0 - u * u


def face_proud(x):
    """How far the body's front stands proud of the face sphere at x: FACE_PROUD across the
    face, falling to 0 toward the heel as the face fades out there (FACE_FADE_X)."""
    e = eye(x)
    h = smooth((x - FACE_HEEL_END[0]) / (FACE_HEEL_END[1] - FACE_HEEL_END[0]))
    return FACE_PROUD * math.copysign(abs(e) ** FACE_EYE_Q, e) * (1.0 - h) - HEEL_RECEDE * h


def detail(x):
    toe = smooth((x - DETAIL_TOE[0]) / (DETAIL_TOE[1] - DETAIL_TOE[0]))
    heel = 1.0 - smooth((x - DETAIL_HEEL[0]) / (DETAIL_HEEL[1] - DETAIL_HEEL[0]))
    return toe * heel


def cap_k(x, start=CAP_X):
    """How much of the toe's outline is left at x: 1 heel-ward of start, closing elliptically to
    0 at the tip (zero slope at start, so the cap joins the body smoothly)."""
    if x >= start:
        return 1.0
    u = (x - start) / (TOE_TIP[0] - start)
    return math.sqrt(max(0.0, 1.0 - u * u))


def heel_k(x):
    """The heel's counterpart of cap_k: 1 toe-ward of HEEL_CAP_X, 0 at the heel tip."""
    if x <= HEEL_CAP_X:
        return 1.0
    u = (x - HEEL_CAP_X) / (HEEL_TIP[0] - HEEL_CAP_X)
    return math.sqrt(max(0.0, 1.0 - u * u))


def section_params(x):
    """The section at x: (front, rear, bottom, top) outline, the centre (y of the apex and the
    sole's low point; heights of the front-most and rear-most points), the four quarters'
    squareness (front-top, back-top, back-bottom, front-bottom), and how much of the body's
    own character is left (1 mid-head, 0 at the tips, where the sections are plain ellipses).
    The sections stand upright:
    the face cut lays the face back by the loft (leaning the sections back with it, then
    upright again for the hosel, twisted the crown where it runs into the hosel)."""
    f = x * x / (2 * BULGE_R) - face_proud(x)
    r = rear_y(x)
    a = CROWN_FALL_TOE if x < CROWN_PEAK_X else CROWN_FALL_HEEL
    t = CROWN_TOP - a * (x - CROWN_PEAK_X) ** 2
    b = (CAMBER_TOE if x < SOLE_LOW_X else CAMBER_HEEL) * (x - SOLE_LOW_X) ** 2
    yc, zf, zb = f + APEX_BACK, FRONT_Z, REAR_Z
    d = detail(x)
    n = [N_FRONT_TOP, N_BACK_TOP, N_BACK_BOT, N_FRONT_BOT]
    body_w = 1.0
    if x < CAP_X:  # the toe cap: everything closes in on the tip, the quarters turn elliptic
        k = cap_k(x)
        _, ty, tz = TOE_TIP
        f = ty + (f - ty) * cap_k(x, CAP_FRONT_X)
        r, yc = (ty + (q - ty) * k for q in (r, yc))
        b, t, zf, zb = (tz + (q - tz) * k for q in (b, t, zf, zb))
        n = [2.0 + (q - 2.0) * k * k for q in n]
        body_w *= k * k
        # ... and centre up, so the last sections are plain ellipses (lopsided ones left creases
        # running into the tip where their quarters meet)
        c = 1.0 - k * k
        yc = yc + ((f + r) / 2 - yc) * c
        zf, zb = zf + ((b + t) / 2 - zf) * c, zb + ((b + t) / 2 - zb) * c
    if x > HEEL_CAP_X:  # the heel: the same, closing on the heel tip
        k = heel_k(x)
        _, hy, hz = HEEL_TIP
        f, r, yc = (hy + (q - hy) * k for q in (f, r, yc))
        b, t, zf, zb = (hz + (q - hz) * k for q in (b, t, zf, zb))
        n = [2.0 + (q - 2.0) * k * k for q in n]
        body_w *= k * k
        c = 1.0 - k * k
        yc = yc + ((f + r) / 2 - yc) * c
        zf, zb = zf + ((b + t) / 2 - zf) * c, zb + ((b + t) / 2 - zb) * c
    # the front quarters are squarest where the front stands furthest proud of the face sphere
    # and turn elliptic where it stops, so the face's height tapers into the eye's corners
    # (square right to its ends, the face came out blunt-ended)
    m = smooth((x * x / (2 * BULGE_R) - f) / FACE_PROUD)  # (a square root here wrinkled the toe)
    if x < 0.0:  # toward the toe, ease off over a long run (following the front, which pulls
        # back fast into the toe tip, it left a pinch on the toe)
        m = smooth((x - TOE_TIP[0] - 2.0) / (CAP_FRONT_X + 6.0 - TOE_TIP[0] - 2.0))
    n[0] = 2.0 + (n[0] - 2.0) * m
    n[3] = 2.0 + (n[3] - 2.0) * m
    depth, height = r - f, t - b
    yc = min(max(yc, f + 0.15 * depth), r - 0.15 * depth)
    zf = min(max(zf, b + 0.15 * height), t - 0.15 * height)
    zb = min(max(zb, b + 0.15 * height), t - 0.15 * height)
    return f, r, b, t, yc, zf, zb, n, body_w


def ring_at(x, n_quarter=None):
    """4 * N_QUARTER points round the section at x, starting at the front-most point and going
    up the face, over the crown, round the back and along the sole."""
    f, r, b, t, yc, zf, zb, n, body_w = section_params(x)
    nq = n_quarter or N_QUARTER
    tension = 0.5523 + (CROWN_TENSION - 0.5523) * body_w  # (0.5523: a quarter circle)
    pts = []
    for q in range(4):
        for j in range(nq):
            if q == 1:  # the crown, apex to rear: the tensioned cubic
                u = j / nq
                p0, p1 = (yc, t), (yc + tension * (r - yc), t)
                p2, p3 = (r, zb + tension * (t - zb)), (r, zb)
                w0, w1, w2, w3 = (1 - u) ** 3, 3 * u * (1 - u) ** 2, 3 * u * u * (1 - u), u ** 3
                pts.append(V(x, w0 * p0[0] + w1 * p1[0] + w2 * p2[0] + w3 * p3[0],
                             w0 * p0[1] + w1 * p1[1] + w2 * p2[1] + w3 * p3[1]))
                continue
            th = (q + j / nq) * math.pi / 2  # 0 at the front, pi/2 at the top ...
            ct, st = -math.cos(th), math.sin(th)    # (the front is -y)
            front = ct < 0 or (ct == 0 and q in (0, 3))
            zc = zf if front else zb
            ay = (yc - f) if ct < 0 else (r - yc)
            az = (t - zc) if st > 0 else (zc - b)
            e = n[q]
            y = yc + ay * math.copysign(abs(ct) ** (2 / e), ct)
            z = zc + az * math.copysign(abs(st) ** (2 / e), st)
            pts.append(V(x, y, z))
    return pts


def body_xs():
    """Ring stations for the body alone: round the toe cap, evenly along the body, round the
    heel cap (each cap evenly round its ellipse, so the rings are about evenly spaced)."""
    xs = []
    n_cap = 14
    for j in range(n_cap, 0, -1):
        xs.append(CAP_X + (TOE_TIP[0] - CAP_X) * math.sin(math.radians(86.0) * j / n_cap))
    n = round((HEEL_CAP_X - CAP_X) / X_STEP)
    xs += [CAP_X + (HEEL_CAP_X - CAP_X) * j / n for j in range(n + 1)]
    for j in range(1, n_cap + 1):
        xs.append(HEEL_CAP_X + (HEEL_TIP[0] - HEEL_CAP_X) * math.sin(math.radians(86.0) * j / n_cap))
    return xs


def head_xs():
    """Ring stations for the whole head: the body's toe and middle, then evenly on through the
    heel and up the hosel to X_END."""
    # (not within 2 mm of the toe tip, where the sampled surface's normals give out: the loft
    # closes from the last ring to the tip)
    xs = [x for x in body_xs() if TOE_TIP[0] + 2.0 <= x <= HEEL_CAP_X]
    n = round((X_END - HEEL_CAP_X) / X_STEP)
    xs += [HEEL_CAP_X + (X_END - HEEL_CAP_X) * j / n for j in range(1, n + 1)]
    return xs


def chord_params(rows):
    """One parameter list for many closed point rings of the same structure: their normalized
    chord lengths (closing span included), averaged. Interpolated with it, every ring's curve has
    the same knots, so the loft does not have to merge them (left free, it merged 47 rings of 60
    points into a 2541-pole surface that stalled every later boolean)."""
    acc = [0.0] * (len(rows[0]) + 1)
    for pts in rows:
        d = [0.0]
        for a, b in zip(pts, pts[1:] + pts[:1]):
            d.append(d[-1] + (b - a).Length)
        acc = [s + v / d[-1] for s, v in zip(acc, d)]
    return [v / len(rows) for v in acc]


def loft_rings(rings, tip=None):
    """A solid lofted through closed point rings (and from a tip vertex), outward-facing."""
    for flip in (False, True):
        wires = [Part.Vertex(tip)] if tip is not None else []
        rows = [[ring[0]] + ring[:0:-1] if flip else ring for ring in rings]
        par = chord_params(rows)
        for pts in rows:
            curve = Part.BSplineCurve()
            curve.interpolate(Points=pts, PeriodicFlag=True, Parameters=par)
            wires.append(Part.Wire(curve.toShape()))
        # degree 2 along the head: through every ring, no overshoot (at the default 5 the
        # surface swung 32 mm out past the hosel; at 3 it blew up altogether)
        loft = Part.makeLoft(wires, True, False, False, 2)
        if loft.Volume > 0:
            return loft
    raise RuntimeError("loft is inside out both ways")


def sample_surface(shape, tol=0.01):
    """Points and outward normals all over a solid: its fine tessellation's vertices, each with
    the area-weighted normal of the triangles round it."""
    import numpy as np
    verts, tris = shape.tessellate(tol)
    p = np.array([(v.x, v.y, v.z) for v in verts])
    t = np.array(tris)
    fn = np.cross(p[t[:, 1]] - p[t[:, 0]], p[t[:, 2]] - p[t[:, 0]])
    n = np.zeros_like(p)
    for k in range(3):
        np.add.at(n, t[:, k], fn)
    keep = np.linalg.norm(n, axis=1) > 1e-12
    p, n = p[keep], n[keep]
    return p, n / np.linalg.norm(n, axis=1)[:, None]


class HeadField:
    """Signed distance to the head: the body (sampled from its own loft) smoothly united with
    the hosel tube. Negative inside."""

    def __init__(self, body):
        import numpy as np
        from scipy.spatial import cKDTree
        self.np = np
        self.p, self.n = sample_surface(body)
        if self.n[self.p[:, 1].argmax(), 1] < 0:  # make the normals point out
            self.n = -self.n
        self.tree = cKDTree(self.p)
        self.g = np.array([HOSEL_GROUND_X, axis_y(), 0.0])
        self.a = np.array([AXIS.x, AXIS.y, AXIS.z])
        self.s_top = HOSEL_TOP_Z / AXIS.z

    def body(self, q):
        np = self.np
        d, i = self.tree.query(q)
        off = q - self.p[i]
        plane = np.einsum("ij,ij->i", off, self.n[i])
        # near the surface the distance to the nearest sample's tangent plane (exact to well
        # under 0.01 mm); further out the distance to the sample itself, signed
        return np.where(d < 3.0, plane, np.sign(plane) * d)

    def hosel(self, q):
        """The hosel tube, run down to the sole line and trimmed there with a round corner."""
        np = self.np
        s = np.clip((q - self.g) @ self.a, -80.0, self.s_top + 60.0)
        foot = self.g + np.outer(s, self.a)
        t = np.clip((s - 30.0) / (self.s_top - 30.0), 0.0, 1.0)
        tube = np.linalg.norm(q - foot, axis=1) - (HOSEL_R + (HOSEL_R_TOP - HOSEL_R) * t)
        x = q[:, 0]
        sole = np.where(x < SOLE_LOW_X, CAMBER_TOE, CAMBER_HEEL) * (x - SOLE_LOW_X) ** 2
        return self.round_and(tube, sole - q[:, 2], HEEL_R)

    def round_and(self, a, b, r):
        """Intersection with a round edge of radius r (hg_sdf fOpIntersectionRound)."""
        np = self.np
        u = np.stack([np.maximum(r + a, 0.0), np.maximum(r + b, 0.0)], axis=1)
        return np.minimum(-r, np.maximum(a, b)) + np.linalg.norm(u, axis=1)

    def round_or(self, a, b, r):
        """Union with a round fillet of radius r in the corners (hg_sdf fOpUnionRound)."""
        np = self.np
        u = np.stack([np.maximum(r - a, 0.0), np.maximum(r - b, 0.0)], axis=1)
        return np.maximum(r, np.minimum(a, b)) - np.linalg.norm(u, axis=1)

    def face(self, q):
        """Distance in front of the face-cut surface (negative behind it, inside the head)."""
        np = self.np
        x, z = q[:, 0], q[:, 2]
        out = np.array([0.0, -math.cos(math.radians(LOFT)), math.sin(math.radians(LOFT))])
        c = np.array([0.0, 0.0, FACE_CZ]) - out * BULGE_R
        sph = c[1] - np.sqrt(np.maximum(BULGE_R ** 2 - (x - c[0]) ** 2 - (z - c[2]) ** 2, 1.0))
        fade = self.smooth((x - FACE_FADE_X[0]) / (FACE_FADE_X[1] - FACE_FADE_X[0])) * self.smooth(
            (z - FACE_FADE_Z[0]) / (FACE_FADE_Z[1] - FACE_FADE_Z[0]))
        y = sph - FACE_FADE * fade
        return (y - q[:, 1]) * math.cos(math.radians(LOFT))

    def smooth(self, t):
        t = self.np.clip(t, 0.0, 1.0)
        return t * t * (3.0 - 2.0 * t)

    def edge_r(self, x):
        toe = 1.0 - self.smooth((x - FACE_EDGE_TOE_X[0]) / (FACE_EDGE_TOE_X[1] - FACE_EDGE_TOE_X[0]))
        heel = self.smooth((x - FACE_EDGE_HEEL_X[0]) / (FACE_EDGE_HEEL_X[1] - FACE_EDGE_HEEL_X[0]))
        return FACE_EDGE_R + (FACE_EDGE_R_TOE - FACE_EDGE_R) * toe + (FACE_EDGE_R_HEEL - FACE_EDGE_R) * heel

    def tube(self, q):
        """Distance to the hosel tube alone (its full length, untrimmed)."""
        np = self.np
        s = np.clip((q - self.g) @ self.a, -80.0, self.s_top + 60.0)
        foot = self.g + np.outer(s, self.a)
        t = np.clip((s - 30.0) / (self.s_top - 30.0), 0.0, 1.0)
        return np.linalg.norm(q - foot, axis=1) - (HOSEL_R + (HOSEL_R_TOP - HOSEL_R) * t)

    def head(self, q):
        """Body and hosel; the face is cut afterwards, exactly (in the field its rounded edge
        and the hosel fought, wrinkling the hosel)."""
        return self.round_or(self.body(q), self.hosel(q), JOIN_R)


def ring_frame(x):
    """Centre and half-size of the section at x, for aiming its rays: the body's own section
    toe-ward, the hosel's round one heel-ward, blended across the heel."""
    f, r, b, t = section_params(min(x, HEEL_TIP[0] - 1.0))[:4]
    hf, hr, hb, ht, _ = hosel_box(x)
    w = smooth((x - 26.0) / (HEEL_TIP[0] + 4.0 - 26.0))
    cy = (f + r) / 2 + ((hf + hr) / 2 - (f + r) / 2) * w
    cz = (b + t) / 2 + ((hb + ht) / 2 - (b + t) / 2) * w
    ay = (r - f) / 2 + ((hr - hf) / 2 - (r - f) / 2) * w
    az = (t - b) / 2 + ((ht - hb) / 2 - (t - b) / 2) * w
    return cy, cz, ay, az


def head_rings(field):
    """Every station's section of the united head, found along N_RAYS rays from its centre
    (aimed round an ellipse of the section's size, so the points spread evenly), starting at the
    front and going up over the crown, like the body's own rings."""
    np = field.np
    rings = []
    for x in head_xs():
        cy, cz, ay, az = ring_frame(x)
        if x >= UNION_FROM_X and field.head(np.array([[x, cy, cz]]))[0] >= 0:
            raise RuntimeError("section centre outside the head at x=%.1f" % x)
        t = 2 * np.pi * np.arange(N_RAYS) / N_RAYS
        d = np.stack([-ay * np.cos(t), az * np.sin(t)], axis=1)
        d /= np.linalg.norm(d, axis=1)[:, None]

        def at(rad):
            return np.stack([np.full(N_RAYS, x), cy + d[:, 0] * rad, cz + d[:, 1] * rad], axis=1)

        if x < UNION_FROM_X:  # the body's own section: where each ray leaves its polygon
            poly = np.array([(p.y, p.z) for p in ring_at(x, 200)])
            a, e = poly, np.roll(poly, -1, axis=0) - poly
            w = a[None, :, :] - np.array([cy, cz])[None, None, :]
            den = d[:, None, 0] * e[None, :, 1] - d[:, None, 1] * e[None, :, 0]
            with np.errstate(divide="ignore", invalid="ignore"):
                tr = (w[..., 0] * e[None, :, 1] - w[..., 1] * e[None, :, 0]) / den
                ue = (w[..., 0] * d[:, None, 1] - w[..., 1] * d[:, None, 0]) / den
            hit = (np.abs(den) > 1e-12) & (tr > 0) & (ue >= 0) & (ue <= 1)
            rad = np.where(hit, tr, np.inf).min(axis=1)
            rings.append([V(x, cy + d[j, 0] * rad[j], cz + d[j, 1] * rad[j]) for j in range(N_RAYS)])
            continue

        # sphere-trace out from the centre (step by the distance to the surface while inside),
        # then bisect between the last point inside and the first outside
        rad = np.zeros(N_RAYS)
        lo = np.zeros(N_RAYS)
        hi = np.full(N_RAYS, np.inf)
        for _ in range(300):
            open_ = np.isinf(hi)
            if not open_.any():
                break
            v = field.head(at(rad))
            inside = v < 0
            lo = np.where(open_ & inside, rad, lo)
            hi = np.where(open_ & ~inside, rad, hi)
            rad = np.where(open_ & inside, rad + np.maximum(-v * 0.9, 0.05), rad)
        for _ in range(22):
            mid = (lo + hi) / 2
            out = field.head(at(mid)) > 0
            hi = np.where(out, mid, hi)
            lo = np.where(out, lo, mid)
        rad = (lo + hi) / 2
        ring = [V(x, cy + d[j, 0] * rad[j], cz + d[j, 1] * rad[j]) for j in range(N_RAYS)]
        gaps = [(ring[j] - ring[j - 1]).Length for j in range(N_RAYS)]
        if max(gaps) > 6.0 * sorted(gaps)[N_RAYS // 2] + 1.0:  # a ray that got away
            print("warning: ragged section at x=%.1f (gap %.1f mm)" % (x, max(gaps)))
        rings.append(ring)
    return rings


def face_sphere():
    """The face: a sphere of BULGE_R through the face centre, its normal there tilted up by
    the loft."""
    out = V(0, -math.cos(math.radians(LOFT)), math.sin(math.radians(LOFT)))
    return Part.makeSphere(BULGE_R, V(0, 0, FACE_CZ) - out * BULGE_R)


def face_cut_y(x, z):
    """y of the surface the face is cut along at (x, z): the face sphere, easing forward off the
    head toward the heel."""
    out = V(0, -math.cos(math.radians(LOFT)), math.sin(math.radians(LOFT)))
    c = V(0, 0, FACE_CZ) - out * BULGE_R
    sph = c.y - math.sqrt(max(BULGE_R ** 2 - (x - c.x) ** 2 - (z - c.z) ** 2, 1.0))
    fade = smooth((x - FACE_FADE_X[0]) / (FACE_FADE_X[1] - FACE_FADE_X[0])) * smooth(
        (z - FACE_FADE_Z[0]) / (FACE_FADE_Z[1] - FACE_FADE_Z[0]))
    return sph - FACE_FADE * fade


def face_cut_tool(behind=0.0):
    """Everything in front of the face-cut surface (moved back by `behind`): the surface
    (interpolated on a grid) swept forward."""
    xs = [-110.0 + 5.0 * i for i in range(45)]
    zs = [-40.0 + 5.0 * j for j in range(33)]
    grid = [[V(x, face_cut_y(x, z) + behind, z) for z in zs] for x in xs]
    surf = Part.BSplineSurface()
    surf.interpolate(grid)
    return Part.Face(surf).extrude(V(0, -150.0, 0))


def is_face_plate(face):
    """Whether a face of the finished head lies on the face-cut surface (the striking face)."""
    if isinstance(face.Surface, Part.Sphere):
        return abs(face.Surface.Radius - BULGE_R) < 0.01
    try:
        u0, u1, v0, v1 = face.ParameterRange
        for a, b in ((0.3, 0.3), (0.5, 0.5), (0.7, 0.6)):
            p = face.valueAt(u0 + (u1 - u0) * a, v0 + (v1 - v0) * b)
            if abs(p.y - (face_cut_y(p.x, p.z) + FACE_TRUE)) > 0.05:
                return False
        return True
    except Exception:
        return False


def hosel_solid(grow=0.0):
    """The hosel tube as a solid (for sparing it from the face cut), from below the ground to
    past the top."""
    g = V(HOSEL_GROUND_X, axis_y(), 0)
    s_top = HOSEL_TOP_Z / AXIS.z
    low = Part.makeCylinder(HOSEL_R + grow, 30.0 + 60.0, g + AXIS * -60.0, AXIS)
    cone = Part.makeCone(HOSEL_R + grow, HOSEL_R_TOP + grow, s_top - 30.0, g + AXIS * 30.0, AXIS)
    top = Part.makeCylinder(HOSEL_R_TOP + grow, 60.0, g + AXIS * s_top, AXIS)
    return low.fuse(cone).fuse(top).removeSplitter()


def fold_plane():
    """The fold plane: tangent to the hosel FOLD_THETA round from its front toward the toe.
    Returns (point, outward normal)."""
    th = math.radians(FOLD_THETA)
    d = V(0, -math.cos(th), 0) + ACROSS * math.sin(th)
    d.normalize()
    return on_axis(45.0) + d * (HOSEL_R + FOLD_CLEAR), d


def exact_face_cut(head):
    """Cut the face flat (the 12" face sphere) everywhere in front of both the sphere and the fold
    plane, then round its edge (not the fold)."""
    out = V(0, -math.cos(math.radians(LOFT)), math.sin(math.radians(LOFT)))
    sphere = Part.makeSphere(BULGE_R, V(0, 0, FACE_CZ) - out * BULGE_R)
    front = Part.makeBox(400.0, 260.0, 300.0, V(-200.0, -200.0, -100.0)).cut(sphere)
    p0, d = fold_plane()
    u = d.cross(AXIS).normalize()
    w = d.cross(u).normalize()
    corner = p0 - u * 300.0 - w * 300.0
    plate = Part.Face(Part.makePolygon([corner, corner + u * 600.0, corner + u * 600.0 + w * 600.0,
                                        corner + w * 600.0, corner]))
    ahead = plate.extrude(d * 300.0)
    body = head.cut(front.common(ahead))
    faces = [f for f in body.Faces if isinstance(f.Surface, Part.Sphere)]
    folds = [f for f in body.Faces if isinstance(f.Surface, Part.Plane)
             and abs(f.Surface.Axis.dot(d)) > 0.999]
    fold_edges = {e.hashCode() for f in folds for e in f.Edges}
    face_hashes = {e.hashCode() for f in faces for e in f.Edges}
    valley = [e for f in folds for e in f.Edges if e.hashCode() in face_hashes]
    for r in FOLD_FILLET:  # the fold's valley first ...
        try:
            filled = body.makeFillet(r, valley)
            if filled.isValid() and len(filled.Solids) == 1:
                body = filled
                break
        except Exception:  # OCC raises when it cannot
            continue
    # ... then the face's own edge: the sphere face's edges onto the loft surface
    faces = [f for f in body.Faces if isinstance(f.Surface, Part.Sphere)]
    loft = [f for f in body.Faces if isinstance(f.Surface, Part.BSplineSurface) and f.Area > 5000.0]
    loft_hashes = {e.hashCode() for f in loft for e in f.Edges}
    edges = [e for f in faces for e in f.Edges if e.hashCode() in loft_hashes]
    for r in FACE_FILLET:
        try:
            rounded = body.makeFillet(r, edges)
            if rounded.isValid() and len(rounded.Solids) == 1:
                return rounded, r
        except Exception:  # OCC raises when it cannot
            continue
    return body, None


def cut_face(body):
    """Plane the body's proud front off along the face-cut surface, then round the face's edge
    if OCC can (FACE_EDGE_R)."""
    cut = body.cut(face_cut_tool())
    faces = [f for f in cut.Faces if f.Surface.isDerivedFrom("Part::GeomBSplineSurface")
             and abs(f.normalAt(*f.Surface.parameter(f.CenterOfMass))[1]) > 0.8 and f.Area > 2000]
    for r in FACE_EDGE_R:
        try:
            out = cut.makeFillet(r, [e for f in faces for e in f.Edges])
            if out.isValid() and len(out.Solids) == 1:
                return out, r
        except Exception:  # OCC raises when it cannot
            continue
    return cut, None


def heel_port(body):
    """Sink the hosel screw into the sole; returns (body, weight)."""
    c = V(PORT_AT[0], PORT_AT[1], 25.0)
    ray = Part.makeLine(c, c + V(0, 0, -80.0))
    hits = [v.Point for v in body.section(ray).Vertexes]
    if not hits:
        return body, None
    p = min(hits, key=lambda q: (q - c).Length)      # where it comes out of the sole
    face = min(body.Faces, key=lambda f: f.distToShape(Part.Vertex(p))[0])
    n = face.normalAt(*face.Surface.parameter(p))    # square to the sole there: the screw goes
    if n.z > 0:                                      # straight up into the head, its head flat
        n = n * -1.0                                 # and flush with the sole
    n.normalize()
    u = n.cross(V(0, 1, 0)).normalize()
    w = n.cross(u)
    # how far the sole round the pocket's rim stands off a plane square to the screw at p
    lift = 0.0
    for i in range(24):
        a = 2 * math.pi * i / 24
        q0 = p + (u * math.cos(a) + w * math.sin(a)) * PORT_R
        line = Part.makeLine(q0 - n * 15.0, q0 + n * 15.0)
        ds = [(q.Point - p).dot(n) for q in body.section(line).Vertexes]
        if ds:
            lift = min(lift, min(ds, key=abs))
    seat = p + n * (lift - 0.3)                      # the pocket's mouth, under the whole rim
    body = body.cut(Part.makeCylinder(PORT_R, PORT_DEPTH + 12.0, seat - n * PORT_DEPTH, n))
    # the screw: a disc with a chamfered rim and a six-lobe drive, its head just inside the mouth
    top = seat - n * PORT_SINK
    h = PORT_DEPTH - PORT_SINK
    weight = Part.makeCylinder(PORT_R - PORT_GAP, h, top - n * h, n)
    rim = [e for e in weight.Edges if abs((e.CenterOfMass - top).dot(n)) < 1e-3 and e.Length > 10]
    try:
        weight = weight.makeChamfer(0.4, rim)
    except Exception:
        pass
    lobes = []
    for i in range(96):
        a = 2 * math.pi * i / 96
        r = 1.5 + 0.28 * math.cos(6 * a)
        lobes.append(top + (u * math.cos(a) + w * math.sin(a)) * r)
    curve = Part.BSplineCurve()
    curve.interpolate(lobes, PeriodicFlag=True)
    drive = Part.Face(Part.Wire([curve.toShape()])).extrude(-n * 1.2)
    weight = weight.cut(drive)
    return body, weight


def score_lines(body):
    """Cut the score-line grooves into the face and fill them with paint; returns (body, paint)."""
    lay = math.radians(LOFT)
    n_out = V(0, -math.cos(lay), math.sin(lay))       # out of the face
    up = V(0, math.sin(lay), math.cos(lay))           # up the face
    slots = []
    for z, *runs in SCORE_ROWS:
        for x0, x1 in runs:
            xm = (x0 + x1) / 2
            c = V(xm, face_cut_y(xm, z) + FACE_TRUE, z)
            half = (x1 - x0) / 2 - SCORE_W / 2
            r = SCORE_W / 2
            pts = [c + V(-half, 0, 0) - up * r, c + V(half, 0, 0) - up * r]
            arc1 = Part.Arc(pts[1], c + V(half + r, 0, 0), c + V(half, 0, 0) + up * r)
            pts2 = [c + V(half, 0, 0) + up * r, c + V(-half, 0, 0) + up * r]
            arc2 = Part.Arc(pts2[1], c + V(-half - r, 0, 0), pts[0])
            wire = Part.Wire([Part.LineSegment(pts[0], pts[1]).toShape(), arc1.toShape(),
                              Part.LineSegment(pts2[0], pts2[1]).toShape(), arc2.toShape()])
            face = Part.Face(wire)
            slots.append(face.translated(n_out * 3.0).extrude(n_out * -6.0))
    slots = Part.makeCompound(slots)
    skin = face_cut_tool(FACE_TRUE + SCORE_D)  # the face's outer SCORE_D
    grooves = slots.common(skin).common(body)
    body = body.cut(grooves)
    paint = grooves.cut(face_cut_tool(FACE_TRUE + SCORE_PAINT_SINK))
    return body, paint


def body_loft():
    """The body alone, closed at both tips."""
    wires = []
    rings = [ring_at(x) for x in body_xs()]
    par = chord_params(rings)
    for pts in rings:
        curve = Part.BSplineCurve()
        curve.interpolate(Points=pts, PeriodicFlag=True, Parameters=par)
        wires.append(Part.Wire(curve.toShape()))
    tips = [Part.Vertex(V(*TOE_TIP))], [Part.Vertex(V(*HEEL_TIP))]
    return Part.makeLoft(tips[0] + wires + tips[1], True, False, False, 2)


def build():
    field = HeadField(body_loft())
    head = loft_rings(head_rings(field), V(*TOE_TIP))
    body, edge_r = exact_face_cut(head)
    body, weight = heel_port(body)
    body, paint = score_lines(body)
    top = on_axis(HOSEL_TOP_Z)
    body = body.cut(Part.makeCylinder(80.0, 80.0, top, AXIS))  # square the hosel top
    body = body.cut(Part.makeCylinder(BORE_R, BORE_DEPTH + 1.0, top + AXIS * 1.0, -AXIS))
    ferrule = Part.makeCone(HOSEL_R_TOP - 0.2, 4.9, FERRULE_H, top, AXIS)
    ferrule = ferrule.cut(Part.makeCylinder(BORE_R, FERRULE_H + 2, top - AXIS, AXIS))
    ground = body.optimalBoundingBox().ZMin
    parts = {"Body": body, "Ferrule": ferrule}
    if weight is not None:
        parts["HeelWeight"] = weight
    if paint is not None and paint.Solids:
        parts["ScorePaint"] = paint
    parts = {n: s.translated(V(0, 0, -ground)) for n, s in parts.items()}
    return parts, {"ground": ground, "axis_y": axis_y(), "top": top, "face_edge_r": edge_r}


def show(parts, info):
    if App.listDocuments().get(DOC_NAME):
        App.closeDocument(DOC_NAME)
    doc = App.newDocument(DOC_NAME)
    colors = {"Body": (0.62, 0.64, 0.67), "Face": (0.30, 0.31, 0.33), "Ferrule": (0.03, 0.03, 0.035),
              "HeelWeight": (0.12, 0.12, 0.13), "ScorePaint": (0.92, 0.92, 0.90)}
    for name, shape in parts.items():
        obj = doc.addObject("Part::Feature", name)
        obj.Shape = shape
        if App.GuiUp:
            mat = App.Material()
            mat.DiffuseColor = colors.get(name, (0.6, 0.6, 0.62))
            mat.SpecularColor = (0.35, 0.35, 0.35)
            mat.Shininess = 0.35
            obj.ViewObject.ShapeAppearance = [mat]
            obj.ViewObject.Deviation = 0.05
            obj.ViewObject.AngularDeflection = 8
            obj.ViewObject.DisplayMode = "Shaded"
    doc.recompute()
    return doc


def usga(body):
    """USGA clubhead dimensions (Appendix II 4b): heel-toe at 0.875" up where the heel is not
    clearly defined, face-back, crown-sole height, volume."""
    bb = body.optimalBoundingBox()
    cut = body.common(Part.makeBox(400, 400, 0.02, V(-200, -200, 22.225 - 0.01)))
    heel_x = cut.optimalBoundingBox().XMax if cut.Solids else float("nan")
    return {"heel_toe": heel_x - bb.XMin, "face_back": bb.YMax - bb.YMin, "volume_cc": body.Volume / 1000.0}


def report(parts, info):
    body = Part.makeCompound([parts["Body"], parts["Face"]]) if "Face" in parts else parts["Body"]
    bb = body.optimalBoundingBox()
    print("VALID", {n: s.isValid() for n, s in parts.items()}, "| face edge rounded", info.get("face_edge_r"))
    print("BBOX mm  x %.1f..%.1f  y %.1f..%.1f  z %.2f..%.1f" % (bb.XMin, bb.XMax, bb.YMin, bb.YMax, bb.ZMin, bb.ZMax))
    u = usga(body)
    print("USGA heel-toe %.1f mm (%.2f in, max 5.00), face-back %.1f mm, volume %.1f cc (max 460)" % (
        u["heel_toe"], u["heel_toe"] / 25.4, u["face_back"], u["volume_cc"]))


if os.environ.get("GOLFHEAD_NO_MAIN") != "1":
    _parts, _info = build()
    report(_parts, _info)
    if App.GuiUp:
        show(_parts, _info)
