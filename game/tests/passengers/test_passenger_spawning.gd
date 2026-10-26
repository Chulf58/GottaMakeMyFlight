class_name TestPassengerSpawning
extends GdUnitTestSuite
## Spawning ahead of the flight from the saved sim RNG, and the debug batch.

var _worlds: Array[PassengerTestWorld] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for world in _worlds:
		world.free_all()
	_worlds.clear()


func _reference(seed: int) -> PassengerTestWorld:
	var world := PassengerTestWorld.reference_world(seed)
	_worlds.append(world)
	return world


func _spawned(world: PassengerTestWorld) -> Array:
	var out := []
	for id in world.sim.passenger_ids():
		var p := world.passenger(id)
		out.append([p.spawn_tick, p.variant])
	return out


func test_a_flight_spawns_its_passengers_ahead_of_doors_close() -> void:
	var world := _reference(7)
	world.sim.schedule_flight(PassengerTestWorld.FLIGHT, 24)
	assert_int(world.sim.pending_spawns()).is_equal(24)
	var doors := world.flights.doors_close_tick(PassengerTestWorld.FLIGHT)
	world.run_to(doors - PassengerSim.LAST_SPAWN_LEAD_TICKS + 1)
	assert_int(world.sim.pending_spawns()).is_equal(0)
	assert_int(world.sim.passenger_ids().size()).is_equal(24)
	var variants := {}
	for id in world.sim.passenger_ids():
		var p := world.passenger(id)
		assert_str(p.flight_id).is_equal(PassengerTestWorld.FLIGHT)
		assert_int(p.spawn_tick).is_between(1, doors - PassengerSim.LAST_SPAWN_LEAD_TICKS)
		assert_int(p.boarding_tick).is_equal(700)
		variants[p.variant] = true
	assert_int(variants.size()).is_equal(2)


func test_the_same_seed_spawns_the_same_passengers() -> void:
	var a := _reference(11)
	var b := _reference(11)
	var c := _reference(12)
	for world in [a, b, c]:
		world.sim.schedule_flight(PassengerTestWorld.FLIGHT, 24)
		world.run_to(1200)
	assert_array(_spawned(a)).is_equal(_spawned(b))
	assert_array(_spawned(a)).is_not_equal(_spawned(c))


func test_debug_batch_spawns_300_through_normal_spawning_and_records_its_seed() -> void:
	var world := _reference(3)
	world.sim.spawn_batch(300, 987654321)
	assert_int(world.sim.last_batch_seed).is_equal(987654321)
	assert_int(world.sim.pending_spawns()).is_equal(300)
	world.run_to(320)
	assert_int(world.sim.pending_spawns()).is_equal(0)
	assert_int(world.sim.passenger_ids().size()).is_equal(300)
	var entrance := ReferenceTerminal.ENTRANCE_CELL
	var first := world.passenger(world.sim.passenger_ids()[0])
	assert_int(first.spawn_tick).is_greater(0)
	var again := _reference(3)
	again.sim.spawn_batch(300, 987654321)
	again.run_to(320)
	assert_array(_spawned(again)).is_equal(_spawned(world))
	var layout := world.sim.layout
	assert_that(layout.door_cell(world.grid, layout.entrances[0])).is_equal(entrance)
