"""The parking lots' accessible spaces: the sign at a space's head and the symbol painted on it
-> assets/facilities/props/ada_sign.glb, ada_paint.glb

    blender -b --factory-startup --disable-autoexec -P tools/blender/build_ada_sign.py [-- --preview <png>]

The sign is the user's Caltrans drawing: R99 (12 x 18 in: the International Symbol of Access
over PARKING ONLY) over R99B (12 x 9 in: MINIMUM FINE $250), white on blue with a white border,
bolted to a galvanised square post, the lower plate's foot 60 in up. Its face looks down -y
(Blender; Godot +z), the post's foot at the origin. The paint is the user's symbol picture: a
1 m blue square with rounded corners, a thin white line inside its edge and the symbol in
white, its top toward +y (Blender; Godot -z), flat on z = 0.

The symbol is drawn from the user's picture (SYMBOL: px, y down): round-ended strokes -- the
head, the back, the arm, the seat, the leg and foot, and the wheel's open ring.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
PROPS = os.path.join(ROOT, "assets", "facilities", "props")
IN = 0.0254
FONT = "C:/Windows/Fonts/ARIALNB.TTF"  # Arial Narrow Bold, condensed to the drawing's widths like the signs' Series B

# the user's symbol picture (750 px square; y down): the blue square, and the strokes
SQUARE = (150.0, 147.0, 597.0, 595.0)  # x0, y0, x1, y1
SQUARE_R = 55.0  # its corners' radius
LINE = (10.0, 18.0)  # the white line inside its edge: from, to (px in)
HEAD = ((330.0, 248.0), 27.0)
STROKES = [  # (from, to, width)
    ((328.0, 268.0), (328.0, 377.0), 26.0),  # the back
    ((328.0, 331.0), (388.0, 331.0), 24.0),  # the arm
    ((328.0, 377.0), (420.0, 377.0), 26.0),  # the seat
    ((420.0, 377.0), (462.0, 470.0), 26.0),  # the leg
    ((462.0, 470.0), (488.0, 470.0), 26.0),  # the foot
]
WHEEL = ((340.0, 425.0), 80.0, 124.0, 337.0, 26.0)  # centre, radius, from, to (degrees, y up), width
SYMBOL_BOX = (247.0, 221.0, 501.0, 518.0)  # the strokes' extent


def srgb(h):
    c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c) + (1.0,)


def material(name, hexc, rough, metal=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = srgb(hexc)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    return m


# ---------------------------------------------------------------- 2D shapes (CCW, y up)

def disc(c, r, segs=28):
    return [(c[0] + r * math.cos(math.tau * i / segs), c[1] + r * math.sin(math.tau * i / segs)) for i in range(segs)]


def capsule(p, q, w, segs=10):
    """A stroke from p to q, `w` wide, with round ends."""
    a = math.atan2(q[1] - p[1], q[0] - p[0])
    r = w * 0.5
    out = []
    for i in range(segs + 1):  # round the far end, then the near
        t = a - math.pi * 0.5 + math.pi * i / segs
        out.append((q[0] + r * math.cos(t), q[1] + r * math.sin(t)))
    for i in range(segs + 1):
        t = a + math.pi * 0.5 + math.pi * i / segs
        out.append((p[0] + r * math.cos(t), p[1] + r * math.sin(t)))
    return out


def ring_arc(c, r, a0, a1, w, segs=36, cap=8):
    """An open ring along radius `r` from a0 to a1 (radians, CCW), `w` wide, with round ends."""
    ro, ri = r + w * 0.5, r - w * 0.5
    out = [(c[0] + ro * math.cos(a0 + (a1 - a0) * i / segs), c[1] + ro * math.sin(a0 + (a1 - a0) * i / segs)) for i in range(segs + 1)]
    e = (c[0] + r * math.cos(a1), c[1] + r * math.sin(a1))
    for i in range(1, cap):
        t = a1 + math.pi * i / cap
        out.append((e[0] + w * 0.5 * math.cos(t), e[1] + w * 0.5 * math.sin(t)))
    out += [(c[0] + ri * math.cos(a1 + (a0 - a1) * i / segs), c[1] + ri * math.sin(a1 + (a0 - a1) * i / segs)) for i in range(segs + 1)]
    s = (c[0] + r * math.cos(a0), c[1] + r * math.sin(a0))
    for i in range(1, cap):
        t = a0 + math.pi + math.pi * i / cap
        out.append((s[0] + w * 0.5 * math.cos(t), s[1] + w * 0.5 * math.sin(t)))
    return out


def rrect(cx, cy, w, h, r, segs=8):
    """A rounded rectangle, CCW from its lower right corner."""
    out = []
    for k, (qx, qy) in enumerate(((1, -1), (1, 1), (-1, 1), (-1, -1))):
        ccx, ccy = cx + qx * (w * 0.5 - r), cy + qy * (h * 0.5 - r)
        a = -math.pi * 0.5 + k * math.pi * 0.5
        for i in range(segs + 1):
            t = a + math.pi * 0.5 * i / segs
            out.append((ccx + r * math.cos(t), ccy + r * math.sin(t)))
    return out


def symbol(scale, at):
    """The symbol's outlines, `scale` m a px, centred on `at` (2D, y up)."""
    bx = (SYMBOL_BOX[0] + SYMBOL_BOX[2]) * 0.5
    by = (SYMBOL_BOX[1] + SYMBOL_BOX[3]) * 0.5
    up = lambda p: (p[0], -p[1])  # the picture's y runs down: drawn y up

    def m(p):  # a y-up picture point onto the target
        return ((p[0] - bx) * scale + at[0], (p[1] + by) * scale + at[1])

    shapes = [[m(v) for v in disc(up(HEAD[0]), HEAD[1])]]
    for p, q, w in STROKES:
        shapes.append([m(v) for v in capsule(up(p), up(q), w)])
    c, r, a0, a1, w = WHEEL
    shapes.append([m(v) for v in ring_arc(up(c), r, math.radians(a0), math.radians(a1), w)])
    return shapes


