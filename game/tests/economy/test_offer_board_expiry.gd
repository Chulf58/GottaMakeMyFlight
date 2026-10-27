class_name TestOfferBoardExpiry
extends GdUnitTestSuite
## Decision airline-offers-expire-at-the-end-of-their-day: an open offer from an
## earlier day expires when a later day starts, keeps its "expired" status in the
## save, and is never redrawn. Offers that were answered keep their answer.

var _board: OfferBoard
var _rng: RandomNumberGenerator
var _changes := 0


func before_test() -> void:
	_changes = 0
	_board = OfferBoard.new()
	_board.changed.connect(func() -> void: _changes += 1)
	_rng = RandomNumberGenerator.new()
	_rng.seed = 99


func test_a_new_day_expires_the_open_offers_of_the_day_before() -> void:
	var day0 := _board.ensure_day(0, _rng)
	var day1 := _board.ensure_day(1, _rng)
	for id in day0:
		assert_str(_board.offer_of(id)["status"]).is_equal(OfferBoard.EXPIRED)
	(
		assert_array(_board.open_offers().map(func(o: Dictionary) -> String: return o["id"]))
		. is_equal(day1)
	)


func test_only_open_offers_expire() -> void:
	var day0 := _board.ensure_day(0, _rng)
	var sim := auto_free(FlightSim.new()) as FlightSim
	_board.decline(day0[0])
	assert_bool(_board.accept(day0[1], sim)).is_true()
	_board.ensure_day(1, _rng)
	assert_str(_board.offer_of(day0[0])["status"]).is_equal(OfferBoard.DECLINED)
	assert_str(_board.offer_of(day0[1])["status"]).is_equal(OfferBoard.ACCEPTED)
	assert_str(_board.offer_of(day0[2])["status"]).is_equal(OfferBoard.EXPIRED)


func test_the_same_day_expires_nothing() -> void:
	var day0 := _board.ensure_day(0, _rng)
	_board.ensure_day(0, _rng)
	assert_array(_board.open_offers()).has_size(day0.size())


func test_an_expired_offer_cannot_be_accepted_or_declined() -> void:
	var day0 := _board.ensure_day(0, _rng)
	_board.ensure_day(1, _rng)
	var sim := auto_free(FlightSim.new()) as FlightSim
	assert_bool(_board.accept(day0[0], sim)).is_false()
	assert_bool(_board.decline(day0[0])).is_false()
	assert_array(sim.contract_ids()).is_empty()
	assert_str(_board.offer_of(day0[0])["status"]).is_equal(OfferBoard.EXPIRED)


func test_an_expired_day_is_never_redrawn() -> void:
	_board.ensure_day(0, _rng)
	_board.ensure_day(1, _rng)
	var state := _rng.state
	assert_array(_board.ensure_day(0, _rng)).is_empty()
	assert_array(_board.ensure_day(1, _rng)).is_empty()
	assert_int(_rng.state).is_equal(state)
	assert_array(_board.open_offers()).has_size(OfferBoard.OFFERS_PER_DAY)


func test_skipping_days_expires_every_earlier_open_offer() -> void:
	_board.ensure_day(0, _rng)
	_board.ensure_day(1, _rng)
	_board.ensure_day(4, _rng)
	for offer in _board.open_offers():
		assert_int(offer["day"]).is_equal(4)


func test_expiry_fires_changed_once_together_with_the_new_draw() -> void:
	_board.ensure_day(0, _rng)
	assert_int(_changes).is_equal(1)
	_board.ensure_day(1, _rng)
	assert_int(_changes).is_equal(2)


## A day's records with every offer set to `status`.
func _day_with(day: int, status: String) -> Array:
	var offers := TestOfferBoard.day_records(day, [600, 720, 840])
	for offer in offers:
		offer["status"] = status
	return offers


func test_expiry_alone_fires_changed_when_the_new_day_was_already_drawn() -> void:
	# Out-of-order calls through the public API: day 0 is drawn after day 1,
	# so it is open when day 1 is asked for again.
	var day1 := _board.ensure_day(1, _rng)
	var day0 := _board.ensure_day(0, _rng)
	assert_int(_board.open_offers().size()).is_equal(2 * OfferBoard.OFFERS_PER_DAY)
	_changes = 0
	var state := _rng.state
	assert_array(_board.ensure_day(1, _rng)).is_empty()
	assert_int(_changes).is_equal(1)
	assert_int(_rng.state).is_equal(state)
	for id in day0:
		assert_str(_board.offer_of(id)["status"]).is_equal(OfferBoard.EXPIRED)
	for id in day1:
		assert_str(_board.offer_of(id)["status"]).is_equal(OfferBoard.OPEN)
	_board.ensure_day(1, _rng)
	assert_int(_changes).is_equal(1)


func test_a_save_with_open_offers_from_before_its_latest_day_is_refused() -> void:
	var offers := _day_with(0, OfferBoard.OPEN)
	offers.append_array(_day_with(1, OfferBoard.OPEN))
	assert_bool(_board.from_snapshot(TestOfferBoard.save_of(offers))).is_false()
	assert_array(_board.open_offers()).is_empty()
	# One still-open offer on an earlier day is enough.
	offers = _day_with(0, OfferBoard.EXPIRED)
	offers[2]["status"] = OfferBoard.OPEN
	offers.append_array(_day_with(1, OfferBoard.OPEN))
	assert_bool(_board.from_snapshot(TestOfferBoard.save_of(offers))).is_false()


func test_a_save_whose_latest_day_is_expired_is_refused() -> void:
	assert_bool(_board.from_snapshot(TestOfferBoard.save_of(_day_with(0, "expired")))).is_false()
	var offers := _day_with(0, OfferBoard.EXPIRED)
	offers.append_array(_day_with(1, OfferBoard.OPEN))
	offers[3]["status"] = OfferBoard.EXPIRED
	assert_bool(_board.from_snapshot(TestOfferBoard.save_of(offers))).is_false()
	assert_array(_board.open_offers()).is_empty()


func test_a_save_a_run_could_have_made_loads() -> void:
	var offers := _day_with(0, OfferBoard.EXPIRED)
	offers[0]["status"] = OfferBoard.DECLINED
	offers[1]["status"] = OfferBoard.ACCEPTED
	offers.append_array(_day_with(1, OfferBoard.OPEN))
	assert_bool(_board.from_snapshot(TestOfferBoard.save_of(offers))).is_true()
	assert_array(_board.open_offers()).has_size(OfferBoard.OFFERS_PER_DAY)


func test_expired_status_survives_a_save_through_json() -> void:
	var day0 := _board.ensure_day(0, _rng)
	_board.ensure_day(1, _rng)
	var parsed: Variant = JSON.parse_string(JSON.stringify(_board.to_snapshot()))
	var loaded := OfferBoard.new()
	assert_bool(loaded.from_snapshot(parsed)).is_true()
	for id in day0:
		assert_str(loaded.offer_of(id)["status"]).is_equal(OfferBoard.EXPIRED)
	assert_array(loaded.open_offers()).is_equal(_board.open_offers())
	assert_dict(loaded.to_snapshot()).is_equal(_board.to_snapshot())
	assert_array(loaded.ensure_day(0, _rng)).is_empty()
	assert_array(loaded.ensure_day(1, _rng)).is_empty()


func test_a_save_with_an_unknown_status_is_still_refused() -> void:
	var offers := TestOfferBoard.day_records(0, [600, 720, 840])
	offers[0]["status"] = "lapsed"
	assert_bool(_board.from_snapshot(TestOfferBoard.save_of(offers))).is_false()
	assert_array(_board.open_offers()).is_empty()
