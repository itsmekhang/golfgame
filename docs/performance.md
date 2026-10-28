# Performance checks

Run these with the Godot 4.7 executable from the project directory:

```powershell
godot --headless --path . --script tests/excavation_distance_test.gd
godot --headless --path . --script tests/turf_shell_culling_test.gd
godot --headless --path . --script tests/bunker_lie_test.gd
$env:PERF_QUICK = '1'
$env:PERF_SHELLS = '1'
godot --path . --resolution 1280x720 --script tests/perf_probe.gd -- 15:tee
```

Use the same resolution and hole for before/after comparisons. Run rendering
measurements alone, after asset imports finish. The probe disables VSync and
uses a throwaway save. `PERF_CAPTURE_DIR` optionally saves each measured view.

## October 2026 cleanup

- Hazard distance queries reject groups of outline segments using bounds and
  compare squared distances. The original vertices and inside/outside test stay
  intact. The regression checks every authored hazard against an exhaustive scan,
  including edges, vertices, replacement outlines and degenerate segments.
- Feature-mask clearing uses a native image rectangle fill. Bunker additions and
  removals still repaint the same inclusive pixel range.
- Turf shells share each terrain tile's mesh in a separate distance-culled overlay.
  All twelve nearby slices remain; distant tiles submit only their base terrain.
  The culling radius includes the tile diagonal and shader displacement, and the
  overlay stays out of the minimap and shadow passes.
- Rough texture arrays are built once per session and reused across hole changes.
- Streamed rough follows individual root positions at mown edges, with uniform
  per-area density and per-clump distance fades instead of square batch cutoffs.
- Aim previews use the same physics in batches of at most 48 steps or about 2 ms
  per frame. Shots, terrain changes, loading and Auto-Putt cancel pending previews.
  `tests/preview_frame_budget_test.gd` compares the entire resulting trajectory
  against the previous single-frame simulation and checks cancellation.
- Windows exports omit tests, tools, documentation and reference artwork. Source
  assets remain available in the project. Generated Python bytecode is ignored.

The distance regression measured 1,908 ms for the exhaustive scan and 499 ms for
the grouped query. In the 1280×720 course probe, the startup mask stage measured
28,007 ms before and 16,672 ms after. These are local measurements, not guaranteed
frame rates or total loading times on other machines.


## Manager rush-hour simulation

- Movement queries reuse actor lists within a simulation update, and invalidate
  them when vehicles, staff or visiting groups change. Ten-metre spatial buckets
  narrow collision queries to nearby bodies; continuous clearance still checks
  the entire proposed stride and turn, including off-center vehicle models.
- Swept inverse transforms are computed once per vehicle query. Hose routes cache
  the detailed grid's alternate weights instead of rescanning the whole grid.
- Stationary camera/mouse combinations reuse the terrain cursor hit.
- The manager offers Pause, 1x, 2x, 4x and 8x. Movement uses 1/30-second steps,
  with at most twelve steps and an approximate ten-millisecond simulation budget
  per rendered frame. A single expensive step can exceed that budget. When the
  requested speed exceeds available processing time, the displayed actual speed
  drops; skipped backlog is not billed as simulated business time.
- The club clock, cash flow and activity advance together. Camera and menus retain
  normal speed. Leaving the manager restores the existing wall-clock business
  behavior. Speed is session-local; traffic mode is saved separately per course.
- Normal, Quiet, Rush hour and Daily cycle adjust arrival spacing, crowd targets
  and golfer demand. Daily cycle has morning/afternoon peaks, a lunch lull and a
  quieter evening. Existing visitors finish naturally; total visible groups are
  capped at 24, with normal golf crowds capped at eight and rush crowds at sixteen.
- The range attendant approaches outside the collection trailer's footprint,
  boards at the cab's side opening, then exits and empties the baskets.
- Manager tee rectangles replace the ground directly underneath them, preventing
  the old painted surface from competing for depth. Regrading rebuilds the tee
  surfaces and ground openings together.

A deterministic headless movement fixture with 72 walkers and 36 vehicles measured
99.628 ms per update before these changes and 24.811 ms afterwards (about 75% less
CPU time). These are simulation measurements, not rendered FPS or guarantees for
other courses/hardware. Reproduce with `tests/rush_crowd_benchmark.gd`.

Checks: `simulation_controls_regression.gd`, `crowd_index_regression.gd` (500
comparisons with exhaustive collision checks), `picker_access_regression.gd`,
`tee_overlap_regression.gd`, plus existing barn, traffic and priority regressions.
