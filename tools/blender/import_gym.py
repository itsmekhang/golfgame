"""The gym's equipment, from the user's models: gym_equipment.glb (a SketchUp set in decimetres:
treadmill, elliptical, spin bike, cable station, plate tree, preacher bench, three bench-press
racks; its loose dumbbell is left out) and, from gym.blend, only the kettlebell, the yoga ball and the yoga mat
(the user's pick; the mat's texture is missing, so it takes a flat colour).

    blender -b --factory-startup --disable-autoexec -P tools/blender/import_gym.py -- <gym_equipment.glb> <gym.blend> [--preview <dir>]

Each piece is joined into one mesh, scaled to metres, turned so its front (where you face it
from: the console end of a treadmill, the bench's open side) faces +Y here (-Z in Godot), stood
on z = 0 centred on its footprint, lightened (its flat areas merged: every curve kept) and written to
assets/facilities/props/gym/gym_<id>.glb. The room places them with GYM_<id> markers
(fm_lib.gym_piece).
"""
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "assets", "facilities", "props", "gym")
# id: (source, piece, size (glb: scale; blend: its longest side in m), rz, triangles). The front
# (+Y) is the way its user faces: a treadmill's console, a bench's foot (its rack behind). Past
# `triangles` a piece is collapsed further -- None for anything with weight plates, wheels or
# flywheels, which a collapse knocks out of round.
PIECES = {
    "treadmill": ("glb", "Component_35_1", 0.09, 0.0, 9000),
    "plate_tree": ("glb", "Component_37_1", 0.1, 0.0, None),
    "elliptical": ("glb", "Component_3_1", 0.09, 0.0, 7000),
    "cable_station": ("glb", "Component_42_1", 0.1, math.pi, 12000),
    "preacher_curl": ("glb", "Group1", 0.1, math.pi, None),
    "spin_bike": ("glb", "Group157", 0.09, 0.0, None),
    "bench_incline": ("glb", "Group2", 0.1, math.pi, None),
    "bench_flat": ("glb", "Group52", 0.1, math.pi, None),
    "bench_adjustable": ("glb", "Group94", 0.1, math.pi, None),
    "gym_ball": ("blend", "ball.001", 0.65, 0.0, 1000),
    "mat": ("blend", "pad", 1.85, 0.0, 300),
    "kettlebell": ("blend", "weight", 0.3, 0.0, 1200),
}
# a missing texture's flat colour, by piece (sRGB hex)
MISSING = {"mat": "2f4f6f"}
# Pieces whose weight plates are rebuilt round (the source draws every circle with 24 sides),
# and how many sides the new ones get.
PLATED = {"plate_tree", "bench_incline", "bench_flat", "bench_adjustable", "preacher_curl"}
PLATE_SEGS = 64


