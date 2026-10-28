import bpy,sys,os,math
from mathutils import Vector,Matrix
HERE=os.path.dirname(os.path.abspath(__file__))
SRC=HERE if os.path.exists(HERE+'/build_people.py') else 'C:/Users/willi/Documents/GolfGame/tools/blender'
sys.path.insert(0,SRC)
import human_base as HB
ns={'__file__':SRC+'/build_people.py','__name__':'npc_builder'}
code=open(SRC+'/build_people.py',encoding='utf8').read().rsplit('\nmain()',1)[0]
code=code.replace('src = [m.name for m in me.materials]', 'src = [m.name for m in me.materials]\n    original_materials = [p.material_index for p in me.polygons]')
code=code.replace('orig = src[p.material_index] if p.material_index < len(src) else ""','orig = src[original_materials[p.index]] if original_materials[p.index] < len(src) else ""')
code=code.replace('body.parent = arm', 'body.parent = arm\n    body.matrix_parent_inverse = Matrix.Identity(4)\n    body.matrix_basis = Matrix.Identity(4)')
code=code.replace('elif orig.startswith("Material.002"):', 'elif False:')
exec(compile(code,SRC+'/build_people.py','exec'),ns)
original_pieces=ns['human_pieces']
HAT_SCALE=1.06  # caps and visors a touch roomier than a tight fit
def trim_front_fringe(body,center,top):
 import bmesh
 bm=bmesh.new();bm.from_mesh(body.data)
 def hair_faces():return [face for face in bm.faces if body.data.materials[face.material_index].name.startswith('hair')]
 # Split only the hair at the brim line; coarse faces must not take the crown with them.
 for point,normal in (((0,0,top-.025),(0,0,1)),((0,0,top-.17),(0,0,1)),((0,center.y-.03,0),(0,1,0))):
  faces=hair_faces();geom=set(faces)
  for face in faces:geom.update(face.verts);geom.update(face.edges)
  bmesh.ops.bisect_plane(bm,geom=list(geom),dist=.00001,plane_co=point,plane_no=normal,clear_inner=False,clear_outer=False)
 # the fringe and the temples, down to the ears, from a little behind the middle of the head forward
 remove=[face for face in hair_faces() if top-.17<face.calc_center_median().z<top-.0251 and face.calc_center_median().y>center.y-.0299]
 bmesh.ops.delete(bm,geom=remove,context='FACES')
 bm.to_mesh(body.data);bm.free();body.data.update()
 print('TRIMMED FRONT FRINGE',len(remove),flush=True)

