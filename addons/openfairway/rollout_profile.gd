class_name RolloutProfile
extends RefCounted
## GDScript port of OpenFairway `RolloutProfile.cs`.
## Centralizes all rollout/friction constants used by BallPhysics ground forces.

# --- Velocity scaling ---
var chip_speed_threshold: float = 20.0
var pitch_speed_threshold: float = 35.0
var chip_velocity_scale_min: float = 0.60
var chip_velocity_scale_max: float = 0.87

# --- Spin thresholds ---
var low_spin_threshold: float = 1750.0
var mid_spin_threshold: float = 1750.0

# --- Spin friction multipliers ---
var low_spin_multiplier_max: float = 1.15
var mid_spin_multiplier_max: float = 2.25
var high_spin_multiplier_max: float = 2.50
var high_spin_ramp_range: float = 1000.0

# --- Friction blending ---
var friction_blend_speed: float = 15.0
var tangent_velocity_threshold: float = 0.05

# --- Metadata ---
var name: String = "Default"
var version: String = "1.0"

static var _default: RolloutProfile


static func get_default() -> RolloutProfile:
	if _default == null:
		_default = RolloutProfile.new()
	return _default


static func from_dict(data: Dictionary) -> RolloutProfile:
	var rp := RolloutProfile.new()
	rp.name = "JsonOverride"
	for key in data.keys():
		var prop: String = String(key).to_snake_case()
		if prop == "name" or prop == "version":
			rp.set(prop, String(data[key]))
		elif prop in rp:
			rp.set(prop, float(data[key]))
	return rp
