extends SceneTree
## The first loading screen shows the hole the round starts on (headless, a few seconds):
##   godot --headless --path . --script tests/round_start_loading_test.gd
## Launches course.tscn the way the start menu does for each Augusta round and reads the
## loading card before the course build gets going. Uses a throwaway save (never the player's).

var failures := 0


func check(cond: bool, what: String) -> void:
	print(("PASS " if cond else "FAIL ") + what)
	if not cond:
		failures += 1


func _init() -> void:
	root.child_entered_tree.connect(func(node: Node) -> void:
		if node is GameState:
			node.autosave = false
			node.save_path = "user://_round_start_unused.json")
	call_deferred("run")


func run() -> void:
	for case in [["front9", 1], ["back9", 10], ["full18", 1]]:
		GameLaunch.play_augusta(case[0])
		var course: Node3D = load("res://scenes/course.tscn").instantiate()
		root.add_child(course)  # _ready runs up to its first await: the loading card is up
		var card: GolfLoadingScreen = course._loading_screen
		var info: Dictionary = CourseBuilder.hole_info(case[1] - 1)
		check(card != null and card.hole_number == case[1], "%s: loading card shows hole %d (got %s)" % [case[0], case[1], str(card.hole_number) if card != null else "none"])
		if card != null:
			check(card.hole_name == str(info["name"]) and card.hole_par == int(info["par"]), "%s: card has hole %d's name and par (%s, par %d)" % [case[0], case[1], card.hole_name, card.hole_par])
			check(card._eyebrow.text.contains("BACK NINE") == (case[1] == 10), "%s: eyebrow %s" % [case[0], card._eyebrow.text])
		root.remove_child(course)
		course.free()
	GameLaunch.play_augusta("full18")
	print("DONE %d failures" % failures)
	quit(1 if failures > 0 else 0)
