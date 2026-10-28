"""Clean the golf bag source models (a cart bag photo scan, generated tour and stand bags, and a
generated bag full of clubs the golfers carry) into game props.

Stage "bake" (Blender): joins each source, strips the scanned ground patch, stands the bag
upright with its pockets facing -Y, rebuilds the scan's broken mouth (cuff, divider top and
grab handle), smooths the scan noise, decimates it to a game mesh with fresh UVs and bakes the
source colour and the high-poly surface detail onto it.
    blender -b --factory-startup --python tools/blender/clean_bags.py -- bake cart=<scan.glb> tour=<tour.glb> stand=<stand.obj> carry=<carry.obj>
(BAGS=stand,carry bakes only those.)

Stage "export" (Blender): writes one .glb per livery from the baked mesh and the livery
textures that tools/blender/bag_liveries.py paints.
    blender -b --factory-startup --python tools/blender/clean_bags.py -- export

The work files live in tools/blender/_bag_work (ignored); the props go to
assets/facilities/props/bags/golf_bag_<model>_<livery>.glb.
"""
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
WORK = os.path.join(ROOT, "tools", "blender", "_bag_work")
OUT = os.path.join(ROOT, "assets", "facilities", "props", "bags")
TEX = 1024

# per source model: how to turn it so the pockets face -Y, its real height, the ground patch
# the scan stands on ("plate": the display plate a generated model comes on), and how many
# triangles the game mesh keeps
MODELS = [
    {"id": "cart", "rz": 0.0, "height": 0.9, "ground": "floor", "tris": 5000, "uv_smooth": 40, "sharp": None, "smooth": (0.7, 40),
     "mouth": 0.95, "handle": (-5.0, 135.0)},
    {"id": "tour", "rz": -math.pi / 2, "height": 0.95, "ground": None, "tris": 9000, "uv_smooth": 40, "sharp": None, "smooth": (0.35, 3)},
    {"id": "stand", "rz": math.pi / 2, "height": 0.9, "ground": "plate", "tris": 9000, "uv_smooth": 40, "sharp": None, "smooth": (0.3, 2)},
    # the golfers' own bag, clubs and all (1.2 m to the top of the driver)
    {"id": "carry", "rz": math.pi / 2, "height": 1.2, "ground": None, "tris": 16000, "uv_smooth": 40, "sharp": None, "smooth": (0.2, 2)},
]


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def source_image(mat):
    """The colour image a source material shows (base colour, or emission for the scans)."""
    for n in mat.node_tree.nodes:
        if n.type != "TEX_IMAGE" or not n.image:
            continue
        for o in n.outputs:
            for l in o.links:
                if l.to_socket.name in ("Base Color", "Color") and l.to_node.type in ("BSDF_PRINCIPLED", "EMISSION"):
                    return n.image
    return None


def import_joined(path):
    if path.lower().endswith(".obj"):
        bpy.ops.wm.obj_import(filepath=path)
    else:
        bpy.ops.import_scene.gltf(filepath=path)
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    for o in meshes:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
    for o in [o for o in bpy.data.objects if o.type != "MESH"]:
        bpy.data.objects.remove(o)
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    ob.name = "high"
    return ob


def image_array(img, size=2048):
    im = img.copy()
    im.scale(size, size)
    a = np.empty(size * size * 4, np.float32)
    im.pixels.foreach_get(a)
    bpy.data.images.remove(im)
    return a.reshape(size, size, 4)


def is_ground(rgb, kind):
    r, g, b = rgb
    mx, mn = max(rgb), min(rgb)
    if kind == "grass":
        return g > r * 1.08 and g > b * 1.15 and mx - mn > 0.05
    if kind == "floor":
        return mn > 0.38 and mx - mn < 0.1
    return False


