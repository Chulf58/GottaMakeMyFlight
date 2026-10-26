class_name TestBoardingWindow
extends GdUnitTestSuite
## Measures the real route from every gate seat in the reference terminal to
## the plane door, and checks the flight's boarding window covers it at a walk.

const MARGIN_TICKS := 200


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func test_boarding_window_covers_the_walk_from_the_farthest_seat() -> void:
	var world := PassengerTestWorld.reference_world()
	var layout := world.sim.layout
	assert_int(layout.seats.size()).is_greater(0)
	var exit_id: int = layout.open_exits(world.grid)[0]
	var exit_cell := layout.door_cell(world.grid, exit_id)
	var apron_mm := world.sim.apron_length_mm(exit_id)
	var worst := 0
	for seat in layout.seats:
		var path := world.grid.find_path(seat["front"], exit_cell)
		assert_bool(path.is_empty()).is_false()
		var mm := Passenger.path_mm(path) + apron_mm
		worst = maxi(worst, PassengerSim.STAND_UP_TICKS + ceili(mm / float(PassengerSim.WALK_MM)))
	var window := world.flights.boarding_window(PassengerTestWorld.FLIGHT)
	print("MEASURE apron_mm=%d worst_seat_to_plane_ticks=%d window=%s" % [apron_mm, worst, window])
	assert_int(apron_mm).is_between(70000, 90000)
	assert_int(worst + MARGIN_TICKS).is_less_equal(window.y - window.x)
	world.free_all()
