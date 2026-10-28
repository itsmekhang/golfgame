"""Shared kit for the Course Manager building models (build_facilities.py): textured materials,
a geometry builder that box-maps UVs at real-world scale, shingle-style architecture parts,
landscaping and a furniture kit.

Conventions: metres; front = Blender +Y (Godot -Z after glTF's Y-up conversion); z up.
"""
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

TEX_DIR = ""  # set by build_facilities.py (absolute path to assets/facilities/textures)

# material -> (srgb hex tint, roughness, metallic, emission strength, alpha)
PALETTE = {
    "shingle": ("ffffff", 0.95, 0.0, 0, 1),
    "roof": ("ffffff", 0.9, 0.0, 0, 1),
    "brick": ("ffffff", 0.9, 0.0, 0, 1),
    "patio_brick": ("ffffff", 0.9, 0.0, 0, 1),
    "stone": ("ffffff", 0.9, 0.0, 0, 1),
    "wood_floor": ("ffffff", 0.55, 0.0, 0, 1),
    "deck": ("ffffff", 0.85, 0.0, 0, 1),
    "carpet": ("ffffff", 0.95, 0.0, 0, 1),
    "tile": ("ffffff", 0.3, 0.0, 0, 1),
    "gravel": ("ffffff", 0.95, 0.0, 0, 1),
    "grass": ("ffffff", 0.95, 0.0, 0, 1),
    "hedge": ("5f8a52", 0.95, 0.0, 0, 1),
    "asphalt": ("ffffff", 0.95, 0.0, 0, 1),
    "concrete": ("ffffff", 0.95, 0.0, 0, 1),
    "plaster": ("ffffff", 0.9, 0.0, 0, 1),
    "plaster_green": ("c9d8c4", 0.9, 0.0, 0, 1),
    "plaster_warm": ("f1dfc4", 0.9, 0.0, 0, 1),
    "trim": ("f7f6f1", 0.5, 0.0, 0, 1),
    "glass": ("26384a", 0.05, 0.6, 0, 1),
    "stone_grey": ("6f6a64", 0.85, 0.0, 0, 1),
    "entry_glass": ("b4d4d8", 0.16, 0.05, 0, 0.28),
    "door_white": ("f2f0ea", 0.5, 0.0, 0, 1),
    "door_wood": ("5a3a24", 0.5, 0.0, 0, 1),
    "brick_cap": ("6d6a65", 0.8, 0.0, 0, 1),
    "mulch": ("4a3223", 0.95, 0.0, 0, 1),
    "boxwood": ("2f5a29", 0.95, 0.0, 0, 1),
    "leaf": ("3d6e30", 0.9, 0.0, 0, 1),
    "flower_red": ("c8324a", 0.8, 0.0, 0, 1),
    "flower_white": ("f4f2ec", 0.8, 0.0, 0, 1),
    "flower_pink": ("e46a9f", 0.8, 0.0, 0, 1),
    "flower_purple": ("8a5bb8", 0.8, 0.0, 0, 1),
    "flower_yellow": ("efc94c", 0.8, 0.0, 0, 1),
    "wood": ("8f6a48", 0.7, 0.0, 0, 1),
    "wood_dark": ("4e3423", 0.6, 0.0, 0, 1),
    "bar_oak": ("352216", 0.42, 0.0, 0, 1),
    "wood_light": ("c49a6a", 0.6, 0.0, 0, 1),
    "fence": ("8a7660", 0.9, 0.0, 0, 1),
    "iron": ("1d2221", 0.5, 0.6, 0, 1),
    "steel": ("b3bcb9", 0.3, 0.8, 0, 1),
    "chrome": ("dfe4e6", 0.15, 1.0, 0, 1),
    "brass": ("c9a24e", 0.3, 0.9, 0, 1),
    "gold": ("e2b955", 0.25, 1.0, 0, 1),
    "white": ("f6f6f2", 0.5, 0.0, 0, 1),
    "porcelain": ("fbfbf9", 0.15, 0.0, 0, 1),
    "black": ("15181a", 0.6, 0.0, 0, 1),
    "charcoal": ("33383b", 0.7, 0.0, 0, 1),
    "grey": ("8c918f", 0.7, 0.0, 0, 1),
    "cloth_white": ("f5f3ee", 0.9, 0.0, 0, 1),
    "cloth_cream": ("eee3cb", 0.9, 0.0, 0, 1),
    "cloth_green": ("2d5a3d", 0.9, 0.0, 0, 1),
    "cloth_navy": ("27324d", 0.9, 0.0, 0, 1),
    "cloth_red": ("9d2f34", 0.9, 0.0, 0, 1),
    "cloth_tan": ("c3a77f", 0.9, 0.0, 0, 1),
    "cloth_sky": ("8ab7d8", 0.9, 0.0, 0, 1),
    "leather": ("5b3323", 0.55, 0.0, 0, 1),
    "leather_green": ("27402f", 0.55, 0.0, 0, 1),
    "screen": ("2f7fcf", 0.3, 0.0, 1.6, 1),
    "simulator_screen": ("ffffff", 0.55, 0.0, 2.2, 1),
    "range_display": ("ffffff", 0.35, 0.0, 1.4, 1),
    "screen_green": ("4bc37a", 0.3, 0.0, 1.4, 1),
    "tv": ("0e1215", 0.2, 0.2, 0.15, 1),
    "bulb": ("fff0c4", 0.5, 0.0, 4.0, 1),
    "fire": ("ff8a2a", 0.5, 0.0, 5.0, 1),
    "water": ("6fb6d6", 0.05, 0.1, 0.25, 1),
    "flag_red": ("b22234", 0.8, 0.0, 0, 1),
    "flag_blue": ("3c3b6e", 0.8, 0.0, 0, 1),
    "cart_green": ("27452f", 0.45, 0.2, 0, 1),
    "line": ("f2f2ee", 0.7, 0.0, 0, 1),
    "sign_blue": ("1f5fa8", 0.5, 0.0, 0, 1),
    "line_yellow": ("e8c33a", 0.7, 0.0, 0, 1),
    "cone": ("ff6a1f", 0.6, 0.0, 0, 1),
    "rubber": ("1a1b1c", 0.9, 0.0, 0, 1),
    "pallet": ("b08a5c", 0.9, 0.0, 0, 1),
    "electric": ("9aa3a2", 0.5, 0.6, 0, 1),
    "hose_green": ("2f7d32", 0.55, 0.0, 0, 1),  # (ClubLife's hose in the cart boy's hand: the same green)
    "mat_green": ("2f7a43", 0.95, 0.0, 0, 1),
    "basket_green": ("1e623f", 0.38, 0.0, 0, 1),
    "divider_mesh": ("263b30", 0.65, 0.25, 0, 1),
    "turf": ("5f9c46", 0.95, 0.0, 0, 1),
    "sign_green": ("244b36", 0.6, 0.0, 0, 1),
    "net": ("1d2722", 0.9, 0.0, 0, 0.35),
    "mirror": ("c9d3d8", 0.05, 1.0, 0, 1),
    "skin": ("e0b08f", 0.7, 0.0, 0, 1),
}
# material -> (texture base name, metres per tile, normal map strength or 0)
TEX = {
    "shingle": ("cedar_shingle", 1.2, 0.8),
    "roof": ("roof_shingle", 1.0, 0.9),
    "brick": ("brick", 0.9, 0.6),
    "patio_brick": ("patio_brick", 0.9, 0.5),
    "stone": ("stone_paving", 2.0, 0.5),
    "wood_floor": ("wood_floor", 2.4, 0.35),
    "deck": ("deck", 2.0, 0.5),
    "carpet": ("carpet", 1.2, 0.0),
    "tile": ("floor_tile", 1.2, 0.3),
    "gravel": ("gravel", 2.0, 0.4),
    "grass": ("grass", 3.0, 0.0),
    "hedge": ("grass", 1.0, 0.0),
    "asphalt": ("asphalt", 4.0, 0.0),
    "concrete": ("concrete", 3.0, 0.0),
    "plaster": ("plaster", 2.0, 0.0),
    "plaster_green": ("plaster", 2.0, 0.0),
    "plaster_warm": ("plaster", 2.0, 0.0),
}


