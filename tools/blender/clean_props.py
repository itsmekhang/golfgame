"""Clean the store props the club's pro shop and people use into game assets:
the golf cap (golfers wear it, the shop sells it in every colour), two clothing racks and two
display mannequins.

    blender -b --factory-startup --python tools/blender/clean_props.py -- cap=<cap.glb>
        rack_a=<rack.glb> rack_b=<rack.glb> mannequin_m=<m.glb> mannequin_f=<f.glb> [--previews <dir>]

Writes assets/facilities/props/<name>.glb (any subset of the props).
  cap          the cap's shell, bill and buttons (the hidden liner and the strap dropped),
               simplified; its grey fabric texture is kept so Godot can tint it any colour.
               Bill toward +Y (the wearer's front), the inside rim at z = 0, ~0.2 m across.
  rack_a / _b  frame and hangers in metal, every shirt its own colour; front (the side the
               shirts face) toward -Y, 1.55 m tall.
  fold_a / _b  piles of folded shirts for the shelves (folded_pile_<a|b>.glb), ~0.34 m across.
  mannequin_*  the torso form on its stand, dressed in a polo and trousers (two outfits each:
               mannequin_<m|f>_<0|1>.glb), front toward -Y, base on z = 0.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "assets", "facilities", "props")
SHIRTS = ["27324d", "f5f3ee", "9d2f34", "3f7a4f", "7fb6d8", "e8c547", "1d1f22", "c3a77f"]


def lin(h):
    c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c) + (1.0,)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_meshes(path, keep=None):
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    for o in meshes:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
    for o in [o for o in bpy.data.objects if o.type != "MESH"]:
        bpy.data.objects.remove(o)
    if keep is not None:
        for o in [o for o in meshes if not keep(o)]:
            bpy.data.objects.remove(o)
        meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bm.to_mesh(ob.data)
    bm.free()
    return ob


def bounds(ob):
    vs = [v.co for v in ob.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    return lo, hi


def normalize(ob, rz, size, axis="z", centre_z=False):
    """Turn by rz, scale so its extent on `axis` ("xy": the wider of x and y) is `size`, centre
    it on x/y, base on z = 0."""
    ob.data.transform(Matrix.Rotation(rz, 4, "Z"))
    lo, hi = bounds(ob)
    ext = max(hi.x - lo.x, hi.y - lo.y) if axis == "xy" else hi["xyz".index(axis)] - lo["xyz".index(axis)]
    s = size / ext
    c = (lo + hi) * 0.5
    ob.data.transform(Matrix.Scale(s, 4) @ Matrix.Translation((-c.x, -c.y, -(c.z if centre_z else lo.z))))
    ob.data.update()


def decimate(ob, tris):
    cur = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    if cur <= tris:
        return
    m = ob.modifiers.new("dec", "DECIMATE")
    m.ratio = tris / cur
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.modifier_apply(modifier=m.name)


def flat_material(name, hexcol, rough=0.8, metal=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = lin(hexcol)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    return m


def export(ob, name):
    for o in bpy.data.objects:
        o.select_set(o == ob)
    bpy.context.view_layer.objects.active = ob
    ob.name = name
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_image_format="AUTO")
    print("EXPORTED", path, sum(len(p.vertices) - 2 for p in ob.data.polygons), "tris")


# ---------------------------------------------------------------- the props

def cap(src):
    # the shell, bill and buttons; the liner (inside, never seen on a head) and the strap
    # buckle (48k triangles at the back) go
    keep = ("baseballCap", "baseballCap.001", "baseballCap.003", "blinn1SG")
    ob = import_meshes(src, lambda o: o.name in keep)
    # the bill sticks out along -Y in the source: turn it to +Y (the wearer's front)
    normalize(ob, math.pi, 0.205, "x")
    decimate(ob, 2200)
    for p in ob.data.polygons:
        p.use_smooth = True
    for mat in ob.data.materials:
        if mat and mat.name.startswith("baseballCap"):
            mat.name = "cap"  # Godot tints this one (its texture is plain grey fabric)
    export(ob, "golf_cap")


def rack(src, name, tris):
    """Frame (top rail, end uprights, base) in metal, the hanging shirts in colours."""
    ob = import_meshes(src)
    decimate(ob, tris)
    # the shirts hang across the rail: the rail runs along the longer of x / y; make it x
    lo, hi = bounds(ob)
    turn = 0.0 if (hi.x - lo.x) >= (hi.y - lo.y) else math.pi / 2
    normalize(ob, turn, 1.55)
    lo, hi = bounds(ob)
    H, W = hi.z - lo.z, hi.x - lo.x
    metal = flat_material("rack_metal", "c9ccd0", 0.32, 0.9)
    shirts = [flat_material("shirt_" + h, h, 0.88) for h in SHIRTS]
    me = ob.data
    me.materials.clear()
    me.materials.append(metal)
    for m in shirts:
        me.materials.append(m)
    bm = bmesh.new()
    bm.from_mesh(me)
    frame, cloth = set(), set()
    for f in bm.faces:
        c = f.calc_center_median()
        is_frame = c.z > hi.z - 0.035 * H or c.z < lo.z + 0.08 * H or abs(c.x) > W * 0.5 - 0.035 * W
        (frame if is_frame else cloth).add(f)
    # each shirt (an island once the frame is set apart) its own colour, left to right
    islands = []
    left = set(cloth)
    while left:
        seed = left.pop()
        isle, stack = [seed], [seed]
        while stack:
            f = stack.pop()
            for e in f.edges:
                for g in e.link_faces:
                    if g in left:
                        left.remove(g)
                        isle.append(g)
                        stack.append(g)
        islands.append(isle)
    islands.sort(key=lambda isle: sum(f.calc_center_median().x for f in isle) / len(isle))
    k = 0
    for isle in islands:
        vs = [v.co for f in isle for v in f.verts]
        ext = sorted(max(v[i] for v in vs) - min(v[i] for v in vs) for i in range(3))
        area = sum(f.calc_area() for f in isle)
        # hooks, slivers, bars and tubes (little surface for their length: a frame of tubing
        # scores ~0.3-0.6 m^2 per metre, a hanging shirt 1.7+): metal
        if len(isle) < 12 or ext[1] < 0.06 or area / max(ext[2], 0.01) < 1.0:
            for f in isle:
                f.material_index = 0
            continue
        for f in isle:
            f.material_index = 1 + (k % len(shirts))
        k += 1
    for f in frame:
        f.material_index = 0
    for f in bm.faces:
        f.smooth = True
    bm.to_mesh(me)
    bm.free()
    print("  %s: %d shirts" % (name, k))
    export(ob, name)


# display outfits for the mannequins: (polo, trousers / shorts)
OUTFITS = {"m": (("27324d", "c3a77f"), ("f5f3ee", "27324d")), "f": (("7fb6d8", "f5f3ee"), ("9d2f34", "5a5e63"))}


def mannequin(src, name, rz):
    """The torso form on its stand, dressed: a polo over the chest and shoulders and trousers
    over the hips, shells lifted a few millimetres off the form. One .glb per outfit."""
    for k, (shirt, pants) in enumerate(OUTFITS[name[-1]]):
        reset()
        ob = import_meshes(src)
        normalize(ob, rz, 1.58)
        me = ob.data
        form = None
        for i, mat in enumerate(me.materials):
            if mat is None:
                continue
            if "Acier" in mat.name or "Mtal" in mat.name:
                mat.name = "steel"
            else:
                mat.name = "mannequin"
                form = i
        zs = [v.co.z for p in me.polygons if p.material_index == form for v in (me.vertices[j] for j in p.vertices)]
        bottom, top = min(zs), max(zs)
        neck = top - 0.25
        waist = bottom + 0.2
        me.materials.append(flat_material("shirt", shirt, 0.85))
        me.materials.append(flat_material("pants", pants, 0.85))
        bm = bmesh.new()
        bm.from_mesh(me)
        bm.normal_update()
        dress = [f for f in bm.faces if f.material_index == form and f.calc_center_median().z < neck]
        res = bmesh.ops.duplicate(bm, geom=dress)
        new_faces = [g for g in res["geom"] if isinstance(g, bmesh.types.BMFace)]
        new_verts = {v for f in new_faces for v in f.verts}
        for v in new_verts:
            v.co += v.normal * 0.008
        shirt_i, pants_i = len(me.materials) - 2, len(me.materials) - 1
        for f in new_faces:
            f.material_index = shirt_i if f.calc_center_median().z > waist else pants_i
        bm.to_mesh(me)
        bm.free()
        for p in me.polygons:
            p.use_smooth = True
        export(ob, "%s_%d" % (name, k))


def folded(src, name):
    """A pile of folded shirts for the shop's shelves and tables: ~0.34 m across, simplified."""
    ob = import_meshes(src)
    normalize(ob, 0.0, 0.34, "xy")
    decimate(ob, 1000)
    for p in ob.data.polygons:
        p.use_smooth = True
    export(ob, name)