def fitted_pieces(P,body,J,items,cap_mesh):
 import bmesh
 scalp=[v.co for v in body.data.vertices if any(body.vertex_groups[g.group].name=='head' and g.weight>.5 for g in v.groups)]
 # The bare scalp defines the fit; remaining side hair must not enlarge the cap.
 hair_vertices={v for p in body.data.polygons if body.data.materials[p.material_index].name.startswith('hair') for v in p.vertices}
 skin=[v.co for v in body.data.vertices if v.index not in hair_vertices and any(body.vertex_groups[g.group].name=='head' and g.weight>.5 for g in v.groups)]
 top=max(p.z for p in skin)
 crown=[p for p in skin if p.z>top-.10]
 low=Vector([min(p[k] for p in crown) for k in range(3)]);high=Vector([max(p[k] for p in crown) for k in range(3)])
 if any(item in items for item in ('cap','visor','chef_hat')):trim_front_fringe(body,(low+high)*.5,top)
 if ('cap' in items and gender!='Female') or 'chef_hat' in items:  # a woman's visor leaves her hair be
  bm=bmesh.new();bm.from_mesh(body.data)
  if 'chef_hat' in items:
   remove=[f for f in bm.faces if body.data.materials[f.material_index].name.startswith('hair') and max(v.co.z for v in f.verts)>top-.085]
  else:
   # under a cap only the hair wholly inside its crown goes (tuck_hair pulls the rest in): the
   # hair below its back edge and in the strap opening stays, so there's no bald patch there
   remove=[f for f in bm.faces if body.data.materials[f.material_index].name.startswith('hair') and min(v.co.z for v in f.verts)>top-.04]
  bmesh.ops.delete(bm,geom=remove,context='FACES');bm.to_mesh(body.data);bm.free()
 if 'visor' in items or (gender=='Female' and 'cap' in items):
  # every visor is the user's visor model (women wear it in place of a cap too: no crown to
  # push through their hair)
  original_pieces(P,body,J,tuple(it for it in items if it not in ('cap','visor')),cap_mesh)
  geo=visor_geo();center=(low+high)*.5
  # a snug band on everyone (the men's was a size too big)
  fit=1.08
  s=(high.x-low.x)*fit*HAT_SCALE/(2*geo['half_w'])
  # Give the forehead a little clearance without widening the sides of the band.
  fitted=[]
  for point in geo['verts']:
   point=point.copy()
   if point.y>0:
    point.y+=.012/s*max(0,1-abs(point.x)/geo['half_w'])
   fitted.append(point)
  bm=bmesh.new();vs=[bm.verts.new(v) for v in fitted]
  for f in geo['faces']:
   try:bm.faces.new([vs[i] for i in f])
   except ValueError:pass
  P._add(bm,'cap' if 'cap' in items else 'accent','head',Matrix.Translation((center.x,center.y-.002,top-.100))@Matrix.Scale(s,4))
  # Only compress hair directly under the front/side band; keep the crown and rear opening full.
  tuck_hair(P,body,center,False)
  return
 original_pieces(P,body,J,tuple(it for it in items if it not in ('cap','visor')),cap_mesh)
 if 'cap' in items and cap_mesh is not None:
  center=(low+high)*.5
  sx=(high.x-low.x)*1.12*HAT_SCALE/.205;sy=(high.y-low.y)*1.15*HAT_SCALE/.223;sz=.14*HAT_SCALE/.143
  # Source brim points +Y; its crown is centered 4.2 cm behind its origin.
  transform=Matrix.Translation((center.x,center.y+.042*sy,top+.035-.143*sz))@Matrix.Diagonal((sx,sy,sz,1))
  mesh=bmesh.new();mesh.from_mesh(cap_mesh);P._add(mesh,'cap','head',transform)
 tuck_hair(P,body,(low+high)*.5,'cap' in items or 'chef_hat' in items)
VISOR=SRC+'/sources/headwear/visor.glb'
_visor_geo=None
def visor_geo():
 """The user's visor -- its band and brim (the logo decal left off) -- as verts and faces, the
 brim toward +Y, the band centred on the origin with its lowest point on z = 0; half_w is the
 band's half width. Read once."""
 global _visor_geo
 if _visor_geo is None:
  before=set(bpy.data.objects);bpy.ops.import_scene.gltf(filepath=VISOR)
  new=[o for o in bpy.data.objects if o not in before]
  main=max((o for o in new if o.type=='MESH'),key=lambda o:len(o.data.polygons))
  mw=main.matrix_world;vs=[mw@v.co for v in main.data.vertices];faces=[tuple(p.vertices) for p in main.data.polygons]
  for o in new:bpy.data.objects.remove(o,do_unlink=True)
  zlo=min(v.z for v in vs);zhi=max(v.z for v in vs)
  band=[v for v in vs if v.z>zlo+(zhi-zlo)*.6]  # the band's top edge: the brim sits lower
  c=sum(band,Vector())/len(band)
  ylo=min(v.y for v in vs);yhi=max(v.y for v in vs)
  flip=Matrix.Rotation(math.pi,3,'Z') if (ylo+yhi)*.5<c.y else Matrix.Identity(3)  # brim to +Y
  vs=[flip@(v-Vector((c.x,c.y,zlo))) for v in vs]
  _visor_geo={'verts':vs,'faces':faces,'half_w':max(abs(v.x) for v in vs if v.z>(zhi-zlo)*.6)}
 return _visor_geo
