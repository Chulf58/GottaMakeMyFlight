class_name TestArrivalTimeline
extends GdUnitTestSuite
## Relaxed passengers arrive before their flight's first state (decision
## passengers-get-an-arrival-type-rushed-typical-or-relaxed): the occurrence
## is already issued when they come, a save taken before the first state keeps
## them and their pending arrivals, and the flight timeline and contract
## fields stay as they were.

## 10:00: the occurrence departs at tick 4800, its first state is at 2840, it
## is issued at 440 and its doors close at 4740.
const CONTRACT := "ARR"
const OCCURRENCE := "ARR-d0"
const MINUTE := 600
const FIRST := 2840
const ISSUED := 440
const DEPARTURE := 4800
const BOOKED := 40
## The one-off flight's first state in the save tests.
const SAVE_FIRST := 4400

var _a: PassengerTestWorld
var _b: PassengerTestWorld
var _issued_at := -1
var _spawned_while_listed: Array[bool] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for world in [_a, _b]:
		if world != null:
			world.free_all()
	_a = null
	_b = null
	_issued_at = -1
	_spawned_while_listed.clear()


func test_the_occurrence_exists_before_its_first_passenger_spawns() -> void:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	_a = PassengerTestWorld.make(grid, FlightSim.schedule_starts(100000), 3)
	# A FlightSim starts closed; this contract flies from an open airport.
	_a.flights.open_airport()
	_a.flights.occurrence_added.connect(func(_id: String) -> void: _issued_at = _a.clock.tick)
	_a.sim.passenger_spawned.connect(_on_spawned)
	var terms := TestFlightContracts.terms(CONTRACT, MINUTE)
	terms["booked_passengers"] = BOOKED
	assert_bool(_a.flights.accept_contract(terms)).is_true()
	_a.run_to(FIRST + 1200)
	assert_int(_a.flights.state_start(OCCURRENCE, FlightSim.State.SCHEDULED)).is_equal(FIRST)
	assert_int(_a.flights.state_start(OCCURRENCE, FlightSim.State.PUSHBACK)).is_equal(DEPARTURE)
	assert_int(_issued_at).is_equal(ISSUED)
	var earliest := 1 << 40
	var before_first := 0
	for id in _a.sim.passenger_ids():
		var spawned := _a.passenger(id).spawn_tick
		earliest = mini(earliest, spawned)
		before_first += int(spawned < FIRST + 1)
	print(
		(
			"issued %d, earliest spawn %d, %d spawned before the first state"
			% [_issued_at, earliest, before_first]
		)
	)
	assert_int(_a.sim.passenger_ids().size()).is_equal(BOOKED)
	assert_int(earliest).is_greater(_issued_at)
	assert_int(earliest).is_greater_equal(DEPARTURE - ArrivalTypes.RELAXED_LEAD_TICKS)
	assert_int(before_first).is_greater(0)
	assert_array(_spawned_while_listed).not_contains([false])
	# However early relaxed arrivals may come, the occurrence is issued first.
	var earliest_offset := FlightTimetable.departure_offset() - ArrivalTypes.RELAXED_LEAD_TICKS
	assert_int(-FlightTimetable.ISSUE_LEAD_TICKS).is_less(earliest_offset)


func _on_spawned(id: int) -> void:
	var p := _a.passenger(id)
	_spawned_while_listed.append(_a.flights.flight_ids().has(p.flight_id))


func test_the_timeline_and_contract_fields_are_unchanged() -> void:
	var phases: Array[int] = [100, 120, 140, 300, 40, 1200, 60, 120, 300, 200]
	assert_array(FlightSim.PHASE_TICKS).is_equal(phases)
	assert_int(FlightTimetable.departure_offset()).is_equal(1960)
	(
		assert_array(FlightContract.KEYS)
		. is_equal(
			[
				"id",
				"airline",
				"destination",
				"departure_minute",
				"gate",
				"plane_size",
				"booked_passengers",
				"fee_per_passenger",
				"first_day",
			]
		)
	)


func _save(world: PassengerTestWorld) -> String:
	return (
		JSON
		. stringify(
			{
				"clock": world.clock.to_snapshot(),
				"flights": world.flights.to_snapshot(),
				"grid": world.grid.to_snapshot(),
				"passengers": world.sim.to_snapshot(),
			}
		)
	)


