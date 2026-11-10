class_name TestOfferPanelClashText
extends GdUnitTestSuite
## A refused accept names the flight it clashes with the way the departures
## board does (time, airline, destination), never by a contract or flight id.

var _port: SubViewport
var _desk: OfferDesk
var _sim: FlightSim
var _panel: OfferPanel
var _ids := RegEx.create_from_string("O\\d+N\\d+|-d\\d+")


func before_test() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_desk = OfferDesk.new()
	_desk.runway = Runway.new(PlaneClasses.LARGE)
	_sim = FlightSim.new()
	_port.add_child(_desk)
	_port.add_child(_sim)


func after_test() -> void:
	_port.free()


func _open_panel(minutes: Array) -> void:
	var records := TestOfferBoard.day_records(0, minutes)
	assert_bool(_desk.board.from_snapshot(TestOfferBoard.save_of(records))).is_true()
	_panel = OfferPanel.new()
	_panel.desk = _desk
	_panel.flights = _sim
	_port.add_child(_panel)
	_panel.open()


func test_a_clash_with_a_contract_names_it_by_time_airline_and_destination() -> void:
	_open_panel([600, 660, 1200])
	_panel.accept_button("O0N1").pressed.emit()
	_panel.accept_button("O0N2").pressed.emit()
	var text := _panel.refusal_text("O0N2")
	print("clash text: %s" % text)
	assert_str(text).starts_with("Can't accept Gotta Air to Oslo: ")
	assert_str(text).contains("the 10:00 Gotta Air flight to Oslo")
	assert_str(text).contains("at gate C")
	assert_object(_ids.search(text)).is_null()


func test_a_refusal_sits_on_its_own_card_and_a_later_one_replaces_it() -> void:
	_open_panel([600, 600, 600])
	_panel.accept_button("O0N1").pressed.emit()
	_panel.accept_button("O0N2").pressed.emit()
	assert_str(_panel.refusal_text("O0N2")).contains("clashes")
	assert_str(_panel.refusal_text("O0N3")).is_empty()
	assert_bool(_panel.card("O0N2").is_ancestor_of(_panel.refusal_label("O0N2"))).is_true()
	_panel.accept_button("O0N3").pressed.emit()
	assert_str(_panel.refusal_text("O0N3")).contains("clashes")
	assert_str(_panel.refusal_text("O0N2")).is_empty()
	assert_bool(_panel.card("O0N3").is_ancestor_of(_panel.refusal_label("O0N3"))).is_true()
	assert_bool(_panel.refusal_label("O0N2").visible).is_false()


func test_a_clash_with_a_one_off_flight_is_named_by_time_and_flight() -> void:
	_open_panel([495, 900, 1200])
	assert_bool(_sim.add_default_flight()).is_true()
	_panel.accept_button("O0N1").pressed.emit()
	var text := _panel.refusal_text("O0N1")
	print("clash text: %s" % text)
	# A one-off (tests and debug only) books no runway since Runway R7 (the
	# planner books the shared ground); it still holds its gate, gate C here.
	assert_str(text).ends_with("it clashes with the 08:13 flight at gate C")
	assert_str(text).not_contains("GMF101")
	assert_str(text).contains("at gate C")
	assert_str(text).not_contains("contract O0N1")
	assert_object(_ids.search(text)).is_null()


func test_a_refusal_that_is_not_a_clash_keeps_the_sim_reason() -> void:
	_open_panel([600, 900, 1200])
	_sim.gate_source = func() -> Array[String]: return [] as Array[String]
	_panel.accept_button("O0N1").pressed.emit()
	assert_str(_panel.refusal_text("O0N1")).is_equal(
		"Can't accept Gotta Air to Oslo: no gate has a stand"
	)


func test_a_clash_shaped_reason_the_parser_misses_shows_no_ids() -> void:
	_open_panel([600, 900, 1200])
	var text := _panel._in_words("contract O0N2 clashes with O0N1 at the gate")
	assert_str(text).is_equal("it clashes with another flight")
	assert_object(_ids.search(text)).is_null()


func test_a_reason_that_only_mentions_clashes_is_not_taken_for_a_clash() -> void:
	_open_panel([600, 900, 1200])
	var reason := "no gate has a stand that clashes with the plane"
	assert_str(_panel._in_words(reason)).is_equal(reason)
