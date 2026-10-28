"""Face-to-hosel blend for the Driver460 head: a drop-in for refine_driver_heel.flush_front().

From Claude's build_driver.py (v41, Documents/FreeCAD/GolfHead/driver), the version whose face
runs flat and flush right up to the hosel, with no warp, sliver or wrinkle.

Usage, in refine_driver_heel.build_refined():

    from face_hosel_blend import blend_face_to_hosel   # (or exec this file)
    head, edge_radius, fold_radius = blend_face_to_hosel(head, ns)    # instead of flush_front(head)

`ns` is the namespace base_driver.py was exec'd into. The input is the uncut head: body and
hosel lofted from the distance field (ns['loft_rings'](ns['head_rings'](field), ...)), with no
face cut yet.

Why not bend the face cut onto the hosel's front (a smooth minimum of the face surface and the
tube's front)?
- Near the hosel the two surfaces are almost tangent, so any cut that follows the tube's front
  grazes it. That leaves a warped band and a ragged sliver along the hosel.
- Doing the face cut or its rounding inside the distance field does the same thing, and wrinkles
  the hosel.

What works is three exact B-rep steps:

1. Cut the face with the true face surface: the 12" bulge-and-roll sphere, laid back by the loft.
   The face is then exactly flat and flush everywhere.
2. Stop the cut at a plane laid tangent to the hosel, FOLD_THETA round from its front toward the
   toe and FOLD_CLEAR clear of it. The cut never touches the hosel. Where the flat face meets the
   plane there is a crisp, deliberate fold, and the plane runs tangentially into the hosel because
   it touches the tube.
3. Fill the fold's valley with a concave fillet (FOLD_FILLET). That puts material back into the
   corner by the hosel and rounds the face's top-heel corner into the hosel. Then fillet the
   face's own edge where it meets the body (FACE_FILLET; on this head 1.0 mm is the largest OCC
   manages there).
"""
import math

import Part
from FreeCAD import Vector as V

FOLD_THETA = 40.0                    # deg round the hosel from its front toward the toe
FOLD_CLEAR = 0.2                     # mm the fold plane stands clear of the hosel
FOLD_FILLET = (9.0, 7.0, 5.0, 3.5)   # concave round in the fold's valley: first that works
FACE_FILLET = (2.5, 2.0, 1.5, 1.0)   # the face's edge onto the body: first that works
RIDGE_FILLET = (8.0, 6.0, 5.0, 4.0, 3.0, 2.0)  # the fold plane's edge onto the heel body (left
                                     # sharp, it shows as a ridge between face and hosel)


def face_sphere(ns):
    """The face surface: a sphere of BULGE_R through the face centre, laid back by the loft."""
    out = V(0, -math.cos(math.radians(ns['LOFT'])), math.sin(math.radians(ns['LOFT'])))
    return Part.makeSphere(ns['BULGE_R'], V(0, 0, ns['FACE_CZ']) - out * ns['BULGE_R'])


def fold_plane(ns):
    """(point, outward normal) of the plane tangent to the hosel FOLD_THETA round from its
    front toward the toe."""
    th = math.radians(FOLD_THETA)
    d = V(0, -math.cos(th), 0) + ns['ACROSS'] * math.sin(th)
    d.normalize()
    return ns['on_axis'](45.0) + d * (ns['HOSEL_R'] + FOLD_CLEAR), d


def _first_fillet(body, radii, edges):
    for r in radii:
        try:
            out = body.makeFillet(r, edges)
            if out.isValid() and len(out.Solids) == 1:
                return out, r
        except Exception:  # OCC raises when it cannot
            continue
    return body, None


