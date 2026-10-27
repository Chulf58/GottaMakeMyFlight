class_name TestRatingBinding
extends GdUnitTestSuite
## Binding is idempotent for the same sims and moves cleanly to different ones,
## so a signal is never connected twice.

var _worlds: Array[PassengerTestWorld] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for world in _worlds:
		world.free_all()
	_worlds.clear()


## A floored room with no entrance and 5 scheduled passengers: when the doors
## close on tick 20 they are 5 no-shows.
func _world() -> PassengerTestWorld:
	var grid := PassengerTestWorld.floored(Vector2i(8, 6))
	var world := PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(10, 20))
	world.sim.schedule_flight(PassengerTestWorld.FLIGHT, 5)
	_worlds.append(world)
	return world


## How many callables listen to the signals the rating binds on a world.
func _listeners(world: PassengerTestWorld) -> int:
	return (
		world.clock.ticked.get_connections().size()
		+ world.flights.doors_closed.get_connections().size()
		+ world.sim.outcome.get_connections().size()
	)


func _rating() -> AirportRating:
	return auto_free(AirportRating.new()) as AirportRating


func test_binding_the_same_sims_twice_counts_once() -> void:
	var world := _world()
	var rating := _rating()
	var before := _listeners(world)
	rating.bind(world.clock, world.flights, world.sim)
	rating.bind(world.clock, world.flights, world.sim)
	assert_int(_listeners(world)).is_equal(before + 3)
	world.run_to(21)
	assert_int(rating.parts()["missed"]).is_equal(5)


func test_ready_after_an_earlier_bind_does_not_connect_again() -> void:
	var world := _world()
	var rating := _rating()
	rating.clock = world.clock
	rating.flights = world.flights
	rating.passengers = world.sim
	rating.bind(world.clock, world.flights, world.sim)
	# Entering the tree runs _ready, which binds the exports again.
	add_child(rating)
	world.run_to(21)
	assert_int(rating.parts()["missed"]).is_equal(5)


func test_binding_other_sims_leaves_the_old_ones() -> void:
	var first := _world()
	var second := _world()
	var rating := _rating()
	var first_before := _listeners(first)
	var second_before := _listeners(second)
	rating.bind(first.clock, first.flights, first.sim)
	assert_int(_listeners(first)).is_equal(first_before + 3)
	rating.bind(second.clock, second.flights, second.sim)
	assert_int(_listeners(first)).is_equal(first_before)
	assert_int(_listeners(second)).is_equal(second_before + 3)
	first.run_to(21)
	assert_int(rating.parts()["missed"]).is_equal(0)
	second.run_to(21)
	assert_int(rating.parts()["missed"]).is_equal(5)
	assert_object(rating.passengers).is_same(second.sim)
