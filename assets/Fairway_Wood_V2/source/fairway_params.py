"""Fairway woods: the Driver460's design (the drop-like flow into a hosel set into the heel, the face
insert) with a domed fairway-wood crown, crossed with the Sport Hybrid 21 (its face-to-hosel joint, its rounder toe
and compact body, its twin sole channels), as three heads of their own (FAIRWAY_STYLE):

  modern   a pear-shaped 3 wood: a sleek low crown, a speed slot across the sole just behind the leading
           edge, twin rails angling out toward the back (the hybrid's channels, raised)
  tour     a compact, small head (the Tour Spoon's "tiny head"): the slot, and a weight port low at the back
  classic  a rounder, deeper-faced pear (the Steelhead's "unmistakable pear shape", the Heirloom's wood):
           a fuller crown, a smooth sole

Run by build_hybrid_driver.py (HEAD_PARAMS=this file) with NS (the driver's parameters), BL (the joint's)
and its own globals. The body's dimensions start from the driver's, scaled heel-to-toe by SX,
face-to-back by SY and in height by SZ; the hosel tube stays its own size. The sole's features are added
to the head's distance field, so they blend into the sole as rounds, not cuts.
"""
import math as _m
import os as _os

STYLE = _os.environ.get("FAIRWAY_STYLE", "modern")
SX, SY, SZ = {"modern": (0.82, 0.76, 0.62), "tour": (0.74, 0.70, 0.60), "classic": (0.80, 0.78, 0.66)}[STYLE]
HOSEL_IN = 6.0                  # the hosel set into the heel (as the driver's, scaled)
NS["N_RAYS"], NS["X_STEP"] = (480, 1.3) if _os.environ.get("FAIRWAY_FAST") else (640, 1.1)  # finer than the driver
NS["HOSEL_SETBACK"] = 0.0       # (set with the neck, below: the hosel's front flush with the face)
NS["LOFT"] = {"modern": 15.0, "tour": 13.0, "classic": 15.0}[STYLE]
NS["BULGE_R"] = 254.0           # 10" bulge and roll
NS["FACE_CZ"] = 31.0 * SZ
NS["FACE_PROUD"] = 12.0 * SY
NS["CROWN_TOP"] = 72.0 * SZ    # the dome's high point, ~11 mm over the face's top edge
NS["CROWN_PEAK_X"] = -6.0 * SX
# face-on, the driver's eye turned over: the driver is a flat crown over a round, deep sole; a fairway
# wood sits flat on the turf - a long, nearly straight sole and leading edge under a gently domed crown
NS["CROWN_FALL_TOE"] = 0.0068 * SZ / SX ** 2   # a domed crown line face-on (the driver's is flat)
NS["CROWN_FALL_HEEL"] = 0.0074 * SZ / SX ** 2
NS["CAMBER_TOE"] = 0.0013 * SZ / SX ** 2
NS["CAMBER_HEEL"] = 0.0016 * SZ / SX ** 2
NS["N_FRONT_BOT"] = 8.0         # the sole runs flat right up to the face: the face's bottom edge is the
                                 # leading edge, at the ground (rounder, the sole rolled up under the face)
NS["N_BACK_BOT"] = 3.8          # a flat sole with a defined skirt
NS["SOLE_LOW_X"] = -8.0 * SX
NS["APEX_BACK"] = 55.0 * SY     # the crown's high point well back from the face (the driver's is close to
                                 # it, so its crown runs back in a long wedge): a dome
NS["N_FRONT_TOP"] = 2.0          # the crown rolls over round into the face (the driver's is squared off)
NS["FRONT_Z"] = 22.0 * SZ
NS["REAR_Z"] = 26.0 * SZ
NS["TOE_TIP"] = (-74.0 * SX, 40.0 * SY, 34.0 * SZ)
NS["CAP_X"] = -12.0 * SX         # the toe closes round from here (the driver's from -28): with a full back,
                                 # one big round arc from the back round the toe
