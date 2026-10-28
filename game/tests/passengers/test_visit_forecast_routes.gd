class_name TestVisitForecastRoutes
extends GdUnitTestSuite
## The routed visit forecast prices the exit the passenger really takes, and
## keeps its route lengths until an edit (decision
## toilet-design-queue-free-reservable-stalls-per-stall-daily-u, point 3).
## With two exits whose walks outside differ a lot, a passenger picks the
## exit nearest inside (PassengerSim._choose_exit()); the forecast picks the
## same one, so the passenger arrives when forecast, not after it. Route
## lengths are searched once and searched again only after a grid edit.

## A floored strip with exit B at its west end and exit C at its east end on
## the north edge; the plane stands just outside C, so B's walk outside is
## long and C's short.
const SIZE := Vector2i(40, 10)
const EXIT_B := Vector2i(2, 0)
const EXIT_C := Vector2i(37, 0)
const ENTRANCE := Vector2i(20, 9)
## Nearer B inside, but nearer the plane through C.
const START := Vector2i(12, 5)
const BOARDING := 30
const DOORS := 6000
## Ticks the sim may spend beyond the forecast where one leg of the walk
## hands over to the next.
const HANDOVER_TICKS := 4

## Free floor between the scanner lanes and the east wall of the reference
## terminal, landside.
const LANDSIDE_CELL := Vector2i(20, 14)

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
		_world = null


func _two_exit_world() -> Dictionary:
	var grid := PassengerTestWorld.floored(SIZE)
	var b := PassengerTestWorld.place(grid, &"exit_door", EXIT_B, 0)
	var c := PassengerTestWorld.place(grid, &"exit_door", EXIT_C, 0)
	PassengerTestWorld.place(grid, &"entrance_door", ENTRANCE, 2)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(BOARDING, DOORS))
	var plane := grid.cell_to_world(EXIT_C) + Vector3(0.0, 0.0, -3.0)
	_world.sim.apron_waypoints = PackedVector3Array([plane])
	_world.run_to(BOARDING + 1)
	return {"b": b, "c": c}


func _indoor_mm(from: Vector2i, door_cell: Vector2i) -> int:
	return Passenger.path_mm(_world.grid.find_path(from, door_cell))


func test_the_forecast_prices_the_exit_the_passenger_takes() -> void:
	var doors := _two_exit_world()
	var sim := _world.sim
	var b_total := _indoor_mm(START, EXIT_B) + sim.apron_length_mm(doors["b"])
	var c_total := _indoor_mm(START, EXIT_C) + sim.apron_length_mm(doors["c"])
	print(
		(
			"indoor B %d C %d, apron B %d C %d"
			% [
				_indoor_mm(START, EXIT_B),
				_indoor_mm(START, EXIT_C),
				sim.apron_length_mm(doors["b"]),
				sim.apron_length_mm(doors["c"])
			]
		)
	)
	# B is nearer inside, C nearer the plane: the cheapest total is not the
	# exit the passenger takes.
	assert_int(_indoor_mm(START, EXIT_B)).is_less(_indoor_mm(START, EXIT_C))
	assert_int(JourneyForecast.walk_ticks(b_total - c_total)).is_greater(100)
	var p := _world.passenger(sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.hunger = 0
	p.cafe_cooldown = 1000000
	p.cleared = true
	p.stage = Passenger.Stage.TO_GATE
	p.stage_tick = _world.clock.tick
	p.at = START
	p.clear_path()
	var start := _world.clock.tick
	var leave := VisitForecast.leave_ticks(sim, p, START, 0, Passenger.Stage.TO_GATE)
	assert_int(leave).is_equal(JourneyForecast.walk_ticks(b_total))
	assert_int(JourneyForecast.nearest_exit(sim, START).x).is_equal(doors["b"])
	while not p.is_done() and _world.clock.tick < DOORS:
		_world.step()
	print(
		(
			"forecast %d, boarded %d after %d ticks through exit %d (B %d)"
			% [start + leave, p.outcome_tick, p.outcome_tick - start, p.exit_object, doors["b"]]
		)
	)
	assert_int(p.stage).is_equal(Passenger.Stage.MADE)
	assert_int(p.exit_object).is_equal(doors["b"])
	assert_int(p.outcome_tick).is_less_equal(start + leave + HANDOVER_TICKS)
	assert_int(p.outcome_tick).is_greater_equal(start + leave - HANDOVER_TICKS)


func test_routes_are_searched_once_and_again_after_an_edit() -> void:
	_world = PassengerTestWorld.reference_world()
	_world.run_to(10)
	var sim := _world.sim
	var p := _world.passenger(sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.carry_on = 0
	p.liquids = false
	p.alarm = false
	p.at = Vector2i(16, 16)
	var resume := Passenger.Stage.TO_SECURITY
	var stand := PassengerSim.STAND_UP_TICKS
	var before := sim.routes.searches
	var first := VisitForecast.live_deadline(sim, p, LANDSIDE_CELL, stand, resume)
	var after_first := sim.routes.searches
	var second := VisitForecast.live_deadline(sim, p, LANDSIDE_CELL, stand, resume)
	print("searches %d, then %d, then %d" % [before, after_first, sim.routes.searches])
	assert_int(after_first).is_greater(before)
	assert_int(sim.routes.searches).is_equal(after_first)
	assert_int(second).is_equal(first)
	# A wall north of the cell's row lengthens the way to security: the edit
	# clears the routes, so the next forecast searches again and sees it.
	for x in range(15, ReferenceTerminal.FLOOR_MAX.x + 1):
		var edit := BuildEdit.place_wall(Vector2i(x, 13), BuildGrid.Side.NORTH)
		assert_bool(_world.grid.apply(edit).ok).is_true()
	assert_int(sim.routes.size()).is_equal(0)
	var walled := VisitForecast.live_deadline(sim, p, LANDSIDE_CELL, stand, resume)
	print("deadline open %d walled %d, searches %d" % [first, walled, sim.routes.searches])
	assert_int(sim.routes.searches).is_greater(after_first)
	assert_int(walled).is_less(first)
	# What the cache answers is what a fresh search answers.
	sim.routes.clear()
	assert_int(VisitForecast.live_deadline(sim, p, LANDSIDE_CELL, stand, resume)).is_equal(walled)


func test_a_cached_landside_live_deadline_is_cheap() -> void:
	var grid := BuildGrid.new()
	CafeTestLayout.build(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_world.run_to(10)
	var sim := _world.sim
	var p := _world.passenger(sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.at = Vector2i(16, 13)
	var approach := Vector2i(24, 14)
	var resume := Passenger.Stage.TO_SECURITY
	var stand := PassengerSim.STAND_UP_TICKS
	const CALLS := 200
	var cold_start := Time.get_ticks_usec()
	for i in CALLS:
		sim.routes.clear()
		VisitForecast.live_deadline(sim, p, approach, stand, resume)
	var cold := Time.get_ticks_usec() - cold_start
	var searches := sim.routes.searches
	var warm_start := Time.get_ticks_usec()
	for i in CALLS:
		VisitForecast.live_deadline(sim, p, approach, stand, resume)
	var warm := Time.get_ticks_usec() - warm_start
	@warning_ignore("integer_division")
	print(
		(
			"live_deadline: %d us a call uncached, %d us cached (%d searches a call uncached, 0 cached)"
			% [cold / CALLS, warm / CALLS, searches / CALLS]
		)
	)
	assert_int(sim.routes.searches).is_equal(searches)
	assert_int(searches).is_greater_equal(CALLS)
