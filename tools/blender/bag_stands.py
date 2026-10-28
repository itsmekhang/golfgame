"""Golf bags standing on their legs, made from the bag props in assets/facilities/props/bags:

- golf_bag_carry_<livery>_stand.glb: a golfer's carry bag set down to play -- leant back onto a
  pair of stand legs swung out of its back, the clubs leaning with it (ClubLife swaps the slung
  bag for it while its golfer plays).
- golf_bag_range_stand_<livery>.glb: the range's stand bags with their clubs re-aimed down the
  bag's own lean (they stood bolt upright out of a leaning bag). Safe to run again: clubs that
  already follow the bag are left as they are.

    blender -b --factory-startup --python tools/blender/bag_stands.py
"""
import math
import os

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BAGS = os.path.join(ROOT, "assets", "facilities", "props", "bags")
CARRY = ("navy", "green", "red", "black")
RANGE = ("grey", "olive", "sky")
LEAN = math.radians(17.0)  # a stand bag leans back this far onto its legs


def load(path):
    """The glb's meshes joined into one object, its transforms applied (Blender Z up; the
    bag's pockets toward -Y)."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    obs = [o for o in bpy.data.objects if o.type == "MESH"]
    for o in bpy.data.objects:
        o.select_set(o in obs)
    bpy.context.view_layer.objects.active = obs[0]
    if len(obs) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.parent = None
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for o in list(bpy.data.objects):
        if o is not ob:
            bpy.data.objects.remove(o, do_unlink=True)
    return ob


def export(path):
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_tangents=True,
                              export_image_format="AUTO", use_selection=False)
    print("EXPORTED", path)


def rod(bm, a, b, r, segs=8):
    d = b - a
    m = Matrix.Translation((a + b) * 0.5) @ d.to_track_quat("Z", "Y").to_matrix().to_4x4()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r, radius2=r, depth=d.length, matrix=m)


def metal(name, rgb, metallic, rough):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1.0)
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Roughness"].default_value = rough
    return m


def slice_centre(pts, z, half=0.025, keep=0.16):
    """The middle of the bag's body at height z (stray legs and straps far from it left out)."""
    band = [p for p in pts if abs(p.z - z) < half]
    if not band:
        return None
    mx = float(np.median([p.x for p in band]))
    my = float(np.median([p.y for p in band]))
    near = [p for p in band if math.hypot(p.x - mx, p.y - my) < keep]
    return sum(near, Vector()) / len(near)


def carry_stand(liv):
    ob = load(os.path.join(BAGS, "golf_bag_carry_%s.glb" % liv))
    me = ob.data
    vs = [v.co.copy() for v in me.vertices]
    zlo = min(v.z for v in vs)
    H = max(v.z for v in vs) - zlo
    # the legs' hinge, high on the back (+Y) of the bag body (the clubs stand above 0.75 H)
    hz = zlo + 0.52 * H
    band = [v for v in vs if abs(v.z - hz) < 0.03]
    cx = float(np.median([v.x for v in band]))
    hinge0 = Vector((cx, max(v.y for v in band if abs(v.x - cx) < 0.06) - 0.01, hz))
    # leant back about the front edge of its base
    foot = [v for v in vs if v.z < zlo + 0.04]
    piv = Vector((cx, min(v.y for v in foot), zlo))
    R = Matrix.Translation(piv) @ Matrix.Rotation(-LEAN, 4, "X") @ Matrix.Translation(-piv)
    me.transform(R)
    drop = Matrix.Translation((0.0, 0.0, -min(v.co.z for v in me.vertices)))
    me.transform(drop)
    hinge = drop @ R @ hinge0
    # two legs from the hinge to feet splayed behind it on the ground, a bracket and rubber feet
    bm = bmesh.new()
    for s in (-1, 1):
        top = hinge + Vector((s * 0.045, 0.012, 0.0))
        toe = Vector((cx + s * 0.17, hinge.y + 0.3, 0.012))
        rod(bm, top, toe, 0.0085)
        rod(bm, toe + Vector((0, 0, -0.01)), toe + Vector((0, 0, 0.03)), 0.016)
    rod(bm, hinge + Vector((-0.07, 0.012, 0.0)), hinge + Vector((0.07, 0.012, 0.0)), 0.014)
    legs = bpy.data.meshes.new("stand_legs")
    bm.to_mesh(legs)
    bm.free()
    lo = bpy.data.objects.new("stand_legs", legs)
    bpy.context.scene.collection.objects.link(lo)
    legs.materials.append(metal("stand_legs", (0.05, 0.05, 0.055), 0.7, 0.35))
    for o in bpy.data.objects:
        o.select_set(o in (ob, lo))
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.join()
    ob.name = "golf_bag"
    export(os.path.join(BAGS, "golf_bag_carry_%s_stand.glb" % liv))


def range_bag(liv):
    path = os.path.join(BAGS, "golf_bag_range_stand_%s.glb" % liv)
    ob = load(path)
    me = ob.data
    bag_mats = {i for i, m in enumerate(me.materials) if m is not None and m.name.startswith("bag_")}
    bm = bmesh.new()
    bm.from_mesh(me)
    club_v = {v for f in bm.faces if f.material_index not in bag_mats for v in f.verts}
    bag_pts = [v.co.copy() for v in bm.verts if v not in club_v]
    if not club_v:
        print("NO CLUBS", path)
        return
    zlo = min(p.z for p in bag_pts)
    zhi = max(p.z for p in bag_pts)
    c1 = slice_centre(bag_pts, zlo + 0.35 * (zhi - zlo))
    c2 = slice_centre(bag_pts, zlo + 0.8 * (zhi - zlo))
    axis = (c2 - c1).normalized()
    mouth = slice_centre(bag_pts, zhi - 0.03, 0.03, 0.2)
    # the clubs' own axis, and where it goes into the bag
    P = np.array([tuple(v.co) for v in club_v])
    mean = P.mean(axis=0)
    w, V = np.linalg.eigh(np.cov((P - mean).T))
    ax = Vector(V[:, int(np.argmax(w))])
    if ax.z < 0:
        ax = -ax
    mean = Vector(mean)
    low = min(((v.co - mean).dot(ax) for v in club_v))
    base = mean + ax * low
    depth = max(mouth.z - base.z, 0.08)
    M = Matrix.Translation(mouth - axis * depth) @ ax.rotation_difference(axis).to_matrix().to_4x4() @ Matrix.Translation(-base)
    for v in club_v:
        v.co = M @ v.co
    bm.to_mesh(me)
    bm.free()
    print("RANGE %s: clubs %.1f deg off the bag, now along it" % (liv, math.degrees(ax.angle(axis))))
    export(path)


for liv in CARRY:
    carry_stand(liv)
for liv in RANGE:
    range_bag(liv)