NS["CAP_FRONT_X"] = -44.0 * SX
NS["DETAIL_TOE"] = (-68.0 * SX, -40.0 * SX)
NS["DETAIL_HEEL"] = (16.0 * SX, 40.0 * SX)
NS["HEEL_CAP_X"] = 10.0 * SX    # ... and the heel round into the hosel from here (the driver's from 20)
NS["JOIN_R"] = 9.0 * 0.8
NS["HEEL_R"] = 24.0 * 0.75
NS["PORT_AT"] = (12.0 * SX, 28.0 * SY)
NS["SCORE_ROWS"] = [(z * SZ,) + tuple((a * SX, b * SX) for a, b in runs) for z, *runs in NS["SCORE_ROWS"]]
NS["HOSEL_GROUND_X"] = (29.0 - HOSEL_IN) * SX
NS["HOSEL_FRONT_AT"] = ((40.0 - HOSEL_IN) * SX, 40.0 * SZ)
NS["HOSEL_TOP_Z"] = 66.0
NS["K_CROWN"], NS["K_HEEL"], NS["K_PLAN"] = 16.0, 22.0, 16.0
NS["FRONT_BLEND"] = ((40.0 - HOSEL_IN) * SX, (54.0 - HOSEL_IN) * SX)
NS["HOSEL_BLEND"] = ((30.0 - HOSEL_IN) * SX, (58.0 - HOSEL_IN) * SX)
NS["X_END"] = 80.0 * SX
NS["HEEL_TIP"] = tuple(NS["on_axis"](46.0 * SZ))  # the heel closes high up the hosel: it wraps it
BL["HOSEL_TAIL"] = (0.0, 6.0)  # the hosel runs all the way down, into the face's heel end and the heel
BL["NECK_FACE_Y"] = (4.0 * SY, 16.0 * SY)
BL["HYBRID_NECK_R"] = 9.0       # the round where the face, crown and heel run into the (flared) hosel
# the hosel flares: it thickens by FLARE over its lower part (s up the shaft from FLARE_S[1] down to
# FLARE_S[0]) into the crown and heel, one smooth taper (a straight tube met the head at a waist: a bottle
# neck); slim at the top
FLARE, FLARE_S = 2.0, (22.0, 56.0)  # (to the back and sides only: flared forward too, its foot bulged
                                    # out ahead of the face at the top-heel corner, a knuckle)
BL["HYBRID_NECK_R_FACE"] = 7.0   # a full round from the face's heel end into the hosel (planed flush with
                                 # the face below, so it cannot bulge ahead of it: see RECUT)
FACE_R = 1.8

# from above: a pear, not the driver's shape scaled - full and round round the toe and the back (the
# hybrid's), drawing in to the heel; the classic rounder still, the tour smaller and tighter
# the back is one round arc from the toe to the heel (a superellipse), not a flat back between two
# tight corners; it sweeps on round the heel into the hosel
def _back(x, xc=-12.0, a_toe=78.0, a_heel=80.0, y0=4.0, b=110.0, n=2.0):
    t = (x - xc) / (a_toe if x < xc else a_heel)
    return y0 + b * max(1.0 - abs(t) ** n, 0.0) ** (1.0 / n)


_PEAR = [(x, _back(x)) for x in (-80.0, -72.0, -62.0, -50.0, -36.0, -22.0, -8.0, 6.0, 20.0, 32.0, 42.0, 50.0,
                                 56.0, 60.0)]
NS["REAR_PTS"] = [(x * SX, y * SY) for x, y in _PEAR]
# the crown from its apex round to the back: a full curve (CROWN_TENSION over 0.55 is fuller than an
# ellipse) down to a back standing REAR_Z high - a dome, where the driver's runs down in a straight wedge
# (0.36) to a low tail
if STYLE == "modern":
    NS["CROWN_TENSION"] = 0.52
    NS["REAR_Z"] = 13.0 * SZ
elif STYLE == "tour":
    NS["CROWN_TENSION"] = 0.52
    NS["REAR_Z"] = 13.0 * SZ
    NS["PORT_AT"] = (-6.0 * SX, 92.0 * SY)  # the tour weight port, low at the back
else:
    NS["CROWN_TENSION"] = 0.55   # rounder still
    NS["REAR_Z"] = 16.0 * SZ
    NS["N_BACK_BOT"] = 3.0       # a softer skirt into a smooth sole

# from above: aim the outline at one round arc - a circle round the back from the toe tip to the heel's
# widest point (then the heel runs forward into the hosel) - and work out the back curve the toe and heel
# caps need to land on it (they close the outline in elliptically toward the toe and heel tips on top of
# the back curve, so the back curve alone left a bell: a narrow back between flat-topped shoulders)
def _round_plan(n=2.0, depth=114.0 * SY):
    toe_x, heel_x = NS["TOE_TIP"][0], NS["HEEL_TIP"][0]
    hy = NS["HEEL_TIP"][1]
    xc, r = (toe_x + heel_x) / 2.0, (heel_x - toe_x) / 2.0
    yc = depth - r
    NS["TOE_TIP"] = (toe_x, yc, NS["TOE_TIP"][2])  # the toe tip at the circle's centre line
    pts = []
    for k in range(121):
        x = toe_x + 0.4 + (heel_x - 0.3 - toe_x - 0.4) * k / 120.0
        t = min(abs(x - xc) / r, 1.0)
        target = yc + r * (1.0 - t ** n) ** (1.0 / n)
        rear = target
        if x < NS["CAP_X"]:
            rear = yc + (target - yc) / max(NS["cap_k"](x), 0.05)
        elif x > NS["HEEL_CAP_X"]:
            rear = hy + (target - hy) / max(NS["heel_k"](x), 0.05)
        # no fuller than the back itself, smoothly (pushed out to the circle right up to the hosel, the
        # heel crowded the hosel and its blend broke up)
        rear = rear - 3.0 * _m.log(1.0 + _m.exp((rear - depth - 2.0) / 3.0))
        pts.append((x, rear))
    return pts


