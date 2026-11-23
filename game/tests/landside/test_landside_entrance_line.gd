class_name TestLandsideEntranceLine
extends GdUnitTestSuite
## Cars and taxis keep their passengers aboard only while the line outside the
## entrance is full (decision arrivals-wait-in-a-tidy-line-outside-the-
## entrance-when-check, EntranceLine): one place per passenger, in release
## order, so a party of four with one free place lets one out; the starter
## terminal's line holds its declared places off the doorway and the walk in,
## and a booking kept aboard for it that misses reads as check-in congestion.

var _world: LandsideTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
	_world = null


func _bare() -> LandsideSim:
	var sim: LandsideSim = auto_free(LandsideSim.new())
	assert_bool(sim.use_definition(LandsideTestWorld.STARTER)).is_true()
	sim.wallet = Wallet.new()
	return sim


## Steps `sim` with no budget until a vehicle wants to let someone out.
func _drive_to_release(sim: LandsideSim, rng: RandomNumberGenerator) -> int:
	for now in range(1, 3000):
		sim.step(now, true, rng, {}, 0)
		if not sim.denied.is_empty():
			return now
	return -1


func test_a_party_of_four_with_one_free_place_lets_one_out() -> void:
	var sim := _bare()
	var rng := RandomNumberGenerator.new()
	var party: Array[int] = [1, 2, 3, 4]
	var car := sim.add_vehicle(LandsideVehicle.Kind.CAR, LandsideVehicle.Intent.DROP, party)
	var at := _drive_to_release(sim, rng)
	assert_int(at).is_greater(0)
	assert_array(sim.denied).is_equal([1])
	assert_int(sim.get_vehicle(car).bookings.size()).is_equal(4)
	# Doors about to close: without the budget all four would get out at once.
	var closes := {1: at + 1, 2: at + 1, 3: at + 1, 4: at + 1}
	var events := sim.step(at + 1, true, rng, closes, 1)
	var out: Array = []
	for event: Dictionary in events:
		out.append_array(event["bookings"])
	prints("released", out, "denied", sim.denied, "aboard", sim.get_vehicle(car).bookings)
	assert_array(out).is_equal([1])
	assert_array(sim.denied).is_equal([2])
	assert_array(sim.get_vehicle(car).bookings).is_equal([2, 3, 4])


## Two taxis waiting at the curb with one place between them: one passenger
## gets out (in the order LandsideSim offers releases), the other stays aboard
## and gets out on the next place. Played twice, the same one goes first.
func test_one_place_lets_one_taxi_passenger_out_the_same_way_every_time() -> void:
	var chosen := []
	for run in 2:
		var sim := _bare()
		var rng := RandomNumberGenerator.new()
		var first: Array[int] = [1]
		var second: Array[int] = [2]
		sim.add_vehicle(LandsideVehicle.Kind.TAXI, LandsideVehicle.Intent.DROP, first)
		for now in range(1, 40):
			sim.step(now, true, rng, {}, 0)
		sim.add_vehicle(LandsideVehicle.Kind.TAXI, LandsideVehicle.Intent.DROP, second)
		var at := 40
		while sim.denied.size() < 2 and at < 3000:
			sim.step(at, true, rng, {}, 0)
			at += 1
		assert_array(sim.denied).contains_exactly_in_any_order([1, 2])
		var events := sim.step(at, true, rng, {}, 1)
		prints("one place, two taxis:", events, "kept aboard", sim.denied)
		assert_int(events.size()).is_equal(1)
		var out: int = events[0]["bookings"][0]
		chosen.append(out)
		assert_array(sim.denied).is_equal([3 - out])
		var next := sim.step(at + 1, true, rng, {}, 1)
		assert_int(next.size()).is_equal(1)
		assert_array(next[0]["bookings"]).is_equal([3 - out])
	assert_int(chosen[0]).is_equal(chosen[1])


func test_the_starter_line_holds_its_places_off_the_doorway_and_the_walk_in() -> void:
	_world = LandsideTestWorld.make()
	var sim := _world.sim
	var line := sim.entrance
	line.derive(sim)
	var door_id := sim.layout.passenger_entrances[0]
	var door := sim.layout.door_cell(sim.grid, door_id)
	var walk_in := {}
	for cells: Array in sim.layout.outside_routes.values():
		for cell: Vector2i in cells:
			walk_in[cell] = true
	var cells := {}
	for at in line.places:
		var cell := sim.grid.world_to_cell(at)
		cells[cell] = true
		assert_bool(walk_in.has(cell)).override_failure_message("on a walk: %s" % cell).is_false()
		assert_bool(SiteRoutes.is_open_ground(sim.grid, sim.site, cell)).is_true()
		var out := (cell - door).length()
		assert_float(out).is_greater_equal(float(EntranceLine.START_STEPS))
	prints("starter line: door", door, "places", cells.keys())
	assert_int(line.capacity()).is_equal(16)
	assert_int(cells.size()).is_equal(16)


