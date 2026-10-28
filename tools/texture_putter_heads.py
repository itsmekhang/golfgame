"""Author thumbnail-matched PBR finishes and UVs for the replacement putter heads.

Run: python tools/texture_putter_heads.py
Stages models and textures in build/putter-finishes for review before installation.
Requires numpy and Pillow. No Blender re-export or geometry fitting is involved:
triangle positions, normals, node transforms, shafts, and grips are preserved.
"""
from pathlib import Path
import argparse
import hashlib
import io
import json
import struct

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'assets/openfairway_equipment'
SIZE, TILE, PAD = 1024, 256, 6
FINISHES = {
    'loaner_putter': ('b9c3c3', .46, .82),
    'rustbelt_blade': ('bd825f', .49, .76),
    'brass_relic': ('c5af68', .43, .86),
    'midnight_mallet': ('25323b', .44, .65),
    'copper_classic': ('d99768', .25, .94),
    'tourline_prototype': ('bdc8cb', .38, .87),
    'blackout_tour_issue': ('23303a', .43, .65),
    'scotty_grail': ('d1dadb', .25, .94),
    'auto_putt_9000': ('3e616b', .38, .72),
}


def rgb(value):
    return np.array([int(value[i:i + 2], 16) for i in (0, 2, 4)], dtype=float)


def png_bytes(array):
    buffer = io.BytesIO()
    Image.fromarray(np.uint8(np.clip(array, 0, 255))).save(buffer, format='PNG')
    return buffer.getvalue()


