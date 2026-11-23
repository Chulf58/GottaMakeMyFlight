class_name TestOfferBoardRunway
extends GdUnitTestSuite
## The runway's size limits what the offer board draws (decision runway-and-
## taxi-technical-design-movement-plan-analytic-bookings-planned-pauses, points
## 1 and 2): a small runway draws no medium or large offer, and the RNG
## advances exactly as it did before, whatever the runway, so a seed replays.

const SEED := 4242
const DAYS := 30
## The sim RNG state after DAYS days of offers drawn from SEED with the board as
## it was before the runway limit existed (measured on the code before this
## change, for every tier), and the hash of the JSON of the offers each tier
## then held. The hashes were measured again when offers gained traits (offer
## save version 4), which change the saved fees, bookings and keys but not the
## RNG state (test_offer_board_traits checks the base draw against a replay),
## and again for save version 5 (the loyal mark, the loyalty count and the
## slice 2 traits in the trait draw), and for save version 6 (Odd hours offers
## depart at 06:00 or 22:00, and trait seed version 3), and for save version 7
## (small-class offers moved to 4..8 passengers and 30..70 fee_per_passenger,
## ruling small-plane-passenger-count-and-fare-balance-4-8-passengers), and for
## save version 8 (the charters array on OfferBoard.to_snapshot(), with offers
## and RNG state unchanged).
const STATE_AFTER := 7055581944236607464
const BEFORE_HASHES := [691078160, 1588298787, 1656781233]


func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	return rng


func _board(tier: int, runway_class: String, rng: RandomNumberGenerator) -> OfferBoard:
	var board := OfferBoard.new()
	for day in DAYS:
		board.ensure_day(day, rng, tier, runway_class)
	return board


func _offers(board: OfferBoard) -> Array[Dictionary]:
	var offers: Array[Dictionary] = []
	for day in DAYS:
		for number in range(1, OfferBoard.OFFERS_PER_DAY + 1):
			offers.append(board.offer_of("O%dN%d" % [day, number]))
	return offers


func test_a_small_runway_draws_only_small_offers_at_every_tier() -> void:
	for tier in range(OfferBoard.MAX_TIER + 1):
		for seed_value in [1, 2, 3, 4242, 99_001, 7_654_321]:
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_value
			var offers := _offers(_board(tier, PlaneClasses.SMALL, rng))
			assert_int(offers.size()).is_equal(DAYS * OfferBoard.OFFERS_PER_DAY)
			for offer in offers:
				(
					assert_str(offer["plane_size"])
					. override_failure_message(
						"tier %d seed %d offer %s" % [tier, seed_value, offer["id"]]
					)
					. is_equal(PlaneClasses.SMALL)
				)
				# Only the starter airlines fly small planes.
				assert_bool(OfferBoard.AIRLINES.has(offer["airline"])).is_true()
				(
					assert_bool(
						PlaneClasses.passengers_fit(PlaneClasses.SMALL, offer["booked_passengers"])
					)
					. is_true()
				)


## Positive control: with a medium runway the same draws do hold medium offers,
## so the small runway's none is the limit, not an empty draw.
func test_a_medium_runway_still_draws_medium_offers() -> void:
	var sizes := {}
	for offer in _offers(_board(1, PlaneClasses.MEDIUM, _rng())):
		sizes[offer["plane_size"]] = true
	print("medium runway, tier 1, sizes drawn: %s" % [sizes.keys()])
	# Tier 1 draws the starter airlines too, which fly small and medium.
	assert_array(sizes.keys()).contains_exactly_in_any_order(
		[PlaneClasses.SMALL, PlaneClasses.MEDIUM]
	)
	sizes.clear()
	for offer in _offers(_board(0, PlaneClasses.MEDIUM, _rng())):
		sizes[offer["plane_size"]] = true
	assert_array(sizes.keys()).contains_exactly_in_any_order(
		[PlaneClasses.SMALL, PlaneClasses.MEDIUM]
	)


## The offer cap (PlaneClasses.max_offer_class) still holds on a large runway.
func test_a_large_runway_offers_what_the_offer_cap_allows() -> void:
	for tier in range(OfferBoard.MAX_TIER + 1):
		for offer in _offers(_board(tier, PlaneClasses.LARGE, _rng())):
			assert_bool(PlaneClasses.is_offered(offer["plane_size"])).is_true()


## The RNG advance does not depend on the runway: every size, every tier, ends
## on the same state as the board did before the limit existed.
func test_the_rng_advance_is_the_same_for_every_runway_size_and_as_before() -> void:
	for tier in range(OfferBoard.MAX_TIER + 1):
		for runway_class in PlaneClasses.ORDER:
			var rng := _rng()
			_board(tier, runway_class, rng)
			(
				assert_int(rng.state)
				. override_failure_message("tier %d, %s runway" % [tier, runway_class])
				. is_equal(STATE_AFTER)
			)
		var plain := _rng()
		var board := OfferBoard.new()
		for day in DAYS:
			board.ensure_day(day, plain, tier)
		assert_int(plain.state).is_equal(STATE_AFTER)


## A runway that takes every offered class changes nothing: the offers are
## byte for byte the ones the board drew before the limit existed.
func test_the_offers_of_a_runway_that_takes_every_class_are_the_old_offers() -> void:
	for tier in range(OfferBoard.MAX_TIER + 1):
		var board := _board(tier, PlaneClasses.LARGE, _rng())
		var hashed := JSON.stringify(board.to_snapshot()).hash()
		assert_int(hashed).override_failure_message("tier %d hash %d" % [tier, hashed]).is_equal(
			BEFORE_HASHES[tier]
		)
		var default_board := OfferBoard.new()
		var rng := _rng()
		for day in DAYS:
			default_board.ensure_day(day, rng, tier)
		assert_dict(default_board.to_snapshot()).is_equal(board.to_snapshot())


## A small runway draws the same airline, destination and departure for the
## starter tier as a medium one: only the plane class is limited.
func test_a_small_runway_changes_only_the_plane_size_and_what_hangs_on_it() -> void:
	var small := _offers(_board(0, PlaneClasses.SMALL, _rng()))
	var medium := _offers(_board(0, PlaneClasses.MEDIUM, _rng()))
	for i in small.size():
		for key in ["id", "airline", "destination", "departure_minute"]:
			assert_that(small[i][key]).is_equal(medium[i][key])


func test_offered_sizes_follow_the_runway() -> void:
	assert_array(OfferBoard.offered_sizes(0, PlaneClasses.SMALL).keys()).is_equal(["small"])
	assert_array(OfferBoard.offered_sizes(0, PlaneClasses.MEDIUM).keys()).is_equal(
		["small", "medium"]
	)
	assert_array(OfferBoard.offered_sizes(1, PlaneClasses.SMALL).keys()).is_empty()
	assert_array(OfferBoard.offered_sizes(1, PlaneClasses.MEDIUM).keys()).is_equal(["medium"])
	assert_dict(OfferBoard.offered_sizes(0)).is_equal(OfferBoard.STARTER_SIZES)


func test_an_unknown_runway_class_is_refused_and_changes_nothing() -> void:
	var rng := _rng()
	var board := OfferBoard.new()
	(
		assert_error(func() -> void: assert_array(board.ensure_day(0, rng, 0, "huge")).is_empty())
		. is_push_error("OfferBoard: runway class 'huge' is not a plane class")
	)
	assert_int(rng.state).is_equal(_rng().state)
	assert_array(board.open_offers()).is_empty()
