"""Simple, head-only putter mesh. Run in Blender 4.3-compatible bpy Python.
Design coordinates are metres, +Y up, face toward -Z.
"""
from pathlib import Path
import math,json
import bpy,bmesh
from mathutils import Vector,Matrix
from mesh_helpers import V,C,active,apply,material,obj_mesh,box,extrusion,tube,bevel,smooth,triangulate_caps

PACK=Path(__file__).resolve().parents[1]
SOCKET=Vector((-.041,.070,-.016))
AXIS=Vector((-math.sin(math.radians(19)),math.cos(math.radians(19)),0))
LOFT=math.radians(3.5)

def cleanup(ob,final=False):
    bm=bmesh.new();bm.from_mesh(ob.data)
    for tolerance in ([2e-7,1e-6,3e-6,7e-6,1.5e-5] if final else [2e-7]):
        bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=tolerance)
        bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=tolerance*.1)
        loose=[e for e in bm.edges if not e.link_faces]
        if loose:bmesh.ops.delete(bm,geom=loose,context='EDGES')
        if all(e.is_manifold for e in bm.edges):break
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(ob.data);bm.free();ob.data.update()

def boolean(head,cutter,operation):
    active(head);m=head.modifiers.new(operation,'BOOLEAN');m.solver='EXACT';m.operation=operation;m.object=cutter
    bpy.ops.object.modifier_apply(modifier=m.name);bpy.data.objects.remove(cutter,do_unlink=True);cleanup(head)

def rounded_outline(xlo,xhi,ylo,yhi,radius,segments=8):
    result=[]
    for x,y,start in [(xhi-radius,yhi-radius,0),(xlo+radius,yhi-radius,90),(xlo+radius,ylo+radius,180),(xhi-radius,ylo+radius,270)]:
        for i in range(segments+1):
            a=math.radians(start+i*90/segments);result.append((x+radius*math.cos(a),y+radius*math.sin(a)))
    return result

def marker(name,position,root,shaft=False):
    ob=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(ob);ob.parent=root;ob.location=V(position);ob.empty_display_type='ARROWS';ob.empty_display_size=.012
    if shaft:ob.rotation_euler=(0,math.radians(-19),0)
    if name=='face_center':ob.rotation_euler.x=LOFT
    return ob

def export(name):
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=str(PACK/name),export_format='GLB',use_selection=True,export_yup=True,export_animations=False,export_extras=True,export_normals=True,export_tangents=False,export_texcoords=False,export_materials='EXPORT')

def mesh_stats(head):
    head.data.calc_loop_triangles();bm=bmesh.new();bm.from_mesh(head.data)
    bad=sum(not e.is_manifold for e in bm.edges);todo=set(bm.verts);components=0
    while todo:
        components+=1;stack=[todo.pop()]
        while stack:
            v=stack.pop()
            for e in v.link_edges:
                other=e.other_vert(v)
                if other in todo:todo.remove(other);stack.append(other)
    bm.free()
    return dict(vertices=len(head.data.vertices),triangles=len(head.data.loop_triangles),nonmanifold_edges=bad,connected_components=components)

