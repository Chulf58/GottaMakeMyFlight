class_name TestDeparturesBoard
extends GdUnitTestSuite
## The departures board's lines (decisions hud-steal-list-self-clearing-alert-
## cards-money-hover-departu, departures-live-ops-drawer-and-actionable-on-time-
## hud-stat): today's live non-departed flights in time order from FlightSim,
## departed flights dropped, tomorrow's flights omitted, and EMPTY_TEXT when none
## remain today.

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
	_board.set_shown(true)


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


func test_today_lists_its_live_flights_in_time_order_and_omits_tomorrow() -> void:
	# Accepted at 09:00 for 20:00 and 11:20, plus 08:00, whose preparation
	# window has passed, so it starts tomorrow (day 1) and is omitted today.
	_run_to(GameCalendar.tick_at(0, 9 * 60, 0))
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
				"11:20  Oslo  Gotta Air  doors close 11:17",
				"20:00  Rome  Sunhop",
			]
		)
	)
	assert_array(lines).not_contains([DeparturesBoard.TOMORROW_HEADING])


func test_a_departed_flight_drops_off_today() -> void:
	_run_to(GameCalendar.tick_at(0, 9 * 60, 0))
	assert_bool(_sim.accept_contract(_terms("EARLY", 11 * 60 + 20, "Oslo", "Gotta Air"))).is_true()
	assert_bool(_sim.accept_contract(_terms("LATE", 20 * 60, "Rome", "Sunhop"))).is_true()
	var before := DeparturesBoard.lines_for(_sim, _clock.tick)
	assert_array(before).contains(
		["11:20  Oslo  Gotta Air  doors close 11:17", "20:00  Rome  Sunhop"]
	)
	_run_to(GameCalendar.tick_at(0, 14 * 60, 0))
	assert_int(_sim.state_of("EARLY-d0")).is_equal(FlightSim.State.DEPARTED)
	var after := DeparturesBoard.lines_for(_sim, _clock.tick)
	print("after the 11:20 left, today: %s" % " | ".join(after))
	assert_array(after).contains_exactly(
		[DeparturesBoard.TODAY_HEADING, "20:00  Rome  Sunhop  doors close 19:57"]
	)


func test_the_board_is_empty_text_when_nothing_is_scheduled() -> void:
	assert_array(DeparturesBoard.lines_for(_sim, 0)).contains_exactly([DeparturesBoard.EMPTY_TEXT])


func test_a_closed_airport_lists_nothing() -> void:
	var closed: FlightSim = auto_free(FlightSim.new())
	assert_array(DeparturesBoard.lines_for(closed, 0)).contains_exactly(
		[DeparturesBoard.EMPTY_TEXT]
	)


func test_a_contract_that_starts_tomorrow_alone_shows_empty_text() -> void:
	_run_to(GameCalendar.tick_at(0, 7 * 60 + 4, 0))
	assert_bool(_sim.accept_contract(_terms("NEXT", 8 * 60, "Lisbon", "Sunhop"))).is_true()
	assert_array(DeparturesBoard.lines_for(_sim, _clock.tick)).contains_exactly(
		[DeparturesBoard.EMPTY_TEXT]
	)


func test_more_flights_than_the_cap_collapse_into_a_count() -> void:
	_sim.gate_source = func() -> Array[String]: return ["C", "D"] as Array[String]
	var total := DeparturesBoard.MAX_ROWS_PER_DAY + 1
	for i in total:
		var minute := 8 * 60 + 30 + i * 100
		assert_bool(_sim.accept_contract(_terms("F%d" % i, minute, "Oslo", "Gotta Air"))).is_true()
	var lines := DeparturesBoard.lines_for(_sim, _clock.tick)
	var rows := lines.slice(1)
	print("today rows: %s" % " | ".join(rows))
	assert_int(rows.size()).is_equal(DeparturesBoard.MAX_ROWS_PER_DAY + 1)
	assert_str(rows[rows.size() - 1]).is_equal(
		"+%d more" % (total - DeparturesBoard.MAX_ROWS_PER_DAY)
	)


func test_the_node_shows_the_same_lines_after_a_refresh() -> void:
	_run_to(GameCalendar.tick_at(0, 9 * 60, 0))
	assert_bool(_sim.accept_contract(_terms("EARLY", 11 * 60 + 20, "Oslo", "Gotta Air"))).is_true()
	_board.refresh()
	assert_array(_board.shown_lines()).is_equal(DeparturesBoard.lines_for(_sim, _clock.tick))
	_run_to(GameCalendar.tick_at(0, 14 * 60, 0))
	_board.refresh()
	assert_bool(_board.is_shown()).is_false()
	_board.set_shown(true)
	assert_array(_board.shown_lines()).is_equal(DeparturesBoard.lines_for(_sim, _clock.tick))