def linear(hexs):
    rgb = [int(hexs[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in rgb]


def open_source(kind, path):
    if kind == "blend":
        bpy.ops.wm.open_mainfile(filepath=path, load_ui=False)
    else:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=path)

    def unhide(lc):
        lc.exclude = False
        lc.hide_viewport = False
        for c in lc.children:
            unhide(c)
    unhide(bpy.context.view_layer.layer_collection)
    for col in bpy.data.collections:
        col.hide_render = False
        col.hide_viewport = False
    for o in bpy.context.scene.objects:
        o.hide_viewport = False
        o.hide_render = False
        o.hide_set(False)
    bpy.context.view_layer.update()


def piece_object(name, pid):
    """The piece's meshes joined into one object with its transforms applied, the rest gone."""
    top = next(o for o in bpy.context.scene.objects if o.name == name)
    parts = [o for o in [top] + list(top.children_recursive) if o.type == "MESH"]
    keep = []
    for o in parts:
        c = o.copy()
        c.data = o.data.copy()
        c.parent = None
        c.matrix_world = o.matrix_world.copy()
        bpy.context.scene.collection.objects.link(c)
        keep.append(c)
    for o in list(bpy.context.scene.objects):
        if o not in keep:
            bpy.data.objects.remove(o, do_unlink=True)
    for o in keep:
        o.select_set(True)
    bpy.context.view_layer.objects.active = keep[0]
    bpy.ops.object.make_single_user(object=True, obdata=True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if len(keep) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = "gym_" + pid
    ob.data.name = "gym_" + pid
    return ob


def fix_materials(ob, pid):
    """A material whose image is missing shows a flat colour instead of magenta."""
    for slot in ob.material_slots:
        m = slot.material
        if m is None or not m.use_nodes:
            continue
        nt = m.node_tree
        for n in list(nt.nodes):
            if n.type == "TEX_IMAGE" and (n.image is None or not n.image.has_data):
                for link in list(n.outputs["Color"].links):
                    sock = link.to_socket
                    nt.links.remove(link)
                    if sock.name in ("Base Color", "Color") and hasattr(sock, "default_value"):
                        sock.default_value = (*linear(MISSING.get(pid, "3a3d40")), 1.0)
                nt.nodes.remove(n)
        flatten(m, pid)


def flatten(m, pid):
    """glTF only carries a Principled BSDF: a material shaded any other way (the mat's diffuse,
    the ball's procedural gloss) becomes a plain Principled one in the colour it shows (its RGB
    node's, else its diffuse colour, else the piece's MISSING colour)."""
    nt = m.node_tree
    out = next((n for n in nt.nodes if n.type == "OUTPUT_MATERIAL" and n.is_active_output), None) or \
        next((n for n in nt.nodes if n.type == "OUTPUT_MATERIAL"), None)
    surf = out.inputs["Surface"].links if out is not None else []
    if surf and surf[0].from_node.type == "BSDF_PRINCIPLED":
        return
    col = None
    rgb = next((n for n in nt.nodes if n.type == "RGB"), None)
    if rgb is not None:
        col = tuple(rgb.outputs[0].default_value)
    else:
        dif = next((n for n in nt.nodes if n.type == "BSDF_DIFFUSE"), None)
        if dif is not None and not dif.inputs["Color"].is_linked and pid not in MISSING:
            col = tuple(dif.inputs["Color"].default_value)
    if col is None:
        col = (*linear(MISSING.get(pid, "3a3d40")), 1.0)
    glossy = any(n.type in ("BSDF_GLOSSY", "BSDF_REFRACTION") for n in nt.nodes)
    nt.nodes.clear()
    p = nt.nodes.new("ShaderNodeBsdfPrincipled")
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(p.outputs["BSDF"], o.inputs["Surface"])
    p.inputs["Base Color"].default_value = col
    p.inputs["Roughness"].default_value = 0.3 if glossy else 0.85
    p.inputs["Metallic"].default_value = 0.0
    m.diffuse_color = col


def unpainted(mats, i):
    """SketchUp's stand-in for a face nobody painted (its front / back default, white)."""
    m = mats[i] if i < len(mats) else None
    return m is not None and m.name.split(".")[0] in ("FrontColor", "BackColor")


def round_plates(ob):
    """Rebuild every weight plate -- a loose part shaped like a disc with a hole: two equal wide
    extents, a thin one, its rim the same distance out all the way round -- as a true round
    plate (PLATE_SEGS sides) in its own place, size, hole and colour: a raised hub, flat
    faces, a lip and a softened rim. The lettering (separate parts) stays on it. The new plates
    come back as an object of their own (joined on after the rest is lightened, which would
    merge their clean face rings into slivers), with how many there were."""
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0002)  # its triangles come loose: weld them (only exact touches: not the plate to its bar)
    seen = set()
    islands = []
    for v in bm.verts:
        if v in seen:
            continue
        seen.add(v)
        stack, comp = [v], []
        while stack:
            x = stack.pop()
            comp.append(x)
            for e in x.link_edges:
                o = e.other_vert(x)
                if o not in seen:
                    seen.add(o)
                    stack.append(o)
        islands.append(comp)
    plates = []
    for comp in islands:
        if len(comp) < 24:
            continue
        P = np.array([tuple(v.co) for v in comp])
        mean = P.mean(axis=0)
        w, V = np.linalg.eigh(np.cov((P - mean).T))
        axis, u, t = V[:, 0], V[:, 2], V[:, 1]
        along = (P - mean) @ axis
        pu, pt = (P - mean) @ u, (P - mean) @ t
        c = mean + axis * (along.max() + along.min()) * 0.5 + u * (pu.max() + pu.min()) * 0.5 + t * (pt.max() + pt.min()) * 0.5
        q = P - c
        a = q @ axis
        rad = np.linalg.norm(q - np.outer(a, axis), axis=1)
        R, thick = rad.max(), a.max() - a.min()
        if not (0.06 < R < 0.35) or thick > R * 1.5 or w[0] > w[1] * 0.2:
            continue  # a stack of plates welded into one part can be up to ~5 thick
        ang = np.arctan2(q @ t, q @ u)
        bins = ((ang + math.pi) / (2 * math.pi) * 24).astype(int) % 24
        outer = [rad[bins == k].max() if np.any(bins == k) else 0.0 for k in range(24)]
        if min(outer) < R * 0.94:
            continue  # not round: a box, a bracket, a cut-off shape
        # its colour: the painted material covering most of it (by area: its hub's many small
        # faces can outnumber the body's), never SketchUp's unpainted white if anything else
        area = {}
        for f in {f for v in comp for f in v.link_faces}:
            area[f.material_index] = area.get(f.material_index, 0.0) + f.calc_area()
        painted = {mi: s for mi, s in area.items() if not unpainted(me.materials, mi)}
        pool = painted or area
        mat = max(pool, key=pool.get) if pool else 0
        plates.append((comp, Vector(c), Vector(axis), Vector(u), Vector(t), R, rad.min(), thick, mat))
    pb = bmesh.new()
    for comp, c, axis, u, t, R, hole, thick, mat in plates:
        bmesh.ops.delete(bm, geom=comp, context="VERTS")
        # a plate is about 0.3 R thick: a thicker part is a stack, rebuilt as that many plates
        count = max(1, round(thick / (R * 0.3)))
        h = thick / count * 0.5 - (0.00075 if count > 1 else 0.0)
        hole = max(hole, 0.012)
        span = R - hole
        hub, lip = min(0.03, span * 0.15), min(0.025, span * 0.12)
        rc, bv = min(0.004, h * 0.25), min(0.006, h * 0.4)
        prof = [(hole, h), (hole + hub, h), (hole + hub, h - rc), (R - lip, h - rc), (R - lip, h), (R - bv, h), (R, h - bv),
                (R, -h + bv), (R - bv, -h), (R - lip, -h), (R - lip, -h + rc), (hole + hub, -h + rc), (hole + hub, -h), (hole, -h)]
        n = len(prof)
        for s in range(count):
            mid = c + axis * ((s + 0.5) * thick / count - thick * 0.5)
            ring = []
            for k in range(PLATE_SEGS):
                th = k * math.tau / PLATE_SEGS
                d = u * math.cos(th) + t * math.sin(th)
                ring.append([pb.verts.new(mid + d * r + axis * z) for r, z in prof])
            new = []
            for k in range(PLATE_SEGS):
                a0, a1 = ring[k], ring[(k + 1) % PLATE_SEGS]
                for j in range(n):
                    f = pb.faces.new((a0[j], a1[j], a1[(j + 1) % n], a0[(j + 1) % n]))
                    f.material_index = mat
                    new.append(f)
            bmesh.ops.recalc_face_normals(pb, faces=new)
    bm.to_mesh(me)
    bm.free()
    me.update()
    pm = bpy.data.meshes.new(me.name + "_plates")
    pb.to_mesh(pm)
    pb.free()
    for m in me.materials:
        pm.materials.append(m)
    po = bpy.data.objects.new(ob.name + "_plates", pm)
    bpy.context.scene.collection.objects.link(po)
    return len(plates), po


def shape(ob, size, rz, glb):
    me = ob.data
    if glb:
        s = size
    else:
        lo = Vector([min(v.co[i] for v in me.vertices) for i in range(3)])
        hi = Vector([max(v.co[i] for v in me.vertices) for i in range(3)])
        s = size / max(hi - lo)
    me.transform(Matrix.Rotation(rz, 4, "Z") @ Matrix.Scale(s, 4))
    lo = Vector([min(v.co[i] for v in me.vertices) for i in range(3)])
    hi = Vector([max(v.co[i] for v in me.vertices) for i in range(3)])
    me.transform(Matrix.Translation((-(lo.x + hi.x) * 0.5, -(lo.y + hi.y) * 0.5, -lo.z)))
    me.update()


def tris(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def decimate(ob, target):
    """Merge the flat areas (coplanar triangles: the shape stays exactly as modelled); only past
    `target` (a piece with nothing round) collapse it further."""
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=0.002)  # its triangles come loose: weld them first (2 mm: far finer than a plate's rim)
    bpy.ops.mesh.dissolve_limited(angle_limit=math.radians(1.0), delimit={"MATERIAL", "UV"})
    bpy.ops.object.mode_set(mode="OBJECT")
    tri = ob.modifiers.new("tri", "TRIANGULATE")
    bpy.ops.object.modifier_apply(modifier=tri.name)
    for _pass in range(4):  # a collapse can stop short of its ratio: go again
        if target is None or tris(ob) <= target * 1.15:
            break
        d = ob.modifiers.new("dec", "DECIMATE")
        d.ratio = target / tris(ob)
        d.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=d.name)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(35))