# (_round_plan shaped the driver's sections; the saucer below replaces them)

# what build_driver.py works out once, as it loads, from the values above
NS["TL"] = _m.tan(_m.radians(NS["LOFT"]))
NS["rear_y"] = NS["pchip"](NS["REAR_PTS"])

# ---- the saucer -------------------------------------------------------------------------------------------
# The body is not the driver's sections (their uneven toe and heel falls and a heel climbing the hosel read as
# a random, lopsided crown): it is a saucer, symmetric about its middle. From behind, a lens: the crown an
# even elliptic dome over a rim RIM of the way up, the sole flat, rounding up to the rim at the toe and heel
# ends. From above, a straight face edge and a round back. Its heel end stops at the hosel, at rim height,
# and the hosel rises out of it (its tube fades away inside the saucer: no lower hosel in the heel).
SAUCER = {"modern": dict(H=39.0, D=88.0), "tour": dict(H=36.5, D=80.0), "classic": dict(H=42.0, D=91.0)}[STYLE]
RIM = 0.45          # the rim (the widest line, from behind) this far up the crown's height
RIM_CROWN, RIM_SOLE = 60.0, 70.0  # a clam: the crown dome arrives at the rim this steeply (deg below level)
                                  # and the sole dome leaves it this steeply - two domes meeting at the rim
HEEL_END = 18.0     # the saucer's heel end this far heel-ward of the hosel's axis, at rim height: past the
                    # hosel's heel side, so the saucer wraps the hosel's foot
TOE_BACK = 0.30     # the toe's round end this far back (of the depth D)
_H, _D = SAUCER["H"], SAUCER["D"]
# the neck (see the one loft, below): the clam's own sections run heel-ward to NECK_X, then turn into the
# round hosel, reached at HOSEL_ROUND_Z (about crown height) with radius HOSEL_R0, which slims to HOSEL_R_TOP
# at the top. The hosel's front meets the face at the face's top-heel corner, flush (lower down the face
# lies ahead of it - the face is lofted, the hosel upright - and the neck's front fills the gap, planed by
# the face's cut: the face runs on into the hosel's front)
NECK_X = 17.0 * SX
HOSEL_ROUND_Z = _H - 1.0
HOSEL_R0 = NS["HOSEL_R"] + 1.0
NS["HOSEL_FRONT_AT"] = (NS["HOSEL_GROUND_X"] + HOSEL_ROUND_Z / _m.tan(_m.radians(NS["LIE"])), HOSEL_ROUND_Z)
NS["HOSEL_SETBACK"] = HOSEL_R0 - NS["HOSEL_R"]
_ZR = RIM * _H
_XT = NS["TOE_TIP"][0]
_HP = NS["on_axis"](_ZR)
_XH = _HP.x + HEEL_END
_XC, _A = (_XT + _XH) / 2.0, (_XH - _XT) / 2.0
_Y_TOE, _Y_HEEL = TOE_BACK * _D, _HP.y
NS["TOE_TIP"] = (_XT, _Y_TOE, _ZR)
NS["HEEL_TIP"] = (_XH, _Y_HEEL, _ZR)
NS["CAP_X"] = NS["CAP_FRONT_X"] = _XC - 0.5 * _A   # (station spacing only)
NS["HEEL_CAP_X"] = _XC + 0.5 * _A
NS["CROWN_TENSION"] = 0.5523   # the crown from its apex to the rim: a quarter ellipse
NS["CROWN_PEAK_X"] = _XC
BL["HOSEL_TAIL"] = (-200.0, -199.0)  # (no taper: a full tube, capped inside the head at HOSEL_CAP_Z)
HOSEL_CAP_Z = _ZR - 2.0  # (the tube starts inside the
                    # saucer and leaves its crown at full size: started lower, its thin tail hung down the heel)


def _sup(u, m):
    return max(1.0 - u ** m, 0.0) ** (1.0 / m)


