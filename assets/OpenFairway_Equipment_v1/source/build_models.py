"""Build editable Blender masters and self-contained glTF 2.0 models.
Run in Blender 4.3+ background mode, or with the matching bpy Python module.
All design coordinates below are metres, Y-up, striking face toward -Z.
"""
from pathlib import Path
import bpy,math,json,sys,argparse
from mathutils import Vector
from catalog_source import CATALOG,FAMILY_LENGTH

PACK=Path(__file__).resolve().parents[1]
ASSETS=PACK/'assets/openfairway_equipment'
TEX=ASSETS/'textures'
MODELS=ASSETS/'models';MODELS.mkdir(parents=True,exist_ok=True)
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

def wood(fam):
    if fam=='driver':N=40;rx=.060;ry=.028;yc=.030;front=-.032;back=.061;prof=[(.0,.86,.76),(.16,.97,.96),(.38,1,1),(.63,.91,.96),(.84,.67,.73),(.97,.27,.42)]
    elif fam=='fairway':N=32;rx=.049;ry=.020;yc=.022;front=-.024;back=.048;prof=[(0,.83,.70),(.19,.96,.94),(.44,1,1),(.72,.8,.89),(.95,.32,.44)]
    else:N=28;rx=.043;ry=.021;yc=.023;front=-.020;back=.031;prof=[(0,.84,.80),(.20,.98,1),(.49,1,.94),(.76,.86,.79),(.97,.35,.34)]
    verts=[]
    for t,sx,sy in prof:
        for i in range(N):
            a=i*math.tau/N;xp=rx*sx*math.cos(a);yp=yc+ry*sy*math.sin(a)
            # Slightly higher toe, flatter sole, fuller heel-to-toe shoulder.
            yp+=max(0,math.sin(a))*.003*(xp/rx+.3)
            verts.append((xp,max(.002,yp),front+(back-front)*t))
    faces=[]
    for j in range(len(prof)-1):
        for i in range(N):faces.append((j*N+i,j*N+(i+1)%N,(j+1)*N+(i+1)%N,(j+1)*N+i))
    verts.append((0,yc,back));last=len(verts)-1
    for i in range(N):faces.append(((len(prof)-1)*N+i,(len(prof)-1)*N+(i+1)%N,last))
    prev=list(range(N))
    for r in [.67,.33]:
        inds=[]
        for i in range(N):
            a=i*math.tau/N;inds.append(len(verts));verts.append((rx*.86*r*math.cos(a),yc+ry*.76*r*math.sin(a),front-.0018*(1-r*r)))
        for i in range(N):faces.append((prev[(i+1)%N],prev[i],inds[i],inds[(i+1)%N]))
        prev=inds
    verts.append((0,yc,front-.002));center=len(verts)-1
    for i in range(N):faces.append((prev[(i+1)%N],prev[i],center))
    shell=obj_mesh('shared_'+fam+'_shell',verts,faces);smooth(shell)
    socket=(-rx*.91,yc+ry+(.016 if fam=='driver' else .018),front+.019)
    neck=tube('offset_hosel',[(-rx*.73,yc+.004,front+.012),(-rx*.87,yc+ry-.002,front+.021),socket],[.0068,.006,.0048],16)
    parts=[shell,neck]
    if fam=='fairway':parts.append(box('sole_plate',(0,.003,.010),(.05,.002,.032),.0006,1))
    head=join(parts,'shared_'+fam+'_head');atlas_uv(head)
    return head,socket,(-.0,yc,front-.002)

