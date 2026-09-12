class_name BounceProfile
extends RefCounted
## GDScript port of OpenFairway `BounceProfile.cs`.
## Centralizes all bounce/COR constants used by BounceCalculator.

# --- COR curve ---
var cor_base_a: float = 0.45
var cor_base_b: float = -0.01
var cor_base_c: float = 0.0002
var cor_high_speed_cap: float = 0.25
var cor_high_speed_threshold: float = 20.0
var cor_kill_threshold: float = 2.0

# --- Tangential retention (first bounce from flight) ---
var flight_tangential_retention_base: float = 0.55
var flight_spin_factor_min: float = 0.40
var flight_spin_factor_divisor: float = 8000.0

# --- Tangential retention (rollout bounces) ---
var rollout_low_spin_retention: float = 0.85
var rollout_high_spin_retention: float = 0.70
var rollout_spin_ratio_threshold: float = 0.20

# --- Spin COR reduction ---
var spin_cor_low_spin_threshold: float = 1500.0
var spin_cor_low_spin_max_reduction: float = 0.30
var spin_cor_high_spin_range_rpm: float = 1500.0
var spin_cor_high_spin_additional_reduction: float = 0.40

# --- Velocity scaling for COR reduction ---
var cor_velocity_low_threshold: float = 12.0
var cor_velocity_mid_threshold: float = 25.0
var cor_velocity_low_scale: float = 0.50

# --- Rollout bounce COR ---
var rollout_bounce_cor_kill_threshold: float = 4.0
var rollout_bounce_cor_scale: float = 0.5

# --- Penner model ---
var penner_low_energy_threshold: float = 20.0

# --- Metadata ---
var name: String = "Default"
var version: String = "1.0"

static var _default: BounceProfile


static func get_default() -> BounceProfile:
	if _default == null:
		_default = BounceProfile.new()
	return _default


static func from_dict(data: Dictionary) -> BounceProfile:
	var bp := BounceProfile.new()
	bp.name = "JsonOverride"
	for key in data.keys():
		var prop: String = String(key).to_snake_case()
		if prop == "name" or prop == "version":
			bp.set(prop, String(data[key]))
		elif prop in bp:
			bp.set(prop, float(data[key]))
	return bp
