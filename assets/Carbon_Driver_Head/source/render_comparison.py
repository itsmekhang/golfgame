"""Compare existing authored heads at unchanged scale and show the original shaft fit."""
from pathlib import Path
import bpy
PACK=Path(__file__).resolve().parents[1]
exec((PACK/'source/render_driver.py').read_text(encoding='utf-8-sig').split('views=[')[0])
ASSETS=PACK.parent
bpy.data.objects['Carbon_Driver_Head'].location=V((-.18,0,0))
for file,x in [('Driver_Head/driver_head_real_scale.glb',0),('Fairway_Wood_Head/fairway_wood_real_scale.glb',.18)]:
    before=set(bpy.context.scene.objects);bpy.ops.import_scene.gltf(filepath=str(ASSETS/file))
    added=set(bpy.context.scene.objects)-before
    bpy.context.view_layer.update()
    # Existing packages use different horizontal pivots. Center each presentation
    # position on its geometry while keeping its authored scale and height.
    xs=[(o.matrix_world@v.co).x for o in added if o.type=='MESH' for v in o.data.vertices]
    horizontal_center=(min(xs)+max(xs))/2
    for o in added:
        if o.parent not in added:o.location+=V((x-horizontal_center,0,0))
scene.render.resolution_x=1800;scene.render.resolution_y=850
cam.location=V((0,.45,-.49));aim(cam,(0,.03,.014));cam.data.ortho_scale=.555
render_png(PREV/'scale_comparison_raw.png')
exec((PACK/'source/render_driver.py').read_text(encoding='utf-8-sig').split('views=[')[0])
bpy.ops.import_scene.gltf(filepath=str(ASSETS/'openfairway_equipment/models/driver/ofg_loaner_driver.glb'))
for o in list(bpy.context.scene.objects):
    if o.name.endswith('__head') or o.name.endswith('__ferrule'):bpy.data.objects.remove(o,do_unlink=True)
cam.location=V((.205,.175,-.25));aim(cam,(0,.050,.012));cam.data.ortho_scale=.205
render_png(PREV/'shaft_fit.png')
print('COMPARISON_RENDER_COMPLETE',flush=True)
