class_name TestLandsideStaggeredUnload
extends GdUnitTestSuite
## A party in one car or taxi steps out one passenger at a time,
## LandsideSim.RELEASE_GAP_TICKS apart, at the curb and in the car park (decision
## passenger-spacing-fixed-per-cause-standing-spots-staggered-unloading-
## ordered-files, part 2). Those still aboard stay in the vehicle; the
## wait is saved, and a load in the middle of unloading plays on exactly like
## the uninterrupted run.

const SEED := 8
const BOOKED := 40

var _a: LandsideTestWorld
var _b: LandsideTestWorld


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


func _bare() -> LandsideSim:
	var sim: LandsideSim = auto_free(LandsideSim.new())
	assert_bool(sim.use_definition(LandsideTestWorld.STARTER)).is_true()
	sim.wallet = Wallet.new()
	return sim


func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	return rng


## {tick: booking id} of the first `count` releases of a lone vehicle that
## enters the road on tick 100 with `aboard`, stepped with `can_release` from
## `allow_from` on.
func _releases(
	sim: LandsideSim,
	kind: LandsideVehicle.Kind,
	intent: LandsideVehicle.Intent,
	aboard: Array[int],
	allow_from := 0
) -> Dictionary:
	var rng := _rng()
	sim.step(100, allow_from <= 100, rng)
	sim.add_vehicle(kind, intent, aboard)
	var out := {}
	for t in range(101, 2000):
		for event in sim.step(t, t >= allow_from, rng):
			assert_int((event["bookings"] as Array).size()).is_equal(1)
			out[t] = (event["bookings"] as Array)[0]
	return out


func test_a_party_at_the_curb_steps_out_one_at_a_time_in_booking_order() -> void:
	var sim := _bare()
	var gap := LandsideSim.RELEASE_GAP_TICKS
	var out := _releases(sim, LandsideVehicle.Kind.CAR, LandsideVehicle.Intent.DROP, [1, 2, 3, 4])
	var ticks: Array = out.keys()
	ticks.sort()
	print("curb releases: %s gap %d" % [out, gap])
	assert_int(gap).is_equal(7)
	assert_int(ticks.size()).is_equal(4)
	for i in 4:
		assert_int(out[ticks[i]]).is_equal(i + 1)
		assert_int(ticks[i]).is_equal(ticks[0] + i * gap)
	assert_int(ticks[0] - 100).is_equal(sim.lead_ticks(LandsideVehicle.Intent.DROP))


func test_a_party_in_the_car_park_steps_out_one_at_a_time() -> void:
	var sim := _bare()
	assert_bool(sim.build_lot(0)).is_true()
	var out := _releases(sim, LandsideVehicle.Kind.CAR, LandsideVehicle.Intent.PARK, [1, 2, 3])
	var ticks: Array = out.keys()
	ticks.sort()
	print("lot releases: %s" % [out])
	assert_int(ticks.size()).is_equal(3)
	for i in 3:
		assert_int(out[ticks[i]]).is_equal(i + 1)
		assert_int(ticks[i]).is_equal(ticks[0] + i * LandsideSim.RELEASE_GAP_TICKS)
	assert_int(sim.get_vehicle(1).stage).is_equal(LandsideVehicle.Stage.PARKED)


func test_the_party_stays_aboard_until_its_turn_and_no_entrance_lets_nobody_out() -> void:
	var sim := _bare()
	var out := _releases(sim, LandsideVehicle.Kind.TAXI, LandsideVehicle.Intent.DROP, [1, 2], 400)
	var ticks: Array = out.keys()
	ticks.sort()
	print("late-entrance releases: %s" % [out])
	# Nobody got out before the entrance opened; then one at once, one a gap later.
	assert_int(ticks[0]).is_equal(400)
	assert_int(ticks[1]).is_equal(400 + LandsideSim.RELEASE_GAP_TICKS)


func test_the_vehicle_waits_for_its_last_passenger_before_it_leaves() -> void:
	var sim := _bare()
	var rng := _rng()
	var aboard: Array[int] = [1, 2, 3]
	sim.step(100, true, rng)
	var id := sim.add_vehicle(LandsideVehicle.Kind.CAR, LandsideVehicle.Intent.DROP, aboard)
	var v := sim.get_vehicle(id)
	var saw_wait := false
	var last := -1
	var left := -1
	for t in range(101, 1000):
		for event in sim.step(t, true, rng):
			last = t
			assert_int(v.bookings.size() + (event["bookings"] as Array).size()).is_greater(0)
		saw_wait = saw_wait or (v.release_wait > 0 and not v.bookings.is_empty())
		if left < 0 and v.stage == LandsideVehicle.Stage.LEAVE:
			left = t
	print("last out %d, started leaving %d, waited %s" % [last, left, saw_wait])
	assert_bool(saw_wait).is_true()
	assert_int(v.release_wait).is_equal(0)
	assert_int(left).is_greater(last)


func test_a_booking_dropped_from_a_waiting_vehicle_clears_the_wait_when_it_empties() -> void:
	var sim := _bare()
	var rng := _rng()
	var aboard: Array[int] = [1, 2]
	sim.step(100, true, rng)
	var id := sim.add_vehicle(LandsideVehicle.Kind.CAR, LandsideVehicle.Intent.DROP, aboard)
	var v := sim.get_vehicle(id)
	var t := 100
	while v.release_wait == 0 and t < 2000:
		t += 1
		sim.step(t, true, rng)
	assert_int(v.release_wait).is_greater(0)
	assert_array(v.bookings).is_equal([2])
	sim.drop_booking(id, 2)
	print("after the drop: wait %d bookings %s" % [v.release_wait, v.bookings])
	assert_int(v.release_wait).is_equal(0)
	assert_array(v.bookings).is_empty()


