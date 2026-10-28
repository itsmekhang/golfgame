"""Sport Hybrid 21: continuous face, rounded heel and upright hosel.

Run in FreeCAD. build() computes geometry; apply() updates an existing draft.
CAD units are mm: +X toe, -Y face, +Z up.
"""
import math
import os

import FreeCAD as App
import Part
from FreeCAD import Vector as V

OUT = r'C:/Users/willi/Documents/Codex/2026-10-03/connec/outputs'
LOFT = 21.0
TAN = math.tan(math.radians(LOFT))
AXIS = V(-0.5, 0, math.sqrt(0.75))      # up the shaft: vertical seen from the toe, 60 deg lie
# Locate the slender hosel close to the face, with zero shaft rake.
HOSEL_FORWARD = 1.2
NECKBASE = V(-40, -3.25 - HOSEL_FORWARD, 22)
MOUTH = NECKBASE + AXIS * 43
HOSEL_R = 6.3
BORE_R = 4.7
FERRULE_AT = 31.0  # mm up the axis from the neck base: the ferrule's foot (it runs to the mouth)
NECK_FILLETS = (12.0,)   # hosel-to-body blend radius, first that OCC manages
HEEL_FILLETS = (2.0,)        # rounding on the shaved lower heel's edges


def ring(y, w, h, zc, xc=0, power=0.85, tilt=1, heel_pull=0, heel_web=0):
    """Body section: the face outline scaled to (w, h) at depth y, laid back by the loft."""
    pts = []
    outline = [(-43, 17), (-38, 9), (-25, 5), (-8, 4), (10, 5), (27, 9), (39, 16), (44, 24), (42, 31), (33, 36),
               (17, 38), (-4, 37), (-24, 32), (-38, 25)]
    fuller = {(-43, 17): (-49, 21), (-38, 9): (-43, 10), (-25, 5): (-29, 5), (-8, 4): (-10, 4), (-38, 25): (-42, 27)}
    for px, pz in outline:
        if (px, pz) in fuller:
            tx, tz = fuller[(px, pz)]
            px, pz = px + (tx - px) * heel_web, pz + (tz - pz) * heel_web
        x = xc + w * px / 44
        x += heel_pull * max(0, -px / 44) ** 2
        z = zc + h * (pz - 21) / 17
        pts.append(V(x, y + TAN * (z - 21) * tilt, z))
    curve = Part.BSplineCurve()
    curve.interpolate(pts, PeriodicFlag=True)
    return Part.Wire([curve.toShape()])


def prism_yz(points):
    vv = [V(-120, y, z) for y, z in points]
    return Part.Face(Part.makePolygon(vv + [vv[0]])).extrude(V(240, 0, 0))


def fillet_first(shape, radii, edges_of):
    """The shape filleted at the first radius OCC can do on edges_of(shape), and that radius."""
    edges = edges_of(shape)
    if not edges:
        return shape, None
    for r in radii:
        try:
            out = shape.makeFillet(r, edges)
            if out.isValid() and out.Solids:
                return out, r
        except Exception:  # OCC raises OCCError or ValueError when it cannot
            continue
    return shape, None


def on_hosel(e):
    """An edge where the hosel cylinder meets the body (not its top rim under the ferrule, not its
    seam line)."""
    if e.Length < 1e-6:
        return False
    if isinstance(e.Curve, (Part.Line, Part.LineSegment)):
        return False
    for p in e.discretize(7):
        d = p - NECKBASE
        if abs((d - AXIS * d.dot(AXIS)).Length - HOSEL_R) > 0.02:
            return False
    rim = NECKBASE + AXIS * FERRULE_AT
    return not all(abs((p - rim).dot(AXIS)) < 1e-3 for p in e.discretize(3))


