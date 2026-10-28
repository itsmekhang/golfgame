"""Shared parametric mesh operations, derived from the existing D1 authoring tools.
The D2 design parameters and component construction live in build_carbon_driver.py.
"""
import bpy, bmesh, math, json, sys
import numpy as np
from pathlib import Path
from mathutils import Vector, Matrix
sys.path.insert(0,str(Path(__file__).resolve().parent))
from mesh_helpers import V, C, active, material, obj_mesh, tube, smooth, triangulate_caps
PACK=Path(__file__).resolve().parents[1]
SOCKET=Vector((-.0546,.074,-.013));TILT=29.0
AXIS=Vector((-math.sin(math.radians(TILT)),math.cos(math.radians(TILT)),0))
LOFT=math.radians(10.5)
PARTS=[];MATS=[];BODY=None
CENTER=Vector((.001,.015));APEX=Vector((.002,.002));APEX_Y=.059
EQ=.0175;SOLE_R=.011;SOLE_CAMBER=.0042;SOLE_POLE=Vector((.001,-.006))


def cubic(a,b,c,d,t):
    return Vector(a)*(1-t)**3+Vector(b)*3*t*(1-t)**2+Vector(c)*3*t*t*(1-t)+Vector(d)*t**3

def smoothstep(t):
    t=max(0,min(1,t));return t*t*(3-2*t)

def bearing(p):
    v=p-CENTER
    return smoothstep(math.atan2(abs(v.x),-v.y)/math.pi)

def crown(p,t):
    w=bearing(p); k1=.60+(.23-.60)*w; k2=.61+(.40-.61)*w
    u=1-t; g=u**3+3*t*u*u+3*t*t*u*k2; h=3*t*u*u*k1+3*t*t*u+t**3
    q=CENTER+(APEX-CENTER)*h+(p-CENTER)*g
    return Vector((q.x,EQ+(APEX_Y-EQ)*h,q.y))

def face_z(x,y):
    return -.0396+y*math.tan(LOFT)+x*x/(2*.31)+(y-.029)**2/(2*.28)

def face_normal(x,y):
    return Vector((x/.31, math.tan(LOFT)+(y-.029)/.28, -1)).normalized()

def cleanup(ob):
    bm=bmesh.new();bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=8e-8)
    bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=1e-8)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    for edge in bm.edges:
        edge.smooth = edge.is_manifold and edge.calc_face_angle(0) < .60
    bm.to_mesh(ob.data);bm.free();ob.data.update()

def boolean(ob, cutter, operation='DIFFERENCE'):
    active(ob);m=ob.modifiers.new(operation+' '+cutter.name,'BOOLEAN')
    m.operation=operation;m.solver='EXACT';m.object=cutter
    bpy.ops.object.modifier_apply(modifier=m.name)
    bpy.data.objects.remove(cutter,do_unlink=True);cleanup(ob)

def bevel(ob,width=.001,segments=4,angle=.48):
    active(ob);m=ob.modifiers.new('Manufactured edge radii','BEVEL')
    m.width=width;m.segments=segments;m.limit_method='ANGLE';m.angle_limit=angle
    bpy.ops.object.modifier_apply(modifier=m.name);cleanup(ob);smooth(ob)

def setmat(ob, mat):
    ob.data.materials.clear();ob.data.materials.append(mat)
    for p in ob.data.polygons:p.material_index=0
    return ob

def finish(ob,mat=None):
    active(ob);bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    if mat:setmat(ob,mat)
    cleanup(ob);triangulate_caps(ob);smooth(ob);PARTS.append(ob)
    return ob

