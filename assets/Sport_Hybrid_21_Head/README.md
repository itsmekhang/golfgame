# Sport Hybrid 21 head

The game's hybrid head (Rescue Rookie 3H, Cloudcutter 4H). Designed by Codex in FreeCAD; finished
here with the user's colours and a per-club livery.

| File | What |
|---|---|
| `Sport_Hybrid_21.FCStd` | The head (copy of Codex's `Documents/Codex/2026-10-03/connec/outputs/Sport_Hybrid_21.FCStd`), painted face by face: carbon face and hosel, white ring on top of the face and black below it, jet-black crown, sole and arrow, blue rails, steel screw. Drawn left-handed (toe +X); the exporter mirrors it. |
| `Sport_Hybrid_21.step` | Codex's STEP export (geometry only). |
| `build_sport_hybrid.py` | Codex's build script (geometry; the colours live only in the `.FCStd`). |
| `textures/` | Livery textures, made by `tools/make_sport_hybrid_textures.py` (hex crown, slate flake, the two soles with their loft marks). Godot ignores this folder (`.gdignore`). |

In the game: `assets/Selected_Club_Heads/skins/cloudcutter_4h_sport_base.glb` and
`rescue_rookie_sport_base.glb`, mapped in `OFGEquipmentAssets.HEAD_OVERRIDES`.

Rebuild after changing the model or a livery:

```
python tools/make_sport_hybrid_textures.py
freecadcmd -c "exec(open(r'C:/Users/willi/Documents/GolfGame/tools/freecad/export_sport_hybrid_head.py').read())"
godot --headless --path . --import
godot --path . --script tools/render_shop_thumbnails.gd -- --models=rescue_rookie,cloudcutter_4h
```

The liveries (finishes per part) are `LIVERIES` in `tools/freecad/export_sport_hybrid_head.py`. The
exporter lengthens the hosel by 3.4 mm under the ferrule so the club keeps the stock hybrids' length
and ground contact (`MOUTH_Z`, measured in the swing rig).
