class_name TestFlightOpenSnapshot
extends GdUnitTestSuite
## FlightSim save version 3 added the airport's open state: the opening tick
## (-1 while closed) and each contract's start day. A load equals an
## uninterrupted run, skipped days stay unflown, and a version 2 save (written
## before the airport could be closed) loads as open since tick 0.
##
## AM (08:00) has its first state at 440 + 28800 * day.

const OPENED := 2 * 28800 + 1000

var _log: Array[String] = []


func before_test() -> void:
	_log.clear()


func _world() -> Array:
	var clock := auto_free(SimClock.new()) as SimClock
	var sim := auto_free(FlightSim.new()) as FlightSim
	sim.bind_clock(clock)
	sim.state_changed.connect(
		func(id: String, state: int) -> void: _log.append("%d %s %d" % [clock.tick, id, state])
	)
	sim.occurrence_added.connect(
		func(id: String) -> void: _log.append("%d add %s" % [clock.tick, id])
	)
	return [clock, sim]


func _run(clock: SimClock, target: int) -> void:
	while clock.tick < target:
		clock.advance(SimClock.STEP)


## AM accepted on day 0 while closed, the airport opened on day 2 (so AM's
## days 0 to 2 are skipped), and LATE (23:00) accepted after opening.
func _opened_world(at_tick: int) -> Array:
	var world := _world()
	var sim: FlightSim = world[1]
	assert_bool(sim.accept_contract(TestFlightContracts.terms("AM", 480))).is_true()
	_run(world[0], OPENED)
	assert_bool(sim.open_airport()).is_true()
	assert_bool(sim.accept_contract(TestFlightContracts.terms("LATE", 1380))).is_true()
	_run(world[0], at_tick)
	return world


func _saved(world: Array) -> Dictionary:
	var text := JSON.stringify({"clock": world[0].to_snapshot(), "flights": world[1].to_snapshot()})
	return JSON.parse_string(text)


func test_version_is_4_with_the_opening_tick_start_days_and_ended() -> void:
	assert_int(FlightSim.SAVE_VERSION).is_equal(4)
	var data: Dictionary = _saved(_opened_world(OPENED + 100))["flights"]
	assert_int(int(data["save_version"])).is_equal(4)
	assert_int(int(data["opened_tick"])).is_equal(OPENED)
	assert_int(int(data["start_day"]["AM"])).is_equal(3)
	assert_int(int(data["start_day"]["LATE"])).is_equal(2)
	assert_int(int(data["contracts"][0]["first_day"])).is_equal(0)


func test_a_closed_save_round_trips_and_stays_closed() -> void:
	var world := _world()
	assert_bool(world[1].accept_contract(TestFlightContracts.terms("AM", 480))).is_true()
	_run(world[0], 5000)
	var data := _saved(world)
	assert_int(int(data["flights"]["opened_tick"])).is_equal(-1)
	var loaded := _world()
	assert_bool(loaded[0].from_snapshot(data["clock"])).is_true()
	assert_bool(loaded[1].from_snapshot(data["flights"])).is_true()
	assert_int(loaded[1].opened_tick).is_equal(-1)
	_run(loaded[0], 40000)
	assert_array(loaded[1].flight_ids()).is_empty()
	assert_array(_log).is_empty()


## Saved after opening with skipped days behind: the loaded sim plays out the
## same events and still reports the skipped days as never flown.
func test_an_open_save_with_skipped_days_round_trips_and_plays_out_the_same() -> void:
	var source := _opened_world(3 * 28800 + 500)
	assert_array(source[1].flight_ids()).is_equal(["AM-d3"])
	var data := _saved(source)
	_log.clear()
	var loaded := _world()
	assert_bool(loaded[0].from_snapshot(data["clock"])).is_true()
	assert_bool(loaded[1].from_snapshot(data["flights"])).is_true()
	assert_array(_log).is_empty()
	assert_int(loaded[1].opened_tick).is_equal(OPENED)
	assert_int(loaded[1].state_of("AM-d2")).is_equal(-1)
	var end := 5 * 28800
	_run(loaded[0], end)
	var after_load := _log.duplicate()
	_log.clear()
	_run(source[0], end)
	assert_array(after_load).is_equal(_log)
	assert_bool(_log.has("%d add AM-d4" % (4 * 28800 + 440 - 2400))).is_true()
	assert_str(JSON.stringify(loaded[1].to_snapshot())).is_equal(
		JSON.stringify(source[1].to_snapshot())
	)
	for id in ["AM-d0", "AM-d1", "AM-d2"]:
		assert_int(loaded[1].state_of(id)).override_failure_message(id).is_equal(-1)
	assert_int(loaded[1].state_of("AM-d3")).is_equal(FlightSim.State.DEPARTED)


