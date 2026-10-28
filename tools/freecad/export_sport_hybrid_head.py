"""Export the Sport Hybrid 21 head (FreeCAD) as the game's hybrid heads, one livery per club.

Source: assets/Sport_Hybrid_21_Head/Sport_Hybrid_21.FCStd, Codex's head (build_sport_hybrid.py beside
it) with its parts painted face by face in FreeCAD. Those colours mark which part of the head each
face is (the white ring on top of the face, the black ring under it, the carbon face and hosel); the
look of each club comes from LIVERIES below, with the textures from tools/make_sport_hybrid_textures.py
(assets/Sport_Hybrid_21_Head/textures/).

Writes assets/Selected_Club_Heads/skins/<skin>_base.glb for every livery, in the 2U skin's frame
(tools/freecad/export_utility_2u_head.py, whose tessellation this reuses): metres, origin at the centre
of the hosel mouth (the top of the ferrule), +Y up the shaft, toe -X, face +Z, a right-handed club;
OFGEquipmentAssets.HEAD_OVERRIDES maps each club to its skin (and so to the 2U's face flip). Codex drew
the head left-handed (toe +X), so it is mirrored first. The hosel is lengthened (or shortened) under
the ferrule, which moves with it, so the mouth sits MOUTH_Z above the sole at the 60 degree lie.
Run inside FreeCAD (a macro, the FreeCAD MCP, or freecadcmd):
    exec(open(r"C:/Users/willi/Documents/GolfGame/tools/freecad/export_sport_hybrid_head.py").read())
then let Godot re-import:  godot --headless --path . --import
"""
import array
import json
import os
import re
import struct
import zipfile

import FreeCAD as App
import Part
from FreeCAD import Vector as V

GAME = r"C:/Users/willi/Documents/GolfGame"
HEAD_DIR = os.path.join(GAME, "assets", "Sport_Hybrid_21_Head")
SOURCE = os.environ.get("SPORT_HYBRID_FCSTD", os.path.join(HEAD_DIR, "Sport_Hybrid_21.FCStd"))
TEXTURES = os.environ.get("SPORT_HYBRID_TEX_DIR", os.path.join(HEAD_DIR, "textures"))
OUT_DIR = os.environ.get("SPORT_HYBRID_OUT_DIR", os.path.join(GAME, "assets", "Selected_Club_Heads", "skins"))
EXPORT_2U = os.path.join(GAME, "tools", "freecad", "export_utility_2u_head.py")
# mm above the sole at the 60 degree lie: seats the head like the stock hybrid heads in the swing rig
# (sole ~2 mm above the turf at address, measured); Codex's own hosel puts it at 55.5
MOUTH_Z = float(os.environ.get("SPORT_HYBRID_MOUTH_Z", "58.4"))
PARTS = ["SatinSilverFrame", "BlackCrown", "GraphiteSole", "BlackFerrule", "BlueSoleRailHeel",
         "BlueSoleRailToe", "RearWeight", "ScrewSeat", "ScrewDriveRecess", "AlignmentChevron"]
PART_SLOT = {"BlackCrown": "crown", "GraphiteSole": "sole", "AlignmentChevron": "arrow", "BlueSoleRailHeel": "rails",
             "BlueSoleRailToe": "rails", "RearWeight": "screw", "ScrewSeat": "screw_seat",
             "ScrewDriveRecess": "drive_recess", "BlackFerrule": "ferrule"}
# the face/ring/hosel part's colours in the document -> its slots
FRAME_COLOURS = {"carbon": (0.09, 0.094, 0.106), "jet": (0.008, 0.008, 0.012), "white": (0.929, 0.929, 0.941)}