def blend_face_to_hosel(head, ns):
    """Cut the face flat up to the hosel, fold onto it, round the fold and the face's edge.
    Returns (body, face_edge_radius, fold_radius); a radius is None when no fillet worked."""
    front = Part.makeBox(400.0, 260.0, 300.0, V(-200.0, -200.0, -100.0)).cut(face_sphere(ns))
    p0, d = fold_plane(ns)
    u = d.cross(ns['AXIS']).normalize()
    w = d.cross(u).normalize()
    c = p0 - u * 300.0 - w * 300.0
    plate = Part.Face(Part.makePolygon([c, c + u * 600.0, c + u * 600.0 + w * 600.0, c + w * 600.0, c]))
    body = head.cut(front.common(plate.extrude(d * 300.0)))

    # the fold's valley: edges shared by the face (sphere) and the fold plane
    faces = [f for f in body.Faces if isinstance(f.Surface, Part.Sphere)]
    folds = [f for f in body.Faces if isinstance(f.Surface, Part.Plane) and abs(f.Surface.Axis.dot(d)) > 0.999]
    on_face = {e.hashCode() for f in faces for e in f.Edges}
    valley = [e for f in folds for e in f.Edges if e.hashCode() in on_face]
    body, fold_r = _first_fillet(body, FOLD_FILLET, valley)

    # the fold plane's far edge, where it cuts into the heel body: round it off, so the band from
    # the face into the hosel has no ridge (along the hosel itself the plane is tangent already)
    folds = [f for f in body.Faces if isinstance(f.Surface, Part.Plane) and abs(f.Surface.Axis.dot(d)) > 0.999]
    big = [f for f in body.Faces if isinstance(f.Surface, Part.BSplineSurface) and f.Area > 2000.0]
    on_big = {e.hashCode() for f in big for e in f.Edges}
    ridge = [e for f in folds for e in f.Edges if e.hashCode() in on_big and e.Length > 1.0]
    body, ridge_r = _first_fillet(body, RIDGE_FILLET, ridge)
    blend_face_to_hosel.ridge_radius = ridge_r

    # the face's own edge: where the face (sphere) meets the lofted body
    faces = [f for f in body.Faces if isinstance(f.Surface, Part.Sphere)]
    loft = [f for f in body.Faces if isinstance(f.Surface, Part.BSplineSurface) and f.Area > 5000.0]
    on_loft = {e.hashCode() for f in loft for e in f.Edges}
    edges = [e for f in faces for e in f.Edges if e.hashCode() in on_loft]
    body, edge_r = _first_fillet(body, FACE_FILLET, edges)
    return body, edge_r, fold_r


NECK_FILLET = (12.0, 10.0, 8.0, 6.0, 5.0, 4.0)  # the hosel's blend into body and face: first
                                     # that OCC manages (the Sport Hybrid 21 uses 12 mm)
FACE_ROUND = (2.5, 2.0, 1.5, 1.0)    # the face's edge, rounded before the hosel goes on


def hybrid_neck(ns, start_s=22.0):
    """The Sport Hybrid 21's face-to-hosel joint, on the driver.

    1. Take the body without its hosel (ns['body_loft']()), cut the whole face flat with the exact
       face sphere, and round the face's edge all the way round (FACE_ROUND).
    2. Fuse a true round hosel on the shaft axis: one cone from start_s mm up the axis (inside
       the heel) to past the top, HOSEL_R tapering to HOSEL_R_TOP.
    3. Fillet every edge where the hosel meets the body (crown, heel and the rounded face edge)
       with one large tangent blend (NECK_FILLET).
    There is no fold plane, so there is no ridge between face and hosel.
    Returns (body, face_round, neck_round); a radius is None when no fillet worked."""
    body = ns['body_loft']()
    front = Part.makeBox(400.0, 260.0, 300.0, V(-200.0, -200.0, -100.0)).cut(face_sphere(ns))
    body = body.cut(front)
    face = max((f for f in body.Faces if isinstance(f.Surface, Part.Sphere)), key=lambda f: f.Area)
    body, face_r = _first_fillet(body, FACE_ROUND, face.Edges)

    axis = ns['AXIS']
    ground = V(ns['HOSEL_GROUND_X'], ns['axis_y'](), 0)
    s_top = ns['HOSEL_TOP_Z'] / axis.z
    s_end = s_top + 12.0
    r0, r1 = ns['HOSEL_R'], ns['HOSEL_R_TOP']

    def radius(s):
        return r0 + (r1 - r0) * (s - start_s) / (s_top - start_s)

    hosel = Part.makeCone(r0, radius(s_end), s_end - start_s, ground + axis * start_s, axis)
    body = body.fuse(hosel).removeSplitter()

    def on_hosel(e):
        if e.Length < 0.5 or isinstance(e.Curve, (Part.Line, Part.LineSegment)):
            return False
        for p in e.discretize(9):
            w = p - ground
            s = w.dot(axis)
            if s > s_top - 0.5 or abs((w - axis * s).Length - radius(s)) > 0.03:
                return False
        return True

    neck = [e for e in body.Edges if on_hosel(e)]
    hybrid_neck.neck_edges = len(neck)
    body, neck_r = _first_fillet(body, NECK_FILLET, neck)
    return body, face_r, neck_r


