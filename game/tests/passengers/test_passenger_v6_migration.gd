class_name TestPassengerV6Migration
extends GdUnitTestSuite
## A version 6 passenger save (no carry-on traits) loads into the current
## version with zero bags and no liquids or alarm, everything else as saved
## and no RNG drawn; a native version 7 save missing a trait is refused, and
## so is version 5 (decision security-lane-technical-design-one-station-per-
## lane-with-int, point 7). Carry-on now changes security times, so the
## continuous world the migrated one is compared with has every trait zeroed
## at spawn, as a version 6 world had; the fixtures are written in the shape
## version 7 saved (SecurityTestWorld.as_v7()).

const SAVE_TICK := 205
const TRAIT_FIELDS := ["carry_on", "liquids", "alarm"]

var _a: PassengerTestWorld
var _b: PassengerTestWorld
var _v7: Dictionary


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_a = PassengerTestWorld.reference_world(4242)
	_zero_traits_of(_a)
	_a.sim.schedule_flight(PassengerTestWorld.FLIGHT, 24)
	for i in 10:
		_a.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_a.run_to(SAVE_TICK)
	# At the save every passenger holds the toilet need migration gives it
	# (version 10), so the continuous world plays like the migrated one.
	for id in _a.sim.passenger_ids():
		_a.passenger(id).toilet_need = ToiletSim.migrated_need(id)
		_a.passenger(id).toilet_cooldown = 0
		# And the boredom version 11 migration gives it.
		_a.passenger(id).boredom = BoredomSim.start_of(id)
	_v7 = SecurityTestWorld.as_v7(_json(_a.sim.to_snapshot()))


## Every passenger `world` spawns gets what a version 6 world had: no bags,
## liquids or alarm. Both worlds a comparison steps need it, as passengers
## still spawn after the save.
static func _zero_traits_of(world: PassengerTestWorld) -> void:
	world.sim.passenger_spawned.connect(
		func(id: int) -> void:
			var p := world.passenger(id)
			p.carry_on = 0
			p.liquids = false
			p.alarm = false
	)


func after_test() -> void:
	for world in [_a, _b]:
		if world != null:
			world.free_all()
	_a = null
	_b = null


func _json(data: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(data))


## The shape version 6 saved: no trait fields on a passenger record.
func _v6() -> Dictionary:
	var data := _v7.duplicate(true)
	data["save_version"] = 6
	for record: Dictionary in data["passengers"]:
		for field in TRAIT_FIELDS:
			record.erase(field)
	return data


## A world holding `a`'s clock and flights, with the passenger part not yet
## loaded.
func _fresh() -> PassengerTestWorld:
	var world := PassengerTestWorld.reference_world(1)
	_zero_traits_of(world)
	world.clock.from_snapshot(_json(_a.clock.to_snapshot()))
	world.flights.from_snapshot(_json(_a.flights.to_snapshot()))
	return world


func test_the_fixture_is_a_real_mid_service_save_without_traits() -> void:
	var data := _v6()
	assert_int(int(data["save_version"])).is_equal(6)
	var serving := 0
	for record: Dictionary in data["passengers"]:
		for field in TRAIT_FIELDS:
			assert_bool(record.has(field)).is_false()
		serving += int(int(record["stage"]) == Passenger.Stage.CHECKIN)
	assert_int(data["passengers"].size()).is_greater(0)
	assert_int(serving).is_greater(0)


func test_a_version_6_save_loads_with_zero_bags_and_no_flags() -> void:
	_b = _fresh()
	assert_bool(_b.sim.from_snapshot(_v6())).is_true()
	assert_int(_b.sim.passenger_ids().size()).is_equal(_a.sim.passenger_ids().size())
	for id in _b.sim.passenger_ids():
		var p := _b.passenger(id)
		assert_int(p.boredom).is_equal(BoredomSim.start_of(id))
		assert_int(p.carry_on).is_equal(0)
		assert_bool(p.liquids).is_false()
		assert_bool(p.alarm).is_false()


