"""Rebuild the planted LS12 bush from the supplied Blender source.

Run with Blender --background --disable-autoexec --python this_file --
  --source <BCY_LS12_Forsythia_02.blend> --textures <textures> --output <model.glb>

Keep the flower UVs/cutouts and simplify each material separately: a blanket
95% collapse destroys the stems and leaves disconnected flower fragments.
The exported mesh is in metres, rooted at ground level, with four surfaces so
ForestPlanter can instance the complete plant as one MultiMesh.
"""

import argparse
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix


def material(name, textures, scratch):
    mat = bpy.data.materials.new("Forsythia_" + name)
    mat.use_nodes = True
    mat.use_backface_culling = False
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    shader = nodes.get("Principled BSDF")
    shader.inputs["Roughness"].default_value = 0.8
    shader.inputs["Specular IOR Level"].default_value = 0.25
    prefix = "LS12_" + name
    diffuse = prefix + ("Front" if name in ("Bud01", "Flower01") else "") + "_dif_su.png"
    color = bpy.data.images.load(str(textures / diffuse), check_existing=False)
    if name == "Flower01":
        mask = bpy.data.images.load(str(textures / (prefix + "_alp_su.png")), check_existing=False)
        mask.colorspace_settings.name = "Non-Color"
        if tuple(mask.size) != tuple(color.size):
            mask.scale(*color.size)
        rgba = np.empty(len(color.pixels), dtype=np.float32)
        alpha = np.empty(len(mask.pixels), dtype=np.float32)
        color.pixels.foreach_get(rgba)
        mask.pixels.foreach_get(alpha)
        rgba[3::4] = alpha[0::4]
        # Loading an RGB PNG leaves a three-channel image even after writing
        # pixel alpha. Allocate RGBA explicitly or PNG saving drops the mask.
        combined = bpy.data.images.new("Forsythia_Flower_RGBA", *color.size, alpha=True)
        combined.colorspace_settings.name = color.colorspace_settings.name
        combined.alpha_mode = "STRAIGHT"
        combined.pixels.foreach_set(rgba)
        color = combined
        color.filepath_raw = str(scratch / "Forsythia_Flower_RGBA.png")
        color.file_format = "PNG"
        color.save()
        color.pack()
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = color
    links.new(tex.outputs["Color"], shader.inputs["Base Color"])
    if name == "Flower01":
        links.new(tex.outputs["Alpha"], shader.inputs["Alpha"])
        # Blender 4.2+ exports this as BLEND; patch to glTF MASK below so
        # cutouts write depth and do not sort whole bushes as transparent.
        mat.surface_render_method = "DITHERED"
    normal = nodes.new("ShaderNodeTexImage")
    normal.image = bpy.data.images.load(str(textures / (prefix + "_nml_su.png")), check_existing=False)
    normal.image.colorspace_settings.name = "Non-Color"
    normal_map = nodes.new("ShaderNodeNormalMap")
    links.new(normal.outputs["Color"], normal_map.inputs["Color"])
    links.new(normal_map.outputs["Normal"], shader.inputs["Normal"])
    return mat


def set_cutout(path):
    import json
    import struct
    raw = path.read_bytes()
    length, kind = struct.unpack_from("<II", raw, 12)
    document = json.loads(raw[20:20 + length])
    for mat in document["materials"]:
        if mat["name"] == "Forsythia_Flower01":
            mat["alphaMode"] = "MASK"
            mat["alphaCutoff"] = 0.45
    payload = json.dumps(document, separators=(",", ":")).encode()
    payload += b" " * (-len(payload) % 4)
    tail = raw[20 + length:]
    path.write_bytes(struct.pack("<III", 0x46546C67, 2, 20 + len(payload) + len(tail))
                     + struct.pack("<II", len(payload), kind) + payload + tail)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--textures", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    bpy.ops.wm.open_mainfile(filepath=str(args.source))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    scratch = args.output.parent / ".source_work"
    scratch.mkdir(exist_ok=True)
    parts = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    ratios = {"Bark01": 0.4, "Branch01": 0.3, "Flower01": 0.75, "Bud01": 0.2}
    for obj in parts:
        kind = next(name for name in ratios if obj.name.startswith(name))
        world = obj.matrix_world.copy()
        obj.parent = None
        obj.data.transform(world)
        obj.matrix_world = Matrix.Identity(4)
        obj.data.materials.clear()
        obj.data.materials.append(material(kind, args.textures, scratch))
        # Imported color attributes are not albedo; exporting them darkens the
        # reconstructed material and inflates every vertex in every instance.
        for attribute in list(obj.data.color_attributes):
            obj.data.color_attributes.remove(attribute)
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        modifier = obj.modifiers.new("Preserve stems and petals", "DECIMATE")
        modifier.ratio = ratios[kind]
        modifier.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        print("BUSH_PART", kind, sum(len(p.vertices) - 2 for p in obj.data.polygons))
    bpy.ops.object.select_all(action="DESELECT")
    for obj in parts:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    bush = bpy.context.object
    bush.name = "Forsythia_02"
    ground = min(v.co.z for v in bush.data.vertices)
    for vertex in bush.data.vertices:
        vertex.co.z -= ground
    bpy.ops.export_scene.gltf(filepath=str(args.output), export_format="GLB",
                              use_selection=True, export_animations=False,
                              export_yup=True, export_extras=False)
    set_cutout(args.output)
    print("BUSH_EXPORTED", args.output)


if __name__ == "__main__":
    main()
