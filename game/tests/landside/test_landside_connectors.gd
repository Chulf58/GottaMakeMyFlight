class_name TestLandsideConnectors
extends GdUnitTestSuite
## A car drives between a lane and a curb berth or a parking slot along the
## berth's or slot's path (LandsidePaths), never jumping: from one tick to the
## next it moves no further than SPEED_MM, from road_in into a berth and out
## to road_out, and from the access lane into a slot and out to the lot's exit.
## Its passengers get out on the tick it has pulled in, where it stands, and a
## parked car pays its fee on that tick. A passenger from the multi-storey's
## top deck walks the aisle and the ramps down, a small height step at a time.
## Bare LandsideSims on the starter road, stepped by hand.

const STARTER := preload("res://landside/starter_landside.tres")
const SURFACE := 0
const MULTI_STOREY := 1
## How far a car may move in one tick, in metres, with float slack.
const STEP_M := LandsideSim.SPEED_MM / 1000.0 + 0.001

var _rng := RandomNumberGenerator.new()


func before_test() -> void:
	_rng.seed = 4


func _sim() -> LandsideSim:
	var sim: LandsideSim = auto_free(LandsideSim.new())
	assert_bool(sim.use_definition(STARTER)).is_true()
	sim.wallet = Wallet.new()
	return sim


func _car(sim: LandsideSim, intent: LandsideVehicle.Intent, booking: int) -> int:
	var bookings: Array[int] = [booking]
	return sim.add_vehicle(LandsideVehicle.Kind.CAR, intent, bookings)


## Steps `sim` from `from` until vehicle `id` has left the map, or `limit`
## ticks. Returns the record of the run: per tick [tick, lane, stage, position]
## while on the map (from its entering the map), the release ticks with their
## walks, and the parking credits' ticks. A parked car's stay is cut to
## `stay` ticks.
func _follow(sim: LandsideSim, id: int, from: int, limit: int, stay := 40) -> Dictionary:
	var run := {"track": [], "released": [], "walks": [], "credits": []}
	sim.wallet.transaction.connect(
		func(_amount: int, category: int, _claimed: Dictionary, _at: int) -> void:
			if category == Wallet.Category.PARKING:
				(run["credits"] as Array).append(sim.tick)
	)
	for t in range(from, from + limit):
		for event in sim.step(t, true, _rng):
			if event["vehicle"] == id:
				(run["released"] as Array).append(t)
				(run["walks"] as Array).append(event["walk"])
		var v := sim.get_vehicle(id)
		if v == null:
			break
		if v.stage == LandsideVehicle.Stage.PARKED and v.leave_tick > t + stay:
			v.leave_tick = t + stay
		if v.lane == LandsideVehicle.Lane.ROAD_IN and v.pos_mm < 0:
			continue
		(run["track"] as Array).append([t, v.lane, v.stage, sim.world_position(v)])
	return run


## The largest move between two ticks on the track, and every lane it drove.
func _assert_continuous(track: Array, lanes: Array) -> void:
	var largest := 0.0
	var seen := {}
	for i in track.size():
		seen[track[i][1]] = true
		if i > 0:
			largest = maxf(largest, (track[i][3] as Vector3).distance_to(track[i - 1][3]))
	print("largest step %.4f m over %d ticks, lanes %s" % [largest, track.size(), seen.keys()])
	assert_float(largest).is_less_equal(STEP_M)
	assert_float(largest).is_greater(0.4)
	for lane in lanes:
		assert_bool(seen.has(lane)).override_failure_message("lane %d" % lane).is_true()


## The first tick on the track with `stage` on `lane`, and where the car was.
static func _first(track: Array, lane: int, stage: int) -> Array:
	for entry in track:
		if entry[1] == lane and entry[2] == stage:
			return entry
	return []


