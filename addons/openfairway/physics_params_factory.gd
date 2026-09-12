class_name PhysicsParamsFactory
extends RefCounted
## GDScript port of OpenFairway `PhysicsParamsFactory.cs` + `ResolvedPhysicsParams.cs`.
## Resolves environment, surface, and ball-profile inputs into the final
## PhysicsParams consumed by BallPhysics.


## Build a PhysicsParams from environment, surface, floor normal, rollout spin,
## optional ball profile and the launch regime inputs.
func create(air_density: float, air_viscosity: float, drag_scale: float, lift_scale: float,
		surface_type: int, floor_normal: Vector3, rollout_impact_spin: float = 0.0,
		ball_profile: BallPhysicsProfile = null, initial_launch_angle_deg: float = 0.0,
		launch_speed_mph: float = 0.0, launch_spin_rpm: float = 0.0) -> PhysicsParams:
	var profile := ball_profile if ball_profile != null else BallPhysicsProfile.new()
	var surface := SurfacePhysicsCatalog.get_settings(surface_type)
	var regime: RegimeScaleOverride = profile.resolve_scale_override(launch_speed_mph, initial_launch_angle_deg, launch_spin_rpm)["override"]

	return PhysicsParams.create(
		air_density,
		air_viscosity,
		drag_scale * profile.drag_scale_multiplier * regime.drag_scale_multiplier,
		lift_scale * profile.lift_scale_multiplier * regime.lift_scale_multiplier,
		surface.kinetic_friction * profile.kinetic_friction_multiplier * regime.kinetic_friction_multiplier,
		surface.rolling_friction * profile.rolling_friction_multiplier * regime.rolling_friction_multiplier,
		surface.grass_viscosity * profile.grass_viscosity_multiplier * regime.grass_viscosity_multiplier,
		surface.critical_angle + profile.critical_angle_offset_radians + regime.critical_angle_offset_radians,
		surface_type,
		floor_normal,
		rollout_impact_spin,
		surface.spinback_response_scale,
		surface.spinback_theta_boost_max * profile.spinback_theta_boost_multiplier * regime.spinback_theta_boost_multiplier,
		surface.spinback_spin_start_rpm,
		surface.spinback_spin_end_rpm,
		surface.spinback_speed_start_mps,
		surface.spinback_speed_end_mps,
		initial_launch_angle_deg,
		profile.resolved_flight
	)
