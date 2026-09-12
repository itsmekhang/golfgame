# Augusta National: a construction brief for Claude and Godot

This brief describes all 18 full-hole paintings and all 18 green close-ups in `hole diagrams.zip`. It also checks `augusta full map.webp`, `hole_maps_check.png`, and `hole info.txt`. Its purpose is to turn the references into distinct, playable landforms rather than eighteen flat fairway ribbons.

## Read the evidence correctly

Three labels distinguish what is known from what is being designed:

- **Observed:** a shape, object, relationship, or tonal pattern visible in the supplied images. Image coordinates are approximate visual readings, not surveyed positions.
- **Corroborated:** a broad course characteristic checked against the linked published description. Older descriptions are used for enduring landforms, not to override the supplied yardages or current objects.
- **Proposed:** an explicit reconstruction choice where the images do not provide measurements. All numerical terrain heights, green dimensions, slopes, transition widths, and fairway widths below are proposed starting values. They are not Augusta survey data.

These are shaded plan illustrations and oblique rendered close-ups, not contour maps. Painterly light and shade communicate curvature, but do not uniquely encode altitude. A broad light patch can be a slope facing the light, rather than the highest point. A dark patch can be a shaded slope, a hollow, rough grass, or a tree shadow. Do not convert image brightness directly into terrain height.

The small yellow symbols resemble pin/flag markers, have no supplied legend, and mostly point the same way. The No. 17 close-up even places one over sand. **Do not use their direction as slope vectors, their number as a count of green tiers, or every marked position as a valid cup location.** Put one active cup on a verified part of the putting surface; choose candidate positions after sculpting.

## Translating the painted shading into geometry

| Visual cue | Geometric reading | Construction instruction |
|---|---|---|
| Broad highlight gradually turning into a broad dark flank | A rounded shoulder or long change of slope is plausible | Build an elongated, smooth landform. Read the pair as one feature; do not create a bright hill and an unrelated dark pit. |
| Several highlight/shadow pairs separated by softer gaps | A chain of lobes with saddles between them | Give each lobe its own center, radius, height, and overlap. Keep the saddles lower than both adjacent crests. No regular sine-wave row. |
| A long, continuous tonal band across the playing line | A crest, terrace face, or valley transition is plausible | Model the change in longitudinal slope over a finite distance; check it from ball height. The sign needs surrounding evidence or corroboration. |
| A narrow dark edge around pale putting turf | Collar, edge shading, or a small grade transition | It does not justify a vertical wall. Blend green, collar, and surrounding terrain continuously except at intentionally steep banks. |
| A bright raised-looking rim next to an enclosed gray-white hollow | Bunker lip above a concave sand floor | Lower the sand floor and vary the rim. Preserve grass fingers and lobes. The white area is not a mound. |
| Crisp, branching dark shapes aligned with nearby trunks | Cast tree shadow | Keep it in lighting. No tree-shaped trenches or raised silhouettes in the terrain. |
| Dense green stippling and brown patches inside tree groups | Rough/understory and exposed soil or pine straw | Use surface materials and vegetation placement; do not interpret their texture as meter-scale bumps. |
| White or blurred outer perimeter | Illustration fade/background | Continue ordinary terrain beyond it. Do not build white ground, cliffs, snow, or a moat at the image edge. |

The strongest mound pattern is around No. 8. No. 14's green contains internal light/dark lobes that call for distinct surface regions. No. 9 and No. 18 need longitudinal slope transitions; No. 16 needs cross-slope. These are different kinds of geometry and must not share one generic hill function.

## Coordinate and scale contract

1. **Image coordinates:** `u` runs left to right from 0 to 1; `v` runs top to bottom from 0 to 1. They always refer to the entire original `hole-map-N.jpg`, including its white margins. An anchor `(0.75, 0.40)` means 75% across and 40% down that particular image.
2. **Golf directions:** left/right in the hole descriptions mean the golfer's left/right while facing the next target. Green front is the approach side; green back is beyond the putting surface. Where the close-up camera differs, the text explicitly says **screenshot-left**, **screenshot-right**, **top**, or **bottom**.
3. **Green registration:** rotate a close-up using at least two bunker/water landmarks before transferring its details. Never assume all close-ups have the same compass direction. No. 13 especially is viewed obliquely from the creek side. Do not mirror the image to make it fit.
4. **Longitudinal coordinates:** `s=0` is the selected championship tee and `s=1` is green center, measured along the proposed golf routing polyline. This is a distance reference for landforms, not a cart path. A shot segment can cross water or sand. Do not paint a fairway along every segment.
5. **Godot coordinates:** use meters. A convenient initial local mapping is image-right = `+X`, image-down = `+Z`, height = `+Y`. Account for the original image's width and height before measuring distance: normalized u and v do not have the same meter scale on a panoramic image.
6. **Length:** retain `hole info.txt` yardages. Convert with `meters = yards × 0.9144`. Sum distances in original-pixel space along the routing anchors, then use `meters_per_pixel = target_length_m / polyline_length_px` for an initial plan scale. Recheck after smoothing the routing. The illustrated widths are not a survey; tune transverse widths separately if necessary and document the change.
7. **Existing check sheet:** its printed meter/pixel factors are rounded and apply to the original corresponding images, not to resized previews. It shows No. 17 as 440 yards, while the supplied data says 450. Use 450. Its orange points are routing marks, not contour measurements.

For a whole-course map, use the full-course image to establish adjacency and overall rotation. Do not glue the independently scaled white-edged illustrations together. Work in a shared terrain system; fit each detailed hole to the routing, reconcile shared ridges and drainage, and blend surrounding land. The local elevation profiles below each start at zero independently; they cannot be pasted together as global elevations.

## Terrain construction requirements

Build four coordinated layers: broad course relief; fairway-scale shoulders and hollows; the green complex with banks and bunker excavations; and the putting surface's own slopes. Keep each editable. A useful conceptual model is `height = broad_relief + local_landforms + green_complex`, with smooth footprint masks to blend features and prevent unrelated hills affecting neighboring holes. Do not add the same base elevation twice inside the green mask.

Use named landforms with explicit locations. Examples: `h08_left_mound_chain`, `h09_front_runoff`, `h10_low_fairway`, `h13_creek_bank`, `h16_upper_right_shelf`. Broad hills should use elongated footprints and unequal shoulders. A terrace has a relatively gentle shelf connected to another shelf by a steeper smooth transition; it is neither a vertical step nor a single tilted plane.

**Proposed starting resolutions:** 2–4 m across distant surrounding terrain; 0.75–1.5 m across playable fairways; 0.20–0.50 m over greens, bunker lips, and important short-game banks. Refine where curvature requires it. Use smooth normals, but verify the actual triangle geometry and collision. A normal map cannot produce a lie or a putting break.

**Proposed putting parameters:** typically 0.5–3% on candidate pin shelves, with 4–8% transitions in selected steeper contour bands. Percent is rise/run: 3% means 0.30 m over 10 m, not 3 degrees. The named shelf-to-shelf height changes are more important than applying these ranges uniformly. Keep cup candidates away from steep transitions. Collar width can begin at 0.8–1.5 m; apron width should vary with the hole, rather than forming a uniform concentric ring.

**Bunkers:** make separate concave excavations with irregular outlines, not white decals or raised sand islands. Preserve the number of connected sand bodies. Lower floors roughly 0.5–1.5 m from nearby rims initially; some deep fairway bunkers can begin at 1.5–2.5 m. Vary lip height and entry slope; do not surround every bunker with the same circular wall. These are modeling proposals, not measured depths.

**Water:** give ponds a level water surface, a basin underneath, and banks that meet the terrain. The creek is a channel with a bed and connected banks; use a modest, consistent downstream grade where the references do not resolve exact levels. Model bridges separately above the channel. Water elevation must be chosen together with adjoining green/runoff elevations.

**Trees:** place groups from the observed woodland footprints, then vary species silhouettes, trunk spacing, crown size, and understory within them. Preserve key isolated trees and openings. Set trunk bases on the terrain and keep fairways clear where the source is clear. Pink/white/red flowering patches are accents within a predominantly green setting.

## Godot implementation notes

Keep the existing project's Godot version and terrain approach unless it cannot represent these features. In Godot 4, `ArrayMesh` or `SurfaceTool` can generate persistent terrain meshes; `SurfaceTool` provides normal generation. Use the correct triangle winding and generate normals after the vertices/indices are ready. [Godot procedural geometry](https://docs.godotengine.org/en/stable/tutorials/3d/procedural_geometry/index.html), [SurfaceTool](https://docs.godotengine.org/en/stable/classes/class_surfacetool.html).

Derive rendered ground and collision from the same height/mesh data. If using `HeightMapShape3D`, match its centered grid, cell spacing, scale, and triangle layout; consult the project's physics backend before scaling it. It cannot represent overhangs. Use separate bridge/cup meshes and appropriate collision. Store authored height fields in floating-point data or suitable EXR/HDR formats; the documented 8-bit import path can create terracing. [HeightMapShape3D](https://docs.godotengine.org/en/stable/classes/class_heightmapshape3d.html).

Make a debug mode that displays surface type, elevation contours generated from the actual mesh, and downhill vectors computed from its gradient. Place a resting/rolling ball on each important slope to verify direction. Disable wind during these checks. If gravity and collision are already handling the slopes, do not add a second artificial downhill force on top.

## Completion contract for Claude

Treat every hole section below as an implementation requirement. Shared helper functions are fine; cloned hole geometry is not.

