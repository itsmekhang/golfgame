class_name RoundTracker
extends RefCounted
## Ledger for one round in progress: strokes per hole, which club instance hit each stroke,
## and whether anything happened that makes the round non-standard (illegal sandbox gear,
## mulligans / restarts, skipped holes). course.gd feeds it; GameState.complete_round() reads
## the to_result() snapshot exactly once.

var round_id: String = ""
var pars: Array[int] = []
var hole_strokes: Array[int] = []  # -1 until the hole is finished (includes penalty strokes)
var strokes_by_instance: Dictionary = {}  # instance_id -> strokes actually swung with it
var store_by_instance: Dictionary = {}  # instance_id -> source_store snapshot
var _current_hole_stack: Array[String] = []  # instance ids of this hole's swings, for undo
var sandbox := false  # an illegal club was swung: no money, progress, restock or records
var assisted := false  # mulligan or hole restart used: pays out, but not a qualifying round
var skipped := false  # a hole was skipped (N): round can't complete
var illegal_used: Array[String] = []
var side_bets: Array = []  # SideBets.roll() for this round: [{id, text, target, reward}]
var started_msec := 0


static func start(p_round_id: String, p_pars: Array[int]) -> RoundTracker:
	var t := RoundTracker.new()
	t.round_id = p_round_id
	t.pars = p_pars.duplicate()
	for i in range(p_pars.size()):
		t.hole_strokes.append(-1)
	t.side_bets = SideBets.roll(p_round_id, p_pars)
	t.started_msec = Time.get_ticks_msec()
	return t


func holes() -> int:
	return pars.size()


func record_stroke(club: Clubs.Club) -> void:
	var iid := club.instance_id
	if iid == "":
		iid = "stock:%s" % club.short
	strokes_by_instance[iid] = int(strokes_by_instance.get(iid, 0)) + 1
	store_by_instance[iid] = club.source_store
	_current_hole_stack.append(iid)
	if club.illegal:
		sandbox = true
		if not illegal_used.has(club.model_id):
			illegal_used.append(club.model_id)


## Mulligan: forget the last swing (penalty strokes are course.gd's counters, not ours).
func undo_last_stroke() -> void:
	if _current_hole_stack.is_empty():
		return
	var iid: String = _current_hole_stack.pop_back()
	strokes_by_instance[iid] = maxi(0, int(strokes_by_instance.get(iid, 0)) - 1)
	if strokes_by_instance[iid] == 0:
		strokes_by_instance.erase(iid)
	if bool(EconomyConfig.round_cfg().get("mulligan_voids_qualifying", true)):
		assisted = true


## R: back to the tee. Every swing on this hole is forgotten; the round is flagged assisted.
func restart_hole() -> void:
	var had_swings := not _current_hole_stack.is_empty()
	while not _current_hole_stack.is_empty():
		undo_last_stroke()
	if had_swings and bool(EconomyConfig.round_cfg().get("restart_voids_qualifying", true)):
		assisted = true
	elif not had_swings:
		# restarting before swinging changes nothing, so don't punish it
		pass


func finish_hole(index: int, total_strokes: int) -> void:
	if index >= 0 and index < hole_strokes.size():
		hole_strokes[index] = total_strokes
	_current_hole_stack.clear()


func skip_hole() -> void:
	skipped = true
	_current_hole_stack.clear()


func holes_finished() -> int:
	var n := 0
	for s in hole_strokes:
		if s >= 0:
			n += 1
	return n


func all_holes_finished() -> bool:
	return holes_finished() == hole_strokes.size()


func total() -> int:
	var t := 0
	for s in hole_strokes:
		if s > 0:
			t += s
	return t


func par_total() -> int:
	var t := 0
	for i in range(pars.size()):
		if hole_strokes[i] >= 0:
			t += pars[i]
	return t


func rel_par() -> int:
	return total() - par_total()


## Instances that recorded at least one stroke and were bought at `store_id`.
func clubs_used_from(store_id: String) -> Array[String]:
	var out: Array[String] = []
	for iid in strokes_by_instance:
		if int(strokes_by_instance[iid]) > 0 and str(store_by_instance.get(iid, "")) == store_id:
			out.append(str(iid))
	return out


func to_result() -> Dictionary:
	return {
		"round_id": round_id,
		"pars": pars.duplicate(),
		"hole_strokes": hole_strokes.duplicate(),
		"total": total(),
		"par": par_total(),
		"rel_par": rel_par(),
		"complete": all_holes_finished() and not skipped,
		"sandbox": sandbox,
		"assisted": assisted,
		"skipped": skipped,
		"illegal_used": illegal_used.duplicate(),
		"strokes_by_instance": strokes_by_instance.duplicate(),
		"store_by_instance": store_by_instance.duplicate(),
		"side_bets": side_bets.duplicate(true),
		"duration_msec": Time.get_ticks_msec() - started_msec,
	}
