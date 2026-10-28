"""Find z-fighting in the facility models: pairs of faces that lie in the same plane, overlap,
face the same way and show different materials (they flicker against each other in game).

    blender -b --factory-startup -P tools/blender/check_zfight.py -- [model ...]

Checks assets/facilities/<model>.gltf (all of them by default) and prints, per model, each
clashing material pair with how many overlapping face pairs and where one of them is.
"""
import os
import sys
from collections import defaultdict

import bpy
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
DIR = os.path.join(ROOT, "assets", "facilities")
TOL = 0.004  # metres apart that still fight at a distance
MIN_AREA = 0.0004  # overlap (m^2) worth reporting


def faces(ob):
    """(axis, sign, plane coord, 2D rect in the other two axes, material) per axis-aligned face."""
    out = []
    me = ob.data
    mw = ob.matrix_world
    for p in me.polygons:
        n = (mw.to_3x3() @ p.normal).normalized()
        axis = max(range(3), key=lambda i: abs(n[i]))
        if abs(n[axis]) < 0.995 or (axis == 2 and n[axis] < 0):
            continue  # downward faces: nobody looks at them
        vs = [mw @ me.vertices[i].co for i in p.vertices]
        others = [i for i in range(3) if i != axis]
        lo = [min(v[o] for v in vs) for o in others]
        hi = [max(v[o] for v in vs) for o in others]
        mat = me.materials[p.material_index].name if me.materials else ""
        out.append((axis, 1 if n[axis] > 0 else -1, sum(v[axis] for v in vs) / len(vs), lo, hi, mat.split(".")[0], ob.name))
    return out


def check(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    allf = []
    for ob in bpy.data.objects:
        if ob.type == "MESH" and not ob.name.startswith("COL_"):
            allf.extend(faces(ob))
    # bucket by (axis, sign, plane) so only neighbours are compared
    buckets = defaultdict(list)
    for f in allf:
        buckets[(f[0], f[1], round(f[2] / TOL))].append(f)
    clashes = defaultdict(lambda: [0, None])
    seen = set()
    for key, fs in buckets.items():
        cand = list(fs) + buckets.get((key[0], key[1], key[2] + 1), [])
        for i in range(len(fs)):
            a = fs[i]
            for b in cand[i + 1:]:
                if a[5] == b[5] or abs(a[2] - b[2]) > TOL:
                    continue
                if a[6].startswith("ROOM_") and b[6].startswith("ROOM_") and a[6].rsplit("_T", 1)[0] == b[6].rsplit("_T", 1)[0] and a[6] != b[6]:
                    continue  # different tiers of one room never show together
                w = min(a[4][0], b[4][0]) - max(a[3][0], b[3][0])
                h = min(a[4][1], b[4][1]) - max(a[3][1], b[3][1])
                if w <= 0.01 or h <= 0.01 or w * h < MIN_AREA:
                    continue
                pair = tuple(sorted((a[5], b[5]))) + ("xyz"[a[0]] + ("+" if a[1] > 0 else "-"),)
                c = clashes[pair]
                c[0] += 1
                if c[1] is None:
                    c[1] = (round(a[2], 3), [round((a[3][k] + a[4][k]) * 0.5, 2) for k in range(2)], a[6], b[6])
    name = os.path.basename(path)
    total = sum(c[0] for c in clashes.values())
    print("MODEL %s: %d clashing face pairs" % (name, total))
    for pair, (n, where) in sorted(clashes.items(), key=lambda kv: -kv[1][0])[:25]:
        print("   %-34s %5d   e.g. plane %s at %s (%s / %s)" % ("%s vs %s (%s)" % pair, n, where[0], where[1], where[2], where[3]))
    return total


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    models = args or sorted(f[:-5] for f in os.listdir(DIR) if f.endswith(".gltf"))
    grand = 0
    for m in models:
        grand += check(os.path.join(DIR, m + ".gltf"))
    print("TOTAL", grand)


main()
