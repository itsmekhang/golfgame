class_name AdminAccess
extends RefCounted
## The project's permission model is a single-player, local one: there is no server and no
## accounts, so "admin" means the person who launched the build with the developer switch.
## Sandbox (illegal) equipment can only be granted, equipped or swung while this is true, and
## any round that swings it is flagged sandbox by RoundTracker regardless.
##
## Enable with the environment variable GOLF_ADMIN=1 or the command-line flag --admin
## (`godot --path . -- --admin`), or for every launch with the project setting
## golf/admin_always_on (on in this build). GOLF_ADMIN=0 forces it off for a normal
## playthrough. Tests can force it either way with set_override().

static var _override := -1  # -1 unset, 0 forced off, 1 forced on


static func is_admin() -> bool:
	if _override >= 0:
		return _override == 1
	if OS.get_environment("GOLF_ADMIN") == "0":
		return false
	if OS.get_environment("GOLF_ADMIN") == "1":
		return true
	if bool(ProjectSettings.get_setting("golf/admin_always_on", false)):
		return true
	for a in OS.get_cmdline_user_args():
		if a == "--admin":
			return true
	for a in OS.get_cmdline_args():
		if a == "--admin":
			return true
	return false


static func set_override(enabled: bool) -> void:
	_override = 1 if enabled else 0


static func clear_override() -> void:
	_override = -1