func test_a_car_drives_from_road_into_a_berth_and_out_without_a_jump() -> void:
	var sim := _sim()
	sim.step(0, true, _rng)
	var id := _car(sim, LandsideVehicle.Intent.DROP, 1)
	var run := _follow(sim, id, 1, 2000)
	var track: Array = run["track"]
	assert_object(sim.get_vehicle(id)).is_null()
	_assert_continuous(
		track,
		[LandsideVehicle.Lane.ROAD_IN, LandsideVehicle.Lane.BERTH, LandsideVehicle.Lane.ROAD_OUT]
	)
	# It got out once, on the tick it stood in the berth, there; before that it
	# drove the berth's path with its passengers aboard.
	var pulling_in := _first(track, LandsideVehicle.Lane.BERTH, LandsideVehicle.Stage.DRIVE)
	var standing := _first(track, LandsideVehicle.Lane.BERTH, LandsideVehicle.Stage.DWELL)
	var pulling_out := _first(track, LandsideVehicle.Lane.BERTH, LandsideVehicle.Stage.LEAVE)
	print("pull-in from %s, stood %s, pull-out %s" % [pulling_in, standing, pulling_out])
	assert_array(run["released"]).is_equal([standing[0]])
	assert_int(standing[0] - pulling_in[0]).is_greater(1)
	assert_vector(standing[3]).is_equal_approx(STARTER.curb.berths[0], Vector3.ONE * 0.001)
	assert_float((pulling_in[3] as Vector3).distance_to(STARTER.curb.berths[0])).is_greater(3.0)
	assert_int(pulling_out[0] - standing[0]).is_greater_equal(LandsideSim.DWELL_TICKS)


func test_a_car_drives_into_a_bay_berth_on_road_in_and_out_without_a_jump() -> void:
	var sim := _sim()
	assert_bool(sim.build_curb(1)).is_true()
	sim.step(0, true, _rng)
	var id := _car(sim, LandsideVehicle.Intent.DROP, 1)
	var run := _follow(sim, id, 1, 2000)
	var track: Array = run["track"]
	_assert_continuous(
		track,
		[LandsideVehicle.Lane.ROAD_IN, LandsideVehicle.Lane.BERTH, LandsideVehicle.Lane.ROAD_OUT]
	)
	var standing := _first(track, LandsideVehicle.Lane.BERTH, LandsideVehicle.Stage.DWELL)
	# Bay 1's first berth, the first a car reaches on road_in.
	assert_vector(standing[3]).is_equal_approx(STARTER.curb_spots[1].berths[1], Vector3.ONE * 0.001)
	assert_array(run["released"]).is_equal([standing[0]])


func test_a_car_drives_into_a_surface_lot_slot_pays_there_and_drives_out() -> void:
	var sim := _sim()
	assert_bool(sim.build_lot(SURFACE)).is_true()
	sim.step(0, true, _rng)
	var id := _car(sim, LandsideVehicle.Intent.PARK, 1)
	var run := _follow(sim, id, 1, 3000)
	var track: Array = run["track"]
	assert_object(sim.get_vehicle(id)).is_null()
	_assert_continuous(
		track,
		[
			LandsideVehicle.Lane.ROAD_IN,
			LandsideVehicle.Lane.ACCESS,
			LandsideVehicle.Lane.SLOT,
			LandsideVehicle.Lane.LOT_EXIT,
		]
	)
	var gate := _first(track, LandsideVehicle.Lane.SLOT, LandsideVehicle.Stage.DRIVE)
	var parked := _first(track, LandsideVehicle.Lane.SLOT, LandsideVehicle.Stage.PARKED)
	print("gate %s parked %s credits %s" % [gate, parked, run["credits"]])
	assert_vector(parked[3]).is_equal_approx(STARTER.lots[SURFACE].slots[0], Vector3.ONE * 0.001)
	assert_int(parked[0] - gate[0]).is_greater(1)
	# Released and paid once, on the tick it stood in the slot, not at the gate.
	assert_array(run["released"]).is_equal([parked[0]])
	assert_array(run["credits"]).is_equal([parked[0]])
	var walk: Array = run["walks"][0]
	assert_vector(walk[0]).is_equal_approx(STARTER.lots[SURFACE].slots[0], Vector3.ONE * 0.001)


