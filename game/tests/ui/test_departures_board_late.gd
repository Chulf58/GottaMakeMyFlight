class_name TestDeparturesBoardLate
extends GdUnitTestSuite
## The soft "N running late" line (board 7f89cf1e, decision calm-cozy-default-
## view-quiet-world-detail-on-ask-soft-statio part 4): each flight's row on the
## departures board says how many of its passengers are running late, in the
## muted HudHint text on line 2, and says nothing at 0. A passenger who boards
## or misses leaves the count. The count is LateCount's, the same lateness
## Passenger.late that made the "I'm late!" bubble.

const FLIGHT_B := "GMF102"

var _world: PassengerTestWorld
var _board: DeparturesBoard


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_world = PassengerTestWorld.reference_world()
	_board = DeparturesBoard.new()
	_board.settings_path = SaveTestKit.run_path("departures_board_late")
	_board.flights = _world.flights
	_board.clock = _world.clock
	_board.passengers = _world.sim
	add_child(_board)


func after_test() -> void:
	var path := _board.settings_path
	_board.free()
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + ".tmp")
	_world.free_all()


func _row(flight_id: String) -> Dictionary:
	for entry in DeparturesBoard.entries_for(
		_world.flights, _world.clock.tick, LateCount.by_flight(_world.sim)
	):
		if entry["kind"] == "row" and entry["text"].contains(flight_id):
			return entry
	return {}


## Line 2 of the flight's row, "" when the row has none.
func _second_line() -> String:
	var label := _board.find_child("Airline", true, false) as Label
	return "" if label == null else label.text


func test_text_is_empty_at_zero_and_counts_otherwise() -> void:
	assert_str(LateCount.text_for(0)).is_equal("")
	assert_str(LateCount.text_for(1)).is_equal("1 running late")
	assert_str(LateCount.text_for(5)).is_equal("5 running late")


func test_count_is_per_flight_and_only_while_the_passenger_is_not_done() -> void:
	_world.flights.add_flight(FLIGHT_B, FlightSim.schedule_starts(0))
	var on_a := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var on_a2 := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var on_b := _world.sim.spawn_now(FLIGHT_B)
	assert_dict(LateCount.by_flight(_world.sim)).is_empty()
	_world.passenger(on_a).late = true
	_world.passenger(on_a2).late = true
	_world.passenger(on_b).late = true
	var counts := LateCount.by_flight(_world.sim)
	assert_int(counts[PassengerTestWorld.FLIGHT]).is_equal(2)
	assert_int(counts[FLIGHT_B]).is_equal(1)
	# A passenger who boards leaves the count; one who misses does too.
	_world.passenger(on_a).stage = Passenger.Stage.MADE
	_world.passenger(on_b).stage = Passenger.Stage.MISSED
	counts = LateCount.by_flight(_world.sim)
	assert_int(counts[PassengerTestWorld.FLIGHT]).is_equal(1)
	assert_bool(counts.has(FLIGHT_B)).is_false()


func test_a_flight_with_nobody_late_shows_no_late_line() -> void:
	_world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.run_to(40)
	_board.refresh()
	var row := _row(PassengerTestWorld.FLIGHT)
	print("row at 40: ", row)
	assert_str(row["late"]).is_equal("")
	assert_str(_second_line()).not_contains("running late")


func test_a_late_passenger_shows_the_line_and_boarding_or_missing_clears_it() -> void:
	_world.run_to(1850)
	var late_id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.run_to(1875)
	var p := _world.passenger(late_id)
	assert_bool(p.late).is_true()
	_board.refresh()
	var row := _row(PassengerTestWorld.FLIGHT)
	print("row at 1875: ", row)
	assert_str(row["late"]).is_equal("1 running late")
	var line := _second_line()
	print("line 2 at 1875: ", line)
	assert_str(line).contains("1 running late")
	assert_int(_board.late_count_of(PassengerTestWorld.FLIGHT)).is_equal(1)
	# The player's view: the passenger boards or misses, the line goes.
	while not p.is_done() and _world.clock.tick < 4000:
		_world.step()
	print("done at ", _world.clock.tick, " stage ", p.stage)
	assert_bool(p.is_done()).is_true()
	_board.refresh()
	assert_str(_row(PassengerTestWorld.FLIGHT).get("late", "x")).is_equal("")
	assert_str(_second_line()).not_contains("running late")
	assert_int(_board.late_count_of(PassengerTestWorld.FLIGHT)).is_equal(0)


