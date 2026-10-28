from pathlib import Path
import bpy, math
from mathutils import Vector
def V(p):return Vector((p[0],-p[2],p[1]))
def C(p):return Vector((p[0],p[2],-p[1]))
def active(obj):
    bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
def apply(obj):
    active(obj);bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
def material(name,color,metal=.0,rough=.5,emission=0):
    m=bpy.data.materials.new(name);m.use_nodes=True;m.use_backface_culling=True;p=m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value=(*color,1);p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough
    if emission:p.inputs['Emission Color'].default_value=(*color,1);p.inputs['Emission Strength'].default_value=emission
    return m
def load_image(path,linear=False):
    im=bpy.data.images.load(str(path),check_existing=True)
    if linear:im.colorspace_settings.name='Non-Color'
    return im
def head_material(c):
    id=c['id'];m=material('ofg_'+id+'__head',(1,1,1),1,.4);n=m.node_tree.nodes;l=m.node_tree.links;p=n.get('Principled BSDF')
    for key in ['albedo','orm','normal']:
        t=n.new('ShaderNodeTexImage');t.image=load_image(TEX/id/f'ofg_{id}_{key}.png',key!='albedo');t.label=key;t.location=(-550, {'albedo':350,'orm':0,'normal':-350}[key])
        if key=='albedo':l.new(t.outputs['Color'],p.inputs['Base Color'])
        elif key=='orm':
            sep=n.new('ShaderNodeSeparateColor');sep.mode='RGB';sep.location=(-300,0);l.new(t.outputs['Color'],sep.inputs[0]);l.new(sep.outputs[1],p.inputs['Roughness']);l.new(sep.outputs[2],p.inputs['Metallic'])
            group=bpy.data.node_groups.get('glTF Material Output')
            if not group:
                group=bpy.data.node_groups.new('glTF Material Output','ShaderNodeTree');group.interface.new_socket(name='Occlusion',in_out='INPUT',socket_type='NodeSocketFloat')
            gn=n.new('ShaderNodeGroup');gn.node_tree=group;l.new(sep.outputs[0],gn.inputs['Occlusion'])
        else:
            norm=n.new('ShaderNodeNormalMap');norm.inputs['Strength'].default_value=.42;norm.location=(-200,-350);l.new(t.outputs['Color'],norm.inputs['Color']);l.new(norm.outputs[0],p.inputs['Normal'])
    m['asset_id']=id;m['condition_driven']=True
    return m
def image_mat(name,path,color=(1,1,1),rough=.5,normal=None):
    m=material(name,color,0,rough);n=m.node_tree.nodes;p=n.get('Principled BSDF');l=m.node_tree.links
    t=n.new('ShaderNodeTexImage');t.image=load_image(path);l.new(t.outputs['Color'],p.inputs['Base Color'])
    if normal:
        t=n.new('ShaderNodeTexImage');t.image=load_image(normal,True);nn=n.new('ShaderNodeNormalMap');nn.inputs['Strength'].default_value=.4;l.new(t.outputs['Color'],nn.inputs['Color']);l.new(nn.outputs[0],p.inputs['Normal'])
    return m
def obj_mesh(name,verts,faces):
    me=bpy.data.meshes.new(name+'__geometry');me.from_pydata([V(v) for v in verts],[],faces);me.update()
    ob=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(ob)
    # Recalculate outward normals without changing topology.
    import bmesh
    bm=bmesh.new();bm.from_mesh(me);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free()
    return ob
def smooth(obj):
    for p in obj.data.polygons:p.use_smooth=True
def triangulate_caps(obj):
    if any(len(p.vertices)>4 for p in obj.data.polygons):
        active(obj);mod=obj.modifiers.new('Export polygon caps','TRIANGULATE');mod.min_vertices=5;mod.keep_custom_normals=True
        bpy.ops.object.modifier_apply(modifier=mod.name)
def bevel(obj,width=.001,segments=2):
    active(obj);b=obj.modifiers.new('Machined edge radii','BEVEL');b.width=width;b.segments=segments;b.limit_method='ANGLE';b.angle_limit=.5
    bpy.ops.object.modifier_apply(modifier=b.name);smooth(obj)
    mod=obj.modifiers.new('Weighted face normals','WEIGHTED_NORMAL');mod.keep_sharp=True;mod.weight=50
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj
def box(name,center,dims,bevel_width=.001,segments=2):
    bpy.ops.mesh.primitive_cube_add(size=1,location=V(center));o=bpy.context.object;o.name=name;o.dimensions=(dims[0],dims[2],dims[1]);apply(o)
    if bevel_width:bevel(o,bevel_width,segments)
    return o
