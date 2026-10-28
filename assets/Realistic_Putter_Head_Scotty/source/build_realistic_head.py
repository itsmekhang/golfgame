"""Head-only golf asset. Metres, Y up, face -Z on glTF export.
Reference-led original blade geometry, not a dimensioned manufacturer CAD copy.
Run with Blender 4.3's bpy/Python runtime.
"""
from pathlib import Path
import json,math
import bpy,bmesh
from mathutils import Vector,Matrix
from mesh_helpers import V,C,active,apply,material,obj_mesh,box,extrusion,tube,disc,join,bevel,smooth,triangulate_caps

PACK=Path(__file__).resolve().parents[1]
SHAFT_ORIGIN=Vector((-.041,.070,-.016))
SHAFT_AXIS=Vector((-math.sin(math.radians(19)),math.cos(math.radians(19)),0))
LOFT=math.radians(3.5)

def cleanup(ob):
    bm=bmesh.new();bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=2e-7)
    bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=1e-7)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bm.to_mesh(ob.data);bm.free();ob.data.update()

def final_cleanup(ob):
    bm=bmesh.new();bm.from_mesh(ob.data)
    for tolerance in [.000005,.000007,.000010,.000015,.000020]:
        bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=tolerance)
        bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=tolerance*.1)
        loose=[e for e in bm.edges if not e.link_faces]
        if loose:bmesh.ops.delete(bm,geom=loose,context='EDGES')
        if all(e.is_manifold for e in bm.edges):break
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(ob.data);bm.free();ob.data.update()

def boolean(ob,cutter,op='DIFFERENCE'):
    active(ob);m=ob.modifiers.new('Physical '+op,'BOOLEAN');m.operation=op;m.solver='EXACT';m.object=cutter
    bpy.ops.object.modifier_apply(modifier=m.name);bpy.data.objects.remove(cutter,do_unlink=True);cleanup(ob)

def rounded_outline(xlo,xhi,zlo,zhi,r,segments=8):
    pts=[]
    for x,z,a0 in [(xhi-r,zhi-r,0),(xlo+r,zhi-r,90),(xlo+r,zlo+r,180),(xhi-r,zlo+r,270)]:
        for j in range(segments+1):
            a=math.radians(a0+90*j/segments);pts.append((x+math.cos(a)*r,z+math.sin(a)*r))
    return pts

def smooth_interp(value,keys):
    if value<=keys[0][0]:return keys[0][1]
    for (a,v),(b,w) in zip(keys,keys[1:]):
        if value<=b:
            t=(value-a)/(b-a);t=t*t*(3-2*t);return v+(w-v)*t
    return keys[-1][1]

def weight_shoulder(sign):
    # Curved ramps descend from the tall face into the low rear flange.
    nx=20;nz=30;verts=[]
    for j in range(nz+1):
        z=-.009+j/nz*.030
        outer=.0562 if z<=.016 else .0502+math.sqrt(max(0,.006**2-(z-.016)**2))
        t=max(0,min(1,(z+.006)/.027))
        height=.0065+.021*(1-t)**2.35
        for i in range(nx+1):
            u=i/nx;x=.023+(outer-.023)*u
            t_x=max(0,min(1,(x-.023)/.0085));edge=t_x*t_x*(3-2*t_x)
            edge*=1-.055*max(0,(x-.048)/.009)**2
            y=.0042+(height-.0042)*edge
            verts.append((sign*x,y,z))
    top_count=len(verts);verts.extend([(x,.0025,z) for x,y,z in list(verts)])
    faces=[]
    for j in range(nz):
        for i in range(nx):
            a=j*(nx+1)+i;b=a+1;c=b+nx+1;d=a+nx+1
            faces.extend([(a,b,c,d),(top_count+d,top_count+c,top_count+b,top_count+a)])
    boundary=list(range(nx+1))+[j*(nx+1)+nx for j in range(1,nz+1)]+[nz*(nx+1)+i for i in range(nx-1,-1,-1)]+[j*(nx+1) for j in range(nz-1,0,-1)]
    for a,b in zip(boundary,boundary[1:]+boundary[:1]):faces.append((a,top_count+a,top_count+b,b))
    return obj_mesh('Sculpted heel' if sign<0 else 'Sculpted toe',verts,faces)

