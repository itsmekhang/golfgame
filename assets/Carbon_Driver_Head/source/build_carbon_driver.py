"""Build the separate OFG D2 Carbon driver in Blender, at the existing club scale.
Run: blender -b -t 6 --python build_carbon_driver.py
The supplied AI OBJs inform silhouette only; all final surfaces are authored here.
"""
import bpy, math, json, sys
import numpy as np
from pathlib import Path
from mathutils import Vector, Matrix
sys.path.insert(0,str(Path(__file__).resolve().parent))
import geometry_core as g
from mesh_helpers import V,C,active,material,obj_mesh,tube,smooth

PACK=Path(__file__).resolve().parents[1]
BASE=.0010
REAR=(.004,.057)
FRONT=(-.033,-.002)

def outline():
    # Broad toe and rear, with a more compact heel and a nearly straight face plan.
    curves=[
        ((-.039,-.044),(-.014,-.048),(.017,-.048),(.040,-.044)),
        ((.040,-.044),(.057,-.040),(.065,-.018),(.065,.002)),
        ((.065,.002),(.066,.026),(.058,.046),(.045,.058)),
        ((.045,.058),(.033,.070),(.019,.075),(.008,.075)),
        ((.008,.075),(-.008,.075),(-.027,.066),(-.038,.055)),
        ((-.038,.055),(-.052,.041),(-.061,.021),(-.061,.002)),
        ((-.061,.002),(-.061,-.019),(-.054,-.039),(-.039,-.044))]
    return [g.cubic(*q,j/24) for q in curves for j in range(24)]

def materials():
    tex=PACK/'textures';tex.mkdir(exist_ok=True)
    shell=material('01 | Obsidian gloss titanium frame',(.010,.012,.016),.40,.28)
    p=shell.node_tree.nodes.get('Principled BSDF');p.inputs['Coat Weight'].default_value=.34;p.inputs['Coat Roughness'].default_value=.19
    carbon=material('02 | Black 2x2 carbon twill',(.018,.021,.025),.10,.40)
    face=material('03 | Crimson woven striking face',(.25,.012,.022),.18,.37)
    s=512;yy,xx=np.mgrid[0:s,0:s]/s*4
    ix=np.floor(xx).astype(int);iy=np.floor(yy).astype(int);fx=xx%1;fy=yy%1
    horizontal=((ix-iy)%4)<2;cross=np.where(horizontal,fy,fx);along=np.where(horizontal,fx,fy)
    edge=np.sin(np.pi*cross)**.5;threads=.94+.06*np.cos(cross*math.pi*2*24)
    weave=edge*(.65+.35*np.sin(np.pi*along));val=(.006+.040*weave)*threads
    rgba=np.ones((s,s,4));rgba[:,:,0]=val*.90;rgba[:,:,1]=val*.96;rgba[:,:,2]=val
    color=g.generated_image('Black carbon twill',rgba,tex/'carbon_twill_color.png')
    gy,gx=np.gradient(weave);nx=-gx*2.0;ny=-gy*2.0;nz=np.ones_like(nx);length=np.sqrt(nx*nx+ny*ny+nz*nz)
    nm=np.ones((s,s,4));nm[:,:,0]=nx/length*.5+.5;nm[:,:,1]=ny/length*.5+.5;nm[:,:,2]=nz/length*.5+.5
    normal=g.generated_image('Woven tangent normal',nm,tex/'carbon_twill_normal.png',True)
    red=np.ones((s,s,4));red[:,:,0]=(.21+.075*weave)*threads;red[:,:,1]=.008+.004*weave;red[:,:,2]=.015+.006*weave
    redimage=g.generated_image('Crimson face carbon',red,tex/'crimson_face_color.png')
    for mat,im,strength,coat in [(carbon,color,.18,.22),(face,redimage,.28,.15)]:
        nt=mat.node_tree;p=nt.nodes.get('Principled BSDF')
        c=nt.nodes.new('ShaderNodeTexImage');c.image=im;nt.links.new(c.outputs['Color'],p.inputs['Base Color'])
        n=nt.nodes.new('ShaderNodeTexImage');n.image=normal
        m=nt.nodes.new('ShaderNodeNormalMap');m.inputs['Strength'].default_value=strength
        nt.links.new(n.outputs['Color'],m.inputs['Color']);nt.links.new(m.outputs['Normal'],p.inputs['Normal'])
        p.inputs['Coat Weight'].default_value=coat;p.inputs['Coat Roughness'].default_value=.24
        if mat==carbon:p.inputs['Specular IOR Level'].default_value=.28
    dark=material('04 | Recesses and graphite gaskets',(.006,.008,.011),.20,.49)
    dark.node_tree.nodes.get('Principled BSDF').inputs['Specular IOR Level'].default_value=.30
    red=material('05 | Anodized scarlet chassis',(.42,.008,.018),.66,.27)
    p=red.node_tree.nodes.get('Principled BSDF');p.inputs['Coat Weight'].default_value=.2
    steel=material('06 | Machined titanium hardware',(.33,.38,.43),.93,.30)
    ferrule=material('07 | Black polymer adapter',(.004,.005,.007),0,.58)
    ferrule.node_tree.nodes.get('Principled BSDF').inputs['Specular IOR Level'].default_value=.25
    grooves=material('08 | Dark recessed scorelines',(.035,.009,.015),.22,.48)
    spine=material('09 | Satin graphite sole spine',(.023,.030,.040),.45,.36)
    ink=material('10 | Platinum markings',(.66,.70,.74),.40,.40)
    g.MATS.extend([shell,carbon,face,dark,red,steel,ferrule,grooves,spine,ink])