# finish: base colour (sRGB; white under a texture), metallic, roughness, base texture ("tex", a key of
# textures.json), metallic-roughness texture ("mr": "brushed", else the texture's *_rough.png), and the
# UV projection: "face" (planar across the face, the brushed grain heel to toe), "top" (from above,
# tiling at the texture's real size) or "sole_fit" (from above, one image over the whole sole)
FINISHES = {
    "carbon_face": dict(base=(0.11, 0.115, 0.125), metallic=0.55, roughness=0.40, mr="brushed", uv="face"),
    "steel_face": dict(base=(0.52, 0.55, 0.58), metallic=0.9, roughness=0.42, mr="brushed", uv="face"),
    "score_white": dict(base=(0.86, 0.87, 0.88), metallic=0.0, roughness=0.38),
    "score_dark": dict(base=(0.10, 0.105, 0.11), metallic=0.0, roughness=0.50),
    "white_paint": dict(base=(0.93, 0.93, 0.94), metallic=0.0, roughness=0.22),
    "silver_trim": dict(base=(0.80, 0.83, 0.85), metallic=0.85, roughness=0.30),
    "jet_black_paint": dict(base=(0.012, 0.012, 0.014), metallic=0.0, roughness=0.14),
    "graphite_paint": dict(base=(0.17, 0.185, 0.20), metallic=0.2, roughness=0.45),
    "hex_crown": dict(base=(1.0, 1.0, 1.0), metallic=0.0, roughness=1.0, tex="hex_crown", uv="top"),
    "slate_flake": dict(base=(1.0, 1.0, 1.0), metallic=1.0, roughness=1.0, tex="slate_flake", uv="top"),
    "cloud_sole": dict(base=(1.0, 1.0, 1.0), metallic=0.0, roughness=1.0, tex="cloud_sole", uv="sole_fit"),
    "rookie_sole": dict(base=(1.0, 1.0, 1.0), metallic=0.0, roughness=1.0, tex="rookie_sole", uv="sole_fit"),
    "blue_paint": dict(base=(0.016, 0.42, 0.722), metallic=0.0, roughness=0.30),
    "trim_paint": dict(base=(0.81, 0.84, 0.86), metallic=0.0, roughness=0.35),
    "screw_steel": dict(base=(0.62, 0.65, 0.68), metallic=0.95, roughness=0.28),
    "screw_seat": dict(base=(0.05, 0.055, 0.065), metallic=0.4, roughness=0.45),
    "drive_recess": dict(base=(0.02, 0.02, 0.025), metallic=0.0, roughness=0.60),
    "ferrule": dict(base=(0.02, 0.02, 0.025), metallic=0.0, roughness=0.35),
}
_COMMON = {"arrow": "jet_black_paint", "screw": "screw_steel", "screw_seat": "screw_seat",
           "drive_recess": "drive_recess", "ferrule": "ferrule"}
LIVERIES = {
    # Cloudcutter 4H (uncommon; finish 355a7a, accent dbe6f0): the head as the user painted it, a SIM-style
    # rescue -- carbon face and hosel with white score lines, gloss jet-black hex-cell crown, white ring on
    # top of the face (black below), jet-black sole with blue rails and a white 22 degree loft by the toe,
    # black alignment arrow
    "cloudcutter_4h_sport": dict(_COMMON, face="carbon_face", hosel="carbon_face", score_line="score_white",
                                 ring_top="white_paint", ring_bottom="jet_black_paint", crown="hex_crown",
                                 sole="cloud_sole", rails="blue_paint"),
    # Rescue Rookie 3H (common; finish 3d4a55, accent cfd6db): plain and practical -- brushed steel face
    # and hosel, slate metallic-flake crown, light-grey trim ring and rails, graphite sole wearing its
    # tell, the 21 degree loft on a half-peeled sticker by the toe
    "rescue_rookie_sport": dict(_COMMON, face="steel_face", hosel="steel_face", score_line="score_dark",
                                ring_top="silver_trim", ring_bottom="graphite_paint", crown="slate_flake",
                                sole="rookie_sole", rails="trim_paint"),
}


def helpers():
    """The 2U exporter's tessellation, head frame and brushed roughness map."""
    os.environ["UTILITY_2U_NO_MAIN"] = "1"
    ns = {"__name__": "export_utility_2u_head"}
    with open(EXPORT_2U, encoding="utf-8") as f:
        exec(f.read(), ns)
    return ns


def codex_constants():
    os.environ["HYBRID_NO_MAIN"] = "1"
    ns = {"__name__": "build_sport_hybrid"}
    with open(os.path.join(HEAD_DIR, "build_sport_hybrid.py"), encoding="utf-8") as f:
        exec(f.read(), ns)
    return ns


