class_name TestDepartureListEnded
extends GdUnitTestSuite
## An ended contract (FlightSim.end_contract) leaves a day's departure rows from
## its end day on, while the days it already issued still show.
##
## AM (08:00) and PM (14:00) fly from day 0. AM ends at tick 26900, when AM-d1
## is issued and AM-d2 is not, so its end day is 2.
##
## Changed for HUD 7/7 (board 3bd42402): these read DepartureList.rows_for_day,
## which the departures board draws, since DepartureList.text() had no caller
## left and was removed.

const DAY := GameCalendar.TICKS_PER_DAY

var _sim: FlightSim


func before_test() -> void:
	_sim = auto_free(FlightSim.new())
	_sim.open_airport()
	assert_bool(_sim.accept_contract(TestFlightContracts.terms("AM", 480))).is_true()
	assert_bool(_sim.accept_contract(TestFlightContracts.terms("PM", 840))).is_true()
	_run_to(26900)
	assert_bool(_sim.end_contract("AM")).is_true()


func _run_to(target: int) -> void:
	for t in range(_sim.tick + 1, target + 1):
		_sim.on_tick(t)


func _text(day: int) -> String:
	var lines := PackedStringArray()
	for row in DepartureList.rows_for_day(_sim, day):
		lines.append(row["line"])
	return "\n".join(lines)


func test_the_ended_contract_still_shows_on_the_days_it_issued() -> void:
	assert_int(_sim.contract_end_day("AM")).is_equal(2)
	var day_one := _text(1)
	assert_str(day_one).contains("08:00  Oslo  Gotta Air")
	assert_str(day_one).contains("14:00  Oslo  Gotta Air")


func test_the_ended_contract_is_gone_from_its_end_day_on() -> void:
	for day in [2, 3, 10]:
		var text := _text(day)
		assert_str(text).not_contains("08:00")
		assert_str(text).contains("14:00  Oslo  Gotta Air")


func test_with_every_contract_ended_the_list_is_empty() -> void:
	assert_bool(_sim.end_contract("PM")).is_true()
	assert_array(DepartureList.rows_for_day(_sim, 3)).is_empty()
