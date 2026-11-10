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
	_hud.departures_settings_path = SaveTestKit.run_path("departures_cap_settings")
	add_child(_hud)


func after_test() -> void:
	DirAccess.remove_absolute(_hud.departures_settings_path)
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


## The Departures list is the one flight list since HUD 3b, so the guard the
## clock panel's line-cap tests gave long names lives here: every rendered row
## label trims with an ellipsis, never wraps, and stays one line tall, and a
## day still lists at most DeparturesBoard.MAX_ROWS_PER_DAY rows then "+n more".
func test_long_names_trim_in_the_departures_list_and_the_day_stays_capped() -> void:
	# A bare FlightSim and clock, as TestDeparturesBoard builds them: at 22:00
	# two gates take six flights tomorrow, 100 minutes apart.
	var sim: FlightSim = auto_free(FlightSim.new())
	var clock: SimClock = auto_free(SimClock.new())
	sim.open_airport()
	var tick := GameCalendar.tick_at(0, 22 * 60)
	for t in range(sim.tick + 1, tick + 1):
		sim.on_tick(t)
	clock.tick = tick
	sim.gate_source = func() -> Array[String]: return ["C", "D"] as Array[String]
	for i in DeparturesBoard.MAX_ROWS_PER_DAY + 1:
		var terms := TestFlightContracts.terms("L%d" % i, 7 * 60 + i * 100)
		terms["destination"] = "Ulaanbaatar International"
		terms["airline"] = "Trans Continental Regional Airways"
		assert_bool(sim.accept_contract(terms)).is_true()
	var board := DeparturesBoard.new()
	board.settings_path = SaveTestKit.run_path("departures_cap_board")
	board.flights = sim
	board.clock = clock
	add_child(board)
	for i in 3:
		await get_tree().process_frame
	var rows := board.find_child("Rows", true, false)
	var reference := Label.new()
	reference.theme = BuildMenu.HUD_THEME
	reference.text = "Ag"
	add_child(reference)
	await get_tree().process_frame
	var one_line := reference.get_minimum_size().y
	reference.free()
	var trimmed := 0
	var row_count := 0
	for row in rows.get_children():
		if not row is HBoxContainer or row.name == "Picker":
			continue
		var label := row.get_child(0) as Label
		row_count += 1
		assert_int(label.autowrap_mode).is_equal(TextServer.AUTOWRAP_OFF)
		assert_int(label.text_overrun_behavior).is_equal(TextServer.OVERRUN_TRIM_ELLIPSIS)
		assert_int(label.get_line_count()).is_equal(1)
		assert_float(label.get_minimum_size().y).is_equal_approx(one_line, 0.5)
		var font := label.get_theme_font("font")
		var wide := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		if wide > label.size.x:
			trimmed += 1
	# Control: the long names really overflowed, so the ellipsis did the work.
	assert_int(trimmed).is_greater(0)
	# Each day lists at most MAX_ROWS_PER_DAY rows, then one "+n more".
	var lines := board.shown_lines()
	var tomorrow := lines.find(DeparturesBoard.TOMORROW_HEADING)
	var days := [lines.slice(1, tomorrow), lines.slice(tomorrow + 1)]
	var collapsed := 0
	for day in days:
		assert_int(day.size()).is_less_equal(DeparturesBoard.MAX_ROWS_PER_DAY + 1)
		if (day[day.size() - 1] as String).ends_with(" more"):
			collapsed += 1
			assert_str(day[day.size() - 1]).starts_with("+")
			assert_int(day.size()).is_equal(DeparturesBoard.MAX_ROWS_PER_DAY + 1)
	assert_int(collapsed).is_greater(0)
	assert_int(row_count).is_less_equal(2 * DeparturesBoard.MAX_ROWS_PER_DAY)
	DirAccess.remove_absolute(board.settings_path)
	board.free()
