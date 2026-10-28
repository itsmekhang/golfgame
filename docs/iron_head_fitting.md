Blade Runner Forged, Tour Forged CB, and Combo Set Prototype use the rounded-heel
muscle-back head, revision 4:
`assets/Forge_Cavity_Iron_Head/Forge6_28deg_MuscleBack_RoundedHeel.glb`.
It is an exact copy of the approved GLB in Downloads, with 102,488 triangles.

The other four inspectable iron sets retain revision 3 of the thin-blade head:
`assets/Forge_Cavity_Iron_Head/Forge6_28deg_StraightHosel_v3.glb`.
It is an exact copy of `Downloads/Forge6_28deg_StraightHosel (1).glb`.

Run `python tools/fit_forge_iron_heads.py` to stage replacement GLBs and
`fit-report.json` under `build/forge-iron-fitted/`. To regenerate just the three
muscle-back sets, use `--ids blade_runner_forged tour_forged_cb combo_proto`.
The fitter preserves each source's complete triangles, vertex positions and
smooth normals. Both sources retain their real dimensions in metres and their
28-degree authored loft.

The source's shaft axis is +Y and its origin is the hosel mouth. A proper rigid
rotation aligns that axis to the existing shaft and turns the striking face
forward. The shaft tip enters the 9.4 mm bore by 6 mm. The existing 9.2 mm shaft
fits with 0.1 mm radial clearance. Neither the head nor the shaft is stretched,
sheared or bent. The full assembly moves vertically as one object to ground the
sole, preserving the shaft and grip geometry and their local transforms.

All seven iron heads use the same solid base color over the face, back, sole,
and hosel, with a small, distinct geometric emblem on each back. The equipment
pack's `source/iron_finishes.py` paints the shapes only in the rear atlas tile;
the face keeps its matching base color. The designs contain no lettering.
Roughness and metallic maps stay uniform. Score lines remain actual mesh geometry.
The UV layout and condition masks are retained for the existing wear system.
After regenerating textures with the pack's `source/build_textures.py`, use
`tools/update_club_texture_images.py` to refresh each GLB's embedded images
without altering its geometry or attachment transforms.
Inventory and HUD icons use the regenerated front previews. The 3D inspector
opens at the rear angle saved in the root extras.
Gameplay club loft, distances, prices and equipment ownership are independent
of these visual models and are not changed by the fitting tool.

Install the staged models into `assets/openfairway_equipment/models/iron/` and
the matching source-pack model directory. Render `_back.png` previews from those
exact models with `assets/OpenFairway_Equipment_v1/source/render_models.py`,
then install them into both preview directories and reimport in Godot.

`tests/iron_attachment_test.gd` checks the imported meshes: source scale and
triangle count, neck/shaft alignment, insertion depth, centered circular bore at
two depths, and a grounded sole. The fitter also checks exact source triangle
positions/normals and unchanged shaft/grip transforms before saving. The attachment
test also checks that each set uses its assigned revision and triangle count.

The older `tools/fit_iron_heads.py` handles the previous OBJ-based head, still used
by the wedges. Do not use it to regenerate these irons. Rusty Gap also
has its own baked UVs; see `docs/wedge_finishes.md` before rebuilding that wedge.
