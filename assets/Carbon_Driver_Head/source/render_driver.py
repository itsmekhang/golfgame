"""Render the exported GLB (not a different high-poly model)."""
import bpy, math, json, sys, time
from pathlib import Path
from mathutils import Vector
PACK=Path(__file__).resolve().parents[1]
PREV=PACK/'previews';PREV.mkdir(exist_ok=True)
def V(p):return Vector((p[0],-p[2],p[1]))
def aim(ob,p):ob.rotation_euler=(V(p)-ob.location).to_track_quat('-Z','Y').to_euler()
def render_png(path):
    bpy.context.scene.render.filepath=str(path)
    bpy.ops.render.render(write_still=False)
    for attempt in range(4):
        try:
            bpy.data.images['Render Result'].save_render(str(path),scene=bpy.context.scene)
            print('SAVED_PREVIEW '+str(path),flush=True)
            break
        except RuntimeError:
            if attempt==3:raise
            time.sleep(.5)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(PACK/'driver_head_real_scale.glb'))
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=40
scene.cycles.use_denoising=True;scene.render.resolution_x=1200;scene.render.resolution_y=960;scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX';scene.view_settings.exposure=-.75
scene.world=bpy.data.worlds.new('Product studio');scene.world.use_nodes=True
scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.16,.18,.22,1)
scene.world.node_tree.nodes['Background'].inputs[1].default_value=.65
for name,loc,power,sx,sy in [
    ('Large overhead softbox',(-.10,.25,-.13),3.5,.19,.13),
    ('Face stripbox',(.16,.08,-.19),2,.075,.19),
    ('Rear rim strip',(.08,.19,.19),4.5,.09,.20),
    ('Heel fill',(-.20,.055,.04),2.5,.10,.14),
    ('Underside softbox',(.12,-.12,.18),2.7,.16,.15)]:
    bpy.ops.object.light_add(type='AREA',location=V(loc));o=bpy.context.object;o.name=name
    o.data.energy=power;o.data.shape='RECTANGLE';o.data.size=sx;o.data.size_y=sy;aim(o,(0,.03,.01))
bpy.ops.object.camera_add();cam=bpy.context.object;cam.name='Asset inspection camera'
cam.data.type='ORTHO';cam.data.lens=55;cam.data.clip_start=.001;cam.data.clip_end=20;scene.camera=cam
views=[
    ('hero',(.205,.175,-.25),(0,.038,.012),.190),
    ('toe',(.26,.070,.028),(0,.036,.012),.183),
    ('sole',(.11,-.225,.125),(0,.017,.015),.182),
    ('face',(.002,.039,-.29),(0,.038,-.012),.183),
    ('crown',(.002,.31,.014),(0,.027,.014),.183),
    ('rear',(-.14,.095,.24),(0,.037,.023),.192)]
args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
chosen=args or ['hero','toe','sole']
for name,loc,target,scale in views:
    if name not in chosen and 'all' not in chosen:continue
    cam.location=V(loc);aim(cam,target);cam.data.ortho_scale=scale
    render_png(PREV/(name+'.png'))
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(PREV/'Carbon_Driver_Studio.blend'))
print('RENDER_COMPLETE',flush=True)