def _saucer_section(x):
    """The section at x, in build_driver.section_params()'s terms."""
    sm = NS["smooth"]
    u = min(abs(x - _XC) / _A, 1.0)
    e = _sup(u, 2.0)
    f0 = x * x / (2.0 * NS["BULGE_R"])
    proud = NS["FACE_PROUD"] * sm((e - 0.1) / 0.5)
    yt = _Y_TOE + (_Y_HEEL - _Y_TOE) * sm((x - _XT) / (_XH - _XT))  # where the outline closes, toe to heel
    f = yt + (f0 - proud - yt) * _sup(u, 5.0)   # the face edge: straight, rounding only at the ends
    r = yt + (f0 + _D - yt) * _sup(u, 2.1)      # the back: round
    t = _ZR + (_H - _ZR) * (1.0 - u ** 2.2) ** 0.8  # from behind: the crown dome ...
    b = _ZR - _ZR * (1.0 - u ** 2.6) ** 0.8          # ... and the sole dome, meeting at the rim in a point at the
                                                # toe and heel (a clam, not a loaf)
    k = sm(e / 0.55)                            # 1 mid-head, 0 at the ends (plain ellipses there)
    d, h = r - f, t - b
    yc = f + (0.42 + 0.08 * (1.0 - k)) * d      # the apex ~40% back
    zf = b + (0.36 + 0.14 * (1.0 - k)) * h
    zb = b + (RIM + (0.5 - RIM) * (1.0 - k)) * h
    n = [2.0 + (q - 2.0) * k for q in (2.0, 2.0, 2.6, 4.6)]  # front-top, (crown), skirt, leading edge
    yc = min(max(yc, f + 0.15 * d), r - 0.15 * d)
    zf = min(max(zf, b + 0.15 * h), t - 0.15 * h)
    zb = min(max(zb, b + 0.15 * h), t - 0.15 * h)
    return f, r, b, t, yc, zf, zb, n, k


NS["section_params"] = _saucer_section


def _clam_ring(x, n_quarter=None):
    """build_driver.ring_at() for the clam: the same points in the same order (from the front-most point
    up the face, over the crown, round the back, along the sole), but the crown and sole are two domes
    meeting at the rim at an angle (cubics), not one round superellipse."""
    from FreeCAD import Vector as V
    f, r, b, t, yc, zf, zb, n, k = _saucer_section(x)
    nq = n_quarter or NS["N_QUARTER"]
    ac, as_ = _m.radians(RIM_CROWN), _m.radians(RIM_SOLE)
    lc = min(0.5 * (t - zb) / _m.sin(ac), 0.6 * (r - yc))
    ls = min(0.5 * (zb - b) / _m.sin(as_), 0.6 * (r - yc))
    crown = ((yc, t), (yc + 0.5 * (r - yc), t), (r - lc * _m.cos(ac), zb + lc * _m.sin(ac)), (r, zb))
    sole = ((r, zb), (r - ls * _m.cos(as_), zb - ls * _m.sin(as_)), (yc + 0.5 * (r - yc), b), (yc, b))

    def cubic(c, u):
        w = ((1 - u) ** 3, 3 * u * (1 - u) ** 2, 3 * u * u * (1 - u), u ** 3)
        return sum(wi * p[0] for wi, p in zip(w, c)), sum(wi * p[1] for wi, p in zip(w, c))

    pts = []
    for q in range(4):
        for j in range(nq):
            if q in (1, 2):
                y, z = cubic(crown if q == 1 else sole, j / nq)
                pts.append(V(x, y, z))
                continue
            th = (q + j / nq) * _m.pi / 2
            ct, st = -_m.cos(th), _m.sin(th)
            zc = zf
            ay = yc - f
            az = (t - zc) if st > 0 else (zc - b)
            e = n[q]
            pts.append(V(x, yc + ay * _m.copysign(abs(ct) ** (2 / e), ct), zc + az * _m.copysign(abs(st) ** (2 / e), st)))
    return pts


NS["ring_at"] = _clam_ring

# ---- one loft: the clam, its neck, the hosel --------------------------------------------------------------
# Built like the irons' (irons/build_irons.py head_sections, the 2U's joint): the hosel is not a tube added
# to the body (every such union - its round, its tracing round a thin heel - spiked, wrinkled or bulged), the
# body's own sections turn into it. Past NECK_X the sections morph along two guides: the crown's top line
# sweeping up into the hosel's toe side, and the sole running on, round HEEL_R and straight up the hosel's
# heel side (face-on, the heel's outline IS the hosel's line curving into the sole). Each point keeps its
# place round the section (its angle) on the round hosel; its depth eases from the clam's onto the hosel's.
NECK_PULL = 0.55        # how tightly the top line's guide hugs its corner into the hosel (smaller = rounder)
HEEL_R = {"modern": 22.0, "tour": 20.0, "classic": 24.0}[STYLE]
N_NECK = 13             # neck steps
NQ = 24                 # points per quarter section
BODY_STEP, HOSEL_STEP = 2.0, 3.0   # section spacing along the body, and up the hosel (mm)
HOSEL_LOFT_TOP = 100.0  # the loft runs on up the shaft past the hosel top (trimmed square to it)
_LOFT = []


def _hosel_r(z):
    t = min(max((z - HOSEL_ROUND_Z) / (NS["HOSEL_TOP_Z"] - HOSEL_ROUND_Z), 0.0), 1.0)
    return HOSEL_R0 + (NS["HOSEL_R_TOP"] - HOSEL_R0) * NS["smooth"](t)


