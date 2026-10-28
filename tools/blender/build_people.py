"""People for Course Manager: the user's low-poly human (tools/blender/sources/human_base.glb,
prepared by human_base.py) dressed per role, on one shared 18-bone rig with idle / walk / work /
swing / putt / sit animations. Exported once per staff role in that role's work uniform
(assets/facilities/people/staff_<role>.glb) and once per golfer look in golf clothes and the
club's cap (assets/facilities/people/golfer_<look>.glb). Golfers carry one of the club's bags
(Godot hangs it off the chest bone) and ride in the carts (the sit pose).

Uniforms are painted onto the body by region (shirt / trousers / shoes / skin, sleeves short or
long, trousers or shorts) plus pieces built on the measured body: the club cap
(assets/facilities/props/golf_cap.glb), visors, chef's hats, aprons, vests, blazers, bow ties
and name badges. Without the human source it falls back to the old stylized body.

Run (Blender 5.x, from the project root):
    blender -b --factory-startup -P tools/blender/build_people.py -- [--previews <dir>]

Materials are named skin / hair / shirt / pants / shoes / accent / detail / cap so Godot can vary
skin, hair and cap colour per person. The character faces Blender +Y (Godot -Z), feet at z = 0,
1.78 m tall.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector, Euler

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "assets", "facilities", "people")
HUMAN = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sources", "human_base.glb")
CAP = os.path.join(ROOT, "assets", "facilities", "props", "golf_cap.glb")
# Clips from the user's motion captures (Mixamo, tools/blender/sources/anims/): the file, the
# source frames used (first, last, step at the clip's own rate), whether the hips keep their
# travel (a walk is done in place) and whether the clip loops. The swing runs address to the
# held finish; the putt address, stroke and held follow-through; the walk is one two-step cycle.
# "stand": taken from a seated capture, the arms and body only, stood up (the typing, done
# standing at a counter), the arms let down "lower" degrees to its height; "floor": the hips'
# height is the capture's own, from the floor (a clip that starts lying down or bent over), not
# its first frame's; "mirror": the capture mirrored left for right (getting into a cart from the
# passenger's side as the capture does from the driver's).
ANIMS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sources", "anims")
CAPTURES = {
    "breathe": {"fbx": "breathing_idle.fbx", "frames": (1, 596, 3), "in_place": True, "loop": True},
    "swing": {"fbx": "golf_drive_4.fbx", "frames": (1, 95, 1), "in_place": False, "loop": False},
    "walk": {"fbx": "walking.fbx", "frames": (1, 59, 2), "in_place": True, "loop": True},
    "putt": {"fbx": "golf_putt.fbx", "frames": (1, 79, 2), "in_place": False, "loop": False},
    "chip": {"fbx": "golf_chip/golf_chip.fbx", "frames": (1, 59, 1), "in_place": False, "loop": False, "floor": True},
    # a bucket of range balls (or anything else) carried in the right hand (our .L), walking
    "carry": {"fbx": "carry_walk/carry_walk.fbx", "frames": (1, 75, 2), "in_place": True, "loop": True},
    "type": {"fbx": "typing/typing.fbx", "frames": (1, 481, 4), "in_place": True, "loop": True, "stand": True, "lower": 24.0},
    "type_sit": {"fbx": "typing/typing.fbx", "frames": (1, 481, 4), "in_place": True, "loop": True, "floor": True},
    "hose": {"fbx": "watering/watering.fbx", "frames": (1, 333, 3), "in_place": True, "loop": True},
    "situp_in": {"fbx": "idle_to_situp/idle_to_situp.fbx", "frames": (1, 233, 3), "in_place": False, "loop": False, "floor": True},
    "situps": {"fbx": "situps/situps.fbx", "frames": (1, 133, 3), "in_place": True, "loop": True, "floor": True},
    "situp_out": {"fbx": "situp_to_idle/situp_to_idle.fbx", "frames": (1, 265, 3), "in_place": False, "loop": False, "floor": True},
    "kettlebell": {"fbx": "kettlebell_swing/kettlebell_swing.fbx", "frames": (1, 117, 2), "in_place": True, "loop": True, "floor": True},
    "front_raise": {"fbx": "front_raises/front_raises.fbx", "frames": (1, 372, 3), "in_place": True, "loop": True},
    "bicep_curl": {"fbx": "bicep_curl/bicep_curl.fbx", "frames": (1, 353, 2), "in_place": True, "loop": True},
    # in and out of a golf cart, standing at its side to sat in its seat and back
    "enter_cart": {"fbx": "enter_cart/enter_cart.fbx", "frames": (1, 217, 3), "in_place": False, "loop": False, "floor": True},
    "exit_cart": {"fbx": "exit_cart/exit_cart.fbx", "frames": (1, 217, 3), "in_place": False, "loop": False, "floor": True},
    "enter_cart_m": {"fbx": "enter_cart/enter_cart.fbx", "frames": (1, 217, 3), "in_place": False, "loop": False, "floor": True, "mirror": True},
    "exit_cart_m": {"fbx": "exit_cart/exit_cart.fbx", "frames": (1, 217, 3), "in_place": False, "loop": False, "floor": True, "mirror": True},
}
# our rig's .L bones are the character's right, so they take Mixamo's Right* bones
CAPTURE_MAP = {"hips": "Hips", "spine": "Spine", "chest": "Spine2", "neck": "Neck", "head": "Head",
               "upper_arm.L": "RightArm", "forearm.L": "RightForeArm", "hand.L": "RightHand",
               "upper_arm.R": "LeftArm", "forearm.R": "LeftForeArm", "hand.R": "LeftHand",
               "thigh.L": "RightUpLeg", "shin.L": "RightLeg", "foot.L": "RightFoot",
               "thigh.R": "LeftUpLeg", "shin.R": "LeftLeg", "foot.R": "LeftFoot"}
_captures = {}
_retargeted = {}
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


def lin(h):
    c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c) + (1.0,)


# role -> shirt, pants, shoes, accent, detail, accessories
ROLES = {
    "greenskeeper": ("2f6b3a", "8a7a5c", "4a3a2a", "2f6b3a", "e8e2d0", ("cap",)),
    "marshal": ("27324d", "c3a77f", "3a2e24", "27324d", "f2d27c", ("cap",)),
    "shop_clerk": ("2d5a3d", "c3a77f", "2a2a2a", "f5f3ee", "f2d27c", ("badge",)),
    "receptionist": ("27324d", "4a4f55", "151515", "f5f3ee", "c9a24e", ("badge", "blazer")),
    "locker_attendant": ("f5f3ee", "1d1f22", "151515", "2d5a3d", "2d5a3d", ("badge",)),
    "chef": ("f7f7f3", "2a2a2a", "151515", "f7f7f3", "1d1f22", ("chef_hat", "apron")),
    "waiter": ("f7f7f3", "151515", "151515", "151515", "151515", ("vest", "bowtie")),
    "bartender": ("1d1f22", "1d1f22", "151515", "6b1f2a", "c9a24e", ("apron", "badge")),
    "cart_attendant": ("2f6b3a", "1d1f22", "2a2a2a", "2f6b3a", "e8e2d0", ("cap",)),
    "range_attendant": ("9d2f34", "c3a77f", "2a2a2a", "f5f3ee", "9d2f34", ("visor",)),
    "event_staff": ("151515", "151515", "151515", "f7f7f3", "c9a24e", ("blazer", "bowtie")),
    "trainer": ("2a8f8a", "1d1f22", "f0f0f0", "1d1f22", "f0f0f0", ()),
    "golf_pro": ("f5f3ee", "27324d", "f0f0f0", "27324d", "2d5a3d", ("visor",)),
    "valet": ("c92d33", "151515", "151515", "f5f3ee", "c9a24e", ("polo", "cap")),
}

# golfer look -> shirt (polo), pants, shoes, accent (cap / visor), detail, accessories, female
GOLFERS = {
    "a": ("27324d", "c3a77f", "f0f0f0", "f5f3ee", "f5f3ee", ("cap",), False),
    "b": ("9d2f34", "5a5e63", "f0f0f0", "f5f3ee", "f5f3ee", ("visor",), False),
    "c": ("f5f3ee", "27324d", "6b4a2f", "27324d", "27324d", ("cap",), False),
    "d": ("3f7a4f", "d8ccb0", "151515", "f5f3ee", "f5f3ee", (), True),
    "e": ("7fb6d8", "f5f3ee", "f0f0f0", "f5f3ee", "27324d", ("visor",), True),
    "f": ("e8c547", "27324d", "f0f0f0", "27324d", "27324d", ("cap",), False),
    "g": ("e2725b", "27324d", "f0f0f0", "f5f3ee", "f5f3ee", ("visor",), True),
    "h": ("8fc1e3", "5a5e63", "151515", "27324d", "27324d", ("cap",), False),
    "i": ("f5f3ee", "2b2b2e", "f0f0f0", "2b2b2e", "2b2b2e", ("cap",), True),
    "j": ("3a3d42", "c3a77f", "6b4a2f", "f5f3ee", "f5f3ee", (), False),
    "k": ("e7a1b8", "f5f3ee", "f0f0f0", "e7a1b8", "e7a1b8", ("visor",), True),
    "l": ("27324d", "d8ccb0", "f0f0f0", "f5f3ee", "f5f3ee", ("cap",), True),
}

BONES = [
    # name, head, tail, parent
    ("root", (0, 0, 0), (0, 0.2, 0), None),
    ("hips", (0, 0, 0.92), (0, 0, 1.08), "root"),
    ("spine", (0, 0, 1.08), (0, 0, 1.28), "hips"),
    ("chest", (0, 0, 1.28), (0, 0, 1.46), "spine"),
    ("neck", (0, 0, 1.46), (0, 0, 1.54), "chest"),
    ("head", (0, 0, 1.54), (0, 0, 1.78), "neck"),
    ("upper_arm.L", (0.2, 0, 1.42), (0.23, 0, 1.15), "chest"),
    ("forearm.L", (0.23, 0, 1.15), (0.24, 0.02, 0.9), "upper_arm.L"),
    ("hand.L", (0.24, 0.02, 0.9), (0.24, 0.03, 0.8), "forearm.L"),
    ("upper_arm.R", (-0.2, 0, 1.42), (-0.23, 0, 1.15), "chest"),
    ("forearm.R", (-0.23, 0, 1.15), (-0.24, 0.02, 0.9), "upper_arm.R"),
    ("hand.R", (-0.24, 0.02, 0.9), (-0.24, 0.03, 0.8), "forearm.R"),
    ("thigh.L", (0.1, 0, 0.92), (0.1, 0.01, 0.5), "hips"),
    ("shin.L", (0.1, 0.01, 0.5), (0.1, 0, 0.09), "thigh.L"),
    ("foot.L", (0.1, 0, 0.09), (0.1, 0.16, 0.04), "shin.L"),
    ("thigh.R", (-0.1, 0, 0.92), (-0.1, 0.01, 0.5), "hips"),
    ("shin.R", (-0.1, 0.01, 0.5), (-0.1, 0, 0.09), "thigh.R"),
    ("foot.R", (-0.1, 0, 0.09), (-0.1, 0.16, 0.04), "shin.R"),
]
NAMES = [b[0] for b in BONES]


class Part:
    """Geometry for one skinned mesh: faces with material names, verts weighted to one bone."""

    def __init__(self):
        self.bm = bmesh.new()
        self.dl = self.bm.verts.layers.deform.verify()
        self.mats = []

    def mi(self, m):
        if m not in self.mats:
            self.mats.append(m)
        return self.mats.index(m)

    def _add(self, src, mat, bone, matrix, smooth=True):
        gi = NAMES.index(bone)
        vmap = {}
        for v in src.verts:
            nv = self.bm.verts.new(matrix @ v.co)
            nv[self.dl][gi] = 1.0
            vmap[v] = nv
        for f in src.faces:
            try:
                nf = self.bm.faces.new([vmap[v] for v in f.verts])
            except ValueError:
                continue
            nf.material_index = self.mi(mat)
            nf.smooth = smooth
        src.free()

    def blob(self, center, size, mat, bone, subdiv=2, rot=None):
        src = bmesh.new()
        bmesh.ops.create_icosphere(src, subdivisions=subdiv, radius=0.5)
        m = Matrix.Translation(Vector(center)) @ (rot or Matrix.Identity(4)) @ Matrix.Diagonal(Vector(tuple(size) + (1,)))
        self._add(src, mat, bone, m)

    def capsule(self, a, b, r0, r1, mat, bone, segs=10):
        """A tapered capsule from point a to b (rounded ends)."""
        a, b = Vector(a), Vector(b)
        d = b - a
        ln = d.length
        src = bmesh.new()
        bmesh.ops.create_cone(src, cap_ends=True, segments=segs, radius1=r0, radius2=r1, depth=ln)
        rot = d.to_track_quat("Z", "Y").to_matrix().to_4x4()
        self._add(src, mat, bone, Matrix.Translation((a + b) * 0.5) @ rot)
        self.blob(a, (r0 * 2, r0 * 2, r0 * 2), mat, bone, 1)
        self.blob(b, (r1 * 2, r1 * 2, r1 * 2), mat, bone, 1)

    def box(self, center, size, mat, bone, bevel=0.02, rx=0.0):
        src = bmesh.new()
        bmesh.ops.create_cube(src, size=1.0)
        bmesh.ops.scale(src, vec=Vector(size), verts=src.verts)
        if bevel > 0:
            bmesh.ops.bevel(src, geom=src.verts[:] + src.edges[:], offset=bevel, segments=2, affect="EDGES", profile=0.5, clamp_overlap=True)
        self._add(src, mat, bone, Matrix.Translation(Vector(center)) @ Matrix.Rotation(rx, 4, "X"), smooth=False)

    def cyl(self, base, r0, r1, h, mat, bone, segs=14):
        src = bmesh.new()
        bmesh.ops.create_cone(src, cap_ends=True, segments=segs, radius1=r0, radius2=r1, depth=h)
        self._add(src, mat, bone, Matrix.Translation(Vector(base) + Vector((0, 0, h * 0.5))))


def body(P, female=False):
    sk, sh, pa, so, hr = "skin", "shirt", "pants", "shoes", "hair"
    # legs + shoes
    for s, side in ((1, "L"), (-1, "R")):
        P.capsule((0.1 * s, 0.0, 0.9), (0.1 * s, 0.01, 0.52), 0.085, 0.07, pa, "thigh." + side)
        P.capsule((0.1 * s, 0.01, 0.5), (0.1 * s, 0.0, 0.12), 0.065, 0.055, pa, "shin." + side)
        P.box((0.1 * s, 0.05, 0.05), (0.11, 0.26, 0.1), so, "foot." + side, 0.03)
    # hips, torso, shoulders
    P.blob((0, 0, 0.98), (0.36, 0.22, 0.26), pa, "hips")
    P.blob((0, 0, 1.16), (0.36, 0.22, 0.34), sh, "spine")
    P.blob((0, 0, 1.34), (0.42, 0.25, 0.3), sh, "chest")
    for s, side in ((1, "L"), (-1, "R")):
        P.blob((0.19 * s, 0, 1.4), (0.14, 0.14, 0.14), sh, "chest", 1)
        P.capsule((0.21 * s, 0.0, 1.38), (0.23 * s, 0.0, 1.17), 0.055, 0.048, sh, "upper_arm." + side)
        P.capsule((0.23 * s, 0.0, 1.14), (0.24 * s, 0.02, 0.92), 0.045, 0.04, sk, "forearm." + side)
        P.blob((0.24 * s, 0.025, 0.86), (0.07, 0.05, 0.1), sk, "hand." + side, 1)
    # neck, head, face, hair
    P.capsule((0, 0, 1.46), (0, 0.005, 1.56), 0.05, 0.05, sk, "neck")
    P.blob((0, 0.01, 1.66), (0.21, 0.22, 0.25), sk, "head")
    P.blob((0, 0.12, 1.65), (0.035, 0.04, 0.04), sk, "head", 1)
    for s in (1, -1):
        P.blob((0.05 * s, 0.105, 1.69), (0.03, 0.02, 0.035), "detail", "head", 1)
        P.blob((0.105 * s, 0.0, 1.66), (0.035, 0.05, 0.06), sk, "head", 1)
    P.blob((0, -0.01, 1.73), (0.225, 0.235, 0.16), hr, "head")
    P.blob((0, -0.06, 1.66), (0.21, 0.14, 0.2), hr, "head")
    if female:
        P.blob((0, -0.12, 1.6), (0.12, 0.1, 0.16), hr, "head")


def accessories(P, items):
    for it in items:
        if it == "cap":
            P.blob((0, 0.0, 1.76), (0.235, 0.245, 0.13), "accent", "head")
            P.box((0, 0.15, 1.735), (0.18, 0.13, 0.02), "accent", "head", 0.008, rx=0.15)
        elif it == "visor":
            P.cyl((0, 0, 1.71), 0.118, 0.118, 0.05, "accent", "head")
            P.box((0, 0.15, 1.73), (0.19, 0.13, 0.02), "accent", "head", 0.008, rx=0.15)
        elif it == "chef_hat":
            P.cyl((0, 0, 1.72), 0.115, 0.13, 0.08, "accent", "head")
            P.blob((0, 0, 1.88), (0.3, 0.3, 0.2), "accent", "head")
        elif it == "apron":
            P.box((0, 0.125, 1.08), (0.32, 0.02, 0.42), "accent", "spine", 0.01)
            P.box((0, 0.13, 1.3), (0.2, 0.02, 0.18), "accent", "chest", 0.01)
        elif it == "vest":
            for s in (1, -1):
                P.box((0.08 * s, 0.112, 1.26), (0.13, 0.03, 0.36), "accent", "chest", 0.02)
        elif it == "blazer":
            for s in (1, -1):
                P.box((0.12 * s, 0.11, 1.22), (0.16, 0.035, 0.46), "shirt", "chest", 0.02)
                P.box((0.06 * s, 0.13, 1.34), (0.04, 0.02, 0.2), "accent", "chest", 0.005)
        elif it == "bowtie":
            P.box((0, 0.13, 1.44), (0.1, 0.03, 0.04), "detail", "chest", 0.01)
        elif it == "polo":
            P.box((0, 0.1, 1.43), (0.16, 0.06, 0.05), "shirt", "chest", 0.015)
            P.box((0, 0.125, 1.37), (0.025, 0.012, 0.09), "detail", "chest", 0.004)
        elif it == "badge":
            P.box((0.09, 0.13, 1.36), (0.07, 0.01, 0.03), "detail", "chest", 0.004)


# how each uniform is cut: long sleeves, shorts (the rest: short sleeves, long trousers)
LONG_SLEEVES = ("receptionist", "chef", "waiter", "bartender", "event_staff", "valet", "golfer_i", "golfer_j")  # quarter-zips
SHORTS = ("trainer", "golfer_e", "golfer_b", "golfer_g", "golfer_k")


def make_materials(role):
    shirt, pants, shoes, accent, detail = (ROLES[role] if role in ROLES else GOLFERS[role[len("golfer_"):]])[:5]
    cols = {"skin": "d9a27e", "hair": "3b2a1f", "shirt": shirt, "pants": pants, "shoes": shoes, "accent": accent, "detail": detail}
    out = {}
    for name, h in cols.items():
        m = bpy.data.materials.new(name)
        try:
            m.use_nodes = True
        except Exception:
            pass
        p = m.node_tree.nodes.get("Principled BSDF")
        p.inputs["Base Color"].default_value = lin(h)
        p.inputs["Roughness"].default_value = 0.75 if name not in ("shoes", "hair") else 0.5
        out[name] = m
    return out


def build_rig(name, C):
    ad = bpy.data.armatures.new(name)
    arm = bpy.data.objects.new(name, ad)
    C.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    for bn, h, t, par in BONES:
        eb = ad.edit_bones.new(bn)
        eb.head, eb.tail = h, t
        eb.roll = 0.0
        if par:
            eb.parent = ad.edit_bones[par]
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


def skinned(name, P, mats, arm, C):
    me = bpy.data.meshes.new(name)
    ob = bpy.data.objects.new(name, me)
    C.objects.link(ob)
    for bn in NAMES:
        ob.vertex_groups.new(name=bn)
    P.bm.normal_update()
    P.bm.to_mesh(me)
    P.bm.free()
    for m in P.mats:
        me.materials.append(mats[m])
    ob.parent = arm
    mod = ob.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    return ob


# ---------------------------------------------------------------- animation

def key_pose(arm, frame, pose, loc=None):
    for bn in NAMES:
        pb = arm.pose.bones[bn]
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = Euler(pose.get(bn, (0, 0, 0)), "XYZ").to_quaternion()
        pb.keyframe_insert("rotation_quaternion", frame=frame)
    hb = arm.pose.bones["hips"]
    hb.location = loc or (0, 0, 0)
    hb.keyframe_insert("location", frame=frame)


def make_action(arm, name, keys):
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    arm.animation_data_create()
    arm.animation_data.action = act
    for frame, pose, loc in keys:
        key_pose(arm, frame, pose, loc)
    for fc in _fcurves(act):
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR" if name == "swing" else "BEZIER"
    track = arm.animation_data.nla_tracks.new()
    track.name = name
    track.strips.new(name, int(keys[0][0]), act)
    arm.animation_data.action = None
    return act


def _fcurves(act):
    if hasattr(act, "fcurves") and len(getattr(act, "fcurves", [])):
        return act.fcurves
    out = []
    for layer in getattr(act, "layers", []):
        for strip in layer.strips:
            for bag in getattr(strip, "channelbags", []):
                out.extend(bag.fcurves)
    return out


# Fitted to the golf cart (tools/blender/import_cart.py) from each rider's own origin
# (ClubLife.SEATS), in rig space (y forward, z up; the .L bones are on +x, the .R on -x): the
# driver's wrists grip the steering wheel's rim at ten to two, each hand on its own side (the
# other way about, the arms crossed over at the wheel); everyone's ankles rest on the cart's
# floor, each under its own knee.
DRIVE_GRIP = {"forearm.L": (0.15, 0.6, 0.76), "forearm.R": (-0.15, 0.6, 0.76)}
CART_FEET = {"shin.L": (0.12, 0.4, -0.08), "shin.R": (-0.12, 0.4, -0.08)}


def _posed(arm, pose, loc):
    """Hold `pose` on the rig (no keys; the NLA is muted so it isn't overridden)."""
    arm.animation_data_create()
    arm.animation_data.use_nla = False
    for bn in NAMES:
        pb = arm.pose.bones[bn]
        pb.rotation_mode = "XYZ"
        pb.rotation_euler = pose.get(bn, (0, 0, 0))
    arm.pose.bones["hips"].location = loc
    bpy.context.view_layer.update()


def lap(arm, pose, loc):
    """Where the wrists rest in the lap of `pose`: on the tops of the thighs, half way down."""
    _posed(arm, pose, loc)
    out = {}
    for s in ("L", "R"):
        pb = arm.pose.bones["thigh." + s]
        mid = pb.head.lerp(pb.tail, 0.55)
        out["forearm." + s] = (mid.x * 0.8, mid.y, mid.z + 0.1)
    arm.animation_data.use_nla = True
    return out


def reach(arm, pose, loc, targets):
    """`pose` with limbs bent by IK so the tail of each targets bone (a forearm: the wrist; a
    shin: the ankle) meets its target (rig space); the two bones' resulting turns go back into
    the pose as plain rotations."""
    _posed(arm, pose, loc)
    empties = []
    for bn, t in targets.items():
        e = bpy.data.objects.new("ik_" + bn, None)
        e.location = t
        bpy.context.scene.collection.objects.link(e)
        c = arm.pose.bones[bn].constraints.new("IK")
        c.target = e
        c.chain_count = 2
        empties.append(e)
    bpy.context.view_layer.update()
    out = dict(pose)
    for bn in targets:
        for pb in (arm.pose.bones[bn].parent, arm.pose.bones[bn]):
            m = arm.convert_space(pose_bone=pb, matrix=pb.matrix, from_space="POSE", to_space="LOCAL")
            out[pb.name] = tuple(m.to_euler("XYZ"))
    for bn in targets:
        pb = arm.pose.bones[bn]
        pb.constraints.remove(pb.constraints[-1])
    for e in empties:
        bpy.data.objects.remove(e)
    arm.animation_data.use_nla = True
    return out


def capture_source(clip):
    """A capture's bones in world space, turned to face our way (+Y, its right side on +X):
    {"rest": {bone: Matrix}, "frames": [(frame, {bone: Matrix})], "fps"}. Read once (every
    person shares it); None without the file."""
    if clip in _captures:
        return _captures[clip]
    cfg = CAPTURES[clip]
    path = os.path.join(ANIMS, cfg["fbx"])
    if not os.path.exists(path):
        _captures[clip] = None
        return None
    objs, acts = set(bpy.data.objects), set(bpy.data.actions)
    sc = bpy.context.scene
    fps = (sc.render.fps, sc.render.fps_base)  # the import sets the clip's own rate
    bpy.ops.import_scene.fbx(filepath=path)
    rate = sc.render.fps / sc.render.fps_base
    new = [o for o in bpy.data.objects if o not in objs]
    src = next(o for o in new if o.type == "ARMATURE")
    names = {b.name.split(":")[-1]: b.name for b in src.data.bones}
    first, last, step = cfg["frames"]
    # which way it faces on its first frame: up crossed with its right (shoulder to shoulder)
    sc.frame_set(first)
    right = (src.matrix_world @ src.pose.bones[names["RightArm"]].head) - (src.matrix_world @ src.pose.bones[names["LeftArm"]].head)
    ahead = Vector((0, 0, 1)).cross(right)
    mw = Matrix.Rotation(math.pi / 2 - math.atan2(ahead.y, ahead.x), 4, "Z") @ src.matrix_world
    wanted = set(CAPTURE_MAP.values())
    rest = {k: mw @ src.data.bones[names[k]].matrix_local for k in wanted}
    frames = []
    for f in range(first, last + 1, step):
        sc.frame_set(f)
        frames.append((f, {k: mw @ src.pose.bones[names[k]].matrix for k in wanted}))
    sc.frame_set(1)
    sc.render.fps, sc.render.fps_base = fps
    # the clip turns the character away from the way its rest pose faces: turn the rest to face
    # the way the first frame does (by the hips' sideways axis), so a bone's turn from rest is
    # the swing's alone
    side = Vector((1, 0, 0))
    r0 = (rest["Hips"].to_3x3() @ side) * Vector((1, 1, 0))
    p0 = (frames[0][1]["Hips"].to_3x3() @ side) * Vector((1, 1, 0))
    yaw = Matrix.Rotation(math.atan2(r0.cross(p0).z, r0.dot(p0)), 4, "Z")
    rest = {k: yaw @ m for k, m in rest.items()}
    if cfg.get("mirror"):
        # left for right: each bone takes its twin's matrices reflected across the body's middle
        # (x -> -x; a turn reflected so is still a turn)
        flip = Matrix.Scale(-1, 4, Vector((1, 0, 0)))

        def twin(k):
            return "Left" + k[5:] if k.startswith("Right") else ("Right" + k[4:] if k.startswith("Left") else k)
        rest = {k: flip @ rest[twin(k)] @ flip for k in rest}
        frames = [(f, {k: flip @ m[twin(k)] @ flip for k in m}) for f, m in frames]
    for o in new:
        bpy.data.objects.remove(o, do_unlink=True)
    for a in set(bpy.data.actions) - acts:
        bpy.data.actions.remove(a)
    _captures[clip] = {"rest": rest, "frames": frames, "fps": rate}
    return _captures[clip]



"""Two palm surfaces on one grip; the forearms are solved outside that contact."""
def turn_golf_torso(arm, seconds):
    # Remove the capture's extra chest winding after impact and finish facing
    # downrange, with the shoulders turning farther than the hips.
    blend=max(0,min(1,(seconds-1.20)/.45));blend=blend*blend*(3-2*blend)
    if blend<=0:return
    bones=arm.pose.bones
    legs={name:bones[name].matrix.to_3x3().copy() for name in NAMES if name.startswith(('thigh.','shin.','foot.'))}
    for name, degrees in (('hips',60),('spine',100),('chest',140),('neck',112),('head',90)):
        bone=bones[name]
        rotation=bone.matrix.to_3x3()
        side=rotation@bone.bone.matrix_local.to_3x3().inverted()@Vector((1,0,0))
        yaw=math.atan2(side.y,side.x)
        delta=(math.radians(degrees)-yaw+math.pi)%(2*math.pi)-math.pi
        bone.matrix=Matrix.Translation(bone.head)@(Matrix.Rotation(delta*blend,3,'Z')@rotation).to_4x4()
        bpy.context.view_layer.update()
    for name, rotation in legs.items():
        bones[name].matrix=Matrix.Translation(bones[name].head)@rotation.to_4x4()
        bpy.context.view_layer.update()


def fit_golf_palms(arm, src, rest, seconds):
    bones=arm.pose.bones
    sides=('L','R')
    hands={s:bones['hand.'+s].matrix.copy() for s in sides}
    local={s:Vector(arm['palm_contact_'+s]) for s in sides}
    local_normal={s:Vector(arm['palm_normal_'+s]) for s in sides}
    source_shoulder=(src['RightArm'].translation+src['LeftArm'].translation)*.5
    shoulder={s:bones['upper_arm.'+s].head.copy() for s in sides}
    midpoint=(shoulder['L']+shoulder['R'])*.5
    source_length=sum((rest[p+'ForeArm'].translation-rest[p+'Arm'].translation).length+(rest[p+'Hand'].translation-rest[p+'ForeArm'].translation).length for p in ('Right','Left'))*.5
    target_length=sum(bones['upper_arm.'+s].length+bones['forearm.'+s].length for s in sides)*.5
    scale=target_length/source_length
    side=(shoulder['L']-shoulder['R'])*Vector((1,1,0));side.normalize()
    source_side=(src['RightArm'].translation-src['LeftArm'].translation)*Vector((1,1,0));source_side.normalize()
    yaw=math.atan2(source_side.cross(side).z,source_side.dot(side))
    mapping=Matrix.Rotation(yaw,3,'Z')
    center=sum((midpoint+mapping@(src[p+'Hand'].translation-source_shoulder)*scale+hands[s].to_3x3()@local[s] for s,p in (('L','Right'),('R','Left'))),Vector())*.5
    up=Vector((0,0,1));forward=up.cross(side).normalized()
    if seconds<.001 or not hasattr(fit_golf_palms,'state'):
        direction=(Vector((0,.78,.045))-center).normalized()
        fit_golf_palms.state={'axis':hands['L'].to_3x3().inverted()@direction,'previous':None}
    state=fit_golf_palms.state
    direction=(hands['L'].to_3x3()@state['axis']).normalized()
    # The new capture's lowest pass is frame 36 (1.1667 seconds).
    impact=1.1666666667
    blend=max(0,1-abs(seconds-impact)/.11)
    blend=blend*blend*(3-2*blend)
    contact=(Vector((0,.78,.045))-center).normalized()
    direction=direction.slerp(contact,blend).normalized()
    # Fold the trail arm across the chest; stacked hands finish beside the lead shoulder.
    # The shaft clears the back of the neck rather than cutting across the head.
    settle=max(0,min(1,(seconds-1.50)/.45));settle=settle*settle*(3-2*settle)
    desired=shoulder['R']-side*.10+forward*.12+up*.20
    center=center.lerp(desired,settle)
    finish_direction=(side*.80-forward*.90-up*.24).normalized()
    delta=direction.rotation_difference(finish_direction).slerp(Matrix.Identity(3).to_quaternion(),1-settle)
    for s in sides:hands[s]=Matrix.Translation(hands[s].translation)@(delta.to_matrix()@hands[s].to_3x3()).to_4x4()
    direction=direction.slerp(finish_direction,settle).normalized()
    # Opposed surface normals make the palms touch; wrist origins may differ
    # because the hands have thickness. They are never placed through each other.
    normals={s:(hands[s].to_3x3()@local_normal[s]).normalized() for s in sides}
    normal=(normals['L']-normals['R']).normalized()
    normal=(normal-direction*normal.dot(direction)).normalized()
    if normal.length<.1:normal=direction.cross(forward).normalized()
    rotations={}
    for s,sign in (('L',1),('R',-1)):
        turn=normals[s].rotation_difference(normal*sign).to_matrix()
        rotations[s]=turn@hands[s].to_3x3()
    offsets={s:direction*(sign*(.0125+.0015*settle))-normal*(sign*.001*(1-settle))-rotations[s]@local[s] for s,sign in (('L',1),('R',-1))}
    # Keep the whole shaft outside the head while the wrists travel into the finish.
    # Solve this together with arm reach, rather than correcting only the last pose.
    head_axis=(bones['head'].matrix.to_3x3()@Vector((0,1,0))).normalized()
    head_points=[bones['head'].head+head_axis*(.045+i*.110/8) for i in range(9)]
    guard=max(0,min(1,(seconds-1.45)/.15));guard=guard*guard*(3-2*guard)
    for iteration in range(32):
        for s in sides:
            reach=center+offsets[s]-shoulder[s]
            limit=bones['upper_arm.'+s].length+bones['forearm.'+s].length-.005
            if reach.length>limit:center-=reach.normalized()*(reach.length-limit)
        if guard>0:
            grip=center+direction*(.0125+.0015*settle)
            clearance=min((point-(grip+direction*max(0,min(1.15,(point-grip).dot(direction))))).length for point in head_points)
            if clearance<.145*guard:
                center-=forward*min(.012,.145*guard-clearance+.001)
    targets={s:center+offsets[s] for s in sides}
    torso_up=(bones['neck'].head-bones['hips'].head).normalized()
    torso_forward=torso_up.cross(side).normalized()
    torso_side=torso_forward.cross(torso_up).normalized()
    torso_center=bones['hips'].head.lerp(bones['neck'].head,.55)
    torso_half=(bones['neck'].head-bones['hips'].head).length*.55+.035
    def body_cost(a,elbow,wrist):
        first=a.lerp(elbow,min(1,.065/(elbow-a).length))
        worst=1.0
        for start,end in ((first,elbow),(elbow,wrist)):
            for k in range(9):
                q=start.lerp(end,k/8)-torso_center
                value=((q.dot(torso_side)/.185)**2+(q.dot(torso_forward)/.155)**2+(q.dot(torso_up)/torso_half)**2)**.5
                worst=min(worst,value)
        return max(0,1-worst)**2*100000
    solutions={}
    for s,p,sign in (('L','Right',1),('R','Left',-1)):
        a=shoulder[s];b=targets[s]
        axis=(b-a).normalized();distance=(b-a).length
        first,second=bones['upper_arm.'+s].length,bones['forearm.'+s].length
        along=(first*first-second*second+distance*distance)/(2*distance)
        height=max(0,first*first-along*along)**.5
        source_elbow=midpoint+mapping@(src[p+'ForeArm'].translation-source_shoulder)*scale
        finish_pole=midpoint+side*(-.16 if s=='L' else -.40)+forward*(.27 if s=='L' else .12)+up*(.045 if s=='L' else .02)
        source_elbow=source_elbow.lerp(finish_pole,settle)
        pole=source_elbow-a+side*(sign*.045)-up*.025
        pole=(pole-axis*pole.dot(axis)).normalized()
        if state['previous']:
            previous=state['previous'][s]-a
            previous=(previous-axis*previous.dot(axis)).normalized()
            pole=(pole*.55+previous*.45).normalized()
        candidates=[]
        for angle in (0,.05,-.05,.10,-.10,.15,-.15,.22,-.22,.3,-.3,.4,-.4,.5,-.5,.65,-.65,.8,-.8,1.0,-1.0,1.2,-1.2,1.7,-1.7,2.2,-2.2,math.pi):
            elbow=a+axis*along+(Matrix.Rotation(angle,3,axis)@pole)*height
            low_elbow=max(0,elbow.z-(bones['head'].head.z-.08))**2*100000*settle if s=='L' else 0
            # The trail elbow must wrap across the FRONT of the chest, never the back.
            front_elbow=max(0,.10-(elbow-midpoint).dot(forward))**2*1000000*settle if s=='L' else 0
            candidates.append((elbow,angle,body_cost(a,elbow,b)+low_elbow+front_elbow))
        solutions[s]=candidates
    def distance(a,b,c,d):
        u,v,w=b-a,d-c,a-c
        aa,bb,cc,dd,ee=u.dot(u),u.dot(v),v.dot(v),u.dot(w),v.dot(w)
        denominator=aa*cc-bb*bb
        x=max(0,min(1,(bb*ee-cc*dd)/denominator)) if denominator>1e-10 else 0
        y=0
        for iteration in range(12):
            y=max(0,min(1,(bb*x+ee)/cc)) if cc>1e-10 else 0
            x=max(0,min(1,(bb*y-dd)/aa)) if aa>1e-10 else 0
        return ((a+u*x)-(c+v*y)).length
    best=None
    for left,la,lc in solutions['L']:
        for right,ra,rc in solutions['R']:
            # Hands meet at the grip; the forearm test stops at the wrist cuff.
            wl=targets['L'].lerp(left,min(1,.055/(targets['L']-left).length))
            wr=targets['R'].lerp(right,min(1,.055/(targets['R']-right).length))
            clearance=min(distance(a,b,c,d) for a,b in ((shoulder['L'],left),(left,wl)) for c,d in ((shoulder['R'],right),(right,wr)))
            cost=la*la+ra*ra+lc+rc+max(0,.075+.01*settle-clearance)**2*(100000+200000*settle)
            if state['previous']:cost+=sum((e-state['previous'][s]).length_squared*30 for s,e in (('L',left),('R',right)))
            if best is None or cost<best[0]:best=(cost,{'L':left,'R':right})
    state['previous']=best[1]
    for s in sides:
        elbow=best[1][s]
        hinge=(elbow-shoulder[s]).cross(targets[s]-elbow).normalized()
        for bone,end in ((bones['upper_arm.'+s],best[1][s]),(bones['forearm.'+s],targets[s])):
            start=bone.head.copy()
            direction=(end-start).normalized()
            rest_rotation=bone.bone.matrix_local.to_3x3()
            rest_y=rest_rotation@Vector((0,1,0))
            rest_hinge=(Vector((1,0,0))-rest_y*rest_y.x).normalized()
            source_frame=Matrix((rest_hinge,rest_y,rest_hinge.cross(rest_y))).transposed()
            target_frame=Matrix((hinge,direction,hinge.cross(direction))).transposed()
            rotation=target_frame@source_frame.inverted()@rest_rotation
            bone.matrix=Matrix.Translation(start)@rotation.to_4x4()
            bpy.context.view_layer.update()
        bones['hand.'+s].matrix=Matrix.Translation(targets[s])@rotations[s].to_4x4()
        bpy.context.view_layer.update()



def captured(arm, clip):
    """A clip's keys retargeted from its capture onto `arm` (24 fps), or None without it. The
    torso turns from its rest the way the capture's does from its own; the limbs point the
    way the capture's point (its rest is a T-pose with the feet pointing down, ours arms-down
    with the feet forward); the hips carry its weight shift scaled to our height (bar the
    travel, for a clip done in place); a looping clip ends on its first pose."""
    bpy.context.view_layer.update()
    signature=(clip,tuple((b.name,tuple(round(v,6) for v in b.head_local),tuple(round(v,6) for v in b.tail_local)) for b in arm.data.bones))
    if signature in _retargeted:
        return _retargeted[signature]
    data = capture_source(clip)
    if data is None:
        return None
    cfg = CAPTURES[clip]
    inv = arm.matrix_world.inverted()
    rest = {pb.name: arm.matrix_world @ pb.bone.matrix_local for pb in arm.pose.bones}
    scale = rest["hips"].translation.z / data["rest"]["Hips"].translation.z
    hips0 = data["frames"][0][1]["Hips"].translation.copy()
    if cfg.get("floor"):
        hips0.z = data["rest"]["Hips"].translation.z  # (its height from the floor, not from where it starts)
    # A fixed rest-roll correspondence preserves the capture's wrist and
    # finger twist. Recomputing a shortest-arc turn each frame loses it.
    roll = {}
    for name, source in CAPTURE_MAP.items():
        if name.startswith(("upper_arm", "forearm", "hand", "finger_")):
            source_rest=data["rest"][source].to_3x3().normalized()
            target_rest=rest[name].to_3x3().normalized()
            align=(source_rest@Vector((0,1,0))).rotation_difference(target_rest@Vector((0,1,0))).to_matrix()
            roll[name]=source_rest.inverted()@align.inverted()@target_rest
    order = [n for n in NAMES if n in CAPTURE_MAP]  # parents first
    arm.animation_data_create()
    arm.animation_data.use_nla = False
    arm.animation_data.action = None
    keys, prev = [], {}
    up = Vector((0, 1, 0))
    frames = data["frames"]
    if clip == "swing":
        # Solve on half-frames as well; the two hands stay together through
        # the rapid transition from impact to the raised finish.
        dense = []
        for (fa, a), (fb, b) in zip(frames, frames[1:]):
            dense.extend([(fa, a), ((fa+fb)*.5, {n:a[n].lerp(b[n], .5) for n in a})])
        frames = dense + [frames[-1]]
    for f, src in frames:
        for pb in arm.pose.bones:
            pb.matrix_basis = Matrix.Identity(4)
        bpy.context.view_layer.update()
        for name in order:
            s, pb = CAPTURE_MAP[name], arm.pose.bones[name]
            r = rest[name].to_3x3()
            if cfg.get("stand") and name.startswith(("hips", "thigh", "shin", "foot")):
                # (stood up out of the chair: the hips and legs at rest, the rest of the body
                # turned as the capture's is from there)
                head = rest["hips"].translation if name == "hips" else (arm.matrix_world @ pb.matrix).translation
                pb.matrix = inv @ Matrix.Translation(head) @ r.normalized().to_4x4()
                bpy.context.view_layer.update()
                continue
            if name in roll:
                rot = src[s].to_3x3().normalized() @ roll[name]
            elif name.startswith(("thigh", "shin", "foot")):
                rot = (r @ up).normalized().rotation_difference((src[s].to_3x3() @ up).normalized()).to_matrix() @ r
            else:
                rot = src[s].to_3x3() @ data["rest"][s].to_3x3().inverted() @ r
            if name == "hips":
                shift = (src["Hips"].translation - hips0) * scale
                if cfg["in_place"]:
                    shift.y = 0.0  # it walks along +Y: keep the bob and sway, drop the travel
                head = rest["hips"].translation + shift
            else:
                head = (arm.matrix_world @ pb.matrix).translation
            pb.matrix = inv @ Matrix.Translation(head) @ rot.normalized().to_4x4()
            bpy.context.view_layer.update()

        if cfg.get("lower"):
            # (the arms let down about the shoulders, the hands to a standing counter's height)
            for s in ("L", "R"):
                pb = arm.pose.bones["upper_arm." + s]
                head = (arm.matrix_world @ pb.matrix).translation
                turn = Matrix.Translation(head) @ Matrix.Rotation(math.radians(-cfg["lower"]), 4, "X") @ Matrix.Translation(-head)
                pb.matrix = inv @ turn @ arm.matrix_world @ pb.matrix
                bpy.context.view_layer.update()
        if clip == "swing":
            turn_golf_torso(arm,(f-cfg["frames"][0])/data["fps"])
            fit_golf_palms(arm,src,data["rest"],(f-cfg["frames"][0])/data["fps"])
        pose = {}
        for name in order:
            e = arm.pose.bones[name].matrix_basis.to_euler("XYZ", prev[name]) if name in prev else arm.pose.bones[name].matrix_basis.to_euler("XYZ")
            prev[name] = e
            pose[name] = tuple(e)
        keys.append((1 + (f - cfg["frames"][0]) * 24.0 / data["fps"], pose, tuple(arm.pose.bones["hips"].matrix_basis.translation)))
    if cfg["loop"]:
        keys.append((1 + (cfg["frames"][1] + cfg["frames"][2] - cfg["frames"][0]) * 24.0 / data["fps"], keys[0][1], keys[0][2]))
    for pb in arm.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    arm.animation_data.use_nla = True
    _retargeted[signature] = keys
    return keys


def animations(arm):
    """Idle, walk, work, swing, putt, sit, and in a cart drive and ride. The rig's conventions (measured, in world terms;
    the character faces +Y with its right side on +X, so a right-handed golfer's target is -X):
      spine / chest / head  +X leans back (bend forward and nod down with -X); +Y turns the
                            chest toward the golfer's left (the target)
      arms / legs           +X swings forward; a negative shin bends the knee
      hips location         bone-local: y is up, z is back"""
    r = math.radians
    # every key below counts frames at 24 fps (an FBX import -- the BaseModels body, the motion
    # capture -- leaves the scene at its own 30)
    bpy.context.scene.render.fps, bpy.context.scene.render.fps_base = 24, 1.0
    walk = []
    for i, ph in enumerate((0.0, 0.25, 0.5, 0.75, 1.0)):
        s = math.sin(ph * math.tau)
        pose = {
            "thigh.L": (r(-28 * s), 0, 0), "thigh.R": (r(28 * s), 0, 0),
            "shin.L": (r(-32 * max(0.0, s)), 0, 0), "shin.R": (r(-32 * max(0.0, -s)), 0, 0),
            "upper_arm.L": (r(22 * s), 0, 0), "upper_arm.R": (r(-22 * s), 0, 0),
            "forearm.L": (r(15), 0, 0), "forearm.R": (r(15), 0, 0),
            "chest": (0, r(-5 * s), 0), "head": (0, r(3 * s), 0),
        }
        walk.append((1 + i * 8, pose, (0, 0.025 * abs(math.cos(ph * math.tau)), 0)))
    walk = captured(arm, "walk") or walk  # the motion capture when it's there
    idle = []
    for i, ph in enumerate((0.0, 0.5, 1.0)):
        s = math.sin(ph * math.tau * 0.5)
        idle.append((1 + i * 30, {"chest": (r(1.5 * s), 0, 0), "head": (r(-3 * s), r(5 * s), 0),
                                  "forearm.L": (r(8), 0, 0), "forearm.R": (r(8), 0, 0)}, (0, -0.008 * s, 0)))
    work = []
    for i, ph in enumerate((0.0, 0.25, 0.5, 0.75, 1.0)):
        s = math.sin(ph * math.tau)
        work.append((1 + i * 9, {
            "upper_arm.L": (r(45 + 10 * s), 0, 0), "upper_arm.R": (r(45 - 10 * s), 0, 0),
            "forearm.L": (r(50 - 15 * s), 0, 0), "forearm.R": (r(50 + 15 * s), 0, 0),
            "chest": (r(-8), r(4 * s), 0), "head": (r(-12), r(-6 * s), 0), "spine": (r(-5), 0, 0)}, (0, 0, 0)))
    make_action(arm, "walk", walk)
    make_action(arm, "idle", idle)
    make_action(arm, "work", work)
    make_action(arm, "wipe", work)  # explicit cleaning action; generic workers use breathe
    # a full swing, right-handed (the lead arm is the left, on -X: ".R"): address, the turn
    # away, the top, impact, the turn through, a held finish
    bend = r(-24)
    arms_down = {"upper_arm.L": (r(28), 0, 0), "upper_arm.R": (r(28), 0, 0), "forearm.L": (r(8), 0, 0), "forearm.R": (r(8), 0, 0)}
    knees = {"thigh.L": (r(14), 0, 0), "thigh.R": (r(14), 0, 0), "shin.L": (r(-18), 0, 0), "shin.R": (r(-18), 0, 0)}

    def pose(base, **extra):
        d = dict(knees)
        d.update(base)
        d.update(extra)
        return d
    address = pose(arms_down, spine=(bend, 0, 0), chest=(r(-6), 0, 0), head=(r(-14), 0, 0))
    top = pose({"upper_arm.R": (r(125), 0, 0), "forearm.R": (r(15), 0, 0), "upper_arm.L": (r(100), 0, 0), "forearm.L": (r(85), 0, 0)},
               spine=(bend, r(-30), 0), chest=(r(-6), r(-55), 0), head=(r(-14), r(70), 0))
    impact = pose(arms_down, spine=(bend, r(18), 0), chest=(r(-6), r(6), 0), head=(r(-14), r(-10), 0))
    through = pose({"upper_arm.R": (r(115), 0, 0), "forearm.R": (r(75), 0, 0), "upper_arm.L": (r(130), 0, 0), "forearm.L": (r(25), 0, 0)},
                   spine=(r(-6), r(45), 0), chest=(r(2), r(50), 0), head=(r(2), r(-20), 0))
    finish = pose({"upper_arm.R": (r(125), 0, 0), "forearm.R": (r(95), 0, 0), "upper_arm.L": (r(140), 0, 0), "forearm.L": (r(35), 0, 0)},
                  spine=(r(0), r(55), 0), chest=(r(5), r(55), 0), head=(r(3), r(-15), 0),
                  **{"thigh.L": (r(8), 0, 0), "shin.L": (r(-38), 0, 0)})  # the trail (right) knee in toward the target
    low = (0, -0.04, 0)
    # the motion capture when it's there (impact 1.1 s in, the finish held to 3.3 s:
    # ClubLife.SWING_S and the ball's launch), else the hand-keyed swing
    make_action(arm, "swing", captured(arm, "swing") or [(1, address, low), (12, address, low), (30, top, low), (37, impact, low), (44, through, (0, -0.01, 0)), (54, finish, (0, 0, 0)), (78, finish, (0, 0, 0))])
    # a putting stroke: the motion capture when it's there (impact 1.25 s in, the follow-through
    # held to 2.6 s: ClubLife.PUTT_S and the ball's roll), else bent over, the shoulders rocking the arms
    p_addr = pose({"upper_arm.L": (r(24), 0, 0), "upper_arm.R": (r(24), 0, 0), "forearm.L": (r(12), 0, 0), "forearm.R": (r(12), 0, 0)},
                  spine=(r(-34), 0, 0), chest=(r(-4), 0, 0), head=(r(-18), 0, 0))
    p_back = dict(p_addr, chest=(r(-4), 0, r(7)))
    p_thru = dict(p_addr, chest=(r(-4), 0, r(-8)))
    make_action(arm, "putt", captured(arm, "putt") or [(1, p_addr, low), (14, p_addr, low), (26, p_back, low), (36, p_thru, low), (50, p_thru, low), (60, p_addr, low)])
    # seated, hands in the lap (a passenger, anyone on a chair); the driver leans in a little
    # with both hands on the wheel
    seat = {"thigh.L": (r(84), 0, 0), "thigh.R": (r(84), 0, 0), "shin.L": (r(-86), 0, 0), "shin.R": (r(-86), 0, 0),
            "upper_arm.L": (r(30), 0, 0), "upper_arm.R": (r(30), 0, 0), "forearm.L": (r(50), 0, 0), "forearm.R": (r(50), 0, 0), "spine": (r(4), 0, 0)}
    sat = (0, -0.4, 0.04)  # hips down onto the seat
    sit = reach(arm, seat, sat, lap(arm, seat, sat))
    in_cart = reach(arm, seat, sat, CART_FEET)  # feet down on the cart's floor
    ride = reach(arm, in_cart, sat, lap(arm, in_cart, sat))
    drive = reach(arm, dict(in_cart, spine=(r(-10), 0, 0), chest=(r(-6), 0, 0)), sat, DRIVE_GRIP)
    make_action(arm, "sit", [(1, sit, sat), (40, dict(sit, head=(0, r(8), 0)), sat), (80, sit, sat)])
    make_action(arm, "ride", [(1, ride, sat), (30, dict(ride, head=(r(-4), r(14), 0)), sat), (60, dict(ride, head=(0, r(-6), 0)), sat), (90, ride, sat)])
    make_action(arm, "drive", [(1, drive, sat), (45, dict(drive, head=(0, r(-5), 0)), sat), (90, drive, sat)])
    # the captures with nothing hand-keyed to fall back on: there only when their file is
    for clip in ("breathe", "chip", "carry", "type", "type_sit", "hose", "situp_in", "situps", "situp_out", "kettlebell", "front_raise", "bicep_curl",
                 "enter_cart", "exit_cart", "enter_cart_m", "exit_cart_m"):
        keys = captured(arm, clip)
        if keys:
            make_action(arm, clip, keys)
    # on the elliptical: upright, a hand on each of its swinging handles, the legs striding on
    # its pedals without going anywhere
    ell = []
    for i, ph in enumerate((0.0, 0.25, 0.5, 0.75, 1.0)):
        s = math.sin(ph * math.tau)
        ell.append((1 + i * 11, {
            "thigh.L": (r(16 * s), 0, 0), "thigh.R": (r(-16 * s), 0, 0),
            "shin.L": (r(-8 - 22 * max(0.0, s)), 0, 0), "shin.R": (r(-8 - 22 * max(0.0, -s)), 0, 0),
            "upper_arm.L": (r(42 - 16 * s), 0, 0), "upper_arm.R": (r(42 + 16 * s), 0, 0),
            "forearm.L": (r(58 + 12 * s), 0, 0), "forearm.R": (r(58 - 12 * s), 0, 0),
            "spine": (r(-5), 0, 0), "chest": (0, r(4 * s), 0), "head": (r(4), 0, 0)}, (0, 0.03 * abs(math.cos(ph * math.tau)) - 0.02, 0)))
    make_action(arm, "elliptical", ell)
    # on the spin bike (its saddle the seat): leant over the bars, a hand on each, pedalling --
    # each ankle round its crank, the two half a turn apart
    lean = dict(seat, spine=(r(-28), 0, 0), chest=(r(-8), 0, 0), head=(r(22), 0, 0),
                **{"thigh.L": (r(62), 0, 0), "thigh.R": (r(62), 0, 0), "shin.L": (r(-70), 0, 0), "shin.R": (r(-70), 0, 0)})
    spin = []
    for i in range(9):
        a = i / 8.0 * math.tau
        crank = {}
        for s, off in (("L", 0.0), ("R", math.pi)):
            x = 0.13 if s == "L" else -0.13
            crank["shin." + s] = (x, 0.34 + 0.16 * math.cos(a + off), -0.22 + 0.16 * math.sin(a + off))
        grip = {"forearm.L": (0.2, 0.56, 0.5), "forearm.R": (-0.2, 0.56, 0.5)}
        spin.append((1 + i * 4, reach(arm, lean, sat, dict(crank, **grip)), sat))
    make_action(arm, "spin", spin)
    # on a weights bench, the bench press: sat on it, lain back along it (the head toward its rack),
    # feet down on the floor either side, pressing the bar from the chest to arms' length
    lie = {"thigh.L": (0, 0, r(-6)), "thigh.R": (0, 0, r(6)), "shin.L": (r(-88), 0, 0), "shin.R": (r(-88), 0, 0),
           "foot.L": (r(10), 0, 0), "foot.R": (r(10), 0, 0)}
    flat = (0, -0.42, 0.0)
    locked = dict(lie, **{"upper_arm.L": (r(88), 0, 0), "upper_arm.R": (r(88), 0, 0), "forearm.L": (r(4), 0, 0), "forearm.R": (r(4), 0, 0)})
    chest = dict(lie, **{"upper_arm.L": (r(14), 0, 0), "upper_arm.R": (r(14), 0, 0), "forearm.L": (r(96), 0, 0), "forearm.R": (r(96), 0, 0)})
    for pose_ in (lie, locked, chest):
        pose_["hips"] = (r(90), 0, 0)
    make_action(arm, "bench", [(1, locked, flat), (22, chest, flat), (36, locked, flat), (50, locked, flat)])


# ---------------------------------------------------------------- the human body

def _face_group(ob, p, dom):
    names = [dom[i] for i in p.vertices]
    return max(set(names), key=names.count)


def paint(ob, J, role, mats):
    """Dress the body by region: which bone a face follows (its vertices' strongest weight)
    and where it sits decide skin / shirt / trousers / shoes."""
    me = ob.data
    src = [m.name for m in me.materials]
    me.materials.clear()
    for k in ("skin", "hair", "shirt", "pants", "shoes", "accent", "detail"):
        me.materials.append(mats[k])
    idx = {m.name.split(".")[0]: i for i, m in enumerate(me.materials)}
    gname = {g.index: g.name for g in ob.vertex_groups}
    dom = []
    for v in me.vertices:
        best = max(v.groups, key=lambda e: e.weight) if len(v.groups) else None
        dom.append(gname[best.group] if best else "hips")
    long_sleeves = role in LONG_SLEEVES
    shorts = role in SHORTS
    waist = J["spine"].z - 0.025  # the shirt reaches down over the top of the trousers

    def along(c, a, b):
        d = b - a
        return max(0.0, min(1.0, (c - a).dot(d) / max(d.length_squared, 1e-6)))

    for p in me.polygons:
        orig = src[p.material_index] if p.material_index < len(src) else ""
        c = p.center
        g = _face_group(ob, p, dom)
        base = g.split(".")[0]
        side = g.split(".")[1] if "." in g else "L"
        if orig.startswith("Hair"):
            m = "hair"
        elif orig.startswith("Material.002"):
            m = "pants"  # the source's shorts
        elif base in ("head", "neck"):
            m = "skin"
        elif base in ("chest", "spine", "hips"):
            m = "shirt" if c.z > waist else "pants"
        elif base == "upper_arm":
            t = along(c, J["shoulder." + side], J["elbow." + side])
            m = "shirt" if long_sleeves or t < 0.55 else "skin"
        elif base == "forearm":
            t = along(c, J["elbow." + side], J["wrist." + side])
            m = "shirt" if long_sleeves and t < 0.9 else "skin"
        elif base == "hand":
            m = "skin"
        elif base == "thigh":
            t = along(c, J["hip." + side], J["knee." + side])
            m = "pants" if not shorts or t < 0.72 else "skin"
        elif base == "shin":
            m = "shoes" if c.z < J["ankle." + side].z + 0.045 else ("skin" if shorts else "pants")
        elif base == "foot":
            m = "shoes"
        else:
            m = "skin"
        p.material_index = idx[m]


def _front(body, z, half=0.09):
    """How far forward (+Y) the body's surface is at height z (near the middle)."""
    ys = [v.co.y for v in body.data.vertices if abs(v.co.z - z) < 0.035 and abs(v.co.x) < half]
    return max(ys) if ys else 0.12


def _back(body, z, half=0.09):
    ys = [v.co.y for v in body.data.vertices if abs(v.co.z - z) < 0.035 and abs(v.co.x) < half]
    return min(ys) if ys else -0.12


def _head_box(body):
    vs = [v.co for v in body.data.vertices if v.groups and any(body.vertex_groups[e.group].name == "head" and e.weight > 0.5 for e in v.groups)]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    return lo, hi


def human_pieces(P, body, J, items, cap_mesh):
    """The uniform's pieces, built on the measured body."""
    hlo, hhi = _head_box(body)
    hc = (hlo + hhi) * 0.5
    hw = hhi.x - hlo.x
    chest_z = J["chest"].z + 0.12
    fy = _front(body, chest_z)
    for it in items:
        if it == "cap" and cap_mesh is not None:
            src = bmesh.new()
            src.from_mesh(cap_mesh)
            s = hw * 1.22 / 0.205
            m = Matrix.Translation((0, hc.y + 0.004, hhi.z - 0.105 * s / 1.0)) @ Matrix.Scale(s, 4)
            P._add(src, "cap", "head", m)
        elif it == "visor":
            P.cyl((0, hc.y, hhi.z - 0.075), hw * 0.58, hw * 0.58, 0.04, "accent", "head", segs=16)
            P.box((0, hhi.y + 0.05, hhi.z - 0.06), (hw * 0.8, 0.12, 0.012), "accent", "head", 0.005, rx=0.18)
        elif it == "chef_hat":
            P.cyl((0, hc.y, hhi.z - 0.06), hw * 0.56, hw * 0.62, 0.1, "accent", "head")
            P.blob((0, hc.y, hhi.z + 0.1), (hw * 1.4, hw * 1.4, 0.2), "accent", "head")
        elif it == "apron":
            z0, z1 = J["pelvis"].z - 0.42, J["chest"].z + 0.05
            P.box((0, _front(body, (z0 + z1) * 0.5, 0.12) + 0.012, (z0 + z1) * 0.5), (0.34, 0.012, z1 - z0), "accent", "hips", 0.004)
            P.box((0, fy + 0.012, chest_z), (0.22, 0.012, 0.18), "accent", "chest", 0.004)
        elif it == "vest":
            for sx in (1, -1):
                z = J["chest"].z + 0.03
                P.box((0.07 * sx, _front(body, z) + 0.012, z), (0.13, 0.016, 0.38), "accent", "chest", 0.004)
        elif it == "blazer":
            for sx in (1, -1):
                P.box((0.055 * sx, fy + 0.016, chest_z - 0.02), (0.045, 0.01, 0.22), "accent", "chest", 0.003)
        elif it == "bowtie":
            P.box((0, _front(body, J["neck"].z - 0.03, 0.05) + 0.012, J["neck"].z - 0.03), (0.09, 0.02, 0.035), "detail", "chest", 0.006)
        elif it == "badge":
            P.box((-0.08, fy + 0.008, chest_z + 0.02), (0.06, 0.006, 0.025), "detail", "chest", 0.003)
        elif it == "polo":
            P.box((0, _front(body, J["neck"].z - 0.02, 0.06) + 0.004, J["neck"].z - 0.02), (0.13, 0.02, 0.04), "shirt", "chest", 0.008)
            P.box((0, fy + 0.006, chest_z + 0.05), (0.022, 0.006, 0.08), "detail", "chest", 0.002)


def human_rig(J, C):
    """Our 18-bone rig on the measured joints (same names and roll as the stylized rig, so the
    animations carry over)."""
    y = J["pelvis"].y
    hips = Vector((0, y, J["pelvis"].z - 0.07))
    sp = Vector((0, J["spine"].y, J["spine"].z + 0.07))
    ch = Vector((0, J["chest"].y, max(J["chest"].z, sp.z + 0.08)))
    nk = Vector((0, J["neck"].y, J["neck"].z))
    hd = Vector((0, J["head"].y, J["head"].z))
    top = Vector((0, J["head"].y, J["head_top"].z))
    pts = [("root", (0, 0, 0), (0, 0.2, 0), None), ("hips", hips, sp, "root"), ("spine", sp, ch, "hips"),
           ("chest", ch, nk, "spine"), ("neck", nk, hd, "chest"), ("head", hd, top, "neck")]
    for s in ("L", "R"):
        pts += [("upper_arm." + s, J["shoulder." + s], J["elbow." + s], "chest"),
                ("forearm." + s, J["elbow." + s], J["wrist." + s], "upper_arm." + s),
                ("hand." + s, J["wrist." + s], J["hand_tip." + s], "forearm." + s),
                ("thigh." + s, J["hip." + s], J["knee." + s], "hips"),
                ("shin." + s, J["knee." + s], J["ankle." + s], "thigh." + s),
                ("foot." + s, J["ankle." + s], Vector((J["toe." + s].x, J["toe." + s].y, J["ankle." + s].z * 0.6)), "shin." + s)]
    ad = bpy.data.armatures.new("Rig")
    arm = bpy.data.objects.new("Rig", ad)
    C.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    # the stylized rig's bone axes: each bone here is rolled to match, so the animations (tuned
    # on that rig) turn every bone the same way
    axes = {}
    for bn, h, t, par in BONES:
        eb = ad.edit_bones.new("_" + bn)
        eb.head, eb.tail = h, t
        eb.roll = 0.0
        axes[bn] = eb.z_axis.copy()
    for bn in list(axes):
        ad.edit_bones.remove(ad.edit_bones["_" + bn])
    for bn, h, t, par in pts:
        eb = ad.edit_bones.new(bn)
        eb.head, eb.tail = Vector(h), Vector(t)
        eb.align_roll(axes[bn])
        if par:
            eb.parent = ad.edit_bones[par]
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


_CAP_MESH = None


def _cap_mesh():
    """The club cap's mesh (shell, bill, buttons) for heads, loaded once."""
    global _CAP_MESH
    try:
        _CAP_MESH.name  # gone with the last file reset?
    except (AttributeError, ReferenceError):
        _CAP_MESH = None
    if _CAP_MESH is None and os.path.exists(CAP):
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=CAP)
        new = [o for o in bpy.data.objects if o not in before]
        ob = [o for o in new if o.type == "MESH"][0]
        _CAP_MESH = ob.data.copy()
        _CAP_MESH.transform(ob.matrix_world)
        _CAP_MESH.use_fake_user = True
        for o in new:
            bpy.data.objects.remove(o)
    return _CAP_MESH


