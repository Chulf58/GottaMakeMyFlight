class_name TestDepartureListEnded
extends GdUnitTestSuite
## An ended contract (FlightSim.end_contract) leaves the departures list from
## its end day on, while the days it already issued still show.
##
## AM (08:00) and PM (14:00) fly from day 0. AM ends at tick 26900, when AM-d1
## is issued and AM-d2 is not, so its end day is 2.

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


func test_the_ended_contract_still_shows_on_the_days_it_issued() -> void:
	assert_int(_sim.contract_end_day("AM")).is_equal(2)
	var day_one := DepartureList.text(_sim, DAY + 100)
	assert_str(day_one).contains("08:00  Oslo  Gotta Air")
	assert_str(day_one).contains("14:00  Oslo  Gotta Air")


func test_the_ended_contract_is_gone_from_its_end_day_on() -> void:
	for day in [2, 3, 10]:
		var text := DepartureList.text(_sim, day * DAY + 100)
		assert_str(text).not_contains("08:00")
		assert_str(text).contains("14:00  Oslo  Gotta Air")


func test_with_every_contract_ended_the_list_is_empty() -> void:
	assert_bool(_sim.end_contract("PM")).is_true()
	assert_str(DepartureList.text(_sim, 3 * DAY + 100)).is_equal(DepartureList.EMPTY_TEXT)
