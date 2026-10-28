"""The office's and pro shop's computer and the bar's till, from the user's models:

- iMAC.obj (centimetres: the monitor, keyboard and mouse) with its texture.rar sets (1 the
  monitor, 2 the keyboard, 3 the mouse: base colour, roughness, metallic, OpenGL normal) ->
  assets/facilities/props/imac.glb
- POS System_Cash Drawer N130125.obj (with its .mtl and textures) -> assets/facilities/props/pos_terminal.glb

    blender -b --factory-startup --disable-autoexec -P tools/blender/import_office_props.py -- <iMAC.obj> <imac textures dir> <POS .obj> [--preview <dir>]

Each is scaled to metres, turned so its front -- the side its user faces: the screen, the till's
drawer -- faces +Y here (-Z in Godot), stood on z = 0 centred on its footprint, joined into one
mesh and written as a .glb (textures shrunk to TEX px). The rooms place them with IMAC / POS
markers (fm_lib.imac, fm_lib.pos_terminal).
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "assets", "facilities", "props")
TEX = 512
# the iMac's parts: OBJ object -> its texture set
IMAC_SETS = {"Plane004": "1", "Plane005": "2", "Box002": "3"}
POS_WIDTH = 0.42  # a till's cash drawer is about this wide


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def bounds(objs):
    P = [o.matrix_world @ v.co for o in objs for v in o.data.vertices]
    lo = Vector((min(p.x for p in P), min(p.y for p in P), min(p.z for p in P)))
    hi = Vector((max(p.x for p in P), max(p.y for p in P), max(p.z for p in P)))
    return lo, hi


def image(path, non_color=False):
    img = bpy.data.images.load(path)
    if max(img.size) > TEX:
        img.scale(TEX, TEX)
    if non_color:
        img.colorspace_settings.name = "Non-Color"
    img.pack()
    return img


def pbr(name, texdir, k):
    """A Principled material from texture set k: base colour, roughness, metallic, normal."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]

    def tex(suffix, non_color=False):
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = image(os.path.join(texdir, "%s_%s.png" % (k, suffix)), non_color)
        return n
    nt.links.new(tex("Base_color").outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(tex("Roughness", True).outputs["Color"], bsdf.inputs["Roughness"])
    nt.links.new(tex("Metallic", True).outputs["Color"], bsdf.inputs["Metallic"])
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(tex("Normal_OpenGL", True).outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    return m


def finish(objs, scale, front, name):
    """Scale, turn `front` (an XY direction) to +Y, stand on z = 0 centred, join, name."""
    rz = math.atan2(-front.x, front.y)  # turns `front` onto +Y
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for o in objs:
        o.data.transform(Matrix.Rotation(-rz, 4, "Z") @ Matrix.Scale(scale, 4))
    lo, hi = bounds(objs)
    for o in objs:
        o.data.transform(Matrix.Translation((-(lo.x + hi.x) * 0.5, -(lo.y + hi.y) * 0.5, -lo.z)))
    if len(objs) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = ob.data.name = name
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(30))
    d = ob.dimensions
    print("PROP %-13s %.3f x %.3f x %.3f m  %d tris" % (name, d.x, d.y, d.z, sum(len(p.vertices) - 2 for p in ob.data.polygons)))
    return ob


def export(ob, path):
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
    cam.data.lens = 50
    cam.data.clip_start = 0.01
    d = Vector((0.5, 1.0, 0.55)).normalized()  # from the front (+Y) and to the right
    cam.location = c + d * size * 2.6
    cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


def imac(obj, texdir, prev):
    reset()
    bpy.ops.wm.obj_import(filepath=obj)
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for o in objs:
        k = IMAC_SETS.get(o.name.split(".")[0])
        if k is not None:
            o.data.materials.clear()
            o.data.materials.append(pbr("imac_%s" % k, texdir, k))
    by = {o.name.split(".")[0]: o for o in objs}
    mon, kb = bounds([by["Plane004"]]), bounds([by["Plane005"]])
    front = ((kb[0] + kb[1]) - (mon[0] + mon[1])) * 0.5  # the keyboard sits in front of the screen
    ob = finish(objs, 0.01, Vector((front.x, front.y, 0)).normalized(), "imac")
    export(ob, os.path.join(OUT, "imac.glb"))
    if prev:
        preview(ob, os.path.join(prev, "imac.png"))


def pos(obj, prev, front=Vector((0, -1, 0))):
    reset()
    bpy.ops.wm.obj_import(filepath=obj, up_axis="Z", forward_axis="Y")  # written Z-up (3ds Max)
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    lo, hi = bounds(objs)
    ob = finish(objs, POS_WIDTH / max(hi.x - lo.x, hi.y - lo.y), front, "pos_terminal")
    for slot in ob.material_slots:  # keep its pictures small too
        if slot.material and slot.material.use_nodes:
            for n in slot.material.node_tree.nodes:
                if n.type == "TEX_IMAGE" and n.image and max(n.image.size) > TEX:
                    n.image.scale(TEX, TEX)
    export(ob, os.path.join(OUT, "pos_terminal.glb"))
    if prev:
        preview(ob, os.path.join(prev, "pos_terminal.png"))


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    prev = args[args.index("--preview") + 1] if "--preview" in args else ""
    if prev:
        os.makedirs(prev, exist_ok=True)
    imac(args[0], args[1], prev)
    pos(args[2], prev, Vector((0, -1, 0)) if "--pos-front-y" not in args else Vector((0, 1, 0)))


main()
