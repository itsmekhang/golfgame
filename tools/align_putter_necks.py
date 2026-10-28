"""Bend the top of each putter head's neck onto its shaft's axis, so shaft and neck meet coaxially.

Some putter heads (assets/openfairway_equipment/models) end in a neck sleeve that is offset from, or tipped
against, the shaft the club places at its shaft socket: the shaft comes out of the side of the sleeve (a step
and a notch), or a sleeve sits on a post at an angle (an elbow). The shaft, grip and head placement are left as
they are (the swing rig holds the grip; the head's lie and face stay put). Instead the neck's last NECK_RUN mm
are warped: the neck is sliced square to the shaft, each slice's centre found, and each slice slid onto the
shaft's axis by a weight that eases in from 0 (NECK_RUN below the socket) to 1 (FULL_AT below it and above),
fading out round each slice (only the neck moves, not the body under it). Normals and tangents follow the warp.

    python tools/align_putter_necks.py [--apply] [id ...]
Without --apply it reports each neck's offset from the shaft along its length. Back the files up first.
"""
from pathlib import Path
import argparse
import json
import struct

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
MODELS = {  # id: (model, options) - centre: slide the neck onto the shaft's axis; min_r: thicken the neck's top
    # to this radius where the shaft sits inside it (thinner, the shaft broke through its wall); set_r / set_from:
    # make the neck's top this radius from this far below the socket up (a fat sleeve slimmed onto the shaft);
    # walls: "all" moves a single-walled sleeve's every vertex (else only its outer wall: normals facing out);
    # ferrule_r: the club's ferrule likewise; cap: close the neck's open top (it cast a ring of shadow). The game's
    # shaft is 4.87 mm in radius: a neck mouth needs ~0.4 mm more, or the shaft shows through it
    "rustbelt_blade": ("putter/ofg_rustbelt_blade.glb", dict(set_r=0.0055, set_from=-0.017, walls="all", ferrule_r=0.0059,
                                                         cap=True)),
    "brass_relic": ("putter/ofg_brass_relic.glb", dict(centre=True, min_r=0.0053)),
    "midnight_mallet": ("putter/ofg_midnight_mallet.glb", dict(centre=True, min_r=0.0053)),
    "tourline_prototype": ("putter/ofg_tourline_prototype.glb", dict(centre=True, min_r=0.0053)),
    "auto_putt_9000": ("admin/ofg_auto_putt_9000.glb", dict(centre=True, min_r=0.0053)),
}
NECK_RUN = 0.030   # m below the socket where the bend starts (weight 0)
FULL_AT = 0.008    # m below the socket from which the neck is fully on the shaft's axis
SLICE = 0.001      # m: slice spacing (and half-thickness 0.75 of it)
SEARCH_R = 0.011   # m: a slice's vertices lie within this of the neck's centre found just above it
FADE_R = 0.003     # m: round each slice, the warp fades out over this beyond the slice's own radius


class Glb:
    def __init__(self, path):
        raw = path.read_bytes()
        magic, version, total = struct.unpack_from("<III", raw)
        assert (magic, version, total) == (0x46546C67, 2, len(raw))
        n = struct.unpack_from("<I", raw, 12)[0]
        self.doc = json.loads(raw[20:20 + n])
        bn, bt = struct.unpack_from("<II", raw, 20 + n)
        assert bt == 0x004E4942
        self.data = bytearray(raw[28 + n:28 + n + bn])

    def _view(self, index):
        a = self.doc["accessors"][index]
        v = self.doc["bufferViews"][a["bufferView"]]
        assert a["componentType"] == 5126
        width = {"VEC3": 3, "VEC4": 4}[a["type"]]
        stride = v.get("byteStride", 4 * width)
        off = v.get("byteOffset", 0) + a.get("byteOffset", 0)
        return a, width, stride, off

    def read(self, index):
        a, width, stride, off = self._view(index)
        return np.ndarray((a["count"], width), dtype="<f4", buffer=self.data, offset=off, strides=(stride, 4)).astype(float)

    def write(self, index, values):
        a, width, stride, off = self._view(index)
        dst = np.ndarray((a["count"], width), dtype="<f4", buffer=self.data, offset=off, strides=(stride, 4))
        dst[:] = values.astype("<f4")
        if "min" in a and width == 3 and index in self.positions:
            a["min"] = [float(x) for x in values.min(0)]
            a["max"] = [float(x) for x in values.max(0)]

    def save(self, path):
        self.doc["buffers"][0]["byteLength"] = len(self.data)
        pad = bytearray(self.data) + b"\0" * (-len(self.data) % 4)
        js = json.dumps(self.doc, separators=(",", ":")).encode()
        js += b" " * (-len(js) % 4)
        out = struct.pack("<III", 0x46546C67, 2, 28 + len(js) + len(pad))
        out += struct.pack("<II", len(js), 0x4E4F534A) + js + struct.pack("<II", len(pad), 0x004E4942) + pad
        path.write_bytes(out)