def extrusion(name,outline,bottom,top,axis='y',radius=.001,segments=2):
    if axis=='y':verts=[(a,bottom,b) for a,b in outline]+[(a,top,b) for a,b in outline]
    else:verts=[(a,b,b*.0+bottom) for a,b in outline]+[(a,b,top) for a,b in outline]
    N=len(outline);faces=[tuple(reversed(range(N))),tuple(range(N,2*N))]+[(i,(i+1)%N,(i+1)%N+N,i+N) for i in range(N)]
    return bevel(obj_mesh(name,verts,faces),radius,segments) if radius else obj_mesh(name,verts,faces)
def tube(name,points,radii,sides=16,caps=True):
    verts=[];pts=[Vector(p) for p in points]
    for i,p in enumerate(pts):
        direction=(pts[min(i+1,len(pts)-1)]-pts[max(0,i-1)]).normalized()
        helper=Vector((0,0,1)) if abs(direction.z)<.9 else Vector((1,0,0))
        a=direction.cross(helper).normalized();b=direction.cross(a).normalized()
        for j in range(sides):verts.append(p+(a*math.cos(j*math.tau/sides)+b*math.sin(j*math.tau/sides))*radii[i])
    faces=[]
    for i in range(len(points)-1):
        for j in range(sides):faces.append((i*sides+j,i*sides+(j+1)%sides,(i+1)*sides+(j+1)%sides,(i+1)*sides+j))
    if caps:faces+=[tuple(reversed(range(sides))),tuple((len(points)-1)*sides+j for j in range(sides))]
    ob=obj_mesh(name,verts,faces);smooth(ob)
    uv=ob.data.uv_layers.new(name='UVMap')
    for poly in ob.data.polygons:
        for li in poly.loop_indices:
            vi=ob.data.loops[li].vertex_index;ring=vi//sides;j=vi%sides
            # Duplicate seam UVs per corner, keeping the mesh topology compact.
            indices=[ob.data.loops[k].vertex_index%sides for k in poly.loop_indices]
            u=j/sides
            if 0 in indices and sides-1 in indices and j==0:u=1
            uv.data[li].uv=(u,ring/(len(points)-1))
    triangulate_caps(ob)
    return ob
def disc(name,center,radius,depth,axis='z',mat=None,sides=24):
    a=Vector(center);b=Vector(center);idx={'x':0,'y':1,'z':2}[axis];a[idx]-=depth/2;b[idx]+=depth/2
    o=tube(name,[a,b],[radius,radius],sides)
    if mat:o.data.materials.append(mat)
    return o
def join(parts,name):
    bpy.ops.object.select_all(action='DESELECT')
    for p in parts:p.select_set(True)
    bpy.context.view_layer.objects.active=parts[0];bpy.ops.object.join();ob=parts[0];ob.name=name
    active(ob);bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    return ob
def atlas_uv(ob):
    uv=ob.data.uv_layers.active or ob.data.uv_layers.new(name='UVMap')
    coords=[C(v.co) for v in ob.data.vertices]
    low=Vector(tuple(min(v[i] for v in coords) for i in range(3)));high=Vector(tuple(max(v[i] for v in coords) for i in range(3)))
    for p in ob.data.polygons:
        n=C(p.normal)
        center=sum((coords[vi] for vi in p.vertices),Vector())/len(p.vertices)
        q=1 if n.z<-.45 else (0 if n.y>.45 else (2 if n.y<-.55 else 3))
        for li in p.loop_indices:
            co=coords[ob.data.loops[li].vertex_index]
            u=(co.x-low.x)/max(.001,high.x-low.x)
            if q in [0,2]:v=1-(co.z-low.z)/max(.001,high.z-low.z)
            else:v=(co.y-low.y)/max(.001,high.y-low.y)
            ox=.5*(q%2);oy=.5 if q<2 else 0
            if center.x < -.033 and center.y > .042:
                uv.data[li].uv=(.948+.029*u,.035+.053*v)
            else:
                uv.data[li].uv=(ox+.018+.464*u,oy+.018+.464*v)
