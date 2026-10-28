# Forged iron heads

The 4-9 iron sets' heads, and the Utility Iron 2U's. One parametric family (`source/build_irons.py`,
working copy in `Documents/FreeCAD/GolfHead/irons/`), every head with the 2U's face-to-hosel joint:

| Head | Built as | Look | Sets |
|---|---|---|---|
| blade | `forged_blade` | the Blade Runner's back, fuller: thin upper plate, a bevel to a crisp level muscle line, a flat pad | blade_runner_forged |
| mb | `forged_mb` | muscle back: the blade's bar with a weight bar and two screws low on the pad, a 1.5 mm cavity following the upper blade | mustard_muscle, combo_proto |
| cb | `forged_cb` | cavity back: a 3 mm dish in a wide frame over a low muscle bar, a raised angular panel in it | loaner_irons, thrift_cavity_backs, tour_forged_cb |
| gi | `game_improver_cb` | the cavity back with a sole as wide as a spatula, a thicker top line, a 3.5 mm dish | game_improver_xl |
| 2u | `utility_iron_2u` | hollow utility iron: a muscle line straight into the neck, no heel dent | utility_2u |

The 4-9 heads have their hosel set 14 mm toe-ward of the 2U's and a 20 mm heel radius, so the heel is
round and the hosel never stands out past it; their faces run 7-8 mm further toward the toe (`TOE_SHIFT`), so
the blade is the Blade Runner's length again.

- `*.FCStd` / `*.step`: each head as FreeCAD solids, right-handed at address, mm, sole on z = 0.
- `source/`: `build_irons.py` (`IRON_VARIANT=blade|mb|cb|gi|2u`), `run_iron.sh` (build + Blender preview),
  `render_iron.py`.
- `geo/<head>/`: the exporter's geometry stage (parts as BREP, `art.json` outlines in face coordinates,
  `back_mask.png`), which the art is drawn on.
- `textures/<set>_back*.png`: each set's back art (`tools/make_iron_textures.py`), face-on as seen from
  behind; colour and glTF metal/rough.

Game skins: `tools/freecad/export_iron_heads.py` (stages `geo`, then `glb` after the art) writes
`assets/Selected_Club_Heads/skins/<set>_v2_base.glb`, and `OFGEquipmentAssets.HEAD_OVERRIDES` maps each set to
it. Each set's hosel mouth height (`LIVERIES[set]["mouth"]`) puts the sole where the set's stock head sat in
the swing rig, at address and impact. The 2U is exported by `tools/freecad/export_utility_2u_head.py`.

```
freecadcmd -c "exec(open(r'C:/Users/willi/Documents/GolfGame/tools/freecad/export_iron_heads.py').read())"   # IRON_STAGE=geo
python tools/make_iron_textures.py
freecadcmd -c "exec(open(r'C:/Users/willi/Documents/GolfGame/tools/freecad/export_iron_heads.py').read())"   # IRON_STAGE=glb
godot --headless --path . --import
godot --path . --script tools/render_shop_thumbnails.gd -- --models=loaner_irons,thrift_cavity_backs,mustard_muscle,game_improver_xl,blade_runner_forged,tour_forged_cb,combo_proto
```
