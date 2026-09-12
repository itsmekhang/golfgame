class_name GolfLoadingScreen
extends CanvasLayer
## Reusable overlay: walk -> step up -> sit -> cruise -> depart -> fade.
## Call begin_hole(), update_progress(), then mark_ready(). No fake completion timer.

signal covered
signal ride_finished

@export var minimum_ride_time := GolfCartArt.DRIVE_START + 0.45
@export var demo_loop := false
@export var animation_speed := 1.0

const DEPART_TIME := 0.85
const FADE_TIME := 0.28
const DEMO_READY_AT := 4.75
const DEMO_DEPART_AT := 5.50
const DEMO_FADE_AT := DEMO_DEPART_AT + DEPART_TIME
const DEMO_LENGTH := DEMO_FADE_AT + 0.35

var art: GolfCartArt
var elapsed := 0.0
var _depart_elapsed := 0.0
var _can_finish := false
var _departing := false
var _covered := false
var _completed := false
var _skip_requested := false
var _redraw_accum := 0.0
var _goal_progress := 0.0

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	art = GolfCartArt.new()
	art.name = "CartIllustration"
	add_child(art)
	art.modulate.a = 0.0

func begin_hole(number: int, title: String, par_value: int, yards: int, initial: bool = false) -> void:
	art.hole_number = number
	art.hole_name = title
	art.hole_par = par_value
	art.hole_yards = yards
	art.initial_load = initial
	art.progress = 0.0
	art.stage_text = "Getting the course ready…" if initial else "Taking the scenic route…"

func update_progress(value: float, caption: String = "") -> void:
	_goal_progress = maxf(_goal_progress, clampf(value, 0.0, 1.0))
	if caption != "":
		art.stage_text = caption

func mark_ready() -> void:
	_can_finish = true
	art.ready_to_play = true
	_goal_progress = 1.0

func is_ready_to_finish() -> bool:
	return _can_finish

func _process(delta: float) -> void:
	if _completed:
		return
	# Preserve the readable walking and boarding if a loading job briefly stalls a frame.
	var step := minf(delta, 0.1) * animation_speed
	elapsed += step
	if demo_loop:
		var time := fmod(elapsed, DEMO_LENGTH)
		art.elapsed = time
		art.departure = clampf((time - DEMO_DEPART_AT) / DEPART_TIME, 0.0, 1.0) if time >= DEMO_DEPART_AT else -1.0
		art.progress = clampf(time / DEMO_READY_AT, 0.0, 1.0)
		art.ready_to_play = time >= DEMO_READY_AT
		art.modulate.a = minf(time / 0.2, 1.0) * (1.0 - clampf((time - DEMO_FADE_AT) / 0.35, 0.0, 1.0))
		art.queue_redraw()
		return
	art.elapsed = elapsed
	art.progress = move_toward(art.progress, _goal_progress, delta * 0.8)
	if not _covered:
		art.modulate.a = minf(elapsed / 0.2, 1.0)
		if elapsed >= 0.2:
			_covered = true
			covered.emit()
	if _can_finish and (elapsed >= minimum_ride_time or _skip_requested):
		_departing = true
	if _departing:
		_depart_elapsed += step
		art.departure = clampf(_depart_elapsed / DEPART_TIME, 0.0, 1.0)
		if _depart_elapsed > DEPART_TIME:
			art.modulate.a = 1.0 - clampf((_depart_elapsed - DEPART_TIME) / FADE_TIME, 0, 1)
		if _depart_elapsed >= DEPART_TIME + FADE_TIME:
			_completed = true
			ride_finished.emit()
	# 30 Hz is plenty for the small loading illustration; no work remains after free.
	_redraw_accum += delta
	if _redraw_accum >= 1.0 / 30.0:
		_redraw_accum = 0.0
		art.queue_redraw()

func _input(event: InputEvent) -> void:
	if _completed or demo_loop:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		# Space can shorten a ready transition; it can never skip unfinished work.
		if _can_finish:
			_skip_requested = true
			elapsed = maxf(elapsed, GolfCartArt.HOP_END)
			_depart_elapsed = maxf(_depart_elapsed, DEPART_TIME - 0.15)
	# The same press must not also hit a golf shot or change clubs underneath.
	get_viewport().set_input_as_handled()