# ---------------------------------------------------------------- building

class Mesh:
    def __init__(self):
        self.bm = bmesh.new()
        self.mats = []

    def slot(self, mat):
        if mat not in self.mats:
            self.mats.append(mat)
        return self.mats.index(mat)

    def flat(self, outline, place, mat, flip=False):
        """A flat face on `outline` (2D), each point put by `place`."""
        vs = [self.bm.verts.new(place(p)) for p in outline]
        if flip:
            vs.reverse()
        f = self.bm.faces.new(vs)
        f.material_index = self.slot(mat)
        return f

    def slab(self, outline, place_front, place_back, front, sides, back):
        """A plate on `outline`: its face where place_front puts it, its back where place_back
        does, and its edge between, every face turned outward."""
        fv = [self.bm.verts.new(place_front(p)) for p in outline]
        bv = [self.bm.verts.new(place_back(p)) for p in outline]
        faces = [self.bm.faces.new(fv), self.bm.faces.new(bv[::-1])]
        faces[0].material_index = self.slot(front)
        faces[1].material_index = self.slot(back)
        for a in range(len(outline)):
            c = (a + 1) % len(outline)
            g = self.bm.faces.new([fv[c], fv[a], bv[a], bv[c]])
            g.material_index = self.slot(sides)
            faces.append(g)
        bmesh.ops.recalc_face_normals(self.bm, faces=faces)

    def box(self, size, centre, mat):
        r = bmesh.ops.create_cube(self.bm, size=1.0)
        bmesh.ops.scale(self.bm, vec=size, verts=r["verts"])
        bmesh.ops.translate(self.bm, vec=centre, verts=r["verts"])
        for f in {f for v in r["verts"] for f in v.link_faces}:
            f.material_index = self.slot(mat)

    def cyl(self, r, h, centre, axis, mat, segs=12):
        res = bmesh.ops.create_cone(self.bm, cap_ends=True, segments=segs, radius1=r, radius2=r, depth=h)
        rot = Vector((0, 0, 1)).rotation_difference(Vector(axis)).to_matrix().to_4x4()
        bmesh.ops.transform(self.bm, matrix=Matrix.Translation(centre) @ rot, verts=res["verts"])
        for f in {f for v in res["verts"] for f in v.link_faces}:
            f.material_index = self.slot(mat)

    def text(self, body, cap, width, centre, place, mat, font):
        """`body` in `font`, its capitals `cap` high and the line `width` wide (condensed or
        spread to it), centred on `centre` (2D), each point put by `place`."""
        cu = bpy.data.curves.new("t", "FONT")
        cu.font = font
        cu.body = body
        cu.size = 1.0
        cu.align_x = "CENTER"
        ob = bpy.data.objects.new("t", cu)
        bpy.context.scene.collection.objects.link(ob)
        me = ob.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh()
        src = bmesh.new()
        src.from_mesh(me)
        ob.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh_clear()
        bpy.data.objects.remove(ob)
        xs = [v.co.x for v in src.verts]
        sx = width / (max(xs) - min(xs))
        sy = cap / CAP_H
        mid = (max(xs) + min(xs)) * 0.5
        vmap = {}
        for v in src.verts:
            vmap[v] = self.bm.verts.new(place(((v.co.x - mid) * sx + centre[0], (v.co.y - CAP_H * 0.5) * sy + centre[1])))
        for f in src.faces:
            g = self.bm.faces.new([vmap[v] for v in f.verts])
            g.material_index = self.slot(mat)
        src.free()

    def finish(self, name):
        bmesh.ops.remove_doubles(self.bm, verts=self.bm.verts, dist=1e-6)
        me = bpy.data.meshes.new(name)
        self.bm.to_mesh(me)
        self.bm.free()
        for m in self.mats:
            me.materials.append(m)
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        return ob


