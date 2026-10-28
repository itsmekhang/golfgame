"""Export the Driver460 head (FreeCAD) as the game's driver heads, one livery per club.

Source: the finished parts of Documents/FreeCAD/GolfHead/driver (build_hybrid_driver.py with HOSEL_SHIFT=6
HEEL_TIP_Z=46, so the hosel stands less clear of the heel: hybrid_h2/*.brep,
right-handed address mm, sole on z = 0, toe -X, face -Y): the body with the Sport Hybrid 21's face-to-
hosel joint, the dark face insert, the score-line paint, the sole screw and the ferrule. The body is
painted in three zones by position (crown paint above the head's widest line, sole below it, a metal
frame round the face, the skirt by the hosel and the hosel itself); the look of each club comes from
LIVERIES (the whole flat face, insert included, in one finish), with crown and sole art from tools/make_driver_textures.py (assets/Driver_460_Head/textures).

Writes assets/Selected_Club_Heads/skins/<club>_d460_base.glb in the 2U skin's frame (metres, origin at the
centre of the hosel mouth = the top of the ferrule, +Y up the shaft, toe -X, face +Z; see
tools/freecad/export_utility_2u_head.py); OFGEquipmentAssets.HEAD_OVERRIDES maps each club to its skin
(and so to the same face flip as the 2U and the hybrids). The hosel is lengthened under the ferrule so the
mouth sits MOUTH_Z above the sole at the 60 degree lie: 77.9 mm puts the head's sole where the stock
driver head's sits in the swing rig (measured at address and impact, iterating: there each mm along the
shaft moves the sole ~0.67 mm; the stock GLB's own mouth height reads 104.9 mm, but its lowest point is
internal geometry, not the sole).
Run with freecadcmd:
    freecadcmd -c "exec(open(r'C:/Users/willi/Documents/GolfGame/tools/freecad/export_driver_460_head.py').read())"
then let Godot re-import:  godot --headless --path . --import
"""
import json
import math
import os

import FreeCAD as App
import MeshPart
import Part
from FreeCAD import Vector as V

GAME = r"C:/Users/willi/Documents/GolfGame"
SRC = os.environ.get("DRIVER_SRC", r"C:/Users/willi/Documents/FreeCAD/GolfHead/driver/hybrid_h2")  # the hosel set in
TEXTURES = os.environ.get("DRIVER_TEX_DIR", os.path.join(GAME, "assets", "Driver_460_Head", "textures"))
# the same head design serves the fairway woods (assets/Fairway_Wood_V2): DRIVER_LIVERY_SET=fairway, with
# their own source, textures, parting line, mouth height and skin names (tools/freecad/export_fairway_head.py)
LIVERY_SET = os.environ.get("DRIVER_LIVERY_SET", "driver")
SKIN_SUFFIX = os.environ.get("DRIVER_SKIN_SUFFIX", "_d460")
OUT_DIR = os.environ.get("DRIVER_OUT_DIR", os.path.join(GAME, "assets", "Selected_Club_Heads", "skins"))
HYBRID_EXPORT = os.path.join(GAME, "tools", "freecad", "export_sport_hybrid_head.py")
EXPORT_2U = os.path.join(GAME, "tools", "freecad", "export_utility_2u_head.py")
MOUTH_Z = float(os.environ.get("DRIVER_MOUTH_Z", "75.0"))  # 77.9 before the hosel was set into the heel
LIE = 60.0
AXIS = V(math.cos(math.radians(LIE)), 0, math.sin(math.radians(LIE)))  # up the shaft (model)
BORE_R = 4.3
DEFLECTION = {"Body": (0.08, 0.2), "FaceInsert": (0.05, 0.2), "ScorePaint": (0.03, 0.3),
              "HeelWeight": (0.03, 0.3), "Ferrule": (0.05, 0.25), "HoselExt": (0.05, 0.2)}
CREASE = 40.0      # degrees: sharper edges keep split normals
Z_PART = float(os.environ.get("DRIVER_Z_PART", "24.0"))  # the crown/sole parting line height (the head's widest line at the back)
RIM = float(os.environ.get("DRIVER_RIM", "4.0"))  # mm of metal frame behind the face's edge
FLAT = 0.05        # mm: the body's surface this close to the face sphere is the flat face itself
HOSEL_ZONE = 10.5  # mm from the hosel's axis (above the heel) that stays metal
UV_METAL = 0.04    # brushed-metal tiling: 1 / 25 mm

