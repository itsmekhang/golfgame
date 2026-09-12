class_name BallPhysics
extends RefCounted
## GDScript port of OpenFairway `BallPhysics.cs`.
## Pure physics calculations for golf ball motion: forces, torques,
## fixed-step integration, and bounce (delegated to BounceCalculator).

# Ball physical properties
const MASS := 0.04592623  # kg (regulation golf ball)
const RADIUS := 0.021335  # m (regulation golf ball)
const CROSS_SECTION := PI * RADIUS * RADIUS  # m²
const MOMENT_OF_INERTIA := 0.4 * MASS * RADIUS * RADIUS  # kg*m²
const SIMULATION_HZ := 120.0  # shared integration rate for runtime + headless
const SIMULATION_DT := 1.0 / SIMULATION_HZ
const SPIN_DECAY_TAU := 5.0  # Spin decay time constant (seconds)

# Gravity force (pre-computed to avoid per-frame allocation)
const GRAVITY_FORCE := Vector3(0.0, -9.81 * MASS, 0.0)

# Read-only properties for parity with the C# API
var ball_mass: float:
	get:
		return MASS
var ball_radius: float:
	get:
		return RADIUS
var ball_cross_section: float:
	get:
		return CROSS_SECTION
var ball_moment_of_inertia: float:
	get:
		return MOMENT_OF_INERTIA
var simulation_hz: float:
	get:
		return SIMULATION_HZ
var simulation_dt: float:
	get:
		return SIMULATION_DT
var spin_decay_tau: float:
	get:
		return SPIN_DECAY_TAU

var _bounce_calc := BounceCalculator.new()
var _rollout: RolloutProfile = RolloutProfile.get_default()
var _bounce: BounceProfile = BounceProfile.get_default()


## Optional: supply ball-specific rollout/bounce profiles (see BallPhysicsProfile).
func set_profiles(rollout: RolloutProfile, bounce: BounceProfile) -> void:
	_rollout = rollout if rollout != null else RolloutProfile.get_default()
	_bounce = bounce if bounce != null else BounceProfile.get_default()


static func _floor_normal(parameters: PhysicsParams) -> Vector3:
	return parameters.floor_normal.normalized() if parameters.floor_normal.length_squared() > 0.000001 else Vector3.UP


## Calculate total forces acting on the ball.
func calculate_forces(velocity: Vector3, omega: Vector3, on_ground: bool, parameters: PhysicsParams) -> Vector3:
	var gravity := GRAVITY_FORCE
	if on_ground:
		# Normal force cancels gravity vertically while gravity still
		# contributes along the local slope tangent.
		var floor_normal := _floor_normal(parameters)
		var gravity_along_slope := gravity - floor_normal * gravity.dot(floor_normal)
		# Ground integration is handled in world-space with collision response.
		gravity_along_slope.y = 0.0

		var ground_forces := calculate_ground_forces(velocity, omega, parameters)
		ground_forces += gravity_along_slope
		ground_forces.y = 0.0
		return ground_forces
	else:
		return gravity + calculate_air_forces(velocity, omega, parameters)


## Calculate ground friction and grass drag forces.
func calculate_ground_forces(velocity: Vector3, omega: Vector3, parameters: PhysicsParams) -> Vector3:
	var grass_drag := velocity * (-6.0 * PI * RADIUS * parameters.grass_viscosity)
	grass_drag.y = 0.0

	var friction := _calculate_friction_force(velocity, omega, parameters, _rollout)

	# Debug: print roughly once per second when on ground
	if PhysicsLogger.get_level() >= PhysicsLogger.Level.VERBOSE and Engine.get_physics_frames() % 60 == 0:
		var floor_normal := _floor_normal(parameters)
		var spin_multiplier := _get_spin_friction_multiplier(omega, parameters.rollout_impact_spin, velocity.length(), _rollout)
		var contact_velocity := velocity + omega.cross(-floor_normal * RADIUS)
		var tangent_velocity := contact_velocity - floor_normal * contact_velocity.dot(floor_normal)
		var tangent_vel_mag := tangent_velocity.length()
		if tangent_vel_mag < _rollout.tangent_velocity_threshold:
			PhysicsLogger.verbose("  ROLLING: vel=%.2f m/s, spin=%.0f rpm, c_rr=%.3f (×%.2f)" % [velocity.length(), omega.length() / ShotSetup.RAD_PER_RPM, parameters.rolling_friction * spin_multiplier, spin_multiplier])
		else:
			PhysicsLogger.verbose("  SLIPPING: vel=%.2f m/s, spin=%.0f rpm, tangent_vel=%.2f" % [velocity.length(), omega.length() / ShotSetup.RAD_PER_RPM, tangent_vel_mag])

	return grass_drag + friction


