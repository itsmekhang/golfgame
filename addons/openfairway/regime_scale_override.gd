class_name RegimeScaleOverride
extends RefCounted
## GDScript port of OpenFairway `RegimeScaleOverride.cs`.
## Runtime-safe scale modifiers keyed by launch regime.

var drag_scale_multiplier: float = 1.0
var lift_scale_multiplier: float = 1.0
var kinetic_friction_multiplier: float = 1.0
var rolling_friction_multiplier: float = 1.0
var grass_viscosity_multiplier: float = 1.0
var critical_angle_offset_radians: float = 0.0
var spinback_theta_boost_multiplier: float = 1.0

static var _neutral: RegimeScaleOverride


static func neutral() -> RegimeScaleOverride:
	if _neutral == null:
		_neutral = RegimeScaleOverride.new()
	return _neutral


static func make(drag: float = 1.0, lift: float = 1.0) -> RegimeScaleOverride:
	var o := RegimeScaleOverride.new()
	o.drag_scale_multiplier = drag
	o.lift_scale_multiplier = lift
	return o


static func from_dict(data: Dictionary, context: String = "RegimeScaleOverride") -> RegimeScaleOverride:
	var o := RegimeScaleOverride.new()
	for key in data.keys():
		var prop: String = String(key).to_snake_case()
		if prop in o:
			o.set(prop, float(data[key]))
		else:
			PhysicsLogger.error("[Profile] Unknown key '%s' in %s — possible typo (will use default)" % [key, context])
	return o
