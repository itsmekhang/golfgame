# Inspectable putter finishes

The replacement putter heads use their own 1024px PBR atlases. Their original
material coordinates were absent or incompatible with the older preview models.
`tools/texture_putter_heads.py` assigns padded planar UV regions and produces
albedo, ORM, normal, and condition wear maps for all nine putters.

The finishes follow `OpenFairway_Putter_Collection.png`: brushed silver loaner,
oxidized copper Rustbelt, aged gold Brass Relic, charcoal Midnight with white
sightlines, polished Copper Classic, satin silver Tourline with a blue line,
Blackout with red paint and a silver weight badge, polished Grail with three red
inlays, and blue-grey Auto-Putt with teal alignment details.

Run `python tools/texture_putter_heads.py` to stage models and maps in
`build/putter-finishes`. `--source` accepts an equipment asset directory to use a
saved input model set. Install the staged `models/` and `textures/` under
`assets/openfairway_equipment/`, then let Godot reimport them.

The tool preserves every triangle position, smooth normal, node transform, shaft,
and grip. It adds UV seams without adding triangles. Per-primitive source material
names remain in glTF extras so existing accent geometry can be recognized on a
later run. The authored preview PNGs and their original source-pack templates stay
as references; their older four-region atlas layout must not receive these new maps.

The inspector supplies putters with a shared 128px studio reflection sky, so their
metals read correctly under the existing lights. Course rendering is unaffected.
