# Fairway Wood Head — 3-wood (revision 3, combined with a reference mesh)

A head-only fairway wood mesh combining a downloaded reference model with a procedurally authored hosel/ferrule calibrated to the game's exact shaft socket. It has a gloss-black crown, a satin scored face insert framed by a gloss-black bezel, a sole with a real moulded weight-port carried over from the reference scan, a short tapered hosel, and a black ferrule.

## Where the shape comes from

The user supplied a downloaded reference model (`base.glb`/`base.obj`, also delivered a second time as "fairway woods.glb"/".obj" — byte-identical to the first copy) containing two full clubs. That file's own vertex welds were broken: thousands of coincident-but-unmerged duplicate vertices along every UV seam, a common export artifact. It needed a "Merge by Distance" pass in Blender before it would even separate into its two distinct clubs. The better-proportioned of the two heads (a complete crown with real scorelines and a sole weight-port already sculpted in) was then cropped away from its shaft with a plane bisect and reoriented from the source scene's arbitrary pose into this project's convention (sole at y=0, face toward -Z, toe toward +X), using the mesh's own geometry as the reference axes — the sole's flat region and the striking face's flat region, found as the two largest near-planar polygon clusters — rather than any assumption about the source file's own orientation. That result is committed as `source/reference_head.glb` so a rebuild does not depend on the much larger, messier original download.

`build_fairway_wood.py` imports that shell, scales it, flattens its face region onto a true plane, positions a freshly authored hosel/ferrule at the exact shaft socket the game's fairway wood shafts already use, and re-derives the crown/face/sole material split from the finished geometry. The scorelines and the sole's weight-port sculpting are the reference mesh's own geometry, not re-authored.

**A pure hand-authored procedural revision with no reference-mesh dependency also exists**, as `source/build_fairway_wood_procedural.py`, and is the one used if this combined revision's remaining imperfection (below) is not acceptable. Both were checked against the same reference photographs (Founders Club Bomb, TaylorMade Stealth, BANG SF).

## What changed from the first combined attempt, and what remains imperfect

The first attempt at this combination scaled the reference shell uniformly by width alone and kept its own native height/depth, which came out taller and more egg-shaped than a real fairway wood (its face also swept up a sole weight-pocket near the toe when flattened by depth alone). This revision fixes both:

