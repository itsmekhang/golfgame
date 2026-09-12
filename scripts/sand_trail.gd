class_name SandTrail
extends RefCounted
## CPU-painted trail mask for the current hole's bunkers: an Image the ball darkens as it
## rolls through sand, pushed to a Texture2D the terrain shader reads. No extra camera/
## viewport -- cheap, and naturally freed/rebuilt per hole alongside terrain_root.

const RESOLUTION := 4096  # pixels per side, covering `region` -- needs to be high enough
                           # that BRUSH_RADIUS_M stays a small, multi-pixel mark rather than
                           # a fraction of a pixel over the (now bunker-scoped) region.
                           # Doubled alongside the last BRUSH_RADIUS_M halving: _stamp_px's
                           # 1-pixel-radius floor was already close (~0.95px at 2048), so
                           # halving the world radius alone would have silently hit that
                           # floor and rendered no visible change.
const BRUSH_RADIUS_M := 0.007  # world metres -- a thin skid mark, not a wide smear
const MAX_DARKEN := 0.55  # 1.0 = untouched, this = darkest a stamp can push a pixel to

var origin: Vector2
var size: Vector2
var image: Image
var texture: ImageTexture
var _px_per_m: Vector2  # pixels per metre, per axis -- region isn't necessarily square
var _dirty := false
var _last_stamp := Vector2(INF, INF)


func _init(region: Rect2) -> void:
	origin = region.position
	size = region.size
	_px_per_m = Vector2(RESOLUTION / maxf(size.x, 0.01), RESOLUTION / maxf(size.y, 0.01))
	image = Image.create(RESOLUTION, RESOLUTION, false, Image.FORMAT_R8)
	image.fill(Color(1, 1, 1, 1))
	texture = ImageTexture.create_from_image(image)


## world_xz -> image pixel coords.
func _px(world_xz: Vector2) -> Vector2:
	return (world_xz - origin) * _px_per_m


## Darken a soft circle (BRUSH_RADIUS_M wide in world space) centred on world_xz. `strength`
## scales how dark this stamp can push pixels (0..1); repeated stamps accumulate darker,
## clamped at MAX_DARKEN.
func stamp(world_xz: Vector2, strength: float = 1.0) -> void:
	var c := _px(world_xz)
	var step_r := maxf(BRUSH_RADIUS_M * maxf(_px_per_m.x, _px_per_m.y), 1.0)
	# Fill the gap if the ball moved further than the brush since the last stamp, so a fast
	# roll doesn't leave a dotted line.
	var points: Array[Vector2] = [c]
	if is_finite(_last_stamp.x):
		var d := c.distance_to(_last_stamp)
		if d > step_r:
			var steps := clampi(int(d / step_r), 1, 6)
			for i in range(steps):
				points.append(_last_stamp.lerp(c, float(i + 1) / (steps + 1)))
	for p in points:
		_stamp_px(p, strength)
	_last_stamp = c
	_dirty = true


func _stamp_px(c: Vector2, strength: float) -> void:
	var rx := maxf(BRUSH_RADIUS_M * _px_per_m.x, 1.0)
	var ry := maxf(BRUSH_RADIUS_M * _px_per_m.y, 1.0)
	var ri := int(ceil(maxf(rx, ry)))
	var x0 := clampi(int(c.x) - ri, 0, RESOLUTION - 1)
	var x1 := clampi(int(c.x) + ri, 0, RESOLUTION - 1)
	var y0 := clampi(int(c.y) - ri, 0, RESOLUTION - 1)
	var y1 := clampi(int(c.y) + ri, 0, RESOLUTION - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			# Normalized per-axis distance so a non-square region's differing px/metre on
			# each axis still reads as a round mark in world space, not an oval one.
			var dx := (x - c.x) / rx
			var dy := (y - c.y) / ry
			var d := sqrt(dx * dx + dy * dy)
			if d > 1.0:
				continue
			var falloff := 1.0 - d
			var cur := image.get_pixel(x, y).r
			var target := maxf(MAX_DARKEN, cur - falloff * strength * 0.5)
			image.set_pixel(x, y, Color(target, target, target, 1.0))


## Push accumulated CPU edits to the GPU texture. Call this throttled, not every stamp.
func flush() -> void:
	if not _dirty:
		return
	texture.set_image(image)
	_dirty = false
