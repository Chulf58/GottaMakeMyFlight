class_name TestOfferBoardLoyalty
extends GdUnitTestSuite
## Bronze (3d +5%), Silver (7d +10%), Gold (12d +15%) loyalty progression and save validation.

const GOLD_BY_DAY_11 := {"Gotta Air": {"days": 12, "last_day": 11}}
const BRONZE_BY_DAY_2 := {"Gotta Air": {"days": 3, "last_day": 2}}

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


func test_only_distinct_days_count_and_the_count_stops_at_gold_days() -> void:
	var board := OfferBoard.new()
	assert_bool(board.note_flown("Sunhop", 2)).is_true()
	assert_bool(board.note_flown("Sunhop", 2)).is_false()
	assert_int(board.loyal_days("Sunhop")).is_equal(1)
	assert_int(board.loyalty_tier("Sunhop")).is_equal(OfferBoard.LOYALTY_TIER_NONE)
	_flown_days(board, "Sunhop", [3, 4])
	assert_int(board.loyal_days("Sunhop")).is_equal(OfferBoard.LOYALTY_BRONZE_DAYS)
	assert_bool(board.is_loyal("Sunhop")).is_true()
	assert_int(board.loyalty_tier("Sunhop")).is_equal(OfferBoard.LOYALTY_TIER_BRONZE)
	_flown_days(board, "Sunhop", [5, 6, 7, 8])
	assert_int(board.loyalty_tier("Sunhop")).is_equal(OfferBoard.LOYALTY_TIER_SILVER)
	_flown_days(board, "Sunhop", [9, 10, 11, 12])
	assert_int(board.loyalty_tier("Sunhop")).is_equal(OfferBoard.LOYALTY_TIER_SILVER)
	assert_bool(board.note_flown("Sunhop", 13)).is_true()
	assert_int(board.loyalty_tier("Sunhop")).is_equal(OfferBoard.LOYALTY_TIER_GOLD)
	assert_bool(board.note_flown("Sunhop", 14)).is_false()
	assert_int(board.loyal_days("Sunhop")).is_equal(OfferBoard.LOYALTY_GOLD_DAYS)
	assert_int(board.loyal_days("Blue Fjord")).is_equal(0)


func test_an_unknown_airline_or_an_earlier_day_is_not_counted() -> void:
	var board := OfferBoard.new()
	assert_bool(board.note_flown("Nowhere Air", 1)).is_false()
	assert_bool(board.note_flown("Sunhop", 5)).is_true()
	assert_bool(board.note_flown("Sunhop", 4)).is_false()
	assert_int(board.loyal_days("Sunhop")).is_equal(1)


func test_a_loyal_airlines_later_offers_pay_tier_bonus() -> void:
	var plain := OfferBoard.new()
	var loyal := OfferBoard.new()
	_flown_days(loyal, "Sunhop", [0, 1, 2, 3, 4, 5, 6])
	var seed_value := _rng.seed
	var before := _offer_from(plain, "Sunhop", 10)
	_rng.seed = seed_value
	var after := _offer_from(loyal, "Sunhop", 10)
	assert_dict(before).is_not_empty()
	assert_str(after["id"]).is_equal(before["id"])
	assert_bool(before["loyal"]).is_false()
	assert_bool(after["loyal"]).is_true()
	assert_int(after["loyalty_tier"]).is_equal(OfferBoard.LOYALTY_TIER_SILVER)
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
	_flown_days(board, "Sunhop", [0, 1, 2, 3, 4, 5, 6])
	_flown_days(board, "Blue Fjord", [1, 3])
	var offer := _offer_from(board, "Sunhop", 10)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(board.to_snapshot()))
	var loaded := OfferBoard.new()
	assert_bool(loaded.from_snapshot(saved)).is_true()
	assert_bool(loaded.is_loyal("Sunhop")).is_true()
	assert_int(loaded.loyalty_tier("Sunhop")).is_equal(OfferBoard.LOYALTY_TIER_SILVER)
	assert_int(loaded.loyal_days("Blue Fjord")).is_equal(2)
	assert_bool(loaded.note_flown("Blue Fjord", 3)).is_false()
	assert_bool(loaded.offer_of(offer["id"])["loyal"]).is_true()
	assert_int(loaded.offer_of(offer["id"])["loyalty_tier"]).is_equal(
		OfferBoard.LOYALTY_TIER_SILVER
	)
	assert_dict(loaded.to_snapshot()).is_equal(board.to_snapshot())


