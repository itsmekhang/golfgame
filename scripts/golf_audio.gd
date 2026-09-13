class_name GolfAudio
extends Node
## Wires the recorded golf sound-effects pack (res://audio/, see audio/cue_catalog.json for
## sourcing) into gameplay: club-strike sounds keyed off Clubs.Club + lie, mishit sounds for
## extreme strike points, sand-escape, cup-out and a crowd reaction on a good score.
##
## Positional shot sounds play from a small round-robin pool of AudioStreamPlayer3D so
## simultaneous/overlapping shots (e.g. a quick mulligan) don't cut each other off; the cup-out
## and crowd stingers use a plain (non-positional) player since they should read clearly
## regardless of camera distance.

const POOL_SIZE := 6

# category -> Array[AudioStream], built once in _ready from the folders under res://audio/.
var _by_club: Dictionary = {}
var _fat_shots: Array = []
var _topped: Array = []
var _swing_driver: Array = []
var _swing_general: Array = []
var _rough_swing: Array = []
var _fairway_hits: Array = []
var _bunker_escape: Array = []
var _cup_in: Array = []
var _crowd_cheer: Array = []
var _putter_hit: Array = []
var _putter_hit_layer: Array = []
var _bounce: Array = []

var _pool: Array[AudioStreamPlayer3D] = []
var _pool_next := 0
var _stinger: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()

# Maps a Clubs.Club "short" code to the res://audio/impacts/<category> folder that matches it.
const CLUB_CATEGORY := {
	"DR": "driver",
	"3W": "woods", "5W": "woods",
	"4I": "irons", "5I": "irons", "6I": "irons", "7I": "irons", "8I": "irons", "9I": "irons",
	"PW": "pitching_wedge",
	"GW": "sand_wedge", "SW": "sand_wedge", "LW": "sand_wedge",
}


func _ready() -> void:
	_rng.randomize()
	for cat in ["woods", "irons", "pitching_wedge", "sand_wedge", "general"]:
		_by_club[cat] = _load_dir("res://audio/impacts/%s" % cat)
	# Putter uses two fixed, layered clips rather than a random pick from the folder -- a putt
	# is the same quiet, consistent stroke every time, so it gets a consistent sound: the base
	# putting-stroke recording plus a harder-edged impact layered underneath for a fuller click.
	_putter_hit = [load("res://audio/impacts/putter/069_putting_a_golf_ball_with_putter.wav")]
	_putter_hit_layer = [load("res://audio/impacts/putter/070_hard_golf_put_impact.wav")]
	# Driver pinned to this hand-picked subset for now, not the full 17-file folder.
	_by_club["driver"] = [
		load("res://audio/impacts/driver/006_teeing_off_with_metal_driver.wav"),
		load("res://audio/impacts/driver/048_distant_recording_of_a_metal_driver_hitting_the_ball_off_a_tee.wav"),
	]
	# These two live in the impacts/driver/ folder but are hand-classified as woods, not
	# driver -- appended on top of the impacts/woods/ folder scan above.
	_by_club["woods"].append_array([
		load("res://audio/impacts/driver/046_driver_with_a_large_metal_head_hits_ball_off_of_a_tee_2.wav"),
		load("res://audio/impacts/driver/047_driver_with_a_small_metal_head_hits_ball_off_of_a_tee.wav"),
	])
	_fat_shots = _load_dir("res://audio/mishits/fat_shots")
	_topped = _load_dir("res://audio/mishits/topped")
	_swing_driver = _load_dir("res://audio/swings/driver")
	_swing_general = _load_dir("res://audio/swings/general")
	_rough_swing = _load_dir("res://audio/swings/rough_and_brush")
	# The source files here are multi-hit range-session recordings (7 and 14 consecutive
	# strikes in one continuous take); split into individual per-hit clips by tools/split_fairway_hits.py
	# (onset-detected cut points) so each swing gets one clean cue instead of a whole sequence.
	_fairway_hits = _load_dir("res://audio/sequences/fairway_hits/split")
	_bunker_escape = _load_dir("res://audio/impacts/bunker")
	_cup_in = _load_dir("res://audio/ball/cup")
	_crowd_cheer = _load_dir("res://audio/crowd/applause_and_cheers")
	_bounce = [load("res://audio/bounce.wav")]

	for i in range(POOL_SIZE):
		var p := AudioStreamPlayer3D.new()
		p.name = "ShotVoice%d" % i
		# Golf hits are loud in reality but this is a gameplay SFX, not a sim -- keep it audible
		# from typical follow-camera distance instead of realistically falling off by ~50m.
		p.unit_size = 8.0
		p.max_distance = 120.0
		add_child(p)
		_pool.append(p)

	_stinger = AudioStreamPlayer.new()
	_stinger.name = "Stinger"
	_stinger.bus = "Master"
	add_child(_stinger)