def stats(ob):
    ob.data.calc_loop_triangles();bm=bmesh.new();bm.from_mesh(ob.data)
    bad=sum(not e.is_manifold for e in bm.edges); boundary=sum(e.is_boundary for e in bm.edges)
    remain=set(bm.verts);components=0
    while remain:
        components+=1;queue=[remain.pop()]
        while queue:
            v=queue.pop()
            for e in v.link_edges:
                other=e.other_vert(v)
                if other in remain:remain.remove(other);queue.append(other)
    volume=abs(bm.calc_volume(signed=True))*1e6
    bm.free()
    return {'vertices':len(ob.data.vertices),'triangles':len(ob.data.loop_triangles),
            'nonmanifold_edges':bad,'boundary_edges':boundary,'closed_components':components,'volume_cc':volume}

def generated_image(name, arr, path, noncolor=False):
    h,w=arr.shape[:2]; im=bpy.data.images.new(name,width=w,height=h,alpha=True)
    if noncolor:im.colorspace_settings.name='Non-Color'
    im.pixels.foreach_set(arr.astype(np.float32).ravel());im.filepath_raw=str(path);im.file_format='PNG'
    im.save();im.pack();return im

def curved_face_cutter():
    nx,ny=64,48;verts=[];faces=[]
    for yj in range(ny+1):
        y=-.02+.12*yj/ny
        for xi in range(nx+1):
            x=-.095+.19*xi/nx;verts.append((x,y,face_z(x,y)))
    count=len(verts)
    verts += [(x,y,-.15) for x,y,z in verts]
    for j in range(ny):
        for i in range(nx):
            a=j*(nx+1)+i;b=a+1;c=b+nx+1;d=a+nx+1
            faces.extend([(a,b,c,d),(a+count,d+count,c+count,b+count)])
    edge=list(range(nx+1))+[j*(nx+1)+nx for j in range(1,ny+1)]+[ny*(nx+1)+i for i in range(nx-1,-1,-1)]+[j*(nx+1) for j in range(ny-1,0,-1)]
    for a,b in zip(edge,edge[1:]+edge[:1]):faces.append((a,a+count,b+count,b))
    ob=obj_mesh('Bulge and roll face die',verts,faces);setmat(ob,MATS[2]);return ob

def round_rect(x0,x1,y0,y1,r,steps=6):
    result=[]
    for x,y,st in [(x1-r,y1-r,0),(x0+r,y1-r,90),(x0+r,y0+r,180),(x1-r,y0+r,270)]:
        for j in range(steps+1):
            a=math.radians(st+90*j/steps);result.append((x+r*math.cos(a),y+r*math.sin(a)))
    return result

def slot_cut(x0,x1,y):
    poly=round_rect(x0,x1,y-.00020,y+.00020,.00018)
    # Extra vertices keep the long groove floor conformal to face bulge.
    points=[]
    for a,b in zip(poly,poly[1:]+poly[:1]):
        steps=max(1,int(math.dist(a,b)/.0025))
        for j in range(steps):
            t=j/steps;points.append((a[0]*(1-t)+b[0]*t,a[1]*(1-t)+b[1]*t))
    vs=[(x,yy,face_z(x,yy)+d) for d in [-.003,.00023] for x,yy in points]
    n=len(points);fs=[tuple(reversed(range(n))),tuple(range(n,2*n))]
    fs += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    ob=obj_mesh('Recessed curved scoreline',vs,fs);setmat(ob,MATS[7]);return ob

def head_hosel():
    heights=[.024,.032,.040,.046,.050,.055,.061,.068,.074,.076]
    radii=[.014,.014,.013,.0118,.0104,.0086,.0076,.0070,.0066,.0065]
    pts=[SOCKET+AXIS*((y-SOCKET.y)/AXIS.y) for y in heights]
    ob=tube('Flowing heel hosel',pts,radii,64);setmat(ob,MATS[0]);return ob

