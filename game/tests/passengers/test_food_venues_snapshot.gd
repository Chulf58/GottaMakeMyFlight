class_name TestFoodVenuesSnapshot
extends GdUnitTestSuite
## A save taken in the middle of a bar or restaurant visit loads and plays on
## exactly (F4-6). The venue is not saved: it is derived from the room's type
## on load, so a load keeps the long order and dwell of its own room type and
## pays by its base spend. A dwell that does not match the room type is refused.

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


func _world(venue: StringName, seed := SEED) -> PassengerTestWorld:
	var grid := BuildGrid.new()
	CafeTestLayout.build(grid, false, null, venue)
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), seed)
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


func _load(text: String) -> PassengerTestWorld:
	var data: Dictionary = JSON.parse_string(text)
	var grid := BuildGrid.new()
	assert_bool(grid.from_snapshot(data["grid"])).is_true()
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), 99)
	_worlds.append(world)
	assert_bool(world.clock.from_snapshot(data["clock"])).is_true()
	assert_bool(world.flights.from_snapshot(data["flights"])).is_true()
	assert_bool(world.sim.from_snapshot(data["passengers"])).is_true()
	assert_bool(world.sim.wallet.from_snapshot(data["wallet"])).is_true()
	return world


## A world with one airside guest on a visit to `venue`, run to `stage`.
func _seated(venue: StringName, stage: Passenger.Stage) -> Array:
	var world := _world(venue)
	var p := world.passenger(world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.hunger = 0
	p.cafe_cooldown = 1000000
	while p.stage != Passenger.Stage.TO_GATE and world.clock.tick < 900:
		world.step()
	assert_bool(world.sim.cafes.try_visit(p)).is_true()
	while p.stage != stage and world.clock.tick < 2500:
		world.step()
	assert_int(p.stage).is_equal(stage)
	return [world, p]


func test_a_restaurant_visit_saved_while_seated_plays_on_exactly() -> void:
	var made := _seated(&"restaurant", Passenger.Stage.CAFE_SEATED)
	var a: PassengerTestWorld = made[0]
	var guest: Passenger = made[1]
	var text := JSON.stringify(_save(a))
	var b := _load(text)
	var visit_b := b.sim.cafes.visit_of(guest.id)
	assert_str(String(visit_b.venue)).is_equal("restaurant")
	var visit_a := a.sim.cafes.visit_of(guest.id)
	assert_int(visit_b.dwell_end).is_equal(visit_a.dwell_end)
	# The dwell is the restaurant's: well past a cafe's.
	assert_int(visit_b.dwell_end - guest.stage_tick).is_equal(
		RoomTypes.get_type(&"restaurant").dwell_ticks
	)
	var end := visit_a.dwell_end + 200
	a.run_to(end)
	b.run_to(end)
	print("balance a %d, b %d" % [a.sim.wallet.balance, b.sim.wallet.balance])
	assert_int(b.sim.wallet.balance).is_equal(a.sim.wallet.balance)
	assert_int(a.sim.wallet.balance).is_greater(0)
	assert_str(b.signature()).is_equal(a.signature())


func test_a_bar_visit_saved_while_ordering_plays_on_exactly() -> void:
	var made := _seated(&"bar", Passenger.Stage.CAFE_ORDER)
	var a: PassengerTestWorld = made[0]
	var guest: Passenger = made[1]
	var b := _load(JSON.stringify(_save(a)))
	var visit_a := a.sim.cafes.visit_of(guest.id)
	assert_int(b.sim.cafes.visit_of(guest.id).service_end).is_equal(visit_a.service_end)
	assert_int(visit_a.service_end - guest.stage_tick).is_equal(
		RoomTypes.get_type(&"bar").order_ticks
	)
	var end := visit_a.service_end + 600
	a.run_to(end)
	b.run_to(end)
	assert_int(b.sim.wallet.balance).is_equal(a.sim.wallet.balance)
	assert_int(a.sim.wallet.balance).is_greater(0)
	assert_str(b.signature()).is_equal(a.signature())


func test_a_dwell_of_the_wrong_room_type_is_refused() -> void:
	var made := _seated(&"restaurant", Passenger.Stage.CAFE_SEATED)
	var a: PassengerTestWorld = made[0]
	var guest: Passenger = made[1]
	var save := _save(a)
	var visits: Array = save["passengers"]["cafe"]["visits"]
	assert_int(visits.size()).is_equal(1)
	# A cafe's dwell in a restaurant.
	visits[0]["dwell_end"] = guest.stage_tick + RoomTypes.get_type(&"cafe").dwell_ticks
	var data: Dictionary = JSON.parse_string(JSON.stringify(save))
	var grid := BuildGrid.new()
	assert_bool(grid.from_snapshot(data["grid"])).is_true()
	var b := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), 99)
	_worlds.append(b)
	assert_bool(b.clock.from_snapshot(data["clock"])).is_true()
	assert_bool(b.flights.from_snapshot(data["flights"])).is_true()
	assert_bool(b.sim.from_snapshot(data["passengers"])).is_false()