def body_blank():
    verts=[(g.SOLE_POLE.x,BASE,g.SOLE_POLE.y)];faces=[];ring_mats=[]
    def add(points,mats):verts.extend(points);ring_mats.append(mats)
    for j in range(6,0,-1):
        s=j/7
        add([(q.x,BASE+g.SOLE_CAMBER*g.smoothstep(1-s),q.y) for p,n in zip(g.OUTLINE,g.OUTNORMALS)
            for q in [g.SOLE_POLE+(p-n*g.SOLE_R-g.SOLE_POLE)*(1-s)]],3)
    for j in range(14,0,-1):
        phi=math.pi/2*j/14;d=g.SOLE_R*(1-math.cos(phi))
        add([(q.x,g.EQ*(1-math.sin(phi))+(BASE+g.SOLE_CAMBER)*math.sin(phi),q.y)
             for p,n in zip(g.OUTLINE,g.OUTNORMALS) for q in [p-n*d]],3)
    add([g.crown(p,0) for p in g.OUTLINE],0)
    for segment,steps in [('frame',17),('seam',2),('carbon',21)]:
        for j in range(1,steps+1):
            f=j/steps;points=[];mats=[]
            for p in g.OUTLINE:
                w=g.bearing(p);high=.605-.445*w+.008*max(0,-p.x/.061)
                if segment=='frame':t=(high-.017)*f;m=0
                elif segment=='seam':t=high-.017+.017*f;m=4 if w>.22 else 0
                else:t=high+(1-high)*f;m=1
                points.append(g.crown(p,t));mats.append(m)
            if segment=='carbon' and j==steps:break
            add(points,mats)
    apex=len(verts);verts.append((g.APEX.x,g.APEX_Y,g.APEX.y));mi=[]
    for i in range(g.N):faces.append((0,1+(i+1)%g.N,1+i));mi.append(3)
    for r in range(len(ring_mats)-1):
        for i in range(g.N):
            a=1+r*g.N+i;b=1+r*g.N+(i+1)%g.N
            faces.append((a,b,b+g.N,a+g.N));m=ring_mats[r+1];mi.append(m if isinstance(m,int) else m[i])
    top=1+(len(ring_mats)-1)*g.N
    for i in range(g.N):faces.append((top+i,top+(i+1)%g.N,apex));mi.append(1)
    ob=obj_mesh('01 D2 monocoque shell and flowing hosel',verts,faces)
    for m in g.MATS:ob.data.materials.append(m)
    for p,m in zip(ob.data.polygons,mi):p.material_index=m
    smooth(ob);return ob

