"""Head-only half-moon mallet asset. Blender 4.3 bpy; meters, +Y up, face toward -Z.

The reference establishes appearance. The authored body is 114 x 72 x 28 mm,
and the shaft connection is shared with the earlier game putter heads.
"""
from pathlib import Path
import math, json
import bpy, bmesh
from mathutils import Vector, Matrix
from mesh_helpers import V, C, active, material, obj_mesh, box, extrusion, tube, smooth, triangulate_caps

PACK = Path(__file__).resolve().parents[1]
SOCKET = Vector((-.041, .070, -.016))
AXIS = Vector((-math.sin(math.radians(19)), math.cos(math.radians(19)), 0))
LOFT = math.radians(3.5)
PARTS = []


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


def rounded_polygon(points, radius=.002, steps=6):
    pts = [Vector(p) for p in points]; out = []
    for i, p in enumerate(pts):
        prev, nxt = pts[i-1], pts[(i+1)%len(pts)]
        r = min(radius, (prev-p).length*.35, (nxt-p).length*.35)
        a = p+(prev-p).normalized()*r; b = p+(nxt-p).normalized()*r
        for j in range(steps+1):
            t = j/steps; out.append(tuple((1-t)**2*a+2*t*(1-t)*p+t*t*b))
    return out


def cubic(a,b,c,d,t):
    return Vector(a)*(1-t)**3+3*Vector(b)*t*(1-t)**2+3*Vector(c)*t*t*(1-t)+Vector(d)*t**3


def finish(ob, mat):
    bake_location(ob); cleanup(ob); triangulate_caps(ob); smooth(ob)
    ob.data.materials.clear(); ob.data.materials.append(mat)
    ob['component'] = ob.name
    PARTS.append(ob)
    return ob


def normal_finish(ob):
    # Preserve planar contact surfaces without flattening the bevel highlights.
    smooth(ob); ob.data.normals_split_custom_set([(0,0,0)]*len(ob.data.loops))
    normals = [tuple(n.vector) for n in ob.data.corner_normals]
    directions = [V((0,math.sin(LOFT),-math.cos(LOFT)))]
    directions += [V(p) for p in [(1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)]]
    for p in ob.data.polygons:
        match = next((n for n in directions if p.normal.dot(n)>.999995), None)
        if match is not None:
            for li in p.loop_indices: normals[li] = tuple(match)
    ob.data.normals_split_custom_set(normals)


def loft_front(ob):
    bm = bmesh.new(); bm.from_mesh(ob.data)
    bmesh.ops.bisect_plane(bm, geom=list(bm.verts)+list(bm.edges)+list(bm.faces),
        dist=1e-7, plane_co=V((0,.0046,0)), plane_no=V((0,1,0)), clear_inner=False, clear_outer=False)
    bm.to_mesh(ob.data); bm.free()
    for v in ob.data.vertices:
        p = C(v.co); w = min(1, max(0,(-.006-p.z)/.010))
        p.z += w*max(0,p.y-.0046)*math.tan(LOFT); v.co = V(p)
    cleanup(ob)


def lathe(name, center, direction, profile, sides=64):
    center = Vector(center); axis = Vector(direction).normalized()
    a = axis.cross(Vector((0,1,0))).normalized(); b = axis.cross(a).normalized()
    vertices = []
    for offset, radius in profile:
        for j in range(sides):
            t = j*math.tau/sides
            vertices.append(center+axis*offset+radius*(a*math.cos(t)+b*math.sin(t)))
    n = len(profile); faces = [tuple(reversed(range(sides))), tuple((n-1)*sides+j for j in range(sides))]
    for i in range(n-1):
        for j in range(sides): faces.append((i*sides+j,i*sides+(j+1)%sides,(i+1)*sides+(j+1)%sides,(i+1)*sides+j))
    return obj_mesh(name, vertices, faces)


def marker(name, point, root, shaft=False):
    ob = bpy.data.objects.new(name, None); bpy.context.collection.objects.link(ob)
    ob.parent=root; ob.location=V(point); ob.empty_display_type='ARROWS'; ob.empty_display_size=.010
    if shaft: ob.rotation_euler.y=math.radians(-19)
    if name=='face_center': ob.rotation_euler.x=LOFT
    return ob


