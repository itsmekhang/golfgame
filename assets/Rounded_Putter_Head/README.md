# Rounded putter head

A standalone 3D putter head based on the rounded reference: an oval outer outline, domed heel and toe weights, a scooped rear cavity, one wide oval recess, and a flowing neck with a hollow shaft socket. The striking face remains flat with 3.5° loft. One continuous closed mesh, one satin stainless steel material, 10,058 triangles.

**Same body size: 114 mm wide × 40 mm deep × 28 mm tall.** The body dimensions exclude the neck. The shaft socket position, orientation, and 9.4 mm bore match the previous heads. The bore accommodates the existing 9.2 mm shaft tip. This asset includes the head, neck, and collar; attach it to your existing shaft.

## Files

| File | Placement |
|---|---|
| `rounded_putter_head_real_scale.glb` | Ground/sole origin. Replace a previous ground-origin head using the same position and rotation. For the uploaded Copper Classic shaft, add it to the club root at position and rotation zero. |
| `rounded_putter_head_shaft_attachment.glb` | Origin at the shaft connection. Local +Y points toward the grip. Replace a previous attachment-origin head using the same transform. |
| `rounded_putter_head_real_scale.obj` + `.mtl` | Mesh and material in meters, with the ground origin. |
| `source/Rounded_Putter_Head.blend` | Editable Blender source with the ground origin. |

**Godot scale: `(1, 1, 1)`. One unit is one meter.** The head is 0.114 model units wide. Keep the scale uniform when attaching it.

The shaft connection in ground coordinates is `(-0.041, 0.070, -0.016)` meters, with direction `(-0.325568, 0.945519, 0)`. The shaft lie is 71°. Socket markers are identical to the earlier heads; `face_center` follows this model's face.

`attach_head.gd` provides `RoundedPutterHeadAttachment.attach(...)` for the socket-origin model. Its default path assumes this folder is copied into the Godot project root. Supply the shaft's lower connection position and the desired face direction. The shaft's local +Y must point toward the grip. Existing transform-based replacements can use the GLBs directly.

The single mesh is named `putter_head_mesh`. Attachment markers are `shaft_socket`, `socket_mouth`, `socket_bottom`, and `face_center`. Override the material to create other club finishes while reusing the geometry.

## Validation and source

Both GLBs passed the Khronos glTF validator with zero errors and warnings. The Blender mesh has one connected component and no open or nonmanifold edges. The shaft markers were compared with the previous head, and both origin versions were checked for identical geometry after alignment. The measured striking-face loft is 3.5°. The exported model was visually inspected from the front, rear, and top. It has not been installed into your game project.

This is a game asset authored to the established dimensions, using the photograph as a shape reference. The photograph does not supply measured manufacturing dimensions.

To rebuild, run `source/build_rounded_head.py` in a Blender 4.3-compatible bpy/Python runtime. Geometry, attachment, and glTF validation results are included as JSON files. The source script writes into this folder.