def _meet(p, dp, q, dq):
    """Where the lines p + a*dp and q + b*dq cross, in the XZ plane."""
    from FreeCAD import Vector as V
    det = dp.x * (-dq.z) - dp.z * (-dq.x)
    rx, rz = q.x - p.x, q.z - p.z
    a = (rx * (-dq.z) - rz * (-dq.x)) / det
    return V(p.x + a * dp.x, 0, p.z + a * dp.z)


def _by_length(at, n=400):
    """at(t) reparametrised by arc length (so the neck's sections step evenly along it)."""
    pts = [at(k / n) for k in range(n + 1)]
    acc = [0.0]
    for a, b in zip(pts, pts[1:]):
        acc.append(acc[-1] + (b - a).Length)

    def even(t):
        s = t * acc[-1]
        k = max(min(next((i for i, v in enumerate(acc) if v >= s), n), n), 1)
        w = (s - acc[k - 1]) / max(acc[k] - acc[k - 1], 1e-12)
        return pts[k - 1] + (pts[k] - pts[k - 1]) * w
    return even


def _body_stations():
    n_cap = 12
    cap_x = _XC - 0.5 * _A
    xs = [cap_x + (_XT - cap_x) * _m.sin(_m.radians(86.0) * j / n_cap) for j in range(n_cap, 0, -1)]
    n = max(1, round((NECK_X - cap_x) / BODY_STEP))
    return xs + [cap_x + (NECK_X - cap_x) * j / n for j in range(n + 1)]


def _head_sections():
    from FreeCAD import Vector as V
    AXIS, ACROSS = NS["AXIS"], NS["ACROSS"]
    rings = [_clam_ring(x, NQ) for x in _body_stations()]
    s0, prev = rings[-1], rings[-2]
    s0b = _clam_ring(NECK_X - 6.0, NQ)  # (for the guides' start directions)
    npt = len(s0)

    def ends(ring):
        lo = min(ring, key=lambda p: p.z)
        hi = max(ring, key=lambda p: p.z)
        return V(lo.x, 0, lo.z), V(hi.x, 0, hi.z)

    b0, p0 = ends(s0)
    b0b, p0b = ends(s0b)
    axis_y = NS["axis_y"]()
    c1 = NS["on_axis"](HOSEL_ROUND_Z)
    c1 = V(c1.x, 0, c1.z)
    b1, p1 = c1 - ACROSS * HOSEL_R0, c1 + ACROSS * HOSEL_R0  # the hosel's heel-down and toe-up sides

    # the top line: a Bezier from the crown's top into the hosel's toe side, hugging its corner by NECK_PULL
    d0 = (p0 - p0b).normalize()
    corner = _meet(p0, d0, p1, -AXIS)
    tg = (p0, p0 + d0 * (NECK_PULL * (corner - p0).Length), p1 - AXIS * (NECK_PULL * (corner - p1).Length), p1)

    def top_at(t):
        w = ((1 - t) ** 3, 3 * t * (1 - t) ** 2, 3 * t * t * (1 - t), t ** 3)
        return sum((p * wi for p, wi in zip(tg, w)), V())
    top_at = _by_length(top_at)

    # the heel: on along the sole, round HEEL_R, then straight up the hosel's heel-side line
    sd = (b0 - b0b).normalize()
    corner = _meet(b0, sd, b1, -AXIS)
    turn = _m.acos(max(-1.0, min(1.0, sd.dot(AXIS))))
    reach = HEEL_R * _m.tan(turn / 2)
    t1, t2 = corner - sd * reach, corner + AXIS * reach
    nrm = V(sd.z, 0, -sd.x)
    if nrm.dot(AXIS) < 0:
        nrm = -nrm
    centre = t1 + nrm * HEEL_R
    a1 = _m.atan2((t1 - centre).z, (t1 - centre).x)
    a2 = _m.atan2((t2 - centre).z, (t2 - centre).x)
    if a2 - a1 > _m.pi:
        a2 -= 2 * _m.pi
    elif a1 - a2 > _m.pi:
        a2 += 2 * _m.pi
    legs = [(t1 - b0).Length, abs(a2 - a1) * HEEL_R, (b1 - t2).Length]
    if min(legs[0], legs[2]) <= 0 or (t1 - b0).dot(sd) <= 0:
        raise RuntimeError("heel round does not fit: %s (NECK_X %.1f)" % (legs, NECK_X))

    def heel_at(t):
        d = t * sum(legs)
        if d <= legs[0]:
            return b0 + sd * d
        d -= legs[0]
        if d <= legs[1]:
            a = a1 + (a2 - a1) * d / legs[1]
            return centre + V(_m.cos(a), 0, _m.sin(a)) * HEEL_R
        return t2 + AXIS * (d - legs[1])

    # each point's place on the round hosel: as far round it (from its front, up over its toe side) as it is
    # round the heel-most clam section, by length - so the hosel's rings are spaced like the body's and one
    # parameter list fits every ring (spaced by angle, the hosel's rings bent the shared parameters off the
    # thin toe sections', which then looped through the head's inside)
    h0 = p0.z - b0.z
    f0 = [(p.z - b0.z) / h0 for p in s0]
    acc = [0.0]
    for a, c in zip(s0, s0[1:] + s0[:1]):
        acc.append(acc[-1] + (c - a).Length)
    phi = [_m.pi - 2.0 * _m.pi * v / acc[-1] for v in acc[:-1]]
    yr = [axis_y + HOSEL_R0 * _m.cos(a) for a in phi]
    fr = [(1 + _m.sin(a)) / 2 for a in phi]
    # the depth eases from the clam's onto the hosel's, leaving at the body's own rate
    for k in range(1, N_NECK):
        t = k / N_NECK
        b, p = heel_at(t), top_at(t)
        s = NS["smooth"](t)
        h00, h10, h01 = 2 * t ** 3 - 3 * t * t + 1, t ** 3 - 2 * t * t + t, 3 * t * t - 2 * t ** 3
        rings.append([b + (p - b) * (f0[i] + (fr[i] - f0[i]) * s)
                      + V(0, h00 * s0[i].y + h10 * (s0[i].y - prev[i].y) * N_NECK + h01 * yr[i], 0)
                      for i in range(npt)])
    # up the hosel in even steps
    n = max(1, round((HOSEL_LOFT_TOP - HOSEL_ROUND_Z) / (HOSEL_STEP * AXIS.z)))
    for j in range(n + 1):
        z = HOSEL_ROUND_Z + (HOSEL_LOFT_TOP - HOSEL_ROUND_Z) * j / n
        r, c = _hosel_r(z), NS["on_axis"](z)
        rings.append([c + V(0, r * _m.cos(a), 0) + ACROSS * (r * _m.sin(a)) for a in phi])
    return rings


