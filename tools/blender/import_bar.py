"""Prepare the supplied bottle shelving as a reusable textured back-bar module."""
import bpy,math,os
from mathutils import Matrix,Vector
HERE=os.path.dirname(os.path.abspath(__file__))
ROOT=os.path.abspath(HERE+'/../..') if os.path.exists(HERE+'/fm_lib.py') else 'C:/Users/willi/Documents/GolfGame'
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=ROOT+'/tools/blender/sources/bar_with_bottles.glb')
obs=[o for o in bpy.data.objects if o.type=='MESH' and 'polka' in o.name.lower()]
for o in list(bpy.data.objects):
 if o not in obs:bpy.data.objects.remove(o,do_unlink=True)
points=[o.matrix_world@v.co for o in obs for v in o.data.vertices]
lo=Vector([min(p[k] for p in points) for k in range(3)]);hi=Vector([max(p[k] for p in points) for k in range(3)])
scale=1.35/(hi.z-lo.z)
width=(hi.y-lo.y)*scale
xf=Matrix.Diagonal((1/width,1,1,1))@Matrix.Rotation(math.pi/2,4,'Z')@Matrix.Scale(scale,4)@Matrix.Translation((-((lo.x+hi.x)/2),-((lo.y+hi.y)/2),-lo.z))
before=sum(len(p.vertices)-2 for o in obs for p in o.data.polygons)
for o in obs:
 world=o.matrix_world.copy();o.parent=None;o.data.transform(xf@world);o.matrix_world=Matrix.Identity(4)
 if len(o.data.polygons)>250:
  bpy.context.view_layer.objects.active=o
  dec=o.modifiers.new('Bottle display LOD','DECIMATE');dec.ratio=.45
  bpy.ops.object.modifier_apply(modifier=dec.name)
# Keep the supplied shelving's UV grain but give it a dark oak finish.
for mat in obs[0].data.materials:
 mat.name='Dark_Oak'
 if not mat.use_nodes:continue
 nodes=mat.node_tree.nodes;links=mat.node_tree.links
 bsdf=next(n for n in nodes if n.type=='BSDF_PRINCIPLED')
 color=bsdf.inputs['Base Color']
 if color.is_linked:
  old=color.links[0].from_socket
  multiply=nodes.new('ShaderNodeMixRGB');multiply.blend_type='MULTIPLY';multiply.inputs[0].default_value=1
  multiply.inputs[2].default_value=(.38,.27,.17,1)
  links.new(old,multiply.inputs[1]);links.new(multiply.outputs[0],color)
 bsdf.inputs['Roughness'].default_value=.62
# Each original bottle is a few hundred triangles. Keep all twenty variants
# and their label UVs, grouping a bottle's transparent overlays with its body.
before_objects=set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=ROOT+'/tools/blender/sources/20_liquor_bottles.glb')
new=[o for o in bpy.data.objects if o not in before_objects and o.type=='MESH']
groups={}
for o in new:
 key=o.name.split('_Atlas')[0].split('_Sprite')[0]
 groups.setdefault(key,[]).append(o)
counter_groups={'DARK':[], 'CLEAR':[]}
categories={'DARK':['Chivas',"Jack_Daniel's",'Jameson'],'CLEAR':['Absolut_Vodka','Beefeater','Cointreau']}
for i,(key,parts) in enumerate(sorted(groups.items())):
 points=[o.matrix_world@v.co for o in parts for v in o.data.vertices]
 low=Vector([min(p[k] for p in points) for k in range(3)]);high=Vector([max(p[k] for p in points) for k in range(3)])
 center=(low+high)*.5
 row=i//7;column=i%7;count=min(7,len(groups)-row*7)
 # The source is arranged radially. Rotate every label toward the bar aisle.
 angle=math.pi/2-math.atan2(center.y,center.x)
 sc=.0128
 x=(-.5+(column+.5)/count)*width*.88
 target=Vector((x,.025,(.058,.488,.920)[row]))
 transform=Matrix.Diagonal((1/width,1,1,1))@Matrix.Translation(target)@Matrix.Rotation(angle,4,'Z')@Matrix.Scale(sc,4)@Matrix.Translation((-center.x,-center.y,-low.z))
 for o in parts:
  world=o.matrix_world.copy()
  for category,names in categories.items():
   if key in names:
    bottle=o.copy();bottle.data=o.data.copy();bpy.context.scene.collection.objects.link(bottle);bottle.parent=None
    counter_x=(names.index(key)-1)*.155
    counter_xf=Matrix.Translation((counter_x,0,.012))@Matrix.Rotation(angle,4,'Z')@Matrix.Scale(sc,4)@Matrix.Translation((-center.x,-center.y,-low.z))
    bottle.data.transform(counter_xf@world);bottle.matrix_world=Matrix.Identity(4);counter_groups[category].append(bottle)
  o.parent=None;o.data.transform(transform@world);o.matrix_world=Matrix.Identity(4);obs.append(o)
