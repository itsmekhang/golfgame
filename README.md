# OpenFairway Golf (Godot 4.7)

A 3D golf game built on a **GDScript port of the OpenFairway golf-ball physics engine**
(aerodynamics, Reynolds/spin-ratio lift & drag, Penner bounce model, surface-dependent
rollout and spin-back) with **Quaternius Stylized Nature MegaKit** props and three
real-course maps baked from drone scans / photogrammetry.

Open `project.godot` in Godot 4.7 (standard build, no .NET needed) and press Play.

## Controls

| Key | Action |
|---|---|
| A / D or right-drag | Aim |
| W / S | Next / previous club |
| Space or left click | Start power meter, lock power, lock accuracy (3 presses) |
| Mouse wheel | Zoom |
| C | Toggle bird's-eye view; arrow keys pan across the hole, wheel changes height |
| N | Next hole |
| R | Restart hole |
| H | Reroll the random water hazards and bunkers (new seed) |
| J | Build a brand new course (new routing seed) |

## The course

There is one course, built entirely by `scripts/course_builder.gd` from a seed
(`course_seed` in `scripts/course.gd`, default 7; **J** rolls a new one):

- a returning nine in parallel 110 m corridors, holes alternating north/south so every
  tee is a short walk from the previous green; pars 4-3-5-4-4-3-5-4-4 with lengths drawn
  per par and doglegs on the par 4s and 5s
- rolling terrain from seeded noise, flattened along fairways, raised greens and tee boxes,
  a 2.5 m first cut around every fairway
- a signature pond beside every third hole and a creek across the longest hole, then
  `WaterHazardGenerator` and `BunkerGenerator` dig the rest (**H** rerolls those only)
- Quaternius trees, bushes, rocks and flowers in the rough, grass blades in a band beside
  the turf

## Bunkers and water hazards (excavations)

Both are `Excavation` polygons (`scripts/excavation.gd`) that carve the terrain and
override the lie:

- `scripts/bunker.gd` — sunken sand floor with a raised lip; lie = bunker.
- `scripts/water_hazard.gd` — pond blob or wavy creek with a bed, banks, water level and
  the water surface mesh (your normal-map shader, `shaders/water_simple.gdshader`).
- `scripts/bunker_generator.gd` — digs 1–3 greenside bunkers around every green (front
  and sides) and a fairway bunker in the driving zone of par 4/5s.
- `scripts/water_hazard_generator.gd` — ponds along fairway edges in landing zones plus
  creeks across long holes. Both generators are deterministic per seed; **H** rerolls.
- `scripts/course_digger.gd` — build-time helpers (`dig_bunker`, `dig_water`, `remove_at`,
  `export_features`) for scripts and tests. Players cannot dig; each call updates the lie
  cache and rebuilds only the 64 m terrain and grass tiles it touches.

**Flagging**: `GolfBall` emits `water_hazard_entered(hazard, position)` the moment it drops
through a hazard's surface and `bunker_entered(position, plugged)` when it plugs into or
rolls into sand; `in_water` / `in_bunker` / `last_hazard` are set, the HUD shows the
splash or bunker message, counts both, and water costs a penalty stroke with a drop.
Tests: `tests/water_hazard_test.gd`, `tests/dig_test.gd`.

## Terrain rendering (TerraBrush)

The course is drawn by the TerraBrush GDExtension (`addons/terrabrush`, MIT) as a clipmap
terrain with LOD, per-texture normal maps, height-blended splatting and anti-tiling.
`scripts/terra_terrain.gd` feeds it from the course layout: a 1 m heightmap, a splat map
(fairway turf / rough / sand) and a colour map carrying the mowing stripes, the lighter
putting greens, the fringe collar and the first cut. Ball physics and lies still come from
the layout, not from TerraBrush. If the extension is missing, the old tiled mesh
(`scripts/terrain_builder.gd`) is used instead; `GOLF_NO_TERRABRUSH=1` forces that.

Lies around a green, from the middle out: green, fringe (2.5 m, plays like fairway),
then whatever surrounds it.

## Turf texture

