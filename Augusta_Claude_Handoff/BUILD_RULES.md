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
