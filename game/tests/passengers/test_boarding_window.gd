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


## The same walk on the airport site, where the exit walks to the plane door
## at the starter stand (decision plane-stand-design-airside-moves-110-m-north-
## stand-snaps-to, point 7: boarding stays at 1200 ticks).
func test_boarding_window_covers_the_walk_on_the_site() -> void:
	var site: SiteDefinition = load("res://build/terminal_site.tres")
	var grid := BuildGrid.new(site.grid_size, site.grid_origin)
	assert_bool(ReferenceTerminal.build(grid, site.starter_offset)).is_true()
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	world.sim.site = site
	var layout := world.sim.layout
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
	print("SITE apron_mm=%d worst_seat_to_plane_ticks=%d window=%s" % [apron_mm, worst, window])
	assert_int(window.y - window.x).is_equal(1200)
	assert_int(apron_mm).is_between(6000, 9000)
	assert_int(worst + MARGIN_TICKS).is_less_equal(window.y - window.x)
	world.free_all()
