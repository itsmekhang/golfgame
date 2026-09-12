class_name PhysicsAdapter
extends RefCounted
## GDScript port of OpenFairway `PhysicsAdapter.cs`.
## Headless shot simulation from launch-monitor style JSON dictionaries.
## Uses the same BallPhysics + PhysicsParamsFactory path as the in-game ball.

const YARDS_PER_METER := ShotSetup.YARDS_PER_METER
const FEET_PER_METER := ShotSetup.FEET_PER_METER
const START_HEIGHT := 0.02
const DEFAULT_TEMP_F := 75.0
const DEFAULT_ALT_FT := 0.0
const MAX_TIME := 12.0
const DT := BallPhysics.SIMULATION_DT

var _physics := BallPhysics.new()
var _aero := Aerodynamics.new()
var _factory := PhysicsParamsFactory.new()
var _shot_setup := ShotSetup.new()
var _ball_profile := BallPhysicsProfile.new()


## Load a BallPhysicsProfile from JSON text. Subsequent simulations use it.
func load_profile_from_json(json_text: String) -> void:
	_ball_profile = BallPhysicsProfile.from_json(json_text)
	_physics.set_profiles(_ball_profile.resolved_rollout, _ball_profile.resolved_bounce)


func set_profile(profile: BallPhysicsProfile) -> void:
	_ball_profile = profile if profile != null else BallPhysicsProfile.new()
	_physics.set_profiles(_ball_profile.resolved_rollout, _ball_profile.resolved_bounce)


## Simulate a shot using a specific profile without changing the stored one.
func simulate_shot_with_profile(shot: Dictionary, profile: BallPhysicsProfile) -> Dictionary:
	var saved := _ball_profile
	set_profile(profile)
	var result := simulate_shot_from_json(shot, PhysicsEnums.SurfaceType.FAIRWAY, Vector3.UP)
	set_profile(saved)
	return result


func simulate_carry_only_with_profile(shot: Dictionary, profile: BallPhysicsProfile) -> Dictionary:
	var saved := _ball_profile
	set_profile(profile)
	var result := _simulate_carry_only_internal(shot, null)
	set_profile(saved)
	return result


