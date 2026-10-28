"""Fit the supplied Forge heads to the existing iron shafts.

Run: python tools/fit_forge_iron_heads.py
Stages GLBs and a validation report under build/forge-iron-fitted. Source positions
and normals remain unchanged; a rigid node transform aligns the straight bore
with the existing shaft. The shaft enters the bore by 6 mm. No head stretching,
shearing, remeshing or shaft length changes are involved.
"""
from pathlib import Path
import argparse
import copy
import hashlib
import json
import math
import sys

import numpy as np

from texture_putter_heads import Glb

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/Forge_Cavity_Iron_Head/Forge6_28deg_StraightHosel_v3.glb'
MUSCLE_BACK_SOURCE = ROOT / 'assets/Forge_Cavity_Iron_Head/Forge6_28deg_MuscleBack_RoundedHeel.glb'
MUSCLE_BACK_IDS = {'blade_runner_forged', 'tour_forged_cb', 'combo_proto'}
RUNTIME = ROOT / 'assets/openfairway_equipment'
OUTPUT = ROOT / 'build/forge-iron-fitted'
sys.path.insert(0, str(ROOT / 'assets/OpenFairway_Equipment_v1/source'))
from catalog_source import CATALOG

INSERT_DEPTH = .006
BORE_RADIUS = .0047
REAR_YAW, REAR_PITCH = .34, .20


def node_matrix(node):
    if 'matrix' in node:
        return np.array(node['matrix']).reshape(4, 4).T
    x, y, z, w = node.get('rotation', [0, 0, 0, 1])
    rotation = np.array([[1 - 2*y*y - 2*z*z, 2*x*y - 2*z*w, 2*x*z + 2*y*w],
                         [2*x*y + 2*z*w, 1 - 2*x*x - 2*z*z, 2*y*z - 2*x*w],
                         [2*x*z - 2*y*w, 2*y*z + 2*x*w, 1 - 2*x*x - 2*y*y]])
    result = np.eye(4)
    result[:3, :3] = rotation @ np.diag(node.get('scale', [1, 1, 1]))
    result[:3, 3] = node.get('translation', [0, 0, 0])
    return result


def map_existing_finish(positions, normals, indices, rotation):
    """Retain the established wear-map UVs; score lines are already in the mesh.

    Project the existing four-region atlas in club coordinates. Every region
    uses the same base finish, with geometric accents confined to the back.
    The original layout also retains the condition masks. The face strip
    avoids the legacy painted score lines.
    """
    placed = positions @ rotation.T
    body = positions[:, 0] < -.016
    lo, hi = placed[body].min(0), placed[body].max(0)
    u = np.clip((placed[:, 0] - lo[0]) / (hi[0] - lo[0]), 0, 1)
    v = np.clip((hi[1] - placed[:, 1]) / (hi[1] - lo[1]), 0, 1)
    # Project the back finish along the authored rear viewing direction. This
    # avoids stretching lettering over the deep curved cavity and heel wall.
    rear = np.array([math.sin(REAR_YAW)*math.cos(REAR_PITCH), -math.sin(REAR_PITCH),
                     math.cos(REAR_YAW)*math.cos(REAR_PITCH)])
    right = np.array([math.cos(REAR_YAW), 0, -math.sin(REAR_YAW)])
    up = np.cross(rear, right)
    across, height = placed @ right, placed @ up
    selected, new_indices, new_uv, lookup = [], [], [], {}
    points = positions[indices]
    directions = np.cross(points[:, 1] - points[:, 0], points[:, 2] - points[:, 0])
    directions /= np.maximum(np.linalg.norm(directions, axis=1)[:, None], 1e-20)
    centers = points.mean(1)
    necks = (centers[:, 1] > -.040) & (np.linalg.norm(centers[:, [0, 2]], axis=1) < .011)
    back_triangles = (directions @ rotation.T @ rear > 0) & ~necks
    back_vertices = indices[back_triangles].ravel()
    # Bound the vertices of every rear triangle, including long heel triangles.
    # Clamping individual vertices would distort interpolated lettering. An
    # affine projection fully inside the atlas also prevents neighboring tiles
    # from bleeding onto the sides of the blade.
    min_u, max_u = across[back_vertices].min(), across[back_vertices].max()
    min_v, max_v = height[back_vertices].min(), height[back_vertices].max()
    back_u = (across - min_u) / (max_u - min_u)
    back_v = (max_v - height) / (max_v - min_v)
    for tri, direction, center in zip(indices, directions, centers):
        neck = center[1] > -.040 and np.linalg.norm(center[[0, 2]]) < .011
        # Every surface visible from the rear shares the same projection,
        # including steep cavity walls. Hidden front surfaces use plain steel.
        region = 'neck' if neck else 'back' if np.dot(rotation @ direction, rear) > 0 else 'face'
        for index in tri:
            key = int(index), region
            if key not in lookup:
                if region == 'back':
                    uv = (.518 + .464*back_u[index], .518 + .464*back_v[index])
                elif region == 'face':
                    # All of this strip is plain face steel, above the atlas's
                    # painted grooves. Preserve the actual modeled grooves.
                    uv = (.52 + .46*u[index], .020 + .022*v[index])
                elif region == 'neck':
                    angle = math.atan2(positions[index, 2], positions[index, 0]) / math.tau + .5
                    uv = (.020 + .46*angle, .020 + .46*np.clip(-positions[index, 1]/.045, 0, 1))
                else:
                    uv = (.018 + .464*u[index], .018 + .464*v[index])
                lookup[key] = len(selected)
                selected.append(index)
                new_uv.append(uv)
            new_indices.append(lookup[key])
    selected = np.asarray(selected)
    new_indices = np.asarray(new_indices)
    assert np.array_equal(positions[selected][new_indices], positions[indices.ravel()])
    assert np.array_equal(normals[selected][new_indices], normals[indices.ravel()])
    return selected, new_indices, new_uv