def preview(ob, path):
    """Top and three-quarter views, a red arrow along +Y (the front)."""
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x, sc.render.resolution_y = 900, 450
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.62, 0.64, 0.68, 1)
    sc.world = w
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(50), 0, math.radians(30))
    sc.collection.objects.link(sun)
    dims = ob.dimensions
    size = max(dims)
    bpy.ops.mesh.primitive_cone_add(radius1=size * 0.06, depth=size * 0.15, location=(0, dims.y * 0.5 + size * 0.15, 0.02), rotation=(-math.pi / 2, 0, 0))
    arrow = bpy.context.active_object
    red = bpy.data.materials.new("arrow")
    red.diffuse_color = (1, 0, 0, 1)
    red.use_nodes = True
    red.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (1, 0, 0, 1)
    arrow.data.materials.append(red)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = size * 1.6
    c = Vector((0, 0, dims.z * 0.5))
    for tag, d in (("top", Vector((0, -0.001, 1))), ("34", Vector((0.7, 0.9, 0.6)))):
        d = d.normalized()
        cam.location = c + d * size * 4
        cam.data.clip_end = size * 20
        cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = path + "_" + tag + ".png"
        bpy.ops.render.render(write_still=True)


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    sources = {"glb": args[0], "blend": args[1]}
    prev = args[args.index("--preview") + 1] if "--preview" in args else ""
    only = args[args.index("--only") + 1].split(",") if "--only" in args else list(PIECES)
    os.makedirs(OUT, exist_ok=True)
    for pid in only:
        kind, name, size, rz, target = PIECES[pid]
        open_source(kind, sources[kind])
        ob = piece_object(name, pid)
        fix_materials(ob, pid)
        shape(ob, size, rz, kind == "glb")
        plates = None
        if pid in PLATED:
            count, plates = round_plates(ob)
            print("PLATES %s: %d rebuilt round" % (pid, count))
        decimate(ob, target)
        if plates is not None:
            bpy.ops.object.select_all(action="DESELECT")
            plates.select_set(True)
            ob.select_set(True)
            bpy.context.view_layer.objects.active = ob
            bpy.ops.object.join()
            bpy.ops.object.shade_smooth_by_angle(angle=math.radians(35))
        d = ob.dimensions
        print("GYM %-17s %5.2f x %5.2f x %5.2f m  %6d tris" % (pid, d.x, d.y, d.z, tris(ob)))
        bpy.ops.object.select_all(action="DESELECT")
        ob.select_set(True)
        bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "gym_%s.glb" % pid), export_format="GLB", use_selection=True,
                                  export_image_format="AUTO", export_apply=True)
        if prev:
            os.makedirs(prev, exist_ok=True)
            preview(ob, os.path.join(prev, pid))


main()
