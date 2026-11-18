class_name TestFlightOddHours
extends GdUnitTestSuite
## Odd hours (decision odd-hours-and-exit-fee-offer-traits-odd-hours-widens-the-
## dep; technical design odd-hours-technical-design-contract-validation-allows-
## 06-00): FlightContract.window gives a contract 07:00 to 21:00, or 06:00 to
## 22:00 with Odd hours, and that one check refuses a departure on accept, in a
## fit trial and on load. The ground planner's guard is 06:00 to 22:00 for every
## flight. An Odd hours contract at 06:00 and one at 22:00 are accepted and fly
## there, and a save taken either side of midnight loads and runs on like the
## original.
##
## Tick 0 is 06:00 on day 0, so a 06:00 contract accepted then first flies on day 1.

const ODD := {"up": "top_fare", "down": "odd_hours", "level": 1}
const EXIT := {"up": "top_fare", "down": "exit_fee", "level": 2}

var _log: Array[String] = []


func before_test() -> void:
	_log.clear()


func _world() -> Array:
	var clock := auto_free(SimClock.new()) as SimClock
	var sim := auto_free(FlightSim.new()) as FlightSim
	sim.bind_clock(clock)
	sim.gate_source = func() -> Array[String]: return ["A", "B", "C", "D"] as Array[String]
	sim.state_changed.connect(
		func(id: String, state: int) -> void: _log.append("%d %s %d" % [clock.tick, id, state])
	)
	sim.open_airport()
	return [clock, sim]


func _terms(id: String, minute: int, traits := {}) -> Dictionary:
	var terms := TestFlightContracts.terms(id, minute)
	terms["traits"] = traits
	return terms


func _run(clock: SimClock, target: int) -> void:
	while clock.tick < target:
		clock.advance(SimClock.STEP)


func test_the_window_widens_by_an_hour_at_each_end_only_for_odd_hours() -> void:
	assert_array(FlightContract.window({})).is_equal([420, 1260])
	assert_array(FlightContract.window(EXIT)).is_equal([420, 1260])
	assert_array(FlightContract.window(ODD)).is_equal([360, 1320])
	(
		assert_array(FlightContract.window({"up": "shoppers", "down": "odd_hours", "level": 2}))
		. is_equal([360, 1320])
	)
	# The guard is the widest window, and the plain one is what OfferBoard draws.
	assert_int(GroundPlanner.EARLIEST_DEPARTURE_MINUTE).is_equal(FlightContract.window(ODD)[0])
	assert_int(GroundPlanner.LATEST_DEPARTURE_MINUTE).is_equal(FlightContract.window(ODD)[1])
	assert_int(OfferBoard.DEPARTURE_FIRST_MINUTE).is_equal(FlightContract.window({})[0])
	assert_int(OfferBoard.DEPARTURE_LAST_MINUTE).is_equal(FlightContract.window({})[1])
	assert_str(FlightSim.QUIET_NIGHT_TEXT).contains("07:00 to 21:00")
	assert_str(FlightSim.ODD_HOURS_NIGHT_TEXT).contains("06:00 to 22:00")


## Accept, the fit trial and FlightFit agree at 06:00 and 22:00: an Odd hours
## contract fits and is taken, a plain one and an Exit fee one are refused as the
## quiet night with the 07:00 to 21:00 words, and past 06:00 to 22:00 even Odd
## hours is refused with its own words.
func test_only_odd_hours_is_accepted_at_06_00_and_22_00() -> void:
	var sim: FlightSim = _world()[1]
	for minute in [360, 1320]:
		for traits: Dictionary in [{}, EXIT]:
			var refused := _terms("P%d" % minute, minute, traits)
			assert_str(sim.accept_problem(refused)).is_equal(FlightSim.QUIET_NIGHT_TEXT)
			assert_str(sim.accept_refusal(refused)["reason"]).is_equal(GroundPlanner.QUIET_NIGHT)
			assert_str(sim.trial_assignment(refused)["blocker"]).is_equal(FlightSim.BLOCKER_NIGHT)
			assert_bool(FlightFit.fits(sim, refused, [])).is_false()
		var odd := _terms("O%d" % minute, minute, ODD)
		assert_str(sim.accept_problem(odd)).is_empty()
		assert_bool(FlightFit.fits(sim, odd, [])).is_true()
		assert_bool(sim.accept_contract(odd)).is_true()
	assert_array(sim.contract_ids()).is_equal(["O360", "O1320"])
	for minute in [345, 1335]:
		var late := _terms("L%d" % minute, minute, ODD)
		assert_str(sim.accept_problem(late)).is_equal(FlightSim.ODD_HOURS_NIGHT_TEXT)
		assert_str(sim.trial_assignment(late)["blocker"]).is_equal(FlightSim.BLOCKER_NIGHT)
	# The plain window's ends still take a plain contract.
	assert_bool(sim.accept_contract(_terms("P420", 420))).is_true()
	assert_bool(sim.accept_contract(_terms("P1260", 1260))).is_true()