## Calculate aerodynamic drag and Magnus forces.
func calculate_air_forces(velocity: Vector3, omega: Vector3, parameters: PhysicsParams) -> Vector3:
	var air_sample := FlightAerodynamicsModel.sample(velocity, omega, parameters.air_density,
		parameters.air_viscosity, parameters.drag_scale, parameters.lift_scale,
		parameters.initial_launch_angle_deg, parameters.flight_profile)
	if not air_sample.has_aerodynamics:
		return Vector3.ZERO

	# Drag force (opposite to velocity): Fd = -0.5 * Cd * rho * A * v * |v|
	var drag := -0.5 * air_sample.drag_coefficient * parameters.air_density * CROSS_SECTION * velocity * air_sample.speed

	# Magnus force: Fm = 0.5 * Cl * rho * A * (omega x v) * |v| / |omega|
	var magnus := Vector3.ZERO
	var omega_len := omega.length()
	if omega_len > 0.1:
		var omega_cross_vel := omega.cross(velocity)
		magnus = 0.5 * air_sample.lift_coefficient * parameters.air_density * CROSS_SECTION * omega_cross_vel * air_sample.speed / omega_len

	return drag + magnus


static func get_spin_drag_multiplier(spin_ratio: float, reynolds: float = -1.0) -> float:
	return FlightAerodynamicsModel.get_spin_drag_multiplier(spin_ratio, reynolds)


static func get_low_launch_lift_scale(initial_launch_angle_deg: float, spin_ratio: float, reynolds: float) -> float:
	return FlightAerodynamicsModel.get_low_launch_lift_scale(initial_launch_angle_deg, spin_ratio, reynolds)


static func sample_flight_aerodynamics(velocity: Vector3, omega: Vector3, air_density: float, air_viscosity: float,
		drag_scale: float, lift_scale: float, initial_launch_angle_deg: float,
		flight_profile: FlightProfile = null) -> FlightAerodynamicsModel.AeroSample:
	return FlightAerodynamicsModel.sample(velocity, omega, air_density, air_viscosity, drag_scale, lift_scale,
		initial_launch_angle_deg, flight_profile)


## Calculate total torques acting on the ball.
func calculate_torques(velocity: Vector3, omega: Vector3, on_ground: bool, parameters: PhysicsParams) -> Vector3:
	if on_ground:
		return calculate_ground_torques(velocity, omega, parameters)
	else:
		# Spin decay torque (exponential decay model)
		return -MOMENT_OF_INERTIA * omega / SPIN_DECAY_TAU


## Integrate velocity and spin one step with a fixed time step.
## Returns [velocity, omega] (GDScript has no ref parameters).
func integrate_step(velocity: Vector3, omega: Vector3, on_ground: bool, parameters: PhysicsParams, dt: float) -> Array:
	var force := calculate_forces(velocity, omega, on_ground, parameters)
	var torque := calculate_torques(velocity, omega, on_ground, parameters)
	velocity += (force / MASS) * dt
	omega += (torque / MOMENT_OF_INERTIA) * dt
	return [velocity, omega]


## Calculate ground friction torques.
func calculate_ground_torques(velocity: Vector3, omega: Vector3, parameters: PhysicsParams) -> Vector3:
	var grass_torque := -6.0 * PI * parameters.grass_viscosity * RADIUS * omega
	var friction_force := _calculate_friction_force(velocity, omega, parameters, _rollout)
	var friction_torque := Vector3.ZERO
	if friction_force.length() > 0.001:
		friction_torque = (-_floor_normal(parameters) * RADIUS).cross(friction_force)
	return friction_torque + grass_torque