def weld(ob):
    """The importer splits vertices along the source's UV seams; weld them so the bag is one
    surface again (the UVs live on the face corners, so they survive)."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.to_mesh(ob.data)
    bm.free()


def strip_plate(ob):
    """Cut away the display plate a generated model stands on: a slab a few centimetres thick
    fused to the bag's bottom. Its top is the height most of the low up-facing faces share;
    everything under it goes (the stand's feet lose the same few centimetres, so the bag and
    its feet still meet the floor together)."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    zs = [v.co.z for v in bm.verts]
    z0, z1 = min(zs), max(zs)
    H = z1 - z0
    hist = {}
    for f in bm.faces:
        c = f.calc_center_median()
        if f.normal.z > 0.9 and z0 + 0.01 * H < c.z < z0 + 0.09 * H:
            k = round((c.z - z0) / 0.002)
            hist[k] = hist.get(k, 0.0) + f.calc_area()
    if not hist:
        bm.free()
        return
    top = z0 + max(hist, key=hist.get) * 0.002 + 0.004
    geom = list(bm.verts) + list(bm.edges) + list(bm.faces)
    bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, 0, top), plane_no=(0, 0, 1), clear_inner=True)
    bm.to_mesh(ob.data)
    bm.free()
    print("  cut the display plate off below %.3f m (of %.3f)" % (top - z0, H))


def strip_ground(ob, kind):
    """Delete the scanned ground patch: low faces whose colour is grass / floor, then any loose
    scraps left over."""
    if not kind:
        return
    if kind == "plate":
        strip_plate(ob)  # then just the scraps below
    else:
        px = image_array(source_image(ob.data.materials[0]))
        n = px.shape[0]
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    uv = bm.loops.layers.uv.active
    zs = [v.co.z for v in bm.verts]
    z0, z1 = min(zs), max(zs)
    cut = z0 + (z1 - z0) * 0.14
    kill = []
    for f in bm.faces if kind != "plate" else ():
        c = f.calc_center_median()
        if c.z > cut:
            continue
        u = sum(l[uv].uv.x for l in f.loops) / len(f.loops)
        v = sum(l[uv].uv.y for l in f.loops) / len(f.loops)
        p = px[min(max(int(v * n), 0), n - 1), min(max(int(u * n), 0), n - 1)]
        # the patch is flat and wide: an up-facing face low down, or a ground-coloured one
        light = p[0] * 0.2126 + p[1] * 0.7152 + p[2] * 0.0722 > 0.4
        if is_ground(tuple(p[:3]), kind) or (f.normal.z > 0.9 and c.z < z0 + (z1 - z0) * 0.06)                 or (light and c.z < z0 + (z1 - z0) * 0.035):  # floor / grass caught round the feet
            kill.append(f)
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    # drop loose scraps (anything under 2% of the faces)
    faces = set(bm.faces)
    islands = []
    while faces:
        seed = faces.pop()
        isle, stack = [seed], [seed]
        while stack:
            f = stack.pop()
            for e in f.edges:
                for g in e.link_faces:
                    if g in faces:
                        faces.remove(g)
                        isle.append(g)
                        stack.append(g)
        islands.append(isle)
    total = sum(len(i) for i in islands)
    scraps = [f for i in islands if len(i) < total * 0.02 for f in i]
    bmesh.ops.delete(bm, geom=scraps, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(ob.data)
    bm.free()
    print("  stripped", len(kill), "ground faces,", len(scraps), "scrap faces")


def stand_up(ob, model):
    """Turn the pockets to -Y, scale to the real height, base on z = 0, centred."""
    ob.data.transform(Matrix.Rotation(model["rz"], 4, "Z"))
    vs = np.array([v.co[:] for v in ob.data.vertices])
    lo, hi = vs.min(0), vs.max(0)
    s = model["height"] / (hi[2] - lo[2])
    # centre on the trunk (the middle band of the bag), not the pockets sticking out
    mid = vs[(vs[:, 2] > lo[2] + (hi[2] - lo[2]) * 0.3) & (vs[:, 2] < lo[2] + (hi[2] - lo[2]) * 0.7)]
    cx, cy = (mid[:, 0].min() + mid[:, 0].max()) * 0.5, (mid[:, 1].min() + mid[:, 1].max()) * 0.5
    ob.data.transform(Matrix.Scale(s, 4) @ Matrix.Translation((-cx, -cy, -lo[2])))
    ob.data.update()


def smooth(ob, factor, reps, group=""):
    m = ob.modifiers.new("smooth", "SMOOTH")
    m.factor = factor
    m.iterations = reps
    m.vertex_group = group
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.modifier_apply(modifier=m.name)


def unwrap_first(ob):
    """Unwrap a clean high-poly surface before decimating (the collapse keeps the UV seams)."""
    while ob.data.uv_layers:
        ob.data.uv_layers.remove(ob.data.uv_layers[0])
    ob.data.uv_layers.new(name="UVMap")
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.004, area_weight=0.8)
    bpy.ops.uv.pack_islands(margin=0.003, rotate=True)
    bpy.ops.object.mode_set(mode="OBJECT")


