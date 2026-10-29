class_name TestPassengerV10Migration
extends GdUnitTestSuite
## A version 10 passenger save (no boredom, kiosk cooldown or kiosk visits)
## loads into version 11 (decision boredom-and-shops-design-boredom-need-
## while-waiting-kiosk-sh, point 4): each passenger gets the boredom
## BoredomSim.start_of() gives its id and no kiosk cooldown, every toilet
## need, cooldown and visit under way is kept as saved, nobody is on a kiosk
## visit, nothing is drawn from the sim RNG, and the game plays on like a
## continuous one whose passengers held that boredom at the save. A version 11
## save missing boredom, or holding it out of range, is refused.

## How long the loaded game is played beside the one it came from: past the
## end of the toilet visit and well into the walk on.
const REPLAY_TICKS := 600

var _a: PassengerTestWorld
var _b: PassengerTestWorld
var _v11: Dictionary


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


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
	ToiletTestLayout.build(grid)
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), seed)
	_needs_in(world)
	return world


func before_test() -> void:
	_a = _toilet_world(4242)
	_a.sim.schedule_flight(PassengerTestWorld.FLIGHT, 24)
	for i in 10:
		_a.sim.spawn_now(PassengerTestWorld.FLIGHT)
	while not _in_stall(_a) and _a.clock.tick < 4000:
		_a.step()
	# The game a migrated save is compared with: at the save, every passenger
	# holds the boredom migration gives it.
	for id in _a.sim.passenger_ids():
		_a.passenger(id).boredom = BoredomSim.start_of(id)
		_a.passenger(id).shop_cooldown = 0
	_v11 = _json(_a.sim.to_snapshot())


func after_test() -> void:
	for world in [_a, _b]:
		if world != null:
			world.free_all()
	_a = null
	_b = null


func _json(data: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(data))


## Whether a passenger in `world` is using a toilet stall.
func _in_stall(world: PassengerTestWorld) -> bool:
	for id in world.sim.toilets.visit_ids():
		if world.passenger(id).stage == Passenger.Stage.TOILET_USE:
			return true
	return false


## The fixture in the shape version 10 saved: no boredom on a passenger record.
func _v10() -> Dictionary:
	var data := _v11.duplicate(true)
	data["save_version"] = 10
	data.erase("shop")
	for record: Dictionary in data["passengers"]:
		record.erase("boredom")
		record.erase("shop_cooldown")
	return data


## A world holding `a`'s grid, clock and flights, with the passenger part not
## yet loaded.
func _fresh() -> PassengerTestWorld:
	var world := _toilet_world(1)
	world.clock.from_snapshot(_json(_a.clock.to_snapshot()))
	world.flights.from_snapshot(_json(_a.flights.to_snapshot()))
	return world


## Every toilet need and cooldown, toilet visit and boredom.
func _needs(world: PassengerTestWorld) -> Array:
	var out: Array = [world.sim.toilets.visit_ids()]
	for id in world.sim.passenger_ids():
		var p := world.passenger(id)
		out.append([id, p.toilet_need, p.toilet_cooldown, p.boredom, p.stage_tick])
	return out


func test_the_fixture_is_a_version_10_save_with_a_toilet_visit_under_way() -> void:
	assert_int(PassengerSim.SAVE_VERSION).is_equal(12)
	var data := _v10()
	assert_bool(_in_stall(_a)).is_true()
	assert_array(data["toilet"]["visits"]).is_not_empty()
	assert_int(data["passengers"].size()).is_greater(10)
	for record: Dictionary in data["passengers"]:
		assert_bool(record.has("boredom")).is_false()
		assert_bool(record.has("shop_cooldown")).is_false()
		assert_bool(record.has("toilet_need")).is_true()
	assert_bool(data.has("shop")).is_false()


