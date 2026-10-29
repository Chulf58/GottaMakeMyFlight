class_name TestCarryOnTraits
extends GdUnitTestSuite
## Every passenger gets carry-on bags (0 to 2), a liquids flag and an alarm
## flag at spawn, drawn from the sim RNG right after hunger, and a version 7
## save keeps them (decision
## carry-on-at-security-costs-time-only-0-2-carry-on-bags-add-s).

const SAMPLES := 20000
const SEED := 4242
## Wide enough for 20000 draws (a share of 0.55 has a standard error of
## 0.0035), tight enough to catch a wrong table.
const TOLERANCE := 0.02

var _a: PassengerTestWorld
var _b: PassengerTestWorld


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


func _drawn(rng: RandomNumberGenerator, n: int) -> Array[Passenger]:
	var out: Array[Passenger] = []
	for i in n:
		var p := Passenger.new()
		CarryOnTraits.draw(rng, p)
		out.append(p)
	return out


func _traits(world: PassengerTestWorld) -> String:
	var parts := PackedStringArray()
	for id in world.sim.passenger_ids():
		var p := world.passenger(id)
		parts.append("%d:%d:%d:%d" % [id, p.carry_on, int(p.liquids), int(p.alarm)])
	return ";".join(parts)


func test_a_new_passenger_has_no_bags_and_no_flags() -> void:
	var p := Passenger.new()
	assert_int(p.carry_on).is_equal(0)
	assert_bool(p.liquids).is_false()
	assert_bool(p.alarm).is_false()


func test_the_bag_shares_add_up_to_the_whole() -> void:
	var total := 0
	for share in CarryOnTraits.BAG_SHARES:
		total += share
	assert_int(total).is_equal(100)
	assert_int(CarryOnTraits.BAG_SHARES.size()).is_equal(CarryOnTraits.MAX_BAGS + 1)


func test_trait_shares_over_seeded_draws_match_the_tables() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var bags := [0, 0, 0]
	var liquids := 0
	var alarms := 0
	for p in _drawn(rng, SAMPLES):
		bags[p.carry_on] += 1
		liquids += int(p.liquids)
		alarms += int(p.alarm)
	for n in bags.size():
		var share: float = bags[n] / float(SAMPLES)
		var want: float = CarryOnTraits.BAG_SHARES[n] / 100.0
		(
			assert_float(share)
			. override_failure_message("%d bags: %.4f, want %.2f" % [n, share, want])
			. is_equal_approx(want, TOLERANCE)
		)
	assert_float(liquids / float(SAMPLES)).is_equal_approx(
		CarryOnTraits.LIQUIDS_PERCENT / 100.0, TOLERANCE
	)
	assert_float(alarms / float(SAMPLES)).is_equal_approx(
		CarryOnTraits.ALARM_PERCENT / 100.0, TOLERANCE
	)


func test_a_draw_takes_exactly_three_rolls_whatever_the_result() -> void:
	var rng := RandomNumberGenerator.new()
	var control := RandomNumberGenerator.new()
	rng.seed = SEED
	control.seed = SEED
	for p in _drawn(rng, 200):
		for i in CarryOnTraits.DRAWS:
			control.randi_range(0, 99)
	assert_int(rng.state).is_equal(control.state)


func test_spawn_draws_the_traits_right_after_hunger_then_the_toilet_need() -> void:
	_a = PassengerTestWorld.reference_world(SEED)
	var mirror := RandomNumberGenerator.new()
	mirror.seed = SEED
	for i in 25:
		var id := _a.sim.spawn_now(PassengerTestWorld.FLIGHT, 0)
		var hunger := mirror.randi_range(CafeSim.HUNGER_START_MIN, CafeSim.HUNGER_START_MAX)
		var want := Passenger.new()
		CarryOnTraits.draw(mirror, want)
		var need := mirror.randi_range(ToiletSim.NEED_START_MIN, ToiletSim.NEED_START_MAX)
		var p := _a.passenger(id)
		assert_int(p.hunger).is_equal(hunger)
		assert_int(p.toilet_need).is_equal(need)
		assert_int(p.carry_on).is_equal(want.carry_on)
		assert_bool(p.liquids).is_equal(want.liquids)
		assert_bool(p.alarm).is_equal(want.alarm)
	assert_int(_a.clock.rng.state).is_equal(mirror.state)


func test_a_current_version_save_keeps_the_traits_and_plays_out_the_same() -> void:
	_a = PassengerTestWorld.reference_world(SEED)
	_a.sim.schedule_flight(PassengerTestWorld.FLIGHT, 24)
	for i in 10:
		_a.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_a.run_to(205)
	assert_int(PassengerSim.SAVE_VERSION).is_equal(10)
	var data: Dictionary = JSON.parse_string(JSON.stringify(_a.sim.to_snapshot()))
	assert_int(int(data["save_version"])).is_equal(10)
	var seen := {}
	for record: Dictionary in data["passengers"]:
		seen[int(record["carry_on"])] = true
	assert_int(seen.size()).is_greater(1)
	_b = PassengerTestWorld.reference_world(1)
	_b.clock.from_snapshot(JSON.parse_string(JSON.stringify(_a.clock.to_snapshot())))
	_b.flights.from_snapshot(JSON.parse_string(JSON.stringify(_a.flights.to_snapshot())))
	assert_bool(_b.sim.from_snapshot(data)).is_true()
	assert_str(_traits(_b)).is_equal(_traits(_a))
	var doors := _a.flights.doors_close_tick(PassengerTestWorld.FLIGHT)
	var first_bad := -1
	while _a.clock.tick <= doors and first_bad < 0:
		_a.step()
		_b.step()
		if _traits(_a) != _traits(_b) or _a.signature() != _b.signature():
			first_bad = _a.clock.tick
	assert_int(first_bad).override_failure_message("first differing tick %d" % first_bad).is_equal(
		-1
	)
