class_name SurfacePhysicsCatalog
extends RefCounted
## GDScript port of OpenFairway `SurfacePhysicsCatalog.cs`.
## Single source of truth for surface tuning values.

static var _fairway: SurfacePhysicsSettings
static var _fairway_soft: SurfacePhysicsSettings
static var _rough: SurfacePhysicsSettings
static var _firm: SurfacePhysicsSettings
static var _green: SurfacePhysicsSettings
static var _bunker: SurfacePhysicsSettings


static func _ensure() -> void:
	if _fairway != null:
		return
	# Rolling friction/viscosity trimmed down further, close to the green's own 0.028/0.0009,
	# so fairway rolls only slightly less than green (previously 0.035/0.0012 -- noticeably
	# more than green's own values -- still moving further from, not toward, the
	# rolling-friction integrator's instability range found earlier: lower is the safe direction).
	# kinetic_friction (ball_physics.gd's _calculate_friction_force) is the skid-phase friction
	# applied right after a bounce, before spin catches up to pure rolling -- at the old 0.50 it
	# was killing most of a shot's forward speed in that first instant of ground contact, well
	# before rolling_friction ever got a chance to matter. FIRM (cart paths) sits at 0.30 and
	# ROUGH at 0.62; 0.34 puts firm fairway turf close to the path end of that range instead of
	# nearly as grabby as rough.
	_fairway = SurfacePhysicsSettings.new(PhysicsEnums.SurfaceType.FAIRWAY,
		0.50, 0.036, 0.0013, 0.29, 0.78, 0.0, 0.0, 0.0, 0.0, 0.0)
	_fairway_soft = SurfacePhysicsSettings.new(PhysicsEnums.SurfaceType.FAIRWAY_SOFT,
		0.56, 0.070, 0.0024, 0.32, 0.92, 0.0, 0.0, 0.0, 0.0, 0.0)
	_rough = SurfacePhysicsSettings.new(PhysicsEnums.SurfaceType.ROUGH,
		0.62, 0.095, 0.0032, 0.35, 0.70, 0.0, 0.0, 0.0, 0.0, 0.0)
	_firm = SurfacePhysicsSettings.new(PhysicsEnums.SurfaceType.FIRM,
		0.30, 0.030, 0.0010, 0.25, 0.60, 0.0, 0.0, 0.0, 0.0, 0.0)
	_green = SurfacePhysicsSettings.new(PhysicsEnums.SurfaceType.GREEN,
		0.58, 0.028, 0.0009, 0.36, 1.12, 0.12, 3500.0, 5500.0, 8.0, 20.0)
	_apply_green_speed()
	# Sand: highest friction/viscosity of any surface (barely any roll once settled) and a
	# low critical angle + minimal spinback response (no meaningful bounce or check-back).
	# golf_ball.gd's _handle_impact also applies extra dead-bounce damping on first contact.
	_bunker = SurfacePhysicsSettings.new(PhysicsEnums.SurfaceType.BUNKER,
		0.95, 0.15, 0.0038, 0.18, 0.15, 0.0, 0.0, 0.0, 0.0, 0.0)


## Green speed for the round as a Stimpmeter reading (feet a ball released at
## 1.83 m/s rolls on a level green). Tour greens run 10-13 ft, a members' green
## 8-10. Sets the green's rolling friction so that release actually rolls that far:
## d = v^2 / (2 * mu * g)  ->  mu = v^2 / (2 * g * d). The catalog's original 0.028
## was equivalent to a ~20 ft green, which is why putts and approach rollout ran away.
const STIMP_RELEASE_MPS := 1.83
static var green_speed_ft: float = 10.0


static func set_green_speed(stimp_ft: float) -> void:
	green_speed_ft = clampf(stimp_ft, 5.0, 16.0)
	_ensure()
	_apply_green_speed()


static func _apply_green_speed() -> void:
	var d := green_speed_ft * 0.3048
	var mu := STIMP_RELEASE_MPS * STIMP_RELEASE_MPS / (2.0 * 9.81 * d)
	_green.rolling_friction = mu
	# the viscous drag term scales with the same speed index so slow trickles die out
	_green.grass_viscosity = 0.0009 * (mu / 0.028)


static func green_speed_label() -> String:
	var word := "slow" if green_speed_ft < 8.5 else "medium" if green_speed_ft < 10.5 else "fast" if green_speed_ft < 12.5 else "tournament"
	return "Greens %.0f ft (%s)" % [green_speed_ft, word]


## Returns the tuning for a surface. Unknown surfaces fall back to Fairway.
static func get_settings(surface: int) -> SurfacePhysicsSettings:
	_ensure()
	match surface:
		PhysicsEnums.SurfaceType.ROUGH:
			return _rough
		PhysicsEnums.SurfaceType.FAIRWAY_SOFT:
			return _fairway_soft
		PhysicsEnums.SurfaceType.FIRM:
			return _firm
		PhysicsEnums.SurfaceType.GREEN:
			return _green
		PhysicsEnums.SurfaceType.BUNKER:
			return _bunker
		_:
			return _fairway


static func surface_name(surface: int) -> String:
	match surface:
		PhysicsEnums.SurfaceType.FAIRWAY:
			return "Fairway"
		PhysicsEnums.SurfaceType.FAIRWAY_SOFT:
			return "FairwaySoft"
		PhysicsEnums.SurfaceType.ROUGH:
			return "Rough"
		PhysicsEnums.SurfaceType.FIRM:
			return "Firm"
		PhysicsEnums.SurfaceType.GREEN:
			return "Green"
		PhysicsEnums.SurfaceType.BUNKER:
			return "Bunker"
		_:
			return "Fairway"