def build():
    log = []
    # Main body: rings from the face (y -13) back to the rear, fuller heel web up front
    sections = [(-13, 44, 16, 21, 0), (-7, 47, 18, 22, 0), (4, 47, 19, 23, 0), (19, 43, 16.8, 22, 3),
                (33, 33, 12, 20, 5), (42, 19, 6, 19, 6), (47, 1, 0.8, 19, 6)]
    pulls = [0, 2, 5, 7, 4, 1, 0]
    webs = [1, 1, 0.5, 0, 0, 0, 0]
    front=[ring(*s,heel_pull=p,heel_web=h) for s,p,h in zip(sections[:5],pulls[:5],webs[:5])]
    # Elliptical progression produces a rounded rear dome with a horizontal
    # tangent at the back, instead of pinching the last two sections together.
    for y in [39,43,45.5,46.6,46.95]:
        w=48.83*math.sqrt(1-((y+6.24)/53.24)**2)
        q=(47-y)/14
        front.append(ring(y,w,w*12/33,19+q,6-q,heel_pull=4*q))
    front.append(Part.Vertex(V(6,47+TAN*(19-21),19)))
    body0=Part.makeLoft(front,True,False)


    # Round the face perimeter first so the later neck blend has a tangent
    # surface to run into. This removes the old ridge at the heel/front join.
    face0 = max((f for f in body0.Faces if isinstance(f.Surface, Part.Plane)), key=lambda f: f.Area)
    body0 = body0.makeFillet(2.5, face0.Edges)

    # the hosel: one true cylinder on the shaft axis from inside the heel up to the ferrule (which
    # runs from 31 mm up the axis to the mouth). It starts 1 mm up the axis from the neck base, so
    # its end disc sits wholly inside the heel, clear of the shave
    hosel = Part.makeCylinder(HOSEL_R, FERRULE_AT - 1, NECKBASE + AXIS * 1, AXIS)

    # the user-drawn lower-heel contour: shave the bulb below the hosel into a long, gradual sole
    # transition (kept from build_sport_hybrid.py), then round the cut's edges
    trim_pts = [V(x, -100, z) for x, z in [(-52, 29), (-48.5, 24), (-46.8, 20), (-42.2, 14.5), (-35.2, 9.5),
                                           (-26, 5.8), (-17, 4.4), (-8, 3.5)]]
    trim_curve = Part.BSplineCurve()
    trim_curve.interpolate(trim_pts)
    tail = [trim_pts[-1], V(-8, -100, -30), V(-120, -100, -30), V(-120, -100, 29), trim_pts[0]]
    trim_wire = Part.Wire([trim_curve.toShape()] + [Part.makeLine(a, b) for a, b in zip(tail, tail[1:])])
    heel_cut = Part.Face(trim_wire).extrude(V(0, 250, 0))
    trim_edge = trim_curve.toShape()

    def on_trim(face):
        """A face lying on the shave: the trim curve swept along Y."""
        try:
            u0, u1, v0, v1 = face.ParameterRange
            for a in (0.2, 0.5, 0.8):
                p = face.Surface.value(u0 + (u1 - u0) * a, v0 + (v1 - v0) * 0.5)
                if trim_edge.distToShape(Part.Vertex(V(p.x, -100, p.z)))[0] > 1e-3:
                    return False
            return True
        except Exception:
            return False

    def shave_edges(s):
        edges = []
        for f in s.Faces:
            if on_trim(f):
                edges += [e for e in f.Edges if e.Length > 0.5]
        return edges

    def hosel_edges(s):
        return [e for e in s.Edges if on_hosel(e)]

    def hosel_then_shave():
        b, r_neck = fillet_first(body0.fuse(hosel).removeSplitter(), NECK_FILLETS, hosel_edges)
        b = b.cut(heel_cut).removeSplitter()
        b, r_heel = fillet_first(b, HEEL_FILLETS, shave_edges)
        return b, r_neck, r_heel

    def shave_then_hosel():
        b = body0.cut(heel_cut).removeSplitter()
        b, r_heel = fillet_first(b, HEEL_FILLETS, shave_edges)
        b, r_neck = fillet_first(b.fuse(hosel).removeSplitter(), NECK_FILLETS, hosel_edges)
        return b, r_neck, r_heel

    # Where the shave meets the hosel's fillet decides which order OCC can round: try both, keep
    # the first that rounds both the hosel junction and the shave, else the best partial result
    best = None
    for order in (hosel_then_shave, shave_then_hosel):
        try:
            b, r_neck, r_heel = order()
        except Exception as ex:  # a boolean OCC cannot do in this order
            log.append("%s failed: %s" % (order.__name__, ex))
            continue
        log.append("%s: hosel junction fillet %s, shaved heel round %s" % (order.__name__, r_neck, r_heel))
        score = (r_neck is not None) * 2 + (r_heel is not None)
        if best is None or score > best[0]:
            best = (score, b)
        if score == 3:
            break
    if best is None or best[0] < 3:
        raise RuntimeError("could not complete the tangent neck and heel rounds")
    body = best[1]

    # A blind socket stops inside the hosel instead of piercing the slim heel.
    bore = Part.makeCylinder(BORE_R, 32, MOUTH - AXIS * 31, AXIS)
    head = body.cut(bore)
    if not head.isValid():
        raise RuntimeError('Invalid main body')
    body = head

    # --- from here on as build_sport_hybrid.py ---------------------------------------------------
    cuts = []
    for z in [11, 15, 19, 23, 27, 31]:
        extent = 33 if z in [15, 19, 23, 27] else 26
        for xa, xb in [(-extent, -4), (4, extent)]:
            y = -13 + TAN * (z - 21)
            cuts.append(Part.makeBox(xb - xa, 1.1, 0.35, V(xa, y - 0.5, z)))
    body = body.cut(Part.makeCompound(cuts))
    # Seat the detailed screw close to the face, normal to the actual sole.
    screw_x, screw_y = 4.0, 8.0
    ray = Part.makeLine(V(screw_x, screw_y, -40), V(screw_x, screw_y, 35))
    hits = body.section(ray).Vertexes
    sole_point = min((p.Point for p in hits), key=lambda p: p.z)
    support = min(body.Faces, key=lambda f: f.distToShape(Part.Vertex(sole_point))[0])
    screw_axis = support.normalAt(*support.Surface.parameter(sole_point))
    if screw_axis.z > 0:
        screw_axis = -screw_axis
    screw_axis.normalize()
    screw_top = sole_point + screw_axis * 0.25
    socket = Part.makeCylinder(5.5, 2.3, sole_point - screw_axis * 1.9, screw_axis)
    body = body.cut(socket)
    screw = Part.makeCylinder(4.65, 1.6, screw_top - screw_axis * 1.6, screw_axis)
    front_rim = [e for e in screw.Edges if e.Length > 20 and abs((e.CenterOfMass - screw_top).dot(screw_axis)) < 0.01]
    screw = screw.makeChamfer(0.22, front_rim)
    u = V(1, 0, 0) - screw_axis * screw_axis.x
    u.normalize()
    v = screw_axis.cross(u)
    drive_pts = []
    for i in range(96):
        t = 2 * math.pi * i / 96
        r = 1.42 + 0.27 * math.cos(6 * t)
        drive_pts.append(screw_top + screw_axis * 0.02 + (u * math.cos(t) + v * math.sin(t)) * r)
    drive_curve = Part.BSplineCurve()
    drive_curve.interpolate(drive_pts, PeriodicFlag=True)
    drive_face = Part.Face(Part.Wire([drive_curve.toShape()]))
    drive_cut = drive_face.extrude(-screw_axis * 0.95)
    annulus = Part.makeCylinder(3.72, 0.20, screw_top - screw_axis * 0.17, screw_axis).cut(
        Part.makeCylinder(3.55, 0.22, screw_top - screw_axis * 0.18, screw_axis))
    screw = screw.cut(drive_cut).cut(annulus)
    seat = Part.makeCylinder(5.4, 1.9, sole_point - screw_axis * 1.85, screw_axis).cut(
        Part.makeCylinder(4.72, 2.1, sole_point - screw_axis * 1.95, screw_axis))
    drive_floor = drive_face.translated(-screw_axis * 0.87).extrude(-screw_axis * 0.04)
    wedge = prism_yz([(-100, -30), (-4 + TAN * (-51), -30), (-4 + TAN * 79, 100), (-100, 100)])
    wedge = wedge.fuse(Part.makeBox(80, 200, 160, V(-120, -100, -30)))
    silver = body.common(wedge)
    shell = body.cut(wedge)
    soletool = Part.makeBox(240, 240, 42, V(-120, -120, -30))
    sole = shell.common(soletool)
    crown = shell.cut(soletool)
    # Keep the tiny heel finish fragment in the surrounding steel finish.
    small = [s for s in crown.Solids if s.Volume < 5]
    if small:
        silver = silver.multiFuse(small).removeSplitter()
        crown = Part.makeCompound([s for s in crown.Solids if s.Volume >= 5])
    ferrule = Part.makeCone(6.3, 5.6, 12, NECKBASE + AXIS * FERRULE_AT, AXIS).cut(bore)
    outer = body.copy()
    outer.translate(V(0, 0, -0.28))
    skin = outer.cut(body)
    rails = {}
    for side in [-1, 1]:
        poly = [V(side * 30, 4, -20), V(side * 32, 8, -20), V(side * 20, 31, -20), V(side * 17, 32, -20),
                V(side * 24, 12, -20)]
        if side < 0:
            poly = [p + V(5, 0, 0) for p in poly]
        rail = Part.Face(Part.makePolygon(poly + [poly[0]])).extrude(V(0, 0, 36))
        rails['BlueSoleRail' + ('Heel' if side < 0 else 'Toe')] = skin.common(rail)
    top = body.copy()
    top.translate(V(0, 0, 0.16))
    topskin = top.cut(body)
    vv = [V(-2, -1, 20), V(0, -4, 20), V(2, -1, 20), V(0, -2, 20)]
    mark = Part.Face(Part.makePolygon(vv + [vv[0]])).extrude(V(0, 0, 40))
    shapes = {'SatinSilverFrame': silver, 'BlackCrown': crown, 'GraphiteSole': sole, 'BlackFerrule': ferrule,
              'RearWeight': screw, 'ScrewSeat': seat, 'ScrewDriveRecess': drive_floor,
              'AlignmentChevron': topskin.common(mark)}
    shapes.update(rails)
    for name, s in shapes.items():
        if s.isNull() or not s.isValid() or not s.Solids:
            raise RuntimeError('Invalid ' + name)
        log.append("%s: solids %d valid %s" % (name, len(s.Solids), s.isValid()))
    return shapes, log


