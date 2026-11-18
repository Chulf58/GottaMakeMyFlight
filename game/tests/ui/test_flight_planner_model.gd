class_name TestFlightPlannerModel
extends GdUnitTestSuite
## What the flight planner draws for a day: one row per gate and one bar per
## flight over its gate hold, read from FlightSim and FlightTimetable.starts_for.

const GATES: Array[String] = ["C", "A", "B"]

var _sim: FlightSim


func before_test() -> void:
	_sim = auto_free(FlightSim.new()) as FlightSim
	_sim.open_airport()
	_sim.gate_source = func() -> Array[String]: return GATES


func _accept(id: String, minute: int, destination: String) -> void:
	var terms := TestFlightContracts.terms(id, minute)
	terms["destination"] = destination
	assert_bool(_sim.accept_contract(terms)).is_true()


func _row(rows: Array[Dictionary], gate: String) -> Dictionary:
	for row in rows:
		if row["gate"] == gate:
			return row
	return {}


func _run_to(tick: int) -> void:
	for t in range(_sim.tick + 1, tick + 1):
		_sim.on_tick(t)


func test_one_row_per_gate_in_gate_order_each_with_its_colour() -> void:
	var rows := FlightPlannerModel.rows_for_day(_sim, 0)
	var gates: Array[String] = []
	for row in rows:
		gates.append(row["gate"])
		assert_object(row["colour"]).is_equal(GateColours.of(row["gate"]))
	print("rows: ", gates)
	assert_array(gates).is_equal(["A", "B", "C"])


func test_a_bar_spans_the_gate_hold_and_marks_the_departure() -> void:
	_accept("X", 600, "Oslo")
	var rows := FlightPlannerModel.rows_for_day(_sim, 0)
	var bars: Array = _row(rows, "A")["bars"]
	var starts := FlightTimetable.starts_for(_sim.contract_of("X"), 0, 0)
	var bar: Dictionary = bars[0]
	var day_start := GameCalendar.day_start(0, 0)
	print("bar: ", bar)
	assert_int(bars.size()).is_equal(1)
	assert_int(bar["start"]).is_equal(starts[FlightSim.State.SCHEDULED])
	assert_int(bar["end"]).is_equal(starts[FlightSim.State.DEPARTED])
	# Gate A's fallback stand is 84 m west of the scene's, a 457 m route in, so X
	# taxis in 1020 ticks, not 1000 (TaxiTimes): the hold is X's own pair's.
	var taxi := FlightTimetable.taxi_of(_sim.contract_of("X"))
	assert_array(taxi).is_equal([1020, 920])
	assert_int(bar["end"] - bar["start"]).is_equal(FlightTimetable.reserved_ticks(taxi))
	assert_int(bar["departure"]).is_equal(GameCalendar.tick_at(0, 600, 0))
	assert_str(bar["label"]).is_equal("10:00  Oslo")
	assert_bool(bar["active"]).is_true()
	assert_float(bar["from"]).is_equal_approx(
		float(bar["start"] - day_start) / GameCalendar.TICKS_PER_DAY, 0.0001
	)
	assert_bool(bar["cut_start"] or bar["cut_end"]).is_false()
	assert_array(_row(rows, "B")["bars"]).is_empty()


func test_a_flight_clashing_on_the_first_gate_gets_a_bar_on_the_next() -> void:
	_accept("X", 600, "Oslo")
	_accept("Y", 660, "Rome")
	var rows := FlightPlannerModel.rows_for_day(_sim, 0)
	assert_str(_row(rows, "A")["bars"][0]["contract"]).is_equal("X")
	assert_str(_row(rows, "B")["bars"][0]["contract"]).is_equal("Y")


## Contracts depart between 07:00 and 21:00, so only a one-off flight can hold a
## gate across midnight; the cut is the model's own arithmetic.
func test_a_hold_across_midnight_is_cut_at_each_midnight() -> void:
	var day_start := GameCalendar.day_start(1, 0)
	var hold := FlightPlannerModel.Hold.new(day_start - 3000, day_start + 900)
	var row := {
		"contract": "", "flight": "F1", "gate": "A", "tick": day_start, "head": "x", "airline": ""
	}
	var before := FlightPlannerModel._bar(row, 0, hold, GameCalendar.day_start(0, 0), [])
	var after := FlightPlannerModel._bar(row, 0, hold, day_start, [])
	print(
		"cut: before ",
		before["from"],
		"-",
		before["to"],
		" after ",
		after["from"],
		"-",
		after["to"]
	)
	assert_bool(before["cut_end"]).is_true()
	assert_float(before["to"]).is_equal(1.0)
	assert_bool(before["cut_start"]).is_false()
	assert_bool(after["cut_start"]).is_true()
	assert_float(after["from"]).is_equal(0.0)
	assert_float(after["to"]).is_equal_approx(900.0 / GameCalendar.TICKS_PER_DAY, 0.0001)
	assert_bool(after["cut_end"]).is_false()
	assert_bool(after["active"]).is_false()


func test_the_same_contract_has_a_bar_on_every_day() -> void:
	_accept("X", 600, "Oslo")
	for day in [1, 2]:
		var bars: Array = _row(FlightPlannerModel.rows_for_day(_sim, day), "A")["bars"]
		assert_int(bars.size()).is_equal(1)
		assert_int(bars[0]["day"]).is_equal(day)


func test_an_issued_day_keeps_its_gate_after_a_move() -> void:
	_accept("X", 600, "Oslo")
	_run_to(GameCalendar.tick_at(0, 7 * 60, 0))
	assert_bool(_sim.reassign_gate("X", "C")).is_true()
	var day0: Array = _row(FlightPlannerModel.rows_for_day(_sim, 0), "A")["bars"]
	var day1: Array = _row(FlightPlannerModel.rows_for_day(_sim, 1), "C")["bars"]
	print("day 0 on A: ", day0.size(), " day 1 on C: ", day1.size())
	assert_int(day0.size()).is_equal(1)
	assert_int(day1.size()).is_equal(1)
	assert_array(_row(FlightPlannerModel.rows_for_day(_sim, 0), "C")["bars"]).is_empty()


func test_an_ended_contract_keeps_its_issued_bar_but_cannot_be_acted_on() -> void:
	_accept("X", 600, "Oslo")
	_run_to(GameCalendar.tick_at(0, 7 * 60, 0))
	assert_bool(_sim.end_contract("X")).is_true()
	var today: Array = _row(FlightPlannerModel.rows_for_day(_sim, 0), "A")["bars"]
	var later: Array = _row(FlightPlannerModel.rows_for_day(_sim, 2), "A")["bars"]
	assert_int(today.size()).is_equal(1)
	assert_bool(today[0]["active"]).is_false()
	assert_array(later).is_empty()


func test_a_gate_that_lost_its_stand_has_no_row_and_no_bar() -> void:
	_accept("X", 600, "Oslo")
	_sim.gate_source = func() -> Array[String]: return ["B", "C"]
	var rows := FlightPlannerModel.rows_for_day(_sim, 0)
	var bars := 0
	for row in rows:
		bars += (row["bars"] as Array).size()
	assert_int(rows.size()).is_equal(2)
	assert_int(bars).is_equal(0)
