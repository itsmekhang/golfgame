class_name BallPhysicsProfile
extends RefCounted
## GDScript port of OpenFairway `BallPhysicsProfile.cs`.
## Ball-specific physics modifiers plus calibrated regime-keyed scale overrides.

var drag_scale_multiplier: float = 1.01
var lift_scale_multiplier: float = 1.0
var kinetic_friction_multiplier: float = 1.0
var rolling_friction_multiplier: float = 1.0
var grass_viscosity_multiplier: float = 1.0
var critical_angle_offset_radians: float = 0.0
var spinback_theta_boost_multiplier: float = 1.0
var regime_scale_overrides: Dictionary = build_default_regime_overrides()

var flight: FlightProfile = null
var bounce: BounceProfile = null
var rollout: RolloutProfile = null

var resolved_flight: FlightProfile:
	get:
		return flight if flight != null else FlightProfile.get_default()
var resolved_bounce: BounceProfile:
	get:
		return bounce if bounce != null else BounceProfile.get_default()
var resolved_rollout: RolloutProfile:
	get:
		return rollout if rollout != null else RolloutProfile.get_default()

const _ROOT_KNOWN_KEYS := [
	"DragScaleMultiplier", "LiftScaleMultiplier",
	"KineticFrictionMultiplier", "RollingFrictionMultiplier",
	"GrassViscosityMultiplier", "CriticalAngleOffsetRadians",
	"SpinbackThetaBoostMultiplier",
	"RegimeScaleOverrides",
	"Flight", "Bounce", "Rollout",
]


