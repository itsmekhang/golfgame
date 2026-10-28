"""Golfer outfit pass (Blender, background):

  blender -b --python tools/golfer_outfit.py -- [--preview]

Re-dresses the Mixamo "Ch01" golfer (assets/golfer/golfer.fbx) from jeans + white tee into
golf clothes by repainting its 4K texture atlas -- the mesh, skeleton and animations are left
untouched, so GolferRig's IK/grip tuning keeps working:

  * polo (shirt mesh): solid colour with the tee's own fold shading, knit grain, a placket
    with buttons and a small chest logo; the hem below the waistband is cut out through
    alpha (alpha-scissor in Godot) so the polo reads as tucked in
  * trousers (pants mesh): denim weave blurred out, recoloured, belt + buckle at the waist
  * a white leather glove on the lead (left) hand, warmer outdoor skin, short hair under the cap
  * golf shoes: sneakers cleaned up, dark accents

How: Cycles bakes each mesh's bind-pose world position into a float image laid out like the
atlas (plus a mesh-id image); numpy then repaints the atlas with masks defined in 3D (e.g.
"left hand past the wrist"), so the edits follow the body, not the UV islands.

Writes assets/golfer/outfit_albedo.png and outfit_normal.png (weave-free trousers).
"""
import bpy
import numpy as np
import sys
import os

ROOT = r"C:\Users\willi\Documents\GolfGame"
FBX = ROOT + r"\assets\golfer\golfer.fbx"
OUT_ALBEDO = ROOT + r"\assets\golfer\outfit_albedo.png"
OUT_NORMAL = ROOT + r"\assets\golfer\outfit_normal.png"
PREVIEW_DIR = ROOT + r"\build\redesign"
N = 4096
POS_OFFSET = np.array([1.0, 1.0, 0.1], np.float32)  # keeps baked positions positive

# Outfit palette (sRGB)
POLO = (0.14, 0.30, 0.55)        # ocean blue
POLO_TRIM = (0.93, 0.93, 0.91)   # placket edge / logo
TROUSERS = (0.56, 0.57, 0.57)    # light grey
BELT = (0.07, 0.065, 0.06)
BUCKLE = (0.78, 0.78, 0.80)
GLOVE = (0.95, 0.95, 0.93)
GLOVE_CUFF = (0.20, 0.30, 0.50)
HAIR = (0.17, 0.12, 0.085)
SKIN_TINT = (1.03, 0.94, 0.86)  # linear multiplier: warmer, slightly tanned

MESH_IDS = {"Ch01_Body": 1, "Ch01_Pants": 2, "Ch01_Shirt": 3, "Ch01_Sneakers": 4}


def srgb_to_lin(c):
    c = np.clip(c, 0.0, 1.0)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def lin_to_srgb(c):
    c = np.clip(c, 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1.0 / 2.4) - 0.055)


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def box_blur(a, r):
    """Separable box blur (edge-clamped) along both image axes."""
    if r <= 0:
        return a
    out = a
    for axis in (0, 1):
        pad = [(0, 0)] * out.ndim
        pad[axis] = (r + 1, r)
        p = np.pad(out, pad, mode="edge")
        c = np.cumsum(p, axis=axis, dtype=np.float64)
        n = out.shape[axis]
        hi = np.take(c, np.arange(2 * r + 1, 2 * r + 1 + n), axis=axis)
        lo = np.take(c, np.arange(0, n), axis=axis)
        out = ((hi - lo) / (2 * r + 1)).astype(np.float32)
    return out


def masked_blur(a, mask, r, passes=2):
    """Blur `a` only from pixels inside `mask` (normalised), so other islands never bleed in."""
    m = mask.astype(np.float32)
    num = a * (m[..., None] if a.ndim == 3 else m)
    den = m
    for _ in range(passes):
        num = box_blur(num, r)
        den = box_blur(den, r)
    den = np.maximum(den, 1e-4)
    return num / (den[..., None] if a.ndim == 3 else den)


def img_to_np(img):
    a = np.empty(img.size[0] * img.size[1] * 4, np.float32)
    img.pixels.foreach_get(a)
    return a.reshape(img.size[1], img.size[0], 4)


