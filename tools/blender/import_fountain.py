"""The Grand clubhouse's fountain, from the user's model (Fountain 8: a .3DS -- Blender has no
3DS importer, so it's read here -- with a granite texture) -> assets/facilities/props/fountain.glb

    blender -b --factory-startup --disable-autoexec -P tools/blender/import_fountain.py -- <fountain.3ds> <texture dir> [--preview <png>]

The model is read chunk by chunk (its meshes' vertices, faces, UVs and face materials and their
placing in the scene; its materials' colours and texture maps), each mesh put where the file's
keyframer stands it, scaled so its basin is FOUNTAIN_WIDTH across, stood on z = 0 centred, joined
into one mesh and written as a .glb. clubhouse_l4 places it with a
FOUNTAIN marker; FacilityBuilder stands the model there.
"""
import os
import struct
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "assets", "facilities", "props", "fountain.glb")
FOUNTAIN_WIDTH = 6.2  # the basin across (m): the old fountain's, inside the drive's island


def read_3ds(path):
    """The meshes and materials of a .3ds: ([{name, verts, faces, uvs, face_mats, matrix}],
    {material: {colour, texture}}, {object: {pivot, pos, rot, scale}})."""
    data = open(path, "rb").read()
    meshes, materials, nodes = [], {}, {}

    def cstring(at):
        end = data.index(b"\0", at)
        return data[at:end].decode("latin-1"), end + 1

    def colour(at, end):
        while at < end:
            cid, clen = struct.unpack_from("<HI", data, at)
            if cid == 0x0010:
                return struct.unpack_from("<3f", data, at + 6)
            if cid in (0x0011, 0x0012):
                return tuple(c / 255.0 for c in data[at + 6:at + 9])
            at += clen
        return None

    def first_key(at, n):
        """A track's first key's `n` floats (its flags, 8 bytes unused, its key count; then each key's
        frame, its spline flags and their floats)."""
        if struct.unpack_from("<I", data, at + 10)[0] == 0:
            return None
        flags = struct.unpack_from("<H", data, at + 18)[0]
        return struct.unpack_from("<%df" % n, data, at + 20 + 4 * bin(flags & 0x1F).count("1"))

    def walk(at, end, mesh=None, mat=None, node=None):
        while at < end:
            cid, clen = struct.unpack_from("<HI", data, at)
            body, stop = at + 6, at + clen
            if clen < 6:
                return
            if cid in (0x4D4D, 0x3D3D, 0x4100, 0xB000):
                walk(body, stop, mesh, mat)
            elif cid == 0xB002:  # an object's node in the keyframer: where the scene puts it
                n = {"name": "", "pivot": (0.0, 0.0, 0.0), "pos": None, "rot": None, "scale": None}
                walk(body, stop, None, None, n)
                if n["name"]:
                    nodes[n["name"]] = n
            elif cid == 0xB010 and node is not None:
                node["name"] = cstring(body)[0]
            elif cid == 0xB013 and node is not None:
                node["pivot"] = struct.unpack_from("<3f", data, body)
            elif cid in (0xB020, 0xB021, 0xB022) and node is not None:
                node[{0xB020: "pos", 0xB021: "rot", 0xB022: "scale"}[cid]] = first_key(body, 4 if cid == 0xB021 else 3)
            elif cid == 0x4160 and mesh is not None:  # the mesh's own frame, in the scene
                f = struct.unpack_from("<12f", data, body)
                mesh["matrix"] = Matrix(((f[0], f[3], f[6], f[9]), (f[1], f[4], f[7], f[10]), (f[2], f[5], f[8], f[11]), (0, 0, 0, 1)))
            elif cid == 0x4000:  # an object: its name, then its mesh
                name, after = cstring(body)
                m = {"name": name, "verts": [], "faces": [], "uvs": [], "face_mats": [], "matrix": Matrix.Identity(4)}
                walk(after, stop, m, mat)
                if m["verts"] and m["faces"]:
                    meshes.append(m)
            elif cid == 0x4110 and mesh is not None:
                n = struct.unpack_from("<H", data, body)[0]
                mesh["verts"] = [struct.unpack_from("<3f", data, body + 2 + i * 12) for i in range(n)]
            elif cid == 0x4120 and mesh is not None:
                n = struct.unpack_from("<H", data, body)[0]
                mesh["faces"] = [struct.unpack_from("<3H", data, body + 2 + i * 8) for i in range(n)]
                walk(body + 2 + n * 8, stop, mesh, mat)  # its face material lists
            elif cid == 0x4130 and mesh is not None:
                name, after = cstring(body)
                n = struct.unpack_from("<H", data, after)[0]
                mesh["face_mats"].append((name, struct.unpack_from("<%dH" % n, data, after + 2)))
            elif cid == 0x4140 and mesh is not None:
                n = struct.unpack_from("<H", data, body)[0]
                mesh["uvs"] = [struct.unpack_from("<2f", data, body + 2 + i * 8) for i in range(n)]
            elif cid == 0xAFFF:  # a material
                m = {"name": "", "colour": None, "texture": ""}
                walk(body, stop, None, m)
                if m["name"]:
                    materials[m["name"]] = m
            elif cid == 0xA000 and mat is not None:
                mat["name"] = cstring(body)[0]
            elif cid == 0xA020 and mat is not None:
                mat["colour"] = colour(body, stop)
            elif cid == 0xA200 and mat is not None:
                walk(body, stop, None, mat)
            elif cid == 0xA300 and mat is not None:
                mat["texture"] = cstring(body)[0]
            at = stop

    walk(0, len(data))
    return meshes, materials, nodes


