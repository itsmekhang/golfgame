"""Export the FreeCAD utility iron head as the game's Utility Iron 2U skin.

The head is the parametric model in C:/Users/willi/Documents/FreeCAD/GolfHead/irons/build_irons.py ("2u");
this rebuilds it and writes assets/Selected_Club_Heads/skins/utility_2u_iron_base.glb.
Run inside FreeCAD (a macro, the FreeCAD MCP, or freecadcmd):
    exec(open(r"C:/Users/willi/Documents/GolfGame/tools/freecad/export_utility_2u_head.py").read())
then let Godot re-import it and re-render the shop photo:
    godot --headless --path . --import
    godot --path . --script tools/render_shop_thumbnails.gd -- --models=utility_2u

Frame, as the iron skins and the earlier (Blender) 2U head: metres, origin at the centre of the
hosel mouth, +Y up the shaft, toe toward -X, face toward +Z (a right-handed club).
OFGEquipmentAssets._swap_head() puts that origin on the catalog club's shaft tip, turns +Y onto
the shaft and spins the head 180 degrees about it (the iron face flip).

The hosel is trimmed to MOUTH_Z above the sole, the earlier 2U head's mouth height, so the club
keeps its length and the swing rig's ball contact (the rig places the club by its original
geometry); the ferrule moves down with it. The head itself is the approved model.
"""
import array
import json
import math
import os
import random
import struct
import zlib

import Part
from FreeCAD import Vector as V

HEAD_SCRIPT = r"C:/Users/willi/Documents/FreeCAD/GolfHead/irons/build_irons.py"  # the iron family, as "2u"
OUT = os.environ.get(
    "UTILITY_2U_GLB",
    r"C:/Users/willi/Documents/GolfGame/assets/Selected_Club_Heads/skins/utility_2u_iron_base.glb")
MOUTH_Z = 55.8        # mm: hosel mouth height above the sole at a 60 degree lie (the old 2U head's sole, in the swing rig)
RIM_CHAMFER = 0.5     # mm, on the trimmed hosel's outer rim
TOLERANCE = 0.04      # mm: tessellation chord deviation (~80k body triangles; true normals keep
                      # it smooth, 0.01 made 320k)
UV_PER_M = 20.0       # condition wear mask repeats every 5 cm (planar, across the face/back)

BRUSH_SIZE = 256      # the body's brushed-satin roughness map (tiles; streaks run along U = heel-toe)

# The brand mark on the back (an invented maker, VELMOR; art by tools/make_utility_2u_brand.py):
# a thin layer over the body's own back triangles inside BRAND_RECT, so it follows the curved
# back. BRAND_RECT is in mm in the back-projection frame (u = heel -> toe, v = up, both measured
# square to the back's mean normal); keep it in step with the art script. Only the back carries
# it: the face, sole and top line face away from that projection.
BRAND_PNG = os.path.join(os.path.dirname(OUT), "utility_2u_iron_brand.png")
BRAND_RECT = (20.0, 21.0, 74.0, 35.98)  # u0, v0, u1, v1
DECAL_LIFT = 0.05e-3  # m off the back, along the surface normals
DECAL_FACING = 0.6    # only triangles this square to the projection take the decal

# part: (node, material, base colour, metallic, roughness). The body keeps the earlier head's
# satin finish (its roughness, 0.36 on average, comes from the brushed map below); the stamp
# fill, plug and ferrule are the dark accents.
PARTS = {
    "Body": ("UtilityIron2U_Body", "ofg_utility_2u__satin_body", (0.80, 0.81, 0.83), 0.90, 0.42),
    "PortPlug": ("UtilityIron2U_WeightPlug", "ofg_utility_2u__weight_plug", (0.09, 0.09, 0.10), 0.85, 0.32),
    "MarkFill": ("UtilityIron2U_LoftStamp", "ofg_utility_2u__paint_fill", (0.025, 0.026, 0.028), 0.0, 0.45),
    "Ferrule": ("UtilityIron2U_Ferrule", "ofg_utility_2u__ferrule", (0.02, 0.02, 0.022), 0.0, 0.35),
}


