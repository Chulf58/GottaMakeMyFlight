class_name TestPassengerHudDeparturesCap
extends GdUnitTestSuite
## However many flights are accepted, the flight panel's departures label shows
## at most DepartureList.MAX_LINES lines and the panel stays clear of the
## flight result card (PassengerHud.RESULT_TOP), so a long day never pushes
## the panel into the card (decision
## flight-panel-the-next-departing-flight-s-row-shows-a-doors-close-countdown).

var _world: PassengerTestWorld
var _hud: PassengerHud


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(8, 6))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 5), 3)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(10, 20))
	_world.flights.open_airport()
	_hud = PassengerHud.new()
	_hud.clock = _world.clock
	_hud.flights = _world.flights
	_hud.sim = _world.sim
	add_child(_hud)


func after_test() -> void:
	_hud.free()
	_world.free_all()


func _accept_many(count: int, destination: String, airline: String) -> void:
	for i in count:
		var terms := TestFlightContracts.terms("C%d" % i, 3 * 60 + i * 180)
		terms["destination"] = destination
		terms["airline"] = airline
		assert_bool(_world.flights.accept_contract(terms)).is_true()


func _label() -> Label:
	return _hud.find_child("Departures", true, false) as Label


func _panel_bottom() -> float:
	var panel := _label().get_parent().get_parent() as Control
	return panel.get_global_rect().end.y


func test_seven_contracts_still_fill_only_the_capped_lines() -> void:
	_accept_many(7, "Rome", "Sunhop")
	_hud.refresh()
	var label := _label()
	var lines := label.text.split("\n")
	assert_int(lines.size()).is_equal(DepartureList.MAX_LINES)
	# The clock is at 06:04: the 03:00 and 06:00 contracts start tomorrow, so
	# today lists GMF101 and the five later contracts, and 6 - 2 shown remain.
	assert_str(lines[DepartureList.MAX_LINES - 1]).is_equal("+4 more")
	assert_int(label.autowrap_mode).is_equal(TextServer.AUTOWRAP_OFF)
	assert_int(label.get_line_count()).is_equal(DepartureList.MAX_LINES)


func test_long_names_do_not_wrap_into_extra_lines() -> void:
	_accept_many(6, "Ulaanbaatar International", "Trans Continental Regional Airways")
	_hud.refresh()
	assert_int(_label().get_line_count()).is_equal(DepartureList.MAX_LINES)


func test_the_panel_stays_clear_of_the_result_card_with_many_flights() -> void:
	_accept_many(7, "Ulaanbaatar International", "Trans Continental Regional Airways")
	_hud.refresh()
	await get_tree().process_frame
	await get_tree().process_frame
	var panel_bottom := _panel_bottom()
	# Control: the panel was laid out, so it has a real height below the label.
	assert_float(panel_bottom).is_greater(_label().get_global_rect().end.y)
	assert_float(panel_bottom).is_less(PassengerHud.RESULT_TOP)
