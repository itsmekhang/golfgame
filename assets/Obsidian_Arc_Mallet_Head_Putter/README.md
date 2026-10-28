# Obsidian Arc Mallet Head

A satin black half-moon mallet with a deep rear scoop, sculpted shoulders, an ivory bow-shaped crown inlay, 32 physical face grooves, a white underside perimeter arc, and a green-edged ARC cavity badge. The neck has a black offset support and stainless socket.

This is a head-only 3D asset for the golf game, including the neck and socket. Attach it to your existing shaft and grip.

## Scale and files

The main body and its inlays are authored at 114 mm wide × 72 mm deep × 28 mm tall. The neck is excluded from those body dimensions.

**One model unit is one meter. Godot import scale: `(1, 1, 1)`.** Each model is 0.114 units wide. The shaft connection retains the earlier heads' position, orientation, and 9.4 mm bore for the existing 9.2 mm shaft tip. Shaft lie is 71°, and the striking-face lands have 3.5° loft.

| File | Placement |
|---|---|
| `obsidian_arc_mallet_real_scale.glb` | Ground/sole origin. Replace an earlier ground-origin head at its existing transform. For the uploaded Copper Classic shaft, place it under the club root with position and rotation zero. |
| `obsidian_arc_mallet_shaft_attachment.glb` | Origin at the shaft socket; local +Y points toward the grip. Attach to the lower shaft connection or replace an earlier socket-origin model using its transform. |
| `obsidian_arc_mallet_real_scale.obj` + `.mtl` | Mesh and materials in meters, using the ground origin. |
| `source/Obsidian_Arc_Mallet_Head.blend` | Editable Blender source. Use Separate by Loose Parts in Edit Mode to access individual solid pieces. |

The shaft connection in ground coordinates is `(-0.041, 0.070, -0.016)` meters, with direction `(-0.325568, 0.945519, 0)`. The markers are `shaft_socket`, `socket_mouth`, `socket_bottom`, and `face_center`.

`attach_head.gd` provides `ObsidianArcMalletAttachment.attach(...)`. Its default path assumes this folder is copied into the Godot project root. Pass the shaft's lower connection position and the desired face direction. The shaft's local +Y must point toward the grip. Existing transform-based replacements can use the GLBs directly.

## Geometry and validation

The game mesh is named `putter_head_mesh`. It contains 25,040 triangles, 11 closed connected components, and 5 PBR material surfaces. Lettering and detailing are modeled geometry. No external image textures are required. Separate solid components meet or overlap at their mounting areas within the assembled game mesh.

Both GLBs passed the Khronos glTF validator with zero errors and warnings. Every component has no open or nonmanifold edges. Shaft markers match the earlier heads. The two origin variants produce the same geometry after alignment, and the milled face lands were checked for 3.5° loft. The JSON files include the measured geometry and validation results.

The exported model was visually inspected from the front, rear, top, and underside. It has not been installed into your game project. Dimensions are authored for the established game scale; the supplied photographs guide the appearance and do not provide measured manufacturer CAD.

To rebuild, run `source/build_obsidian_arc.py` in a Blender 4.3-compatible bpy/Python runtime. The script writes its GLB, OBJ, Blender source, and geometry report into this folder.
