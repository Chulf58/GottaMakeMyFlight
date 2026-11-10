class_name TestDepartureListTomorrow
extends GdUnitTestSuite
## When nothing leaves today but an accepted contract starts tomorrow, the
## departures say so with the flight's time (board item "Smoke playtest 6
## friction", point 1): a contract accepted at 07:04 for 08:00 misses its
## day-0 preparation window and starts on day 1.
##
## Changed for HUD 7/7 (board 3bd42402): the old flight panel's "Tomorrow" line
## came from DepartureList.text(), which had no caller left and was removed. The
## departures board carries the same news under its Tomorrow heading, so these
## read DeparturesBoard.lines_for.

const ACCEPTED_AT := 7 * 60 + 4

var _sim: FlightSim


func before_test() -> void:
	_sim = auto_free(FlightSim.new())
	_sim.open_airport()
	for t in range(1, GameCalendar.tick_at(0, ACCEPTED_AT) + 1):
		_sim.on_tick(t)


func _lisbon() -> Dictionary:
	var terms := TestFlightContracts.terms("SH1", 480)
	terms["destination"] = "Lisbon"
	terms["airline"] = "Sunhop"
	return terms


func test_a_contract_that_starts_tomorrow_is_announced_with_its_time() -> void:
	assert_bool(_sim.accept_contract(_lisbon())).is_true()
	assert_int(int(_sim.start_days["SH1"])).is_equal(1)
	var lines := DeparturesBoard.lines_for(_sim, _sim.tick)
	print("nothing today, one tomorrow: %s" % " | ".join(lines))
	(
		assert_array(Array(lines))
		. is_equal(
			[
				DeparturesBoard.TODAY_HEADING,
				DeparturesBoard.NONE_TEXT,
				DeparturesBoard.TOMORROW_HEADING,
				"08:00  Lisbon  Sunhop",
			]
		)
	)


func test_an_ended_contract_is_not_announced() -> void:
	assert_bool(_sim.accept_contract(_lisbon())).is_true()
	assert_bool(_sim.end_contract("SH1")).is_true()
	assert_array(Array(DeparturesBoard.lines_for(_sim, _sim.tick))).is_equal(
		[DeparturesBoard.EMPTY_TEXT]
	)


func test_nothing_is_announced_without_a_contract() -> void:
	assert_array(Array(DeparturesBoard.lines_for(_sim, _sim.tick))).is_equal(
		[DeparturesBoard.EMPTY_TEXT]
	)