# finish: base colour (sRGB, white under a texture), metallic, roughness, and its textures: "brushed"
# (the 2U's brushed-satin roughness map, planar), "crown" / "sole" (the club's art, from above)
FINISHES = {
    "satin_steel": dict(base=(0.66, 0.68, 0.71), metallic=0.9, roughness=0.32, mr="brushed"),
    "chrome": dict(base=(0.86, 0.87, 0.89), metallic=1.0, roughness=0.10),
    "gunmetal": dict(base=(0.30, 0.31, 0.33), metallic=0.9, roughness=0.30, mr="brushed"),
    "dark_pvd": dict(base=(0.11, 0.11, 0.12), metallic=0.85, roughness=0.34, mr="brushed"),
    "steel_face": dict(base=(0.52, 0.55, 0.58), metallic=0.9, roughness=0.42, mr="brushed"),
    "hot_titanium": dict(base=(0.60, 0.50, 0.40), metallic=0.95, roughness=0.36, mr="brushed"),
    "black_face": dict(base=(0.07, 0.07, 0.08), metallic=0.6, roughness=0.40, mr="brushed"),
    "carbon_face": dict(base=(0.11, 0.115, 0.125), metallic=0.55, roughness=0.40, mr="brushed"),
    "score_white": dict(base=(0.88, 0.89, 0.90), metallic=0.0, roughness=0.38),
    "score_dark": dict(base=(0.10, 0.105, 0.11), metallic=0.0, roughness=0.50),
    "score_cream": dict(base=(0.95, 0.89, 0.75), metallic=0.0, roughness=0.40),
    "score_gold": dict(base=(0.91, 0.76, 0.35), metallic=0.8, roughness=0.30),
    "score_orange": dict(base=(1.0, 0.55, 0.23), metallic=0.0, roughness=0.40),
    "score_blue": dict(base=(0.79, 0.83, 0.91), metallic=0.0, roughness=0.40),
    "score_yellow": dict(base=(1.0, 0.82, 0.23), metallic=0.0, roughness=0.40),
    "score_red": dict(base=(0.80, 0.13, 0.16), metallic=0.0, roughness=0.40),
    "score_royal": dict(base=(0.20, 0.42, 0.84), metallic=0.0, roughness=0.40),
    "score_teal": dict(base=(0.25, 0.70, 0.68), metallic=0.0, roughness=0.40),
    "score_ice": dict(base=(0.86, 0.91, 0.95), metallic=0.6, roughness=0.25),
    "screw_yellow": dict(base=(1.0, 0.82, 0.23), metallic=0.3, roughness=0.40),
    "screw_steel": dict(base=(0.62, 0.65, 0.68), metallic=0.95, roughness=0.28),
    "screw_gold": dict(base=(0.91, 0.76, 0.35), metallic=1.0, roughness=0.25),
    "screw_black": dict(base=(0.04, 0.04, 0.045), metallic=0.6, roughness=0.35),
    "ferrule": dict(base=(0.02, 0.02, 0.025), metallic=0.0, roughness=0.35),
    "lacquer_black": dict(base=(0.025, 0.022, 0.02), metallic=0.0, roughness=0.18),
    "oxblood_face": dict(base=(0.20, 0.045, 0.035), metallic=0.0, roughness=0.34),
    "screw_brass": dict(base=(0.78, 0.62, 0.35), metallic=1.0, roughness=0.32),
    "crown_art": dict(base=(1.0, 1.0, 1.0), metallic=1.0, roughness=1.0, tex="crown"),
    "sole_art": dict(base=(1.0, 1.0, 1.0), metallic=1.0, roughness=1.0, tex="sole"),
}
_COMMON = {"crown": "crown_art", "sole": "sole_art", "ferrule": "ferrule"}
LIVERIES = {  # club -> {slot: finish}; crown and sole art from textures.json[club]
    "loaner_driver": dict(_COMMON, metal="satin_steel", insert="steel_face", score="score_dark", screw="screw_steel"),
    "thrift_titan_460": dict(_COMMON, metal="gunmetal", insert="steel_face", score="score_white", screw="screw_steel"),
    "slice_slayer": dict(_COMMON, metal="satin_steel", insert="steel_face", score="score_blue", screw="screw_steel"),
    "rocket_boomer_lt": dict(_COMMON, metal="chrome", insert="hot_titanium", score="score_cream", screw="screw_steel"),
    "hollow_point_tour": dict(_COMMON, metal="dark_pvd", insert="black_face", score="score_gold", screw="screw_gold"),
    "meteor_xr_proto": dict(_COMMON, metal="gunmetal", insert="carbon_face", score="score_orange", screw="screw_black"),
    "grenade_driver": dict(_COMMON, metal="dark_pvd", insert="black_face", score="score_yellow", screw="screw_yellow"),
    # persimmon: a black lacquered frame and hosel (like whipping), an oxblood phenolic face, brass screw
    "persimmon_ghost": dict(_COMMON, metal="lacquer_black", insert="oxblood_face", score="score_cream", screw="screw_brass"),
}
FAIRWAY_LIVERIES = {  # the fairway woods (crown and sole art: tools/make_fairway_textures.py): frame, face, score lines
    "loaner_3w": dict(_COMMON, metal="satin_steel", insert="steel_face", score="score_red", screw="screw_steel"),
    "loaner_5w": dict(_COMMON, metal="satin_steel", insert="steel_face", score="score_royal", screw="screw_steel"),
    "garage_3w": dict(_COMMON, metal="gunmetal", insert="steel_face", score="score_teal", screw="screw_steel"),
    "steelhead_classic": dict(_COMMON, metal="chrome", insert="steel_face", score="score_ice", screw="screw_steel"),
    "tour_spoon": dict(_COMMON, metal="dark_pvd", insert="black_face", score="score_gold", screw="screw_gold"),
    "lowball_5w": dict(_COMMON, metal="gunmetal", insert="black_face", score="score_red", screw="screw_black"),
    "heirloom_5w": dict(_COMMON, metal="lacquer_black", insert="oxblood_face", score="score_cream", screw="screw_brass"),
}
if LIVERY_SET == "fairway":
    LIVERIES = FAIRWAY_LIVERIES
