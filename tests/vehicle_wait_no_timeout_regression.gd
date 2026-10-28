extends SceneTree
var failed := false

func _init() -> void:
	root.child_entered_tree.connect(func(n: Node) -> void:
		if n is GameState: n.autosave = false)
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)

func actor(life: ClubLife) -> ClubLife.Walker:
	var w := ClubLife.Walker.new()
	w.node = Node3D.new()
	life.add_child(w.node)
	return w

class BlockedLife extends ClubLife:
	func _cart_ahead(_v: Walker, _dir: Vector3) -> bool: return true
	func _round_parked(_v: Walker, _dir: Vector3) -> void: pass
	func _person_ahead(_v: Walker, _dir: Vector3) -> bool: return false
	func _manned(_v: Walker) -> bool: return true

func run() -> void:
	var life := BlockedLife.new()
	root.add_child(life)
	life.set_process(false)
	for golf_cart in [true,false]:
		var car := actor(life)
		car.data = {"vehicle":true,"golf_cart":golf_cart}
		car.speed = 4.0
		car.path = [Vector3(0,0,-20)]
		for tick in range(500): life._step(car,0.1)
		check(car.node.global_position == Vector3.ZERO,"Blocked vehicle drove through after its timeout")
		check(not car.path.is_empty(),"Blocked vehicle discarded its original route")
	print("VEHICLE WAIT NO TIMEOUT: ","FAIL" if failed else "PASS")
	quit(1 if failed else 0)