def face_colours(path):
    """{part: [sRGB diffuse per face]} from the document's ShapeAppearance files (24-byte records:
    ambient, diffuse, specular, emissive as 0xRRGGBBAA, shininess, transparency)."""
    z = zipfile.ZipFile(path)
    gui = z.read("GuiDocument.xml").decode("utf-8")
    out = {}
    for name in PARTS:
        vp = re.search(r'<ViewProvider name="%s".*?</ViewProvider>' % re.escape(name), gui, re.S).group(0)
        raw = z.read(re.search(r'name="ShapeAppearance".*?file="([^"]+)"', vp, re.S).group(1))
        count = struct.unpack("<I", raw[:4])[0]
        colours = []
        for i in range(count):
            packed = struct.unpack("<I", raw[4 + 24 * i + 4:4 + 24 * i + 8])[0]
            colours.append(tuple(((packed >> s) & 255) / 255.0 for s in (24, 16, 8)))
        out[name] = colours
    return out


def slot_of(part, face, colour):
    """Which part of the head a face is (Codex's left-handed coordinates: +X toe, -Y face)."""
    if part != "SatinSilverFrame":
        return PART_SLOT[part]
    kind = min(FRAME_COLOURS, key=lambda k: sum((a - b) ** 2 for a, b in zip(colour, FRAME_COLOURS[k])))
    if kind == "white":
        return "ring_top"
    if kind == "jet":
        return "ring_bottom"
    c = face.CenterOfMass
    if isinstance(face.Surface, Part.Plane) and face.Area < 20 and -34 <= c.x <= 34 and -17.5 <= c.y <= -8:
        return "score_line"
    return "hosel" if c.x < -38 else "face"


def sample(face):
    """A point on the face and the outward normal there."""
    pts, tris = face.tessellate(0.2)
    if tris:
        a, b, c = tris[0]
        p = (pts[a] + pts[b] + pts[c]) * (1.0 / 3.0)
    else:  # a sliver too small to tessellate
        p = face.CenterOfMass
    u, v = face.Surface.parameter(p)
    return face.Surface.value(u, v), face.normalAt(u, v)


