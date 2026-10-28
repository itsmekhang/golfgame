"""The low-poly human the club's people are made from (the user's rigged character model).

load(path) imports it and returns {"body": mesh object, "parts": [all mesh objects], "joints":
{name: Vector}} with the character standing at the origin facing +Y, 1.78 m tall, arms lowered
from the source's T-pose, and every vertex group renamed to build_people.py's 18-bone rig (with
weights summed: fingers into the hand, clavicles into the chest, and so on). The source's own
armature is thrown away -- its bones came through the FBX -> glTF conversion with broken
transforms -- and the joints are measured from where its weight groups meet instead.
"""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector

HEIGHT = 1.78
# the source's weight groups (prefix before "_<n>") -> our bone, by side; None: drop
GROUPS = {
    "_rootJoint": "hips", "Root": "hips", "Base": "hips", "Pelvis": "hips",
    "Spine": "spine", "Chest": "chest", "Neck": "neck", "Head": "head", "Head_end": "head",
    "Arm": "chest", "UpArm": "upper_arm", "LowArm": "forearm", "Palm": "hand",
    "UpLeg": "thigh", "LowLeg": "shin", "Foot": "foot", "Toe": "foot", "Toe_end": "foot",
}


def _ours(name):
    """Our bone name for a source group ('UpArm.L_08' -> ('upper_arm', 'L')), or None."""
    base = name.rsplit("_", 1)[0] if name[-1].isdigit() and "_" in name else name
    side = None
    if base.endswith((".L", ".R", ".l", ".r")):
        side = base[-1].upper()
        base = base[:-2]
    if base.startswith("f") and base[1:2].isdigit():
        return ("hand", side)
    if base.startswith(("FootIK", "Pole")):
        return None
    ours = GROUPS.get(base)
    return (ours, side) if ours else None


def load(path):
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [o for o in bpy.data.objects if o.type == "MESH" and o.vertex_groups]
    for o in [o for o in bpy.data.objects if o.type == "MESH" and not o.vertex_groups]:
        bpy.data.objects.remove(o)  # a stray icosphere in the source
    # bake the source armature's deformation (it's what stands the raw mesh up in its T-pose)
    # and every transform into the meshes, then drop the armature
    for o in meshes:
        bpy.ops.object.select_all(action="DESELECT")
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        for m in list(o.modifiers):
            if m.type == "ARMATURE":
                bpy.ops.object.modifier_apply(modifier=m.name)
            else:
                o.modifiers.remove(m)
        mw = o.matrix_world.copy()
        o.parent = None
        o.data.transform(mw)
        o.matrix_world = Matrix.Identity(4)
    for o in [o for o in bpy.data.objects if o.type != "MESH"]:
        bpy.data.objects.remove(o)
    body = max(meshes, key=lambda o: len(o.data.vertices))
    # stand it up: feet on z = 0, facing +Y (the source faces -Y), 1.78 m tall
    allv = [v.co for o in meshes for v in o.data.vertices]
    lo = Vector((min(v.x for v in allv), min(v.y for v in allv), min(v.z for v in allv)))
    hi = Vector((max(v.x for v in allv), max(v.y for v in allv), max(v.z for v in allv)))
    s = HEIGHT / (hi.z - lo.z)
    fix = Matrix.Rotation(math.pi, 4, "Z") @ Matrix.Scale(s, 4) @ Matrix.Translation((-(lo.x + hi.x) * 0.5, -(lo.y + hi.y) * 0.5, -lo.z))
    for o in meshes:
        o.data.transform(fix)
        _merge_groups(o)
    joints = measure(body)
    for o in meshes:
        lower_arms(o, joints)
    joints = measure(body)
    return {"body": body, "parts": meshes, "joints": joints}