def make_atlas(asset_id, bounds, body_height, destination):
    """16 padded planar/material regions; markings have real physical proportions."""
    color, roughness, metallic = FINISHES[asset_id]
    rng = np.random.default_rng(int(hashlib.sha256(asset_id.encode()).hexdigest()[:8], 16))
    maps = {kind: np.zeros((SIZE, SIZE, 3), dtype=np.uint8)
            for kind in ('albedo', 'orm', 'normal', 'wear')}
    yy, xx = np.mgrid[:TILE, :TILE]
    x, y = (xx - PAD) / (TILE - 2 * PAD), (yy - PAD) / (TILE - 2 * PAD)
    low = np.array(Image.fromarray(rng.integers(0, 256, (24, 24), dtype=np.uint8))
                   .resize((TILE, TILE), Image.Resampling.BICUBIC), dtype=float) / 255
    fine = rng.random((TILE, TILE)) - .5
    brush = rng.normal(0, .65, (TILE, 1)) + fine * .8
    width, depth = bounds[1][0] - bounds[0][0], bounds[1][2] - bounds[0][2]
    world_x = bounds[0][0] + x * width
    world_z = bounds[0][2] + y * depth
    world_y = (1 - y) * body_height

    for slot in range(16):
        c, r, m = rgb(color), roughness, metallic
        if slot == 1:
            r = min(.56, roughness + .10)
        elif slot == 3:
            c, r = c * .87, min(.6, r + .10)
        elif slot == 6:
            c, r, m = rgb('e8eddf'), .36, .05  # ivory alignment paint
        elif slot == 7:
            c, r, m = rgb('46d6c5' if asset_id == 'auto_putt_9000' else '4b9fdd'), .27, .18
        elif slot == 8:
            c, r, m = rgb('25323b'), .48, .52
        elif slot == 9:
            c, r, m = rgb('c93e37'), .25, .15
        elif slot == 10:
            c, r, m = rgb('c3ced0'), .26, .92
        a = np.broadcast_to(c, (TILE, TILE, 3)).copy() + brush[..., None]
        rough = np.full((TILE, TILE), r) + fine * .016
        metal = np.full((TILE, TILE), m)
        height = brush * .06
        if slot <= 5 and asset_id == 'rustbelt_blade':
            oxidation = np.clip((low - .32) * .38, 0, .24)
            a = a * (1 - oxidation[..., None]) + rgb('995a3b') * oxidation[..., None]
            rough += oxidation * .3
            metal *= 1 - oxidation * .38
            height += fine * oxidation * .25
        elif slot <= 5 and asset_id == 'brass_relic':
            patina = np.clip((low - .60) * .9, 0, .20)
            a = a * (1 - patina[..., None]) + rgb('5d866a') * patina[..., None]
            rough += patina * .25
            metal *= 1 - patina * .4
        if slot == 1 and asset_id != 'loaner_putter':
            # Fine milling only on the striking face, never stretched up the neck.
            milling = np.sin(xx * .46 + np.sin(yy * .26) * 2.1)
            height += milling * .10
            a += milling[..., None] * .55

        def paint(mask, tint, surface_roughness=.30, surface_metallic=.12):
            a[mask] = rgb(tint)
            rough[mask], metal[mask] = surface_roughness, surface_metallic

        if slot == 0:
            if asset_id == 'midnight_mallet':
                lines = (((np.abs(world_x - .010) < .0009) |
                          (np.abs(world_x + .010) < .0009)) &
                         (world_z > -.006) & (world_z < .039))
                lines |= (np.abs(world_x) < .0008) & (world_z > -.009) & (world_z < .003)
                paint(lines, 'e8eddf')
            elif asset_id == 'tourline_prototype':
                paint((np.abs(world_x) < .0016) & (world_z > .002) & (world_z < .048), '4b9fdd')
            elif asset_id == 'blackout_tour_issue':
                paint((np.abs(world_z + .0065) < .0010) & (np.abs(world_x) < width * .47), 'df5144')
            elif asset_id == 'auto_putt_9000':
                paint((np.abs(world_z + .008) < .0013) & (np.abs(world_x) < width * .43), '46d6c5')
        if slot == 2 and asset_id == 'scotty_grail':
            for center_x in (-.013, 0, .013):
                distance = ((world_x - center_x) ** 2 + (world_y - .0175) ** 2) ** .5
                paint(distance < .0035, '59656a', .27, .88)
                paint(distance < .0028, 'ce3732', .23, .18)
                paint(((world_x - center_x + .0006) ** 2 + (world_y - .0183) ** 2) < .00045 ** 2,
                      'ef8f78', .20, .18)
        if slot == 2 and asset_id == 'blackout_tour_issue':
            distance = ((world_x - .035) ** 2 + (world_y - .011) ** 2) ** .5
            paint(distance < .0043, 'aebec2', .25, .88)
            paint(distance < .0029, '34464c', .43, .65)
            paint((distance < .0021) & ((np.abs(world_x - .035) < .00045) |
                                      (np.abs(world_y - .011) < .00045)), 'bbc8ca', .3, .85)

        # Tangent-space detail and condition masks use the same UV layout.
        gy, gx = np.gradient(height)
        normal = np.stack((-gx, gy, np.ones_like(height)), -1)
        normal /= np.linalg.norm(normal, axis=2)[..., None]
        wear = np.stack((20 + low * 55, np.clip((fine - .28) * 400, 0, 80), low * 65), -1)
        if slot in (6, 7, 9):
            wear *= .35
        col, row = slot % 4, slot // 4
        region = np.s_[row * TILE:(row + 1) * TILE, col * TILE:(col + 1) * TILE, :]
        maps['albedo'][region] = np.uint8(np.clip(a, 0, 255))
        maps['orm'][region] = np.uint8(np.stack((np.ones_like(rough), np.clip(rough, 0, 1), metal), -1) * 255)
        maps['normal'][region] = np.uint8((normal * .5 + .5) * 255)
        maps['wear'][region] = np.uint8(wear)
    destination.mkdir(parents=True, exist_ok=True)
    output = {}
    for kind, array in maps.items():
        output[kind] = png_bytes(array)
        (destination / f'ofg_{asset_id}_{kind}.png').write_bytes(output[kind])
    return output


