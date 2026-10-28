"""Fairway wood (3-wood, 15 deg) head asset. Blender 4.3+/5.x bpy; meters, +Y up, face toward -Z.

The photographs guide a modern low-profile fairway wood silhouette: a bluff,
near-full-height face, a crown that peaks a third of the way back and tapers
to a low rounded rear skirt, a cambered sole, and a long tapered hosel.
Units and the shaft connection match the game's original fairway woods
(ofg_loaner_3w and friends): socket (-0.04459, 0.060, -0.005), 61 deg lie,
9.2 mm shaft tip. The body shape is authored here; it is not manufacturer CAD.
"""
from pathlib import Path
import sys; sys.path.insert(0, str(Path(__file__).resolve().parent))
import math, json
import bpy, bmesh
from mathutils import Vector, Matrix
from mesh_helpers import V, C, active, material, obj_mesh, extrusion, tube, smooth, triangulate_caps

PACK = Path(__file__).resolve().parents[1]
PACK.mkdir(parents=True, exist_ok=True)
SOCKET = Vector((-.04459, .060, -.005))
TILT = 29                                       # shaft tilt from vertical; lie = 61 deg
AXIS = Vector((-math.sin(math.radians(TILT)), math.cos(math.radians(TILT)), 0))
LOFT = math.radians(15)
TAN = math.tan(LOFT)
FACE_Z0 = -.026                                 # face plane z at ground level (leading edge)
PARTS = []


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


def bake_location(ob):
    active(ob); bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return ob


def boolean(ob, cutter, operation='DIFFERENCE'):
    active(ob); m = ob.modifiers.new(operation, 'BOOLEAN')
    m.operation = operation; m.solver = 'EXACT'; m.object = cutter
    bpy.ops.object.modifier_apply(modifier=m.name)
    bpy.data.objects.remove(cutter, do_unlink=True); cleanup(ob)


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


def cubic(a,b,c,d,t):
    return Vector(a)*(1-t)**3+3*Vector(b)*t*(1-t)**2+3*Vector(c)*t*t*(1-t)+Vector(d)*t**3


def smoothstep(t):
    t = max(0.0, min(1.0, t)); return t*t*(3-2*t)


def finish(ob, mat):
    bake_location(ob); cleanup(ob); triangulate_caps(ob); smooth(ob)
    ob.data.materials.clear(); ob.data.materials.append(mat)
    ob['component'] = ob.name
    PARTS.append(ob)
    return ob


def on_face(center, normal, front, tol=.00002):
    return normal.dot(front) > .99995 and abs(center.z-plane_z(center.y)) < tol


def normal_finish(ob):
    # Keep the flat striking face flat under smooth shading.
    smooth(ob); ob.data.normals_split_custom_set([(0,0,0)]*len(ob.data.loops))
    normals=[tuple(n.vector) for n in ob.data.corner_normals]
    front=V((0,math.sin(LOFT),-math.cos(LOFT)))
    down=V((0,-1,0))
    for p in ob.data.polygons:
        if on_face(C(p.center), p.normal, front):
            for li in p.loop_indices: normals[li]=tuple(front)
        elif p.normal.dot(down)>.97 and C(p.center).y<.004:
            # The sole camber is 1.2 mm over the whole plate; shade it flat so the long
            # triangles around the recesses do not streak.
            for li in p.loop_indices: normals[li]=tuple(down)
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


# ---------------------------------------------------------------- body shape
def plan_outline(per=20):
    """Skirt outline in the XZ plane (x toe +, z back +). Pear shape: a long,
    gently bulged front edge, a round toe, a broad rear arc and a narrower heel."""
    # Every junction is tangent-continuous (control points collinear across it), so no
    # crease meridians run up the crown from the outline.
    A=(-.031,-.027); B=(.033,-.027); T=(.054,.004); K=(.005,.052); H=(-.052,.006)
    curves=[
        (A,(-.0103,-.0305),(.0143,-.0302),B),        # bulged front edge (before the face cut)
        (B,(.0468,-.0246),(.054,-.010),T),           # large-radius toe front corner
        (T,(.054,.016),(.048,.028),(.038,.037)),      # toe, widest point near the front
        ((.038,.037),(.028,.046),(.018,.052),K),      # toe-side rear taper
        (K,(-.008,.052),(-.018,.049),(-.026,.044)),   # heel-side rear taper
        ((-.026,.044),(-.040,.03525),(-.052,.022),H), # heel
        (H,(-.052,-.006),(-.0438,-.0248),A)]          # heel front corner
    return [cubic(*c,i/per) for c in curves for i in range(per)]