if os.environ.get("FAIRWAY_CLUBS"):  # (a fairway head's own clubs)
    LIVERIES = {k: v for k, v in LIVERIES.items() if k in os.environ["FAIRWAY_CLUBS"].split(",")}
for _livery in LIVERIES.values():  # the whole flat face is one plane in one finish: the insert's
    _livery["face"] = _livery["insert"]
PART_SLOT = {"FaceInsert": "insert", "ScorePaint": "score", "HeelWeight": "screw", "Ferrule": "ferrule",
             "HoselExt": "metal"}


def module(path, env):
    os.environ[env] = "1"
    ns = {"__name__": os.path.basename(path)}
    with open(path, encoding="utf-8") as f:
        exec(f.read(), ns)
    return ns


def load_parts():
    parts = {}
    for name in ("Body", "FaceInsert", "ScorePaint", "HeelWeight", "Ferrule"):
        s = Part.Shape()
        s.read(os.path.join(SRC, name + ".brep"))
        parts[name] = s
    return parts


def circle(e):
    """The edge's circle, or None (some edges, like the toe tip's degenerate one, have no curve)."""
    try:
        c = e.Curve
    except Exception:
        return None
    return c if isinstance(c, Part.Circle) else None


def hosel_top(ferrule):
    """The hosel's top centre (the ferrule's foot) and the ferrule's top centre."""
    circles = [c for c in map(circle, ferrule.Edges) if c is not None and c.Radius > BORE_R + 0.5]
    centres = sorted((c.Center for c in circles), key=lambda c: c.dot(AXIS))
    return centres[0], centres[-1]


def sample(face):
    pts, tris = face.tessellate(0.2)
    if tris:
        a, b, c = tris[0]
        p = (pts[a] + pts[b] + pts[c]) * (1.0 / 3.0)
    else:
        p = face.CenterOfMass
    u, v = face.Surface.parameter(p)
    return face.Surface.value(u, v), face.normalAt(u, v)


def visible_faces(parts, solids, top):
    """Each part's faces that can be seen: not with material on both sides (the insert's pocket, the
    hosel top under the extension), not the shaft bore."""
    inside = lambda q: any(s.isInside(q, 1e-4, False) for s in solids)
    out, hidden = {}, 0
    for name, shape in parts.items():
        keep = []
        for f in shape.Faces:
            p, n = sample(f)
            w = p - top
            radial = (w - AXIS * w.dot(AXIS)).Length
            if isinstance(f.Surface, Part.Cylinder) and abs(radial - BORE_R) < 0.05:
                hidden += 1
                continue
            if inside(p + n * 0.05) and inside(p - n * 0.05):
                hidden += 1
                continue
            keep.append(f)
        out[name] = keep
    return out, hidden