## Full flight + bounce + rollout simulation. Returns carry/total distances and diagnostics.
func simulate_shot_from_json(shot: Dictionary, surface: int = PhysicsEnums.SurfaceType.FAIRWAY,
		floor_normal: Vector3 = Vector3.UP) -> Dictionary:
	var ball_dict: Dictionary = shot["BallData"] if shot.has("BallData") else shot
	if ball_dict == null or ball_dict.is_empty():
		PhysicsLogger.push_physics_error("Shot JSON missing BallData")
		return {}

	var speed_mph := float(ball_dict.get("Speed", 0.0))
	var vla := float(ball_dict.get("VLA", 0.0))
	var hla := float(ball_dict.get("HLA", 0.0))
	var spin_data := _shot_setup.parse_spin(ball_dict)
	var backspin: float = spin_data["backspin"]
	var sidespin: float = spin_data["sidespin"]
	var total_spin: float = spin_data["total"]
	var spin_axis: float = spin_data["axis"]

	var regime := _ball_profile.resolve_scale_override(speed_mph, vla, total_spin)
	var regime_key: String = regime["regime_key"]
	var matched_key: String = regime["matched_key"]
	if matched_key != "":
		var ro: RegimeScaleOverride = regime["override"]
		PhysicsLogger.info("[Regime] %s matched=%s drag=%.3f lift=%.3f" % [regime_key, matched_key, ro.drag_scale_multiplier, ro.lift_scale_multiplier])

	var launch := _shot_setup.build_launch_vectors_from_components(speed_mph, vla, hla, backspin, sidespin)
	var velocity: Vector3 = launch["velocity"]
	var omega: Vector3 = launch["omega"]
	var shot_dir: Vector3 = launch["shot_direction"]

	var contact_normal := floor_normal.normalized() if floor_normal.length_squared() > 0.000001 else Vector3.UP
	var parameters := _create_params(contact_normal, surface, vla, speed_mph, total_spin)

	var pos := Vector3(0.0, START_HEIGHT, 0.0)
	var state: int = PhysicsEnums.BallState.FLIGHT
	var on_ground := false
	var carry_m := 0.0
	var carry_recorded := false
	var hang_time_s := 0.0
	var apex_m := pos.y
	var first_impact_spinback := false
	var landing_speed_mps := 0.0
	var landing_angle_deg := 0.0
	var first_impact_tangent_in := 0.0
	var first_impact_tangent_out := 0.0

	var initial_air := BallPhysics.sample_flight_aerodynamics(velocity, omega, parameters.air_density,
		parameters.air_viscosity, parameters.drag_scale, parameters.lift_scale,
		parameters.initial_launch_angle_deg, parameters.flight_profile)
	var peak_cl := 0.0

	var steps := int(MAX_TIME / DT)
	for i in range(steps):
		if not on_ground:
			var air := BallPhysics.sample_flight_aerodynamics(velocity, omega, parameters.air_density,
				parameters.air_viscosity, parameters.drag_scale, parameters.lift_scale,
				parameters.initial_launch_angle_deg, parameters.flight_profile)
			if air.has_aerodynamics:
				peak_cl = maxf(peak_cl, air.lift_coefficient)

		var integrated := _physics.integrate_step(velocity, omega, on_ground, parameters, DT)
		velocity = integrated[0]
		omega = integrated[1]

		pos += velocity * DT
		apex_m = maxf(apex_m, pos.y)

		var has_impact := pos.y <= 0.0 and (velocity.y < -0.01 or state == PhysicsEnums.BallState.FLIGHT)
		if has_impact:
			pos.y = 0.0
			var pre_impact_speed := velocity.length()
			var pre_impact_normal_speed := absf(velocity.dot(contact_normal))
			var pre_impact_tangent := velocity - contact_normal * velocity.dot(contact_normal)
			var bounce := _physics.calculate_bounce(velocity, omega, contact_normal, state, parameters)
			velocity = bounce.new_velocity
			omega = bounce.new_omega
			state = bounce.new_state
			on_ground = state != PhysicsEnums.BallState.FLIGHT
			velocity.y = maxf(velocity.y, 0.0)

			if not carry_recorded:
				var post_impact_tangent := velocity - contact_normal * velocity.dot(contact_normal)
				var pre_tan_mag := pre_impact_tangent.length()
				var post_tan_mag := post_impact_tangent.length()
				first_impact_tangent_in = pre_tan_mag
				first_impact_tangent_out = post_tan_mag
				landing_speed_mps = pre_impact_speed
				landing_angle_deg = rad_to_deg(atan2(pre_impact_normal_speed, maxf(pre_tan_mag, 0.0001)))
				if pre_tan_mag > 0.01 and post_tan_mag > 0.01:
					var direction_dot := pre_impact_tangent.normalized().dot(post_impact_tangent.normalized())
					first_impact_spinback = direction_dot < -0.001
					if first_impact_spinback:
						first_impact_tangent_out = -post_tan_mag

				carry_m = maxf(pos.dot(shot_dir), 0.0)
				carry_recorded = true
				hang_time_s = (i + 1) * DT
		else:
			if pos.y < 0.0:
				pos.y = 0.0
				velocity.y = maxf(velocity.y, 0.0)
			on_ground = state != PhysicsEnums.BallState.FLIGHT and pos.y <= 0.02

		var speed := velocity.length()
		if on_ground and speed < 0.05 and omega.length() < 0.5:
			state = PhysicsEnums.BallState.REST
			velocity = Vector3.ZERO
			omega = Vector3.ZERO
			break

	var total_m := maxf(pos.dot(shot_dir), 0.0)
	if not carry_recorded:
		carry_m = total_m

	return {
		"carry_yd": carry_m * YARDS_PER_METER,
		"total_yd": total_m * YARDS_PER_METER,
		"carry_yd_first_impact": carry_m * YARDS_PER_METER,
		"apex_ft": apex_m * FEET_PER_METER,
		"hang_time_s": hang_time_s,
		"flight_time_s": hang_time_s,
		"first_impact_time_s": hang_time_s,
		"landing_speed_mps": landing_speed_mps,
		"landing_angle_deg": landing_angle_deg,
		"initial_re": initial_air.reynolds,
		"initial_spin_ratio": initial_air.spin_ratio,
		"initial_launch_angle_deg": vla,
		"initial_low_launch_lift_scale": initial_air.low_launch_lift_scale,
		"initial_spin_drag_multiplier": initial_air.spin_drag_multiplier,
		"initial_backspin_rpm": backspin,
		"initial_sidespin_rpm": sidespin,
		"initial_total_spin_rpm": total_spin,
		"initial_spin_axis_deg": spin_axis,
		"initial_cd": initial_air.drag_coefficient,
		"initial_cl": initial_air.lift_coefficient,
		"peak_cl": peak_cl,
		"launch_regime_key": regime_key,
		"matched_regime_override_key": matched_key,
		"surface": SurfacePhysicsCatalog.surface_name(surface),
		"first_impact_spinback": first_impact_spinback,
		"first_impact_tangent_in_mps": first_impact_tangent_in,
		"first_impact_tangent_out_mps": first_impact_tangent_out,
	}