def dense_poly(poly,step=.002):
    pts=[]
    for a,b in zip(poly,poly[1:]+poly[:1]):
        count=max(1,math.ceil(math.dist(a,b)/step))
        pts.extend([Vector(a).lerp(Vector(b),j/count) for j in range(count)])
    return pts

def patch(name,poly,mat,offset=.0003,top=False,center=None):
    return g.projected_patch(name,dense_poly(poly),g.MATS[mat],offset=offset,depth=.0003,top=top,center=center)

def hole(name,position,r,top=.010,bottom=-.015,sides=64):
    x,z=position;return tube(name,[(x,bottom,z),(x,top,z)],[r,r],sides)

def sole_channel(name,x0,x1,z0,z1,top):
    points=dense_poly(g.round_rect(x0,x1,z0,z1,min((z1-z0)/2-.00005,.0024)),.003)
    verts=[(p.x,y,p.y) for y in [-.012,top] for p in points];n=len(points)
    fs=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    return obj_mesh(name,verts,fs)

def weight(position,r,name):
    x,z=position;loc,_=g.ray_surface(x,z);outer_y=loc.y-.00045
    for label,outer,inner,lo,hi,mat in [
        ('scarlet gasket',r-.00025,r-.0012,outer_y+.00020,outer_y+.0016,4),
        ('titanium bezel',r-.0011,r-.0022,outer_y,outer_y+.0018,5)]:
        o=tube(name+' '+label,[(x,lo,z),(x,hi,z)],[outer,outer],64)
        g.boolean(o,hole('Ring aperture',position,inner,hi+.01,lo-.01));g.bevel(o,.00012,3);g.finish(o,g.MATS[mat])
    plug=tube(name+' recessed hex bolt',[(x,outer_y+.00025,z),(x,outer_y+.003,z)],[r-.00235,r-.00235],64)
    g.boolean(plug,hole('Hex socket',position,.00175 if r>.007 else .0013,outer_y+.0015,-.01,6))
    g.bevel(plug,.00013,3);g.finish(plug,g.MATS[8])

def lettering(body,x,z,size,name,mat=9,top=False,offset=.0009):
    curve=bpy.data.curves.new(name,'FONT');curve.body=body;curve.size=size;curve.align_x='CENTER'
    curve.extrude=.000022;curve.bevel_depth=.000008;curve.bevel_resolution=1;curve.resolution_u=6
    ob=bpy.data.objects.new(name,curve);bpy.context.collection.objects.link(ob)
    if not top:ob.rotation_euler.x=math.pi
    ob.location=V((x,0,z));active(ob);bpy.ops.object.convert(target='MESH');ob=bpy.context.object
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    for v in ob.data.vertices:
        q=C(v.co);loc,norm=g.ray_surface(q.x,q.z,top)
        q.y=loc.y+(.00025 if top else -offset)+q.y;v.co=V(q)
    g.finish(ob,g.MATS[mat])
    for p in ob.data.polygons:p.use_smooth=False

