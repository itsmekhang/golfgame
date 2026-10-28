"""AutoPutt 9000 head-only ring mallet asset. Blender 4.3 bpy; meters, +Y up, face toward -Z.

The reference establishes appearance. The authored body is 114 x 94 x 28 mm,
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


def ring_outline():
    out=[(-.029,-.006),(.029,-.006)]
    curves=[((.029,-.006),(.025,.000),(.024,.009),(.029,.014)),
            ((.029,.014),(.037,.020),(.044,.028),(.044,.040)),
            ((.044,.040),(.044,.060),(.025,.076),(0,.076)),
            ((0,.076),(-.025,.076),(-.044,.060),(-.044,.040)),
            ((-.044,.040),(-.044,.028),(-.037,.020),(-.029,.014)),
            ((-.029,.014),(-.024,.009),(-.025,.000),(-.029,-.006))]
    for c in curves:
        for i in range(1,21): out.append(tuple(cubic(*c,i/20)))
    return out[:-1]


def face_panel():
    ymin,ymax=.005,.023; r=.0024
    rows={ymin:0,ymax:0}
    for i in range(24):
        center=.0063+i*.00065
        for dy in [-.00013,-.00003,.00003,.00013]: rows[center+dy]=0
    for i in range(1,9): rows.setdefault(ymin+r*i/9,0); rows.setdefault(ymax-r*i/9,0)
    verts=[]; keys=sorted(rows)
    for y in keys:
        edge=min(y-ymin,ymax-y)
        half=.0445 if edge>=r else .0445-r+math.sqrt(max(0,r*r-(r-edge)**2))
        depth=0
        for i in range(24):
            d=abs(y-(.0063+i*.00065))
            if d<.00013: depth=max(depth,.000085*min(1,(.00013-d)/.00010))
        verts.extend([(-half,y,-.01805+depth),(half,y,-.01805+depth),(-half,y,-.0153),(half,y,-.0153)])
    faces=[(0,2,3,1)]
    for i in range(len(keys)-1):
        a=i*4; b=a+4
        faces.extend([(a,a+1,b+1,b),(a+2,b+2,b+3,a+3),(a,b,b+2,a+2),(a+1,a+3,b+3,b+1)])
    a=(len(keys)-1)*4; faces.append((a,a+1,a+3,a+2))
    return obj_mesh('Fine milled brass face insert',verts,faces)


def hex_recess(ob,center,axis,radius,depth):
    c=Vector(center); a=Vector(axis).normalized()
    helper=Vector((1,0,0)) if abs(a.x)<.9 else Vector((0,0,1))
    u=(helper-a*helper.dot(a)).normalized(); v=a.cross(u)
    verts=[]
    for t in [-depth,.002]:
        for i in range(6):
            angle=i*math.tau/6; verts.append(c+a*t+radius*(u*math.cos(angle)+v*math.sin(angle)))
    faces=[tuple(reversed(range(6))),tuple(range(6,12))]
    faces += [(i,(i+1)%6,(i+1)%6+6,i+6) for i in range(6)]
    boolean(ob,obj_mesh('Hex drive cutter',verts,faces))


def screw(name,center,axis,radius,mat):
    a=Vector(axis); c=Vector(center)
    ob=tube(name,[c-a*.00155,c-a*.00030,c],[radius*.90,radius,radius*.91],40)
    hex_recess(ob,c,a,radius*.36,.00075)
    bevel(ob,.00006,2); finish(ob,mat)


def swept_neck():
    end=SOCKET-AXIS*.007
    controls=[Vector((-.018,.023,.006)),Vector((-.017,.045,.006)),end-AXIS*.013,end]
    path=[cubic(*controls,i/30) for i in range(31)]
    return tube('Swept stainless shaft connection',path,[.00525+(.00602-.00525)*i/30 for i in range(31)],56)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    black=material('Graphite black ring chassis',(.014,.020,.027),.56,.42)
    red=material('Crimson anodized face bar',(.30,.022,.031),.67,.32)
    brass=material('Brushed brass striking insert',(.52,.30,.105),.88,.34)
    white=material('White T alignment and numerals',(.88,.91,.89),.06,.32)
    steel=material('Stainless neck and fasteners',(.48,.53,.56),.96,.27)

    body=extrusion('Circular rear chassis',ring_outline(),.001,.026,radius=0)
    boolean(body,tube('38 mm through-opening',[(0,-.006,.040),(0,.034,.040)],[.019,.019],112))
    bevel(body,.00125,4)
    fasteners=[(-.025,.010),(.025,.010),(-.032,.035),(.032,.035),(-.023,.060),(.023,.060)]
    for x,z in fasteners:
        boolean(body,tube('Underside screw counterbore',[(x,-.003,z),(x,.0032,z)],[.0036,.0036],40))
    bevel(body,.00018,3); finish(body,black)

    rail_outline=rounded_polygon([(-.057,-.018),(.057,-.018),(.057,-.008),(.048,.004),(-.048,.004),(-.057,-.008)],.0016,7)
    rail=extrusion('Red full-width face bar',rail_outline,0,.028,radius=0)
    bevel(rail,.0009,4)
    opening=rounded_rect(-.0447,.0447,.0048,.0232,.0025,10)
    boolean(rail,extrusion('Brass insert seat',opening,-.022,-.0150,axis='z',radius=0))
    for x in [-.0505,.0505]:
        boolean(rail,tube('Face insert mounting recess',[(x,.014,-.022),(x,.014,-.0154)],[.0023,.0023],40))
    # White T uses a single recessed solid inlay on the face bar's top surface.
    t_outline=[(-.025,-.0118),(.025,-.0118),(.025,-.0109),(.00048,-.0109),
               (.00048,.001),(-.00048,.001),(-.00048,-.0109),(-.025,-.0109)]
    boolean(rail,extrusion('T alignment recess',t_outline,.02725,.031,radius=0))
    bevel(rail,.00012,2); finish(rail,red)
    mark=extrusion('White T alignment',t_outline,.02732,.02794,radius=0)
    bevel(mark,.00008,2); finish(mark,white)
    finish(face_panel(),brass)
    for x in [-.0505,.0505]:
        screw('Brass face retaining screw', (x,.014,-.01794),(0,0,-1),.00205,steel)
    for i,(x,z) in enumerate(fasteners,1):
        screw('Underside tuning screw '+str(i),(x,.00110,z),(0,-1,0),.00338,steel)

    # Model identification on the rear arc; no texture dependency.
    curve=bpy.data.curves.new('9000 numerals','FONT'); curve.body='9000'; curve.size=.005
    curve.align_x='CENTER'; curve.align_y='CENTER'; curve.extrude=.000055; curve.bevel_depth=.000012; curve.bevel_resolution=1; curve.resolution_u=8
    text=bpy.data.objects.new('AutoPutt 9000 rear marking',curve); bpy.context.collection.objects.link(text)
    text.location=V((0,.02604,.067)); active(text); bpy.ops.object.convert(target='MESH'); finish(bpy.context.object,white)

    points=[C(v.co) for ob in PARTS for v in ob.data.vertices]
    lo=Vector([min(p[i] for p in points) for i in range(3)]); hi=Vector([max(p[i] for p in points) for i in range(3)])
    target_lo=Vector((-.057,0,-.018)); target_size=Vector((.114,.028,.094))
    for ob in PARTS:
        for v in ob.data.vertices:
            p=C(v.co); v.co=V(tuple(target_lo[i]+(p[i]-lo[i])*target_size[i]/(hi[i]-lo[i]) for i in range(3)))
        loft_front(ob)
    points=[C(v.co) for ob in PARTS for v in ob.data.vertices]
    body_dims=[1000*(max(p[i] for p in points)-min(p[i] for p in points)) for i in range(3)]

    # Compact connection to the existing 9.2 mm shaft tip; +Y points to the grip.
    foot=tube('Black hosel foot',[(-.018,.0215,.006),(-.018,.029,.006)],[.0064,.0057],56)
    bevel(foot,.00045,3); finish(foot,black)
    neck=swept_neck()
    boolean(neck,tube('Upper shaft sleeve',[SOCKET-AXIS*.010,SOCKET+AXIS*.009],[.00608,.00585],64),'UNION')
    boolean(neck,tube('9.4 mm shaft socket',[SOCKET-AXIS*.0095,SOCKET+AXIS*.012],[.0047,.0047],64))
    bevel(neck,.00020,3); finish(neck,steel)

    part_reports=[]
    for ob in PARTS:
        cleanup(ob,repair=True); normal_finish(ob); st=stats(ob)
        assert st['nonmanifold_edges']==0,(ob.name,st)
        part_reports.append({'name':ob.name,**st})
    root=bpy.data.objects.new('AutoPutt_9000_Head',None); bpy.context.collection.objects.link(root)
    bpy.ops.object.select_all(action='DESELECT')
    for ob in PARTS: ob.select_set(True)
    bpy.context.view_layer.objects.active=PARTS[0]; bpy.ops.object.join()
    mesh=bpy.context.object; mesh.name='putter_head_mesh'; mesh.data.name='autoputt_9000_ring_geometry'; mesh.parent=root
    mesh['assembly_components']=json.dumps([p['name'] for p in part_reports])
    root['units']='metres'; root['asset_type']='head_only'; root['body_dimensions_mm_xyz']=body_dims
    root['nominal_body_dimensions_mm_width_depth_height']=[114,94,28]
    root['bore_diameter_mm']=9.4; root['shaft_tip_diameter_mm']=9.2; root['lie_degrees']=71; root['face_loft_degrees']=3.5
    root['design']='black circular chassis, open rear ring, red face bar, brass insert, T alignment, exposed tuning hardware'
    marker('shaft_socket',SOCKET,root,True); marker('socket_mouth',SOCKET+AXIS*.009,root,True)
    marker('socket_bottom',SOCKET-AXIS*.0095,root,True)
    marker('face_center',(0,.014,-.018+(.014-.0046)*math.tan(LOFT)),root)
    bpy.context.scene.unit_settings.system='METRIC'; bpy.context.scene.unit_settings.scale_length=1
    export('autoputt_9000_real_scale.glb')
    active(mesh); bpy.ops.wm.obj_export(filepath=str(PACK/'autoputt_9000_real_scale.obj'),export_selected_objects=True,
        forward_axis='NEGATIVE_Z',up_axis='Y',export_materials=True,export_triangulated_mesh=True)
    bpy.context.preferences.filepaths.save_version=0; bpy.ops.wm.save_as_mainfile(filepath=str(PACK/'source/AutoPutt_9000_Head.blend'))
    inverse=(Matrix.Translation(V(SOCKET))@Matrix.Rotation(math.radians(-19),4,'Y')).inverted()
    for ob in root.children:
        if ob.type=='MESH': ob.data.transform(inverse)
        else: ob.matrix_local=inverse@ob.matrix_local
    root['pivot']='shaft_socket'; root['local_positive_y']='toward grip along shaft'
    export('autoputt_9000_shaft_attachment.glb')
    report={**stats(mesh),'body_dimensions_mm_xyz':body_dims,'nominal_body_dimensions_mm_width_depth_height':[114,94,28],
        'units':'metres','head_only':True,'shaft_origin_metres':list(SOCKET),'shaft_axis':list(AXIS),
        'bore_diameter_mm':9.4,'original_shaft_tip_diameter_mm':9.2,'lie_degrees':71,'face_loft_degrees':3.5,
        'materials':len(mesh.data.materials),'closed_assembly_parts':part_reports,'horizontal_face_grooves':24,
        'nominal_rear_opening_diameter_mm':38,'underside_fasteners':6,'face_fasteners':2,'texture_images':0}
    (PACK/'geometry_report.json').write_text(json.dumps(report,indent=2))
    print('AUTOPUTT 9000 COMPLETE',json.dumps(report),flush=True)


if __name__=='__main__': main()

