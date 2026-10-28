"""Fairway wood (3-wood, 15 deg) head asset -- v3, combining a real reference mesh
with a procedural hosel/ferrule. Blender 4.3+/5.x bpy; meters, +Y up, face toward -Z.

The user supplied a downloaded reference model (source: base.glb/base.obj = "fairway
woods.glb"/".obj", two full clubs in one file). That file's own vertex welds were
broken -- thousands of coincident-but-unmerged duplicate vertices along every UV seam,
a common export artifact -- so it needed a "Merge by Distance" pass before it would
even separate into its two distinct clubs. The better-proportioned of the two heads
(a complete crown with real scorelines and a sole weight-port already sculpted in) was
then cropped away from its shaft with a plane bisect and reoriented from the source
scene's arbitrary pose into this project's convention (sole at y=0, face toward -Z,
toe toward +X), using the mesh's own geometry as the reference axes: the sole's flat
region and the striking face's flat region, found as the two largest near-planar
polygon clusters, rather than any assumption about the source file's own orientation.
That result is committed as `source/reference_head.glb` so a rebuild does not depend
on the much larger, messier original download.

Revision 2 (the first attempt at this combination) scaled that shell uniformly by
width alone and left its own native height/depth, which came out taller and more
egg-shaped than a real fairway wood, and flattened the face by simple depth alone,
which sometimes swept up a similarly-deep sole weight-pocket near the toe. Both are
fixed here: the shell is scaled independently on all three axes to this project's
already-validated fairway wood envelope (106 x 37 x 77 mm, the same numbers the
hand-authored procedural revision uses), and the face-flatten step also requires the
vertex to touch a face whose normal actually matches the loft direction, which the
sole pocket's floor does not. A gloss-black bezel is cut into the material assignment
around the satin scored insert, matching every reference photo, the same fix already
applied to the procedural revision (kept alongside this one as
`build_fairway_wood_procedural.py`).
"""
from pathlib import Path
import sys; sys.path.insert(0, str(Path(__file__).resolve().parent))
import math, json
import bpy, bmesh
from mathutils import Vector, Matrix
from mesh_helpers import V, C, active, material, obj_mesh, extrusion, tube, smooth, triangulate_caps

PACK = Path(__file__).resolve().parents[1]
PACK.mkdir(parents=True, exist_ok=True)
REFERENCE = Path(__file__).resolve().parent / 'reference_head.glb'
SOCKET = Vector((-.04459, .060, -.005))
TILT = 29                                       # shaft tilt from vertical; lie = 61 deg
AXIS = Vector((-math.sin(math.radians(TILT)), math.cos(math.radians(TILT)), 0))
LOFT = math.radians(15)
TAN = math.tan(LOFT)
TARGET_DIMS = Vector((.106, .037, .077))        # width(x), height(y), depth(z): the game's established fairway wood envelope
FACE_INSET = .0012                              # shave this far behind the reference's own (slightly noisy) face
PARTS = []
FACE_Z0 = 0.0                                   # face plane z at y=0; set from the reference shell in main()


def plane_z(y): return FACE_Z0 + y*TAN


def cleanup(ob, repair=False):
    bm = bmesh.new(); bm.from_mesh(ob.data)
    for tolerance in ([2e-7,1e-6,3e-6,7e-6,1.5e-5] if repair else [2e-7]):
        bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=tolerance)
        bmesh.ops.dissolve_degenerate(bm, edges=list(bm.edges), dist=tolerance*.1)
        if all(e.is_manifold for e in bm.edges): break
    loose = [e for e in bm.edges if not e.link_faces]
    if loose: bmesh.ops.delete(bm, geom=loose, context='EDGES')
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(ob.data); bm.free(); ob.data.update()


def keep_largest_island(ob):
    """The reference crop can leave a stray sliver or two behind; keep only the
    main connected shell before it goes anywhere near a boolean solver."""
    bm = bmesh.new(); bm.from_mesh(ob.data)
    remaining = set(bm.verts); islands = []
    while remaining:
        stack = [remaining.pop()]; island = [stack[0]]
        while stack:
            v = stack.pop()
            for e in v.link_edges:
                other = e.other_vert(v)
                if other in remaining:
                    remaining.remove(other); stack.append(other); island.append(other)
        islands.append(island)
    if len(islands) > 1:
        islands.sort(key=len)
        drop = [v for isl in islands[:-1] for v in isl]
        bmesh.ops.delete(bm, geom=drop, context='VERTS')
    bmesh.ops.holes_fill(bm, edges=[e for e in bm.edges if e.is_boundary])
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(ob.data); bm.free(); ob.data.update()


