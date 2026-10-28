"""Head-only mallet asset. Blender 4.3 bpy; meters, +Y up, face toward -Z.

The reference establishes appearance. The authored body is 114 x 92 x 28 mm,
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


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    white = material('Pearl white crown', (.88,.90,.91), .18, .28)
    aqua = material('Turquoise anodized wings', (.050,.420,.535), .62, .31)
    insert_mat = material('Turquoise grooved face insert', (.095,.475,.590), .12, .44)
    steel = material('Polished stainless hardware', (.53,.57,.59), .95, .23)
    graphite = material('Graphite gaskets and sole badge', (.018,.023,.028), .40, .38)

    # White crown: broad in front, clipped and tapered between the rear forks.
    crown_outline = rounded_polygon([(-.052,-.017),(.052,-.017),(.056,-.010),(.057,.003),
        (.053,.017),(.043,.030),(.022,.049),(-.022,.049),(-.043,.030),(-.053,.017),(-.057,.003),(-.056,-.010)],.004,8)
    head = extrusion('White crown and central chassis', crown_outline, .0244, .028, radius=0)
    beam = extrusion('Full height striking frame', rounded_rect(-.057,.057,0,.028,.004,10), -.018,-.008,axis='z',radius=0)
    boolean(head,beam,'UNION')
    core_outline=rounded_polygon([(-.046,-.013),(.046,-.013),(.046,.007),(.040,.021),(.024,.044),(.023,.049),(-.023,.049),(-.024,.044),(-.040,.021),(-.046,.007)],.002,6)
    boolean(head,extrusion('Central sole chassis',core_outline,.0018,.0248,radius=0),'UNION')
    # The crown overhangs an open rear chamber and a thin sole bridge, avoiding
    # a solid block between the two rear outriggers.
    rear_chamber=box('Open chamber beneath suspended crown',(0,.0144,.055),(.070,.0188,.058),.0013,5)
    boolean(head,rear_chamber)
    bevel(head,.001,4)

    # Inset striking face and its thin dark perimeter gasket.
    outer = rounded_polygon([(-.047,.020),(-.044,.024),(.044,.024),(.047,.020),(.043,.004),(-.043,.004)],.003,8)
    boolean(head,extrusion('Face recess',outer,-.022,-.0150,axis='z',radius=0))
    # Recess the three alignment dots into the top plate.
    for z in [-.008,.001,.010]:
        boolean(head,tube('Dot seat',[(0,.0273,z),(0,.030,z)],[.00255,.00255],48))
    # The central sole badge is set into the underside, not floating below it.
    badge_outline=rounded_polygon([(-.021,-.002),(.021,-.002),(.025,.025),(.016,.043),(-.016,.043),(-.025,.025)],.003,8)
    boolean(head,extrusion('Sole badge recess',badge_outline,-.002,.0039,radius=0))
    bevel(head,.00030,3)
    finish(head,white)

    # Two solid outriggers with real triangular through-openings.
    wing_outline=rounded_polygon([(.043,-.014),(.052,-.010),(.057,.004),(.057,.020),(.054,.035),
        (.047,.061),(.042,.074),(.025,.074),(.025,.063),(.031,.039),(.040,.013)],.0018,8)
    hole_outline=rounded_polygon([(.043,.030),(.047,.048),(.033,.061)],.0014,8)
    for side,label in [(-1,'Heel'),(1,'Toe')]:
        outline=[(side*x,z) for x,z in wing_outline]
        wing=extrusion(label+' turquoise wing',outline,0,.024,radius=0)
        hole=extrusion(label+' open wing window',[(side*x,z) for x,z in hole_outline],-.005,.032,radius=0)
        boolean(wing,hole)
        # Rear weights sit lower than the white crown, as in the side reference.
        for v in wing.data.vertices:
            p=C(v.co); f=max(0,min(1,(p.z+.014)/.088)); p.y*=1-.27*f; v.co=V(p)
        boolean(wing,tube(label+' screw seat',[(side*.0337,.0087,.0708),(side*.0337,.0087,.078)],[.00465,.00465],64))
        bevel(wing,.0008,4)
        finish(wing,aqua)
        profile=[(-.0023,.00415),(-.0018,.00445),(-.0004,.00445),(0,.00418),
            (0,.00375),(-.00016,.00360),(-.00016,.00340),(0,.00325),
            (0,.00288),(-.00013,.00272),(-.00013,.00252),(0,.00238),(0,.00150)]
        screw=lathe(label+' concentric rear weight screw',(side*.0337,.0087,.07365),(0,0,1),profile,64)
        hexagon=[(side*.0337+.00135*math.cos(t*math.tau/6),.0087+.00135*math.sin(t*math.tau/6)) for t in range(6)]
        boolean(screw,extrusion('Hex key recess',hexagon,.07285,.075,axis='z',radius=0))
        bevel(screw,.00007,2)
        finish(screw,steel)

    gasket=extrusion('Dark face perimeter',outer,-.01797,-.0151,axis='z',radius=0)
    bevel(gasket,.00020,3); finish(gasket,graphite)
    bezel_outline=[(x*.978,.014+(y-.014)*.955) for x,y in outer]
    bezel=extrusion('White insert surround',bezel_outline,-.0180,-.0161,axis='z',radius=0)
    insert_outline=rounded_polygon([(-.037,.0206),(-.032,.0230),(.032,.0230),(.037,.0206),(.031,.0052),(-.031,.0052)],.0024,8)
    boolean(bezel,extrusion('Insert opening',insert_outline,-.021,-.014,axis='z',radius=0))
    bevel(bezel,.00015,3); finish(bezel,white)
    face=extrusion('Grooved turquoise striking insert',insert_outline,-.01805,-.0154,axis='z',radius=0)
    for i in range(8):
        y=.0066+i*.00210
        cut=box('Horizontal milled channel',(0,y,-.01805),(.100,.00044,.00105),0)
        boolean(face,cut)
    bevel(face,.000085,2); finish(face,insert_mat)

    for i,z in enumerate([-.008,.001,.010],1):
        rim=tube('Alignment dot '+str(i)+' rim',[(0,.0274,z),(0,.02805,z)],[.00246,.00246],48)
        bevel(rim,.00008,2); finish(rim,steel)
        dot=tube('Alignment dot '+str(i),[(0,.02785,z),(0,.02809,z)],[.00210,.00210],48)
        bevel(dot,.00006,2); finish(dot,insert_mat)

    badge=extrusion('Inset graphite sole badge',badge_outline,.00195,.0038,radius=0)
    bevel(badge,.00025,3); finish(badge,graphite)
    panels=[ [(-.018,.001),(.018,.001),(.021,.016),(.012,.021),(-.012,.021),(-.021,.016)],
        [(-.010,.027),(.010,.027),(.018,.035),(.013,.040),(-.013,.040),(-.018,.035)] ]
    for i,outline in enumerate(panels,1):
        panel=extrusion('Turquoise sole inlay '+str(i),rounded_polygon(outline,.001,5),.00166,.0024,radius=0)
        bevel(panel,.00016,3); finish(panel,aqua)

    # Fit only the body components to the authored envelope. The common socket
    # coordinates and bore dimensions are independent of the body normalization.
    points=[C(v.co) for ob in PARTS for v in ob.data.vertices]
    lo=Vector([min(p[i] for p in points) for i in range(3)])
    hi=Vector([max(p[i] for p in points) for i in range(3)])
    target_lo=Vector((-.057,0,-.018)); target_size=Vector((.114,.028,.092))
    for ob in PARTS:
        for v in ob.data.vertices:
            p=C(v.co); v.co=V(tuple(target_lo[i]+(p[i]-lo[i])*target_size[i]/(hi[i]-lo[i]) for i in range(3)))
        loft_front(ob)
    body_points=[C(v.co) for ob in PARTS for v in ob.data.vertices]
    body_dims=[1000*(max(p[i] for p in body_points)-min(p[i] for p in body_points)) for i in range(3)]

    # A compact double-bend connection gives the photo's chrome shaft transition
    # while retaining the existing lower-shaft origin and 9.4 mm socket.
    base=tube('Pearl white shaft seat',[(-.041,.023,-.006),(-.041,.031,-.006)],[.0066,.0059],64)
    bevel(base,.00045,3); finish(base,white)
    end=SOCKET-AXIS*.007
    control=[Vector((-.041,.028,-.006)),Vector((-.041,.045,-.006)),end-AXIS*.014,end]
    curve=[cubic(*control,i/28) for i in range(29)]
    neck=tube('Bent stainless neck',curve,[.00535+(.00602-.00535)*i/28 for i in range(29)],64)
    sleeve=tube('Socket sleeve',[SOCKET-AXIS*.010,SOCKET+AXIS*.009],[.00608,.00585],64)
    boolean(neck,sleeve,'UNION')
    boolean(neck,tube('9.4 mm shaft bore',[SOCKET-AXIS*.0095,SOCKET+AXIS*.012],[.0047,.0047],64))
    bevel(neck,.00020,3); finish(neck,steel)

    part_reports=[]
    for ob in PARTS:
        cleanup(ob,repair=True); normal_finish(ob); st=stats(ob)
        assert st['nonmanifold_edges']==0,(ob.name,st)
        part_reports.append({'name':ob.name,**st})
    root=bpy.data.objects.new('Aqua_Fork_Mallet_Head',None); bpy.context.collection.objects.link(root)
    # One game mesh, five PBR material surfaces. Source keeps component provenance.
    bpy.ops.object.select_all(action='DESELECT')
    for ob in PARTS: ob.select_set(True)
    bpy.context.view_layer.objects.active=PARTS[0]; bpy.ops.object.join()
    mesh=bpy.context.object; mesh.name='putter_head_mesh'; mesh.data.name='aqua_fork_mallet_geometry'; mesh.parent=root
    mesh['assembly_components']=json.dumps([p['name'] for p in part_reports])
    root['units']='metres'; root['asset_type']='head_only'; root['body_dimensions_mm_xyz']=body_dims
    root['nominal_body_dimensions_mm_width_depth_height']=[114,92,28]
    root['bore_diameter_mm']=9.4; root['shaft_tip_diameter_mm']=9.2; root['face_loft_degrees']=3.5; root['lie_degrees']=71
    root['design']='white shield crown, turquoise open rear forks, grooved insert, three alignment dots, weight screws'
    marker('shaft_socket',SOCKET,root,True); marker('socket_mouth',SOCKET+AXIS*.009,root,True)
    marker('socket_bottom',SOCKET-AXIS*.0095,root,True)
    marker('face_center',(0,.014,-.018+(.014-.0046)*math.tan(LOFT)),root)
    bpy.context.scene.unit_settings.system='METRIC'; bpy.context.scene.unit_settings.scale_length=1
    export('aqua_fork_mallet_real_scale.glb')
    active(mesh); bpy.ops.wm.obj_export(filepath=str(PACK/'aqua_fork_mallet_real_scale.obj'),
        export_selected_objects=True,forward_axis='NEGATIVE_Z',up_axis='Y',export_materials=True,export_triangulated_mesh=True)
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(PACK/'source/Aqua_Fork_Mallet_Head.blend'))
    inverse=(Matrix.Translation(V(SOCKET))@Matrix.Rotation(math.radians(-19),4,'Y')).inverted()
    for ob in root.children:
        if ob.type=='MESH': ob.data.transform(inverse)
        else: ob.matrix_local=inverse@ob.matrix_local
    root['pivot']='shaft_socket'; root['local_positive_y']='toward grip along shaft'
    export('aqua_fork_mallet_shaft_attachment.glb')
    report={**stats(mesh),'body_dimensions_mm_xyz':body_dims,'nominal_body_dimensions_mm_width_depth_height':[114,92,28],
        'units':'metres','head_only':True,'shaft_origin_metres':list(SOCKET),'shaft_axis':list(AXIS),
        'bore_diameter_mm':9.4,'original_shaft_tip_diameter_mm':9.2,'lie_degrees':71,'face_loft_degrees':3.5,
        'materials':len(mesh.data.materials),'closed_assembly_parts':part_reports,'horizontal_face_grooves':8,
        'alignment_dots':3,'open_rear_forks':2,'texture_images':0}
    (PACK/'geometry_report.json').write_text(json.dumps(report,indent=2))
    print('AQUA MALLET COMPLETE',json.dumps(report),flush=True)


if __name__=='__main__': main()
