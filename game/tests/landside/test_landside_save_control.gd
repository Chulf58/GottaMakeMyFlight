class_name TestLandsideSaveControl
extends GdUnitTestSuite
## A save taken mid-queue (cars waiting for the one curb berth, others in or
## on their way to the car park) loads into a world that plays on exactly
## like the unsaved control: the same passengers, bookings and cars on every
## tick through doors close. Parked cars keep their absolute leave ticks, so
## a loaded lot empties on the same ticks as the control's.

const BOOKED := 40
const SEED := 8

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


func _world(seed: int) -> LandsideTestWorld:
	var world := LandsideTestWorld.make(LandsideTestWorld.with_berths(1), [], seed)
	assert_bool(world.landside.build_lot(0)).is_true()
	return world


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
	var world := _world(99)
	# A fresh world's lot is built by the fixture; the save says it again.
	assert_bool(world.world.clock.from_snapshot(data["clock"])).is_true()
	assert_bool(world.world.flights.from_snapshot(data["flights"])).is_true()
	assert_bool(world.sim.from_snapshot(data["passengers"])).is_true()
	assert_bool(world.landside.from_snapshot(data["landside"], world.sim.arrivals)).is_true()
	return world


## Everything that decides what happens next on the landside and inside.
func _state(world: LandsideTestWorld) -> String:
	return (
		"%s|%s"
		% [
			world.world.signature(),
			JSON.stringify(world.landside.to_snapshot(world.sim.arrivals, world.sim.tick)),
		]
	)


func _count(world: LandsideTestWorld, stage: LandsideVehicle.Stage) -> int:
	var count := 0
	for id in world.landside.vehicle_ids():
		count += int(world.landside.get_vehicle(id).stage == stage)
	return count


func test_a_mid_queue_save_plays_on_like_the_unsaved_control() -> void:
	_a = _world(SEED)
	_a.schedule(BOOKED)
	while (
		(
			_count(_a, LandsideVehicle.Stage.QUEUE) == 0
			or _count(_a, LandsideVehicle.Stage.PARKED) == 0
		)
		and _a.sim.tick < 9000
	):
		_a.step()
	var queued := _count(_a, LandsideVehicle.Stage.QUEUE)
	var parked := _count(_a, LandsideVehicle.Stage.PARKED)
	var awaiting := 0
	for id in _a.sim.arrivals.booking_ids():
		awaiting += int(_a.sim.arrivals.get_booking(id).state == ArrivalBooking.State.AWAITING)
	print(
		(
			"saved at %d: %d queued, %d parked, %d bookings awaiting, %d passengers"
			% [_a.sim.tick, queued, parked, awaiting, _a.sim.passenger_ids().size()]
		)
	)
	assert_int(queued).is_greater(0)
	assert_int(parked).is_greater(0)
	assert_int(awaiting).is_greater(0)
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
	print(
		(
			"compared %d ticks, first differing %d, made %d missed %d"
			% [ticks, first_bad, _a.sim.made_count(), _a.sim.missed_count()]
		)
	)
	assert_int(first_bad).is_equal(-1)
	assert_int(_a.sim.made_count() + _a.sim.missed_count()).is_greater(0)


func test_parked_cars_leave_on_the_same_ticks_after_a_load() -> void:
	var control: LandsideSim = auto_free(LandsideSim.new())
	var loaded: LandsideSim = auto_free(LandsideSim.new())
	assert_bool(control.use_definition(LandsideTestWorld.STARTER)).is_true()
	assert_bool(loaded.use_definition(LandsideTestWorld.STARTER)).is_true()
	control.wallet = Wallet.new()
	assert_bool(control.build_lot(0)).is_true()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	for i in 4:
		var aboard: Array[int] = [i + 1]
		control.add_vehicle(LandsideVehicle.Kind.CAR, LandsideVehicle.Intent.PARK, aboard)
	var t := 0
	while _parked(control) < 4 and t < 2000:
		t += 1
		control.step(t, true, rng)
	assert_int(_parked(control)).is_equal(4)
	# Everyone got out, so no booking is aboard and the bookings are empty.
	var bookings := ArrivalBookings.new()
	var text := JSON.stringify(control.to_snapshot(bookings, t))
	assert_bool(loaded.from_snapshot(JSON.parse_string(text), ArrivalBookings.new())).is_true()
	loaded.wallet = Wallet.new()
	var leaves: Array[int] = []
	for id in control.vehicle_ids():
		leaves.append(control.get_vehicle(id).leave_tick)
	print("parked at %d, leaving at %s" % [t, leaves])
	assert_int(leaves.min()).is_greater_equal(t + LandsideSim.STAY_MIN_TICKS - 400)
	assert_int(leaves.max()).is_less_equal(t + LandsideSim.STAY_MAX_TICKS)
	# Nothing moves while every car is parked, so skip to just before the
	# next one leaves, then step both tick by tick while one drives.
	var gone := {}
	var first_bad := -1
	while not control.vehicle_ids().is_empty() and t < leaves.max() + 2000:
		t = maxi(t + 1, _next_leave(control) - 1)
		control.step(t, true, rng)
		loaded.step(t, true, rng)
		var a := JSON.stringify(control.to_snapshot(bookings, t))
		if first_bad < 0 and a != JSON.stringify(loaded.to_snapshot(bookings, t)):
			first_bad = t
		for id in [1, 2, 3, 4]:
			if not gone.has(id) and control.get_vehicle(id) == null:
				gone[id] = t
	print("left the map at %s, first differing %d" % [gone, first_bad])
	assert_int(gone.size()).is_equal(4)
	assert_int(first_bad).is_equal(-1)
	assert_array(loaded.vehicle_ids()).is_empty()
	assert_int(loaded.wallet.balance).is_equal(0)


## The earliest leave tick while every car is parked, else 0.
func _next_leave(sim: LandsideSim) -> int:
	var next := 0
	for id in sim.vehicle_ids():
		var v := sim.get_vehicle(id)
		if v.stage != LandsideVehicle.Stage.PARKED:
			return 0
		next = v.leave_tick if next == 0 else mini(next, v.leave_tick)
	return next


func _parked(sim: LandsideSim) -> int:
	var count := 0
	for id in sim.vehicle_ids():
		count += int(sim.get_vehicle(id).stage == LandsideVehicle.Stage.PARKED)
	return count