HYBRID_FACE_R = 2.5   # the face's edge round (Sport Hybrid 21: 2.5 mm)
HYBRID_NECK_R = 12.0  # the hosel's tangent blend into body and face edge (Sport Hybrid 21: 12 mm)
HYBRID_NECK_R_FACE = 4.0  # ... easing to this at the face (y below NECK_FACE_Y[0]): a round
HOSEL_TAIL = (12.0, 38.0)  # the hosel tube fades in over this run up its axis (z ~10 .. 33)
NECK_FACE_Y = (4.0, 16.0)  # union this big bulges past nearly parallel surfaces closer than ~0.6 r,
                           # and the hosel sits only a few mm behind the face plane


def hybrid_field(ns, face_r=None):
    """The Sport Hybrid 21's face-to-hosel joint, in the head's distance field, in the hybrid's
    order: the face is cut off the BODY with its rounded edge first, then the hosel is added with
    one big tangent blend into crown, heel and the face's rounded edge. The hosel is never cut,
    so there is no fold and no ridge (cutting the face after the hosel went on sliced the
    blend). Loft it with ns['loft_rings'](ns['head_rings'](field), V(*ns['TOE_TIP']))."""
    base = ns['HeadField']
    fr = HYBRID_FACE_R if face_r is None else face_r

    class HybridField(base):
        def body(self, q):
            """Distance to the body: the tangent-plane distances of the 8 nearest surface samples,
            weighted by closeness (the base's single nearest sample, switching to a point
            distance past 3 mm, jumped from sample to sample and streaked the rounds)."""
            np = self.np
            d, i = self.tree.query(q, k=8)
            off = q[:, None, :] - self.p[i]
            plane = np.einsum("ijk,ijk->ij", off, self.n[i])
            w = 1.0 / (d * d + 1e-6)
            return (plane * w).sum(axis=1) / w.sum(axis=1)

        def hosel(self, q):
            """The hosel tube, tapering away to nothing inside the heel (between HOSEL_TAIL s mm
            up its axis), like the drop's tail: run down to the sole it stood proud of the heel
            on its heel-front side, a spine from the hosel to the sole."""
            np = self.np
            s = np.clip((q - self.g) @ self.a, -80.0, self.s_top + 60.0)
            foot = self.g + np.outer(s, self.a)
            t = np.clip((s - 30.0) / (self.s_top - 30.0), 0.0, 1.0)
            r = ns['HOSEL_R'] + (ns['HOSEL_R_TOP'] - ns['HOSEL_R']) * t
            u = np.clip((s - HOSEL_TAIL[0]) / (HOSEL_TAIL[1] - HOSEL_TAIL[0]), 0.0, 1.0)
            tube = np.linalg.norm(q - foot, axis=1) - r * u * u * (3 - 2 * u)
            # ... and trimmed at the sole line (its tail's point poked out under the heel)
            x = q[:, 0]
            sole = np.where(x < ns['SOLE_LOW_X'], ns['CAMBER_TOE'], ns['CAMBER_HEEL']) * (x - ns['SOLE_LOW_X']) ** 2
            return self.round_and(tube, sole + 1.0 - q[:, 2], 4.0)

        def face_sphere_dist(self, q):
            np = self.np
            x, z = q[:, 0], q[:, 2]
            out = np.array([0.0, -math.cos(math.radians(ns['LOFT'])), math.sin(math.radians(ns['LOFT']))])
            c = np.array([0.0, 0.0, ns['FACE_CZ']]) - out * ns['BULGE_R']
            # the sphere's centre is behind the face: negative inside the ball = behind the face
            return np.linalg.norm(q - c[None, :], axis=1) - ns['BULGE_R']

        def head(self, q):
            np = self.np
            faced = self.round_and(self.body(q), self.face_sphere_dist(q), fr)
            w = np.clip((q[:, 1] - NECK_FACE_Y[0]) / (NECK_FACE_Y[1] - NECK_FACE_Y[0]), 0.0, 1.0)
            r = HYBRID_NECK_R_FACE + (HYBRID_NECK_R - HYBRID_NECK_R_FACE) * w * w * (3 - 2 * w)
            return self.round_or(faced, self.hosel(q), r)

    return HybridField(ns['body_loft']())