For each hole, deliver its route, traced turf/hazard boundaries, named terrain features, specific green footprint and surface, tree groups, working terrain collision, one playable cup, and the hole-specific checks. Use the accompanying JSON as a locator and parameter sheet; it is not a complete mesh or a surveyed heightmap. Trace the supplied images for boundaries instead of promoting a center point into an oval.

Provide five review views per hole: plan view; tee at golfer eye height; approach at golfer eye height; a low side view exposing major relief; and a green close-up with computed contour/downhill overlays. Also show the green from the opposite side where a shelf could be hidden. Render with neutral diagnostic lighting before judging the final material lighting.

Do not claim a feature is complete because it looks shaded from above. Show that it changes the silhouette, surface normal, ball lie, and rollout where applicable. If the environment cannot render or run the project, state that precisely and leave the appropriate check marked unverified. Do not fabricate screenshots or test results.

Build in this order: establish all routing and shared broad relief; complete Nos. 6, 8, 9, 13, 14, and 16 to prove the distinct terrain systems; finish the remaining holes; reconcile the shared course edges; then add final vegetation and lighting. Continue through all 18; the first six are an implementation sequence, not a reduced scope.

The per-hole height profiles are deliberately concrete **proposals** so work can proceed. Change them when better reference evidence appears, recording the reason. Preserve the named landform relationships even if you adjust the numbers.

## Handoff data

The companion `hole_blueprints.json` includes 44 sand footprints derived from the supplied images, individually assigned to their owning hole. It also includes route and water locators, original image dimensions, green shape notes, and proposed terrain profiles. Sand boundaries were isolated from the illustrations and simplified; use their irregular outlines as starting footprints, then add the grass lip and depth in 3D. No. 12's larger rear bunker is partly hidden by canopy: its visible main body has a smooth estimated edge, explicitly flagged in the JSON, rather than leaf-shaped sand fingers. Other canopy-covered edges represent visible extent only. These are not surveyed ground boundaries. Fairway, green, water, and tree boundaries still need their own shapes; their locators must not be expanded into generic circles.

## Hole index

| Hole | Name | Par | Yards | Owned bunkers |
|---|---|---:|---:|---:|
| 1 | Tea Olive | 4 | 445 | 2 |
| 2 | Pink Dogwood | 5 | 585 | 3 |
| 3 | Flowering Peach | 4 | 350 | 5 |
| 4 | Flowering Crab Apple | 3 | 240 | 2 |
| 5 | Magnolia | 4 | 495 | 3 |
| 6 | Juniper | 3 | 180 | 1 |
| 7 | Pampas | 4 | 450 | 5 |
| 8 | Yellow Jasmine | 5 | 570 | 1 |
| 9 | Carolina Cherry | 4 | 460 | 2 |
| 10 | Camellia | 4 | 495 | 2 |
| 11 | White Dogwood | 4 | 520 | 1 |
| 12 | Golden Bell | 3 | 155 | 3 |
| 13 | Azalea | 5 | 545 | 4 |
| 14 | Chinese Fir | 4 | 440 | 0 |
| 15 | Firethorn | 5 | 550 | 1 |
| 16 | Redbud | 3 | 170 | 3 |
| 17 | Nandina | 4 | 450 | 2 |
| 18 | Holly | 4 | 465 | 4 |

Total: **par 72, 7,565 yards, 44 owned bunker bodies** in the supplied hole set. Neighboring No. 12 sand visible in No. 13's illustration is counted only once.


---

## 01 — Tea Olive

**Par 4 · 445 yd · 406.9 m nominal routing length.**