func _unloading(world: LandsideTestWorld) -> bool:
	for id in world.landside.vehicle_ids():
		var v := world.landside.get_vehicle(id)
		if v.release_wait > 0 and not v.bookings.is_empty():
			return true
	return false


func _save(world: LandsideTestWorld) -> String:
	return (
		JSON
		. stringify(
			{
				"clock": world.world.clock.to_snapshot(),
				"flights": world.world.flights.to_snapshot(),
				"passengers": world.sim.to_snapshot(),
				"landside": world.landside.to_snapshot(world.sim.arrivals, world.sim.tick),
			}
		)
	)


func _load(text: String) -> LandsideTestWorld:
	var data: Dictionary = JSON.parse_string(text)
	var world := LandsideTestWorld.make(LandsideTestWorld.with_berths(1), [], 99)
	assert_bool(world.landside.build_lot(0)).is_true()
	assert_bool(world.world.clock.from_snapshot(data["clock"])).is_true()
	assert_bool(world.world.flights.from_snapshot(data["flights"])).is_true()
	assert_bool(world.sim.from_snapshot(data["passengers"])).is_true()
	assert_bool(world.landside.from_snapshot(data["landside"], world.sim.arrivals)).is_true()
	return world


func _state(world: LandsideTestWorld) -> String:
	return (
		"%s|%s"
		% [
			world.world.signature(),
			JSON.stringify(world.landside.to_snapshot(world.sim.arrivals, world.sim.tick)),
		]
	)


func _world() -> LandsideTestWorld:
	var world := LandsideTestWorld.make(LandsideTestWorld.with_berths(1), [], SEED)
	assert_bool(world.landside.build_lot(0)).is_true()
	return world


func test_a_reload_mid_unloading_replays_like_the_uninterrupted_run() -> void:
	_a = _world()
	_a.schedule(BOOKED)
	var party_of := {}
	for id in _a.sim.arrivals.booking_ids():
		party_of[id] = _a.sim.arrivals.get_booking(id).party
	while not _unloading(_a) and _a.sim.tick < 9000:
		_a.step()
	assert_bool(_unloading(_a)).is_true()
	var waiting := 0
	for id in _a.landside.vehicle_ids():
		var v := _a.landside.get_vehicle(id)
		if v.release_wait > 0:
			waiting = v.release_wait
			print(
				(
					"saved at %d: vehicle %d has %s aboard, next out in %d"
					% [_a.sim.tick, id, v.bookings, v.release_wait]
				)
			)
	assert_int(waiting).is_greater(0)
	var saved_at := _a.sim.tick
	_b = _load(_save(_a))
	assert_str(_state(_b)).is_equal(_state(_a))
	var doors := _a.world.flights.doors_close_tick(PassengerTestWorld.FLIGHT)
	var first_bad := -1
	var ticks := 0
	while _a.sim.tick <= doors:
		_a.step()
		_b.step()
		ticks += 1
		if first_bad < 0 and _state(_a) != _state(_b):
			first_bad = _a.sim.tick
	print("compared %d ticks, first differing %d" % [ticks, first_bad])
	assert_int(first_bad).is_equal(-1)
	# The release ticks after the save are the control's, and there are some.
	var after_save := 0
	for id in _b.released:
		assert_int(_b.released[id]).is_equal(_a.released[id])
		after_save += int(_b.released[id] > saved_at)
	assert_int(after_save).is_greater(0)
	# Within a party no two passengers got out less than the gap apart.
	var by_party := {}
	for id in _a.released:
		if not by_party.has(party_of[id]):
			by_party[party_of[id]] = []
		(by_party[party_of[id]] as Array).append(int(_a.released[id]))
	var parties := 0
	for party in by_party:
		var at: Array = by_party[party]
		at.sort()
		parties += int(at.size() > 1)
		for i in range(1, at.size()):
			assert_int(at[i] - at[i - 1]).is_greater_equal(LandsideSim.RELEASE_GAP_TICKS)
	print("%d parties of more than one got out, %d released in all" % [parties, _a.released.size()])
	assert_int(parties).is_greater(0)


func test_a_saved_wait_that_does_not_fit_is_refused() -> void:
	_a = _world()
	_a.schedule(BOOKED)
	while not _unloading(_a) and _a.sim.tick < 9000:
		_a.step()
	var data: Dictionary = JSON.parse_string(_save(_a))["landside"]
	var cases := {"too long": LandsideSim.RELEASE_GAP_TICKS + 1, "negative": -1}
	for case_name in cases:
		var bad: Dictionary = data.duplicate(true)
		for entry in bad["vehicles"]:
			if int(entry["release_wait"]) > 0:
				entry["release_wait"] = cases[case_name]
		var loaded := LandsideSnapshot.load(bad, LandsideTestWorld.with_berths(1))
		print("%s: %s" % [case_name, loaded.get("error", "LOADED")])
		assert_bool(loaded.has("error")).override_failure_message(case_name).is_true()
	var empty: Dictionary = data.duplicate(true)
	for entry in empty["vehicles"]:
		if int(entry["release_wait"]) > 0:
			entry["bookings"] = []
	empty["bookings"] = (empty["bookings"] as Array).filter(
		func(b: Dictionary) -> bool: return int(b["state"]) != ArrivalBooking.State.IN_VEHICLE
	)
	var loaded := LandsideSnapshot.load(empty, LandsideTestWorld.with_berths(1))
	print("wait with nobody aboard: %s" % loaded.get("error", "LOADED"))
	assert_bool(loaded.has("error")).is_true()
