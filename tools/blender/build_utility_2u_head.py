"""Build the Utility Iron 2U head from the muscle-back skin: a thicker hollow-body iron whose
back is closed -- a flat machined plate across the upper back with two screws, a black
channel insert under it, a smooth lower body and a small "2U" mark. Run:
  blender -b --python tools/blender/build_utility_2u_head.py --     assets/Selected_Club_Heads/skins/mustard_muscle_base.glb     assets/Selected_Club_Heads/skins/utility_2u_iron_base.glb <preview_dir>
then re-render the shop photo: godot --path . --script tools/render_shop_thumbnails.gd -- --models=utility_2u
"""
import bpy, bmesh, sys, math
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

args = sys.argv[sys.argv.index('--') + 1:]
SRC, OUT, PREVIEW = args[0], args[1], args[2]

THICKEN = 1.45        # depth behind the face, hollow-body chunkier than a muscle back
PLATE_RAISE = 0.0011  # plate stands this far proud of the highest back point it covers
BEVEL = 0.0016        # plate edge chamfer width
INSET_TOP = 0.0026    # plate top edge below the top line
INSET_TOE = 0.0040
GROOVE_W = 0.0024


def smoothstep(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3 - 2 * t)


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
body = [o for o in bpy.context.scene.objects if o.type == 'MESH'][0]
body.name = 'UtilityIron2U_Body'
me = body.data

# ---- face plane: area-weighted fit of the polygons facing -Y on the blade
nsum = Vector((0, 0, 0))
csum = Vector((0, 0, 0))
asum = 0.0
for p in me.polygons:
    if p.normal.y < -0.85 and p.center.x < -0.012:
        nsum += p.normal * p.area
        csum += p.center * p.area
        asum += p.area
n_face = nsum.normalized()          # outward from the strike face
p0 = csum / asum
back = -n_face                       # into the back of the head
e_u = (Vector((1, 0, 0)) - n_face * n_face.x).normalized()   # toward the heel, in the face plane
e_v = n_face.cross(e_u).normalized()
if e_v.z < 0:
    e_v = -e_v
print('face normal', n_face, 'p0', p0)

# ---- thicken the blade behind the face (hosel blended out)
for v in me.vertices:
    d = (v.co - p0).dot(back)
    if d <= 0:
        continue
    w = smoothstep(0.004, 0.016, -v.co.x)
    v.co += back * d * (THICKEN - 1.0) * w
me.update()
# clean shading after the move: smooth by angle keeps the score lines crisp
if hasattr(me, 'has_custom_normals') and me.has_custom_normals:
    with bpy.context.temp_override(object=body, active_object=body, selected_objects=[body]):
        bpy.ops.mesh.customdata_custom_splitnormals_clear()
bpy.context.view_layer.objects.active = body
body.select_set(True)
bpy.ops.object.shade_smooth_by_angle(angle=math.radians(35))

# ---- back outline in face-plane coordinates (u along the head, v up the face)
bm_src = bmesh.new()
bm_src.from_mesh(me)
bvh = BVHTree.FromBMesh(bm_src)
top = {}
bot = {}
dmax_at = {}
for v in me.vertices:
    rel = v.co - p0
    d = rel.dot(back)
    if d < 0.0015:
        continue
    u = rel.dot(e_u)
    vv = rel.dot(e_v)
    k = round(u * 1000)
    top[k] = max(top.get(k, -1e9), vv)
    bot[k] = min(bot.get(k, 1e9), vv)
