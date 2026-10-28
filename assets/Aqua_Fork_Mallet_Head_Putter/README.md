# Aqua Fork Mallet Head

A head-only 3D game asset based on the supplied white and turquoise mallet references. The mesh has a pearl white shield crown above an open rear chamber, two turquoise rear wings with triangular through-openings, a grooved turquoise face insert with a dark perimeter, three recessed alignment dots, concentric rear weight screws, an inset sole badge, and a bent stainless shaft connection.

## Dimensions and attachment

The nominal body dimensions are **114 mm wide × 92 mm deep × 28 mm tall**, excluding the neck. The finished body measures 114 × 91.960 × 28 mm after face loft. This mallet keeps the previous heads' width and height; its deeper footprint follows the new reference.

**One model unit is one meter. Godot scale: `(1, 1, 1)`.** The head is 0.114 units wide. The shaft attachment retains the earlier heads' socket position and rotation, 9.4 mm bore, and 9.2 mm shaft-tip compatibility. The shaft lie is 71° and face loft is 3.5°.

| File | Placement |
|---|---|
| `aqua_fork_mallet_real_scale.glb` | Ground/sole origin. Replace an earlier ground-origin head at its existing transform. For the uploaded Copper Classic shaft, place it under the club root at position and rotation zero. |
| `aqua_fork_mallet_shaft_attachment.glb` | Origin at the shaft connection, with local +Y toward the grip. Use for attaching to the existing shaft tip or replacing an earlier socket-origin head. |
| `aqua_fork_mallet_real_scale.obj` + `.mtl` | Mesh and materials using the same meter scale and ground origin. |
| `source/Aqua_Fork_Mallet_Head.blend` | Editable Blender source. Use Separate by Loose Parts in Edit Mode to access the individual assembly pieces. |

The shaft connection in ground coordinates is `(-0.041, 0.070, -0.016)` meters, with direction `(-0.325568, 0.945519, 0)`. Markers are `shaft_socket`, `socket_mouth`, `socket_bottom`, and `face_center`. There is no full shaft or grip in the asset.

`attach_head.gd` provides `AquaForkMalletAttachment.attach(...)`. Its default path assumes this folder is copied into the Godot project root. Supply the shaft's lower connection position and the desired face direction. The shaft's local +Y must point toward the grip. Existing transform-based replacements can use the GLBs directly.

## Mesh and materials

The game mesh is named `putter_head_mesh`. It contains 37,522 triangles, with 19 closed assembly pieces and five PBR material surfaces. The geometry includes the eight face grooves, three alignment dots, two open wing windows, and recessed screw details. No external image textures are required.

| Material | Part |
|---|---|
| Pearl white crown | Crown, chassis, face surround, and shaft seat |
| Turquoise anodized wings | Rear wings and sole accents |
| Turquoise grooved face insert | Striking insert and alignment dots |
| Polished stainless hardware | Neck, screw weights, and dot rims |
| Graphite gaskets and sole badge | Face perimeter and underside badge |

The assembled solid components meet or overlap at their mounting areas. They are separate closed solids within one mesh object, allowing different materials and future editing. The file is a game mesh, rather than a single fused manufacturing solid.

## Validation and rebuilding

Both GLBs passed the Khronos glTF validator with zero errors and warnings. Every component has no open or nonmanifold edges. The shaft markers match the earlier heads, and the two origin versions produce the same geometry after alignment. Measured face loft is 3.5°. Validation reports are included as JSON files.

The exported GLB was inspected from the front, rear, top, and underside. The asset has not been installed into your game project. Shape and colors follow the supplied photographs; dimensions are authored for the established game scale rather than measured from manufacturer CAD.

To rebuild, run `source/build_aqua_mallet.py` in a Blender 4.3-compatible bpy/Python runtime. The script writes the GLB, OBJ, Blender source, and geometry report into this folder.
