class_name TestStarterTerminal
extends GdUnitTestSuite
## The starter terminal (ReferenceTerminal, the debug starter button's layout)
## on the airport site: both its doors have a walk outside, so they are in
## service, and a passenger walks in from the road, through the terminal and
## out to the plane, and makes the flight.

const SITE := preload("res://build/terminal_site.tres")
const LAST_TICK := 1900

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := BuildGrid.new(SITE.grid_size, SITE.grid_origin)
	assert_bool(ReferenceTerminal.build(grid)).is_true()
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_world.sim.site = SITE


func after_test() -> void:
	_world.free_all()
	_world = null


func test_both_doors_have_a_walk_outside_and_are_in_service() -> void:
	var ids := ReferenceTerminal.object_ids(_world.grid)
	var entrance: int = ids["entrances"][0]
	var exit_door: int = ids["exits"][0]
	var layout := _world.sim.layout
	assert_bool(layout.outside_routes.has(entrance)).is_true()
	assert_bool(layout.outside_routes.has(exit_door)).is_true()
	assert_array(layout.out_of_service).is_empty()
	assert_array(layout.passenger_entrances).contains_exactly([entrance])
	var walk_in := OutsideWalks.arrival(_world.sim, entrance)
	var walk_out := OutsideWalks.departure(_world.sim, exit_door)
	print(
		"walk in %s .. %s, walk out %s .. %s" % [walk_in[0], walk_in[-1], walk_out[0], walk_out[-1]]
	)
	# The walk in starts on the pavement line by the road, the walk out ends at
	# the plane door.
	assert_float(walk_in[0].z).is_equal_approx(SITE.road_z, 0.01)
	assert_vector(walk_out[-1]).is_equal_approx(SITE.plane_route[-1], Vector3.ONE * 0.01)


func test_a_passenger_walks_from_the_road_to_the_plane_and_makes_the_flight() -> void:
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	assert_int(p.apron_total_mm()).is_greater(0)
	_world.run_to(LAST_TICK)
	print("stage %s at tick %d" % [Passenger.Stage.keys()[p.stage], _world.clock.tick])
	assert_int(p.stage).is_equal(Passenger.Stage.MADE)
	assert_int(_world.sim.made_count()).is_equal(1)


func test_on_the_default_grid_the_layout_is_the_reference_one() -> void:
	var grid := BuildGrid.new()
	assert_bool(ReferenceTerminal.build(grid)).is_true()
	var ids := ReferenceTerminal.object_ids(grid)
	assert_that(grid.get_object(ids["entrances"][0])["anchor"]).is_equal(
		ReferenceTerminal.ENTRANCE_CELL
	)
	assert_that(grid.get_object(ids["exits"][0])["anchor"]).is_equal(ReferenceTerminal.EXIT_CELL)
