class_name TestPassengerV9Migration
extends GdUnitTestSuite
## Version 9 and version 8 passenger saves (no toilet need, cooldown or
## visits) load into version 10 (decision toilet-design-queue-free-
## reservable-stalls-per-stall-daily-u, point 6): each passenger gets the need
## ToiletSim.migrated_need() gives its id and no cooldown, nobody is on a toilet
## visit, nothing is drawn from the sim RNG, and the game plays on like a
## continuous one whose passengers held those needs at the save. A version 9 save
## naming a stage version 9 did not have is refused.

const SAVE_TICK := 205
const TOILET_FIELDS := ["toilet_need", "toilet_cooldown"]

var _a: PassengerTestWorld
var _b: PassengerTestWorld
var _v10: Dictionary


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_a = PassengerTestWorld.reference_world(4242)
	_a.sim.schedule_flight(PassengerTestWorld.FLIGHT, 24)
	for i in 10:
		_a.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_a.run_to(SAVE_TICK)
	# The game a migrated save is compared with: at the save, every passenger
	# holds the need migration gives it and no cooldown. Later spawns draw
	# theirs from the sim RNG in both.
	for id in _a.sim.passenger_ids():
		_a.passenger(id).toilet_need = ToiletSim.migrated_need(id)
		_a.passenger(id).toilet_cooldown = 0
	_v10 = _json(_a.sim.to_snapshot())


func after_test() -> void:
	for world in [_a, _b]:
		if world != null:
			world.free_all()
	_a = null
	_b = null


func _json(data: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(data))


## The fixture in the shape `version` (8 or 9) saved: no toilet fields on a
## passenger record and no "toilet" block.
func _old(version: int) -> Dictionary:
	var data := _v10.duplicate(true)
	data["save_version"] = version
	data.erase("toilet")
	for record: Dictionary in data["passengers"]:
		for field in TOILET_FIELDS:
			record.erase(field)
	return data


## A world holding `a`'s clock and flights, with the passenger part not yet
## loaded.
func _fresh() -> PassengerTestWorld:
	var world := PassengerTestWorld.reference_world(1)
	world.clock.from_snapshot(_json(_a.clock.to_snapshot()))
	world.flights.from_snapshot(_json(_a.flights.to_snapshot()))
	return world


func _needs(world: PassengerTestWorld) -> Array:
	var out: Array = []
	for id in world.sim.passenger_ids():
		var p := world.passenger(id)
		out.append([id, p.toilet_need, p.toilet_cooldown])
	return out


func test_the_fixture_is_a_real_save_without_toilets() -> void:
	assert_int(PassengerSim.SAVE_VERSION).is_equal(10)
	for version in [8, 9]:
		var data := _old(version)
		assert_bool(data.has("toilet")).is_false()
		assert_int(data["passengers"].size()).is_greater(10)
		for record: Dictionary in data["passengers"]:
			for field in TOILET_FIELDS:
				assert_bool(record.has(field)).is_false()


func test_version_9_and_8_saves_load_with_needs_from_the_id_and_no_visits() -> void:
	for version in [9, 8]:
		_b = _fresh()
		var rng_before := _b.clock.rng.state
		assert_bool(_b.sim.from_snapshot(_old(version))).is_true()
		# Nothing was drawn from the sim RNG.
		assert_int(_b.clock.rng.state).is_equal(rng_before)
		assert_int(_b.clock.rng.state).is_equal(_a.clock.rng.state)
		assert_array(_b.sim.toilets.visit_ids()).is_empty()
		var seen := {}
		for id in _b.sim.passenger_ids():
			var p := _b.passenger(id)
			assert_int(p.toilet_need).is_equal(ToiletSim.migrated_need(id))
			assert_int(p.toilet_need).is_between(ToiletSim.NEED_START_MIN, ToiletSim.NEED_START_MAX)
			assert_int(p.toilet_cooldown).is_equal(0)
			seen[p.toilet_need] = true
		print(
			(
				"version %d: %d passengers, %d distinct needs"
				% [version, _b.sim.passenger_ids().size(), seen.size()]
			)
		)
		assert_int(seen.size()).is_greater(5)
		# A second load gives the same needs.
		var again := _fresh()
		assert_bool(again.sim.from_snapshot(_old(version))).is_true()
		assert_array(_needs(again)).is_equal(_needs(_b))
		again.free_all()
		_b.free_all()
		_b = null


func test_a_migrated_version_9_save_plays_on_like_the_game_it_came_from() -> void:
	_b = _fresh()
	assert_bool(_b.sim.from_snapshot(_old(9))).is_true()
	assert_str(_b.signature()).is_equal(_a.signature())
	assert_array(_needs(_b)).is_equal(_needs(_a))
	var doors := _a.flights.doors_close_tick(PassengerTestWorld.FLIGHT)
	var first_bad := -1
	while _a.clock.tick <= doors and first_bad < 0:
		_a.step()
		_b.step()
		if _a.signature() != _b.signature() or _needs(_a) != _needs(_b):
			first_bad = _a.clock.tick
	print("first differing tick %d, made %d" % [first_bad, _a.sim.made_count()])
	assert_int(first_bad).is_equal(-1)
	assert_int(_a.sim.made_count()).is_greater(0)


func test_a_migrated_world_saves_as_version_10_and_loads_again() -> void:
	_b = _fresh()
	assert_bool(_b.sim.from_snapshot(_old(9))).is_true()
	var again := _json(_b.sim.to_snapshot())
	assert_int(int(again["save_version"])).is_equal(10)
	assert_bool(again.has("toilet")).is_true()
	var third := _fresh()
	assert_bool(third.sim.from_snapshot(again)).is_true()
	assert_str(third.signature()).is_equal(_b.signature())
	assert_array(_needs(third)).is_equal(_needs(_b))
	third.free_all()


func test_migrating_does_not_edit_the_dictionary_it_was_given() -> void:
	var old := _old(9)
	var copy := old.duplicate(true)
	_b = _fresh()
	assert_bool(_b.sim.from_snapshot(old)).is_true()
	assert_bool(old == copy).is_true()


func test_a_version_9_save_naming_a_toilet_stage_is_refused() -> void:
	var old := _old(9)
	(old["passengers"][0] as Dictionary)["stage"] = Passenger.Stage.TOILET_USE
	_b = _fresh()
	var before := _b.signature()
	var problem: String = PassengerSnapshot.load(old, _b.grid).get("error", "")
	print("refused: %s" % problem)
	assert_str(problem).contains("at a toilet with no visit")
	assert_bool(_b.sim.from_snapshot(old)).is_false()
	assert_str(_b.signature()).is_equal(before)