def tuck_hair(P,body,center,closed):
 """Tuck the hair under whatever sits on the head (cap, visor, chef's hat): a hair vertex in the
 hat's height band and outside its surface -- measured per direction round the head, a
 centimetre at a time -- is pulled in just under it; under a closed crown none pokes out of
 the top. Hair below the band (a ponytail) is left alone."""
 head=ns['NAMES'].index('head')
 hat=[v.co.copy() for v in P.bm.verts if v[P.dl].get(head,0)>.5 and any(P.mats[f.material_index] in ('cap','accent') for f in v.link_faces)]
 if not hat:return
 sectors,bins=24,{}
 zlo=min(p.z for p in hat);zhi=max(p.z for p in hat)
 def sector(p):return int((math.atan2(p.y-center.y,p.x-center.x)+math.pi)/(2*math.pi)*sectors)%sectors
 for p in hat:
  key=(sector(p),int((p.z-zlo)/.01));bins[key]=max(bins.get(key,0.0),(p.xy-center.xy).length)
 reach={s:max([r for (k,b),r in bins.items() if k==s] or [0.0]) for s in range(sectors)}
 hair={i for f in body.data.polygons if body.data.materials[f.material_index].name.startswith('hair') for i in f.vertices}
 for i in hair:
  v=body.data.vertices[i];p=v.co
  if p.z<zlo-.01:continue
  if not closed and (p.z>zhi or p.y<center.y-.025):continue
  if closed and p.z>zhi-.012:p.z=zhi-.012
  s=sector(p);r=bins.get((s,int((p.z-zlo)/.01)),reach[s])-.006
  d=p.xy-center.xy
  if not closed:r=max(r,d.length-.012)
  if r>0 and d.length>r:
   d=d.normalized()*r;p.x,p.y=center.x+d.x,center.y+d.y
ns['human_pieces']=fitted_pieces
OUT=os.path.normpath(SRC+'/../../assets/facilities/people') if HERE==SRC else HERE+'/npc_props';os.makedirs(OUT,exist_ok=True)
gender='Male'
def ours(name):
 name=name.split(':')[-1];side=None
 # our rig's .L bones are the character's right (they stand on the BaseModels' Right* joints,
 # below), so the body's Right* weights go to them
 for prefix,s in [('Left','R'),('Right','L')]:
  if name.startswith(prefix):side=s;name=name[len(prefix):]
 mapping={'Hips':'hips','Spine':'spine','Spine1':'chest','Spine2':'chest','Neck':'neck','Head':'head','HeadTop_End':'head','Shoulder':'chest','Arm':'upper_arm','ForeArm':'forearm','UpLeg':'thigh','Leg':'shin','Foot':'foot','ToeBase':'foot'}
 if name=='Hand':return ('hand',side)
 for finger in ('Thumb','Index','Middle','Ring','Pinky'):
  if name.startswith('Hand'+finger):
   digit=min(3,int(name[-1])) if name[-1].isdigit() else 1
   return ('finger_'+finger.lower()+str(digit),side)
 return (mapping[name],side) if name in mapping else None

HB._ours=ours
FINGERS=('Thumb','Index','Middle')
for side,prefix in (('L','Right'),('R','Left')):
 for finger in FINGERS:
  for digit in range(1,4):
   name='finger_'+finger.lower()+str(digit)+'.'+side
   ns['NAMES'].append(name)
   ns['CAPTURE_MAP'][name]=prefix+'Hand'+finger+str(digit)

def lower_full_arms(ob,J,angle=math.radians(79)):
 # Preserve the source finger weights instead of merging them into the palm.
 for side,sign in (('L',1),('R',-1)):
  pivot=J['shoulder.'+side];rot=Matrix.Rotation(angle*sign,3,'Y')
  indices={g.index for g in ob.vertex_groups if g.name.endswith('.'+side) and g.name.startswith(('upper_arm','forearm','hand','finger_'))}
  for v in ob.data.vertices:
   weight=min(1,sum(e.weight for e in v.groups if e.group in indices))
   if weight:v.co=v.co.lerp(pivot+rot@(v.co-pivot),weight)
 ob.data.update()
HB.lower_arms=lower_full_arms