def compact_geometry_buffers(glb):
    """Discard replaced head arrays so repeated fitting does not grow the GLB."""
    doc = glb.doc
    assert not doc.get('skins') and not doc.get('animations')
    used = set()
    for mesh in doc['meshes']:
        for primitive in mesh['primitives']:
            used.update(primitive['attributes'].values())
            if 'indices' in primitive:
                used.add(primitive['indices'])
            for target in primitive.get('targets', []):
                used.update(target.values())
    remap = {old: new for new, old in enumerate(sorted(used))}
    doc['accessors'] = [doc['accessors'][old] for old in sorted(used)]
    for mesh in doc['meshes']:
        for primitive in mesh['primitives']:
            primitive['attributes'] = {key: remap[index] for key, index in primitive['attributes'].items()}
            if 'indices' in primitive:
                primitive['indices'] = remap[primitive['indices']]
            for target in primitive.get('targets', []):
                for key in target:
                    target[key] = remap[target[key]]
    references = list(doc['accessors']) + [im for im in doc.get('images', []) if 'bufferView' in im]
    assert not any('sparse' in a for a in doc['accessors'])
    views = sorted({ref['bufferView'] for ref in references})
    view_map = {old: new for new, old in enumerate(views)}
    old_data = glb.data
    new_data = bytearray()
    new_views = []
    for old in views:
        view = dict(doc['bufferViews'][old])
        start = view.get('byteOffset', 0)
        new_data.extend(b'\0' * (-len(new_data) % 4))
        view['byteOffset'] = len(new_data)
        new_data.extend(old_data[start:start + view['byteLength']])
        new_views.append(view)
    for ref in references:
        ref['bufferView'] = view_map[ref['bufferView']]
    doc['bufferViews'], glb.data = new_views, new_data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ids', nargs='+', choices=[c['id'] for c in CATALOG if c['family'] == 'iron'])
    parser.add_argument('--output', type=Path, default=OUTPUT)
    args = parser.parse_args()
    output = args.output.resolve()
    sources = {}
    report = []
    for item in (c for c in CATALOG if c['family'] == 'iron' and (not args.ids or c['id'] in args.ids)):
        aid, stem = item['id'], 'ofg_' + item['id']
        source = MUSCLE_BACK_SOURCE if aid in MUSCLE_BACK_IDS else SOURCE
        revision = 4 if aid in MUSCLE_BACK_IDS else 3
        reference = Glb(source)
        source_node = next(n for n in reference.doc['nodes'] if 'mesh' in n)
        primitives = reference.doc['meshes'][source_node['mesh']]['primitives']
        assert len(primitives) == 1
        source_prim = primitives[0]
        assert np.allclose(node_matrix(source_node), np.eye(4))
        positions = reference.read(source_prim['attributes']['POSITION'])
        normals = reference.read(source_prim['attributes']['NORMAL'])
        indices = reference.read(source_prim['indices']).ravel().reshape(-1, 3)
        sources[source.stem] = dict(path=str(source.relative_to(ROOT)),
            sha256=hashlib.sha256(source.read_bytes()).hexdigest(), revision=revision)
        glb = Glb(RUNTIME / 'models/iron' / (stem + '.glb'))
        nodes = glb.doc['nodes']
        root = next(n for n in nodes if n.get('name') == stem)
        head = next(n for n in nodes if n.get('name') == stem + '__head')
        shaft = next(n for n in nodes if n.get('name') == stem + '__shaft')
        original_shaft = copy.deepcopy(shaft)
        original_grip = copy.deepcopy(next(n for n in nodes if n.get('name') == stem + '__grip'))
        shaft_transform = node_matrix(shaft)
        socket = shaft_transform[:3, 3]
        axis = shaft_transform[:3, 1]
        axis = axis / np.linalg.norm(axis)
        # The source has its blade on -X and face toward +Z. A proper rotation
        # places the blade on the right and face toward -Z in the game.
        front = np.array([0., 0., -1.])
        side = np.cross(axis, front); side /= np.linalg.norm(side)
        forward = np.cross(side, axis)
        rotation = np.column_stack((side, axis, forward))
        assert np.allclose(rotation.T @ rotation, np.eye(3), atol=1e-8)
        assert np.linalg.det(rotation) > .999999
        mouth = socket + axis * INSERT_DEPTH
        transform = np.eye(4); transform[:3, :3] = rotation; transform[:3, 3] = mouth
        placed = positions @ rotation.T + mouth
        for key in ('translation', 'rotation', 'scale', 'matrix'):
            head.pop(key, None)
        head['matrix'] = transform.T.ravel().tolist()
        head.setdefault('extras', {}).update(
            source_asset=source.stem, source_revision=revision, source_triangles=len(indices),
            fit_method='rigid_socket_alignment', shaft_insert_depth_m=INSERT_DEPTH,
            bore_radius_m=BORE_RADIUS, source_loft_degrees=28)
        selected, new_indices, uvs = map_existing_finish(positions, normals, indices, rotation)
        albedo, orm, normal = [glb.image(stem + '_' + kind,
                               (RUNTIME / 'textures' / aid / (stem + '_' + kind + '.png')).read_bytes())
                               for kind in ('albedo', 'orm', 'normal')]
        material_index = len(glb.doc['materials'])
        glb.doc['materials'].append({
            'name': stem + '__head_finish',
            'pbrMetallicRoughness': {'baseColorTexture': {'index': albedo},
                                    'metallicRoughnessTexture': {'index': orm}},
            'normalTexture': {'index': normal, 'scale': .42},
            'occlusionTexture': {'index': orm}})
        glb.doc['meshes'][head['mesh']]['primitives'] = [{
            'attributes': {'POSITION': glb.accessor(positions[selected]),
                           'NORMAL': glb.accessor(normals[selected]),
                           'TEXCOORD_0': glb.accessor(uvs)},
            'indices': glb.accessor(new_indices, indices=True), 'material': material_index}]
        # Move the assembly as one object, keeping all existing shaft/grip nodes
        # and their relative joins intact. The source's real dimensions survive.
        # Preserve any authored pose of the complete club. A root rotation must
        # move the head, shaft and grip together, and grounding uses that pose.
        root_transform = node_matrix(root)
        world_placed = placed @ root_transform[:3, :3].T + root_transform[:3, 3]
        ground_adjustment = -float(world_placed[:, 1].min())
        root_transform[1, 3] += ground_adjustment
        for key in ('translation', 'rotation', 'scale', 'matrix'):
            root.pop(key, None)
        root['matrix'] = root_transform.T.ravel().tolist()
        root.setdefault('extras', {}).update(asset_id=aid, rarity=item['rarity'],
            rear_view_yaw=REAR_YAW, rear_view_pitch=REAR_PITCH, source_head_revision=revision)
        # Store an explicit mouth marker so tooling distinguishes the opening
        # from the shaft tip six millimetres farther inside the hollow neck.
        marker_name = stem + '__hosel_mouth'
        marker = next((n for n in nodes if n.get('name') == marker_name), None)
        if marker is None:
            root.setdefault('children', []).append(len(nodes))
            nodes.append({'name': marker_name, 'translation': mouth.tolist()})
        else:
            marker['translation'] = mouth.tolist()
        assert shaft == original_shaft
        assert next(n for n in nodes if n.get('name') == stem + '__grip') == original_grip
        shaft_prim = glb.doc['meshes'][shaft['mesh']]['primitives'][0]
        shaft_points = glb.read(shaft_prim['attributes']['POSITION'])
        tip = shaft_points[shaft_points[:, 1] < shaft_points[:, 1].min() + .00001]
        tip_world = tip @ shaft_transform[:3, :3].T + socket
        tip_radius = float(np.linalg.norm(np.cross(tip_world - socket, axis), axis=1).max())
        assert tip_radius < BORE_RADIUS and BORE_RADIUS - tip_radius < .0003
        assert np.linalg.norm(np.cross(mouth - socket, axis)) < 1e-8
        target = output / 'models' / (stem + '.glb')
        compact_geometry_buffers(glb)
        glb.save(target)
        row = dict(id=aid, source_asset=source.stem, source_revision=revision, source_triangles=len(indices),
                   uniform_scale=1, rigid_determinant=float(np.linalg.det(rotation)),
                   insert_depth_m=INSERT_DEPTH, shaft_radius_m=tip_radius,
                   bore_radial_clearance_m=BORE_RADIUS-tip_radius,
                   ground_shift_m=ground_adjustment,
                   source_positions_and_normals_unchanged=True,
                   existing_shaft_and_grip_nodes_unchanged=True)
        report.append(row)
        print('FITTED', json.dumps(row), flush=True)
    (output / 'fit-report.json').write_text(json.dumps({'sources': sources, 'irons': report}, indent=2))


if __name__ == '__main__':
    main()
