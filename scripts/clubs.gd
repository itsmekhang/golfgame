class_name Clubs
extends RefCounted
## Club bag. Launch numbers are typical launch-monitor values at full power
## (ball speed mph, vertical launch deg, backspin rpm).

class Club:
	var name: String
	var short: String
	var ball_speed_mph: float
	var vla_deg: float
	var backspin_rpm: float
	var is_putter: bool
	func _init(p_name: String, p_short: String, p_speed: float, p_vla: float, p_spin: float, p_putter: bool = false) -> void:
		name = p_name
		short = p_short
		ball_speed_mph = p_speed
		vla_deg = p_vla
		backspin_rpm = p_spin
		is_putter = p_putter


static func bag() -> Array[Club]:
	return [
		# Real drivers/woods essentially never generate enough backspin to check or drift
		# backward on landing -- that's an irons/wedges thing. Low enough here that the
		# bounce model's steep-impact spinback term (bounce_calculator.gd's Penner branch,
		# which isn't green-only -- it can fire on any surface at high impact speed) has too
		# little spin left to meaningfully reverse the roll; these clubs should only ever go
		# forward and roll out, backing up only from an actual slope/hill, never from spin.
		Club.new("Driver", "DR", 160.0, 11.5, 1500.0),
		Club.new("3 Wood", "3W", 148.0, 12.5, 1900.0),
		Club.new("5 Wood", "5W", 140.0, 13.5, 2400.0),
		Club.new("4 Iron", "4I", 132.0, 14.0, 4600.0),
		Club.new("5 Iron", "5I", 127.0, 15.0, 5200.0),
		Club.new("6 Iron", "6I", 122.0, 16.0, 5800.0),
		Club.new("7 Iron", "7I", 117.0, 17.5, 6600.0),
		Club.new("8 Iron", "8I", 111.0, 19.5, 7400.0),
		Club.new("9 Iron", "9I", 105.0, 21.5, 8200.0),
		Club.new("Pitching Wedge", "PW", 98.0, 24.5, 9000.0),
		Club.new("Gap Wedge", "GW", 90.0, 27.0, 9400.0),
		Club.new("Sand Wedge", "SW", 82.0, 30.0, 9800.0),
		Club.new("Lob Wedge", "LW", 72.0, 34.0, 9500.0),
		Club.new("Putter", "PT", 18.0, 1.0, 60.0, true),
	]


## Typical full-power carry (yards) per bag() index, Driver..Lob Wedge (excludes the Putter).
const STOCK_CARRIES_YD := [265.0, 240.0, 225.0, 200.0, 190.0, 180.0, 165.0, 155.0, 140.0, 125.0, 110.0, 95.0, 75.0]


## Best club index for a distance to the pin (yards) - used for auto-select.
static func suggest(distance_yd: float, on_green: bool) -> int:
	var b := bag()
	if on_green:
		return b.size() - 1
	for i in range(STOCK_CARRIES_YD.size()):
		if distance_yd >= STOCK_CARRIES_YD[i] * 0.93:
			return i
	return STOCK_CARRIES_YD.size() - 1


## Rough full-swing carry estimate (yards) for a club at a given power fraction (0..1) --
## a cheap pre-flight proxy (audio cues, etc.) that doesn't need to run real ball physics.
static func stock_carry_yd(club_index: int, pfrac: float = 1.0) -> float:
	if club_index < 0 or club_index >= STOCK_CARRIES_YD.size():
		return 0.0
	return STOCK_CARRIES_YD[club_index] * clampf(pfrac, 0.0, 1.0)
