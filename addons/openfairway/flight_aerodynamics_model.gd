class_name FlightAerodynamicsModel
extends RefCounted
## GDScript port of OpenFairway `FlightAerodynamicsModel.cs`.
## Shared flight-coefficient sampling path (spin ratio, Reynolds number,
## drag multiplier, lift recovery, Cd, Cl) used by BallPhysics and PhysicsAdapter.

const MIN_AERODYNAMIC_SPEED := 0.5

## Result of one aerodynamic sample (mirrors `FlightAerodynamicsSample`).
class AeroSample:
	extends RefCounted
	var speed: float = 0.0
	var spin_ratio: float = 0.0
	var reynolds: float = 0.0
	var spin_drag_multiplier: float = 1.0
	var low_launch_lift_scale: float = 1.0
	var drag_coefficient: float = 0.0
	var lift_coefficient: float = 0.0

	var has_aerodynamics: bool:
		get:
			return speed >= FlightAerodynamicsModel.MIN_AERODYNAMIC_SPEED

	func _init(p_speed: float = 0.0, p_spin_ratio: float = 0.0, p_reynolds: float = 0.0,
			p_spin_drag_multiplier: float = 1.0, p_low_launch_lift_scale: float = 1.0,
			p_drag_coefficient: float = 0.0, p_lift_coefficient: float = 0.0) -> void:
		speed = p_speed
		spin_ratio = p_spin_ratio
		reynolds = p_reynolds
		spin_drag_multiplier = p_spin_drag_multiplier
		low_launch_lift_scale = p_low_launch_lift_scale
		drag_coefficient = p_drag_coefficient
		lift_coefficient = p_lift_coefficient


static func _p(profile: FlightProfile) -> FlightProfile:
	return profile if profile != null else FlightProfile.get_default()


static func sample(velocity: Vector3, omega: Vector3, air_density: float, air_viscosity: float,
		drag_scale: float, lift_scale: float, initial_launch_angle_deg: float,
		profile: FlightProfile = null) -> AeroSample:
	var p := _p(profile)
	var speed := velocity.length()
	if speed < MIN_AERODYNAMIC_SPEED:
		return AeroSample.new(0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0)

	var spin_ratio := omega.length() * BallPhysics.RADIUS / speed
	var reynolds := air_density * speed * BallPhysics.RADIUS * 2.0 / air_viscosity
	var spin_drag_multiplier := get_spin_drag_multiplier(spin_ratio, reynolds, p)
	var low_launch_lift_scale := get_low_launch_lift_scale(initial_launch_angle_deg, spin_ratio, reynolds, p)
	var high_launch_drag_scale := get_high_launch_drag_scale(initial_launch_angle_deg, spin_ratio, p)
	var drag_coefficient := get_cd(reynolds, p) * spin_drag_multiplier * drag_scale * high_launch_drag_scale
	var lift_coefficient := get_cl(reynolds, spin_ratio, p) * lift_scale * low_launch_lift_scale
	lift_coefficient *= get_mid_spin_cl_boost(spin_ratio, p)

	return AeroSample.new(speed, spin_ratio, reynolds, spin_drag_multiplier,
		low_launch_lift_scale, drag_coefficient, lift_coefficient)


static func get_cd(reynolds: float, profile: FlightProfile = null) -> float:
	var p := _p(profile)
	if reynolds > 200000.0:
		return p.high_re_cd_cap

	if reynolds >= 50000.0:
		return p.cd_poly_a + p.cd_poly_b * reynolds + \
			p.cd_poly_c * reynolds * reynolds + \
			p.cd_poly_d * reynolds * reynolds * reynolds

	if reynolds <= p.low_re_blend_start:
		return p.low_re_cd_floor

	var t := safe_smooth_step01(reynolds, p.low_re_blend_start, 50000.0)
	return lerpf(p.low_re_cd_floor, p.cd_at50k, t)


static func get_cl(reynolds: float, spin_ratio: float, profile: FlightProfile = null) -> float:
	var p := _p(profile)
	var spin := maxf(0.0, spin_ratio)
	if spin <= 0.0:
		return 0.0

	var dynamic_cl_max := get_cl_max(spin, p)

	if reynolds < 50000.0:
		if reynolds <= 30000.0:
			return 0.0
		var low_re_t := smooth_step01((reynolds - 30000.0) / 20000.0)
		var cl_at_50k := clampf(_cl_re50k(spin), 0.0, dynamic_cl_max)
		var cl_before_atten := cl_at_50k * low_re_t
		return _apply_low_re_high_spin_lift_attenuation(spin, cl_before_atten, p)

	if reynolds >= p.high_re_start:
		return _apply_high_spin_lift_attenuation(spin, clampf(_cl_high_re(spin, p), 0.0, dynamic_cl_max), p)

	var re_values := [50000, 60000, 65000, 70000, 75000]
	var re_high_index := re_values.size() - 1
	for i in range(re_values.size()):
		if reynolds <= re_values[i]:
			re_high_index = i
			break

	var re_low_index: int = maxi(re_high_index - 1, 0)

	var cl_low := maxf(0.0, _cl_at_reynolds_index(re_low_index, spin, p))
	var cl_high := maxf(0.0, _cl_at_reynolds_index(re_high_index, spin, p))
	var re_low: float = re_values[re_low_index]
	var re_high: float = re_values[re_high_index]
	var weight := (reynolds - re_low) / (re_high - re_low) if re_high != re_low else 0.0

	var cl_interpolated := lerpf(cl_low, cl_high, weight)
	var cl_clamped := clampf(cl_interpolated, 0.0, dynamic_cl_max)

	return _apply_low_re_high_spin_lift_attenuation(spin, cl_clamped, p)


