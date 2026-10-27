class_name TestOfferBoardAccept
extends GdUnitTestSuite
## Accepting an offer turns it into a FlightSim contract with the offer's terms,
## in the first occurrence whose preparation window is still ahead; a gate
## clash refuses it and leaves the offer open.
##
## A save holds whole days, so each case loads day 0 with three offers, O0N1 to
## O0N3, at the given departure minutes.

var _board: OfferBoard
var _sim: FlightSim


func before_test() -> void:
	_board = OfferBoard.new()
	_sim = auto_free(FlightSim.new()) as FlightSim


func _load(minutes: Array) -> void:
	var offers := TestOfferBoard.day_records(0, minutes)
	assert_bool(_board.from_snapshot(TestOfferBoard.save_of(offers))).is_true()


func test_accepting_makes_a_contract_with_the_offers_terms() -> void:
	var offers := TestOfferBoard.day_records(0, [600, 720, 840])
	var offer: Dictionary = offers[0]
	offer["airline"] = "Blue Fjord"
	offer["destination"] = "Rome"
	offer["plane_size"] = "medium"
	offer["booked_passengers"] = 41
	offer["fee_per_passenger"] = 30
	assert_bool(_board.from_snapshot(TestOfferBoard.save_of(offers))).is_true()
	assert_bool(_board.accept("O0N1", _sim)).is_true()
	var contract := _sim.contract_of("O0N1")
	assert_bool(contract.is_read_only()).is_true()
	for key in FlightContract.TERM_KEYS:
		assert_that(contract[key]).is_equal(offer[key])
	assert_array(_sim.contract_ids()).is_equal(["O0N1"])


func test_the_contract_starts_in_the_first_occurrence_still_ahead() -> void:
	# 07:00 would begin its preparation at 05:22, before the 06:00 start.
	_load([420, 900, 1200])
	assert_bool(_board.accept("O0N1", _sim)).is_true()
	assert_bool(_board.accept("O0N2", _sim)).is_true()
	assert_int(_sim.contract_of("O0N1")["first_day"]).is_equal(1)
	assert_int(_sim.contract_of("O0N2")["first_day"]).is_equal(0)


func test_an_accepted_offer_leaves_the_open_list_and_cannot_be_taken_twice() -> void:
	_load([600, 720, 840])
	assert_bool(_board.accept("O0N1", _sim)).is_true()
	assert_str(_board.offer_of("O0N1")["status"]).is_equal(OfferBoard.ACCEPTED)
	assert_array(_board.open_offers()).has_size(2)
	assert_bool(_board.accept("O0N1", _sim)).is_false()
	assert_array(_sim.contract_ids()).is_equal(["O0N1"])


func test_a_gate_clash_refuses_the_offer_and_leaves_it_open() -> void:
	# 10:00 and 11:00 both want gate C for 129 minutes.
	_load([600, 660, 1200])
	assert_bool(_board.accept("O0N1", _sim)).is_true()
	assert_bool(_board.accept("O0N2", _sim)).is_false()
	assert_str(_board.offer_of("O0N2")["status"]).is_equal(OfferBoard.OPEN)
	assert_array(_board.open_offers()).has_size(2)
	assert_array(_sim.contract_ids()).is_equal(["O0N1"])


func test_a_refused_offer_can_still_be_declined() -> void:
	_load([600, 660, 1200])
	_board.accept("O0N1", _sim)
	_board.accept("O0N2", _sim)
	assert_bool(_board.decline("O0N2")).is_true()
	assert_array(_board.open_offers()).has_size(1)
	assert_str(_board.open_offers()[0]["id"]).is_equal("O0N3")


func test_declined_and_unknown_offers_cannot_be_accepted() -> void:
	_load([600, 720, 840])
	assert_bool(_board.decline("O0N1")).is_true()
	assert_bool(_board.accept("O0N1", _sim)).is_false()
	assert_bool(_board.accept("NOPE", _sim)).is_false()
	assert_array(_sim.contract_ids()).is_empty()


func test_an_offer_whose_contract_id_is_taken_is_refused_and_stays_open() -> void:
	assert_bool(_sim.accept_contract(TestFlightContracts.terms("O0N1", 900))).is_true()
	_load([600, 720, 840])
	assert_bool(_board.accept("O0N1", _sim)).is_false()
	assert_str(_board.offer_of("O0N1")["status"]).is_equal(OfferBoard.OPEN)


func test_a_generated_offer_accepts_cleanly_when_the_gate_is_free() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var ids := _board.ensure_day(0, rng)
	assert_bool(_board.accept(ids[0], _sim)).is_true()
	assert_array(_sim.contract_ids()).is_equal([ids[0]])


func test_accepted_state_survives_a_save() -> void:
	_load([600, 720, 840])
	_board.accept("O0N1", _sim)
	var loaded := OfferBoard.new()
	assert_bool(loaded.from_snapshot(_board.to_snapshot())).is_true()
	assert_str(loaded.offer_of("O0N1")["status"]).is_equal(OfferBoard.ACCEPTED)
	assert_array(loaded.open_offers()).has_size(2)