def material_and_normals(head, slots):
    me=head.data;me.update()
    for p in me.polygons:
        c=C(p.center);d=c.z-face_z(c.x,c.y);n=C(p.normal)
        if abs(d)<.000055 and n.dot(face_normal(c.x,c.y))>.985:p.material_index=2
        elif -.00002<d<.00034 and any(x0-.0001<c.x<x1+.0001 and abs(c.y-y)<.00025 for x0,x1,y in slots):p.material_index=7
    smooth(head)
    me.normals_split_custom_set([(0,0,0)]*len(me.loops))
    normals=[tuple(n.vector) for n in me.corner_normals]
    for p in me.polygons:
        if p.material_index==2:
            for li in p.loop_indices:
                q=C(me.vertices[me.loops[li].vertex_index].co);normals[li]=tuple(V(face_normal(q.x,q.y)))
        elif p.material_index==7:
            for li in p.loop_indices:normals[li]=tuple(p.normal)
    me.normals_split_custom_set(normals)

def ray_surface(x,z,top=False):
    # Body is baked at identity. Ray results are in Blender coordinates.
    origin=V((x,.2 if top else -.08,z));direction=V((0,-1 if top else 1,0))
    hit,loc,normal,index=BODY.ray_cast(origin,direction)
    if not hit:raise RuntimeError(('Projection missed shell',x,z,top))
    return C(loc),C(normal)

def projected_patch(name, poly, mat, top=False, offset=.00017, depth=.00045, center=None, rings=10):
    # Dense concentric loops follow camber; inner layer makes every panel a closed solid.
    center=Vector(center) if center is not None else sum((Vector(p) for p in poly),Vector((0,0)))/len(poly);n=len(poly)
    verts=[];faces=[]
    for surface in [1,0]:
        for j in range(1,rings+1):
            f=j/rings
            for p in poly:
                q=center+(Vector(p)-center)*f;loc,norm=ray_surface(q.x,q.y,top)
                v=loc+norm*(offset if surface else -depth)
                if not top and surface:v.y=max(0.0,v.y)
                verts.append(v)
        loc,norm=ray_surface(center.x,center.y,top)
        v=loc+norm*(offset if surface else -depth)
        if not top and surface:v.y=max(0.0,v.y)
        verts.append(v)
    L=rings*n+1
    for k in range(2):
        off=k*L
        for j in range(rings-1):
            for i in range(n):
                a=off+j*n+i;b=off+j*n+(i+1)%n;faces.append((a,b,b+n,a+n))
        for i in range(n):faces.append((off+rings*n,off+(i+1)%n,off+i))
    outer=(rings-1)*n
    for i in range(n):faces.append((outer+i,outer+(i+1)%n,outer+(i+1)%n+L,outer+i+L))
    return finish(obj_mesh(name,verts,faces),mat)

def marker(name,point,root,shaft=False):
    ob=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(ob);ob.parent=root
    ob.location=V(point);ob.empty_display_type='ARROWS';ob.empty_display_size=.009
    if shaft:ob.rotation_euler.y=math.radians(-TILT)
    if name=='face_center':ob.rotation_euler.x=LOFT
    return ob

def build_ferrule():
    f=tube('04 Tapered hollow ferrule',
           [SOCKET-AXIS*.0015,SOCKET+AXIS*.001,SOCKET+AXIS*.003,SOCKET+AXIS*.0135],
           [.00665,.0065,.00615,.00555],64)
    boolean(f,tube('Ferrule bore',[SOCKET-AXIS*.004,SOCKET+AXIS*.018],[.0047,.0047],64))
    bevel(f,.00015,3);finish(f,MATS[6])
    ring=tube('05 Titanium hosel collar',[SOCKET-AXIS*.002,SOCKET-AXIS*.0013],[.00672,.00672],64)
    boolean(ring,tube('Collar bore',[SOCKET-AXIS*.003,SOCKET+AXIS*.001],[.0047,.0047],64))
    bevel(ring,.00008,2);finish(ring,MATS[5])

def export_glb(mesh,root,markers,path):
    bpy.ops.object.select_all(action='DESELECT')
    for o in [mesh,root]+markers:o.select_set(True)
    bpy.context.view_layer.objects.active=mesh
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,
        export_yup=True,export_animations=False,export_extras=True,export_normals=True,
        export_tangents=True,export_texcoords=True,export_materials='EXPORT',
        export_image_format='AUTO')