The fairway photo (`assets/textures/fairway/fairway_diffuse.jpg`, from the "Rectangular Grass
Patch" package) is mirror-tiled into `fairway_tile.png` so it repeats without seams, and the
terrain shader tiles it in world space every 5 m on all grass surfaces, modulated by the
class tint so the mowing stripes, first cut and rough shades stay. The flat patch mesh in the
package is not used. Original sources sit in `source/` folders that Godot ignores.

## Sky

`shaders/sky_atmosphere.gdshader` (your physically based sky with ray-marched cumulus,
cirrus, stars and an optional rainbow) drives the `Sky` with generated 3D noise textures.
Parameters are set in `_sky_material()` in `scripts/course.gd`.

## Rough grass

`scripts/rough_grass.gd` fills a 26 m band of rough beside every fairway, green and tee
(sparser further out) with grass in 64 m tiles. Modes (`RoughGrass.MODE` in `scripts/rough_grass.gd`):

- `wind` (default): unshaded `shaders/grass_wind.gdshader` on the same generated tapered
  blade mesh as `gradient`. Color comes from a generated vertical gradient texture (no photo
  texture), motion from a tiling wind-noise texture sampled once per vertex, and blades push
  away from the ball within `character_radius`. Cheap enough to replace `kolosok` everywhere.
- `gradient`: your gradient/wind shader (`shaders/grass_gradient.gdshader`) on the same
  generated tapered blade mesh; blades flatten under the ball (wind sway disabled for perf).
- `atlas`: your atlas shader (`shaders/grass_atlas.gdshader`) on the SimpleGrassTextured
  cross-quad mesh and `grassbushcc008.png` (1x1 atlas).
- `sgt`: the stock SimpleGrassTextured node (`addons/simplegrasstextured`, MIT).
- `kolosok`: your photo-scanned "Trava Kolosok" blades. The two JPEGs were merged into one
  RGBA atlas (`assets/textures/tiles/rough_grass/kolosok_atlas.png`) and the OBJ clump is
  parsed at load time; each instance is a tuft of 34 of its cards on the two-sided card
  shader (`shaders/grass_cards.gdshader`) with flattening under the ball. 34 cards/clump plus
  the 2.4 MB atlas was the actual performance cost in the rough, so this is no longer the
  default -- kept only for reference.

Hole routing for the scanned courses lives in `assets/scanned/<course>/holes.json`
(tee, waypoints, cup, par). Edit those to add or move holes.

## Physics engine (`addons/openfairway/`)

Line-by-line GDScript port of the OpenFairway C# addon (MIT), same class names in
snake_case: `BallPhysics`, `BounceCalculator`, `Aerodynamics`, `FlightAerodynamicsModel`,
`FlightProfile` / `BounceProfile` / `RolloutProfile`, `BallPhysicsProfile` (with the
32 calibrated regime overrides), `ShotRegimeKey`, `SurfacePhysicsCatalog`,
`PhysicsParamsFactory`, `PhysicsParams`, `PhysicsAdapter`, `ShotSetup`, `PhysicsLogger`.

Headless regression:

```
godot --headless --path . --script tests/physics_smoke_test.gd
```

Game integration follows the addon's ownership rules: `GolfBall` owns launch state,
contact, floor normal and calls `BallPhysics`; the course controller supplies the
lie-surface resolver (`LieSurfaceResolver` → `SurfaceZone` override → class map → default),
and `PhysicsParamsFactory` decides how a surface changes bounce, spin-back and rollout.

## Baking a new course

Gaussian splat (super-splat compressed PLY):

```
python tools/splat_to_course.py "path/scan.ply" assets/scanned/<name> --scale 200 --cell 2 --align
```

Photogrammetry mesh (GLB):

```
python tools/mesh_to_course.py assets/scanned/<name>/model.glb assets/scanned/<name> --cell 1.5
```

Both write `heightmap.png` (16-bit), `albedo.png`, `classmap.png` (0 rough, 1 fairway,
2 green, 3 bunker, 4 water, 5 path, 7 trees), `trees.json` and `meta.json`. Add a
`holes.json`, then add the folder name to `COURSES` in `scripts/course.gd`.
Requires Python with numpy, scipy and Pillow.

## Changing the course

Edit `CourseBuilder.build()` for routing rules (par sequence, corridor spacing, lengths,
dogleg sizes) and the generators for where sand and water go.
`tests/timing_test.gd` prints how long each build phase takes.

## Credits

- OpenFairway Physics by jesseincode & Jakobi (MIT) — `addons/openfairway/LICENSE`
- Stylized Nature MegaKit by Quaternius (CC0) — `assets/nature/LICENSE_Quaternius.txt`
- SimpleGrassTextured by IcterusGames (MIT) — `addons/simplegrasstextured/LICENSE`
- Water, sky, gradient grass and atlas grass shaders supplied by the project owner
