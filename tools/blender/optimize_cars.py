"""Build lighter runtime cars, preserving the original models in the parent folder.
Run Blender in background with this script. No placement, scale or material names change.
"""
from pathlib import Path
import bpy,json

ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/'assets/facilities/props/cars'
OUTPUT=SOURCE/'lite'
OUTPUT.mkdir(exist_ok=True)
report=[]
for path in sorted(SOURCE.glob('car_*.glb')):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(path))
    meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
    before=sum(len(p.vertices)-2 for o in meshes for p in o.data.polygons)
    for ob in meshes:
        bpy.context.view_layer.objects.active=ob
        modifier=ob.modifiers.new('Lighter car geometry','DECIMATE')
        modifier.ratio=.60
        modifier.use_collapse_triangulate=True
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    for img in bpy.data.images:
        if img.size[0] == 0: continue
        limit=256 if 'wheel' in img.name.lower() or 'wheek' in img.name.lower() else 512
        longest=max(img.size)
        if longest>limit:
            img.scale(max(1,round(img.size[0]*limit/longest)),max(1,round(img.size[1]*limit/longest)))
            img.pack()  # Encode resized pixels instead of reusing original packed bytes.
    after=sum(len(p.vertices)-2 for o in meshes for p in o.data.polygons)
    out=OUTPUT/path.name
    bpy.ops.export_scene.gltf(filepath=str(out),export_format='GLB',export_image_format='AUTO')
    entry={'model':path.stem,'source_triangles':before,'runtime_triangles':after,'source_bytes':path.stat().st_size,'runtime_bytes':out.stat().st_size}
    report.append(entry)
    print('CAR OPTIMIZED',entry)
(OUTPUT/'optimization.json').write_text(json.dumps(report,indent=2))