def np_to_img(name, a, colorspace="sRGB", float_buffer=False):
    img = bpy.data.images.new(name, a.shape[1], a.shape[0], alpha=True, float_buffer=float_buffer)
    img.colorspace_settings.name = colorspace
    img.pixels.foreach_set(np.ascontiguousarray(a, np.float32).ravel())
    return img


def setup():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=FBX)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 1
    sc.render.bake.margin = 8
    sc.render.bake.margin_type = "EXTEND"
    sc.render.bake.use_clear = False
    meshes = [o for o in bpy.data.objects if o.type == "MESH" and o.name in MESH_IDS]
    for o in meshes:
        for m in o.modifiers:
            if m.type == "ARMATURE":
                m.show_render = False
                m.show_viewport = False
    return meshes


def bake(meshes, target, emission_for):
    """Bake an emission shader (built by emission_for(nodes, links, obj) -> socket) into `target`."""
    originals = {}
    for o in meshes:
        originals[o.name] = [s.material for s in o.material_slots]
        mat = bpy.data.materials.new("bake_" + o.name)
        mat.use_nodes = True
        nt = mat.node_tree
        nt.nodes.clear()
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        em = nt.nodes.new("ShaderNodeEmission")
        nt.links.new(emission_for(nt.nodes, nt.links, o), em.inputs["Color"])
        nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = target
        nt.nodes.active = tex
        for s in o.material_slots:
            s.material = mat
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.bake(type="EMIT", margin=8, use_clear=False)
    for o in meshes:
        for s, m in zip(o.material_slots, originals[o.name]):
            s.material = m


def position_emission(nodes, links, o):
    geo = nodes.new("ShaderNodeNewGeometry")
    add = nodes.new("ShaderNodeVectorMath")
    add.operation = "ADD"
    add.inputs[1].default_value = tuple(POS_OFFSET)
    links.new(geo.outputs["Position"], add.inputs[0])
    return add.outputs["Vector"]


def id_emission(nodes, links, o):
    rgb = nodes.new("ShaderNodeRGB")
    v = MESH_IDS[o.name] / 10.0
    rgb.outputs[0].default_value = (v, v, v, 1.0)
    return rgb.outputs[0]


