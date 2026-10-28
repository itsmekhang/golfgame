"""Cut appliances out of the Altesheim SketchUp/Collada kitchen into game-ready .glb files.

usage: python3 -I tools/altesheim/export_pieces.py tools/altesheim <Altesheim model.dae> assets/facilities/props/altesheim tools/altesheim/pieces.json
(the model.dae export of Altesheim.skp, with its model/ texture folder beside it)
spec: {"name": {"node": "ID123", "turn": 0|90|180|270, "drop_tris": 20000, "drop": ["ID.."],
                "brushed": ["material names to treat as steel beyond the usual metal ones"]}}
Each piece is squared up (the source scene sits a few degrees off-axis), turned by `turn` degrees
about Y after that so its front faces -Z, centred on its footprint and stood on y = 0.
"""
import json, os, sys
import numpy as np
sys.path.insert(0, sys.argv[1])
from dae_lib import Dae
from glb_lib import write_glb
from yaw import min_area_yaw
from brushed import textures as brushed_textures, box_uv
from PIL import Image

dae_path, out_dir, spec = sys.argv[2], sys.argv[3], json.load(open(sys.argv[4]))
d = Dae(dae_path)
base_dir = os.path.dirname(dae_path)
os.makedirs(out_dir, exist_ok=True)

# world matrix of every scene node (by id), walking the visual scene once
world = {}
def index(node, M):
    M = M @ d._matrix(node)
    if node.get("id") and node.get("id") not in world:
        world[node.get("id")] = (node, M)
    for ch in node.findall("node"):
        index(ch, M)
for n in d.visual_scene().findall("node"):
    index(n, np.eye(4))

# brushed-metal look for the steel the pack paints flat (SketchUp has no PBR)
METAL_WORDS = ("silber", "stainless", "metal", "steel", "alumin", "chrome", "color_001_4", "color_001_5",
               "color_b03", "lavenderblush", "_lightgray", "corrogat", "corrugat", "fencing", "grate")
def material_for(mid, extra_metal=()):
    m = d.materials.get(mid, {"name": mid, "color": (0.8, 0.8, 0.8, 1), "texture": None})
    name = m["name"] or mid
    low = name.lower() + " " + (m["texture"] or "").lower()
    col = list(m["color"]) + [1.0] * (4 - len(m["color"]))
    metal = any(w in low for w in METAL_WORDS) or name in extra_metal
    mat = {"name": name, "doubleSided": True,
           "pbrMetallicRoughness": {"baseColorFactor": col, "metallicFactor": 0.0, "roughnessFactor": 0.6}}
    if metal:
        mat["extras"] = {"brushed": True}
    if col[3] < 0.99:
        mat["alphaMode"] = "BLEND"
    return mat, m["texture"]