HYBRID_RECUT = 0.8    # the sampled face is planed off this far behind the face sphere (deeper
                      # than its sampled edge round), so the face is the exact sphere ...
HYBRID_EDGE_R = (2.5, 2.0, 1.5, 1.0)  # ... and its edge a true fillet, first radius that works


def hybrid_head(ns, face_r=0.6):
    """The driver head with the Sport Hybrid 21's face-to-hosel joint: the distance-field head
    (hybrid_field: face cut off the body first, hosel added with a 12 mm tangent blend), lofted,
    then the face planed exactly flat with the 12" face sphere (HYBRID_RECUT behind it) and its
    edge filleted. Returns (head, edge_radius)."""
    field = hybrid_field(ns, face_r)  # a nearly sharp face edge in the field: the real round
                                      # is the fillet below
    head = ns['loft_rings'](ns['head_rings'](field), V(*ns['TOE_TIP']))
    out = V(0, -math.cos(math.radians(ns['LOFT'])), math.sin(math.radians(ns['LOFT'])))
    ball = Part.makeSphere(ns['BULGE_R'] - HYBRID_RECUT, V(0, 0, ns['FACE_CZ']) - out * ns['BULGE_R'])
    body = head.cut(Part.makeBox(400.0, 260.0, 300.0, V(-200.0, -200.0, -100.0)).cut(ball))
    face = max((f for f in body.Faces if isinstance(f.Surface, Part.Sphere)), key=lambda f: f.Area)
    body, edge_r = _first_fillet(body, HYBRID_EDGE_R, face.Edges)
    return body, edge_r


def face_finish(parts, ns, depth=1.4, inset=0.2):
    """Split the face insert (FaceSurface) off the body: a drop-in for refine_driver_heel's
    face_finish(parts). It uses the face's own outline instead of a hand-drawn one, which spilled
    onto the fold's round and left a jagged border at the top-heel corner. The outline is the
    edge of the flat face (where its rounded edge and the fold's round begin), pulled in by
    `inset`, taken straight back through the body; the insert is the body's outer `depth` mm
    there."""
    body = parts['Body']
    face = max((f for f in body.Faces if isinstance(f.Surface, Part.Sphere)), key=lambda f: f.Area)
    ring = []
    for p in face.OuterWire.discretize(Distance=1.0):
        q = V(p.x, -60.0, p.z)
        if not ring or (q - ring[-1]).Length > 0.3:
            ring.append(q)
    if (ring[0] - ring[-1]).Length < 0.3:
        ring.pop()
    if inset:  # each point in along the outline's inward normal (makeOffset2D fails on this curve)
        cx = sum(p.x for p in ring) / len(ring)
        cz = sum(p.z for p in ring) / len(ring)
        moved = []
        for i, p in enumerate(ring):
            t = ring[(i + 1) % len(ring)] - ring[i - 1]
            nrm = V(-t.z, 0, t.x).normalize()
            if nrm.x * (cx - p.x) + nrm.z * (cz - p.z) < 0:
                nrm = nrm * -1.0
            moved.append(p + nrm * inset)
        ring = moved
    curve = Part.BSplineCurve()
    curve.interpolate(ring, PeriodicFlag=True)
    prism = Part.Face(Part.Wire(curve.toShape())).extrude(V(0, 100.0, 0))
    skin = body.common(ns['face_cut_tool'](depth)).common(prism)
    frame = body.cut(skin).removeSplitter()
    if not (skin.isValid() and len(skin.Solids) == 1 and frame.isValid() and len(frame.Solids) == 1):
        raise RuntimeError('face insert split failed')
    parts = dict(parts)
    parts['Body'], parts['FaceSurface'] = frame, skin
    return parts