def main():
    preview = "--preview" in sys.argv
    meshes = setup()
    pos_img = bpy.data.images.new("posmap", N, N, alpha=True, float_buffer=True)
    pos_img.colorspace_settings.name = "Non-Color"
    pos_img.generated_color = (0, 0, 0, 0)
    id_img = bpy.data.images.new("idmap", N, N, alpha=True, float_buffer=True)
    id_img.colorspace_settings.name = "Non-Color"
    id_img.generated_color = (0, 0, 0, 0)
    bake(meshes, pos_img, position_emission)
    print("[outfit] baked positions")
    bake(meshes, id_img, id_emission)
    print("[outfit] baked ids")
    pos = img_to_np(pos_img)[..., :3] - POS_OFFSET
    mid = np.rint(img_to_np(id_img)[..., 0] * 10.0).astype(np.int32)
    x, y, z = pos[..., 0], pos[..., 1], pos[..., 2]
    body, pants, shirt, shoes = (mid == 1), (mid == 2), (mid == 3), (mid == 4)

    albedo_src = bpy.data.images["file1"]
    normal_src = bpy.data.images["file3"]
    src = img_to_np(albedo_src)
    rgb = srgb_to_lin(src[..., :3])
    lum = rgb @ np.array([0.2126, 0.7152, 0.0722], np.float32)
    out = rgb.copy()
    alpha = np.ones(lum.shape, np.float32)
    rng = np.random.default_rng(7)
    grain = rng.standard_normal(lum.shape).astype(np.float32)

    def col(c):
        return srgb_to_lin(np.array(c, np.float32))

    # ---- polo ------------------------------------------------------------------------
    sh_l = masked_blur(lum, shirt, 2, 1)
    ref = np.percentile(sh_l[shirt], 80)
    shade = np.clip(sh_l / ref, 0.25, 1.15) ** 1.15
    knit = 1.0 + 0.035 * grain
    polo = col(POLO)[None, None, :] * (shade * knit)[..., None]
    front = y < -0.02
    # placket: a 3 cm band down the chest from the neckline, edged, three buttons
    placket = shirt & front & (np.abs(x) < 0.017) & (z > 1.375) & (z < 1.56)
    edge = shirt & front & (np.abs(np.abs(x) - 0.017) < 0.0016) & (z > 1.375) & (z < 1.56)
    bottom = shirt & front & (np.abs(x) < 0.017) & (np.abs(z - 1.375) < 0.0016)
    polo = np.where(placket[..., None], polo * 0.93, polo)
    polo = np.where((edge | bottom)[..., None], polo * 0.55, polo)
    for bz in (1.505, 1.465, 1.425):
        d = np.sqrt(x * x + (z - bz) ** 2)
        btn = shirt & front & (d < 0.0055)
        ring = shirt & front & (np.abs(d - 0.0055) < 0.0012)
        polo = np.where(btn[..., None], col(POLO_TRIM) * (0.9 + 0.1 * shade)[..., None], polo)
        polo = np.where(ring[..., None], polo * 0.5, polo)
    # small chest logo on the left breast: a white ring with a gold dot
    d = np.sqrt((x - 0.085) ** 2 + (z - 1.425) ** 2)
    logo_ring = shirt & front & (np.abs(d - 0.011) < 0.0022)
    logo_dot = shirt & front & (d < 0.0045)
    polo = np.where(logo_ring[..., None], col(POLO_TRIM) * shade[..., None], polo)
    polo = np.where(logo_dot[..., None], col((0.85, 0.66, 0.25)) * shade[..., None], polo)
    # sleeve hems: a knit rib band at the sleeve ends (|x| ~ 0.36..0.39)
    rib = shirt & (np.abs(x) > 0.352)
    polo = np.where(rib[..., None], polo * (0.86 + 0.06 * np.sin(z * 2200.0))[..., None], polo)
    out = np.where(shirt[..., None], polo, out)
    # tucked in: cut the hem away below the waistband (alpha scissor)
    alpha = np.where(shirt & (z < 0.985), 0.0, alpha)

    # ---- trousers + belt -------------------------------------------------------------
    pa_l = masked_blur(lum, pants, 10, 3)
    ref = np.percentile(pa_l[pants], 75)
    shade = np.clip(pa_l / ref, 0.3, 1.15) ** 1.1
    trousers = col(TROUSERS)[None, None, :] * (shade * (1.0 + 0.02 * grain))[..., None]
    # belt: the top 4 cm of the trousers all round
    ang = np.arctan2(y + 0.01, x)
    pv = np.array([v.co for v in bpy.data.objects["Ch01_Pants"].data.vertices]) if False else None
    belt = pants & (z > 0.962)
    buckle = belt & front & (np.abs(x) < 0.03) & (z > 0.966) & (z < 1.0)
    buckle_in = buckle & (np.abs(x) < 0.02) & (z > 0.973) & (z < 0.993)
    belt_col = col(BELT)[None, None, :] * (0.85 + 0.15 * shade)[..., None]
    trousers = np.where(belt[..., None], belt_col, trousers)
    trousers = np.where(buckle[..., None], col(BUCKLE)[None, None, :] * np.ones_like(shade)[..., None], trousers)
    trousers = np.where(buckle_in[..., None], col(BELT) * 1.4 * np.ones_like(shade)[..., None], trousers)
    out = np.where(pants[..., None], trousers, out)

    # ---- skin, glove, hair -----------------------------------------------------------
    glove = body & (x > 0.703)
    cuff = glove & (x < 0.727)
    sk = body & ~glove
    out = np.where(sk[..., None], out * np.array(SKIN_TINT, np.float32)[None, None, :], out)
    gl_l = masked_blur(lum, glove, 2, 1)
    ref = np.percentile(gl_l[glove], 85)
    gshade = np.clip(gl_l / ref, 0.35, 1.1)
    glove_col = col(GLOVE)[None, None, :] * gshade[..., None]
    glove_col = np.where(cuff[..., None], col(GLOVE_CUFF)[None, None, :] * gshade[..., None], glove_col)
    out = np.where(glove[..., None], glove_col, out)
    # short hair: top and back of the head and the sides above the ears; soft hairline
    head = body & (z > 1.50)
    top = smooth(1.700, 1.712, z)                          # forehead hairline
    back = smooth(-0.045, -0.02, y) * smooth(1.575, 1.595, z)  # back of the head down to the nape
    sides = smooth(0.066, 0.074, np.abs(x)) * smooth(1.635, 1.65, z) * smooth(-0.075, -0.06, y)
    ear = smooth(0.082, 0.088, np.abs(x)) * (z > 1.60) * (z < 1.69) * (y > -0.06) * (y < 0.035)
    hm = np.clip(np.maximum(np.maximum(top, back), sides) * (1.0 - ear), 0.0, 1.0) * head
    strand = 0.75 + 0.25 * np.clip(grain * 0.6 + 0.5, 0.0, 1.0)
    hair = col(HAIR)[None, None, :] * strand[..., None]
    out = out * (1.0 - hm * 0.92)[..., None] + hair * (hm * 0.92)[..., None]

    # ---- shoes: whiter uppers, deeper darks ------------------------------------------
    sh_rgb = out
    shoe_l = lum
    shoe = np.where((shoe_l > 0.35)[..., None], np.minimum(sh_rgb * 1.12, 1.0), sh_rgb * 0.6)
    out = np.where(shoes[..., None], shoe, out)

    res = np.concatenate([lin_to_srgb(out), alpha[..., None]], axis=-1)
    covered = mid > 0
    res = np.where(covered[..., None], res, src)  # untouched where no mesh landed (eyes etc.)
    res[..., 3] = np.where(covered, alpha, 1.0)
    img = np_to_img("outfit_albedo", res)
    img.filepath_raw = OUT_ALBEDO
    img.file_format = "PNG"
    img.save()
    print("[outfit] wrote", OUT_ALBEDO)

    # normal map: trousers lose the denim weave, keep the folds
    nsrc = img_to_np(normal_src)
    nb = masked_blur(nsrc[..., :3], pants, 8, 3)
    nrm = np.where(pants[..., None], nb, nsrc[..., :3])
    nimg = np_to_img("outfit_normal", np.concatenate([nrm, np.ones_like(nsrc[..., :1])], axis=-1), "Non-Color")
    nimg.filepath_raw = OUT_NORMAL
    nimg.file_format = "PNG"
    nimg.save()
    print("[outfit] wrote", OUT_NORMAL)

    if preview:
        render_preview(img)