def snap_precision(ob, grid=.00002):
    """Round every vertex to a coarse grid immediately before it goes anywhere
    near the EXACT boolean solver. This mesh has passed through several scale and
    shift transforms since it was cropped out of a scan; the solver has repeatedly
    produced stray faces or a crude re-fill at specific unrelated locations on it,
    which is a known symptom of it choking on the resulting fine floating-point
    noise rather than on any real geometric feature."""
    bm = bmesh.new(); bm.from_mesh(ob.data)
    for v in bm.verts:
        v.co.x = round(v.co.x/grid)*grid; v.co.y = round(v.co.y/grid)*grid; v.co.z = round(v.co.z/grid)*grid
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=grid*.5)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(ob.data); bm.free(); ob.data.update()


def bake_location(ob):
    active(ob); bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return ob


def boolean(ob, cutter, operation='DIFFERENCE', check_stray=False):
    active(ob); m = ob.modifiers.new(operation, 'BOOLEAN')
    m.operation = operation; m.solver = 'EXACT'; m.object = cutter
    bpy.ops.object.modifier_apply(modifier=m.name)
    bpy.data.objects.remove(cutter, do_unlink=True); cleanup(ob)
    if check_stray:
        discard_stray_cutter_faces(ob)


def discard_stray_cutter_faces(ob):
    """The EXACT boolean solver occasionally leaves a handful of the cutter's own
    flat faces fused into the result instead of cleanly removing them (a known
    tangency edge case) -- visible as a few oversized, flat n-gons unlike anything
    our own geometry produces. Nothing in this pipeline legitimately has a face
    with more than 8 sides, so any that do are leftover cutter debris: delete them
    and re-close the small gap that leaves."""
    bm = bmesh.new(); bm.from_mesh(ob.data)
    stray = [f for f in bm.faces if len(f.verts) > 8]
    if not stray:
        bm.free(); return
    bmesh.ops.delete(bm, geom=stray, context='FACES')
    boundary = [e for e in bm.edges if e.is_boundary]
    if boundary:
        bmesh.ops.holes_fill(bm, edges=boundary, sides=0)
        bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(ob.data); bm.free(); ob.data.update()
    print(f'  discarded {len(stray)} stray cutter face(s), re-filled {len(boundary)} boundary edge(s)')


def bevel(ob, width=.0008, segments=3, angle=.40):
    active(ob); m = ob.modifiers.new('Manufactured edge radii', 'BEVEL')
    m.width = width; m.segments = segments; m.limit_method = 'ANGLE'; m.angle_limit = angle
    bpy.ops.object.modifier_apply(modifier=m.name); cleanup(ob)
    return ob


def rounded_rect(x0, x1, y0, y1, r, steps=8):
    out = []
    for x, y, start in [(x1-r,y1-r,0),(x0+r,y1-r,90),(x0+r,y0+r,180),(x1-r,y0+r,270)]:
        for i in range(steps+1):
            a = math.radians(start+90*i/steps); out.append((x+r*math.cos(a), y+r*math.sin(a)))
    return out


def finish(ob, mat):
    bake_location(ob); cleanup(ob); triangulate_caps(ob); smooth(ob)
    ob.data.materials.clear(); ob.data.materials.append(mat)
    ob['component'] = ob.name
    PARTS.append(ob)
    return ob


def on_face(center, normal, front, tol=.00006):
    return normal.dot(front) > .9995 and abs(center.z-plane_z(center.y)) < tol


def normal_finish(ob):
    smooth(ob); ob.data.normals_split_custom_set([(0,0,0)]*len(ob.data.loops))
    normals=[tuple(n.vector) for n in ob.data.corner_normals]
    front=V((0,math.sin(LOFT),-math.cos(LOFT)))
    for p in ob.data.polygons:
        if on_face(C(p.center), p.normal, front):
            for li in p.loop_indices: normals[li]=tuple(front)
    ob.data.normals_split_custom_set(normals)


