class_name TestOfferBoard
extends GdUnitTestSuite
## The daily offer board: offers drawn from the sim RNG once per day, declined
## offers removed, and a save that keeps offers and dispositions so loading
## never re-rolls.

var _board: OfferBoard
var _rng: RandomNumberGenerator
var _changes := 0


func before_test() -> void:
	_changes = 0
	_board = OfferBoard.new()
	_board.changed.connect(func() -> void: _changes += 1)
	_rng = RandomNumberGenerator.new()
	_rng.seed = 1234


## A saved offer with the fixed terms the tests need.
static func record(id: String, day: int, minute: int, status := OfferBoard.OPEN) -> Dictionary:
	return {
		"id": id,
		"day": day,
		"airline": "Gotta Air",
		"destination": "Oslo",
		"departure_minute": minute,
		"gate": "C",
		"plane_size": "small",
		"booked_passengers": 20,
		"fee_per_passenger": 25,
		"status": status,
	}


## The whole offer set of `day`, ids O<day>N1.., one departure minute each.
static func day_records(day: int, minutes: Array) -> Array:
	var offers := []
	for i in minutes.size():
		offers.append(record("O%dN%d" % [day, i + 1], day, minutes[i]))
	return offers


static func save_of(offers: Array) -> Dictionary:
	return {"save_version": OfferBoard.SAVE_VERSION, "offers": offers}


func test_a_day_draws_the_daily_count_of_valid_starter_offers() -> void:
	for seed_value in [1, 2, 3, 99, 123456]:
		var board := OfferBoard.new()
		_rng.seed = seed_value
		var ids := board.ensure_day(3, _rng)
		assert_int(ids.size()).is_equal(OfferBoard.OFFERS_PER_DAY)
		assert_array(board.open_offers()).has_size(OfferBoard.OFFERS_PER_DAY)
		for offer in board.open_offers():
			var terms := OfferBoard.terms_of(offer)
			assert_str(FlightContract.problem(terms, FlightContract.TERM_KEYS)).is_empty()
			assert_int(offer["day"]).is_equal(3)
			assert_str(offer["status"]).is_equal(OfferBoard.OPEN)
			assert_bool(OfferBoard.AIRLINES.has(offer["airline"])).is_true()
			assert_bool(OfferBoard.DESTINATIONS.has(offer["destination"])).is_true()
			assert_bool(OfferBoard.STARTER_SIZES.has(offer["plane_size"])).is_true()
			assert_bool(FlightSim.GATES.has(offer["gate"])).is_true()
			assert_int(offer["departure_minute"]).is_between(
				OfferBoard.DEPARTURE_FIRST_MINUTE, OfferBoard.DEPARTURE_LAST_MINUTE
			)
			var slot: int = offer["departure_minute"] - OfferBoard.DEPARTURE_FIRST_MINUTE
			assert_int(slot % OfferBoard.DEPARTURE_STEP).is_equal(0)
			var booked_range: Array = OfferBoard.STARTER_SIZES[offer["plane_size"]]
			assert_int(offer["booked_passengers"]).is_between(booked_range[0], booked_range[1])
			assert_int(offer["fee_per_passenger"]).is_between(
				OfferBoard.FEE_MIN, OfferBoard.FEE_MAX
			)


func test_offer_ids_are_unique_and_name_their_day() -> void:
	var seen := {}
	for day in 4:
		for id in _board.ensure_day(day, _rng):
			assert_bool(seen.has(id)).is_false()
			seen[id] = true
			assert_int(_board.offer_of(id)["day"]).is_equal(day)
	assert_int(seen.size()).is_equal(4 * OfferBoard.OFFERS_PER_DAY)


func test_the_same_seed_gives_the_same_offers_and_the_rng_advances() -> void:
	var other := OfferBoard.new()
	var other_rng := RandomNumberGenerator.new()
	other_rng.seed = 1234
	var before_state := _rng.state
	_board.ensure_day(5, _rng)
	other.ensure_day(5, other_rng)
	assert_array(_board.open_offers()).is_equal(other.open_offers())
	assert_int(_rng.state).is_not_equal(before_state)
	assert_int(_rng.state).is_equal(other_rng.state)


func test_a_day_already_generated_never_draws_again() -> void:
	var first := _board.ensure_day(2, _rng)
	var offers := _board.open_offers()
	var state := _rng.state
	assert_array(_board.ensure_day(2, _rng)).is_empty()
	assert_int(_rng.state).is_equal(state)
	assert_array(_board.open_offers()).is_equal(offers)
	assert_array(first).has_size(OfferBoard.OFFERS_PER_DAY)


