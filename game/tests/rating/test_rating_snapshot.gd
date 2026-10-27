class_name TestRatingSnapshot
extends GdUnitTestSuite
## The save snapshot round-trips through JSON and refuses bad input whole.

var _rating: AirportRating
var _other: AirportRating


func before_test() -> void:
	_rating = auto_free(AirportRating.new()) as AirportRating
	_other = auto_free(AirportRating.new()) as AirportRating


## Two days of data, a low streak and one flight waiting for its no-shows.
func _filled() -> void:
	var day0 := GameCalendar.tick_at(0, 12 * 60)
	for i in 6:
		_rating.record_passenger(day0, false, 0)
	_rating.on_tick(GameCalendar.day_start(1))
	for i in 4:
		_rating.record_passenger(GameCalendar.tick_at(1, 9 * 60), true, 70)
	_rating.note_doors_closed("GMF101", GameCalendar.tick_at(1, 10 * 60))
	_rating.on_tick(GameCalendar.tick_at(1, 10 * 60))


func _json() -> Dictionary:
	return JSON.parse_string(JSON.stringify(_rating.to_snapshot()))


func _text(rating: AirportRating) -> String:
	return JSON.stringify(rating.to_snapshot())


func test_a_json_round_trip_restores_the_same_rating() -> void:
	_filled()
	assert_bool(_other.from_snapshot(_json())).is_true()
	assert_float(_other.stars()).is_equal(_rating.stars())
	assert_int(_other.low_days()).is_equal(1)
	assert_int(_other.current_day()).is_equal(1)
	assert_dict(_other.parts()).is_equal(_rating.parts())
	assert_str(_text(_other)).is_equal(_text(_rating))


func test_a_restored_rating_goes_on_exactly_like_the_original() -> void:
	_filled()
	assert_bool(_other.from_snapshot(_json())).is_true()
	for rating in [_rating, _other]:
		rating.on_tick(GameCalendar.day_start(2))
		rating.on_tick(GameCalendar.day_start(3))
	assert_str(_text(_other)).is_equal(_text(_rating))
	assert_int(_other.low_days()).is_equal(_rating.low_days())


func test_a_fresh_rating_round_trips() -> void:
	assert_bool(_other.from_snapshot(_json())).is_true()
	assert_bool(_other.has_data()).is_false()


func test_bad_snapshots_are_refused_and_leave_the_rating_unchanged() -> void:
	_filled()
	var good := _json()
	var max_count := RatingFormula.MAX_DAY_COUNT
	var cases := {
		"unknown key": func(d): d["extra"] = 1,
		"missing key": func(d): d.erase("days"),
		"old version": func(d): d["save_version"] = 0,
		"fractional version": func(d): d["save_version"] = 1.5,
		"string tick": func(d): d["tick"] = "5",
		"fractional tick": func(d): d["tick"] = 100.5,
		"negative tick": func(d): d["tick"] = -1,
		"days not an array": func(d): d["days"] = {},
		"day entry key missing": func(d): d["days"][0].erase("made"),
		"day entry extra key": func(d): d["days"][0]["x"] = 1,
		"negative count": func(d): d["days"][0]["missed"] = -1,
		"fractional count": func(d): d["days"][0]["made"] = 1.5,
		"huge count": func(d): d["days"][0]["missed"] = max_count + 1,
		"mood above the maximum": func(d): d["days"][1]["mood_sum"] = 4 * 100 + 1,
		"mood with nobody made": func(d): d["days"][0]["mood_sum"] = 1,
		"day outside the window": func(d): d["days"][0]["day"] = -5,
		"day in the future": func(d): d["days"][1]["day"] = 2,
		"duplicate day": func(d): d["days"][0]["day"] = d["days"][1]["day"],
		"days out of order": func(d): d["days"].reverse(),
		"low days above the days played": func(d): d["low_days"] = 2,
		"negative low days": func(d): d["low_days"] = -1,
		"pending not an array": func(d): d["pending"] = "GMF101",
		"pending entry malformed": func(d): d["pending"][0] = "GMF101",
		"pending empty flight id": func(d): d["pending"][0]["flight"] = "",
		"pending after the saved tick": func(d): d["pending"][0]["tick"] = d["tick"] + 1,
		"duplicate pending flight": func(d): d["pending"].append(d["pending"][0].duplicate()),
	}
	var before := _text(_other)
	for name in cases:
		var data: Dictionary = good.duplicate(true)
		cases[name].call(data)
		assert_bool(_other.from_snapshot(data)).override_failure_message(name).is_false()
		assert_str(_text(_other)).override_failure_message(name).is_equal(before)
	assert_bool(_other.from_snapshot(good)).is_true()
