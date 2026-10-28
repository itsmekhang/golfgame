"""Blender (Cycles, CPU) preview renders of the driver's STL parts, headless.

blender -b --python render_driver.py -- <stl_dir> <out_dir> [view ...]
Views (orthographic, address position: toe -X, face -Y, up +Z): face, front34, hosel_close,
heel34, top, sole, toe_close, heel_under_close, rear34.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
stl_dir, out_dir = os.path.abspath(args[0]), os.path.abspath(args[1])
VIEWS = {  # direction the camera looks, up, centre (mm), ortho height (mm)
    "face": ((0, 1, 0), (0, 0, 1), (2, 0, 38), 175),
    "front34": ((0.55, 0.7, -0.45), (0, 0, 1), (0, 40, 30), 185),
    "hosel_close": ((-0.35, 0.8, -0.3), (0, 0, 1), (42, 15, 40), 80),
    "heel34": ((-0.6, 0.62, -0.42), (0, 0, 1), (20, 40, 35), 185),
    "top": ((0, 0, -1), (0, 1, 0), (2, 50, 30), 175),
    "sole": ((0, 0, 1), (0, 1, 0), (2, 50, 30), 175),
    "toe_close": ((0.75, 0.55, -0.3), (0, 0, 1), (-55, 30, 30), 80),
    "heel_under_close": ((-0.55, -0.55, 0.62), (0, 0, 1), (42, 22, 18), 70),
    "rear34": ((-0.45, -0.75, -0.5), (0, 0, 1), (0, 50, 30), 185),
    "heel_front": ((-0.62, 0.78, -0.08), (0, 0, 1), (15, 30, 38), 165),
    "spine_close": ((-0.62, 0.78, -0.08), (0, 0, 1), (38, 18, 28), 70),
}
views = args[2:] or list(VIEWS)
os.makedirs(out_dir, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

MATS = {  # base colour, metallic, roughness
    "Body": ((0.56, 0.58, 0.61), 0.85, 0.32),
    "FaceInsert": ((0.06, 0.06, 0.07), 0.6, 0.42),
    "ScorePaint": ((0.92, 0.92, 0.90), 0.0, 0.5),
    "Ferrule": ((0.015, 0.015, 0.017), 0.3, 0.25),
    "HeelWeight": ((0.06, 0.06, 0.065), 0.8, 0.35),
}
for name, (col, metal, rough) in MATS.items():
    path = os.path.join(stl_dir, name + ".stl")
    if not os.path.exists(path):
        continue
    bpy.ops.wm.stl_import(filepath=path)  # mm units kept: cameras below are in mm
    obj = bpy.context.selected_objects[0]
    obj.name = name
    try:
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(30))
    except Exception:
        bpy.ops.object.shade_smooth()
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*col, 1)
    bsdf.inputs["Metallic"].default_value = metal
    bsdf.inputs["Roughness"].default_value = rough
    obj.data.materials.append(mat)

scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 48
scene.cycles.use_denoising = True
world = bpy.data.worlds.new("w")
scene.world = world
world.use_nodes = True
bg = world.node_tree.nodes["Background"]
bg.inputs["Color"].default_value = (0.10, 0.11, 0.13, 1)
bg.inputs["Strength"].default_value = 0.6
for name, d, e in [("key", (0.5, 0.9, 1.1), 2.6), ("fill", (-0.9, -1.0, 0.4), 0.7),
                   ("top", (0.0, 0.0, 1.0), 0.8), ("rim", (0.3, -0.7, -0.4), 0.6)]:
    ld = bpy.data.lights.new(name, "SUN")
    ld.energy = e
    lo = bpy.data.objects.new(name, ld)
    scene.collection.objects.link(lo)
    lo.rotation_euler = (-Vector(d)).to_track_quat("-Z", "Y").to_euler()
scene.render.resolution_x = 1000
scene.render.resolution_y = 800
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
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    # roll the camera so `up` is up
    q = d.to_track_quat("-Z", "Y")
    cam_up = q @ Vector((0, 1, 0))
    want = Vector(up) - d * Vector(up).dot(d)
    if want.length > 1e-6:
        want.normalize()
        ang = cam_up.angle(want)
        if d.dot(cam_up.cross(want)) < 0:
            ang = -ang
        from mathutils import Quaternion
        cam.rotation_euler = (Quaternion(d, ang) @ q).to_euler()
    cam_data.ortho_scale = h * 1.25
    scene.render.filepath = os.path.join(out_dir, v + ".png")
    bpy.ops.render.render(write_still=True)
    print("rendered", v)