def sole_details(head):
    # Main carbon shield, with a separate structural red perimeter.
    poly=[(-.031,-.011),(.034,-.011),(.041,.004),(.022,.036),(.012,.061),(-.005,.064),(-.027,.035),(-.039,.005)]
    border=patch('06 Scarlet perimeter of sole shield',poly,4,.0003)
    center=Vector((.002,.021));inner=[center+(Vector(q)-center)*.955 for q in poly]
    shield=patch('07 Carbon composite sole shield',inner,1,.0006)
    for ob in [border,shield]:
        g.boolean(ob,hole('Rear weight clearance',REAR,.0089,.022))
        g.boolean(ob,hole('Forward heel weight clearance',FRONT,.0070,.022))
    # A shallow satin Y-spine gives the sole a designed section and an actual ground contact.
    keel=[(-.018,-.012),(.019,-.012),(.018,.005),(.010,.029),(.005,.048),(-.001,.048),(-.007,.028),(-.016,.006)]
    spine=patch('08 Sculpted central graphite keel',keel,8,.0010,center=g.SOLE_POLE)
    # The keel's central contact is the ground-origin reference, without moving the socket.
    v=min(spine.data.vertices,key=lambda v:C(v.co).y);q=C(v.co);q.y=0;v.co=V(q);spine.data.update()
    # Titanium strakes flank the central spine; each tapers toward the rear weight.
    for side in [-1,1]:
        rib=[(side*.024,-.006),(side*.028,-.004),(side*.014,.028),(side*.0065,.046),(side*.010,.023)]
        patch(('09 Heel' if side<0 else '10 Toe')+' machined sole strake',rib,5,.00085)
    # Front slot is truly recessed; its floor is a dark solid 2 mm below the shell surface.
    floor=sole_channel('11 Elastomer floor of front relief channel',-.036,.039,-.0215,-.0171,.0073)
    # Keep only the top of the cutter as a thin closed insert, fully inside the head.
    for v in floor.data.vertices:
        p=C(v.co)
        if p.y<0:p.y=.0067;v.co=V(p)
    g.finish(floor,g.MATS[6])
    weight(REAR,.0089,'12 Rear weight')
    weight(FRONT,.0070,'13 Forward heel weight')
    lettering('D2',.001,.020,.009,'14 D2 sole wordmark',9,offset=.00115)
    lettering('C A R B O N',.001,.029,.0032,'15 Carbon designation',4,offset=.00115)
    lettering('10.5',.030,-.006,.0036,'16 Loft engraving',9)
    lettering('O F G',.024,.046,.0037,'17 Maker mark',9)
    # Original alignment emblem made as two convex slivers, avoiding overlapping fans.
    patch('18 Crown alignment left',[(0,-.014),(-.0033,-.0097),(-.0017,-.0102)],9,.00017,True)
    patch('19 Crown alignment right',[(0,-.014),(.0017,-.0102),(.0033,-.0097)],9,.00017,True)

def uv_map(ob):
    uv=ob.data.uv_layers.get('UVMap') or ob.data.uv_layers.new(name='UVMap')
    for p in ob.data.polygons:
        name=ob.data.materials[p.material_index].name
        face=name.startswith('03 |')
        normal=C(p.normal)
        for li in p.loop_indices:
            q=C(ob.data.vertices[ob.data.loops[li].vertex_index].co)
            # Smaller weave on the face, with a 30-degree rotated crown weave.
            if face:uv.data[li].uv=(q.x/.0032,q.y/.0032)
            elif abs(normal.y)<.15:
                # Give pocket walls and panel edges real UV area; planar XZ mapping
                # collapses vertical faces and produces undefined tangent vectors.
                uv.data[li].uv=((q.x if abs(normal.z)>abs(normal.x) else q.z)/.0064,q.y/.0064)
            else:uv.data[li].uv=((.866*q.x-.5*q.z)/.0064,(.5*q.x+.866*q.z)/.0064)