def mesh(faces, deflection):
    """Points and triangles (numpy) of a list of faces."""
    import numpy as np
    m = MeshPart.meshFromShape(Shape=Part.makeCompound(faces), LinearDeflection=deflection[0],
                               AngularDeflection=deflection[1], Relative=False)
    pts, tris = m.Topology
    return np.array([(p.x, p.y, p.z) for p in pts]), np.array(tris, dtype=np.int64)


def creased(points, tris, crease=CREASE):
    """Per-corner normals: the area-weighted normals of the triangles round each vertex that lie
    within `crease` degrees of the corner's own triangle (sharp edges stay sharp). Returns welded
    (positions, normals, triangles)."""
    import numpy as np
    a, b, c = points[tris[:, 0]], points[tris[:, 1]], points[tris[:, 2]]
    fn = np.cross(b - a, c - a)                       # area-weighted
    fu = fn / np.maximum(np.linalg.norm(fn, axis=1), 1e-12)[:, None]
    cos = math.cos(math.radians(crease))
    corner_v = tris.reshape(-1)
    corner_t = np.repeat(np.arange(len(tris)), 3)
    order = np.argsort(corner_v, kind="stable")
    sv, st = corner_v[order], corner_t[order]
    starts = np.flatnonzero(np.r_[True, sv[1:] != sv[:-1]])
    ends = np.r_[starts[1:], len(sv)]
    corner_n = np.zeros((len(corner_v), 3))
    for s, e in zip(starts, ends):
        ts = st[s:e]
        dots = fu[ts] @ fu[ts].T
        nsum = (dots >= cos).astype(float) @ fn[ts]
        corner_n[order[s:e]] = nsum / np.maximum(np.linalg.norm(nsum, axis=1), 1e-12)[:, None]
    key = np.c_[corner_v, np.round(corner_n * 2000).astype(np.int64)]
    uniq, inv = np.unique(key, axis=0, return_inverse=True)
    inv = inv.reshape(-1)
    pos = points[uniq[:, 0]]
    nrm = np.zeros((len(uniq), 3))
    nrm[inv] = corner_n
    return pos, nrm, inv.reshape(-1, 3)


def zone_fields(pos, sphere_c, sphere_r, top):
    """Fields over the body (mm): "face" < 0 on the flat face (on the face sphere), "metal" < 0 on
    the metal frame (within RIM behind the face's edge, or the hosel above the heel), "part" > 0
    above the crown/sole parting line."""
    import numpy as np
    dx, dz = pos[:, 0] - sphere_c.x, pos[:, 2] - sphere_c.z
    face_y = sphere_c.y - np.sqrt(np.maximum(sphere_r ** 2 - dx * dx - dz * dz, 0.0))
    a = np.array([AXIS.x, AXIS.y, AXIS.z])
    w = pos - np.array([top.x, top.y, top.z])
    radial = np.linalg.norm(w - np.outer(w @ a, a), axis=1)
    hosel = np.maximum(radial - HOSEL_ZONE, 28.0 - pos[:, 2])
    behind = pos[:, 1] - face_y
    return {"face": behind - FLAT, "metal": np.minimum(behind - RIM, hosel), "part": pos[:, 2] - Z_PART}


def split_along(pos, nrm, tris, f):
    """Cut every triangle the zero line of the per-vertex field f crosses, exactly along it (new
    vertices shared between neighbours), so zone boundaries are smooth lines, not triangle edges."""
    import numpy as np
    s = f > 0
    cross = np.flatnonzero((s[tris[:, 0]] != s[tris[:, 1]]) | (s[tris[:, 1]] != s[tris[:, 2]]))
    if len(cross) == 0:
        return pos, nrm, tris
    pos, nrm = list(map(tuple, pos)), list(map(tuple, nrm))
    cache = {}

    def cut(i, j):
        key = (min(i, j), max(i, j))
        if key not in cache:
            t = f[i] / (f[i] - f[j])
            p = tuple(pos[i][k] + (pos[j][k] - pos[i][k]) * t for k in range(3))
            n = tuple(nrm[i][k] + (nrm[j][k] - nrm[i][k]) * t for k in range(3))
            ln = math.sqrt(sum(c * c for c in n)) or 1.0
            pos.append(p)
            nrm.append(tuple(c / ln for c in n))
            cache[key] = len(pos) - 1
        return cache[key]

    keep = np.ones(len(tris), dtype=bool)
    keep[cross] = False
    new = []
    for t in cross:
        a, b, c = tris[t]
        # rotate so the vertex alone on its side comes first (cyclic order keeps the winding)
        if s[a] == s[b]:
            a, b, c = c, a, b
        elif s[a] == s[c]:
            a, b, c = b, c, a
        pab, pac = cut(a, b), cut(a, c)
        new += [(a, pab, pac), (pab, b, c), (pab, c, pac)]
    return np.array(pos), np.array(nrm), np.vstack([tris[keep], np.array(new, dtype=np.int64)])


