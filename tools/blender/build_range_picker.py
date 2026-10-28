"""The driving range's ball picker: the club's golf cart (assets/facilities/props/golf_cart.glb, the
user's model as import_cart.py leaves it) with a protective cage over its cab -- a black tube frame
and wire-mesh panels, the lower doorways left open to climb in -- its bag holder taken off (it
carries balls, not bags), and a three-gang picker towed
behind it on a hitch: rows of rubber pick-up discs in black frames, a see-through wire basket on
each that ClubLife fills with the balls it picks up (its PICKER_BASKETS, inside these walls).

    blender -b --factory-startup -P tools/blender/build_range_picker.py

Writes assets/facilities/props/range_picker.glb. The cart keeps its frame (front +Y here, -Z in
Godot; wheels on z = 0), so ClubLife's seats and wheels fit it as they do the cart; the gang's
middle, where the balls are picked up, is GANG_Y behind the cart's (+GANG_Y in Godot's z).
"""
import math
import os

import bmesh
import bpy
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
CART = os.path.join(ROOT, "assets", "facilities", "props", "golf_cart.glb")
OUT = os.path.join(ROOT, "assets", "facilities", "props", "range_picker.glb")
GANG_Y = 2.45  # m behind the cart's middle: the discs' axle
CAB = (0.66, -0.72, 0.74)  # the cage's posts: x either side, y back and front of the cab
ROOF = 1.88  # the cage's top, just over the cart's roof frame (1.81 m)


