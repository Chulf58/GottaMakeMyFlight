class_name TestCalendarEpoch
extends GdUnitTestSuite
## The calendar epoch E (decision closed-airport-calendar-design-an-explicit-
## calendar-epoch-pa): SimClock owns and saves it, it follows the tick while
## held and freezes when started, every calendar call takes it explicitly, a
## save's staged parts and a refused load use the saved E, and two worlds at
## once each keep their own. Two main.tscn worlds: A opens early and is saved;
## B is still closed, many ticks later, when it loads A's save.

const SEED := 18_112_027
const B_WAIT := 3000
const OPEN_LIMIT := 3000

var _a: Node
var _b: Node
var _saved := {}


func before() -> void:
	_a = SaveTestKit.boot(self, SEED)
	_b = SaveTestKit.boot(self, SEED + 1)
	SaveTestKit.start_airport(_a)
	var flights: FlightSim = _a.get_node("FlightSim")
	while flights.opened_tick < 0 and _clock(_a).tick < OPEN_LIMIT:
		SaveTestKit.step(_a)
	for i in 50:
		SaveTestKit.step(_a)
	for i in B_WAIT:
		SaveTestKit.step(_b)
	_saved = SaveTestKit.save_game(_a).snapshot()


func after() -> void:
	_a.free()
	_b.free()


static func _clock(main: Node) -> SimClock:
	return main.get_node("SimClock")


func test_a_held_calendar_follows_the_tick_and_starting_it_freezes_it() -> void:
	var clock: SimClock = auto_free(SimClock.new())
	assert_int(clock.epoch).is_equal(0)
	clock.tick = 500
	assert_int(clock.epoch).is_equal(0)
	clock.hold_calendar()
	for i in 40:
		clock.advance(SimClock.STEP)
		assert_int(clock.epoch).is_equal(clock.tick)
	assert_str(GameCalendar.clock_text(clock.tick, clock.epoch)).is_equal("06:00")
	clock.start_calendar()
	var frozen := clock.tick
	for i in 40:
		clock.advance(SimClock.STEP)
	assert_int(clock.epoch).is_equal(frozen)
	assert_str(GameCalendar.clock_text(clock.tick, clock.epoch)).is_equal("06:02")


func test_the_epoch_is_saved_and_restored() -> void:
	var clock: SimClock = auto_free(SimClock.new())
	clock.hold_calendar()
	clock.tick = 900
	clock.start_calendar()
	clock.tick = 1300
	var data: Dictionary = JSON.parse_string(JSON.stringify(clock.to_snapshot()))
	assert_str(data["epoch"]).is_equal("900")
	assert_bool(data["calendar_held"]).is_false()
	var other: SimClock = auto_free(SimClock.new())
	assert_bool(other.from_snapshot(data)).is_true()
	assert_int(other.epoch).is_equal(900)
	assert_bool(other.calendar_held).is_false()
	other.hold_calendar()
	var held: Dictionary = JSON.parse_string(JSON.stringify(other.to_snapshot()))
	assert_str(held["epoch"]).is_equal("1300")
	var third: SimClock = auto_free(SimClock.new())
	assert_bool(third.from_snapshot(held)).is_true()
	assert_bool(third.calendar_held).is_true()
	third.advance(SimClock.STEP)
	assert_int(third.epoch).is_equal(1301)


func test_a_bad_saved_epoch_is_refused() -> void:
	var clock: SimClock = auto_free(SimClock.new())
	clock.tick = 1000
	var cases := {
		"after the tick": {"epoch": "1001"},
		"held off the tick": {"epoch": "400", "calendar_held": true},
		"negative": {"epoch": "-1"},
		"not a string": {"epoch": 5},
		"held not a bool": {"calendar_held": "yes"},
		"version 1": {"save_version": 1},
	}
	for name: String in cases:
		var data := clock.to_snapshot()
		data.merge(cases[name], true)
		await (
			assert_error(func() -> void: assert_bool(clock.from_snapshot(data)).is_false())
			. is_push_error(any_string())
		)
	var missing := clock.to_snapshot()
	missing.erase("epoch")
	await assert_error(func() -> void: clock.from_snapshot(missing)).is_push_error(any_string())
	assert_int(clock.tick).is_equal(1000)
	assert_int(clock.epoch).is_equal(0)