## Creates a profile from a JSON string. Only keys present override defaults.
static func from_json(json_text: String) -> BallPhysicsProfile:
	var parsed = JSON.parse_string(json_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		PhysicsLogger.error("[Profile] Failed to parse BallPhysicsProfile JSON")
		return BallPhysicsProfile.new()
	return from_dict(parsed)


static func from_dict(root: Dictionary) -> BallPhysicsProfile:
	var profile := BallPhysicsProfile.new()

	for key in root.keys():
		if not (String(key) in _ROOT_KNOWN_KEYS):
			PhysicsLogger.error("[Profile] Unknown key '%s' in BallPhysicsProfile — possible typo (will use default)" % key)

	if root.has("DragScaleMultiplier"):
		profile.drag_scale_multiplier = float(root["DragScaleMultiplier"])
	if root.has("LiftScaleMultiplier"):
		profile.lift_scale_multiplier = float(root["LiftScaleMultiplier"])
	if root.has("KineticFrictionMultiplier"):
		profile.kinetic_friction_multiplier = float(root["KineticFrictionMultiplier"])
	if root.has("RollingFrictionMultiplier"):
		profile.rolling_friction_multiplier = float(root["RollingFrictionMultiplier"])
	if root.has("GrassViscosityMultiplier"):
		profile.grass_viscosity_multiplier = float(root["GrassViscosityMultiplier"])
	if root.has("CriticalAngleOffsetRadians"):
		profile.critical_angle_offset_radians = float(root["CriticalAngleOffsetRadians"])
	if root.has("SpinbackThetaBoostMultiplier"):
		profile.spinback_theta_boost_multiplier = float(root["SpinbackThetaBoostMultiplier"])

	if root.has("RegimeScaleOverrides") and typeof(root["RegimeScaleOverrides"]) == TYPE_DICTIONARY:
		var regimes: Dictionary = root["RegimeScaleOverrides"]
		for regime_key in regimes.keys():
			profile.regime_scale_overrides[String(regime_key)] = RegimeScaleOverride.from_dict(regimes[regime_key], "RegimeScaleOverride[%s]" % regime_key)

	if root.has("Flight") and typeof(root["Flight"]) == TYPE_DICTIONARY:
		profile.flight = FlightProfile.from_dict(root["Flight"])
		for warning in profile.flight.validate():
			PhysicsLogger.error("[Profile] %s" % warning)
	if root.has("Bounce") and typeof(root["Bounce"]) == TYPE_DICTIONARY:
		profile.bounce = BounceProfile.from_dict(root["Bounce"])
	if root.has("Rollout") and typeof(root["Rollout"]) == TYPE_DICTIONARY:
		profile.rollout = RolloutProfile.from_dict(root["Rollout"])

	return profile


## Resolve the regime override for a launch. Returns a Dictionary:
## { "override": RegimeScaleOverride, "regime_key": String, "matched_key": String }
func resolve_scale_override(speed_mph: float, launch_angle_deg: float, total_spin_rpm: float) -> Dictionary:
	var regime_key := ShotRegimeKey.build(speed_mph, launch_angle_deg, total_spin_rpm)
	var result := {
		"override": RegimeScaleOverride.neutral(),
		"regime_key": regime_key,
		"matched_key": "",
	}
	if regime_scale_overrides == null or regime_scale_overrides.is_empty():
		return result

	for candidate in ShotRegimeKey.build_lookup_keys(speed_mph, launch_angle_deg, total_spin_rpm):
		if regime_scale_overrides.has(candidate):
			result["override"] = regime_scale_overrides[candidate]
			result["matched_key"] = candidate
			return result

	return result


## Calibrated regime-specific scale overrides derived from FS reference data
## (iteration 099, 32 keys). Identical values to the C# defaults.
static func build_default_regime_overrides() -> Dictionary:
	var R := RegimeScaleOverride
	return {
		# Chip shots (speed < 60 mph): systematic under-carry at low Reynolds
		"C-S0": R.make(0.70, 1.20),
		"C-S0-V1-P0": R.make(0.55, 1.15),
		"C-S0-V4-P3": R.make(0.65, 1.25),

		# Slow iron S1a (60-72 mph)
		"I-S1a-V0-P1": R.make(0.94, 1.04),
		"I-S1a-V2-P1": R.make(0.80, 1.14),
		"I-S1a-V2-P2": R.make(0.82, 1.13),
		"I-S1a-V2-P3": R.make(0.82, 1.12),
		"I-S1a-V3-P2": R.make(0.79, 1.14),
		"I-S1a-V3-P3": R.make(0.94, 1.04),
		"I-S1a-V1-P2": R.make(0.92, 1.05),

		# Mid iron S1b (72-85 mph)
		"I-S1b-V0-P0": R.make(0.97, 1.02),
		"I-S1b-V2-P2": R.make(0.94, 1.03),
		"I-S1b-V2-P3": R.make(0.97, 1.01),
		"I-S1b-V3-P2": R.make(0.88, 1.06),
		"I-S1b-V3-P3": R.make(0.97, 1.02),
		"I-S1b-V1-P2": R.make(0.98, 1.01),

		# Wedge lob (launch > 30 deg, 60-72 mph)
		"W-S1a-V3-P3": R.make(0.83, 1.10),

		# Fast iron with high spin: over-carry
		"I-S3-V2-P3": R.make(1.11, 0.94),
		"I-S3-V1-P2": R.make(1.04, 0.98),
		"I-S2-V2-P3": R.make(1.05, 1.0),
		"I-S2-V2-P4": R.make(1.06, 0.95),

		# Mid-speed iron: over-carry clusters
		"I-S2-V1-P2": R.make(1.03, 0.99),
		"I-S2-V0-P2": R.make(1.06, 0.96),

		# Mid-speed iron: under-carry (very low spin)
		"I-S2-V1-P0": R.make(0.96, 1.03),

		# Mid-speed iron: all short
		"I-S2-V1-P1": R.make(0.97, 1.02),

		# Driver regime: slight over-carry
		"D-S3-V1": R.make(1.04, 0.99),
		"D-S4-V0-P1": R.make(1.03, 0.98),
		"D-S4-V0-P2": R.make(1.09, 0.94),
		"D-S4-V1-P0": R.make(0.98, 1.02),
		"D-S4-V1-P1": R.make(1.04, 1.0),
		"D-S4-V1-P2": R.make(1.04, 1.0),

		# High-speed wedge (launch > 30 deg, 85-105 mph): over-carry
		"W-S2-V3-P4": R.make(1.06, 0.97),
	}
