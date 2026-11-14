extends GdUnitTestSuite
## Which misses on the road read as check-in congestion (EntranceLine.held,
## board 66be00a0 fix round 3): a booking aboard a car the line outside the
## entrance kept stays marked while it is still aboard, after the hold clears
## too, and a car the line never held up misses for the road even while the
## line is full.

const CLOSE := 2400

var _world: LandsideTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
	_world = null


## Fills every desk's line and the line outside the entrance.
func _fill_line() -> void:
	var sim := _world.sim
	for i in sim.entrance.capacity() - sim.entrance.order.size():
		assert_int(sim.spawn_now(PassengerTestWorld.FLIGHT)).is_greater(0)


## Frees every place of the line outside the entrance: its waiting
## passengers are made.
func _empty_line() -> void:
	var sim := _world.sim
	for id: int in sim.entrance.order.duplicate():
		PassengerLifecycle.finish(sim, sim.get_passenger(id), false)


## The one-berth curb, check-in and the line outside full, doors closing at
## CLOSE: the first two parties due at `early` (one car takes the berth and
## is kept for the line, the next queues behind it), a third due at `late`,
## the rest after the doors close. Returns the vehicles' bookings by party
## order [first, second, third].
func _scenario(early: int, late: int) -> Array:
	_world = LandsideTestWorld.make(
		LandsideTestWorld.with_berths(1), PassengerTestWorld.starts_with(1500, CLOSE)
	)
	var sim := _world.sim
	_world.step()
	for desk in sim.layout.desks:
		for i in sim.layout.line_of(desk).size():
			HoldLineKit.member(_world.world, desk)
	_world.step()
	_fill_line()
	_world.schedule(10)
	var parties := []
	for id in sim.arrivals.booking_ids():
		var b := sim.arrivals.get_booking(id)
		var index := parties.find(b.party)
		if index < 0:
			parties.append(b.party)
			index = parties.size() - 1
		var due := early if index < 2 else (late if index == 2 else CLOSE + 2000)
		var members := 0
		for other in sim.arrivals.booking_ids():
			var o := sim.arrivals.get_booking(other)
			members += int(o.party == b.party and o.id < b.id)
		b.unload_tick = due + members * LandsideSim.RELEASE_GAP_TICKS
	var bookings := []
	for party in parties.slice(0, 3):
		var ids: Array[int] = []
		for id in sim.arrivals.booking_ids():
			if sim.arrivals.get_booking(id).party == party:
				ids.append(id)
		bookings.append(ids)
	return bookings


func _vehicle_of(booking: int) -> LandsideVehicle:
	var landside := _world.landside
	for id in landside.vehicle_ids():
		if landside.get_vehicle(id).bookings.has(booking):
			return landside.get_vehicle(id)
	return null


func _reasons() -> Dictionary:
	var texts := {}
	for reason: Dictionary in (
		FlightResult.summarize(_world.sim, PassengerTestWorld.FLIGHT)["reasons"]
	):
		texts[reason["text"]] = reason["count"]
	return texts


## The first car takes the berth and is kept for the line; the second queues
## behind it and is kept too. The line then empties, the first car lets its
## party out and the hold is over, but the second is still queued behind it
## when the doors close: its miss is check-in congestion, not a road delay.
func test_a_car_kept_for_the_line_then_freed_but_still_queued_misses_for_check_in() -> void:
	var parties := _scenario(2200, CLOSE + 2000)
	var sim := _world.sim
	var landside := _world.landside
	_world.run_to(2330)
	var first := _vehicle_of(parties[0][0])
	var second := _vehicle_of(parties[1][0])
	# Control: the line held both cars up.
	assert_bool(landside.line_held.has(first.id)).is_true()
	assert_bool(landside.line_held.has(second.id)).is_true()
	_empty_line()
	_world.run_to(CLOSE - 1)
	prints(
		"first aboard",
		first.bookings,
		"second aboard",
		second.bookings,
		"kept now",
		landside.line_held.keys(),
		"held",
		sim.entrance.held.keys()
	)
	assert_array(first.bookings).is_empty()
	assert_array(second.bookings).is_equal(parties[1])
	assert_bool(landside.line_held.has(second.id)).is_false()
	_world.run_to(CLOSE + 2)
	var texts := _reasons()
	prints("reasons", texts, "held missed", sim.entrance.held_missed)
	var size: int = parties[1].size()
	assert_int(int(sim.arrivals.missed_by_flight.get(PassengerTestWorld.FLIGHT, 0))).is_equal(size)
	assert_int(int(sim.entrance.held_missed.get(PassengerTestWorld.FLIGHT, 0))).is_equal(size)
	assert_bool(texts.has(FlightResult.WAITING_FOR_DROP_OFF)).is_false()


## As above, and a third car turns up after the hold is over: it queues
## behind the second, held up only by the road, while the line outside is full
## again when the doors close. Its miss is a road delay; the second car's is
## still check-in congestion.
func test_a_car_the_line_never_held_misses_for_the_road_with_the_line_full() -> void:
	var parties := _scenario(2200, 2380)
	var sim := _world.sim
	var landside := _world.landside
	_world.run_to(2330)
	assert_bool(landside.line_held.has(_vehicle_of(parties[1][0]).id)).is_true()
	_empty_line()
	_world.run_to(2336)
	_fill_line()
	var third: LandsideVehicle = null
	var third_kept := 0
	var third_marked := 0
	for t in range(2337, CLOSE):
		_world.step()
		if third == null:
			third = _vehicle_of(parties[2][0])
		if third != null:
			third_kept += int(landside.line_held.has(third.id))
		for id: int in parties[2]:
			third_marked += int(sim.entrance.held.has(id))
	var room := sim.entrance.room_for_arrivals(sim)
	prints(
		"third",
		third.id if third != null else 0,
		"aboard",
		third.bookings if third != null else [],
		"stage",
		third.stage if third != null else -1,
		"kept ticks",
		third_kept,
		"marked ticks",
		third_marked,
		"line room",
		room
	)
	# Control: the third car is on the road, queued, with its party aboard.
	assert_object(third).is_not_null()
	assert_array(third.bookings).is_equal(parties[2])
	assert_int(third.stage).is_equal(LandsideVehicle.Stage.QUEUE)
	assert_int(room).is_equal(0)
	assert_int(third_kept).is_equal(0)
	assert_int(third_marked).is_equal(0)
	_world.run_to(CLOSE + 2)
	var texts := _reasons()
	prints("reasons", texts, "held missed", sim.entrance.held_missed)
	var second: int = parties[1].size()
	var road: int = parties[2].size()
	assert_int(int(sim.arrivals.missed_by_flight.get(PassengerTestWorld.FLIGHT, 0))).is_equal(
		second + road
	)
	assert_int(int(sim.entrance.held_missed.get(PassengerTestWorld.FLIGHT, 0))).is_equal(second)
	assert_int(int(texts.get(FlightResult.WAITING_FOR_DROP_OFF, 0))).is_equal(road)
