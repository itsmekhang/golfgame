"""The pro shop's golf ball packs as box models (run ball_pack_textures.py first).

    blender -b --factory-startup -P tools/blender/build_ball_packs.py

Each pack is one box the size of the real thing (ball_pack_layout.SHAPES), its six faces UV'd
onto the texture layout: the front faces +Y here (-Z in Godot, the way the shop's displays
face), the base centred on the origin. The window that shows a ball is part of the printed
art, so a box is twelve triangles. Writes assets/facilities/props/ball_packs/ball_<pack>.glb.
"""
import os
import sys

import bmesh
import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ball_pack_layout import PACKS, shape_of  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
TEX = os.path.join(ROOT, "tools", "blender", "sources", "ball_packs", "textures")
OUT = os.path.join(ROOT, "assets", "facilities", "props", "ball_packs")


def corners(w, d, h):
    """Each face's corners as the art sees them -- bottom-left, bottom-right, top-right,
    top-left -- going round the box so the side strip runs on from face to face."""
    x, y = w * 0.5, d * 0.5
    return {
        "front": [(x, y, 0), (-x, y, 0), (-x, y, h), (x, y, h)],
        "right": [(-x, y, 0), (-x, -y, 0), (-x, -y, h), (-x, y, h)],
        "back": [(-x, -y, 0), (x, -y, 0), (x, -y, h), (-x, -y, h)],
        "left": [(x, -y, 0), (x, y, 0), (x, y, h), (x, -y, h)],
        "top": [(x, y, h), (-x, y, h), (-x, -y, h), (x, -y, h)],
        "bottom": [(x, -y, 0), (-x, -y, 0), (-x, y, 0), (x, y, 0)],
    }


def material(pack):
    mat = bpy.data.materials.new("ball_pack_" + pack)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(os.path.join(TEX, pack + ".png"))
    tex.interpolation = "Linear"
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.42  # printed, coated card
    bsdf.inputs["Metallic"].default_value = 0.0
    return mat


def build(pack):
    shape = shape_of(pack)
    cw, ch = shape["canvas"]
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    for face, pts in corners(*shape["size"]).items():
        x, y, w, h = shape["faces"][face]
        u0, u1 = x / cw, (x + w) / cw
        vb, vt = 1.0 - (y + h) / ch, 1.0 - y / ch
        f = bm.faces.new([bm.verts.new(p) for p in pts])
        for loop, coord in zip(f.loops, ((u0, vb), (u1, vb), (u1, vt), (u0, vt))):
            loop[uv].uv = coord
    me = bpy.data.meshes.new("ball_" + pack)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(material(pack))
    ob = bpy.data.objects.new("ball_" + pack, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def main():
    os.makedirs(OUT, exist_ok=True)
    for pack in PACKS:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        build(pack)
        path = os.path.join(OUT, "ball_%s.glb" % pack)
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=False,
                                  export_image_format="JPEG", export_image_quality=90)
        print("BALL PACK", pack, "->", os.path.basename(path))


main()
