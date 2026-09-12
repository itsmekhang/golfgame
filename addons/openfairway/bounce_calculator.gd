class_name BounceCalculator
extends RefCounted
## GDScript port of OpenFairway `BounceCalculator.cs`.
## Impact bounce resolution, coefficient of restitution, and critical angle computation.


## Calculate bounce physics when the ball impacts a surface.
## `bp` is optional; when omitted the default BounceProfile is used (matches the
## non-profile C# overload, whose constants equal the default profile).
func calculate_bounce(vel: Vector3, omega: Vector3, normal: Vector3, current_state: int,
		parameters: PhysicsParams, bp: BounceProfile = null) -> BounceResult:
	if bp == null:
		bp = BounceProfile.get_default()

	var new_state: int = PhysicsEnums.BallState.ROLLOUT if current_state == PhysicsEnums.BallState.FLIGHT else current_state

	# Decompose velocity
	var vel_normal := vel.project(normal)
	var speed_normal := vel_normal.length()
	var vel_tangent := vel - vel_normal
	var speed_tangent := vel_tangent.length()

	# Decompose angular velocity
	var omega_normal := omega.project(normal)
	var omega_tangent := omega - omega_normal

	# Impact angle measured from the SURFACE (Penner's critical angle convention)
	var angle_to_normal := vel.angle_to(normal)
	var impact_angle := absf(angle_to_normal - PI / 2.0)

	var omega_tangent_magnitude := omega_tangent.length()
	var current_spin_rpm := omega.length() / ShotSetup.RAD_PER_RPM

	var tangential_retention: float
	if current_state == PhysicsEnums.BallState.FLIGHT:
		var spin_factor := clampf(1.0 - (current_spin_rpm / bp.flight_spin_factor_divisor), bp.flight_spin_factor_min, 1.0)
		tangential_retention = bp.flight_tangential_retention_base * spin_factor
	else:
		var ball_speed := vel.length()
		var spin_ratio := (omega.length() * BallPhysics.RADIUS) / ball_speed if ball_speed > 0.1 else 0.0
		if spin_ratio < bp.rollout_spin_ratio_threshold:
			tangential_retention = lerpf(bp.rollout_low_spin_retention, bp.rollout_high_spin_retention, spin_ratio / bp.rollout_spin_ratio_threshold)
		else:
			tangential_retention = bp.rollout_high_spin_retention

	if new_state == PhysicsEnums.BallState.ROLLOUT:
		PhysicsLogger.verbose("  Bounce: spin=%.0f rpm, retention=%.3f" % [current_spin_rpm, tangential_retention])

	var new_tangent_speed: float
	if current_state == PhysicsEnums.BallState.FLIGHT:
		var impact_speed := vel.length()
		var has_spinback_surface := parameters.spinback_theta_boost_max > 0.0 or parameters.spinback_response_scale > 1.0
		var effective_critical_angle := get_effective_critical_angle(parameters, current_spin_rpm, impact_speed, current_state)
		var impact_angle_deg := rad_to_deg(impact_angle)
		var critical_angle_deg := rad_to_deg(effective_critical_angle)
		var is_steep_impact := impact_angle >= effective_critical_angle

		# High backspin (>4000 RPM) indicates a wedge/flop, not a chip — lower the energy guard.
		var penner_speed_threshold := bp.penner_low_energy_threshold
		if current_spin_rpm > 4000.0:
			var spin_t := clampf((current_spin_rpm - 4000.0) / 4000.0, 0.0, 1.0)
			penner_speed_threshold = lerpf(bp.penner_low_energy_threshold, 12.0, spin_t)
		var should_use_penner := is_steep_impact and (impact_speed >= penner_speed_threshold or has_spinback_surface)

		if not should_use_penner:
			new_tangent_speed = speed_tangent * tangential_retention
			if not is_steep_impact:
				PhysicsLogger.verbose("  Bounce: Shallow angle (%.2f° < %.2f°) - using simple retention" % [impact_angle_deg, critical_angle_deg])
			elif impact_speed < penner_speed_threshold and not has_spinback_surface:
				PhysicsLogger.verbose("  Bounce: Low energy (%.2f m/s < %.2f m/s) - using simple retention" % [impact_speed, penner_speed_threshold])
			else:
				PhysicsLogger.verbose("  Bounce: Using simple retention (surface=%s, speed=%.2f m/s)" % [SurfacePhysicsCatalog.surface_name(parameters.surface_type), impact_speed])
			PhysicsLogger.verbose("    speedTangent=%.2f m/s, newTangentSpeed=%.2f m/s" % [speed_tangent, new_tangent_speed])
		else:
			# Penner tangential model for steep impacts: backspin term can reverse tangential velocity.
			var spinback_term := 2.0 * BallPhysics.RADIUS * omega_tangent_magnitude * maxf(parameters.spinback_response_scale, 0.0) / 7.0
			new_tangent_speed = tangential_retention * vel.length() * sin(impact_angle - effective_critical_angle) - spinback_term
			PhysicsLogger.verbose("  Bounce: Penner model (%s) speed=%.2f m/s angle=%.2f° crit=%.2f°" % [SurfacePhysicsCatalog.surface_name(parameters.surface_type), impact_speed, impact_angle_deg, critical_angle_deg])
			PhysicsLogger.verbose("    speedTangent=%.2f m/s, spinbackScale=%.2f, newTangentSpeed=%.2f m/s" % [speed_tangent, parameters.spinback_response_scale, new_tangent_speed])
	else:
		# Subsequent bounces during rollout: simple friction factor
		new_tangent_speed = speed_tangent * tangential_retention

	if speed_tangent < 0.01 and absf(new_tangent_speed) < 0.01:
		vel_tangent = Vector3.ZERO
	elif new_tangent_speed < 0.0:
		# Spin-back: reverse tangential direction
		vel_tangent = -vel_tangent.normalized() * absf(new_tangent_speed)
	else:
		vel_tangent = vel_tangent.limit_length(new_tangent_speed)

	# Update tangential angular velocity
	if current_state == PhysicsEnums.BallState.FLIGHT:
		var new_omega_tangent := absf(new_tangent_speed) / BallPhysics.RADIUS
		if omega_tangent.length() < 0.1 or new_omega_tangent < 0.01:
			omega_tangent = Vector3.ZERO
		elif new_tangent_speed < 0.0:
			omega_tangent = -omega_tangent.normalized() * new_omega_tangent
		else:
			omega_tangent = omega_tangent.limit_length(new_omega_tangent)
	else:
		# Rollout: preserve existing spin magnitude, align toward rolling direction
		if new_tangent_speed > 0.05:
			var existing_spin_mag := omega_tangent.length()
			var tangent_dir := vel_tangent.normalized() if vel_tangent.length() > 0.01 else Vector3.RIGHT
			var rolling_axis := normal.cross(tangent_dir).normalized()
			if existing_spin_mag > 0.05:
				omega_tangent = rolling_axis * existing_spin_mag
			else:
				omega_tangent = Vector3.ZERO
		else:
			omega_tangent = Vector3.ZERO

	# Coefficient of restitution (speed-dependent and spin-dependent)
	var cor: float
	if current_state == PhysicsEnums.BallState.FLIGHT:
		var base_cor := get_coefficient_of_restitution(speed_normal, bp)
		var spin_rpm := omega.length() / ShotSetup.RAD_PER_RPM

		var cor_velocity_scale: float
		if speed_normal < bp.cor_velocity_low_threshold:
			cor_velocity_scale = lerpf(0.0, bp.cor_velocity_low_scale, speed_normal / bp.cor_velocity_low_threshold)
		elif speed_normal < bp.cor_velocity_mid_threshold:
			cor_velocity_scale = lerpf(bp.cor_velocity_low_scale, 1.0, (speed_normal - bp.cor_velocity_low_threshold) / (bp.cor_velocity_mid_threshold - bp.cor_velocity_low_threshold))
		else:
			cor_velocity_scale = 1.0

		var spin_cor_reduction: float
		if spin_rpm < bp.spin_cor_low_spin_threshold:
			spin_cor_reduction = (spin_rpm / bp.spin_cor_low_spin_threshold) * bp.spin_cor_low_spin_max_reduction
		else:
			var excess_spin := spin_rpm - bp.spin_cor_low_spin_threshold
			var spin_factor := minf(excess_spin / bp.spin_cor_high_spin_range_rpm, 1.0)
			var max_reduction := bp.spin_cor_low_spin_max_reduction + spin_factor * bp.spin_cor_high_spin_additional_reduction
			spin_cor_reduction = max_reduction * cor_velocity_scale

		cor = base_cor * (1.0 - spin_cor_reduction)

		if new_state == PhysicsEnums.BallState.ROLLOUT:
			PhysicsLogger.verbose("    speedNormal=%.2f m/s, spin=%.0f rpm" % [speed_normal, spin_rpm])
			PhysicsLogger.verbose("    baseCOR=%.3f, spinReduction=%.2f, finalCOR=%.3f" % [base_cor, spin_cor_reduction, cor])
			PhysicsLogger.verbose("    velNormal will be %.2f m/s" % [speed_normal * cor])
	else:
		# Rollout bounces: kill small bounces aggressively to settle into roll
		if speed_normal < bp.rollout_bounce_cor_kill_threshold:
			cor = 0.0
		else:
			cor = get_coefficient_of_restitution(speed_normal, bp) * bp.rollout_bounce_cor_scale
		if speed_normal > 0.5:
			PhysicsLogger.verbose("    speedNormal=%.2f m/s, COR=%.3f, velNormal will be %.2f m/s" % [speed_normal, cor, speed_normal * cor])

	vel_normal = vel_normal * -cor

	var new_omega := omega_normal + omega_tangent
	var new_velocity := vel_normal + vel_tangent

	return BounceResult.new(new_velocity, new_omega, new_state)


