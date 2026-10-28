"""Export the forged iron heads (FreeCAD) as the game's 4-9 iron sets, one livery per set.

The heads are the parametric family in Documents/FreeCAD/GolfHead/irons/build_irons.py, all with the
Utility 2U's face-to-hosel joint: "blade" (the Blade Runner's muscle bar, fuller), "mb" (muscle back:
the bar with a weight bar low on it and a shallow cavity following the upper blade), "cb" (cavity back:
a 3 mm dish in a wide frame, a raised panel in it) and "gi" (the cavity back with a spatula-wide sole).
Each set's look is LIVERIES[set]: its head, finishes for the face, screws, number paint and ferrule,
and back art from tools/make_iron_textures.py (assets/Iron_Heads/textures/<set>_back*.png) projected
square to the face over the whole body except the face itself (the art's ground is the body finish).

Two stages, run with freecadcmd (env IRON_STAGE):
    geo   build each head; save its parts (assets/Iron_Heads/geo/<head>/*.brep) and the geometry the
          art is drawn on (geo/<head>/art.json: outlines in face coordinates, and back_mask.png)
    glb   per set: the head's hosel cut so its mouth sits MOUTH_Z[set] above the sole (matching the
          set's stock head in the swing rig), meshed, written to assets/Selected_Club_Heads/skins/
          <set>_v2_base.glb in the 2U skin's frame (metres, origin at the hosel mouth, +Y up the shaft,
          toe -X, face +Z: OFGEquipmentAssets gives iron skins the face flip)
    freecadcmd -c "exec(open(r'C:/Users/willi/Documents/GolfGame/tools/freecad/export_iron_heads.py').read())"
then python tools/make_iron_textures.py (between the stages), and Godot's import.
"""
import json
import math
import os

GAME = r"C:/Users/willi/Documents/GolfGame"
HEAD_SCRIPT = r"C:/Users/willi/Documents/FreeCAD/GolfHead/irons/build_irons.py"
ROOT = os.path.join(GAME, "assets", "Iron_Heads")
GEO = os.path.join(ROOT, "geo")
TEXTURES = os.path.join(ROOT, "textures")
OUT_DIR = os.environ.get("IRON_OUT_DIR", os.path.join(GAME, "assets", "Selected_Club_Heads", "skins"))
HYBRID_EXPORT = os.path.join(GAME, "tools", "freecad", "export_sport_hybrid_head.py")
EXPORT_2U = os.path.join(GAME, "tools", "freecad", "export_utility_2u_head.py")
HEADS = ("blade", "mb", "cb", "gi", "2u")
BOX = (-45.0, 100.0, -8.0, 92.0)  # the art's frame: face coordinates (x heel -> toe, z up the face), mm
PPM = 8.0
FACE_Y = 0.6       # mm behind the face plane: the face itself (its edge rounds start here)
HOSEL_CLEAR = 1.2  # ... and this far off the hosel (whose front stands proud of the face)
RIM_CHAMFER = 0.5
TOLERANCE = (0.03, 0.12)  # tessellation: chord deviation (mm), angle (rad)
CREASE = 35.0
UV_METAL = 0.04