def drop_paths(node, M, drop_tris, drop):
    """geometry instances under node, skipping heavy sub-nodes (oven trays and the like)."""
    out = []
    def count(n):
        c = sum(sum(len(P) // 3 for _, P, _, _ in d.geometry(ig.get("url")[1:])) for ig in n.findall("instance_geometry"))
        kids = [d.ids[i.get("url")[1:]] for i in n.findall("instance_node")] + n.findall("node")
        return c + sum(count(k) for k in kids)
    def rec(n, M):
        M = M @ d._matrix(n)
        kids = [d.ids[i.get("url")[1:]] for i in n.findall("instance_node")] + n.findall("node")
        for ig in n.findall("instance_geometry"):
            binds = {im.get("symbol"): im.get("target")[1:] for im in ig.iter("instance_material")}
            out.append((M, ig.get("url")[1:], binds))
        for k in kids:
            if k.get("id") in drop:
                continue
            if drop_tris and count(k) > drop_tris:
                # drop only the innermost heavy part (a tray), not the oven holding the trays
                grand = [d.ids[i.get("url")[1:]] for i in k.findall("instance_node")] + k.findall("node")
                if not any(count(g) > drop_tris for g in grand):
                    continue
            rec(k, M)
    parent_M = M @ np.linalg.inv(d._matrix(node))
    rec(node, parent_M)
    return out

BRUSHED = brushed_textures()
for name, s in spec.items():
    node, M = world[s["node"]]
    soups = {}
    for W, gid, binds in drop_paths(node, M, s.get("drop_tris", 0), set(s.get("drop", []))):
        T = d.to_y_up @ W
        R = T[:3, :3]; nrm = np.linalg.inv(R).T; flip = np.linalg.det(R) < 0
        for sym, P, N, UV in d.geometry(gid):
            mid = binds.get(sym, sym)
            Pw = P @ R.T + T[:3, 3]
            Nw = N @ nrm.T if N is not None else None
            if flip:
                Pw = Pw.reshape(-1, 3, 3)[:, ::-1].reshape(-1, 3)
                Nw = None if Nw is None else Nw.reshape(-1, 3, 3)[:, ::-1].reshape(-1, 3)
                UV = None if UV is None else UV.reshape(-1, 3, 2)[:, ::-1].reshape(-1, 2)
            soups.setdefault(mid, []).append((Pw, Nw, UV))
    allP = np.concatenate([p for v in soups.values() for p, _, _ in v])
    yaw = s.get("yaw", min_area_yaw(allP[:, [0, 2]]))
    a = np.radians(yaw + s.get("turn", 0))
    c, sn = np.cos(a), np.sin(a)
    # yaw.py turns (x, z) by +deg with [[c,-s],[s,c]]; about Y that is x' = c x - s z, z' = s x + c z
    Ry = np.array([[c, 0, -sn], [0, 1, 0], [sn, 0, c]])
    rotP = allP @ Ry.T
    lo, hi = rotP.min(0), rotP.max(0)
    off = np.array([-(lo[0] + hi[0]) / 2, -lo[1], -(lo[2] + hi[2]) / 2])
    parts, materials, images, img_index = [], [], [], {}
    brushed_pair = None
    for mid, lst in soups.items():
        P = np.concatenate([p for p, _, _ in lst]) @ Ry.T + off
        N = np.concatenate([n if n is not None else np.zeros_like(p) for p, n, _ in lst]) @ Ry.T
        if not np.any(N):  # flat normals from the faces
            t = P.reshape(-1, 3, 3); fn = np.cross(t[:, 1] - t[:, 0], t[:, 2] - t[:, 0]); N = np.repeat(fn, 3, 0)
        ln = np.linalg.norm(N, axis=1, keepdims=True); N = N / np.where(ln == 0, 1, ln)
        has_uv = all(uv is not None for _, _, uv in lst)
        UV = np.concatenate([uv for _, _, uv in lst]) if has_uv else None
        mat, tex = material_for(mid, s.get("brushed", ()))
        if mat.get("extras", {}).get("brushed"):
            if brushed_pair is None:
                alb, mr = BRUSHED
                images.append((alb, "image/png")); images.append((mr, "image/png"))
                brushed_pair = (len(images) - 2, len(images) - 1)
            tint = np.array(mat["pbrMetallicRoughness"]["baseColorFactor"][:3], float)
            if tex and os.path.exists(os.path.join(base_dir, tex)):
                tint = np.asarray(Image.open(os.path.join(base_dir, tex)).convert("RGB").resize((16, 16))).reshape(-1, 3).mean(0) / 255
            lum = float(tint @ [0.2126, 0.7152, 0.0722])
            tint = tint * (np.clip(lum, 0.62, 0.86) / max(lum, 1e-3))
            mat["pbrMetallicRoughness"].update(baseColorFactor=[*np.clip(tint, 0, 1).round(4).tolist(), mat["pbrMetallicRoughness"]["baseColorFactor"][3]],
                                               metallicFactor=0.9, roughnessFactor=1.0)
            mat["baseColorTexture"], mat["mrTexture"] = brushed_pair
            mat["name"] = "brushed_" + mat["name"]
            UV = box_uv(P, N)
        elif tex and has_uv and os.path.exists(os.path.join(base_dir, tex)):
            if tex not in img_index:
                data = open(os.path.join(base_dir, tex), "rb").read()
                images.append((data, "image/png" if tex.lower().endswith(".png") else "image/jpeg"))
                img_index[tex] = len(images) - 1
            mat["baseColorTexture"] = img_index[tex]
            mat["pbrMetallicRoughness"]["baseColorFactor"] = [1, 1, 1, mat["pbrMetallicRoughness"]["baseColorFactor"][3]]
            UV = UV.copy(); UV[:, 1] = 1.0 - UV[:, 1]  # Collada v-up -> glTF v-down
        else:
            UV = None
        # weld identical corners
        cols = [P, N] + ([UV] if UV is not None else [])
        key = np.round(np.concatenate(cols, 1), 5)
        uniq, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
        materials.append(mat)
        parts.append((len(materials) - 1, P[first], N[first], UV[first] if UV is not None else None, inv.ravel().astype(np.uint32)))
    write_glb(os.path.join(out_dir, name + ".glb"), "Kitchen_" + name, parts, materials, images)
    size = hi - lo
    info = {"node": s["node"], "yaw": round(float(yaw), 2), "size": [round(float(v), 3) for v in size],
                    "tris": int(sum(len(p[4]) // 3 for p in parts)), "kb": os.path.getsize(os.path.join(out_dir, name + ".glb")) // 1024}
    print(name, info, flush=True)