ns['NAMES'].extend(('grip.L','grip.R'))
base_human_rig=ns['human_rig']
def full_human_rig(J,C):
 arm=base_human_rig(J,C)
 bpy.context.view_layer.objects.active=arm
 bpy.ops.object.mode_set(mode='EDIT')
 for side in ('L','R'):
  for finger in FINGERS:
   for digit in range(1,4):
    name='finger_'+finger.lower()+str(digit)+'.'+side
    bone=arm.data.edit_bones.new(name)
    bone.head=J['finger_'+finger.lower()+str(digit)+'.'+side]
    bone.tail=J['finger_'+finger.lower()+str(digit+1)+'.'+side]
    bone.align_roll(arm.data.edit_bones['hand.'+side].z_axis)
    parent='hand.'+side if digit==1 else 'finger_'+finger.lower()+str(digit-1)+'.'+side
    bone.parent=arm.data.edit_bones[parent]
 for side,sign in (('L',1),('R',-1)):
  hand=arm.data.edit_bones['hand.'+side]
  wrist=J['wrist.'+side]
  index=J['finger_index1.'+side];middle=J['finger_middle1.'+side]
  forward=((index+middle)*.5-wrist).normalized()
  normal=(index-middle).cross(forward).normalized()*sign
  palm=wrist.lerp((index+middle)*.5,.62)+normal*.008
  arm['palm_contact_'+side]=list(hand.matrix.inverted()@palm)
  arm['palm_normal_'+side]=list(hand.matrix.to_3x3().inverted()@normal)
  bone=arm.data.edit_bones.new('grip.'+side)
  bone.head=palm;bone.tail=palm+hand.y_axis*.025
  bone.align_roll(hand.z_axis);bone.parent=hand
 bpy.ops.object.mode_set(mode='OBJECT')
 return arm
ns['human_rig']=full_human_rig

def load_body(_path):
 before=set(bpy.data.objects)
 sources=SRC+'/sources/BaseModels' if os.path.isdir(SRC+'/sources/BaseModels') else 'C:/Users/willi/Downloads/BaseModels'
 bpy.ops.import_scene.fbx(filepath=sources+'/'+gender+'_Rigged_T-Pose.fbx')
 new=[o for o in bpy.data.objects if o not in before];arm=next(o for o in new if o.type=='ARMATURE');parts=[o for o in new if o.type=='MESH']
 for ob in new:ob.animation_data_clear()
 arm.data.pose_position='REST'
 bpy.context.view_layer.update()
 bones={b.name.split(':')[-1]:arm.matrix_world@b.head_local for b in arm.data.bones}
 up=(bones['Neck']-bones['Hips']).normalized();right=(bones['RightArm']-bones['LeftArm']).normalized();forward=up.cross(right).normalized();right=forward.cross(up).normalized()
 orient=Matrix((right,forward,up)).to_4x4()
 for ob in parts:
  bpy.ops.object.select_all(action='DESELECT');ob.select_set(True);bpy.context.view_layer.objects.active=ob
  for mod in list(ob.modifiers):
   if mod.type=='ARMATURE':bpy.ops.object.modifier_apply(modifier=mod.name)
   else:ob.modifiers.remove(mod)
  world=ob.matrix_world.copy();ob.parent=None;ob.data.transform(orient@world);ob.matrix_world=Matrix.Identity(4)
 points=[v.co for o in parts for v in o.data.vertices];low=Vector([min(p[k] for p in points) for k in range(3)]);high=Vector([max(p[k] for p in points) for k in range(3)])
 scale=(1.72 if gender=='Female' else 1.78)/(high.z-low.z)
 fix=Matrix.Scale(scale,4)@Matrix.Translation((-(low.x+high.x)/2,-(low.y+high.y)/2,-low.z))
 for ob in parts:ob.data.transform(fix);HB._merge_groups(ob)
 joints={k:fix@orient@p for k,p in bones.items()}
 J={a:joints[b] for a,b in [('pelvis','Hips'),('spine','Spine'),('chest','Spine1'),('neck','Neck'),('head','Head'),('head_top','HeadTop_End')]}
 for s,prefix in [('L','Right'),('R','Left')]:
  for a,b in [('shoulder','Arm'),('elbow','ForeArm'),('wrist','Hand'),('hand_tip','HandMiddle1'),('hip','UpLeg'),('knee','Leg'),('ankle','Foot'),('toe','ToeBase')]:J[a+'.'+s]=joints[prefix+b]
 for side,prefix in (('L','Right'),('R','Left')):
  for finger in FINGERS:
   for digit in range(1,5):
    name=prefix+'Hand'+finger+str(digit)
    value=joints.get(name)
    if value is None:value=joints[prefix+'Hand'+finger+'3']+(joints[prefix+'Hand'+finger+'3']-joints[prefix+'Hand'+finger+'2'])*.65
    J['finger_'+finger.lower()+str(digit)+'.'+side]=value.copy()
 for ob in parts:HB.lower_arms(ob,J)
 for s,sign in [('L',1),('R',-1)]:
  rot=Matrix.Rotation(math.radians(79)*sign,3,'Y');pivot=J['shoulder.'+s]
  for key in list(J):
   if key.endswith('.'+s) and (key.split('.')[0] in ('elbow','wrist','hand_tip') or key.startswith('finger_')):
    J[key]=pivot+rot@(J[key]-pivot)
 for ob in new:
  if ob not in parts:bpy.data.objects.remove(ob,do_unlink=True)
 for action in list(bpy.data.actions):bpy.data.actions.remove(action)
 return {'body':max(parts,key=lambda o:len(o.data.vertices)),'parts':parts,'joints':J}