def iron(fam):
    wedge=fam=='wedge';loft=.76 if wedge else .47
    outline=[(-.043,.006),(-.045,.014),(-.039,.023),(-.025,.035),(-.006,.047),(.019,.059 if wedge else .055),(.035,.060 if wedge else .056),(.045,.053),(.048,.039),(.047,.013),(.038,.004),(-.026,.002)]
    thickness=.015 if wedge else .012
    N=len(outline);verts=[]
    for dep in [0,thickness]:
        verts += [(x,y,y*loft-.020+dep) for x,y in outline]
    faces=[tuple(reversed(range(N)))]+[(i,(i+1)%N,(i+1)%N+N,i+N) for i in range(N)]
    if not wedge:
        inner=[(x*.70,.029+(y-.029)*.64) for x,y in outline]
        verts += [(x,y,y*loft-.020+thickness-.005) for x,y in inner]
        for i in range(N):faces.append((i+N,(i+1)%N+N,(i+1)%N+2*N,i+2*N))
        faces.append(tuple(range(2*N,3*N)))
    else:faces.append(tuple(range(N,2*N)))
    body=bevel(obj_mesh('shared_'+fam+'_body',verts,faces),.0010,2)
    socket=(-.048,.075,.013)
    neck=tube('forged_hosel',[(-.036,.025,.004),(-.043,.049,.009),socket],[.0072,.006,.0048],16)
    head=join([body,neck],'shared_'+fam+'_head');atlas_uv(head)
    triangulate_caps(head)
    head.shape_key_add(name='Basis');wide=head.shape_key_add(name='WideSole')
    for v in wide.data:
        weight=max(0,1-v.co.z/.024)
        if v.co.y<.006:v.co.y-=.025*weight
    return head,socket,(.008,.025,.025*loft-.020)

def plumber(x=-.036):
    return [box('plumber_neck',(x,.042,-.005),(.008,.035,.008),.001,2),box('plumber_offset',(x,.058,-.010),(.008,.009,.017),.001,2),tube('neck_socket',[(x,.058,-.016),(x-.003,.070,-.016)],[.0056,.0048],16)]
