class_name TestOfferBoardLoyalty
extends GdUnitTestSuite
## Loyal airline: the board counts, per airline, the days on which one of its
## contracts with the Loyal trait had a flight depart; after OfferTraits.
## LOYAL_DAYS such days that airline's later offers pay 10% more, folded into the
## drawn fee and marked "loyal" on the offer for the card. The count is saved.
## Also the save check on a traited fee: a fee loads only when some base fee of
## the tier maps to it.

## Gotta Air flew its fifth Loyal day on day 5, so its day 6 offers may be loyal.
const LOYAL_BY_DAY_5 := {"Gotta Air": {"days": 5, "last_day": 5}}

var _rng: RandomNumberGenerator


func before_test() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = 4321


## Draws days from `first` on until a day has an offer from `airline`; that offer.
func _offer_from(board: OfferBoard, airline: String, first: int) -> Dictionary:
	for day in range(first, first + 60):
		board.ensure_day(day, _rng)
		for offer in board.open_offers():
			if offer["airline"] == airline:
				return offer
	return {}


func _flown_days(board: OfferBoard, airline: String, days: Array) -> void:
	for day in days:
		board.note_flown(airline, day)


func test_only_distinct_days_count_and_the_count_stops_at_loyal_days() -> void:
	var board := OfferBoard.new()
	assert_bool(board.note_flown("Sunhop", 2)).is_true()
	assert_bool(board.note_flown("Sunhop", 2)).is_false()
	assert_int(board.loyal_days("Sunhop")).is_equal(1)
	_flown_days(board, "Sunhop", [3, 4, 5])
	assert_int(board.loyal_days("Sunhop")).is_equal(4)
	assert_bool(board.is_loyal("Sunhop")).is_false()
	assert_bool(board.note_flown("Sunhop", 6)).is_true()
	assert_bool(board.is_loyal("Sunhop")).is_true()
	assert_bool(board.note_flown("Sunhop", 7)).is_false()
	assert_int(board.loyal_days("Sunhop")).is_equal(OfferTraits.LOYAL_DAYS)
	assert_int(board.loyal_days("Blue Fjord")).is_equal(0)


func test_an_unknown_airline_or_an_earlier_day_is_not_counted() -> void:
	var board := OfferBoard.new()
	assert_bool(board.note_flown("Nowhere Air", 1)).is_false()
	assert_bool(board.note_flown("Sunhop", 5)).is_true()
	assert_bool(board.note_flown("Sunhop", 4)).is_false()
	assert_int(board.loyal_days("Sunhop")).is_equal(1)


func test_a_loyal_airlines_later_offers_pay_ten_percent_more() -> void:
	var plain := OfferBoard.new()
	var loyal := OfferBoard.new()
	_flown_days(loyal, "Sunhop", [0, 1, 2, 3, 4])
	var seed_value := _rng.seed
	var before := _offer_from(plain, "Sunhop", 10)
	_rng.seed = seed_value
	var after := _offer_from(loyal, "Sunhop", 10)
	assert_dict(before).is_not_empty()
	assert_str(after["id"]).is_equal(before["id"])
	assert_bool(before["loyal"]).is_false()
	assert_bool(after["loyal"]).is_true()
	assert_int(after["fee_per_passenger"]).is_equal(
		OfferTraits.loyal_fee_of(before["fee_per_passenger"], true)
	)
	# The other airlines' offers on the same day are unchanged.
	for offer in loyal.open_offers():
		if offer["airline"] != "Sunhop":
			assert_bool(offer["loyal"]).is_false()
			assert_dict(offer).is_equal(plain.offer_of(offer["id"]))


func test_the_count_and_the_loyal_mark_survive_a_json_save() -> void:
	var board := OfferBoard.new()
	_flown_days(board, "Sunhop", [0, 1, 2, 3, 4])
	_flown_days(board, "Blue Fjord", [1, 3])
	var offer := _offer_from(board, "Sunhop", 10)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(board.to_snapshot()))
	var loaded := OfferBoard.new()
	assert_bool(loaded.from_snapshot(saved)).is_true()
	assert_bool(loaded.is_loyal("Sunhop")).is_true()
	assert_int(loaded.loyal_days("Blue Fjord")).is_equal(2)
	assert_bool(loaded.note_flown("Blue Fjord", 3)).is_false()
	assert_bool(loaded.offer_of(offer["id"])["loyal"]).is_true()
	assert_dict(loaded.to_snapshot()).is_equal(board.to_snapshot())


func test_a_bad_saved_loyalty_count_is_refused() -> void:
	var bad: Array = [
		{"Nowhere Air": {"days": 1, "last_day": 0}},
		{"Sunhop": {"days": 0, "last_day": 0}},
		{"Sunhop": {"days": OfferTraits.LOYAL_DAYS + 1, "last_day": 9}},
		{"Sunhop": {"days": 1, "last_day": -1}},
		{"Sunhop": {"days": 1.5, "last_day": 2}},
		{"Sunhop": {"days": 1}},
		{"Sunhop": {"days": 1, "last_day": 2, "extra": 0}},
		{"Sunhop": 3},
		[],
	]
	for loyalty in bad:
		var data := TestOfferBoard.save_of(TestOfferBoard.day_records(0, [600, 720, 840]))
		data["loyalty"] = loyalty
		(
			assert_bool(OfferBoard.new().from_snapshot(data))
			. override_failure_message(str(loyalty))
			. is_false()
		)
	var missing := TestOfferBoard.save_of([])
	missing.erase("loyalty")
	assert_bool(OfferBoard.new().from_snapshot(missing)).is_false()