def material(name, hex_colour, rough=0.6, metal=0.0, alpha=1.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    # the hex is the colour as it shows (sRGB); the shader takes it linear
    c = tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in (int(hex_colour[i:i + 2], 16) / 255.0 for i in (0, 2, 4)))
    bsdf.inputs["Base Color"].default_value = (c[0], c[1], c[2], 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
        if hasattr(m, "surface_render_method"):
            m.surface_render_method = "BLENDED"
        elif hasattr(m, "blend_method"):
            m.blend_method = "BLEND"
    return m


MATS = {}


def mat(name):
    return MATS[name]


PARTS = []


def box(size, centre, m, rot=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=centre, rotation=rot)
    ob = bpy.context.active_object
    ob.scale = size
    ob.data.materials.append(mat(m))
    PARTS.append(ob)
    return ob


def tube(a, b, r, m, segs=8):
    a, b = Vector(a), Vector(b)
    d = b - a
    bpy.ops.mesh.primitive_cylinder_add(vertices=segs, radius=r, depth=d.length, location=(a + b) * 0.5)
    ob = bpy.context.active_object
    ob.rotation_mode = "QUATERNION"
    ob.rotation_quaternion = d.to_track_quat("Z", "Y")
    ob.data.materials.append(mat(m))
    PARTS.append(ob)
    return ob


def disc(centre, r, thick, m, segs=14):
    bpy.ops.mesh.primitive_cylinder_add(vertices=segs, radius=r, depth=thick, location=centre, rotation=(0.0, math.pi / 2, 0.0))
    ob = bpy.context.active_object
    ob.data.materials.append(mat(m))
    PARTS.append(ob)
    return ob


def strip_bag_rack(obs):
    """The cart's bag holder off: every piece of its rack (the black steel, the stainless
    fasteners, the rubber liners) that rises above the bed it stands in -- the uprights, the
    cradle and its rings -- leaving the empty bed."""
    for ob in obs:
        if ob.type != "MESH":
            continue
        names = [m.name if m else "" for m in ob.data.materials]
        rack = {i for i, n in enumerate(names) if n.startswith("Rack - ")}
        if not rack:
            continue
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        seen, doomed = set(), []
        for f in bm.faces:
            if f.material_index not in rack or f in seen:
                continue
            part, stack = [], [f]
            seen.add(f)
            while stack:
                g = stack.pop()
                part.append(g)
                for e in g.edges:
                    for h in e.link_faces:
                        if h.material_index in rack and h not in seen:
                            seen.add(h)
                            stack.append(h)
            top = max((ob.matrix_world @ v.co).z for g in part for v in g.verts)
            if not (names[part[0].material_index] == "Rack - black powder coated steel" and top < 0.6):
                doomed.extend(part)
        bmesh.ops.delete(bm, geom=doomed, context="FACES")
        bm.to_mesh(ob.data)
        bm.free()
        print("BAG_RACK off: %d faces" % len(doomed))


def cage():
    """A tube frame round the cab, mesh over its top, front, back and the upper sides."""
    x, y0, y1 = CAB
    for sx in (-x, x):
        for y in (y0, y1):
            tube((sx, y, 0.32), (sx, y, ROOF), 0.022, "steel_black")
        tube((sx, y0, ROOF), (sx, y1, ROOF), 0.022, "steel_black")
        tube((sx, y0, 1.15), (sx, y1, 1.15), 0.016, "steel_black")  # the side rail over the doorway
    for y in (y0, y1):
        tube((-x, y, ROOF), (x, y, ROOF), 0.022, "steel_black")
        tube((-x, y, 0.95), (x, y, 0.95), 0.016, "steel_black")
    for k in range(1, 5):  # roof bows
        y = y0 + (y1 - y0) * k / 5
        tube((-x, y, ROOF), (x, y, ROOF), 0.014, "steel_black")
    # the wire mesh: top, front (over the windscreen), back, and each side above its rail
    box((2 * x, y1 - y0, 0.006), (0, (y0 + y1) * 0.5, ROOF + 0.01), "wire")
    box((2 * x, 0.006, ROOF - 0.95), (0, y1 + 0.01, (ROOF + 0.95) * 0.5), "wire")
    box((2 * x, 0.006, ROOF - 0.95), (0, y0 - 0.01, (ROOF + 0.95) * 0.5), "wire")
    for sx in (-x, x):
        box((0.006, y1 - y0, ROOF - 1.15), (sx + math.copysign(0.01, sx), (y0 + y1) * 0.5, (ROOF + 1.15) * 0.5), "wire")
    for k in range(1, 6):  # a few heavier vertical bars over the front mesh
        bx = -x + 2 * x * k / 6
        tube((bx, y1 + 0.015, 0.95), (bx, y1 + 0.015, ROOF), 0.008, "steel_black", 6)


def gang():
    """Three picker sections abreast behind the cart on a hitch and a cross frame."""
    tube((0, -1.25, 0.32), (0, -GANG_Y + 0.42, 0.34), 0.03, "steel_black")  # the hitch
    cross_y = -GANG_Y + 0.4
    box((2.75, 0.07, 0.07), (0, cross_y, 0.36), "picker_frame")
    for sx in (-0.9, 0.0, 0.9):
        # an arm back from the cross frame to the section's axle
        box((0.05, 0.42, 0.05), (sx, (cross_y + -GANG_Y) * 0.5, 0.30), "picker_frame")
        # the discs on their axle, a frame plate either end
        n = 16
        for i in range(n):
            disc((sx - 0.38 + 0.76 * i / (n - 1), -GANG_Y, 0.15), 0.15, 0.022, "rubber")
        tube((sx - 0.42, -GANG_Y, 0.15), (sx + 0.42, -GANG_Y, 0.15), 0.012, "steel_black", 6)
        for ex in (sx - 0.42, sx + 0.42):
            box((0.02, 0.34, 0.30), (ex, -GANG_Y, 0.17), "picker_frame")
        # the basket the balls ride up into, over the discs
        box((0.84, 0.36, 0.008), (sx, -GANG_Y, 0.33), "picker_frame")
        box((0.84, 0.006, 0.24), (sx, -GANG_Y + 0.18, 0.45), "wire")
        box((0.84, 0.006, 0.24), (sx, -GANG_Y - 0.18, 0.45), "wire")
        for ex in (sx - 0.42, sx + 0.42):
            box((0.006, 0.36, 0.24), (ex, -GANG_Y, 0.45), "wire")
        box((0.86, 0.03, 0.03), (sx, -GANG_Y + 0.18, 0.57), "picker_frame")
        box((0.86, 0.03, 0.03), (sx, -GANG_Y - 0.18, 0.57), "picker_frame")


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=CART)
    cart_objects = list(bpy.data.objects)
    strip_bag_rack(cart_objects)
    MATS.update({
        "steel_black": material("picker_steel", "16181a", 0.5, 0.3),
        "wire": material("picker_wire_mesh", "141516", 0.6, 0.2, 0.5),
        "picker_frame": material("picker_frame", "121314", 0.6, 0.05),
        "rubber": material("picker_rubber", "1b1b1b", 0.85),
    })
    cage()
    gang()
    bpy.ops.object.select_all(action="DESELECT")
    for ob in PARTS:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = PARTS[0]
    bpy.ops.object.join()
    picker = bpy.context.view_layer.objects.active
    picker.name = "PickerCageAndGang"
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True)
    print("RANGE_PICKER %d cart objects + cage and gang (%d faces) -> %s (%d bytes)" % (len(cart_objects), len(picker.data.polygons), OUT, os.path.getsize(OUT)))


main()
