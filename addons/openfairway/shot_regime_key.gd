class_name ShotRegimeKey
extends RefCounted
## GDScript port of OpenFairway `ShotRegimeKey.cs`.
## Shared launch-regime classifier: `<family>-<speed_bin>-<launch_bin>-<spin_bin>`.


static func build(speed_mph: float, launch_angle_deg: float, total_spin_rpm: float) -> String:
	return "%s-%s-%s-%s" % [get_family(speed_mph, launch_angle_deg), get_speed_bin(speed_mph),
		get_launch_bin(launch_angle_deg), get_spin_bin(total_spin_rpm)]


## Most-specific to least-specific lookup keys.
static func build_lookup_keys(speed_mph: float, launch_angle_deg: float, total_spin_rpm: float) -> Array[String]:
	var family := get_family(speed_mph, launch_angle_deg)
	var speed := get_speed_bin(speed_mph)
	var launch := get_launch_bin(launch_angle_deg)
	var spin := get_spin_bin(total_spin_rpm)
	return [
		"%s-%s-%s-%s" % [family, speed, launch, spin],
		"%s-%s-%s" % [family, speed, launch],
		"%s-%s" % [family, speed],
		family,
	]


static func get_family(speed_mph: float, launch_angle_deg: float) -> String:
	if speed_mph < 60.0:
		return "C"
	if speed_mph > 110.0 and launch_angle_deg < 18.0:
		return "D"
	if launch_angle_deg > 30.0:
		return "W"
	return "I"


static func get_speed_bin(speed_mph: float) -> String:
	if speed_mph < 60.0:
		return "S0"
	if speed_mph < 72.0:
		return "S1a"
	if speed_mph < 85.0:
		return "S1b"
	if speed_mph < 105.0:
		return "S2"
	if speed_mph < 120.0:
		return "S3"
	return "S4"


static func get_launch_bin(launch_angle_deg: float) -> String:
	if launch_angle_deg < 10.0:
		return "V0"
	if launch_angle_deg < 18.0:
		return "V1"
	if launch_angle_deg < 25.0:
		return "V2"
	if launch_angle_deg < 33.0:
		return "V3"
	return "V4"


static func get_spin_bin(total_spin_rpm: float) -> String:
	if total_spin_rpm < 2500.0:
		return "P0"
	if total_spin_rpm < 4000.0:
		return "P1"
	if total_spin_rpm < 5500.0:
		return "P2"
	if total_spin_rpm < 7500.0:
		return "P3"
	return "P4"