func test_a_bad_saved_loyalty_count_is_refused() -> void:
	var bad: Array = [
		{"Nowhere Air": {"days": 1, "last_day": 0}},
		{"Sunhop": {"days": 0, "last_day": 0}},
		{"Sunhop": {"days": OfferBoard.LOYALTY_GOLD_DAYS + 1, "last_day": 19}},
		{"Sunhop": {"days": 12, "last_day": 4}},
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
	assert_int(OfferBoard.SAVE_VERSION).is_greater(5)


## Small-offer fees run 30..70. Top fare +15% maps 36 -> 41, 37 -> 43, so
## 42 is inside the min..max of the traited fees but no base fee rounds to it.
func test_a_saved_fee_loads_only_when_a_base_fee_maps_to_it() -> void:
	var top := {"up": "top_fare", "down": "rush_crowd", "level": 1}
	var cases: Array = [
		[top, false, 42, false],
		[top, false, 41, true],
		[top, false, 43, true],
		# Plain terms pay 90%: 30 -> 27, ..., 70 -> 63; 64 is not reached.
		[{}, false, 64, false],
		[{}, false, 63, true],
		# Loyal on a neutral offer: 34 -> 37, 35 -> 39, so 38 is a gap; 30 -> 33.
		[TestOfferBoard.NEUTRAL_TRAITS, true, 38, false],
		[TestOfferBoard.NEUTRAL_TRAITS, true, 39, true],
		[TestOfferBoard.NEUTRAL_TRAITS, true, 33, true],
		[TestOfferBoard.NEUTRAL_TRAITS, true, 30, false],
		[TestOfferBoard.NEUTRAL_TRAITS, false, 30, true],
		# Top fare then Loyal: 30 -> 35 -> 39.
		[top, true, 39, true],
		[top, true, 38, false],
	]
	for case in cases:
		var offers := TestOfferBoard.day_records(12, [660, 720, 840])
		offers[0]["traits"] = case[0]
		offers[0]["loyal"] = case[1]
		offers[0]["loyalty_tier"] = OfferBoard.LOYALTY_TIER_SILVER if case[1] else 0
		offers[0]["fee_per_passenger"] = case[2]
		# The other two offers fly for an airline with no count, so only the
		# case's offer depends on the loyalty state.
		for other in [1, 2]:
			offers[other]["airline"] = "Sunhop"
		var data := TestOfferBoard.save_of(offers)
		data["loyalty"] = {"Gotta Air": {"days": 7, "last_day": 11}} if case[1] else {}
		(
			assert_bool(OfferBoard.new().from_snapshot(data))
			. override_failure_message(str(case))
			. is_equal(case[3])
		)


## A loyal mark too early (day 0/1 initial draw) or inconsistent with tier/hub is refused.
func test_a_loyal_mark_the_count_cannot_explain_is_refused() -> void:
	var early_day_1 := TestOfferBoard.day_records(1, [660, 720, 840])
	early_day_1[0]["loyal"] = true
	early_day_1[0]["loyalty_tier"] = OfferBoard.LOYALTY_TIER_BRONZE
	early_day_1[0]["fee_per_passenger"] = OfferTraits.fee_with_bonus(50, 5)
	assert_bool(OfferBoard.new().from_snapshot(TestOfferBoard.save_of(early_day_1))).is_false()

	var hub_without_gold := TestOfferBoard.day_records(12, [660, 720, 840])
	hub_without_gold[0]["loyal"] = true
	hub_without_gold[0]["loyalty_tier"] = OfferBoard.LOYALTY_TIER_SILVER
	hub_without_gold[0]["is_hub"] = true
	hub_without_gold[0]["fee_per_passenger"] = OfferTraits.fee_with_bonus(50, 20)
	var hub_data := TestOfferBoard.save_of(hub_without_gold)
	hub_data["loyalty"] = {"Gotta Air": {"days": 7, "last_day": 11}}
	assert_bool(OfferBoard.new().from_snapshot(hub_data)).is_false()

	var tier_mismatch := TestOfferBoard.day_records(12, [660, 720, 840])
	tier_mismatch[0]["loyal"] = false
	tier_mismatch[0]["loyalty_tier"] = OfferBoard.LOYALTY_TIER_BRONZE
	assert_bool(OfferBoard.new().from_snapshot(TestOfferBoard.save_of(tier_mismatch))).is_false()

	var valid_gold := TestOfferBoard.day_records(12, [660, 720, 840])
	for offer in valid_gold:
		offer["loyal"] = true
		offer["loyalty_tier"] = OfferBoard.LOYALTY_TIER_GOLD
		offer["fee_per_passenger"] = OfferTraits.fee_with_bonus(50, 15)
	var valid_data := TestOfferBoard.save_of(valid_gold)
	valid_data["loyalty"] = GOLD_BY_DAY_11
	assert_bool(OfferBoard.new().from_snapshot(valid_data)).is_true()


## An offer drawn after its airline earned a tier must carry at least that tier.
func test_a_missing_loyal_mark_the_count_requires_is_refused() -> void:
	var day_3 := TestOfferBoard.day_records(3, [660, 720, 840])
	var data := TestOfferBoard.save_of(day_3)
	data["loyalty"] = BRONZE_BY_DAY_2
	assert_bool(OfferBoard.new().from_snapshot(data)).is_false()
	for offer in day_3:
		offer["loyal"] = true
		offer["loyalty_tier"] = OfferBoard.LOYALTY_TIER_BRONZE
		offer["fee_per_passenger"] = OfferTraits.fee_with_bonus(50, 5)
	var day_2 := TestOfferBoard.day_records(2, [600, 720, 840])
	for offer in day_2:
		offer["status"] = OfferBoard.EXPIRED
	data = TestOfferBoard.save_of(day_2 + day_3)
	data["loyalty"] = BRONZE_BY_DAY_2
	assert_bool(OfferBoard.new().from_snapshot(data)).is_true()
	day_3[0]["loyalty_tier"] = OfferBoard.LOYALTY_TIER_GOLD
	day_3[0]["fee_per_passenger"] = OfferTraits.fee_with_bonus(50, 15)
	data = TestOfferBoard.save_of(day_2 + day_3)
	data["loyalty"] = BRONZE_BY_DAY_2
	# A higher historical tier (e.g. after demotion) is permitted; lower than current is refused.
	assert_bool(OfferBoard.new().from_snapshot(data)).is_true()
	var day_12 := TestOfferBoard.day_records(12, [660, 720, 840])
	for offer in day_12:
		offer["loyal"] = true
		offer["loyalty_tier"] = OfferBoard.LOYALTY_TIER_SILVER
		offer["fee_per_passenger"] = OfferTraits.fee_with_bonus(50, 10)
	data = TestOfferBoard.save_of(day_12)
	data["loyalty"] = GOLD_BY_DAY_11
	assert_bool(OfferBoard.new().from_snapshot(data)).is_false()


func test_a_saved_loyal_mark_must_be_a_boolean() -> void:
	var offers := TestOfferBoard.day_records(0, [600, 720, 840])
	offers[0]["loyal"] = 1
	assert_bool(OfferBoard.new().from_snapshot(TestOfferBoard.save_of(offers))).is_false()
	offers[0].erase("loyal")
	assert_bool(OfferBoard.new().from_snapshot(TestOfferBoard.save_of(offers))).is_false()
