"""Blender --background --disable-autoexec --python tools/rebuild_woodland_bushes.py

Restore the supplied bush color/opacity maps explicitly. The source materials
use custom node groups and color mixes that glTF cannot export faithfully.
Never execute embedded scripts from the source .blend files.
"""
from pathlib import Path
import json
import struct
import bpy
import numpy as np
from mathutils import Matrix

ROOT = Path(__file__).resolve().parents[1]
SOURCES = Path.home() / 'Downloads'
OUTPUT = ROOT / 'assets/foliage_bushes'
WORK = ROOT / 'build/woodland-materials'
WORK.mkdir(parents=True, exist_ok=True)


def material(name, diffuse, normal, opacity=None):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.use_backface_culling = False
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes.get('Principled BSDF')
    bsdf.inputs['Roughness'].default_value = 0.88
    bsdf.inputs['Specular IOR Level'].default_value = 0.15
    source = bpy.data.images[diffuse]
    if source.size[0] > 2048:
        source.scale(2048, round(source.size[1] * 2048 / source.size[0]))
    rgba = np.empty(len(source.pixels), dtype=np.float32)
    source.pixels.foreach_get(rgba)
    if opacity:
        alpha = bpy.data.images[opacity]
        alpha.colorspace_settings.name = 'Non-Color'
        if tuple(alpha.size) != tuple(source.size):
            alpha.scale(*source.size)
        mask = np.empty(len(alpha.pixels), dtype=np.float32)
        alpha.pixels.foreach_get(mask)
        rgba[3::4] = mask[0::4]
    texture = bpy.data.images.new(name + '_Color', *source.size, alpha=True)
    texture.colorspace_settings.name = source.colorspace_settings.name
    texture.pixels.foreach_set(rgba)
    texture.filepath_raw = str(WORK / (name + '_Color.png'))
    texture.file_format = 'PNG'
    texture.save()
    texture.pack()
    color = nodes.new('ShaderNodeTexImage')
    color.image = texture
    links.new(color.outputs['Color'], bsdf.inputs['Base Color'])
    if opacity:
        mat.surface_render_method = 'DITHERED'
        links.new(color.outputs['Alpha'], bsdf.inputs['Alpha'])
    norm = nodes.new('ShaderNodeTexImage')
    norm.image = bpy.data.images[normal]
    norm.image.colorspace_settings.name = 'Non-Color'
    if norm.image.size[0] > 2048:
        norm.image.scale(2048, round(norm.image.size[1] * 2048 / norm.image.size[0]))
    mapping = nodes.new('ShaderNodeNormalMap')
    mapping.inputs['Strength'].default_value = 0.55
    links.new(norm.outputs['Color'], mapping.inputs['Color'])
    links.new(mapping.outputs['Normal'], bsdf.inputs['Normal'])
    return mat


def rebuild(filename, output, leaf=False):
    bpy.ops.wm.open_mainfile(filepath=str(SOURCES / filename))
    meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    for obj in meshes:
        if leaf:
            if obj.name.startswith('Bark'):
                mat = material('Woodland_Bark', 'Bark_2diffuse.png', 'Bark_2_Normal.png')
            elif obj.name.startswith('Leaf_Cluster_1'):
                mat = material('Woodland_Leaf1', 'Leaf_Cluster_1_Summer-diffuse.png', 'Leaf_Cluster_1_Summer_Mat_Normal.001', 'Leaf_Cluster_1_Summer_Mat_Opacity.001')
            else:
                mat = material('Woodland_Leaf2', 'Leaf_Cluster_2_Summer_Mat_Color', 'Leaf_Cluster_2_Summer_Mat_Normal.001', 'Leaf_Cluster_2_Summer_Mat_Opacity.001')
        else:
            mat = material('Woodland_Button', 'T_Button_Bush_01_BC.jpg', 'T_Button_Bush_01_N.jpg', 'T_Button_Bush_01_OP.jpg')
        matrix = obj.matrix_world.copy()
        obj.parent = None
        obj.data.transform(matrix)
        obj.matrix_world = Matrix.Identity(4)
        obj.data.materials.clear()
        obj.data.materials.append(mat)
        for attr in list(obj.data.color_attributes):
            obj.data.color_attributes.remove(attr)
        bpy.ops.object.select_all(action='DESELECT')
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        # Keep the button bush's original leaf cards. The previous reduction
        # damaged their UVs and reduced a full shrub to sparse fragments.
        if leaf:
            mod = obj.modifiers.new('Woodland geometry budget', 'DECIMATE')
            mod.ratio = 0.45
            mod.use_collapse_triangulate = True
            bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = output
    low = min(v.co.z for v in obj.data.vertices)
    for vertex in obj.data.vertices:
        vertex.co.z -= low
    path = OUTPUT / (output + '.glb')
    bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB', use_selection=True, export_animations=False)
    raw = path.read_bytes()
    length, kind = struct.unpack_from('<II', raw, 12)
    doc = json.loads(raw[20:20+length])
    for mat in doc['materials']:
        if mat['name'].startswith(('Woodland_Button', 'Woodland_Leaf')):
            # Summer woodland foliage: retain the photographic leaf variation
            # while bringing the pale source atlas into the course's greens.
            mat['pbrMetallicRoughness']['baseColorFactor'] = [0.30, 0.55, 0.22, 1.0]
        if mat.get('alphaMode') == 'BLEND':
            mat['alphaMode'] = 'MASK'
            mat['alphaCutoff'] = 0.4
    payload = json.dumps(doc, separators=(',', ':')).encode()
    payload += b' ' * (-len(payload) % 4)
    tail = raw[20+length:]
    path.write_bytes(struct.pack('<III', 0x46546c67, 2, 20+len(payload)+len(tail)) + struct.pack('<II', len(payload), kind) + payload + tail)
    print('REBUILT', path, 'triangles', sum(len(p.vertices)-2 for p in obj.data.polygons))


rebuild('sqpk4kd.blend', 'leafcluster_01', True)
rebuild('re9lox99fhnk.blend', 'buttonbush_01')
rebuild('5ktowp6q.blend', 'buttonbush_02')