def body_slots(pos, nrm, tris, sphere_c, sphere_r, top):
    """Cut the body along the zone boundaries; returns (pos, nrm, tris, slot per triangle)."""
    import numpy as np
    for key in ("face", "metal", "part"):
        f = zone_fields(pos, sphere_c, sphere_r, top)[key]
        f = np.where(np.abs(f) < 1e-6, 1e-6, f)  # no vertex exactly on a boundary
        pos, nrm, tris = split_along(pos, nrm, tris, f)
    cen = (pos[tris[:, 0]] + pos[tris[:, 1]] + pos[tris[:, 2]]) / 3.0
    z = zone_fields(cen, sphere_c, sphere_r, top)
    slot = np.where(z["face"] < 0, "face", np.where(z["metal"] < 0, "metal",
                                                     np.where(z["part"] > 0, "crown", "sole")))
    return pos, nrm, tris, slot


def export(out_dir=OUT_DIR):
    import numpy as np
    hy = module(HYBRID_EXPORT, "SPORT_HYBRID_NO_MAIN")
    h2 = module(EXPORT_2U, "UTILITY_2U_NO_MAIN")
    tex = json.load(open(os.path.join(TEXTURES, "textures.json")))
    x0, x1, y0, y1 = tex["box_mm"]
    parts = load_parts()
    top, ferrule_top = hosel_top(parts["Ferrule"])
    sphere = next(f.Surface for f in parts["FaceInsert"].Faces if isinstance(f.Surface, Part.Sphere))
    # lengthen the hosel under the ferrule: the mouth (the ferrule's top) MOUTH_Z above the sole
    grow = (MOUTH_Z - ferrule_top.z) / AXIS.z
    report = ["ferrule top %.1f mm above the sole -> hosel %+.1f mm along the shaft" % (ferrule_top.z, grow)]
    r_top = min((c.Radius for c in map(circle, parts["Body"].Edges) if c is not None
                 and (c.Center - top).Length < 0.5 and c.Radius > BORE_R + 0.5), default=6.6)
    solids = [s for p in parts.values() for s in p.Solids]
    if grow > 0.01:
        ext = Part.makeCylinder(r_top, grow, top, AXIS)
        solids.append(ext)
        parts["HoselExt"] = Part.makeCompound([f for f in ext.Faces if isinstance(f.Surface, Part.Cylinder)])
        parts["Ferrule"] = parts["Ferrule"].translated(AXIS * grow)
    elif grow < -0.01:  # cut the hosel back under the ferrule, which moves down with it
        top = top + AXIS * grow
        parts["Body"] = parts["Body"].cut(Part.makeCylinder(40.0, 80.0, top, AXIS))
        # ... remade to the hosel's size where it is now cut (it is thicker lower down: the ferrule's foot
        # stood in from the hosel, a step, and the hosel read too thin for it)
        fer = parts["Ferrule"].translated(AXIS * grow)
        length = max((v.Point - top).dot(AXIS) for v in fer.Vertexes)
        rim = []
        for e in parts["Body"].Edges:
            if e.Length < 1e-4 or abs((e.BoundBox.Center - top).dot(AXIS)) > 1.0:
                continue
            try:  # (degenerate edges, like the toe tip's, cannot be sampled)
                pts = e.discretize(36)
            except Exception:
                continue
            if all(abs((q - top).dot(AXIS)) < 1e-3 for q in pts):
                rim += pts
        radial = [((p - top) - AXIS * (p - top).dot(AXIS)).Length for p in rim]
        r_cut = max(radial) if radial else None
        if r_cut and r_cut > BORE_R + 1.0:
            cone = Part.makeCone(r_cut, r_cut - 1.5, length, top, AXIS)
            parts["Ferrule"] = cone.cut(Part.makeCylinder(BORE_R, length + 2.0, top - AXIS, AXIS))
            report.append("ferrule remade to the hosel at the cut: foot radius %.2f mm" % r_cut)
        else:
            parts["Ferrule"] = fer
        solids = [s for p in parts.values() for s in p.Solids]
    mouth = ferrule_top + AXIS * grow
    faces, hidden = visible_faces({k: v for k, v in parts.items() if k != "HoselExt"}, solids, top)
    if "HoselExt" in parts:
        faces["HoselExt"] = parts["HoselExt"].Faces
    report.append("%d hidden faces dropped" % hidden)

    # skin frame: +Y up the shaft, X across it toward the heel, Z toward the target (the face)
    X = V(AXIS.z, 0.0, -AXIS.x)
    Z = X.cross(AXIS)
    M = np.array([[X.x, X.y, X.z], [AXIS.x, AXIS.y, AXIS.z], [Z.x, Z.y, Z.z]])
    m0 = np.array([mouth.x, mouth.y, mouth.z])

    geo = {}  # slot -> list of (pos mm model, nrm, tris)
    for name, fs in faces.items():
        if not fs:
            continue
        pts, tris = mesh(fs, DEFLECTION[name])
        pos, nrm, tri = creased(pts, tris)
        if name == "Body":
            pos, nrm, tri, slot = body_slots(pos, nrm, tri, sphere.Center, sphere.Radius, top)
            for s in ("face", "crown", "sole", "metal"):
                sel = tri[slot == s]
                used = np.unique(sel)
                remap = -np.ones(len(pos), dtype=np.int64)
                remap[used] = np.arange(len(used))
                geo.setdefault(s, []).append((pos[used], nrm[used], remap[sel]))
        else:
            geo.setdefault(PART_SLOT[name], []).append((pos, nrm, tri))
        report.append("%s: %d triangles" % (name, len(tri)))

    def uv_for(slot, p):
        if slot in ("crown", "sole"):
            return np.c_[(p[:, 0] - x0) / (x1 - x0), (p[:, 1] - y0) / (y1 - y0)]
        return np.c_[p[:, 0] * UV_METAL, p[:, 2] * UV_METAL]  # planar, the grain heel to toe

    images = {"brushed": (h2["brushed_map"](), 10497)}
    for skin_club, livery in LIVERIES.items():
        for key in ("crown", "sole"):
            for kind, suffix in (("", "_base"), ("_rough", "_rough")):
                with open(os.path.join(TEXTURES, tex[skin_club][key + kind]), "rb") as f:
                    images["%s_%s%s" % (skin_club, key, suffix)] = (f.read(), 33071)
    for club, livery in LIVERIES.items():
        meshes = []
        by_finish = {}  # slots sharing a finish (the insert and the rest of the flat face) share a mesh
        for slot, fin in sorted(livery.items()):
            for chunk in geo.get(slot, []):
                by_finish.setdefault(fin, []).append((slot, chunk))
        for fin, chunks in sorted(by_finish.items()):
            spec = FINISHES[fin]
            pos, nrm, uv, idx = [], [], [], []
            for slot, (p, n, t) in chunks:
                base = len(pos) // 3
                gp = (p - m0) @ M.T * 0.001
                gn = n @ M.T
                pos += gp.reshape(-1).tolist()
                nrm += gn.reshape(-1).tolist()
                uv += uv_for(slot, p).reshape(-1).tolist()
                idx += (t.reshape(-1) + base).tolist()
            tkey = spec.get("tex")
            mat = {"name": "ofg_%s%s__%s" % (club, SKIN_SUFFIX, fin), "base": hy["linear"](spec["base"]),
                   "metallic": spec["metallic"], "roughness": spec["roughness"],
                   "base_tex": "%s_%s_base" % (club, tkey) if tkey else None,
                   "mr_tex": "%s_%s_rough" % (club, tkey) if tkey else spec.get("mr")}
            node = "%s%s_%s" % ("".join(w.capitalize() for w in club.split("_")), SKIN_SUFFIX.strip("_").upper(),
                                  "".join(w.capitalize() for w in fin.split("_")))
            meshes.append((node, mat, pos, nrm, uv, idx))
        path = os.path.join(out_dir, club + SKIN_SUFFIX + "_base.glb")
        hy["write_glb"](path, meshes, images)
        report.append("wrote %s (%d meshes, %.1f MB)" % (path, len(meshes), os.path.getsize(path) / 1e6))
    return report


if os.environ.get("DRIVER_EXPORT_NO_MAIN") != "1":
    print("\n".join(export()))
