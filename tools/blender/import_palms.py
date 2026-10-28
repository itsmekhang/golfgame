"""The clubhouse drives' palms, from the user's low-poly palm pack (three palms, each a root flare,
a trunk and a crown of fronds, textured) -> assets/facilities/props/palm_a.glb, palm_b.glb,
palm_c.glb

    blender -b --factory-startup --disable-autoexec -P tools/blender/import_palms.py -- <palm_tree_pack_lowpoly.glb>

Each palm's parts joined into one mesh, stood on z = 0 with its trunk's foot at the origin, its
fronds' texture cut out by its alpha (no see-through blending), and written as its own .glb. The
clubhouses plant them with PALM_A / PALM_B / PALM_C markers; FacilityBuilder stands them there.
"""
import os
import sys

import bpy
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "assets", "facilities", "props", "palm_%s.glb")


def main():
    path = sys.argv[sys.argv.index("--") + 1]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    bpy.context.view_layer.update()
    groups = {}
    for ob in bpy.data.objects:
        if ob.type == "MESH":
            groups.setdefault(ob.name.split("_")[0], []).append(ob)
    for m in bpy.data.materials:
        if "frond" in m.name.lower():
            m.blend_method = "CLIP"  # (glTF MASK: its leaves cut out of the card, no sorting)
            m.alpha_threshold = 0.5
    for k, name in enumerate(sorted(groups)):
        parts = groups[name]
        bpy.ops.object.select_all(action="DESELECT")
        for ob in parts:
            ob.select_set(True)
            mw = ob.matrix_world.copy()
            ob.parent = None
            ob.matrix_world = mw
        bpy.context.view_layer.objects.active = parts[0]
        bpy.ops.object.join()
        ob = bpy.context.view_layer.objects.active
        ob.name = "Palm"
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        vs = [v.co for v in ob.data.vertices]
        z0 = min(v.z for v in vs)
        foot = [v for v in vs if v.z < z0 + 0.5]  # (its root flare: where it stands)
        cx = (min(v.x for v in foot) + max(v.x for v in foot)) * 0.5
        cy = (min(v.y for v in foot) + max(v.y for v in foot)) * 0.5
        ob.data.transform(Matrix.Translation((-cx, -cy, -z0)))
        out = OUT % "abc"[k]
        os.makedirs(os.path.dirname(out), exist_ok=True)
        bpy.ops.object.select_all(action="DESELECT")
        ob.select_set(True)
        bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_apply=True, export_yup=True)
        vs = [v.co for v in ob.data.vertices]
        print("PALM %s (%s): %.1f m tall, crown %.1f m across, %d triangles -> %s" % ("abc"[k], name, max(v.z for v in vs),
              max(v.x for v in vs) - min(v.x for v in vs), sum(len(p.vertices) - 2 for p in ob.data.polygons), out))
        bpy.data.objects.remove(ob)


main()
