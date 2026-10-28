"""Fit the supplied club head without deforming it or changing existing shafts.

Run with Blender --background --python tools/fit_iron_heads.py -- [--family wedge] [--render].
Outputs replacements to build/<family>-refit; it never overwrites game assets.
The OBJ's original shaft defines the head socket and orientation. All head vertices
receive ONE positive uniform scale, rotation and translation, preserving its shape.
"""
from pathlib import Path
import argparse
import json
import math
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

PROJECT = Path(__file__).resolve().parents[1]
PACK_SOURCE = PROJECT / 'assets/OpenFairway_Equipment_v1/source'
sys.path.insert(0, str(PACK_SOURCE))
from build_models import head_material
from catalog_source import CATALOG

RUNTIME = PROJECT / 'assets/openfairway_equipment/models'


def world_points(obj):
    return np.array([obj.matrix_world @ v.co for v in obj.data.vertices], dtype=np.float64)


def unit(v):
    v = np.asarray(v, dtype=np.float64)
    return v / np.linalg.norm(v)


def load_reference(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.wm.obj_import(filepath=str(path))
    head = bpy.data.objects['HEAD002']
    points = world_points(head)
    shaft = world_points(bpy.data.objects['SHAFT002'])
    grip = world_points(bpy.data.objects['GRIP002'])
    _, axes = np.linalg.eigh(np.cov(shaft.T))
    up = axes[:, -1]
    if np.dot(up, grip.mean(axis=0) - points.mean(axis=0)) < 0:
        up = -up
    # The flat socket cap is perpendicular to the authored shaft axis. Select its
    # actual ring, not an arbitrary band at the top of an axis-aligned bounding box.
    heights = points @ up
    ring = points[heights > heights.max() - 0.02]
    socket = ring.mean(axis=0)
    radial = ring - socket
    radial -= np.outer(radial @ up, up)
    socket_radius = np.linalg.norm(radial, axis=1).max()
    face = max(head.data.polygons, key=lambda p: p.area)
    normal = unit(np.array(head.matrix_world.to_3x3() @ face.normal))
    face_point = np.array(head.matrix_world @ face.center)
    # Baking the import's axis rotation before fitting avoids mirroring either axis.
    mesh = head.data.copy()
    mesh.transform(head.matrix_world)
    mesh.materials.clear()
    mesh.use_fake_user = True
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    return mesh, points, up, socket, socket_radius, normal, face_point, ring


def fit_rotation(source_up, source_face, target_up):
    cosine = float(np.dot(source_up, source_face))
    # Keep the striking face square across the club (+Y in Blender, -Z in Godot).
    # Its loft comes from the source head; do not flatten it to a target bounding box.
    face_z = cosine / target_up[2]
    if abs(face_z) >= 1.0:
        raise ValueError('Source face cannot meet this shaft lie without deformation')
    target_face = np.array([0.0, math.sqrt(1.0 - face_z * face_z), face_z])
    source_front = unit(source_face - source_up * cosine)
    target_front = unit(target_face - target_up * np.dot(target_face, target_up))
    source_basis = np.column_stack([np.cross(source_up, source_front), source_up, source_front])
    target_basis = np.column_stack([np.cross(target_up, target_front), target_up, target_front])
    rotation = target_basis @ source_basis.T
    assert np.linalg.det(rotation) > 0.99999, 'Head fitting must not mirror the mesh'
    return rotation


def map_finish(head, original, source_socket, source_up, face_normal):
    """Project the finish onto the body; the long hosel stays polished steel."""
    points = np.array([v.co for v in head.data.vertices])
    axial = (original - source_socket) @ source_up
    body = points[axial < -30.0]
    face_up = unit(np.cross(np.array([1.0, 0.0, 0.0]), face_normal))
    if face_up[2] < 0:
        face_up = -face_up
    lo_x, hi_x = body[:, 0].min(), body[:, 0].max()
    projected = body @ face_up
    lo_v, hi_v = projected.min(), projected.max()
    uv = head.data.uv_layers.active or head.data.uv_layers.new(name='UVMap')
    for polygon in head.data.polygons:
        if axial[list(polygon.vertices)].mean() > -30.0:
            for loop in polygon.loop_indices:
                uv.data[loop].uv = (0.96, 0.06)
            continue
        facing = np.dot(polygon.normal, face_normal)
        region = 1 if facing > 0.45 else (3 if facing < -0.45 else (0 if polygon.normal.z > 0.1 else 2))
        for loop in polygon.loop_indices:
            point = points[head.data.loops[loop].vertex_index]
            u = float(np.clip((point[0] - lo_x) / (hi_x - lo_x), 0, 1))
            v = float(np.clip((np.dot(point, face_up) - lo_v) / (hi_v - lo_v), 0, 1))
            uv.data[loop].uv = (0.5 * (region % 2) + 0.018 + 0.464 * u,
                                (0.5 if region < 2 else 0.0) + 0.018 + 0.464 * v)


def build(args):
    selected = [c for c in CATALOG if c['family'] == args.family]
    if args.output is None:
        args.output = PROJECT / 'build' / (args.family + '-refit')
    args.output.mkdir(parents=True, exist_ok=True)
    model_dir = args.output / 'models'
    model_dir.mkdir(exist_ok=True)
    mesh, original, source_up, source_socket, radius, face, face_point, ring = load_reference(args.source)
    results = []
    for item in selected:
        model_id = item['id']
        stem = 'ofg_' + model_id
        bpy.ops.import_scene.gltf(filepath=str(RUNTIME / args.family / (stem + '.glb')))
        root = bpy.data.objects[stem]
        shaft = bpy.data.objects[stem + '__shaft']
        old_head = bpy.data.objects[stem + '__head']
        # GLB +Y is converted to Blender +Z at import. The existing shaft's local Z
        # is its length axis; normalize it so shaft length never squashes the head.
        target_up = unit(np.array(shaft.matrix_world.to_3x3() @ Vector((0, 0, 1))))
        target_socket = np.array(shaft.matrix_world.translation)
        tip_points = np.array([v.co for v in shaft.data.vertices])
        tip = tip_points[tip_points[:, 2] < tip_points[:, 2].min() + 0.00001]
        tip_world = np.array([shaft.matrix_world @ Vector(v) for v in tip])
        tip_radius = np.linalg.norm(np.cross(tip_world - target_socket, target_up), axis=1).max()
        scale = float(tip_radius / radius)
        rotation = fit_rotation(source_up, face, target_up)
        linear = rotation * scale
        translation = target_socket - linear @ source_socket
        transform = Matrix(linear.tolist()).to_4x4()
        transform.translation = Vector(translation)
        fitted = original @ linear.T + translation
        # Verify distances throughout the mesh, including the neck and sole. An
        # axis squeeze, shear or a inherited shaft scale cannot pass this check.
        source_lengths = np.linalg.norm(original - original[0], axis=1)
        fitted_lengths = np.linalg.norm(fitted - fitted[0], axis=1)
        error = float(np.max(np.abs(fitted_lengths - source_lengths * scale)))
        ring_fitted = ring @ linear.T + translation
        seam_error = float(np.linalg.norm(ring_fitted.mean(axis=0) - target_socket))
        assert error < 1e-7 and seam_error < 1e-7, (error, seam_error)
        assert np.dot(rotation @ source_up, target_up) > 0.999999
        bpy.data.objects.remove(old_head, do_unlink=True)
        head = bpy.data.objects.new(stem + '__head', mesh.copy())
        bpy.context.collection.objects.link(head)
        head.data.name = stem + '__head_geometry'
        head.data.use_fake_user = False
        head.data.transform(transform)
        head.data.update()
        head.parent = root
        head.matrix_world = Matrix.Identity(4)
        # The replacement OBJ uses unrelated UVs and glass-like MTL settings. Map
        # the preserved club finish atlas onto the fitted head and keep solid steel.
        map_finish(head, original, source_socket, source_up, rotation @ face)
        head.data.materials.clear()
        head.data.materials.append(head_material(item))
        for polygon in head.data.polygons:
            polygon.material_index = 0
        head['base_mesh_family'] = item['family']
        head['fit_method'] = 'uniform_scale_socket_alignment'
        # This head has a lofted back. A lower orbit reveals it instead of looking
        # along its edge. Both the runtime inspector and studio renders read this.
        root['rear_view_yaw'] = 0.45
        root['rear_view_pitch'] = 0.45
        face_marker = bpy.data.objects[stem + '__face_center']
        face_marker.location = Vector(linear @ face_point + translation)
        # The new head may extend slightly below the previous sole. Move the whole
        # assembly together to keep it grounded; preserve every relative join.
        ground_shift = -float(fitted[:, 2].min())
        for child in root.children:
            child.location.z += ground_shift
        bpy.ops.object.select_all(action='DESELECT')
        root.select_set(True)
        for child in root.children_recursive:
            child.select_set(True)
        path = model_dir / (stem + '.glb')
        bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB', use_selection=True,
                                 export_yup=True, export_animations=False, export_extras=True,
                                 export_tangents=True)
        head.data.calc_loop_triangles()
        result = dict(id=model_id, uniform_scale=scale, distance_error_m=error,
                      socket_error_m=seam_error, shaft_alignment_dot=float(np.dot(rotation @ source_up, target_up)),
                      head_dimensions_m=np.ptp(fitted, axis=0).tolist(), head_triangles=len(head.data.loop_triangles),
                      ground_shift_m=ground_shift, socket_radius_m=tip_radius)
        results.append(result)
        print('FITTED', json.dumps(result), flush=True)
        for obj in list(bpy.data.objects):
            bpy.data.objects.remove(obj, do_unlink=True)
    (args.output / 'fit_report.json').write_text(json.dumps(results, indent=2))
    if args.render:
        from render_models import render
        for item in selected:
            render(item['id'], back=True, model_path=model_dir / ('ofg_' + item['id'] + '.glb'),
                   output_dir=args.output / 'previews')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=PACK_SOURCE / 'iron_reference/golf stick.obj')
    parser.add_argument('--family', choices=['iron', 'wedge'], default='iron')
    parser.add_argument('--output', type=Path)
    parser.add_argument('--render', action='store_true')
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    build(parser.parse_args(argv))
