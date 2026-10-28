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
| Hold Space / left click (ball moving) | Fast-forward the shot 3× (a fresh press after the hit) |
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

## Progression, shops and the putter cabinet

Golf pays the bills and the bills buy clubs. Press **Tab** (or hole out the round's last hole)
to open the **Clubhouse** hub: Shop, Bag, Collection, Objectives and, with admin access, the
illegal-club sandbox. All numbers live in `data/economy.json` (cash, payouts, resale rates,
store personalities, rarity weights, Scotty Cameron chances, modifier bounds) and
`data/club_catalog.json` (every club model: slot, rarity, fair value, modifiers, art hints).

- **Start**: $60 and a complete loaner bag that plays exactly like the old stock bag. Loaners
  can't be sold, so a playable bag always exists. Goodwill is the only open store.
- **Rounds**: the first `holes_per_round` holes (default 9). Finishing pays ~$35 plus small,
  capped bonuses (pars, score tiers, first round, milestones, personal best). Mulligans (M)
  and restarts (R) still pay, but that round can't qualify for an unlock or a record.
  Skipping a hole (N) abandons the round: no pay, no restock.
- **Stores** (`scripts/economy/loot_generator.gd`): Goodwill ($5-$25 tags, rarity-blind, so a
  legendary can sit there for $19), the pawn shop (inconsistent pricing, sometimes doesn't
  know what it has), Facebook Marketplace (simulated sellers: Motivated Mover, Dreamer,
  Clueless Uncle...), and the PGA used section (clean, graded, priced like it). Each store has
  a nonzero chance at every collectible putter; the Grail is a flat per-listing roll
  (0.01% / 0.05% / 0.15% / 0.30%). Model, condition, price and provenance are rolled separately.
- **Restocks** happen only after a completed standard round (`GameState.complete_round`).
  Opening menus, reloading, restarting or abandoning never rerolls stock. Reserve one listing
  per store with a 10% deposit and it survives two more restocks; the deposit counts toward
  the price.
- **Unlocks** (`scripts/economy/progression.gd`): pawn shop = 2 distinct Goodwill models +
  a round at +12 or better swinging two Goodwill finds; Marketplace = 3 pawn models + +8;
  PGA = 4 Marketplace models + +4. Targets are per nine holes and scale with round length.
  Unlocks are permanent; the Objectives tab shows "Buy Goodwill clubs: 1/2 ..." progress.
- **Equipment** (`scripts/clubs.gd`, `course.gd _shot_params` / `_dispersion_deg`): bounded
  multipliers on ball speed, backspin, off-centre penalties (forgiveness), shot shaping
  (control) and a small random push on the fired shot only (dispersion, condition). The
  preview line is always the intended line. Putters differ subtly in forgiveness/control;
  nothing makes a putt drop by itself.
- **Selling**: shops offer 50-65% of fair used value (model + condition, never what you paid),
  quoted before you confirm. Selling an equipped club swaps a replacement in. No buybacks.
- **Collection**: exactly seven collectible putters (`collectible: true` in the catalog) fill
  the cabinet; missing ones are silhouettes, sold ones keep their discovery record. Owning all
  seven at once turns the cabinet gold (cosmetic). Drivers, woods, hybrids, irons and wedges
  have their own discovered/owned tallies.
- **Admin sandbox**: run with `GOLF_ADMIN=1` or `--admin` to see the Admin tab and grant the
  **Grenade Prototype Driver** (~400-yard bombs, fireball, shockwave, synthesized boom) or the
  **Auto-Putt 9000** (reads the green with the shot predictor and drops putts inside
  `auto_putt_range_m`). They never appear in loot, shops, resale or the collection, and any
  round that swings one is a sandbox round: no money, progress, records or restock.
- **Save**: `user://openfairway_save.json` (`GameState`, autoload `GolfState`). Round rewards
  are applied once per round id; purchases remove the listing before saving. Missing fields
  are filled in on load, so older saves migrate.
- **Placeholder art**: club shapes are vector silhouettes (`scripts/ui/club_silhouette.gd`)
  keyed by the catalog's `silhouette` / `finish` / `accent` fields; swap for sprites or 3D
  previews later without touching the shop or cabinet code. Not yet built: delayed
  Marketplace selling (post your own listings) and collector leads.

Headless checks:

```
godot --headless --path . --script tests/economy_loop_test.gd
godot --headless --path . --script tests/course_progression_test.gd
```

## Golf course manager

Run one of your Course Studio courses as a business in its own mode: start menu > **Course
Manager** (separate from Course Studio, which only builds courses). Tunables are in
`data/economy.json` under `manager`; rules in `scripts/economy/course_business.gd`, money and
saving in `GameState`, the mode in `scripts/manager/course_manager.gd`.

- **Unlock**: the deed ($2,500) is only sold once the PGA store is unlocked, so you have to
  play your way up as a golfer first; passive income can't shortcut the store/club ladder.
- **Your course**: any saved Course Studio course with at least 3 holes. Facilities are placed
  on a 3D view of it (Place, hover open rough, click; **Q**/**E**, **R**/**Shift+R** or the
  Turn buttons turn it, **Esc** cancels; a placed building turns where it stands from its card)
  and built / upgraded on the Facilities tab: the clubhouse (Serviceable > Expanded > Prestige >
  Grand), the cart barn, the driving range, the short game area and the parking lot, 4 levels
  each. The short game area (Practice Green > Chipping Area > Short Game Academy > Tour Short
  Game Complex) is putting and chipping greens and bunkers painted onto the course with Course
  Studio's own brushes (`FacilityBuilder.PRACTICE_TURF`: organic greens in fairway collars,
  kidney bunkers dug like the course's; a layer of the course that's never saved,
  `PaintedCourse.turf_a`), with hitting mats and a shelter; every cup has the course's cloth
  flagstick cut down to a practice pin (`size_scale`), waving in the breeze. It earns from
  locals practising and warms up a share of your golfers before they tee off. The deed comes
  with a gravel parking lot (24 spaces), set down beside the clubhouse; every space takes 0.35
  golfers an hour, so the lot caps the course until it's paved (48), landscaped (64) or a valet
  plaza (80). The ground under each plot is graded flat (cut and fill, eased back into the
  course); the course's own rough grows on it right up to the paving, floors and beds (each
  model's paving mask), with no trees.
