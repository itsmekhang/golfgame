class_name OrbitCamera
extends Camera3D
## Two modes:
##  - AIM: sits behind the ball looking down the aim line (right-drag / Q,E rotate, wheel zoom)
##  - FOLLOW: chases the ball in flight from behind and above, then eases back to AIM.

enum Mode { AIM, FOLLOW, OVERHEAD }

var mode: Mode = Mode.AIM
var target: Node3D
var aim_yaw: float = 0.0  # radians, direction ball will travel (0 = -Z)
var aim_pitch: float = deg_to_rad(12.0)
var distance: float = 6.0
var height_at_ground: Callable  # (x, z) -> float
var _follow_vel := Vector3.ZERO
var _dragging := false
var _smooth_pos: Vector3
var _smooth_look: Vector3
var frozen := false  # debug: stop following the target
## Bird's-eye view: pan with the arrow keys, wheel changes height. Look direction is
## right-drag only (like scouting below) -- A/D used to also spin this view, which fought
## with panning; now A/D do nothing here and right-drag both rotates (horizontal) and
## tilts between looking down at the ground and out toward the hole (vertical).
var overhead_offset := Vector3.ZERO
var overhead_height := 70.0
var overhead_yaw: float = 0.0
## Tilt ratio in the desired-position formula below: 0 = straight down at the ground,
## higher = pulled back further and angled out toward the horizon/hole.
var overhead_tilt: float = 0.28
const OVERHEAD_TILT_MIN := 0.05  # keep just off 0 -- exactly straight down is parallel to look_at's up vector
## Terrain/props only exist within the current hole's loaded region (course.gd's
## active_region). A flat OVERHEAD_TILT_MAX cap alone isn't enough to keep the view inside
## it: the camera sits height*tilt away from its look-at centre, so at high altitude even a
## modest tilt ratio pushes the camera (and what's visible beyond centre, away from it) far
## outside any reasonably-sized region. Capping height*tilt instead (OVERHEAD_REACH_CAP)
## keeps that horizontal pullback bounded regardless of height -- tilt is allowed to be
## fuller zoomed in low, and is automatically squeezed toward straight-down at high altitude.
const OVERHEAD_TILT_MAX := 0.6
const OVERHEAD_REACH_CAP := 90.0
## Even at tilt 0 (straight down), the camera's own FOV footprint on the ground grows with
## height -- at the old 400m max, on a typically fairway-width-ish region that footprint
## alone extended well past the loaded region's edges before tilt/pan were ever a factor.
## 150m keeps the worst-case footprint comfortably inside a normal hole's region.
const OVERHEAD_HEIGHT_MAX := 110.0
## World-space bounds (course.gd's active_region, shrunk by a safety margin) the overhead
## pan centre is clamped to -- set each frame by course.gd, empty Rect2 = unconstrained.
## Keeps the same "can't pan/tilt to see outside the loaded chunk" guarantee OVERHEAD_TILT_MAX
## covers for tilt, but for arrow-key panning instead.
var pan_bounds := Rect2()
## Ground-plane point the overhead camera is looking at, updated every frame while in
## OVERHEAD mode. Read by the minimap to draw the camera's focus circle.
var overhead_focus_point := Vector3.ZERO
## The height/tilt actually used this frame after the pan_bounds-fit shrink below --
## may be less than overhead_height/overhead_tilt on a small hole region. Exposed
## (rather than kept local to _process) so tests can check the real visible footprint
## instead of re-deriving the shrink logic themselves.
var overhead_used_height := 0.0
var overhead_used_tilt := 0.0

## Z (see course.gd): hold to fly out to a look at the anticipated landing spot, release to
## fly back to the normal view -- both transitions are a genuine flight (boosted-speed lerp),
## never an instant cut. Overlays on top of whatever `mode` is active rather than replacing
## it, so releasing always returns to wherever the camera already was (AIM, typically).
var scouting := false
var scout_target := Vector3.ZERO
var _was_scouting := false
var _was_overhead := false
var _scout_enter_t := 0.0
var _scout_return_t := 0.0
const SCOUT_FLY_TIME := 0.5
## Where the scout camera looks from around scout_target -- independent of aim_yaw so
## looking around while scouting never also changes the shot direction. A/D do nothing
## while scouting; right-drag rotates this instead (see _unhandled_input/_process).
var scout_yaw: float = 0.0
## Vertical look angle while scouting (radians, like aim_pitch) -- right-drag up/down
## tilts between looking out toward the hole and looking down at the landing spot.
var scout_pitch: float = deg_to_rad(54.25)  # matches the view's old fixed height/back framing
const SCOUT_PITCH_MIN := deg_to_rad(8.0)
const SCOUT_PITCH_MAX := deg_to_rad(85.0)
## Distance from scout_target the scout camera orbits at (sqrt(25^2 + 18^2), the old fixed
## height/back offsets) so the default framing is unchanged.
const SCOUT_DIST := 30.81


