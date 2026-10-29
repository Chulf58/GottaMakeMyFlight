class_name TestToiletSnapshot
extends GdUnitTestSuite
## Toilet visits in the passenger save (ToiletSnapshot, PassengerSim save
## version 10): a save taken in any phase of a visit loads and plays on tick
## for tick like the game it came from; a toilet state no play could reach is
## refused and changes nothing.

## How long a loaded game is played beside the one it came from: past the end
## of every visit and well into the walk on.
const REPLAY_TICKS := 600

var _a: PassengerTestWorld
var _b: PassengerTestWorld
var _ids: Dictionary
## Tick -> _signature(_a) after that tick.
var _trace: Dictionary = {}
## Passenger id -> whether it made the flight, in world A.
var _made: Dictionary = {}


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
	_trace.clear()
	_made.clear()


## Passengers 1 and 2 need a toilet from spawn, nobody else ever does. Every
## world that plays the flight needs it, as passengers still spawn after a
## save.
static func _needs_in(world: PassengerTestWorld) -> void:
	world.sim.passenger_spawned.connect(
		func(id: int) -> void:
			var p := world.passenger(id)
			p.toilet_need = 95 if id <= 2 else 0
			p.toilet_cooldown = 0 if id <= 2 else 1000000
	)


func _toilet_world(seed: int) -> PassengerTestWorld:
	var grid := BuildGrid.new()
	_ids = ToiletTestLayout.build(grid)
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), seed)
	return world


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


## A world loaded from `text`, or null when the passengers were refused.
func _load(text: String) -> PassengerTestWorld:
	var data: Dictionary = JSON.parse_string(text)
	var grid := BuildGrid.new()
	assert_bool(grid.from_snapshot(data["grid"])).is_true()
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), 99)
	assert_bool(world.clock.from_snapshot(data["clock"])).is_true()
	assert_bool(world.flights.from_snapshot(data["flights"])).is_true()
	assert_bool(world.sim.from_snapshot(data["passengers"])).is_true()
	return world


## The passenger signature plus every toilet need, cooldown and visit.
func _signature(world: PassengerTestWorld) -> String:
	var toilets := world.sim.toilets
	var parts := PackedStringArray([world.signature()])
	for id in world.sim.passenger_ids():
		var p := world.passenger(id)
		parts.append("%d:%d:%d:%d" % [id, p.toilet_need, p.toilet_cooldown, p.stage_tick])
	for id in toilets.visit_ids():
		var v := toilets.visit_of(id)
		parts.append(
			(
				"v%d|%d|%d|%d|%d|%d"
				% [
					id,
					v.room,
					v.stall_id,
					v.resume_stage,
					v.deadline,
					toilets.stall_holder(v.stall_id)
				]
			)
		)
	return ";".join(parts)


## World A with a flight's passengers, two of them made to need a toilet now,
## run to the doors closing. A save is taken on the first tick each visit
## phase starts, and A's signature is traced every tick. Returns {phase name: save}.
func _play_and_save() -> Dictionary:
	_a = _toilet_world(4242)
	var saves := {}
	var sim := _a.sim
	assert_bool(sim.schedule_flight(PassengerTestWorld.FLIGHT, 12)).is_true()
	_needs_in(_a)
	sim.outcome.connect(func(id: int, made: bool) -> void: _made[id] = made)
	var doors := _a.flights.doors_close_tick(PassengerTestWorld.FLIGHT)
	while _a.clock.tick <= doors:
		_a.step()
		for id in sim.toilets.visit_ids():
			var p := _a.passenger(id)
			var stage: String = Passenger.Stage.keys()[p.stage]
			if not saves.has(stage) and p.stage_tick == _a.clock.tick:
				saves[stage] = _save(_a)
		_trace[_a.clock.tick] = _signature(_a)
	return saves


func test_a_save_in_every_phase_of_a_visit_loads_and_plays_on_alike() -> void:
	var saves := _play_and_save()
	print("saved in %s" % [saves.keys()])
	for stage in [
		"TOILET_WALK",
		"TOILET_ENTER",
		"TOILET_SITTING_DOWN",
		"TOILET_USE",
		"TOILET_STANDING_UP",
		"TOILET_EXIT",
	]:
		assert_bool(saves.has(stage)).override_failure_message("no save in %s" % stage).is_true()
	var doors := _a.flights.doors_close_tick(PassengerTestWorld.FLIGHT)
	for stage: String in saves:
		_b = _load(saves[stage])
		_needs_in(_b)
		var start := _b.clock.tick
		assert_str(_signature(_b)).is_equal(_trace[start])
		var first_bad := -1
		while _b.clock.tick <= mini(doors, start + REPLAY_TICKS) and first_bad < 0:
			_b.step()
			if _signature(_b) != _trace[_b.clock.tick]:
				first_bad = _b.clock.tick
		print("%s saved at %d: first differing tick %d" % [stage, start, first_bad])
		assert_int(first_bad).override_failure_message("%s differs" % stage).is_equal(-1)
		_b.free_all()
		_b = null
	# The guests used the stalls and boarded.
	for id in [1, 2]:
		assert_bool(_made.get(id, false)).is_true()