def shear(ob):
    for v in ob.data.vertices:
        p=C(v.co); p.z+=p.y*TAN; v.co=V(p)
    cleanup(ob)


def marker(name, point, root, shaft=False):
    ob = bpy.data.objects.new(name, None); bpy.context.collection.objects.link(ob)
    ob.parent=root; ob.location=V(point); ob.empty_display_type='ARROWS'; ob.empty_display_size=.010
    if shaft: ob.rotation_euler.y=math.radians(-TILT)
    if name=='face_center': ob.rotation_euler.x=LOFT
    return ob


def stats(ob):
    if hasattr(ob.data,'calc_loop_triangles'): ob.data.calc_loop_triangles()
    bm=bmesh.new(); bm.from_mesh(ob.data)
    bad=sum(not e.is_manifold for e in bm.edges); remaining=set(bm.verts); components=0
    while remaining:
        components+=1; stack=[remaining.pop()]
        while stack:
            v=stack.pop()
            for e in v.link_edges:
                other=e.other_vert(v)
                if other in remaining: remaining.remove(other); stack.append(other)
    bm.free()
    return {'vertices':len(ob.data.vertices),'triangles':len(ob.data.loop_triangles),'nonmanifold_edges':bad,'connected_components':components}


def export(name):
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=str(PACK/name), export_format='GLB', use_selection=True,
        export_yup=True, export_animations=False, export_extras=True, export_normals=True,
        export_tangents=False, export_texcoords=False, export_materials='EXPORT')


# --------------------------------------------------------------- reference shell
def _align_hosel_stub(ob):
    """Slide the shell in X/Z (not Y: the sole must stay grounded) so the
    remaining crop stub -- the highest point left after cropping away the
    reference's own hosel/shaft -- lines up with our fixed real-world hosel axis
    at the same height. Without this the two rarely overlap enough for a clean
    boolean union. Callable more than once: any later resize needs it redone."""
    pts = [C(v.co) for v in ob.data.vertices]
    stub_top = max(pts, key=lambda p: p.y)
    target = SOCKET + AXIS * ((stub_top.y - SOCKET.y) / AXIS.y)
    shift = Vector((target.x - stub_top.x, 0.0, target.z - stub_top.z))
    bm = bmesh.new(); bm.from_mesh(ob.data)
    for v in bm.verts:
        p = C(v.co) + shift
        v.co = V(p)
    bm.to_mesh(ob.data); bm.free(); ob.data.update()


def import_reference():
    bpy.ops.import_scene.gltf(filepath=str(REFERENCE))
    ob = [o for o in bpy.data.objects if o.type == 'MESH'][0]
    ob.name = 'Fairway wood body'
    active(ob)
    pts = [C(v.co) for v in ob.data.vertices]
    width = max(p.x for p in pts) - min(p.x for p in pts)
    # Uniform scale by width only, for now: face-flatten below finds the face by
    # matching surface normals against a fixed loft direction, which only stays
    # accurate under a uniform scale (a non-uniform one tilts every normal by a
    # different amount). The independent per-axis correction to this project's
    # real fairway wood envelope happens in reshape_to_target(), after the face
    # is already a flat plane and so cannot be un-flattened by scaling it further.
    scale = TARGET_DIMS.x / width
    bm = bmesh.new(); bm.from_mesh(ob.data)
    for v in bm.verts:
        p = C(v.co); p.x *= scale; p.y *= scale; p.z *= scale; v.co = V(p)
    bm.to_mesh(ob.data); bm.free(); ob.data.update()
    cleanup(ob, repair=True)
    keep_largest_island(ob)
    cleanup(ob, repair=True)
    # A mild relax pass: the scan mesh has fine (sub-mm) jitter along some seams
    # between what were originally separate UV islands, most visible as a jagged
    # ridge right at the face/sole leading edge under a glossy material. A couple
    # of light Laplacian smoothing passes iron that out without softening the
    # actual sculpted features (weight port, badge, scorelines), which are all
    # larger-scale than this noise.
    bm = bmesh.new(); bm.from_mesh(ob.data)
    for _ in range(3):
        bmesh.ops.smooth_vert(bm, verts=list(bm.verts), factor=.25,
            use_axis_x=True, use_axis_y=True, use_axis_z=True)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(ob.data); bm.free(); ob.data.update()
    _align_hosel_stub(ob)
    return ob


