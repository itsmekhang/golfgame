"""Minimal Collada (SketchUp export) reader: flattens the scene into per-node triangle soups.

Only the subset SketchUp writes: <matrix> transforms, <instance_geometry>/<instance_node>,
<triangles> with VERTEX(POSITION[,NORMAL]) + optional TEXCOORD, phong/lambert diffuse colour or
texture. Output space: metres, Y-up (Godot / glTF): (x, y, z)_skp -> (x, z, -y) * unit.
"""
import re
import xml.etree.ElementTree as ET
import numpy as np


def _strip(tree):
    for el in tree.iter():
        if isinstance(el.tag, str) and "}" in el.tag:
            el.tag = el.tag.split("}", 1)[1]
    return tree


def _floats(text):
    return np.array(text.split(), dtype=np.float64) if text else np.zeros(0)


class Dae:
    def __init__(self, path):
        self.root = _strip(ET.parse(path)).getroot()
        unit = self.root.find("asset/unit")
        self.unit = float(unit.get("meter")) if unit is not None else 1.0
        self.ids = {el.get("id"): el for el in self.root.iter() if el.get("id")}
        self.images = {}
        for im in self.root.iter("image"):
            f = im.find("init_from")
            if f is not None:
                self.images[im.get("id")] = f.text
        self._geo_cache = {}
        self.materials = {}
        for m in self.root.iter("material"):
            self.materials[m.get("id")] = self._material(m)
        # SketchUp Z-up inches -> Y-up metres
        s = self.unit
        self.to_y_up = np.array([[s, 0, 0, 0], [0, 0, s, 0], [0, -s, 0, 0], [0, 0, 0, 1]], dtype=np.float64)

    def _material(self, m):
        info = {"id": m.get("id"), "name": m.get("name") or m.get("id"), "color": (0.8, 0.8, 0.8, 1.0), "texture": None}
        ie = m.find("instance_effect")
        eff = self.ids.get(ie.get("url", "")[1:]) if ie is not None else None
        if eff is None:
            return info
        diffuse = eff.find(".//diffuse")
        if diffuse is not None:
            c = diffuse.find("color")
            if c is not None:
                info["color"] = tuple(float(v) for v in c.text.split())
            t = diffuse.find("texture")
            if t is not None:
                # texture -> sampler2D newparam -> surface newparam -> image
                samp = t.get("texture")
                img = None
                for np_ in eff.iter("newparam"):
                    if np_.get("sid") == samp:
                        src = np_.find(".//source")
                        surf = src.text if src is not None else None
                        for np2 in eff.iter("newparam"):
                            if np2.get("sid") == surf:
                                f = np2.find(".//init_from")
                                img = f.text if f is not None else None
                if img is None:
                    img = samp
                info["texture"] = self.images.get(img, img)
        tr = eff.find(".//transparency/float")
        if tr is not None:
            a = float(tr.text)
            col = list(info["color"])
            col[3] = col[3] * a if len(col) == 4 else a
            info["color"] = tuple(col)
        return info

    def geometry(self, gid):
        """[(material_symbol, P (n*3,3), N (n*3,3) or None, UV (n*3,2) or None)] per <triangles>."""
        if gid in self._geo_cache:
            return self._geo_cache[gid]
        g = self.ids[gid]
        mesh = g.find("mesh")
        sources = {}
        for s in mesh.findall("source"):
            fa = s.find("float_array")
            if fa is None:
                continue
            acc = s.find("technique_common/accessor")
            stride = int(acc.get("stride", "1")) if acc is not None else 1
            sources[s.get("id")] = _floats(fa.text).reshape(-1, stride)
        verts = {}
        for v in mesh.findall("vertices"):
            verts[v.get("id")] = {i.get("semantic"): sources[i.get("source")[1:]] for i in v.findall("input")}
        out = []
        for tri in mesh.findall("triangles"):
            inputs = tri.findall("input")
            stride = max(int(i.get("offset")) for i in inputs) + 1
            p = tri.find("p")
            if p is None or not p.text:
                continue
            idx = np.array(p.text.split(), dtype=np.int64).reshape(-1, stride)
            P = N = UV = None
            for i in inputs:
                sem, off, src = i.get("semantic"), int(i.get("offset")), i.get("source")[1:]
                col = idx[:, off]
                if sem == "VERTEX":
                    vv = verts[src]
                    P = vv["POSITION"][col][:, :3]
                    if "NORMAL" in vv:
                        N = vv["NORMAL"][col][:, :3]
                elif sem == "NORMAL":
                    N = sources[src][col][:, :3]
                elif sem == "TEXCOORD" and UV is None:
                    UV = sources[src][col][:, :2]
            out.append((tri.get("material"), P, N, UV))
        self._geo_cache[gid] = out
        return out

    def visual_scene(self):
        inst = self.root.find("scene/instance_visual_scene")
        return self.ids[inst.get("url")[1:]]

    @staticmethod
    def _matrix(node):
        m = node.find("matrix")
        return _floats(m.text).reshape(4, 4) if m is not None else np.eye(4)

    def walk(self, node, M=None, path=(), visit=None):
        """Yield (path, world_matrix, geometry_id, {symbol: material_id}) for every geometry
        instance below `node`. `path` is a tuple of (id, name) of the nodes walked through."""
        if M is None:
            M = np.eye(4)
        M = M @ self._matrix(node)
        path = path + ((node.get("id"), node.get("name")),)
        for ig in node.findall("instance_geometry"):
            binds = {im.get("symbol"): im.get("target")[1:] for im in ig.iter("instance_material")}
            yield path, M, ig.get("url")[1:], binds
        for inn in node.findall("instance_node"):
            yield from self.walk(self.ids[inn.get("url")[1:]], M, path)
        for ch in node.findall("node"):
            yield from self.walk(ch, M, path)

    def triangles(self, node, M=None):
        """All triangles under node in Y-up metres: list of (material_id, P, N, UV)."""
        res = []
        base = self.to_y_up if M is None else self.to_y_up @ M
        for path, W, gid, binds in self.walk(node, None):
            T = base @ W
            R = T[:3, :3]
            nrm = np.linalg.inv(R).T
            det = np.linalg.det(R)
            for sym, P, N, UV in self.geometry(gid):
                mid = binds.get(sym, sym)
                Pw = P @ T[:3, :3].T + T[:3, 3]
                Nw = None
                if N is not None:
                    Nw = N @ nrm.T
                    ln = np.linalg.norm(Nw, axis=1, keepdims=True)
                    Nw = Nw / np.where(ln == 0, 1, ln)
                if det < 0:  # mirrored instance: flip winding
                    Pw = Pw.reshape(-1, 3, 3)[:, ::-1].reshape(-1, 3)
                    Nw = None if Nw is None else Nw.reshape(-1, 3, 3)[:, ::-1].reshape(-1, 3)
                    UV = None if UV is None else UV.reshape(-1, 3, 2)[:, ::-1].reshape(-1, 2)
                res.append((mid, Pw, Nw, UV))
        return res
