"""The day spa's hot tub and massage table, from the user's models:

- jacuzzi.glb (centimetres: a wood-clad square tub with its water) -> assets/facilities/props/jacuzzi.glb
- 3d-model.obj (inches: a massage table with a face cradle, untextured) -> assets/facilities/props/massage_table.glb;
  its padded top and cradle take a cream leather, the frame a light wood

    blender -b --factory-startup --disable-autoexec -P tools/blender/import_spa_props.py -- <jacuzzi.glb> <3d-model.obj> [--preview <dir>]

Each is scaled to metres, stood on z = 0 centred on its footprint, joined into one mesh and
written as a .glb. The spa places them with JACUZZI / MASSAGE_TABLE markers (fm_lib.jacuzzi,
fm_lib.massage_table): the tub square to the room, the table's length along local Y.
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "assets", "facilities", "props")
TEX = 1024


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def bounds(objs):
    P = [o.matrix_world @ v.co for o in objs for v in o.data.vertices]
    lo = Vector((min(p.x for p in P), min(p.y for p in P), min(p.z for p in P)))
    hi = Vector((max(p.x for p in P), max(p.y for p in P), max(p.z for p in P)))
    return lo, hi


def flat(name, rgb, rough, metal=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    lin = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in rgb]
    b.inputs["Base Color"].default_value = (*lin, 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    m.diffuse_color = (*lin, 1.0)
    return m


def finish(objs, scale, name):
    """Apply transforms, scale to metres, stand on z = 0 centred, join, name."""
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
        mw = o.matrix_world.copy()  # keep what its parents did (the glb's Y-up turn)
        o.parent = None
        o.matrix_world = mw
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.make_single_user(object=True, obdata=True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for o in objs:
        o.data.transform(Matrix.Scale(scale, 4))
    lo, hi = bounds(objs)
    for o in objs:
        o.data.transform(Matrix.Translation((-(lo.x + hi.x) * 0.5, -(lo.y + hi.y) * 0.5, -lo.z)))
    if len(objs) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = ob.data.name = name
    for o in list(bpy.context.scene.objects):
        if o is not ob:
            bpy.data.objects.remove(o, do_unlink=True)
    ob.data.update()
    bpy.context.view_layer.update()
    d = ob.dimensions
    print("PROP %-14s %.2f x %.2f x %.2f m  %d tris" % (name, d.x, d.y, d.z, sum(len(p.vertices) - 2 for p in ob.data.polygons)))
    return ob


def export(ob, path):
    for slot in ob.material_slots:  # keep its pictures small
        if slot.material and slot.material.use_nodes:
            for n in slot.material.node_tree.nodes:
                if n.type == "TEX_IMAGE" and n.image and max(n.image.size) > TEX:
                    n.image.scale(TEX, TEX)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_image_format="AUTO",
                              export_apply=True)
    print("EXPORTED", path)


def preview(ob, path):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x, sc.render.resolution_y = 700, 500
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.62, 0.64, 0.68, 1)
    sc.world = w
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(50), 0, math.radians(30))
    sc.collection.objects.link(sun)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    size = max(ob.dimensions)
    c = Vector((0, 0, ob.dimensions.z * 0.5))
    cam.data.clip_start = 0.01
    d = Vector((0.7, 1.0, 0.8)).normalized()
    cam.location = c + d * size * 2.2
    cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


def jacuzzi(path, prev):
    reset()
    bpy.ops.import_scene.gltf(filepath=path)
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    lo, hi = bounds(objs)
    ob = finish(objs, 2.28 / max(hi.x - lo.x, hi.y - lo.y), "jacuzzi")  # a 2.28 m square tub
    export(ob, os.path.join(OUT, "jacuzzi.glb"))
    if prev:
        preview(ob, os.path.join(prev, "jacuzzi.png"))


def massage_table(path, prev):
    reset()
    bpy.ops.wm.obj_import(filepath=path)
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    ob = finish(objs, 0.0254, "massage_table")
    me = ob.data
    me.materials.clear()
    me.materials.append(flat("massage_frame", (0.78, 0.62, 0.44), 0.6))
    me.materials.append(flat("massage_pad", (0.93, 0.89, 0.8), 0.75))
    top = ob.dimensions.z
    for p in me.polygons:  # the padded top and the face cradle: everything up high
        p.material_index = 1 if p.center.z > top * 0.8 else 0
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(30))
    export(ob, os.path.join(OUT, "massage_table.glb"))
    if prev:
        preview(ob, os.path.join(prev, "massage_table.png"))


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    prev = args[args.index("--preview") + 1] if "--preview" in args else ""
    if prev:
        os.makedirs(prev, exist_ok=True)
    jacuzzi(args[0], prev)
    massage_table(args[1], prev)


main()