def putter(id,mats):
    parts=[];acc=[];face=(0,.014,-.010);socket=(-.032,.060,0)
    if id=='loaner_putter':
        parts=[box('plain_blade',(0,.011,0),(.096,.022,.013),.0013,2),tube('plain_neck',[(-.024,.020,0),(-.030,.054,0)],[.005,.0047],16)];socket=(-.030,.054,0);face=(0,.011,-.0065)
    elif id=='rustbelt_blade':
        outline=[(-.045,-.004),(.040,-.004),(.046,0),(.042,.005),(-.043,.005),(-.048,.002)]
        parts=[extrusion('thin_rust_blade',outline,.002,.024,radius=.0018,segments=3),tube('centre_bend',[(0,.020,.001),(-.010,.042,.002),(-.019,.064,-.003)],[.005,.0048,.0045],20)];socket=(-.019,.064,-.003);face=(0,.013,-.004)
    elif id=='brass_relic':
        outline=[(-.048,-.009),(.047,-.009),(.050,0),(.044,.014),(.029,.025),(-.029,.025),(-.045,.013),(-.050,0)]
        parts=[extrusion('rounded_brass_flange',outline,.002,.011,radius=.0025,segments=3),box('flange_blade',(0,.019,-.003),(.095,.024,.016),.0030,3),tube('near_centre_neck',[(-.012,.026,.002),(-.018,.050,.003),(-.022,.063,.003)],[.0062,.0052,.0048],20)];socket=(-.022,.063,.003)
    elif id in ['midnight_mallet','auto_putt_9000']:
        robot=id=='auto_putt_9000';w=.105 if robot else .120;depth=.070
        outline=[(-w/2,-.016),(w/2,-.016)]
        for j in range(21):
            a=j*math.pi/20;outline.append((w/2*math.cos(a),-.005+(depth-.011)*math.sin(a)))
        parts=[extrusion('rounded_mallet_chassis',outline,.002,.027,radius=.0015,segments=2)]
        if robot:
            parts+=[box('servo_neck',(-.044,.043,.0),(.015,.035,.017),.003,3),tube('servo_socket',[(-.044,.055,0),(-.048,.070,0)],[.007,.0048],20)]
            bpy.ops.mesh.primitive_uv_sphere_add(segments=24,ring_count=12,radius=1,location=V((0,.031,.028)));eye=bpy.context.object;eye.name='teal_sensor_dome';eye.scale=(.014,.014,.011);apply(eye);smooth(eye);eye.data.materials.append(mats['eye']);acc.append(eye)
            led=box('teal_lock_led',(0,.028,-.011),(.079,.002,.003),.0008,2);led.data.materials.append(mats['led']);acc.append(led)
            acc.append(disc('sensor_retaining_ring',(0,.028,.028),.016,.004,'y',mats['dark'],24))
            socket=(-.048,.070,0)
        else:
            parts.append(tube('double_bend_neck',[(-.046,.024,-.003),(-.045,.044,-.006),(-.050,.068,-.006)],[.0055,.005,.0048],20));socket=(-.050,.068,-.006)
            for xp in [-.011,.011]:
                a=box('white_parallel_inlay',(xp,.0276,.018),(.002,.0006,.054),.0002,1);a.data.materials.append(mats['white']);acc.append(a)
            a=box('short_center_tick',(0,.0276,-.003),(.0017,.0006,.013),.0002,1);a.data.materials.append(mats['white']);acc.append(a)
        face=(0,.014,-.016)
    elif id in ['copper_classic','scotty_grail','blackout_tour_issue']:
        w={'copper_classic':.100,'scotty_grail':.090,'blackout_tour_issue':.108}[id]
        depth=.034 if id!='blackout_tour_issue' else .030
        parts=[box('front_milled_blade',(0,.015,-.007),(w,.028,.011),.0015,3),box('rear_sole_flange',(0,.004,.006),(w,.007,depth),.0015,3)]
        for sign in [-1,1]:parts.append(box('heel_toe_weight',(sign*(w/2-.010),.013,.010),(.020,.022,.024),.0017,3))
        if id=='blackout_tour_issue':
            parts.append(tube('tour_neck',[(-.038,.024,.001),(-.039,.048,-.008),(-.042,.063,-.008)],[.0056,.0052,.0048],20));socket=(-.042,.063,-.008)
            a=box('red_full_sightline',(0,.0294,-.007),(w-.005,.0007,.0016),.00025,1);a.data.materials.append(mats['red']);acc.append(a)
            acc.append(disc('removable_weight_port',(.039,.014,.023),.0055,.0013,'z',mats['steel'],24))
            acc.append(disc('weight_screw',(.039,.014,.024),.0035,.0013,'z',mats['dark'],20))
            for angle in [0,math.pi/2]:
                a=box('screw_recess',(.039,.014,.0248),(.0045,.0006,.0003),0);a.rotation_euler.y=angle;apply(a);a.data.materials.append(mats['steel']);acc.append(a)
        else:parts+=plumber(-w*.38);socket=(-w*.38-.003,.070,-.016)
        if id=='scotty_grail':
            for xp in [-.014,0,.014]:
                acc.append(disc('cherry_inlay_socket',(xp,.016,-.0009),.0035,.001,'z',mats['dark'],24))
                acc.append(disc('cherry_red_inlay',(xp,.016,-.0001),.0027,.0012,'z',mats['red'],24))
        face=(0,.015,-.0125)
    elif id=='tourline_prototype':
        parts=[box('squared_face_beam',(0,.014,-.009),(.098,.026,.019),.0015,3),box('central_bridge',(0,.011,.014),(.067,.017,.042),.0018,3)]
        for sign in [-1,1]:
            o=box('splayed_rear_wing',(sign*.043,.014,.024),(.018,.024,.059),.0018,3);o.rotation_euler.z=sign*math.radians(18);apply(o);parts.append(o)
        parts.append(tube('raw_neck',[(-.041,.025,-.007),(-.042,.047,-.011),(-.047,.065,-.011)],[.006,.0052,.0048],20));socket=(-.047,.065,-.011)
        a=box('single_blue_sightline',(0,.020,.017),(.003,.001,.041),.0003,1);a.data.materials.append(mats['blue']);acc.append(a)
        face=(0,.014,-.0185)
    head=join(parts,'unique_'+id+'_head');atlas_uv(head)
    return head,socket,face,acc

