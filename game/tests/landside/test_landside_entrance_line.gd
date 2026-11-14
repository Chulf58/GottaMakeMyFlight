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
	assert_int(int(texts.get(FlightResult.ENTRANCE_LINE_TEXT, 0))).is_greater(
		EntranceLine.MAX_PLACES
	)
