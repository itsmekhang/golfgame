"""Driver460 with the Sport Hybrid 21's face-to-hosel joint, built headless in stages.

    freecadcmd -c "exec(open(r'.../build_hybrid_driver.py').read())"   with env STAGE=head|finish

head:   the distance-field head in the hybrid's order (face cut off the body with a rounded
        edge, then the hosel added with a 12 mm tangent blend: face_hosel_blend.hybrid_field),
        lofted at high resolution -> out/head.brep, and the flat face's outline seen face-on
        (surface points on the face sphere whose normal is the face's) -> out/face_edge.json
finish: head.brep + the fitted insert outline (out/insert.json, from fit_insert.py) -> heel
        screw, score lines, squared and bored hosel, ferrule, the dark face insert split into the
        face -> out/*.brep, out/stl/*.stl (insert as its own mesh), driver_460_hybrid.step and
        .FCStd, and a json report
"""
import json
import math
import os
import time

import FreeCAD as App
import Part
from FreeCAD import Vector as V

DRV = r"C:/Users/willi/Documents/FreeCAD/GolfHead/driver"
HELPER = r"C:/Users/willi/Documents/Codex/2026-10-03/connec/outputs/Driver_460_Heel_Refinement/face_hosel_blend.py"
OUT = os.environ.get("DRIVER_OUT", DRV + "/hybrid")  # (variants build into their own folder)
os.makedirs(OUT + "/stl", exist_ok=True)

os.environ["GOLFHEAD_NO_MAIN"] = "1"
NS = {"__name__": "driver_base"}
exec(open(DRV + "/build_driver.py", encoding="utf-8").read(), NS)
NS["FACE_HEEL_END"] = (200.0, 210.0)
NS["N_RAYS"] = 480       # dense enough round each section for the 3 mm face round
NS["X_STEP"] = 1.5
NS["HOSEL_SETBACK"] = 2.5  # 1 mm further back than build_driver.py: room for the face to run flat to it
NS["HEEL_TIP"] = tuple(NS["on_axis"](36.0))  # the body's heel closes on the hosel's axis, well inside it
NS["PORT_AT"] = (12.0, 28.0)  # the sole screw on the flat of the sole (by the heel edge its pocket broke out)
# HOSEL_SHIFT: the hosel moved this far toe-ward (with the x-ranges that hand the heel over to it),
# and HEEL_TIP_Z: how far up its axis the body's heel closes - together they set how much of the
# hosel stands clear of the heel (from above it poked out like a spout)
_shift = float(os.environ.get("HOSEL_SHIFT", "0"))
if _shift:
    NS["HOSEL_GROUND_X"] -= _shift
    NS["HOSEL_FRONT_AT"] = (NS["HOSEL_FRONT_AT"][0] - _shift, NS["HOSEL_FRONT_AT"][1])
    NS["HOSEL_BLEND"] = tuple(v - _shift for v in NS["HOSEL_BLEND"])
    NS["FACE_EDGE_HEEL_X"] = tuple(v - _shift for v in NS["FACE_EDGE_HEEL_X"])
NS["HEEL_TIP"] = tuple(NS["on_axis"](float(os.environ.get("HEEL_TIP_Z", "36"))))
BL = {"__name__": "face_hosel_blend"}
exec(open(HELPER, encoding="utf-8").read(), BL)
FACE_R = 3.0             # the face's edge round, in the field (Sport Hybrid 21: 2.5)

out_dir = V(0, -math.cos(math.radians(NS["LOFT"])), math.sin(math.radians(NS["LOFT"])))
SPHERE_C = V(0, 0, NS["FACE_CZ"]) - out_dir * NS["BULGE_R"]


