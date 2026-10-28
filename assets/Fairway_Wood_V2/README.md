# Fairway wood heads (V2)

The fairway woods' heads: three of their own, not a shrunken driver - small, low and shallow-faced, sitting
flat on the turf. From behind each is a clam: a crown dome and a sole dome meeting at the rim, even from toe to
heel. From above the outline is round, the back one arc from the toe round to the heel. Face-on the top line
sweeps up into the hosel and the heel curves up into the hosel's heel side.

The body is one loft, built like the irons' (`_head_sections` in `source/fairway_params.py`): the clam's
sections run heel-ward to the neck, then turn into the round hosel along two guides - the crown's top line
into the hosel's toe side, the sole round a 20-24 mm heel radius and up the hosel's heel side - each point
keeping its place round the section. Nothing is added to the body, so there is no seam, spike or blob where
the hosel meets it. The hosel's front meets the face at the face's top-heel corner, flush. The face is then
cut once through it all in the head's distance field, its edge rounded 1.8 mm, growing to 5 mm heel-ward so the
flat face eases round into the hosel's front; above the face the cut lifts off gently so the hosel is never
sliced. The sole runs flat right up to the face, so the face's bottom edge is the leading edge, on the ground.
The face carries seven full-length score lines (grooves 0.8 mm wide, 0.35 mm deep, 2.4 mm apart) across its
insert, painted per club. In the game the black ferrule is remade to the hosel's size where the hosel is cut,
so the two meet flush.

| Head | Clubs | Shape |
|---|---|---|
| `fairway_modern` | Daddy's 3 and 5 woods, Garage Sale 3W, Lowball 5W | ~199 cc, 15 degrees, a round outline, a low clam crown, a speed slot across the sole behind the leading edge |
| `fairway_tour` | Tour Spoon 13 | ~156 cc, 13 degrees, compact ("tiny head"), the slot, a weight port low at the back of the sole |
| `fairway_classic` | Steelhead Classic, Heirloom 5W | ~218 cc, 15 degrees, a deeper face, the fullest dome, a smooth sole |

- `fairway_<head>.FCStd` / `.step`: each head as FreeCAD solids (Body, FaceInsert, ScorePaint, HeelWeight,
  Ferrule), right-handed at address, mm, sole on z = 0, toe -X, face -Y.
- `source/fairway_params.py`: the heads' parameters over the driver's (`FAIRWAY_STYLE`), the one-loft body
  (`_head_sections`), and the face's cut and the sole's slot in the head's distance field, run by the driver's
  pipeline:

```
cd Documents/FreeCAD/GolfHead/driver
FAIRWAY_STYLE=modern HEAD_PARAMS=../fairway/fairway_params.py DRIVER_OUT=../fairway/modern DRIVER_DOC=../fairway/fairway_modern ./run_hybrid_variant.sh
```

- `textures/`: crown and sole art per club (`tools/make_fairway_textures.py`, drawn on each head's own masks,
  `textures/masks_<head>`), abstract and minimal: a crown of one material with a thin accent line along the face
  and the alignment arrow (the same on every crown, tip at the face); a sole of the frame's metal with one inset
  panel, at most one raked accent facet, one short word and the club's number, the accent on the screw ring,
  the skirt line and the loft (by the toe, toe down). The club's tell stays, subtly (Lowball's chipped toe,
  Heirloom's small burned mark and brass plate).

Game skins: `tools/freecad/export_fairway_head.py` (the driver's exporter, once per head, with its source, art,
parting line, a wide cup-face band round the face on the modern and tour heads, mouth height and its clubs'
`FAIRWAY_LIVERIES`) writes `assets/Selected_Club_Heads/skins/<club>_fw_base.glb`; `OFGEquipmentAssets.HEAD_OVERRIDES`
maps each fairway wood to it. Each head's mouth height seats it where the stock fairway woods sat in the swing
rig (61.3 mm: within ~0.6 mm at address and impact).