class Glb:
    def __init__(self, path):
        original = path.read_bytes()
        magic, version, total = struct.unpack_from('<III', original)
        assert (magic, version, total) == (0x46546C67, 2, len(original))
        json_size = struct.unpack_from('<I', original, 12)[0]
        self.doc = json.loads(original[20:20 + json_size])
        bin_size, bin_type = struct.unpack_from('<II', original, 20 + json_size)
        assert bin_type == 0x004E4942
        self.data = bytearray(original[28 + json_size:28 + json_size + bin_size])

    def read(self, index):
        a = self.doc['accessors'][index]
        view = self.doc['bufferViews'][a['bufferView']]
        dtype = np.dtype({5126: '<f4', 5125: '<u4', 5123: '<u2', 5121: 'u1'}[a['componentType']])
        width = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[a['type']]
        return np.ndarray((a['count'], width), dtype=dtype, buffer=self.data,
                          offset=view.get('byteOffset', 0) + a.get('byteOffset', 0),
                          strides=(view.get('byteStride', dtype.itemsize * width), dtype.itemsize)).copy()

    def buffer(self, data, target=None):
        self.data.extend(b'\0' * (-len(self.data) % 4))
        view = {'buffer': 0, 'byteOffset': len(self.data), 'byteLength': len(data)}
        if target is not None:
            view['target'] = target
        self.data.extend(data)
        self.doc['bufferViews'].append(view)
        return len(self.doc['bufferViews']) - 1

    def accessor(self, array, indices=False):
        array = np.asarray(array, dtype='<u4' if indices else '<f4')
        width = array.shape[1] if array.ndim == 2 else 1
        a = {'bufferView': self.buffer(array.tobytes(), 34963 if indices else 34962),
             'componentType': 5125 if indices else 5126, 'count': len(array),
             'type': {1: 'SCALAR', 2: 'VEC2', 3: 'VEC3', 4: 'VEC4'}[width]}
        if not indices:
            a['min'], a['max'] = array.min(axis=0).tolist(), array.max(axis=0).tolist()
        self.doc['accessors'].append(a)
        return len(self.doc['accessors']) - 1

    def image(self, name, data):
        self.doc.setdefault('images', []).append({'name': name, 'mimeType': 'image/png', 'bufferView': self.buffer(data)})
        self.doc.setdefault('textures', []).append({'source': len(self.doc['images']) - 1})
        return len(self.doc['textures']) - 1

    def save(self, path):
        self.doc['buffers'][0]['byteLength'] = len(self.data)
        self.data.extend(b'\0' * (-len(self.data) % 4))
        encoded = json.dumps(self.doc, separators=(',', ':')).encode()
        encoded += b' ' * (-len(encoded) % 4)
        result = struct.pack('<III', 0x46546C67, 2, 28 + len(encoded) + len(self.data))
        result += struct.pack('<II', len(encoded), 0x4E4F534A) + encoded
        result += struct.pack('<II', len(self.data), 0x004E4942) + self.data
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(result)