static func get_spin_drag_multiplier(spin_ratio: float, reynolds: float = -1.0, profile: FlightProfile = null) -> float:
	var p := _p(profile)
	if reynolds < 0.0:
		reynolds = p.high_spin_drag_relief_re_full_max
	if spin_ratio <= 0.0:
		return 1.0

	var high_spin_weight := safe_smooth_step01(spin_ratio, p.high_spin_drag_sr_start, p.high_spin_drag_sr_end)
	var re_relief_weight := 1.0 - safe_smooth_step01(reynolds, p.high_spin_drag_relief_re_full_max, p.high_spin_drag_relief_re_zero)
	var relief_weight := high_spin_weight * re_relief_weight
	var effective_cap := lerpf(p.spin_drag_multiplier_max, p.spin_drag_multiplier_high_spin_max, relief_weight)

	var progressive_boost := p.spin_drag_progressive_cap_boost_max \
		* safe_smooth_step01(spin_ratio, p.spin_drag_progressive_cap_sr_start, p.spin_drag_progressive_cap_sr_end)
	effective_cap += progressive_boost

	var ultra_high_spin_weight := safe_smooth_step01(spin_ratio, p.ultra_high_spin_drag_sr_start, p.ultra_high_spin_drag_sr_end)
	effective_cap = lerpf(effective_cap, p.spin_drag_multiplier_ultra_high_spin_max, ultra_high_spin_weight)

	var spin_drag_multiplier := 1.0 + p.spin_drag_multiplier_coeff * spin_ratio * spin_ratio
	return minf(spin_drag_multiplier, effective_cap)


static func get_low_launch_lift_scale(initial_launch_angle_deg: float, spin_ratio: float, reynolds: float, profile: FlightProfile = null) -> float:
	var p := _p(profile)
	var launch_factor := safe_smooth_step01(p.low_launch_vla_zero_deg - initial_launch_angle_deg, 0.0, p.low_launch_vla_zero_deg - p.low_launch_vla_full_deg)
	if launch_factor <= 0.0:
		return 1.0

	var re_factor := safe_smooth_step01(reynolds, p.low_launch_re_start, p.low_launch_re_end)
	if re_factor <= 0.0:
		return 1.0

	var spin_factor := 1.0 - safe_smooth_step01(spin_ratio, p.low_launch_spin_ratio_full, p.low_launch_spin_ratio_max)
	if spin_factor <= 0.0:
		return 1.0

	var recovery_weight := launch_factor * re_factor * spin_factor
	return lerpf(1.0, p.low_launch_lift_recovery_max, recovery_weight)


static func get_high_launch_drag_scale(initial_launch_angle_deg: float, spin_ratio: float, profile: FlightProfile = null) -> float:
	var p := _p(profile)
	var launch_factor := safe_smooth_step01(initial_launch_angle_deg, p.high_launch_drag_vla_start_deg, p.high_launch_drag_vla_full_deg)
	if launch_factor <= 0.0:
		return 1.0

	var spin_factor := safe_smooth_step01(spin_ratio, p.high_launch_drag_sr_start, p.high_launch_drag_sr_end)
	if spin_factor <= 0.0:
		return 1.0

	var boost_weight := launch_factor * spin_factor
	return lerpf(1.0, p.high_launch_drag_boost_max, boost_weight)


static func get_mid_spin_cl_boost(spin_ratio: float, profile: FlightProfile = null) -> float:
	var p := _p(profile)
	if p.mid_spin_cl_boost_max <= 0.0:
		return 1.0
	var t := safe_smooth_step01(spin_ratio, p.mid_spin_cl_boost_sr_start, p.mid_spin_cl_boost_sr_end)
	var bell := t * (1.0 - t) * 4.0
	return 1.0 + p.mid_spin_cl_boost_max * bell