# finish: base colour (sRGB), metallic, roughness, optional "brushed" roughness map
FINISHES = {
    "blast_face": dict(base=(0.70, 0.72, 0.74), metallic=0.9, roughness=0.46, mr="brushed"),
    "raw_face": dict(base=(0.62, 0.64, 0.66), metallic=0.95, roughness=0.40, mr="brushed"),
    "black_face": dict(base=(0.16, 0.17, 0.18), metallic=0.85, roughness=0.42, mr="brushed"),
    "gold_face": dict(base=(0.62, 0.50, 0.26), metallic=0.95, roughness=0.42, mr="brushed"),
    "navy_face": dict(base=(0.13, 0.15, 0.20), metallic=0.85, roughness=0.42, mr="brushed"),
    "screw_steel": dict(base=(0.62, 0.65, 0.68), metallic=0.95, roughness=0.28),
    "plug_steel": dict(base=(0.78, 0.80, 0.83), metallic=1.0, roughness=0.22),
    "smoke_face": dict(base=(0.20, 0.21, 0.23), metallic=0.9, roughness=0.42, mr="brushed"),
    "screw_gold": dict(base=(0.91, 0.76, 0.35), metallic=1.0, roughness=0.25),
    "screw_black": dict(base=(0.05, 0.05, 0.055), metallic=0.6, roughness=0.35),
    "screw_orange": dict(base=(1.0, 0.45, 0.12), metallic=0.8, roughness=0.30),
    "paint_white": dict(base=(0.90, 0.90, 0.90), metallic=0.0, roughness=0.40),
    "paint_black": dict(base=(0.03, 0.03, 0.035), metallic=0.0, roughness=0.45),
    "paint_gold": dict(base=(0.91, 0.76, 0.35), metallic=0.8, roughness=0.30),
    "paint_orange": dict(base=(1.0, 0.55, 0.23), metallic=0.0, roughness=0.40),
    "paint_red": dict(base=(0.70, 0.10, 0.08), metallic=0.0, roughness=0.45),
    "paint_cream": dict(base=(0.91, 0.82, 0.60), metallic=0.0, roughness=0.45),
    "ferrule": dict(base=(0.02, 0.02, 0.025), metallic=0.0, roughness=0.35),
    "ferrule_yellowed": dict(base=(0.86, 0.76, 0.46), metallic=0.0, roughness=0.45),
    "ferrule_white": dict(base=(0.86, 0.86, 0.84), metallic=0.0, roughness=0.40),
    "back_art": dict(base=(1.0, 1.0, 1.0), metallic=1.0, roughness=1.0, tex="back"),
}
# set -> head, its mouth height (mm above the sole at the 60 degree lie: seats the head where the
# set's stock head sat in the swing rig, measured at address and impact), and the finish of each slot
LIVERIES = {
    "loaner_irons": dict(head="cb", mouth=56.65, face="blast_face", screw="screw_steel", mark="paint_black", ferrule="ferrule"),
    "thrift_cavity_backs": dict(head="cb", mouth=56.65, face="blast_face", screw="screw_steel", mark="paint_red", ferrule="ferrule"),
    "game_improver_xl": dict(head="gi", mouth=56.70, face="blast_face", screw="screw_steel", mark="paint_black", ferrule="ferrule"),
    "mustard_muscle": dict(head="mb", mouth=55.22, face="gold_face", screw="screw_gold", mark="paint_cream", ferrule="ferrule_yellowed"),
    "blade_runner_forged": dict(head="blade", mouth=55.22, face="raw_face", screw="screw_steel", mark="paint_white", ferrule="ferrule"),
    "tour_forged_cb": dict(head="cb", mouth=56.60, face="black_face", screw="screw_gold", mark="paint_gold", ferrule="ferrule"),
    # the Utility Iron 2U (a hybrid in the catalog, an iron head: the same face flip through HEAD_OVERRIDES)
    "utility_2u": dict(head="2u", mouth=55.8, face="smoke_face", screw="screw_steel", mark="paint_white", ferrule="ferrule",
                       plug="plug_steel"),
    "combo_proto": dict(head="mb", mouth=55.22, face="navy_face", screw="screw_orange", mark="paint_orange", ferrule="ferrule"),
}
_MOUTH = json.loads(os.environ.get("IRON_MOUTH", "{}"))  # calibration overrides: {set: mm}
for _k, _v in _MOUTH.items():
    LIVERIES[_k]["mouth"] = _v
PART_SLOT = {"Badge": "shell", "Screws": "screw", "MarkFill": "mark", "Ferrule": "ferrule", "PortPlug": "plug"}


def head_ns(variant):
    """build_irons.py's namespace for one head (it reads IRON_VARIANT as it loads)."""
    os.environ["GOLFHEAD_NO_MAIN"] = "1"
    os.environ["IRON_VARIANT"] = variant
    ns = {"__name__": "irons_" + variant}
    with open(HEAD_SCRIPT, encoding="utf-8") as f:
        exec(f.read(), ns)
    return ns


def face_coords(points, info, ns):
    """Final model points (right-handed address mm, numpy N x 3) -> face coordinates (x heel -> toe as
    built, y back from the face plane, z up the face)."""
    import numpy as np
    cl, sl = math.cos(math.radians(ns["LOFT"])), math.sin(math.radians(ns["LOFT"]))
    xb = -points[:, 0]
    ya = points[:, 1]
    za = points[:, 2] + info["ground"] + info["drop"]
    return np.c_[xb, ya * cl - za * sl, ya * sl + za * cl]


# ---- stage geo ------------------------------------------------------------------------------------
def poly_of(face, step=0.5):
    return [(p.x, p.z) for p in face.OuterWire.discretize(Distance=step)]