def tangent_charts(mesh):
    # Boolean intersections can leave micron-scale triangles whose planar UVs
    # collapse although the 3D triangle has area. Give those triangles local charts.
    me=mesh.data;uv=me.uv_layers.active
    repaired=0
    for attempt in range(3):
        me.calc_tangents(uvmap=uv.name)
        bad=[p for p in me.polygons if any(me.loops[li].tangent.length<.9 for li in p.loop_indices)]
        if not bad:break
        for p in bad:
            loops=list(p.loop_indices);pts=[me.vertices[me.loops[i].vertex_index].co for i in loops]
            origin=pts[0];u=(pts[1]-origin).normalized();v=p.normal.cross(u).normalized()
            anchor=uv.data[loops[0]].uv.copy()
            coords=[Vector(((q-origin).dot(u)/.0064,(q-origin).dot(v)/.0064)) for q in pts]
            if abs(coords[1].x*coords[2].y-coords[1].y*coords[2].x)<1e-8:coords[2].y+=.0001
            for li,q in zip(loops,coords):uv.data[li].uv=anchor+q
            repaired+=1
        me.free_tangents();me.update()
    me.calc_tangents(uvmap=uv.name)
    assert all(loop.tangent.length>.9 for loop in me.loops),'Unresolved tangent chart'
    me.free_tangents()
    return repaired

def export(head,body_dims,body_volume,slots):
    root=bpy.data.objects.new('Carbon_Driver_Head',None);bpy.context.collection.objects.link(root)
    meta={'asset_type':'head_only','family':'driver','model':'OFG D2 Carbon','units':'metres','import_scale':1.0,
          'body_dimensions_mm_xyz':body_dims,'face_loft_degrees_at_center':10.5,'lie_degrees':61.0,
          'shaft_tip_diameter_mm':9.2,'bore_diameter_mm':9.4,'face_bulge_radius_mm':310,'face_roll_radius_mm':280,
          'design':'Black carbon crown, crimson carbon face, scarlet rim, twin sole weights and graphite keel'}
    for k,v in meta.items():root[k]=v
    for o in g.PARTS:o.parent=root;uv_map(o)
    markers=[g.marker('shaft_socket',g.SOCKET,root,True),g.marker('socket_mouth',g.SOCKET+g.AXIS*.0135,root,True),
             g.marker('socket_bottom',g.SOCKET-g.AXIS*.027,root,True),g.marker('face_center',(0,.029,g.face_z(0,.029)),root)]
    reports=[{'name':o.name,**g.stats(o)} for o in g.PARTS]
    for st in reports:assert st['nonmanifold_edges']==0,st
    scene=bpy.context.scene;scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1.0;scene.unit_settings.length_unit='MILLIMETERS'
    bpy.ops.object.select_all(action='DESELECT');copies=[]
    for ob in g.PARTS:
        cp=ob.copy();cp.data=ob.data.copy();bpy.context.collection.objects.link(cp);cp.select_set(True);copies.append(cp)
    bpy.context.view_layer.objects.active=copies[0];bpy.ops.object.join();mesh=bpy.context.object
    mesh.name='driver_head_mesh';mesh.data.name='D2_Carbon_geometry';mesh.parent=root
    active(mesh);tri=mesh.modifiers.new('Explicit export triangulation','TRIANGULATE');tri.keep_custom_normals=True;bpy.ops.object.modifier_apply(modifier=tri.name)
    tangent_charts(mesh)
    g.export_glb(mesh,root,markers,PACK/'driver_head_real_scale.glb')
    active(mesh);bpy.ops.wm.obj_export(filepath=str(PACK/'driver_head_real_scale.obj'),export_selected_objects=True,
        forward_axis='NEGATIVE_Z',up_axis='Y',export_materials=True,export_triangulated_mesh=True,path_mode='RELATIVE')
    mtl=PACK/'driver_head_real_scale.mtl';lines=mtl.read_text().splitlines()
    for i,line in enumerate(lines):
        if line.startswith('map_'):
            fields=line.split();fields[-1]='textures/'+Path(fields[-1].replace('\\','/')).name;lines[i]=' '.join(fields)
    mtl.write_text('\n'.join(lines)+'\n')
    inv=(Matrix.Translation(V(g.SOCKET))@Matrix.Rotation(math.radians(-g.TILT),4,'Y')).inverted()
    # Preserve the identical vertex buffer in both variants. Baking another float32
    # rotation into tiny Boolean triangles can collapse their area and tangents.
    mesh.matrix_local=inv
    matrices=[m.matrix_local.copy() for m in markers]
    for m in markers:m.matrix_local=inv@m.matrix_local
    root['pivot']='shaft_socket';g.export_glb(mesh,root,markers,PACK/'driver_head_shaft_attachment.glb')
    for m,matrix in zip(markers,matrices):m.matrix_local=matrix
    del root['pivot'];bpy.data.objects.remove(mesh,do_unlink=True)
    for m in markers:m.hide_set(True)
    active(head)
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=='VIEW_3D':
                s=area.spaces.active;s.clip_start=.001;s.clip_end=100;s.region_3d.view_distance=.25
                s.region_3d.view_location=V((0,.034,.013));s.region_3d.view_rotation=(V((0,.034,.013))-V((.205,.175,-.25))).to_track_quat('-Z','Y')
                s.shading.type='MATERIAL'
    bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(PACK/'source/Carbon_Driver_Head.blend'))
    report={**meta,'body_envelope_volume_cc_before_hosel':body_volume,'shaft_socket_metres':list(g.SOCKET),'shaft_axis':list(g.AXIS),
            'scoreline_segments':len(slots),'scoreline_width_mm':.4,'scoreline_depth_mm':.23,
            'total_triangles':sum(x['triangles'] for x in reports),'materials':len(g.MATS),'embedded_texture_images':3,'components':reports,
            'reference_meshes':[{'file':'Downloads/driver 1.obj','triangles':500000},{'file':'Downloads/driver/base.obj','triangles':500000}]}
    (PACK/'geometry_report.json').write_text(json.dumps(report,indent=2));print('D2_BUILD_COMPLETE '+json.dumps(report),flush=True)