def reshape_to_target(ob):
    """Independently correct height and depth to this project's already-validated
    fairway wood envelope, now that the face is a flat plane. A flat plane stays
    flat under this further scale -- an affine map sends planes to planes -- but
    it is no longer the *same* plane: scaling y and z by different factors changes
    the effective loft angle, so FACE_Z0/LOFT/TAN are recomputed analytically for
    the new plane rather than re-measured (there is nothing left to re-measure by
    normal direction; every remaining face vertex is already exactly coplanar)."""
    global FACE_Z0, LOFT, TAN
    pts = [C(v.co) for v in ob.data.vertices]
    size = Vector((max(p.x for p in pts)-min(p.x for p in pts),
                   max(p.y for p in pts)-min(p.y for p in pts),
                   max(p.z for p in pts)-min(p.z for p in pts)))
    scale = Vector((TARGET_DIMS.x/size.x, TARGET_DIMS.y/size.y, TARGET_DIMS.z/size.z))
    bm = bmesh.new(); bm.from_mesh(ob.data)
    for v in bm.verts:
        p = C(v.co); p.x *= scale.x; p.y *= scale.y; p.z *= scale.z; v.co = V(p)
    bm.to_mesh(ob.data); bm.free(); ob.data.update()
    cleanup(ob, repair=True)
    _align_hosel_stub(ob)  # the resize moved the crop stub away from SOCKET; redo it
    old_loft_deg = math.degrees(LOFT)
    FACE_Z0 *= scale.z
    TAN *= scale.z/scale.y
    LOFT = math.atan(TAN)
    print(f'  reshaped to {[round(x*1000,1) for x in TARGET_DIMS]}mm (was {[round(x*1000,1) for x in size]}mm);'
          f' loft {old_loft_deg:.2f} -> {math.degrees(LOFT):.2f} deg')


def _smoothstep(edge0, edge1, x):
    t = max(0.0, min(1.0, (x-edge0)/(edge1-edge0)))
    return t*t*(3-2*t)


def flatten_face(ob, margin=.002, falloff=.012):
    """Snap the reference's own (already close to flat) face region exactly onto
    plane_z(), instead of cutting it with a boolean -- the reference mesh's face
    has an irregular, non-planar boundary loop where it meets the crown/sole/toe/
    heel, and an EXACT-solver DIFFERENCE cut there has repeatedly fused stray flat
    facets from the cutter into the result. A shallow toe-side sole pocket (part of
    the reference's own weight-port sculpting) sits at a similar depth to the real
    face and would otherwise get swept up by depth alone; weight by how well the
    vertex's own faces match the loft direction, which the pocket's floor does not.
    The correction fades out smoothly with depth and with normal match rather than
    snapping on a hard per-vertex threshold: a hard cutoff follows the mesh's own
    irregular triangulation at the boundary and reads as a crinkled seam, since
    adjacent triangles either side of the threshold end up with mismatched depths."""
    front = V((0, math.sin(LOFT), -math.cos(LOFT)))
    bm = bmesh.new(); bm.from_mesh(ob.data)
    moved = 0
    for v in bm.verts:
        p = C(v.co)
        depth = p.z - plane_z(p.y)
        align = max((f.normal.dot(front) for f in v.link_faces), default=-1.0)
        depth_t = 1.0 - _smoothstep(margin, margin+falloff, depth)
        align_t = _smoothstep(.5, .9, align)
        blend = depth_t * align_t
        if blend > .002:
            target_z = plane_z(p.y)
            p.z = p.z*(1-blend) + target_z*blend
            v.co = V(p)
            moved += 1
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(ob.data); bm.free(); ob.data.update()
    print(f'  flattened {moved} face-region vertices onto plane_z()')


def face_cutter():
    cutter=extrusion('Face plane cutter',rounded_rect(-.09,.09,-.02,.10,.001,4),-.12,FACE_Z0,axis='z',radius=0)
    shear(cutter)
    return cutter


