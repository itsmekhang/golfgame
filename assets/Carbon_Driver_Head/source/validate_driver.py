"""Validate the exported GLBs against the original driver and against one another. Blender Python."""
from pathlib import Path
import json,struct,math
import numpy as np
from mathutils import Vector
from mathutils.kdtree import KDTree
PACK=Path(__file__).resolve().parents[1]
ASSETS=PACK.parent
def read(path):
 b=path.read_bytes();n=struct.unpack_from('<I',b,12)[0]
 return json.loads(b[20:20+n]),b[28+n:]
def acc(g,b,i):
 a=g['accessors'][i];v=g['bufferViews'][a['bufferView']]
 ct={5120:np.int8,5121:np.uint8,5122:np.int16,5123:np.uint16,5125:np.uint32,5126:np.float32}[a['componentType']]
 n={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']]
 offset=v.get('byteOffset',0)+a.get('byteOffset',0);stride=v.get('byteStride',n*np.dtype(ct).itemsize)
 return np.ndarray((a['count'],n),dtype=ct,buffer=b,offset=offset,strides=(stride,np.dtype(ct).itemsize)).copy()
def matrix(node):
 if 'matrix' in node:return np.array(node['matrix']).reshape(4,4).T
 x,y,z,w=node.get('rotation',[0,0,0,1])
 r=np.array([[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],
             [2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],
             [2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]])
 m=np.eye(4);m[:3,:3]=r@np.diag(node.get('scale',[1,1,1]));m[:3,3]=node.get('translation',[0,0,0])
 return m
def worlds(g):
 parents={c:i for i,n in enumerate(g['nodes']) for c in n.get('children',[])}
 def get(i):return get(parents[i])@matrix(g['nodes'][i]) if i in parents else matrix(g['nodes'][i])
 return [get(i) for i in range(len(g['nodes']))]
def transform(points,m):
 return np.c_[points,np.ones(len(points))].dot(m.T)[:,:3]
def mesh_data(g,b):
 ws=worlds(g);out=[];triangles=0;face=[]
 for i,node in enumerate(g['nodes']):
  if 'mesh' not in node:continue
  for p in g['meshes'][node['mesh']]['primitives']:
   assert all(x in p['attributes'] for x in ['POSITION','NORMAL','TEXCOORD_0','TANGENT'])
   v=transform(acc(g,b,p['attributes']['POSITION']),ws[i]);out.append(v)
   assert np.isfinite(v).all()
   tri=acc(g,b,p['indices']).ravel();assert tri.max()<len(v);triangles+=len(tri)//3
   if g['materials'][p['material']]['name'].startswith('03 |'):face.append(v)
 return np.concatenate(out),triangles,np.concatenate(face) if face else None
def named(g,suffix):
 ws=worlds(g);return next(ws[i] for i,n in enumerate(g['nodes']) if n.get('name','').endswith(suffix))
g,b=read(PACK/'driver_head_real_scale.glb')
a,ab=read(PACK/'driver_head_shaft_attachment.glb')
orig,ob=read(ASSETS/'openfairway_equipment/models/driver/ofg_loaner_driver.glb')
gv,gt,face=mesh_data(g,b);av,at,_=mesh_data(a,ab)
socket=named(g,'shaft_socket');attachment_socket=named(a,'shaft_socket')
original_socket=named(orig,'shaft_socket');original_shaft=named(orig,'__shaft')
axis=socket[:3,1];orig_axis=original_shaft[:3,1];orig_axis/=np.linalg.norm(orig_axis)
restored=transform(av,socket)
tree=KDTree(len(gv))
for i,p in enumerate(gv):tree.insert(Vector(p),i)
tree.balance()
err=max(tree.find(Vector(p))[2] for p in restored)
mesh_node=next(n for n in orig['nodes'] if n.get('name','').endswith('__shaft'))
primitive=orig['meshes'][mesh_node['mesh']]['primitives'][0]
shaft_vertices=acc(orig,ob,primitive['attributes']['POSITION'])
tip=shaft_vertices[shaft_vertices[:,1]<1e-7]
tip_diameter=float(np.max(np.linalg.norm(tip[:,[0,2]],axis=1))*2*1000)
# Least-squares measurement of the actual exported face surface, including bulge and roll.
x,y,z=face.T
fit=np.linalg.lstsq(np.column_stack([np.ones(len(x)),x,x*x,y,y*y]),z,rcond=None)[0]
measured_loft=math.degrees(math.atan(float(fit[3]+2*fit[4]*.029)))
bulge=1000/(2*fit[2]);roll=1000/(2*fit[4])
residual=float(np.max(np.abs(np.column_stack([np.ones(len(x)),x,x*x,y,y*y])@fit-z)))
bore_points=gv-socket[:3,3]
t=bore_points@axis;radial=bore_points-t[:,None]*axis
radii=np.linalg.norm(radial,axis=1)
wall=radii[(t>-.023)&(t<.011)&(abs(radii-.0047)<1e-6)]
images_embedded=all('bufferView' in im and 'uri' not in im for im in g.get('images',[]))
source=json.loads((PACK/'geometry_report.json').read_text())
report={
 'validator':'Export geometry, coordinate-frame and original-shaft measurements',
 'units':'metres','import_scale':1,
 'mesh_nodes':sum('mesh' in n for n in g['nodes']),'triangles':gt,
 'materials':len(g['materials']),'images_embedded':images_embedded,'texture_image_count':len(g.get('images',[])),
 'all_primitives_have_uv_normals_and_tangents':True,
 'contains_camera_or_animation':bool(g.get('cameras') or g.get('animations')),
 'overall_bounds_metres':{'min':gv.min(axis=0).tolist(),'max':gv.max(axis=0).tolist()},
 'sole_ground_error_metres':abs(float(gv[:,1].min())),
 'body_dimensions_mm_xyz':source['body_dimensions_mm_xyz'],
 'shaft_socket_position_error_m':float(np.linalg.norm(socket[:3,3]-original_socket[:3,3])),
 'shaft_socket_direction_error':float(np.linalg.norm(axis-orig_axis)),
 'original_driver_tip_diameter_mm':tip_diameter,
 'bore_vertex_diameter_mm':float(2*wall.mean()*1000),'bore_wall_vertices_measured':len(wall),
 'shaft_lie_degrees':math.degrees(math.atan2(axis[1],abs(axis[0]))),
 'face_center_loft_degrees_measured':measured_loft,
 'bulge_radius_mm_measured':float(bulge),'roll_radius_mm_measured':float(roll),
 'face_quadratic_fit_max_error_m':residual,
 'attachment_origin_is_zero':bool(np.linalg.norm(attachment_socket[:3,3])<1e-7),
 'attachment_positive_y_is_shaft_axis':bool(np.linalg.norm(attachment_socket[:3,1]-[0,1,0])<1e-7),
 'attachment_triangle_count_matches':gt==at,'attachment_geometry_max_error_m':err,
 'open_or_nonmanifold_edges_in_source':sum(c['nonmanifold_edges'] for c in source['components'])}
checks=[
 report['shaft_socket_position_error_m']<1e-7,report['shaft_socket_direction_error']<1e-6,
 abs(measured_loft-10.5)<.05,abs(bulge-310)<5,abs(roll-280)<5,
 len(wall)>200,abs(report['bore_vertex_diameter_mm']-9.4)<.01,
 images_embedded,report['texture_image_count']==3,gt==at,err<1e-6,
 report['attachment_origin_is_zero'],report['attachment_positive_y_is_shaft_axis'],
 report['open_or_nonmanifold_edges_in_source']==0,report['sole_ground_error_metres']<2e-6]
report['all_checks_passed']=all(checks)
(PACK/'attachment_validation.json').write_text(json.dumps(report,indent=2))
print('ATTACHMENT_VALIDATION '+json.dumps(report),flush=True)
assert all(checks),[(i,v) for i,v in enumerate(checks) if not v]