func test_migration_changes_nothing_else_and_in_progress_service_continues() -> void:
	_b = _fresh()
	assert_bool(_b.sim.from_snapshot(_v6())).is_true()
	assert_str(_b.signature()).is_equal(_a.signature())
	for id in _a.sim.passenger_ids():
		var want := _a.passenger(id)
		var got := _b.passenger(id)
		# A scanner's service is its remaining work now; service_end is the
		# desk's.
		if want.stage != Passenger.Stage.SECURITY:
			assert_int(got.service_end).is_equal(want.service_end)
		assert_int(got.security_phase).is_equal(want.security_phase)
		assert_int(got.security_work).is_equal(want.security_work)
		assert_int(got.station).is_equal(want.station)
		assert_int(got.hunger).is_equal(want.hunger)
		assert_int(got.arrival_type).is_equal(want.arrival_type)
	var doors := _a.flights.doors_close_tick(PassengerTestWorld.FLIGHT)
	var first_bad := -1
	while _a.clock.tick <= doors and first_bad < 0:
		_a.step()
		_b.step()
		if _a.signature() != _b.signature():
			first_bad = _a.clock.tick
	assert_int(first_bad).override_failure_message("first differing tick %d" % first_bad).is_equal(
		-1
	)
	assert_int(_b.sim.made_count()).is_equal(_a.sim.made_count())
	assert_int(_b.sim.missed_count()).is_equal(_a.sim.missed_count())


func test_loading_a_version_6_save_draws_no_random_numbers() -> void:
	_b = _fresh()
	var seed_before := _b.clock.rng.seed
	var state_before := _b.clock.rng.state
	assert_bool(_b.sim.from_snapshot(_v6())).is_true()
	assert_int(_b.clock.rng.seed).is_equal(seed_before)
	assert_int(_b.clock.rng.state).is_equal(state_before)


func test_a_migrated_world_saves_as_version_7_with_the_traits() -> void:
	_b = _fresh()
	assert_bool(_b.sim.from_snapshot(_v6())).is_true()
	var again := _json(_b.sim.to_snapshot())
	assert_int(int(again["save_version"])).is_equal(PassengerSim.SAVE_VERSION)
	for record: Dictionary in again["passengers"]:
		assert_int(int(record["carry_on"])).is_equal(0)
		assert_bool(record["liquids"]).is_false()
		assert_bool(record["alarm"]).is_false()
	var third := _fresh()
	assert_bool(third.sim.from_snapshot(again)).is_true()
	assert_str(third.signature()).is_equal(_a.signature())
	third.free_all()


func test_migrating_does_not_edit_the_dictionary_it_was_given() -> void:
	var data := _v6()
	var copy := data.duplicate(true)
	_b = _fresh()
	assert_bool(_b.sim.from_snapshot(data)).is_true()
	assert_bool(data == copy).is_true()


func test_a_version_6_save_with_a_bad_record_is_still_refused() -> void:
	var bad_stage := _v6()
	bad_stage["passengers"][0]["stage"] = 99
	var bad_version := _v6()
	bad_version["save_version"] = 5
	var bad_array := _v6()
	bad_array["passengers"] = "none"
	var bad_record := _v6()
	bad_record["passengers"][0] = 7
	_b = _fresh()
	var before := _b.signature()
	for bad: Dictionary in [bad_stage, bad_version, bad_array, bad_record]:
		assert_bool(_b.sim.from_snapshot(bad)).is_false()
		assert_str(_b.signature()).is_equal(before)


func test_a_native_version_7_save_missing_a_trait_is_refused() -> void:
	_b = _fresh()
	assert_bool(_b.sim.from_snapshot(_v7.duplicate(true))).is_true()
	for field in TRAIT_FIELDS:
		var data := _v7.duplicate(true)
		(data["passengers"][0] as Dictionary).erase(field)
		assert_bool(_b.sim.from_snapshot(data)).override_failure_message(field).is_false()


func test_bad_trait_values_in_a_version_7_save_are_refused() -> void:
	var cases := [
		["carry_on", -1],
		["carry_on", 3],
		["carry_on", 1.5],
		["carry_on", "1"],
		["liquids", 1],
		["liquids", "true"],
		["alarm", 0],
		["alarm", null],
	]
	_b = _fresh()
	for pair: Array in cases:
		var data := _v7.duplicate(true)
		data["passengers"][0][pair[0]] = pair[1]
		(
			assert_bool(_b.sim.from_snapshot(data))
			. override_failure_message("%s = %s" % [pair[0], str(pair[1])])
			. is_false()
		)