def _fairway_loft():
    """The body: one loft from the toe tip through the clam, its neck and up the hosel."""
    from FreeCAD import Vector as V
    if not _LOFT:
        _LOFT.append(NS["loft_rings"](_head_sections(), V(*NS["TOE_TIP"])))
    return _LOFT[0]


NS["body_loft"] = _fairway_loft


def _slice_frame(x):
    """The loft's section at x: its area centroid and half-sizes (from the slice as a fine polygon)."""
    from FreeCAD import Vector as V
    for dx in (0.0, 0.013, -0.017, 0.031):  # (an odd slice comes back empty: nudge it)
        ws = _fairway_loft().slice(V(1, 0, 0), x + dx)
        if ws:
            break
    w = max(ws, key=lambda w: w.BoundBox.DiagonalLength)
    pts = w.discretize(Distance=0.2)
    ys, zs = [p.y for p in pts], [p.z for p in pts]
    a = cy = cz = 0.0
    for k in range(len(pts) - 1):
        c = ys[k] * zs[k + 1] - ys[k + 1] * zs[k]
        a += c
        cy += (ys[k] + ys[k + 1]) * c
        cz += (zs[k] + zs[k + 1]) * c
    return cy / (3 * a), cz / (3 * a), (max(ys) - min(ys)) / 2, (max(zs) - min(zs)) / 2


_FRAMES = {}


def _ring_frame(x):
    """Centre and half-size of the head's section at x (for aiming the tracing rays): the loft's own,
    smoothed along the stations (a jittery centre slides every ray's point round its ring: ripples)."""
    if not _FRAMES:
        xs = NS["head_xs"]()
        raw = [_slice_frame(v) for v in xs]
        for k, v in enumerate(xs):
            acc, wsum = [0.0] * 4, 0.0
            for j in range(max(0, k - 4), min(len(xs), k + 5)):
                w = _m.exp(-0.5 * ((j - k) / 1.6) ** 2)
                acc = [a + w * b for a, b in zip(acc, raw[j])]
                wsum += w
            _FRAMES[round(v, 6)] = tuple(a / wsum for a in acc)
    return _FRAMES.get(round(x, 6)) or _slice_frame(x)


NS["ring_frame"] = _ring_frame
NS["HEEL_CAP_X"] = NECK_X  # (tracing stations: evenly on from here through the neck and up the hosel)

# ---- the face's score lines ---------------------------------------------------------------------------------
# A fairway wood's face: grooves right across it (the driver's short toe and heel groups, scaled down, left
# the face bare and spilled off the insert): SCORE_N rows SCORE_PITCH apart about the insert's centre, each
# running the insert's length at its height less SCORE_INSET at either end, painted per club. Built when the
# finish stage cuts them, from the fitted insert (insert.json); the driver's rows only place the pattern.
SCORE_N, SCORE_PITCH, SCORE_INSET, SCORE_MIN = 7, 2.4, 6.0, 14.0
_driver_score_lines = NS["score_lines"]


