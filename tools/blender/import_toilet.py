"""The locker rooms' toilet, from the user's model (tools/blender/sources/toilet/toilet.obj: a
Blender 2.91 export in metres, Y up, no .mtl: its bowl, tank, lid, seat and flush handle).

    blender -b --factory-startup --disable-autoexec -P tools/blender/import_toilet.py -- <toilet.obj>

Stood up on z = 0, turned so its front (the bowl, where you sit facing out) faces +Y here (-Z in
Godot) with the tank behind, centred on its footprint, joined into one mesh and lightened (its
flat areas merged, the curves kept round), all of it white glazed porcelain bar the chrome flush
handle. Writes assets/facilities/props/toilet.glb; the stalls place it with TOILET markers
(fm_lib.toilet_stall).
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "assets", "facilities", "props", "toilet.glb")
TRIANGLES = 6000  # about this many once lightened


def srgb(h):
    c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c) + (1.0,)


def material(name, hexc, rough, metal=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = srgb(hexc)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    return m


def main():
    path = sys.argv[sys.argv.index("--") + 1]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.wm.obj_import(filepath=path)
    parts = [o for o in bpy.data.objects if o.type == "MESH"]
    porcelain = material("porcelain", "f4f4f1", 0.12)
    chrome = material("chrome", "dfe4e6", 0.15, 1.0)
    tank = next((o for o in parts if o.name.lower().startswith("deposito")), None)
    for ob in parts:
        ob.data.materials.clear()
        ob.data.materials.append(chrome if ob.name.lower().startswith("tirador") else porcelain)
    # which way it faces: from the tank to the middle of the whole is forward
    bpy.context.view_layer.update()
    pts = [ob.matrix_world @ v.co for ob in parts for v in ob.data.vertices]
    mid = sum(pts, Vector()) / len(pts)
    tpts = [tank.matrix_world @ v.co for v in tank.data.vertices] if tank else pts
    tmid = sum(tpts, Vector()) / len(tpts)
    ahead = Vector((mid.x - tmid.x, mid.y - tmid.y, 0.0))
    turn = Matrix.Rotation(math.atan2(ahead.x, ahead.y), 4, "Z") if ahead.length > 1e-4 else Matrix.Identity(4)
    bpy.ops.object.select_all(action="DESELECT")
    for ob in parts:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = "Toilet"
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    ob.data.transform(turn)
    vs = [v.co for v in ob.data.vertices]
    lo = Vector([min(v[k] for v in vs) for k in range(3)])
    hi = Vector([max(v[k] for v in vs) for k in range(3)])
    ob.data.transform(Matrix.Translation((-(lo.x + hi.x) * 0.5, -(lo.y + hi.y) * 0.5, -lo.z)))
    # lighter: flat areas merged first (curves untouched), then collapsed to about TRIANGLES
    mod = ob.modifiers.new("planar", "DECIMATE")
    mod.decimate_type = "DISSOLVE"
    mod.angle_limit = math.radians(2.0)
    bpy.ops.object.modifier_apply(modifier=mod.name)
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    if tris > TRIANGLES:
        mod = ob.modifiers.new("collapse", "DECIMATE")
        mod.ratio = TRIANGLES / tris
        bpy.ops.object.modifier_apply(modifier=mod.name)
    for p in ob.data.polygons:
        p.use_smooth = True
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_apply=True, export_yup=True)
    print("TOILET %.2f x %.2f x %.2f m, %d triangles -> %s" % (hi.x - lo.x, hi.y - lo.y, hi.z - lo.z, tris, OUT))


main()
