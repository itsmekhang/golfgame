# Utility Iron 2U head

The Utility Iron 2U's hollow-body iron head. Now built by the forged iron family
(`assets/Iron_Heads/source/build_irons.py`, `IRON_VARIANT=2u`: a muscle line running straight into the neck,
no heel dent, the heel's outline on the hosel's line). `utility_iron_2u.FCStd` / `.step` are that build;
`build_utility_iron.py` is the earlier version, kept for reference.

| File | What |
|---|---|
| `build_utility_iron.py` | The parametric model (heel filled out at the neck: `HEEL_FILL_X`, `HEEL_BULGE`). |
| `utility_iron_2u.FCStd` / `.step` | Its built document and STEP. |

In the game: `assets/Selected_Club_Heads/skins/utility_2u_iron_base.glb` (with the VELMOR brand
decal), exported by `tools/freecad/export_utility_2u_head.py`, which builds from
`Documents/FreeCAD/GolfHead/build_utility_iron.py`:

```
freecadcmd -c "exec(open(r'C:/Users/willi/Documents/GolfGame/tools/freecad/export_utility_2u_head.py').read())"
godot --headless --path . --import
godot --path . --script tools/render_shop_thumbnails.gd -- --models=utility_2u
```