def stage_geo():
    import numpy as np
    import MeshPart
    import Part
    from PIL import Image, ImageDraw
    from FreeCAD import Vector as V
    for variant in HEADS:
        ns = head_ns(variant)
        parts, info = ns["build"]()
        out = os.path.join(GEO, variant)
        os.makedirs(out, exist_ok=True)
        for name, shape in parts.items():
            shape.exportBrep(os.path.join(out, name + ".brep"))
        top = info["top"]
        meta = {"drop": info["drop"], "ground": info["ground"], "top": [top.x, top.y, top.z],
                "loft": ns["LOFT"], "lie": ns["LIE"], "bore_r": ns["BORE_R"], "hosel_r": ns["HOSEL_R"],
                "neck_x": ns["NECK_X"], "box": BOX, "ppm": PPM, "parts": sorted(parts)}
        xs = [ns["NECK_X"] + k * 0.5 for k in range(int((96 - ns["NECK_X"]) / 0.5) + 1)]
        art = {"top": [(x, ns["top_h"](x)) for x in xs], "toe": [list(p) for p in ns["toe_outline"]()],
               "neck_x": ns["NECK_X"]}
        if ns["SECTION"] == "shelf":
            art["crease"] = [(x, ns["lip_z"](x)) for x in xs]
            art["lip"] = [(x, ns["lip_z"](x) + ns["STEP_H"]) for x in xs]
            if ns["PORT"]:
                art["port"] = [ns["PORT_AT"][0], ns["PORT_AT"][1], ns["PORT_R"] + ns["PORT_GAP"]]
        if ns["SECTION"] == "bar":
            cz = (ns["BAR_CREASE_Z"] + ns["BAR_PAD"] * ns["SL"]) / ns["CL"]
            art["crease"] = [(x, cz) for x in xs]
            art["lip"] = [(x, ns["lip_z"](x)) for x in xs]
            if "pad_band" in ns:
                art["pad"] = [(x,) + tuple(ns["pad_band"](x)) for x in xs]
        if ns["CAVITY"]:
            art["pocket"] = [(p.x, p.z) for p in ns["pocket_outline"]()]
            if ns["CAVITY_PANEL"]:
                pts = ns["pocket_outline"]()
                n = len(pts)
                inset = []
                for k in range(n):
                    t = pts[(k + 1) % n] - pts[k - 1]
                    inset.append(pts[k] + V(-t.z, 0, t.x).normalize() * ns["BADGE_GAP"])
                panel = Part.Face(ns["closed_curve"](inset))
                x0, x1 = min(p.x for p in pts), max(p.x for p in pts)

                def height_at(x, f):
                    lo = ns["lip_z"](x) + ns["POCKET_LIP"]
                    return lo + (ns["top_h"](x) - ns["RAIL_W"] - lo) * f
                xk = x0 + (x1 - x0) * ns["BADGE_KINK"]
                bt = ns["BADGE_TOP"]
                line = [V(x0 - 5.0, 0, height_at(x0, bt[0])), V(xk, 0, height_at(xk, bt[1])), V(x1 + 5.0, 0, height_at(x1, bt[2]))]
                below = Part.Face(Part.makePolygon(line + [V(x1 + 5.0, 0, -50.0), V(x0 - 5.0, 0, -50.0), line[0]]))
                art["panel"] = poly_of(panel.common(below).Faces[0])
        if ns["MB_WEIGHT"]:
            wf = ns["weight_outline"]()
            art["weight"] = poly_of(wf)
            bb = wf.BoundBox
            art["screws"] = [(x, sum(ns["pad_band"](x)) / 2) for x in (bb.XMin + ns["SCREW_IN"] + 1.0, bb.XMax - ns["SCREW_IN"] - 1.0)]
        json.dump(meta, open(os.path.join(out, "info.json"), "w"), indent=1)
        json.dump(art, open(os.path.join(out, "art.json"), "w"))
        # where the back's art shows: the body's faces turned away from the face, seen square to it
        m = MeshPart.meshFromShape(Shape=parts["Body"], LinearDeflection=0.05, AngularDeflection=0.2, Relative=False)
        pts, tris = m.Topology
        P = face_coords(np.array([(p.x, p.y, p.z) for p in pts]), info, ns)
        T = np.array(tris)
        a, b, c = P[T[:, 0]], P[T[:, 1]], P[T[:, 2]]
        nrm = np.cross(b - a, c - a)
        back = nrm[:, 1] / np.maximum(np.linalg.norm(nrm, axis=1), 1e-12) > 0.25
        x0, x1, z0, z1 = BOX
        img = Image.new("L", (round((x1 - x0) * PPM), round((z1 - z0) * PPM)), 0)
        d = ImageDraw.Draw(img)
        for t in T[back]:
            d.polygon([((P[i, 0] - x0) * PPM, (z1 - P[i, 2]) * PPM) for i in t], fill=255)
        img.save(os.path.join(out, "back_mask.png"))
        print(variant, "geo:", sorted(parts), "back triangles", int(back.sum()))