func _load(text: String) -> PassengerTestWorld:
	var data: Dictionary = JSON.parse_string(text)
	var grid := BuildGrid.new()
	assert_bool(grid.from_snapshot(data["grid"])).is_true()
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), 99)
	assert_bool(world.clock.from_snapshot(data["clock"])).is_true()
	assert_bool(world.flights.from_snapshot(data["flights"])).is_true()
	assert_bool(world.sim.from_snapshot(data["passengers"])).is_true()
	return world


func _types(world: PassengerTestWorld) -> Array:
	var out := []
	for id in world.sim.passenger_ids():
		out.append([id, int(world.passenger(id).arrival_type)])
	return out


## A save before the flight's first state, with relaxed passengers already in
## the terminal and the rest still to come.
func _saved_early() -> Dictionary:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	_a = PassengerTestWorld.make(grid, FlightSim.schedule_starts(SAVE_FIRST), 21)
	assert_bool(_a.sim.schedule_flight(PassengerTestWorld.FLIGHT, BOOKED)).is_true()
	_a.run_to(SAVE_FIRST - 100)
	assert_int(_a.flights.state_of(PassengerTestWorld.FLIGHT)).is_equal(FlightSim.State.SCHEDULED)
	assert_int(_a.sim.passenger_ids().size()).is_greater(0)
	assert_int(_a.sim.pending_spawns()).is_greater(0)
	for id in _a.sim.passenger_ids():
		assert_int(_a.passenger(id).arrival_type).is_equal(ArrivalTypes.Type.RELAXED)
	return JSON.parse_string(JSON.stringify(_a.sim.to_snapshot()))


func test_a_save_before_the_first_state_keeps_arrival_types_and_plays_out_the_same() -> void:
	var data := _saved_early()
	var pending_types := {}
	for entry: Dictionary in data["schedule"]:
		pending_types[int(entry["arrival"])] = true
	assert_int(pending_types.size()).is_equal(3)
	_b = _load(_save(_a))
	assert_str(_b.signature()).is_equal(_a.signature())
	assert_array(_types(_b)).is_equal(_types(_a))
	var doors := _a.flights.doors_close_tick(PassengerTestWorld.FLIGHT)
	var first_bad := -1
	while _a.clock.tick <= doors and first_bad < 0:
		_a.step()
		_b.step()
		if _a.signature() != _b.signature() or _types(_a) != _types(_b):
			first_bad = _a.clock.tick
	assert_int(first_bad).override_failure_message("first differing tick %d" % first_bad).is_equal(
		-1
	)
	assert_int(_a.sim.made_count() + _a.sim.missed_count()).is_equal(BOOKED)
	assert_int(_b.sim.made_count()).is_equal(_a.sim.made_count())


func test_bad_arrival_types_and_version_5_saves_are_refused_whole() -> void:
	var good := _saved_early()
	assert_int(int(good["save_version"])).is_equal(PassengerSim.SAVE_VERSION)
	var bad_cases: Array[Dictionary] = []
	for value in [-1, 3, 1.5, "relaxed"]:
		var record := good.duplicate(true)
		record["passengers"][0]["arrival_type"] = value
		bad_cases.append(record)
		var entry := good.duplicate(true)
		entry["schedule"][0]["arrival"] = value
		bad_cases.append(entry)
	var no_record_type := good.duplicate(true)
	no_record_type["passengers"][0].erase("arrival_type")
	bad_cases.append(no_record_type)
	var no_entry_type := good.duplicate(true)
	no_entry_type["schedule"][0].erase("arrival")
	bad_cases.append(no_entry_type)
	var version_5 := good.duplicate(true)
	version_5["save_version"] = 5
	bad_cases.append(version_5)
	_b = PassengerTestWorld.reference_world()
	var before := _b.signature()
	for bad in bad_cases:
		assert_bool(_b.sim.from_snapshot(bad)).is_false()
		assert_str(_b.signature()).is_equal(before)
		assert_int(_b.sim.pending_spawns()).is_equal(0)
	assert_bool(_b.sim.from_snapshot(good)).is_true()