static func get_cl_max(spin_ratio: float, profile: FlightProfile = null) -> float:
	var p := _p(profile)
	if spin_ratio <= p.cl_max_sr_transition_start:
		return p.cl_max_base
	elif spin_ratio >= p.cl_max_sr_transition_end:
		return p.cl_max_high_spin
	else:
		var t := safe_smooth_step01(spin_ratio, p.cl_max_sr_transition_start, p.cl_max_sr_transition_end)
		return lerpf(p.cl_max_base, p.cl_max_high_spin, t)


static func _cl_at_reynolds_index(index: int, spin_ratio: float, p: FlightProfile) -> float:
	match index:
		0:
			return _cl_re50k(spin_ratio)
		1:
			return _cl_re60k(spin_ratio)
		2:
			return _cl_re65k(spin_ratio)
		3:
			return _cl_re70k(spin_ratio)
		_:
			return _cl_high_re(spin_ratio, p)


# Cl polynomial curves — hardcoded (not part of the profile), same as C#.
static func _cl_re50k(spin_ratio: float) -> float:
	return 0.0472121 + 2.84795 * spin_ratio - 23.4342 * spin_ratio * spin_ratio + \
		45.4849 * spin_ratio * spin_ratio * spin_ratio


static func _cl_re60k(spin_ratio: float) -> float:
	return 0.320524 - 4.7032 * spin_ratio + 14.0613 * spin_ratio * spin_ratio


static func _cl_re65k(spin_ratio: float) -> float:
	return 0.266667 - 4.0 * spin_ratio + 13.3333 * spin_ratio * spin_ratio


static func _cl_re70k(spin_ratio: float) -> float:
	return 0.0496189 + 0.00211396 * spin_ratio + 2.34201 * spin_ratio * spin_ratio


static func _cl_high_re(spin_ratio: float, p: FlightProfile) -> float:
	var effective_gain := _get_high_re_spin_gain(spin_ratio, p)
	var dynamic_cl_max := get_cl_max(spin_ratio, p)
	return dynamic_cl_max * spin_ratio * effective_gain / (1.0 + spin_ratio * effective_gain)


static func _apply_high_spin_lift_attenuation(spin_ratio: float, cl: float, p: FlightProfile) -> float:
	var attenuation_t := safe_smooth_step01(spin_ratio, p.high_spin_cl_attenuation_start, p.high_spin_cl_attenuation_end)
	var attenuation := 1.0 - p.high_spin_cl_attenuation_max * attenuation_t

	var ultra_t := safe_smooth_step01(spin_ratio, p.ultra_high_spin_cl_attenuation_start, p.ultra_high_spin_cl_attenuation_end)
	var ultra_attenuation := 1.0 - p.ultra_high_spin_cl_attenuation_max * ultra_t

	return cl * attenuation * ultra_attenuation


static func _apply_low_re_high_spin_lift_attenuation(spin_ratio: float, cl: float, p: FlightProfile) -> float:
	var attenuation_t := safe_smooth_step01(spin_ratio, p.high_spin_cl_attenuation_start, p.high_spin_cl_attenuation_end)
	var attenuation := 1.0 - p.low_re_high_spin_cl_attenuation_max * attenuation_t

	var ultra_t := safe_smooth_step01(spin_ratio, p.ultra_high_spin_cl_attenuation_start, p.ultra_high_spin_cl_attenuation_end)
	var ultra_attenuation := 1.0 - p.low_re_ultra_high_spin_cl_attenuation_max * ultra_t

	return cl * attenuation * ultra_attenuation


static func _get_high_re_spin_gain(spin_ratio: float, p: FlightProfile) -> float:
	if spin_ratio <= p.high_re_gain_reduction_start:
		return p.high_re_spin_gain

	if spin_ratio < p.high_re_gain_reduction_end:
		var reduction_t := safe_smooth_step01(spin_ratio, p.high_re_gain_reduction_start, p.high_re_gain_reduction_end)
		return lerpf(p.high_re_spin_gain, p.high_re_mid_spin_gain, reduction_t)

	if spin_ratio <= p.high_re_gain_recovery_start:
		return p.high_re_mid_spin_gain

	if spin_ratio < p.high_re_gain_recovery_end:
		var recovery_t := safe_smooth_step01(spin_ratio, p.high_re_gain_recovery_start, p.high_re_gain_recovery_end)
		return lerpf(p.high_re_mid_spin_gain, p.high_re_spin_gain, recovery_t)

	return p.high_re_spin_gain


static func smooth_step01(t: float) -> float:
	var clamped_t := clampf(t, 0.0, 1.0)
	return clamped_t * clamped_t * (3.0 - 2.0 * clamped_t)


## SmoothStep with safe division: when (end - start) is near zero,
## returns 1 if value >= end, else 0.
static func safe_smooth_step01(value: float, start: float, end: float) -> float:
	var range_v := end - start
	if absf(range_v) < 1e-6:
		return 1.0 if value >= end else 0.0
	return smooth_step01((value - start) / range_v)