keys = sorted(top)
u_toe = min(keys) / 1000.0
# the blade ends where the hosel neck starts: last bin before the outline height jumps
heights = [(k, top[k] - bot[k]) for k in keys]
mid = sorted(h for k, h in heights)[len(heights) // 2]
u_heel = max(keys) / 1000.0
for k, h in heights:
    # the hosel column: past the middle of the head, the outline suddenly grows tall
    if k / 1000.0 > (u_toe + max(keys) / 1000.0) * 0.5 and h > mid * 1.3:
        u_heel = k / 1000.0
        break
print('u range', u_toe, u_heel, 'median height', mid)
print('heights', [(k, round(h * 1000, 1)) for k, h in heights[::4]])


def v_top(u):
    k = round(u * 1000)
    while k not in top and k > min(keys):
        k -= 1
    return top.get(k, 0.0)


def v_bot(u):
    k = round(u * 1000)
    while k not in bot and k > min(keys):
        k -= 1
    return bot.get(k, 0.0)


def surface_d(u, vv):
    """Depth behind the face plane of the back surface at (u, v), via a ray from behind."""
    origin = p0 + e_u * u + e_v * vv + back * 0.08
    hit = bvh.ray_cast(origin, -back, 0.2)
    if hit[0] is None:
        return None
    return (hit[0] - p0).dot(back)


u0 = u_toe + INSET_TOE
u1 = u_heel - 0.0045
span = u1 - u0


def plate_top(u):
    return v_top(u) - INSET_TOP


def plate_bottom(u):
    # the plate covers the upper ~38% of the blade, following the top line
    t = (u - u0) / span
    return plate_top(u) - (v_top(u) - v_bot(u)) * (0.38 - 0.05 * t)


# plate depth: proud of the highest back point it covers
dmax = 0.0
for i in range(41):
    u = u0 + span * i / 40
    for j in range(9):
        vv = plate_bottom(u) + (plate_top(u) - plate_bottom(u)) * j / 8
        d = surface_d(u, vv)
        if d is not None:
            dmax = max(dmax, d)
D_PLATE = dmax + PLATE_RAISE
print('plate depth', D_PLATE)


def world(u, vv, d):
    return p0 + e_u * u + e_v * vv + back * d


def heightfield(name, nu, nv, rect, depth_fn, material):
    """Grid mesh over a (u, v) region, each vertex placed at depth_fn(u, v, s)."""
    bm = bmesh.new()
    grid = []
    for i in range(nu + 1):
        row = []
        a = i / nu
        u = rect[0] + (rect[1] - rect[0]) * a
        lo, hi = rect[2](u), rect[3](u)
        for j in range(nv + 1):
            b = j / nv
            vv = lo + (hi - lo) * b
            d = depth_fn(u, vv, a, b)
            row.append(bm.verts.new(world(u, vv, d)) if d is not None else None)
        grid.append(row)
    for i in range(nu):
        for j in range(nv):
            q = [grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]]
            if all(q):
                # wind so the faces point out of the back
                bm.faces.new(q if ((q[1].co - q[0].co).cross(q[3].co - q[0].co)).dot(back) > 0 else list(reversed(q)))
    m = bpy.data.meshes.new(name)
    bm.to_mesh(m)
    bm.free()
    o = bpy.data.objects.new(name, m)
    bpy.context.scene.collection.objects.link(o)
    m.materials.append(material)
    for p in m.polygons:
        p.use_smooth = True
    return o


def make_mat(name, rgb, metallic, rough):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (rgb[0], rgb[1], rgb[2], 1.0)
    bsdf.inputs['Metallic'].default_value = metallic
    bsdf.inputs['Roughness'].default_value = rough
    return m


satin = make_mat('ofg_utility_2u__satin_body', (0.80, 0.81, 0.83), 0.9, 0.36)
polished = make_mat('ofg_utility_2u__polished_plate', (0.86, 0.87, 0.89), 0.92, 0.24)
black = make_mat('ofg_utility_2u__black_insert', (0.025, 0.026, 0.028), 0.0, 0.45)
steel = make_mat('ofg_utility_2u__screw_steel', (0.62, 0.63, 0.66), 0.9, 0.3)
body.data.materials.clear()
body.data.materials.append(satin)


def plate_depth(u, vv, a, b):
    d = surface_d(u, vv)
    if d is None:
        return None
    # distance to the plate border in metres, for the chamfer
    lo, hi = plate_bottom(u), plate_top(u)
    edge = min(vv - lo, hi - vv, (u - u0), (u1 - u))
    s = smoothstep(0.0, BEVEL, edge)
    return d + 0.00008 + (D_PLATE - d - 0.00008) * s


plate = heightfield('UtilityIron2U_Plate', 160, 36, (u0, u1, plate_bottom, plate_top), plate_depth, polished)

# channel insert: a black strip under the plate across the middle of the head
g0 = u0 + span * 0.20
g1 = u0 + span * 0.80


def groove_depth(u, vv, a, b):
    d = surface_d(u, vv)
    return None if d is None else d + 0.00012


groove = heightfield('UtilityIron2U_Insert', 80, 4, (g0, g1, lambda u: plate_bottom(u) - GROOVE_W - 0.0006, lambda u: plate_bottom(u) - 0.0006), groove_depth, black)

