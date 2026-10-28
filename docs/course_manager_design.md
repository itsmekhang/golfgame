# Course Manager design (roadmap)

The full facility and systems wishlist for Course Manager mode, as written by the game's author,
followed by how it's being built in waves. Course Manager is its own mode (start menu), separate
from Course Studio, which only builds courses.

## 1. Clubhouse & core hospitality

The hub of revenue and member prestige. These can be standalone buildings or modular rooms within a
main clubhouse structure.

| Facility | Game mechanic / function | Upgrade path |
|---|---|---|
| Pro Shop | Generates retail income (balls, clubs, apparel); required before golfers can tee off. | Small Kiosk → Boutique Pro Shop → Flagship Golf Superstore |
| Locker Rooms | Boosts Hygiene and Comfort stats; required for hosting pro tournaments. | Basic Restrooms → Member Lockers → VIP Spa Lockers (Sauna/Steam) |
| Dining & Beverage | Restores Hunger/Thirst; major source of high-margin secondary revenue. | Snack Bar → 19th Hole Sports Grill → Fine Dining Steakhouse |
| Event & Banquet Hall | Generates passive weekend income via weddings, charity galas and corporate retreats. | Outdoor Pavilion → Ballroom → Grand Convention Center |
| Bag Drop & Valet | Speeds up golfer arrival-to-tee time; boosts luxury prestige rating. | Self-Park Rack → Curbside Bag Drop → Full Valet & Concierge |
| Cart Barn | Stores and charges electric/gas golf carts; determines max cart fleet size. | Open Carport → Charging Shed → Underground Garage |
| Trophy & History Room | Passive boost to Club Prestige and membership renewal rates. | Display Case → Hall of Fame Gallery |

## 2. Practice & training facilities

Golfers use these to warm up before a round (improving their mood even if they play poorly) or visit
specifically for skill-building, generating non-tee-time revenue.

- **Driving Range**: tee-off bays (turf mats vs. real grass), yardage target greens and boundary
  safety netting. Can be upgraded to a two-tier heated / Toptracer range for night revenue.
- **Putting Green**: essential low-cost warm-up zone placed near the 1st tee to prevent bottlenecks.
- **Short Game / Chipping Area**: practice bunkers and a smaller green for wedge practice.
- **Golf Academy & Swing Studio**: indoor building with launch monitors, high-speed cameras and AI
  swing simulators where Club Pros charge for high-ticket lessons.
- **Club Fitting Workshop**: custom equipment tuning, boosting Pro Shop revenue and golfer
  performance stats.

## 3. On-course amenities & functional structures

Placed along the routing to keep golfers happy, fed and safe during a 4-hour round.

- **Starter's Hut**: at the 1st (and sometimes 10th) tee to regulate pace of play.
- **Halfway House**: snack and drink shack between the 9th green and 10th tee.
- **On-Course Restrooms**: essential at holes 4–5 and 13–14 to prevent hygiene penalties.
- **Weather & Lightning Shelters**: wooden gazebos with lightning rods at the farthest points.
- **Ball Washers & Trash Cans**: micro-placeables at every tee; cleanliness, slight drive accuracy.
- **Drinking Water Stations / Coolers**: hydration in summer.
- **Yardage Markers & Tee Signs**: stone monuments or GPS kiosks showing hole layout and par.
- **Spectator Infrastructure (Tournament Mode)**: bleachers, VIP hospitality tents, leaderboards,
  media broadcast towers, rope barriers.

## 4. Course architecture & landscaping

- **Tee boxes**: Championship (Black), Back (Blue), Member (White), Senior (Gold), Forward (Red).
- **Surface brushes**: fairway, first cut, deep rough, fescue/native grass, pine straw, waste areas,
  putting green turf.
- **Bunkers**: fairway, greenside, pot bunkers, church pews.
- **Water hazards**: ponds, lakes, creeks, waterfalls, coastal ocean cliffs.
- **Walls & edging**: railway-sleeper bulkheads, stacked stone retaining walls, island-green rock borders.
- **Routing infrastructure**: cart paths, wooden footbridges, stone suspension bridges, underpass tunnels.
- **Safety & boundaries**: OB white stakes, hazard red/yellow stakes, errant-ball safety netting.

