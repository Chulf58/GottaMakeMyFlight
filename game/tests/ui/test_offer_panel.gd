class_name TestOfferPanel
extends GdUnitTestSuite
## OfferPanel (Pick-1-of-3 side-by-side): a button with the open offer count,
## a horizontal row of 3 daily offer cards (airline badge, destination,
## departure, size, booked passengers, fee per passenger, Accept) plus a Pass
## button. Accepting 1 daily offer dismisses the others with a spin-away
## discard animation. A refused accept shows FlightSim.accept_problem's reason.

var _port: SubViewport
var _desk: OfferDesk
var _sim: FlightSim
var _panel: OfferPanel


func before_test() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_desk = OfferDesk.new()
	_desk.runway = Runway.new(PlaneClasses.LARGE)
	_sim = FlightSim.new()
	_sim.open_airport()
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
	assert_object(_panel.decline_button("O0N1")).is_null()
	assert_object(_panel.pass_button()).is_not_null()
	assert_bool(_panel.pass_button().visible).is_true()
	var text := _panel.card_text("O0N1")
	for part in ["Gotta Air", "Oslo", "10:00", "Small", "6 passengers", "$58"]:
		assert_str(text).contains(part)
	assert_str(text).not_contains("Gate")


func test_the_card_lines_show_airline_destination_departure_size_passengers_and_fee() -> void:
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
				"Departs 07:15 daily",
				"Medium plane",
				"41 passengers booked   $30 per passenger",
			]
		)
	)


func test_accept_makes_a_contract_closes_others_and_animates_spin_away() -> void:
	_panel.open()
	await get_tree().process_frame
	_panel.accept_button("O0N1").pressed.emit()
	assert_array(_sim.contract_ids()).is_equal(["O0N1"])
	assert_str(_desk.board.offer_of("O0N1")["status"]).is_equal(OfferBoard.ACCEPTED)
	assert_str(_desk.board.offer_of("O0N2")["status"]).is_equal(OfferBoard.DECLINED)
	assert_str(_desk.board.offer_of("O0N3")["status"]).is_equal(OfferBoard.DECLINED)
	assert_array(_desk.board.open_offers()).is_empty()
	assert_str(_panel.message()).contains("Accepted")
	assert_str(_panel.toggle_button().text).is_equal("Offers (0)")
	assert_bool(_panel.is_discard_animating()).is_true()
	assert_object(_panel.discard_tween()).is_not_null()
	assert_bool(_panel.accept_button("O0N1").disabled).is_true()
	assert_bool(_panel.accept_button("O0N2").disabled).is_true()
	assert_bool(_panel.pass_button().disabled).is_true()

	await get_tree().create_timer(0.20).timeout
	for unchosen in ["O0N2", "O0N3"]:
		var c := _panel.card(unchosen)
		assert_object(c).is_not_null()
		assert_float(absf(c.rotation)).is_greater(0.01)
		assert_float(c.scale.x).is_less(1.0)
		assert_float(c.modulate.a).is_less(1.0)

	var safety := 0
	while _panel.is_discard_animating() and safety < 30:
		safety += 1
		await get_tree().create_timer(0.05).timeout
	await get_tree().process_frame
	assert_bool(_panel.is_discard_animating()).is_false()
	assert_array(_panel.card_ids()).is_empty()
	assert_str(_panel.message()).is_equal(OfferPanel.PICKED_TODAY_TEXT)
	assert_bool(_panel.pass_button().visible).is_false()


func test_a_refused_accept_shows_the_reason_and_keeps_the_offer() -> void:
	assert_bool(_sim.accept_contract(TestFlightContracts.terms("EXISTING", 600))).is_true()
	_panel.open()
	var reason := _sim.accept_problem(TestFlightContracts.terms("O0N2", 660))
	_panel.accept_button("O0N2").pressed.emit()
	assert_str(reason).is_not_empty()
	assert_str(_panel.refusal_text("O0N2")).starts_with("Can't accept Gotta Air to Oslo: ")
	assert_str(_panel.refusal_text("O0N2")).not_contains("O0N")
	assert_str(_panel.message()).is_empty()
	assert_bool(_panel.refusal_label("O0N2").is_visible_in_tree()).is_true()
	assert_bool(_panel.card("O0N2").is_ancestor_of(_panel.refusal_label("O0N2"))).is_true()
	assert_str(_panel.refusal_text("O0N3")).is_empty()
	assert_bool(_panel.refusal_label("O0N3").visible).is_false()
	assert_array(_sim.contract_ids()).is_equal(["EXISTING"])
	assert_str(_desk.board.offer_of("O0N2")["status"]).is_equal(OfferBoard.OPEN)
	assert_array(_panel.card_ids()).is_equal(["O0N1", "O0N2", "O0N3"])
	assert_bool(_panel.is_discard_animating()).is_false()