# screws at each end of the plate
screws = []
for t in (0.10, 0.90):
    u = u0 + span * t
    vv = (plate_bottom(u) + plate_top(u)) * 0.5
    c = world(u, vv, D_PLATE)
    bm = bmesh.new()
    r = 0.0031
    ring = bmesh.ops.create_circle(bm, cap_ends=True, segments=40, radius=r)
    top_verts = ring['verts']
    ext = bmesh.ops.extrude_face_region(bm, geom=[f for f in bm.faces])
    for vtx in [e for e in ext['geom'] if isinstance(e, bmesh.types.BMVert)]:
        vtx.co.z += 0.0005
    m = bpy.data.meshes.new('UtilityIron2U_Screw')
    bm.to_mesh(m)
    bm.free()
    o = bpy.data.objects.new('UtilityIron2U_Screw', m)
    bpy.context.scene.collection.objects.link(o)
    m.materials.append(steel)
    # local z -> out of the back, x -> along the head
    rot = Matrix((e_u, back.cross(e_u), back)).transposed().to_4x4()
    o.matrix_world = Matrix.Translation(c - back * 0.0003) @ rot
    for p in m.polygons:
        p.use_smooth = False
    screws.append(o)
    # torx recess: a black six-point star on the screw head
    bm = bmesh.new()
    pts = []
    for k in range(12):
        ang = math.pi * k / 6
        rr = 0.0014 if k % 2 == 0 else 0.0008
        pts.append(bm.verts.new((math.cos(ang) * rr, math.sin(ang) * rr, 0.00022)))
    bm.faces.new(pts)
    m2 = bpy.data.meshes.new('UtilityIron2U_ScrewRecess')
    bm.to_mesh(m2)
    bm.free()
    o2 = bpy.data.objects.new('UtilityIron2U_ScrewRecess', m2)
    bpy.context.scene.collection.objects.link(o2)
    m2.materials.append(black)
    o2.matrix_world = o.matrix_world
    screws.append(o2)

# "2U" mark on the lower heel side of the back
curve = bpy.data.curves.new('mark', 'FONT')
curve.body = '2U'
curve.size = 0.0042
curve.align_x = 'CENTER'
curve.align_y = 'CENTER'
txt = bpy.data.objects.new('mark', curve)
bpy.context.scene.collection.objects.link(txt)
mu = u0 + span * 0.78
mv = plate_bottom(mu) - (plate_bottom(mu) - v_bot(mu)) * 0.45
md = max(d for d in [surface_d(mu + du, mv + dv) for du in (-0.004, 0, 0.004) for dv in (-0.002, 0, 0.002)] if d is not None) + 0.00012
# viewed from behind, the viewer's right is -e_u
rot = Matrix((-e_u, e_v, back)).transposed().to_4x4()
txt.matrix_world = Matrix.Translation(world(mu, mv, md)) @ rot
bpy.context.view_layer.objects.active = txt
for o in bpy.context.selected_objects:
    o.select_set(False)
txt.select_set(True)
bpy.ops.object.convert(target='MESH')
txt.name = 'UtilityIron2U_Mark'
txt.data.materials.clear()
txt.data.materials.append(black)

bm_src.free()
body['revision'] = 'Utility Iron 2U: hollow-body driving iron built from the muscle-back skin; closed back with plate, screws and channel insert'
body['units'] = 'meters'

# ---- previews
scene = bpy.context.scene
scene.render.engine = 'BLENDER_EEVEE' if 'BLENDER_EEVEE' in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items] else 'BLENDER_EEVEE_NEXT'
world_bg = bpy.data.worlds.new('w')
scene.world = world_bg
world_bg.use_nodes = True
world_bg.node_tree.nodes['Background'].inputs['Color'].default_value = (0.55, 0.62, 0.70, 1)
world_bg.node_tree.nodes['Background'].inputs['Strength'].default_value = 1.2
for name, d, e in [('key', (0.4, 1.0, 1.2), 3.0), ('rim', (-1.0, -0.5, 0.6), 2.0)]:
    ld = bpy.data.lights.new(name, 'SUN')
    ld.energy = e
    lo = bpy.data.objects.new(name, ld)
    scene.collection.objects.link(lo)
    lo.rotation_euler = (-Vector(d)).to_track_quat('-Z', 'Y').to_euler()
scene.render.resolution_x = 900
scene.render.resolution_y = 700
cam_data = bpy.data.cameras.new('cam')
cam_data.type = 'ORTHO'
cam_data.ortho_scale = 0.11
cam = bpy.data.objects.new('cam', cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
center = p0 + back * 0.008 + Vector((0, 0, 0.012))
for name, dv in [('back', back * 1.0 + Vector((0.15, 0, 0.25))), ('back_low', back * 1.0 + Vector((-0.35, 0, -0.1))), ('face', -back + Vector((0.2, 0, 0.2))), ('top', Vector((0, 0.2, 1.0)))]:
    v = dv.normalized()
    cam.location = center + v * 0.4
    cam.rotation_euler = (center - cam.location).to_track_quat('-Z', 'Y').to_euler()
    scene.render.filepath = PREVIEW + '/' + name + '.png'
    bpy.ops.render.render(write_still=True)

bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_yup=True, export_apply=True, export_extras=True, use_selection=False, export_lights=False, export_cameras=False)
print('EXPORTED', OUT)