def build_head():
    os.environ["GOLFHEAD_NO_MAIN"] = "1"
    os.environ["IRON_VARIANT"] = "2u"  # the 2U's back: a muscle line straight into the neck, no heel dent
    ns = {"__name__": "golfhead"}
    with open(HEAD_SCRIPT, encoding="utf-8") as f:
        exec(f.read(), ns)
    parts, info = ns["build"]()
    return ns, parts, info


def trim_hosel(ns, parts, info):
    """Cut the hosel square to its axis at MOUTH_Z, chamfer the new rim, seat the ferrule on it."""
    lh = ns["AXIS"]
    axis = V(-lh.x, lh.y, lh.z)  # the model is mirrored right-handed at the end of build()
    top = info["top"]
    down = (top.z - MOUTH_Z) / axis.z
    mouth = top - axis * down
    body = parts["Body"].common(Part.makeCylinder(400.0, 800.0, mouth - axis * 800.0, axis))

    def on_rim(e):
        pts = e.discretize(6)
        return (all(abs((p - mouth).dot(axis)) < 1e-4 for p in pts)
                and min((p - mouth).Length for p in pts) > ns["BORE_R"] + 0.2)

    try:
        chamfered = body.makeChamfer(RIM_CHAMFER, [e for e in body.Edges if on_rim(e)])
        if chamfered.isValid():
            body = chamfered
    except Exception:  # OCC raises OCCError or ValueError when it cannot
        pass
    out = dict(parts)
    out["Body"] = body
    out["Ferrule"] = parts["Ferrule"].translated(-axis * down)
    return out, mouth, axis


def head_frame(mouth, axis):
    """Model (right-handed address, mm) -> skin frame (m): +Y up the shaft, toe -X, face +Z."""
    y = axis
    x = V(axis.z, 0.0, -axis.x)  # across the shaft in the address plane, toward the heel
    z = x.cross(y)               # toward the target: the face side

    def point(p):
        d = p - mouth
        return (d.dot(x) * 0.001, d.dot(y) * 0.001, d.dot(z) * 0.001)

    def normal(n):
        return (n.dot(x), n.dot(y), n.dot(z))

    # texture coordinates: planar across the face/back, U level along the ground line (heel-toe
    # at address, so the brushed grain runs along the sole like a machined finish), V upright
    along, upright = V(1.0, 0.0, 0.0), V(0.0, 0.0, 1.0)
    ua, va = normal(along), normal(upright)

    def uv(gp):
        return ((gp[0] * ua[0] + gp[1] * ua[1] + gp[2] * ua[2]) * UV_PER_M,
                (gp[0] * va[0] + gp[1] * va[1] + gp[2] * va[2]) * UV_PER_M)

    return point, normal, uv


def mesh_part(shape, point, normal, uv_of):
    """Triangles of every face, each face with its own vertices and true surface normals: the
    ridge crease and real edges stay crisp, smooth surfaces stay smooth."""
    if len(shape.Solids) <= 1 and len(shape.Shells) > 1:  # the body's sealed cavity is never seen
        # (a part of several solids, like the "18°" stamp's glyphs, keeps them all)
        shape = max(shape.Shells, key=lambda s: s.BoundBox.DiagonalLength)
    pos, nrm, uv, idx = [], [], [], []
    for face in shape.Faces:
        pts, tris = face.tessellate(TOLERANCE)
        if not tris:
            continue
        # project each point for its surface parameters (slow but exact): Face.getUVNodes() does
        # not follow tessellate()'s point order, and its normals came out scrambled (crumpled foil)
        uvs = [face.Surface.parameter(p) for p in pts]
        base = len(pos) // 3
        normals = []
        for p, (u, v) in zip(pts, uvs):
            n = face.normalAt(u, v)
            normals.append(n)
            gp = point(p)
            pos += gp
            nrm += normal(n)
            uv += uv_of(gp)
        for a, b, c in tris:
            # wind every triangle outward, by the surface normals at its corners
            facet = (pts[b] - pts[a]).cross(pts[c] - pts[a])
            if facet.dot(normals[a] + normals[b] + normals[c]) < 0:
                b, c = c, b
            idx += (base + a, base + b, base + c)
    return pos, nrm, uv, idx