def apply(shapes, doc_name='SportHybrid21'):
    """Put the rebuilt shapes into the open document (keeping its colours, labels, finishes) and
    save it with a STEP beside it."""
    doc = App.getDocument(doc_name)
    for name, shape in shapes.items():
        obj = doc.getObject(name)
        if obj is None:
            raise RuntimeError('missing object ' + name)
        obj.Shape = shape
        obj.ViewObject.Deviation = 0.015
        obj.ViewObject.AngularDeflection = 5.0
        obj.ViewObject.DisplayMode = "Shaded"
    params = doc.getObject('DesignParameters')
    if params is not None:
        if 'HoselForwardShift' not in params.PropertiesList:
            params.addProperty('App::PropertyFloat', 'HoselForwardShift', 'Design')
        params.HoselForwardShift = HOSEL_FORWARD
        for name,value in [('HeelBlendRadius',12.0),('FaceEdgeRound',2.5),('HeelSoleRound',2.0),('RearCrownRadius',53.24)]:
            if name not in params.PropertiesList:
                params.addProperty('App::PropertyFloat',name,'Design')
            setattr(params,name,value)
        params.DesignNotes = ('Continuous steel face, heel and hosel: the face is one plane to the heel; the hosel '
                              'rises through a 12 mm tangent blend into a face perimeter rounded by 2.5 mm; the '
                              'shaved lower heel is rounded. Upper shaft vertical in toe view, 60-degree lie in '
                              'face view. Rounded elliptical rear crown, black crown and blue sole rails.')
    doc.recompute()
    doc.save()
    keep = [doc.getObject(n) for n in ['SatinSilverFrame', 'BlackCrown', 'GraphiteSole', 'BlackFerrule',
                                       'BlueSoleRailHeel', 'BlueSoleRailToe', 'RearWeight', 'ScrewSeat',
                                       'ScrewDriveRecess', 'AlignmentChevron']]
    Part.export(keep, os.path.join(OUT, 'Sport_Hybrid_21.step'))
    return doc.FileName


if os.environ.get('HYBRID_NO_MAIN') != '1':
    built, notes = build()
    print('\n'.join(notes))
    active=App.ActiveDocument
    if active is None or active.getObject('SatinSilverFrame') is None:
        active=App.openDocument(os.path.join(OUT,'Sport_Hybrid_21.FCStd'))
    print('SAVED', apply(built,active.Name))
