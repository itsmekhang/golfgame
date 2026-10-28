"""Parked cars for the club's parking lot, from the user's car pack.

    blender -b --factory-startup -P tools/blender/import_cars.py -- <generic_passenger_car_pack.glb>

The pack lays its ten cars out in a ring (each car an empty "<Type> Body", its wheels loose
nodes beside it, each going to the car it's nearest). Each car is taken out with its wheels,
turned to face +Y here (-Z in Godot) -- its length is the long axis of its body, its front the
end away from the cabin's glass (a pickup's cab, a mid-engined sports car's cockpit and a city car's tall cabin are
forward, so the other way round) -- centred with
the tyres on z = 0 and joined into one mesh with all source polygons retained.
Colour textures are capped at TEX (WHEEL_TEX for wheels) and normal maps dropped. Writes
assets/facilities/props/cars/car_<type>.glb.
"""
import argparse
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "assets", "facilities", "props", "cars")
TEX = 1024
WHEEL_TEX = 512
CAB_FORWARD = ("pickup", "sport", "compact")


def bounds(obs):
    pts = [o.matrix_world @ v.co for o in obs for v in o.data.vertices]
    return Vector([min(p[i] for p in pts) for i in range(3)]), Vector([max(p[i] for p in pts) for i in range(3)])


def slim_materials(obs, size):
    """Shrink each material's colour texture, unhook its normal map."""
    for ob in obs:
        for mat in ob.data.materials:
            if mat is None or not mat.use_nodes:
                continue
            nt = mat.node_tree
            for n in list(nt.nodes):
                if n.type == "NORMAL_MAP":
                    nt.nodes.remove(n)
            for n in nt.nodes:
                if n.type == "TEX_IMAGE" and n.image is not None:
                    if n.image.colorspace_settings.name != "sRGB":
                        continue
                    if max(n.image.size) > size:
                        n.image.scale(size, size)


def car_type(name):
    return name.replace(" Body", "").replace(" body", "").strip().lower().replace(" ", "_")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source")
    parser.add_argument("--only", choices=("sedan", "suv", "hatchback", "wagon", "minivan", "pickup", "compact", "coupe", "offroad", "sport"))
    parser.add_argument("--out", default=OUT)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    src = args.source
    os.makedirs(args.out, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    cars = [o for o in bpy.data.objects if o.type == "EMPTY" and o.name.lower().endswith(" body")]
    wheels = [o for o in bpy.data.objects if o.type == "MESH" and "Wheel" in o.name]
    centres = {}
    for car in cars:
        lo, hi = bounds([o for o in car.children_recursive if o.type == "MESH"])
        centres[car.name] = (lo + hi) * 0.5
    owner = {}
    for w in wheels:
        wl, wh = bounds([w])
        c = (wl + wh) * 0.5
        owner[w.name] = min(centres, key=lambda k: ((centres[k] - c).xy).length)
    for car in cars:
        name = car_type(car.name)
        if args.only and name != args.only:
            continue
        parts = [o for o in car.children_recursive if o.type == "MESH"]
        mine = []
        for w in wheels:
            if owner[w.name] != car.name:
                continue
            wl, wh = bounds([w])
            if all((((wl + wh) * 0.5) - k).length > 0.05 for k in [(a + b) * 0.5 for a, b in (bounds([m]) for m in mine)]):
                mine.append(w)  # the pack doubles some wheels in place: one of each
        body = [o for o in parts if "Glass" not in o.name and "Optics" not in o.name]
        glass = [o for o in parts if "Glass" in o.name]
        # the body's long axis (principal axis of its footprint) and which end is the front
        pts = [(o.matrix_world @ v.co).xy for o in body for v in o.data.vertices]
        c = sum(pts, Vector((0, 0))) / len(pts)
        sxx = sum((p.x - c.x) ** 2 for p in pts)
        syy = sum((p.y - c.y) ** 2 for p in pts)
        sxy = sum((p.x - c.x) * (p.y - c.y) for p in pts)
        ang = 0.5 * math.atan2(2 * sxy, sxx - syy)
        u = Vector((math.cos(ang), math.sin(ang)))
        blo, bhi = bounds(body)
        mid = ((blo + bhi) * 0.5).xy
        gl, gh = bounds(glass)
        cabin = ((gl + gh) * 0.5).xy - mid
        if (cabin.dot(u) > 0) != car.name.lower().startswith(CAB_FORWARD):
            u = -u  # the front is the end away from the cabin (bar the cab-forward ones)
        turn = math.pi / 2 - math.atan2(u.y, u.x)
        to_local = Matrix.Rotation(turn, 4, "Z") @ Matrix.Translation((-mid.x, -mid.y, 0.0))
        objs = []
        for o in parts + mine:
            dup = o.copy()
            dup.data = o.data.copy()
            bpy.context.scene.collection.objects.link(dup)
            dup.parent = None
            dup.matrix_world = to_local @ o.matrix_world
            bpy.ops.object.select_all(action="DESELECT")
            dup.select_set(True)
            bpy.context.view_layer.objects.active = dup
            bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
            # Preserve the source body panels, wheel arches, rims and tyres.
            objs.append(dup)
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.object.join()
        ob = bpy.context.view_layer.objects.active
        pts = [v.co for v in ob.data.vertices]
        clo = Vector([min(p[i] for p in pts) for i in range(3)])
        chi = Vector([max(p[i] for p in pts) for i in range(3)])
        ob.data.transform(Matrix.Translation((-(clo.x + chi.x) * 0.5, -(clo.y + chi.y) * 0.5, -clo.z)))
        name = car_type(car.name)
        ob.name = "car_" + name
        ob.data.name = "car_" + name
        slim_materials([ob], TEX)
        for mat in ob.data.materials:
            if mat and mat.name.lower().startswith(("wheel", "wheek")):
                for n in mat.node_tree.nodes:
                    wheel_size = WHEEL_TEX
                    if n.type == "TEX_IMAGE" and n.image is not None and max(n.image.size) > wheel_size:
                        n.image.scale(wheel_size, wheel_size)
        bpy.ops.object.select_all(action="DESELECT")
        ob.select_set(True)
        path = os.path.join(args.out, "car_%s.glb" % name)
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_image_format="JPEG", export_image_quality=85)
        size = chi - clo
        print("CAR %-10s %.2f x %.2f x %.2f m, %d wheel parts, %d tris -> %s" % (name, size.y, size.x, size.z, len(mine), sum(len(p.vertices) - 2 for p in ob.data.polygons), os.path.basename(path)))
        bpy.data.objects.remove(ob)


main()
