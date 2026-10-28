"""Tiny glTF-binary writer/reader for triangle soups grouped by material (numpy + stdlib only)."""
import json
import os
import struct
import numpy as np


def _pad(b, ch=b"\x00"):
    return b + ch * ((4 - len(b) % 4) % 4)


def write_glb(path, name, parts, materials, images):
    """parts: [(material_index, P float32 (n,3), N float32 (n,3), UV float32 (n,2) or None, I uint32 (m,))]
    materials: list of glTF material dicts; a "baseColorTexture" key holding an image index is turned
    into a texture reference. images: list of (bytes, mime)."""
    bin_ = bytearray()
    views, accessors, prims = [], [], []

    def view(data, target=None):
        off = len(bin_)
        bin_.extend(_pad(bytes(data)))
        v = {"buffer": 0, "byteOffset": off, "byteLength": len(data)}
        if target:
            v["target"] = target
        views.append(v)
        return len(views) - 1

    def acc(arr, ctype, typ, target, minmax=False):
        a = {"bufferView": view(arr.tobytes(), target), "componentType": ctype, "count": int(arr.shape[0]), "type": typ}
        if minmax:
            a["min"] = arr.min(0).tolist()
            a["max"] = arr.max(0).tolist()
        accessors.append(a)
        return len(accessors) - 1

    for mi, P, N, UV, I in parts:
        attrs = {"POSITION": acc(P.astype(np.float32), 5126, "VEC3", 34962, True),
                 "NORMAL": acc(N.astype(np.float32), 5126, "VEC3", 34962)}
        if UV is not None:
            attrs["TEXCOORD_0"] = acc(UV.astype(np.float32), 5126, "VEC2", 34962)
        prims.append({"attributes": attrs, "indices": acc(I.astype(np.uint32), 5125, "SCALAR", 34963), "material": mi, "mode": 4})

    gl_images, textures = [], []
    for data, mime in images:
        gl_images.append({"bufferView": view(data), "mimeType": mime})
        textures.append({"source": len(gl_images) - 1, "sampler": 0})
    mats = []
    for m in materials:
        m = json.loads(json.dumps(m))
        pbr = m.setdefault("pbrMetallicRoughness", {})
        if "baseColorTexture" in m:
            pbr["baseColorTexture"] = {"index": m.pop("baseColorTexture")}
        if "mrTexture" in m:
            pbr["metallicRoughnessTexture"] = {"index": m.pop("mrTexture")}
        mats.append(m)
    doc = {"asset": {"version": "2.0", "generator": "golfgame tools/altesheim"},
           "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0, "name": name}],
           "meshes": [{"name": name, "primitives": prims}], "materials": mats,
           "accessors": accessors, "bufferViews": views, "buffers": [{"byteLength": len(bin_)}]}
    if gl_images:
        doc["images"] = gl_images
        doc["textures"] = textures
        doc["samplers"] = [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}]
    js = _pad(json.dumps(doc, separators=(",", ":")).encode(), b" ")
    bb = bytes(bin_)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(bb)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(bb), 0x004E4942) + bb)


def read_glb_positions(path):
    """All POSITION data of a glb (node transforms ignored) and its JSON."""
    raw = open(path, "rb").read()
    jl, _ = struct.unpack_from("<II", raw, 12)
    doc = json.loads(raw[20:20 + jl])
    bin_ = raw[20 + jl + 8:]
    pts = []
    for mesh in doc["meshes"]:
        for p in mesh["primitives"]:
            a = doc["accessors"][p["attributes"]["POSITION"]]
            v = doc["bufferViews"][a["bufferView"]]
            off = v.get("byteOffset", 0) + a.get("byteOffset", 0)
            pts.append(np.frombuffer(bin_, np.float32, a["count"] * 3, off).reshape(-1, 3))
    return np.concatenate(pts), doc