def _lin(h):
    c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return [((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c]


_MATS = {}
_IMGS = {}


def _image(name, non_color=False):
    key = (name, non_color)
    if key in _IMGS:
        return _IMGS[key]
    img = bpy.data.images.load(os.path.join(TEX_DIR, name + ".png"), check_existing=True)
    if non_color:
        img.colorspace_settings.name = "Non-Color"
    _IMGS[key] = img
    return img


def material(name):
    if name in _MATS:
        return _MATS[name]
    hexc, rough, metal, emit, alpha = PALETTE[name]
    m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except Exception:
        pass
    nt = m.node_tree
    p = nt.nodes.get("Principled BSDF")
    col = _lin(hexc) + [1.0]
    p.inputs["Base Color"].default_value = col
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    if name in TEX:
        tex, _tile, nstr = TEX[name]
        it = nt.nodes.new("ShaderNodeTexImage")
        it.image = _image(tex)
        if hexc.lower() != "ffffff":
            mix = nt.nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            mix.blend_type = "MULTIPLY"
            mix.inputs["Factor"].default_value = 1.0
            nt.links.new(it.outputs["Color"], mix.inputs[6])
            mix.inputs[7].default_value = col
            nt.links.new(mix.outputs[2], p.inputs["Base Color"])
        else:
            nt.links.new(it.outputs["Color"], p.inputs["Base Color"])
        if nstr > 0 and os.path.exists(os.path.join(TEX_DIR, tex + "_n.png")):
            nm = nt.nodes.new("ShaderNodeTexImage")
            nm.image = _image(tex + "_n", True)
            nmap = nt.nodes.new("ShaderNodeNormalMap")
            nmap.inputs["Strength"].default_value = nstr
            nt.links.new(nm.outputs["Color"], nmap.inputs["Color"])
            nt.links.new(nmap.outputs["Normal"], p.inputs["Normal"])
    if emit > 0:
        p.inputs["Emission Color"].default_value = col
        p.inputs["Emission Strength"].default_value = emit
    if name in ("simulator_screen", "range_display"):
        it = nt.nodes.new("ShaderNodeTexImage")
        it.image = _image("simulator_range" if name == "simulator_screen" else "range_monitor")
        it.extension = "EXTEND"
        nt.links.new(it.outputs["Color"], p.inputs["Base Color"])
        nt.links.new(it.outputs["Color"], p.inputs["Emission Color"])
    if alpha < 1.0:
        p.inputs["Alpha"].default_value = alpha
        if hasattr(m, "surface_render_method"):
            m.surface_render_method = "BLENDED"
    m.diffuse_color = col
    _MATS[name] = m
    return m


FACING = {  # wall frames: u = viewer's right when facing the wall from outside, n = outward
    "+y": (Vector((-1, 0, 0)), Vector((0, 1, 0))),
    "-y": (Vector((1, 0, 0)), Vector((0, -1, 0))),
    "+x": (Vector((0, 1, 0)), Vector((1, 0, 0))),
    "-x": (Vector((0, -1, 0)), Vector((-1, 0, 0))),
}


def frame_matrix(u, n, c):
    m = Matrix.Identity(4)
    for i in range(3):
        m[i][0], m[i][1], m[i][2], m[i][3] = u[i], n[i], (0, 0, 1)[i], c[i]
    return m


class Builder:
    """One mesh's worth of geometry, a material index per face; UVs box-mapped at finish().
    `markers` are placements Godot fills with real assets: ("CART" | "PLANT_<nature pack id>",
    x, y, z, yaw, scale)."""

    def __init__(self):
        self.bm = bmesh.new()
        self.mats = []
        self.markers = []

    def marker(self, kind, x, y, z, rz=0.0, scale=1.0):
        self.markers.append((kind, x, y, z, rz, scale))

    def mi(self, name):
        if name not in self.mats:
            self.mats.append(name)
        return self.mats.index(name)

    def append(self, src, matrix, mat, smooth=False, face_mat=None):
        vmap = {}
        for v in src.verts:
            vmap[v] = self.bm.verts.new(matrix @ v.co)
        rot = matrix.to_3x3()
        for f in src.faces:
            try:
                nf = self.bm.faces.new([vmap[v] for v in f.verts])
            except ValueError:
                continue
            m = face_mat(rot @ f.normal) if face_mat else mat
            nf.material_index = self.mi(m)
            nf.smooth = smooth or f.smooth
        src.free()

    def box(self, size, center, mat, rz=0.0, rx=0.0, ry=0.0, bevel=0.0, matrix=None, face_mat=None):
        src = bmesh.new()
        bmesh.ops.create_cube(src, size=1.0)
        bmesh.ops.scale(src, vec=Vector(size), verts=src.verts)
        if bevel > 0 and min(size) > bevel * 2.5:
            bmesh.ops.bevel(src, geom=src.verts[:] + src.edges[:], offset=bevel, segments=2, affect="EDGES", profile=0.5, clamp_overlap=True)
        m = Matrix.Translation(Vector(center)) @ Matrix.Rotation(rz, 4, "Z") @ Matrix.Rotation(ry, 4, "Y") @ Matrix.Rotation(rx, 4, "X")
        self.append(src, (matrix @ m) if matrix is not None else m, mat, face_mat=face_mat)

    def fbox(self, frame, c, size, mat, bevel=0.0):
        """Box in a wall frame (u, n, up): c and size are (along, out, up)."""
        src = bmesh.new()
        bmesh.ops.create_cube(src, size=1.0)
        bmesh.ops.scale(src, vec=Vector(size), verts=src.verts)
        if bevel > 0 and min(size) > bevel * 2.5:
            bmesh.ops.bevel(src, geom=src.verts[:] + src.edges[:], offset=bevel, segments=2, affect="EDGES", profile=0.5, clamp_overlap=True)
        self.append(src, frame @ Matrix.Translation(Vector(c)), mat)

    def cyl(self, r1, r2, h, base, mat, segs=12, smooth=True, rz=0.0, rx=0.0, ry=0.0, matrix=None):
        src = bmesh.new()
        bmesh.ops.create_cone(src, cap_ends=True, cap_tris=False, segments=segs, radius1=r1, radius2=r2, depth=h)
        for f in src.faces:
            f.smooth = smooth and len(f.verts) == 4
        m = Matrix.Translation(Vector(base)) @ Matrix.Rotation(rz, 4, "Z") @ Matrix.Rotation(ry, 4, "Y") @ Matrix.Rotation(rx, 4, "X") @ Matrix.Translation((0, 0, h * 0.5))
        self.append(src, (matrix @ m) if matrix is not None else m, mat)

    def ball(self, r, center, mat, scale=(1, 1, 1), subdiv=2, matrix=None):
        src = bmesh.new()
        bmesh.ops.create_icosphere(src, subdivisions=subdiv, radius=r)
        for f in src.faces:
            f.smooth = True
        m = Matrix.Translation(Vector(center)) @ Matrix.Diagonal(Vector(tuple(scale) + (1,)))
        self.append(src, (matrix @ m) if matrix is not None else m, mat, smooth=True)

    def poly(self, verts, faces, mat, smooth=False, recalc=True):
        src = bmesh.new()
        vs = [src.verts.new(Vector(v)) for v in verts]
        for f in faces:
            try:
                src.faces.new([vs[i] for i in f])
            except ValueError:
                pass
        if recalc:
            bmesh.ops.recalc_face_normals(src, faces=src.faces)
        self.append(src, Matrix.Identity(4), mat, smooth)

    def image_quad(self, verts, mat, matrix=None, uv_rect=(0, 0, 1, 1)):
        """A single display image, with explicit full-image UVs rather than tiled world UVs."""
        xf = matrix if matrix is not None else Matrix.Identity(4)
        vs = [self.bm.verts.new(xf @ Vector(v)) for v in verts]
        face = self.bm.faces.new(vs)
        face.material_index = self.mi(mat)
        uv = self.bm.loops.layers.uv.get("DisplayUV") or self.bm.loops.layers.uv.new("DisplayUV")
        u0, v0, u1, v1 = uv_rect
        # Seen from +Y, +X is the left side of the display.
        for lp, coord in zip(face.loops, ((u0, v0), (u1, v0), (u1, v1), (u0, v1))):
            lp[uv].uv = coord

    def text(self, body, facing, c, size, mat, depth=0.05, font_bold=True):
        cu = bpy.data.curves.new("txt", "FONT")
        cu.body = body
        cu.align_x = "CENTER"
        cu.align_y = "CENTER"
        cu.size = size
        cu.extrude = depth * 0.5
        ob = bpy.data.objects.new("txt", cu)
        bpy.context.scene.collection.objects.link(ob)
        dg = bpy.context.evaluated_depsgraph_get()
        ev = ob.evaluated_get(dg)
        me = ev.to_mesh()
        src = bmesh.new()
        src.from_mesh(me)
        ev.to_mesh_clear()
        bpy.data.objects.remove(ob)
        bpy.data.curves.remove(cu)
        u, n = FACING[facing]
        rot = Matrix.Identity(4)
        for i in range(3):
            rot[i][0], rot[i][1], rot[i][2] = u[i], (0, 0, 1)[i], n[i]
        self.append(src, Matrix.Translation(Vector(c) + n * depth * 0.5) @ rot, mat)

    def finish(self, name, collection, parent=None):
        if len(self.bm.faces) == 0:
            self.bm.free()
            if not self.markers:
                return None
            ob = bpy.data.objects.new(name, None)
            collection.objects.link(ob)
            self._emit_markers(ob, collection)
            return ob
        self.bm.normal_update()
        uv = self.bm.loops.layers.uv.new("UVMap")
        display_uv = self.bm.loops.layers.uv.get("DisplayUV")
        for f in self.bm.faces:
            mname = self.mats[f.material_index]
            if mname in ("simulator_screen", "range_display") and display_uv is not None:
                for lp in f.loops:
                    lp[uv].uv = lp[display_uv].uv
                continue
            tile = TEX[mname][1] if mname in TEX else 1.0
            n = f.normal
            if abs(n.z) > 0.92:
                t, b = Vector((1, 0, 0)), Vector((0, 1, 0))
            else:
                t = Vector((-n.y, n.x, 0)).normalized()
                b = n.cross(t)
                if b.z < 0:
                    b = -b
                    t = -t
            for lp in f.loops:
                co = lp.vert.co
                lp[uv].uv = (co.dot(t) / tile, co.dot(b) / tile)
        me = bpy.data.meshes.new(name)
        self.bm.to_mesh(me)
        self.bm.free()
        if me.uv_layers.get("DisplayUV") is not None:
            me.uv_layers.remove(me.uv_layers["DisplayUV"])
        if me.uv_layers.get("UVMap") is not None:
            me.uv_layers.active = me.uv_layers["UVMap"]
        for m in self.mats:
            me.materials.append(material(m))
        ob = bpy.data.objects.new(name, me)
        collection.objects.link(ob)
        if parent is not None:
            ob.parent = parent
        self._emit_markers(ob, collection)
        return ob

    def _emit_markers(self, ob, collection):
        for i, (kind, x, y, z, rz, sc) in enumerate(self.markers):
            e = bpy.data.objects.new("%s_%d" % (kind, i), None)
            e.location = (x, y, z)
            e.rotation_euler = (0, 0, rz)
            e.scale = (sc, sc, sc)
            e.empty_display_type = "ARROWS"
            e["marker"] = kind
            collection.objects.link(e)
            e.parent = ob


class Model:
    """A facility level: named geometry groups (one mesh each) plus markers."""

    GROUPS = ("BASE", "WALLS_HIGH", "ROOF")

    def __init__(self, name):
        self.name = name
        self.C = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(self.C)
        self.g = {k: Builder() for k in self.GROUPS}
        self.rooms = {}  # "ROOM_<id>_T<k>" -> Builder
        self.spots = {}  # "ROOM_<id>_T<k>" -> [(x, y, z, facing)]
        self.roomboxes = []
        self.cols = []
        self.sign = None
        self.sign_size = None  # a monument's panel (width, height): Godot fits the name inside it
        self.cut = 1.1  # walls above floor + cut go in WALLS_HIGH
        # every window and door as the walls go up: {"c": centre XY, "u": the wall's direction,
        # "w": width, "z0" / "z1": its sill and head, "pass": people walk through it}
        self.openings = []
        self.deferred = []  # rooms waiting to be furnished once the walls are all up

    def room(self, rid, tier):
        key = "ROOM_%s_T%d" % (rid, tier)
        if key not in self.rooms:
            self.rooms[key] = Builder()
            self.spots[key] = []
        return self.rooms[key]

    def spot(self, rid, tier, x, y, z, face=0.0, role=""):
        """Where staff stand in a room tier (facing `face`); `role` keeps it for one staff role
        (a chef in the kitchen, a bartender behind the bar)."""
        self.spots["ROOM_%s_T%d" % (rid, tier)].append((x, y, z, face, role))

    def finish(self):
        objs = []
        for k, b in self.g.items():
            ob = b.finish(k, self.C)
            if ob:
                objs.append(ob)
        for index,(builder,hinge,side) in enumerate(getattr(self,'door_leaves',[])):
            ob=builder.finish('DOORLEAF_'+side+'_'+str(index),self.C)
            ob.matrix_world=hinge
            objs.append(ob)
        for k, b in self.rooms.items():
            ob = b.finish(k, self.C)
            if ob is None:
                ob = bpy.data.objects.new(k, None)
                self.C.objects.link(ob)
            for i, (x, y, z, face, role) in enumerate(self.spots[k]):
                e = bpy.data.objects.new("SPOT_%s_%d" % (role, i) if role else "SPOT_%d" % i, None)
                e.location = (x, y, z)
                e.rotation_euler = (0, 0, face)
                self.C.objects.link(e)
                e.parent = ob
            objs.append(ob)
        for rid, (x0, y0, x1, y1, z) in self.roomboxes:
            e = bpy.data.objects.new("ROOMBOX_" + rid, None)
            e.location = ((x0 + x1) * 0.5, (y0 + y1) * 0.5, z)
            e.scale = (x1 - x0, y1 - y0, 1.0)
            e.empty_display_type = "CUBE"
            self.C.objects.link(e)
        if self.sign:
            # one, at (x, y, z) facing +y -- or a list of (x, y, z, turn), one for each face
            for k, s in enumerate(self.sign if isinstance(self.sign, list) else [tuple(self.sign) + (0.0,)]):
                e = bpy.data.objects.new("SIGN_%d" % k if k else "SIGN", None)
                e.location = s[:3]
                e.rotation_euler = (0.0, 0.0, s[3])
                if self.sign_size:
                    e.scale = (self.sign_size[0], 1.0, self.sign_size[1])
                self.C.objects.link(e)
        for name, size, center in self.cols:
            me = bpy.data.meshes.new("COL_" + name)
            bm = bmesh.new()
            bmesh.ops.create_cube(bm, size=1.0)
            bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
            bm.to_mesh(me)
            bm.free()
            ob = bpy.data.objects.new("COL_" + name, me)
            ob.location = center
            ob.hide_render = True
            ob.display_type = "WIRE"
            self.C.objects.link(ob)
        return objs


# ---------------------------------------------------------------- architecture

def split_box(M, size, center, low_mat_fn=None, mat="plaster", face_mat=None, rz=0.0):
    """A box that may straddle the cutaway height: low part to BASE, high part to WALLS_HIGH."""
    cut = M.floor_z + M.cut
    z0 = center[2] - size[2] * 0.5
    z1 = center[2] + size[2] * 0.5
    if z1 <= cut + 1e-4:
        M.g["BASE"].box(size, center, mat, rz=rz, face_mat=face_mat)
    elif z0 >= cut - 1e-4:
        M.g["WALLS_HIGH"].box(size, center, mat, rz=rz, face_mat=face_mat)
    else:
        M.g["BASE"].box((size[0], size[1], cut - z0), (center[0], center[1], (z0 + cut) * 0.5), mat, rz=rz, face_mat=face_mat)
        M.g["WALLS_HIGH"].box((size[0], size[1], z1 - cut), (center[0], center[1], (cut + z1) * 0.5), mat, rz=rz, face_mat=face_mat)


def wall(M, p0, p1, height, ext="shingle", intm="plaster", openings=(), thick=0.25, outward=None, z0=None):
    """A straight wall from p0 to p1 (XY) rising `height` from the floor, with openings:
    dicts {at: centre distance from p0, w, sill, head, kind: 'window'|'door'|'open'|'french'|'gap'}
    ('gap': just no wall there -- one room running on through it -- not a doorway: no DOOR marker).
    `outward` (unit XY) faces the exterior material; None = interior both sides."""
    z0 = M.floor_z if z0 is None else z0
    a = Vector((p0[0], p0[1], 0))
    b = Vector((p1[0], p1[1], 0))
    d = b - a
    ln = d.length
    if ln < 0.01:
        return
    u = d / ln
    ang = math.atan2(u.y, u.x)
    n = Vector((-u.y, u.x, 0))
    if outward is not None and n.dot(Vector((outward[0], outward[1], 0))) < 0:
        n = -n
    out = n if outward is not None else None

    def fm(normal):
        if out is not None and normal.dot(out) > 0.5:
            return ext
        return intm

    def seg(s0, s1, h0, h1):
        if s1 - s0 < 0.01 or h1 - h0 < 0.01:
            return
        c = a + u * ((s0 + s1) * 0.5)
        split_box(M, (s1 - s0, thick, h1 - h0), (c.x, c.y, z0 + (h0 + h1) * 0.5), mat=intm, face_mat=fm, rz=ang)
        if h0 <= 0.0:  # a baseboard along the foot of the wall
            M.g["BASE"].box((s1 - s0, thick + 0.03, 0.13), (c.x, c.y, z0 + 0.065), "trim", rz=ang)

    ops = sorted(openings, key=lambda o: o["at"])
    s = 0.0
    for o in ops:
        o0, o1 = o["at"] - o["w"] * 0.5, o["at"] + o["w"] * 0.5
        seg(s, o0, 0.0, height)
        seg(o0, o1, 0.0, o.get("sill", 0.0))
        seg(o0, o1, o.get("head", 2.2), height)
        c = a + u * o["at"]
        kind = o.get("kind", "window")
        glazed = kind in ("window", "french")
        if not o.get("backed"):  # (a gap another wall stands in is no way through, nor kept clear)
            M.openings.append({"c": (c.x, c.y), "u": (u.x, u.y), "w": o["w"],
                               "z0": z0 + (o.get("sill", 0.9) if glazed else 0.0),
                               "z1": z0 + o.get("head", 2.3 if glazed else (2.8 if kind == "garage" else 2.2)),
                               "pass": not glazed or o.get("sill", 0.9) < 0.2})
        F = frame_matrix(Vector((math.cos(ang), math.sin(ang), 0)), n, (c.x, c.y, z0))
        if kind in ("window", "french"):
            _window_in(M, F, o["w"], o.get("sill", 0.9), o.get("head", 2.3), thick, out is not None, kind == "french")
            if kind == "french" and o.get("sill", 0.9) < 0.2:
                M.g["BASE"].marker("DOOR", c.x, c.y, z0, ang, o["w"])  # a garden door: people use it
        elif kind == "door":
            M.g["BASE"].marker("DOOR", c.x, c.y, z0, ang, o["w"])
            _door_in(M, F, o["w"], o.get("head", 2.2), thick, o.get("door", "door_white"), out is not None, o.get("double", False))
        elif kind == "open":
            M.g["BASE"].marker("DOOR", c.x, c.y, z0, ang, o["w"])
        elif kind == "garage":
            _garage_in(M, F, o["w"], o.get("head", 2.8), thick, o.get("open", True))
        s = o1
    seg(s, ln, 0.0, height)


def moving_door(M, F, w, head, mat="door_white", french=False, side="L"):
    """A separate hinged leaf; the game opens it before a person reaches it."""
    if not hasattr(M, 'door_leaves'):M.door_leaves=[]
    leaf=Builder()
    if mat == "entry_glass":
        leaf.box((w-.12,.022,head-.16),(w*.5,0,head*.5),mat)
        for x in (.03,w-.03):leaf.box((.06,.08,head),(x,0,head*.5),"iron")
        for z in (.04,head-.04):leaf.box((w,.08,.08),(w*.5,0,z),"iron")
        leaf.box((w-.12,.028,.11),(w*.5,0,.14),"brass")
        for normal in (-1,1):
            leaf.cyl(.016,.016,.58,(w-.15,normal*.11,head*.46),"brass",segs=10)
            for dz in (-.24,.24):leaf.box((.032,.10,.032),(w-.15,normal*.065,head*.46+dz),"brass")
    elif french:
        leaf.box((w-.12,.045,head-.15),(w*.5,0,head*.5),"glass")
        for x in (.045,w-.045):leaf.box((.09,.075,head),(x,0,head*.5),"trim")
        for z in (.045,head-.045):leaf.box((w,.075,.09),(w*.5,0,z),"trim")
        for row in range(1,5):leaf.box((w-.12,.075,.035),(w*.5,0,head*row/5),"trim")
    else:
        leaf.box((w,.065,head),(w*.5,0,head*.5),mat)
        for normal in (-1,1):
            leaf.box((w*.72,.015,head*.32),(w*.5,normal*.04,head*.72),"glass" if mat=="door_white" else mat)
    if mat != "entry_glass":
        for normal in (-1,1):leaf.box((.045,.08,.08),(w-.13,normal*.07,head*.46),"brass")
    M.door_leaves.append((leaf,F,side))


def _window_in(M, F, w, sill, head, thick, exterior, french=False):
    G = M.g["WALLS_HIGH"]
    h = head - sill
    zc = sill + h * 0.5
    if french and M.name.startswith("clubhouse"):
        for side,sign in (("L",1),("R",-1)):
            hinge=F@Matrix.Translation((-sign*w*.5,0,0))
            if sign<0:hinge=hinge@Matrix.Rotation(math.pi,4,'Z')
            moving_door(M,hinge,w*.5,head,"door_white",True,side)
        for x in (-w*.5-.06,w*.5+.06):
            G.fbox(F,(x,0,head*.5),(.12,thick+.06,head+.1),"trim")
        G.fbox(F,(0,0,head+.06),(w+.3,thick+.06,.12),"trim")
        return
    G.fbox(F, (0, 0, zc), (w, 0.04, h), "glass")
    ft = 0.09
    for side in ((1,) if not exterior else (1, -1)):
        off = side * (thick * 0.5 + 0.02)
        G.fbox(F, (0, off, head + 0.06), (w + 0.36, 0.08, 0.16), "trim")
        G.fbox(F, (0, off, sill - 0.05), (w + 0.36, 0.14 if side > 0 else 0.08, 0.1), "trim")
        for s2 in (-1, 1):
            G.fbox(F, (s2 * (w * 0.5 + 0.09), off, zc), (0.18, 0.08, h + 0.12), "trim")
    G.fbox(F, (0, 0, zc), (w, thick + 0.02, 0.06) if not french else (0.06, thick + 0.02, h), "trim")
    cols = 3 if w > 1.2 else 2
    rows = 4 if not french else 5
    for i in range(1, cols):
        G.fbox(F, (-w * 0.5 + w * i / cols, 0.0, zc), (0.035, 0.07, h), "trim")
    for j in range(1, rows):
        if not french and j == rows // 2:
            continue
        G.fbox(F, (0, 0.0, sill + h * j / rows), (w, 0.07, 0.035), "trim")
    for s2 in (-1, 1):  # jamb lining through the wall
        G.fbox(F, (s2 * w * 0.5, 0, zc), (0.04, thick, h), "trim")
    G.fbox(F, (0, 0, head), (w, thick, 0.04), "trim")


def _door_in(M, F, w, head, thick, mat, exterior, double=False):
    G = M.g["WALLS_HIGH"]
    dynamic=M.name.startswith("clubhouse")
    if dynamic and double:
        # a pair of leaves meeting in the middle, hinged at either jamb (like the French doors)
        for side,sign in (("L",1),("R",-1)):
            hinge=F@Matrix.Translation((-sign*w*.5,0,0))
            if sign<0:hinge=hinge@Matrix.Rotation(math.pi,4,'Z')
            moving_door(M,hinge,w*.5,head,mat,False,side)
    elif dynamic:
        moving_door(M,F@Matrix.Translation((-w*.5,0,0)),w,head,mat)
    leaf = F @ Matrix.Translation((-w / 2, 0, 0)) @ Matrix.Rotation(math.radians(85), 4, "Z") @ Matrix.Translation((w / 2, 0, 0))
    if not dynamic:G.fbox(leaf, (0, 0, head * 0.5), (w, 0.06, head), mat)
    for s2 in (-1, 1):
        G.fbox(F, (s2 * (w * 0.5 + 0.08), 0, head * 0.5), (0.16, thick + 0.06, head + 0.1), "trim")
    G.fbox(F, (0, 0, head + 0.08), (w + 0.4, thick + 0.06, 0.16), "trim")
    for side in (() if dynamic else (1, -1)):
        G.fbox(leaf, (0, side * 0.04, head * 0.72), (w * 0.8, 0.02, head * 0.36), "glass" if mat == "door_white" else mat)
        G.fbox(leaf, (w * 0.35, side * 0.06, head * 0.48), (0.05, 0.05, 0.05), "brass")


def _garage_in(M, F, w, head, thick, is_open):
    G = M.g["WALLS_HIGH"]
    for s2 in (-1, 1):
        G.fbox(F, (s2 * (w * 0.5 + 0.1), 0.06, head * 0.5), (0.2, thick + 0.1, head + 0.1), "trim")
    G.fbox(F, (0, 0.06, head + 0.1), (w + 0.4, thick + 0.1, 0.2), "trim")
    # Numeric fractions raise a sectional door by part of its height; bools retain
    # the ordinary closed / fully open meaning used by existing facilities.
    opened = max(0.0, min(1.0, float(is_open)))
    bottom = head * opened
    remaining = head - bottom
    if remaining > .02:
        count = max(1, round(remaining / .42))
        for k in range(count):
            G.fbox(F, (0, 0.0, bottom + (k + .5) * remaining / count),
                   (w, .065, remaining / count - .018), "door_white")
        G.fbox(F, (0, .06, bottom + .16), (.45, .035, .05), "black")
    if opened > .01:
        G.fbox(F, (0, -bottom * .5, head + .05), (w, bottom, .09), "door_white")
    # Side tracks make raised leaves read as proper overhead garage doors.
    for side in (-1, 1):
        G.fbox(F, (side * (w * .5 - .04), -.12, head * .5), (.04, .04, head), "chrome")


def shell(M, x0, y0, x1, y1, height, front_openings=(), back_openings=(), left_openings=(), right_openings=(), ext="shingle", intm="plaster", thick=0.25):
    """Four exterior walls of a rectangle (front = +y side = y1)."""
    wall(M, (x1, y1), (x0, y1), height, ext, intm, front_openings, thick, (0, 1))   # front, runs right->left (viewer's left->right is -x->+x... at = distance from x1)
    wall(M, (x0, y0), (x1, y0), height, ext, intm, back_openings, thick, (0, -1))
    wall(M, (x0, y1), (x0, y0), height, ext, intm, left_openings, thick, (-1, 0))
    wall(M, (x1, y0), (x1, y1), height, ext, intm, right_openings, thick, (1, 0))
    # corner boards, water table, frieze
    G = M.g["WALLS_HIGH"]
    for (cx, cy) in ((x0, y0), (x1, y0), (x0, y1), (x1, y1)):
        split_box(M, (0.3, 0.3, height), (cx, cy, M.floor_z + height * 0.5), mat="trim")

    def board(group, a, b, openings, cut, tall, z):
        """A trim board along the wall a -> b (and round its corners), `tall` high at `z`, broken
        at each of its openings that `cut` says."""
        ln = math.hypot(b[0] - a[0], b[1] - a[1])
        ux, uy = (b[0] - a[0]) / ln, (b[1] - a[1]) / ln
        cuts = sorted((o["at"] - o["w"] * 0.5, o["at"] + o["w"] * 0.5) for o in openings if cut(o))
        s = -0.15
        for c0, c1 in cuts + [(ln + 0.15, ln + 0.15)]:
            if c0 - s > 0.01:
                mid = (s + c0) * 0.5
                size = (c0 - s, 0.32, tall) if abs(ux) > 0.5 else (0.32, c0 - s, tall)
                group.box(size, (a[0] + ux * mid, a[1] + uy * mid, z), "trim")
            s = max(s, c1)

    def doorway(o):
        # people walk through a door, not over a kerb of trim across it (nor where there's no wall)
        return o.get("kind") in ("door", "open", "garage", "gap") or (o.get("kind") == "french" and o.get("sill", 0.9) < 0.2)

    for a, b, openings in (((x1, y1), (x0, y1), front_openings), ((x0, y0), (x1, y0), back_openings),
                           ((x0, y1), (x0, y0), left_openings), ((x1, y0), (x1, y1), right_openings)):
        board(M.g["BASE"], a, b, openings, doorway, 0.2, M.floor_z + 0.1)  # the water table
        board(G, a, b, openings, lambda o: o.get("kind") == "gap", 0.35, M.floor_z + height - 0.17)  # the frieze


def foundation(M, x0, y0, x1, y1, mat="brick"):
    h = M.floor_z - M.ground_z
    M.g["BASE"].box((x1 - x0 + 0.1, y1 - y0 + 0.1, h), ((x0 + x1) * 0.5, (y0 + y1) * 0.5, M.ground_z + h * 0.5), mat)


def floor(M, x0, y0, x1, y1, mat):
    M.g["BASE"].box((x1 - x0, y1 - y0, 0.04), ((x0 + x1) * 0.5, (y0 + y1) * 0.5, M.floor_z + 0.02), mat)


def gable_roof(G, L, S, rise, c, z0, mat="roof", ridge="x", over=0.45, t=0.18, trim=True):
    """Gable roof with overhang and white fascia / rake boards; eaves at z0."""
    half = S * 0.5 + over
    drop = over * rise / (S * 0.5)
    ze, zr, hl = z0 - drop, z0 + rise, L * 0.5 + over

    def P(a, s, z):
        return (c[0] + a, c[1] + s, z) if ridge == "x" else (c[0] + s, c[1] + a, z)

    top = [P(-hl, -half, ze), P(-hl, 0, zr), P(-hl, half, ze), P(hl, -half, ze), P(hl, 0, zr), P(hl, half, ze)]
    bot = [(p[0], p[1], p[2] - t) for p in top]
    f = [(0, 1, 4, 3), (1, 2, 5, 4), (6, 9, 10, 7), (7, 10, 11, 8), (0, 3, 9, 6), (2, 8, 11, 5), (0, 6, 7, 1), (1, 7, 8, 2), (3, 4, 10, 9), (4, 5, 11, 10)]
    G.poly(top + bot, f, mat)
    if not trim:
        return
    slope = math.atan2(rise, S * 0.5)
    ln = math.hypot(half, rise + drop)
    for side in (-1, 1):  # fascia along each eave
        cc = P(0, side * half, ze - t * 0.5)
        G.box((L + over * 2 + 0.05, 0.06, 0.3) if ridge == "x" else (0.06, L + over * 2 + 0.05, 0.3), cc, "trim")
    for end in (-1, 1):  # rake boards up each gable edge
        for side in (-1, 1):
            cc = P(end * (hl + 0.02), side * half * 0.5, (ze + zr) * 0.5 - t * 0.5)
            if ridge == "x":
                G.box((0.08, ln, 0.3), cc, "trim", rx=-side * slope)
            else:
                G.box((ln, 0.08, 0.3), cc, "trim", ry=side * slope)


def gable_wall(G, L, S, rise, c, z0, mat="shingle", ridge="x"):
    hs, hl = S * 0.5, L * 0.5

    def P(a, s, z):
        return (c[0] + a, c[1] + s, z) if ridge == "x" else (c[0] + s, c[1] + a, z)

    v = [P(-hl, -hs, z0), P(-hl, 0, z0 + rise), P(-hl, hs, z0), P(hl, -hs, z0), P(hl, 0, z0 + rise), P(hl, hs, z0)]
    # Only the vertical end walls belong here. Closing this as a triangular prism
    # puts cedar faces exactly on the roof-shingle slopes, causing z-fighting.
    G.poly(v, [(0, 1, 2), (3, 5, 4)], mat)


def hip_roof(G, L, S, rise, c, z0, mat="roof", over=0.45, t=0.18):
    hl, hs = L * 0.5 + over, S * 0.5 + over
    drop = over * rise / (min(L, S) * 0.5)
    ze, zr = z0 - drop, z0 + rise
    x, y = c[0], c[1]
    if L >= S:
        rl = L * 0.5 - S * 0.5
        top = [(x - hl, y - hs, ze), (x + hl, y - hs, ze), (x + hl, y + hs, ze), (x - hl, y + hs, ze), (x - rl, y, zr), (x + rl, y, zr)]
        f = [(0, 1, 5, 4), (1, 2, 5), (2, 3, 4, 5), (3, 0, 4)]
    else:
        rl = S * 0.5 - L * 0.5
        top = [(x - hl, y - hs, ze), (x + hl, y - hs, ze), (x + hl, y + hs, ze), (x - hl, y + hs, ze), (x, y - rl, zr), (x, y + rl, zr)]
        f = [(0, 1, 4), (1, 2, 5, 4), (2, 3, 5), (3, 0, 4, 5)]
    bot = [(p[0], p[1], p[2] - t) for p in top]
    fb = [tuple(i + 6 for i in reversed(ff)) for ff in f]
    sides = [(0, 6, 7, 1), (1, 7, 8, 2), (2, 8, 9, 3), (3, 9, 6, 0)]
    G.poly(top + bot, f + fb + sides, mat)
    for (a, b) in ((0, 1), (1, 2), (2, 3), (3, 0)):
        p, q = Vector(top[a]), Vector(top[b])
        mid = (p + q) * 0.5
        d = q - p
        G.box((d.length + 0.05, 0.06, 0.3), (mid.x, mid.y, mid.z - t * 0.5), "trim", rz=math.atan2(d.y, d.x))


def dormer(M, x, y_face, z_base, w=2.2, h=1.9, depth=3.2, window_w=0.95):
    """Gable dormer facing +y on a front roof slope."""
    G = M.g["ROOF"]
    G.box((w, depth, h), (x, y_face - depth * 0.5, z_base + h * 0.5), "shingle")
    for s in (-1, 1):
        G.box((0.18, 0.18, h), (x + s * w * 0.5, y_face, z_base + h * 0.5), "trim")
    rise = w * 0.62
    gable_wall(G, depth, w, rise, (x, y_face - depth * 0.5), z_base + h, "shingle", ridge="y")
    gable_roof(G, depth + 0.1, w, rise, (x, y_face - depth * 0.5 + 0.12), z_base + h, ridge="y", over=0.22)
    F = frame_matrix(Vector((-1, 0, 0)), Vector((0, 1, 0)), (x, y_face, 0))
    G.fbox(F, (0, 0.02, z_base + h * 0.5), (window_w, 0.05, h * 0.62), "glass")
    for s in (-1, 1):
        G.fbox(F, (s * (window_w * 0.5 + 0.08), 0.06, z_base + h * 0.5), (0.16, 0.08, h * 0.62 + 0.2), "trim")
    G.fbox(F, (0, 0.06, z_base + h * 0.81 + 0.06), (window_w + 0.36, 0.08, 0.14), "trim")
    G.fbox(F, (0, 0.08, z_base + h * 0.19 - 0.05), (window_w + 0.36, 0.14, 0.1), "trim")
    G.fbox(F, (0, 0.05, z_base + h * 0.5), (0.035, 0.06, h * 0.62), "trim")
    G.fbox(F, (0, 0.05, z_base + h * 0.5), (window_w, 0.06, 0.035), "trim")


def chimney(M, x, y, z_top, w=1.2, d=0.9):
    G = M.g["ROOF"]
    h = z_top - M.floor_z
    G.box((w, d, h), (x, y, M.floor_z + h * 0.5), "brick")
    G.box((w + 0.2, d + 0.2, 0.22), (x, y, z_top + 0.11), "brick_cap")
    for s in (-0.22, 0.22):
        G.cyl(0.12, 0.12, 0.4, (x + s, y, z_top + 0.22), "brick_cap", segs=8)


def column(G, x, y, z0, h, r=0.2, mat="trim"):
    G.box((r * 2.6, r * 2.6, 0.25), (x, y, z0 + 0.125), mat, bevel=0.02)
    G.cyl(r, r * 0.9, h - 0.5, (x, y, z0 + 0.25), mat, segs=16)
    G.box((r * 2.6, r * 2.6, 0.25), (x, y, z0 + h - 0.125), mat, bevel=0.02)


def railing(G, p0, p1, z0, h=0.95, mat="trim", post_every=2.0, spindle=0.16, post=True):
    a = Vector((p0[0], p0[1], 0))
    b = Vector((p1[0], p1[1], 0))
    d = b - a
    ln = d.length
    if ln < 0.05:
        return
    ang = math.atan2(d.y, d.x)
    mid = (a + b) * 0.5
    G.box((ln, 0.12, 0.08), (mid.x, mid.y, z0 + h - 0.04), mat, rz=ang)
    G.box((ln, 0.08, 0.06), (mid.x, mid.y, z0 + 0.12), mat, rz=ang)
    if post:
        n = max(int(ln / post_every), 1)
        for i in range(n + 1):
            p = a + d * (i / n)
            G.box((0.14, 0.14, h + 0.06), (p.x, p.y, z0 + (h + 0.06) * 0.5), mat, rz=ang)
    ns = int(ln / spindle)
    for i in range(1, ns):
        p = a + d * (i / ns)
        G.box((0.04, 0.04, h - 0.2), (p.x, p.y, z0 + 0.15 + (h - 0.2) * 0.5), mat, rz=ang)


def porch(M, x0, x1, y0, y1, roof_z, cols_y, col_xs, steps=(), rail=True, deck="deck", roof_slope=0.22, facing="+y"):
    """A covered porch over the rectangle x0..x1, y0..y1 against a wall on the side away from
    `facing`: "+y" in front of a wall at y0 (out toward +y, to y1); "-x" beside a wall at x1 (out
    toward -x, to x0); "+x", "-y" likewise. Its roof slopes down away from the wall. `cols_y`: how
    far out its columns stand (a y; an x for "-x" / "+x"); `col_xs` and the steps' (centre, width):
    along it."""
    B, G, R = M.g["BASE"], M.g["WALLS_HIGH"], M.g["ROOF"]
    z = M.floor_z
    # built in the porch's own frame (a: along the wall, o: out from it), turned to its side
    m = Matrix.Rotation({"+y": 0.0, "-x": math.pi / 2, "-y": math.pi, "+x": -math.pi / 2}[facing], 4, "Z")
    inv = m.inverted()
    side = facing in ("-x", "+x")
    corners = [inv @ Vector((px, py, 0)) for px in (x0, x1) for py in (y0, y1)]
    a0, a1 = min(c.x for c in corners), max(c.x for c in corners)
    o0, o1 = min(c.y for c in corners), max(c.y for c in corners)
    oc = (inv @ (Vector((cols_y, 0, 0)) if side else Vector((0, cols_y, 0)))).y
    am = (a0 + a1) * 0.5

    def at(along):  # world XY of the column line `along` it
        return (cols_y, along) if side else (along, cols_y)

    B.box((a1 - a0, o1 - o0, z - M.ground_z), (am, (o0 + o1) * 0.5, M.ground_z + (z - M.ground_z) * 0.5), "brick", matrix=m)
    B.box((a1 - a0 + 0.1, o1 - o0 + 0.1, 0.08), (am, (o0 + o1) * 0.5, z - 0.04), deck, matrix=m)
    for x in col_xs:
        column(G, *at(x), z, roof_z - z)
    depth = o1 - o0 + 0.6
    R.box((a1 - a0 + 0.8, depth, 0.16), (am, (o0 + o1) * 0.5 + 0.3, roof_z + math.tan(roof_slope) * depth * 0.5 - 0.05), "roof", rx=-roof_slope, matrix=m)
    R.box((a1 - a0 + 0.8, 0.06, 0.32), (am, o1 + 0.6, roof_z - 0.1), "trim", matrix=m)
    G.box((a1 - a0 + 0.4, 0.3, 0.3), (am, oc, roof_z - 0.15), "trim", matrix=m)
    if rail:
        gaps = sorted(steps)
        xs = sorted(col_xs)
        for i in range(len(xs) - 1):
            a, b = xs[i], xs[i + 1]
            if any(a < sx < b for sx, _w in gaps):
                continue
            railing(G, at(a + 0.2), at(b - 0.2), z, 0.9, post=False)
    edge = {"+y": y1, "-y": y0, "+x": x1, "-x": x0}[facing]
    for sx, sw in steps:
        stairs(B, sx, edge, z, M.ground_z, sw, facing=1 if facing in ("+y", "+x") else -1, axis="x" if side else "y")


def stairs(B, x, y_edge, z_top, z_bot, width, run=0.32, mat="stone", facing=1, axis="y"):
    """Solid steps down from z_top at the edge y = y_edge toward `facing` (+1 / -1), centred on
    x; with axis 'x' they run along x instead (from the edge x = y_edge, centred on y = x).
    Returns how far they run."""
    rise = z_top - z_bot
    n = max(int(math.ceil(rise / 0.18)), 1)
    for i in range(n):
        h = rise * (n - i) / n
        s = y_edge + facing * run * (i + 0.5)
        if axis == "y":
            B.box((width, run, h), (x, s, z_bot + h * 0.5), mat)
        else:
            B.box((run, width, h), (s, x, z_bot + h * 0.5), mat)
    return run * n


# ---------------------------------------------------------------- landscaping

def lawn(B, x0, y0, x1, y1, z):
    """Lawn is the course's own ground (its rough, grass and all, graded flat under the plot):
    nothing is laid here, so no raised slab of a different green."""
    return


def pave(B, x0, y0, x1, y1, z, mat="stone", h=0.06):
    B.box((x1 - x0, y1 - y0, h), ((x0 + x1) * 0.5, (y0 + y1) * 0.5, z + h * 0.5 - 0.02), mat)


# Nature pack shrubs are ~2.6 m across and ~1.2 m tall at scale 1; the hedge piece is 3.28 m long.
SHRUB_WIDTH = 2.6
HEDGE_PIECE = 3.28
BED_PLANTS = ("azalea_pink_A", "azalea_red_A", "azalea_white_A", "hydrangea_A", "azalea_pink_B", "azalea_red_B")


def shrub(B, x, y, z, r=0.6, species=None, seed=0):
    """A nature pack shrub about 2r across (boxwood unless a species is given)."""
    sp = species or ("boxwood_A", "boxwood_B")[int(abs(x * 7.3 + y * 3.1)) % 2]
    B.marker("PLANT_" + sp, x, y, z, (x * 12.9898 + y * 78.233) % math.tau, r * 2.0 / SHRUB_WIDTH)


def flower_bed(B, x0, x1, y, z, depth=1.4, seed=0):
    """Foundation planting: a mulch bed with a low clipped hedge along the back (the hedge
    tiles) and azaleas / hydrangea and daisy / wildflower patches in front."""
    B.box((abs(x1 - x0), depth, 0.08), ((x0 + x1) * 0.5, y, z + 0.02), "mulch")
    hedge(B, x0 + 0.2, y - depth * 0.22, x1 - 0.2, y - depth * 0.22, z + 0.06, 0.85)
    n = max(int(abs(x1 - x0) / 1.3), 1)
    for i in range(n + 1):
        x = x0 + (x1 - x0) * i / n
        if i % 2 == 0:
            B.marker("PLANT_" + BED_PLANTS[(i + seed) % len(BED_PLANTS)], x, y + depth * 0.2, z, i * 1.7, 0.3)
        else:
            B.marker("PLANT_" + ("daisy_patch", "wildflower_mix")[(i + seed) % 2], x, y + depth * 0.28, z, i * 2.3, 0.85)


HEDGE_TILE = (4.3, 2.2)  # length, height of the club's seamless hedge tiles at scale 1


def hedge(B, x0, y0, x1, y1, z, h=1.0, w=0.9, variant=None):
    """A clipped hedge from (x0, y0) to (x1, y1) about h tall, laid from the seamless hedge
    tiles (variants A/B/C) end to end, scaled to the height."""
    d = Vector((x1 - x0, y1 - y0, 0))
    ln = d.length
    if ln < 0.1:
        return
    sc = max(h / HEDGE_TILE[1], 0.2)
    n = max(int(math.ceil(ln / (HEDGE_TILE[0] * sc * 0.96))), 1)
    sx = ln / (n * HEDGE_TILE[0] * sc)  # stretch each tile a touch so the row ends on the line
    ang = math.atan2(d.y, d.x)
    for i in range(n):
        p = Vector((x0, y0, 0)) + d * ((i + 0.5) / n)
        v = variant or "ABC"[int(abs(x0 * 3.1 + y0 * 1.7 + i)) % 3]
        B.marker("HEDGE_" + v, p.x, p.y, z, ang, sc * min(max(sx, 0.85), 1.15))


def split_rail(B, p0, p1, z, every=2.6):
    a, b = Vector((p0[0], p0[1], 0)), Vector((p1[0], p1[1], 0))
    d = b - a
    ln = d.length
    ang = math.atan2(d.y, d.x)
    n = max(int(ln / every), 1)
    for i in range(n + 1):
        p = a + d * (i / n)
        B.box((0.16, 0.16, 1.25), (p.x, p.y, z + 0.62), "fence", rz=ang)
    mid = (a + b) * 0.5
    for hh in (0.45, 0.85, 1.15):
        B.box((ln, 0.08, 0.1), (mid.x, mid.y, z + hh), "fence", rz=ang)


def lamp(B, x, y, z, h=3.4):
    """A lamp post `h` tall: from 2 m up, the user's street lamp (a STREET_LAMP marker, scaled to
    its height: Godot stands props/street_lamp.glb, tools/blender/import_street_lamp.py); a path
    light below that, made here."""
    if h >= 2.0:
        B.marker("STREET_LAMP", x, y, z, (x * 5.31 + y * 2.17) % math.tau, h / 3.4)
        return
    B.cyl(0.12, 0.16, 0.35, (x, y, z), "iron", segs=8)
    B.cyl(0.05, 0.05, h - 0.35, (x, y, z + 0.35), "iron", segs=8)
    B.box((0.3, 0.3, 0.42), (x, y, z + h + 0.12), "bulb")
    B.cyl(0.28, 0.02, 0.26, (x, y, z + h + 0.33), "iron", segs=4, smooth=False, rz=math.pi / 4)


def us_flag(B, x, y, z, h=9.0):
    B.cyl(0.22, 0.26, 0.3, (x, y, z), "concrete", segs=12)
    B.cyl(0.05, 0.08, h, (x, y, z + 0.3), "white", segs=10)
    B.ball(0.1, (x, y, z + h + 0.38), "gold", subdiv=1)
    B.marker("USFLAG", x, y, z, 0, h)


def bench(B, x, y, z, rz=0.0):
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
    for k in range(3):
        B.box((1.8, 0.12, 0.05), (0, -0.15 + k * 0.15, 0.46), "wood", matrix=m)
    for k in range(2):
        B.box((1.8, 0.05, 0.12), (0, -0.27, 0.62 + k * 0.17), "wood", rx=0.15, matrix=m)
    for s in (-0.78, 0.78):
        B.box((0.06, 0.5, 0.46), (s, 0, 0.23), "iron", matrix=m)


def umbrella_table(B, x, y, z, canopy="cloth_cream", cloth=False, chairs=4, r=0.5):
    B.cyl(0.05, 0.05, 0.72, (x, y, z), "iron", segs=6)
    B.cyl(r, r, 0.04, (x, y, z + 0.72), "cloth_white" if cloth else "white", segs=16)
    if cloth:
        B.cyl(r + 0.03, r + 0.1, 0.3, (x, y, z + 0.46), "cloth_white", segs=16)
    for i in range(chairs):
        a = i * math.tau / chairs + math.pi / 4
        chair(B, x + math.cos(a) * 0.8, y + math.sin(a) * 0.8, z, a + math.pi / 2)
    if canopy:
        B.cyl(0.03, 0.03, 2.3, (x, y, z + 0.74), "white", segs=6)
        B.cyl(1.45, 0.03, 0.5, (x, y, z + 2.55), canopy, segs=8, smooth=False)
        B.cyl(1.47, 1.47, 0.12, (x, y, z + 2.5), canopy, segs=8, smooth=False)


def chair(B, x, y, z, rz=0.0, mat="wood_dark", seat="wood_dark"):
    """A dining chair facing +Y: tapered legs with stretchers, a cushioned seat, a slatted back."""
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
    for kx, ky in ((-0.18, -0.18), (0.18, -0.18), (-0.18, 0.18), (0.18, 0.18)):
        B.cyl(0.022, 0.016, 0.43, (kx, ky, 0), mat, segs=8, matrix=m)
    for k in (-0.18, 0.18):
        B.box((0.02, 0.36, 0.02), (k, 0, 0.14), mat, matrix=m)
    B.box((0.44, 0.44, 0.04), (0, 0, 0.43), mat, bevel=0.012, matrix=m)
    B.box((0.4, 0.38, 0.05), (0, 0.015, 0.475), seat, bevel=0.02, matrix=m)
    for k in (-0.18, 0.18):
        B.cyl(0.018, 0.018, 0.52, (k, -0.19, 0.45), mat, segs=8, matrix=m)
    B.box((0.42, 0.035, 0.09), (0, -0.19, 0.93), mat, bevel=0.012, matrix=m)
    for i in range(3):
        B.box((0.045, 0.02, 0.34), (-0.1 + i * 0.1, -0.19, 0.71), mat, matrix=m)


def cart(B, x, y, z, rz=0.0, body="cart_green"):
    """A golf cart (the club's cart model, placed by Godot): front along -Y turned by rz."""
    B.marker("CART", x, y, z, rz + math.pi, 1.0)


def _cart_blocky(B, x, y, z, rz=0.0, body="cart_green"):
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
    B.box((1.2, 2.3, 0.48), (0, 0, 0.55), body, bevel=0.1, matrix=m)
    B.box((1.15, 0.7, 0.3), (0, 0.5, 0.92), "cloth_cream", bevel=0.06, matrix=m)
    B.box((1.15, 0.14, 0.55), (0, 0.88, 1.2), "cloth_cream", bevel=0.04, matrix=m)
    B.box((1.32, 1.95, 0.07), (0, 0.05, 2.0), "white", bevel=0.03, matrix=m)
    B.box((0.95, 0.55, 0.7), (0, 1.3, 0.95), "black", matrix=m)
    B.cyl(0.18, 0.18, 0.04, (-0.25, -0.35, 1.05), "black", segs=12, rx=0.6, matrix=m)
    for sx in (-0.58, 0.58):
        for sy in (-0.8, 0.85):
            B.cyl(0.025, 0.025, 1.1, (sx, sy, 0.9), "chrome", segs=5, matrix=m)
            B.cyl(0.24, 0.24, 0.17, (sx * 1.04, sy, 0.24), "rubber", segs=14, matrix=m, ry=math.pi / 2)


def parking_lines(B, x0, x1, y0, y1, z, every=2.7, along="x"):
    n = int(abs(x1 - x0) / every) if along == "x" else int(abs(y1 - y0) / every)
    for i in range(n + 1):
        if along == "x":
            x = x0 + i * every
            B.box((0.12, abs(y1 - y0), 0.01), (x, (y0 + y1) * 0.5, z + 0.045), "line")  # (on the asphalt: L.pave's top is z + 0.04)
        else:
            y = y0 + i * every
            B.box((abs(x1 - x0), 0.12, 0.01), ((x0 + x1) * 0.5, y, z + 0.045), "line")


def ring_drive(B, cx, cy, r_out, r_in, z, segs=48, mat="asphalt"):
    v, f = [], []
    for i in range(segs):
        a = math.tau * i / segs
        for r in (r_out, r_in):
            v.append((cx + math.cos(a) * r, cy + math.sin(a) * r, z + 0.04))
    n = len(v)
    for i in range(segs):
        a0, b0 = i * 2, i * 2 + 1
        a1, b1 = ((i + 1) % segs) * 2, ((i + 1) % segs) * 2 + 1
        f.append((a0, a1, b1, b0))
    for i in range(segs):
        a = math.tau * i / segs
        for r in (r_out, r_in):
            v.append((cx + math.cos(a) * r, cy + math.sin(a) * r, z - 0.02))
    for i in range(segs):
        a0, a1 = i * 2, ((i + 1) % segs) * 2
        f.append((a0 + n, a1 + n, a1, a0))
        b0, b1 = i * 2 + 1, ((i + 1) % segs) * 2 + 1
        f.append((b0, b1, b1 + n, b0 + n))
    B.poly(v, f, mat)
    # a kerb round the island; the island inside is the course's own grass
    annulus(B, cx, cy, r_in, r_in - 0.25, z - 0.04, z + 0.12, "concrete", segs)


def annulus(B, cx, cy, r_out, r_in, z0, z1, mat, segs=48):
    """A ring (a kerb, a planter's rim): top, outer and inner sides between z0 and z1."""
    v = []
    for zz in (z1, z0):
        for i in range(segs):
            a = math.tau * i / segs
            for r in (r_out, r_in):
                v.append((cx + math.cos(a) * r, cy + math.sin(a) * r, zz))
    n = segs * 2
    f = []
    for i in range(segs):
        a0, b0 = i * 2, i * 2 + 1
        a1, b1 = ((i + 1) % segs) * 2, ((i + 1) % segs) * 2 + 1
        f.append((a0, a1, b1, b0))  # top
        f.append((a0 + n, a1 + n, a1, a0))  # outer side
        f.append((b0, b1, b1 + n, b0 + n))  # inner side
    B.poly(v, f, mat)


def fountain(B, x, y, z):
    B.cyl(3.0, 3.1, 0.6, (x, y, z), "stone", segs=32)
    B.cyl(2.75, 2.75, 0.08, (x, y, z + 0.45), "water", segs=32)
    B.cyl(0.45, 0.6, 1.6, (x, y, z + 0.5), "stone", segs=16)
    B.cyl(1.4, 0.5, 0.35, (x, y, z + 2.0), "stone", segs=24)
    B.cyl(1.25, 1.25, 0.06, (x, y, z + 2.28), "water", segs=24)
    B.cyl(0.18, 0.25, 0.9, (x, y, z + 2.3), "stone", segs=12)
    B.cyl(0.6, 0.25, 0.22, (x, y, z + 3.15), "stone", segs=16)
    B.cyl(0.08, 0.02, 0.8, (x, y, z + 3.35), "water", segs=8)


def tires(B, x, y, z, n=4):
    for i in range(n):
        B.cyl(0.36, 0.36, 0.24, (x, y, z + i * 0.25), "rubber", segs=14)
        B.cyl(0.18, 0.18, 0.26, (x, y, z + i * 0.25 - 0.01), "black", segs=10)


def pallet(B, x, y, z, rz=0.0):
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
    for k in range(3):
        B.box((1.2, 0.12, 0.1), (0, -0.5 + k * 0.5, 0.05), "pallet", matrix=m)
    for k in range(7):
        B.box((0.14, 1.2, 0.03), (-0.54 + k * 0.18, 0, 0.12), "pallet", matrix=m)


# ---------------------------------------------------------------- furniture

def counter(B, x, y, z, w, d=0.7, h=1.0, top="wood_dark", body="wood", rz=0.0):
    """A counter: recessed toe-kick, a body with raised panels on both long faces, an overhanging
    top with a rounded edge."""
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
    B.box((w - 0.1, d - 0.1, 0.1), (0, 0, 0.05), "charcoal", matrix=m)
    B.box((w, d, h - 0.15), (0, 0, 0.1 + (h - 0.15) * 0.5), body, matrix=m, bevel=0.015)
    n = max(int(w / 0.6), 1)
    panel = "wood_dark" if body in ("wood", "wood_light") else body
    for side in (-1, 1):
        for i in range(n):
            px = -w * 0.5 + (i + 0.5) * w / n
            B.box((w / n - 0.1, 0.02, h - 0.4), (px, side * (d * 0.5 + 0.008), 0.1 + (h - 0.15) * 0.5), panel, bevel=0.006, matrix=m)
    B.box((w + 0.06, d + 0.06, 0.05), (0, 0, h - 0.025), top, bevel=0.012, matrix=m)


def shelf_unit(B, x, y, z, w, h=2.0, d=0.45, rz=0.0, goods=("cloth_navy", "cloth_white", "cloth_green", "cloth_red", "cloth_tan"), seed=0, books=False):
    """Open shelving with a plinth and a crown, stocked with piles of folded shirts and shoe
    boxes (or, `books`, rows of book spines in the `goods` colours)."""
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
    B.box((w, 0.03, h), (0, -d * 0.5 + 0.015, h * 0.5), "wood", matrix=m)
    for s2 in (-1, 1):
        B.box((0.04, d, h), (s2 * w * 0.5, 0, h * 0.5), "wood", bevel=0.008, matrix=m)
    B.box((w + 0.02, d + 0.02, 0.1), (0, 0, 0.05), "wood_dark", matrix=m)
    B.box((w + 0.08, d + 0.06, 0.06), (0, 0.01, h + 0.03), "wood_dark", bevel=0.012, matrix=m)
    n = 4
    for k in range(n + 1):
        zs = 0.12 + k * (h - 0.22) / n
        B.box((w - 0.04, d - 0.02, 0.028), (0, 0.0, zs), "wood", bevel=0.005, matrix=m)
        if k == n:
            break
        if books:
            bx = -w * 0.5 + 0.05
            i = 0
            while bx < w * 0.5 - 0.08:
                bw = 0.03 + ((i * 7 + k * 3 + seed) % 5) * 0.008
                bh = (h - 0.22) / n * (0.62 + ((i * 3 + k + seed) % 4) * 0.07)
                lean = 0.18 if (i + k + seed) % 11 == 0 else 0.0
                B.box((bw, d * 0.7, bh), (bx + bw * 0.5, 0.02, zs + 0.015 + bh * 0.5), goods[(i + k + seed) % len(goods)], ry=lean, matrix=m)
                bx += bw + 0.004
                i += 1
            continue
        slots = max(int(w / 0.34), 1)
        for i in range(slots):
            gx = -w * 0.5 + (i + 0.5) * w / slots
            col = goods[(i + k + seed) % len(goods)]
            if (i + k + seed) % 4 == 3:  # a shoe box or two
                B.box((w / slots * 0.7, d * 0.6, 0.12), (gx, 0.02, zs + 0.075), "cloth_tan" if col != "cloth_tan" else "white", bevel=0.004, matrix=m)
                continue
            fold_marker(B, m, (gx, 0.02, zs + 0.015), i + k + seed, w / slots * 0.86)


def clothes_rack(B, x, y, z, w=1.4, rz=0.0, cols=None, seed=0):
    """A garment rail of shirts: one of the club's two clothes rack models (placed by Godot)."""
    B.marker("RACK_" + "AB"[seed % 2], x, y, z, rz, 1.0)


def display_case(B, x, y, z, w=1.2, d=0.6, h=1.0, rz=0.0, items="gold"):
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
    B.box((w, d, h * 0.6), (0, 0, h * 0.3), "wood_dark", matrix=m)
    B.box((w - 0.04, d - 0.04, h * 0.4), (0, 0, h * 0.8), "glass", matrix=m)
    B.box((w, d, 0.03), (0, 0, h), "chrome", matrix=m)
    for i in range(3):
        B.ball(0.07, (-w * 0.3 + i * w * 0.3, 0, h * 0.68), items, subdiv=1, matrix=m)


def club_marker(B, family, m, local, yaw=0.0):
    """Where a real club from the game's catalog stands (grip end at the point, head up, face
    turned by yaw); Godot builds the club with OFGEquipmentAssets.create_club()."""
    p = m @ Vector(local)
    B.marker("CLUB_" + family, p.x, p.y, p.z, m.to_euler().z + yaw, 1.0)


def club_wall(B, x, y, z, w=3.0, rz=0.0):
    """A wall rack of drivers, fairways and hybrids standing on a ledge, heads up."""
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
    B.box((w, 0.06, 2.0), (0, -0.2, 1.3), "wood_dark", matrix=m)
    B.box((w, 0.3, 0.06), (0, -0.05, 0.3), "wood_dark", matrix=m)
    n = max(int(w / 0.22), 1)
    fams = ("driver", "fairway", "hybrid")
    for i in range(n):
        club_marker(B, fams[(i * len(fams)) // n], m, (-w * 0.5 + (i + 0.5) * w / n, -0.08, 0.33))


def bag_marker(B, m, local, yaw=0.0):
    """Where one of the club's golf bags stands (the cleaned bag models, placed by Godot): its
    pockets face local +Y turned by yaw."""
    p = m @ Vector(local)
    B.marker("BAG", p.x, p.y, p.z, m.to_euler().z + yaw + math.pi, 1.0)


def bag_stand(B, x, y, z, col="cloth_navy", rz=0.0):
    """A golf bag standing on a small rubber mat."""
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
    B.box((0.5, 0.5, 0.02), (0, 0, 0.01), "black", matrix=m)
    bag_marker(B, m, (0, 0, 0.02))


def mannequin(B, x, y, z, shirt=None, rz=0.0, seed=0):
    """A dressed display mannequin (the club's mannequin models, placed by Godot), facing +Y."""
    B.marker("MANNEQUIN_" + "MF"[seed % 2], x, y, z, rz + math.pi, 1.0)


def table(B, x, y, z, w=1.2, d=0.8, h=0.74, top="wood_dark", rz=0.0, cloth=False):
    """A table: a top with a rounded edge over an apron, tapered legs (or a cloth to the floor)."""
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
    B.box((w, d, 0.045), (0, 0, h - 0.022), top, bevel=0.012, matrix=m)
    B.box((w - 0.14, d - 0.14, 0.08), (0, 0, h - 0.085), top, matrix=m)
    for sx in (-1, 1):
        for sy in (-1, 1):
            B.cyl(0.03, 0.02, h - 0.045, (sx * (w * 0.5 - 0.08), sy * (d * 0.5 - 0.08), 0), top, segs=8, matrix=m)
    if cloth:
        B.box((w + 0.08, d + 0.08, 0.012), (0, 0, h + 0.006), "cloth_white", matrix=m)
        B.box((w + 0.1, d + 0.1, 0.32), (0, 0, h - 0.16), "cloth_white", bevel=0.02, matrix=m)


def round_table(B, x, y, z, r=0.8, cloth=True, chairs=6, chair_mat="wood_dark", seat="cloth_red"):
    """A round dining table on a pedestal, laid for its chairs (plate, glass, napkin) with a
    small flower centrepiece."""
    B.cyl(0.3, 0.34, 0.035, (x, y, z), "iron", segs=16)
    B.cyl(0.05, 0.06, 0.7, (x, y, z), "iron", segs=10)
    B.cyl(r, r, 0.04, (x, y, z + 0.7), "cloth_white" if cloth else "wood_dark", segs=28)
    if cloth:
        B.cyl(r + 0.03, r + 0.14, 0.52, (x, y, z + 0.2), "cloth_white", segs=28)
    for i in range(chairs):
        a = math.tau * i / chairs
        ca, sa = math.cos(a), math.sin(a)
        px, py = x + ca * (r - 0.2), y + sa * (r - 0.2)
        B.cyl(0.12, 0.11, 0.012, (px, py, z + 0.74), "porcelain", segs=16)
        B.cyl(0.032, 0.025, 0.13, (px - sa * 0.17 + ca * 0.06, py + ca * 0.17 + sa * 0.06, z + 0.74), "glass", segs=8)
        B.box((0.1, 0.16, 0.012), (px + sa * 0.17, py - ca * 0.17, z + 0.746), "cloth_red" if seat == "cloth_red" else "cloth_white", rz=a, matrix=None)
        chair(B, x + ca * (r + 0.45), y + sa * (r + 0.45), z, a + math.pi / 2, chair_mat, seat)
    B.cyl(0.06, 0.045, 0.16, (x, y, z + 0.74), "glass", segs=10)
    B.marker("PLANT_daisy_patch", x, y, z + 0.86, (x * 3.1 + y) % math.tau, 0.18)


def sofa(B, x, y, z, w=2.0, mat="leather", rz=0.0):
    """A sofa facing +Y: a frame on short feet, seat and back cushions, rolled arms."""
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
    for sx in (-1, 1):
        for sy in (-1, 1):
            B.cyl(0.03, 0.022, 0.1, (sx * (w * 0.5 - 0.1), sy * 0.34, 0), "wood_dark", segs=8, matrix=m)
    B.box((w, 0.86, 0.22), (0, 0, 0.21), mat, bevel=0.04, matrix=m)
    B.box((w - 0.1, 0.16, 0.6), (0, -0.35, 0.56), mat, bevel=0.05, matrix=m)
    n = max(int((w - 0.36) / 0.62), 1)
    cw = (w - 0.4) / n
    for i in range(n):
        px = -w * 0.5 + 0.2 + (i + 0.5) * cw
        B.box((cw - 0.02, 0.64, 0.15), (px, 0.07, 0.395), mat, bevel=0.055, matrix=m)
        B.box((cw - 0.03, 0.18, 0.42), (px, -0.23, 0.66), mat, rx=-0.16, bevel=0.07, matrix=m)
    for sx in (-1, 1):
        B.box((0.2, 0.86, 0.34), (sx * (w * 0.5 - 0.1), 0, 0.45), mat, bevel=0.05, matrix=m)
        B.cyl(0.11, 0.11, 0.86, (sx * (w * 0.5 - 0.1), -0.43, 0.62), mat, segs=12, rx=-math.pi / 2, matrix=m)


def armchair(B, x, y, z, mat="leather_green", rz=0.0):
    sofa(B, x, y, z, 0.95, mat, rz)


def rug(B, x0, y0, x1, y1, z, mat="carpet"):
    B.box((x1 - x0, y1 - y0, 0.02), ((x0 + x1) * 0.5, (y0 + y1) * 0.5, z + 0.05), mat)


def plant(B, x, y, z, h=1.4, pot="charcoal"):
    """A potted plant: a pot with a nature pack fern / hosta in it."""
    B.cyl(0.25, 0.2, 0.45, (x, y, z), pot, segs=12)
    B.cyl(0.22, 0.22, 0.03, (x, y, z + 0.42), "mulch", segs=12)
    B.marker("PLANT_" + ("sword_fern_A", "hosta_A", "sword_fern_B")[int(abs(x * 3.7 + y)) % 3], x, y, z + 0.44, (x + y) % math.tau, 0.55 * h / 1.4)


def imac(B, x, y, z, rz=0.0):
    """The user's iMac -- monitor, keyboard and mouse (tools/blender/import_office_props.py,
    placed by Godot) -- standing on a top at z, its screen toward local +Y turned by rz."""
    B.marker("IMAC", x, y, z, rz, 1.0)


def pos_terminal(B, x, y, z, rz=0.0):
    """The user's till: a cash drawer with a touchscreen on an arm (placed by Godot), on a top
    at z, its screen toward local +Y turned by rz."""
    B.marker("POS", x, y, z, rz, 1.0)


def desk(B, x, y, z, w=1.6, rz=0.0, monitor=True, top="wood_dark"):
    """An office desk: a drawer pedestal, a modesty panel, the iMac and a desk lamp."""
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
    B.box((w, 0.75, 0.045), (0, 0, 0.74), top, bevel=0.01, matrix=m)
    B.box((0.05, 0.7, 0.72), (-(w * 0.5 - 0.03), 0, 0.36), top, matrix=m)
    B.box((0.45, 0.7, 0.72), (w * 0.5 - 0.24, 0, 0.36), top, bevel=0.008, matrix=m)
    for k in range(3):
        B.box((0.4, 0.02, 0.19), (w * 0.5 - 0.24, -0.355, 0.13 + k * 0.22), "wood", bevel=0.005, matrix=m)
        B.box((0.1, 0.02, 0.015), (w * 0.5 - 0.24, -0.37, 0.18 + k * 0.22), "brass", matrix=m)
    B.box((w - 0.55, 0.025, 0.45), (-0.24, 0.33, 0.46), top, matrix=m)
    if monitor:  # facing whoever sits at the desk (local -Y)
        p = m @ Vector((0.0, 0.02, 0.765))
        imac(B, p.x, p.y, p.z, rz + math.pi)
    B.cyl(0.07, 0.07, 0.02, (-w * 0.5 + 0.18, 0.2, 0.765), "brass", segs=12, matrix=m)
    B.cyl(0.012, 0.012, 0.36, (-w * 0.5 + 0.18, 0.2, 0.78), "brass", segs=6, matrix=m)
    B.cyl(0.12, 0.05, 0.12, (-w * 0.5 + 0.18, 0.2, 1.08), "cloth_cream", segs=12, matrix=m)


def office_chair(B, x, y, z, rz=0.0):
    """A swivel chair facing +Y: a five-star base on casters, a gas lift, armrests."""
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
    for i in range(5):
        a = math.tau * i / 5
        B.box((0.3, 0.04, 0.03), (math.cos(a) * 0.15, math.sin(a) * 0.15, 0.07), "black", rz=a, matrix=m)
        B.ball(0.025, (math.cos(a) * 0.29, math.sin(a) * 0.29, 0.03), "black", subdiv=1, matrix=m)
    B.cyl(0.025, 0.025, 0.36, (0, 0, 0.08), "chrome", segs=8, matrix=m)
    B.box((0.5, 0.48, 0.08), (0, 0.02, 0.48), "black", bevel=0.03, matrix=m)
    B.box((0.46, 0.07, 0.52), (0, -0.22, 0.8), "black", rx=-0.12, bevel=0.03, matrix=m)
    for sx in (-1, 1):
        B.box((0.04, 0.04, 0.2), (sx * 0.24, 0.02, 0.6), "black", matrix=m)
        B.box((0.06, 0.28, 0.03), (sx * 0.24, 0.04, 0.7), "black", bevel=0.01, matrix=m)


def bookshelf(B, x, y, z, w=1.6, h=2.2, rz=0.0, seed=0):
    shelf_unit(B, x, y, z, w, h, 0.35, rz, ("cloth_red", "cloth_navy", "cloth_green", "leather", "cloth_tan"), seed, books=True)


def lockers(B, x, y, z, w, rz=0.0, mat="wood", h=1.9):
    """A bank of lockers facing +Y: panelled doors with vents and handles (no bench of its own: the
    room's benches stand out in the middle, clear of the doors)."""
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
    n = max(int(w / 0.45), 1)
    B.box((w, 0.5, 0.1), (0, 0, 0.05), "charcoal", matrix=m)
    B.box((w + 0.04, 0.54, 0.05), (0, 0, h + 0.025), mat, bevel=0.01, matrix=m)
    for i in range(n):
        px = -w * 0.5 + (i + 0.5) * w / n
        B.box((w / n - 0.015, 0.5, h - 0.1), (px, 0, 0.1 + (h - 0.1) * 0.5), mat, bevel=0.006, matrix=m)
        B.box((w / n - 0.09, 0.02, h - 0.5), (px, 0.255, 0.1 + (h - 0.1) * 0.5), "wood_dark" if mat == "wood" else mat, bevel=0.005, matrix=m)
        for k in range(4):
            B.box((w / n * 0.5, 0.025, 0.012), (px, 0.26, h - 0.18 - k * 0.04), "charcoal", matrix=m)
        B.box((0.02, 0.03, 0.12), (px + w / n * 0.33, 0.27, 1.05), "brass", matrix=m)


def toilet_stall(B, x, y, z, rz=0.0):
    """A toilet stall, 1 m wide and 1.5 m deep against a wall (behind at local -Y, turned by rz):
    its partitions either side clear of the floor, its door across the front and, against the
    back, the user's toilet (props/toilet.glb, placed by Godot at its TOILET marker) facing out."""
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
    for s in (-1, 1):
        B.box((0.04, 1.52, 1.8), (s * 0.5, 0.01, 1.05), "grey", matrix=m)
    # the door across the front, closing it right up to both partitions (no gaps either side), the
    # same height as them, with a headrail over the lot and a latch
    B.box((0.98, 0.04, 1.8), (0, 0.75, 1.05), "grey", matrix=m)
    B.box((1.04, 0.05, 0.05), (0, 0.76, 1.975), "chrome", matrix=m)
    B.box((0.04, 0.05, 0.1), (0.38, 0.79, 1.0), "chrome", matrix=m)
    at = m @ Vector((0, -0.75 + 0.42, 0))
    B.marker("TOILET", at.x, at.y, z, rz)


def shower_stalls(B, x, y, z, w, n, rz=0.0, d=1.05, h=2.1):
    """A bank of `n` shower stalls `w` wide against a wall (behind at local -Y, turned by rz),
    centred on x: tiled back and partitions, a white tray behind a tiled curb, a chrome rain head,
    riser and mixer in each, and a chrome-railed glass door across its front."""
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
    sw = w / n
    B.box((w, 0.05, h), (0, 0.025, h * 0.5), "tile", matrix=m)
    for i in range(n + 1):
        B.box((0.07, d, h), (-w * 0.5 + i * sw, d * 0.5, h * 0.5), "tile", matrix=m)
    for i in range(n):
        px = -w * 0.5 + (i + 0.5) * sw
        B.box((sw - 0.08, d - 0.06, 0.04), (px, d * 0.5, 0.02), "white", matrix=m)
        B.box((sw - 0.08, 0.06, 0.09), (px, d - 0.03, 0.045), "tile", matrix=m)
        B.cyl(0.012, 0.012, 0.35, (px, 0.07, 1.75), "chrome", segs=6, matrix=m)
        B.box((0.035, 0.26, 0.03), (px, 0.19, 2.1), "chrome", matrix=m)
        B.cyl(0.11, 0.11, 0.02, (px, 0.31, 2.06), "chrome", segs=18, matrix=m)
        B.cyl(0.045, 0.045, 0.04, (px, 0.05, 1.1), "chrome", segs=12, rx=-math.pi / 2, matrix=m)
        B.box((sw - 0.16, 0.025, 1.9), (px, d - 0.02, 1.04), "glass", matrix=m)
        B.box((sw - 0.1, 0.045, 0.04), (px, d - 0.02, 2.0), "chrome", matrix=m)
        B.box((0.02, 0.05, 0.35), (px + sw * 0.3, d + 0.02, 1.05), "chrome", matrix=m)


def spa_cabin(B, x, y, z, kind, rz=0.0, w=1.9, d=1.6, h=2.2):
    """A walk-in sauna ("SAUNA": cedar inside and out, two tiers of slatted benches along its back,
    a stove of hot stones in the front corner, a pail and ladle) or steam room ("STEAM": tiled
    through, a tiled bench round its back and one side, the steam outlet low on the other wall),
    `w` wide and `d` deep: its front on the local +Y side (turned by rz), a clear glass door on
    its frame toward one end and, well along from it, a small clear window; the name on a board
    over the door."""
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
    sauna = kind == "SAUNA"
    skin = "wood_light" if sauna else "tile"
    frame = "wood_dark" if sauna else "chrome"
    t, hw, hd = 0.08, w * 0.5, d * 0.5
    fy = hd - t * 0.5  # the front wall's middle
    B.box((w, d, 0.04), (0, 0, 0.02), "wood" if sauna else "tile", matrix=m)
    B.box((w, t, h), (0, -hd + t * 0.5, h * 0.5), skin, matrix=m)
    for s in (-1, 1):
        B.box((t, d - t, h), (s * (hw - t * 0.5), t * 0.5, h * 0.5), skin, matrix=m)
    B.box((w, d, t), (0, 0, h - t * 0.5), skin, matrix=m)
    B.box((w + 0.06, d + 0.06, 0.06), (0, 0, h + 0.03), "wood_dark" if sauna else "trim", bevel=0.01, matrix=m)
    # the front: the door toward the +x end, the window at the far end, plain wall between
    dw, dh = 0.72, 2.0
    dx = hw - t - 0.08 - dw * 0.5
    ww, wh, wz = 0.3, 0.34, 1.5
    wx = -hw + t + 0.14 + ww * 0.5
    spans = [(-hw + t, wx - ww * 0.5, 0.0, h), (wx + ww * 0.5, dx - dw * 0.5, 0.0, h), (dx + dw * 0.5, hw - t, 0.0, h),
             (wx - ww * 0.5, wx + ww * 0.5, 0.0, wz - wh * 0.5), (wx - ww * 0.5, wx + ww * 0.5, wz + wh * 0.5, h),
             (dx - dw * 0.5, dx + dw * 0.5, dh, h)]
    for a, b, lo, hi in spans:
        if b - a > 0.005 and hi - lo > 0.005:
            B.box((b - a, t, hi - lo), ((a + b) * 0.5, fy, (lo + hi) * 0.5), skin, matrix=m)
    # the door: its frame round the opening, the clear glass leaf in it and a bar handle
    for px, pw in ((dx - dw * 0.5 + 0.025, 0.05), (dx + dw * 0.5 - 0.025, 0.05)):
        B.box((pw, t + 0.02, dh), (px, fy, dh * 0.5), frame, matrix=m)
    B.box((dw, t + 0.02, 0.05), (dx, fy, dh - 0.025), frame, matrix=m)
    B.box((dw - 0.1, 0.02, dh - 0.08), (dx, fy, (dh - 0.05) * 0.5 + 0.02), "entry_glass", matrix=m)
    B.box((0.03, 0.05, 0.42), (dx - dw * 0.5 + 0.12, hd + 0.04, 1.05), frame, matrix=m)
    # the window: a small clear pane in its frame
    for (px, pz, sx, sz) in ((wx, wz - wh * 0.5 + 0.02, ww, 0.04), (wx, wz + wh * 0.5 - 0.02, ww, 0.04),
                             (wx - ww * 0.5 + 0.02, wz, 0.04, wh), (wx + ww * 0.5 - 0.02, wz, 0.04, wh)):
        B.box((sx, t + 0.02, sz), (px, fy, pz), frame, matrix=m)
    B.box((ww - 0.06, 0.02, wh - 0.06), (wx, fy, wz), "entry_glass", matrix=m)
    # the name over the door
    B.box((dw + 0.1, 0.03, 0.14), (dx, hd + 0.015, 2.11), "sign_green", matrix=m)
    p = m @ Vector((dx, hd + 0.035, 2.11))
    B.text(kind, "+y" if math.cos(rz) > 0 else "-y", (p.x, p.y, p.z), 0.1, "white", 0.01)
    inner = w - 2 * t
    back = -hd + t
    if sauna:
        # two tiers of slatted cedar benches along the back, each with a board down its front
        for top, y0, y1 in ((0.92, back, back + 0.52), (0.48, back + 0.52, back + 1.0)):
            n = 5
            for k in range(n):
                sy = y0 + (k + 0.5) * (y1 - y0) / n
                B.box((inner, (y1 - y0) / n - 0.015, 0.04), (0, sy, top - 0.02), "wood", matrix=m)
            B.box((inner, 0.03, top - 0.04), (0, y1 - 0.015, (top - 0.04) * 0.5), "wood_dark", matrix=m)
        B.box((inner, 0.52, 0.44), (0, back + 0.26, 0.48 + 0.22), "wood_light", matrix=m)  # (under the top tier)
        # the stove in the front corner by the window: a black box of hot stones, a cedar guard
        sx, sy = -hw + t + 0.26, hd - t - 0.26
        B.box((0.36, 0.36, 0.5), (sx, sy, 0.25), "charcoal", matrix=m, bevel=0.02)
        for k in range(9):
            B.ball(0.045, (sx - 0.1 + (k % 3) * 0.1, sy - 0.1 + (k // 3) * 0.1, 0.53 + 0.02 * (k % 2)), "stone_grey", subdiv=1, matrix=m)
        for k in range(3):
            B.box((0.03, 0.46, 0.05), (sx + 0.24, sy, 0.2 + k * 0.18), "wood", matrix=m)
        # the pail and its ladle on the lower bench, by the door
        px, py = hw - t - 0.25, back + 0.78
        B.cyl(0.1, 0.085, 0.18, (px, py, 0.48), "wood", segs=12, matrix=m)
        B.cyl(0.012, 0.012, 0.45, (px - 0.06, py, 0.62), "wood_dark", segs=6, ry=0.6, matrix=m)
        B.box((0.16, 0.06, 0.08), (0, back + 0.02, 1.85), "bulb", matrix=m)  # a lamp on the back wall
    else:
        # a tiled bench round the back and down the window's side, the steam outlet on the other
        B.box((inner, 0.48, 0.46), (0, back + 0.24, 0.23), "tile", matrix=m)
        B.box((0.48, d - 2 * t - 0.48 - 0.5, 0.46), (-hw + t + 0.24, back + 0.48 + (d - 2 * t - 0.48 - 0.5) * 0.5, 0.23), "tile", matrix=m)
        B.box((inner + 0.02, 0.5, 0.03), (0, back + 0.25, 0.475), "white", matrix=m)
        B.box((0.06, 0.16, 0.1), (hw - t - 0.03, 0.0, 0.35), "chrome", matrix=m)
        B.cyl(0.12, 0.12, 0.02, (0, 0, h - t - 0.01), "bulb", segs=16, matrix=m)

def locker_bench(B, x, y, z, w, rz=0.0):
    """A locker-room bench: a padded leather top on a dark rail and chrome legs."""
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
    B.box((w, 0.42, 0.08), (0, 0, 0.44), "leather", bevel=0.02, matrix=m)
    B.box((w - 0.05, 0.36, 0.04), (0, 0, 0.38), "wood_dark", matrix=m)
    for s in (-1, 1):
        B.box((0.05, 0.34, 0.36), (s * (w * 0.5 - 0.15), 0, 0.18), "chrome", matrix=m)


def vanity(B, x, y, z, w=2.4, rz=0.0, lights=False):
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
    B.box((w, 0.55, 0.85), (0, 0, 0.425), "wood_dark", matrix=m)
    B.box((w + 0.04, 0.6, 0.05), (0, 0, 0.87), "stone", matrix=m)
    n = max(int(w / 0.8), 1)
    for i in range(n):
        px = -w * 0.5 + (i + 0.5) * w / n
        B.cyl(0.2, 0.17, 0.12, (px, 0.02, 0.78), "porcelain", segs=14, matrix=m)
        B.cyl(0.02, 0.02, 0.25, (px, -0.18, 0.9), "chrome", segs=6, matrix=m)
    B.box((w, 0.03, 1.0), (0, -0.27, 1.6), "mirror", matrix=m)
    if lights:
        for i in range(n + 1):
            B.ball(0.06, (-w * 0.5 + i * w / n, -0.24, 2.15), "bulb", subdiv=1, matrix=m)


def restaurant_wood_stool(B, x, y, z, rz=0.0):
    """User-supplied textured stool, placed by the game with its feet above the rug."""
    B.marker("RESTAURANT_STOOL", x, y, z + 0.065, rz, 1.0)


def bar_counter(B, x, y, z, w, rz=0.0, stools=True):
    """A bar: panelled front with a brass foot rail and a stone top; behind it a back bar with
    a mirror, lit shelves of bottles and glasses; swivel stools with back rings."""
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
    B.box((w, 0.6, 1.05), (0, 0, 0.525), "bar_oak", matrix=m, bevel=0.03)
    n = max(int(w / 0.7), 1)
    for i in range(n):
        B.box((w / n - 0.12, 0.02, 0.62), (-w * 0.5 + (i + 0.5) * w / n, 0.305, 0.55), "bar_oak", bevel=0.008, matrix=m)
    B.box((w + 0.1, 0.75, 0.06), (0, 0.05, 1.08), "bar_oak", bevel=0.015, matrix=m)
    p = m @ Vector((-w * 0.5 + 0.45, -1.18, 1.00))  # the till at one end, facing the bartender
    pos_terminal(B, p.x, p.y, p.z, rz)
    B.cyl(0.025, 0.025, w, (-w * 0.5, 0.42, 0.22), "brass", segs=8, ry=math.pi / 2, matrix=m)
    B.marker("BAR_POS",p.x,p.y,p.z,rz,1.0)
    # the back bar
    B.box((w, 0.45, 0.8), (0, -1.3, 0.4), "bar_oak", bevel=0.02, matrix=m)
    for sy in (-1.505,-1.095):
        B.box((w,.035,.95),(0,sy,.475),"bar_oak",matrix=m)
    sink_x = min(w*.2,w/2-.7)
    left,right = -w/2-.02,w/2+.02
    for start,end in ((left,sink_x-.32),(sink_x+.32,right)):
        B.box((end-start,.5,.04),((start+end)/2,-1.3,.97),"bar_oak",matrix=m)
    for sy in (-1.535,-1.065):
        B.box((.64,.03,.04),(sink_x,sy,.97),"bar_oak",matrix=m)
    # Brushed steel basin, rim, drain and an arched mixer tap.
    B.box((.60,.39,.025),(sink_x,-1.3,.83),"steel",bevel=.02,matrix=m)
    for sy in (-1.49,-1.11):
        B.box((.62,.025,.14),(sink_x,sy,.90),"steel",matrix=m)
    for sx in (-.30,.30):
        B.box((.025,.39,.14),(sink_x+sx,-1.3,.90),"steel",matrix=m)
    B.box((.55,.32,.012),(sink_x,-1.3,.85),"charcoal",matrix=m)
    B.cyl(.032,.032,.01,(sink_x,-1.3,.86),"chrome",segs=12,matrix=m)
    B.cyl(.018,.018,.25,(sink_x,-1.50,.99),"chrome",segs=10,matrix=m)
    B.cyl(.018,.018,.16,(sink_x,-1.50,1.24),"chrome",segs=10,rx=-math.pi/2,matrix=m)
    B.cyl(.025,.025,.05,(sink_x,-1.34,1.19),"chrome",segs=10,matrix=m)
    B.marker("BAR_SINK",*(m@Vector((sink_x,-1.3,.99))),rz,1.0)
    countertop_sets=[("DARK",w*.40),("CLEAR",-w*.22)] if w>=5 else [("DARK",-.20)]
    for kind,px in countertop_sets:
        B.box((.52,.26,.018),(px,-1.3,1.00),"bar_oak",bevel=.008,matrix=m)
        for sy in (-1.43,-1.17):
            B.box((.52,.012,.035),(px,sy,1.02),"brass",matrix=m)
        p=m@Vector((px,-1.3,1.01))
        B.marker("COUNTER_BOTTLES_"+kind,p.x,p.y,p.z,rz,1.0)
    # Supplied bar_with_bottles.glb: reusable UV-textured shelf modules.
    modules = max(1,round(w/1.73))
    module_w = w/modules
    for i in range(modules):
        p = m @ Vector((-w/2+(i+.5)*module_w,-1.48,1.45))
        B.marker("BAR_SHELF",p.x,p.y,p.z,rz,module_w)
    # Suspended stemware rack above the front counter. Rails cradle the feet
    # of the original asset's inverted wine glasses, above head height.
    for sy in (-.18,.28):
        B.box((w-.35,.035,.035),(0,sy,2.72),"bar_oak",matrix=m)
    for px in (-w/2+.3,w/2-.3):
        B.box((.035,.52,.035),(px,.05,2.72),"brass",matrix=m)
        B.box((.025,.025,.70),(px,.05,3.07),"brass",matrix=m)
    glass_count=max(4,int((w-.6)/.24))
    for i in range(glass_count):
        px=-w/2+.4+i*(w-.8)/max(1,glass_count-1)
        for sy in (-.07,.17):
            for side in (-1,1):
                B.box((.012,.20,.012),(px+side*.028,sy,2.68),"brass",matrix=m)
            p=m@Vector((px,sy,2.70))
            B.marker("HANGING_GLASS",p.x,p.y,p.z,rz,1.0)
    if stools:
        for i in range(int(w / 0.75)):
            px = -w * 0.5 + (i + 0.5) * w / int(w / 0.75)
            p = m @ Vector((px, 0.75, 0.0))
            B.marker("RESTAURANT_STOOL", p.x, p.y, p.z, rz + math.pi, 1.0)



def tv(B, x, y, z, w=1.4, rz=0.0, on=True, b=0.015):
    """A flat-screen TV centred on (x, y, z), its face toward local +Y: the body from y -0.03 to
    0.01, a thin bezel `b` round its front to 0.03, and a 16:9 screen (w - 2b across) set back
    inside the bezel, its face at 0.014 -- never standing proud of the frame. `on` False: no
    screen, the body's dark face inside the bezel (for a picture laid in there: TV_CLIP / TV_VIDEO
    markers). The set is (w - 2b) * 9 / 16 + 2b high (tv_height)."""
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
    h = tv_height(w, b)
    B.box((w, 0.04, h), (0, -0.01, 0), "tv", matrix=m)
    for sx, sz, px, pz in ((w, b, 0, (h - b) / 2), (w, b, 0, -(h - b) / 2), (b, h - 2 * b, (w - b) / 2, 0), (b, h - 2 * b, -(w - b) / 2, 0)):
        B.box((sx, 0.02, sz), (px, 0.02, pz), "tv", matrix=m)
    if on:
        B.box((w - 2 * b, 0.004, h - 2 * b), (0, 0.012, 0), "screen_green", matrix=m)


def tv_height(w, b=0.015):
    """How high a `w`-wide TV (bezel `b`) stands: its 16:9 screen and the bezel round it."""
    return (w - 2 * b) * 9.0 / 16.0 + 2 * b


def stove_line(B, x, y, z, w, rz=0.0):
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
    B.box((w, 0.8, 0.9), (0, 0, 0.45), "steel", matrix=m)
    n = int(w / 0.6)
    for i in range(n):
        px = -w * 0.5 + (i + 0.5) * w / n
        B.cyl(0.12, 0.12, 0.03, (px, 0.1, 0.9), "black", segs=12, matrix=m)
        B.box((0.4, 0.02, 0.3), (px, 0.41, 0.55), "black", matrix=m)
    B.box((w, 0.9, 0.5), (0, -0.05, 2.2), "steel", matrix=m)  # hood


def fridge(B, x, y, z, rz=0.0, w=0.9):
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
    B.box((w, 0.75, 2.0), (0, 0, 1.0), "steel", matrix=m, bevel=0.02)
    B.box((0.03, 0.04, 0.6), (w * 0.35, 0.39, 1.2), "chrome", matrix=m)


def prep_table(B, x, y, z, w=2.0, rz=0.0):
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
    B.box((w, 0.8, 0.04), (0, 0, 0.9), "steel", matrix=m)
    B.box((w - 0.1, 0.7, 0.03), (0, 0, 0.25), "steel", matrix=m)
    for sx in (-1, 1):
        for sy in (-1, 1):
            B.box((0.04, 0.04, 0.9), (sx * (w * 0.5 - 0.05), sy * 0.35, 0.45), "steel", matrix=m)


def trophy(B, x, y, z, s=1.0):
    B.box((0.16 * s, 0.16 * s, 0.08 * s), (x, y, z + 0.04 * s), "wood_dark")
    B.cyl(0.03 * s, 0.03 * s, 0.12 * s, (x, y, z + 0.08 * s), "gold", segs=6)
    B.cyl(0.03 * s, 0.11 * s, 0.16 * s, (x, y, z + 0.2 * s), "gold", segs=10)


def picture(B, x, y, z, w=0.7, h=0.5, facing="+y", mat="cloth_sky"):
    u, n = FACING[facing]
    F = frame_matrix(u, n, (x, y, z))
    B.fbox(F, (0, 0.02, 0), (w + 0.08, 0.04, h + 0.08), "gold")
    B.fbox(F, (0, 0.045, 0), (w, 0.01, h), mat)


def chandelier(B, x, y, z):
    B.cyl(0.015, 0.015, 0.8, (x, y, z - 0.8), "brass", segs=4)
    B.cyl(0.5, 0.35, 0.1, (x, y, z - 1.0), "brass", segs=12)
    for i in range(8):
        a = math.tau * i / 8
        B.ball(0.07, (x + math.cos(a) * 0.48, y + math.sin(a) * 0.48, z - 0.86), "bulb", subdiv=1)


def treadmill(B, x, y, z, rz=0.0):
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
    B.box((0.75, 1.8, 0.2), (0, 0, 0.1), "black", matrix=m, bevel=0.03)
    B.box((0.6, 1.6, 0.02), (0, 0, 0.21), "charcoal", matrix=m)
    for s in (-1, 1):
        B.box((0.05, 0.05, 1.2), (s * 0.35, 0.8, 0.7), "steel", matrix=m)
    B.box((0.75, 0.2, 0.3), (0, 0.85, 1.3), "black", matrix=m)
    B.box((0.3, 0.02, 0.2), (0, 0.74, 1.32), "screen", matrix=m)


def weight_rack(B, x, y, z, rz=0.0):
    """The gym's two-tier dumbbell rack (the user's model, tools/blender/import_dumbbells.py,
    placed by Godot): 2.1 m along local x, its front toward local +Y turned by rz."""
    B.marker("DUMBBELL_RACK", x, y, z, rz, 1.0)


def gym_piece(B, pid, x, y, z, rz=0.0):
    """One of the gym's machines (the user's models, tools/blender/import_gym.py: gym_<pid>.glb,
    placed by Godot), standing on z; its front -- the way its user faces -- toward local +Y
    turned by rz."""
    B.marker("GYM_" + pid, x, y, z, rz, 1.0)


def hot_tub(B, x, y, z, r=1.2):
    """Retained tier-three spa tub used by the clubhouse builder."""
    B.cyl(r, r, 0.85, (x, y, z), "wood_light", segs=20)
    B.cyl(r - 0.12, r - 0.12, 0.05, (x, y, z + 0.78), "water", segs=20)


def massage_table(B, x, y, z, rz=0.0):
    """The user's massage table (tools/blender/import_spa_props.py, placed by Godot): 0.7 x 2.0 m,
    its length along local Y turned by rz."""
    B.marker("MASSAGE_TABLE", x, y, z, rz, 1.0)


def jacuzzi(B, x, y, z, rz=0.0):
    """The user's hot tub (placed by Godot): a 2.28 m square, wood-clad, 0.95 m to the rim."""
    B.marker("JACUZZI", x, y, z, rz, 1.0)


def sim_bay(B, x, y, z, w=4.0, rz=0.0):
    """Golf simulator: impact screen, hitting mat, launch monitor, side nets."""
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
    B.box((w, 0.08, 2.8), (0, -2.2, 1.5), "black", matrix=m)
    # Keep the supplied 16:9 image undistorted, with dark padding above and below.
    image_h = min(2.7, w * 9.0 / 16.0)
    image_w = image_h * 16.0 / 9.0
    B.image_quad([(image_w / 2, -2.149, 1.5 - image_h / 2),
                  (-image_w / 2, -2.149, 1.5 - image_h / 2),
                  (-image_w / 2, -2.149, 1.5 + image_h / 2),
                  (image_w / 2, -2.149, 1.5 + image_h / 2)], "simulator_screen", matrix=m)
    B.box((w + 0.2, 0.2, 0.2), (0, -2.2, 3.0), "black", matrix=m)
    for s in (-1, 1):
        B.box((0.05, 3.0, 3.0), (s * w * 0.5, -0.8, 1.5), "net", matrix=m)
    B.box((1.5, 1.5, 0.04), (0, 0.6, 0.02), "mat_green", matrix=m)
    B.box((w * 0.9, 3.0, 0.02), (0, -0.8, 0.01), "turf", matrix=m)
    B.box((0.25, 0.2, 0.15), (0.9, 0.2, 0.1), "black", matrix=m)


def stage(B, x0, y0, x1, y1, z, h=0.6):
    B.box((x1 - x0, y1 - y0, h), ((x0 + x1) * 0.5, (y0 + y1) * 0.5, z + h * 0.5), "wood_dark")
    B.box((x1 - x0, 0.06, h), ((x0 + x1) * 0.5, y1, z + h * 0.5), "brass")


def fireplace(B, x, y, z, facing="+y", w=1.8):
    u, n = FACING[facing]
    F = frame_matrix(u, n, (x, y, z))
    B.fbox(F, (0, 0.25, 0.75), (w, 0.5, 1.5), "brick")
    B.fbox(F, (0, 0.45, 0.45), (w * 0.5, 0.15, 0.7), "black")
    B.fbox(F, (0, 0.45, 0.25), (w * 0.4, 0.1, 0.18), "fire")
    B.fbox(F, (0, 0.55, 1.55), (w + 0.3, 0.6, 0.12), "wood_dark")


# ---------------------------------------------------------------- yard & modern kit

def ground_text(B, body, x, y, z, size, mat="line", rz=0.0):
    """Paint on the ground, readable from above (from the +Y side when rz = 0)."""
    cu = bpy.data.curves.new("gtxt", "FONT")
    cu.body = body
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    cu.size = size
    cu.extrude = 0.005
    ob = bpy.data.objects.new("gtxt", cu)
    bpy.context.scene.collection.objects.link(ob)
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = ev.to_mesh()
    src = bmesh.new()
    src.from_mesh(me)
    ev.to_mesh_clear()
    bpy.data.objects.remove(ob)
    bpy.data.curves.remove(cu)
    B.append(src, Matrix.Translation((x, y, z + 0.012)) @ Matrix.Rotation(rz + math.pi, 4, "Z"), mat)


def arrow(B, x, y, z, rz=0.0, mat="line", s=1.0):
    m = Matrix.Translation((x, y, z + 0.012)) @ Matrix.Rotation(rz, 4, "Z")
    B.box((0.3 * s, 1.6 * s, 0.01), (0, -0.4 * s, 0), mat, matrix=m)
    v = [(-0.6 * s, 0.4 * s, 0), (0.6 * s, 0.4 * s, 0), (0, 1.3 * s, 0)]
    B.poly([tuple(m @ Vector(p)) for p in v], [(0, 1, 2)], mat)


def chainlink(B, p0, p1, z, h=2.2, every=3.0):
    a, b = Vector((p0[0], p0[1], 0)), Vector((p1[0], p1[1], 0))
    d = b - a
    ln = d.length
    ang = math.atan2(d.y, d.x)
    n = max(int(ln / every), 1)
    for i in range(n + 1):
        p = a + d * (i / n)
        B.cyl(0.05, 0.05, h, (p.x, p.y, z), "steel", segs=8)
    mid = (a + b) * 0.5
    B.box((ln, 0.06, 0.06), (mid.x, mid.y, z + h - 0.05), "steel", rz=ang)
    B.box((ln, 0.02, h - 0.1), (mid.x, mid.y, z + h * 0.5), "net", rz=ang)


def transformer(B, x, y, z, rz=0.0):
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
    B.box((1.6, 1.2, 0.15), (0, 0, 0.075), "concrete", matrix=m)
    B.box((1.3, 0.95, 1.4), (0, 0, 0.85), "electric", matrix=m, bevel=0.03)
    for i in range(6):
        B.box((0.04, 1.05, 1.1), (-0.55 + i * 0.22, 0, 0.8), "electric", matrix=m)
    B.box((0.5, 0.2, 0.6), (0.4, 0.58, 1.0), "electric", matrix=m)
    B.box((0.25, 0.03, 0.15), (0.4, 0.69, 1.3), "line_yellow", matrix=m)


def wall_charger(B, x, y, z, rz=0.0):
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
    B.box((0.32, 0.14, 0.45), (0, 0, 1.35), "white", matrix=m, bevel=0.03)
    B.box((0.14, 0.02, 0.05), (0, 0.08, 1.45), "screen_green", matrix=m)
    B.cyl(0.015, 0.015, 1.0, (0.1, 0.05, 0.35), "black", segs=5, matrix=m)


def hose_reel(B, x, y, z, rz=0.0):
    """A hose reel on an outside wall (its face at local y 0, out toward local +Y, turned by rz;
    z the floor at its foot): a steel backplate on two brackets holding the drum, wound with green
    hose, between side discs on an axle with a crank; the water pipe up the wall into it and a
    hook under it. Markers: HOSE_REEL where the hose comes off the drum, HOSE_HOOK where its end
    and nozzle hang up (ClubLife draws those, and the hose out to the cart boy's hand)."""
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
    hy, hz = 0.27, 1.12  # (the drum's axle: out from the wall, up)
    B.box((0.42, 0.03, 0.46), (0, 0.015, hz), "steel", bevel=0.008, matrix=m)
    for sx in (-1, 1):
        B.box((0.03, hy, 0.06), (sx * 0.185, hy * 0.5, hz), "steel", matrix=m)
        B.cyl(0.25, 0.25, 0.02, (sx * 0.17 - 0.01, hy, hz), "steel", segs=20, ry=math.pi / 2, matrix=m)
    B.cyl(0.17, 0.17, 0.32, (-0.16, hy, hz), "hose_green", segs=20, ry=math.pi / 2, matrix=m)  # (the hose wound on it)
    for k in range(4):  # (its turns)
        B.cyl(0.176, 0.176, 0.012, (-0.13 + k * 0.08, hy, hz), "leaf", segs=20, ry=math.pi / 2, matrix=m)
    B.cyl(0.02, 0.02, 0.44, (-0.22, hy, hz), "chrome", segs=8, ry=math.pi / 2, matrix=m)
    B.box((0.02, 0.025, 0.17), (0.235, hy, hz + 0.08), "steel", matrix=m)  # the crank
    B.cyl(0.018, 0.018, 0.08, (0.235, hy, hz + 0.16), "black", segs=8, ry=math.pi / 2, matrix=m)
    B.cyl(0.016, 0.016, hz - 0.3, (-0.12, 0.035, 0.0), "brass", segs=8, matrix=m)  # the water pipe in
    B.box((0.08, 0.03, 0.02), (-0.12, 0.07, 0.55), "brass", matrix=m)  # (its tap)
    B.box((0.04, 0.16, 0.035), (0.0, 0.08, 0.72), "steel", matrix=m)  # the hook
    B.box((0.04, 0.035, 0.07), (0.0, 0.15, 0.75), "steel", matrix=m)
    for kind, lx, ly, lz in (("HOSE_REEL", 0.0, hy + 0.12, hz - 0.12), ("HOSE_HOOK", 0.0, 0.13, 0.76)):
        at = m @ Vector((lx, ly, lz))
        B.marker(kind, at.x, at.y, at.z, rz)


def clock_pole(B, x, y, z, rz=0.0):
    """A golf club's street clock (the user's reference) on its lawn, about 6 m to its finial, in
    dark green cast iron trimmed in gold: a square pedestal, its faces panelled, under a sloped
    cap; a column -- plain below a gold collar, fluted above it -- up to a flared, leafed capital;
    and on top a drum clock, read from both ways (local +Y and -Y, turned by rz), its cream dials
    ringed in gold with their hour marks, under a scrolled crest with a gold roundel and finial.
    A CLOCK_FACE marker at each dial's middle, facing out of it: Godot puts its hands there and
    keeps them to the club's time (ClubLife). A KEEPOUT marker keeps people a step off it."""
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
    iron, dark, gold = "sign_green", "iron", "gold"
    # the pedestal: plinth, block, panels on its four faces, cornice and a sloped cap
    B.box((0.78, 0.78, 0.12), (0, 0, 0.06), iron, bevel=0.01, matrix=m)
    B.box((0.62, 0.62, 1.1), (0, 0, 0.67), iron, matrix=m)
    for k in range(4):
        f = m @ Matrix.Rotation(k * math.pi / 2, 4, "Z")
        B.box((0.44, 0.03, 0.8), (0, 0.32, 0.67), iron, bevel=0.008, matrix=f)
        for (bw, bh, bx, bz) in ((0.4, 0.015, 0, 1.05), (0.4, 0.015, 0, 0.29), (0.015, 0.76, -0.2, 0.67), (0.015, 0.76, 0.2, 0.67)):
            B.box((bw, 0.012, bh), (bx, 0.337, bz), gold, matrix=f)
    B.box((0.72, 0.72, 0.07), (0, 0, 1.255), iron, bevel=0.01, matrix=m)
    B.cyl(0.5, 0.2, 0.28, (0, 0, 1.29), iron, segs=4, rz=math.pi / 4, matrix=m)
    # the column: a base ring, the plain lower shaft, a gold collar, the fluted shaft
    B.cyl(0.18, 0.15, 0.1, (0, 0, 1.55), iron, segs=20, matrix=m)
    B.cyl(0.13, 0.12, 0.72, (0, 0, 1.64), iron, segs=20, matrix=m)
    B.cyl(0.17, 0.17, 0.06, (0, 0, 2.36), gold, segs=20, matrix=m)
    B.cyl(0.15, 0.15, 0.06, (0, 0, 2.42), iron, segs=20, matrix=m)
    B.cyl(0.11, 0.1, 1.5, (0, 0, 2.48), iron, segs=20, matrix=m)
    for k in range(12):
        a = math.tau * k / 12
        B.box((0.022, 0.022, 1.4), (math.cos(a) * 0.108, math.sin(a) * 0.108, 3.23), dark, rz=a, matrix=m)
    # the capital: flared, leafed, under its abacus
    B.cyl(0.1, 0.19, 0.22, (0, 0, 3.98), gold, segs=20, matrix=m)
    for k in range(8):
        a = math.tau * k / 8
        B.box((0.06, 0.03, 0.16), (math.cos(a) * 0.16, math.sin(a) * 0.16, 4.1), gold, rz=a + math.pi / 2, rx=0.35, matrix=m)
    B.box((0.46, 0.34, 0.06), (0, 0, 4.23), iron, bevel=0.01, matrix=m)
    # the bracket under the drum, its scrolls
    B.box((0.36, 0.26, 0.16), (0, 0, 4.34), iron, matrix=m)
    for sx in (-1, 1):
        B.cyl(0.07, 0.07, 0.26, (sx * 0.22, 0.13, 4.36), gold, segs=12, rx=math.pi / 2, matrix=m)
        B.box((0.16, 0.22, 0.22), (sx * 0.4, 0, 4.48), iron, bevel=0.02, matrix=m)
    # the drum and its two faces
    R, d, zc = 0.55, 0.34, 4.97
    B.cyl(R, R, d, (0, d / 2, zc), iron, segs=40, rx=math.pi / 2, matrix=m)
    for f in (1, -1):
        fy = f * d / 2
        B.cyl(R + 0.03, R + 0.03, 0.05, (0, fy + f * 0.05 if f > 0 else fy, zc), gold, segs=40, rx=math.pi / 2, matrix=m)  # its bezel
        B.cyl(R - 0.08, R - 0.08, 0.012, (0, fy + f * 0.062 if f > 0 else fy - 0.05, zc), "white", segs=40, rx=math.pi / 2, matrix=m)  # its dial
        face_y = fy + f * 0.063
        for k in range(12):
            a = math.tau * k / 12
            tx = -f * math.sin(a)  # (clockwise as read: to its reader's right)
            big = k % 3 == 0
            B.box((0.045 if big else 0.025, 0.008, 0.1 if big else 0.07), (tx * 0.4, face_y, zc + math.cos(a) * 0.4), "black", ry=math.atan2(tx, math.cos(a)), matrix=m)
        B.cyl(0.03, 0.03, 0.02, (0, face_y + f * 0.02 if f > 0 else face_y, zc), "brass", segs=12, rx=math.pi / 2, matrix=m)
        at = m @ Vector((0, face_y + f * 0.004, zc))
        B.marker("CLOCK_FACE", at.x, at.y, at.z, rz + (0.0 if f > 0 else math.pi))  # (its hands: ClubLife)
    # the crest over the drum: a panel, its gabled top and arch, scrolls, a roundel each face, the finial
    top = zc + R
    B.box((0.92, 0.2, 0.34), (0, 0, top + 0.09), iron, bevel=0.01, matrix=m)
    gable = [(-0.5, top + 0.26), (0.5, top + 0.26), (0.0, top + 0.5)]
    v = [tuple(m @ Vector((gx, gy, gz))) for gy in (-0.1, 0.1) for gx, gz in gable]
    B.poly(v, [(0, 1, 2), (5, 4, 3), (0, 3, 4, 1), (1, 4, 5, 2), (2, 5, 3, 0)], iron)
    B.cyl(0.2, 0.2, 0.2, (0, 0.1, top + 0.26), iron, segs=20, rx=math.pi / 2, matrix=m)
    for sx in (-1, 1):
        B.cyl(0.075, 0.075, 0.24, (sx * 0.5, 0.12, top + 0.24), gold, segs=14, rx=math.pi / 2, matrix=m)
    for f in (1, -1):
        B.cyl(0.1, 0.1, 0.02, (0, f * 0.1 + (0.02 if f > 0 else 0.0), top + 0.12), gold, segs=20, rx=math.pi / 2, matrix=m)
    B.ball(0.07, (0, 0, top + 0.56), gold, subdiv=1, matrix=m)
    at = m @ Vector((0, 0, 0))
    B.marker("KEEPOUT", at.x, at.y, z, 0.0, 0.7)


def wash_station(B, x, y, z):
    B.box((4.0, 4.0, 0.06), (x, y, z + 0.03), "concrete")
    B.cyl(1.4, 1.4, 0.01, (x + 0.4, y - 0.3, z + 0.065), "water", segs=20)
    B.cyl(0.6, 0.6, 0.01, (x - 0.8, y + 0.9, z + 0.065), "water", segs=14)
    B.box((0.25, 0.25, 1.1), (x - 1.4, y - 1.4, z + 0.55), "steel")
    B.cyl(0.18, 0.18, 0.1, (x - 1.4, y - 1.4, z + 0.9), "cloth_green", segs=12, rx=math.pi / 2)
    B.cyl(0.3, 0.3, 0.02, (x - 1.0, y - 1.0, z + 0.07), "cloth_green", segs=14)


def steel_post(B, x, y, z, h, w=0.25):
    B.box((w, w, h), (x, y, z + h * 0.5), "iron")


def flat_roof(B, x0, y0, x1, y1, z, t=0.35, over=0.4, mat="charcoal", fascia="iron"):
    B.box((x1 - x0 + over * 2, y1 - y0 + over * 2, t), ((x0 + x1) * 0.5, (y0 + y1) * 0.5, z + t * 0.5), mat)
    B.box((x1 - x0 + over * 2 + 0.06, y1 - y0 + over * 2 + 0.06, 0.12), ((x0 + x1) * 0.5, (y0 + y1) * 0.5, z + t + 0.02), fascia)


def glass_wall(B, p0, p1, z, h, mullion=1.6, frame="iron"):
    a, b = Vector((p0[0], p0[1], 0)), Vector((p1[0], p1[1], 0))
    d = b - a
    ln = d.length
    ang = math.atan2(d.y, d.x)
    mid = (a + b) * 0.5
    B.box((ln, 0.06, h), (mid.x, mid.y, z + h * 0.5), "glass", rz=ang)
    n = max(int(ln / mullion), 1)
    for i in range(n + 1):
        p = a + d * (i / n)
        B.box((0.08, 0.12, h), (p.x, p.y, z + h * 0.5), frame, rz=ang)
    for hh in (0.05, h - 0.05):
        B.box((ln, 0.12, 0.1), (mid.x, mid.y, z + hh), frame, rz=ang)


def clad_wall(B, p0, p1, z, h, mat="wood_light", thick=0.25):
    a, b = Vector((p0[0], p0[1], 0)), Vector((p1[0], p1[1], 0))
    d = b - a
    ang = math.atan2(d.y, d.x)
    mid = (a + b) * 0.5
    B.box((d.length, thick, h), (mid.x, mid.y, z + h * 0.5), mat, rz=ang)
    n = int(h / 0.18)
    for i in range(1, n):
        B.box((d.length + 0.01, thick + 0.02, 0.02), (mid.x, mid.y, z + i * 0.18), "wood", rz=ang)


def ext_stairs(B, x, y0, z0, z1, width=1.4, run_dir=1, mat="wood", rail="iron"):
    """A straight outdoor stair along y from (x, y0) at z0 up to z1. Returns how far it runs."""
    rise = z1 - z0
    n = max(int(math.ceil(rise / 0.18)), 2)
    run = 0.28
    for i in range(n):
        B.box((width, run, 0.06), (x, y0 + run_dir * run * (i + 0.5), z0 + rise * (i + 1) / n - 0.03), mat)
    ln = math.hypot(run * n, rise)
    ang = math.atan2(rise, run * n) * run_dir
    for s in (-1, 1):
        B.box((0.05, ln, 0.05), (x + s * width * 0.5, y0 + run_dir * run * n * 0.5, (z0 + z1) * 0.5 + 0.95), rail, rx=ang)
        B.box((0.06, ln, 0.2), (x + s * width * 0.5, y0 + run_dir * run * n * 0.5, (z0 + z1) * 0.5), rail, rx=ang)
    return run * n


def range_bucket(B, x, y, z, rz=0.0):
    """Tapered open green lattice basket, loose white balls and a black bail handle."""
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")

    def rod(a, b, radius, mat):
        a, b = Vector(a), Vector(b)
        d = b - a
        xf = m @ Matrix.Translation(a) @ d.to_track_quat("Z", "Y").to_matrix().to_4x4()
        B.cyl(radius, radius, d.length, (0, 0, 0), mat, segs=6, matrix=xf)

    def band(radius, height, thick, width):
        verts = []
        for zz, rr in ((height - width / 2, radius), (height + width / 2, radius),
                       (height - width / 2, radius - thick), (height + width / 2, radius - thick)):
            for i in range(24):
                a = math.tau * i / 24
                verts.append(tuple(m @ Vector((rr * math.cos(a), rr * math.sin(a), zz))))
        faces = []
        for i in range(24):
            j = (i + 1) % 24
            faces += [(i, j, j + 24, i + 24), (i + 48, i + 72, j + 72, j + 48),
                      (i + 24, j + 24, j + 72, i + 72), (i, i + 48, j + 48, j)]
        B.poly(verts, faces, "basket_green")

    B.cyl(0.106, 0.106, 0.015, (0, 0, 0), "basket_green", segs=24, matrix=m)
    for zz in (0.025, 0.10, 0.18, 0.275):
        band(0.108 + zz * 0.19, zz, 0.012, 0.025 if zz == 0.275 else 0.014)
    for i in range(16):
        a = math.tau * i / 16
        rod((0.105 * math.cos(a), 0.105 * math.sin(a), 0.015),
            (0.155 * math.cos(a), 0.155 * math.sin(a), 0.275), 0.006, "basket_green")
    # Visible layers behind the lattice, with a loose mound across the open top.
    for layer in range(6):
        zz = 0.039 + layer * 0.043
        rr = 0.108 + zz * 0.19 - 0.028
        count = int(math.tau * rr / 0.047)
        for i in range(count):
            a = math.tau * i / count + layer * 0.29
            B.ball(0.023, (rr * math.cos(a), rr * math.sin(a), zz), "white", subdiv=2, matrix=m)
    for yy in range(-2, 3):
        for xx in range(-2, 3):
            bx, by = xx * 0.047 + (yy % 2) * 0.0235, yy * 0.041
            if math.hypot(bx, by) < 0.10:
                B.ball(0.023, (bx, by, 0.283 + 0.025 * (1 - math.hypot(bx, by) / 0.10)), "white", subdiv=2, matrix=m)
    for sign in (-1, 1):
        B.ball(0.012, (sign * 0.16, 0, 0.27), "black", subdiv=1, matrix=m)
    handle = [(0.163 * math.cos(math.pi * i / 20), 0, 0.27 + 0.18 * math.sin(math.pi * i / 20)) for i in range(21)]
    for a, b in zip(handle, handle[1:]):
        rod(a, b, 0.006, "black")


def mat_bay(B, x, y, z, rz=0.0, grass=False):
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
    B.box((1.5, 1.5, 0.04), (0, 0, 0.02), "turf" if grass else "mat_green", matrix=m)
    B.cyl(0.02, 0.02, 0.06, (0.2, 0.3, 0.04), "white", segs=5, matrix=m)
    # (no bucket of its own: the golfer brings one over from the ball dispenser, ClubLife)
    # Right-hand ball feed, parallel to the mat and outside the golfer's stance.
    m = m @ Matrix.Translation((0, -0.43, 0)) @ Matrix.Rotation(-math.pi / 2, 4, "Z")
    B.box((0.72, 0.31, 0.025), (-0.43, 0.96, 0.03), "rubber", matrix=m)
    for sy in (0.80, 1.12):
        B.box((0.76, 0.025, 0.075), (-0.43, sy, 0.05), "black", matrix=m)
    for sx in (-0.80, -0.06):
        B.box((0.025, 0.33, 0.075), (sx, 0.96, 0.05), "black", matrix=m)
    for row in range(3):
        for col in range(11):
            B.ball(0.0215, (-0.73 + col * 0.057 + (row % 2) * 0.012, 0.875 + row * 0.075,
                           0.065), "white", subdiv=2, matrix=m)


def divider(B, x, y, z, rz=0.0, h=1.2, d=1.6):
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
    # Rounded frame, taller at the outfield end and lower by the walking aisle.
    corners = [Vector((-d / 2, 0.10)), Vector((d / 2, 0.10)),
               Vector((d / 2, h)), Vector((-d / 2, h * 0.48))]
    outline = []
    for i, p in enumerate(corners):
        prev, nxt = corners[i - 1], corners[(i + 1) % len(corners)]
        a = p + (prev - p).normalized() * 0.10
        b = p + (nxt - p).normalized() * 0.10
        for k in range(6):
            t = k / 5
            outline.append(a * (1 - t) ** 2 + p * (2 * (1 - t) * t) + b * t ** 2)
    for i, a in enumerate(outline):
        b = outline[(i + 1) % len(outline)]
        start, end = Vector((0, a.x, a.y)), Vector((0, b.x, b.y))
        delta = end - start
        xf = m @ Matrix.Translation(start) @ delta.to_track_quat("Z", "Y").to_matrix().to_4x4()
        B.cyl(0.022, 0.022, delta.length, (0, 0, 0), "iron", segs=8, matrix=xf)
    # Actual diamond openings rather than a solid or translucent panel.
    for slope in (-0.8, 0.8):
        for k in range(-30, 40):
            intercept = k * 0.075
            hits = []
            for i, a in enumerate(outline):
                b = outline[(i + 1) % len(outline)]
                fa = a.y - slope * a.x - intercept
                fb = b.y - slope * b.x - intercept
                if fa * fb < 0:
                    hits.append(a.lerp(b, fa / (fa - fb)))
            if len(hits) < 2:
                continue
            a, b = min(hits, key=lambda q: q.x), max(hits, key=lambda q: q.x)
            delta = (b - a).normalized()
            side = Vector((-delta.y, delta.x)) * 0.004
            pts = [a - side, b - side, b + side, a + side]
            B.poly([tuple(m @ Vector((0, p.x, p.y))) for p in pts], [(0, 1, 2, 3)], "divider_mesh")
    for sy in (-d / 2 + 0.12, d / 2 - 0.12):
        B.box((0.24, 0.16, 0.025), (0, sy, 0.0125), "iron", matrix=m)
        B.cyl(0.016, 0.016, 0.08, (0, sy, 0.025), "iron", segs=8, matrix=m)


def ball_dispenser(B, x, y, z, rz=0.0, cage=True):
    """The range's ball machine (its front, the screen and the chute, toward +y turned by rz),
    and a BALL_DISPENSER marker where a golfer stands at its chute to fill a bucket, facing it."""
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
    stand = m @ Vector((0, 0.95, 0))
    B.marker("BALL_DISPENSER", stand.x, stand.y, z, rz + math.pi)
    B.box((0.9, 0.8, 1.6), (0, 0, 0.8), "charcoal", matrix=m, bevel=0.04)
    B.box((0.4, 0.02, 0.25), (0, 0.41, 1.25), "screen", matrix=m)
    B.box((0.3, 0.2, 0.15), (0, 0.45, 0.55), "steel", matrix=m)
    if cage:
        for s in (-1, 1):
            B.box((0.04, 1.4, 2.2), (s * 0.8, 0.0, 1.1), "iron", matrix=m)
        B.box((1.64, 1.4, 0.04), (0, 0.0, 2.2), "iron", matrix=m)
        for s in (-1, 1):
            B.box((1.6, 0.02, 2.1), (0, s * 0.7, 1.05), "net", matrix=m)


def tv_post(B, x, y, z, rz=0.0):
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
    B.box((0.08, 0.08, 1.2), (0, 0, 0.6), "iron", matrix=m)
    B.box((0.6, 0.05, 0.4), (0, 0.04, 1.35), "tv", matrix=m)
    # Map the display area of the reference photo onto the 3D monitor's own bezel.
    B.image_quad([(0.27, 0.075, 1.198125), (-0.27, 0.075, 1.198125),
                  (-0.27, 0.075, 1.501875), (0.27, 0.075, 1.501875)],
                 "range_display", matrix=m,
                 uv_rect=(100 / 966, 1 - 541 / 650, 872 / 966, 1 - 106 / 650))


def tractor(B, x, y, z, rz=0.0, body="cloth_green"):
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
    B.box((1.3, 2.4, 0.7), (0, 0.2, 0.9), body, matrix=m, bevel=0.08)
    B.box((1.2, 1.0, 1.0), (0, -0.6, 1.6), "glass", matrix=m)
    B.box((1.3, 1.1, 0.08), (0, -0.6, 2.12), body, matrix=m)
    for sx in (-0.75, 0.75):
        B.cyl(0.55, 0.55, 0.35, (sx, -0.7, 0.55), "rubber", segs=14, ry=math.pi / 2, matrix=m)
        B.cyl(0.35, 0.35, 0.25, (sx * 0.9, 0.9, 0.35), "rubber", segs=12, ry=math.pi / 2, matrix=m)
    B.box((2.4, 0.6, 0.4), (0, 1.9, 0.35), "steel", matrix=m)


def cone(B, x, y, z):
    B.box((0.36, 0.36, 0.03), (x, y, z + 0.015), "black")
    B.cyl(0.14, 0.03, 0.55, (x, y, z + 0.03), "cone", segs=10)
    B.cyl(0.1, 0.07, 0.08, (x, y, z + 0.28), "white", segs=10)


# ---------------------------------------------------------------- room frames & shop props

class RoomFrame:
    """A room's local frame: `lb` runs along the door wall, `la` from the door wall (la = -D/2)
    to the far wall (la = +D/2); W, D are the room's extents along them."""

    def __init__(self, r, door):
        x0, y0, x1, y1 = r
        self.cx, self.cy = (x0 + x1) * 0.5, (y0 + y1) * 0.5
        a, b = {"-y": ((0, 1), (1, 0)), "+y": ((0, -1), (-1, 0)), "-x": ((1, 0), (0, -1)), "+x": ((-1, 0), (0, 1))}[door]
        self.a, self.b = Vector((a[0], a[1], 0)), Vector((b[0], b[1], 0))
        self.yaw = math.atan2(b[1], b[0])
        self.W = abs(x1 - x0) if abs(b[0]) > 0.5 else abs(y1 - y0)
        self.D = abs(y1 - y0) if abs(a[1]) > 0.5 else abs(x1 - x0)

    def p(self, lb, la):
        v = self.b * lb + self.a * la
        return self.cx + v.x, self.cy + v.y

    def rz(self, local=0.0):
        return self.yaw + local

    def facing(self, wall):
        """A FACING key for the wall the frame calls 'far' / 'door' / 'left' / 'right'."""
        n = {"far": self.a, "door": -self.a, "left": -self.b, "right": self.b}[wall]
        if abs(n.x) > 0.5:
            return "-x" if n.x > 0 else "+x"
        return "-y" if n.y > 0 else "+y"


# the pro shop's golf ball packs (tools/blender/build_ball_packs.py; ball_pack_layout.py)
BALL_SLEEVES = ("sleeve_titleist_pro_v1", "sleeve_titleist_trufeel")
BALL_DOZENS = ("dozen_taylormade_tp5", "dozen_callaway_chrome_tour", "dozen_callaway_chrome_soft")


def pack_marker(B, m, local, pack, yaw=0.0):
    """Where one of the pro shop's ball packs stands (placed by Godot): its base centred on the
    point, its front toward local +Y turned by yaw."""
    p = m @ Vector(local)
    B.marker("BALLPACK_" + pack, p.x, p.y, p.z, m.to_euler().z + yaw, 1.0)


def _facing(rz):
    """The FACING key nearest local +Y turned by rz (for lettering on a turned display)."""
    n = Vector((-math.sin(rz), math.cos(rz)))
    if abs(n.x) > abs(n.y):
        return "+x" if n.x > 0 else "-x"
    return "+y" if n.y > 0 else "-y"


def ball_sleeve_tower(B, x, y, z, rz=0.0, seed=0):
    """A freestanding stand of ball sleeves: four tiers stepping back and up, each a row of
    sleeves standing fronts out in blocks of each kind, under a GOLF BALLS header."""
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
    w, d = 0.96, 0.52
    back = -d * 0.5
    low = 0.0
    for k in range(4):
        front = d * 0.5 - k * 0.13
        top = 0.5 + k * 0.2
        B.box((w, front - back, top - 0.012 - low), (0, (front + back) * 0.5, (low + top - 0.012) * 0.5), "white", matrix=m)
        B.box((w + 0.01, front - back + 0.01, 0.012), (0, (front + back) * 0.5, top - 0.006), "wood_light", matrix=m)
        low = top
        n = int((w - 0.06) / 0.052)
        for i in range(n):
            pack_marker(B, m, (-(n - 1) * 0.026 + i * 0.052, front - 0.05, top), BALL_SLEEVES[(k + i // 4 + seed) % 2])
    for sx in (-1, 1):
        B.box((0.03, 0.03, 0.62), (sx * (w * 0.5 - 0.03), back + 0.03, low + 0.31), "charcoal", matrix=m)
    B.box((w, 0.03, 0.24), (0, back + 0.03, low + 0.52), "charcoal", matrix=m)
    B.text("GOLF BALLS", _facing(rz), tuple(m @ Vector((0, back + 0.045, low + 0.52))), 0.11, "white", 0.01)


def ball_cubby_wall(B, x, y, z, w, facing_rz, seed=0):
    """A wall unit of cubbies: six rows of dozen boxes, fronts out two deep, over a kick plate,
    a row of ball sleeves along the top and a GOLF BALLS header."""
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(facing_rz, 4, "Z")
    d = 0.34
    n = max(int(w / 0.23), 1)
    cw = w / n
    floors = [0.16 + r * 0.22 for r in range(7)]  # shelf tops; the top row holds sleeves
    top = floors[-1] + 0.2
    B.box((w, 0.02, top), (0, 0.01, top * 0.5), "wood", matrix=m)
    for sx in (-1, 1):
        B.box((0.025, d, top), (sx * (w * 0.5 - 0.0125), d * 0.5, top * 0.5), "wood_light", matrix=m)
    B.box((w - 0.05, d - 0.02, 0.14), (0, d * 0.5 + 0.01, 0.07), "charcoal", matrix=m)
    for f in floors:
        B.box((w - 0.05, d - 0.02, 0.02), (0, d * 0.5 + 0.01, f - 0.01), "wood_light", matrix=m)
    B.box((w, d, 0.03), (0, d * 0.5, top + 0.015), "wood_light", matrix=m)
    for i in range(1, n):
        B.box((0.015, d - 0.04, top - 0.16), (-w * 0.5 + i * cw, d * 0.5 + 0.01, (top + 0.16) * 0.5), "wood_light", matrix=m)
    for r, f in enumerate(floors):
        for i in range(n):
            cx = -w * 0.5 + (i + 0.5) * cw
            if r < len(floors) - 1:
                for j in range(2):
                    pack_marker(B, m, (cx, d - 0.04 - j * 0.06, f), BALL_DOZENS[(i + r + seed) % len(BALL_DOZENS)])
            else:
                k = int((cw - 0.03) / 0.05)
                for s in range(k):
                    pack_marker(B, m, (cx - (k - 1) * 0.025 + s * 0.05, d - 0.05, f), BALL_SLEEVES[(i + s // 2 + seed) % 2])
    B.box((w, 0.03, 0.22), (0, d - 0.02, top + 0.14), "charcoal", matrix=m)
    B.text("GOLF BALLS", _facing(facing_rz), tuple(m @ Vector((0, d - 0.005, top + 0.14))), 0.1, "white", 0.01)


def ball_pyramid(B, x, y, z, layers=4, r=0.021, mat="white"):
    """A pyramid of golf balls (the shop counter classic)."""
    for k in range(layers):
        n = layers - k
        for i in range(n):
            for j in range(n):
                B.ball(r, (x + (i - (n - 1) * 0.5) * r * 2.05, y + (j - (n - 1) * 0.5) * r * 2.05, z + r + k * r * 1.45), mat, subdiv=1)


def ball_bin(B, x, y, z, w=0.6, rz=0.0):
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
    B.box((w, w, 0.7), (0, 0, 0.35), "wood_light", matrix=m)
    for i in range(int(w / 0.06) ** 2 // 2):
        a = i * 2.39996
        rr = (i % 7) / 7.0 * w * 0.42
        B.ball(0.021, (math.cos(a) * rr, math.sin(a) * rr, 0.72 + (i % 3) * 0.02), "white", subdiv=1, matrix=m)
    top = m @ Vector((0, 0, 0.74))
    ball_pyramid(B, top.x, top.y, top.z + 0.04, 3)


def golf_cap(B, x, y, z, rz=0.0, crown="cloth_navy", brim=None):
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
    B.ball(0.095, (0, 0, 0.0), crown, scale=(1.0, 1.08, 0.7), subdiv=2, matrix=m)
    B.box((0.17, 0.12, 0.012), (0, 0.13, -0.045), brim or crown, rx=0.18, matrix=m)
    B.ball(0.012, (0, 0, 0.066), crown, subdiv=1, matrix=m)


CAP_COLS = ("cloth_navy", "white", "cloth_red", "cloth_green", "black", "cloth_tan", "cloth_sky")
CAP_REACH = 0.142  # how far the cap model (props/golf_cap.glb) reaches from its point, back and front


def fold_marker(B, m, local, seed, width=0.34):
    """Where a pile of folded shirts sits (one of the club's two folded-clothes models, placed by
    Godot), shrunk to fit `width` across."""
    p = m @ Vector(local)
    B.marker("FOLD_" + "AB"[seed % 2], p.x, p.y, p.z, m.to_euler().z + (math.pi if seed % 3 == 0 else 0.0), min(1.0, width / 0.34))


def cap_marker(B, m, local, colour, yaw=0.0):
    """Where one of the club's caps sits (the cap model, tinted CAP_COLS[colour] by Godot): the
    point at the foot of its rim, midway between the back of the crown and the tip of the bill
    (CAP_REACH either way), the bill toward local +Y turned by yaw."""
    p = m @ Vector(local)
    B.marker("CAP_%d" % colour, p.x, p.y, p.z, m.to_euler().z + yaw, 1.0)


def hat_wall(B, x, y, z, w, facing_rz, rows=3, seed=0):
    """Rows of the club's caps sat on shelves along a headwear slat-wall section: each shelf deep
    enough for a whole cap (crown to the tip of its bill), on brackets."""
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(facing_rz, 4, "Z")
    B.box((w, 0.05, 1.6), (0, -0.02, 1.35), "wood_light", matrix=m)
    for k in range(8):
        B.box((w, 0.012, 0.012), (0, 0.007, 0.6 + k * 0.2), "wood", matrix=m)
    n = max(int(w / 0.3), 1)
    out = 0.005 + CAP_REACH + 0.013  # each cap's point: the back of its crown clear of the board's face (5 mm out)
    deep = out + CAP_REACH + 0.02  # from the board to just past the tip of the bill
    for r in range(rows):
        top = 0.73 + r * 0.42  # the shelf's top, the caps' rims on it
        B.box((w, deep, 0.025), (0, deep * 0.5, top - 0.0125), "wood", bevel=0.004, matrix=m)
        for bx in (-w * 0.5 + 0.06, w * 0.5 - 0.06):
            B.box((0.02, deep * 0.7, 0.1), (bx, deep * 0.35, top - 0.075), "wood", matrix=m)
        for i in range(n):
            px = -w * 0.5 + (i + 0.5) * w / n
            cap_marker(B, m, (px, out, top), (i + r + seed) % len(CAP_COLS))


def slat_wall(B, x, y, z, w, facing_rz, h=2.4, shirts=True, seed=0, shoes=False):
    """Slat-wall panel with apparel 'waterfalls' (angled arms of hanging shirts) or a shoe shelf."""
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(facing_rz, 4, "Z")
    B.box((w, 0.06, h), (0, -0.03, h * 0.5 + 0.1), "charcoal", matrix=m)
    for k in range(int(h / 0.15)):
        B.box((w, 0.02, 0.02), (0, 0.01, 0.2 + k * 0.15), "grey", matrix=m)
    cols = ("cloth_navy", "cloth_white", "cloth_green", "cloth_sky", "cloth_red", "cloth_tan", "charcoal")
    if shirts:
        n = max(int(w / 0.9), 1)
        for i in range(n):
            px = -w * 0.5 + (i + 0.5) * w / n
            B.box((0.03, 0.66, 0.03), (px, 0.34, 1.75), "chrome", rx=-0.12, matrix=m)
            for k in range(3):
                pos = m @ Vector((px, 0.20 + k * 0.18, 1.79 - k * 0.022))
                variant = ("TEE_NAVY", "POLO_GREEN", "TEE_CREAM", "POLO_SKY")[(i + k + seed) % 4]
                B.marker("SHIRT_" + variant, *pos, facing_rz + math.pi)
    if shoes:
        n = max(int(w / 0.50), 1)
        for r in range(4):
            for i in range(n):
                px = -w * 0.5 + (i + 0.5) * w / n
                B.box((0.38, 0.34, 0.025), (px, 0.18, 0.7 + r * 0.42), "chrome", matrix=m)
                pos = m @ Vector((px, 0.19, 0.713 + r * 0.42))
                variant = ("SPORT", "CANVAS", "ADIDAS", "TRAINER", "NIKE", "CLASSIC", "KNIT")[(i + r * n) % 7]
                B.marker("SHOE_" + variant, *pos, facing_rz + math.pi + 0.25)


def t_stand(B, x, y, z, rz=0.0, seed=0, caps=True):
    """A clothes rack of shirts (one of the club's rack models), with a little cap table beside it."""
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
    clothes_rack(B, x, y, z, 1.4, rz, seed=seed)
    if caps:
        tm = m @ Matrix.Translation((1.15, 0, 0))
        B.cyl(0.22, 0.25, 0.04, (0, 0, 0), "charcoal", segs=14, matrix=tm)
        B.cyl(0.04, 0.04, 0.9, (0, 0, 0.04), "chrome", segs=8, matrix=tm)
        B.cyl(0.32, 0.32, 0.03, (0, 0, 0.94), "wood_light", segs=18, matrix=tm)
        for i in range(4):
            a = math.tau * i / 4
            cap_marker(B, tm, (math.cos(a) * 0.17, math.sin(a) * 0.17, 0.97), (i + seed) % len(CAP_COLS), a)


def club_rack(B, x, y, z, family="iron", rz=0.0, n=8):
    """Open metal retail rack with individual grip sockets and a labeled header."""
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
    width, depth = .76, .48
    B.box((width, depth, .07), (0, 0, .055), "wood_light", bevel=.025, matrix=m)
    for sx in (-1, 1):
        B.box((.035, .035, 1.48), (sx*.34, -.17, .78), "iron", matrix=m)
    B.box((width, .035, .28), (0, -.17, 1.40), "sign_green", bevel=.012, matrix=m)
    B.box((width-.08, .06, .045), (0, -.04, .72), "iron", matrix=m)
    for i in range(n):
        row, col = i//4, i%4
        px,py = -.255+col*.17, -.09+row*.18
        B.cyl(.028,.028,.012,(px,py,.096),"rubber",segs=12,matrix=m)
        club_marker(B,family,m,(px,py,.105),0)
    front=m.to_3x3()@Vector((0,1,0))
    facing=("+x" if front.x>0 else "-x") if abs(front.x)>.5 else ("+y" if front.y>0 else "-y")
    label={"driver":"DRIVERS","fairway":"FAIRWAY WOODS","hybrid":"HYBRIDS","iron":"IRON SETS","wedge":"WEDGES","putter":"PUTTERS"}[family]
    p=m@Vector((0,-.145,1.4))
    B.text(label,facing,tuple(p),.058 if family=="fairway" else .078,"white",depth=.002)


def club_bin(B, x, y, z, rz=0.0, n=12, label="black", family=None):
    """A floor bin of real clubs standing grip-down, heads up, like the shop's iron bins."""
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
    B.box((0.6, 0.45, 0.55), (0, 0, 0.275), label, matrix=m, bevel=0.02)
    B.box((0.56, 0.41, 0.02), (0, 0, 0.5), "black", matrix=m)
    fams = (family,) if family else ("iron", "wedge", "iron", "driver", "putter", "iron")
    for i in range(n):
        px = -0.22 + (i % 5) * 0.11
        py = -0.11 + (i // 5) * 0.11
        club_marker(B, fams[i % len(fams)], m, (px, py, 0.12), (i % 4) * 0.4 - 0.6)


def bag_display(B, x, y, z, rz=0.0, n=3, seed=0):
    """A carpeted riser of golf bags, every other one turned so both aisles see the pockets."""
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
    B.box((n * 0.62 + 0.4, 0.9, 0.3), (0, 0, 0.15), "grey", matrix=m, bevel=0.05)
    B.box((n * 0.62 + 0.3, 0.8, 0.02), (0, 0, 0.31), "carpet", matrix=m)
    for i in range(n):
        px = -(n - 1) * 0.31 + i * 0.62
        bag_marker(B, m, (px, 0.05 if i % 2 else -0.05, 0.32), math.pi if (i + seed) % 2 else 0.0)


def promo_table(B, x, y, z, w=1.6, d=0.8, rz=0.0, seed=0):
    """A wood display table of folded polos, ball boxes and a ball pyramid."""
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
    B.box((w, d, 0.06), (0, 0, 0.8), "wood_light", matrix=m)
    B.box((w - 0.1, d - 0.1, 0.77), (0, 0, 0.385), "wood", matrix=m)
    for i in range(3):  # piles of folded polos
        fold_marker(B, m, (-w * 0.32 + i * 0.36, -d * 0.18, 0.83), i + seed, 0.34)
    for i in range(2):  # stacks of dozen boxes
        for k in range(2):
            pack_marker(B, m, (w * 0.18 + i * 0.2, d * 0.22, 0.83 + k * 0.14), BALL_DOZENS[(i + k + seed) % len(BALL_DOZENS)])
    bm = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
    p = bm @ Vector((w * 0.32, -d * 0.2, 0.83))
    ball_pyramid(B, p.x, p.y, p.z, 4)


def pro_counter(B, x, y, z, w=2.6, rz=0.0, ret=1.4):
    """The pro-shop desk: wooden front, stone top, a glass case of ball boxes, a till, and an L return."""
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
    B.box((w, 0.7, 1.0), (0, 0, 0.5), "wood_light", matrix=m, bevel=0.02)
    B.box((w + 0.06, 0.76, 0.05), (0, 0, 1.02), "stone", matrix=m)
    B.box((w * 0.45, 0.04, 0.6), (w * 0.2, 0.36, 0.45), "glass", matrix=m)
    # the case: dozens on the lower glass shelf, sleeves on the upper, fronts to the glass
    case = w * 0.43
    for k, zs in enumerate((0.16, 0.44)):
        B.box((case, 0.2, 0.01), (w * 0.2, 0.25, zs - 0.005), "glass", matrix=m)
        step = 0.195 if k == 0 else 0.055
        n = int(case / step)
        for i in range(n):
            px = w * 0.2 - (n - 1) * step * 0.5 + i * step
            pack_marker(B, m, (px, 0.27, zs), BALL_DOZENS[i % len(BALL_DOZENS)] if k == 0 else BALL_SLEEVES[(i // 3) % 2])
    # a little riser of dozens on the counter top
    B.box((0.44, 0.15, 0.05), (w * 0.02, 0.2, 1.07), "wood_dark", matrix=m, bevel=0.005)
    for i in range(2):
        pack_marker(B, m, (w * 0.02 - 0.1 + i * 0.2, 0.2, 1.095), BALL_DOZENS[i + 1])
    p = m @ Vector((-w * 0.3, -0.06, 1.045))  # the till: the iMac, facing the clerk
    imac(B, p.x, p.y, p.z, rz + math.pi)
    if ret > 0:
        B.box((0.7, ret, 1.0), (w * 0.5 - 0.35, -ret * 0.5 - 0.35, 0.5), "wood_light", matrix=m, bevel=0.02)
        B.box((0.76, ret + 0.06, 0.05), (w * 0.5 - 0.35, -ret * 0.5 - 0.35, 1.02), "stone", matrix=m)
    p = m @ Vector((w * 0.35, 0.0, 1.05))
    ball_pyramid(B, p.x, p.y, p.z, 4)


def drink_cooler(B, x, y, z, rz=0.0, doors=2):
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
    w = doors * 0.75
    B.box((w, 0.7, 2.0), (0, 0, 1.0), "black", matrix=m)
    B.box((w - 0.1, 0.02, 1.7), (0, 0.36, 1.05), "glass", matrix=m)
    for r in range(4):
        for i in range(int(w / 0.12)):
            B.cyl(0.03, 0.03, 0.22, (-w * 0.5 + 0.1 + i * 0.12, 0.2, 0.3 + r * 0.42), ("cloth_sky", "cloth_red", "screen_green", "cloth_tan")[(i + r) % 4], segs=6, matrix=m)


def peg_wall(B, x, y, z, w, facing_rz, mat_items=("white", "black", "cloth_red", "cloth_sky")):
    """Peg / slat wall of small packages (gloves, ball sleeves, tees)."""
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(facing_rz, 4, "Z")
    B.box((w, 0.05, 1.8), (0, -0.02, 1.3), "white", matrix=m)
    n = max(int(w / 0.2), 1)
    for r in range(6):
        for i in range(n):
            px = -w * 0.5 + (i + 0.5) * w / n
            B.box((0.14, 0.03, 0.2), (px, 0.04, 0.6 + r * 0.26), mat_items[(i + r) % len(mat_items)], matrix=m)


def juke_box(B, x, y, z, rz=0.0):
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
    B.box((0.9, 0.6, 1.4), (0, 0, 0.7), "wood_dark", matrix=m, bevel=0.05)
    B.cyl(0.45, 0.45, 0.6, (0, 0.0, 1.4), "wood_dark", segs=16, rx=math.pi / 2, matrix=m)
    B.box((0.6, 0.02, 0.5), (0, 0.31, 1.0), "screen", matrix=m)
    B.box((0.7, 0.02, 0.08), (0, 0.31, 1.45), "fire", matrix=m)


def banquette(B, x0, y0, x1, y1, z, mat="leather"):
    """A banquette bench along a line (seat + back)."""
    d = Vector((x1 - x0, y1 - y0, 0))
    ang = math.atan2(d.y, d.x)
    mid = Vector(((x0 + x1) * 0.5, (y0 + y1) * 0.5, 0))
    B.box((d.length, 0.55, 0.45), (mid.x, mid.y, z + 0.225), mat, rz=ang, bevel=0.05)
    n = Vector((-math.sin(ang), math.cos(ang), 0))
    b = mid - n * 0.32
    B.box((d.length, 0.18, 1.0), (b.x, b.y, z + 0.5), mat, rz=ang, bevel=0.05)


# ---------------------------------------------------------------- z-fighting

def defight(objects, nudge=0.005, tol=0.004, min_area=0.0004):
    """Coplanar overlapping faces in different materials flicker against each other in game
    (window glass flush with a wall, a trim flush with the siding, soil level with a pot rim).
    For every such pair facing the same way, push the smaller face out along its normal by
    `nudge`. Faces looking down are left alone (nobody sees them), and furniture of different
    tiers of the same room never shows together, so those pairs don't count.
    Returns how many faces moved."""
    from collections import defaultdict
    recs = []  # (obj index, face index, axis, sign, plane, lo, hi, material, area, room tier key)
    meshes = [o for o in objects if o.type == "MESH" and not o.name.startswith("COL_")]
    for oi, ob in enumerate(meshes):
        me = ob.data
        mw = ob.matrix_world
        rot = mw.to_3x3()
        tier = None
        if ob.name.startswith("ROOM_"):
            base = ob.name.split(".")[0]
            k = base.rfind("_T")
            tier = (base[5:k], base[k + 2:])
        for p in me.polygons:
            n = (rot @ p.normal).normalized()
            axis = max(range(3), key=lambda i: abs(n[i]))
            if abs(n[axis]) < 0.995 or (axis == 2 and n[axis] < 0):
                continue
            vs = [mw @ me.vertices[i].co for i in p.vertices]
            others = [i for i in range(3) if i != axis]
            lo = [min(v[o] for v in vs) for o in others]
            hi = [max(v[o] for v in vs) for o in others]
            mat = me.materials[p.material_index].name if me.materials else ""
            recs.append((oi, p.index, axis, 1 if n[axis] > 0 else -1, sum(v[axis] for v in vs) / len(vs), lo, hi, mat, p.area, tier))
    buckets = defaultdict(list)
    for r in recs:
        buckets[(r[2], r[3], round(r[4] / tol))].append(r)
    move = defaultdict(set)  # obj index -> face indices
    for key, fs in buckets.items():
        cand = fs + buckets.get((key[0], key[1], key[2] + 1), [])
        for i in range(len(fs)):
            a = fs[i]
            for b in cand[i + 1:]:
                if a[7] == b[7] or abs(a[4] - b[4]) > tol:
                    continue
                if a[9] and b[9] and a[9][0] == b[9][0] and a[9][1] != b[9][1]:
                    continue
                w = min(a[6][0], b[6][0]) - max(a[5][0], b[5][0])
                h = min(a[6][1], b[6][1]) - max(a[5][1], b[5][1])
                if w <= 0.01 or h <= 0.01 or w * h < min_area:
                    continue
                small = a if a[8] <= b[8] else b
                move[small[0]].add(small[1])
    moved = 0
    for oi, idxs in move.items():
        ob = meshes[oi]
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bm.faces.ensure_lookup_table()
        dirs = {}  # vertex -> the distinct directions it goes out in (a corner of two nudged faces: both)
        for fi in idxs:
            f = bm.faces[fi]
            for v in f.verts:
                ds = dirs.setdefault(v, [])
                if not any(d.dot(f.normal) > 0.99 for d in ds):
                    ds.append(f.normal.copy())
        for v, ds in dirs.items():
            for d in ds:
                v.co += d * nudge
        bm.to_mesh(ob.data)
        bm.free()
        moved += len(idxs)
    return moved