def render_preview(img):
    sc = bpy.context.scene
    for o in bpy.data.objects:
        if o.type == "MESH":
            for m in o.modifiers:
                if m.type == "ARMATURE":
                    m.show_render = True
        if o.type == "MESH":
            for s in o.material_slots:
                mat = s.material
                if mat is None or not mat.use_nodes:
                    continue
                for n in mat.node_tree.nodes:
                    if n.type == "TEX_IMAGE" and n.image is not None and n.image.name == "file1":
                        n.image = img
                        for l in list(n.outputs["Alpha"].links):
                            mat.node_tree.links.remove(l)
                bsdf = mat.node_tree.nodes.get("Principled BSDF")
                if bsdf is not None and o.name == "Ch01_Shirt":
                    for n in mat.node_tree.nodes:
                        if n.type == "TEX_IMAGE" and n.image == img:
                            mat.node_tree.links.new(n.outputs["Alpha"], bsdf.inputs["Alpha"])
    sc.cycles.samples = 24
    sc.render.resolution_x = 900
    sc.render.resolution_y = 1100
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.62, 0.7, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.8
    sc.world = world
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.5
    sun.rotation_euler = (0.9, 0.2, -0.6)
    sc.collection.objects.link(sun)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    from mathutils import Vector
    shots = {"full_front": (Vector((0.6, -3.2, 1.1)), Vector((0, 0, 0.95)), 32),
             "full_back": (Vector((-0.8, 3.2, 1.1)), Vector((0, 0, 0.95)), 32),
             "head": (Vector((0.25, -0.75, 1.68)), Vector((0, 0, 1.62)), 50),
             "head_back": (Vector((-0.45, 0.6, 1.72)), Vector((0, 0, 1.64)), 50),
             "waist": (Vector((0.3, -1.1, 1.1)), Vector((0, 0, 1.08)), 50),
             "hand": (Vector((0.78, -0.55, 1.55)), Vector((0.76, 0, 1.42)), 50)}
    for name, (p, t, lens) in shots.items():
        cam.location = p
        cam.data.lens = lens
        d = t - p
        cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = os.path.join(PREVIEW_DIR, "outfit_" + name + ".png")
        bpy.ops.render.render(write_still=True)
        print("[outfit] preview", sc.render.filepath)


main()
