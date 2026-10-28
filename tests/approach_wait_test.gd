extends SceneTree
## The shot onto the green waits for the flight ahead only while it's still playing the hole or
## standing on the green; once they've holed out and stepped off it toward the next tee, it's
## played. Other shots still wait for anyone within reach.
var failed := false


func _init() -> void:
	root.child_entered_tree.connect(func(n: Node) -> void:
		if n is GameState:
			n.autosave = false
			n.save_path = "user://_approach_wait_test_unused.json")
	call_deferred("run")


func check(ok: bool, msg: String) -> void:
	if not ok:
		failed = true
		push_error(msg)


func person(life: ClubLife, at: Vector2) -> ClubLife.Walker:
	var w := ClubLife.Walker.new()
	w.node = Node3D.new()
	life.add_child(w.node)
	w.node.global_position = Vector3(at.x, 0.0, at.y)
	return w


func run() -> void:
	var c := PaintedCourse.create("Approach wait", Vector2i(400, 400))
	var pin := Vector2(0, -150)
	c.holes.append({"tee": Vector2(0, 0), "pin": pin, "par": 4, "bends": [], "curve": false})
	c.holes.append({"tee": Vector2(25, -165), "pin": Vector2(25, -300), "par": 3, "bends": [], "curve": false})
	c.paint(PaintedCourse.Surface.GREEN, pin, 12, 1, 1)
	var life := ClubLife.new()
	root.add_child(life)
	life.set_process(false)
	life.course = c
	# the flight playing in: its approach from 40 m out
	var g := ClubLife.Group.new()
	g.hole = 0
	g.stops = [Vector2(0, 0), Vector2(0, -110), pin]
	g.stop = 1
	g.turn = 0
	g.ball_positions = [Vector2(0, -110)]
	g.golfers = [person(life, Vector2(2, -110))]
	life._groups.append(g)
	# the flight ahead: still putting out on the green
	var a := ClubLife.Group.new()
	a.hole = 0
	a.hole_reserved = true
	a.stops = g.stops.duplicate()
	a.stop = 2
	a.golfers = [person(life, pin + Vector2(3, 2)), person(life, pin + Vector2(-4, 1))]
	life._groups.append(a)
	check(life._flight_ahead(g), "The approach was played into a flight still putting out")
	# holed out (on to the next hole), one of them still on the green
	a.hole = 1
	a.stop = 0
	(a.golfers[0] as ClubLife.Walker).node.global_position = Vector3(pin.x + 18, 0, pin.y - 6)
	check(life._flight_ahead(g), "The approach was played while one of the flight ahead still stood on the green")
	# both off the green, walking to the next tee just beyond it: play on
	(a.golfers[1] as ClubLife.Walker).node.global_position = Vector3(pin.x + 16, 0, pin.y - 10)
	check(not life._flight_ahead(g), "The approach waited for the flight ahead to reach the next tee")
	# the tee shot still waits for them in the fairway ahead
	g.stop = 0
	g.ball_positions = [Vector2(0, 0)]
	a.hole = 0
	a.stop = 1
	(a.golfers[0] as ClubLife.Walker).node.global_position = Vector3(0, 0, -120)
	(a.golfers[1] as ClubLife.Walker).node.global_position = Vector3(4, 0, -125)
	check(life._flight_ahead(g), "The tee shot didn't wait for the flight in the fairway")
	life.free()
	print("APPROACH WAIT: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