def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mats={'steel':material('ofg_shared_polished_steel',(.55,.60,.61),.95,.22),'dark':material('ofg_shared_dark_fittings',(.018,.025,.03),.7,.4),'red':material('ofg_cherry_lacquer',(.52,.017,.020),.35,.23),'blue':material('ofg_blue_inlay',(.016,.19,.54),.2,.28),'white':material('ofg_white_inlay',(.87,.90,.86),.05,.25),'eye':material('ofg_teal_sensor',(.008,.28,.25),.65,.16,.6),'led':material('ofg_teal_led',(.012,.70,.54),.2,.25,2.5)}
    gripmat=image_mat('ofg_shared_grip',TEX/'shared/ofg_grip_albedo.png',rough=.83,normal=TEX/'shared/ofg_grip_normal.png')
    shaft=tube('shared_unit_shaft',[(0,h,0) for h in [0,.06,.23,.43,.61,.77]],[.0046,.0047,.005,.0052,.0056,.006],16);shaft.data.materials.append(mats['steel']);shaftmesh=shaft.data;bpy.data.objects.remove(shaft,do_unlink=True)
    grip=tube('shared_unit_grip',[(0,h,0) for h in [.764,.773,.90,.995,1.0]],[.0066,.0070,.0102,.011,.0105],20);grip.data.materials.append(gripmat);gripmesh=grip.data;bpy.data.objects.remove(grip,do_unlink=True)
    templates={}
    for fam in ['driver','fairway','hybrid','iron','wedge']:
        ob,sk,fc=wood(fam) if fam in ['driver','fairway','hybrid'] else iron(fam)
        templates[fam]=(ob.data,sk,fc);bpy.data.objects.remove(ob,do_unlink=True)
    roots=[];manifest=[]
    for c in CATALOG:
        id=c['id'];fam=c['family'];collection=bpy.data.collections.new('ofg_'+id);bpy.context.scene.collection.children.link(collection)
        root=bpy.data.objects.new('ofg_'+id,None);collection.objects.link(root);root['asset_id']=id;root['rarity']=c['rarity'];root['admin_only']=c.get('admin_only',False)
        if fam=='putter':head,sk,fc,acc=putter(id,mats)
        else:
            data,sk,fc=templates[fam];head=bpy.data.objects.new('head',data.copy());bpy.context.collection.objects.link(head);acc=[]
            if head.data.shape_keys:head.data.shape_keys.key_blocks['WideSole'].value=c.get('sole_width',1)-1
            if c.get('head_depth_scale'):head.scale.y=c['head_depth_scale'];sk=(sk[0],sk[1],sk[2]*c['head_depth_scale'])
        head.name='ofg_'+id+'__head';head.data.name='ofg_'+id+'__head_geometry';head.data.materials.clear();head.data.materials.append(head_material(c));head['base_mesh_family']=fam if fam!='putter' else id
        length=c.get('length',FAMILY_LENGTH[fam]);lie=19 if fam=='putter' else (29 if fam in ['driver','fairway'] else 26)
        direction=Vector((-math.sin(math.radians(lie)),math.cos(math.radians(lie)),0));shaft_length=length-sk[1]
        shaftob=bpy.data.objects.new('ofg_'+id+'__shaft',shaftmesh);bpy.context.collection.objects.link(shaftob)
        gripob=bpy.data.objects.new('ofg_'+id+'__grip',gripmesh);bpy.context.collection.objects.link(gripob)
        for ob in [shaftob,gripob]:ob.location=V(sk);ob.rotation_mode='QUATERNION';ob.rotation_quaternion=V(direction).to_track_quat('Z','Y');ob.scale.z=shaft_length
        ferrule=tube('ofg_'+id+'__ferrule',[Vector(sk)-direction*.001,Vector(sk)+direction*.012],[.0057,.0054],16);ferrule.data.materials.append(gripmat)
        items=[head,shaftob,gripob,ferrule]+acc
        for i,ob in enumerate(items):
            if not ob.data.shape_keys:triangulate_caps(ob)
            if ob in acc:ob.name='ofg_'+id+'__'+ob.name
            for old in list(ob.users_collection):old.objects.unlink(ob)
            collection.objects.link(ob);ob.parent=root
        for tag,loc in [('face_center',fc),('grip_anchor',Vector(sk)+direction*shaft_length*.89),('shaft_socket',sk)]:
            ob=bpy.data.objects.new('ofg_'+id+'__'+tag,None);ob.empty_display_type='PLAIN_AXES';ob.empty_display_size=.01;ob.location=V(loc);ob.parent=root;collection.objects.link(ob);items.append(ob)
        # Export one model at a time, with metre units and embedded images.
        bpy.ops.object.select_all(action='DESELECT');root.select_set(True)
        for ob in items:ob.select_set(True)
        folder=MODELS/('admin' if c.get('admin_only') else fam);folder.mkdir(exist_ok=True)
        path=folder/f'ofg_{id}.glb'
        bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_yup=True,export_apply=False,export_animations=False,export_extras=True,export_texcoords=True,export_normals=True,export_tangents=True,export_image_format='AUTO',export_materials='EXPORT')
        htris=0;total=0
        for ob in items:
            if ob.type=='MESH':
                ob.data.calc_loop_triangles();n=len(ob.data.loop_triangles);total+=n
                if ob not in [shaftob,gripob,ferrule]:htris+=n
        corrosive=c['style'] in ['rust','raw','rustbelt','rental','cavity','brass']
        manifest.append(dict(id=id,display_name=c['name'],family=fam,rarity=c['rarity'],admin_only=c.get('admin_only',False),collectible=fam=='putter' and id not in ['loaner_putter','auto_putt_9000'],base_price=c['price'],model='res://assets/openfairway_equipment/'+str(path.relative_to(ASSETS)),head_triangles=htris,total_triangles=total,shaft_length_m=round(shaft_length,4),overall_reference_length_m=length,condition=1.0,wear_texture=f'res://assets/openfairway_equipment/textures/{id}/ofg_{id}_wear.png',chip_strength=0.0 if c['style'] in ['brass','bronze','copper','grail','rust','rustbelt','raw'] else .70,corrosion_strength=.65 if corrosive else .10,oxidation_color=([.12,.28,.21] if c['style']=='brass' else ([.32,.24,.18] if c['style']=='copper' else [.38,.16,.055])),sole_width_weight=c.get('sole_width',1)-1,head_depth_scale=c.get('head_depth_scale',1)))
        root.hide_render=True
        for o in items:o.hide_render=True
        roots.append(root)
        print(f'EXPORTED {id} head={htris} whole={total}',flush=True)
    # Fitted, separate textile display prop. It never duplicates an inventory entry.
    covermat=image_mat('ofg_grail_headcover_fabric',TEX/'shared/ofg_grail_headcover_albedo.png',rough=.91)
    cover=join([box('fitted_padded_body',(0,.023,.006),(.110,.045,.051),.009,4),box('fitted_neck_sock',(-.039,.052,-.008),(.026,.060,.028),.009,4)],'ofg_grail_headcover');atlas_uv(cover);cover.data.materials.append(covermat);triangulate_caps(cover)
    # The cover uses a single fabric tile, rather than the equipment atlas.
    for uv in cover.data.uv_layers.active.data:uv.uv=((uv.uv.x*2)%1,(uv.uv.y*2)%1)
    props=MODELS/'props';props.mkdir(exist_ok=True);active(cover)
    bpy.ops.export_scene.gltf(filepath=str(props/'ofg_grail_headcover.glb'),export_format='GLB',use_selection=True,export_yup=True,export_animations=False,export_extras=True)
    cover.hide_render=True
    manifestdoc={'format_version':1,'units':'metres','up_axis':'+Y','face_forward':'-Z','pivot':'sole at ground, head centered on X','item_count':45,'items':manifest,'props':[{'id':'grail_headcover','model':'res://assets/openfairway_equipment/models/props/ofg_grail_headcover.glb'}]}
    (ASSETS/'catalog.json').write_text(json.dumps(manifestdoc,indent=2))
    bpy.context.scene.unit_settings.system='METRIC';bpy.context.scene.unit_settings.scale_length=1
    # Lay out source collections for editing; exported clubs stay at their sole origin.
    for i,root in enumerate(roots):root.location=(i%9*.70, i//9*-.75,0)
    cover.location=(3.6,-3.0,0)
    for ob in bpy.context.scene.objects:ob.hide_render=False
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=str(PACK/'source/OpenFairway_Equipment_Master.blend'))
    print('BUILD_COMPLETE',flush=True)

if __name__=='__main__':build()