def squared_neck():
    pts=[Vector(p) for p in [(-.043,.025,-.005),(-.041,.032,-.005),(-.035,.044,-.007),(-.035,.048,-.016),(-.037,.061,-.016)]]
    verts=[];outline=rounded_outline(-.0052,.0052,-.0051,.0051,.0010,4);n=len(outline)
    for i,p in enumerate(pts):
        tangent=(pts[min(i+1,len(pts)-1)]-pts[max(0,i-1)]).normalized()
        a=Vector((1,0,0));a=(a-tangent*a.dot(tangent)).normalized();b=tangent.cross(a).normalized()
        verts.extend([tuple(p+a*x+b*z) for x,z in outline])
    faces=[tuple(reversed(range(n))),tuple((len(pts)-1)*n+i for i in range(n))]
    for j in range(len(pts)-1):
        for i in range(n):faces.append((j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i))
    return obj_mesh('Offset plumber neck',verts,faces)

def marker(name,location,parent,shaft_frame=False):
    o=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(o);o.parent=parent;o.location=V(location);o.empty_display_type='ARROWS';o.empty_display_size=.012
    if shaft_frame:o.rotation_euler=(0,math.radians(-19),0)
    if name=='face_center':o.rotation_euler.x=LOFT
    return o

def export(path):
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_yup=True,export_animations=False,export_extras=True,export_normals=True,export_tangents=False,export_texcoords=True,export_materials='EXPORT')