func test_a_version_10_save_keeps_its_toilet_visits_and_gets_boredom_from_the_id() -> void:
	_b = _fresh()
	var rng_before := _b.clock.rng.state
	assert_bool(_b.sim.from_snapshot(_v10())).is_true()
	# Nothing was drawn from the sim RNG.
	assert_int(_b.clock.rng.state).is_equal(rng_before)
	assert_int(_b.clock.rng.state).is_equal(_a.clock.rng.state)
	# The visit under way, and every toilet need and cooldown, are as saved.
	print("visits kept: %s" % [_b.sim.toilets.visit_ids()])
	assert_array(_b.sim.toilets.visit_ids()).is_not_empty()
	assert_array(_needs(_b)).is_equal(_needs(_a))
	assert_array(_b.sim.shops.visit_ids()).is_empty()
	for id in _b.sim.toilets.visit_ids():
		var kept := _b.sim.toilets.visit_of(id)
		var saved := _a.sim.toilets.visit_of(id)
		assert_int(kept.stall_id).is_equal(saved.stall_id)
		assert_int(kept.deadline).is_equal(saved.deadline)
	for id in _b.sim.passenger_ids():
		var p := _b.passenger(id)
		assert_int(p.boredom).is_equal(BoredomSim.start_of(id))
		assert_int(p.shop_cooldown).is_equal(0)
		assert_int(p.toilet_need).is_equal(_a.passenger(id).toilet_need)


func test_a_migrated_version_10_save_plays_on_like_the_game_it_came_from() -> void:
	_b = _fresh()
	assert_bool(_b.sim.from_snapshot(_v10())).is_true()
	assert_str(_b.signature()).is_equal(_a.signature())
	var end := _a.clock.tick + REPLAY_TICKS
	var first_bad := -1
	var used := 0
	while _a.clock.tick < end and first_bad < 0:
		_a.step()
		_b.step()
		used += int(_in_stall(_a))
		if _a.signature() != _b.signature() or _needs(_a) != _needs(_b):
			first_bad = _a.clock.tick
	print("first differing tick %d, ticks in a stall %d" % [first_bad, used])
	assert_int(first_bad).is_equal(-1)
	assert_int(used).is_greater(0)
	# The visit ran out within the replay.
	assert_bool(_in_stall(_a)).is_false()


func test_a_migrated_world_saves_as_the_current_version_and_loads_again() -> void:
	_b = _fresh()
	assert_bool(_b.sim.from_snapshot(_v10())).is_true()
	var again := _json(_b.sim.to_snapshot())
	assert_int(int(again["save_version"])).is_equal(12)
	for record: Dictionary in again["passengers"]:
		assert_bool(record.has("boredom")).is_true()
	var third := _fresh()
	assert_bool(third.sim.from_snapshot(again)).is_true()
	assert_str(third.signature()).is_equal(_b.signature())
	assert_array(_needs(third)).is_equal(_needs(_b))
	third.free_all()


func test_migrating_does_not_edit_the_dictionary_it_was_given() -> void:
	var old := _v10()
	var copy := old.duplicate(true)
	_b = _fresh()
	assert_bool(_b.sim.from_snapshot(old)).is_true()
	assert_bool(old == copy).is_true()


func test_a_version_11_save_missing_boredom_or_out_of_range_is_refused() -> void:
	_b = _fresh()
	var before := _b.signature()
	var missing := _v11.duplicate(true)
	(missing["passengers"][0] as Dictionary).erase("boredom")
	var high := _v11.duplicate(true)
	(high["passengers"][0] as Dictionary)["boredom"] = BoredomSim.MAX + 1
	var low := _v11.duplicate(true)
	(low["passengers"][0] as Dictionary)["boredom"] = -1
	for bad in [missing, high, low]:
		var problem: String = PassengerSnapshot.load(bad, _b.grid).get("error", "")
		print("refused: %s" % problem)
		assert_str(problem).is_not_empty()
		assert_bool(_b.sim.from_snapshot(bad)).is_false()
		assert_str(_b.signature()).is_equal(before)
	assert_bool(_b.sim.from_snapshot(_v11)).is_true()
