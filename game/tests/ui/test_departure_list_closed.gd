class_name TestDepartureListClosed
extends GdUnitTestSuite
## A day's departure rows and the airport's open state (decision airport-opening-
## design-stays-open-once-opened-starter-flight-placed-after-opening): while
## closed no contract is listed, and a contract accepted while closed is
## listed only from its recorded start day, never on a day it skipped.
##
## AM (08:00) is accepted on day 0 while closed; the airport opens on day 2 at
## 06:50 (tick 58600), too late for AM's day-2 slot, so AM starts on day 3.
## LATE (23:00), accepted after opening, flies on day 2.
##
## Changed for HUD 7/7 (board 3bd42402): these read DepartureList.rows_for_day,
## which the departures board draws, since DepartureList.text() (the old flight
## panel's text) had no caller left and was removed.

const OPENED := 2 * 28800 + 1000

var _sim: FlightSim


func before_test() -> void:
	_sim = auto_free(FlightSim.new())


func _run_to(target: int) -> void:
	for t in range(_sim.tick + 1, target + 1):
		_sim.on_tick(t)


## The row lines for `day`, or for the day holding the sim's tick.
func _lines(day: int = -1) -> PackedStringArray:
	var lines := PackedStringArray()
	var on := GameCalendar.day_of(_sim.tick) if day < 0 else day
	for row in DepartureList.rows_for_day(_sim, on):
		lines.append(row["line"])
	return lines


func test_a_closed_airport_lists_no_contract() -> void:
	assert_bool(_sim.accept_contract(TestFlightContracts.terms("AM", 480))).is_true()
	assert_array(Array(_lines(0))).is_empty()
	_run_to(GameCalendar.TICKS_PER_DAY + 100)
	assert_array(Array(_lines())).is_empty()


func test_a_contract_accepted_while_closed_never_shows_a_skipped_day() -> void:
	assert_bool(_sim.accept_contract(TestFlightContracts.terms("AM", 480))).is_true()
	_run_to(OPENED)
	assert_bool(_sim.open_airport()).is_true()
	assert_bool(_sim.accept_contract(TestFlightContracts.terms("LATE", 1260))).is_true()
	assert_int(int(_sim.start_days["AM"])).is_equal(3)
	var day_two := _lines()
	print("day 2 after opening: %s" % " | ".join(day_two))
	assert_str(" | ".join(day_two)).not_contains("08:00")
	assert_str(day_two[0]).starts_with("21:00  Oslo  Gotta Air")
	_run_to(3 * GameCalendar.TICKS_PER_DAY - 7200 + 60)
	var day_three := _lines()
	print("day 3 after midnight: %s" % " | ".join(day_three))
	assert_int(GameCalendar.day_of(_sim.tick)).is_equal(3)
	assert_str(day_three[0]).starts_with("08:00  Oslo  Gotta Air")