def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    steel=material('Brushed stainless steel',(.30,.33,.34),.96,.40)
    pocketmat=material('Recessed machined steel',(.23,.27,.28),.95,.40)
    sightmat=material('Engraved alignment fill',(.015,.019,.020),.1,.46)
    sole=extrusion('Rounded sole',rounded_outline(-.057,.057,-.018,.022,.006,10),0,.0046,radius=0)
    face=box('Lofted striking face',(0,.014,-.012),(.114,.028,.012),0)
    # Face loft is actual geometry: the upper leading edge recedes 1.71 mm.
    face_world=face.matrix_world.copy();face_inverse=face_world.inverted()
    for v in face.data.vertices:
        p=C(face_world@v.co);p.z+=max(0,(-.006-p.z)/.012)*p.y*math.tan(LOFT);v.co=face_inverse@V(p)
    boolean(sole,face,'UNION')
    for sign in [-1,1]:boolean(sole,weight_shoulder(sign),'UNION')
    bevel(sole,.00105,4);cleanup(sole)
    body_bounds=[C(sole.matrix_world@v.co) for v in sole.data.vertices]
    body_size=[round((max(p[i] for p in body_bounds)-min(p[i] for p in body_bounds))*1000,3) for i in range(3)]
    boolean(sole,squared_neck(),'UNION')
    collar=tube('Hosel collar',[SHAFT_ORIGIN-SHAFT_AXIS*.0115,SHAFT_ORIGIN+SHAFT_AXIS*.009],[.00615,.00585],64)
    boolean(sole,collar,'UNION')
    # A real socket bore accommodates the original shaft's 9.2 mm tip.
    bore=tube('9.4 mm socket bore',[SHAFT_ORIGIN-SHAFT_AXIS*.0095,SHAFT_ORIGIN+SHAFT_AXIS*.012],[.00470,.00470],64)
    boolean(sole,bore)
    bevel(sole,.00032,3);cleanup(sole)
    # Three shallow counterbored medallions are cut into the cavity wall.
    for xp in [-.0145,0,.0145]:
        cutter=disc('Outer medallion counterbore',(xp,.0175,-.00612),.0059,.0009,'z',sides=64);boolean(sole,cutter)
        cutter=disc('Inner medallion pocket',(xp,.0175,-.0066),.0048,.00135,'z',sides=64);boolean(sole,cutter)
    groove=box('Engraved sightline cutter',(0,.0046,.009),(.0008,.0010,.017),.00018,2);boolean(sole,groove)
    bevel(sole,.00012,2);cleanup(sole)
    # Machine-flat face, subtle horizontal milling built into the mesh.
    groove_parts=[]
    for i in range(21):
        y=.0060+i*.00086;z=-.018+y*math.tan(LOFT)
        groove_parts.append(box('Face micro milling',(0,y,z+.000025),(.099,.00009,.00018),0))
    cutters=join(groove_parts,'Milled face cutter');boolean(sole,cutters)
    cleanup(sole);sole.name='putter_head_mesh';sole.data.name='realistic_blade_head_geometry'
    sole.data.materials.append(steel);sole.data.materials.append(pocketmat)
    for p in sole.data.polygons:
        center=C(p.center)
        if center.z<-.00645 and center.z>-.0074 and any((center.x-x)**2+(center.y-.0175)**2<.00485**2 for x in [-.0145,0,.0145]):p.material_index=1
    smooth(sole);active(sole);wn=sole.modifiers.new('Final surface normals','WEIGHTED_NORMAL');wn.keep_sharp=True;wn.weight=70;bpy.ops.object.modifier_apply(modifier=wn.name)
    stripe=box('Recessed sightline',(0,.00417,.009),(.00057,.00015,.0166),.00006,2);stripe.data.materials.append(sightmat)
    head=join([sole,stripe],'putter_head_mesh');triangulate_caps(head);final_cleanup(head)
    active(head);wn=head.modifiers.new('Export weighted normals','WEIGHTED_NORMAL');wn.keep_sharp=True;wn.weight=70;bpy.ops.object.modifier_apply(modifier=wn.name)
    # Keep machined planes exactly flat while retaining smooth shoulder fillets.
    normals=[tuple(n.vector) for n in head.data.corner_normals]
    flat_directions=[V((0,math.sin(LOFT),-math.cos(LOFT))),V((0,0,1)),V((0,1,0)),V((0,-1,0)),V((1,0,0)),V((-1,0,0))]
    for p in head.data.polygons:
        matching=next((n for n in flat_directions if p.normal.dot(n)>.99999),None)
        if matching is not None:
            for li in p.loop_indices:normals[li]=tuple(matching)
    head.data.normals_split_custom_set(normals)
    head.data.name='realistic_blade_head_geometry';head.data.calc_loop_triangles()
    root=bpy.data.objects.new('Realistic_Putter_Head',None);bpy.context.collection.objects.link(root);head.parent=root
    root['units']='metres';root['asset_type']='head_only';root['head_body_dimensions_mm']=body_size;root['shaft_tip_diameter_mm']=9.2;root['hosel_bore_diameter_mm']=9.4;root['face_loft_degrees']=3.5;root['lie_degrees']=71.0
    marker('shaft_socket',SHAFT_ORIGIN,root,True)
    marker('socket_mouth',SHAFT_ORIGIN+SHAFT_AXIS*.009,root,True)
    marker('socket_bottom',SHAFT_ORIGIN-SHAFT_AXIS*.0095,root,True)
    fc=Vector((0,.014,-.018+.014*math.tan(LOFT)))
    marker('face_center',fc,root)
    bpy.context.scene.unit_settings.system='METRIC';bpy.context.scene.unit_settings.scale_length=1
    export(PACK/'putter_head_real_scale.glb')
    # Raw mesh option for MeshInstance3D; no shaft, grip, light, plane or camera.
    active(head)
    bpy.ops.wm.obj_export(filepath=str(PACK/'putter_head_real_scale.obj'),export_selected_objects=True,forward_axis='NEGATIVE_Z',up_axis='Y',export_materials=True,export_triangulated_mesh=True)
    bpy.ops.file.pack_all();bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(PACK/'source/Realistic_Putter_Head.blend'))
    # Socket-origin version: +Y is the shaft axis; origin matches the existing shaft tip.
    attach=Matrix.Translation(V(SHAFT_ORIGIN))@Matrix.Rotation(math.radians(-19),4,'Y')
    inv=attach.inverted()
    for ob in list(root.children):
        if ob.type=='MESH':ob.data.transform(inv)
        else:ob.matrix_local=inv@ob.matrix_local
    root['pivot']='shaft_socket';root['local_positive_y']='toward grip along shaft';root['orientation_note']='position and rotate this root to the shaft tip, keeping scale at 1'
    export(PACK/'putter_head_shaft_attachment.glb')
    bm=bmesh.new();bm.from_mesh(head.data);bad=sum(not e.is_manifold for e in bm.edges);components=0;todo=set(bm.verts)
    while todo:
        components+=1;stack=[todo.pop()]
        while stack:
            v=stack.pop()
            for e in v.link_edges:
                w=e.other_vert(v)
                if w in todo:todo.remove(w);stack.append(w)
    bm.free()
    report={'body_dimensions_mm_xyz':body_size,'units':'metres','triangle_count':len(head.data.loop_triangles),'mesh_vertex_count':len(head.data.vertices),'nonmanifold_edges':bad,'connected_components_including_recessed_sightline':components,'shaft_origin_metres':list(SHAFT_ORIGIN),'shaft_axis':list(SHAFT_AXIS),'socket_bore_diameter_mm':9.4,'original_shaft_tip_diameter_mm':9.2,'face_loft_degrees':3.5,'lie_degrees':71,'head_only':True}
    (PACK/'geometry_report.json').write_text(json.dumps(report,indent=2));print('HEAD BUILT',json.dumps(report),flush=True)
    assert bad==0,report
    assert components==2,report

if __name__=='__main__':main()