def build_human(role):
    import human_base as HB
    C = bpy.data.collections.new(role)
    bpy.context.scene.collection.children.link(C)
    mats = make_materials(role)
    cap_mesh = _cap_mesh()
    if cap_mesh is not None:
        # the cap's own fabric (its normal map's stitching) in the uniform's colour
        cm = cap_mesh.materials[0] if cap_mesh.materials else None
        cap_mat = cm.copy() if cm is not None else bpy.data.materials.new("cap")
        cap_mat.name = "cap"
        p = cap_mat.node_tree.nodes.get("Principled BSDF")
        if p is not None:
            for l in list(p.inputs["Base Color"].links):
                cap_mat.node_tree.links.remove(l)
            p.inputs["Base Color"].default_value = mats["accent"].node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value
        mats["cap"] = cap_mat
    r = HB.load(HUMAN)
    J = r["joints"]
    for o in r["parts"]:
        for c in list(o.users_collection):
            c.objects.unlink(o)
        C.objects.link(o)
    bpy.ops.object.select_all(action="DESELECT")
    for o in r["parts"]:
        o.select_set(True)
    bpy.context.view_layer.objects.active = r["body"]
    bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.name = "Body"
    paint(body, J, role, mats)
    items = ROLES[role][5] if role in ROLES else GOLFERS[role[len("golfer_"):]][5] + ("polo",)
    P = Part()
    human_pieces(P, body, J, items, cap_mesh)
    if P.bm.faces:
        acc = bpy.data.meshes.new("Acc")
        aob = bpy.data.objects.new("Acc", acc)
        C.objects.link(aob)
        for bn in NAMES:
            aob.vertex_groups.new(name=bn)
        P.bm.normal_update()
        P.bm.to_mesh(acc)
        for m in P.mats:
            acc.materials.append(mats[m])
        bpy.ops.object.select_all(action="DESELECT")
        aob.select_set(True)
        body.select_set(True)
        bpy.context.view_layer.objects.active = body
        bpy.ops.object.join()
    P.bm.free()
    arm = human_rig(J, C)
    body.parent = arm
    mod = body.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    animations(arm)
    return C, arm