# ---- stage glb ------------------------------------------------------------------------------------
def load_head(variant):
    import Part
    meta = json.load(open(os.path.join(GEO, variant, "info.json")))
    parts = {}
    for name in meta["parts"]:
        s = Part.Shape()
        s.read(os.path.join(GEO, variant, name + ".brep"))
        parts[name] = s
    return parts, meta


def stage_glb():
    import numpy as np
    import MeshPart
    import Part
    from FreeCAD import Vector as V
    hy = {"__name__": "x"}
    os.environ["SPORT_HYBRID_NO_MAIN"] = "1"
    exec(open(HYBRID_EXPORT, encoding="utf-8").read(), hy)
    h2 = {"__name__": "y"}
    os.environ["UTILITY_2U_NO_MAIN"] = "1"
    exec(open(EXPORT_2U, encoding="utf-8").read(), h2)
    brushed = h2["brushed_map"]()
    report = []
    for club, liv in LIVERIES.items():
        if os.environ.get("IRON_ONLY") and club not in os.environ["IRON_ONLY"].split(","):
            continue  # (IRON_ONLY=set,set: just those)
        parts, meta = load_head(liv["head"])
        info = {"drop": meta["drop"], "ground": meta["ground"]}
        ns = {"LOFT": meta["loft"]}
        lie = math.radians(meta["lie"])
        axis = V(math.cos(lie), 0, math.sin(lie))  # up the shaft, right-handed (toe -X)
        top = V(*meta["top"])
        down = (top.z - liv["mouth"]) / axis.z
        mouth = top - axis * down
        body = parts["Body"].common(Part.makeCylinder(400.0, 800.0, mouth - axis * 800.0, axis))
        try:
            rim = [e for e in body.Edges if all(abs((p - mouth).dot(axis)) < 1e-4 for p in e.discretize(6))
                   and min((p - mouth).Length for p in e.discretize(6)) > meta["bore_r"] + 0.2]
            ch = body.makeChamfer(RIM_CHAMFER, rim)
            if ch.isValid():
                body = ch
        except Exception:
            pass
        parts = dict(parts)
        parts["Body"] = body
        parts["Ferrule"] = parts["Ferrule"].translated(-axis * down)
        # skin frame: +Y up the shaft, X across it toward the heel, Z toward the target (the face)
        X = V(axis.z, 0.0, -axis.x)
        Z = X.cross(axis)
        M = np.array([[X.x, X.y, X.z], [axis.x, axis.y, axis.z], [Z.x, Z.y, Z.z]])
        m0 = np.array([mouth.x, mouth.y, mouth.z])
        a_np = np.array([axis.x, axis.y, axis.z])
        x0, x1, z0, z1 = BOX

        def art_uv(p):
            f = face_coords(p, info, ns)
            return np.c_[(f[:, 0] - x0) / (x1 - x0), (z1 - f[:, 2]) / (z1 - z0)]

        def metal_uv(p):
            f = face_coords(p, info, ns)
            return np.c_[f[:, 0] * UV_METAL, f[:, 2] * UV_METAL]

        groups = {}  # finish -> list of (pos, nrm, uv, tris)

        def add(fin, pos, nrm, uv, tri):
            groups.setdefault(fin, []).append((pos, nrm, uv, tri))

        for name, shape in parts.items():
            faces = []
            if len(shape.Solids) <= 1 and len(shape.Shells) > 1:  # (a hollow body's sealed inside)
                shape = max(shape.Shells, key=lambda sh: sh.BoundBox.DiagonalLength)
            for f in shape.Faces:  # not the shaft's bore
                if isinstance(f.Surface, Part.Cylinder) and abs(f.Surface.Radius - meta["bore_r"]) < 0.05:
                    continue
                faces.append(f)
            if not faces:
                continue
            m = MeshPart.meshFromShape(Shape=Part.makeCompound(faces), LinearDeflection=TOLERANCE[0],
                                       AngularDeflection=TOLERANCE[1], Relative=False)
            pts, tris = m.Topology
            pos0 = np.array([(p.x, p.y, p.z) for p in pts])
            pos, nrm, tri = EXP["creased"](pos0, np.array(tris, dtype=np.int64), CREASE)
            if name == "Body":
                f = face_coords(pos, info, ns)
                w = pos - np.array([mouth.x, mouth.y, mouth.z])
                radial = np.linalg.norm(w - np.outer(w @ a_np, a_np), axis=1)
                field = np.maximum(f[:, 1] - FACE_Y, meta["hosel_r"] + HOSEL_CLEAR - radial)
                field = np.where(np.abs(field) < 1e-6, 1e-6, field)
                pos, nrm, tri = EXP["split_along"](pos, nrm, tri, field)
                cen = (pos[tri[:, 0]] + pos[tri[:, 1]] + pos[tri[:, 2]]) / 3.0
                fc = face_coords(cen, info, ns)
                w = cen - np.array([mouth.x, mouth.y, mouth.z])
                radial = np.linalg.norm(w - np.outer(w @ a_np, a_np), axis=1)
                is_face = np.maximum(fc[:, 1] - FACE_Y, meta["hosel_r"] + HOSEL_CLEAR - radial) < 0
                for fin, sel in ((liv["face"], tri[is_face]), ("back_art", tri[~is_face])):
                    used = np.unique(sel)
                    remap = -np.ones(len(pos), dtype=np.int64)
                    remap[used] = np.arange(len(used))
                    p = pos[used]
                    add(fin, p, nrm[used], art_uv(p) if fin == "back_art" else metal_uv(p), remap[sel])
            else:
                slot = PART_SLOT[name]
                fin = "back_art" if slot == "shell" else liv[slot]
                add(fin, pos, nrm, art_uv(pos) if fin == "back_art" else metal_uv(pos), tri)
            report.append("%s %s: %d triangles" % (club, name, len(tri)))

        images = {"brushed": (brushed, 10497)}
        for kind, suffix in (("", "_base"), ("_rough", "_rough")):
            with open(os.path.join(TEXTURES, "%s_back%s.png" % (club, kind)), "rb") as fh:
                images["%s_back%s" % (club, suffix)] = (fh.read(), 33071)
        meshes = []
        for fin, chunks in sorted(groups.items()):
            spec = FINISHES[fin]
            P, N, U, I = [], [], [], []
            for p, n, uv, t in chunks:
                base = len(P) // 3
                P += ((p - m0) @ M.T * 0.001).reshape(-1).tolist()
                N += (n @ M.T).reshape(-1).tolist()
                U += uv.reshape(-1).tolist()
                I += (t.reshape(-1) + base).tolist()
            tkey = spec.get("tex")
            mat = {"name": "ofg_%s_v2__%s" % (club, fin), "base": hy["linear"](spec["base"]),
                   "metallic": spec["metallic"], "roughness": spec["roughness"],
                   "base_tex": "%s_back_base" % club if tkey else None,
                   "mr_tex": "%s_back_rough" % club if tkey else spec.get("mr")}
            node = "%sV2_%s" % ("".join(w.capitalize() for w in club.split("_")),
                                "".join(w.capitalize() for w in fin.split("_")))
            meshes.append((node, mat, P, N, U, I))
        path = os.path.join(OUT_DIR, club + "_v2_base.glb")
        hy["write_glb"](path, meshes, images)
        report.append("wrote %s (%s head, mouth %.2f mm, %d meshes, %.1f MB)" % (
            path, liv["head"], liv["mouth"], len(meshes), os.path.getsize(path) / 1e6))
    return report


EXP = {}
if os.environ.get("IRON_EXPORT_NO_MAIN") != "1":
    stage = os.environ.get("IRON_STAGE", "geo")
    if stage == "geo":
        stage_geo()
    else:
        os.environ["DRIVER_EXPORT_NO_MAIN"] = "1"
        exec(open(os.path.join(GAME, "tools", "freecad", "export_driver_460_head.py"), encoding="utf-8").read(), EXP)
        print("\n".join(stage_glb()))
