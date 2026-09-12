class_name PhysicsLogger
extends RefCounted
## GDScript port of OpenFairway `PhysicsLogger.cs`.
## Controls debug output verbosity for the physics engine.
## 0 = Off, 1 = Error, 2 = Info, 3 = Verbose.

enum Level { OFF = 0, ERROR = 1, INFO = 2, VERBOSE = 3 }

static var _level: int = Level.ERROR


static func set_level(level: int) -> void:
	_level = level


static func get_level() -> int:
	return _level


static func info(message: String) -> void:
	if _level >= Level.INFO:
		print(message)


static func verbose(message: String) -> void:
	if _level >= Level.VERBOSE:
		print(message)


static func error(message: String) -> void:
	if _level >= Level.ERROR:
		printerr(message)


static func push_physics_error(message: String) -> void:
	if _level >= Level.ERROR:
		push_error(message)
