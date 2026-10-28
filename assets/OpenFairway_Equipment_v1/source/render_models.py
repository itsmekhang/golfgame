"""Preview the exported GLBs themselves, using Blender Cycles."""
from pathlib import Path
import bpy,math,json,sys,os
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).resolve().parent))
from catalog_source import CATALOG
PACK=Path(__file__).resolve().parents[1]
OUT=PACK/'previews';OUT.mkdir(exist_ok=True)
def V(p):return Vector((p[0],-p[2],p[1]))
def mat(name,c,rough):
 m=bpy.data.materials.new(name);m.use_nodes=True;p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*c,1);p.inputs['Roughness'].default_value=rough;return m
def area(name,loc,power,size,color,target=(0,.01,0)):
 d=bpy.data.lights.new(name,'AREA');d.energy=power;d.shape='RECTANGLE';d.size=size;d.size_y=size*.65;d.color=color
 o=bpy.data.objects.new(name,d);bpy.context.collection.objects.link(o);o.location=V(loc);o.rotation_euler=(V(target)-o.location).to_track_quat('-Z','Y').to_euler()
def render(id,back=False,full=False,outname=None,model_path=None,output_dir=None):
 bpy.ops.wm.read_factory_settings(use_empty=True)
 model=Path(model_path) if model_path else next((PACK/'assets/openfairway_equipment/models').rglob('ofg_'+id+'.glb'))
 bpy.ops.import_scene.gltf(filepath=str(model))
 root=bpy.data.objects.get('ofg_'+id)
 rear_yaw=root.get('rear_view_yaw') if root else None
 rear_pitch=root.get('rear_view_pitch') if root else None
 scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=20;scene.cycles.use_denoising=True;scene.cycles.max_bounces=5
 scene.render.threads_mode='FIXED';scene.render.threads=8
 scene.render.resolution_x=640 if not full else 700;scene.render.resolution_y=560 if not full else 1100;scene.render.resolution_percentage=100
 scene.view_settings.view_transform='AgX';scene.view_settings.look='AgX - Medium High Contrast';scene.view_settings.exposure=-.55;scene.render.film_transparent=True
 world=bpy.data.worlds.new('Soft studio');world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.66,.71,.73,1);world.node_tree.nodes['Background'].inputs[1].default_value=.55;scene.world=world
 # Large softboxes reveal the actual smooth normals and bevels in metal.
 if full:
  area('key',(.8,1.2,-.9),85,1.4,(1,.93,.82),(-.1,.45,0));area('rim',(-.7,.7,.6),65,1.0,(.75,.86,1),(-.1,.4,0));area('fill',(.2,.3,.8),20,.8,(1,1,1),(-.1,.4,0))
 else:
  area('key',(.13,.27,-.18),5,.27,(1,.94,.85));area('rim',(-.13,.19,.16),4,.22,(.76,.88,1));area('fill',(.18,.05,.20),1.3,.17,(1,.99,.91))
 bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.002));floor=bpy.context.object;floor.name='Studio shadow catcher';floor.is_shadow_catcher=True;floor.data.materials.append(mat('Studio surface',(.6,.61,.58),.8))
 camera=bpy.data.cameras.new('Camera');ob=bpy.data.objects.new('Camera',camera);bpy.context.collection.objects.link(ob);scene.camera=ob;camera.type='ORTHO';camera.lens=60
 if full:target=V((-.18,.49,.0));ob.location=V((.70,.72,-1.6));camera.ortho_scale=1.16
 else:
  target=V((-.004,.040,.010));ob.location=V((.18,.17,.24 if back else -.24));camera.ortho_scale=.186 if id not in ['auto_putt_9000','midnight_mallet'] else .204
  if back and rear_yaw is not None and rear_pitch is not None:
   offset=(math.sin(rear_yaw)*math.cos(rear_pitch),-math.sin(rear_pitch),math.cos(rear_yaw)*math.cos(rear_pitch))
   ob.location=target+V(offset)*.30
   floor.hide_render=True
 ob.rotation_euler=(target-ob.location).to_track_quat('-Z','Y').to_euler();camera.clip_start=.001;camera.clip_end=100
 scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGBA'
 destination=Path(output_dir).resolve() if output_dir else OUT
 destination.mkdir(parents=True,exist_ok=True)
 scene.render.filepath=str(destination/(outname or (f'ofg_{id}'+('_full' if full else '_back' if back else '')+'.png')))
 bpy.ops.render.render(write_still=True)
 print('RENDERED',id,'back' if back else 'front','full' if full else '',flush=True)
if __name__=='__main__':
 args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else sys.argv[1:]
 if args and args[0]=='one':
  render(args[1],len(args)>2 and args[2]=='back',len(args)>3 and args[3]=='full')
 elif args and args[0]=='sample':
  for id,back in [('loaner_driver',False),('persimmon_ghost',False),('blade_runner_forged',False),('scotty_grail',True),('tourline_prototype',True),('midnight_mallet',True)]:render(id,back)
 elif args and args[0]=='full':
  for id in ['meteor_xr_proto','scotty_grail','auto_putt_9000']:render(id,False,True)
 elif args and args[0]=='irons':
  for c in CATALOG:
   if c['family']=='iron' or c['id']=='utility_2u':render(c['id'],True)
 else:
  for c in CATALOG:render(c['id'],c['family'] in ['putter','iron'] or c['id']=='utility_2u')
  render('grail_headcover',True)