def make_low(high, tris, uv_smooth=40, sharp=None, uv_first=False, extra=None):
    low = high.copy()
    low.data = high.data.copy()
    low.name = "low"
    bpy.context.collection.objects.link(low)
    if uv_first:
        # the high mesh carries the source UVs the colour bake reads; unwrap the copy instead
        unwrap_first(low)
    cur = sum(len(p.vertices) - 2 for p in low.data.polygons)
    m = low.modifiers.new("dec", "DECIMATE")
    m.ratio = min(tris / max(cur, 1), 1.0)
    bpy.ops.object.select_all(action="DESELECT")
    low.select_set(True)
    bpy.context.view_layer.objects.active = low
    bpy.ops.object.modifier_apply(modifier=m.name)
    smooth(low, 0.5, 2)
    if sharp:
        # the generated bag has crisp panel edges: keep them hard instead of baking them in
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(sharp))
    else:
        for p in low.data.polygons:
            p.use_smooth = True
    if uv_first:
        low.data.materials.clear()
        return low
    # the unwrap smooths a twin of the scan only: the modelled parts (no vertex group) keep
    # their shape, so a thin handle doesn't collapse to nothing in UV space
    low.vertex_groups.new(name="scan").add(range(len(low.data.vertices)), 1.0, "REPLACE")
    if extra is not None:
        join_into(low, extra)
        for p in low.data.polygons:
            p.use_smooth = True
    while low.data.uv_layers:
        low.data.uv_layers.remove(low.data.uv_layers[0])
    low.data.uv_layers.new(name="UVMap")
    # unwrap a heavily smoothed twin (same topology) so the scan noise doesn't shatter the
    # islands, then copy its UVs back
    twin = low.copy()
    twin.data = low.data.copy()
    bpy.context.collection.objects.link(twin)
    bpy.ops.object.select_all(action="DESELECT")
    twin.select_set(True)
    bpy.context.view_layer.objects.active = twin
    smooth(twin, 1.0, uv_smooth, "scan")
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(72), island_margin=0.004, area_weight=0.8)
    bpy.ops.uv.pack_islands(margin=0.003, rotate=True)
    bpy.ops.object.mode_set(mode="OBJECT")
    uvs = np.empty(len(twin.data.loops) * 2, np.float32)
    twin.data.uv_layers[0].data.foreach_get("uv", uvs)
    low.data.uv_layers[0].data.foreach_set("uv", uvs)
    bpy.data.objects.remove(twin)
    bpy.ops.object.select_all(action="DESELECT")
    low.select_set(True)
    bpy.context.view_layer.objects.active = low
    low.data.materials.clear()
    return low


def bake_target(low, name, non_color):
    img = bpy.data.images.new(name, TEX, TEX, alpha=False)
    if non_color:
        img.colorspace_settings.name = "Non-Color"
    mat = bpy.data.materials.new("bake_" + name)
    mat.use_nodes = True
    node = mat.node_tree.nodes.new("ShaderNodeTexImage")
    node.image = img
    mat.node_tree.nodes.active = node
    low.data.materials.clear()
    low.data.materials.append(mat)
    return img


def bake(high, low, kind, img_name, non_color=False):
    img = bake_target(low, img_name, non_color)
    sc = bpy.context.scene
    bpy.ops.object.select_all(action="DESELECT")
    high.select_set(True)
    low.select_set(True)
    bpy.context.view_layer.objects.active = low
    if kind == "NORMAL":
        bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT", use_selected_to_active=True,
                            cage_extrusion=0.015, max_ray_distance=0.04, margin=8)
    else:
        bpy.ops.object.bake(type="EMIT", use_selected_to_active=True,
                            cage_extrusion=0.015, max_ray_distance=0.04, margin=8)
    img.filepath_raw = os.path.join(WORK, img_name + ".png")
    img.file_format = "PNG"
    img.save()
    return img


