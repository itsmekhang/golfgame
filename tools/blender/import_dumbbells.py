"""The spa gym's dumbbell rack, from the user's model (Dumbbells_OBJ.obj, millimetres).

    blender -b --factory-startup -P tools/blender/import_dumbbells.py -- <Dumbbells_OBJ.obj>

The OBJ comes in on its back (height along its Y, the trays above the base): it is stood up,
turned so its front (the side the lower tray reaches out to) faces +Y here (-Z in Godot, the
way displays face; the gym places it with a DUMBBELL_RACK marker), scaled to metres, centred
on its footprint on z = 0 and joined into one mesh. Materials by part: the dumbbells' heads
black rubber and their handles chrome (a dumbbell piece's faces near its own axis), the frame
and trays dark graphite. Writes assets/facilities/props/dumbbell_rack.glb.
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "assets", "facilities", "props", "dumbbell_rack.glb")
MATS = {  # name: (sRGB hex, roughness, metallic)
    "rack_frame": ("2b2e31", 0.45, 0.6),
    "dumbbell_rubber": ("1a1b1c", 0.8, 0.0),
    "dumbbell_chrome": ("c9ccd0", 0.18, 1.0),
}
PIECE = 0.35  # parts no longer than this (m) are dumbbell pieces
HANDLE_R = 0.028  # a piece's faces this close to its axis are the handle


def material(name):
    hexs, rough, metal = MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    rgb = [int(hexs[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    b.inputs["Base Color"].default_value = (*[c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in rgb], 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    return m


def bounds(pts):
    return Vector([min(p[i] for p in pts) for i in range(3)]), Vector([max(p[i] for p in pts) for i in range(3)])


def main():
    src = sys.argv[sys.argv.index("--") + 1:][0]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.wm.obj_import(filepath=src, use_split_groups=True)
    obs = [o for o in bpy.data.objects if o.type == "MESH"]
    # stand it up (its height runs along -Y as imported) and into metres
    xf = Matrix.Rotation(-math.pi / 2, 4, "X") @ Matrix.Scale(0.001, 4) @ obs[0].matrix_world
    for o in obs:
        o.data.transform(xf)
        o.matrix_world = Matrix.Identity(4)
    # the front: where the lower of the two trays (the long flat parts) reaches out to
    trays = []
    for o in obs:
        lo, hi = bounds([v.co for v in o.data.vertices])
        if hi.x - lo.x > 1.5:
            trays.append((lo + hi) * 0.5)
    trays.sort(key=lambda c: c.z)
    if len(trays) >= 2 and trays[0].y < trays[-1].y:
        for o in obs:
            o.data.transform(Matrix.Rotation(math.pi, 4, "Z"))
    lo, hi = bounds([v.co for o in obs for v in o.data.vertices])
    shift = Matrix.Translation((-(lo.x + hi.x) * 0.5, -(lo.y + hi.y) * 0.5, -lo.z))
    mats = {k: material(k) for k in MATS}
    for o in obs:
        o.data.transform(shift)
        o.data.materials.clear()
        for k in MATS:
            o.data.materials.append(mats[k])
        plo, phi = bounds([v.co for v in o.data.vertices])
        size = phi - plo
        if max(size) > PIECE:
            for p in o.data.polygons:
                p.material_index = 0
            continue
        # a dumbbell piece: its axis is the dimension unlike the other two (a cylinder's length)
        dims = sorted(range(3), key=lambda i: size[i])
        axis = dims[0] if abs(size[dims[0]] - size[dims[1]]) > abs(size[dims[2]] - size[dims[1]]) else dims[2]
        c = (plo + phi) * 0.5
        for p in o.data.polygons:
            d = p.center - c
            d[axis] = 0.0
            p.material_index = 2 if d.length < HANDLE_R else 1
    bpy.ops.object.select_all(action="DESELECT")
    for o in obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = ob.data.name = "dumbbell_rack"
    for p in ob.data.polygons:
        p.use_smooth = True
    ob.data.set_sharp_from_angle(angle=math.radians(40))
    size = hi - lo
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=False)
    print("DUMBBELL RACK %.2f long x %.2f deep x %.2f tall, %d tris -> %s" % (size.x, size.y, size.z, sum(len(p.vertices) - 2 for p in ob.data.polygons), OUT))


main()
