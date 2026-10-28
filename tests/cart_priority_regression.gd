extends SceneTree
var failed := false

class Scheduler extends ClubLife:
	var slots: Array = []
	var cleanings := 0
	var barn_fetches := 0
	func _line_slots() -> Array:
		return slots
	func _wash_steps(_p: Walker) -> Array:
		cleanings += 1
		return [{"do": "cleaning_selected"}]
	func _new_barn_cart() -> Walker:
		barn_fetches += 1
		return null
	func _post_steps(_p: Walker) -> Array:
		return []
	func _home_steps(_p: Walker) -> Array:
		return []

func _init() -> void:
	root.child_entered_tree.connect(func(n: Node) -> void:
		if n is GameState: n.autosave = false)
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)

func actor(life: Scheduler) -> ClubLife.Walker:
	var w := ClubLife.Walker.new()
	w.node = Node3D.new()
	life.add_child(w.node)
	return w

func run() -> void:
	var life := Scheduler.new()
	root.add_child(life)
	life.set_process(false)
	life.course = PaintedCourse.create("Attendant priorities", Vector2i(100, 100))
	life.business = CourseBusiness.create()
	var workers: Array = []
	for i in range(3):
		var p := actor(life)
		p.data["role"] = "cart_attendant"
		workers.append(p)
		life._staff.append(p)
		check(life._runs_bags(p) and life._cart_duty(p) == "all", "Attendant %d is locked to a role" % (i + 1))
	for i in range(4):
		life.slots.append(Transform3D(Basis.IDENTITY, Vector3(i * 3, 0, 0)))
	var carts: Array = []
	for i in range(6): carts.append(actor(life))
	life._line = [null, carts[0], carts[1], null]
	life._stock = [carts[2]]
	for i in range(3):
		var g := ClubLife.Group.new()
		g.bag_run = true
		g.carts = [carts[i + 3]]
		life._groups.append(g)
		life._bag_runs.append([g, 0])
	for i in range(3):
		var steps := life._cart_job(workers[i])
		check(not steps.is_empty() and steps.back().get("do") == "hand_over", "Attendant %d chose a lower priority over delivery" % (i + 1))
	check(life.cleanings == 0 and life.barn_fetches == 0 and life._stock.size() == 1, "Lower priority work started while deliveries waited")
	var move := life._cart_job(workers[0])
	check(move.size() == 4 and move[2].get("kind") == "up", "Compaction did not precede barn replenishment")
	check(life._stock.size() == 1 and life.barn_fetches == 0, "Fetched a cart before rearranging existing carts")
	var moved: ClubLife.Walker = move[2]["cart"]
	move[2]["set"] = true
	workers[0].data["steps"] = move.slice(2)
	life._cart_boy(workers[0])
	check(moved.data.has("job"), "Cart reservation ended before its driver climbed out")
	check(life._cart_job(workers[1])[0].get("do") == "cleaning_selected", "Other attendants did not clean during a reserved line move")
	life._cart_boy(workers[0])
	check(not moved.data.has("job"), "Finished rearrangement did not release its cart")
	# No internal gap remains: replenishment is now the next job, for any attendant.
	life._line = [carts[0], carts[1], carts[3], null]
	var fetch := life._cart_job(workers[2])
	check(fetch.size() == 4 and fetch[2].get("kind") == "fetch" and life._stock.is_empty(), "Third attendant cannot replenish after compaction")
	check(life.cleanings == 1, "Cleaning selected before available replenishment")
	for c: ClubLife.Walker in carts: c.data.erase("job")
	life._line = [carts[0], carts[1], carts[2], carts[3]]
	for p: ClubLife.Walker in workers:
		p.data.erase("steps")
		var cleaning := life._cart_job(p)
		check(not cleaning.is_empty() and cleaning[0].get("do") == "cleaning_selected", "An attendant cannot clean when higher priorities are complete")
	check(life.cleanings == 4, "Cleaning remains restricted to one attendant")
	life._line[3] = null
	life._restocking = false
	check(life._cart_job(workers[0])[0].get("do") == "cleaning_selected", "An almost-full line caused a needless refill trip")
	life._line[3] = carts[3]
	# An actual wash step must keep running when a delivery and a line gap appear.
	var p: ClubLife.Walker = workers[0]
	var c: ClubLife.Walker = carts[0]
	c.data["washing"] = true
	p.data["wash_cart"] = c
	var current: Array = [{"do": "wash", "cart": c, "t": 0.0, "keep": true}, {"do": "dry", "cart": c, "hood": true}]
	p.data["steps"] = current
	life._bag_runs.append([life._groups[0], 0])
	life._line[3] = null
	life._cart_boy(p)
	check(p.data.get("steps") == current and current[0].get("do") == "wash" and current[0].get("t") == 0.5, "Current cleaning was interrupted by higher priority work")
	check(p.data.get("wash_cart") == c and c.data.has("washing") and life._bag_runs.size() == 1, "Active task lost its cart or claimed the next job early")
	check(life._claim_cart("line") == null and life._line[0] == c and c.data.has("washing"), "Delivery stole a cart before its cleaning completed")
	workers[1].riding = true
	workers[2].riding = true
	life._wake_returning_attendants()
	workers[1].riding = false
	workers[2].riding = false
	check((p.data["steps"] as Array).is_empty() and not p.data.has("wash_cart") and not c.data.has("washing"), "Urgent delivery failed to interrupt and release a cleaning task")
	var no_bags := life._bag_run_steps(p)
	check(not no_bags.any(func(step: Dictionary) -> bool: return step.get("kind") in ["curb", "away"]), "A delivery without bags detours to the front curb")
	# Restore the occupied-line wash check below.
	c.data["washing"] = true
	var flight := ClubLife.Group.new()
	flight.golfers = [workers[1]]
	check(not life._take_line(flight), "Self-service pickup interrupted an active cleaning job")
	print("ATTENDANTS: all 3 flexible; delivery > rearrange > replenish > clean; cleaning yields safely to demand; no empty bag-drop trips")
	life.queue_free()
	await process_frame
	print("CART PRIORITY REGRESSION: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