def stats(ob):
    ob.data.calc_loop_triangles(); bm=bmesh.new(); bm.from_mesh(ob.data)
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


def half_moon_outline():
    result=[(-.049,-.018),(.049,-.018)]
    for i in range(1,13):
        result.append(tuple(cubic((.049,-.018),(.055,-.018),(.057,-.012),(.057,-.004),i/12)))
    for i in range(1,73):
        t=math.pi*i/72; result.append((.057*math.cos(t),-.004+.058*math.sin(t)))
    for i in range(1,12):
        result.append(tuple(cubic((-.057,-.004),(-.057,-.012),(-.055,-.018),(-.049,-.018),i/12)))
    return result


def shoulder_cutter():
    profile=[]
    for i in range(49):
        t=i/48; z=.007+.047*t
        height=.007+.021*(1-math.sin(t*math.pi/2))
        profile.append((height,z))
    profile.extend([(.007,.090),(.14,.090),(.14,.007)])
    verts=[(x,y,z) for x in [-.12,.12] for y,z in profile]; n=len(profile)
    faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]
    faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    return obj_mesh('Sculpted shoulder envelope',verts,faces)


def arc_outline(width=.0013):
    outer=[]; inner=[]
    for i in range(81):
        t=math.radians(5+170*i/80)
        outer.append(((.052+width/2)*math.cos(t),-.004+(.053+width/2)*math.sin(t)))
        inner.append(((.052-width/2)*math.cos(t),-.004+(.053-width/2)*math.sin(t)))
    return outer+list(reversed(inner))


def milled_face():
    # A closed panel with physically recessed channels. Flat land strips retain
    # the 3.5-degree contact plane; groove ramps are modeled explicitly.
    y0,y1=.0026,.0254; r=.0034
    rows={y0:0,y1:0}
    for center in [.0040+i*.00064 for i in range(32)]:
        for dy,depth in [(-.00015,0),(-.00004,.00012),(.00004,.00012),(.00015,0)]:
            rows[center+dy]=depth
    for i in range(1,9):
        rows.setdefault(y0+r*i/9,0); rows.setdefault(y1-r*i/9,0)
    # Interpolate the groove depth at added outline samples.
    keys=sorted(rows)
    verts=[]
    for y in keys:
        depth=0
        for center in [.0040+i*.00064 for i in range(32)]:
            d=abs(y-center)
            if d<.00015: depth=max(depth,.00012*min(1,(.00015-d)/.00011))
        edge_distance=min(y-y0,y1-y)
        half=.0515 if edge_distance>=r else .0515-r+math.sqrt(max(0,r*r-(r-edge_distance)**2))
        verts.extend([(-half,y,-.01805+depth),(half,y,-.01805+depth),
                      (-half,y,-.0161),(half,y,-.0161)])
    faces=[(0,2,3,1)]
    for i in range(len(keys)-1):
        a=i*4; b=a+4
        faces.extend([(a,a+1,b+1,b),(a+2,b+2,b+3,a+3),
                      (a,b,b+2,a+2),(a+1,a+3,b+3,b+1)])
    a=(len(keys)-1)*4; faces.append((a,a+1,a+3,a+2))
    return obj_mesh('Micro-milled striking face',verts,faces)