func test_a_refusal_is_gone_when_the_sheet_is_closed_and_opened_again() -> void:
	assert_bool(_sim.accept_contract(TestFlightContracts.terms("EXISTING", 600))).is_true()
	_panel.open()
	_panel.accept_button("O0N2").pressed.emit()
	assert_str(_panel.refusal_text("O0N2")).is_not_empty()
	_panel.close()
	assert_str(_panel.refusal_text("O0N2")).is_empty()
	_panel.open()
	assert_str(_panel.refusal_text("O0N2")).is_empty()
	assert_bool(_panel.refusal_label("O0N2").visible).is_false()


func test_a_refused_offer_batch_can_still_be_passed() -> void:
	assert_bool(_sim.accept_contract(TestFlightContracts.terms("EXISTING", 600))).is_true()
	_panel.open()
	await get_tree().process_frame
	_panel.accept_button("O0N2").pressed.emit()
	assert_str(_panel.refusal_text("O0N2")).is_not_empty()
	_panel.pass_button().pressed.emit()
	assert_array(_desk.board.open_offers()).is_empty()
	assert_str(_desk.board.offer_of("O0N2")["status"]).is_equal(OfferBoard.DECLINED)
	_panel.close()
	await get_tree().process_frame
	assert_array(_panel.card_ids()).is_empty()


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
		_desk.board.decline(id)
	assert_array(_panel.card_ids()).is_empty()
	assert_str(_panel.message()).is_equal(OfferPanel.EMPTY_TEXT)
	assert_str(_panel.toggle_button().text).is_equal("Offers (0)")


func test_the_accept_message_is_gone_when_the_sheet_is_closed_and_opened_again() -> void:
	_panel.open()
	_panel.accept_button("O0N1").pressed.emit()
	assert_str(_panel.message()).contains("Accepted")
	_panel.close()
	_panel.open()
	assert_str(_panel.message()).is_equal(OfferPanel.PICKED_TODAY_TEXT)


func test_a_panel_without_a_desk_builds_nothing_instead_of_showing_no_offers() -> void:
	var bare := OfferPanel.new()
	bare.flights = _sim
	await (
		assert_error(func() -> void: _port.add_child(bare))
		. is_push_error("OfferPanel: desk and flights must both be set, so nothing is shown")
	)
	assert_int(bare.get_child_count()).is_equal(0)


func test_a_panel_without_flights_builds_nothing() -> void:
	var bare := OfferPanel.new()
	bare.desk = _desk
	await (
		assert_error(func() -> void: _port.add_child(bare))
		. is_push_error("OfferPanel: desk and flights must both be set, so nothing is shown")
	)
	assert_int(bare.get_child_count()).is_equal(0)


func test_the_sheet_title_explains_airline_contracts() -> void:
	var title := _panel.find_child("OfferTitle", true, false) as Label
	assert_object(title).is_not_null()
	assert_str(title.text).is_equal("Airline Contracts — Accept to schedule flights")


func test_offers_stay_hidden_until_the_airport_opens() -> void:
	var closed_sim := FlightSim.new()
	_port.add_child(closed_sim)
	var closed_panel := OfferPanel.new()
	closed_panel.desk = _desk
	closed_panel.flights = closed_sim
	_port.add_child(closed_panel)
	assert_bool(closed_panel.toggle_button().visible).is_false()
	assert_bool(closed_panel.toggle_button().disabled).is_true()
	closed_panel.open()
	assert_bool(closed_panel.is_open()).is_false()
	closed_sim.open_airport()
	closed_panel._process(0.0)
	assert_bool(closed_panel.toggle_button().visible).is_true()
	assert_bool(closed_panel.toggle_button().disabled).is_false()
	closed_panel.open()
	assert_bool(closed_panel.is_open()).is_true()
