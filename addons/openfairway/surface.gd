class_name Surface
extends RefCounted
## GDScript port of OpenFairway `Surface.cs`.
## Compatibility helper that forwards to SurfacePhysicsCatalog.


## Returns ground interaction parameters for a given surface type:
## u_k, u_kr, nu_g, theta_c and the spinback_* fields.
func get_params(surface: int) -> Dictionary:
	return SurfacePhysicsCatalog.get_settings(surface).to_dictionary()
