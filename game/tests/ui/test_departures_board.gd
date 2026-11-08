class_name TestDeparturesBoard
extends GdUnitTestSuite
## The departures board's lines (HUD 3/7, decision hud-steal-list-self-clearing-
## alert-cards-money-hover-departu): today's and tomorrow's flights in time
## order from the FlightSim, departed flights dropped, and the empty text.

var _sim: FlightSim
var _clock: SimClock
var _board: DeparturesBoard


func before_test() -> void:
	_sim = auto_free(FlightSim.new())
	_clock = auto_free(SimClock.new())
	_sim.open_airport()
	_board = DeparturesBoard.new()
	_board.settings_path = SaveTestKit.run_path("departures_board_lines")
	_board.flights = _sim
	_board.clock = _clock
	add_child(_board)


func after_test() -> void:
	var path := _board.settings_path
	_board.free()
	DirAccess.remove_absolute(path)


func _terms(id: String, minute: int, destination: String, airline: String) -> Dictionary:
	var terms := TestFlightContracts.terms(id, minute)
	terms["destination"] = destination
	terms["airline"] = airline
	return terms


## Runs the FlightSim to `tick` so contracts issue and flights advance.
func _run_to(tick: int) -> void:
	for t in range(_sim.tick + 1, tick + 1):
		_sim.on_tick(t)
	_clock.tick = tick


func test_today_and_tomorrow_list_their_flights_in_time_order() -> void:
	# Accepted at 09:00 for 20:00 and 11:20, plus 08:00, whose preparation
	# window has passed, so it starts tomorrow (day 1). Each holds the gate for
	# 195 minutes (FlightTimetable.reserved_ticks()), so 08:00 and 11:20 do not
	# clash (the 11:20 flight was 11:00 when a flight held it for 165).
	_run_to(GameCalendar.tick_at(0, 9 * 60))
	assert_bool(_sim.accept_contract(_terms("LATE", 20 * 60, "Rome", "Sunhop"))).is_true()
	assert_bool(_sim.accept_contract(_terms("EARLY", 11 * 60 + 20, "Oslo", "Gotta Air"))).is_true()
	assert_bool(_sim.accept_contract(_terms("NEXT", 8 * 60, "Lisbon", "Sunhop"))).is_true()
	var lines := DeparturesBoard.lines_for(_sim, _clock.tick)
	print("board lines: %s" % " | ".join(lines))
	(
		assert_array(lines)
		. contains_exactly(
			[
				DeparturesBoard.TODAY_HEADING,
				"11:20  Oslo  Gotta Air",
				"20:00  Rome  Sunhop",
				DeparturesBoard.TOMORROW_HEADING,
				"08:00  Lisbon  Sunhop",
				"11:20  Oslo  Gotta Air",
				"20:00  Rome  Sunhop",
			]
		)
	)


func test_a_departed_flight_drops_off_and_tomorrow_keeps_its_row() -> void:
	_run_to(GameCalendar.tick_at(0, 9 * 60))
	assert_bool(_sim.accept_contract(_terms("EARLY", 11 * 60 + 20, "Oslo", "Gotta Air"))).is_true()
	assert_bool(_sim.accept_contract(_terms("LATE", 20 * 60, "Rome", "Sunhop"))).is_true()
	var before := DeparturesBoard.lines_for(_sim, _clock.tick)
	assert_array(before).contains(["11:20  Oslo  Gotta Air", "20:00  Rome  Sunhop"])
	_run_to(GameCalendar.tick_at(0, 14 * 60))
	assert_int(_sim.state_of("EARLY-d0")).is_equal(FlightSim.State.DEPARTED)
	var after := DeparturesBoard.lines_for(_sim, _clock.tick)
	var today := after.slice(1, after.find(DeparturesBoard.TOMORROW_HEADING))
	print("after the 11:20 left, today: %s" % " | ".join(today))
	assert_array(today).contains_exactly(["20:00  Rome  Sunhop"])
	assert_array(after).contains(["11:20  Oslo  Gotta Air"])


func test_the_board_is_empty_text_when_nothing_is_scheduled() -> void:
	assert_array(DeparturesBoard.lines_for(_sim, 0)).contains_exactly([DeparturesBoard.EMPTY_TEXT])


func test_a_closed_airport_lists_nothing() -> void:
	var closed: FlightSim = auto_free(FlightSim.new())
	assert_array(DeparturesBoard.lines_for(closed, 0)).contains_exactly(
		[DeparturesBoard.EMPTY_TEXT]
	)


func test_a_day_with_no_flights_says_none_while_the_other_lists_its_own() -> void:
	_run_to(GameCalendar.tick_at(0, 7 * 60 + 4))
	assert_bool(_sim.accept_contract(_terms("NEXT", 8 * 60, "Lisbon", "Sunhop"))).is_true()
	(
		assert_array(DeparturesBoard.lines_for(_sim, _clock.tick))
		. contains_exactly(
			[
				DeparturesBoard.TODAY_HEADING,
				DeparturesBoard.NONE_TEXT,
				DeparturesBoard.TOMORROW_HEADING,
				"08:00  Lisbon  Sunhop",
			]
		)
	)


func test_more_flights_than_the_cap_collapse_into_a_count() -> void:
	_run_to(GameCalendar.tick_at(0, 6 * 60 + 5))
	# One flight more than the cap. A gate holds each flight for
	# FlightTimetable.reserved_ticks() (195 minutes), so the six fit only in a
	# whole day: tomorrow's, from 00:20. Today, from 06:05, the first departure
	# can be 08:18 and six would run past midnight (when the reservation was
	# 165 minutes, six fitted today from 09:00).
	var total := DeparturesBoard.MAX_ROWS_PER_DAY + 1
	var apart := ceili(float(FlightTimetable.reserved_ticks()) / GameCalendar.TICKS_PER_MINUTE)
	for i in total:
		var minute := 20 + i * apart
		assert_bool(_sim.accept_contract(_terms("F%d" % i, minute, "Oslo", "Gotta Air"))).is_true()
	var lines := DeparturesBoard.lines_for(_sim, _clock.tick)
	var tomorrow := lines.slice(lines.find(DeparturesBoard.TOMORROW_HEADING) + 1)
	print("tomorrow: %s" % " | ".join(tomorrow))
	assert_int(tomorrow.size()).is_equal(DeparturesBoard.MAX_ROWS_PER_DAY + 1)
	assert_str(tomorrow[tomorrow.size() - 1]).is_equal(
		"+%d more" % (total - DeparturesBoard.MAX_ROWS_PER_DAY)
	)


func test_the_node_shows_the_same_lines_after_a_refresh() -> void:
	_run_to(GameCalendar.tick_at(0, 9 * 60))
	assert_bool(_sim.accept_contract(_terms("EARLY", 11 * 60 + 20, "Oslo", "Gotta Air"))).is_true()
	_board.refresh()
	assert_array(_board.shown_lines()).is_equal(DeparturesBoard.lines_for(_sim, _clock.tick))
	_run_to(GameCalendar.tick_at(0, 14 * 60))
	_board.refresh()
	assert_array(_board.shown_lines()).is_equal(DeparturesBoard.lines_for(_sim, _clock.tick))
