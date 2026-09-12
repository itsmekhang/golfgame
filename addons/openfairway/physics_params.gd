class_name PhysicsParams
extends Resource
## GDScript port of OpenFairway `PhysicsParams.cs`.
## Runtime parameter resource passed to BallPhysics.

@export var air_density: float = 0.0
@export var air_viscosity: float = 0.0
@export var drag_scale: float = 0.0
@export var lift_scale: float = 0.0
@export var kinetic_friction: float = 0.0
@export var rolling_friction: float = 0.0
@export var grass_viscosity: float = 0.0
@export var critical_angle: float = 0.0
@export var surface_type: PhysicsEnums.SurfaceType = PhysicsEnums.SurfaceType.FAIRWAY
## Surface/Floor normal at the ball's ground contact point.
## Expected to be a unit vector; zero-length is treated as Vector3.UP.
@export var floor_normal: Vector3 = Vector3.ZERO
## Spin RPM when the ball first landed, used by the rollout friction model.
@export var rollout_impact_spin: float = 0.0
@export var spinback_response_scale: float = 1.0
# Spinback parameters — non-zero values enable check/spin-back on steep high-spin impacts.
@export var spinback_theta_boost_max: float = 0.0
@export var spinback_spin_start_rpm: float = 0.0
@export var spinback_spin_end_rpm: float = 0.0
@export var spinback_speed_start_mps: float = 0.0
@export var spinback_speed_end_mps: float = 0.0
@export var initial_launch_angle_deg: float = 0.0

var flight_profile: FlightProfile = null:
	get:
		return flight_profile if flight_profile != null else FlightProfile.get_default()


static func create(p_air_density: float, p_air_viscosity: float, p_drag_scale: float, p_lift_scale: float,
		p_kinetic_friction: float, p_rolling_friction: float, p_grass_viscosity: float, p_critical_angle: float,
		p_surface_type: int, p_floor_normal: Vector3, p_rollout_impact_spin: float = 0.0,
		p_spinback_response_scale: float = 1.0, p_spinback_theta_boost_max: float = 0.0,
		p_spinback_spin_start_rpm: float = 0.0, p_spinback_spin_end_rpm: float = 0.0,
		p_spinback_speed_start_mps: float = 0.0, p_spinback_speed_end_mps: float = 0.0,
		p_initial_launch_angle_deg: float = 0.0, p_flight_profile: FlightProfile = null) -> PhysicsParams:
	var p := PhysicsParams.new()
	p.air_density = p_air_density
	p.air_viscosity = p_air_viscosity
	p.drag_scale = p_drag_scale
	p.lift_scale = p_lift_scale
	p.kinetic_friction = p_kinetic_friction
	p.rolling_friction = p_rolling_friction
	p.grass_viscosity = p_grass_viscosity
	p.critical_angle = p_critical_angle
	p.surface_type = p_surface_type as PhysicsEnums.SurfaceType
	p.floor_normal = p_floor_normal
	p.rollout_impact_spin = p_rollout_impact_spin
	p.spinback_response_scale = p_spinback_response_scale
	p.spinback_theta_boost_max = p_spinback_theta_boost_max
	p.spinback_spin_start_rpm = p_spinback_spin_start_rpm
	p.spinback_spin_end_rpm = p_spinback_spin_end_rpm
	p.spinback_speed_start_mps = p_spinback_speed_start_mps
	p.spinback_speed_end_mps = p_spinback_speed_end_mps
	p.initial_launch_angle_deg = p_initial_launch_angle_deg
	p.flight_profile = p_flight_profile
	return p
