class_name TestStallWalkOnSnapshot
extends GdUnitTestSuite
## A save taken in the middle of a stall visit loads and plays on exactly. A
## walk-on visit holds no seat: its seat key is empty, several can share the
## queue, and a seat key on one (or none on a seated venue's) is refused.

const SEED := 4242

var _worlds: Array[PassengerTestWorld] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for world in _worlds:
		world.free_all()
	_worlds.clear()


func _world(venue: StringName, tables: bool) -> PassengerTestWorld:
	var grid := BuildGrid.new()
	CafeTestLayout.build(grid, false, null, venue, tables)
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), SEED)
	_worlds.append(world)
	return world


func _save(world: PassengerTestWorld) -> Dictionary:
	return {
		"clock": world.clock.to_snapshot(),
		"flights": world.flights.to_snapshot(),
		"grid": world.grid.to_snapshot(),
		"passengers": world.sim.to_snapshot(),
		"wallet": world.sim.wallet.to_snapshot(),
	}


## The world a save describes, or null when its passengers are refused.
func _load(save: Dictionary) -> PassengerTestWorld:
	var data: Dictionary = JSON.parse_string(JSON.stringify(save))
	var grid := BuildGrid.new()
	assert_bool(grid.from_snapshot(data["grid"])).is_true()
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), 99)
	_worlds.append(world)
	assert_bool(world.clock.from_snapshot(data["clock"])).is_true()
	assert_bool(world.flights.from_snapshot(data["flights"])).is_true()
	if not world.sim.from_snapshot(data["passengers"]):
		return null
	assert_bool(world.sim.wallet.from_snapshot(data["wallet"])).is_true()
	return world


## `count` airside guests committed to `venue` visits as they reach the gate
## leg, run until the first is in `stage`. Returns [world, guests].
func _visiting(venue: StringName, tables: bool, count: int, stage: Passenger.Stage) -> Array:
	var world := _world(venue, tables)
	var guests: Array[Passenger] = []
	for i in count:
		var p := world.passenger(world.sim.spawn_now(PassengerTestWorld.FLIGHT))
		p.hunger = 0
		p.cafe_cooldown = 1000000
		guests.append(p)
	var committed := {}
	var found := false
	while not found and world.clock.tick < 2500:
		world.step()
		for guest in guests:
			if guest.stage == Passenger.Stage.TO_GATE and not committed.has(guest.id):
				assert_bool(world.sim.cafes.try_visit(guest)).is_true()
				committed[guest.id] = true
		# All committed, one in `stage`, and (with several) a queue behind it.
		found = committed.size() == count and world.sim.cafes.visit_ids().size() >= mini(count, 2)
		found = found and guests.any(func(g: Passenger) -> bool: return g.stage == stage)
	assert_bool(found).is_true()
	return [world, guests]


func _assert_plays_on_exactly(a: PassengerTestWorld, b: PassengerTestWorld, until: int) -> void:
	a.run_to(until)
	b.run_to(until)
	print("balance a %d, b %d" % [a.sim.wallet.balance, b.sim.wallet.balance])
	assert_int(b.sim.wallet.balance).is_equal(a.sim.wallet.balance)
	assert_int(a.sim.wallet.balance).is_greater(0)
	assert_str(b.signature()).is_equal(a.signature())


func test_a_stall_visit_saved_while_ordering_plays_on_exactly() -> void:
	var made := _visiting(&"stall", false, 1, Passenger.Stage.CAFE_ORDER)
	var a: PassengerTestWorld = made[0]
	var guest: Passenger = made[1][0]
	var visit_a := a.sim.cafes.visit_of(guest.id)
	assert_str(visit_a.seat_key).is_empty()
	var b := _load(_save(a))
	assert_object(b).is_not_null()
	var visit_b := b.sim.cafes.visit_of(guest.id)
	assert_bool(visit_b.walk_on()).is_true()
	assert_str(visit_b.seat_key).is_empty()
	assert_int(visit_b.service_end).is_equal(visit_a.service_end)
	assert_int(visit_b.deadline).is_equal(visit_a.deadline)
	_assert_plays_on_exactly(a, b, visit_a.service_end + 200)
	assert_int(visit_b.outcome).is_equal(CafeVisit.Outcome.COMPLETE)


func test_a_queue_of_stall_guests_with_no_seat_keys_saved_mid_order_plays_on_exactly() -> void:
	var made := _visiting(&"stall", false, 3, Passenger.Stage.CAFE_ORDER)
	var a: PassengerTestWorld = made[0]
	var guests: Array = made[1]
	var queued := 0
	for guest: Passenger in guests:
		var visit := a.sim.cafes.visit_of(guest.id)
		if visit != null:
			queued += 1
			assert_str(visit.seat_key).is_empty()
	print("%d stall guests saved with visits" % queued)
	assert_int(queued).is_greater(1)
	var b := _load(_save(a))
	assert_object(b).is_not_null()
	for guest: Passenger in guests:
		var in_a := a.sim.cafes.visit_of(guest.id) != null
		assert_bool(b.sim.cafes.visit_of(guest.id) != null).is_equal(in_a)
	_assert_plays_on_exactly(a, b, a.clock.tick + 600)


func test_a_seat_key_on_a_stall_visit_is_refused() -> void:
	var made := _visiting(&"stall", false, 1, Passenger.Stage.CAFE_ORDER)
	var save := _save(made[0])
	var visits: Array = save["passengers"]["cafe"]["visits"]
	assert_int(visits.size()).is_equal(1)
	visits[0]["seat_key"] = "1:0"
	assert_object(_load(save)).is_null()


func test_a_cafe_visit_with_no_seat_key_is_refused() -> void:
	var made := _visiting(&"cafe", true, 1, Passenger.Stage.CAFE_ORDER)
	var save := _save(made[0])
	var visits: Array = save["passengers"]["cafe"]["visits"]
	assert_int(visits.size()).is_equal(1)
	visits[0]["seat_key"] = ""
	assert_object(_load(save)).is_null()
