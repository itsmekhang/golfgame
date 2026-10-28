"""Generate selective clips, preserving original GLB geometry and all other animations."""
import bpy,sys,math,json,struct,copy
from pathlib import Path
from mathutils import Euler,Vector,Matrix
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'tools/blender/generated_task_clips';OUT.mkdir(exist_ok=True)
src=ROOT/'tools/blender/build_people.py'
ns={'__file__':str(src),'__name__':'motion_helpers'}
sys.path.insert(0,str(src.parent))
exec(compile(src.read_text().rsplit('\nmain()',1)[0],str(src),'exec'),ns)
ns['CAPTURES']['block_a']={'fbx':'blocking.fbx','frames':(1,80,2),'in_place':True,'loop':False,'stand':True,'lower':35}
ns['CAPTURES']['block_b']={'fbx':'blocking_1.fbx','frames':(1,72,2),'in_place':True,'loop':False,'stand':True,'lower':35}
def read(p):
 raw=p.read_bytes();n=struct.unpack_from('<I',raw,12)[0];j=json.loads(raw[20:20+n]);start=20+n;size=struct.unpack_from('<I',raw,start)[0];return j,raw[start+8:start+8+size]
def merge(original,added,dest):
 j,b=read(original);a,ab=read(added); old=copy.deepcopy(j)
 names={n.get('name'):i for i,n in enumerate(j['nodes'])}
 offset=len(b);b+=ab;vo=len(j.get('bufferViews',[]));ao=len(j.get('accessors',[]))
 for v in a['bufferViews']:
  v=copy.deepcopy(v);v['buffer']=0;v['byteOffset']=v.get('byteOffset',0)+offset;j.setdefault('bufferViews',[]).append(v)
 for acc in a['accessors']:
  acc=copy.deepcopy(acc)
  if 'bufferView' in acc:acc['bufferView']+=vo
  assert 'sparse' not in acc
  j.setdefault('accessors',[]).append(acc)
 added_names=[]
 for anim in a['animations']:
  for sampler in anim['samplers']:sampler['input']+=ao;sampler['output']+=ao
  for ch in anim['channels']:ch['target']['node']=names[a['nodes'][ch['target']['node']]['name']]
  j['animations']=[x for x in j.get('animations',[]) if x.get('name')!=anim['name']];j['animations'].append(anim);added_names.append(anim['name'])
 j['buffers'][0]['byteLength']=len(b)
 assert j['nodes']==old['nodes'] and j['meshes']==old['meshes'] and j['skins']==old['skins']
 enc=json.dumps(j,separators=(',',':')).encode();enc+=b' '*((-len(enc))%4);b+=b'\0'*((-len(b))%4)
 dest.write_bytes(struct.pack('<III',0x46546c67,2,28+len(enc)+len(b))+struct.pack('<II',len(enc),0x4e4f534a)+enc+struct.pack('<II',len(b),0x004e4942)+b)
 print('MERGED',original.name,added_names,flush=True)
def wipe(arm,hood=False):
 a=ns['captured'](arm,'block_a');b=ns['captured'](arm,'block_b');keys=[]
 # Use both captures' shoulder/elbow rhythms, blended at the crossover and loop seam.
 for i in range(73):
  t=i/72;u=(1-math.cos(t*math.tau))/2
  pa=a[min(len(a)-1,round(u*(len(a)-1)))][1];pb=b[min(len(b)-1,round(u*(len(b)-1)))][1]
  blend=(1-math.cos(t*math.tau))/2
  pose={n:tuple(Euler(pa.get(n,(0,0,0))).to_quaternion().slerp(Euler(pb.get(n,(0,0,0))).to_quaternion(),blend).to_euler()) for n in ns['NAMES']}
  for n in pose:
   if n.startswith(('hips','thigh','shin','foot')):pose[n]=(0,0,0)
  pose['spine']=(math.radians(-22 if hood else -3),0,0)
  pose['chest']=(math.radians(-24 if hood else -8),0,math.radians(3)*math.sin(t*math.tau))
  # Flatten the broad block into an oval scrub against the cart body, below shoulder level.
  target=(.16+.15*math.sin(t*math.tau*2),.65+.07*math.cos(t*math.tau*2),.92) if hood else (.16+.15*math.sin(t*math.tau*2),.49,1.03+.10*math.cos(t*math.tau*2))
  pose=ns['reach'](arm,pose,(0,0,0),{'forearm.L':target,'forearm.R':(-.22,.20,.96)})
  keys.append((1+i,pose,(0,0,0)))
 keys[-1]=(73,keys[0][1],keys[0][2]);return keys
def bench(arm,incline=False):
 keys=[];r=math.radians
 hip=arm.data.bones['hips'].head_local
 loc=(0,(.59 if incline else .70)-hip.z,-(.15 if incline else .28)+hip.y)
 for i in range(49):
  t=i/48;lift=(1+math.cos(t*math.tau))/2
  pose={'hips':(r(58 if incline else 90),0,0)}
  for side,sign in [('L',1),('R',-1)]:
   pose['thigh.'+side]=(r(32 if incline else 0),0,r(-sign*8))
   pose['shin.'+side]=(r(-88),0,0)
   pose['upper_arm.'+side]=(r(30),0,r(sign*12))
   pose['forearm.'+side]=(r(85),0,0)
  z=(1.09 if incline else .93)+lift*.40
  pose=ns['reach'](arm,pose,loc,{'forearm.L':(.36,-.24,z),'forearm.R':(-.36,-.24,z),'shin.L':(.27,.72,.10),'shin.R':(-.27,.72,.10)})
  keys.append((1+i*1.5,pose,loc))
 keys[-1]=(73,keys[0][1],keys[0][2]);return keys
cache={}
files=sorted((ROOT/'assets/facilities/people').glob('golfer_*.glb' if '--gym' in sys.argv else 'staff_*.glb'))
for p in files:
 j,_=read(p);signature=json.dumps([(n.get('name'),n.get('translation'),n.get('rotation'),n.get('scale')) for n in j['nodes'] if n.get('name') in ns['NAMES']],sort_keys=True)
 kind='gym' if p.stem.startswith('golfer_') else ('cart' if p.stem=='staff_cart_attendant' else 'staff');key=(signature,kind)
 if key not in cache:
  bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.scene.render.fps=24
  bpy.ops.import_scene.gltf(filepath=str(p),bone_heuristic='BLENDER')
  arm=next(o for o in bpy.data.objects if o.type=='ARMATURE');arm.animation_data_clear()
  for act in list(bpy.data.actions):bpy.data.actions.remove(act)
  if kind=='gym':
   ns['make_action'](arm,'bench',bench(arm))
   ns['make_action'](arm,'bench_incline',bench(arm,True))
  else:ns['make_action'](arm,'breathe',ns['captured'](arm,'breathe'))
  if kind=='cart':
   ns['make_action'](arm,'wipe',wipe(arm))
   ns['make_action'](arm,'wipe_hood',wipe(arm,True))
  for ob in list(bpy.data.objects):
   if ob!=arm:bpy.data.objects.remove(ob,do_unlink=True)
  bpy.ops.object.select_all(action='DESELECT');arm.select_set(True);bpy.context.view_layer.objects.active=arm
  dest=OUT/('clips_'+str(len(cache))+'.glb')
  bpy.ops.export_scene.gltf(filepath=str(dest),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='ACTIONS',export_skins=True)
  cache[key]=dest
 merge(p,cache[key],OUT/p.name)
print('DONE',len(files),flush=True)