- **Proportions:** the shell is scaled independently on all three axes to this project's already-validated fairway wood envelope (106 × 37 × 77 mm — the same numbers the hand-authored procedural revision uses), applied only *after* the face is already flattened, since a flat plane stays flat under further scaling but a curved surface's normals do not survive a non-uniform scale undistorted. This does shift the striking plane's own loft angle away from a round 15°, since height and depth are compressed by different amounts; the finished loft measures **17.5°**, reported honestly in `geometry_report.json` rather than forced back to 15°.
- **Face isolation:** flattening a vertex now also requires it to touch a face whose normal actually matches the loft direction, which a shallow toe-side sole pocket (part of the reference's own weight-port sculpting) does not, so it is no longer swept into the face by depth alone.
- **Hosel:** unioning the hosel into the scan-derived body with a boolean repeatedly triggered the EXACT solver into leaving stray faces behind, or handing back a crudely re-filled boundary, at a location on the body unrelated to where the hosel actually sits — a symptom of the solver struggling with the mesh's own residual scan noise. The hosel is instead a separate closed solid, embedded into and overlapping the body without a boolean, the same way the ferrule already works.
- **Face bezel:** a gloss-black bezel is cut into the material assignment around the satin scored insert, matching every reference photo (previously the satin material ran to the flat-cut edge with no border).

**Known remaining imperfection:** a visible, somewhat irregular seam is still present specifically along the crown-to-face transition at the top edge of the insert. It was investigated at length — confirmed present (in smaller form) even in the untouched, unprocessed reference shell before this script does anything to it, and unmoved by every fix tried against it (normal-direction filtering, a smoothed depth/normal-weighted blend instead of a hard cutoff at multiple margin/falloff settings, Laplacian relaxation of the whole shell before flattening, snapping vertex precision to a coarse grid, and removing the hosel boolean entirely). It is most likely a genuine, if slightly rough, part-line in the original scan at the boundary between what were originally separate UV-mapped patches, not a topological defect: the mesh remains fully manifold (zero non-manifold edges) throughout. It reads as a visible seam line under the glossy crown material, not as a hole or gap. If this is not acceptable, use `build_fairway_wood_procedural.py`, which has no such seam.

## Scale and placement

**One model unit is one meter. Import scale: `(1, 1, 1)`.** The body is **106 mm wide × 37 mm tall × 77 mm deep** (heel-to-toe, sole-to-crown, face-to-back), matching the game's established fairway wood envelope. The face is 21.2 mm tall at its centre. The body dimensions exclude the hosel and ferrule. This sits at real scale next to the other heads in this folder: the putters are 114 mm wide and the forged iron is 90 mm wide.

The shaft connection matches the game's original fairway woods (`ofg_loaner_3w`, `ofg_tour_spoon`, and the rest of the `fairway` family) exactly: socket at `(-0.04459, 0.060, -0.005)` meters, direction `(-0.484810, 0.874620, 0)`. The shaft lie is 61°. The 9.4 mm bore matches the original wood shaft's 9.2 mm tip. Measured face loft is 17.5° (see above).

| File | Placement |
|---|---|
| `fairway_wood_real_scale.glb` | Ground/sole origin; place at the original wood's club-root transform. |
| `fairway_wood_shaft_attachment.glb` | Pivot at the shaft connection; local +Y points toward the grip. |
| `fairway_wood_real_scale.obj` + `.mtl` | Mesh and materials in meters, with the ground origin. |
| `source/Fairway_Wood_Head.blend` | Editable Blender source. |
| `source/reference_head.glb` | The cleaned, cropped, reoriented reference shell the build starts from. |
| `source/build_fairway_wood_procedural.py` | The fully hand-authored alternative, no reference-mesh dependency. |

This assembly includes a ferrule. Remove the original `__head` and `__ferrule` objects when replacing a head from the original equipment pack. Retain its shaft and grip.

`attach_head.gd` provides `FairwayWoodHeadAttachment.attach(...)`. Its default path assumes this folder stays at `res://assets/Fairway_Wood_Head/`; adjust `HEAD_PATH` if you move it. Pass the shaft's lower connection position and desired face direction; the shaft's local +Y must point toward the grip.

The mesh node is `wood_head_mesh`. Attachment markers are `shaft_socket`, `socket_mouth`, `socket_bottom`, and `face_center`. This package is retained as an editable design option. The active fairway replacement is the user-selected `assets/Selected_Club_Heads/Fairway_Wood_Head.glb`; see that package for the current integration.

## Geometry and validation

The model contains **29,484 triangles** across three closed solids (body, hosel, ferrule) joined into one mesh node, and four PBR materials: gloss black crown/body, satin scored face insert, brushed steel sole, and a black ferrule. No external image textures are required. All components have zero open or nonmanifold edges. Both GLB exports passed the Khronos glTF validator with zero errors and zero warnings.

The shaft position, direction, and tip diameter were checked against the original `ofg_loaner_3w.glb`. The socket marker matches the original shaft origin with zero error and the original shaft axis to within 0.0001. The two GLB variants (ground origin and shaft-pivot) match after alignment to 1.8e-8 m. Validation reports are included as JSON files.

## Rebuild

Run `source/build_fairway_wood.py` with Blender 4.3-or-newer bpy/Python (built with Blender 5.2). It imports `source/reference_head.glb`, scales it uniformly by width, flattens its face onto a true plane (a smoothly weighted vertex projection, not a boolean cut — the EXACT solver has repeatedly produced artifacts cutting this scan-derived mesh), independently corrects height and depth to the target envelope, and adds the procedural hosel, bore, ferrule, and face bezel. To regenerate `source/reference_head.glb` itself from a different or updated reference download, the crop/reorient steps described above currently have to be redone by hand in Blender rather than from a checked-in script.
