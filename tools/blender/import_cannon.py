"""The clubhouse lawn's cannon, from the user's model (a Civil War field gun: a 857k-triangle .glb
with a 1024 px texture set per part) -> assets/facilities/props/cannon.glb

    blender -b --factory-startup --disable-autoexec -P tools/blender/import_cannon.py -- <civil_war_cannon.glb>

Far too heavy for a lawn ornament as it comes, so: each part's material flattened to the average
of its base-colour texture, then aged a century and a half (user; weathered): its grey metal --
the barrel -- a bronze gone green with patina, the darker iron fittings rusted, the wood of its
carriage greyed and dried out, none of it shiny (Godot adds a blotchy grime over the lot:
FacilityBuilder._cannon_mesh). The parts lightened to
about TRIANGLES in all, joined into one mesh, scaled so its wheels stand WHEEL m tall, turned so
its muzzle faces +Y here (-Z in Godot), centred on its footprint and stood on z = 0. The
clubhouses place it with a CANNON marker; FacilityBuilder stands the model there.
"""
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "assets", "facilities", "props", "cannon.glb")
TRIANGLES = 30000  # about this many once lightened
WHEEL = 1.45  # its wheels' height (m): a 12-pounder's


def base_colour(mat):
    """`mat`'s base colour (linear RGBA): its base-colour texture's average, else its own colour;
    its metallic and roughness."""
    col, metal, rough = (0.5, 0.5, 0.5, 1.0), 0.0, 0.6
    if mat is None or not mat.use_nodes:
        return col, metal, rough
    bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        return col, metal, rough
    col = tuple(bsdf.inputs["Base Color"].default_value)
    metal = float(bsdf.inputs["Metallic"].default_value)
    rough = float(bsdf.inputs["Roughness"].default_value)
    link = bsdf.inputs["Base Color"].links
    node = link[0].from_node if link else None
    while node is not None and node.type != "TEX_IMAGE" and node.inputs:
        ins = [i for i in node.inputs if i.links]
        node = ins[0].links[0].from_node if ins else None
    if node is not None and node.type == "TEX_IMAGE" and node.image is not None and node.image.size[0] > 0:
        px = np.array(node.image.pixels[:], dtype=np.float32).reshape(-1, 4)
        avg = px[:, :3].mean(axis=0)
        if node.image.colorspace_settings.name.lower().startswith("srgb"):
            avg = np.where(avg <= 0.04045, avg / 12.92, ((avg + 0.055) / 1.055) ** 2.4)
        col = (float(avg[0]), float(avg[1]), float(avg[2]), 1.0)
    return col, metal, rough


def _srgb(c):
    return tuple(x * 12.92 if x <= 0.0031308 else 1.055 * x ** (1 / 2.4) - 0.055 for x in c[:3])


def _lin(c):
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c[:3])


def weathered(col):
    """`col` (linear RGBA, a part's average) as it'd look on a gun stood out since the 1860s, with
    its metallic and roughness: grey metal -> verdigris bronze (the lighter: the barrel) or rusted
    iron (the darker); wood -> greyed, dried timber."""
    import colorsys
    r, g, b = _srgb(col)
    h, l, sat = colorsys.rgb_to_hls(r, g, b)
    if sat < 0.08:
        if l > 0.45:
            tone = 0.85 + (l - 0.45) * 0.8  # (lighter parts a touch lighter still)
            out, metal, rough = (0.35 * tone, 0.43 * tone, 0.36 * tone), 0.35, 0.8
        else:
            tone = 0.7 + l
            out, metal, rough = (0.30 * tone, 0.21 * tone, 0.15 * tone), 0.25, 0.92
    else:
        grey = (r + g + b) / 3.0
        out = tuple((x * 0.5 + grey * 0.5) * 1.12 + 0.03 for x in (r, g, b))  # (half the colour gone, sun-bleached)
        metal, rough = 0.0, 0.95
    return _lin(out) + (1.0,), metal, rough


def main():
    path = sys.argv[sys.argv.index("--") + 1]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    parts = [o for o in bpy.data.objects if o.type == "MESH"]
    # one flat material per look (texture averages a 16th apart merged)
    flat = {}
    for ob in parts:
        src = ob.data.materials[0] if ob.data.materials else None
        col, metal, rough = weathered(base_colour(src)[0])
        key = (tuple(round(c * 16) for c in col[:3]), round(metal * 4), round(rough * 4))
        if key not in flat:
            m = bpy.data.materials.new("cannon_%d" % len(flat))
            m.use_nodes = True
            b = m.node_tree.nodes["Principled BSDF"]
            b.inputs["Base Color"].default_value = col
            b.inputs["Metallic"].default_value = metal
            b.inputs["Roughness"].default_value = rough
            flat[key] = m
        ob.data.materials.clear()
        ob.data.materials.append(flat[key])
    # lighter, part by part (the small ones as they are)
    bpy.context.view_layer.update()
    total = sum(len(p.vertices) - 2 for ob in parts for p in ob.data.polygons)
    for ob in parts:
        tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
        ratio = max(TRIANGLES / total, min(1.0, 300.0 / max(tris, 1)))
        if ratio < 1.0:
            bpy.context.view_layer.objects.active = ob
            mod = ob.modifiers.new("collapse", "DECIMATE")
            mod.ratio = ratio
            bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.ops.object.select_all(action="DESELECT")
    for ob in parts:
        mw = ob.matrix_world.copy()  # (off the file's root, which stands it Y-up: where it is kept)
        ob.parent = None
        ob.matrix_world = mw
        ob.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = "Cannon"
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    vs = [v.co for v in ob.data.vertices]
    lo = Vector([min(v[k] for v in vs) for k in range(3)])
    hi = Vector([max(v[k] for v in vs) for k in range(3)])
    # its long way (barrel to trail) along Y, muzzle +Y: the end whose cross-section stands higher
    long_y = (hi.y - lo.y) >= (hi.x - lo.x)
    if not long_y:
        ob.data.transform(Matrix.Rotation(math.pi / 2, 4, "Z"))
        vs = [v.co for v in ob.data.vertices]
        lo = Vector([min(v[k] for v in vs) for k in range(3)])
        hi = Vector([max(v[k] for v in vs) for k in range(3)])
    mid_y = (lo.y + hi.y) * 0.5
    far = [v.z for v in vs if v.y > mid_y + (hi.y - mid_y) * 0.6]
    near = [v.z for v in vs if v.y < mid_y - (mid_y - lo.y) * 0.6]
    if far and near and min(far) < min(near):  # (the trail rests on the ground; the muzzle's up in the air)
        ob.data.transform(Matrix.Rotation(math.pi, 4, "Z"))
    vs = [v.co for v in ob.data.vertices]
    lo = Vector([min(v[k] for v in vs) for k in range(3)])
    hi = Vector([max(v[k] for v in vs) for k in range(3)])
    s = WHEEL / (hi.z - lo.z)
    ob.data.transform(Matrix.Scale(s, 4) @ Matrix.Translation((-(lo.x + hi.x) * 0.5, -(lo.y + hi.y) * 0.5, -lo.z)))
    for p in ob.data.polygons:
        p.use_smooth = True
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_apply=True, export_yup=True)
    d = (hi - lo) * s
    print("CANNON %.2f x %.2f x %.2f m, %d triangles, %d materials -> %s" % (d.x, d.y, d.z, tris, len(flat), OUT))


main()
