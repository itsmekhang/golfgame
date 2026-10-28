"""Close the gap between each putter head's neck opening and the shaft/grip/ferrule.

The live putter heads (assets/openfairway_equipment/models/putter/*.glb, plus the
admin auto_putt_9000) were fitted with replacement head meshes at some point, but the
shaft/grip/ferrule/shaft_socket nodes were left at the old procedural socket position,
which sits a few millimetres away from where the replacement head's neck actually ends.
This measures the head mesh's real neck-opening centre (the vertices nearest the
existing shaft_socket marker) and re-anchors shaft/grip/ferrule/shaft_socket there,
without touching any head geometry, materials, or textures.

Run: python tools/fix_putter_heads_gap.py [--apply]
Without --apply it only reports the measured gap per club. With --apply it rewrites
the glb files in place (back up first).
"""
from pathlib import Path
import argparse
import json
import struct

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
TARGETS = [
    ROOT / 'assets/openfairway_equipment/models/putter/ofg_loaner_putter.glb',
    ROOT / 'assets/openfairway_equipment/models/putter/ofg_rustbelt_blade.glb',
    ROOT / 'assets/openfairway_equipment/models/putter/ofg_brass_relic.glb',
    ROOT / 'assets/openfairway_equipment/models/putter/ofg_midnight_mallet.glb',
    ROOT / 'assets/openfairway_equipment/models/putter/ofg_copper_classic.glb',
    ROOT / 'assets/openfairway_equipment/models/putter/ofg_tourline_prototype.glb',
    ROOT / 'assets/openfairway_equipment/models/putter/ofg_blackout_tour_issue.glb',
    ROOT / 'assets/openfairway_equipment/models/putter/ofg_scotty_grail.glb',
    ROOT / 'assets/openfairway_equipment/models/admin/ofg_auto_putt_9000.glb',
]
# The true neck-end ring sits at a near-constant distance from the current (slightly
# wrong) socket point, but how much slack is needed to capture the *whole* ring (not
# just the near-side arc) varies per model with how lateral the gap is. So instead of
# one fixed tolerance, scan a range and take the smallest one whose ring has grown to
# match the shaft's own radius -- any looser than that starts pulling in unrelated
# body/flange geometry that happens to be similarly far from the target.
TOLERANCE_STEPS_MM = [0.3, 0.5, 0.8, 1.2, 1.6, 2.0, 2.5, 3.0, 4.0, 5.0]


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

    def save(self, path):
        self.doc['buffers'][0]['byteLength'] = len(self.data)
        padded = bytearray(self.data)
        padded.extend(b'\0' * (-len(padded) % 4))
        encoded = json.dumps(self.doc, separators=(',', ':')).encode()
        encoded += b' ' * (-len(encoded) % 4)
        result = struct.pack('<III', 0x46546C67, 2, 28 + len(encoded) + len(padded))
        result += struct.pack('<II', len(encoded), 0x4E4F534A) + encoded
        result += struct.pack('<II', len(padded), 0x004E4942) + padded
        path.write_bytes(result)


def node_by_suffix(doc, suffix):
    return next(n for n in doc['nodes'] if n.get('name', '').endswith(suffix))


def node_by_suffix_optional(doc, suffix):
    return next((n for n in doc['nodes'] if n.get('name', '').endswith(suffix)), None)


def shaft_start_radius(doc, glb):
    shaft = node_by_suffix(doc, '__shaft')
    mesh = doc['meshes'][shaft['mesh']]
    pos = np.concatenate([glb.read(p['attributes']['POSITION']) for p in mesh['primitives']])
    ymin = pos[:, 1].min()
    ring = pos[pos[:, 1] < ymin + 0.0005]
    return float(np.linalg.norm(ring - ring.mean(0), axis=1).mean())


def find_ring(world, target, expected_radius):
    dist = np.linalg.norm(world - target, axis=1)
    d_min = dist.min()
    if d_min > 0.02:
        return None
    best = None
    for tol_mm in TOLERANCE_STEPS_MM:
        ring = world[dist < d_min + tol_mm / 1000]
        if len(ring) < 6:
            continue
        centroid = ring.mean(0)
        radius = float(np.linalg.norm(ring - centroid, axis=1).mean())
        best = (ring, centroid, radius, tol_mm)
        if radius >= expected_radius * 0.85:
            break  # ring has grown to full size -- stop before contamination creeps in
    return best


def fix_one(path, apply_):
    glb = Glb(path)
    doc = glb.doc
    head = node_by_suffix(doc, '__head')
    socket = node_by_suffix(doc, '__shaft_socket')
    head_t = np.array(head.get('translation', [0, 0, 0]), dtype=float)
    target = np.array(socket['translation'], dtype=float)
    expected_radius = shaft_start_radius(doc, glb)

    mesh = doc['meshes'][head['mesh']]
    positions = np.concatenate([glb.read(p['attributes']['POSITION']) for p in mesh['primitives']])
    world = positions + head_t  # head node carries translation only (no rotation/scale)

    found = find_ring(world, target, expected_radius)
    if found is None:
        print(f'{path.name}: could not isolate a clean ring -- skipping, needs manual look')
        return
    ring, new_target, ring_radius, tol_mm = found
    gap = float(np.linalg.norm(new_target - target))
    print(f'{path.name}: {len(ring)} verts at tol={tol_mm}mm, ring radius {ring_radius * 1000:.2f}mm '
          f'(shaft {expected_radius * 1000:.2f}mm), gap {gap * 1000:.2f}mm, '
          f'delta {(new_target - target) * 1000} mm')

    if not apply_:
        return

    delta = new_target - target
    for suffix in ('__shaft', '__grip', '__ferrule', '__shaft_socket'):
        node = node_by_suffix_optional(doc, suffix)
        if node is None:
            continue
        t = np.array(node.get('translation', [0, 0, 0]), dtype=float) + delta
        node['translation'] = t.tolist()
    glb.save(path)
    print(f'  -> patched shaft/grip/ferrule/socket by {np.linalg.norm(delta) * 1000:.2f}mm')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true', help='write the fix (default: dry run report only)')
    args = parser.parse_args()
    for path in TARGETS:
        fix_one(path, args.apply)
