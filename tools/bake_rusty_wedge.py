"""Bake the Rusty Gap material and unwrap its complete head, including the hosel.

Run with Blender --background --python tools/bake_rusty_wedge.py.
Stages the fitted club in build/wedge-distinct/models and writes reusable source
maps. Geometry, smooth normals, transforms, shafts and grips stay unchanged.
All projection, corrosion masks and bump calculations happen offline; the game
uses the same four texture samples as every other equipment finish.
"""
from pathlib import Path
import json
import math
import struct
import sys

import bpy
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/OpenFairway_Equipment_v1/source/materials/rusty_gap_52'
OUTPUT = ROOT / 'build/wedge-distinct'
STEM = 'ofg_rusty_gap_52'
SIZE = 1024


def read_glb(path):
    blob = path.read_bytes()
    size = struct.unpack_from('<I', blob, 12)[0]
    return json.loads(blob[20:20 + size]), bytearray(blob[28 + size:])


def read_array(doc, data, index):
    a = doc['accessors'][index]
    view = doc['bufferViews'][a['bufferView']]
    dtype = np.dtype({5126: '<f4', 5125: '<u4', 5123: '<u2', 5121: 'u1'}[a['componentType']])
    width = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[a['type']]
    return np.ndarray((a['count'], width), dtype=dtype, buffer=data,
                      offset=view.get('byteOffset', 0) + a.get('byteOffset', 0),
                      strides=(view.get('byteStride', dtype.itemsize * width), dtype.itemsize)).copy()


def add_array(doc, data, values, indices=False):
    a = np.asarray(values, dtype='<u4' if indices else '<f4')
    width = a.shape[1] if a.ndim == 2 else 1
    data.extend(b'\0' * (-len(data) % 4))
    doc['bufferViews'].append({'buffer': 0, 'byteOffset': len(data), 'byteLength': a.nbytes,
                               'target': 34963 if indices else 34962})
    data.extend(a.tobytes())
    accessor = {'bufferView': len(doc['bufferViews']) - 1, 'count': len(a),
                'componentType': 5125 if indices else 5126,
                'type': {1: 'SCALAR', 2: 'VEC2', 3: 'VEC3', 4: 'VEC4'}[width]}
    if not indices:
        accessor.update(min=a.min(axis=0).tolist(), max=a.max(axis=0).tolist())
    doc['accessors'].append(accessor)
    return len(doc['accessors']) - 1