def hosel_mesh():
    # Points along the shaft axis, parametrised by height. Real fairway wood hosels
    # are short: the neck flares into the crown within about 2.5cm, not a long straw.
    def at(y): return SOCKET+AXIS*((y-SOCKET.y)/AXIS.y)
    heights=[.011,.015,.019,.022,.025,.028,.031,.034]
    radii=[.0112,.0110,.0100,.0088,.0078,.0070,.0066,.0064]
    points=[at(y) for y in heights]+[SOCKET+AXIS*.001]
    radii.append(.0063)
    return tube('Tapered hosel',points,radii,64)


def face_boundary_crossings(head, y):
    front=V((0,math.sin(LOFT),-math.cos(LOFT)))
    me=head.data
    face_polys=[p for p in me.polygons if on_face(C(p.center),p.normal,front,.00006)]
    edge_count={}
    for p in face_polys:
        for k in p.edge_keys: edge_count[k]=edge_count.get(k,0)+1
    crossing=[]
    for (a,b),cnt in edge_count.items():
        if cnt!=1: continue
        pa=C(me.vertices[a].co); pb=C(me.vertices[b].co)
        if (pa.y>y)!=(pb.y>y): crossing.append(pa.x+(pb.x-pa.x)*(y-pa.y)/(pb.y-pa.y))
    return crossing


