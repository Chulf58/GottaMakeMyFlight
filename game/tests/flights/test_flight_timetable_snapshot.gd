class_name TestFlightTimetableSnapshot
extends GdUnitTestSuite
## Saving a timetable: contracts, the issued-occurrence record and live
## occurrences survive JSON, a load never re-issues, and a bad save is refused
## whole.

const MIDNIGHT := 21600

var _log: Array[String] = []


func before_test() -> void:
	_log.clear()


func _world() -> Array:
	var clock := auto_free(SimClock.new()) as SimClock
	var sim := auto_free(FlightSim.new()) as FlightSim
	sim.bind_clock(clock)
	sim.state_changed.connect(_on_state.bind(clock))
	sim.occurrence_added.connect(_on_added.bind(clock))
	return [clock, sim]


func _on_state(id: String, state: int, clock: SimClock) -> void:
	_log.append("%d %s %d" % [clock.tick, id, state])


func _on_added(id: String, clock: SimClock) -> void:
	_log.append("%d add %s" % [clock.tick, id])


func _run(clock: SimClock, target: int) -> void:
	while clock.tick < target:
		clock.advance(SimClock.STEP)


## NIGHT (00:30) is boarding over midnight and AM (08:00) is issued the next
## morning, so the run after the load crosses a day rollover and new issues.
func _timetabled(at_tick: int) -> Array:
	var world := _world()
	var sim: FlightSim = world[1]
	assert_bool(sim.accept_contract(TestFlightContracts.terms("NIGHT", 30))).is_true()
	assert_bool(sim.accept_contract(TestFlightContracts.terms("AM", 480))).is_true()
	_run(world[0], at_tick)
	return world


func _saved(world: Array) -> Dictionary:
	var text := JSON.stringify({"clock": world[0].to_snapshot(), "flights": world[1].to_snapshot()})
	return JSON.parse_string(text)


func test_save_and_load_just_before_midnight_gives_the_same_future() -> void:
	var source := _timetabled(MIDNIGHT - 10)
	assert_array(source[1].flight_ids()).is_equal(["NIGHT-d1"])
	var data := _saved(source)
	_log.clear()
	var loaded := _world()
	assert_bool(loaded[0].from_snapshot(data["clock"])).is_true()
	assert_bool(loaded[1].from_snapshot(data["flights"])).is_true()
	assert_array(_log).is_empty()
	assert_array(loaded[1].flight_ids()).is_equal(["NIGHT-d1"])
	assert_bool(loaded[1].contract_of("AM").is_read_only()).is_true()
	var end := MIDNIGHT + GameCalendar.TICKS_PER_DAY
	_run(loaded[0], end)
	var after_load := _log.duplicate()
	_log.clear()
	_run(source[0], end)
	assert_array(after_load).is_equal(_log)
	(
		assert_bool(_log.has("%d add AM-d1" % (28800 + 440 - FlightTimetable.ISSUE_LEAD_TICKS)))
		. is_true()
	)
	assert_bool(_log.has("22200 NIGHT-d1 %d" % FlightSim.State.PUSHBACK)).is_true()
	assert_int(_log.size()).is_greater(20)
	assert_str(JSON.stringify(loaded[1].to_snapshot())).is_equal(
		JSON.stringify(source[1].to_snapshot())
	)


func test_snapshot_records_version_contracts_and_issued_days() -> void:
	var data: Dictionary = _saved(_timetabled(MIDNIGHT - 10))["flights"]
	assert_int(int(data["save_version"])).is_equal(FlightSim.SAVE_VERSION)
	assert_int(data["contracts"].size()).is_equal(2)
	assert_int(int(data["next_day"]["NIGHT"])).is_equal(2)
	assert_int(int(data["next_day"]["AM"])).is_equal(1)
	assert_str(data["flights"][0]["contract"]).is_equal("NIGHT")
	assert_int(int(data["flights"][0]["day"])).is_equal(1)