func test_cars_hold_passengers_only_while_the_line_is_full_and_such_a_miss_is_check_in() -> void:
	_world = LandsideTestWorld.make(null, PassengerTestWorld.starts_with(1500, 2400))
	var sim := _world.sim
	var world := _world.world
	world.step()
	for desk in sim.layout.desks:
		for i in sim.layout.line_of(desk).size():
			HoldLineKit.member(world, desk)
	world.step()
	var waiting: Array[int] = []
	for i in sim.entrance.capacity():
		waiting.append(sim.spawn_now(PassengerTestWorld.FLIGHT))
	assert_bool(waiting.has(0)).is_false()
	_world.schedule(12)
	_world.run_to(2400 + 2)
	var result := FlightResult.summarize(sim, PassengerTestWorld.FLIGHT)
	prints("released", _world.released.size(), "held missed", sim.entrance.held_missed)
	prints("reasons", result["reasons"])
	assert_int(_world.released.size()).is_equal(0)
	assert_int(int(sim.entrance.held_missed.get(PassengerTestWorld.FLIGHT, 0))).is_greater(0)
	var texts := {}
	for reason: Dictionary in result["reasons"]:
		texts[reason["text"]] = reason["count"]
	# Every booking missed aboard, kept for the line or queued behind a car that
	# was: all of it is check-in congestion, none reads as a road delay.
	assert_int(int(sim.entrance.held_missed.get(PassengerTestWorld.FLIGHT, 0))).is_equal(12)
	assert_bool(texts.has(FlightResult.WAITING_FOR_DROP_OFF)).is_false()
	assert_int(int(texts.get(FlightResult.ENTRANCE_LINE_TEXT, 0))).is_equal(
		EntranceLine.MAX_PLACES + 12
	)


## The world on `definition` (the starter road when null) with every desk's
## line taken and the line outside the entrance full, doors closing at 2400.
func _full_line(definition: LandsideDefinition) -> void:
	_world = LandsideTestWorld.make(definition, PassengerTestWorld.starts_with(1500, 2400))
	var sim := _world.sim
	_world.world.step()
	for desk in sim.layout.desks:
		for i in sim.layout.line_of(desk).size():
			HoldLineKit.member(_world.world, desk)
	_world.world.step()
	for i in sim.entrance.capacity():
		assert_int(sim.spawn_now(PassengerTestWorld.FLIGHT)).is_greater(0)


func _reason_counts() -> Dictionary:
	var texts := {}
	for reason: Dictionary in (
		FlightResult.summarize(_world.sim, PassengerTestWorld.FLIGHT)["reasons"]
	):
		texts[reason["text"]] = reason["count"]
	return texts


## Cars still driving in when the doors close, held up by nothing the line
## does, miss for the road even though the line outside is full then.
func test_a_road_delay_while_the_line_is_full_is_not_check_in_congestion() -> void:
	_full_line(null)
	var sim := _world.sim
	_world.schedule(4)
	# Every party sets off so late that the doors close on its car on the road in.
	for id in sim.arrivals.booking_ids():
		sim.arrivals.get_booking(id).unload_tick = 2400 + 40
	_world.run_to(2399)
	var on_road := 0
	for id in _world.landside.vehicle_ids():
		var v := _world.landside.get_vehicle(id)
		on_road += v.bookings.size()
		assert_bool(_world.landside.line_held.has(id)).is_false()
	var room := sim.entrance.room_for_arrivals(sim)
	_world.run_to(2400 + 2)
	var texts := _reason_counts()
	prints("aboard on the road", on_road, "line room", room, "reasons", texts)
	assert_int(on_road).is_equal(4)
	assert_int(room).is_equal(0)
	assert_int(int(sim.arrivals.missed_by_flight.get(PassengerTestWorld.FLIGHT, 0))).is_equal(4)
	assert_int(int(sim.entrance.held_missed.get(PassengerTestWorld.FLIGHT, 0))).is_equal(0)
	assert_int(int(texts.get(FlightResult.WAITING_FOR_DROP_OFF, 0))).is_equal(4)