def main():
    global FACE_Z0
    bpy.ops.wm.read_factory_settings(use_empty=True)
    gloss=material('Gloss black crown',(.010,.011,.013),.30,.20)
    face=material('Satin steel face',(.33,.35,.37),.90,.50)
    sole=material('Brushed steel sole',(.42,.44,.46),.92,.42)
    dark=material('Black shaft ferrule',(.006,.008,.010),.02,.65)

    head = import_reference()
    pts = [C(v.co) for v in head.data.vertices]
    natural_face_z = min(p.z for p in pts)          # the reference's own (approximately flat) face
    FACE_Z0 = natural_face_z + FACE_INSET
    flatten_face(head)
    cleanup(head, repair=True)
    print('DEBUG after face flatten', stats(head))
    reshape_to_target(head)                          # independent height/depth correction; updates FACE_Z0/LOFT/TAN
    cleanup(head, repair=True)
    pts = [C(v.co) for v in head.data.vertices]
    body_dims=[1000*(max(p[i] for p in pts)-min(p[i] for p in pts)) for i in range(3)]
    face_top=max(p.y for p in pts if abs(p.z-plane_z(p.y))<.00006)
    # The hosel is its own closed solid, embedded into and overlapping the body
    # rather than boolean-unioned with it (the same way the ferrule already works).
    # A UNION here needs the EXACT solver to walk the scan-derived body's full
    # surface, and it has repeatedly handed back a handful of stray faces or a
    # crudely re-filled boundary at some unrelated, far-away point on that surface
    # (a symptom of the solver struggling with the mesh's residual scan noise, not
    # of anything actually wrong where the hosel sits) despite several different
    # fixes. Overlap avoids the solver for this step entirely.
    hosel = hosel_mesh()
    bore=tube('Wood shaft bore',[SOCKET-AXIS*.024,SOCKET+AXIS*.018],[.0047,.0047],64)
    boolean(hosel, bore)                              # simple tube-minus-tube: no scan geometry involved
    print('DEBUG hosel', stats(hosel))
    finish(hosel, gloss)
    finish(head,gloss)
    head.data.materials.append(face); head.data.materials.append(sole)
    front=V((0,math.sin(LOFT),-math.cos(LOFT)))
    # A real face insert sits inboard of the cast body with a visible gloss-black
    # bezel all around it; without this the satin material fills the whole flat-cut
    # face edge to edge and reads as one slab.
    mid_y = face_top*.5
    edge = face_boundary_crossings(head, mid_y)
    bez = .0068
    if len(edge) >= 2:
        insert_left, insert_right = min(edge)+bez, max(edge)-bez
    else:
        insert_left, insert_right = -1.0, 1.0
    insert_bottom = .0012; insert_top = face_top - .0058
    for poly in head.data.polygons:
        center=C(poly.center)
        inset = insert_left<center.x<insert_right and insert_bottom<center.y<insert_top
        if on_face(center,poly.normal,front) and inset: poly.material_index=1
        elif C(poly.normal).y<-.7 and center.y<.012: poly.material_index=2  # sole, including the reference's weight port

    ferrule=tube('Black shaft ferrule',[SOCKET-AXIS*.002,SOCKET+AXIS*.002,SOCKET+AXIS*.013],[.0064,.0062,.0056],64)
    boolean(ferrule,tube('Ferrule shaft passage',[SOCKET-AXIS*.004,SOCKET+AXIS*.015],[.0047,.0047],64))
    bevel(ferrule,.0002,3); finish(ferrule,dark)
    part_reports=[]
    for ob in PARTS:
        cleanup(ob,repair=True); normal_finish(ob); st=stats(ob)
        assert st['nonmanifold_edges']==0,(ob.name,st)
        part_reports.append({'name':ob.name,**st})
    root=bpy.data.objects.new('Fairway_Wood_Head',None); bpy.context.collection.objects.link(root)
    bpy.ops.object.select_all(action='DESELECT')
    for ob in PARTS: ob.select_set(True)
    bpy.context.view_layer.objects.active=PARTS[0]; bpy.ops.object.join()
    mesh=bpy.context.object; mesh.name='wood_head_mesh'; mesh.data.name='fairway_wood_geometry'; mesh.parent=root
    mesh['assembly_components']=json.dumps([p['name'] for p in part_reports])
    root['revision']='3 - combined with a traced reference shell'; root['units']='metres'; root['asset_type']='head_only'; root['family']='fairway'; root['profile']='3_wood'
    root['body_dimensions_mm_xyz']=body_dims; root['shaft_tip_diameter_mm']=9.2; root['bore_diameter_mm']=9.4
    root['lie_degrees']=90-TILT; root['face_loft_degrees']=math.degrees(LOFT)
    marker('shaft_socket',SOCKET,root,True); marker('socket_mouth',SOCKET+AXIS*.013,root,True)
    marker('socket_bottom',SOCKET-AXIS*.0215,root,True)
    fc_y=face_top*.5
    marker('face_center',(0,fc_y,plane_z(fc_y)),root)
    bpy.context.scene.unit_settings.system='METRIC'; bpy.context.scene.unit_settings.scale_length=1
    export('fairway_wood_real_scale.glb')
    active(mesh); bpy.ops.wm.obj_export(filepath=str(PACK/'fairway_wood_real_scale.obj'),export_selected_objects=True,
        forward_axis='NEGATIVE_Z',up_axis='Y',export_materials=True,export_triangulated_mesh=True)
    bpy.context.preferences.filepaths.save_version=0; bpy.ops.wm.save_as_mainfile(filepath=str(PACK/'source/Fairway_Wood_Head.blend'))
    inverse=(Matrix.Translation(V(SOCKET))@Matrix.Rotation(math.radians(-TILT),4,'Y')).inverted()
    for ob in root.children:
        if ob.type=='MESH': ob.data.transform(inverse)
        else: ob.matrix_local=inverse@ob.matrix_local
    root['pivot']='shaft_socket'; root['local_positive_y']='toward grip along shaft'
    export('fairway_wood_shaft_attachment.glb')
    report={'revision':3,**stats(mesh),'body_dimensions_mm_xyz':body_dims,'face_height_mm':face_top*1000,'units':'metres','head_only':True,'profile':'3_wood',
        'shaft_origin_metres':list(SOCKET),'shaft_axis':list(AXIS),'bore_diameter_mm':9.4,'original_shaft_tip_diameter_mm':9.2,
        'lie_degrees':90-TILT,'face_loft_degrees':math.degrees(LOFT),'materials':len(mesh.data.materials),'includes_ferrule':True,
        'closed_assembly_parts':part_reports,'texture_images':0,
        'source_geometry':'assets/Fairway_Wood_Head/source/reference_head.glb (traced from a user-supplied reference model, see README)'}
    (PACK/'geometry_report.json').write_text(json.dumps(report,indent=2)); print('FAIRWAY WOOD COMPLETE',json.dumps(report),flush=True)


if __name__=='__main__': main()
