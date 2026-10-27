class_name TestOfferPanel
extends GdUnitTestSuite
## OfferPanel: a button with the open offer count, and a cream card per open
## offer (airline, destination, departure, gate, size, booked passengers, fee
## per passenger) with Accept and Decline wired to the board and FlightSim. A
## refused accept shows FlightSim.accept_problem's reason and leaves the offer.

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
	# 10:00 and 11:00 want gate C together, so O0N1 and O0N2 clash.
	_load(TestOfferBoard.day_records(0, [600, 660, 1200]))
	_panel = OfferPanel.new()
	_panel.desk = _desk
	_panel.flights = _sim
	_port.add_child(_panel)


func after_test() -> void:
	_port.free()


func _load(offers: Array) -> void:
	assert_bool(_desk.board.from_snapshot(TestOfferBoard.save_of(offers))).is_true()


func test_the_button_counts_the_open_offers_and_the_sheet_starts_closed() -> void:
	assert_str(_panel.toggle_button().text).is_equal("Offers (3)")
	assert_bool(_panel.is_open()).is_false()
	_desk.board.decline("O0N3")
	assert_str(_panel.toggle_button().text).is_equal("Offers (2)")


func test_the_button_opens_and_closes_the_sheet() -> void:
	_panel.toggle_button().pressed.emit()
	assert_bool(_panel.is_open()).is_true()
	_panel.toggle_button().pressed.emit()
	assert_bool(_panel.is_open()).is_false()


func test_each_open_offer_has_a_card_with_its_terms() -> void:
	_panel.open()
	assert_array(_panel.card_ids()).is_equal(["O0N1", "O0N2", "O0N3"])
	var text := _panel.card_text("O0N1")
	for part in ["Gotta Air", "Oslo", "10:00", "Gate C", "Small", "20 passengers", "$25"]:
		assert_str(text).contains(part)


func test_the_card_text_names_every_term_of_an_offer() -> void:
	var offer := TestOfferBoard.record("O2N3", 2, 435)
	offer["airline"] = "Blue Fjord"
	offer["destination"] = "Rome"
	offer["plane_size"] = "medium"
	offer["booked_passengers"] = 41
	offer["fee_per_passenger"] = 30
	(
		assert_array(OfferPanel.card_lines(offer))
		. is_equal(
			[
				"Blue Fjord to Rome",
				"Departs 07:15 daily   Gate C   Medium plane",
				"41 passengers booked   $30 per passenger",
			]
		)
	)


func test_accept_makes_a_contract_and_removes_the_card() -> void:
	_panel.open()
	_panel.accept_button("O0N1").pressed.emit()
	assert_array(_sim.contract_ids()).is_equal(["O0N1"])
	assert_str(_desk.board.offer_of("O0N1")["status"]).is_equal(OfferBoard.ACCEPTED)
	assert_array(_panel.card_ids()).is_equal(["O0N2", "O0N3"])
	assert_str(_panel.message()).contains("Accepted")
	assert_str(_panel.toggle_button().text).is_equal("Offers (2)")


func test_a_refused_accept_shows_the_reason_and_keeps_the_offer() -> void:
	_panel.open()
	_panel.accept_button("O0N1").pressed.emit()
	var reason := _sim.accept_problem(TestFlightContracts.terms("O0N2", 660))
	_panel.accept_button("O0N2").pressed.emit()
	assert_str(reason).is_not_empty()
	assert_str(_panel.message()).contains(reason)
	assert_array(_sim.contract_ids()).is_equal(["O0N1"])
	assert_str(_desk.board.offer_of("O0N2")["status"]).is_equal(OfferBoard.OPEN)
	assert_array(_panel.card_ids()).is_equal(["O0N2", "O0N3"])


func test_a_refused_offer_can_still_be_declined() -> void:
	_panel.open()
	_panel.accept_button("O0N1").pressed.emit()
	_panel.accept_button("O0N2").pressed.emit()
	_panel.decline_button("O0N2").pressed.emit()
	assert_array(_panel.card_ids()).is_equal(["O0N3"])
	assert_str(_desk.board.offer_of("O0N2")["status"]).is_equal(OfferBoard.DECLINED)


func test_decline_removes_the_card_and_makes_no_contract() -> void:
	_panel.open()
	_panel.decline_button("O0N1").pressed.emit()
	assert_array(_sim.contract_ids()).is_empty()
	assert_str(_desk.board.offer_of("O0N1")["status"]).is_equal(OfferBoard.DECLINED)
	assert_array(_panel.card_ids()).is_equal(["O0N2", "O0N3"])


func test_a_new_day_replaces_the_cards_with_the_new_days_offers() -> void:
	_panel.open()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var day1 := _desk.board.ensure_day(1, rng)
	assert_array(_panel.card_ids()).is_equal(day1)
	assert_str(_panel.toggle_button().text).is_equal("Offers (3)")


func test_with_no_open_offers_the_sheet_says_when_more_arrive() -> void:
	_panel.open()
	for id in ["O0N1", "O0N2", "O0N3"]:
		_panel.decline_button(id).pressed.emit()
	assert_array(_panel.card_ids()).is_empty()
	assert_str(_panel.message()).is_equal(OfferPanel.EMPTY_TEXT)
	assert_str(_panel.toggle_button().text).is_equal("Offers (0)")