func test_a_car_drives_up_to_the_top_deck_and_its_passenger_walks_down_the_ramps() -> void:
	var sim := _sim()
	assert_bool(sim.build_lot(MULTI_STOREY)).is_true()
	var spot := STARTER.lots[MULTI_STOREY]
	# Every slot below the top deck taken, so the next car parks up there.
	var top := 24
	for i in top:
		_car(sim, LandsideVehicle.Intent.PARK, i + 1)
	var t := 1
	while sim.free_slots(MULTI_STOREY) > spot.slots.size() - top and t < 4000:
		sim.step(t, false, _rng)
		t += 1
	var id := _car(sim, LandsideVehicle.Intent.PARK, 100)
	var run := _follow(sim, id, t, 6000, 1000000)
	var track: Array = run["track"]
	var v := sim.get_vehicle(id)
	assert_int(v.stop).is_equal(top)
	_assert_continuous(
		track,
		[LandsideVehicle.Lane.ROAD_IN, LandsideVehicle.Lane.ACCESS, LandsideVehicle.Lane.SLOT]
	)
	var parked := _first(track, LandsideVehicle.Lane.SLOT, LandsideVehicle.Stage.PARKED)
	assert_vector(parked[3]).is_equal_approx(spot.slots[top], Vector3.ONE * 0.001)
	assert_float(spot.slots[top].y).is_greater(10.0)
	assert_array(run["released"]).is_equal([parked[0]])
	# The walk: from the slot over to the aisle, down both ramps and out through
	# the entrance, then the gate and the crossing. Inside the building every
	# point is on a deck or on the ramp strip, never over a deck's ramp opening,
	# and no two points differ in height by more than one walk step.
	var walk: Array = run["walks"][0]
	var gate := spot.access[spot.access.size() - 1]
	var at_gate := walk.find(gate)
	var at_door := walk.find(spot.entrance[spot.entrance.size() - 1])
	print("walk %d points, door at %d, gate at %d: %s" % [walk.size(), at_door, at_gate, walk])
	assert_vector(walk[0]).is_equal_approx(spot.slots[top], Vector3.ONE * 0.001)
	assert_int(at_door).is_greater(10)
	assert_int(at_gate).is_equal(at_door + 2)
	assert_vector(walk[at_gate - 1]).is_equal(spot.entrance[0])
	var lowest := INF
	for i in range(1, walk.size()):
		var a: Vector3 = walk[i - 1]
		var b: Vector3 = walk[i]
		var step := absf(b.y - a.y)
		assert_float(step).override_failure_message("%s -> %s" % [a, b]).is_less_equal(
			LandsidePaths.WALK_STEP_M + 0.0001
		)
		if i <= at_door:
			assert_str(_walkable(spot, b)).override_failure_message("%s" % b).is_empty()
			(
				assert_str(_walkable(spot, a.lerp(b, 0.5)))
				. override_failure_message("mid %s" % b)
				. is_empty()
			)
		lowest = minf(lowest, b.y)
	assert_float(lowest).is_less(0.5)


## The multi-storey's walkable area, written out from the asset measurements
## in test_landside_geometry.gd: inside its inner walls, on a deck top (0.3,
## 5.3, 10.3, a slot's paint 3 cm above), or on the ramp strip x 1.7 to 8.3
## (local) between z -22.5 and 8.5, where no deck stands over the opening at
## x 1 to 9, z -9.52 to 8.5. "" when `at` is walkable, else why not.
static func _walkable(spot: LandsideLotSpot, at: Vector3) -> String:
	var local := at - spot.centre
	if absf(local.x) > 10.2 or absf(local.z) > 22.7:
		return "outside the inner walls"
	var on_ramp := local.x >= 1.7 and local.x <= 8.3 and local.z >= -22.5 and local.z <= 8.5
	if on_ramp:
		return ""
	var deck := -1.0
	for top in [0.3, 5.3, 10.3]:
		if at.y >= top - 0.01 and at.y <= top + 0.04:
			deck = top
	if deck < 0.0:
		return "between decks"
	var opening := local.x > 1.0 and local.x < 9.0 and local.z > -9.52 and local.z < 8.5
	if deck > 1.0 and opening:
		return "over the ramp opening"
	return ""