## Coefficient of restitution based on normal impact speed.
func get_coefficient_of_restitution(speed_normal: float, bp: BounceProfile = null) -> float:
	if bp == null:
		bp = BounceProfile.get_default()
	if speed_normal > bp.cor_high_speed_threshold:
		return bp.cor_high_speed_cap
	elif speed_normal < bp.cor_kill_threshold:
		return 0.0
	else:
		return bp.cor_base_a + bp.cor_base_b * speed_normal + bp.cor_base_c * speed_normal * speed_normal


## Greens exhibit stronger check/spinback on steep, high-spin impacts.
## Modelled as an effective increase in critical angle.
static func get_effective_critical_angle(parameters: PhysicsParams, current_spin_rpm: float,
		impact_speed: float, current_state: int) -> float:
	if current_state != PhysicsEnums.BallState.FLIGHT or parameters.spinback_theta_boost_max <= 0.0:
		return parameters.critical_angle

	var spin_range := parameters.spinback_spin_end_rpm - parameters.spinback_spin_start_rpm
	var spin_t := clampf((current_spin_rpm - parameters.spinback_spin_start_rpm) / spin_range, 0.0, 1.0) if spin_range > 0.0 else 0.0
	spin_t = spin_t * spin_t * (3.0 - 2.0 * spin_t)

	var speed_range := parameters.spinback_speed_end_mps - parameters.spinback_speed_start_mps
	var speed_t := clampf((impact_speed - parameters.spinback_speed_start_mps) / speed_range, 0.0, 1.0) if speed_range > 0.0 else 0.0
	speed_t = speed_t * speed_t * (3.0 - 2.0 * speed_t)

	var boost := parameters.spinback_theta_boost_max * spin_t * speed_t
	return parameters.critical_angle + boost
