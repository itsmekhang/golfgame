class_name FlightProfile
extends RefCounted
## GDScript port of OpenFairway `FlightProfile.cs`.
## Centralizes all flight aerodynamics constants into a single swappable profile.

# --- Drag curve (Cd polynomial) ---
var cd_poly_a: float = 1.1948
var cd_poly_b: float = -0.0000209661
var cd_poly_c: float = 1.42472e-10
var cd_poly_d: float = -3.14383e-16
var high_re_cd_cap: float = 0.2
var low_re_cd_floor: float = 0.38
var low_re_blend_start: float = 30000.0
var cd_at50k: float = 0.4632
var cd_min: float = 0.223

# --- Lift caps ---
var cl_max_base: float = 0.268
var cl_max_high_spin: float = 0.32
var cl_max_sr_transition_start: float = 0.35
var cl_max_sr_transition_end: float = 0.50

# --- Spin drag ---
var spin_drag_multiplier_coeff: float = 4.0
var spin_drag_multiplier_max: float = 1.20
var spin_drag_multiplier_high_spin_max: float = 1.03
var spin_drag_multiplier_ultra_high_spin_max: float = 1.21

# Spin drag relief window thresholds
var high_spin_drag_sr_start: float = 0.30
var high_spin_drag_sr_end: float = 0.48
var high_spin_drag_relief_re_full_max: float = 90000.0
var high_spin_drag_relief_re_zero: float = 105000.0
var ultra_high_spin_drag_sr_start: float = 0.57
var ultra_high_spin_drag_sr_end: float = 0.77

# --- High-Re lift ---
var high_re_start: float = 75000.0
var high_re_mid_spin_gain: float = 16.0
var high_re_spin_gain: float = 16.0
var high_re_gain_reduction_start: float = 0.10
var high_re_gain_reduction_end: float = 0.18
var high_re_gain_recovery_start: float = 0.26
var high_re_gain_recovery_end: float = 0.40

# --- High-Re lift attenuation ---
var high_spin_cl_attenuation_start: float = 0.45
var high_spin_cl_attenuation_end: float = 0.55
var high_spin_cl_attenuation_max: float = 0.09
var ultra_high_spin_cl_attenuation_start: float = 0.58
var ultra_high_spin_cl_attenuation_end: float = 0.85
var ultra_high_spin_cl_attenuation_max: float = 0.10

# --- Low-Re lift attenuation ---
var low_re_high_spin_cl_attenuation_max: float = 0.10
var low_re_ultra_high_spin_cl_attenuation_max: float = 0.06

# --- Low-launch lift recovery ---
var low_launch_lift_recovery_max: float = 1.08
var low_launch_vla_full_deg: float = 6.5
var low_launch_vla_zero_deg: float = 9.5
var low_launch_re_start: float = 85000.0
var low_launch_re_end: float = 110000.0
var low_launch_spin_ratio_full: float = 0.18
var low_launch_spin_ratio_max: float = 0.22

# --- Progressive spin drag cap boost (increased form drag at high SR) ---
var spin_drag_progressive_cap_sr_start: float = 0.33
var spin_drag_progressive_cap_sr_end: float = 0.50
var spin_drag_progressive_cap_boost_max: float = 0.25

# --- Mid-spin Cl boost (bell-shaped lift recovery for mid-iron SR regime) ---
var mid_spin_cl_boost_sr_start: float = 0.17
var mid_spin_cl_boost_sr_end: float = 0.31
var mid_spin_cl_boost_max: float = 0.45

# --- High-launch drag boost ---
var high_launch_drag_boost_max: float = 1.24
var high_launch_drag_vla_start_deg: float = 24.5
var high_launch_drag_vla_full_deg: float = 31.5
var high_launch_drag_sr_start: float = 0.50
var high_launch_drag_sr_end: float = 0.70

# --- Metadata ---
var name: String = "Default"
var version: String = "1.0"

static var _default: FlightProfile


## Shared default profile (mirrors `FlightProfile.Default`).
static func get_default() -> FlightProfile:
	if _default == null:
		_default = FlightProfile.new()
	return _default


