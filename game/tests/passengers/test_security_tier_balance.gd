class_name TestSecurityTierBalance
extends GdUnitTestSuite
## The two security tiers stay apart (decision security-tiers-the-old-single-
## scanner-stays-as-a-cheap-basic): the basic scanner is the cheap, slow tier
## and the lane the faster upgrade, worth more than two basic scanners and
## less than three (the price table's comment). The lane is measured as
## throughput, because it is one station with one officer.
##
## The stream is 30 passengers sent 12 ticks apart with the spawn trait odds
## (CarryOnTraits: 12% liquids, 8% alarm), on SecurityTestWorld's grid, at a
## basic scanner, an unhelped lane (primary officer only, >= 1.55x), and a
## helped lane (primary + helper officer, >= 1.75x) per ruling cfe9a3d2
## (keeping REPACK_TICKS = 80 so full 4 s bubble/pat-down visibility holds and
## hiring a lane helper is rewarded without bumping SAVE_VERSION).

## The lane must clear the stream at least this many times as fast as the
## basic scanner (1.55x unhelped, 1.75x helped), and not more than the price of
## three basic scanners would buy.
const MIN_SPEEDUP := 1.55
const MIN_HELPED_SPEEDUP := 1.75
const MAX_SPEEDUP := 3.0
const PASSENGERS := 30
const GAP := 12
const SEEDS: Array[int] = [1, 2]

var _worlds: Array[SecurityTestWorld] = []
var _cached_basic := 0
var _cached_unhelped := 0


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for w in _worlds:
		w.world.free_all()
	_worlds.clear()


## [bags, liquids, alarm] with CarryOnTraits' odds, from a seeded generator so
## both tiers see the same passengers.
static func _traits(rng: RandomNumberGenerator) -> Array:
	var roll := rng.randf()
	var bags := 0 if roll < 0.2 else (1 if roll < 0.75 else 2)
	return [
		bags,
		rng.randf() < CarryOnTraits.LIQUIDS_PERCENT / 100.0,
		rng.randf() < CarryOnTraits.ALARM_PERCENT / 100.0,
	]


## The tick the last of the stream is cleared at `use_lane`'s tier, over all
## SEEDS; `helped` seats a helper officer alongside the primary on a lane.
func _finish(use_lane: bool, helped := false) -> int:
	var total := 0
	for seed in SEEDS:
		var w := SecurityTestWorld.make(use_lane, seed)
		_worlds.append(w)
		if use_lane and helped:
			w.world.auto_staff = false
			StaffTestKit.seat(w.world.staff, w.station, StaffMember.Slot.PRIMARY)
			StaffTestKit.seat(w.world.staff, w.station, StaffMember.Slot.HELPER)
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var ids: Array[int] = []
		for i in PASSENGERS:
			var t := _traits(rng)
			ids.append(w.send(t[0], t[1], t[2]))
			w.world.run_to(w.world.clock.tick + GAP)
		assert_bool(w.run_until_cleared(ids, 6000)).is_true()
		var last := 0
		for id in ids:
			last = maxi(last, w.cleared[id])
		total += last
	return total


func _basic_total() -> int:
	if _cached_basic == 0:
		_cached_basic = _finish(false)
	return _cached_basic


func _unhelped_total() -> int:
	if _cached_unhelped == 0:
		_cached_unhelped = _finish(true)
	return _cached_unhelped


func test_the_lane_clears_a_stream_much_faster_than_the_basic_scanner() -> void:
	var basic := _basic_total()
	var lane := _unhelped_total()
	var speedup := float(basic) / float(lane)
	print(
		(
			"last cleared over %d seeds (unhelped): basic %d, lane %d, speedup %.2f"
			% [SEEDS.size(), basic, lane, speedup]
		)
	)
	assert_float(speedup).is_greater_equal(MIN_SPEEDUP)
	assert_float(speedup).is_less_equal(MAX_SPEEDUP)


func test_a_helped_lane_clears_a_stream_at_least_1_75x_faster() -> void:
	var basic := _basic_total()
	var unhelped := _unhelped_total()
	var lane := _finish(true, true)
	var speedup := float(basic) / float(lane)
	print(
		(
			"last cleared over %d seeds (helped): basic %d, lane %d, speedup %.2f"
			% [SEEDS.size(), basic, lane, speedup]
		)
	)
	assert_int(lane).is_less(unhelped)
	assert_float(speedup).is_greater_equal(MIN_HELPED_SPEEDUP)
	assert_float(speedup).is_less_equal(MAX_SPEEDUP)


func test_a_whole_lane_costs_between_two_and_three_basic_scanners() -> void:
	var basic := PriceTable.price_of_object(&"security_scanner")
	var lane := 0
	for id in SecurityLanes.PART_IDS:
		lane += PriceTable.price_of_object(id)
	print("basic scanner %d, whole lane %d" % [basic, lane])
	assert_int(lane).is_greater(2 * basic)
	assert_int(lane).is_less(3 * basic)
