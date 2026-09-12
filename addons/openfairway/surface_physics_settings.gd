class_name SurfacePhysicsSettings
extends RefCounted
## GDScript port of OpenFairway `SurfacePhysicsSettings.cs`.
## Typed surface tuning values used to build physics parameters.

var surface_type: int = PhysicsEnums.SurfaceType.FAIRWAY
var kinetic_friction: float = 0.0
var rolling_friction: float = 0.0
var grass_viscosity: float = 0.0
var critical_angle: float = 0.0
var spinback_response_scale: float = 1.0
var spinback_theta_boost_max: float = 0.0
var spinback_spin_start_rpm: float = 0.0
var spinback_spin_end_rpm: float = 0.0
var spinback_speed_start_mps: float = 0.0
var spinback_speed_end_mps: float = 0.0


func _init(p_surface_type: int = PhysicsEnums.SurfaceType.FAIRWAY, p_kinetic_friction: float = 0.0,
		p_rolling_friction: float = 0.0, p_grass_viscosity: float = 0.0, p_critical_angle: float = 0.0,
		p_spinback_response_scale: float = 1.0, p_spinback_theta_boost_max: float = 0.0,
		p_spinback_spin_start_rpm: float = 0.0, p_spinback_spin_end_rpm: float = 0.0,
		p_spinback_speed_start_mps: float = 0.0, p_spinback_speed_end_mps: float = 0.0) -> void:
	surface_type = p_surface_type
	kinetic_friction = p_kinetic_friction
	rolling_friction = p_rolling_friction
	grass_viscosity = p_grass_viscosity
	critical_angle = p_critical_angle
	spinback_response_scale = p_spinback_response_scale
	spinback_theta_boost_max = p_spinback_theta_boost_max
	spinback_spin_start_rpm = p_spinback_spin_start_rpm
	spinback_spin_end_rpm = p_spinback_spin_end_rpm
	spinback_speed_start_mps = p_spinback_speed_start_mps
	spinback_speed_end_mps = p_spinback_speed_end_mps


func to_dictionary() -> Dictionary:
	return {
		"u_k": kinetic_friction,
		"u_kr": rolling_friction,
		"nu_g": grass_viscosity,
		"theta_c": critical_angle,
		"spinback_response_scale": spinback_response_scale,
		"spinback_theta_boost_max": spinback_theta_boost_max,
		"spinback_spin_start_rpm": spinback_spin_start_rpm,
		"spinback_spin_end_rpm": spinback_spin_end_rpm,
		"spinback_speed_start_mps": spinback_speed_start_mps,
		"spinback_speed_end_mps": spinback_speed_end_mps,
	}