def profile(t, k1, k2):
    """Cubic profile from the skirt (1,0) to the pole (0,1): returns (radial scale, height fraction).
    k1 keeps the skirt vertical for longer; k2 keeps the crown flat for longer."""
    u=1-t
    g=u**3+3*t*u*u+3*t*t*u*k2
    h=3*t*u*u*k1+3*t*t*u+t**3
    return g,h


def outline_normals(outline):
    n=len(outline); area=sum(outline[i].x*outline[(i+1)%n].y-outline[(i+1)%n].x*outline[i].y for i in range(n))
    out=[]
    for i,p in enumerate(outline):
        t=(outline[(i+1)%n]-outline[i-1]).normalized()
        nrm=Vector((t.y,-t.x)) if area>0 else Vector((-t.y,t.x))
        out.append(nrm)
    return out


def wood_blank():
    outline=plan_outline(); n=len(outline); normals=outline_normals(outline)
    zmin=min(p.y for p in outline); zmax=max(p.y for p in outline)
    center=Vector((.001,.010))                      # plan center (x,z) at the skirt
    apex=Vector((-.003,.004)); apex_y=.037          # crown high point
    sole_pole=Vector((.001,.004))                   # ground contact point
    y_eq=.009                                       # skirt height (widest section)
    r_sole=.007; camber=.0012                       # constant-width sole roundover, cambered sole
    NB, NT, NI = 12, 24, 6
    verts=[]; faces=[]
    verts.append((sole_pole.x,0.0,sole_pole.y))
    def crown_ring(t):
        for p in outline:
            rel=p-center
            # Blend the profile by bearing from the plan centre so it changes continuously
            # along the flat front edge: 0 facing the face, 1 facing the rear.
            w=smoothstep(math.atan2(abs(rel.x),-rel.y)/math.pi)
            k1=.46+(.20-.46)*w; k2=.52+(.32-.52)*w
            g,h=profile(t,k1,k2)
            c=center+(apex-center)*h
            q=c+rel*g; y=y_eq+(apex_y-y_eq)*h
            verts.append((q.x,y,q.y))
    def sole_ring(phi):
        # Quarter roundover of constant width, offset along the local outline normal.
        d=r_sole*(1-math.cos(phi)); y=y_eq*(1-math.sin(phi))+camber*math.sin(phi)
        for p,nrm in zip(outline,normals):
            q=p-nrm*d; verts.append((q.x,y,q.y))
    def inner_ring(s):
        for p,nrm in zip(outline,normals):
            q=sole_pole+((p-nrm*r_sole)-sole_pole)*(1-s); verts.append((q.x,camber*(1-s*s),q.y))
    for j in range(NI-1,0,-1): inner_ring(j/NI)
    for j in range(NB,0,-1): sole_ring(math.pi/2*j/NB)
    crown_ring(0.0)
    for j in range(1,NT): crown_ring(j/NT)
    verts.append((apex.x,apex_y,apex.y))
    rings=(len(verts)-2)//n
    base=1
    for i in range(n): faces.append((0,base+(i+1)%n,base+i))
    for j in range(rings-1):
        for i in range(n): faces.append((base+j*n+i,base+j*n+(i+1)%n,base+(j+1)*n+(i+1)%n,base+(j+1)*n+i))
    top=base+(rings-1)*n; apex_i=len(verts)-1
    for i in range(n): faces.append((top+i,top+(i+1)%n,apex_i))
    ob=obj_mesh('Fairway wood body',verts,faces)
    smooth(ob)
    return ob