func test_the_worst_line_two_fits_the_list_on_one_line() -> void:
	for i in 3:
		await get_tree().process_frame
	var rows := _board.find_child("Rows", true, false) as Control
	# The longest airline name (OfferBoard), "Boarding" (the last status a late
	# passenger can see) and the largest count a flight can reach (its plane
	# class's top booking, three digits for a large plane), drawn as the board
	# draws them.
	var most := 0
	for plane_class: String in PlaneClasses.ORDER:
		most = maxi(most, int(PlaneClasses.passenger_range(plane_class)[1]))
	var label := Label.new()
	label.theme_type_variation = &"HudHint"
	_board.add_child(label)
	label.text = "Skyline Global  Boarding  %s" % LateCount.text_for(most)
	var font := label.get_theme_font("font")
	var size := label.get_theme_font_size("font_size")
	var wide := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	label.free()
	print("worst line 2 width ", wide, " of rows width ", rows.size.x, " for ", most)
	assert_int(most).is_greater(99)
	# Control: the rows were laid out and the text has a real width.
	assert_float(rows.size.x).is_greater(100.0)
	assert_float(wide).is_greater(100.0)
	assert_float(wide).is_less(rows.size.x)


func _accept(id: String, minute: int, airline: String) -> String:
	var terms := TestFlightContracts.terms(id, minute)
	terms["airline"] = airline
	assert_bool(_world.flights.accept_contract(terms)).is_true()
	return FlightTimetable.occurrence_id(id, 0)


func test_each_contract_flight_row_counts_its_own_late_passengers() -> void:
	_world.flights.open_airport()
	var first := _accept("SH100", 14 * 60, "Gotta Air")
	var second := _accept("LG200", 19 * 60, "Skyline Global")
	for flight in [first, second, second]:
		_world.passenger(_world.sim.spawn_now(flight)).late = true
	_world.step()
	_board.refresh()
	var first_line := _board.find_child("Airline_SH100_0", true, false) as Label
	var second_line := _board.find_child("Airline_LG200_0", true, false) as Label
	print("first: ", first_line.text, " second: ", second_line.text)
	assert_str(first_line.text).is_equal("Gotta Air  1 running late")
	assert_str(second_line.text).is_equal("Skyline Global  2 running late")


func test_a_load_at_the_same_tick_updates_the_line() -> void:
	_world.run_to(1850)
	var late_id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.run_to(1875)
	assert_bool(_world.passenger(late_id).late).is_true()
	var with_late := _world.sim.to_snapshot()
	_world.passenger(late_id).late = false
	var without_late := _world.sim.to_snapshot()
	assert_bool(with_late.is_empty() or without_late.is_empty()).is_false()
	_world.passenger(late_id).late = true
	_board.refresh()
	assert_int(_board.late_count_of(PassengerTestWorld.FLIGHT)).is_equal(1)
	# Loading pauses the clock, so the tick stays the same: the line must
	# follow the load alone, to nobody late and back.
	var tick := _world.sim.tick
	assert_bool(_world.sim.from_snapshot(without_late)).is_true()
	assert_int(_world.sim.tick).is_equal(tick)
	_board.refresh()
	print("load without late at ", tick, ": ", _board.late_count_of(PassengerTestWorld.FLIGHT))
	assert_int(_board.late_count_of(PassengerTestWorld.FLIGHT)).is_equal(0)
	assert_str(_second_line()).not_contains("running late")
	assert_bool(_world.sim.from_snapshot(with_late)).is_true()
	assert_int(_world.sim.tick).is_equal(tick)
	_board.refresh()
	assert_int(_board.late_count_of(PassengerTestWorld.FLIGHT)).is_equal(1)
	assert_str(_second_line()).contains("1 running late")


func test_another_sim_at_the_same_tick_drops_the_old_counts() -> void:
	_world.run_to(1850)
	var late_id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.run_to(1875)
	assert_bool(_world.passenger(late_id).late).is_true()
	_board.refresh()
	assert_int(_board.late_count_of(PassengerTestWorld.FLIGHT)).is_equal(1)
	var other := PassengerTestWorld.reference_world()
	other.run_to(1875)
	assert_int(other.sim.tick).is_equal(_world.sim.tick)
	_board.passengers = other.sim
	_board.refresh()
	assert_int(_board.late_count_of(PassengerTestWorld.FLIGHT)).is_equal(0)
	other.free_all()
