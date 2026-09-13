# Course flyover visual reference

Reference: the user's local 575.6-second, 1280 x 720 course flyover MP4. Sampled frames are in the ignored `build/reference` folder. The video itself is not bundled with the game.

Current visual changes:

- Olive fairways with subtle mowing variation instead of strong alternating lime stripes.
- Slightly lighter putting surfaces, near-white bunker sand, and tighter material boundaries.
- Distance-faded turf grain and normal mapping so broad slopes read cleanly from the tee.
- Calmer dark water with subdued ripples; neutral sand grain without the old yellow texture cast.
- Darker foliage and pine straw, more pine-dominant woodland, and less continuous flowering understory. The separate plain green bush assets are excluded from gameplay and Windows exports.
- Lower sun angle for more legible terrain/woodland shadows; reduced cloud opacity. Static sky lighting uses quality mode instead of repeated realtime cubemap updates.
- Authored hole elevation profiles with the later tee, hill, green, rough-island, bunker and creek adjustments. Green grade and relief caps are retained.
- Dense tree geometry nearby, reduced branch-and-leaf geometry from 90 to 450 metres, and baked cross cards beyond that. Streamed grass cards retain nearby ground detail.
- A coarse surrounding course and distant woodland continue the view beyond the active hole.
- An upright flag waypoint tracks the pin across the top of the screen; the minimap mirrors the main-view shot path and short white ball tail.

Scope and accuracy: the traced outlines form the base, with the subsequent per-hole edits applied. The layout still arranges holes in artificial corridors, not the real site's routing. Existing elevation data is a reconstruction proposal, not surveyed terrain. The reconstruction does not claim exact topography, exact tree placement, or tournament buildings/crowds from the video.

Validation includes graphical checks of the tee, distant course, minimap tracer and flag waypoint; ground-contact, foliage, friction, green-speed and cup-capture checks; and Windows export/startup checks. Performance varies by view and hardware.
