class_name TestClosedCalendar
extends GdUnitTestSuite
## While the airport is closed no game minute or day passes (ruling day-clock-
## stops-until-the-airport-opens-the-opening-call-pau; decision closed-airport-
## calendar-design-an-explicit-calendar-epoch-pa). On the real main scene, with
## the starter terminal built and a check-in agent hired but no security
## officer (so it stays closed), 10 000 ticks pass with the calendar held: every
## tick reads 06:00 on day 0, and no wage, offer roll, autosave, quit-log day
## or rating day comes. The control opens the airport on the same world and
## runs past its first midnight: each of those day boundaries then comes.
## One boot of main.tscn for the file; before() records what each case reads.

const SEED := 18_112_026
const CLOSED_TICKS := 10_000
const OPEN_LIMIT := 3000

var _main: Node
var _closed := {}
var _control := {}
## Ticks seen by the listener, ticks not at 06:00 on day 0, last ticks of a day
## and first ticks of a day (the quit log's day_end and day_start).
var _seen := 0
var _moved := 0
var _day_ends := 0
var _day_starts := 0


func before() -> void:
	_main = SaveTestKit.boot(self, SEED)
	var clock: SimClock = _main.get_node("SimClock")
	(_main.get_node("PassengerHud") as PassengerHud).press_starter_terminal()
	var staff: StaffSim = _main.get_node("Staff")
	staff.hire(StaffMember.Role.CHECKIN)
	clock.ticked.connect(_on_tick)
	var before_state := _state()
	for i in CLOSED_TICKS:
		SaveTestKit.step(_main)
	_closed = _state()
	_closed["before"] = before_state
	_closed["counts"] = [_seen, _moved, _day_ends, _day_starts]
	_closed["held"] = clock.calendar_held
	_closed["epoch_is_tick"] = clock.epoch == clock.tick
	staff.hire(StaffMember.Role.SECURITY)
	var flights: FlightSim = _main.get_node("FlightSim")
	var limit := clock.tick + OPEN_LIMIT
	while flights.opened_tick < 0 and clock.tick < limit:
		SaveTestKit.step(_main)
	_control["opened_tick"] = flights.opened_tick
	_control["epoch"] = clock.epoch
	_day_ends = 0
	_day_starts = 0
	var midnight := GameCalendar.day_start(1, clock.epoch)
	while clock.tick < midnight + 1:
		SaveTestKit.step(_main)
	_control.merge(_state())
	_control["counts"] = [_day_ends, _day_starts]


func after() -> void:
	_main.free()


func _on_tick(tick: int) -> void:
	var clock: SimClock = _main.get_node("SimClock")
	var minute := GameCalendar.minute_of_day(tick, clock.epoch)
	if clock.calendar_held:
		_seen += 1
		if minute != GameCalendar.START_MINUTE or GameCalendar.day_of(tick, clock.epoch) != 0:
			_moved += 1
	if GameCalendar.is_last_tick_of_day(tick, clock.epoch):
		_day_ends += 1
	elif GameCalendar.tick_of_day(tick, clock.epoch) == 0:
		_day_starts += 1


## What the day-boundary listeners hold now.
func _state() -> Dictionary:
	var clock: SimClock = _main.get_node("SimClock")
	var offer_days := {}
	for offer in (_main.get_node("OfferDesk") as OfferDesk).board.open_offers():
		offer_days[offer["day"]] = true
	return {
		"tick": clock.tick,
		"balance": (_main.get_node("Finances") as Finances).wallet.balance,
		"ledger_day": (_main.get_node("DayLedger") as DayLedger).day(),
		"rating_day": (_main.get_node("AirportRating") as AirportRating).current_day(),
		"autosave_day": (_main.get_node("SaveGame") as SaveGame)._autosave_day,
		"offer_days": offer_days.keys(),
		"opened_tick": (_main.get_node("FlightSim") as FlightSim).opened_tick,
	}


func test_no_minute_or_day_passes_over_10000_closed_ticks() -> void:
	assert_int(_closed["opened_tick"]).is_equal(-1)
	assert_bool(_closed["held"]).is_true()
	assert_bool(_closed["epoch_is_tick"]).is_true()
	# [ticks seen held, ticks off 06:00 day 0, day ends, day starts]
	assert_array(_closed["counts"]).is_equal([CLOSED_TICKS, 0, 0, 0])
	assert_int(_closed["tick"] - _closed["before"]["tick"]).is_equal(CLOSED_TICKS)


func test_no_wage_offer_roll_autosave_or_rating_day_comes_while_closed() -> void:
	for key in ["balance", "ledger_day", "rating_day", "autosave_day", "offer_days"]:
		assert_that(_closed[key]).override_failure_message(key).is_equal(_closed["before"][key])
	assert_int(_closed["ledger_day"]).is_equal(0)
	assert_int(_closed["rating_day"]).is_equal(0)
	assert_int(_closed["autosave_day"]).is_equal(0)
	assert_array(_closed["offer_days"]).is_equal([0])


## The control: open, the calendar starts at the opening tick, and its first
## midnight rolls every listener over to day 1 and charges the day's wages.
func test_after_the_opening_the_first_midnight_rolls_every_listener() -> void:
	assert_int(_control["opened_tick"]).is_greater(_closed["tick"])
	assert_int(_control["epoch"]).is_equal(_control["opened_tick"])
	assert_array(_control["counts"]).is_equal([1, 1])
	assert_int(_control["ledger_day"]).is_equal(1)
	assert_int(_control["rating_day"]).is_equal(1)
	assert_int(_control["autosave_day"]).is_equal(1)
	assert_array(_control["offer_days"]).contains([1])
	assert_int(_control["balance"]).is_not_equal(_closed["balance"])
