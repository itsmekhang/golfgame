"""The grounds' street lamp, from the user's model (a textured lamp post, in centimetres)
-> assets/facilities/props/street_lamp.glb

    blender -b --factory-startup --disable-autoexec -P tools/blender/import_street_lamp.py -- <street_lamp.glb>

Off the file's root (its parts kept where it stands them), joined into one mesh, scaled to HEIGHT
m to the top of its lantern -- the old lamp's (fm_lib.lamp: a 3.4 m post and its lantern) -- its
post's foot at the origin on z = 0. fm_lib.lamp places it with a STREET_LAMP marker (its scale the
post's height over the 3.4 m it's made for); FacilityBuilder stands the model there. Lit (user):
its lantern's panes -- the pale, tinted faces up in its top quarter, by its texture under them --
glow a warm white (their own material, emissive).
"""
import os
import sys

import colorsys

import bpy
import numpy as np
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "assets", "facilities", "props", "street_lamp.glb")
HEIGHT = 3.9
GLOW = (1.0, 0.86, 0.6, 1.0)  # (linear: a warm lamp's light)


def light_lantern(ob, z0, z1):
    """The lantern's panes their own glowing material: faces in the lamp's top quarter whose
    texture under them is pale and tinted (glass), not grey (the iron round them)."""
    mat = ob.data.materials[0]
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    img = bsdf.inputs["Base Color"].links[0].from_node.image
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    uv = ob.data.uv_layers.active.data
    glass = bpy.data.materials.new("lamp_glass")
    glass.use_nodes = True
    b = glass.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = GLOW
    b.inputs["Emission Color"].default_value = GLOW
    b.inputs["Emission Strength"].default_value = 3.0
    b.inputs["Roughness"].default_value = 0.3
    ob.data.materials.append(glass)
    k = len(ob.data.materials) - 1
    lit = 0
    for p in ob.data.polygons:
        if p.center.z < z0 + (z1 - z0) * 0.75:
            continue
        u = sum(uv[i].uv[0] for i in p.loop_indices) / p.loop_total
        v = sum(uv[i].uv[1] for i in p.loop_indices) / p.loop_total
        c = px[int((v % 1) * (h - 1)), int((u % 1) * (w - 1)), :3]
        _h, l, sat = colorsys.rgb_to_hls(*c)
        if sat >= 0.15 and l >= 0.55:
            p.material_index = k
            lit += 1
    return lit


def main():
    path = sys.argv[sys.argv.index("--") + 1]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    bpy.context.view_layer.update()
    parts = [o for o in bpy.data.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for ob in parts:
        mw = ob.matrix_world.copy()
        ob.parent = None
        ob.matrix_world = mw
        ob.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    if len(parts) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = "StreetLamp"
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    vs = [v.co for v in ob.data.vertices]
    z0, z1 = min(v.z for v in vs), max(v.z for v in vs)
    foot = [v for v in vs if v.z < z0 + (z1 - z0) * 0.05]  # (its base: where it stands)
    cx = (min(v.x for v in foot) + max(v.x for v in foot)) * 0.5
    cy = (min(v.y for v in foot) + max(v.y for v in foot)) * 0.5
    lit = light_lantern(ob, z0, z1)
    s = HEIGHT / (z1 - z0)
    ob.data.transform(Matrix.Scale(s, 4) @ Matrix.Translation((-cx, -cy, -z0)))
    for p in ob.data.polygons:
        p.use_smooth = True
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_apply=True, export_yup=True)
    vs = [v.co for v in ob.data.vertices]
    print("STREET LAMP %.2f x %.2f x %.2f m, %d triangles, %d lantern panes lit -> %s" % (max(v.x for v in vs) - min(v.x for v in vs), max(v.y for v in vs) - min(v.y for v in vs),
          max(v.z for v in vs), sum(len(p.vertices) - 2 for p in ob.data.polygons), lit, OUT))


main()
