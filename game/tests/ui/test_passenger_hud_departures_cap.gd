class_name TestPassengerHudDeparturesCap
extends GdUnitTestSuite
## However many flights are accepted, the right rail (AlertStack, with the
## flight result card) hangs GROUP_GAP under the clock panel. The panel no
## longer lists flights (HUD 3b, decision top-right-clock-panel-slims-to-day-
## time-and-speed-flight-row), so a long day never touches it.

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
		# Back to back at gate C from 07:00: five fit before the quiet night.
		var terms := TestFlightContracts.terms("C%d" % i, 7 * 60 + i * 195)
		terms["destination"] = destination
		terms["airline"] = airline
		assert_bool(_world.flights.accept_contract(terms)).is_true()


func _panel() -> Control:
	return _hud.find_child("FlightPanel", false, false) as Control


func test_the_panel_stays_clear_of_the_result_card_with_many_flights() -> void:
	_accept_many(5, "Ulaanbaatar International", "Trans Continental Regional Airways")
	_hud.refresh()
	await get_tree().process_frame
	await get_tree().process_frame
	var panel_bottom := _panel().get_global_rect().end.y
	# Control: the panel was laid out, so it has a real height.
	assert_float(_panel().size.y).is_greater(0.0)
	_hud.refresh()
	await get_tree().process_frame
	var rail := (_hud.find_child("AlertStack", false, false) as Control).get_global_rect()
	assert_float(rail.position.y).is_equal_approx(panel_bottom + HudLayout.GROUP_GAP, 0.5)
