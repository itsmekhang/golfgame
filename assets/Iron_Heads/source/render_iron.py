"""Blender (Cycles, CPU) preview renders of an iron head's STL parts, headless.

blender -b --python render_iron.py -- <stl_dir> <out_dir> [view ...]
Address position, mm: toe -X, face -Y, up +Z, hosel toward +X.
"""
import math
import os
import sys

import bpy
from mathutils import Quaternion, Vector

args = sys.argv[sys.argv.index("--") + 1:]
stl_dir, out_dir = os.path.abspath(args[0]), os.path.abspath(args[1])
VIEWS = {  # direction the camera looks, up, centre (mm), ortho height (mm)
    "back": ((0, -1, 0), (0, 0, 1), (-23, 10, 36), 95),
    "back_low": ((-0.1, -1, 0.12), (0, 0, 1), (-23, 10, 33), 95),
    "back34": ((0.5, -0.8, -0.35), (0, 0, 1), (-23, 10, 33), 100),
    "heel_back": ((-0.45, -0.85, -0.2), (0, 0, 1), (10, 10, 28), 60),
    "toe_back": ((0.55, -0.8, -0.1), (0, 0, 1), (-55, 10, 24), 60),
    "face": ((0, 1, 0), (0, 0, 1), (-23, 0, 36), 95),
    "toe": ((1, 0, 0), (0, 0, 1), (-85, 8, 36), 80),
    "heel": ((-1, 0, 0), (0, 0, 1), (30, 8, 36), 80),
    "top": ((0, 0, -1), (0, 1, 0), (-23, 8, 30), 95),
    "sole": ((0, 0, 1), (0, 1, 0), (-23, 8, 10), 95),
    "hosel_back": ((-0.2, -1, -0.15), (0, 0, 1), (14, 8, 40), 62),
    "hosel_heel": ((-1, -0.25, -0.1), (0, 0, 1), (20, 8, 38), 70),
    "hosel_side_back": ((-0.75, -0.65, -0.1), (0, 0, 1), (16, 8, 36), 62),
    "hosel_front": ((-0.25, 1, -0.1), (0, 0, 1), (14, 0, 40), 62),
}
views = args[2:] or list(VIEWS)
os.makedirs(out_dir, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

MATS = {  # base colour, metallic, roughness
    "Body": ((0.66, 0.68, 0.71), 0.9, 0.28),
    "PortPlug": ((0.06, 0.06, 0.065), 0.8, 0.35),
    "MarkFill": ((0.02, 0.02, 0.022), 0.0, 0.6),
    "Ferrule": ((0.015, 0.015, 0.017), 0.3, 0.25),
    "Badge": ((0.20, 0.21, 0.23), 0.9, 0.45),
    "Insert": ((0.12, 0.13, 0.15), 0.8, 0.45),
    "Screws": ((0.70, 0.71, 0.73), 1.0, 0.25),
}
for name, (col, metal, rough) in MATS.items():
    path = os.path.join(stl_dir, name + ".obj")  # true normals (see build_irons.write_obj)
    if os.path.exists(path):
        bpy.ops.wm.obj_import(filepath=path, forward_axis="Y", up_axis="Z")
        obj = bpy.context.selected_objects[0]
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.shade_smooth(keep_sharp_edges=True)
    else:
        path = os.path.join(stl_dir, name + ".stl")
        if not os.path.exists(path):
            continue
        bpy.ops.wm.stl_import(filepath=path)
        obj = bpy.context.selected_objects[0]
        try:
            bpy.ops.object.shade_smooth_by_angle(angle=math.radians(30))
        except Exception:
            bpy.ops.object.shade_smooth()
    obj.name = name
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*col, 1)
    bsdf.inputs["Metallic"].default_value = metal
    bsdf.inputs["Roughness"].default_value = rough
    obj.data.materials.append(mat)

scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 40
scene.cycles.use_denoising = True
world = bpy.data.worlds.new("w")
scene.world = world
world.use_nodes = True
bg = world.node_tree.nodes["Background"]
bg.inputs["Color"].default_value = (0.12, 0.13, 0.15, 1)
bg.inputs["Strength"].default_value = 0.7
for name, d, e in [("key", (0.4, 0.9, 1.1), 2.6), ("fill", (-0.9, -1.0, 0.4), 0.7),
                   ("top", (0.0, 0.0, 1.0), 0.9), ("rim", (0.3, 0.7, -0.4), 0.6),
                   ("back", (-0.3, 1.0, 0.2), 1.0)]:
    ld = bpy.data.lights.new(name, "SUN")
    ld.energy = e
    lo = bpy.data.objects.new(name, ld)
    scene.collection.objects.link(lo)
    lo.rotation_euler = (-Vector(d)).to_track_quat("-Z", "Y").to_euler()
scene.render.resolution_x = 1000
scene.render.resolution_y = 760
cam_data = bpy.data.cameras.new("cam")
cam_data.type = "ORTHO"
cam_data.clip_start, cam_data.clip_end = 1.0, 5000.0
cam = bpy.data.objects.new("cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
for v in views:
    d, up, c, h = VIEWS[v]
    d = Vector(d).normalized()
    cam.location = Vector(c) - d * 600.0
    q = d.to_track_quat("-Z", "Y")
    cam_up = q @ Vector((0, 1, 0))
    want = Vector(up) - d * Vector(up).dot(d)
    ang = 0.0
    if want.length > 1e-6:
        want.normalize()
        ang = cam_up.angle(want)
        if d.dot(cam_up.cross(want)) < 0:
            ang = -ang
    cam.rotation_euler = (Quaternion(d, ang) @ q).to_euler()
    cam_data.ortho_scale = h * 1.32
    scene.render.filepath = os.path.join(out_dir, v + ".png")
    bpy.ops.render.render(write_still=True)
    print("rendered", v)