def compact_neck():
    end=SOCKET-AXIS*.007
    controls=[Vector((-.029,.024,-.010)),Vector((-.028,.046,-.010)),end-AXIS*.010,end]
    rings=24; sides=40; verts=[]
    for i in range(rings+1):
        t=i/rings; point=cubic(*controls,t)
        direction=(3*(1-t)**2*(controls[1]-controls[0])+6*t*(1-t)*(controls[2]-controls[1])+3*t*t*(controls[3]-controls[2])).normalized()
        a=Vector((1,0,0)); a=(a-direction*a.dot(direction)).normalized(); b=direction.cross(a).normalized()
        exponent=3.5-1.5*t; width=.0045*(1-t)+.0059*t; depth=.0043*(1-t)+.0059*t
        for j in range(sides):
            angle=j*math.tau/sides; ca,sa=math.cos(angle),math.sin(angle)
            x=width*math.copysign(abs(ca)**(2/exponent),ca)
            z=depth*math.copysign(abs(sa)**(2/exponent),sa)
            verts.append(point+a*x+b*z)
    faces=[tuple(reversed(range(sides))),tuple(rings*sides+j for j in range(sides))]
    for i in range(rings):
        for j in range(sides): faces.append((i*sides+j,i*sides+(j+1)%sides,(i+1)*sides+(j+1)%sides,(i+1)*sides+j))
    return obj_mesh('Compact black offset neck',verts,faces)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    black=material('Satin black PVD body',(.019,.022,.025),.74,.43)
    face_mat=material('Milled dark steel face',(.024,.028,.031),.80,.40)
    white=material('Ivory alignment inlays',(.86,.89,.87),.08,.31)
    steel=material('Stainless shaft socket',(.50,.54,.56),.95,.27)
    lime=material('Lime cavity accent',(.17,.42,.019),.12,.38)

    head=extrusion('Half-moon mallet body',half_moon_outline(),0,.028,radius=0)
    silhouette=extrusion('Rounded face silhouette',rounded_rect(-.057,.057,0,.028,.005,12),-.05,.10,axis='z',radius=0)
    boolean(head,silhouette,'INTERSECT')
    boolean(head,shoulder_cutter())
    cavity=box('Deep open rear scoop',(0,.043,.041),(.064,.076,.078),.007,12)
    boolean(head,cavity)
    bevel(head,.0011,4)

    # A broad bow-shaped alignment inlay sits behind the shaft on the crown.
    crown_outline=rounded_polygon([(-.050,-.014),(-.039,-.014),(-.021,-.001),(.021,-.001),
        (.044,-.014),(.050,-.013),(.049,.003),(.022,.005),(-.022,.005),(-.049,.003)],.0006,6)
    boolean(head,extrusion('Crown alignment recess',crown_outline,.02735,.031,radius=0))
    face_outline=rounded_rect(-.0517,.0517,.0024,.0256,.0035,12)
    boolean(head,extrusion('Milled face seat',face_outline,-.022,-.0157,axis='z',radius=0))
    boolean(head,extrusion('Underside arc seat',arc_outline(.00165),-.002,.0011,radius=0))
    badge_outline=rounded_rect(-.021,.021,.014,.025,.0028,10)
    boolean(head,extrusion('Cavity badge seat',badge_outline,.00065,.0050,axis='z',radius=0))
    bevel(head,.00022,3)
    finish(head,black)

    crown=extrusion('White bow alignment inlay',crown_outline,.02742,.02795,radius=0)
    bevel(crown,.00012,3); finish(crown,white)
    face=milled_face(); finish(face,face_mat)
    sole_arc=extrusion('White underside perimeter arc',arc_outline(.00125),.00008,.00105,radius=0)
    bevel(sole_arc,.00007,2); finish(sole_arc,white)
    frame=extrusion('Lime cavity badge rim',badge_outline,.00085,.00218,axis='z',radius=0)
    bevel(frame,.00018,3); finish(frame,lime)
    inner=extrusion('Black cavity badge',rounded_rect(-.0198,.0198,.0147,.0243,.0023,10),.0011,.00234,axis='z',radius=0)
    bevel(inner,.00018,3); finish(inner,black)
    # Small original model lettering is actual shallow extruded geometry.
    curve=bpy.data.curves.new('ARC lettering','FONT'); curve.body='ARC'; curve.size=.0063
    curve.align_x='CENTER'; curve.align_y='CENTER'; curve.extrude=.00006; curve.bevel_depth=.000015; curve.bevel_resolution=1; curve.resolution_u=8
    label=bpy.data.objects.new('ARC cavity lettering',curve); bpy.context.collection.objects.link(label)
    label.location=V((0,.0194,.00236)); label.rotation_euler.x=math.pi/2
    active(label); bpy.ops.object.convert(target='MESH'); finish(bpy.context.object,white)

    # Normalize the body and its inlays before attaching the shared socket.
    points=[C(v.co) for ob in PARTS for v in ob.data.vertices]
    lo=Vector([min(p[i] for p in points) for i in range(3)])
    hi=Vector([max(p[i] for p in points) for i in range(3)])
    target_lo=Vector((-.057,0,-.018)); target_size=Vector((.114,.028,.072))
    for ob in PARTS:
        for v in ob.data.vertices:
            p=C(v.co); v.co=V(tuple(target_lo[i]+(p[i]-lo[i])*target_size[i]/(hi[i]-lo[i]) for i in range(3)))
        loft_front(ob)
    points=[C(v.co) for ob in PARTS for v in ob.data.vertices]
    body_dims=[1000*(max(p[i] for p in points)-min(p[i] for p in points)) for i in range(3)]

    neck=compact_neck()
    boolean(neck,tube('Bore into black neck',[SOCKET-AXIS*.0095,SOCKET+AXIS*.012],[.0047,.0047],64))
    bevel(neck,.00038,3); finish(neck,black)
    collar=tube('Stainless socket sleeve',[SOCKET-AXIS*.010,SOCKET+AXIS*.009],[.00612,.00585],64)
    boolean(collar,tube('9.4 mm shaft bore',[SOCKET-AXIS*.0095,SOCKET+AXIS*.012],[.0047,.0047],64))
    bevel(collar,.00015,3); finish(collar,steel)

    part_reports=[]
    for ob in PARTS:
        cleanup(ob,repair=True); normal_finish(ob); st=stats(ob)
        assert st['nonmanifold_edges']==0,(ob.name,st)
        part_reports.append({'name':ob.name,**st})
    root=bpy.data.objects.new('Obsidian_Arc_Mallet_Head',None); bpy.context.collection.objects.link(root)
    bpy.ops.object.select_all(action='DESELECT')
    for ob in PARTS: ob.select_set(True)
    bpy.context.view_layer.objects.active=PARTS[0]; bpy.ops.object.join()
    mesh=bpy.context.object; mesh.name='putter_head_mesh'; mesh.data.name='obsidian_arc_mallet_geometry'; mesh.parent=root
    mesh['assembly_components']=json.dumps([p['name'] for p in part_reports])
    root['units']='metres'; root['asset_type']='head_only'; root['body_dimensions_mm_xyz']=body_dims
    root['nominal_body_dimensions_mm_width_depth_height']=[114,72,28]
    root['bore_diameter_mm']=9.4; root['shaft_tip_diameter_mm']=9.2; root['lie_degrees']=71; root['face_loft_degrees']=3.5
    root['design']='black half-moon mallet, scooped rear cavity, ivory bow inlay, milled face, lime badge'
    marker('shaft_socket',SOCKET,root,True); marker('socket_mouth',SOCKET+AXIS*.009,root,True)
    marker('socket_bottom',SOCKET-AXIS*.0095,root,True)
    marker('face_center',(0,.014,-.018+(.014-.0046)*math.tan(LOFT)),root)
    bpy.context.scene.unit_settings.system='METRIC'; bpy.context.scene.unit_settings.scale_length=1
    export('obsidian_arc_mallet_real_scale.glb')
    active(mesh); bpy.ops.wm.obj_export(filepath=str(PACK/'obsidian_arc_mallet_real_scale.obj'),export_selected_objects=True,
        forward_axis='NEGATIVE_Z',up_axis='Y',export_materials=True,export_triangulated_mesh=True)
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(PACK/'source/Obsidian_Arc_Mallet_Head.blend'))
    inverse=(Matrix.Translation(V(SOCKET))@Matrix.Rotation(math.radians(-19),4,'Y')).inverted()
    for ob in root.children:
        if ob.type=='MESH': ob.data.transform(inverse)
        else: ob.matrix_local=inverse@ob.matrix_local
    root['pivot']='shaft_socket'; root['local_positive_y']='toward grip along shaft'
    export('obsidian_arc_mallet_shaft_attachment.glb')
    report={**stats(mesh),'body_dimensions_mm_xyz':body_dims,'nominal_body_dimensions_mm_width_depth_height':[114,72,28],
        'units':'metres','head_only':True,'shaft_origin_metres':list(SOCKET),'shaft_axis':list(AXIS),
        'bore_diameter_mm':9.4,'original_shaft_tip_diameter_mm':9.2,'lie_degrees':71,'face_loft_degrees':3.5,
        'materials':len(mesh.data.materials),'closed_assembly_parts':part_reports,'horizontal_face_grooves':32,'texture_images':0}
    (PACK/'geometry_report.json').write_text(json.dumps(report,indent=2))
    print('OBSIDIAN ARC COMPLETE',json.dumps(report),flush=True)


if __name__=='__main__': main()