## A version 2 save has no open state: it loads as open since tick 0 with
## every contract starting on its first_day, and saves again as version 4.
func test_a_version_2_save_loads_as_open() -> void:
	var world := _world()
	assert_bool(world[1].open_airport()).is_true()
	assert_bool(world[1].accept_contract(TestFlightContracts.terms("AM", 480))).is_true()
	_run(world[0], 600)
	var v3: Dictionary = _saved(world)["flights"]
	var v2 := v3.duplicate(true)
	v2["save_version"] = 2
	v2.erase("opened_tick")
	v2.erase("start_day")
	v2.erase("ended")
	var loaded: FlightSim = auto_free(FlightSim.new())
	assert_bool(loaded.from_snapshot(v2)).is_true()
	assert_int(loaded.opened_tick).is_equal(0)
	assert_array(loaded.flight_ids()).is_equal(["AM-d0"])
	assert_str(JSON.stringify(loaded.to_snapshot())).is_equal(
		JSON.stringify(world[1].to_snapshot())
	)


func test_saves_of_other_versions_or_with_the_wrong_keys_for_theirs_are_refused() -> void:
	var good: Dictionary = _saved(_opened_world(OPENED + 100))["flights"]
	var v2_with_open := good.duplicate(true)
	v2_with_open["save_version"] = 2
	var v3_without := good.duplicate(true)
	v3_without.erase("start_day")
	var v1 := good.duplicate(true)
	v1["save_version"] = 1
	var v5 := good.duplicate(true)
	v5["save_version"] = 5
	for bad in [v2_with_open, v3_without, v1, v5]:
		var target: FlightSim = auto_free(FlightSim.new())
		assert_bool(target.from_snapshot(bad)).override_failure_message(str(bad)).is_false()
		assert_int(target.opened_tick).is_equal(-1)


## Each edit makes a save no uninterrupted run could hold.
func test_an_inconsistent_open_state_is_refused_whole() -> void:
	var good: Dictionary = _saved(_opened_world(3 * 28800 + 500))["flights"]
	assert_bool((auto_free(FlightSim.new()) as FlightSim).from_snapshot(good)).is_true()
	var edits := [
		func(d: Dictionary) -> void: d["opened_tick"] = d["tick"] + 1,
		func(d: Dictionary) -> void: d["opened_tick"] = -2,
		func(d: Dictionary) -> void: d["opened_tick"] = 0.5,
		func(d: Dictionary) -> void: d["opened_tick"] = 3 * 28800 + 100,
		func(d: Dictionary) -> void: d["start_day"].erase("AM"),
		func(d: Dictionary) -> void: d["start_day"]["AM"] = 2,
		func(d: Dictionary) -> void: d["start_day"]["AM"] = 4,
		func(d: Dictionary) -> void: d["start_day"]["LATE"] = 3,
		func(d: Dictionary) -> void: d["start_day"] = [],
		func(d: Dictionary) -> void: _close(d),
	]
	for edit: Callable in edits:
		var bad := good.duplicate(true)
		edit.call(bad)
		var target: FlightSim = auto_free(FlightSim.new())
		assert_bool(target.from_snapshot(bad)).override_failure_message(str(bad)).is_false()
		assert_int(target.opened_tick).is_equal(-1)
		assert_array(target.contract_ids()).is_empty()


## A closed save cannot hold issued occurrences.
static func _close(d: Dictionary) -> void:
	d["opened_tick"] = -1
	d["start_day"]["AM"] = 0
	d["start_day"]["LATE"] = 2