def preview(out_dir, names):
    reset()
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x = 1600
    sc.render.resolution_y = 600
    w = bpy.data.worlds.new("w")
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.7, 0.72, 0.75, 1)
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.0
    sun.rotation_euler = (0.8, 0.2, 0.5)
    sc.collection.objects.link(sun)
    x = 0.0
    for n in names:
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=os.path.join(OUT, n + ".glb"))
        for o in set(bpy.data.objects) - before:
            if o.parent is None:
                o.location.x = x
                if n == "golf_cap":
                    o.scale = (4, 4, 4)
                    o.location.z = 0.4
        x += 2.0
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = x + 0.5
    sc.collection.objects.link(cam)
    sc.camera = cam
    d = Vector((0.35, -1, 0.3)).normalized()
    cam.location = Vector(((x - 2.0) * 0.5, 0, 0.8)) + d * 12
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = os.path.join(out_dir, "props.png")
    bpy.ops.render.render(write_still=True)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    prev = argv[argv.index("--previews") + 1] if "--previews" in argv else ""
    srcs = dict(a.split("=", 1) for a in argv if "=" in a)
    os.makedirs(OUT, exist_ok=True)
    done = []
    for name, fn in (("cap", lambda p: cap(p)),
                     ("rack_a", lambda p: rack(p, "clothes_rack_a", 9000)),
                     ("rack_b", lambda p: rack(p, "clothes_rack_b", 16000)),
                     ("fold_a", lambda p: folded(p, "folded_pile_a")),
                     ("fold_b", lambda p: folded(p, "folded_pile_b")),
                     ("mannequin_m", lambda p: mannequin(p, "mannequin_m", math.pi)),
                     ("mannequin_f", lambda p: mannequin(p, "mannequin_f", math.pi))):
        if name in srcs:
            reset()
            fn(srcs[name])
            done += {"cap": ["golf_cap"], "rack_a": ["clothes_rack_a"], "rack_b": ["clothes_rack_b"], "fold_a": ["folded_pile_a"], "fold_b": ["folded_pile_b"]}.get(name, [name + "_0", name + "_1"])
    if prev and done:
        os.makedirs(prev, exist_ok=True)
        preview(prev, done)
    print("DONE")


main()