CAP_H = 0.716  # Arial Narrow Bold's capitals, of its size (measured in main)


def sign(font, M):
    """R99 over R99B on the post: plates in the x-z plane, facing -y."""
    m = Mesh()
    t = 0.08 * IN  # the aluminium
    foot = 60 * IN  # R99B's foot
    lo = (foot, foot + 9 * IN)  # R99B's foot and top
    hi = (lo[1] + 0.5 * IN, lo[1] + 0.5 * IN + 18 * IN)  # R99's
    post = 2 * IN
    yb = -post * 0.5 - 0.004  # the plates' backs, just in front of the post
    yf = yb - t  # their faces
    for (z0, z1) in (lo, hi):
        zc = (z0 + z1) * 0.5
        h = z1 - z0
        at = lambda d: (lambda p: (p[0], d, p[1]))
        m.slab(rrect(0.0, zc, 12 * IN, h, 1.5 * IN), at(yf), at(yb), M["white"], M["metal"], M["metal"])
        m.flat(rrect(0.0, zc, 11 * IN, h - 1 * IN, 1.0 * IN), at(yf - 0.0006), M["blue"])
        for dz in (h * 0.5 - 1.0 * IN, -h * 0.5 + 1.0 * IN):  # the bolts, through the white border
            m.cyl(0.22 * IN, 0.006, Vector((0.0, yf - 0.002, zc + dz)), (0, 1, 0), M["metal"], segs=8)
    face = lambda p: (p[0], yf - 0.0012, p[1])
    top = hi[1]
    sym_h = 8 * IN
    for s in symbol(sym_h / (SYMBOL_BOX[3] - SYMBOL_BOX[1]), (0.0, top - 1 * IN - sym_h * 0.5)):
        m.flat(s, face, M["white"])
    m.text("PARKING", 3 * IN, 9.9 * IN, (0.0, top - 11.0 * IN), face, M["white"], font)
    m.text("ONLY", 3 * IN, 6.0 * IN, (0.0, top - 15.0 * IN), face, M["white"], font)
    m.text("MINIMUM", 2 * IN, 7.2 * IN, (0.0, lo[1] - 3.0 * IN), face, M["white"], font)
    m.text("FINE  $250", 2 * IN, 9.6 * IN, (0.0, lo[1] - 6.0 * IN), face, M["white"], font)
    # the post: galvanised square tube, capped, standing to an inch under R99's top
    ph = top - 1 * IN
    m.box((post, post, ph), (0.0, 0.0, ph * 0.5), M["post"])
    m.box((post + 0.004, post + 0.004, 0.01), (0.0, 0.0, ph + 0.005), M["post"])
    return m.finish("ADA_Sign")


