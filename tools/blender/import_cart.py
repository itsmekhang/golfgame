"""The club's golf cart, from the user's model with the rear bag well and bag holders.

    blender -b --factory-startup -P tools/blender/import_cart.py -- <cart.glb>

Joins the model into one mesh (so the cart barn batches it as one), turns it to face +Y here
(-Z in Godot), scales it so a seated golfer clears the roof (SCALE: the seat cushion lands
0.83 m up, the roof frame 1.81 m) and centres it on its footprint with the wheels on z = 0.
Writes assets/facilities/props/golf_cart.glb and prints, in Godot's frame (x right, y up,
z back), what ClubLife and the people's seated poses are fitted to: the seat cushion, the
floor, the steering wheel and the two bag trays with their cradle rings.
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "assets", "facilities", "props", "golf_cart.glb")
SCALE = 0.0215  # source units to metres


def join_all():
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    for o in meshes:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
    for o in [o for o in bpy.data.objects if o.type != "MESH"]:
        bpy.data.objects.remove(o)
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return ob


def godot(v):
    return Vector((v.x, v.z, -v.y))


def report(ob, named):
    """Where the parts the game fits to ended up (Godot frame)."""
    me = ob.data
    up = {}
    for p in me.polygons:
        mat = me.materials[p.material_index].name if me.materials else ""
        if p.normal.z > 0.8:
            up.setdefault(mat, []).append((p.center.copy(), p.area))
    seat = [c for c, a in up.get("Warm saddle tan upholstery", []) if c.z < 1.0]
    zs = sorted(c.z for c in seat)
    top = zs[len(zs) // 2]
    ys = [c.y for c in seat if abs(c.z - top) < 0.03]
    print("SEAT cushion top %.3f m, front edge z %.3f, back edge z %.3f (Godot z)" % (top, -max(ys), -min(ys)))
    floor = [c for c, a in up.get("golfcart", []) if c.z < 0.4 and a > 0.05]
    fz = sorted(c.z for c in floor)
    print("FLOOR heights (large up faces under 0.4 m):", sorted(set(round(z, 2) for z in fz))[:8])
    for name, (lo, hi) in named.items():
        c = (lo + hi) * 0.5
        print("PART %-24s centre %s  size %s" % (name, tuple(round(x, 3) for x in godot(c)), tuple(round(abs(x), 3) for x in godot(hi - lo))))


def main():
    src = sys.argv[sys.argv.index("--") + 1:][0]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    # the parts we fit to, by their source names (bounds, before joining)
    named = {}
    for o in bpy.data.objects:
        if o.type == "MESH" and any(k in o.name for k in ("bag tray", "upper bag cradle")):
            pts = [o.matrix_world @ v.co for v in o.data.vertices]
            named[o.name] = (Vector([min(p[i] for p in pts) for i in range(3)]), Vector([max(p[i] for p in pts) for i in range(3)]))
    ob = join_all()
    xf = Matrix.Rotation(-math.pi / 2, 4, "Z") @ Matrix.Scale(SCALE, 4)
    ob.data.transform(xf)
    pts = [v.co for v in ob.data.vertices]
    lo = Vector([min(p[i] for p in pts) for i in range(3)])
    hi = Vector([max(p[i] for p in pts) for i in range(3)])
    shift = Matrix.Translation((-(lo.x + hi.x) * 0.5, -(lo.y + hi.y) * 0.5, -lo.z))
    ob.data.transform(shift)
    ob.data.update()
    for k, (a, b) in named.items():
        a2, b2 = shift @ (xf @ a), shift @ (xf @ b)
        named[k] = (Vector([min(a2[i], b2[i]) for i in range(3)]), Vector([max(a2[i], b2[i]) for i in range(3)]))
    ob.name = "golf_cart"
    ob.data.name = "golf_cart"
    size = hi - lo
    print("CART %.2f long, %.2f wide, %.2f tall; %d tris" % (size.y, size.x, size.z, sum(len(p.vertices) - 2 for p in ob.data.polygons)))
    report(ob, named)
    # the steering wheel: the ring of vertices up in the driver's half of the cab
    ring = [v.co for v in ob.data.vertices if 0.95 < v.co.z < 1.5 and v.co.y > 0.2]
    if ring:
        c = sum(ring, Vector()) / len(ring)
        side = [p for p in ring if (p.x > 0) == (c.x > 0)]
        cs = sum(side, Vector()) / len(side)
        print("WHEEL region centre %s (n=%d)" % (tuple(round(x, 3) for x in godot(cs)), len(side)))
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=False)
    print("WROTE", OUT)


main()
