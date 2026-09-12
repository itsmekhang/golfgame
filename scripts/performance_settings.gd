class_name PerformanceSettings
extends RefCounted
## Central, deliberately bounded rendering budgets. Physics quality is unchanged.

const DETAIL_LAYER := 2

static func low() -> bool:
	return OS.get_environment("GOLF_QUALITY").to_lower() == "low"

static func grass_tiles() -> int:
	return 25 if low() else 64

## Was pushed to 12000/5000 earlier this session chasing "way more density" -- at
## grass_tiles() * grass_per_tile() that's up to ~768,000 resident clumps, which is
## consistent with the framerate drops now being reported (and with GPU-load-correlated
## crashes found earlier this session). Pulled back to something the GPU can hold at a
## sustained framerate while still reading far thicker than the original 128/64.
static func grass_per_tile() -> int:
	return 6000 if low() else 26000

static func grass_distance() -> float:
	return 40.0 if low() else 65.0

## Trees/props are now scoped to one hole's region at a time (see course.gd's
## _ensure_hole_region), so their draw distance no longer has to cover 18 holes'
## worth of budget simultaneously -- these can be far more generous than grass_distance().
static func tree_distance() -> float:
	return 300.0 if low() else 900.0

static func prop_distance() -> float:
	return 90.0 if low() else 220.0

static func grass_enabled() -> bool:
	return OS.get_environment("GOLF_GRASS") != "0"
