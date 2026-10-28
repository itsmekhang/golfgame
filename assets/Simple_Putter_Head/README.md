# Simple putter head

A standalone 3D head based on your latest references: a plain face, broad heel and toe weights, an open rear cavity, rounded outer edges, and a straight plumber neck with a short top offset. One continuous closed mesh, one brushed steel material, 1,396 triangles.

**Same body size: 114 mm wide × 40 mm deep × 28 mm tall.** The shaft socket position, orientation, and 9.4 mm bore are identical to the previous head. The bore accommodates the existing 9.2 mm shaft tip. The model includes the head, neck, and collar.

## Files

| File | Placement |
|---|---|
| `simple_putter_head_real_scale.glb` | Ground/sole origin. Replace the previous ground-origin head at the same position and rotation. For the uploaded Copper Classic shaft, add it to the club root at position and rotation zero. |
| `simple_putter_head_shaft_attachment.glb` | Origin at the shaft connection. Local +Y points toward the grip. Replace the previous attachment-origin head with the same transform. |
| `simple_putter_head_real_scale.obj` + `.mtl` | Raw mesh and material, using the same meter scale and ground origin. |
| `source/Simple_Putter_Head.blend` | Editable Blender source. |

**Godot scale: `(1, 1, 1)`. One unit is one meter.** The head's width is 0.114 model units. Avoid scaling individual axes to fit the shaft.

The shaft connection in ground coordinates is `(-0.041, 0.070, -0.016)` meters, with direction `(-0.325568, 0.945519, 0)`. The socket bore, collar dimensions, 71° lie, and attachment markers are retained. The face has 3.5° loft; `face_center` follows the new plain face.

`attach_head.gd` provides `SimplePutterHeadAttachment.attach(...)` for attaching the socket-origin model to a shaft. Its default path assumes this folder is copied into the Godot project root. It expects the shaft origin at its lower tip and local +Y pointing toward the grip. Existing transform-based replacements can use the GLBs directly.

The single MeshInstance3D is named `putter_head_mesh`. Other nodes are attachment markers: `shaft_socket`, `socket_mouth`, `socket_bottom`, and `face_center`. Override the material to create other club finishes while reusing the geometry.

Both GLBs passed glTF validation with zero errors and warnings. The mesh has no open/nonmanifold edges, and the socket transforms were compared against the previous head. The two origin versions were checked for identical geometry after alignment. This asset was inspected from the exported GLB; it has not been installed into your game project.

To rebuild, run `source/build_simple_head.py` using a Blender 4.3-compatible bpy/Python runtime. See the JSON reports for measured geometry and validation results.