def as_emission(ob):
    """Swap each source material for a flat emission of its colour image (for the colour bake);
    the flat-colour materials the new mouth uses are emissions already."""
    for i, mat in enumerate(ob.data.materials):
        img = source_image(mat)
        if img is None:
            continue
        em = bpy.data.materials.new(mat.name + "_emit")
        em.use_nodes = True
        nt = em.node_tree
        nt.nodes.clear()
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = img
        e = nt.nodes.new("ShaderNodeEmission")
        o = nt.nodes.new("ShaderNodeOutputMaterial")
        nt.links.new(t.outputs["Color"], e.inputs["Color"])
        nt.links.new(e.outputs["Emission"], o.inputs["Surface"])
        ob.data.materials[i] = em


def flat_material(name, srgb):
    """An emission of one grey level, so the livery gradient map colours it like the fabric of
    that shade (srgb: the brightness it bakes to)."""
    lin = srgb / 12.92 if srgb <= 0.04045 else ((srgb + 0.055) / 1.055) ** 2.4
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    e = nt.nodes.new("ShaderNodeEmission")
    e.inputs["Color"].default_value = (lin, lin, lin, 1.0)
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(e.outputs["Emission"], o.inputs["Surface"])
    return m


def _hull(pts):
    pts = sorted(set(pts))
    if len(pts) < 3:
        return pts

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def _resample(poly, n):
    """`n` points evenly spaced round a closed polygon, then eased a little rounder."""
    segs = [(Vector(poly[i]), Vector(poly[(i + 1) % len(poly)])) for i in range(len(poly))]
    total = sum((b - a).length for a, b in segs)
    out = []
    for k in range(n):
        t = total * k / n
        for a, b in segs:
            ln = (b - a).length
            if t <= ln or (a, b) == segs[-1]:
                out.append(a.lerp(b, min(t / max(ln, 1e-9), 1.0)))
                break
            t -= ln
    for _ in range(3):
        out = [(out[i - 1] + out[i] * 2 + out[(i + 1) % n]) * 0.25 for i in range(n)]
    return out


def _handle(bm, ring, c, z0, a0, a1, mat, rise=0.05, width=0.034, thick=0.016, steps=24):
    """A padded strap from angle a0 to a1 round the cuff ring, arching `rise` above z0 at its
    middle, its ends sunk into the cuff."""
    if a1 < a0:
        a0, a1 = a1, a0

    def rim(ang, inset=0.97):
        d = Vector((math.cos(ang), math.sin(ang)))
        far = max(ring, key=lambda p: (p - c).dot(d))
        return c + d * (far - c).dot(d) * inset

    rings = []
    for k in range(steps + 1):
        t = k / steps
        p = rim(a0 + (a1 - a0) * t)
        z = z0 + rise * math.sin(math.pi * t) - (0.02 if k in (0, steps) else 0.0)
        tan = (rim(a0 + (a1 - a0) * min(t + 0.01, 1.0)) - rim(a0 + (a1 - a0) * max(t - 0.01, 0.0))).normalized()
        out = Vector((tan.y, -tan.x))  # across the strap, level
        if out.dot(p - c) < 0:
            out = -out
        # a rounded-rectangle section: wide and flat, like a padded grab handle
        sec = []
        for j in range(8):
            ang = j / 8 * math.tau
            sx, sz = math.cos(ang), math.sin(ang)
            sx = math.copysign(abs(sx) ** 0.6, sx) * width * 0.5
            sz = math.copysign(abs(sz) ** 0.6, sz) * thick * 0.5
            sec.append(bm.verts.new((p.x + out.x * sx, p.y + out.y * sx, z + sz)))
        rings.append(sec)
    for k in range(steps):
        for j in range(8):
            f = bm.faces.new((rings[k][j], rings[k][(j + 1) % 8], rings[k + 1][(j + 1) % 8], rings[k + 1][j]))
            f.material_index = mat
    for sec in (rings[0], rings[-1]):
        f = bm.faces.new(sec)
        f.material_index = mat


