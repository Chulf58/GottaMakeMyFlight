class_name TestRatingAdjustmentSnapshot
extends GdUnitTestSuite
## Incident adjustments go through the rating's save (AirportRating save
## version 2): a JSON round trip restores them, the restored rating expires
## them exactly like the original, and a bad adjustment refuses the whole
## snapshot, leaving the rating as it was.

var _rating: AirportRating
var _other: AirportRating


func before_test() -> void:
	_rating = auto_free(AirportRating.new()) as AirportRating
	_other = auto_free(AirportRating.new()) as AirportRating


func _noon(day: int) -> int:
	return GameCalendar.tick_at(day, 12 * 60)


## A day of passengers at 3.5 stars and two adjustments held at noon of day 1.
func _filled() -> void:
	for i in 5:
		_rating.record_passenger(_noon(0), true, PassengerSim.MOOD_MAX)
		_rating.record_passenger(_noon(0), false, 0)
	assert_bool(_rating.add_adjustment("inspector-0", _noon(0), _noon(2), -2)).is_true()
	assert_bool(_rating.add_adjustment("vip-1", _noon(1), _noon(1) + 50, -1)).is_true()


func _json() -> Dictionary:
	return JSON.parse_string(JSON.stringify(_rating.to_snapshot()))


func _text(rating: AirportRating) -> String:
	return JSON.stringify(rating.to_snapshot())


func test_adjustments_round_trip_through_json() -> void:
	_filled()
	var saved := _json()
	print(saved["adjustments"])
	assert_int(int(saved["save_version"])).is_equal(2)
	assert_array(saved["adjustments"]).has_size(2)
	assert_bool(_other.from_snapshot(saved)).is_true()
	assert_array(_other.active_adjustments()).is_equal(_rating.active_adjustments())
	assert_float(_other.stars()).is_equal(_rating.stars())
	assert_float(_other.stars()).is_equal(2.0)
	assert_str(_text(_other)).is_equal(_text(_rating))


func test_a_restored_rating_expires_them_like_the_original() -> void:
	_filled()
	assert_bool(_other.from_snapshot(_json())).is_true()
	for rating: AirportRating in [_rating, _other]:
		rating.on_tick(_noon(1) + 50)
	assert_array(_other.active_adjustments()).has_size(1)
	assert_float(_other.stars()).is_equal(2.5)
	for rating: AirportRating in [_rating, _other]:
		rating.on_tick(_noon(2))
	assert_array(_other.active_adjustments()).is_empty()
	assert_str(_text(_other)).is_equal(_text(_rating))


func test_bad_adjustments_refuse_the_snapshot_and_leave_the_rating_unchanged() -> void:
	_filled()
	var good := _json()
	var tick: int = good["tick"]
	var most := RatingAdjustments.MAX_HALF_STAR_DELTA
	var past_max := RatingSnapshot.MAX_TICK + 2.0
	var cases := {
		"version 1": func(d): d["save_version"] = 1,
		"no adjustments key": func(d): d.erase("adjustments"),
		"adjustments not an array": func(d): d["adjustments"] = {},
		"entry not a dictionary": func(d): d["adjustments"][0] = "x",
		"entry key missing": func(d): d["adjustments"][0].erase("expiry_tick"),
		"entry extra key": func(d): d["adjustments"][0]["x"] = 1,
		"id not a string": func(d): d["adjustments"][0]["id"] = 3,
		"empty id": func(d): d["adjustments"][0]["id"] = "",
		"id twice": func(d): d["adjustments"][1]["id"] = "inspector-0",
		"zero delta": func(d): d["adjustments"][0]["half_star_delta"] = 0,
		"fractional delta": func(d): d["adjustments"][0]["half_star_delta"] = -1.5,
		"string delta": func(d): d["adjustments"][0]["half_star_delta"] = "-2",
		"positive delta": func(d): d["adjustments"][0]["half_star_delta"] = 1,
		"delta above the most": func(d): d["adjustments"][0]["half_star_delta"] = most + 1,
		"delta below the least": func(d): d["adjustments"][0]["half_star_delta"] = -most - 1,
		"negative outcome": func(d): d["adjustments"][0]["outcome_tick"] = -1,
		"outcome after the saved tick": func(d): d["adjustments"][0]["outcome_tick"] = tick + 1,
		"fractional outcome": func(d): d["adjustments"][0]["outcome_tick"] = 10.5,
		"expiry at the saved tick": func(d): d["adjustments"][0]["expiry_tick"] = tick,
		"expiry past 2^53": func(d): d["adjustments"][0]["expiry_tick"] = past_max,
		"too many": func(d): _overfill(d),
	}
	var before := _text(_rating)
	for name: String in cases:
		var data: Dictionary = good.duplicate(true)
		(cases[name] as Callable).call(data)
		assert_bool(_rating.from_snapshot(data)).override_failure_message(name).is_false()
		assert_str(_text(_rating)).override_failure_message(name).is_equal(before)


## More adjustments than RatingAdjustments.MAX_COUNT, each valid on its own.
func _overfill(data: Dictionary) -> void:
	var list: Array = []
	for i in RatingAdjustments.MAX_COUNT + 1:
		var entry := {"id": "a%d" % i, "half_star_delta": -1}
		entry["outcome_tick"] = data["tick"]
		entry["expiry_tick"] = data["tick"] + 10
		list.append(entry)
	data["adjustments"] = list


func test_a_snapshot_without_adjustments_still_loads_through_save() -> void:
	var no_pending: Array[Dictionary] = []
	var data := RatingSnapshot.save(0, {}, 0, no_pending)
	assert_array(data["adjustments"]).is_empty()
	assert_bool(_other.from_snapshot(data)).is_true()
	assert_array(_other.active_adjustments()).is_empty()