func test_a_day_with_every_offer_declined_is_not_rolled_again() -> void:
	for id in _board.ensure_day(0, _rng):
		assert_bool(_board.decline(id)).is_true()
	var state := _rng.state
	assert_array(_board.ensure_day(0, _rng)).is_empty()
	assert_int(_rng.state).is_equal(state)
	assert_array(_board.open_offers()).is_empty()


func test_a_day_outside_the_calendar_range_is_refused_without_drawing() -> void:
	var state := _rng.state
	assert_array(_board.ensure_day(-1, _rng)).is_empty()
	assert_array(_board.ensure_day(FlightContract.MAX_DAY + 1, _rng)).is_empty()
	assert_int(_rng.state).is_equal(state)
	assert_array(_board.open_offers()).is_empty()


func test_decline_removes_the_offer_from_the_open_list() -> void:
	var ids := _board.ensure_day(0, _rng)
	assert_bool(_board.decline(ids[1])).is_true()
	assert_str(_board.offer_of(ids[1])["status"]).is_equal(OfferBoard.DECLINED)
	var open_ids: Array[String] = []
	for offer in _board.open_offers():
		open_ids.append(offer["id"])
	assert_array(open_ids).is_equal([ids[0], ids[2]])


func test_declining_an_unknown_or_settled_offer_is_refused() -> void:
	var ids := _board.ensure_day(0, _rng)
	assert_bool(_board.decline("NOPE")).is_false()
	assert_bool(_board.decline(ids[0])).is_true()
	assert_bool(_board.decline(ids[0])).is_false()


func test_changed_fires_when_offers_arrive_or_one_is_declined_only() -> void:
	var ids := _board.ensure_day(0, _rng)
	assert_int(_changes).is_equal(1)
	_board.ensure_day(0, _rng)
	_board.decline("NOPE")
	assert_int(_changes).is_equal(1)
	_board.decline(ids[0])
	assert_int(_changes).is_equal(2)


func test_a_save_through_json_restores_offers_and_dispositions() -> void:
	var ids := _board.ensure_day(0, _rng)
	_board.ensure_day(1, _rng)
	_board.decline(ids[0])
	var parsed: Variant = JSON.parse_string(JSON.stringify(_board.to_snapshot()))
	var loaded := OfferBoard.new()
	assert_bool(loaded.from_snapshot(parsed)).is_true()
	assert_array(loaded.open_offers()).is_equal(_board.open_offers())
	assert_str(loaded.offer_of(ids[0])["status"]).is_equal(OfferBoard.DECLINED)
	assert_dict(loaded.to_snapshot()).is_equal(_board.to_snapshot())


func test_loading_never_rerolls_the_days_it_saved() -> void:
	_board.ensure_day(0, _rng)
	var loaded := OfferBoard.new()
	assert_bool(loaded.from_snapshot(_board.to_snapshot())).is_true()
	var state := _rng.state
	assert_array(loaded.ensure_day(0, _rng)).is_empty()
	assert_int(_rng.state).is_equal(state)
	assert_array(loaded.ensure_day(1, _rng)).has_size(OfferBoard.OFFERS_PER_DAY)


func test_a_restored_rng_gives_the_offers_an_uninterrupted_run_would() -> void:
	_board.ensure_day(0, _rng)
	var loaded := OfferBoard.new()
	loaded.from_snapshot(_board.to_snapshot())
	var restored := RandomNumberGenerator.new()
	restored.seed = _rng.seed
	restored.state = _rng.state
	_board.ensure_day(1, _rng)
	loaded.ensure_day(1, restored)
	assert_array(loaded.open_offers()).is_equal(_board.open_offers())


## A save whose day 0 is the valid draw with `key` set to `value` on its first offer.
static func with_first(key: String, value: Variant) -> Dictionary:
	var offers := day_records(0, [600, 720, 840])
	offers[0][key] = value
	return save_of(offers)


func test_a_bad_save_is_refused_whole_and_leaves_the_board_alone() -> void:
	_board.ensure_day(0, _rng)
	var before := _board.to_snapshot()
	var cases: Array = [
		with_first("colour", "red"),
		with_first("status", "maybe"),
		with_first("plane_size", "jumbo"),
		with_first("day", -1),
		with_first("id", "O0N2"),
		save_of(["not a record"]),
		{"save_version": OfferBoard.SAVE_VERSION + 1, "offers": []},
		{"save_version": OfferBoard.SAVE_VERSION},
		{"offers": []},
		{"save_version": OfferBoard.SAVE_VERSION, "offers": [], "extra": 1},
	]
	for bad in cases:
		assert_bool(_board.from_snapshot(bad)).override_failure_message(str(bad)).is_false()
		assert_dict(_board.to_snapshot()).is_equal(before)


