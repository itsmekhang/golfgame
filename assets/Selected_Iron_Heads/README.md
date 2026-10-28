# Selected iron skins

This package contains the seven supplied iron skin GLBs and the 512px rear-view shop thumbnails. The runtime applies these files only to the iron catalog entries:

- `loaner_irons`
- `thrift_cavity_backs`
- `mustard_muscle`
- `game_improver_xl`
- `blade_runner_forged`
- `tour_forged_cb`
- `combo_proto`

The existing full-club catalog scenes still provide the original shaft and grip. Each supplied head is attached at the existing shaft and receives the game's condition/wear shader. Wedge assets and wedge thumbnails were intentionally left unchanged.

The source package is `Iron_Wedge_Head_Skins_and_Source`; only its seven entries with `family: iron` were installed. The supplied GLBs contain their baked skin materials and preserve the source iron UVs and attachment data.

The `shop_thumbnails/512/` folder contains matching `_back.png` and `_top.png` renders for every iron. The shop uses a rear three-quarter view that also reveals the top edge; the higher top views are available for design review. The folder name is retained for compatibility; the current renders are 640 x 560 pixels.

Regenerate thumbnails with `godot --path . --script tools/render_shop_thumbnails.gd` (requires a graphics device). This uses the runtime head, imported atlas UVs, and condition material with controlled studio lighting. All club previews have transparent backgrounds and cast shadows. Camera fitting includes the complete head and projected shadow, leaving a clear border below the sole. The earlier Blender lighting setup overexposed the small meter-scale heads and is superseded by this renderer.