def face_cutter():
    cutter=extrusion('Face plane cutter',rounded_rect(-.09,.09,-.02,.08,.001,4),-.12,FACE_Z0,axis='z',radius=0)
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
    face_polys=[p for p in me.polygons if on_face(C(p.center),p.normal,front,.00002)]
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
    bpy.ops.wm.read_factory_settings(use_empty=True)
    gloss=material('Gloss black crown',(.010,.011,.013),.30,.20)
    face=material('Satin steel face',(.33,.35,.37),.90,.50)
    sole=material('Brushed steel sole',(.42,.44,.46),.92,.42)
    dark=material('Black shaft ferrule',(.006,.008,.010),.02,.65)

    head=wood_blank()
    boolean(head,face_cutter())
    points=[C(v.co) for v in head.data.vertices]
    body_dims=[1000*(max(p[i] for p in points)-min(p[i] for p in points)) for i in range(3)]
    face_top=max(p.y for p in points if abs(p.z-plane_z(p.y))<.00002)
    boolean(head,hosel_mesh(),'UNION')
    bevel(head,.0009,5,angle=.50)
    cleanup(head,repair=True)
    # Scorelines follow the face outline, with a clear margin.
    lines=0; slots=[]
    for i in range(9):
        y=.0055+i*.0028
        crossing=face_boundary_crossings(head,y)
        if len(crossing)<2: continue
        left=min(crossing)+.0045; right=max(crossing)-.0045
        if right-left<.020: continue
        slot=rounded_rect(left,right,y-.00027,y+.00027,.00024,6)
        cutter=extrusion('Cut scoreline '+str(i+1),slot,-.032,FACE_Z0+.0004,axis='z',radius=0)
        shear(cutter); boolean(head,cutter); lines+=1; slots.append((left,right,y))
    bore=tube('Wood shaft bore',[SOCKET-AXIS*.024,SOCKET+AXIS*.018],[.0047,.0047],64)
    boolean(head,bore)
    # Sole details: a shallow speed slot behind the leading edge and a round rear weight port.
    SLOT=(-.031,.031,-.0150,-.0085); PORT=(Vector((.003,.036)),.0062)
    slot=extrusion('Cut sole slot',rounded_rect(SLOT[0],SLOT[1],SLOT[2],SLOT[3],.0028,8),-.005,.0020,axis='y',radius=0)
    boolean(head,slot)
    port=tube('Cut weight port',[(PORT[0].x,-.005,PORT[0].y),(PORT[0].x,.0022,PORT[0].y)],[PORT[1],PORT[1]],48)
    boolean(head,port)
    def in_recess(c):
        return (SLOT[0]-.0005<c.x<SLOT[1]+.0005 and SLOT[2]-.0005<c.z<SLOT[3]+.0005) or (Vector((c.x,c.z))-PORT[0]).length<PORT[1]+.0005
    cleanup(head,repair=True)
    finish(head,gloss)
    head.data.materials.append(face); head.data.materials.append(sole)
    front=V((0,math.sin(LOFT),-math.cos(LOFT)))
    # A real face insert sits inboard of the cast body with a visible gloss-black bezel
    # all around it (see the Founders Club/BANG reference photos); without this the
    # satin material fills the whole flat-cut face edge to edge and reads as one slab.
    mid_y = (slots[len(slots)//2][2] if slots else .012)
    edge = face_boundary_crossings(head, mid_y)
    bezel = .0068
    if len(edge) >= 2:
        insert_left, insert_right = min(edge)+bezel, max(edge)-bezel
    else:
        insert_left, insert_right = -1.0, 1.0
    insert_bottom = -.0005
    insert_top = face_top - .0058
    for poly in head.data.polygons:
        center=C(poly.center); d=center.z-plane_z(center.y)
        inset = insert_left<center.x<insert_right and insert_bottom<center.y<insert_top
        if on_face(center,poly.normal,front) and inset: poly.material_index=1
        elif -.00001<d<.00062 and any(l-.0004<center.x<r+.0004 and abs(center.y-yy)<.0004 for l,r,yy in slots):
            poly.material_index=1                                          # scoreline walls and floors
        elif C(poly.normal).y<-.78 and center.y<.006 and not (center.y>.0014 and in_recess(center)): poly.material_index=2

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
    root['revision']='1 - low profile 3-wood'; root['units']='metres'; root['asset_type']='head_only'; root['family']='fairway'; root['profile']='3_wood'
    root['body_dimensions_mm_xyz']=body_dims; root['shaft_tip_diameter_mm']=9.2; root['bore_diameter_mm']=9.4
    root['lie_degrees']=90-TILT; root['face_loft_degrees']=math.degrees(LOFT); root['scorelines']=lines
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
    report={'revision':1,**stats(mesh),'body_dimensions_mm_xyz':body_dims,'face_height_mm':face_top*1000,'units':'metres','head_only':True,'profile':'3_wood',
        'shaft_origin_metres':list(SOCKET),'shaft_axis':list(AXIS),'bore_diameter_mm':9.4,'original_shaft_tip_diameter_mm':9.2,
        'lie_degrees':90-TILT,'face_loft_degrees':math.degrees(LOFT),'scorelines':lines,'materials':len(mesh.data.materials),'includes_ferrule':True,
        'closed_assembly_parts':part_reports,'texture_images':0}
    (PACK/'geometry_report.json').write_text(json.dumps(report,indent=2)); print('FAIRWAY WOOD COMPLETE',json.dumps(report),flush=True)


if __name__=='__main__': main()
