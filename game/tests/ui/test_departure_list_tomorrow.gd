class_name TestDepartureListTomorrow
extends GdUnitTestSuite
## A contract accepted at 07:04 for 08:00 misses its day-0 preparation window
## and starts on day 1. Under departures-live-ops-drawer-and-actionable-on-
## time-hud-stat (35d321c7), DeparturesBoard lists today's live flights only
## (omitting Tomorrow rows), while DepartureList.rows_for_day(_, 1) still feeds
## tomorrow's rows to FlightPlanner.

const ACCEPTED_AT := 7 * 60 + 4

var _sim: FlightSim


func before_test() -> void:
	_sim = auto_free(FlightSim.new())
	_sim.open_airport()
	for t in range(1, GameCalendar.tick_at(0, ACCEPTED_AT, 0) + 1):
		_sim.on_tick(t)


func _lisbon() -> Dictionary:
	var terms := TestFlightContracts.terms("SH1", 480)
	terms["destination"] = "Lisbon"
	terms["airline"] = "Sunhop"
	return terms


func test_a_contract_that_starts_tomorrow_is_omitted_from_today_board_and_kept_for_day_1() -> void:
	assert_bool(_sim.accept_contract(_lisbon())).is_true()
	assert_int(int(_sim.start_days["SH1"])).is_equal(1)
	var lines := DeparturesBoard.lines_for(_sim, _sim.tick)
	assert_array(Array(lines)).is_equal([DeparturesBoard.EMPTY_TEXT])
	var tomorrow := DepartureList.rows_for_day(_sim, 1)
	assert_int(tomorrow.size()).is_equal(1)
	assert_str(tomorrow[0]["line"]).is_equal("08:00  Lisbon  Sunhop")


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