def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    steel=material('Simple brushed steel',(.30,.33,.34),.92,.46)
    head=extrusion('Rounded blade blank',rounded_outline(-.057,.057,-.018,.022,.006,8),0,.028,radius=0)
    # Rounded face silhouette gives soft heel/toe ends at the same exact bounds.
    silhouette=extrusion('Rounded face profile',rounded_outline(-.057,.057,0,.028,.004,8),-.050,.060,axis='z',radius=0)
    boolean(head,silhouette,'INTERSECT')
    # A single planar slope creates the broad, simple rear shoulders.
    normal=Vector((0,1,12/28)).normalized();cut_origin=Vector((0,.028,-.006))
    cut=box('Rear shoulder plane',cut_origin+normal*.070,(.250,.140,.250),0)
    cut.rotation_mode='QUATERNION';cut.rotation_quaternion=V(normal).to_track_quat('Z','Y');apply(cut)
    boolean(head,cut,'DIFFERENCE')
    # One open cavity, rounded where its walls meet the thick sole.
    cavity=box('Open rear cavity',(0,.0375,.018),(.066,.064,.048),.0030,6)
    boolean(head,cavity,'DIFFERENCE')
    # Retain the full sole depth; the plain face above it has the same 3.5° loft.
    bm=bmesh.new();bm.from_mesh(head.data)
    bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=1e-7,plane_co=V((0,.0046,0)),plane_no=V((0,1,0)),clear_inner=False,clear_outer=False)
    bm.to_mesh(head.data);bm.free()
    for vertex in head.data.vertices:
        p=C(vertex.co);front_weight=max(0,min(1,(-.006-p.z)/.012))
        p.z+=front_weight*max(0,p.y-.0046)*math.tan(LOFT);vertex.co=V(p)
    bevel(head,.0010,3);cleanup(head,True)
    points=[C(v.co) for v in head.data.vertices]
    body_dims=[round(1000*(max(p[i] for p in points)-min(p[i] for p in points)),4) for i in range(3)]
    assert max(abs(a-b) for a,b in zip(body_dims,[114,28,40]))<.01,body_dims
    # Straight plumber neck and short top offset retain the existing socket pose.
    upright=box('Straight plumber neck',(-.036,.043,-.003),(.0085,.036,.0090),.0006,3)
    boolean(head,upright,'UNION')
    offset=box('Simple top offset',(-.0365,.059,-.010),(.010,.009,.020),.0007,3)
    boolean(head,offset,'UNION')
    collar=tube('Hosel collar',[SOCKET-AXIS*.0115,SOCKET+AXIS*.009],[.00615,.00585],48)
    boolean(head,collar,'UNION')
    bore=tube('Shaft socket',[SOCKET-AXIS*.0095,SOCKET+AXIS*.012],[.0047,.0047],48)
    boolean(head,bore,'DIFFERENCE')
    bevel(head,.00030,2);triangulate_caps(head);cleanup(head,True)
    head.name='putter_head_mesh';head.data.name='simple_blade_head_geometry';head.data.materials.clear();head.data.materials.append(steel)
    smooth(head)
    head.data.normals_split_custom_set([(0,0,0)]*len(head.data.loops))
    normals=[tuple(n.vector) for n in head.data.corner_normals]
    directions=[V((0,math.sin(LOFT),-math.cos(LOFT))),V(normal)]+[V(p) for p in [(1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)]]
    for poly in head.data.polygons:
        match=next((n for n in directions if poly.normal.dot(n)>.99999),None)
        if match is not None:
            for li in poly.loop_indices:normals[li]=tuple(match)
    head.data.normals_split_custom_set(normals)
    stats=mesh_stats(head);assert stats['nonmanifold_edges']==0,stats;assert stats['connected_components']==1,stats
    root=bpy.data.objects.new('Simple_Putter_Head',None);bpy.context.collection.objects.link(root);head.parent=root
    root['units']='metres';root['asset_type']='head_only';root['body_dimensions_mm_xyz']=body_dims;root['bore_diameter_mm']=9.4;root['shaft_tip_diameter_mm']=9.2;root['face_loft_degrees']=3.5;root['lie_degrees']=71
    root['design']='plain face, open cavity, straight plumber neck'
    marker('shaft_socket',SOCKET,root,True);marker('socket_mouth',SOCKET+AXIS*.009,root,True);marker('socket_bottom',SOCKET-AXIS*.0095,root,True)
    marker('face_center',(0,.014,-.018+(.014-.0046)*math.tan(LOFT)),root)
    bpy.context.scene.unit_settings.system='METRIC';bpy.context.scene.unit_settings.scale_length=1
    export('simple_putter_head_real_scale.glb')
    active(head);bpy.ops.wm.obj_export(filepath=str(PACK/'simple_putter_head_real_scale.obj'),export_selected_objects=True,forward_axis='NEGATIVE_Z',up_axis='Y',export_materials=True,export_triangulated_mesh=True)
    bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(PACK/'source/Simple_Putter_Head.blend'))
    attachment=Matrix.Translation(V(SOCKET))@Matrix.Rotation(math.radians(-19),4,'Y');inverse=attachment.inverted()
    for ob in list(root.children):
        if ob.type=='MESH':ob.data.transform(inverse)
        else:ob.matrix_local=inverse@ob.matrix_local
    root['pivot']='shaft_socket';root['local_positive_y']='toward grip along shaft';export('simple_putter_head_shaft_attachment.glb')
    report=dict(stats,body_dimensions_mm_xyz=body_dims,units='metres',shaft_origin_metres=list(SOCKET),shaft_axis=list(AXIS),bore_diameter_mm=9.4,original_shaft_tip_diameter_mm=9.2,face_loft_degrees=3.5,lie_degrees=71,head_only=True,materials=1)
    (PACK/'geometry_report.json').write_text(json.dumps(report,indent=2));print('SIMPLE HEAD COMPLETE',json.dumps(report),flush=True)

if __name__=='__main__':main()