## A car queued for the one berth behind a car kept for the line is kept for
## the line too; a place opening in the line on the closing tick does not
## turn its miss into a road delay.
func test_a_car_queued_behind_one_kept_for_the_line_misses_for_check_in() -> void:
	_full_line(LandsideTestWorld.with_berths(1))
	var sim := _world.sim
	var landside := _world.landside
	_world.schedule(12)
	_world.run_to(2399)
	var queued := 0
	var aboard := 0
	for id in landside.vehicle_ids():
		var v := landside.get_vehicle(id)
		aboard += v.bookings.size()
		var denied := v.bookings.any(func(b: int) -> bool: return landside.denied.has(b))
		if landside.line_held.has(id) and not denied:
			queued += v.bookings.size()
	assert_bool(sim.flights.is_doors_closed(PassengerTestWorld.FLIGHT)).is_false()
	# A place opens in the line on the closing tick.
	var last: int = sim.entrance.order.back()
	PassengerLifecycle.finish(sim, sim.get_passenger(last), false)
	assert_int(sim.entrance.room_for_arrivals(sim)).is_greater(0)
	_world.step()
	var texts := _reason_counts()
	prints("aboard", aboard, "queued behind", queued, "reasons", texts)
	assert_bool(sim.flights.is_doors_closed(PassengerTestWorld.FLIGHT)).is_true()
	assert_int(queued).is_greater(0)
	assert_int(int(sim.arrivals.missed_by_flight.get(PassengerTestWorld.FLIGHT, 0))).is_equal(
		aboard
	)
	assert_int(int(sim.entrance.held_missed.get(PassengerTestWorld.FLIGHT, 0))).is_equal(aboard)
	assert_bool(texts.has(FlightResult.WAITING_FOR_DROP_OFF)).is_false()


## A car of `bookings` standing in berth `berth` of `sim`, in its unload gap
## (`gap` ticks left) or, with 0, about to let its next passenger out.
static func _in_berth(sim: LandsideSim, berth: int, bookings: Array[int], gap: int) -> int:
	var id := sim.add_vehicle(LandsideVehicle.Kind.TAXI, LandsideVehicle.Intent.DROP, bookings)
	var v := sim.get_vehicle(id)
	v.lane = LandsideVehicle.Lane.BERTH
	v.stage = LandsideVehicle.Stage.DWELL
	v.stop = berth
	v.pos_mm = sim.paths.berth_stand[berth]
	v.release_wait = gap
	return id


## The curb with bay 0 built (berths 2 and 3, upstream of the starter curb's
## two): every berth but 2 holds a car in its unload gap, berth 2 a car kept
## for the line, and a car waits on road_in at the stop, or with
## `starter_stop` at the starter curb's stop. One step with no line budget;
## whether that waiting car is kept for the line.
func _queued_kept(starter_stop: bool) -> bool:
	var sim := _bare()
	assert_bool(sim.build_curb(0)).is_true()
	var pos_mm := LandsideTestWorld.STARTER.curb.stop_mm if starter_stop else sim.curb_stop_mm()
	var booking := 1
	for berth in [0, 1, 3]:
		var party: Array[int] = [booking]
		_in_berth(sim, berth, party, 5)
		booking += 1
	var kept_party: Array[int] = [booking]
	var kept := _in_berth(sim, 2, kept_party, 0)
	var queued_party: Array[int] = [booking + 1]
	var queued := sim.add_vehicle(
		LandsideVehicle.Kind.TAXI, LandsideVehicle.Intent.DROP, queued_party
	)
	sim.get_vehicle(queued).pos_mm = pos_mm
	sim.get_vehicle(queued).stage = LandsideVehicle.Stage.QUEUE
	sim._rederive()
	sim.step(1, true, RandomNumberGenerator.new(), {}, 0)
	prints(
		"waiting at",
		pos_mm,
		"stop",
		sim.curb_stop_mm(),
		"berth 2 split",
		sim.paths.berth_split[2],
		"line held",
		sim.line_held.keys(),
		"denied",
		sim.denied
	)
	# Control: the car in berth 2 was kept for the line, and the waiting car
	# found no berth free.
	assert_bool(sim.line_held.has(kept)).is_true()
	assert_array(sim.denied).is_equal([booking])
	assert_int(sim.get_vehicle(queued).lane).is_equal(LandsideVehicle.Lane.ROAD_IN)
	return sim.line_held.has(queued)


## A car waiting at the stop is kept for the line only by a kept car in a
## berth it could have taken: one already past that berth's way in (at the
## starter curb's stop, downstream of bay 0) is held up by the cars in their
## unload gap, a road delay, not by the line.
func test_a_kept_car_in_a_berth_the_waiting_car_cannot_take_does_not_keep_it() -> void:
	# Control: at the stop before bay 0 it could take berth 2, so it is kept.
	assert_bool(_queued_kept(false)).is_true()
	assert_bool(_queued_kept(true)).is_false()