HB.load=load_body
if '--gym-curl-only' in sys.argv:
 # Supplement the existing rigs without regenerating their geometry or other clips.
 for gender,look in (('male','a'),('female','d')):
  bpy.ops.wm.read_factory_settings(use_empty=True)
  bpy.ops.import_scene.gltf(filepath=OUT+'/golfer_'+look+'.glb')
  arm=next(o for o in bpy.data.objects if o.type=='ARMATURE')
  arm.animation_data_clear()
  for action in list(bpy.data.actions):bpy.data.actions.remove(action)
  for bone in arm.pose.bones:bone.matrix_basis=Matrix.Identity(4)
  bpy.context.scene.render.fps=24;bpy.context.view_layer.update()
  keys=ns['captured'](arm,'bicep_curl')
  if not keys:raise RuntimeError('Bicep Curl capture is missing')
  ns['make_action'](arm,'bicep_curl',keys)
  for track in arm.animation_data.nla_tracks:track.mute=True
  arm.animation_data.action=None
  for bone in arm.pose.bones:bone.matrix_basis=Matrix.Identity(4)
  bpy.context.view_layer.update()
  C=bpy.data.collections.new('GymCurl');bpy.context.scene.collection.children.link(C)
  for ob in bpy.data.objects:C.objects.link(ob)
  ns['export'](C,OUT+'/gym_curl_'+gender+'.glb')
  print('GYM CURL BUILT',gender,flush=True)
 sys.exit(0)
people=[(r,'staff_'+r+'.glb') for r in ns['ROLES']]+[('golfer_'+r,'golfer_'+r+'.glb') for r in ns['GOLFERS']]
if '--only' in sys.argv:
 selected=set(sys.argv[sys.argv.index('--only')+1].split(','));people=[p for p in people if p[0] in selected]
for role,filename in people:
 bpy.ops.wm.read_factory_settings(use_empty=True)
 gender='Female' if role in ('receptionist','trainer','shop_clerk') or (role.startswith('golfer_') and ns['GOLFERS'][role[7:]][6]) else 'Male'
 C,arm=ns['build_human'](role)
 for track in arm.animation_data.nla_tracks:track.mute=True
 arm.animation_data.action=None
 for bone in arm.pose.bones:bone.matrix_basis=Matrix.Identity(4)
 bpy.context.view_layer.update()
 ns['export'](C,OUT+'/'+filename)
 print('NPC BUILT',role,gender,flush=True)
# Reimport two exported assets for a representative pose preview.
if HERE==SRC:
 print('NPC MODELS COMPLETE',flush=True)
 sys.exit(0)
bpy.ops.wm.read_factory_settings(use_empty=True)
for i,key in enumerate(('a','d')):
 before=set(bpy.data.objects);bpy.ops.import_scene.gltf(filepath=OUT+'/golfer_'+key+'.glb')
 for ob in bpy.data.objects:
  if ob not in before and ob.parent is None:ob.location.x=(i-.5)*1.5
sys.path.insert(0,HERE+'/staged')
source=HERE+'/staged/build_facilities.py';preview={'__file__':source,'__name__':'preview'}
exec(compile(open(source,encoding='utf8').read().rsplit('\nmain()',1)[0],source,'exec'),preview)
cam=preview['setup_preview']();cam.location=(0,5,2);cam.rotation_euler=(Vector((0,0,.9))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=3.5
bpy.context.scene.render.filepath='C:/Users/willi/Documents/Codex/2026-10-23/ths/outputs/pro_shop/npc_models.png';bpy.ops.render.render(write_still=True)