for mat in bpy.data.materials:
 if mat.name.startswith('Atlas') and mat.use_nodes:
  bsdf=next((n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None)
  if bsdf:
   for link in list(bsdf.inputs['Alpha'].links):mat.node_tree.links.remove(link)
   bsdf.inputs['Alpha'].default_value=1.0
   bsdf.inputs['Roughness'].default_value=.26
for img in bpy.data.images:
 if img.size[0]>2048 or img.size[1]>2048:
  ratio=2048/max(img.size);img.scale(round(img.size[0]*ratio),round(img.size[1]*ratio))
# Export small, ordered countertop sets separately from the wall cabinets.
for category,items in counter_groups.items():
 bpy.ops.object.select_all(action='DESELECT')
 for item in items:item.select_set(True)
 bpy.context.view_layer.objects.active=items[0]
 bpy.ops.object.join();bpy.context.object.name='Counter_'+category
 bpy.ops.export_scene.gltf(filepath=ROOT+'/assets/facilities/props/bar_counter_'+category.lower()+'.glb',export_format='GLB',use_selection=True,export_yup=True)
for o in list(bpy.data.objects):
 if o not in obs:bpy.data.objects.remove(o,do_unlink=True)
bpy.ops.object.select_all(action='DESELECT')
for o in obs:o.select_set(True)
bpy.context.view_layer.objects.active=obs[0]
bpy.ops.object.join();ob=bpy.context.object;ob.name='BottleBarShelf'
# Embedded source UVs and bottle-label textures are preserved.
out=ROOT+'/assets/facilities/props/bar_bottles.glb'
bpy.ops.export_scene.gltf(filepath=out,export_format='GLB',use_selection=True,export_yup=True)
print('BAR MODULE',len(groups),'bottle variants;',sum(len(p.vertices)-2 for p in ob.data.polygons),'triangles; width 1, height 1.35, native module width',width,flush=True)
# A wine glass from the supplied bar, reused upside down on the stemware rack.
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=ROOT+'/tools/blender/sources/bar_with_bottles.glb')
glass=next(o for o in bpy.data.objects if o.name=='Object022_glass_0')
world=glass.matrix_world.copy();glass.parent=None;glass.data.transform(world);glass.matrix_world=Matrix.Identity(4)
lo=Vector([min(v.co[k] for v in glass.data.vertices) for k in range(3)]);hi=Vector([max(v.co[k] for v in glass.data.vertices) for k in range(3)])
glass.data.transform(Matrix.Scale(.23/(hi.z-lo.z),4)@Matrix.Translation((-((lo.x+hi.x)/2),-((lo.y+hi.y)/2),-lo.z)))
for mat in glass.data.materials:
 mat.name='Stemware_Glass'
 if mat.use_nodes:
  bsdf=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
  for socket in ('Base Color','Alpha'):
   for link in list(bsdf.inputs[socket].links):mat.node_tree.links.remove(link)
  bsdf.inputs['Base Color'].default_value=(.70,.85,.9,1)
  bsdf.inputs['Alpha'].default_value=.42
  bsdf.inputs['Roughness'].default_value=.16
  bsdf.inputs['Metallic'].default_value=.12
bpy.ops.object.select_all(action='DESELECT');glass.select_set(True)
bpy.context.view_layer.objects.active=glass
bpy.ops.export_scene.gltf(filepath=ROOT+'/assets/facilities/props/bar_wine_glass.glb',export_format='GLB',use_selection=True,export_yup=True)