def rebuild_mouth(ob, frac, handle=None):
    """The scan's mouth (cuff and divider top) is ragged and part of the rim never got
    scanned: cut it off at `frac` of the height and build a padded cuff with piping and a
    divider top over the cut, in flat shades the livery maps like the fabric. `handle`: the
    angles (degrees round the cuff, from +X) where the scan caught the grab handle's two ends;
    its padded strap arches between them along the rim (the scan missed the strap itself).
    Returns the new parts as their own object, so the decimation that simplifies the scan
    leaves them whole."""
    scan = bmesh.new()
    scan.from_mesh(ob.data)
    H = max(v.co.z for v in scan.verts)
    zc = H * frac
    geom = list(scan.verts) + list(scan.edges) + list(scan.faces)
    bmesh.ops.bisect_plane(scan, geom=geom, plane_co=(0, 0, zc), plane_no=(0, 0, 1), clear_outer=True)
    ring = _resample(_hull([(round(v.co.x, 4), round(v.co.y, 4)) for v in scan.verts if v.co.z > zc - 0.03]), 72)
    scan.to_mesh(ob.data)
    scan.free()
    ob.data.update()
    c = sum(ring, Vector((0, 0))) / len(ring)
    me = bpy.data.meshes.new("mouth")
    for name, shade in (("mouth_cuff", 0.12), ("mouth_piping", 0.62), ("mouth_top", 0.05), ("mouth_rib", 0.15)):
        me.materials.append(flat_material(name, shade))
    cuff, piping, top, rib = 0, 1, 2, 3
    bm = bmesh.new()

    def loop(scale, z):
        return [bm.verts.new((c.x + (p.x - c.x) * scale, c.y + (p.y - c.y) * scale, z)) for p in ring]

    # the cuff's profile, outside in: (scale, height above the cut, material of the band above)
    prof = [(0.995, -0.03, cuff), (1.03, 0.0, cuff), (1.045, 0.025, cuff), (1.03, 0.045, piping),
            (0.985, 0.058, piping), (0.93, 0.06, cuff), (0.89, 0.05, cuff), (0.875, 0.035, top)]
    loops = [loop(sc, zc + dz) for sc, dz, _ in prof]
    n = len(ring)
    for k in range(len(loops) - 1):
        for i in range(n):
            f = bm.faces.new((loops[k][i], loops[k][(i + 1) % n], loops[k + 1][(i + 1) % n], loops[k + 1][i]))
            f.material_index = prof[k][2]
    # the divider top: a dished panel with an inner ring and a cross of padded ribs
    centre = bm.verts.new((c.x, c.y, zc + 0.03))
    for i in range(n):
        f = bm.faces.new((loops[-1][i], loops[-1][(i + 1) % n], centre))
        f.material_index = top
    zr = zc + 0.032

    def rib_box(p0, p1, w=0.016, h=0.03):
        d = (p1 - p0)
        ln = d.length
        if ln < 0.01:
            return
        ang = math.atan2(d.y, d.x)
        res = bmesh.ops.create_cube(bm, size=1.0)
        vs = res["verts"]
        m = Matrix.Translation(((p0.x + p1.x) * 0.5, (p0.y + p1.y) * 0.5, zr + h * 0.5)) @ Matrix.Rotation(ang, 4, "Z") @ Matrix.Diagonal((ln, w, h, 1.0))
        bmesh.ops.transform(bm, matrix=m, verts=vs)
        for f in {f for v in vs for f in v.link_faces}:
            f.material_index = rib
    if handle:
        _handle(bm, ring, c, zc + 0.05, math.radians(handle[0]), math.radians(handle[1]), cuff)
    inner = [c + (p - c) * 0.48 for p in ring]
    for i in range(0, n, 3):
        rib_box(inner[i], inner[(i + 3) % n], 0.014)
    # the cross: from the inner ring out to the cuff along the bag's two axes
    for ang in (0.0, math.pi * 0.5, math.pi, math.pi * 1.5):
        d = Vector((math.cos(ang), math.sin(ang)))
        far = max(ring, key=lambda p: (p - c).dot(d))
        reach = (far - c).dot(d)
        rib_box(c + d * reach * 0.48, c + d * reach * 0.86)
    bm.to_mesh(me)
    bm.free()
    mouth = bpy.data.objects.new("mouth", me)
    bpy.context.collection.objects.link(mouth)
    return mouth


def join_into(target, other):
    """Join a copy of `other` into `target` (materials and all)."""
    dup = other.copy()
    dup.data = other.data.copy()
    bpy.context.collection.objects.link(dup)
    bpy.ops.object.select_all(action="DESELECT")
    dup.select_set(True)
    target.select_set(True)
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.join()