**Identity:** an uphill opening hole with a subtle rightward bend and an uneven green complex. Corroborated: uphill, slight dogleg right. [Course description](https://www.golfmonthly.com/tour/us-masters/augusta-course-guide-27876).

**Observed plan.** The tee occupies the broad open left end. Two pale tee rectangles are visible. The playable corridor narrows between a long woodland mass above the fairway and a more irregular, closer woodland edge below it. The latter protrudes into the landing zone. A single connected, lobed fairway bunker sits against that lower edge, on the golfer's right. The approach then bends slightly toward the lower-right green. One curved greenside bunker guards the approach-left edge. There is no water.

**Read the shading.** The broad light-dark changes through the opening and middle fairway suggest rolling shoulders, not a perfectly even uphill ramp. Near the right fairway bunker, the bright turf and darker adjoining flank should read as a shoulder containing a cut-in sand hollow. Around the green, alternating broad patches imply several changes of surface direction; the perimeter's darker halo alone is not evidence of a raised wall.

**Proposed terrain.** Let the first part of the hole dip gently from the tee before the sustained climb. Introduce a broad crest in the landing area around `s=0.60–0.70`, with the right bunker cut into its side. Follow it with a gentler rising approach. Make the green complex a rounded shoulder of that larger hill, rather than a mound dropped on top of a flat fairway. Blend the right and rear surroundings into rough and trees.

**Green.** The close-up shows a rounded, irregular outline: a broad rear portion, a somewhat narrowing front, and a left indentation beside the curved bunker. Preserve that asymmetry. Start with an overall back-to-front tendency, then add two low, intersecting rolls so the front-left, front-right, and back regions do not all share one plane. Proposed internal relief: approximately 0.35–0.70 m, spread over broad transitions. Keep plausible pin shelves between the rolls; do not infer their heights from the yellow markers.

**Bunkers and vegetation.** Retain the fairway bunker's connected three-lobed silhouette and the greenside bunker's long hooked outline. Keep the near-right tree line intrusive and the early tee clearing open. Do not ring the entire green with equally spaced trees.

**Acceptance checks.** From the tee, the terrain must rise beyond an initial low section. A ball crossing the landing shoulder should encounter a change in grade. The two bunkers must occupy different stages of the hole. A diagonal putt should respond to more than one surface direction, without small random bumps.

### Locator and starting-parameter sheet

Image coordinates refer to the full original hole painting. They are approximate; the original dimensions are 4970 × 1620 px.

**Golf routing:** (0.100, 0.487) → (0.290, 0.465) → (0.480, 0.415) → (0.640, 0.435) → (0.750, 0.510) → (0.854, 0.569).

**Owned bunker locators:** fairway_right (0.597, 0.486); green_left (0.830, 0.491). The JSON contains each visible sand outline.

**Proposed green envelope:** 32 m across the final approach × 30 m along it; internal relief approximately 0.35–0.70 m. These are editable reconstruction dimensions, not measurements.

**Proposed longitudinal terrain/bed profile:** local tee = 0 m. Keep water surfaces separate from this ground profile.

| Fraction s | Height Y (m) |
|---:|---:|
| 0.00 | +0.0 |
| 0.15 | -2.0 |
| 0.35 | +2.0 |
| 0.62 | +10.0 |
| 0.78 | +12.0 |
| 0.93 | +15.0 |
| 1.00 | +16.0 |

**Named landforms to implement:** `h01_opening_dip`, `h01_landing_crest`, `h01_rising_green_shoulder`.


---

## 02 — Pink Dogwood

**Par 5 · 585 yd · 534.9 m nominal routing length.**

**Identity:** a long descending dogleg left, ending in a broad, winged target. Corroborated: downhill, dogleg left. [Course description](https://www.golfmonthly.com/tour/us-masters/augusta-course-guide-27876).

**Observed plan.** Start in the upper-left wooded tee pocket. The corridor runs diagonally down and right, opens into a broad lower fairway, then curves back up toward the green at the far right. That is the left-turning golf route when viewed along the direction of travel; it is not a straight horizontal strip. A large wooded mass forms the inside corner above the fairway. One bean-shaped bunker occupies the outer/right landing-zone edge. Two separate bunkers frame the front-left and front-right of the green. No water is shown.

**Read the shading.** The landing zone is wide but uneven: broad tonal fields connect the descent to a flatter-looking approach, while the green surrounds contain smaller lobes. Do not turn the inside woodland into a single artificial mountain or flatten the entire open lower half of the image.

**Proposed terrain.** Hold the tee on an upper bench, descend through the initial corridor, then make a long rounded downslope through the dogleg. Reduce the longitudinal grade toward the final approach. Add a broad, mild cross-slope into the inside/left half, with a separate shoulder around the right bunker. Keep enough level change that a well-directed drive can gain rollout; avoid a sheer break that launches every ball.

**Green.** In the close-up the putting outline resembles a rounded Y or wishbone: a forward tongue between the bunkers opens into wide left and right rear wings. The right bunker is larger and has a pronounced inward notch; the left is longer and curved. Do not replace the surface with a circular green centered between identical bunkers. Proposed sculpt: a slightly raised central junction and right wing, with a shallow lower route toward the front/left portion, using roughly 0.50–0.90 m of total internal relief. Make the wing-to-wing transition broad enough for a ball to travel across it. This is a reconstruction choice, not a surveyed break map.

**Vegetation.** Preserve dense woods at the inside of the dogleg, pink flowering accents along both corridor edges, and more scattered trees in the open approach-right surroundings.

**Acceptance checks.** The tee-to-green profile must show sustained descent, not just a lowered green. The right fairway bunker must be distinct from both greenside bunkers. The green must retain three recognizable outline lobes and a narrow forward entrance, with different lies across its wings.

### Locator and starting-parameter sheet

Image coordinates refer to the full original hole painting. They are approximate; the original dimensions are 4337 × 1792 px.

**Golf routing:** (0.074, 0.211) → (0.230, 0.475) → (0.440, 0.670) → (0.650, 0.670) → (0.800, 0.560) → (0.895, 0.437).

**Owned bunker locators:** fairway_right (0.506, 0.745); green_left (0.864, 0.420); green_right (0.891, 0.503). The JSON contains each visible sand outline.

**Proposed green envelope:** 40 m across the final approach × 30 m along it; internal relief approximately 0.50–0.90 m. These are editable reconstruction dimensions, not measurements.

**Proposed longitudinal terrain/bed profile:** local tee = 0 m. Keep water surfaces separate from this ground profile.

| Fraction s | Height Y (m) |
|---:|---:|
| 0.00 | +0.0 |
| 0.15 | -3.0 |
| 0.35 | -12.0 |
| 0.60 | -21.0 |
| 0.85 | -25.0 |
| 1.00 | -24.0 |

**Named landforms to implement:** `h02_tee_bench`, `h02_long_dogleg_descent`, `h02_bunker_outer_shoulder`, `h02_flattening_approach`.


---

## 03 — Flowering Peach

**Par 4 · 350 yd · 320.0 m nominal routing length.**

**Identity:** a short hole whose small, awkwardly shaped green and surrounding relief provide the main challenge. Corroborated: green falls generally from the golfer's right toward the left. [Course description](https://www.golfmonthly.com/tour/us-masters/augusta-course-guide-27876).

**Observed plan.** The tee begins at the left; the hole is largely straight, with the green offset slightly toward the lower-right. A long thin tree island lies above the early fairway. Four separate fairway bunkers form a compact, irregular group above the central-to-late landing zone: two smaller bodies, one elongated curved body, and a separate oval-like body. These are on the golfer's left. A fifth bunker guards the green's left approach edge. A pair of small tree groups sits below the early/middle corridor; denser woods wrap the far end.

**Read the shading.** This image contains conspicuous localized lobes around the fairway bunker group and around the green. The brighter cap beyond/right of the green, next to a dark curved flank, is a plausible raised surround. The four sand bodies sit in distinct hollows separated by grass saddles; do not merge them into one trench.

**Proposed terrain.** Keep the opening more gently rolling, then build a low shoulder around the fairway bunker group. Rise into a small elevated green complex over the last fifth of the hole. The approach-front bank should fall away enough to reject a short or spinning shot. Put a separate rounded mound outside the green on its right/rear side and preserve a lower recovery area toward the left. Use 1–2 m relief for the surrounding small mounds, rather than repeating that amplitude across the putting surface.

**Green.** The close-up has a broad near portion and an extended, narrower rear-right lobe; the left side pinches inward. Preserve the triangular/pear-like asymmetry and the tight left-hand target beside sand. Raise the golfer's right portion and connect it to a lower left/front shelf through a smooth cross-slope. Proposed internal relief: 0.60–1.00 m. Add a mild front falloff, but keep the dominant cross-slope legible. The turf outside the edge may be steeper than the putting surface itself.

**Acceptance checks.** Count exactly four fairway bunkers plus one greenside bunker. Show the narrow left green region, the wider opposing region, and the separate raised surround. A slow ball released from the higher right region should move toward the left; a ball leaving the front should encounter the approach bank rather than a flat apron.

### Locator and starting-parameter sheet

Image coordinates refer to the full original hole painting. They are approximate; the original dimensions are 4342 × 1714 px.

**Golf routing:** (0.085, 0.563) → (0.340, 0.550) → (0.570, 0.575) → (0.760, 0.610) → (0.881, 0.630).

**Owned bunker locators:** fairway_left_a (0.629, 0.371); fairway_left_b (0.617, 0.432); fairway_left_c (0.653, 0.420); fairway_left_d (0.691, 0.404); green_left (0.884, 0.481). The JSON contains each visible sand outline.

**Proposed green envelope:** 30 m across the final approach × 22 m along it; internal relief approximately 0.60–1.00 m. These are editable reconstruction dimensions, not measurements.

**Proposed longitudinal terrain/bed profile:** local tee = 0 m. Keep water surfaces separate from this ground profile.

| Fraction s | Height Y (m) |
|---:|---:|
| 0.00 | +0.0 |
| 0.25 | -1.0 |
| 0.50 | +1.0 |
| 0.72 | +2.0 |
| 0.90 | +4.0 |
| 1.00 | +6.0 |

**Named landforms to implement:** `h03_fairway_bunker_shoulders`, `h03_front_runoff`, `h03_right_rear_green_mound`.


---

## 04 — Flowering Crab Apple

**Par 3 · 240 yd · 219.5 m nominal routing length.**

**Identity:** a long downhill par three with a broad rear green and a narrow entrance. Corroborated: downhill. [Course description](https://www.golfmonthly.com/tour/us-masters/augusta-blog/augusta-national-hole-names-88155).

**Observed plan.** Two tee pads sit at the left, separated longitudinally. There is an extensive rough carry before a broad, short-grass apron begins around the middle of the illustration. Woodland encloses both sides; this is not a par-four fairway with a landing bunker halfway along it. The green at the right has a T-like outline: a wide back bar and a forward tongue. A smaller elongated bunker guards the golfer's front-left; a larger irregular bunker guards the front-right. There are two sand bodies and no water.

**Read the shading.** The large tonal transitions in the apron indicate a smoothly changing approach grade. The green's broad transverse band should become a surface change, not a stripe in the grass material. Tree-shaped shadows near the rear of the close-up are lighting, not green contours.

**Proposed terrain.** Build an elevated tee bench, a broad descending middle slope, and a gentler final apron. The green can be raised above its immediate surroundings while remaining below the tee; keep those two scales separate. Give the two front bunkers distinct bowls and lips, with a narrow turf route between them. Surrounding ground should blend into the forested banks instead of ending in a stadium wall.

**Green.** Register the close-up using the skinny left bunker and larger right bunker. Preserve the long rear-left-to-rear-right span and the narrow central front tongue. Corroborated: the green generally falls toward its front. [Green description](https://www.golfmonthly.com/tour/us-masters/augusta-course-guide-27876). Proposed sculpt: a broad rear shelf 0.50–0.90 m above the entrance, with a gently curved transition through the middle and a modest local difference between its rear corners. Avoid creating four separate abrupt tiers merely because the outline has several corners.

**Acceptance checks.** The eye-height tee view must visibly look down toward the target. The full carry must remain mostly rough until the apron shown in the image. The green's usable depth must vary across its width. Approaches toward the side wings should interact differently with the two unequal bunkers.

### Locator and starting-parameter sheet

Image coordinates refer to the full original hole painting. They are approximate; the original dimensions are 4684 × 1930 px.

**Golf routing:** (0.151, 0.504) → (0.530, 0.500) → (0.816, 0.534).

**Owned bunker locators:** green_front_left (0.802, 0.378); green_front_right (0.784, 0.572). The JSON contains each visible sand outline.

**Proposed green envelope:** 38 m across the final approach × 27 m along it; internal relief approximately 0.50–0.90 m. These are editable reconstruction dimensions, not measurements.

**Proposed longitudinal terrain/bed profile:** local tee = 0 m. Keep water surfaces separate from this ground profile.

| Fraction s | Height Y (m) |
|---:|---:|
| 0.00 | +0.0 |
| 0.15 | -1.0 |
| 0.45 | -7.0 |
| 0.75 | -11.0 |
| 0.92 | -10.5 |
| 1.00 | -10.0 |

**Named landforms to implement:** `h04_elevated_tee`, `h04_descending_carry`, `h04_local_green_platform`.


---

## 05 — Magnolia

**Par 4 · 495 yd · 452.6 m nominal routing length.**

**Identity:** an uphill left-turning hole with two conspicuous inside-corner fairway bunkers. Corroborated: uphill dogleg left; green generally falls toward the front. [Course description](https://www.golfmonthly.com/tour/us-masters/augusta-course-guide-27876).

**Observed plan.** A wooded tee clearing occupies the far left, with another tee pad farther along. The defined fairway starts later, around a third of the image width, widens into the lower-middle portion, then bends upward toward the upper-right green. Two long, narrow sand bodies stand next to each other at the upper/inside edge of the landing zone. One small bunker sits beyond the green on its rear-left side after registration with the close-up. No water is shown.

**Read the shading.** The fairway contains multiple broad rolls, including a highlighted shoulder at its beginning and another through the landing area. The two fairway bunkers are sunk into a rising bank: their long dark-side edges imply real depth. At the green, the pale crescent and darker central swale suggest a shaped surface, not a plain disk.

**Proposed terrain.** Start with a moderately rising tee corridor, widen onto a rounded landing shoulder, then climb more strongly around and beyond the bunker pair. Leave the outer/right side as a sloping alternative route; do not put both bunkers in the center of a symmetrical fairway. Build a broad elevated green complex at the end of the climb. Smooth the approach into that shoulder and allow the outer rough to fall away.

**Green.** The close-up shows a broad rounded front body narrowing toward the back, with the rear-left bunker eating into that back region. Preserve the small concavity on that side. Make the surface generally descend toward the approach, then add a diagonal shoulder through its middle so the rear and side regions differ. Proposed internal relief: 0.70–1.20 m; use gradual shelf transitions rather than a crater centered on the green. The small bunker should remain behind the green's main front body, not be moved into the approach entrance.

**Vegetation.** Both sides are strongly enclosed, with flowering accents concentrated along woodland edges. The inside-corner trees influence the second-shot view; retain their intrusion without placing random trunks in the fairway.

**Acceptance checks.** Both deep fairway bunkers must be separate, elongated, and on the inside/left of the bend. Show the uphill approach from a low camera. The green must have one rear bunker and a sloped front entrance; do not produce a front-bunkered copy of No. 4.

### Locator and starting-parameter sheet

Image coordinates refer to the full original hole painting. They are approximate; the original dimensions are 4685 × 1763 px.

**Golf routing:** (0.104, 0.422) → (0.340, 0.548) → (0.560, 0.640) → (0.700, 0.580) → (0.866, 0.350).

**Owned bunker locators:** fairway_left_a (0.559, 0.538); fairway_left_b (0.593, 0.529); green_rear_left (0.885, 0.282). The JSON contains each visible sand outline.

**Proposed green envelope:** 31 m across the final approach × 34 m along it; internal relief approximately 0.70–1.20 m. These are editable reconstruction dimensions, not measurements.

**Proposed longitudinal terrain/bed profile:** local tee = 0 m. Keep water surfaces separate from this ground profile.

| Fraction s | Height Y (m) |
|---:|---:|
| 0.00 | +0.0 |
| 0.20 | +2.0 |
| 0.42 | +6.0 |
| 0.65 | +10.0 |
| 0.84 | +14.0 |
| 1.00 | +18.0 |

**Named landforms to implement:** `h05_first_fairway_roll`, `h05_inside_bunker_bank`, `h05_upper_green_complex`.


---

## 06 — Juniper

**Par 3 · 180 yd · 164.6 m nominal routing length.**

**Identity:** a short downhill shot from a high tee into a compact, strongly shaped target. Corroborated: downhill. [Course description](https://www.golfmonthly.com/tour/us-masters/augusta-blog/augusta-national-hole-names-88155).

**Observed plan.** One long tee platform sits at the left. A rough hillside separates it from the large irregular mown area around the green. The green occupies the far-right half of that apron. One connected, highly lobed bunker lies in front and toward the golfer's left. Flowering shrubs gather around the tee; trees wrap the upper and right edges. An isolated tree is visible near the lower/front apron edge. No water exists in this supplied version.

**Read the shading.** Broad apron bands support a rolling descent. The green painting has a brighter far-right cap next to a darker inward band, while the close-up shows an irregular four-sided footprint, wider in its rear region. Together these support a distinct raised region and a lower body, but do not supply a contour interval or prove an exact shelf boundary.

**Proposed terrain.** Give the tee a genuinely high bench, then a substantial sloping foreground; do not achieve the whole effect by sinking only the green. Let the lower apron flatten before rising locally into the green platform. Use the profile table as a starting point, keeping the target well below the tee. The single front bunker should cut into the platform rather than sit on the downhill plane as a flat white shape.

**Green.** Make a broad lower front/left body, a distinct raised back-right shelf, and a curved connecting face. For the initial reconstruction, give the shelf 0.8–1.3 m of rise over the lower body and spread the transition over roughly 5–9 m. Keep a relatively gentle usable area on top; it should be a shelf rather than a sharp cone. Add a smaller roll across the remaining surface so the whole lower body is not perfectly level. The proposed back-right placement is a modeling interpretation, not a measured contour recovered from the screenshot.

**Acceptance checks.** Show the green from both the tee and the low opposite side. Those views must reveal the tee's overall height advantage and the green's local shelf as separate features. A ball just short of the upper shelf should be able to roll back to the lower body. There must be exactly one connected bunker, with its grass fingers retained, and no invented pond or stream.

### Locator and starting-parameter sheet

Image coordinates refer to the full original hole painting. They are approximate; the original dimensions are 3887 × 1823 px.

**Golf routing:** (0.154, 0.487) → (0.550, 0.520) → (0.817, 0.487).

**Owned bunker locators:** green_front_left (0.724, 0.419). The JSON contains each visible sand outline.

**Proposed green envelope:** 34 m across the final approach × 31 m along it; internal relief approximately 0.80–1.30 m. These are editable reconstruction dimensions, not measurements.

**Proposed longitudinal terrain/bed profile:** local tee = 0 m. Keep water surfaces separate from this ground profile.

| Fraction s | Height Y (m) |
|---:|---:|
| 0.00 | +0.0 |
| 0.12 | +0.0 |
| 0.35 | -7.0 |
| 0.65 | -13.0 |
| 0.85 | -14.0 |
| 1.00 | -12.0 |

**Named landforms to implement:** `h06_high_tee_bench`, `h06_broad_downhill_face`, `h06_green_platform`, `h06_green_back_right_shelf`.


---

## 07 — Pampas

**Par 4 · 450 yd · 411.5 m nominal routing length.**

**Identity:** a confined, nearly straight corridor ending at a small elevated green surrounded by five bunkers. Corroborated: the green sits on a hill. [Course description](https://www.golfmonthly.com/tour/us-masters/augusta-blog/augusta-national-hole-names-88155).

**Observed plan.** The left tee is enclosed by trees. A second pale tee pad lies farther into the corridor. Long woodland strips bound the playing line: the upper strip has a middle opening, while the lower boundary is more continuous and close. The fairway is not perfectly constant in width; it widens in the middle and tightens toward the target. No fairway bunkers interrupt it. Five separate sand bodies surround the green: three on the approach side and two beyond it. There is no water.

**Read the shading.** Broad vertical-looking light/dark bands across the illustration indicate gentle changes in the fairway's grade. The sharper shading around the five sand edges belongs to the elevated green complex and excavations. Preserve that distinction: moderate large-scale fairway relief, stronger local banks near the target.

**Proposed terrain.** Build a gently rising and subtly rolling corridor, then a more definite climb into the green over the final 35–60 m. The putting platform should be approximately 1.5–2.5 m above the nearby front recovery ground initially. Merge it into the surrounding hill, not an isolated pedestal. Let the front bunkers interrupt the bank at different heights and depths, with narrow grass separators.

**Green.** In the close-up the green is a compact, broad, somewhat rectangular/oval shape, wider across the approach than it is deep. Its left-front outline has a shallow indentation. Three large front sand bodies make the front boundary feel compressed, while the two rear bunkers leave only a limited back margin. Proposed sculpt: a modest back-to-front pitch with a slightly higher central/back shoulder and lower side pockets; about 0.35–0.70 m of internal relief. The green does not need No. 6's dramatic isolated shelf to be difficult.

**Bunker geometry.** The front-left bunker is the largest and lobed, the front-middle is rounded triangular, and the front-right has a strong inward notch. The rear pair are smaller and unequal. Keep all five independent. The full-hole picture shows three along screenshot-left of the green and two along screenshot-right because of its rotation.

**Acceptance checks.** The tee view should feel constricted by tree spacing and the corridor silhouette. The approach must climb onto the green complex. The plan and close-up must agree on five sand bodies, three front/two back. Do not hide the green's elevation solely in bunker lip geometry.

### Locator and starting-parameter sheet

Image coordinates refer to the full original hole painting. They are approximate; the original dimensions are 4705 × 1338 px.

**Golf routing:** (0.110, 0.478) → (0.350, 0.470) → (0.570, 0.500) → (0.750, 0.510) → (0.888, 0.530).

**Owned bunker locators:** green_front_left (0.870, 0.447); green_front_middle (0.864, 0.534); green_front_right (0.868, 0.629); green_back_left (0.910, 0.429); green_back_right (0.913, 0.575). The JSON contains each visible sand outline.

**Proposed green envelope:** 34 m across the final approach × 22 m along it; internal relief approximately 0.35–0.70 m. These are editable reconstruction dimensions, not measurements.

**Proposed longitudinal terrain/bed profile:** local tee = 0 m. Keep water surfaces separate from this ground profile.

| Fraction s | Height Y (m) |
|---:|---:|
| 0.00 | +0.0 |
| 0.25 | +1.0 |
| 0.50 | +2.0 |
| 0.75 | +3.0 |
| 0.90 | +5.0 |
| 1.00 | +8.0 |

**Named landforms to implement:** `h07_subtle_fairway_rolls`, `h07_final_climb`, `h07_five_bunker_platform`.


---

## 08 — Yellow Jasmine

**Par 5 · 570 yd · 521.2 m nominal routing length.**

**Identity:** an uphill par five whose green is protected by a chain of grassy mounds. Corroborated: uphill, with a punchbowl-style green setting. [Course description](https://www.golfmonthly.com/tour/us-masters/augusta-blog/augusta-national-hole-names-88155).

**Observed plan.** The back tee is low on the illustration's left, with a forward tee above and to its right. The route passes a single connected, deeply notched fairway bunker on the golfer's right, then works around the woodland bordering the inside/left approach. The green sits near the far-right end. Numerous small highlight/shadow pairs surround it and extend back down the approach. There are no greenside bunkers and no water. The lone fairway bunker is not a three-bunker cluster; its grass tongue creates its branching silhouette.

**Read the shading.** This is the clearest example of repeated convex lobes in the archive. The bright caps and dark flanks are unevenly spaced. They form a broken enclosure with low gaps, not a single continuous doughnut-shaped rim. Several are outside the putting surface and some sit along the approach. Do not imprint all of them as bumps inside the green.

**Proposed terrain.** Rise through the fairway, carry the climb through the second-shot area, and let the last approach thread between mounds. Build roughly 8–12 overlapping mound lobes in the final approach/green surroundings, guided by the actual tonal clusters rather than equal spacing. Start with 1–3 m of height above the adjoining apron, footprints roughly 8–20 m across, and unequal slopes. Keep low saddles and at least one open front entry. A group on the inside/left can partly obscure the putting surface from a distant approach.

**Green.** The close-up is long and narrow, with a slim forward extension, an inward waist on its left, and a broader rounded rear body. Preserve the bent, asymmetric outline. Set it lower than several surrounding mound crests, but do not make a deep bowl with every putt sucked into one center point. Use two gentle internal regions joined by a shallow saddle or shoulder; proposed internal relief is 0.40–0.80 m. The surrounding mound relief should dominate the silhouette.

**Acceptance checks.** In untextured side lighting, individual mound lobes and lower gaps must remain visible. A ball played into a grassy flank should be able to feed toward the apron/green on an inward-facing side or deflect away on an outward-facing side. Show the narrow forward green and broader rear body. Count one fairway bunker and zero greenside bunkers.

### Locator and starting-parameter sheet

Image coordinates refer to the full original hole painting. They are approximate; the original dimensions are 4662 × 1434 px.

**Golf routing:** (0.088, 0.616) → (0.330, 0.500) → (0.470, 0.455) → (0.680, 0.565) → (0.790, 0.620) → (0.879, 0.493).

**Owned bunker locators:** fairway_right (0.488, 0.571). The JSON contains each visible sand outline.

**Proposed green envelope:** 23 m across the final approach × 42 m along it; internal relief approximately 0.40–0.80 m. These are editable reconstruction dimensions, not measurements.

**Proposed longitudinal terrain/bed profile:** local tee = 0 m. Keep water surfaces separate from this ground profile.

| Fraction s | Height Y (m) |
|---:|---:|
| 0.00 | +0.0 |
| 0.20 | +3.0 |
| 0.40 | +8.0 |
| 0.62 | +13.0 |
| 0.82 | +19.0 |
| 1.00 | +22.0 |

**Named landforms to implement:** `h08_long_uphill_fairway`, `h08_right_fairway_bunker_bank`, `h08_approach_mound_chain`, `h08_green_mound_enclosure`.


---

## 09 — Carolina Cherry

**Par 4 · 460 yd · 420.6 m nominal routing length.**

**Identity:** a valley-shaped hole followed by an uphill approach to a green that rejects short shots. Corroborated: pronounced back-to-front green slope and a long front rollback. [Course description](https://www.golfmonthly.com/tour/us-masters/augusta-course-guide-27876).

**Observed plan.** The tees are in the upper-left. The golf route runs down and right around the long wooded strip, then turns left/up toward the far-right green. The early and middle playing space is below that strip, not through it. A separate woodland island forms part of the lower-middle boundary, and a lone tree sits nearer the open fairway. Two bunkers occupy the green's approach-left flank. There are no fairway bunkers and no water.

**Read the shading.** The large-scale tonal field must be read as a valley-to-hill transition, not just local bumps. At the green, repeated diagonal tonal changes suggest multiple surface regions. The narrow dark front edge alone does not explain the rollback: the apron below it must carry the slope continuously.

**Proposed terrain.** Descend away from the tee to a broad low section around the middle/late fairway, then climb strongly toward the target. Make the last 35–50 m of the front approach a continuous sloping bank. Let it begin around 8–14% grade in the steepest exterior section, easing into the putting surface; adjust after rolling tests. Avoid a flat shelf immediately outside the front collar, which would catch every rejected ball.

**Green.** Register the two unequal bunkers on the golfer's left. The close-up shows a diagonally elongated rounded shape, narrower in the far-left/rear end and broader toward the near-right portion. Build three connected height regions—front, middle, and rear—with curved rather than perfectly straight transition bands. Proposed total internal rise from front to rear: 1.2–2.0 m. Keep pin-sized gentle zones within those regions. These exact tiers and their heights are a reconstruction proposal; the corroborated requirement is the strong overall fall toward the front.

**Bunkers and surrounds.** The front-left body is broad/triangular and the farther-left body is longer and curved. Excavate both into the green's sidehill, separated by a narrow grass finger. The high green should remain part of the broader rising ground, rather than be enclosed in a uniform ring of mounds.

**Acceptance checks.** Show a tee-to-green side profile with the valley and final climb. A ball released on the steep front apron must continue down the approach; do not require it to travel an exact distance before physics is calibrated. Demonstrate different uphill putts across the three proposed regions. Preserve exactly two left-side greenside bunkers.

### Locator and starting-parameter sheet

Image coordinates refer to the full original hole painting. They are approximate; the original dimensions are 4374 × 1666 px.

**Golf routing:** (0.091, 0.285) → (0.320, 0.495) → (0.600, 0.680) → (0.750, 0.600) → (0.900, 0.360).

**Owned bunker locators:** green_left_rear (0.882, 0.297); green_left_front (0.868, 0.363). The JSON contains each visible sand outline.

**Proposed green envelope:** 30 m across the final approach × 34 m along it; internal relief approximately 1.20–2.00 m. These are editable reconstruction dimensions, not measurements.

**Proposed longitudinal terrain/bed profile:** local tee = 0 m. Keep water surfaces separate from this ground profile.

| Fraction s | Height Y (m) |
|---:|---:|
| 0.00 | +0.0 |
| 0.20 | -5.0 |
| 0.50 | -13.0 |
| 0.70 | -10.0 |
| 0.87 | -2.0 |
| 1.00 | +6.0 |

**Named landforms to implement:** `h09_fairway_valley`, `h09_uphill_approach`, `h09_front_runoff`, `h09_green_height_regions`.


---

## 10 — Camellia

**Par 4 · 495 yd · 452.6 m nominal routing length.**

**Identity:** a sweeping downhill left-turning hole with a conspicuous decorative-looking fairway bunker short of the green. Corroborated: descending fairway; green falls generally right to left. [Course description](https://www.golfmonthly.com/tour/us-masters/augusta-course-guide-27876).

**Observed plan.** The tee starts high on the illustration's left; the wide corridor bends downward through the middle and then back upward to the far-right target. Long woodland boundaries closely frame both sides. An isolated broad tree intrudes from the lower/outer side around the early-middle fairway. The large late fairway bunker has an unmistakable branching outline: an elongated lower-left arm, several rounded outward lobes, and deep grass fingers. A separate, smaller bunker lies at the green's right/front-right flank. No water is shown.

**Read the shading.** The broad smooth dark-to-light transitions belong to a large continuous descent, not a line of disconnected hillocks. Near the decorative bunker, a change in grade precedes the final green platform. Do not read the sunlit back of the green as evidence that the entire hole is uphill.

**Proposed terrain.** Make a substantial descent from tee to the late fairway, using roughly 25–35 m total fall as an initial reconstruction range. Keep the steepest broad section around the first two-thirds, then reach a lower area and rise gently again into the green. This local finishing rise can coexist with a much lower green than tee. Corroborated: the present green occupies higher ground than the old low green site. [Green setting](https://www.golfmonthly.com/tour/us-masters/augusta-blog/augusta-national-hole-names-88155).

**Green.** The close-up shows a long rounded rectangle with a broad front, a narrowing rounded back, and the right side pressed against a curved bunker. Retain a clear higher right half and lower left half, connected by a broad diagonal slope. Proposed cross-green relief: 0.6–1.1 m. Add a smaller longitudinal roll so its front and back are not identical copies of the same cross section. Let the left exterior continue down away from the surface.

**Bunker geometry.** Trace the large branching bunker with enough vertices to keep every major grass finger; it is one connected sand body, not several circles. Place it clearly short of the green, with ground between the two complexes. The second bunker belongs directly to the green.

**Acceptance checks.** The tee view and low side view must reveal a continuous hillside descent. A ball landing on the downslope should gain forward rollout. The end should have a local uphill finish from the low fairway. Show the branching bunker silhouette and a putting break from higher right toward lower left.

### Locator and starting-parameter sheet

Image coordinates refer to the full original hole painting. They are approximate; the original dimensions are 4507 × 1678 px.

**Golf routing:** (0.092, 0.286) → (0.300, 0.510) → (0.500, 0.590) → (0.680, 0.520) → (0.810, 0.390) → (0.891, 0.332).

**Owned bunker locators:** fairway_branching (0.751, 0.428); green_right (0.869, 0.408). The JSON contains each visible sand outline.

**Proposed green envelope:** 26 m across the final approach × 36 m along it; internal relief approximately 0.60–1.10 m. These are editable reconstruction dimensions, not measurements.

**Proposed longitudinal terrain/bed profile:** local tee = 0 m. Keep water surfaces separate from this ground profile.

| Fraction s | Height Y (m) |
|---:|---:|
| 0.00 | +0.0 |
| 0.20 | -9.0 |
| 0.45 | -23.0 |
| 0.70 | -30.0 |
| 0.85 | -31.0 |
| 1.00 | -28.0 |

**Named landforms to implement:** `h10_major_downhill_fairway`, `h10_low_fairway`, `h10_finishing_rise`, `h10_green_cross_slope`.


---

## 11 — White Dogwood

**Par 4 · 520 yd · 475.5 m nominal routing length.**

**Identity:** a long corridor opening into a spacious approach beside a pond, with the green perched on its bank.

**Observed plan.** The tee is at the far left, with a forward pad farther right. The explicitly mown fairway begins well beyond the tee corridor and opens considerably in the second half. Woodland remains tight on the upper/left side and becomes more broken on the lower/right. Three isolated trees punctuate the lower/right portion of the mid-to-late playing area; keep them as deliberate landmarks. A small pond presses against the green's left side. A wider channel passes beyond the green region, with a narrow bridge visible near the far-right edge. One small bunker lies behind/right of the green. Corroborated: pond on the green's left. [Course description](https://www.golfmonthly.com/tour/us-masters/augusta-blog/augusta-national-hole-names-88155).

**Read the shading.** The broad central fairway tones suggest gentle shoulders over a much larger grade change. The pond edge is a distinct bank, not a dark shadow around the green. In the close-up, the water wraps the screenshot-left side and the bunker is above/right; use these to register the green. Do not merge the nearby channel and pond into an enormous circular lake because both are blue.

**Proposed terrain.** Establish an upper tee corridor with a rounded crest, then descend gradually into the more open late fairway. Ease the descent approaching the waterside complex. Keep the right approach as playable undulating recovery ground. Raise the green roughly 1–2 m above its adjacent water level initially, with a narrow, relatively steep left bank and a broader transition to the right. Choose the pond level together with the ground, so it does not accidentally flood the green.

**Green.** The close-up is an elongated kidney/pear-like outline, with a narrow rear-left portion toward the water and a wider front/right body. Proposed sculpt: a modest central/high-right shoulder feeding some putts toward the lower waterside half, plus a subtle division between the narrow back and broad front regions. Use approximately 0.4–0.8 m internal relief. Do not slope the entire right recovery area directly into the pond; preserve a playable bailout region.

**Acceptance checks.** The pond must touch the correct left flank after rotating the hole into course space. Show the raised bank in side view and a ball rolling off its water-facing edge. Keep one greenside bunker, three distinct approach-area tree landmarks, and no invented fairway sand. The channel and bridge must align with the shared Amen Corner surroundings when neighboring holes are assembled.

### Locator and starting-parameter sheet

Image coordinates refer to the full original hole painting. They are approximate; the original dimensions are 4353 × 1302 px.

**Golf routing:** (0.080, 0.562) → (0.360, 0.430) → (0.580, 0.390) → (0.710, 0.420) → (0.852, 0.527).

**Owned bunker locators:** green_back_right (0.879, 0.583). The JSON contains each visible sand outline.

**Water locators:** pond_left_of_green (0.827, 0.418); channel_beyond_green (0.917, 0.361). These points are not water boundaries or surface levels.

**Proposed green envelope:** 28 m across the final approach × 33 m along it; internal relief approximately 0.40–0.80 m. These are editable reconstruction dimensions, not measurements.

**Proposed longitudinal terrain/bed profile:** local tee = 0 m. Keep water surfaces separate from this ground profile.

| Fraction s | Height Y (m) |
|---:|---:|
| 0.00 | +0.0 |
| 0.18 | +2.0 |
| 0.40 | -4.0 |
| 0.65 | -14.0 |
| 0.87 | -23.0 |
| 1.00 | -22.0 |

**Named landforms to implement:** `h11_upper_crest`, `h11_descending_open_fairway`, `h11_waterside_green_bank`.


---

## 12 — Golden Bell

**Par 3 · 155 yd · 141.7 m nominal routing length.**

**Identity:** a short shot across a creek to a narrow, diagonally oriented green backed by a wooded flowering bank.

**Observed plan.** The two large tee rectangles are on the left side of the creek. The water crosses diagonally from upper-middle to lower-right and separates tee-side ground from the green shelf. The green lies lengthwise along the far bank: it is much wider across the golfer's view than it is deep along the shot. One irregular bunker lies between the creek and green; two separate bunkers sit behind it beneath the vegetation. Corroborated: front creek, one front bunker, two rear bunkers. [Course description](https://www.golfmonthly.com/tour/us-masters/augusta-course-guide-27876). A bridge crosses away from the main target line. The pale rectangle beyond/right of the green is adjacent-hole tee context, not the No. 12 starting tee.

**Read the shading.** The far side is a narrow raised strip between water and woodland. The darker front bank represents a real change in slope where its form is continuous with the creek edge. Sharp canopy shadows over the two rear bunkers are lighting. The green's smooth pale color does not mean its surface is level, but the image does not define a detailed putting-break map.

The larger rear bunker is partly hidden by trees. Its supplied footprint therefore follows the visible main sand body with an estimated smooth canopy-side edge. Do not mistake tiny gray/white gaps through leaves for additional sand lobes; the full hidden boundary is unresolved.

**Proposed terrain.** Use broadly comparable tee and green elevations, with the creek surface roughly 1.5–2.5 m below the neighboring green/apron as a starting point. Cut a real channel and slope the turf down into it. Raise the wooded rear ground so it reads as a backdrop above the putting shelf. Keep front collar-to-bank continuity, especially in places not intercepted by the front bunker.

**Green.** The outline is a long curved bean/banana with a pinched middle and unequal rounded ends. In the close-up its long axis runs upper-left to lower-right. Keep it skewed relative to the incoming shot, rather than rotating it perpendicular and making every carry identical. Proposed surface: two broad gentle lobes connected by a shallow saddle, with about 0.3–0.6 m internal relief. Avoid adding huge tiers that overwhelm this small target. Exterior bank slopes can be much steeper than the putting surface.

**Acceptance checks.** From the tee, show the narrow depth of the green, the intervening creek, and the rising foliage behind. Misses short of unprotected front edges must roll toward water. Preserve all three separate bunkers. The bridge must clear the channel and be walkable; it must not sit in the center of the intended shot line. Do not accidentally start the hole from the neighboring tee beyond the green.

### Locator and starting-parameter sheet

Image coordinates refer to the full original hole painting. They are approximate; the original dimensions are 4149 × 1884 px.

**Golf routing:** (0.159, 0.517) → (0.736, 0.513).

**Owned bunker locators:** green_front (0.707, 0.524); green_back_left (0.793, 0.474); green_back_right (0.811, 0.532). The JSON contains each visible sand outline.

**Water locators:** diagonal_creek_crossing (0.599, 0.534). These points are not water boundaries or surface levels.

**Proposed green envelope:** 38 m across the final approach × 18 m along it; internal relief approximately 0.30–0.60 m. These are editable reconstruction dimensions, not measurements.

**Proposed longitudinal terrain/bed profile:** local tee = 0 m. Keep water surfaces separate from this ground profile.

| Fraction s | Height Y (m) |
|---:|---:|
| 0.00 | +0.0 |
| 0.62 | -0.5 |
| 0.78 | -3.0 |
| 0.86 | -2.5 |
| 0.94 | -1.0 |
| 1.00 | -1.0 |

**Named landforms to implement:** `h12_creek_channel`, `h12_narrow_green_bank`, `h12_rear_wooded_bank`.


---

## 13 — Azalea

**Par 5 · 545 yd · 498.3 m nominal routing length.**

**Identity:** a strong dogleg left around trees and a creek, followed by a sidehill approach across a narrow tributary to a raised green.

**Observed plan.** The championship tee is the far upper-left rectangle in the extended wooded chute. The route crosses the broad channel, opens into the large lower fairway, turns around the wooded inside corner, and finishes at the upper-right green. A narrow stream follows the inside edge of the fairway and then bends across the front of the No. 13 green. Four separate bunkers form an uneven arc behind/left/back-right of that green. Flowering shrubs are especially dense around the inside woods and the green backdrop.

**Critical ownership check.** The smaller green beside the broad channel at the left of this image is **No. 12**, including its three bunkers. It is neighboring scenery, not a second No. 13 green. No. 13 owns the far-right green and its four bunkers. In a full course, reuse the No. 12 geometry in that shared region instead of building it twice.

**Read the shading.** The large fairway's gentle tonal transition should become a coherent sidehill, not a level floor. The bright narrow strip alongside the tributary is a bank/rim; the dark channel lies below it. Around the target, separate bright/dark turf shoulders support a raised green setting. Do not raise the blue channel or turn every flowering shrub patch into a hill.

**Proposed terrain.** Let the tee corridor descend into the lower dogleg. Tilt the principal second-shot landing area down toward the inside/left creek bank: start around 3–5% across a 25–35 m span. Keep a higher outer/right shoulder and a lower inner side, then raise the green complex beyond the tributary. The final crossing is a local valley between fairway and green, not a huge canyon. Start with green-front turf around 1.5–2.5 m above the stream surface, then tune the bank slopes and carry.

**Green.** The close-up's creek runs along screenshot-right and its sand bodies occupy screenshot-left/top, indicating a rotated oblique view. Register it with the four bunkers and creek, not an assumed screen-up approach direction. The surface is an elongated rounded rectangle with unequal lobes and a narrowing end. Proposed sculpt: a higher rear/inside region, a broader lower approach-side shelf, and a diagonal connecting roll, with approximately 0.6–1.0 m internal relief. Leave believable flatter zones; do not make the whole surface a single plane aimed at the water. Preserve the small culvert/bridge detail visible at the end of the close-up channel if reproducing that local view.

**Acceptance checks.** Demonstrate a sidehill lie in the second-shot area and a distinct creek crossing before the green. The tributary must remain narrow and follow the curved bank. Count four owned bunkers, not seven. Show both green and creek from a low approach view. The completed shared map must contain one No. 12 green and one No. 13 green.

### Locator and starting-parameter sheet

Image coordinates refer to the full original hole painting. They are approximate; the original dimensions are 4333 × 2071 px.

**Golf routing:** (0.078, 0.172) → (0.290, 0.580) → (0.490, 0.750) → (0.700, 0.670) → (0.805, 0.510) → (0.864, 0.348).

**Owned bunker locators:** green_arc_image_west (0.805, 0.333); green_arc_upper_left (0.853, 0.278); green_arc_upper_right (0.897, 0.273); green_arc_image_east (0.913, 0.312). The JSON contains each visible sand outline.

**Water locators:** broad_channel_near_tee (0.221, 0.447); inside_tributary (0.523, 0.640); tributary_front_of_green (0.863, 0.421). These points are not water boundaries or surface levels.

**Proposed green envelope:** 35 m across the final approach × 29 m along it; internal relief approximately 0.60–1.00 m. These are editable reconstruction dimensions, not measurements.

**Proposed longitudinal terrain/bed profile:** local tee = 0 m. Keep water surfaces separate from this ground profile.

| Fraction s | Height Y (m) |
|---:|---:|
| 0.00 | +0.0 |
| 0.18 | -2.0 |
| 0.40 | -5.0 |
| 0.64 | -4.0 |
| 0.82 | -3.0 |
| 0.93 | -4.0 |
| 1.00 | -1.0 |

**Named landforms to implement:** `h13_lower_dogleg`, `h13_sidehill_landing`, `h13_tributary_crossing`, `h13_raised_green_bank`.


---

## 14 — Chinese Fir

**Par 4 · 440 yd · 402.3 m nominal routing length.**

**Identity:** a bunkerless hole where a strongly contoured green does the defensive work. Corroborated: the green's contours tend to feed the ball right. [Green description](https://www.nbcsports.com/golf/news/article-doug-ferguson-hole-hole-look-augusta-national-golf-club).

**Observed plan.** The tee starts upper-left, with a forward rectangle farther right. The fairway is broad through the middle, gently bows down in the painting, then returns up toward the right-hand green. A long tree strip occupies the upper/inside boundary; the lower tree mass begins later. One conspicuous isolated tree stands in the lower-middle open surroundings. There are **zero bunkers and zero water hazards** in this image. The putting surface contains several pronounced pale/dark lobes.

**Read the shading.** The green's internal tonal variations are the essential cue. They are not grass patches to reproduce as color. Read them as a connected combination of convex shoulders, a trough/saddle, and lower receiving areas. The close-up includes large branching tree shadows; do not cut those shapes into the surface. This is a case where the full-hole painting contributes more usable form information than the darker close-up.

**Proposed terrain.** Build a gentle overall climb with broad fairway rolls. Add a mild cross-slope around the landing zone, rather than flat ground between trees. Increase relief in the green complex without surrounding it with sand. The front apron should rise into a prominent shoulder and fall back toward the approach if a ball fails to climb it.

**Green.** Preserve the broad irregular kidney shape with a narrower rear extension. Build a lower front entry; a pronounced curved ridge across roughly the front third; a higher left/back shoulder continuing behind that ridge; and a lower right receiving region. Use a shallow connecting saddle so a putt can change direction rather than merely speed. Proposed total internal relief: 1.0–1.8 m, with the main ridge transition spread over about 5–9 m. Leave usable, gentler areas around the contour structure. Those exact ridge placements are an interpretation of the artwork, not surveyed coordinates.

The left-high/right-low relationship should remain readable even if the proposed ridge location changes during refinement. Avoid a symmetrical central volcano, a simple bowl, or a perfectly flat green with a bumpy normal map. The hard part is the sequence of slopes.

**Acceptance checks.** Show actual mesh-generated contours and a cross section through the front ridge. A ball that does not crest the front shoulder should be able to return toward the approach; a ball on the higher left region should encounter a route toward the right receiving area. Confirm no sand or water has been added to compensate for unfinished terrain.

### Locator and starting-parameter sheet

Image coordinates refer to the full original hole painting. They are approximate; the original dimensions are 4397 × 1552 px.

**Golf routing:** (0.085, 0.300) → (0.310, 0.450) → (0.540, 0.550) → (0.700, 0.515) → (0.872, 0.404).

**Owned bunker locators:** none. The JSON contains each visible sand outline.

**Proposed green envelope:** 32 m across the final approach × 36 m along it; internal relief approximately 1.00–1.80 m. These are editable reconstruction dimensions, not measurements.

**Proposed longitudinal terrain/bed profile:** local tee = 0 m. Keep water surfaces separate from this ground profile.

| Fraction s | Height Y (m) |
|---:|---:|
| 0.00 | +0.0 |
| 0.25 | +1.0 |
| 0.50 | +3.0 |
| 0.75 | +5.0 |
| 0.90 | +8.0 |
| 1.00 | +10.0 |

**Named landforms to implement:** `h14_rolling_rising_fairway`, `h14_front_green_ridge`, `h14_high_left_back_shoulder`, `h14_lower_right_receiver`.


---

## 15 — Firethorn

**Par 5 · 550 yd · 502.9 m nominal routing length.**

**Identity:** a long hole ending with a downhill approach over a pond to a shallow green, with more water beyond.

**Observed plan.** Two tee areas begin at the left. The fairway runs broadly left to right, with a dense upper tree boundary, several lower woodland islands, and an isolated lower-middle tree. A wooded bulge intrudes from the upper side before the final approach. The front pond lies across the incoming line immediately short of the green; its long axis is transverse to the shot. The green occupies a narrow land strip, with a second water body beyond/right in the illustration. One elongated bunker guards the golfer's right side. A small bridge crosses near the upper end of the front pond. Do not turn this into an island green surrounded by one continuous circular moat.

**Read the shading.** The alternating broad bands in the central fairway suggest rolling terrain followed by a grade change into the approach. The bright thin strip on the far side of the front pond is part of a raised, closely mown bank. The green outline looks long vertically in the full painting because it lies across the shot; that is its width, not its approach depth.

**Proposed terrain.** Rise gently to a broad fairway crest around `s=0.40–0.55`, then descend toward the lay-up zone and front pond. Give players different lies along that descending section. Raise the green above the pond by roughly 1.5–2.5 m initially, with a short, relatively steep front apron that slopes back into the water. Maintain a narrow land strip beyond the green before the farther water where shown. The front bank is a key gameplay feature; its continuity matters more than its painted highlight. Corroborated: the far bank of the front pond is steep. [Bank description](https://www.golfmonthly.com/tour/us-masters/augusta-blog/augusta-national-hole-names-88155).

**Green.** The close-up shows a wide, shallow surface with an uneven rear line, a comparatively straight/softly curved front, and a fuller right end beside the bunker. Proposed sculpt: a gentle front-to-back crown/shoulder with distinct left and right receiving areas, about 0.35–0.70 m internal relief. Keep the strong water-directed slope mainly in the front runoff; do not uniformly tilt every pin shelf steeply into the pond.

**Acceptance checks.** From the late fairway, the approach should visibly descend toward water and then climb a short far bank onto a shallow target. Demonstrate a ball slipping from the front edge into the pond. Show that an overlong shot can pass beyond the green toward the farther hazard. Keep one right-side bunker and the two water footprints distinct.

### Locator and starting-parameter sheet

Image coordinates refer to the full original hole painting. They are approximate; the original dimensions are 4497 × 1337 px.

**Golf routing:** (0.080, 0.533) → (0.350, 0.490) → (0.550, 0.500) → (0.750, 0.430) → (0.885, 0.493).

**Owned bunker locators:** green_right (0.871, 0.610). The JSON contains each visible sand outline.

**Water locators:** front_pond (0.842, 0.480); farther_water (0.955, 0.407). These points are not water boundaries or surface levels.

**Proposed green envelope:** 36 m across the final approach × 20 m along it; internal relief approximately 0.35–0.70 m. These are editable reconstruction dimensions, not measurements.

**Proposed longitudinal terrain/bed profile:** local tee = 0 m. Keep water surfaces separate from this ground profile.

| Fraction s | Height Y (m) |
|---:|---:|
| 0.00 | +0.0 |
| 0.25 | +3.0 |
| 0.48 | +6.0 |
| 0.65 | +1.0 |
| 0.82 | -7.0 |
| 0.93 | -13.0 |
| 1.00 | -10.0 |

**Named landforms to implement:** `h15_broad_fairway_crest`, `h15_descending_layup`, `h15_front_pond_basin`, `h15_far_bank_runoff`.


---

## 16 — Redbud

**Par 3 · 170 yd · 155.4 m nominal routing length.**

**Identity:** a water-carry par three with a green set into a hillside and a strong right-to-left slope. Corroborated: right-to-left green slope. [Course description](https://www.golfmonthly.com/tour/us-masters/augusta-course-guide-27876).

**Observed plan.** A long tee rectangle lies at the left. The elongated pond fills most of the space between tee and green and continues along the green's left. A mown strip runs around the pond on the golfer's right, which appears along the bottom of the full-hole painting. The green is at the far-right end and has a broad rear body and narrower forward portion. Three bunkers surround it: a narrow one on the pond-side/back-left edge, a smaller front-right bunker, and a larger rear-right bunker. Tree groups cover the far bank and the ground beyond/right of the green.

**Read the shading.** The bright outer/right shoulder and the broad darker internal band imply an important transverse change of slope. This is a hillside green, not a bowl centered in the pond. Register the close-up with water on screenshot-left and the two bunkers on screenshot-right. The branching shadows over the upper putting surface must remain lighting, while the broad shelf division becomes geometry.

**Proposed terrain.** Place the pond below the adjoining grass and build a continuous higher bank along the green's right side. Let that higher land blend into the tree-covered ground beyond. The pond-side edge is lower, with a narrow collar/runoff bank. Start with the lower green region 1–2 m above the water surface, then reconcile the entire green complex with the pond's level.

**Green.** Build an upper-right shelf, a broad lower-left putting region, and a curved diagonal transition between them. Proposed internal height difference: 0.9–1.5 m, concentrated through a smooth 6–12 m transition. The higher side should have a usable shelf, not just an exposed steep slope. Add a subtle lower-back-left receiving pocket while keeping a connected lower-left corridor. Any characteristic feeding putt must result from the mesh and ball physics, never from a scripted attraction to the cup.

**Bunkers.** The pond-side bunker is long and narrow; the front-right is smaller and bean-like; the rear-right is broad and elongated. The water and bunker arrangement must stay asymmetric. Preserve separate grass strips between the three hazards and the putting surface.

**Acceptance checks.** With neutral lighting, show the upper-right shelf and lower-left region in cross section. A ball crossing the main transition from the right must feed left. Move the cup and verify the rollout does not magically track its new position. Count three bunkers and preserve the dry walking/mown strip around the pond's right side.

### Locator and starting-parameter sheet

Image coordinates refer to the full original hole painting. They are approximate; the original dimensions are 4346 × 2049 px.

**Golf routing:** (0.219, 0.417) → (0.816, 0.484).

**Owned bunker locators:** green_pond_side (0.833, 0.361); green_front_right (0.749, 0.607); green_back_right (0.874, 0.607). The JSON contains each visible sand outline.

**Water locators:** long_pond (0.555, 0.429). These points are not water boundaries or surface levels.

**Proposed green envelope:** 31 m across the final approach × 37 m along it; internal relief approximately 0.90–1.50 m. These are editable reconstruction dimensions, not measurements.

**Proposed longitudinal terrain/bed profile:** local tee = 0 m. Keep water surfaces separate from this ground profile.

| Fraction s | Height Y (m) |
|---:|---:|
| 0.00 | +0.0 |
| 0.16 | -1.0 |
| 0.30 | -4.0 |
| 0.76 | -4.0 |
| 0.89 | -3.0 |
| 1.00 | -2.0 |

**Named landforms to implement:** `h16_pond_basin`, `h16_high_right_green_bank`, `h16_upper_right_green_shelf`, `h16_lower_left_green_corridor`.


---

## 17 — Nandina

**Par 4 · 450 yd · 411.5 m nominal routing length.**

**Identity:** a mostly straight corridor with subtle fairway rolls and a small asymmetric green guarded by two front bunkers.

**Observed plan.** The back tee is at the left; the forward pad is farther right. A long woodland strip forms the upper boundary. The lower boundary is broken into several islands with gaps, rather than one continuous wall. The fairway widens near its beginning, tightens gently through the middle, and opens around the green. Two unequal bunkers sit on the green's approach side, one left and one right. No fairway bunker or water is visible. Do not invent a central fairway tree from a historic course description when it is not in this supplied plan.

**Data discrepancy.** Use **450 yards**, as specified in `hole info.txt`. The supplied overview/check sheet prints 440 yards for this hole; its label and scale should not silently override the explicit data file.

**Read the shading.** The fairway has mild broad rolls. The green contains smaller, brighter lobes and darker flanks, especially toward one side, supporting a more uneven surface than its overall compact shape suggests. The close-up has a yellow marker in the lower-right bunker. That marker is neither proof of a valid cup nor a slope measurement.

**Proposed terrain.** Make a gentle overall rise from tee to green with two shallow fairway shoulders, rather than a monotonous ramp. Increase the grade over the final approach and raise the green complex locally. Allow rough to continue between the lower tree islands; those openings contribute to the appearance of the hole.

**Green.** The close-up shows a broad near-left/front body, a rear extension shifted to the right, and a curved indented entrance between the front bunkers. Retain that offset footprint. Proposed sculpt: a low central crown with a slightly stronger rear/right shoulder and two quieter front/side areas. Start with approximately 0.45–0.85 m of internal relief. Let selected side/back edges shed balls into the surrounds, while keeping some gentle pin zones. Do not clone No. 18's two-tier arrangement or No. 16's large transverse shelf.

**Bunkers.** Both guard the entrance, but the left is taller/longer in the close-up and the right is broader and rounded. Keep the narrow grass entrance between them and the separate turf border around the green. Do not convert the erroneous sand-overlaid marker into a hole in the bunker.

**Acceptance checks.** Verify the 450-yard length convention after scaling. Show the staggered woodland islands and the green's offset rear lobe. Demonstrate subtle changes in lie over the fairway shoulders. Count two front bunkers and validate every cup candidate against the actual putting-surface polygon.

### Locator and starting-parameter sheet

Image coordinates refer to the full original hole painting. They are approximate; the original dimensions are 4218 × 1250 px.

**Golf routing:** (0.095, 0.383) → (0.360, 0.460) → (0.610, 0.540) → (0.800, 0.450) → (0.904, 0.438).

**Owned bunker locators:** green_front_left (0.880, 0.338); green_front_right (0.877, 0.478). The JSON contains each visible sand outline.

**Proposed green envelope:** 32 m across the final approach × 28 m along it; internal relief approximately 0.45–0.85 m. These are editable reconstruction dimensions, not measurements.

**Proposed longitudinal terrain/bed profile:** local tee = 0 m. Keep water surfaces separate from this ground profile.

| Fraction s | Height Y (m) |
|---:|---:|
| 0.00 | +0.0 |
| 0.25 | +1.0 |
| 0.50 | +4.0 |
| 0.70 | +5.0 |
| 0.90 | +7.0 |
| 1.00 | +10.0 |

**Named landforms to implement:** `h17_two_fairway_shoulders`, `h17_final_green_climb`, `h17_offset_green_crown`.


---

## 18 — Holly

**Par 4 · 465 yd · 425.2 m nominal routing length.**

**Identity:** a climbing finish through a tight opening corridor, turning right past two fairway bunkers toward a raised green. Corroborated: substantial tee-to-green ascent. [Course description](https://www.golfmonthly.com/tour/us-masters/augusta-blog/augusta-national-hole-names-88155).

**Observed plan.** The back tee begins at the lower-left. The narrow opening runs diagonally up and right between tree lines before the defined fairway opens in the upper-middle part of the painting. The route turns right toward the lower-right green. Two separate fairway bunkers sit at the outer/left side of that turning area. Two more bunkers guard the green: one front-left and one on the right flank. An isolated broad tree stands short/left of the green region; keep it away from the center of the putting approach. No water is shown.

**Read the shading.** The longitudinal tonal changes are important: the ascent must pass through the dogleg and continue toward the target, not stop at the fairway bunkers. The green's diagonal light/dark division supports at least two surface regions. The larger-scale hill and the green's internal rise must remain separate editable features.

**Proposed terrain.** Begin on a lower tee bench and climb gradually through the narrow corridor. Increase the climb into the bend, then keep rising through the approach. Start with a tee-to-green gain around 18–24 m, tuning it to the supplied plan and eventual shared-course terrain. Shape the fairway bunker bank into the side of the hill. Preserve a continuous playable ascent around it rather than two disconnected platforms.

**Green.** Register the close-up using the large right-side bunker and the partially cropped front-left bunker. The putting surface has a broad front, a slightly narrowed/rounded rear, and an indentation along the right side where sand presses inward. Proposed sculpt: a lower front shelf and a higher back shelf, connected by a broad curved transition across the central region. Start with 0.7–1.2 m between the shelves, spread over 5–9 m, plus a small cross-slope difference so the two halves are not perfectly rectangular ramps. Keep the front apron descending into the larger uphill approach.

**Bunkers and trees.** The fairway pair have unequal, roughly rounded-rectangular footprints; both are visible on the golfer's left near the dogleg. The greenside pair are curvier and occupy a different scale. Keep the tee corridor narrow in its actual geometry and tree positions, rather than faking a tunnel with camera zoom or fog.

**Acceptance checks.** From the tee, show the narrow rising opening and restricted view toward the dogleg. From the approach, show a continued climb to the target and the green's own second level. Count two fairway plus two greenside bunkers. A putt across the middle transition must change speed/grade while remaining on smooth, continuous collision geometry.

### Locator and starting-parameter sheet

Image coordinates refer to the full original hole painting. They are approximate; the original dimensions are 4106 × 1510 px.

**Golf routing:** (0.098, 0.697) → (0.330, 0.535) → (0.480, 0.428) → (0.650, 0.398) → (0.780, 0.520) → (0.897, 0.630).

**Owned bunker locators:** fairway_left_a (0.625, 0.300); fairway_left_b (0.664, 0.324); green_front_left (0.856, 0.544); green_right (0.883, 0.690). The JSON contains each visible sand outline.

**Proposed green envelope:** 30 m across the final approach × 32 m along it; internal relief approximately 0.70–1.20 m. These are editable reconstruction dimensions, not measurements.

**Proposed longitudinal terrain/bed profile:** local tee = 0 m. Keep water surfaces separate from this ground profile.

| Fraction s | Height Y (m) |
|---:|---:|
| 0.00 | +0.0 |
| 0.20 | +2.0 |
| 0.42 | +7.0 |
| 0.62 | +12.0 |
| 0.82 | +17.0 |
| 1.00 | +21.0 |

**Named landforms to implement:** `h18_rising_tee_corridor`, `h18_dogleg_bunker_bank`, `h18_uphill_approach`, `h18_two_green_shelves`.