func calculate_bounce(vel: Vector3, omega: Vector3, normal: Vector3, current_state: int,
		parameters: PhysicsParams, bp: BounceProfile = null) -> BounceResult:
	return _bounce_calc.calculate_bounce(vel, omega, normal, current_state, parameters, bp if bp != null else _bounce)


func get_coefficient_of_restitution(speed_normal: float, bp: BounceProfile = null) -> float:
	return _bounce_calc.get_coefficient_of_restitution(speed_normal, bp if bp != null else _bounce)


static func _get_spin_friction_multiplier(omega: Vector3, impact_spin_rpm: float, ball_speed: float, rp: RolloutProfile) -> float:
	var current_spin_rpm := omega.length() / ShotSetup.RAD_PER_RPM
	var effective_spin_rpm := maxf(current_spin_rpm, impact_spin_rpm)

	var velocity_scale: float
	if ball_speed < rp.chip_speed_threshold:
		velocity_scale = lerpf(rp.chip_velocity_scale_min, rp.chip_velocity_scale_max, ball_speed / rp.chip_speed_threshold)
	elif ball_speed < rp.pitch_speed_threshold:
		velocity_scale = lerpf(rp.chip_velocity_scale_max, 1.0,
			(ball_speed - rp.chip_speed_threshold) / (rp.pitch_speed_threshold - rp.chip_speed_threshold))
	else:
		velocity_scale = 1.0

	var spin_multiplier: float
	if effective_spin_rpm < rp.low_spin_threshold:
		spin_multiplier = 1.0 + (effective_spin_rpm / rp.low_spin_threshold) * (rp.low_spin_multiplier_max - 1.0)
	elif effective_spin_rpm < rp.mid_spin_threshold:
		var excess_spin := effective_spin_rpm - rp.low_spin_threshold
		var mid_range := rp.mid_spin_threshold - rp.low_spin_threshold
		spin_multiplier = rp.low_spin_multiplier_max + (excess_spin / mid_range) * (rp.mid_spin_multiplier_max - rp.low_spin_multiplier_max)
	else:
		var excess_spin := effective_spin_rpm - rp.mid_spin_threshold
		var spin_factor := minf(excess_spin / rp.high_spin_ramp_range, 1.0)
		spin_multiplier = rp.mid_spin_multiplier_max + spin_factor * (rp.high_spin_multiplier_max - rp.mid_spin_multiplier_max)

	return 1.0 + (spin_multiplier - 1.0) * velocity_scale


static func _calculate_friction_force(velocity: Vector3, omega: Vector3, parameters: PhysicsParams, rp: RolloutProfile) -> Vector3:
	var floor_normal := _floor_normal(parameters)
	var contact_velocity := velocity + omega.cross(-floor_normal * RADIUS)
	var tangent_velocity := contact_velocity - floor_normal * contact_velocity.dot(floor_normal)

	var spin_multiplier := _get_spin_friction_multiplier(omega, parameters.rollout_impact_spin, velocity.length(), rp)
	var tangent_vel_mag := tangent_velocity.length()

	if tangent_vel_mag < rp.tangent_velocity_threshold:
		# Pure rolling: rolling resistance opposes flat velocity
		var flat_velocity := velocity - floor_normal * velocity.dot(floor_normal)
		var friction_dir := flat_velocity.normalized() if flat_velocity.length() > 0.01 else Vector3.ZERO
		var effective_rolling_friction := parameters.rolling_friction * spin_multiplier
		return friction_dir * (-effective_rolling_friction * MASS * 9.81)
	else:
		# Slipping: kinetic friction opposes contact-point slip
		var velocity_mag := velocity.length()
		var base_friction: float
		if velocity_mag < rp.friction_blend_speed:
			var blend_factor := clampf(velocity_mag / rp.friction_blend_speed, 0.0, 1.0)
			blend_factor = blend_factor * blend_factor
			base_friction = lerpf(parameters.rolling_friction, parameters.kinetic_friction, blend_factor)
		else:
			base_friction = parameters.kinetic_friction

		var effective_friction := base_friction * spin_multiplier
		var slip_dir := tangent_velocity.normalized() if tangent_vel_mag > 0.01 else Vector3.ZERO
		return slip_dir * (-effective_friction * MASS * 9.81)