## The 06:00 and 22:00 Odd hours flights push back at those minutes and depart,
## beside plain flights at 07:00 and 21:00, on two days running.
func test_odd_hours_flights_fly_at_06_00_and_22_00() -> void:
	var world := _world()
	var sim: FlightSim = world[1]
	assert_bool(sim.accept_contract(_terms("EARLY", 360, ODD))).is_true()
	assert_bool(sim.accept_contract(_terms("LATE", 1320, ODD))).is_true()
	assert_bool(sim.accept_contract(_terms("AM", 420))).is_true()
	assert_bool(sim.accept_contract(_terms("PM", 1260))).is_true()
	_run(world[0], GameCalendar.tick_at(3, 0, 0))
	var departed := 0
	for flight: String in [
		"EARLY-d1", "EARLY-d2", "LATE-d0", "LATE-d1", "LATE-d2", "AM-d1", "PM-d1"
	]:
		var pushback := _tick_of(flight, FlightSim.State.PUSHBACK)
		print("%s pushes back at %s" % [flight, GameCalendar.clock_text(pushback, 0)])
		var expected: int = sim.contract_of(flight.get_slice("-", 0))["departure_minute"]
		assert_int(GameCalendar.minute_of_day(pushback, 0)).is_equal(expected)
		if _tick_of(flight, FlightSim.State.DEPARTED) > pushback:
			departed += 1
	assert_int(departed).is_equal(7)


## The tick `flight` entered `state` at, from the log, or -1.
func _tick_of(flight: String, state: int) -> int:
	var line := " %s %d" % [flight, state]
	for entry in _log:
		if entry.ends_with(line):
			return entry.get_slice(" ", 0).to_int()
	return -1


## A save taken at 23:30 (after the 22:00 flight) and one at 00:30 (before the
## 06:00 one is issued) each load, and the loaded sim runs on to day 2 exactly
## as the original does.
func test_a_save_either_side_of_midnight_loads_and_runs_on_like_the_original() -> void:
	for minute in [23 * 60 + 30, 30]:
		var day := 0 if minute > 720 else 1
		var world := _world()
		var sim: FlightSim = world[1]
		assert_bool(sim.accept_contract(_terms("EARLY", 360, ODD))).is_true()
		assert_bool(sim.accept_contract(_terms("LATE", 1320, ODD))).is_true()
		_run(world[0], GameCalendar.tick_at(day, minute, 0))
		var data: Dictionary = JSON.parse_string(JSON.stringify(sim.to_snapshot()))
		assert_int(int(data["save_version"])).is_equal(FlightSim.SAVE_VERSION)
		var clone := _world()
		clone[0].from_snapshot(world[0].to_snapshot())
		assert_bool(clone[1].from_snapshot(data)).is_true()
		_log.clear()
		_run(world[0], GameCalendar.tick_at(2, 600, 0))
		var original := _log.duplicate()
		_log.clear()
		_run(clone[0], GameCalendar.tick_at(2, 600, 0))
		var saved_at := GameCalendar.clock_text(GameCalendar.tick_at(day, minute, 0), 0)
		print("saved at %s, %d state changes after" % [saved_at, original.size()])
		assert_int(original.size()).is_greater(0)
		assert_array(_log).is_equal(original)
		assert_str(JSON.stringify(clone[1].to_snapshot())).is_equal(
			JSON.stringify(sim.to_snapshot())
		)


## A load refuses a contract at 06:00 or 22:00 whose traits are not Odd hours;
## the same save with the traits intact loads (the control).
func test_a_load_refuses_a_plain_contract_at_06_00_or_22_00() -> void:
	var world := _world()
	var sim: FlightSim = world[1]
	assert_bool(sim.accept_contract(_terms("EARLY", 360, ODD))).is_true()
	assert_bool(sim.accept_contract(_terms("LATE", 1320, ODD))).is_true()
	var data: Dictionary = JSON.parse_string(JSON.stringify(sim.to_snapshot()))
	var good := _world()
	assert_bool(good[1].from_snapshot(data.duplicate(true))).is_true()
	assert_array(good[1].contract_ids()).is_equal(["EARLY", "LATE"])
	for index in 2:
		var bad := data.duplicate(true)
		bad["contracts"][index]["traits"] = EXIT.duplicate()
		var fresh := _world()
		await (
			assert_error(func() -> void: fresh[1].from_snapshot(bad))
			. is_push_error("FlightSim.from_snapshot: %s" % FlightSim.QUIET_NIGHT_TEXT)
		)
		assert_array(fresh[1].contract_ids()).is_empty()