## Carry-only simulation (flight loop only, stops at first ground impact).
func simulate_carry_only_from_json(shot: Dictionary) -> Dictionary:
	return _simulate_carry_only_internal(shot, null)


func simulate_carry_only(shot: Dictionary, flight_profile: FlightProfile = null) -> Dictionary:
	return _simulate_carry_only_internal(shot, flight_profile)


func _simulate_carry_only_internal(shot: Dictionary, flight_profile: FlightProfile) -> Dictionary:
	var ball_dict: Dictionary = shot["BallData"] if shot.has("BallData") else shot
	if ball_dict == null or ball_dict.is_empty():
		PhysicsLogger.push_physics_error("Shot JSON missing BallData")
		return {}

	var speed_mph := float(ball_dict.get("Speed", 0.0))
	var vla := float(ball_dict.get("VLA", 0.0))
	var hla := float(ball_dict.get("HLA", 0.0))
	var spin_data := _shot_setup.parse_spin(ball_dict)
	var backspin: float = spin_data["backspin"]
	var sidespin: float = spin_data["sidespin"]
	var total_spin: float = spin_data["total"]
	var spin_axis: float = spin_data["axis"]

	var launch := _shot_setup.build_launch_vectors_from_components(speed_mph, vla, hla, backspin, sidespin)
	var velocity: Vector3 = launch["velocity"]
	var omega: Vector3 = launch["omega"]
	var shot_dir: Vector3 = launch["shot_direction"]

	var regime_key := ShotRegimeKey.build(speed_mph, vla, total_spin)
	var matched_key := ""
	var drag_scale := 1.0
	var lift_scale := 1.0
	var fp: FlightProfile
	if flight_profile != null:
		fp = flight_profile
	else:
		var regime := _ball_profile.resolve_scale_override(speed_mph, vla, total_spin)
		var ro: RegimeScaleOverride = regime["override"]
		regime_key = regime["regime_key"]
		matched_key = regime["matched_key"]
		if matched_key != "":
			PhysicsLogger.info("[Regime] %s matched=%s drag=%.3f lift=%.3f" % [regime_key, matched_key, ro.drag_scale_multiplier, ro.lift_scale_multiplier])
		drag_scale = _ball_profile.drag_scale_multiplier * ro.drag_scale_multiplier
		lift_scale = _ball_profile.lift_scale_multiplier * ro.lift_scale_multiplier
		fp = _ball_profile.resolved_flight

	var air_density := _aero.get_air_density(DEFAULT_ALT_FT, DEFAULT_TEMP_F, PhysicsEnums.Units.IMPERIAL)
	var air_viscosity := _aero.get_dynamic_viscosity(DEFAULT_TEMP_F, PhysicsEnums.Units.IMPERIAL)

	var initial_air := BallPhysics.sample_flight_aerodynamics(velocity, omega, air_density, air_viscosity, drag_scale, lift_scale, vla, fp)

	var pos := Vector3(0.0, START_HEIGHT, 0.0)
	var apex_m := pos.y
	var peak_cl := 0.0
	var steps := int(MAX_TIME / DT)
	var carry_m := 0.0
	var hang_time_s := 0.0
	var landing_speed_mps := 0.0
	var landing_angle_deg := 0.0

	for i in range(steps):
		var air := BallPhysics.sample_flight_aerodynamics(velocity, omega, air_density, air_viscosity, drag_scale, lift_scale, vla, fp)
		if air.has_aerodynamics:
			peak_cl = maxf(peak_cl, air.lift_coefficient)

		# Inline flight integration (gravity + air forces only)
		var gravity := Vector3(0.0, -9.81 * BallPhysics.MASS, 0.0)
		var air_forces := Vector3.ZERO
		if air.has_aerodynamics:
			var drag := -0.5 * air.drag_coefficient * air_density * BallPhysics.CROSS_SECTION * velocity * air.speed
			var magnus := Vector3.ZERO
			var omega_len := omega.length()
			if omega_len > 0.1:
				magnus = 0.5 * air.lift_coefficient * air_density * BallPhysics.CROSS_SECTION * omega.cross(velocity) * air.speed / omega_len
			air_forces = drag + magnus

		var force := gravity + air_forces
		var torque := -BallPhysics.MOMENT_OF_INERTIA * omega / BallPhysics.SPIN_DECAY_TAU
		velocity += (force / BallPhysics.MASS) * DT
		omega += (torque / BallPhysics.MOMENT_OF_INERTIA) * DT
		pos += velocity * DT
		apex_m = maxf(apex_m, pos.y)

		if pos.y <= 0.0 and velocity.y < -0.01:
			pos.y = 0.0
			carry_m = maxf(pos.dot(shot_dir), 0.0)
			hang_time_s = (i + 1) * DT
			landing_speed_mps = velocity.length()
			var normal_speed := absf(velocity.y)
			var tangent_speed := Vector3(velocity.x, 0, velocity.z).length()
			landing_angle_deg = rad_to_deg(atan2(normal_speed, maxf(tangent_speed, 0.0001)))
			break

	if hang_time_s == 0.0:
		carry_m = maxf(pos.dot(shot_dir), 0.0)
		hang_time_s = MAX_TIME

	return {
		"carry_yd": carry_m * YARDS_PER_METER,
		"apex_ft": apex_m * FEET_PER_METER,
		"hang_time_s": hang_time_s,
		"landing_speed_mps": landing_speed_mps,
		"landing_angle_deg": landing_angle_deg,
		"initial_re": initial_air.reynolds,
		"initial_spin_ratio": initial_air.spin_ratio,
		"initial_launch_angle_deg": vla,
		"initial_low_launch_lift_scale": initial_air.low_launch_lift_scale,
		"initial_spin_drag_multiplier": initial_air.spin_drag_multiplier,
		"initial_backspin_rpm": backspin,
		"initial_sidespin_rpm": sidespin,
		"initial_total_spin_rpm": total_spin,
		"initial_spin_axis_deg": spin_axis,
		"initial_cd": initial_air.drag_coefficient,
		"initial_cl": initial_air.lift_coefficient,
		"peak_cl": peak_cl,
		"launch_regime_key": regime_key,
		"matched_regime_override_key": matched_key,
		"flight_profile_name": fp.name,
	}


func _create_params(floor_normal: Vector3, surface: int, initial_launch_angle_deg: float,
		launch_speed_mph: float, launch_spin_rpm: float) -> PhysicsParams:
	var air_density := _aero.get_air_density(DEFAULT_ALT_FT, DEFAULT_TEMP_F, PhysicsEnums.Units.IMPERIAL)
	var air_viscosity := _aero.get_dynamic_viscosity(DEFAULT_TEMP_F, PhysicsEnums.Units.IMPERIAL)
	return _factory.create(air_density, air_viscosity, 1.0, 1.0, surface, floor_normal, 0.0,
		_ball_profile, initial_launch_angle_deg, launch_speed_mph, launch_spin_rpm)
