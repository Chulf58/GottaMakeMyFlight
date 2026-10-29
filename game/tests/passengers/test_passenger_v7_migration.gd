class_name TestPassengerV7Migration
extends GdUnitTestSuite
## A version 7 passenger save (before the security runtime) loads into
## version 8. A basic scanner's service in progress stays exactly as it was:
## it ends on its saved service end, with no bag time or repack added even for
## a passenger with bags and liquids, and nothing is drawn. Everyone else has
## no security phase (decision security-lane-technical-design-one-station-per-
## lane-with-int, point 4).

## Ticks left of the saved service: longer than the passage walk still to go.
const LEFT := 50

var _a: SecurityTestWorld
var _b: SecurityTestWorld
var _first := 0
var _second := 0
var _v7: Dictionary


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_a = SecurityTestWorld.make(false)
	var ids := _a.send_all([[2, true, false], [1, false, false]])
	_first = ids[0]
	_second = ids[1]
	while not _a.admitted.has(_first):
		_a.world.step()
	_a.world.run_to(_a.world.clock.tick + 5)
	_v7 = SecurityTestWorld.as_v7(_json(_a.world.sim.to_snapshot()))
	for record: Dictionary in _v7["passengers"]:
		if int(record["id"]) == _first:
			record["service_end"] = _a.world.sim.tick + LEFT


func after_test() -> void:
	for w in [_a, _b]:
		if w != null:
			w.world.free_all()
	_a = null
	_b = null


func _json(data: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(data))


func _fresh() -> SecurityTestWorld:
	var w := SecurityTestWorld.make(false)
	w.world.clock.from_snapshot(_json(_a.world.clock.to_snapshot()))
	w.world.flights.from_snapshot(_json(_a.world.flights.to_snapshot()))
	return w


func test_the_fixture_is_a_version_7_save_mid_scan() -> void:
	assert_int(int(_v7["save_version"])).is_equal(7)
	assert_bool(_v7.has("security")).is_false()
	var serving := 0
	for queue: Dictionary in _v7["queues"]:
		serving = maxi(serving, int(queue["serving"]))
	assert_int(serving).is_equal(_first)
	for record: Dictionary in _v7["passengers"]:
		assert_bool(record.has("security_phase")).is_false()
		if int(record["id"]) == _first:
			assert_int(int(record["stage"])).is_equal(Passenger.Stage.SECURITY)
			assert_bool(record["liquids"]).is_true()
			assert_int(int(record["carry_on"])).is_equal(2)


func test_an_in_progress_basic_service_ends_on_its_saved_tick_with_no_repack() -> void:
	_b = _fresh()
	var seed_before := _b.world.clock.rng.seed
	var state_before := _b.world.clock.rng.state
	assert_bool(_b.world.sim.from_snapshot(_v7)).is_true()
	assert_int(_b.world.clock.rng.seed).is_equal(seed_before)
	assert_int(_b.world.clock.rng.state).is_equal(state_before)
	var p := _b.world.passenger(_first)
	var saved_at := _b.world.sim.tick
	assert_int(p.security_phase).is_equal(SecurityRuntime.Phase.SCAN)
	assert_int(p.security_work).is_equal(LEFT)
	assert_bool(p.incident_resolved).is_true()
	assert_int(p.stage).is_equal(Passenger.Stage.SECURITY)
	var record := _b.runtime_record()
	assert_array(record["admitted"]).is_equal([_first])
	assert_int(record["main"]).is_equal(_first)
	assert_int(_b.world.sim.queue_of(_b.station).size()).is_less_equal(1)
	assert_bool(_b.run_until_cleared([_first, _second])).is_true()
	print("saved at %d, cleared %s" % [saved_at, _b.cleared])
	assert_int(_b.cleared[_first]).is_equal(saved_at + LEFT)
	assert_int(p.security_phase).is_equal(SecurityRuntime.Phase.NONE)
	# The next passenger is served by the version 8 rules: one bag.
	var second_took: int = _b.cleared[_second] - _b.admitted[_second]
	assert_int(second_took).is_equal(
		SecurityRuntime.BASIC_SCAN_TICKS + SecurityRuntime.BASIC_BAG_TICKS
	)


func test_everyone_not_in_service_loads_with_no_phase() -> void:
	_b = _fresh()
	assert_bool(_b.world.sim.from_snapshot(_v7)).is_true()
	for id in _b.world.sim.passenger_ids():
		var p := _b.world.passenger(id)
		# Version 10 to 11: the boredom start from the id.
		assert_int(p.boredom).is_equal(BoredomSim.start_of(id))
		if id == _first:
			continue
		assert_int(p.security_phase).is_equal(SecurityRuntime.Phase.NONE)
		assert_int(p.security_work).is_equal(0)
		assert_bool(p.incident_resolved).is_false()


func test_a_migrated_world_saves_as_version_8_and_loads_again() -> void:
	_b = _fresh()
	assert_bool(_b.world.sim.from_snapshot(_v7)).is_true()
	var again := _json(_b.world.sim.to_snapshot())
	assert_int(int(again["save_version"])).is_equal(PassengerSim.SAVE_VERSION)
	assert_int(again["security"].size()).is_equal(1)
	var third := _fresh()
	assert_bool(third.world.sim.from_snapshot(again)).is_true()
	assert_str(third.signature()).is_equal(_b.signature())
	third.world.free_all()


func test_migrating_does_not_edit_the_dictionary_it_was_given() -> void:
	var copy := _v7.duplicate(true)
	_b = _fresh()
	assert_bool(_b.world.sim.from_snapshot(_v7)).is_true()
	assert_bool(_v7 == copy).is_true()


func test_a_version_7_save_with_a_bad_record_is_still_refused() -> void:
	var bad_stage := _v7.duplicate(true)
	bad_stage["passengers"][0]["stage"] = 99
	var no_trait := _v7.duplicate(true)
	(no_trait["passengers"][0] as Dictionary).erase("liquids")
	var bad_version := _v7.duplicate(true)
	bad_version["save_version"] = PassengerSim.SAVE_VERSION + 1
	# Version 7 scanned for 40 ticks at most; a service end far beyond what a
	# scan of these bags takes would hold the scanner for ever.
	var endless := _v7.duplicate(true)
	for record: Dictionary in endless["passengers"]:
		if int(record["id"]) == _first:
			record["service_end"] = _a.world.sim.tick + 1000000000
	_b = _fresh()
	var problem: String = PassengerSnapshot.load(endless, _b.world.grid).get("error", "")
	assert_str(problem).contains("more work left than its phase starts with")
	var before := _b.signature()
	for bad: Dictionary in [bad_stage, no_trait, bad_version, endless]:
		assert_bool(_b.world.sim.from_snapshot(bad)).is_false()
		assert_str(_b.signature()).is_equal(before)
