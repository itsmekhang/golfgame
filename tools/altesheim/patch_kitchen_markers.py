"""Write tools/blender/kitchen_layout.py's kitchen into the built clubhouse glTFs without a Blender
rebuild: per restaurant tier, the KITCHEN_* markers and SPOT_chef_* spots are replaced, and the box
fridges fm_lib.fridge baked into the tier's furniture mesh are cut out (the Altesheim fridge model
stands in their place now). A Blender rebuild (build_facilities.py) gives the same result.

usage (project root): python3 -I tools/altesheim/patch_kitchen_markers.py [clubhouse_l2 clubhouse_l3 ...]
"""
import json
import math
import os
import re
import struct
import sys

import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "blender"))
import kitchen_layout as KL  # noqa: E402

FACILITIES = os.path.join(ROOT, "assets", "facilities")
CTYPE = {5121: np.uint8, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def base(name):
    return name.split(".")[0]


def read(g, bin_, ai):
    a = g["accessors"][ai]
    v = g["bufferViews"][a["bufferView"]]
    n = a["count"] * WIDTH[a["type"]]
    arr = np.frombuffer(bin_, CTYPE[a["componentType"]], n, v.get("byteOffset", 0) + a.get("byteOffset", 0))
    return arr.reshape(a["count"], -1) if WIDTH[a["type"]] > 1 else arr


def patch(model):
    path = os.path.join(FACILITIES, model + ".gltf")
    g = json.load(open(path, encoding="utf-8"))
    bin_path = os.path.join(FACILITIES, g["buffers"][0]["uri"])
    bin_ = open(bin_path, "rb").read()  # read from as it was; new index data goes on `tail`
    tail = bytearray()
    nodes = g["nodes"]
    box = next((n for n in nodes if base(n.get("name", "")) == "ROOMBOX_restaurant__kitchen"), None)
    if box is None:
        print(model, "has no kitchen")
        return
    (cx, floor, cz), (sx, _, sz) = box["translation"], box["scale"]
    # Godot (x, y, z) = Blender (x, z, -y)
    kitchen = (cx - sx / 2, -(cz + sz / 2), cx + sx / 2, -(cz - sz / 2))
    k0, ky0, k1, ky1 = kitchen
    back_z = cz + sz / 2  # the back wall, Godot z
    doors = [(n["translation"][0], n.get("scale", [1.0])[0]) for n in nodes
             if re.fullmatch(r"DOOR_\d+", base(n.get("name", ""))) and abs(n["translation"][2] - back_z) < 0.5 and k0 < n["translation"][0] < k1]
    for ti, room in enumerate(nodes):
        m = re.fullmatch(r"ROOM_restaurant_T(\d)", base(room.get("name", "")))
        if not m:
            continue
        tier = int(m.group(1))
        fixtures, chefs = KL.layout(kitchen, tier, doors)
        wanted = [("KITCHEN_%s_%d" % (kind, i), x, y, rz) for i, (kind, x, y, rz) in enumerate(fixtures)]
        wanted += [("SPOT_chef_%d" % i, x, y, face) for i, (x, y, face) in enumerate(chefs)]
        old = [c for c in room["children"] if base(nodes[c]["name"]).startswith("KITCHEN_") or re.fullmatch(r"SPOT_chef_\d+", base(nodes[c]["name"]))]
        slots = old + [None] * (len(wanted) - len(old))
        if len(old) > len(wanted):
            raise SystemExit("%s T%d: more old markers than new (%d > %d)" % (model, tier, len(old), len(wanted)))
        for slot, (name, x, y, rz) in zip(slots, wanted):
            node = {"name": name}
            if abs(rz) > 1e-9:
                node["rotation"] = [0, math.sin(rz / 2), 0, math.cos(rz / 2)]
            node["translation"] = [x, floor, -y]
            if slot is None:
                nodes.append(node)
                room["children"].append(len(nodes) - 1)
            else:
                nodes[slot] = node
        # cut the old box fridges (fm_lib.fridge: a 0.9 x 0.75 x 2.0 steel box with a chrome
        # handle at k0 + 0.6 + i * 1.05, ky0 + 0.5) out of this tier's furniture mesh
        boxes = []
        for i in range(KL.fridge_count(k1 - k0, tier)):
            fx, fy = k0 + 0.6 + i * 1.05, ky0 + 0.5
            boxes.append((fx - 0.48, floor - 0.02, -(fy + 0.45), fx + 0.48, floor + 2.06, -(fy - 0.42)))
        cut = 0
        for prim in g["meshes"][room["mesh"]]["primitives"]:
            if g["materials"][prim["material"]]["name"] not in ("steel", "chrome"):
                continue
            P = read(g, bin_, prim["attributes"]["POSITION"])
            idx = read(g, bin_, prim["indices"]).reshape(-1, 3)
            tri = P[idx]  # (n, 3, 3)
            inside = np.zeros(len(idx), bool)
            for b in boxes:
                inside |= np.all((tri >= b[:3]) & (tri <= b[3:]), axis=(1, 2))
            if not inside.any():
                continue
            cut += int(inside.sum())
            keep = idx[~inside].astype(CTYPE[g["accessors"][prim["indices"]]["componentType"]]).ravel()
            while (len(bin_) + len(tail)) % 4:
                tail.append(0)
            g["bufferViews"].append({"buffer": 0, "byteOffset": len(bin_) + len(tail), "byteLength": keep.nbytes, "target": 34963})
            tail.extend(keep.tobytes())
            a = g["accessors"][prim["indices"]]
            a.update(bufferView=len(g["bufferViews"]) - 1, count=int(keep.size))
            a.pop("byteOffset", None)
        print("%s T%d: %d markers, %d chef spots, back doors %s, cut %d fridge triangles" % (model, tier, len(fixtures), len(chefs), doors, cut))
    g["buffers"][0]["byteLength"] = len(bin_) + len(tail)
    open(bin_path, "wb").write(bin_ + bytes(tail))
    open(path, "w", encoding="utf-8").write(json.dumps(g, indent="\t", separators=(",", ":"), ensure_ascii=False) + "\n")


for model in sys.argv[1:] or ["clubhouse_l2", "clubhouse_l3", "clubhouse_l4"]:
    patch(model)
