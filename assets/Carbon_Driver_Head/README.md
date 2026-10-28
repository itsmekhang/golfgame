# OFG D2 Carbon Driver Head

A second, separately authored driver head built in Blender from the two supplied AI meshes and the local driver photographs. The design combines a broad pear-shaped carbon crown, a crimson woven face, a slim scarlet perimeter, a flowing heel hosel, and a sculpted sole with two recessed hex-drive weights. The sole has a carbon shield, a graphite center keel, titanium strakes, and a recessed channel behind the face. OFG/D2 markings are original.

## Open the model

| File | Purpose |
|---|---|
| `source/Carbon_Driver_Head.blend` | Editable Blender source with 21 named components, metric units, and packed textures. |
| `driver_head_real_scale.glb` | Ground-origin game asset; import at scale **1, 1, 1**. |
| `driver_head_shaft_attachment.glb` | Socket-origin asset with local +Y pointing along the shaft. |
| `driver_head_real_scale.obj` and `.mtl` | Interchange mesh; keep the `textures` directory alongside it. |
| `preview_sheet.png` | Six views of the exported GLB. |
| `scale_comparison.png` | D2, the existing D1, and the fairway wood at identical scale. |
| `previews/shaft_fit.png` | D2 placed on the unchanged original driver shaft. |
| `previews/Carbon_Driver_Studio.blend` | Studio scene containing the imported GLB. |
| `attach_head.gd` | Optional Godot socket-attachment helper, `CarbonDriverHeadAttachment`. |

This package is an additional design option. The active game replacement is the user-selected `assets/Selected_Club_Heads/Driver_Head.glb`.

## Scale and fitting

**One unit is one meter.** The shell measures **126.08 mm wide × 112.61 mm deep × 59.00 mm high**. Including the sole keel, the head is **60.00 mm high**, excluding the hosel and ferrule. The comparison heads are D1 at 124 mm wide and the fairway wood at 106 mm wide.

The fitting matches `openfairway_equipment/models/driver/ofg_loaner_driver.glb`:

- Socket position in Godot coordinates: **(-0.0546, 0.074, -0.013) m**.
- Shaft axis: **(-0.484810, 0.874620, 0)**; lie **61°**.
- Bore **9.4 mm**, for the original **9.2 mm** shaft tip.
- Center face loft **10.5°**; horizontal bulge radius **310 mm**; vertical roll radius **280 mm**.
- Ground export: +Y up, face toward -Z, heel toward -X, sole contact at Y = 0.
- Overall bounds including the hosel/ferrule: approximately **131.08 × 88.50 × 112.61 mm**, in X/Y/Z order.

The model includes its ferrule. For a future game replacement, remove the old head and ferrule and insert the ground-origin GLB at the original club root with identity transform. Keep the original shaft and grip. The socket variant instead uses the included attachment helper. Its mesh child carries the coordinate transform so both GLBs retain identical mesh data without another floating-point bake.

Markers are `shaft_socket`, `socket_mouth`, `socket_bottom`, and `face_center`.

## Geometry and materials

- **71,624 triangles**, one exported mesh node, **10 materials**, and **3 embedded texture images**.
- **18 recessed scoreline segments**, 0.4 mm wide and 0.23 mm deep.
- The carbon weave uses color and tangent-normal textures, with clearcoat on the crown and face.
- All 21 source components are closed, with **zero boundary or nonmanifold edges**.
- The two supplied AI OBJs contain 500,000 triangles each. Their silhouettes were inspected from four angles; the final smooth geometry was rebuilt, including the sole, lofted face, bore, and hardware.

GLB retains the complete PBR finish. OBJ/MTL preserves the mesh and basic materials, with more limited clearcoat/specular support.

## Verification

Both GLBs pass the **Khronos glTF Validator with zero errors and zero warnings**. The validator's informational notes concern unused UV/tangent channels on untextured materials and intentional empty attachment markers.

Measurements from the exported model confirm:

- Original socket position error: **0 m**.
- Shaft-axis error: **7.64e-8**.
- Center face loft: **10.4999°**.
- Ground-contact error: **0 m**.
- Maximum difference between aligned origin variants: **8.33e-9 m**.
- Every primitive has normals, UVs, and valid tangent data; textures are embedded.

Detailed measurements are in `geometry_report.json`, `attachment_validation.json`, and `glTF_validation.json`. The head is an authored visual game asset; its shape and finishes are reference-guided rather than manufacturer CAD.

## References and rebuild

References inspected:

- `C:/Users/willi/Downloads/driver 1.obj`
- `C:/Users/willi/Downloads/driver/base.obj`
- `image reference/taylormade-stealth-2-driver.jpg`
- `image reference/driver stealth.jpg`
- `image reference/driver reference 1.png`, `driver reference 2.webp`, `driver reference 3.avif`, and `driver reference 4.png`

Built using Blender **5.2.1 LTS**. From the project root, with Blender on PATH:

```text
blender -b -t 6 --python assets/Carbon_Driver_Head/source/build_carbon_driver.py
blender -b --python assets/Carbon_Driver_Head/source/validate_driver.py
node assets/Carbon_Driver_Head/source/validate_glb.mjs
blender -b -t 6 --python assets/Carbon_Driver_Head/source/render_driver.py -- all
blender -b -t 6 --python assets/Carbon_Driver_Head/source/render_comparison.py
python assets/Carbon_Driver_Head/source/make_preview_sheet.py
```

The builder uses Blender's bundled Python modules and the included geometry helpers. The sheet script requires Pillow. The glTF check uses the Khronos `gltf-validator` npm package; set `GLTF_VALIDATOR_MODULE` to its module path on another machine.
