class_name ShotSetup
extends RefCounted
## GDScript port of OpenFairway `ShotSetup.cs`.
## Shared utilities for parsing launch monitor spin data and building
## initial physics vectors from shot parameters.

const MPS_PER_MPH := 0.44704
const RAD_PER_RPM := 0.10472
const YARDS_PER_METER := 1.09361
const FEET_PER_METER := 3.28084


## Normalize spin data from various launch-monitor input formats.
## Accepts any combination of BackSpin/SideSpin and TotalSpin/SpinAxis.
## Returns { "backspin", "sidespin", "total", "axis" } (RPM / degrees).
func parse_spin(data: Dictionary, emit_consistency_warnings: bool = true) -> Dictionary:
	var has_backspin := data.has("BackSpin")
	var has_sidespin := data.has("SideSpin")
	var has_total := data.has("TotalSpin")
	var has_axis := data.has("SpinAxis")

	var backspin: float = float(data.get("BackSpin", 0.0))
	var sidespin: float = float(data.get("SideSpin", 0.0))
	var total_spin: float = float(data.get("TotalSpin", 0.0))
	var spin_axis: float = float(data.get("SpinAxis", 0.0))

	# Derive total from components
	if total_spin == 0.0 and (has_backspin or has_sidespin):
		total_spin = sqrt(backspin * backspin + sidespin * sidespin)

	# Derive axis from components
	if not has_axis and (has_backspin or has_sidespin):
		spin_axis = rad_to_deg(atan2(sidespin, backspin))

	# Derive components from total + axis
	if has_total and has_axis:
		if not has_backspin:
			backspin = total_spin * cos(deg_to_rad(spin_axis))
		if not has_sidespin:
			sidespin = total_spin * sin(deg_to_rad(spin_axis))

	# Validate consistency: components are ground truth
	if has_backspin and has_sidespin and has_total:
		var computed_total := sqrt(backspin * backspin + sidespin * sidespin)
		if absf(computed_total - total_spin) > 1.0:
			if emit_consistency_warnings:
				PhysicsLogger.info("  Spin data inconsistent: TotalSpin=%.0f but sqrt(BS²+SS²)=%.0f, using computed value" % [total_spin, computed_total])
			total_spin = computed_total
			spin_axis = rad_to_deg(atan2(sidespin, backspin))

	return {
		"backspin": backspin,
		"sidespin": sidespin,
		"total": total_spin,
		"axis": spin_axis,
	}


## Convert launch monitor data (mph, degrees, RPM) to physics vectors (m/s, rad/s).
## Returns { "velocity": Vector3, "omega": Vector3, "shot_direction": Vector3 }.
func build_launch_vectors(speed_mph: float, vla_deg: float, hla_deg: float,
		total_spin_rpm: float, spin_axis_deg: float) -> Dictionary:
	var backspin_rpm := total_spin_rpm * cos(deg_to_rad(spin_axis_deg))
	var sidespin_rpm := total_spin_rpm * sin(deg_to_rad(spin_axis_deg))
	return build_launch_vectors_from_components(speed_mph, vla_deg, hla_deg, backspin_rpm, sidespin_rpm)


## Build launch vectors from measured backspin and sidespin components.
## Shot travels along +X at HLA 0; positive HLA turns the shot toward -Z.
func build_launch_vectors_from_components(speed_mph: float, vla_deg: float, hla_deg: float,
		backspin_rpm: float, sidespin_rpm: float) -> Dictionary:
	var speed_mps := speed_mph * MPS_PER_MPH

	var velocity := Vector3(speed_mps, 0.0, 0.0) \
		.rotated(Vector3.FORWARD, deg_to_rad(-vla_deg)) \
		.rotated(Vector3.UP, deg_to_rad(-hla_deg))

	var omega := Vector3(0.0, -sidespin_rpm * RAD_PER_RPM, backspin_rpm * RAD_PER_RPM) \
		.rotated(Vector3.UP, deg_to_rad(-hla_deg))

	var flat_velocity := Vector3(velocity.x, 0.0, velocity.z)
	var shot_direction := flat_velocity.normalized() if flat_velocity.length() > 0.001 else Vector3.RIGHT

	return {
		"velocity": velocity,
		"omega": omega,
		"shot_direction": shot_direction,
	}
