# Driver460 head

The game's driver head for loaner_driver, thrift_titan_460, slice_slayer, rocket_boomer_lt,
hollow_point_tour, meteor_xr_proto, persimmon_ghost (oiled persimmon, brass sole plate) and the
admin-sandbox grenade_driver.

The hosel is set into the heel (built with `HOSEL_SHIFT=6 HEEL_TIP_Z=46`, `source/run_hybrid_variant.sh`):
6 mm toe-ward, with the heel closing 46 mm up its axis, so from above it no longer stands out past the
heel like a spout.

- `driver_460_hybrid.FCStd` / `.step`: the head as FreeCAD solids (Body, FaceInsert, ScorePaint, HeelWeight,
  Ferrule), right-handed at address, mm, sole on z = 0, toe -X, face -Y.
- `source/`: how it is built, headless, in stages (`run_hybrid_pipeline.sh`):
  - `build_driver.py`: the parametric body (outline, wide-open-eye face view, wedge crown, eye-shaped face).
  - `face_hosel_blend.py`: the Sport Hybrid 21's face-to-hosel joint in the head's distance field (face cut
    off the body first with a rounded edge, then the hosel added with a 12 mm tangent blend, tapering to
    4 mm at the face; the hosel tube fades away inside the heel), and helpers.
  - `build_hybrid_driver.py`: stage `head` (loft the field at high resolution, extract the flat face's
    outline) and stage `finish` (sole screw, score lines, squared and bored hosel, ferrule, face insert).
  - `fit_insert.py`: the face insert's outline, a left-right symmetric lens with round ends fitted 2.5 mm
    inside the face (`insert_outline.json`).
  - `render_driver.py`: Blender (Cycles CPU) preview renders.
- `textures/`: crown and sole art per club (`tools/make_driver_textures.py`); the loft mark sits on the sole
  by the toe, upright with the club held toe down; every crown has the same alignment arrow, a solid
  triangle with its tip at the face, pointing at the target.

Game skins: `tools/freecad/export_driver_460_head.py` writes
`assets/Selected_Club_Heads/skins/<club>_d460_base.glb` (one livery per club: crown and sole art, metal frame
finish, the flat face in one finish, score-line colour, screw) in the 2U skin frame; `OFGEquipmentAssets.HEAD_OVERRIDES`
maps each club to its skin. The hosel is cut back under the ferrule so the head sits in the swing rig
where the stock driver head did (sole height at address and impact).