func test_a_toilet_state_no_play_could_reach_is_refused_and_changes_nothing() -> void:
	var saves := _play_and_save()
	var good: Dictionary = JSON.parse_string(saves["TOILET_USE"])["passengers"]
	var visit: Dictionary = good["toilet"]["visits"][0]
	var guest := int(visit["passenger"])
	var cases: Array = []
	var copy := func() -> Dictionary: return good.duplicate(true)
	var record_of := func(data: Dictionary) -> Dictionary:
		for record: Dictionary in data["passengers"]:
			if int(record["id"]) == guest:
				return record
		return {}
	var d: Dictionary = copy.call()
	d["toilet"]["visits"][0]["stall"] = 9999
	cases.append(["no such toilet stall", d])
	d = copy.call()
	d["toilet"]["visits"] = []
	cases.append(["at a toilet with no visit", d])
	d = copy.call()
	record_of.call(d)["stage"] = Passenger.Stage.TO_SECURITY
	cases.append(["has a toilet visit but is not at a toilet", d])
	d = copy.call()
	var side := int(visit["resume_stage"])
	d["toilet"]["visits"][0]["resume_stage"] = (
		Passenger.Stage.TO_GATE
		if side == Passenger.Stage.TO_SECURITY
		else Passenger.Stage.TO_SECURITY
	)
	cases.append(["other side of security", d])
	d = copy.call()
	var at: Array = record_of.call(d)["at"]
	record_of.call(d)["at"] = [at[0], int(at[1]) + 1]
	cases.append(["not on its approach cell", d])
	d = copy.call()
	record_of.call(d)["stage_tick"] = int(str(d["tick"])) - ToiletSim.USE_TICKS
	cases.append(["does not run past the saved tick", d])
	d = copy.call()
	d["toilet"]["visits"].append(d["toilet"]["visits"][0].duplicate())
	cases.append(["malformed or repeated", d])
	d = copy.call()
	record_of.call(d)["toilet_need"] = ToiletSim.NEED_MAX + 1
	cases.append(["malformed or repeated", d])
	d = copy.call()
	d["toilet"]["deadlines_stale"] = "no"
	cases.append(["deadlines_stale must be true or false", d])
	d = copy.call()
	d.erase("toilet")
	cases.append(["missing key 'toilet'", d])
	_b = _toilet_world(1)
	var before := _signature(_b)
	for entry: Array in cases:
		var expected: String = entry[0]
		var problem: String = PassengerSnapshot.load(entry[1], _b.grid).get("error", "")
		print("%s -> %s" % [expected, problem])
		assert_str(problem).contains(expected)
		assert_bool(_b.sim.from_snapshot(entry[1])).is_false()
		assert_str(_signature(_b)).is_equal(before)
	# Control: the unaltered save loads.
	assert_bool(_b.sim.from_snapshot(good)).is_true()


func test_a_save_with_stale_toilet_deadlines_keeps_them_stale_for_the_next_tick() -> void:
	var saves := _play_and_save()
	var data: Dictionary = JSON.parse_string(saves["TOILET_USE"])
	var passengers: Dictionary = data["passengers"]
	var guest := int(passengers["toilet"]["visits"][0]["passenger"])
	passengers["toilet"]["deadlines_stale"] = true
	passengers["toilet"]["visits"][0]["deadline"] = 1
	_b = _load(JSON.stringify(data))
	assert_bool(_b.sim.toilets.deadlines_stale).is_true()
	assert_int(_b.sim.toilets.visit_of(guest).deadline).is_equal(1)
	_b.step()
	# The next tick worked the deadline out again, so the guest stays on.
	print("deadline after the next tick %d" % _b.sim.toilets.visit_of(guest).deadline)
	assert_bool(_b.sim.toilets.deadlines_stale).is_false()
	assert_int(_b.sim.toilets.visit_of(guest).deadline).is_greater(_b.clock.tick)
	assert_int(_b.passenger(guest).stage).is_equal(Passenger.Stage.TOILET_USE)
