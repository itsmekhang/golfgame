# Realistic putter head — actual 3D mesh

This is a standalone putter head with an offset plumber neck, a real bored hosel, a lofted milled face, curved heel and toe shoulders, a recessed rear cavity, three machined circular recesses, and an engraved alignment line. It contains no full shaft or grip.

The supplied CAD screenshots guide its shape. The screenshots do not provide dimensions, so the body was modeled at **114 mm wide × 40 mm front-to-back × 28 mm tall**. Overall height including the neck is approximately 80 mm. This is an original game asset with specified dimensions, rather than a manufacturer CAD file.

## Which file to use

| File | Use |
|---|---|
| `putter_head_shaft_attachment.glb` | Attach this head to the bottom of an existing shaft. The origin is at the shaft attachment point; local +Y runs up the shaft toward the grip. |
| `putter_head_real_scale.glb` | Head at its ground/sole origin, +Y up, striking face toward -Z. Its socket matches the shaft origin in the uploaded Copper Classic GLB. |
| `putter_head_real_scale.obj` and `.mtl` | Raw mesh and materials, for direct mesh editing or MeshInstance3D workflows. Same meter scale and ground origin as the GLB. |
| `source/Realistic_Putter_Head.blend` | Editable Blender source with applied geometry and materials. |

**One model unit is one meter. Keep import scale and node scale at `(1, 1, 1)`.** A head should span 0.114 units across the face; an 114-unit-wide import has been interpreted as millimeters incorrectly.

## Existing Copper Classic shafts

For the uploaded `ofg_copper_classic.glb`, remove its old head and head decorations while keeping the shaft and grip. Add `putter_head_real_scale.glb` under the same unscaled club root at position `(0, 0, 0)` and rotation `(0, 0, 0)`.

The shaft origin is `(-0.041, 0.070, -0.016)` meters. The shaft direction is `(-0.325568, 0.945519, 0)`, matching the uploaded model's 71° lie. The connector bore is 9.4 mm in diameter and receives that model's 9.2 mm shaft tip. The neck includes the collar, so remove the old ferrule if it overlaps the new collar.

Other clubs can use the attachment-origin version. Place its root at the shaft's bottom/origin and align the head's local +Y with the shaft direction. Rotate it around that axis until the striking face points toward the ball. The body should remain at the intended lie angle; do not flatten it by scaling an axis.

The included `attach_head.gd` helper aligns an attachment-origin head using a shaft node and a desired world-space face direction. It assumes the shaft's local +Y points toward the grip and its origin is at the shaft's lower tip, which is true of the uploaded club. For a center-origin cylinder, supply the actual bottom position instead.

## Mesh structure

There is one MeshInstance3D named `putter_head_mesh`, with stainless steel, recessed steel, and sightline material slots. All shape details are modeled geometry. The black sightline is a small separate closed component inside that mesh. You can override its materials for copper, brass, or black club variants while sharing the same geometry.

Markers: `shaft_socket`, `socket_mouth`, `socket_bottom`, and `face_center`. The face marker includes the 3.5° loft rotation. There are no animation, billboard, camera, or light nodes.

The 3.5° face loft is a design reference from the [manufacturer's published Newport 2 specifications](https://www.scottycameron.com/putters/super-select/newport-2/). The body dimensions and neck were authored for this asset; the 71° lie and attachment location match the supplied club rather than the manufacturer's standard 70° lie.

See `geometry_report.json`, `glTF_validation.json`, and `attachment_validation.json` for measured mesh dimensions and checks. The GLBs were reimported for validation and visual inspection. The asset has not been installed into your game project.

To rebuild: run `source/build_realistic_head.py` in a Blender 4.3-compatible bpy/Python runtime. The script exports both origin conventions plus OBJ and Blender files beside this README.