func test_an_older_save_version_is_refused() -> void:
	var data := TestOfferBoard.save_of([])
	data["save_version"] = 5
	assert_bool(OfferBoard.new().from_snapshot(data)).is_false()
	assert_int(OfferBoard.SAVE_VERSION).is_equal(6)


## Tier 0 fees run 15..35. Top fare +15% maps 15 -> 17, 16 -> 18, 17 -> 20, so
## 19 is inside the min..max of the traited fees but no base fee rounds to it.
func test_a_saved_fee_loads_only_when_a_base_fee_maps_to_it() -> void:
	var top := {"up": "top_fare", "down": "rush_crowd", "level": 1}
	var cases: Array = [
		[top, false, 19, false],
		[top, false, 18, true],
		[top, false, 20, true],
		# Plain terms pay 90%: 15 -> 14, 16 -> 14, 17 -> 15, ...; every fee 14..32 is
		# reached, 33 is not (35 -> 32).
		[{}, false, 33, false],
		[{}, false, 32, true],
		# Loyal on a neutral offer: 24 -> 26, 25 -> 28, so 27 is a gap; 15 -> 17.
		[TestOfferBoard.NEUTRAL_TRAITS, true, 27, false],
		[TestOfferBoard.NEUTRAL_TRAITS, true, 28, true],
		[TestOfferBoard.NEUTRAL_TRAITS, true, 17, true],
		[TestOfferBoard.NEUTRAL_TRAITS, true, 15, false],
		[TestOfferBoard.NEUTRAL_TRAITS, false, 15, true],
		# Top fare then Loyal: 15 -> 17 -> 19.
		[top, true, 19, true],
		[top, true, 18, false],
	]
	for case in cases:
		var offers := TestOfferBoard.day_records(6, [600, 720, 840])
		offers[0]["traits"] = case[0]
		offers[0]["loyal"] = case[1]
		offers[0]["fee_per_passenger"] = case[2]
		# The other two offers fly for an airline with no count, so only the
		# case's offer depends on the loyalty state.
		for other in [1, 2]:
			offers[other]["airline"] = "Sunhop"
		var data := TestOfferBoard.save_of(offers)
		data["loyalty"] = LOYAL_BY_DAY_5 if case[1] else {}
		(
			assert_bool(OfferBoard.new().from_snapshot(data))
			. override_failure_message(str(case))
			. is_equal(case[3])
		)


## A loyal mark is possible only when the airline's saved count is full and the
## offer was drawn after the last counted day; a count's last day is at least
## its days - 1.
func test_a_loyal_mark_the_count_cannot_explain_is_refused() -> void:
	var cases: Array = [
		[{}, 6, false],
		[{"Gotta Air": {"days": 4, "last_day": 5}}, 6, false],
		[LOYAL_BY_DAY_5, 5, false],
		[LOYAL_BY_DAY_5, 6, true],
		[{"Gotta Air": {"days": 5, "last_day": 3}}, 6, false],
		[{"Gotta Air": {"days": 5, "last_day": 4}}, 6, true],
	]
	for case in cases:
		var offers := TestOfferBoard.day_records(case[1], [600, 720, 840])
		for offer in offers:
			offer["loyal"] = true
			offer["fee_per_passenger"] = OfferTraits.loyal_fee_of(25, true)
		var data := TestOfferBoard.save_of(offers)
		data["loyalty"] = case[0]
		(
			assert_bool(OfferBoard.new().from_snapshot(data))
			. override_failure_message(str(case))
			. is_equal(case[2])
		)


## The inverse: an offer drawn after its airline's count was full must carry the
## loyal mark, so a day 6 offer from an airline loyal by day 5 saved without it
## is refused; its day 5 offers, drawn before the fifth day flew, are not loyal.
func test_a_missing_loyal_mark_the_count_requires_is_refused() -> void:
	var day_6 := TestOfferBoard.day_records(6, [600, 720, 840])
	var data := TestOfferBoard.save_of(day_6)
	data["loyalty"] = LOYAL_BY_DAY_5
	assert_bool(OfferBoard.new().from_snapshot(data)).is_false()
	for offer in day_6:
		offer["loyal"] = true
		offer["fee_per_passenger"] = OfferTraits.loyal_fee_of(25, true)
	var day_5 := TestOfferBoard.day_records(5, [600, 720, 840])
	for offer in day_5:
		offer["status"] = OfferBoard.EXPIRED
	data = TestOfferBoard.save_of(day_5 + day_6)
	data["loyalty"] = LOYAL_BY_DAY_5
	assert_bool(OfferBoard.new().from_snapshot(data)).is_true()
	day_5[0]["loyal"] = true
	day_5[0]["fee_per_passenger"] = OfferTraits.loyal_fee_of(25, true)
	data = TestOfferBoard.save_of(day_5 + day_6)
	data["loyalty"] = LOYAL_BY_DAY_5
	assert_bool(OfferBoard.new().from_snapshot(data)).is_false()


func test_a_saved_loyal_mark_must_be_a_boolean() -> void:
	var offers := TestOfferBoard.day_records(0, [600, 720, 840])
	offers[0]["loyal"] = 1
	assert_bool(OfferBoard.new().from_snapshot(TestOfferBoard.save_of(offers))).is_false()
	offers[0].erase("loyal")
	assert_bool(OfferBoard.new().from_snapshot(TestOfferBoard.save_of(offers))).is_false()
