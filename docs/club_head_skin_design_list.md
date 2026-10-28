# Club head skin and texture design list

This is the current design roster for every available driver, fairway wood, hybrid, iron, and wedge. Model IDs are the stable IDs used by the catalog and should be used for texture folders, preview names, and variation records.

## Shared head sources

| Family | Applied head | Primary texture regions |
|---|---|---|
| Drivers | `assets/Selected_Club_Heads/Driver_Head.glb` by default; `assets/Driver_Head/driver_head_real_scale.glb` for `persimmon_ghost` | carbon crown, chassis/polymer shell, sole plate, strike face, trim, fasteners |
| Fairway woods | `assets/Selected_Club_Heads/Fairway_Wood_Head.glb` | carbon crown, chassis/polymer shell, sole plate, strike face, trim, fasteners |
| Hybrids | `assets/Selected_Club_Heads/Hybrid_Rescue_Head.glb` | chassis, crown/shell, sole plate, strike face, trim, fasteners |

Each catalog model currently keeps its own shaft/grip and wear profile while sharing the family head geometry. Skins can therefore be authored as material/texture variants without changing club scale or fitting.

## Drivers

| ID | Display name | Slot | Rarity | Current design cue | Texture/wear folder |
|---|---|---:|---|---|---|
| `loaner_driver` | Daddy's Driver | DR | loaner | scuffed gray rental head | `textures/loaner_driver/` |
| `thrift_titan_460` | Thrift Titan 460 | DR | common | dark blue-gray with pale metal accent | `textures/thrift_titan_460/` |
| `slice_slayer` | Slice Slayer Offset | DR | common | navy/blue game-improvement look | `textures/slice_slayer/` |
| `persimmon_ghost` | Persimmon Ghost | DR | uncommon | separate D1 pear-shaped driver model; oiled persimmon wood and brass design direction | `textures/persimmon_ghost/` and `assets/Driver_Head/` |
| `rocket_boomer_lt` | Rocket Boomer LT | DR | rare | red hot-rod cannon | `textures/rocket_boomer_lt/` |
| `hollow_point_tour` | Hollow Point Tour | DR | epic | black tour head with gold details | `textures/hollow_point_tour/` |
| `meteor_xr_proto` | Meteor XR Prototype | DR | legendary | raw violet carbon with orange prototype marks | `textures/meteor_xr_proto/` |
| `grenade_driver` | Grenade Prototype Driver | DR | mythic/admin | olive military shell with yellow hazard accents | `textures/grenade_driver/` |

## Fairway woods

| ID | Display name | Slot | Rarity | Current design cue | Texture/wear folder |
|---|---|---:|---|---|---|
| `loaner_3w` | Daddy's 3 Wood | 3W | loaner | gray rental head with a rattle | `textures/loaner_3w/` |
| `loaner_5w` | Daddy's 5 Wood | 5W | loaner | gray rental head with shiny grip | `textures/loaner_5w/` |
| `garage_3w` | Garage Sale 3 Wood | 3W | common | chipped neutral garage-find finish | `textures/garage_3w/` |
| `steelhead_classic` | Steelhead Classic 3W | 3W | uncommon | blue steel classic pear shape | `textures/steelhead_classic/` |
| `tour_spoon` | Tour Spoon 13° | 3W | rare | compact black/gold tour weapon | `textures/tour_spoon/` |
| `lowball_5w` | Lowball 5 Wood | 5W | common | understated gray low-launch head | `textures/lowball_5w/` |
| `heirloom_5w` | Heirloom 5 Wood | 5W | epic | laminated maple with a burned maker mark | `textures/heirloom_5w/` |

## Hybrids and utility heads

| ID | Display name | Slot | Rarity | Current design cue | Texture/wear folder |
|---|---|---:|---|---|---|
| `rescue_rookie` | Rescue Rookie 3H | HY | common | forgiving blue-gray rescue head | `textures/rescue_rookie/` |
| `cloudcutter_4h` | Cloudcutter 4H | HY | uncommon | blue high-launch head with light alignment detail | `textures/cloudcutter_4h/` |
| `utility_2u` | Utility Iron 2U | HY | rare | dark hollow-body utility iron | `textures/utility_2u/` |

## Iron and wedge head sources

Unlike the driver/fairway/hybrid families, the current iron and wedge catalog GLBs bake their head geometry directly into each item's own model file rather than swapping in one shared external head. Comparing the actual head mesh data (not just the catalog's triangle-count fields, which are stale) shows exactly two distinct head shapes per family:

| Family | Head type | Reference source | Items currently using it |
|---|---|---|---|
| Iron | **Forge** (cavity-back) | `C:\Users\willi\Downloads\Forge_Cavity_Iron_Head.zip` (`forge_cavity_iron_real_scale.obj`/`.glb`, source `.blend` included) | `thrift_cavity_backs`, `loaner_irons`, `game_improver_xl`, `mustard_muscle` |
| Iron | **Blade** (muscle-back) | `C:\Users\willi\Downloads\Forge6_28deg_MuscleBack_RoundedHeel.glb` / `Forge6_28deg_StraightHosel.glb` (GLB only, no `.obj`) | `blade_runner_forged`, `tour_forged_cb`, `combo_proto` |
| Wedge | Shape A (standard cast wedge) | no external download found; baked in-place | all 10 wedges except `rusty_gap_52` |
| Wedge | Shape B (distinct rounded head) | no external download found; baked in-place | `rusty_gap_52` only |

