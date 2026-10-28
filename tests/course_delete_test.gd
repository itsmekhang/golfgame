extends SceneTree
## Deleting saved Course Studio courses from the start menu (My Courses) and from the studio's
## Open dialog: asks first in the row, Keep backs out, Delete removes the file, and the studio
## keeps a deleted open course as an unsaved one. Run: godot --headless --path . --script tests/course_delete_test.gd

var failed := false


func _init() -> void:
	root.child_entered_tree.connect(func(node: Node) -> void:
		if node is GameState:
			node.autosave = false
			node.save_path = "user://course_delete_test_unused.json")
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	if not ok:
		failed = true
		push_error(label)


func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text and not node.is_queued_for_deletion():
		return node
	for c in node.get_children():
		var b := _find_button(c, text)
		if b != null:
			return b
	return null


func _row_of(list: Node, course_name: String) -> HBoxContainer:
	for row in list.get_children():
		if row is HBoxContainer and not row.is_queued_for_deletion():
			for l in row.find_children("*", "Label", true, false):
				if (l as Label).text == course_name:
					return row
	return null


func run() -> void:
	await process_frame
	var paths: Array = []
	for n in ["_Delete Test A", "_Delete Test B"]:
		var c := PaintedCourse.starter(n)
		check(c.save() == OK, "Saved %s" % n)
		paths.append(c.default_path())

	# ---- start menu: My Courses
	var menu = load("res://scenes/start_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	menu._show_courses()
	await process_frame
	var scroll: ScrollContainer = menu._sub.get_child(1)
	var list: VBoxContainer = scroll.get_child(0)
	var row := _row_of(list, "_Delete Test A")
	check(row != null, "My Courses lists the course")
	_find_button(row, "Delete").pressed.emit()
	await process_frame
	check(FileAccess.file_exists(paths[0]), "First click only asks")
	_find_button(row, "Keep").pressed.emit()
	await process_frame
	check(FileAccess.file_exists(paths[0]), "Keep backs out")
	list = (menu._sub.get_child(1) as ScrollContainer).get_child(0)
	row = _row_of(list, "_Delete Test A")
	_find_button(row, "Delete").pressed.emit()
	await process_frame
	_find_button(row, "Delete").pressed.emit()
	await process_frame
	check(not FileAccess.file_exists(paths[0]), "Confirmed delete removes the file")
	await process_frame
	var still := false
	for e in PaintedCourse.list_saved():
		still = still or str(e["path"]) == paths[0]
	check(not still, "Deleted course gone from the list")
	menu.queue_free()
	await process_frame

	# ---- studio: Open dialog, deleting the course that's open
	GameLaunch.custom_course = paths[1]
	var studio = load("res://scenes/course_studio.tscn").instantiate()
	root.add_child(studio)
	for i in range(5):
		await process_frame
	check(studio.path == paths[1], "Studio opened the second course")
	studio._show_open_dialog()
	await process_frame
	var srow := _row_of(studio._dialog, "_Delete Test B   ·   1 hole")
	if srow == null:
		for b in studio._dialog.find_children("*", "Button", true, false):
			if (b as Button).text.begins_with("_Delete Test B"):
				srow = b.get_parent()
	check(srow != null, "Open dialog lists the course")
	_find_button(srow, "Delete").pressed.emit()
	await process_frame
	_find_button(srow, "Delete").pressed.emit()
	await process_frame
	check(not FileAccess.file_exists(paths[1]), "Studio delete removes the file")
	check(studio.path == "" and studio.course != null, "Deleted open course stays open, unsaved")
	studio.queue_free()
	await process_frame
	for p in paths:
		PaintedCourse.delete_saved(p)
	print("COURSE DELETE: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