def brand_decal(body, normal, mouth):
    """The brand layer: the body mesh's back triangles that touch BRAND_RECT, lifted DECAL_LIFT
    along their vertex normals, with UVs mapping the rectangle onto the brand art (whose
    margins are clear, so triangles reaching past the rectangle just show nothing)."""
    pos, nrm, _, idx = body

    def vec(a, i):
        return (a[3 * i], a[3 * i + 1], a[3 * i + 2])

    def dot(a, b):
        return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]

    def cross(a, b):
        return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])

    def unit(a):
        n = math.sqrt(dot(a, a))
        return (a[0] / n, a[1] / n, a[2] / n)

    def outward(t):  # 2 * area * outward normal (mesh_part winds every triangle outward)
        a, b, c = (vec(pos, idx[t + k]) for k in range(3))
        return cross(tuple(b[i] - a[i] for i in range(3)), tuple(c[i] - a[i] for i in range(3)))

    # projection: the area-weighted mean normal of everything facing away from the target
    back_ref = normal(V(0.0, 1.0, 0.0))
    acc = [0.0, 0.0, 0.0]
    for t in range(0, len(idx), 3):
        n = outward(t)
        size = math.sqrt(dot(n, n))
        if size > 0.0 and dot(n, back_ref) / size > 0.25:
            acc = [acc[i] + n[i] for i in range(3)]
    nb = unit(acc)
    toe, up = normal(V(-1.0, 0.0, 0.0)), normal(V(0.0, 0.0, 1.0))
    ua = unit(tuple(toe[i] - nb[i] * dot(toe, nb) for i in range(3)))
    va = cross(nb, ua)
    if dot(va, up) < 0.0:
        va = tuple(-c for c in va)
    # the rectangle is measured from the model's origin; the skin frame's origin is the mouth
    model = [normal(V(*e)) for e in ((1, 0, 0), (0, 1, 0), (0, 0, 1))]  # skin images of model axes
    mouth_mm = (mouth.x, mouth.y, mouth.z)
    u_off = sum(mouth_mm[i] * dot(ua, model[i]) for i in range(3))
    v_off = sum(mouth_mm[i] * dot(va, model[i]) for i in range(3))
    u0, v0, u1, v1 = BRAND_RECT

    def uv_mm(p):
        return u_off + 1000.0 * dot(p, ua), v_off + 1000.0 * dot(p, va)

    out_pos, out_nrm, out_uv, out_idx, remap = [], [], [], [], {}
    for t in range(0, len(idx), 3):
        n = outward(t)
        size = math.sqrt(dot(n, n))
        if size == 0.0 or dot(n, nb) / size < DECAL_FACING:
            continue
        corners = [uv_mm(vec(pos, idx[t + k])) for k in range(3)]
        if not any(u0 <= u <= u1 and v0 <= v <= v1 for u, v in corners):
            continue
        for k in range(3):
            i = idx[t + k]
            if i not in remap:
                p, vn = vec(pos, i), vec(nrm, i)
                u, v = uv_mm(p)
                remap[i] = len(out_pos) // 3
                out_pos += [p[c] + vn[c] * DECAL_LIFT for c in range(3)]
                out_nrm += vn
                # turned half round: the brand reads with the head up and the grip down, as irons' backs do
                out_uv += [(u1 - u) / (u1 - u0), (v - v0) / (v1 - v0)]
            out_idx.append(remap[i])
    return out_pos, out_nrm, out_uv, out_idx