def save_glb(doc, data, path):
    doc['buffers'][0]['byteLength'] = len(data)
    data.extend(b'\0' * (-len(data) % 4))
    encoded = json.dumps(doc, separators=(',', ':')).encode()
    encoded += b' ' * (-len(encoded) % 4)
    blob = struct.pack('<III', 0x46546C67, 2, 28 + len(encoded) + len(data))
    blob += struct.pack('<II', len(encoded), 0x4E4F534A) + encoded
    blob += struct.pack('<II', len(data), 0x004E4942) + data
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(blob)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    doc, data = read_glb(SOURCE / 'mapping_reference.glb')
    head = next(n for n in doc['nodes'] if n.get('name', '').endswith('__head'))
    primitives = doc['meshes'][head['mesh']]['primitives']
    assert len(primitives) == 1
    prim = primitives[0]
    attrs = {key: read_array(doc, data, index) for key, index in prim['attributes'].items()}
    indices = read_array(doc, data, prim['indices']).ravel().reshape(-1, 3)
    old_corners = indices.ravel()
    positions, normals, old_uv = attrs['POSITION'], attrs['NORMAL'], attrs['TEXCOORD_0']
    # Weld positions only in the baking mesh so old atlas seams do not fragment
    # the unwrap. Output vertices are still copied from the original GLB arrays.
    unique, inverse = np.unique(positions, axis=0, return_inverse=True)
    mesh = bpy.data.meshes.new('RustyGapBakeMesh')
    mesh.from_pydata(unique.tolist(), [], inverse[indices].tolist())
    mesh.update()
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    mesh.normals_split_custom_set(normals[old_corners].tolist())
    obj = bpy.data.objects.new(STEM + '__head_bake', mesh)
    bpy.context.collection.objects.link(obj)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    original_uv = mesh.uv_layers.new(name='OriginalFinish')
    corner_uv = old_uv[old_corners].copy()
    corner_uv[:, 1] = 1 - corner_uv[:, 1]
    original_uv.data.foreach_set('uv', corner_uv.ravel())
    baked_uv = mesh.uv_layers.new(name='RustAtlas')
    mesh.uv_layers.active_index = len(mesh.uv_layers) - 1
    baked_uv.active_render = True
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=.018,
                            area_weight=.25, correct_aspect=True, scale_to_bounds=True)
    bpy.ops.object.mode_set(mode='OBJECT')
    # Edit-mode conversion rebuilds mesh storage: reacquire RNA layers afterward.
    baked_uv = mesh.uv_layers['RustAtlas']
    print('UNWRAPPED', mesh.uv_layers.active.name,
          len({tuple(v.uv) for v in baked_uv.data}), 'distinct coordinates', flush=True)

    # Face-only abrasion is derived from the original functional face region.
    # The neck has a separate real UV island instead of sampling one brown pixel.
    wear_layer = mesh.color_attributes.new(name='ContactWear', type='FLOAT_COLOR', domain='CORNER')
    uv = old_uv[old_corners]
    face = ((uv[:, 0] > .5) & (uv[:, 1] < .5)).astype(float)
    wear = face * np.exp(-((uv[:, 0] - .76) / .14) ** 4 - ((uv[:, 1] - .26) / .13) ** 4) * .67
    wear_layer.data.foreach_set('color', np.column_stack((wear, wear, wear, np.ones(len(wear)))).ravel())

    mat = bpy.data.materials.new('RustyGapOfflineMaterial')
    mat.use_nodes = True
    mesh.materials.append(mat)
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.clear()

    def node(kind):
        return nodes.new(kind)

    def connect(value, target):
        if isinstance(value, (int, float, tuple)):
            target.default_value = value
        else:
            links.new(value, target)

    def math_node(op, a, b=None):
        n = node('ShaderNodeMath')
        n.operation = op
        connect(a, n.inputs[0])
        if b is not None:
            connect(b, n.inputs[1])
        return n.outputs[0]

    def mix(factor, a, b):
        n = node('ShaderNodeMixRGB')
        connect(factor, n.inputs[0]); connect(a, n.inputs[1]); connect(b, n.inputs[2])
        return n.outputs[0]

    def rgb(r, g, b):
        n = node('ShaderNodeCombineColor')
        connect(r, n.inputs[0]); connect(g, n.inputs[1]); connect(b, n.inputs[2])
        return n.outputs[0]

    def separate(vector, vector_type='ShaderNodeSeparateColor'):
        n = node(vector_type)
        links.new(vector, n.inputs[0])
        return n.outputs

    coord = node('ShaderNodeTexCoord')
    scale = node('ShaderNodeVectorMath')
    scale.operation = 'SCALE'
    links.new(coord.outputs['Object'], scale.inputs[0])
    scale.inputs['Scale'].default_value = 1 / .07
    texture = node('ShaderNodeTexImage')
    texture.image = bpy.data.images.load(str(SOURCE / 'rusted_steel_source.png'))
    texture.projection = 'BOX'
    texture.projection_blend = .23
    links.new(scale.outputs[0], texture.inputs['Vector'])
    channels = separate(texture.outputs['Color'])
    saturation = math_node('DIVIDE', math_node('SUBTRACT', channels[0], channels[2]),
                           math_node('MAXIMUM', channels[0], .02))
    corrosion = math_node('MINIMUM', math_node('MAXIMUM',
                           math_node('SUBTRACT', math_node('MULTIPLY', saturation, 2.2), .24), 0), 1)
    contact = node('ShaderNodeVertexColor'); contact.layer_name = 'ContactWear'
    abrasion = contact.outputs['Color']
    rust = math_node('MULTIPLY', corrosion, math_node('SUBTRACT', 1, abrasion))
    albedo = mix(abrasion, texture.outputs['Color'], (.24, .26, .265, 1))
    # Push the whole finish warmer/redder -- the photographed rust texture reads too
    # neutral/grey on its own; multiply-tint it toward red-brown while keeping the
    # existing wear and corrosion variation intact.
    warm_tint = node('ShaderNodeMixRGB')
    warm_tint.blend_type = 'MULTIPLY'
    connect(.75, warm_tint.inputs[0])
    connect(albedo, warm_tint.inputs[1])
    connect((1.28, 0.78, 0.55, 1), warm_tint.inputs[2])
    albedo = warm_tint.outputs[0]
    roughness = math_node('ADD', .36, math_node('MULTIPLY', rust, .5))
    metallic = math_node('SUBTRACT', .91, math_node('MULTIPLY', rust, .88))
    orm = rgb(1, roughness, metallic)
    # Existing rust stays visible at mint condition. Damage gently darkens the
    # same rust regions instead of stamping unrelated corrosion shapes over it.
    condition_map = rgb(math_node('ADD', .06, math_node('MULTIPLY', rust, .18)),
                        math_node('MULTIPLY', abrasion, .08), math_node('MULTIPLY', rust, .22))

    micro = node('ShaderNodeTexNoise')
    links.new(coord.outputs['Object'], micro.inputs['Vector'])
    micro.inputs['Scale'].default_value = 3800
    micro.inputs['Detail'].default_value = 2
    pit_height = math_node('MULTIPLY', rust, micro.outputs['Fac'])
    bump = node('ShaderNodeBump')
    bump.inputs['Strength'].default_value = .55
    bump.inputs['Distance'].default_value = .00013
    links.new(pit_height, bump.inputs['Height'])
    # Functional score lines remain on the face and are baked into the new UVs.
    uv_node = node('ShaderNodeUVMap'); uv_node.uv_map = 'OriginalFinish'
    uv_parts = separate(uv_node.outputs[0], 'ShaderNodeSeparateXYZ')
    line_y = math_node('FRACT', math_node('MULTIPLY', uv_parts[1], 28.45))
    lines = math_node('LESS_THAN', line_y, .068)
    gate = math_node('MULTIPLY', math_node('GREATER_THAN', uv_parts[0], .56),
                     math_node('LESS_THAN', uv_parts[0], .94))
    gate = math_node('MULTIPLY', gate, math_node('GREATER_THAN', uv_parts[1], .57))
    gate = math_node('MULTIPLY', gate, math_node('LESS_THAN', uv_parts[1], .93))
    grooves = node('ShaderNodeBump')
    grooves.invert = True
    grooves.inputs['Strength'].default_value = .6
    grooves.inputs['Distance'].default_value = .00023
    links.new(math_node('MULTIPLY', gate, lines), grooves.inputs['Height'])
    links.new(bump.outputs['Normal'], grooves.inputs['Normal'])
    bsdf = node('ShaderNodeBsdfPrincipled')
    links.new(albedo, bsdf.inputs['Base Color'])
    links.new(roughness, bsdf.inputs['Roughness'])
    links.new(metallic, bsdf.inputs['Metallic'])
    links.new(grooves.outputs['Normal'], bsdf.inputs['Normal'])
    output = node('ShaderNodeOutputMaterial')
    emission = node('ShaderNodeEmission')
    target = node('ShaderNodeTexImage')
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = 1
    scene.render.threads_mode = 'FIXED'
    scene.render.threads = 8
    scene.render.bake.margin = 12
    scene.render.bake.use_clear = True
    scene.view_settings.view_transform = 'Standard'
    dest = SOURCE / 'baked'
    dest.mkdir(exist_ok=True)
    for kind, socket in [('albedo', albedo), ('orm', orm), ('wear', condition_map), ('normal', None)]:
        image = bpy.data.images.new(STEM + '_' + kind, width=SIZE, height=SIZE, alpha=False)
        image.colorspace_settings.name = 'sRGB' if kind == 'albedo' else 'Non-Color'
        target.image = image
        for n in nodes:
            n.select = False
        target.select = True
        nodes.active = target
        for link in list(output.inputs['Surface'].links):
            links.remove(link)
        if socket is None:
            links.new(bsdf.outputs[0], output.inputs['Surface'])
            bpy.ops.object.bake(type='NORMAL', normal_space='TANGENT')
        else:
            links.new(socket, emission.inputs['Color'])
            links.new(emission.outputs[0], output.inputs['Surface'])
            bpy.ops.object.bake(type='EMIT')
        image.filepath_raw = str(dest / (STEM + '_' + kind + '.png'))
        image.file_format = 'PNG'
        image.save()
        print('BAKED', kind, flush=True)

    mesh.calc_tangents(uvmap='RustAtlas')
    baked_uv = mesh.uv_layers['RustAtlas']
    uvs = np.array([loop.uv[:] for loop in baked_uv.data], dtype=np.float32)
    uvs[:, 1] = 1 - uvs[:, 1]
    tangents = np.array([(*loop.tangent, loop.bitangent_sign) for loop in mesh.loops], dtype=np.float32)
    mesh.free_tangents()
    uv_triangles = uvs.reshape(-1, 3, 2)
    uv_edge_a = uv_triangles[:, 1] - uv_triangles[:, 0]
    uv_edge_b = uv_triangles[:, 2] - uv_triangles[:, 0]
    uv_area = np.abs(uv_edge_a[:, 0] * uv_edge_b[:, 1] - uv_edge_a[:, 1] * uv_edge_b[:, 0])
    assert (uv_area > 1e-12).all(), 'Baked head contains collapsed UV triangles'
    # Match Blender's glTF exporter: flip UV V, retain tangent handedness.
    selected, new_indices, final_uvs, final_tangents, lookup = [], [], [], [], {}
    for corner, old_index in enumerate(old_corners):
        key = (int(old_index), *uvs[corner].tolist(), *tangents[corner].tolist())
        if key not in lookup:
            lookup[key] = len(selected)
            selected.append(old_index)
            final_uvs.append(uvs[corner])
            final_tangents.append(tangents[corner])
        new_indices.append(lookup[key])
    selected = np.asarray(selected)
    assert np.array_equal(positions[selected][new_indices], positions[old_corners])
    assert np.array_equal(normals[selected][new_indices], normals[old_corners])
    prim['attributes'] = {name: add_array(doc, data, values[selected]) for name, values in attrs.items()
                          if name not in ('TEXCOORD_0', 'TANGENT')}
    prim['attributes']['TEXCOORD_0'] = add_array(doc, data, final_uvs)
    prim['attributes']['TANGENT'] = add_array(doc, data, final_tangents)
    prim['indices'] = add_array(doc, data, new_indices, indices=True)
    head.setdefault('extras', {})['finish_uv'] = 'rust_atlas_v1'
    path = OUTPUT / 'models' / (STEM + '.glb')
    save_glb(doc, data, path)
    sys.path.insert(0, str(ROOT / 'tools'))
    from update_club_texture_images import update
    update(path, dest)
    report = {'triangles': len(indices), 'vertices_before': len(positions), 'vertices_after': len(selected),
              'geometry_and_normals_unchanged': True, 'maps': SIZE,
              'head_dimensions_m': (positions.max(0) - positions.min(0)).tolist()}
    (OUTPUT / 'rust-bake-report.json').write_text(json.dumps(report, indent=2))
    print('RUST BAKE PASS', report, flush=True)


if __name__ == '__main__':
    main()