def _row_span(outline, z):
    xs = []
    for (x0, z0), (x1, z1) in zip(outline, outline[1:] + outline[:1]):
        if (z0 - z) * (z1 - z) <= 0 and z0 != z1:
            xs.append(x0 + (x1 - x0) * (z - z0) / (z1 - z0))
    return (min(xs), max(xs)) if len(xs) >= 2 else None


def _fairway_score_lines(body):
    import json
    ins = json.load(open(_os.environ.get("DRIVER_OUT", ".") + "/insert.json"))
    outline, cz = [tuple(p) for p in ins["outline"]], ins["params"]["cz"]
    rows = []
    for k in range(SCORE_N):
        z = cz + (k - (SCORE_N - 1) / 2.0) * SCORE_PITCH
        span = _row_span(outline, z)
        if span and span[1] - span[0] - 2 * SCORE_INSET >= SCORE_MIN:
            rows.append((z, (span[0] + SCORE_INSET, span[1] - SCORE_INSET)))
    NS["SCORE_ROWS"] = rows
    print(json.dumps({"score_rows": [(round(z, 1), round(a, 1), round(b, 1)) for z, (a, b) in rows]}))
    return _driver_score_lines(body)


NS["score_lines"] = _fairway_score_lines

# ---- the sole's features, in the distance field ------------------------------------------------
SLOT = {"modern": dict(y=8.0, x=(-30.0, 15.0), r=2.6, depth=1.6),
        "tour": dict(y=7.0, x=(-26.0, 12.0), r=2.4, depth=1.6)}.get(STYLE)  # (clear of the heel's round)
RAILS = []  # (raised rails stood ~1 mm under the sole: the head sat on them, the face's bottom edge off the ground)
RAIL_R, RAIL_H, RAIL_BLEND = 3.4, 1.1, 2.4
SLOT_BLEND = 0.9
# the heel: trimmed along the hosel's own heel-side line carried on down to the sole (HEEL_CLEAR outside the
# tube, never touching it), its corner with the sole rounded HEEL_ROUND - so seen face-on the heel is the
# hosel's line sweeping round into the sole (the body's heel wall dropped straight down under the hosel: a
# notch over a knee)
HEEL_CLEAR, HEEL_ROUND = 0.8, 10.0
# the face planed once more through the hosel's blend, up to RECUT_Z (fading out above over RECUT_FADE): the
# blend's round meets the face in the face's own plane, so the flat face sweeps up into the hosel's front in
# one curve (blended only after the face was cut, the face's edge and the hosel met in a pinched crease)
RECUT_Z, RECUT_FADE = 26.0, 10.0  # (unused now)
SHIELD_Z, SHIELD_W, SHIELD_RATE = HOSEL_ROUND_Z + 0.5, 1.5, 0.8  # (see head(), below)
SHIELD_X = (NECK_X + 4.0, NECK_X + 16.0)
FACE_R_HEEL, FACE_R_HEEL_X = 5.0, (NECK_X + 8.0, NECK_X + 22.0)  # (see head(), below)
                                    # axis (fading in over SHIELD_FADE): above where it rises clear of the
                                    # face, the curved face would slice it
HEEL_TRIM_S = (12.0, 28.0)  # ... the trim hugs the hosel line only low down, then stands HEEL_ROUND clear of it
                            # (closer, its round cut a groove along the hosel's heel side: rounds bite into
                            # anything within their radius)

_base_field = BL["hybrid_field"]


def _sole_table(head, pts, np):
    """The sole's height under each (x, y): where the head's field crosses zero going up."""
    lo = np.full(len(pts), -6.0)
    hi = np.full(len(pts), 18.0)
    for _ in range(40):
        mid = (lo + hi) / 2
        inside = head(np.c_[pts[:, 0], pts[:, 1], mid]) < 0
        hi = np.where(inside, mid, hi)
        lo = np.where(inside, lo, mid)
    return (lo + hi) / 2