def build_role(role):
    if os.path.exists(HUMAN):
        return build_human(role)
    C = bpy.data.collections.new(role)
    bpy.context.scene.collection.children.link(C)
    mats = make_materials(role)
    arm = build_rig("Rig", C)
    P = Part()
    if role in ROLES:
        body(P, female=role in ("receptionist", "trainer", "shop_clerk"))
        accessories(P, ROLES[role][5])
    else:
        look = GOLFERS[role[len("golfer_"):]]
        body(P, female=look[6])
        accessories(P, look[5] + ("polo",))
    skinned("Body", P, mats, arm, C)
    animations(arm)
    return C, arm


def export(C, path):
    bpy.ops.object.select_all(action="DESELECT")
    for ob in C.all_objects:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = [o for o in C.all_objects if o.type == "ARMATURE"][0]
    # Export at 60 Hz so the baked grip constraint survives resampling.
    ratio = 60.0 / bpy.context.scene.render.fps
    for action in bpy.data.actions:
        for curve in _fcurves(action):
            for key in curve.keyframe_points:
                key.co.x = 1+(key.co.x-1)*ratio
                key.handle_left.x = 1+(key.handle_left.x-1)*ratio
                key.handle_right.x = 1+(key.handle_right.x-1)*ratio
    bpy.context.scene.render.fps = 60
    kw = dict(filepath=path, export_format="GLB", use_selection=True, export_yup=True, export_animations=True, export_skins=True)
    try:
        bpy.ops.export_scene.gltf(export_animation_mode="ACTIONS", **kw)
    except TypeError:
        bpy.ops.export_scene.gltf(**kw)