## Each of these passes FlightContract validation but is not something the
## board could have drawn.
func test_terms_no_draw_could_produce_are_refused() -> void:
	var cases: Array = [
		["airline", "Mystery Air"],
		["destination", "Atlantis"],
		["gate", "Z"],
		["plane_size", "large"],
		["booked_passengers", OfferBoard.STARTER_SIZES["small"][0] - 1],
		["booked_passengers", OfferBoard.STARTER_SIZES["small"][1] + 1],
		["departure_minute", OfferBoard.DEPARTURE_FIRST_MINUTE + 1],
		["departure_minute", OfferBoard.DEPARTURE_FIRST_MINUTE - OfferBoard.DEPARTURE_STEP],
		["departure_minute", OfferBoard.DEPARTURE_LAST_MINUTE + OfferBoard.DEPARTURE_STEP],
		["fee_per_passenger", OfferBoard.FEE_MIN - 1],
		["fee_per_passenger", OfferBoard.FEE_MAX + 1],
	]
	var before := _board.to_snapshot()
	for case in cases:
		var bad := with_first(case[0], case[1])
		var terms := OfferBoard.terms_of(bad["offers"][0])
		assert_str(FlightContract.problem(terms, FlightContract.TERM_KEYS)).is_empty()
		assert_bool(_board.from_snapshot(bad)).override_failure_message(str(case)).is_false()
		assert_dict(_board.to_snapshot()).is_equal(before)


func test_the_extremes_of_every_draw_range_load() -> void:
	var small: Array = OfferBoard.STARTER_SIZES["small"]
	var low := with_first("booked_passengers", small[0])
	var high := with_first("booked_passengers", small[1])
	var early := with_first("departure_minute", OfferBoard.DEPARTURE_FIRST_MINUTE)
	var late := with_first("departure_minute", OfferBoard.DEPARTURE_LAST_MINUTE)
	var cheap := with_first("fee_per_passenger", OfferBoard.FEE_MIN)
	var dear := with_first("fee_per_passenger", OfferBoard.FEE_MAX)
	for good in [low, high, early, late, cheap, dear]:
		var loaded := OfferBoard.new().from_snapshot(good)
		assert_bool(loaded).override_failure_message(str(good)).is_true()


## A day with offers is never drawn again, so a save holding only part of a day
## would leave it short for good: every day must be the whole canonical set.
func test_a_partial_or_oversized_day_is_refused() -> void:
	_board.ensure_day(0, _rng)
	var before := _board.to_snapshot()
	var missing := day_records(0, [600, 720, 840])
	missing.remove_at(1)
	var extra := day_records(0, [600, 720, 840])
	extra.append(record("O0N4", 0, 900))
	var renamed := day_records(0, [600, 720, 840])
	renamed[2]["id"] = "A1"
	var second_day_short := day_records(0, [600, 720, 840]) + day_records(1, [600, 720, 840])
	second_day_short.pop_back()
	for offers in [missing, extra, renamed, second_day_short]:
		var loaded := _board.from_snapshot(save_of(offers))
		assert_bool(loaded).override_failure_message(str(offers)).is_false()
		assert_dict(_board.to_snapshot()).is_equal(before)


func test_a_refused_partial_day_leaves_ensure_day_and_the_rng_alone() -> void:
	_board.ensure_day(0, _rng)
	var offers: Array = _board.to_snapshot()["offers"]
	offers.remove_at(0)
	assert_bool(_board.from_snapshot(save_of(offers))).is_false()
	assert_array(_board.open_offers()).has_size(OfferBoard.OFFERS_PER_DAY)
	var state := _rng.state
	assert_array(_board.ensure_day(0, _rng)).is_empty()
	assert_int(_rng.state).is_equal(state)
	var fresh := OfferBoard.new()
	assert_bool(fresh.from_snapshot(save_of(offers))).is_false()
	assert_array(fresh.ensure_day(0, _rng)).has_size(OfferBoard.OFFERS_PER_DAY)


func test_whole_days_load_in_any_order() -> void:
	var offers := day_records(0, [600, 720, 840])
	offers.reverse()
	assert_bool(_board.from_snapshot(save_of(offers))).is_true()
	assert_array(_board.ensure_day(0, _rng)).is_empty()


func test_an_empty_save_loads_an_empty_board() -> void:
	_board.ensure_day(0, _rng)
	assert_bool(_board.from_snapshot(save_of([]))).is_true()
	assert_array(_board.open_offers()).is_empty()
	assert_array(_board.ensure_day(0, _rng)).has_size(OfferBoard.OFFERS_PER_DAY)