def _merge_groups(ob):
    """Rename / sum the source's weight groups into ours (sides by where they are: our '.L' is
    on +X, the character's right, as build_people.py's rig has it)."""
    me = ob.data
    src = {g.index: _ours(g.name) for g in ob.vertex_groups}
    # which side each source side letter ended up on
    side_x = {}
    for g in ob.vertex_groups:
        o = _ours(g.name)
        if o and o[1]:
            xs = [v.co.x for v in me.vertices for e in v.groups if e.group == g.index and e.weight > 0.3]
            if xs:
                side_x.setdefault(o[1], []).extend(xs)
    letter = {k: ("L" if sum(v) / len(v) > 0 else "R") for k, v in side_x.items()}
    weights = []
    for v in me.vertices:
        acc = {}
        for e in v.groups:
            o = src.get(e.group)
            if not o or e.weight <= 0.0:
                continue
            central = o[0] in ("hips", "spine", "chest", "neck", "head")  # clavicles fold into the chest
            name = o[0] + ("." + letter[o[1]] if o[1] and not central else "")
            acc[name] = acc.get(name, 0.0) + e.weight
        tot = sum(acc.values())
        weights.append({k: w / tot for k, w in acc.items()} if tot > 0 else {"hips": 1.0})
    for g in list(ob.vertex_groups):
        ob.vertex_groups.remove(g)
    names = sorted({k for w in weights for k in w})
    groups = {n: ob.vertex_groups.new(name=n) for n in names}
    for i, w in enumerate(weights):
        for k, val in w.items():
            groups[k].add([i], val, "REPLACE")


def _w(ob, v, name):
    g = ob.vertex_groups.get(name)
    if g is None:
        return 0.0
    for e in v.groups:
        if e.group == g.index:
            return e.weight
    return 0.0


def _joint(ob, a, b):
    """Where groups a and b meet: the weight-blended centroid of the vertices both pull on."""
    tot = 0.0
    acc = Vector()
    for v in ob.data.vertices:
        w = min(_w(ob, v, a), _w(ob, v, b))
        if w > 0.02:
            acc += v.co * w
            tot += w
    return acc / tot if tot > 0 else None


def _centroid(ob, name, pick=None):
    vs = [v.co for v in ob.data.vertices if _w(ob, v, name) > 0.5]
    if not vs:
        return None
    if pick:
        return pick(vs)
    return sum(vs, Vector()) / len(vs)


def measure(ob):
    J = {}
    for s in ("L", "R"):
        J["shoulder." + s] = _joint(ob, "chest", "upper_arm." + s)
        J["elbow." + s] = _joint(ob, "upper_arm." + s, "forearm." + s)
        J["wrist." + s] = _joint(ob, "forearm." + s, "hand." + s)
        J["hand_tip." + s] = _centroid(ob, "hand." + s, lambda vs: max(vs, key=lambda v: (v - J["wrist." + s]).length))
        J["hip." + s] = _joint(ob, "hips", "thigh." + s)
        J["knee." + s] = _joint(ob, "thigh." + s, "shin." + s)
        J["ankle." + s] = _joint(ob, "shin." + s, "foot." + s)
        J["toe." + s] = _centroid(ob, "foot." + s, lambda vs: max(vs, key=lambda v: v.y))
    J["spine"] = _joint(ob, "hips", "spine")
    J["chest"] = _joint(ob, "spine", "chest")
    J["neck"] = _joint(ob, "chest", "neck")
    J["head"] = _joint(ob, "neck", "head")
    J["head_top"] = _centroid(ob, "head", lambda vs: max(vs, key=lambda v: v.z))
    J["pelvis"] = (J["hip.L"] + J["hip.R"]) * 0.5
    return J


def lower_arms(ob, J, angle=math.radians(79)):
    """Bring the T-pose arms down by the character's sides (blended by the arm weights, the
    shoulder as pivot), so the rig's rest pose is arms-down like the animations expect."""
    for s, sign in (("L", 1.0), ("R", -1.0)):
        pivot = J["shoulder." + s]
        if pivot is None:
            continue
        # turning about Y: the +X arm swings down with a positive angle, the -X arm negative
        rot = Matrix.Rotation(angle * sign, 4, "Y")
        for v in ob.data.vertices:
            w = sum(_w(ob, v, n + "." + s) for n in ("upper_arm", "forearm", "hand"))
            w = min(w, 1.0)
            if w <= 0.0:
                continue
            moved = pivot + (rot @ (v.co - pivot).to_4d()).to_3d()
            v.co = v.co.lerp(moved, w)
    ob.data.update()