func _load_dir(path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(path)
	if dir == null:
		push_warning("GolfAudio: missing folder %s" % path)
		return out
	# In an exported PCK an imported resource's raw source file isn't itself packed -- the
	# directory listing shows only "<name>.wav.import" (the remap descriptor), not "<name>.wav".
	# Running from source (editor/headless dev) sees BOTH the real ".wav" and its ".import"
	# sidecar as separate files on disk, so de-dupe by resolved resource name or dev mode would
	# load (and audibly double-play) every file twice.
	var seen := {}
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir():
			var res_name := fname.trim_suffix(".import")
			if res_name.get_extension().to_lower() == "wav" and not seen.has(res_name):
				seen[res_name] = true
				var stream: AudioStream = load(path.path_join(res_name))
				if stream != null:
					out.append(stream)
		fname = dir.get_next()
	dir.list_dir_end()
	return out


func _pick(streams: Array) -> AudioStream:
	if streams.is_empty():
		return null
	return streams[_rng.randi_range(0, streams.size() - 1)]


func _play_at(streams: Array, pos: Vector3, volume_db: float = 0.0) -> void:
	var stream := _pick(streams)
	if stream == null:
		return
	var p := _pool[_pool_next]
	_pool_next = (_pool_next + 1) % _pool.size()
	p.global_position = pos
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = _rng.randf_range(0.95, 1.05)
	p.play()


func _play_stinger(streams: Array, volume_db: float = 0.0, delay: float = 0.0) -> void:
	var stream := _pick(streams)
	if stream == null:
		return
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	_stinger.stream = stream
	_stinger.volume_db = volume_db
	_stinger.pitch_scale = _rng.randf_range(0.97, 1.03)
	_stinger.play()


## Swings shorter than this (estimated carry, see Clubs.stock_carry_yd) are too soft/short a
## stroke for the big air whoosh -- a half-timed wedge shot shouldn't sound like a full driver
## rip. Below this the club just gets its clean strike sound with no swing layer under it.
const WHOOSH_MIN_CARRY_YD := 170.0


## Called once per swing (course.gd's _fire_shot), right as the ball is struck.
##  - club: the Clubs.Club in use.
##  - lie: PhysicsEnums.SurfaceType / CourseLayout.SURFACE_* the ball was addressed from.
##  - hit: strike point from StrikeSelector (x heel/toe, y low/high), used to pick a
##    fat/topped mishit sound on an extreme strike instead of a clean hit.
##  - pos: world position to play the sound from (the ball's position at address).
##  - est_carry_yd: rough pre-flight carry estimate (Clubs.stock_carry_yd) -- gates the
##    swing-driver/swing-general air whoosh to swings long enough to actually have one.
func play_shot(club: Clubs.Club, lie: int, hit: Vector2, pos: Vector3, est_carry_yd: float = 0.0) -> void:
	if club.is_putter:
		# Two fixed clips layered together every putt -- see the _putter_hit/_putter_hit_layer
		# loading comment in _ready. No lie/whoosh/mishit layers below apply to a putting stroke.
		_play_at(_putter_hit, pos)
		_play_at(_putter_hit_layer, pos, -6.0)
		return

	# A ball played out of a bunker always uses the dedicated sand-extraction sound as its
	# swing sound -- it already captures the full downswing-through-sand character on its own
	# (unlike the plain air whoosh below), so it replaces the lie-layer instead of sitting
	# under it, and matches what the strike-point mechanic already does to speed/spin for a
	# bunker lie (see course.gd's _shot_params).
	if lie == CourseLayout.SURFACE_BUNKER:
		_play_at(_bunker_escape, pos)
		return

	var category: String = CLUB_CATEGORY.get(club.short, "general")
	var is_iron_or_wedge := category == "irons" or category == "pitching_wedge" or category == "sand_wedge"

	# The downswing whoosh has no separate timing of its own in this game (contact is
	# instantaneous when the shot fires) so it's layered under the strike sound rather than
	# sequenced before it -- quieter than the strike so it reads as texture, not a second hit.
	# The lie shapes the base texture: rough gets its own grass-brushing swish; an iron or
	# wedge played off the fairway gets one of the split fairway-hit cues (see _ready). The air
	# whoosh is a separate, distance-gated layer on top of that -- a long enough swing (a real
	# drive off the tee, say) gets both the lie texture AND the whoosh together, not one or the
	# other.
	if lie == PhysicsEnums.SurfaceType.ROUGH:
		_play_at(_rough_swing, pos, -6.0)
	elif is_iron_or_wedge and (lie == PhysicsEnums.SurfaceType.FAIRWAY or lie == PhysicsEnums.SurfaceType.FAIRWAY_SOFT):
		_play_at(_fairway_hits, pos, -8.0)
	if est_carry_yd > WHOOSH_MIN_CARRY_YD:
		var swing_pool: Array = _swing_driver if club.short == "DR" else _swing_general
		_play_at(swing_pool, pos, -6.0)

	# Extreme low/high strikes already cost speed/spin in _shot_params; give them a matching
	# wrong-sounding contact instead of the same clean strike sound every time.
	if hit.y <= -0.65:
		_play_at(_fat_shots, pos)
		return
	elif hit.y >= 0.75:
		_play_at(_topped, pos)
		return

	var pool: Array = _by_club.get(category, _by_club.get("general", []))
	_play_at(pool, pos)


## The ball's first ground contact after flight -- course.gd's _on_first_impact -- covering
## the landing/bounce/roll, wherever it comes down. The source recording is quiet relative to
## the rest of the pack (peaks around -11 dBFS vs. the strike sounds' much hotter levels), so
## it gets a boost rather than the default 0 dB every other cue uses.
func play_bounce(pos: Vector3) -> void:
	_play_at(_bounce, pos, 8.0)


## Ball dropping into the cup -- course.gd's _on_ball_holed, right as the hole finishes.
func play_holed() -> void:
	_play_stinger(_cup_in, -2.0)


## Par or better -- layered slightly after the cup-in sound.
func play_crowd_cheer() -> void:
	_play_stinger(_crowd_cheer, -4.0, 0.35)