def node(doc, suffix):
    return next(n for n in doc["nodes"] if n.get("name", "").endswith(suffix))


def quat_rotate(q, v):
    x, y, z, w = q
    u = np.array([x, y, z])
    return v + 2.0 * np.cross(u, np.cross(u, v) + w * v)


def centreline(p, a, e1, e2):
    """The neck's centre (in the plane square to the shaft, as offsets along e1, e2) at each slice height s,
    from the top of the neck down to NECK_RUN below the socket, tracking it slice by slice."""
    s = p @ a
    u, v = p @ e1, p @ e2
    near = np.hypot(u, v) < SEARCH_R
    top = s[near].max()
    rows = []
    cu, cv = 0.0, 0.0
    k = top
    while k > -NECK_RUN - 0.004:
        m = (np.abs(s - k) < 0.75 * SLICE) & (np.hypot(u - cu, v - cv) < SEARCH_R)
        if m.sum() >= 6:
            cu, cv = (u[m].min() + u[m].max()) / 2, (v[m].min() + v[m].max()) / 2
            r = max(u[m].max() - u[m].min(), v[m].max() - v[m].min()) / 2
            rows.append((k, cu, cv, r))
        k -= SLICE
    rows.sort()
    return np.array(rows)


def weight(s):
    t = np.clip((s + NECK_RUN) / (NECK_RUN - FULL_AT), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def smooth(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3 - 2 * t)


def displacement(p, a, e1, e2, rows, opts, n=None):
    """The warp at points p (relative to the socket): each slid toward the shaft's axis by its slice's offset
    (centre); then the neck's outer wall (normals facing away from the axis) set round the axis at set_r, or
    pushed out to at least min_r, vertex by vertex (a slice scaled as a whole kept a flattened side too close
    to the shaft, which showed through it)."""
    s = p @ a
    u, v = p @ e1, p @ e2
    ss = rows[:, 0]
    cu = np.interp(s, ss, rows[:, 1])
    cv = np.interp(s, ss, rows[:, 2])
    r = np.interp(s, ss, rows[:, 3])
    inside = (s >= ss[0] - SLICE) & (s <= ss[-1] + 0.004)
    D = np.zeros_like(p)
    if opts.get("centre"):
        d = np.hypot(u - cu, v - cv)
        fall = smooth((r + FADE_R - d) / FADE_R)
        w = weight(s) * fall * inside
        D -= np.outer(w * cu, e1) + np.outer(w * cv, e2)
    if (opts.get("min_r") or opts.get("set_r")) and n is not None:
        q = p + D
        qu, qv = q @ e1, q @ e2
        rho = np.maximum(np.hypot(qu, qv), 1e-6)
        du, dv = qu / rho, qv / rho
        outer = ((n @ e1) * du + (n @ e2) * dv) > 0.2 if opts.get("walls") != "all" else np.ones(len(p), bool)
        near = rho < SEARCH_R
        if opts.get("set_r"):
            target = np.full_like(rho, opts["set_r"])
            wt = smooth((s - opts["set_from"] + 0.003) / 0.003)
        else:
            k = 0.0006  # (a smooth max: no crease where the push starts)
            target = 0.5 * (rho + opts["min_r"] + np.sqrt((rho - opts["min_r"]) ** 2 + k * k))
            wt = smooth((s + 0.016) / 0.006)
        g = wt * outer * near * inside * (target - rho)
        D += np.outer(g * du, e1) + np.outer(g * dv, e2)
    return D


def cofactor_normals(J, n):
    """Normals carried through a warp with Jacobian J: cof(J) n (= det J * J^-T n), defined even where the warp
    flattens a direction (a wall set to one radius)."""
    j1, j2, j3 = J[:, :, 0], J[:, :, 1], J[:, :, 2]
    cof = np.stack([np.cross(j2, j3), np.cross(j3, j1), np.cross(j1, j2)], axis=2)
    out = np.einsum("nij,nj->ni", cof, n)
    bad = np.linalg.norm(out, axis=1) < 1e-9
    out[bad] = n[bad]
    return out / np.linalg.norm(out, axis=1)[:, None]


def boundary_loop(pos, idx):
    """The mesh's one open edge loop (by welded position), ordered: vertex indices into pos."""
    from collections import Counter, defaultdict
    key = np.round(pos * 1e5).astype(np.int64)
    _, weld = np.unique(key, axis=0, return_inverse=True)
    weld = weld.ravel()
    rep = {}
    for i, w in enumerate(weld):
        rep.setdefault(int(w), i)
    count = Counter()
    for tri in weld[idx]:
        for a_, b_ in ((tri[0], tri[1]), (tri[1], tri[2]), (tri[2], tri[0])):
            count[tuple(sorted((int(a_), int(b_))))] += 1
    nbr = defaultdict(list)
    for (a_, b_), n in count.items():
        if n == 1:
            nbr[a_].append(b_)
            nbr[b_].append(a_)
    if not nbr:
        return []
    start = next(iter(nbr))
    loop, prev, cur = [start], None, start
    while True:
        nxt = [q for q in nbr[cur] if q != prev]
        if not nxt or nxt[0] == start:
            break
        prev, cur = cur, nxt[0]
        loop.append(cur)
    return [rep[w] for w in loop]


def append_primitive(g, mesh, material, pos, nrm, uv, tris):
    """A new primitive on `mesh` (positions, normals, UVs, triangles) at the end of the GLB's buffer."""
    def add(arr, comp, kind, target):
        while len(g.data) % 4:
            g.data.append(0)
        off = len(g.data)
        g.data.extend(arr.tobytes())
        g.doc["bufferViews"].append({"buffer": 0, "byteOffset": off, "byteLength": arr.nbytes, "target": target})
        acc = {"bufferView": len(g.doc["bufferViews"]) - 1, "componentType": comp, "count": len(arr), "type": kind}
        if kind == "VEC3" and comp == 5126:
            acc["min"], acc["max"] = [float(x) for x in arr.min(0)], [float(x) for x in arr.max(0)]
        g.doc["accessors"].append(acc)
        return len(g.doc["accessors"]) - 1
    prim = {"attributes": {"POSITION": add(pos.astype("<f4"), 5126, "VEC3", 34962),
                           "NORMAL": add(nrm.astype("<f4"), 5126, "VEC3", 34962),
                           "TEXCOORD_0": add(uv.astype("<f4"), 5126, "VEC2", 34962)},
            "indices": add(tris.astype("<u4").ravel(), 5125, "SCALAR", 34963), "material": material, "mode": 4}
    mesh["primitives"].append(prim)


def read_any(g, index):
    a = g.doc["accessors"][index]
    v = g.doc["bufferViews"][a["bufferView"]]
    dt = {5126: "<f4", 5125: "<u4", 5123: "<u2", 5121: "u1"}[a["componentType"]]
    width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
    item = np.dtype(dt).itemsize
    return np.ndarray((a["count"], width), dtype=dt, buffer=g.data, offset=v.get("byteOffset", 0) + a.get("byteOffset", 0),
                      strides=(v.get("byteStride", item * width), item)).copy()


def align(path, opts, apply_):
    g = Glb(path)
    doc = g.doc
    head, shaft = node(doc, "__head"), node(doc, "__shaft")
    assert not head.get("rotation") and not head.get("scale"), "head node carries more than a translation"
    th = np.array(head.get("translation", [0, 0, 0]), float)
    socket = np.array(shaft["translation"], float)
    a = quat_rotate(np.array(shaft["rotation"], float), np.array([0.0, 1.0, 0.0]))
    a /= np.linalg.norm(a)
    e1 = np.cross(a, [0.0, 0.0, 1.0])
    e1 /= np.linalg.norm(e1)
    e2 = np.cross(a, e1)
    mesh = doc["meshes"][head["mesh"]]
    g.positions = {pr["attributes"]["POSITION"] for pr in mesh["primitives"]}
    allp = np.concatenate([g.read(pr["attributes"]["POSITION"]) for pr in mesh["primitives"]]) + th - socket
    rows = centreline(allp, a, e1, e2)
    if not opts.get("centre"):  # (about the axis: each slice's radius from the axis itself, steadied)
        rr = []
        for k_ in rows[:, 0]:
            m = (np.abs(allp @ a - k_) < 0.75 * SLICE) & (np.hypot(allp @ e1, allp @ e2) < SEARCH_R)
            rr.append(np.hypot(allp[m] @ e1, allp[m] @ e2).max() if m.any() else np.nan)
        rr = np.array(rr)
        rows[:, 3] = np.array([np.nanmedian(rr[max(0, i - 2):i + 3]) for i in range(len(rr))])
    report = ["%s: neck offset from the shaft's axis (mm), by height below the socket:" % path.name]
    for k in (-0.028, -0.020, -0.012, -0.006, 0.0, 0.004):
        if rows[0, 0] <= k <= rows[-1, 0]:
            cu, cv, r = (np.interp(k, rows[:, 0], rows[:, j]) for j in (1, 2, 3))
            report.append("   s %+5.1f: offset %.2f (r %.2f)" % (k * 1000, np.hypot(cu, cv) * 1000, r * 1000))
    print("\n".join(report))
    if not apply_:
        return
    moved = 0
    eps = 1e-5
    for pr in mesh["primitives"]:
        at = pr["attributes"]
        p = g.read(at["POSITION"]) + th - socket
        n0 = g.read(at["NORMAL"]) if "NORMAL" in at else None
        warp = lambda q: displacement(q, a, e1, e2, rows, opts, n0)  # noqa: E731
        D = warp(p)
        moved += int((np.linalg.norm(D, axis=1) > 1e-6).sum())
        J = np.repeat(np.eye(3)[None], len(p), 0)
        for e in (a, e1, e2):  # J = I + sum over the frame of (d warp / d e) e^T
            J += np.einsum("ni,j->nij", (warp(p + eps * e) - warp(p - eps * e)) / (2 * eps), e)
        g.write(at["POSITION"], p + D + socket - th)
        if n0 is not None:
            g.write(at["NORMAL"], cofactor_normals(J, n0))
        if "TANGENT" in at:
            t = g.read(at["TANGENT"])
            t3 = np.einsum("nij,nj->ni", J, t[:, :3])
            t[:, :3] = t3 / np.maximum(np.linalg.norm(t3, axis=1), 1e-9)[:, None]
            g.write(at["TANGENT"], t)
    if opts.get("ferrule_r"):  # the ferrule, slimmed onto the shaft likewise (uniformly, about the axis)
        f = node(doc, "__ferrule")
        tf = np.array(f.get("translation", [0, 0, 0]), float)
        for pr in doc["meshes"][f["mesh"]]["primitives"]:
            at = pr["attributes"]
            q = g.read(at["POSITION"]) + tf - socket
            qa = q @ a
            rad = q - np.outer(qa, a)
            k = opts["ferrule_r"] / np.linalg.norm(rad, axis=1).max()
            g.positions = {at["POSITION"]}
            g.write(at["POSITION"], np.outer(qa, a) + rad * k + socket - tf)
            n = g.read(at["NORMAL"])
            na = n @ a
            n2 = np.outer(na, a) + (n - np.outer(na, a)) / k
            g.write(at["NORMAL"], n2 / np.linalg.norm(n2, axis=1)[:, None])
            print("   ferrule slimmed x%.2f" % k)
    if opts.get("cap"):  # close the neck's open top
        pr = mesh["primitives"][0]
        pos = g.read(pr["attributes"]["POSITION"])
        idx = read_any(g, pr["indices"]).reshape(-1, 3).astype(np.int64)
        loop = boundary_loop(pos, idx)
        if len(loop) >= 3:
            ring = pos[loop]
            centre = ring.mean(0)
            uvs = read_any(g, pr["attributes"]["TEXCOORD_0"]).astype(float)[loop]
            cp = np.vstack([ring, centre[None]])
            cuv = np.vstack([uvs, uvs.mean(0)[None]])
            n = len(ring)
            tris = np.array([[n, i, (i + 1) % n] for i in range(n)])
            face_n = np.cross(cp[tris[0, 1]] - cp[n], cp[tris[0, 2]] - cp[n])
            if face_n @ a < 0:
                tris = tris[:, [0, 2, 1]]
            append_primitive(g, mesh, pr.get("material"), cp, np.tile(a, (n + 1, 1)), cuv, tris)
            print("   capped the neck's open top (%d edges)" % n)
    g.save(path)
    print("   warped %d vertices" % moved)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("ids", nargs="*")
    args = ap.parse_args()
    for cid in args.ids or MODELS:
        model, opts = MODELS[cid]
        align(ROOT / "assets/openfairway_equipment/models" / model, opts, args.apply)


if __name__ == "__main__":
    main()