def preview(roles, out_dir):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x = 1400
    sc.render.resolution_y = 520
    w = bpy.data.worlds.new("w")
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.75, 0.78, 0.8, 1)
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.5
    sun.rotation_euler = (math.radians(50), 0, math.radians(30))
    sc.collection.objects.link(sun)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 13.5
    sc.collection.objects.link(cam)
    sc.camera = cam
    for i, (role, C, arm) in enumerate(roles):
        arm.location.x = (i - (len(roles) - 1) * 0.5) * 1.0
    cam.location = (0, 12, 2.2)
    cam.rotation_euler = (math.radians(88), 0, math.radians(180))
    for fname, action, frame in (("people_idle.png", None, 9), ("people_walk.png", "walk", 9), ("people_swing_top.png", "swing", 30),
                                 ("people_swing_finish.png", "swing", 60), ("people_putt.png", "putt", 26), ("people_sit.png", "sit", 10)):
        for i, (role, C, arm) in enumerate(roles):
            arm.animation_data.action = None
            if action:
                acts = sorted(a.name for a in bpy.data.actions if a.name == action or a.name.startswith(action + "."))
                arm.animation_data.action = bpy.data.actions[acts[i % len(acts)]] if acts else None
        sc.frame_set(frame)
        sc.render.filepath = os.path.join(out_dir, fname)
        bpy.ops.render.render(write_still=True)
    for role, C, arm in roles:
        arm.location.x = 0
        arm.animation_data.action = None


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    prev = argv[argv.index("--previews") + 1] if "--previews" in argv else ""
    os.makedirs(OUT, exist_ok=True)
    people = [(r, "staff_%s.glb" % r) for r in ROLES] + [("golfer_" + g, "golfer_%s.glb" % g) for g in GOLFERS]
    if "--staff-only" in argv:
        people = [(role, name) for role, name in people if not role.startswith("golfer_")]
    # one fresh file per person, so each .glb carries just its own animations
    for role, fname in people:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        C, arm = build_role(role)
        export(C, os.path.join(OUT, fname))
        print("BUILT", role)
    if prev:
        os.makedirs(prev, exist_ok=True)
        bpy.ops.wm.read_factory_settings(use_empty=True)
        preview([(r,) + build_role(r) for r, _f in people[-8:]], prev)
    print("DONE")


main()