def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    g.PACK=PACK;g.PARTS.clear();g.MATS.clear();g.APEX_Y=.060
    g.OUTLINE=outline();g.N=len(g.OUTLINE);g.OUTNORMALS=[]
    for i,p in enumerate(g.OUTLINE):
        t=(g.OUTLINE[(i+1)%g.N]-g.OUTLINE[i-1]).normalized();g.OUTNORMALS.append(Vector((t.y,-t.x)))
    materials();head=body_blank();g.boolean(head,g.curved_face_cutter())
    coords=[C(v.co) for v in head.data.vertices]
    dims=[1000*(max(p[i] for p in coords)-min(p[i] for p in coords)) for i in range(3)];volume=g.stats(head)['volume_cc']
    g.boolean(head,g.head_hosel(),'UNION');g.bevel(head,.0014,5,.48)
    slots=[]
    for y in [.009,.014,.019,.024,.029,.034,.039,.044,.048]:
        xs=[C(p.center).x for p in head.data.polygons if abs(C(p.center).z-g.face_z(C(p.center).x,C(p.center).y))<.000055 and abs(C(p.center).y-y)<.0016]
        if not xs:continue
        left=min(xs)+.004;right=max(xs)-.004;gap=.0145+.002*math.sin((y-.009)/.039*math.pi)
        for a,b in [(left,-gap),(gap,right)]:
            if b-a>.006:g.boolean(head,g.slot_cut(a,b,y));slots.append((a,b,y))
    g.boolean(head,tube('9.4 mm blind shaft bore',[g.SOCKET-g.AXIS*.027,g.SOCKET+g.AXIS*.025],[.0047,.0047],64))
    projection=head.copy();projection.data=head.data.copy();bpy.context.collection.objects.link(projection);g.BODY=projection
    g.boolean(head,hole('Rear weight pocket',REAR,.0089,.012))
    g.boolean(head,hole('Forward heel weight pocket',FRONT,.0070,.011))
    channel=sole_channel('Recessed face-adjacent relief slot',-.036,.039,-.0215,-.0171,.0075);g.setmat(channel,g.MATS[3]);g.boolean(head,channel)
    g.finish(head);g.material_and_normals(head,slots);g.build_ferrule();sole_details(head)
    bpy.data.objects.remove(projection,do_unlink=True)
    export(head,dims,volume,slots)

if __name__=='__main__':main()
