class_name TestAirsideExitDoor
extends GdUnitTestSuite
## Arrivals Slice A1: airside_exit_door placement, ARRIVING/staff-only passage,
## DEPARTING two-way blocking, and priority exit routing
## (airside_exit_door -> divider door -> reverse security scanner).

var _worlds: Array[PassengerTestWorld] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for world in _worlds:
		world.free_all()
	_worlds.clear()


func _placed_exit(grid: BuildGrid, cell: Vector2i, facing: int) -> bool:
	var place := BuildEdit.place_object(BuildCatalog.AIRSIDE_EXIT_ID, cell, facing)
	for edit: BuildEdit in DoorPlacement.edits_for(grid, place):
		var res: BuildResult = grid.apply(edit)
		if not res.ok:
			return false
	return true


func test_airside_exit_requires_floor_on_both_sides_and_allows_staff_not_departing() -> void:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	var air := Vector2i(13, 8)
	var land := Vector2i(13, 9)
	assert_bool(_placed_exit(grid, air, 2)).is_true()

	# Outside terminal floor (y = 2 north edge) must refuse AIRSIDE_EXIT_NEEDS_FLOOR.
	var edge_res := DoorPlacement.edge_problem(
		grid, BuildEdit.place_object(BuildCatalog.AIRSIDE_EXIT_ID, Vector2i(13, 2), 0)
	)
	assert_object(edge_res).is_not_null()
	assert_int(edge_res.reason).is_equal(BuildResult.Reason.AIRSIDE_EXIT_NEEDS_FLOOR)

	# Generic / departing pathing is blocked BOTH ways across airside_exit_door.
	assert_bool(grid.crosses_airside_exit(air, land)).is_true()
	assert_bool(grid.crosses_airside_exit(land, air)).is_true()
	assert_bool(grid.can_route(air, land)).is_false()
	assert_bool(grid.can_route(land, air)).is_false()
	# Staff can cross in both directions.
	assert_bool(grid.can_staff_route(air, land)).is_true()
	assert_bool(grid.can_staff_route(land, air)).is_true()

	# Even a cleared departing passenger cannot walk back out through airside_exit_door.
	var layout := TerminalLayout.new()
	layout.rebuild(grid)
	assert_int(layout.airside_exits.size()).is_equal(1)
	assert_array(grid.find_path(air, ReferenceTerminal.ENTRANCE_CELL)).is_empty()
	assert_array(grid.find_path(ReferenceTerminal.ENTRANCE_CELL, air)).is_empty()


func test_arriving_exit_priority_prefers_airside_exit_then_divider_then_reverse_scanner() -> void:
	# (a) airside_exit_door present -> uses it instead of reverse scanner.
	var grid_a := BuildGrid.new()
	ReferenceTerminal.build(grid_a)
	assert_bool(_placed_exit(grid_a, Vector2i(13, 8), 2)).is_true()
	var w_a := PassengerTestWorld.make(grid_a, FlightSim.schedule_starts(0))
	_worlds.append(w_a)
	var p_a := PassengerArrivals.spawn(w_a.sim, PassengerTestWorld.FLIGHT, 0)
	assert_object(p_a).is_not_null()
	p_a.apron.clear()
	p_a.apron_mm = 0
	p_a.clear_path()
	p_a.at = Vector2i(13, 7)
	w_a.sim._set_stage(p_a, Passenger.Stage.TO_AIRSIDE_EXIT)
	PassengerArrivals.advance(w_a.sim, p_a)
	assert_bool(p_a.path.has(Vector2i(13, 9))).is_true()

	# (b) No airside_exit_door, divider WallKind.DOOR present -> uses divider door.
	var grid_b := BuildGrid.new()
	ReferenceTerminal.build(grid_b)
	(
		assert_bool(grid_b.apply(BuildEdit.remove_wall(Vector2i(12, 9), BuildGrid.Side.NORTH)).ok)
		. is_true()
	)
	(
		assert_bool(
			(
				grid_b
				. apply(
					BuildEdit.place_wall(
						Vector2i(12, 9), BuildGrid.Side.NORTH, BuildGrid.WallKind.DOOR
					)
				)
				. ok
			)
		)
		. is_true()
	)
	var w_b := PassengerTestWorld.make(grid_b, FlightSim.schedule_starts(0))
	_worlds.append(w_b)
	var p_b := PassengerArrivals.spawn(w_b.sim, PassengerTestWorld.FLIGHT, 0)
	p_b.apron.clear()
	p_b.apron_mm = 0
	p_b.clear_path()
	p_b.at = Vector2i(12, 7)
	w_b.sim._set_stage(p_b, Passenger.Stage.TO_AIRSIDE_EXIT)
	PassengerArrivals.advance(w_b.sim, p_b)
	assert_bool(p_b.path.has(Vector2i(12, 9))).is_true()

	# (c) Day-1 fallback: neither airside_exit_door nor divider door -> reverse scanner passage.
	var grid_c := BuildGrid.new()
	ReferenceTerminal.build(grid_c)
	var w_c := PassengerTestWorld.make(grid_c, FlightSim.schedule_starts(0))
	_worlds.append(w_c)
	var scanner_xs := ReferenceTerminal.SCANNER_XS
	var p_c := PassengerArrivals.spawn(w_c.sim, PassengerTestWorld.FLIGHT, 0)
	p_c.apron.clear()
	p_c.apron_mm = 0
	p_c.at = Vector2i(scanner_xs[0], 6)
	w_c.sim._set_stage(p_c, Passenger.Stage.TO_AIRSIDE_EXIT)
	PassengerArrivals.advance(w_c.sim, p_c)
	var expected_land := Vector2i(scanner_xs[0], ReferenceTerminal.DIVIDER_Y + 1)
	assert_bool(p_c.path.has(expected_land) or p_c.path.has(Vector2i(scanner_xs[0], 9))).is_true()