def placing(m, node):
    """Where the scene stands mesh `m`: its keyframer node's position, turn and scale about its
    pivot, applied to the mesh taken back into its own frame (a .3ds keeps a mesh's vertices where
    they stood when it was made; its node is what places it now, the way 3ds Max shows it)."""
    if node is None:
        return Matrix.Identity(4)
    t = Matrix.Translation(Vector(node["pos"] or (0, 0, 0)))
    r = Matrix.Identity(4)
    rot = node["rot"]
    if rot and Vector(rot[1:]).length > 1e-6:
        r = Quaternion(Vector(rot[1:]).normalized(), -rot[0]).to_matrix().to_4x4()  # a .3ds turns the other way
    s = Matrix.Diagonal((*(node["scale"] or (1, 1, 1)), 1.0))
    return t @ r @ s @ Matrix.Translation(-Vector(node["pivot"])) @ m["matrix"].inverted()


def material(name, m, tex_dir):
    out = bpy.data.materials.new(name)
    out.use_nodes = True
    bsdf = out.node_tree.nodes["Principled BSDF"]
    rgb = m.get("colour") or (0.7, 0.7, 0.7)
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.85
    tex = m.get("texture", "")
    found = ""
    for f in os.listdir(tex_dir):  # its map by name, whatever its case -- or, with none named, the
        # picture named after the material (the model's Granite.jpg comes alongside, unreferenced)
        if (tex and f.lower() == os.path.basename(tex).lower()) or (not tex and os.path.splitext(f)[0].lower() == name.lower()):
            found = os.path.join(tex_dir, f)
    if found:
        node = out.node_tree.nodes.new("ShaderNodeTexImage")
        node.image = bpy.data.images.load(found)
        out.node_tree.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
    if "water" in name.lower() or (rgb[2] > rgb[0] * 1.3 and rgb[2] > 0.3 and not found):
        bsdf.inputs["Base Color"].default_value = (0.32, 0.55, 0.62, 1.0)  # water: a clear blue-green, glossy
        bsdf.inputs["Roughness"].default_value = 0.08
    print("MATERIAL", name, rgb, found or "-")
    return out


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    src, tex_dir = argv[0], argv[1]
    preview = argv[argv.index("--preview") + 1] if "--preview" in argv else ""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    meshes, mats, nodes = read_3ds(src)
    print("READ %d meshes, %d materials, %d nodes" % (len(meshes), len(mats), len(nodes)))
    made = {}
    objs = []
    for m in meshes:
        me = bpy.data.meshes.new(m["name"])
        at = placing(m, nodes.get(m["name"]))
        me.from_pydata([at @ Vector(v) for v in m["verts"]], [], [tuple(f) for f in m["faces"]])
        names = [n for n, _faces in m["face_mats"]] or [""]
        for n in names:
            if n not in made:
                made[n] = material(n or "stone", mats.get(n, {}), tex_dir)
            me.materials.append(made[n])
        for slot, (_n, faces) in enumerate(m["face_mats"]):
            for fi in faces:
                if fi < len(me.polygons):
                    me.polygons[fi].material_index = slot
        if m["uvs"] and len(m["uvs"]) == len(m["verts"]):
            uv = me.uv_layers.new(name="UVMap")
            for poly in me.polygons:
                for li in poly.loop_indices:
                    uv.data[li].uv = m["uvs"][me.loops[li].vertex_index]
        me.validate()
        me.update()
        ob = bpy.data.objects.new(m["name"], me)
        bpy.context.scene.collection.objects.link(ob)
        objs.append(ob)
        Q = [v.co for v in me.vertices]
        print("MESH %-24s verts %6d faces %6d mats %s  x %.0f..%.0f y %.0f..%.0f z %.0f..%.0f" % (m["name"], len(m["verts"]), len(m["faces"]), names,
              min(q.x for q in Q), max(q.x for q in Q), min(q.y for q in Q), max(q.y for q in Q), min(q.z for q in Q), max(q.z for q in Q)))
    # one mesh, in metres, standing on z = 0 at the middle of its footprint
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    P = [v.co for v in ob.data.vertices]
    lo = Vector((min(p.x for p in P), min(p.y for p in P), min(p.z for p in P)))
    hi = Vector((max(p.x for p in P), max(p.y for p in P), max(p.z for p in P)))
    s = FOUNTAIN_WIDTH / max(hi.x - lo.x, hi.y - lo.y)
    mid = Vector(((lo.x + hi.x) * 0.5, (lo.y + hi.y) * 0.5, lo.z))
    for v in ob.data.vertices:
        v.co = (v.co - mid) * s
    ob.data.update()
    bpy.ops.object.shade_smooth_by_angle(angle=0.6)
    ob.name = "Fountain"
    print("FOUNTAIN %.2f m across, %.2f m high (scaled %.4f)" % ((hi.x - lo.x) * s, (hi.z - lo.z) * s, s))
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_image_format="AUTO", export_apply=True)
    print("EXPORTED", OUT)
    if preview:
        sc = bpy.context.scene
        cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
        sc.collection.objects.link(cam)
        sc.camera = cam
        cam.location = (7.0, -9.0, 5.0)
        cam.rotation_euler = (Vector((0, 0, 1.2)) - cam.location).to_track_quat("-Z", "Y").to_euler()
        sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
        sc.collection.objects.link(sun)
        sun.rotation_euler = (0.8, 0.2, 0.6)
        sc.world = bpy.data.worlds.new("w")
        sc.world.color = (0.6, 0.7, 0.8)
        sc.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE"
        sc.render.resolution_x, sc.render.resolution_y = 900, 600
        sc.render.filepath = preview
        bpy.ops.render.render(write_still=True)


main()
