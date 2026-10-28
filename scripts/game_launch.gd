class_name GameLaunch
extends RefCounted
## What the start menu asked for, read by the course scene when it loads (static, so it
## survives the scene change). Running scenes/course.tscn directly keeps the old defaults.

## "front9" | "back9" | "full18" (see course.gd round_span).
static var round_span := "full18"
## A user course from the Course Studio (user://courses/<name>.course.json); "" = Augusta.
static var custom_course := ""
## True once the start menu has run, so the course knows "Main menu" has somewhere to go.
static var from_menu := false
## Where the round's Esc-overlay button leads: the start menu, back into the Course Studio
## when the round was launched from its Play button (test-play loop), or back to the Course
## Manager when you walked out to play your club's course.
static var return_scene := ""

const MENU_SCENE := "res://scenes/start_menu.tscn"
const COURSE_SCENE := "res://scenes/course.tscn"
const STUDIO_SCENE := "res://scenes/course_studio.tscn"
const MANAGER_SCENE := "res://scenes/course_manager.tscn"


static func play_augusta(span: String) -> void:
	round_span = span
	custom_course = ""
	from_menu = true
	return_scene = ""


static func play_custom(path: String, from_studio: bool = false, back_to: String = "") -> void:
	round_span = "full18"
	custom_course = path
	from_menu = true
	return_scene = STUDIO_SCENE if from_studio else back_to


static func exit_scene() -> String:
	return return_scene if return_scene != "" else MENU_SCENE


static func exit_label() -> String:
	return {STUDIO_SCENE: "Back to Studio", MANAGER_SCENE: "Back to Course Manager"}.get(return_scene, "Main menu")