## 5. Country club & resort lifestyle

- **Racquet Sports Complex**: tennis (hard, clay, grass), pickleball, padel, tennis pro shop.
- **Aquatics Center**: leisure and lap pools, splash pad, hot tubs, cabanas, poolside tiki bar.
- **Fitness & Wellness Center**: gym, yoga/pilates studio, day spa.
- **Lodging & Real Estate**: member cottages / golf villas, resort hotel, real-estate plots along the
  boundary (big one-time cash, at the risk of homeowners complaining about broken windows).
- **Secondary recreation**: croquet, bocce, kids' club / childcare, helipad or private marina.

## 6. Back-of-house, maintenance & utilities

Usually emits a "negative noise/sightline" radius that must be hidden behind trees or hills.

- **Greenskeeper Compound**: mower fleets, aerators, grounds-crew rooms.
- **Material Storage Bays**: topdressing sand, mulch, gravel, sod.
- **Chemical & Fertilizer Silos**: turf disease and green speed (Stimpmeter).
- **Irrigation**: pump house, pipes and sprinkler heads (droughts turn turf brown).
- **Sub-Air & Drainage** under greens.
- **Driving Range Picker Shed**: ball-picker tractors and ball washers.
- **Power & Waste**: substations, solar arrays, compost heaps, dumpster enclosures.
- **Parking Lots**: standard, VIP, staff, overflow grass lots; EV charging.

## 7. Hero buildings with 4-level progressions

Every outdoor facility grows through four levels on a plot sized for its top level. The
clubhouse and the cart barn follow the author's concept art (shingle style: grey cedar shingles,
steep grey roofs with dormers, white trim and columned porches, brick chimneys).

- **Clubhouse**: Lv1 Serviceable (Cape Cod with pro shop, restrooms, members' lobby) → Lv2
  Expanded (wrap-around colonnaded porch, restaurant + kitchen, office) → Lv3 Prestige (grand
  gable pediment, multi-tier balcony, ballroom, lounge, locker rooms, reception, circle drive) →
  Lv4 Grand (spa & fitness, indoor simulator wing, valet lobby / porte-cochère, terraced patio,
  fountain drive). The pro shop, dining, locker rooms, lounge, ballroom, spa, simulator and valet
  are **rooms inside it**, each with its own 3-tier upgrade path from section 1. Manager view:
  lift the roof / drop the walls (The Sims / Cities: Skylines) to see and upgrade rooms and watch
  employees work.
- **Cart Barn** (front of house): Lv1 Basic Shed (2 bays, gravel pad, fence) → Lv2 Standard Barn
  (4 charging bays, cart-return apron, wash station, office) → Lv3 Expanded Garage (cross gable,
  dormers, side wing) → Lv4 Prestige Operations (office building, covered cart canopy, marked lot,
  flags, entrance sign, fenced electrical substation, staff parking).
- **Agronomy / Maintenance Compound ("The Boneyard")**, separate from the cart barn, hidden behind
  trees: Lv1 Grounds Shed (small wooden garage, push mowers, a dirt/sand pile) → Lv2 Greenskeeper
  Yard (3-bay equipment shed, fenced gravel lot, concrete bins for sand/mulch, fuel tank) → Lv3
  Agronomy Center (L-shaped maintenance building, mechanic lift bay, covered mower ports,
  chemical silos, staff breakroom) → Lv4 Championship Turf Complex (20+ mowers/rollers, automated
  wash rack, soil lab office, greenhouse for nursery sod). Visuals: metal/shingle sheds, triplex
  greens mowers, fairway units, tractor-pulled rough mowers, open concrete bays of bunker sand /
  topdressing / gravel, fuel tanks, chemical lockup.
- **Halfway House (Turn Shack)** between the 9th green and 10th tee: Lv1 Refreshment Stand
  (wooden walk-up kiosk, umbrella table, ice coolers) → Lv2 Turn Shack (shingled cottage, walk-up
  window, attached restrooms, small brick patio) → Lv3 Halfway Pavilion (wrap-around porch,
  outdoor grill, covered bar stools, cart pull-off lane) → Lv4 10th Tee Grill & Comfort Station
  (indoor/outdoor lounge, stone fireplace, luxury restrooms, grab-and-go market).
- **Golf Academy / Teaching & Fitting Studio** at the end of the range tee line: Lv1 Covered
  Hitting Bay (wooden awning over 2 mats, ball dispenser cage, picker shed) → Lv2 Teaching Studio
  (indoor-outdoor bay with roll-up door, video cameras, ball wash/storage) → Lv3 Performance &
  Fitting Center (3-bay shingle building, roll-up glass doors onto the range, launch monitors,
  club workshop) → Lv4 Tour Academy Complex (two-storey horseshoe/winged building, heated covered
  bays, VIP fitting suites, indoor putting lab, viewing deck).
- **Starter's Hut & Caddie Master** between the putting green and 1st tee: Lv1 Starter Podium
  (podium, umbrella, tee sheet, ball washer / scorecard box) → Lv2 Starter's Booth (shingle kiosk,
  clock tower / bell, digital tee-time board) → Lv3 Starter Pavilion & Bag Staging (covered bag
  racks, ice/towel station, waiting bench) → Lv4 Caddie Master & Sanctuary House (cottage with the
  starter desk, caddie lounge / bib lockup, antique clock).