- **Rooms**: the clubhouse holds the rooms, fitted out on the Rooms tab in 3 tiers each: pro
  shop, locker rooms and lobby from the start; restaurant and office with the Expanded
  clubhouse; ballroom and trophy lounge at Prestige; spa & fitness, simulator studio and valet
  at Grand. **V** (or the view buttons) lifts the roof off and drops the walls to see inside;
  click a room to open it.
- **Staff**: 14 roles. Rooms and facilities that name a role earn nothing without one; others
  take optional crew who each add a bonus. Hired staff work at their posts in Course Manager:
  the shop clerk, bartender and receptionist stay behind their desk or bar, chefs keep to the
  kitchen, waiters walk the dining room between the tables, greenskeepers work the holes and the
  marshal tours in a cart. Golfers the club draws come in the clubhouse's front door to check
  in, then leave by the back: out the garden door, over the deck, down the steps and along the
  covered walk to the course (the model's TEEWAY markers), some by way of the range or the short
  game area. They walk the holes carrying their bags (stood on their legs beside them while they
  play: `tools/blender/bag_stands.py`) or ride in carts with the bags on the back, one at a time
  on the tee, swinging and putting with the user's motion captures
  (`tools/blender/sources/anims/`) (`scripts/manager/club_life.gd`). People stand on what's
  under them -- floors, decks, steps, greens, paving -- from each model's walk map
  (`<type>_l<level>_walk.png`, `FacilityBuilder.walk_height`). Everyone paths
  round the furniture (walkable grids traced from each room) and, outdoors, round water, woods
  and the buildings. When you play the course yourself it's booked just for you: buildings
  only, nobody about.
- **Testing**: unlimited money (the Clubhouse's admin tab, or the "∞ $" button by Course
  Manager's wallet) keeps the wallet full; your real balance is saved aside and comes back when
  you turn it off.
- **Money**: golfers per hour come from hole count, appeal (turf condition, facilities and
  rooms), marshals, the office and how the green fee compares to the course's fair price.
  Takings: green fees, shop and restaurant spend per golfer, range buckets, cart rentals, and
  hourly events, memberships and lessons from the ballroom, spa and simulator. Costs: wages and
  upkeep, paid even while closed. One business hour = 4 real minutes, running in the background
  while the game is open; time away earns 25% for up to 4 hours. Days are 12 business hours and
  close into a 7-day ledger. Same wallet as the club shops; it never goes below $0.
- **Art**: every building level is a Blender model built by `tools/blender/build_facilities.py`
  (kit in `tools/blender/fm_lib.py`) into `assets/facilities/<type>_l<level>.gltf`;
  `scripts/facility_builder.gd` loads it and fills its markers with the club cart (the user's
  model with bag holders, `tools/blender/import_cart.py`), golf bags (`tools/blender/clean_bags.py`
  + `bag_liveries.py`: shop bags, and the bag full of clubs the golfers carry), parked cars (the
  user's car pack, `tools/blender/import_cars.py`), hedge tiles, the woodland's big bushes for the
  shrubs, nature pack plants and the
  real catalog clubs in the pro shop, plus the store props from `tools/blender/clean_props.py`
  (the club cap, two clothes racks, dressed mannequins, folded-shirt piles) and the golf ball
  packs (Pro V1 and TruFeel sleeves with their peek-a-ball windows, TP5, Chrome Tour and Chrome
  Soft dozens: `tools/blender/ball_pack_textures.py` cuts their faces from the user's die-line
  sheet into the `ball_pack_layout.py` layout, `build_ball_packs.py` builds the boxes) on the
  counter's glass case, a counter riser, the promo table, a GOLF BALLS cubby wall and a stepped
  sleeve stand, and the gym's machines (the user's equipment sets: treadmills, elliptical,
  spin bikes, bench-press racks, preacher bench, cable station and plate tree, with yoga mats,
  yoga balls and kettlebells, `tools/blender/import_gym.py`) around the dumbbell rack; the
  user's iMac on the office desk, the reception desk and the pro-shop counter and their till on
  the bars (`tools/blender/import_office_props.py`); their hot tub and massage tables in the day
  spa (`tools/blender/import_spa_props.py`). Rooms are furnished after the walls go up, so wall
  pieces (racks, shelves, pictures, lockers, vanities, showers) keep clear of every window and
  door (`clear_span()` / `doorways()` in `build_facilities.py`). Every door has a way down: the back
  garden door a railed deck and steps, service doors a landing and steps (`stoop()`), and the
  club's name is on a stone monument by the drive. Any two faces left
  in the same plane are nudged apart on export (no flicker). People: `tools/blender/build_npcs.py`
  (on top of `build_people.py`'s rig, uniforms and animations) builds the staff and golfers from
  the user's BaseModels; in a cart the driver's hands are on the wheel and a passenger's in the
  lap, put there by IK against the cart (`build_people.py` DRIVE_GRIP / CART_FEET,
  `ClubLife.SEATS`).
- **Not yet built**: the other hero buildings (maintenance compound, halfway house, academy,
  starter's hut, comfort stations, pump house) and a playable driving range; see
  `docs/course_manager_design.md`.

```
godot --headless --path . --script tests/course_business_test.gd
godot --headless --path . --script tests/manager_mode_test.gd
godot --headless --path . --script tests/club_life_test.gd
godot --path . --script tests/manager_screenshot.gd -- <out_dir> [level] [golf]
```

## Credits

- OpenFairway Physics by jesseincode & Jakobi (MIT) — `addons/openfairway/LICENSE`
- Stylized Nature MegaKit by Quaternius (CC0) — `assets/nature/LICENSE_Quaternius.txt`
- SimpleGrassTextured by IcterusGames (MIT) — `addons/simplegrasstextured/LICENSE`
- Water, sky, gradient grass and atlas grass shaders supplied by the project owner