def fairway_field(ns, face_r):
    f = _base_field(ns, face_r)
    np = f.np
    feats = []

    def base_head(q):
        return f.round_and(f.body(q), f.face_sphere_dist(q), face_r)
    if SLOT:
        xs = np.linspace(SLOT["x"][0], SLOT["x"][1], 61)
        zs = _sole_table(base_head, np.c_[xs, np.full_like(xs, SLOT["y"])], np)
        feats.append(("slot", xs, zs))
    for (a, b) in RAILS:
        t = np.linspace(0.0, 1.0, 41)
        p = np.array(a)[None, :] + (np.array(b) - np.array(a))[None, :] * t[:, None]
        zs = _sole_table(base_head, p, np)
        feats.append(("rail", (np.array(a), np.array(b)), zs))

    tail = BL["HOSEL_TAIL"]

    def flare_w(s_):
        w = np.clip((FLARE_S[1] - s_) / (FLARE_S[1] - FLARE_S[0]), 0.0, 1.0)
        return w * w * (3 - 2 * w)

    def flare_r(s_):
        t = np.clip((s_ - 30.0) / (f.s_top - 30.0), 0.0, 1.0)
        return ns["HOSEL_R"] + (ns["HOSEL_R_TOP"] - ns["HOSEL_R"]) * t + FLARE * flare_w(s_)

    def hosel(q):  # the joint's tapered hosel (face_hosel_blend.hybrid_field), flared at the bottom
        s_ = np.clip((q - f.g) @ f.a, -80.0, f.s_top + 60.0)
        foot = f.g + np.outer(s_, f.a)
        off = q - foot
        dist = np.linalg.norm(off, axis=1)
        base = flare_r(s_)  # (flared all round: the face planes its front flush)
        u = np.clip((s_ - tail[0]) / (tail[1] - tail[0]), 0.0, 1.0)
        tube = dist - base * u * u * (3 - 2 * u)
        x = q[:, 0]
        sole = np.where(x < ns["SOLE_LOW_X"], ns["CAMBER_TOE"], ns["CAMBER_HEEL"]) * (x - ns["SOLE_LOW_X"]) ** 2
        return f.round_and(tube, HOSEL_CAP_Z - q[:, 2], 3.0)  # (capped inside the head)

    f.hosel = hosel
    a = f.a / np.linalg.norm(f.a)
    n_heel = np.array([a[2], 0.0, -a[0]])  # square to the shaft in the face plane, toward the heel and down
    if n_heel[0] < 0:
        n_heel = -n_heel

    def head(q):
        # the body with its heel trimmed back to the hosel's heel-side line (rounded HEEL_ROUND into the
        # sole); the hosel, running all the way down, blended in with HYBRID_NECK_R; then the face cut once
        # through it all, its edge rounded face_r - so the face's heel end sweeps up into the hosel's front
        # in one round, the blend never stands ahead of the face, and nothing is cut twice (two cuts left
        # a seam across the face, an unrounded one a crumpled crease). Only the hosel tube is shielded from
        # the cut, from SHIELD_S up its axis
        sph = f.face_sphere_dist(q)
        s_ = np.clip((q - f.g) @ f.a, -80.0, f.s_top + 60.0)
        d = f.body(q)  # (body, neck and hosel: one loft)
        # the cut lifted off above the face's top-heel corner, heel-ward: the hosel rises clear of the face
        # there, and the lofted face would slice its front (ramped by height and x alone: a ramp round the
        # hosel's axis crossed its surface and crumpled it)
        # (gently - SHIELD_RATE mm per mm up, just ahead of how far the hosel's front stands out of the lofted
        # face: a steep lift is no distance any more, and the face's round crumpled on it)
        up = SHIELD_W * np.logaddexp(0.0, (q[:, 2] - SHIELD_Z) / SHIELD_W)
        heel = np.clip((q[:, 0] - SHIELD_X[0]) / (SHIELD_X[1] - SHIELD_X[0]), 0.0, 1.0)
        lift = SHIELD_RATE * up * (heel * heel * (3 - 2 * heel))
        # the face's edge round grows heel-ward, where the flat face meets the neck at a shallow angle (a small
        # round there left a crease running up into the hosel): the face eases round into the hosel's front
        w = np.clip((q[:, 0] - FACE_R_HEEL_X[0]) / (FACE_R_HEEL_X[1] - FACE_R_HEEL_X[0]), 0.0, 1.0)
        r = face_r + (FACE_R_HEEL - face_r) * w * w * (3 - 2 * w)
        d = f.round_and(d, sph - lift, r)
        x, y, z = q[:, 0], q[:, 1], q[:, 2]
        for kind, geo, zs in feats:
            if kind == "slot":  # a channel across the sole, following it, its depth SLOT["depth"]
                xs = geo
                xc = np.clip(x, xs[0], xs[-1])
                zc = np.interp(xc, xs, zs) + SLOT["depth"] - SLOT["r"]
                cap = np.sqrt((x - xc) ** 2 + (y - SLOT["y"]) ** 2 + (z - zc) ** 2) - SLOT["r"]
                d = f.round_and(d, -cap, SLOT_BLEND)
            else:  # a raised runner along the sole, RAIL_H proud of it
                a, b = geo
                ab = b - a
                t = np.clip(((x - a[0]) * ab[0] + (y - a[1]) * ab[1]) / (ab @ ab), 0.0, 1.0)
                px, py = a[0] + ab[0] * t, a[1] + ab[1] * t
                pz = np.interp(t, np.linspace(0.0, 1.0, len(zs)), zs) - RAIL_H + RAIL_R
                cap = np.sqrt((x - px) ** 2 + (y - py) ** 2 + (z - pz) ** 2) - RAIL_R
                d = f.round_or(d, cap, RAIL_BLEND)
        return d

    f.head = head
    return f


BL["hybrid_field"] = fairway_field