No wedge source `.obj`/`.glb` exists anywhere in the project or in Downloads — the two wedge shapes above are only present pre-baked inside the catalog files. If a proper wedge reference (equivalent to the iron Forge/Blade pair) shows up later, it should replace this row.

### Iron head-type mismatches to fix in the redesign

Two current items are baked with the geometry that doesn't match their own name/style, worth correcting when the skins are rebuilt:

- `mustard_muscle` ("Mustard **Muscle Backs**") is currently baked on the **Forge/cavity-back** mesh. Muscle-back irons are a blade-style head by definition — this should move to the **Blade** mesh.
- `tour_forged_cb` ("Tour Forged **CB**" — CB = cavity back) is currently baked on the **Blade** mesh. This should move to the **Forge/cavity-back** mesh.

### Irons

| ID | Display name | Rarity | Recommended head type | Current design cue | Texture/wear folder |
|---|---|---|---|---|---|
| `loaner_irons` | Loaner Irons 4–9 | loaner | Forge (cavity-back) | scuffed mid-gray practice-set irons | `textures/loaner_irons/` |
| `thrift_cavity_backs` | Thrift Cavity Backs | common | Forge (cavity-back) | light silver thrift-store cavity backs | `textures/thrift_cavity_backs/` |
| `mustard_muscle` | Mustard Muscle Backs | uncommon | **Blade** (currently mis-baked as Forge — fix) | mustard-bronze muscle-back forging | `textures/mustard_muscle/` |
| `game_improver_xl` | Game Improver XL | uncommon | Forge (cavity-back), wide sole | pale blue-gray super-game-improvement iron | `textures/game_improver_xl/` |
| `blade_runner_forged` | Blade Runner Forged | rare | Blade (muscle-back) | raw forged steel blade | `textures/blade_runner_forged/` |
| `tour_forged_cb` | Tour Forged CB | epic | **Forge (cavity-back)** (currently mis-baked as Blade — fix) | dark charcoal tour cavity-back forging | `textures/tour_forged_cb/` |
| `combo_proto` | Combo Set Prototype | legendary | Blade, styled as a combo set | deep navy prototype blending both head styles | `textures/combo_proto/` |

### Wedges

| ID | Display name | Loft | Rarity | Head shape | Current design cue | Texture/wear folder |
|---|---|---|---|---|---|---|
| `loaner_pw` | Loaner PW | PW | loaner | A | gray rental pitching wedge | `textures/loaner_pw/` |
| `loaner_gw` | Loaner GW | GW | loaner | A | gray rental gap wedge | `textures/loaner_gw/` |
| `loaner_sw` | Loaner SW | SW | loaner | A | gray rental sand wedge | `textures/loaner_sw/` |
| `loaner_lw` | Loaner LW | LW | loaner | A | gray rental lob wedge | `textures/loaner_lw/` |
| `grocery_pw` | Grocery Store PW | PW | common | A | bargain-bin pale pitching wedge | `textures/grocery_pw/` |
| `bent_neck_pw` | Bent Neck PW | PW | uncommon | A | slate-gray head with a visibly bent neck/hosel | `textures/bent_neck_pw/` |
| `rusty_gap_52` | Rusty Gap 52° | 52° (GW) | uncommon | **B** (distinct geometry) | corroded rust-brown gap wedge | `textures/rusty_gap_52/` |
| `flop_master_60` | Flop Master 60° | 60° (LW) | uncommon | A, wide sole | light gray wide-sole flop/lob wedge | `textures/flop_master_60/` |
| `raw_face_56` | Raw Face 56° | 56° (SW) | rare | A | raw unplated-face sand wedge | `textures/raw_face_56/` |
| `tour_grind_58` | Tour Grind 58° | 58° (LW) | epic | A | dark tour-grind wedge with contrasting sole grind | `textures/tour_grind_58/` |
| `sand_shovel` | Sand Shovel SW | SW | common | A, extra-wide sole | extra-wide "shovel" sole sand wedge | `textures/sand_shovel/` |

## Recommended variation fields

For each new skin, record:

- `model_id` and variation ID, for example `meteor_xr_proto_nebula`.
- Crown, chassis, sole, face, trim, and fastener colors.
- Finish type: gloss, satin, matte, raw carbon, brushed metal, anodized metal, painted, wood, or worn.
- Pattern/graphic: solid, fade, geometric, carbon weave, forged marks, pinstripes, decals, or alignment aid.
- Face treatment: score-line contrast, milling visibility, face wear, and edge polish.
- Sole treatment: plate color, weight-port color, scratches, dirt, oxidation, and laser marks.
- Condition response: chip strength, corrosion strength, oxidation color, and wear-mask design.
- Preview filename: `ofg_<model_id>_<variation_id>.png`.

Texture channels should preserve the existing authored material layout: base color, normal, roughness, and optional metallic/clearcoat maps. Keep the supplied head proportions and `ShaftSocket` alignment unchanged for every skin.

For irons and wedges specifically, also record:

- Topline/back region: cavity badge color and insert material (Forge heads), or muscle-back top-rail thickness and forging lines (Blade heads).
- Hosel/neck finish: plated, raw, welded seam visibility, and any bend (e.g. `bent_neck_pw`).
- Groove/score-line treatment: milled contrast, wear/polish on the leading grooves, and face roughness.
- Sole grind and bounce plate: width, camber, heel/toe relief, and any stamped grind markings (`raw_face_56`, `tour_grind_58`, `sand_shovel`).
- Loft/lie stamp: engraved or painted loft marking on the back (wedges only, matching each item's loft label).