def brushed_map(size=BRUSH_SIZE, seed=7):
    """A glTF metallic-roughness map (R unused, G roughness, B metallic) for a brushed satin
    finish: fine streaks along U, each row its own shade, a few deeper scratches, and a soft
    wave along each streak. It tiles both ways (rows wrap, waves have whole periods)."""
    rnd = random.Random(seed)
    rows = [rnd.random() for _ in range(size)]
    streak = [(rows[i - 1] + 2.0 * rows[i] + rows[(i + 1) % size]) / 4.0 for i in range(size)]
    for _ in range(14):
        i = rnd.randrange(size)
        streak[i] = min(1.0, streak[i] + 0.55)
    phase = [rnd.random() * 2.0 * math.pi for _ in range(size)]
    low = [0.5 + 0.5 * math.sin(2.0 * math.pi * 3.0 * i / size) * math.cos(2.0 * math.pi * 5.0 * i / size)
           for i in range(size)]
    pixels = []
    for i in range(size):
        row = bytearray()
        for j in range(size):
            wave = 0.85 + 0.15 * math.sin(2.0 * math.pi * 2.0 * j / size + phase[i])
            g = min(1.0, max(0.0, 0.78 + 0.18 * streak[i] * wave + 0.04 * low[i]))
            row += bytes((255, int(round(g * 255)), 255))
        pixels.append(bytes(row))
    return png_rgb(size, size, pixels)


def png_rgb(width, height, rows):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    raw = b"".join(b"\x00" + r for r in rows)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def write_glb(path, meshes, brushed_png=None, decal=None):
    """meshes: [(node name, material name, rgb, metallic, roughness, pos, nrm, uv, idx)]. The first
    mesh (the body) takes brushed_png as its metallic-roughness map. decal: (node name, material
    name, png bytes, pos, nrm, uv, idx), an alpha-blended layer textured with the png (clamped).
    A "ShaftSocket" node marks the hosel mouth (the origin) for
    OFGEquipmentAssets._find_attachment_marker()."""
    blob = bytearray()
    views, accessors = [], []

    def view(data, target):
        while len(blob) % 4:
            blob.append(0)
        views.append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(data), "target": target})
        blob.extend(data)
        return len(views) - 1

    def accessor(values, count, kind, ctype, target, bounds=False):
        code = "I" if ctype == 5125 else "f"
        acc = {"bufferView": view(array.array(code, values).tobytes(), target), "componentType": ctype,
               "count": count, "type": kind}
        if bounds:
            k = {"VEC3": 3, "VEC2": 2}[kind]
            acc["min"] = [min(values[i::k]) for i in range(k)]
            acc["max"] = [max(values[i::k]) for i in range(k)]
        accessors.append(acc)
        return len(accessors) - 1

    nodes, gl_meshes, materials = [], [], []
    for name, mat, rgb, metallic, roughness, pos, nrm, uv, idx in meshes:
        n = len(pos) // 3
        prim = {"attributes": {"POSITION": accessor(pos, n, "VEC3", 5126, 34962, True),
                               "NORMAL": accessor(nrm, n, "VEC3", 5126, 34962),
                               "TEXCOORD_0": accessor(uv, n, "VEC2", 5126, 34962)},
                "indices": accessor(idx, len(idx), "SCALAR", 5125, 34963),
                "material": len(materials)}
        pbr = {"baseColorFactor": [rgb[0], rgb[1], rgb[2], 1.0], "metallicFactor": metallic,
               "roughnessFactor": roughness}
        if brushed_png is not None and not materials:
            pbr["metallicRoughnessTexture"] = {"index": 0, "texCoord": 0}
        materials.append({"name": mat, "doubleSided": False, "pbrMetallicRoughness": pbr})
        gl_meshes.append({"name": name, "primitives": [prim]})
        nodes.append({"name": name, "mesh": len(gl_meshes) - 1})

    images, samplers, textures = [], [], []

    def texture(png, name, wrap):
        while len(blob) % 4:
            blob.append(0)
        views.append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(png)})
        blob.extend(png)
        images.append({"name": name, "mimeType": "image/png", "bufferView": len(views) - 1})
        samplers.append({"magFilter": 9729, "minFilter": 9987, "wrapS": wrap, "wrapT": wrap})
        textures.append({"sampler": len(samplers) - 1, "source": len(images) - 1})
        return len(textures) - 1

    if brushed_png is not None:
        texture(brushed_png, "utility_2u_brushed_metal_roughness", 10497)  # repeat; texture 0
    if decal is not None:
        name, mat, png, pos, nrm, uv, idx = decal
        n = len(pos) // 3
        prim = {"attributes": {"POSITION": accessor(pos, n, "VEC3", 5126, 34962, True),
                               "NORMAL": accessor(nrm, n, "VEC3", 5126, 34962),
                               "TEXCOORD_0": accessor(uv, n, "VEC2", 5126, 34962)},
                "indices": accessor(idx, len(idx), "SCALAR", 5125, 34963),
                "material": len(materials)}
        materials.append({"name": mat, "doubleSided": False, "alphaMode": "BLEND",
                          "pbrMetallicRoughness": {"baseColorFactor": [1.0, 1.0, 1.0, 1.0],
                                                   "baseColorTexture": {"index": texture(png, mat, 33071), "texCoord": 0},
                                                   "metallicFactor": 0.0, "roughnessFactor": 0.45}})
        gl_meshes.append({"name": name, "primitives": [prim]})
        nodes.append({"name": name, "mesh": len(gl_meshes) - 1})
    nodes.append({"name": "ShaftSocket"})  # at the origin: the hosel mouth, +Y up the shaft
    doc = {"asset": {"version": "2.0", "generator": "export_utility_2u_head.py (FreeCAD)"},
           "scene": 0, "scenes": [{"name": "Scene", "nodes": list(range(len(nodes)))}],
           "nodes": nodes, "meshes": gl_meshes, "materials": materials}
    if images:
        doc.update({"images": images, "samplers": samplers, "textures": textures})
    while len(blob) % 4:
        blob.append(0)
    doc.update({"accessors": accessors, "bufferViews": views, "buffers": [{"byteLength": len(blob)}]})
    js = json.dumps(doc, separators=(",", ":")).encode("utf-8")
    js += b" " * ((-len(js)) % 4)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(blob), 0x004E4942) + bytes(blob))