func test_an_inconsistent_timetable_save_is_refused_whole() -> void:
	var good: Dictionary = _saved(_timetabled(MIDNIGHT - 10))["flights"]
	var cases: Array[Dictionary] = []
	var edits := [
		func(d: Dictionary) -> void: d.erase("save_version"),
		func(d: Dictionary) -> void: d["save_version"] = 0,
		func(d: Dictionary) -> void: d["extra"] = 1,
		func(d: Dictionary) -> void: d["tick"] = 1e300,
		func(d: Dictionary) -> void: d["next_day"]["NIGHT"] = 1,
		func(d: Dictionary) -> void: d["next_day"]["AM"] = 2,
		func(d: Dictionary) -> void: d["next_day"].erase("AM"),
		func(d: Dictionary) -> void: d["flights"].clear(),
		func(d: Dictionary) -> void: d["flights"][0]["starts"][0] = 20241,
		func(d: Dictionary) -> void: d["flights"][0]["id"] = "NIGHT-d2",
		func(d: Dictionary) -> void: d["flights"][0]["day"] = 2,
		func(d: Dictionary) -> void: d["flights"][0]["contract"] = "GONE",
		func(d: Dictionary) -> void: d["flights"][0]["gate"] = "A",
		func(d: Dictionary) -> void: d["flights"][0].erase("day"),
		func(d: Dictionary) -> void: d["contracts"][1]["departure_minute"] = 40,
		func(d: Dictionary) -> void: d["contracts"][1]["gate"] = "B",
		func(d: Dictionary) -> void: d["contracts"][1]["first_day"] = 3,
		func(d: Dictionary) -> void: d["contracts"][1]["id"] = "NIGHT",
		func(d: Dictionary) -> void: d["contracts"][0]["fee_per_passenger"] = 2.5,
		func(d: Dictionary) -> void: d["contracts"][0]["surprise"] = true,
		func(d: Dictionary) -> void: d["flights"].append(_raw_entry(d["flights"][0])),
	]
	for edit: Callable in edits:
		var bad := good.duplicate(true)
		edit.call(bad)
		cases.append(bad)
	for bad in cases:
		var target := auto_free(FlightSim.new()) as FlightSim
		assert_bool(target.from_snapshot(bad)).override_failure_message(str(bad)).is_false()
		assert_array(target.flight_ids()).is_empty()
		assert_array(target.contract_ids()).is_empty()
		assert_int(target.tick).is_equal(0)


## A raw flight copying NIGHT-d1's schedule at the same gate clashes with it.
static func _raw_entry(occurrence: Dictionary) -> Dictionary:
	var raw := occurrence.duplicate(true)
	raw["id"] = "RAW"
	raw["contract"] = ""
	raw["day"] = -1
	return raw


## A save taken after an occurrence was pruned must not list it again.
func test_a_pruned_occurrence_in_a_save_is_refused() -> void:
	var good: Dictionary = _saved(_timetabled(24020))["flights"]
	assert_array(good["flights"]).is_empty()
	assert_bool((auto_free(FlightSim.new()) as FlightSim).from_snapshot(good)).is_true()
	var stale := good.duplicate(true)
	var record := _saved(_timetabled(24019))["flights"]["flights"][0] as Dictionary
	stale["flights"].append(record)
	var target := auto_free(FlightSim.new()) as FlightSim
	assert_bool(target.from_snapshot(stale)).is_false()
	assert_array(target.contract_ids()).is_empty()
	assert_int(target.state_of("NIGHT-d1")).is_equal(-1)


## first_day must be one an acceptance between tick 0 and the save's tick could
## give: NIGHT (00:30) could not start on day 0, and at tick 21590 AM (08:00)
## would go to day 1 at the latest, never day 2.
func test_a_first_day_no_acceptance_could_give_is_refused() -> void:
	var good: Dictionary = _saved(_timetabled(MIDNIGHT - 10))["flights"]
	assert_bool((auto_free(FlightSim.new()) as FlightSim).from_snapshot(good)).is_true()
	var too_early := good.duplicate(true)
	too_early["contracts"][0]["first_day"] = 0
	var postponed := good.duplicate(true)
	postponed["contracts"][1]["first_day"] = 2
	postponed["next_day"]["AM"] = 2
	for bad in [too_early, postponed]:
		var target := auto_free(FlightSim.new()) as FlightSim
		assert_bool(target.from_snapshot(bad)).override_failure_message(str(bad)).is_false()
		assert_array(target.contract_ids()).is_empty()


## Live flights are listed in timetable order (first start tick, then id), the
## order PassengerHud and spawn_batch read; a save in another order is refused.
func test_live_flights_out_of_timetable_order_are_refused() -> void:
	var world := _world()
	var sim: FlightSim = world[1]
	assert_bool(sim.accept_contract(TestFlightContracts.terms("LATE", 1430))).is_true()
	assert_bool(sim.accept_contract(TestFlightContracts.terms("NEXT", 119))).is_true()
	_run(world[0], 21000)
	assert_array(sim.flight_ids()).is_equal(["LATE-d0", "NEXT-d1"])
	var good: Dictionary = _saved(world)["flights"]
	assert_bool((auto_free(FlightSim.new()) as FlightSim).from_snapshot(good)).is_true()
	var reversed := good.duplicate(true)
	reversed["flights"].reverse()
	var target := auto_free(FlightSim.new()) as FlightSim
	assert_bool(target.from_snapshot(reversed)).is_false()
	assert_array(target.flight_ids()).is_empty()