func _ready() -> void:
	fov = 60.0
	near = 0.05
	far = 8000.0
	_smooth_pos = global_position
	_smooth_look = target.global_position if target != null else Vector3.ZERO


func aim_direction() -> Vector3:
	return Vector3(-sin(aim_yaw), 0.0, -cos(aim_yaw)).normalized()


## World-space XZ bounds of the ground the OVERHEAD camera's 4 frustum corners hit,
## relative to a look-at centre at the world origin -- translation-invariant (the eye
## offset and view direction depend only on `fwd`/`eff_tilt`/`height`, not on where
## centre actually is), so the caller just offsets this by the real centre. Gives the
## bird's-eye view a real boundary: clamping only the look-at point (the old approach)
## still let a tilted, high, wide-FOV view see well past the edge of whatever ground
## is actually loaded (terrain only exists inside course.gd's active_region) -- this
## clamps the whole visible footprint instead. Returns [min, max]; either coordinate
## being INF means no corner hit the ground (shouldn't happen at OVERHEAD's tilts).
func _overhead_ground_extent(fwd: Vector3, eff_tilt: float, height: float) -> Array:
	var eye := Vector3.UP * height - fwd * (height * eff_tilt)
	var forward := (-eye).normalized()
	if forward.length_squared() < 0.0001:
		forward = Vector3.DOWN
	var right := forward.cross(Vector3.UP)
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	right = right.normalized()
	var cam_up := right.cross(forward).normalized()
	var aspect := 16.0 / 9.0
	var vp := get_viewport()
	if vp != null:
		var sz := vp.get_visible_rect().size
		if sz.y > 0.0:
			aspect = sz.x / sz.y
	var vfov_half := deg_to_rad(fov * 0.5)
	var hfov_half := atan(tan(vfov_half) * aspect)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	# Typed explicitly: an untyped array literal iterated inline leaves `su`/`sv` as
	# Variant, which then poisons every expression built from them (right * (su * ...))
	# into Variant too -- the GDScript parser then can't statically type `dir`/`t`/`pt`
	# below even though they carry their own type annotations, and refuses to compile.
	var signs: Array[float] = [-1.0, 1.0]
	for su in signs:
		for sv in signs:
			var dir: Vector3 = (forward + right * (su * tan(hfov_half)) + cam_up * (sv * tan(vfov_half))).normalized()
			if dir.y > -0.02:
				continue  # this corner points at/above the horizon -- sky, not ground, no bound needed
			var t: float = eye.y / -dir.y
			var pt: Vector3 = eye + dir * t
			lo.x = minf(lo.x, pt.x)
			hi.x = maxf(hi.x, pt.x)
			lo.y = minf(lo.y, pt.z)
			hi.y = maxf(hi.y, pt.z)
	return [lo, hi]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			if mode == Mode.OVERHEAD:
				overhead_height = clampf(overhead_height * 0.85, 20.0, OVERHEAD_HEIGHT_MAX)
			else:
				distance = clampf(distance * 0.85, 1.2, 40.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			if mode == Mode.OVERHEAD:
				overhead_height = clampf(overhead_height * 1.18, 20.0, OVERHEAD_HEIGHT_MAX)
			else:
				distance = clampf(distance * 1.18, 1.2, 40.0)
	elif event is InputEventMouseMotion and _dragging and scouting:
		# While scouting, right-drag orbits the scout camera around the landing spot via its
		# own scout_yaw/scout_pitch -- detached from aim_yaw so looking around never also
		# changes where the shot is aimed (A/D do nothing here, see _process). Horizontal
		# drag rotates around the target; vertical drag tilts between looking out toward the
		# hole (drag up) and looking down at the landing spot (drag down).
		var mm := event as InputEventMouseMotion
		scout_yaw -= mm.relative.x * 0.004
		scout_pitch = clampf(scout_pitch - mm.relative.y * 0.003, SCOUT_PITCH_MIN, SCOUT_PITCH_MAX)
	elif event is InputEventMouseMotion and _dragging and mode == Mode.OVERHEAD:
		# Right-drag is the only way to look around in bird's-eye view -- A/D used to also
		# spin this view (via aim_yaw), which fought with the arrow-key panning below; aim
		# there is A/D only in AIM mode now (see _process). Horizontal drag rotates the view
		# around the pan centre; vertical drag tilts between looking straight down at the
		# ground (drag down) and angled out toward the hole (drag up).
		var mm := event as InputEventMouseMotion
		overhead_yaw -= mm.relative.x * 0.004
		overhead_tilt = clampf(overhead_tilt - mm.relative.y * 0.0025, OVERHEAD_TILT_MIN, OVERHEAD_TILT_MAX)
	elif event is InputEventMouseMotion and _dragging and mode == Mode.AIM:
		# Right-drag aims only in AIM mode.
		var mm := event as InputEventMouseMotion
		aim_yaw -= mm.relative.x * 0.004
		aim_pitch = clampf(aim_pitch + mm.relative.y * 0.003, deg_to_rad(2.0), deg_to_rad(70.0))


func _process(delta: float) -> void:
	if target == null or frozen:
		return
	# A/D never touch aim_yaw while scouting -- that's fully detached to scout_yaw
	# (right-drag, see _unhandled_input) so looking around a landing spot can never also
	# nudge the actual shot direction.
	if scouting:
		pass
	elif mode == Mode.AIM:
		var turn := 0.0
		if Input.is_action_pressed("aim_left"):
			turn += 1.0
		if Input.is_action_pressed("aim_right"):
			turn -= 1.0
		aim_yaw += turn * delta * 0.9
	# OVERHEAD no longer reads A/D at all -- looking around is right-drag only (see
	# _unhandled_input), which sets overhead_yaw/overhead_tilt directly. Arrow keys still
	# pan below.

	var ball := target.global_position
	var desired: Vector3
	var look: Vector3
	match mode:
		Mode.AIM:
			var back := -aim_direction()
			desired = ball + back * distance * cos(aim_pitch) + Vector3.UP * (distance * sin(aim_pitch) + 0.4)
			look = ball + aim_direction() * 12.0 + Vector3.UP * 0.5
		Mode.FOLLOW:
			var v: Vector3 = target.velocity if "velocity" in target else Vector3.ZERO
			var dir := Vector3(v.x, 0.0, v.z)
			if dir.length() < 0.5:
				dir = aim_direction()
			dir = dir.normalized()
			var speed := v.length()
			var d := clampf(4.0 + speed * 0.12, 4.0, 14.0)
			desired = ball - dir * d + Vector3.UP * (2.0 + speed * 0.05)
			look = ball + dir * 2.0
		Mode.OVERHEAD:
			# Arrow keys pan the view across the hole (speed scales with height)
			var pan := Vector3.ZERO
			if Input.is_key_pressed(KEY_LEFT):
				pan.x -= 1.0
			if Input.is_key_pressed(KEY_RIGHT):
				pan.x += 1.0
			if Input.is_key_pressed(KEY_UP):
				pan.z -= 1.0
			if Input.is_key_pressed(KEY_DOWN):
				pan.z += 1.0
			# fwd = wherever right-drag has pointed the view (overhead_yaw, independent of
			# aim_yaw -- see _unhandled_input); the pan direction and the tilt below are both
			# built from it so panning "up" always matches whatever the view is currently
			# facing, however it's been rotated.
			if not _was_overhead:
				overhead_yaw = aim_yaw  # start facing the same way as the current aim
			var fwd := Vector3(-sin(overhead_yaw), 0.0, -cos(overhead_yaw)).normalized()
			if pan != Vector3.ZERO:
				var right := Vector3(-fwd.z, 0.0, fwd.x)
				overhead_offset += (right * pan.x - fwd * pan.z) * delta * overhead_height * 0.9
			var centre := ball + overhead_offset
			# Sit behind (away from the pin) and above, tilted by overhead_tilt (right-drag
			# vertical: 0 = straight down at the ground, higher = angled out toward the hole)
			# -- see OVERHEAD_REACH_CAP for why the effective tilt is squeezed at altitude.
			var used_height := overhead_height
			var eff_tilt := minf(overhead_tilt, OVERHEAD_REACH_CAP / maxf(used_height, 1.0))
			var ext := _overhead_ground_extent(fwd, eff_tilt, used_height)
			if pan_bounds.size != Vector2.ZERO:
				# Re-centring alone can't fix it when the *whole* footprint is wider than
				# pan_bounds itself (a small hole region at max height/tilt) -- no centre
				# position makes that fit, so first shrink the height (which shrinks the
				# footprint) until it does. Binary search: 8 m always fits any real hole
				# region, so it anchors the "fits" side.
				if ext[1].x - ext[0].x > pan_bounds.size.x or ext[1].y - ext[0].y > pan_bounds.size.y:
					var lo_h := 8.0
					var hi_h := used_height
					for i in range(14):
						var mid_h := (lo_h + hi_h) * 0.5
						var mid_tilt := minf(overhead_tilt, OVERHEAD_REACH_CAP / maxf(mid_h, 1.0))
						var mid_ext := _overhead_ground_extent(fwd, mid_tilt, mid_h)
						if mid_ext[1].x - mid_ext[0].x <= pan_bounds.size.x and mid_ext[1].y - mid_ext[0].y <= pan_bounds.size.y:
							lo_h = mid_h
						else:
							hi_h = mid_h
					used_height = lo_h
					eff_tilt = minf(overhead_tilt, OVERHEAD_REACH_CAP / maxf(used_height, 1.0))
					ext = _overhead_ground_extent(fwd, eff_tilt, used_height)
				# Now the footprint fits inside pan_bounds in both axes -- clamp the actual
				# visible ground into it, not just the look-at point (at height/tilt the far
				# edge of the frustum reaches well past centre, so clamping centre alone still
				# let the view see past the edge of whatever ground is loaded).
				var lo: Vector2 = ext[0]
				var hi: Vector2 = ext[1]
				var lo_x := pan_bounds.position.x - lo.x
				var hi_x := pan_bounds.end.x - hi.x
				var lo_z := pan_bounds.position.y - lo.y
				var hi_z := pan_bounds.end.y - hi.y
				centre.x = clampf(centre.x, lo_x, hi_x) if lo_x <= hi_x else (lo_x + hi_x) * 0.5
				centre.z = clampf(centre.z, lo_z, hi_z) if lo_z <= hi_z else (lo_z + hi_z) * 0.5
				overhead_offset = centre - ball
			overhead_focus_point = centre
			overhead_used_height = used_height
			overhead_used_tilt = eff_tilt
			desired = centre + Vector3.UP * used_height - fwd * (used_height * eff_tilt)
			look = centre
			_was_overhead = true

	if mode != Mode.OVERHEAD:
		_was_overhead = false

	# Z: overrides whatever `mode` computed above with a look at the anticipated landing
	# spot, so releasing always falls back to that same mode's framing.
	if scouting:
		if not _was_scouting:
			scout_yaw = aim_yaw  # start facing the same way as the current aim
		var scout_fwd := Vector3(-sin(scout_yaw), 0.0, -cos(scout_yaw)).normalized()
		# scout_pitch (right-drag vertical): higher = looking further out toward the hole,
		# lower = looking more straight down at the landing spot -- same shape as the AIM
		# camera's back*cos + up*sin formula, just orbiting scout_target instead of the ball.
		desired = scout_target - scout_fwd * SCOUT_DIST * cos(scout_pitch) + Vector3.UP * SCOUT_DIST * sin(scout_pitch)
		look = scout_target

	# Keep the camera above the terrain
	if height_at_ground.is_valid():
		var gy: float = height_at_ground.call(desired.x, desired.z)
		desired.y = maxf(desired.y, gy + 0.6)

	if scouting and not _was_scouting:
		_scout_enter_t = SCOUT_FLY_TIME
	if not scouting and _was_scouting:
		_scout_return_t = SCOUT_FLY_TIME
	_was_scouting = scouting

	var speed := 10.0 if mode == Mode.AIM else 5.0
	if _scout_enter_t > 0.0:
		_scout_enter_t -= delta
		speed = 14.0  # fly out to the landing spot instead of cutting to it
	elif _scout_return_t > 0.0:
		_scout_return_t -= delta
		speed = 18.0  # sling-shot back to the normal view after releasing Z
	var k := 1.0 - exp(-delta * speed)
	_smooth_pos = _smooth_pos.lerp(desired, k)
	_smooth_look = _smooth_look.lerp(look, k)
	global_position = _smooth_pos
	if (_smooth_look - _smooth_pos).length() > 0.01:
		look_at(_smooth_look, Vector3.UP)


func set_mode(m: Mode) -> void:
	if m != Mode.OVERHEAD:
		overhead_offset = Vector3.ZERO
	mode = m


func snap_to_aim() -> void:
	_smooth_pos = global_position