def export(path=OUT):
    ns, parts, info = build_head()
    parts, mouth, axis = trim_hosel(ns, parts, info)
    point, normal, uv_of = head_frame(mouth, axis)
    meshes, report = [], []
    for key, (node, mat, rgb, metallic, roughness) in PARTS.items():
        pos, nrm, uv, idx = mesh_part(parts[key], point, normal, uv_of)
        meshes.append((node, mat, rgb, metallic, roughness, pos, nrm, uv, idx))
        report.append("%s: %d triangles" % (node, len(idx) // 3))
    decal = None
    if os.path.exists(BRAND_PNG):
        dpos, dnrm, duv, didx = brand_decal(meshes[0][5:9], normal, mouth)
        with open(BRAND_PNG, "rb") as f:
            decal = ("UtilityIron2U_BrandDecal", "ofg_utility_2u__brand_paint", f.read(), dpos, dnrm, duv, didx)
        report.append("UtilityIron2U_BrandDecal: %d triangles" % (len(didx) // 3))
    write_glb(path, meshes, brushed_map(), decal)
    xs, ys, zs = (meshes[0][5][i::3] for i in range(3))
    report.append("body bounds mm: x %.1f..%.1f  y %.1f..%.1f  z %.1f..%.1f" % (
        min(xs) * 1000, max(xs) * 1000, min(ys) * 1000, max(ys) * 1000, min(zs) * 1000, max(zs) * 1000))
    report.append("wrote " + path)
    return report


if os.environ.get("UTILITY_2U_NO_MAIN") != "1":
    print("\n".join(export()))
