class_name TestPassengerV8Migration
extends GdUnitTestSuite
## A version 8 passenger save, written when a lane's unpack work was 6 + 8 per
## bag, loads into version 9, where it is 3 + 4 per bag (lowering a phase's
## work constant needs a migration: anti-pattern lowering-a-phase-s-work-
## constant-without-a-save-migration-re). Remaining UNPACK work is scaled to
## the new start, rounded up so a passenger mid-unpack keeps at least 1. A
## version 9 save is still held to the new maximum.

## The unpack work version 8 started with, per passenger with no bags and per bag.
const OLD_TICKS := 6
const OLD_BAG_TICKS := 8

var _a: SecurityTestWorld
var _b: SecurityTestWorld
var _id := 0
var _v9: Dictionary


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_a = SecurityTestWorld.make(true)
	_id = _a.send(2)
	while _a.world.passenger(_id).security_phase != SecurityRuntime.Phase.UNPACK:
		_a.world.step()
	_v9 = _json(_a.world.sim.to_snapshot())


func after_test() -> void:
	for w in [_a, _b]:
		if w != null:
			w.world.free_all()
	_a = null
	_b = null


func _json(data: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(data))


func _fresh() -> SecurityTestWorld:
	var w := SecurityTestWorld.make(true)
	w.world.clock.from_snapshot(_json(_a.world.clock.to_snapshot()))
	w.world.flights.from_snapshot(_json(_a.world.flights.to_snapshot()))
	return w


## The fixture written as version 8 wrote it: `work` ticks of unpack left for
## a passenger with `bags` bags.
func _v8(work: int, bags := 2) -> Dictionary:
	var out := _v9.duplicate(true)
	out["save_version"] = 8
	# Version 8 had no toilet need, cooldown or visits, no boredom, kiosk
	# cooldown or kiosk visits.
	out.erase("toilet")
	out.erase("shop")
	for record: Dictionary in out["passengers"]:
		record.erase("toilet_need")
		record.erase("toilet_cooldown")
		record.erase("boredom")
		record.erase("shop_cooldown")
		if int(record["id"]) == _id:
			record["carry_on"] = bags
			record["security_work"] = work
	return out


func _loaded_work(data: Dictionary) -> int:
	_b = _fresh()
	assert_bool(_b.world.sim.from_snapshot(data)).is_true()
	return _b.world.passenger(_id).security_work


func test_the_fixture_is_mid_unpack_with_two_bags_at_the_current_version() -> void:
	assert_int(int(_v9["save_version"])).is_equal(PassengerSim.SAVE_VERSION)
	assert_int(PassengerSim.SAVE_VERSION).is_equal(13)
	var p := _a.world.passenger(_id)
	assert_int(p.carry_on).is_equal(2)
	assert_int(SecurityRuntime.work_for(SecurityRuntime.Phase.UNPACK, p)).is_equal(11)
	assert_int(OLD_TICKS + OLD_BAG_TICKS * 2).is_equal(22)


func test_a_version_8_save_mid_two_bag_unpack_loads_with_scaled_work_and_plays_on() -> void:
	# 15 of the old 22 ticks left is more than the new maximum of 11.
	_b = _fresh()
	assert_bool(_b.world.sim.from_snapshot(_v8(15))).is_true()
	var p := _b.world.passenger(_id)
	assert_int(p.security_phase).is_equal(SecurityRuntime.Phase.UNPACK)
	# ceil(15 * 11 / 22) = 8
	assert_int(p.security_work).is_equal(8)
	assert_int(p.boredom).is_equal(BoredomSim.start_of(_id))
	assert_bool(_b.run_until_cleared([_id])).is_true()
	assert_int(p.security_phase).is_equal(SecurityRuntime.Phase.NONE)


func test_scaling_covers_the_whole_old_range_for_two_bags() -> void:
	# [old work left, new work left]: the old maximum maps to the new one and
	# any work still left keeps at least 1.
	for pair: Array in [[22, 11], [21, 11], [12, 6], [2, 1], [1, 1], [0, 0]]:
		(
			assert_int(_loaded_work(_v8(pair[0])))
			. override_failure_message("old work %d" % pair[0])
			. is_equal(pair[1])
		)
		_b.world.free_all()
		_b = null


func test_scaling_uses_the_passengers_own_bag_count() -> void:
	# No bags: the old start was 6 and the new one is 3.
	for pair: Array in [[6, 3], [4, 2], [1, 1]]:
		(
			assert_int(_loaded_work(_v8(pair[0], 0)))
			. override_failure_message("old work %d" % pair[0])
			. is_equal(pair[1])
		)
		_b.world.free_all()
		_b = null


func test_a_migrated_world_saves_as_the_current_version_and_loads_again() -> void:
	_b = _fresh()
	assert_bool(_b.world.sim.from_snapshot(_v8(15))).is_true()
	var again := _json(_b.world.sim.to_snapshot())
	assert_int(int(again["save_version"])).is_equal(PassengerSim.SAVE_VERSION)
	var third := _fresh()
	assert_bool(third.world.sim.from_snapshot(again)).is_true()
	assert_str(third.signature()).is_equal(_b.signature())
	third.world.free_all()


func test_migrating_does_not_edit_the_dictionary_it_was_given() -> void:
	var old := _v8(15)
	var copy := old.duplicate(true)
	_b = _fresh()
	assert_bool(_b.world.sim.from_snapshot(old)).is_true()
	assert_bool(old == copy).is_true()


func test_work_above_the_new_maximum_is_refused_at_the_new_version() -> void:
	var over := _v9.duplicate(true)
	for record: Dictionary in over["passengers"]:
		if int(record["id"]) == _id:
			record["security_work"] = 12
	_b = _fresh()
	var problem: String = PassengerSnapshot.load(over, _b.world.grid).get("error", "")
	assert_str(problem).contains("more work left than its phase starts with")
	var before := _b.signature()
	assert_bool(_b.world.sim.from_snapshot(over)).is_false()
	assert_str(_b.signature()).is_equal(before)
	# The new maximum itself is accepted.
	for record: Dictionary in over["passengers"]:
		if int(record["id"]) == _id:
			record["security_work"] = 11
	assert_bool(_b.world.sim.from_snapshot(over)).is_true()


func test_a_version_8_save_above_the_old_maximum_is_still_refused() -> void:
	# 23 of the old 22 ticks cannot have been saved; it scales to 12 and fails.
	_b = _fresh()
	var before := _b.signature()
	var problem: String = PassengerSnapshot.load(_v8(23), _b.world.grid).get("error", "")
	assert_str(problem).contains("more work left than its phase starts with")
	assert_bool(_b.world.sim.from_snapshot(_v8(23))).is_false()
	assert_str(_b.signature()).is_equal(before)