def linear(c):
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def head_geometry(h, k):
    """{slot: (pos, nrm, idx)} in the skin frame, plus the mouth and shaft axis (model mm)."""
    colours = face_colours(SOURCE)
    doc = App.openDocument(SOURCE)
    parts = {n: doc.getObject(n).Shape.copy() for n in PARTS}
    App.closeDocument(doc.Name)
    slots = {}
    for n, s in parts.items():
        cols = colours[n] * len(s.Faces) if len(colours[n]) == 1 else colours[n]
        if len(cols) != len(s.Faces):
            raise RuntimeError("%s: %d colours for %d faces" % (n, len(cols), len(s.Faces)))
        slots[n] = [slot_of(n, f, c) for f, c in zip(s.Faces, cols)]
    # right-handed: mirror (the mirror keeps the face order)
    flip = lambda p: V(-p.x, p.y, p.z)
    parts = {n: s.mirror(V(0, 0, 0), V(1, 0, 0)) for n, s in parts.items()}
    axis, neck, mouth = flip(k["AXIS"]), flip(k["NECKBASE"]), flip(k["MOUTH"])

    # put the mouth MOUTH_Z above the sole: grow (or cut back) the hosel under the ferrule, which moves too
    ground = min(parts[n].optimalBoundingBox().ZMin for n in ("SatinSilverFrame", "BlackCrown", "GraphiteSole"))
    down = (mouth.z - ground - MOUTH_Z) / axis.z
    report = ["sole at z %.2f, Codex's mouth %.2f mm above it -> hosel %+.2f mm along the shaft" % (
        ground, mouth.z - ground, -down)]
    old, old_slots = parts["SatinSilverFrame"], slots["SatinSilverFrame"]
    if down > 0.0:
        foot = neck + axis * (k["FERRULE_AT"] - down)
        frame = old.common(Part.makeCylinder(400.0, 800.0, foot - axis * 800.0, axis))
    else:
        start = neck + axis * k["FERRULE_AT"]
        grow = Part.makeCylinder(k["HOSEL_R"], -down, start, axis).cut(
            Part.makeCylinder(k["BORE_R"], 2.0 - down, start - axis, axis))
        # only into the solid that carries the hosel: the frame is two solids seamed where the ring
        # turns from white to black, and fusing the whole part would weld that seam away
        sols = old.Solids
        host = min(range(len(sols)), key=lambda i: sols[i].distToShape(Part.Vertex(start))[0])
        frame = Part.makeCompound([sols[i].fuse(grow).removeSplitter() if i == host else sols[i]
                                   for i in range(len(sols))])
    if not frame.isValid() or len(frame.Solids) != len(old.Solids):
        raise RuntimeError("hosel edit broke the frame: valid %s, solids %d" % (frame.isValid(), len(frame.Solids)))
    slots["SatinSilverFrame"] = []
    for f in frame.Faces:  # each face keeps the slot of the face it was cut from
        p, _ = sample(f)
        src = min(range(len(old.Faces)), key=lambda i: old.Faces[i].distToShape(Part.Vertex(p))[0])
        slots["SatinSilverFrame"].append(old_slots[src])
    parts["SatinSilverFrame"] = frame
    parts["BlackFerrule"] = parts["BlackFerrule"].translated(-axis * down)
    mouth = mouth - axis * down

    # drop faces with material on both sides (the frame's back and seam faces, the hosel's top under
    # the ferrule, ...): never seen, and coincident with another part's face
    solids = [sol for s in parts.values() for sol in s.Solids]
    inside = lambda q: any(sol.isInside(q, 1e-4, False) for sol in solids)
    by_slot, hidden = {}, 0
    for n, s in parts.items():
        for f, slot in zip(s.Faces, slots[n]):
            p, nv = sample(f)
            if inside(p + nv * 0.05) and inside(p - nv * 0.05):
                hidden += 1
                continue
            by_slot.setdefault(slot, []).append(f)
    report.append("%d hidden faces dropped" % hidden)
    point, normal, _ = h["head_frame"](mouth, axis)
    geo = {}
    for slot, faces in by_slot.items():
        pos, nrm, _, idx = h["mesh_part"](Part.makeCompound(faces), point, normal, lambda gp: (0.0, 0.0))
        geo[slot] = (pos, nrm, idx)
        report.append("%s: %d faces, %d triangles" % (slot, len(faces), len(idx) // 3))
    return geo, mouth, axis, report


def uv_maker(h, mouth, axis, tex):
    """UV function for a finish, on skin-frame points (metres)."""
    x = V(axis.z, 0.0, -axis.x)
    z = x.cross(axis)

    def model(gp):  # skin frame (m) -> model mm
        return mouth + (x * gp[0] + axis * gp[1] + z * gp[2]) * 1000.0
    _, _, face_uv = h["head_frame"](mouth, axis)

    def make(fin):
        mode = FINISHES[fin].get("uv", "face")
        if mode == "top":
            tw, th = tex[FINISHES[fin]["tex"]]["tile_mm"]
            return lambda gp: (model(gp).x / tw, model(gp).y / th)
        if mode == "sole_fit":
            x0, x1, y0, y1 = tex[FINISHES[fin]["tex"]]["sole_mm"]
            return lambda gp: ((model(gp).x - x0) / (x1 - x0), (model(gp).y - y0) / (y1 - y0))
        return face_uv
    return make


def write_glb(path, meshes, images):
    """meshes: [(node, material dict, pos, nrm, uv, idx)]; material: name, base (linear rgb), metallic,
    roughness, base_tex / mr_tex (keys into images: {key: (png bytes, wrap mode)}). A "ShaftSocket"
    node marks the hosel mouth (the origin) for OFGEquipmentAssets._find_attachment_marker()."""
    blob = bytearray()
    views, accessors, gl_images, samplers, textures, tex_index = [], [], [], [], [], {}

    def pad():
        while len(blob) % 4:
            blob.append(0)

    def view(data, target=None):
        pad()
        v = {"buffer": 0, "byteOffset": len(blob), "byteLength": len(data)}
        if target:
            v["target"] = target
        views.append(v)
        blob.extend(data)
        return len(views) - 1

    def accessor(values, count, kind, ctype, target, bounds=False):
        acc = {"bufferView": view(array.array("I" if ctype == 5125 else "f", values).tobytes(), target),
               "componentType": ctype, "count": count, "type": kind}
        if bounds:
            n = {"VEC3": 3, "VEC2": 2}[kind]
            acc["min"] = [min(values[i::n]) for i in range(n)]
            acc["max"] = [max(values[i::n]) for i in range(n)]
        accessors.append(acc)
        return len(accessors) - 1

    def texture(key):
        if key not in tex_index:
            png, wrap = images[key]
            gl_images.append({"name": key, "mimeType": "image/png", "bufferView": view(png)})
            samplers.append({"magFilter": 9729, "minFilter": 9987, "wrapS": wrap, "wrapT": wrap})
            textures.append({"sampler": len(samplers) - 1, "source": len(gl_images) - 1})
            tex_index[key] = len(textures) - 1
        return tex_index[key]

    nodes, gl_meshes, materials = [], [], []
    for node, mat, pos, nrm, uv, idx in meshes:
        n = len(pos) // 3
        prim = {"attributes": {"POSITION": accessor(pos, n, "VEC3", 5126, 34962, True),
                               "NORMAL": accessor(nrm, n, "VEC3", 5126, 34962),
                               "TEXCOORD_0": accessor(uv, n, "VEC2", 5126, 34962)},
                "indices": accessor(idx, len(idx), "SCALAR", 5125, 34963), "material": len(materials)}
        pbr = {"baseColorFactor": list(mat["base"]) + [1.0], "metallicFactor": mat["metallic"],
               "roughnessFactor": mat["roughness"]}
        if mat.get("base_tex"):
            pbr["baseColorTexture"] = {"index": texture(mat["base_tex"]), "texCoord": 0}
        if mat.get("mr_tex"):
            pbr["metallicRoughnessTexture"] = {"index": texture(mat["mr_tex"]), "texCoord": 0}
        materials.append({"name": mat["name"], "doubleSided": False, "pbrMetallicRoughness": pbr})
        gl_meshes.append({"name": node, "primitives": [prim]})
        nodes.append({"name": node, "mesh": len(gl_meshes) - 1})
    nodes.append({"name": "ShaftSocket"})
    doc = {"asset": {"version": "2.0", "generator": "export_sport_hybrid_head.py (FreeCAD)"},
           "scene": 0, "scenes": [{"name": "Scene", "nodes": list(range(len(nodes)))}],
           "nodes": nodes, "meshes": gl_meshes, "materials": materials}
    if gl_images:
        doc.update({"images": gl_images, "samplers": samplers, "textures": textures})
    pad()
    doc.update({"accessors": accessors, "bufferViews": views, "buffers": [{"byteLength": len(blob)}]})
    js = json.dumps(doc, separators=(",", ":")).encode("utf-8")
    js += b" " * ((-len(js)) % 4)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(blob), 0x004E4942) + bytes(blob))