## Build a profile from a JSON-style dictionary using the C# PascalCase keys
## (e.g. "ClMaxBase"). Unknown keys are reported through PhysicsLogger.
static func from_dict(data: Dictionary) -> FlightProfile:
	var fp := FlightProfile.new()
	fp.name = "JsonOverride"
	for key in data.keys():
		var prop: String = String(key).to_snake_case()
		if prop == "cd_at50k" or prop == "cd_at_50k":
			fp.cd_at50k = float(data[key])
			continue
		if prop == "name" or prop == "version":
			fp.set(prop, String(data[key]))
			continue
		if prop in fp:
			fp.set(prop, float(data[key]))
		else:
			PhysicsLogger.error("[Profile] Unknown key '%s' in FlightProfile — possible typo (will use default)" % key)
	return fp


## Validates range parameters (start < end) and returns warnings for any
## inconsistencies that would cause division-by-zero in safe_smooth_step01.
func validate() -> Array[String]:
	var warnings: Array[String] = []
	_validate_range(warnings, "high_spin_drag_sr_start", high_spin_drag_sr_start, "high_spin_drag_sr_end", high_spin_drag_sr_end)
	_validate_range(warnings, "ultra_high_spin_drag_sr_start", ultra_high_spin_drag_sr_start, "ultra_high_spin_drag_sr_end", ultra_high_spin_drag_sr_end)
	_validate_range(warnings, "high_spin_drag_relief_re_full_max", high_spin_drag_relief_re_full_max, "high_spin_drag_relief_re_zero", high_spin_drag_relief_re_zero)
	_validate_range(warnings, "low_launch_vla_full_deg", low_launch_vla_full_deg, "low_launch_vla_zero_deg", low_launch_vla_zero_deg)
	_validate_range(warnings, "low_launch_re_start", low_launch_re_start, "low_launch_re_end", low_launch_re_end)
	_validate_range(warnings, "low_launch_spin_ratio_full", low_launch_spin_ratio_full, "low_launch_spin_ratio_max", low_launch_spin_ratio_max)
	_validate_range(warnings, "high_launch_drag_vla_start_deg", high_launch_drag_vla_start_deg, "high_launch_drag_vla_full_deg", high_launch_drag_vla_full_deg)
	_validate_range(warnings, "high_launch_drag_sr_start", high_launch_drag_sr_start, "high_launch_drag_sr_end", high_launch_drag_sr_end)
	_validate_range(warnings, "spin_drag_progressive_cap_sr_start", spin_drag_progressive_cap_sr_start, "spin_drag_progressive_cap_sr_end", spin_drag_progressive_cap_sr_end)
	_validate_range(warnings, "cl_max_sr_transition_start", cl_max_sr_transition_start, "cl_max_sr_transition_end", cl_max_sr_transition_end)
	_validate_range(warnings, "high_spin_cl_attenuation_start", high_spin_cl_attenuation_start, "high_spin_cl_attenuation_end", high_spin_cl_attenuation_end)
	_validate_range(warnings, "ultra_high_spin_cl_attenuation_start", ultra_high_spin_cl_attenuation_start, "ultra_high_spin_cl_attenuation_end", ultra_high_spin_cl_attenuation_end)
	_validate_range(warnings, "high_re_gain_reduction_start", high_re_gain_reduction_start, "high_re_gain_reduction_end", high_re_gain_reduction_end)
	_validate_range(warnings, "high_re_gain_recovery_start", high_re_gain_recovery_start, "high_re_gain_recovery_end", high_re_gain_recovery_end)
	_validate_range(warnings, "mid_spin_cl_boost_sr_start", mid_spin_cl_boost_sr_start, "mid_spin_cl_boost_sr_end", mid_spin_cl_boost_sr_end)
	return warnings


static func _validate_range(warnings: Array[String], start_name: String, start_val: float, end_name: String, end_val: float) -> void:
	if start_val >= end_val:
		warnings.append("FlightProfile range invalid: %s (%s) >= %s (%s)" % [start_name, start_val, end_name, end_val])
