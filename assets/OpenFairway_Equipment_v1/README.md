# OpenFairway Equipment Pack

45 individually named club models and a separate fitted Grail headcover, built from the supplied Pro Shop Spec Book. Smooth shading, bevels, original PBR finish atlases, and nine distinct putter designs follow the spec's lightweight geometry budget.

## Use in your golf game

1. Copy `assets/openfairway_equipment/` into your project's `res://assets/` folder.
2. Let Godot finish importing. Each `ofg_<catalog_id>.glb` is a complete, textured scene that can be dragged into your game.
3. For condition changes, use the optional adapter below. All catalog IDs match the spec, including `scotty_grail`.

```gdscript
const Equipment = preload("res://assets/openfairway_equipment/scripts/equipment_assets.gd")

func equip_example() -> void:
    var club = Equipment.create_club("copper_classic", 0.82)
    add_child(club)
    # Change this instance's condition later:
    Equipment.apply_condition(club, 0.22)
```

Open this pack's `project.godot` as a separate project and press F5 to use the inspection scene. Select an item, drag to rotate, scroll to zoom, switch to the full club, and move the condition slider. Developer equipment is hidden until its checkbox is enabled. When integrating with your existing project, copy the asset folder rather than this sample project configuration.

## Contents

| Group | Inventory items | Head geometry |
| --- | ---: | --- |
| Drivers | 7 regular + 1 developer | 1 shared |
| Fairway woods | 7 | 1 shared |
| Hybrids | 3 | 1 shared |
| Iron sets | 7 | 1 shared |
| Wedges | 11 | 1 shared |
| Putters | 8 regular + 1 developer | 9 distinct |
| Fitted headcover | Separate prop | 1 separate mesh |

The seven collectible putters are Rustbelt Blade, Brass Relic, Midnight Mallet, Copper Classic, Tourline Prototype, Blackout Tour Issue, and The Grail. The loaner and Auto-Putt are separate designs outside that seven-item collection. The Grail includes actual cavity dot inlays; Auto-Putt includes separate emissive sensor and LED materials.

`catalog.json` maps each ID to its GLB, rarity, triangle counts, wear map, and visual parameters. Prices are recorded only where the supplied spec states them; absent putter prices are `null`. Connect this mapping to your existing economy instead of replacing economy data with it.

## Scale, orientation and attachments

- Units: metres. Up: **+Y**. Striking face: **−Z**. Toe: **+X**; heel and shaft: **−X**.
- Origin: ground level beneath the head. No billboard behavior or camera-facing nodes are used.
- Each club has uniquely named `__head`, `__shaft`, `__grip`, and `__ferrule` nodes.
- Empty attachment nodes end in `__face_center`, `__grip_anchor`, and `__shaft_socket`. Use the grip anchor's inverse transform to position the club in a hand or swing rig.
- Clubs are static meshes intended for equipment inspection, bags, displays, and attachment to your game's existing swing animation.
- Shafts and grips share the same geometry and vary by node transforms. The five non-putter head families share identical base geometry. `WideSole` morph weights provide the specified sole-width exceptions without introducing another base mesh; Utility 2U uses a depth scale on the shared hybrid head.
- Iron-set inventory rows are represented by one head, as specified. Loaner PW/GW/SW/LW are four inventory files on the same wedge shape.

## Materials and condition

Each club has a 1024 × 1024 albedo, ORM, normal, and fixed-UV wear atlas. ORM channels are **R = ambient occlusion, G = roughness, B = metallic**. Wear channels are **R = grime, G = scuff/chip placement, B = oxidation placement**. The shared grip uses 512 × 512 maps. GLBs embed the textures needed for their default materials; external maps support the editable condition shader.

The head atlas uses four padded regions: upper-left crown/top, upper-right face, lower-left sole, lower-right back/skirt. Shaft/grip UVs wrap around the cylinder. Fine grooves and milling are normal-map detail; the main silhouettes, cavities, flanges, necks, wings, inlays, sensor and cover are 3D geometry.

`condition` ranges from 0 to 1 and is independent of rarity. All standalone GLBs show their base finish. The optional shader adds wear per instance. Rusty Gap's raw rust, Rustbelt's sweet-spot oxidation, brass patina, and prototype tape are identifying base-finish features; additional condition damage layers over them. Solid copper/brass finishes do not expose an invented silver plating layer.

| Value | Label |
| ---: | --- |
| 0.00–0.21 | Poor |
| 0.22–0.41 | Worn |
| 0.42–0.61 | Fair |
| 0.62–0.81 | Good |
| 0.82–0.93 | Excellent |
| 0.94–1.00 | Mint |

`grenade_driver` and `auto_putt_9000` require `allow_admin = true` when created through the adapter. Use your game's existing permissions to decide when that flag is appropriate. The adapter only controls asset access; it does not implement gameplay effects.

## Editable sources and previews

- `source/OpenFairway_Equipment_Master.blend`: all 45 clubs arranged by collection, with packed material images and editable parts.
- `source/catalog_source.py`, `build_textures.py`, and `build_models.py`: reproducible generation sources. Use Blender 4.3 or its matching `bpy` module, NumPy 1.26, and Pillow. Run textures first, then models. For Blender command-line execution, include this source folder in `PYTHONPATH`.
- `previews/`: renders of the exported GLBs and two labeled overview sheets.
- `validation_report.json`: Khronos glTF structural validation, geometry-sharing checks, and coverage results.

Geometry and finish artwork are original to this pack. Reference images and reference-site content are not embedded. Catalog identifiers are retained, while the models carry no manufacturer logos.

Godot reference: [glTF import](https://docs.godotengine.org/en/4.4/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html) and [spatial shaders](https://docs.godotengine.org/en/4.4/tutorials/shaders/shader_reference/spatial_shader.html).

## Validation record

46 GLBs pass the Khronos validator with zero errors and warnings. All 226 embedded images and 184 external texture maps decode successfully. Godot 4.4.1 headless checks instantiate all 45 club entries, verify attachment scale and per-instance condition materials, and start the inspection scene. The batch check emits one diagnostic from the engine's dummy renderer; details are retained in `validation_report.json`. The preview sheets are Blender renders of the exported GLBs. The sample Godot interface has been checked for startup and script errors, but has not been graphically reviewed in Godot.