- **On-course Comfort Stations & Weather Shelters** (small 1x1 / 2x2 tiles near holes 4–5 and
  13–14): port-a-potty enclosure → wooden gazebo & water cooler → plumbed shingle restroom cottage
  → luxury comfort station (restrooms + free snack/drink pantry).
- **Irrigation Pump House** snapping onto a water hazard's edge: stone or shingle utility building
  with intake pipes into the water, transformers and pressure tanks. Upgrades raise water-pressure
  capacity (more holes irrigated at once) and unlock Sub-Air green cooling.

---

## Build plan

Phase 1 (built): the deed gate (PGA store unlocked + $2,500), choosing the club's Course Studio
course, placing / building / upgrading facilities, staff, green fee, real-time books.
Code: `scripts/economy/course_business.gd`, `scripts/manager/course_manager.gd`,
`scripts/facility_builder.gd`; tunables in `data/economy.json` "manager".

- **Wave 1 (built)**: Blender models with real textures for the Clubhouse (Lv1–4 shells with
  furnished interiors; every room in 3 tiers; roof and upper walls lift off), the Cart Barn and
  the Driving Range (Lv1–4); the room-based economy (`rooms` in economy.json, 13 staff roles);
  graded building plots; the Sims-style cutaway in Course Manager (V: building / roof off / walls
  down, click a room); the pro shop stocked with the real catalog clubs and the club's golf bags
  (cleaned scans + liveries); stylized animated staff at their posts and golfers playing the
  holes on foot with their bags or in carts (`scripts/manager/club_life.gd`). Tools:
  `tools/blender/make_textures.py`, `fm_lib.py`, `build_facilities.py`, `build_people.py`,
  `clean_bags.py`, `bag_liveries.py`.
- **Wave 2**: section 7's other hero buildings (Maintenance Compound, Halfway House, Golf
  Academy, Starter's Hut, Comfort Stations, Pump House) and the practice facilities (Putting Green,
  Short Game Area), all 4 levels; the driving range rebuilt in the new style.
- **Wave 3**: golfers as simulated visitors with needs (hunger, thirst, hygiene, comfort, mood;
  prestige and membership) visiting the rooms between rounds, a follow-cam spectate view;
  section 3 amenities.
- **Wave 4**: back-of-house and utilities (noise/sightline, irrigation, turf, Stimpmeter), weather.
- **Wave 5**: tournaments (spectator infrastructure) and the resort lifestyle (section 5).
- Course-building items in section 4 belong to Course Studio.
