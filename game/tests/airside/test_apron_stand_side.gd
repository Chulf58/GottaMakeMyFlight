class_name TestApronStandSide
extends GdUnitTestSuite
## ApronStand with west and east stands (slice S3 of design airside-all-
## around-technical-design-one-route-source-per-con): a saved side stand keeps
## its side through JSON. The taxi-out guard at side stands is
## test_apron_stand_taxi_guard.gd's.

const SITE := preload("res://build/terminal_site.tres")
const NORTH := {"exit": 2, "x": -22.5, "wall_z": -98.0}


func test_saved_side_stands_keep_their_side_through_json() -> void:
	var west := StandPlacement.make(2, 62.0, -150.0, StandPlacement.WEST)
	var east := StandPlacement.make(5, -62.0, -150.0, StandPlacement.EAST)
	var saved := {"stands": {"A": west, "B": east, "C": NORTH}}
	var data: Dictionary = JSON.parse_string(JSON.stringify(saved))
	var loaded := ApronStand.checked(data, SITE)
	print("loaded %s" % [loaded])
	assert_dict(loaded).not_contains_keys(["error"])
	assert_dict(loaded["stands"]["A"]).is_equal(west)
	assert_dict(loaded["stands"]["B"]).is_equal(east)
	assert_dict(loaded["stands"]["C"]).is_equal(NORTH)
	var one := ApronStand.checked(JSON.parse_string(JSON.stringify({"live": east})), SITE)
	assert_dict(one["live"]).is_equal(east)
	data["stands"]["A"]["side"] = "S"
	assert_dict(ApronStand.checked(data, SITE)).contains_keys(["error"])