def paint(M, side=1.0):
    """The symbol on the ground: the blue square, its white line and the symbol, flat on z = 0
    (the white over the blue), its top toward +y."""
    m = Mesh()
    k = side / (SQUARE[2] - SQUARE[0])
    cx, cy = (SQUARE[0] + SQUARE[2]) * 0.5, (SQUARE[1] + SQUARE[3]) * 0.5
    blue = lambda p: (p[0], p[1], 0.008)
    white = lambda p: (p[0], p[1], 0.012)
    m.flat(rrect(0.0, 0.0, side, side, SQUARE_R * k), blue, M["paint_blue"])
    # the line: a strip between two rounded squares, inset LINE[0] and LINE[1]
    o = rrect(0.0, 0.0, side - 2 * LINE[0] * k, side - 2 * LINE[0] * k, (SQUARE_R - LINE[0]) * k)
    i = rrect(0.0, 0.0, side - 2 * LINE[1] * k, side - 2 * LINE[1] * k, (SQUARE_R - LINE[1]) * k)
    for a in range(len(o)):
        b = (a + 1) % len(o)
        m.flat([o[a], o[b], i[b], i[a]], white, M["paint_white"])
    bx = (SYMBOL_BOX[0] + SYMBOL_BOX[2]) * 0.5
    by = (SYMBOL_BOX[1] + SYMBOL_BOX[3]) * 0.5
    for s in symbol(k, ((bx - cx) * k, (cy - by) * k)):
        m.flat(s, white, M["paint_white"])
    return m.finish("ADA_Paint")


def export(ob, path):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True)
    ob.select_set(False)
    print("EXPORTED", path, os.path.getsize(path))


def main():
    global CAP_H
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    preview = argv[argv.index("--preview") + 1] if "--preview" in argv else ""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    font = bpy.data.fonts.load(FONT)
    # the font's capital height, of its size: an "H" set at size 1
    cu = bpy.data.curves.new("h", "FONT")
    cu.font = font
    cu.body = "H"
    ob = bpy.data.objects.new("h", cu)
    bpy.context.scene.collection.objects.link(ob)
    me = ob.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh()
    CAP_H = max(v.co.y for v in me.vertices) - min(v.co.y for v in me.vertices)
    ob.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh_clear()
    bpy.data.objects.remove(ob)
    M = {
        "white": material("sign_white", "f4f6f4", 0.35),
        "blue": material("sign_blue", "1d3f94", 0.35),
        "metal": material("sign_back", "aeb3b5", 0.4, 0.6),
        "post": material("galvanised", "a7adae", 0.45, 0.75),
        "paint_blue": material("paint_blue", "1f4096", 0.75),
        "paint_white": material("paint_white", "f2f4f2", 0.7),
    }
    s = sign(font, M)
    export(s, os.path.join(PROPS, "ada_sign.glb"))
    p = paint(M)
    export(p, os.path.join(PROPS, "ada_paint.glb"))
    print("SIGN %d tris, PAINT %d tris, cap %.3f" % (sum(len(f.vertices) - 2 for f in s.data.polygons), sum(len(f.vertices) - 2 for f in p.data.polygons), CAP_H))
    if preview:
        p.location = (1.0, -1.2, 0.0)
        sc = bpy.context.scene
        cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
        sc.collection.objects.link(cam)
        sc.camera = cam
        sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
        sc.collection.objects.link(sun)
        sun.rotation_euler = (0.7, 0.0, -0.5)
        sun.data.energy = 3.0
        sc.world = bpy.data.worlds.new("w")
        sc.world.color = (0.6, 0.65, 0.7)
        sc.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE"
        for name, at, look, res in (("face", (0.0, -1.6, 1.95), (0.0, 0.0, 1.95), (600, 900)),
                                    ("whole", (2.6, -3.6, 1.8), (0.4, -0.6, 0.9), (900, 700)),
                                    ("paint", (1.0, -1.2, 2.2), (1.0, -1.2, 0.0), (700, 700))):
            cam.location = at
            cam.rotation_euler = (Vector(look) - Vector(at)).to_track_quat("-Z", "Y").to_euler()
            sc.render.resolution_x, sc.render.resolution_y = res
            sc.render.filepath = preview.replace(".png", "_%s.png" % name)
            bpy.ops.render.render(write_still=True)


main()
