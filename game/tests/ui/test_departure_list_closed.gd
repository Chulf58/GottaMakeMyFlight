class_name TestDepartureListClosed
extends GdUnitTestSuite
## Today's departures and the airport's open state (decision airport-opening-
## design-stays-open-once-opened-starter-flight-placed-after-opening): while
## closed no contract is listed, and a contract accepted while closed is
## listed only from its recorded start day, never on a day it skipped.
##
## AM (08:00) is accepted on day 0 while closed; the airport opens on day 2 at
## 06:50 (tick 58600), too late for AM's day-2 slot, so AM starts on day 3.
## LATE (23:00), accepted after opening, flies on day 2.

const OPENED := 2 * 28800 + 1000

var _sim: FlightSim


func before_test() -> void:
	_sim = auto_free(FlightSim.new())


func _run_to(target: int) -> void:
	for t in range(_sim.tick + 1, target + 1):
		_sim.on_tick(t)


func test_a_closed_airport_lists_no_contract() -> void:
	assert_bool(_sim.accept_contract(TestFlightContracts.terms("AM", 480))).is_true()
	assert_str(DepartureList.text(_sim, 0)).is_equal(DepartureList.EMPTY_TEXT)
	_run_to(GameCalendar.TICKS_PER_DAY + 100)
	assert_str(DepartureList.text(_sim, _sim.tick)).is_equal(DepartureList.EMPTY_TEXT)


func test_a_contract_accepted_while_closed_never_shows_a_skipped_day() -> void:
	assert_bool(_sim.accept_contract(TestFlightContracts.terms("AM", 480))).is_true()
	_run_to(OPENED)
	assert_bool(_sim.open_airport()).is_true()
	assert_bool(_sim.accept_contract(TestFlightContracts.terms("LATE", 1380))).is_true()
	assert_int(int(_sim.start_days["AM"])).is_equal(3)
	var day_two := DepartureList.text(_sim, _sim.tick)
	print("day 2 after opening: %s" % day_two.replace("\n", " | "))
	assert_str(day_two).not_contains("08:00")
	assert_str(day_two).starts_with("23:00  Oslo  Gotta Air")
	_run_to(3 * GameCalendar.TICKS_PER_DAY - 7200 + 60)
	var day_three := DepartureList.text(_sim, _sim.tick)
	print("day 3 after midnight: %s" % day_three.replace("\n", " | "))
	assert_int(GameCalendar.day_of(_sim.tick)).is_equal(3)
	assert_str(day_three).starts_with("08:00  Oslo  Gotta Air")