def stage_head():
    t = time.time()
    field = BL["hybrid_field"](NS, FACE_R)
    head = NS["loft_rings"](NS["head_rings"](field), V(*NS["TOE_TIP"]))
    head.exportBrep(OUT + "/head.brep")
    s = head.Faces[0].Surface
    rows = {}
    dev = []
    for i in range(700):
        for j in range(700):
            u, v = i / 699.0, j / 699.0
            p = s.value(u, v)
            d = (p - SPHERE_C).Length - NS["BULGE_R"]
            if abs(d) > 0.01:
                continue
            n = s.normal(u, v)
            radial = p - SPHERE_C
            radial.normalize()
            if abs(n.dot(radial)) < 0.9995:  # crossing the sphere at an angle (hosel): not face
                continue
            dev.append(d)
            k = round(p.z * 2) / 2
            lo, hi = rows.get(k, (p.x, p.x))
            rows[k] = (min(lo, p.x), max(hi, p.x))
    ks = sorted(rows)
    poly = [(rows[k][1], k) for k in ks] + [(rows[k][0], k) for k in reversed(ks)]
    json.dump(poly, open(OUT + "/face_edge.json", "w"))
    rep = {"stage": "head", "valid": head.isValid(), "cc": head.Volume / 1000.0,
           "face_dev_mm": (min(dev), max(dev)), "seconds": time.time() - t}
    json.dump(rep, open(OUT + "/head_report.json", "w"), indent=1)
    print(json.dumps(rep))


INSERT_DEPTH = 1.0  # the face insert: a plate this thick inside the fitted outline


def face_insert(body, outline):
    """The dark face insert as its own part: the body's outer INSERT_DEPTH behind the face, inside
    the fitted outline (seen face-on); returns (frame, insert). Rebuilding one solid round a
    split face came out invalid."""
    pts = [V(x, -40.0, z) for x, z in outline]
    curve = Part.BSplineCurve()
    curve.interpolate(pts, PeriodicFlag=True)
    prism = Part.Face(Part.Wire(curve.toShape())).extrude(V(0, 52.0, 0))  # y -40 .. 12
    ball = Part.makeSphere(NS["BULGE_R"] - INSERT_DEPTH, SPHERE_C)
    skin = body.common(prism).cut(ball)
    frame = body.cut(skin)
    return frame, skin


def stage_finish():
    t = time.time()
    head = Part.Shape()
    head.read(OUT + "/head.brep")
    body, weight = NS["heel_port"](head)
    body, paint = NS["score_lines"](body)
    top = NS["on_axis"](NS["HOSEL_TOP_Z"])
    body = body.cut(Part.makeCylinder(80.0, 80.0, top, NS["AXIS"]))
    body = body.cut(Part.makeCylinder(NS["BORE_R"], NS["BORE_DEPTH"] + 1.0, top + NS["AXIS"], -NS["AXIS"]))
    outline = json.load(open(OUT + "/insert.json"))["outline"]
    body, insert = face_insert(body, outline)
    ferrule = Part.makeCone(NS["HOSEL_R_TOP"] - 0.2, 4.9, NS["FERRULE_H"], top, NS["AXIS"])
    ferrule = ferrule.cut(Part.makeCylinder(NS["BORE_R"], NS["FERRULE_H"] + 2, top - NS["AXIS"], NS["AXIS"]))
    ground = body.optimalBoundingBox().ZMin
    shift = V(0, 0, -ground)
    parts = {"Body": body, "FaceInsert": insert, "Ferrule": ferrule, "HeelWeight": weight, "ScorePaint": paint}
    parts = {n: s.translated(shift) for n, s in parts.items() if s is not None}
    for n, s in parts.items():
        s.exportBrep(OUT + "/" + n + ".brep")
    import MeshPart
    for n, s in parts.items():
        MeshPart.meshFromShape(Shape=s, LinearDeflection=0.02, AngularDeflection=0.12).write(OUT + "/stl/" + n + ".stl")
    doc = App.newDocument("Driver460Hybrid")
    for n, s in parts.items():
        doc.addObject("Part::Feature", n).Shape = s
    doc.recompute()
    doc.saveAs(DRV + "/" + os.environ.get("DRIVER_DOC", "driver_460_hybrid") + ".FCStd")
    import Import
    Import.export(doc.Objects, DRV + "/" + os.environ.get("DRIVER_DOC", "driver_460_hybrid") + ".step")
    u = NS["usga"](parts["Body"])
    rep = {"stage": "finish", "valid": {n: s.isValid() for n, s in parts.items()},
           "cc": (parts["Body"].Volume + parts["FaceInsert"].Volume) / 1000.0,
           "heel_toe_in": u["heel_toe"] / 25.4, "face_back_mm": u["face_back"], "seconds": time.time() - t}
    json.dump(rep, open(OUT + "/finish_report.json", "w"), indent=1)
    print(json.dumps(rep))


{"head": stage_head, "finish": stage_finish}[os.environ.get("STAGE", "head")]()