def stage_bake(srcs, only=None):
    """srcs: {model id: source .glb path}."""
    os.makedirs(WORK, exist_ok=True)
    for model in MODELS:
        src = srcs.get(model["id"])
        if not src or (only and model["id"] not in only):
            continue
        print("BAG", model["id"], src)
        reset()
        sc = bpy.context.scene
        sc.render.engine = "CYCLES"
        sc.cycles.device = "CPU"
        sc.cycles.samples = 8
        high = import_joined(src)
        weld(high)
        strip_ground(high, model["ground"])
        stand_up(high, model)
        mouth = rebuild_mouth(high, model["mouth"], model.get("handle")) if model.get("mouth") else None
        # the scans are lumpy at the centimetre scale: iron that out of the surface the normal
        # map is baked from (the generated bag is clean already)
        smooth(high, *model["smooth"])
        low = make_low(high, model["tris"], model["uv_smooth"], model["sharp"], model.get("uv_first", False), mouth)
        if mouth is not None:
            join_into(high, mouth)
            bpy.data.objects.remove(mouth)
        # surface detail from the geometry only: the generated model's own normal map carries
        # its fake lettering, which the retexture drops
        as_emission(high)
        bake(high, low, "NORMAL", model["id"] + "_normal", True)
        bake(high, low, "EMIT", model["id"] + "_color")
        # keep only the game mesh in the work file
        bpy.data.objects.remove(high)
        low.data.materials.clear()
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(WORK, model["id"] + ".blend"))
        print("  low tris", sum(len(p.vertices) - 2 for p in low.data.polygons))


def livery_names(mid):
    return sorted(f[len(mid) + 1:-4] for f in os.listdir(WORK) if f.startswith(mid + "_") and f.endswith(".jpg")
                  and not f.endswith("_rough.jpg"))


def stage_export():
    os.makedirs(OUT, exist_ok=True)
    for model in MODELS:
        mid = model["id"]
        for liv in livery_names(mid):
            bpy.ops.wm.open_mainfile(filepath=os.path.join(WORK, mid + ".blend"))
            low = bpy.data.objects["low"]
            low.name = "golf_bag"
            low.data.name = "golf_bag_" + mid
            mat = bpy.data.materials.new("bag_%s_%s" % (mid, liv))
            mat.use_nodes = True
            nt = mat.node_tree
            bsdf = nt.nodes["Principled BSDF"]
            col = nt.nodes.new("ShaderNodeTexImage")
            col.image = bpy.data.images.load(os.path.join(WORK, "%s_%s.jpg" % (mid, liv)))
            nt.links.new(col.outputs["Color"], bsdf.inputs["Base Color"])
            rough = nt.nodes.new("ShaderNodeTexImage")
            rough.image = bpy.data.images.load(os.path.join(WORK, mid + "_rough.jpg"))
            rough.image.colorspace_settings.name = "Non-Color"
            sep = nt.nodes.new("ShaderNodeSeparateColor")
            nt.links.new(rough.outputs["Color"], sep.inputs["Color"])
            nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
            bsdf.inputs["Metallic"].default_value = 0.0
            nrm = nt.nodes.new("ShaderNodeTexImage")
            nrm.image = bpy.data.images.load(os.path.join(WORK, mid + "_normal.png"))
            nrm.image.colorspace_settings.name = "Non-Color"
            nm = nt.nodes.new("ShaderNodeNormalMap")
            nm.inputs["Strength"].default_value = 0.7
            nt.links.new(nrm.outputs["Color"], nm.inputs["Color"])
            nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
            low.data.materials.append(mat)
            path = os.path.join(OUT, "golf_bag_%s_%s.glb" % (mid, liv))
            bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_tangents=True,
                                      export_image_format="AUTO", use_selection=False)
            print("EXPORTED", path)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if args and args[0] == "bake":
        only = os.environ.get("BAGS", "").split(",") if os.environ.get("BAGS") else None
        stage_bake(dict(a.split("=", 1) for a in args[1:]), only)
    elif args and args[0] == "export":
        stage_export()
    else:
        raise SystemExit("usage: -- bake <src...> | -- export")
