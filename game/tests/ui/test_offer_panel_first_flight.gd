class_name TestOfferPanelFirstFlight
extends GdUnitTestSuite
## An offer's card says "first flight tomorrow" exactly when the sim would not
## fly today's slot: FlightTimetable.first_day is after today. The note follows
## the clock and appears only while the airport is open (a contract accepted
## while it is closed starts at the opening).

const NOON := 12 * 60

var _port: SubViewport
var _desk: OfferDesk
var _sim: FlightSim
var _panel: OfferPanel


func before_test() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_desk = OfferDesk.new()
	_sim = FlightSim.new()
	_port.add_child(_desk)
	_port.add_child(_sim)
	# 10:00 has passed at noon, 20:00 has not.
	_load(TestOfferBoard.day_records(0, [600, 1200, 1260]))
	_panel = OfferPanel.new()
	_panel.desk = _desk
	_panel.flights = _sim
	_port.add_child(_panel)


func _load(offers: Array) -> void:
	assert_bool(_desk.board.from_snapshot(TestOfferBoard.save_of(offers))).is_true()


func after_test() -> void:
	_port.free()


func _at(minute: int) -> void:
	_sim.tick = GameCalendar.tick_at(0, minute)
	_sim.open_airport()
	_panel.open()


func test_a_slot_that_has_passed_says_the_first_flight_is_tomorrow() -> void:
	_at(NOON)
	assert_str(_panel.card_text("O0N1")).contains("Departs 10:00 daily, first flight tomorrow")


func test_a_slot_still_ahead_says_nothing_extra() -> void:
	_at(NOON)
	assert_str(_panel.card_text("O0N2")).contains("Departs 20:00 daily   Gate")
	assert_str(_panel.card_text("O0N2")).not_contains("first flight")


func test_the_note_agrees_with_the_day_the_sim_flies_the_accepted_offer() -> void:
	_at(NOON)
	for id in ["O0N1", "O0N2"]:
		var noted := _panel.card_text(id).contains("first flight tomorrow")
		var terms := OfferBoard.terms_of(_desk.board.offer_of(id))
		assert_bool(_sim.accept_contract(terms)).is_true()
		var first_day: int = _sim.contract_of(id)["first_day"]
		assert_bool(noted).is_equal(first_day > 0)
	assert_int(_sim.contract_of("O0N1")["first_day"]).is_equal(1)
	assert_int(_sim.contract_of("O0N2")["first_day"]).is_equal(0)


func test_a_slot_whose_preparation_has_started_counts_as_passed() -> void:
	# Departure 20:00; the flight's first state comes departure_offset earlier.
	var offset := FlightTimetable.departure_offset()
	_sim.tick = GameCalendar.tick_at(0, 1200) - offset + 1
	_sim.open_airport()
	_panel.open()
	assert_str(_panel.card_text("O0N2")).contains("first flight tomorrow")
	_sim.tick = GameCalendar.tick_at(0, 1200) - offset
	_panel.close()
	_panel.open()
	assert_str(_panel.card_text("O0N2")).not_contains("first flight")


func test_the_note_appears_when_the_clock_passes_the_slot_while_open() -> void:
	_at(NOON)
	assert_str(_panel.card_text("O0N2")).not_contains("first flight")
	_sim.tick = GameCalendar.tick_at(0, 21 * 60)
	await get_tree().process_frame
	assert_str(_panel.card_text("O0N2")).contains("Departs 20:00 daily, first flight tomorrow")


func test_no_note_while_the_airport_is_closed() -> void:
	_sim.tick = GameCalendar.tick_at(0, NOON)
	_panel.open()
	assert_str(_panel.card_text("O0N1")).not_contains("first flight")


func test_a_slot_two_days_out_names_the_day() -> void:
	var offer := TestOfferBoard.record("O0N9", 0, 30)
	var now := GameCalendar.tick_at(0, 23 * 60 + 58)
	assert_int(FlightTimetable.first_day(offer, now) - GameCalendar.day_of(now)).is_equal(2)
	assert_str(OfferPanel.first_flight_note(offer, now)).is_equal("first flight on Day 3")


func test_card_lines_without_a_note_are_unchanged() -> void:
	var offer := TestOfferBoard.record("O0N9", 0, 600)
	assert_str(OfferPanel.card_lines(offer)[1]).is_equal(
		"Departs 10:00 daily   Gate C   Small plane"
	)
	assert_str(OfferPanel.card_lines(offer, "first flight tomorrow")[1]).is_equal(
		"Departs 10:00 daily, first flight tomorrow   Gate C   Small plane"
	)