def texture_head(item, output, source_base=BASE):
    asset_id = item['id']
    source = source_base / item['model'].replace('res://assets/openfairway_equipment/', '')
    glb = Glb(source)
    node = next(n for n in glb.doc['nodes'] if n.get('name', '').endswith('__head'))
    mesh = glb.doc['meshes'][node['mesh']]
    all_positions = np.concatenate([glb.read(p['attributes']['POSITION']) for p in mesh['primitives']])
    bounds = all_positions.min(0), all_positions.max(0)
    center = (bounds[0] + bounds[1]) * .5
    body = all_positions[np.abs(all_positions[:, 0] - center[0]) < (bounds[1][0] - bounds[0][0]) * .23]
    body_height = float(body[:, 1].max())
    maps = make_atlas(asset_id, bounds, body_height, output / 'textures' / asset_id)
    albedo = glb.image(f'ofg_{asset_id}_albedo', maps['albedo'])
    orm = glb.image(f'ofg_{asset_id}_orm', maps['orm'])
    normal = glb.image(f'ofg_{asset_id}_normal', maps['normal'])
    material = len(glb.doc['materials'])
    glb.doc['materials'].append({'name': f'ofg_{asset_id}_thumbnail_finish',
                                'pbrMetallicRoughness': {'baseColorTexture': {'index': albedo},
                                                        'metallicRoughnessTexture': {'index': orm}},
                                'normalTexture': {'index': normal, 'scale': .42},
                                'occlusionTexture': {'index': orm}})
    triangle_count, vertex_count = 0, 0
    used_slots = set()
    for primitive in mesh['primitives']:
        assert primitive.get('mode', 4) == 4
        source_name = primitive.get('extras', {}).get('ofg_source_material', glb.doc['materials'][primitive['material']]['name'])
        attrs = {name: glb.read(index) for name, index in primitive['attributes'].items()
                 if name not in ('TEXCOORD_0', 'TEXCOORD_1', 'TANGENT')}
        pos = attrs['POSITION']
        indices = glb.read(primitive['indices']).ravel().reshape(-1, 3)
        new_indices, selected, uvs, dedup = [], [], [], {}
        for tri in indices:
            points = pos[tri]
            centroid = points.mean(0)
            n = np.cross(points[1] - points[0], points[2] - points[0])
            if np.linalg.norm(n) < 1e-12:
                n = attrs['NORMAL'][tri].mean(0)
            axis = int(np.abs(n).argmax())
            mode = 'xz' if axis == 1 else 'xy' if axis == 2 else 'zy'
            slot = (0 if n[1] > 0 else 3) if axis == 1 else (1 if n[2] < 0 else 2) if axis == 2 else 4
            if centroid[1] > body_height + .001:
                slot, mode = 5, 'neck'
            if asset_id == 'midnight_mallet':
                # The replacement has large white crown panels. Keep them dark
                # and use the thumbnail's narrow, projected parallel sightlines.
                if 'Lime' in source_name:
                    slot = 8
            elif asset_id == 'tourline_prototype':
                if 'Graphite' in source_name:
                    slot = 8
            elif asset_id == 'auto_putt_9000':
                if 'White T' in source_name:
                    slot = 7
            elif asset_id == 'scotty_grail':
                if 'Recessed' in source_name:
                    slot, mode = 2, 'xy'
                elif 'Engraved' in source_name:
                    slot = 8
            used_slots.add(slot)
            for old_index in tri:
                key = int(old_index), slot, mode
                if key not in dedup:
                    v = pos[old_index]
                    if mode == 'xz':
                        u, w = (v[[0, 2]] - bounds[0][[0, 2]]) / (bounds[1] - bounds[0])[[0, 2]]
                    elif mode == 'zy':
                        u, w = (v[2] - bounds[0][2]) / (bounds[1][2] - bounds[0][2]), 1 - v[1] / body_height
                    else:
                        u = (v[0] - bounds[0][0]) / (bounds[1][0] - bounds[0][0])
                        w = 1 - v[1] / (bounds[1][1] if mode == 'neck' else body_height)
                    uv = ((slot % 4) * TILE + PAD + np.clip(u, 0, 1) * (TILE - 2 * PAD),
                          (slot // 4) * TILE + PAD + np.clip(w, 0, 1) * (TILE - 2 * PAD))
                    dedup[key] = len(selected)
                    selected.append(int(old_index))
                    uvs.append(np.array(uv) / SIZE)
                new_indices.append(dedup[key])
        # Geometry and smooth normals are copied, not recalculated or rescaled.
        selected = np.asarray(selected)
        assert np.array_equal(pos[selected][new_indices], pos[indices.ravel()])
        assert np.array_equal(attrs['NORMAL'][selected][new_indices], attrs['NORMAL'][indices.ravel()])
        primitive['attributes'] = {name: glb.accessor(values[selected]) for name, values in attrs.items()}
        primitive['attributes']['TEXCOORD_0'] = glb.accessor(uvs)
        primitive['indices'] = glb.accessor(new_indices, True)
        primitive['material'] = material
        primitive.setdefault('extras', {})['ofg_source_material'] = source_name
        triangle_count += len(indices)
        vertex_count += len(selected)
    mesh.setdefault('extras', {})['ofg_finish_layout'] = 'putter_16_tile_v1'
    glb.save(output / 'models' / source.parent.name / source.name)
    return {'id': asset_id, 'triangles_preserved': triangle_count, 'vertices_with_uvs': vertex_count,
            'atlas_slots': sorted(used_slots), 'body_height_m': body_height}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'build/putter-finishes')
    parser.add_argument('--source', type=Path, default=BASE,
                        help='Equipment asset directory containing the input models')
    args = parser.parse_args()
    report = []
    for item in json.loads((BASE / 'catalog.json').read_text())['items']:
        if item['id'] in FINISHES:
            result = texture_head(item, args.output, args.source)
            report.append(result)
            print(json.dumps(result), flush=True)
    (args.output / 'report.json').write_text(json.dumps(report, indent=2))