def export(out_dir=OUT_DIR):
    h, k = helpers(), codex_constants()
    with open(os.path.join(TEXTURES, "textures.json")) as f:
        tex = json.load(f)
    geo, mouth, axis, report = head_geometry(h, k)
    uv_for = uv_maker(h, mouth, axis, tex)
    images = {"brushed": (h["brushed_map"](), 10497)}
    for key, t in tex.items():
        wrap = 33071 if "sole_mm" in t else 10497  # the one-off sole art is clamped, patterns repeat
        for kind in ("base", "rough"):
            with open(os.path.join(TEXTURES, t[kind]), "rb") as f:
                images["%s_%s" % (key, kind)] = (f.read(), wrap)
    for skin, livery in LIVERIES.items():
        by_finish = {}
        for slot, fin in livery.items():
            if slot in geo:
                by_finish.setdefault(fin, []).append(geo[slot])
        meshes = []
        for fin, chunks in sorted(by_finish.items()):
            spec = FINISHES[fin]
            uv_of = uv_for(fin)
            pos, nrm, uv, idx = [], [], [], []
            for p, n, i in chunks:
                base = len(pos) // 3
                pos += p
                nrm += n
                idx += [base + j for j in i]
                for j in range(0, len(p), 3):
                    uv += uv_of((p[j], p[j + 1], p[j + 2]))
            mr = spec.get("mr") or (spec["tex"] + "_rough" if spec.get("tex") else None)
            mat = {"name": "ofg_%s__%s" % (skin, fin), "base": linear(spec["base"]), "metallic": spec["metallic"],
                   "roughness": spec["roughness"], "base_tex": spec["tex"] + "_base" if spec.get("tex") else None,
                   "mr_tex": mr}
            node = "%s_%s" % ("".join(w.capitalize() for w in skin.split("_")),
                              "".join(w.capitalize() for w in fin.split("_")))
            meshes.append((node, mat, pos, nrm, uv, idx))
        path = os.path.join(out_dir, skin + "_base.glb")
        write_glb(path, meshes, images)
        report.append("wrote %s (%d meshes)" % (path, len(meshes)))
    return report


if os.environ.get("SPORT_HYBRID_NO_MAIN") != "1":
    print("\n".join(export()))