func test_two_worlds_at_once_keep_their_own_epoch() -> void:
	var a_epoch := _clock(_a).epoch
	var b_epoch := _clock(_b).epoch
	assert_int(a_epoch).is_equal((_a.get_node("FlightSim") as FlightSim).opened_tick)
	assert_bool(_clock(_b).calendar_held).is_true()
	assert_int(b_epoch).is_equal(_clock(_b).tick)
	assert_int(b_epoch).is_not_equal(a_epoch)
	assert_int((_a.get_node("FlightSim") as FlightSim).epoch).is_equal(a_epoch)
	assert_int((_b.get_node("FlightSim") as FlightSim).epoch).is_equal(b_epoch)
	assert_str(GameCalendar.clock_text(_clock(_b).tick, b_epoch)).is_equal("06:00")
	assert_str(GameCalendar.clock_text(_clock(_a).tick, a_epoch)).is_equal("06:02")


## The flights' check derives the starter's times from E: at the saved E they
## load, one tick off they are refused, so staging that loads them read it.
func test_the_flights_check_reads_the_saved_epoch() -> void:
	var epoch := SimClock.saved_epoch(_saved["clock"])
	var gates := (_a.get_node("FlightSim") as FlightSim).gate_ids()
	var good := FlightSnapshot.load(_saved["flights"].duplicate(true), gates, epoch)
	assert_bool(good.has("error")).override_failure_message(str(good)).is_false()
	var off := FlightSnapshot.load(_saved["flights"].duplicate(true), gates, epoch + 7)
	assert_bool(off.has("error")).is_true()


## A failed load leaves B's own E: a saved epoch 20 ticks off is refused by
## the flights staged at that saved E (the starter's times no longer match),
## and a calendar saved as held while the airport is open is refused too
## (SaveGame._epoch_problem names it). Then the good save stages and installs
## the saved E.
func test_a_failed_load_keeps_the_live_epoch_and_a_load_installs_the_saved_one() -> void:
	var save := SaveTestKit.save_game(_b)
	var live := _clock(_b).epoch
	var bad: Dictionary = _saved.duplicate(true)
	bad["clock"]["epoch"] = str(SimClock.saved_epoch(_saved["clock"]) + 20)
	await assert_error(func() -> void: save.load_world(bad)).is_push_error(any_string())
	assert_str(save.message_text()).contains(
		"flights: flight GMF101-d0 does not match its contract's timetable"
	)
	assert_int(_clock(_b).epoch).is_equal(live)
	assert_bool(_clock(_b).calendar_held).is_true()
	var held: Dictionary = _saved.duplicate(true)
	held["clock"]["calendar_held"] = true
	held["clock"]["epoch"] = held["clock"]["tick"]
	await assert_error(func() -> void: save.load_world(held)).is_push_error(any_string())
	assert_str(save._epoch_problem(held)).starts_with("clock: the calendar is held")
	var shifted: Dictionary = _saved.duplicate(true)
	shifted["clock"]["epoch"] = str(SimClock.saved_epoch(_saved["clock"]) - 1)
	assert_str(save._epoch_problem(shifted)).contains("is not the opening tick")
	assert_str(save._epoch_problem(_saved)).is_empty()
	assert_int(_clock(_b).epoch).is_equal(live)
	assert_bool(save.load_world(_saved.duplicate(true))).is_true()
	var epoch := SimClock.saved_epoch(_saved["clock"])
	assert_int(_clock(_b).epoch).is_equal(epoch)
	assert_bool(_clock(_b).calendar_held).is_false()
	assert_int((_b.get_node("FlightSim") as FlightSim).epoch).is_equal(epoch)
	assert_int(epoch).is_not_equal(live)
