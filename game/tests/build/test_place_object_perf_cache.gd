class_name TestPlaceObjectPerfCache
extends GdUnitTestSuite
## Indoor non-door object placements and removals do not rebuild floor/wall
## MultiMeshes, roof masks, enclosure gaps, gate links, or outdoor SiteRoutes
## fields, while structural edits (walls, floors, doors), undo, and snapshot
## loads do update them accurately.

const SITE := preload("res://build/terminal_site.tres")

var _mode: BuildMode
var _roof: RoofView
var _gaps: GapMarkers
var _layout: TerminalLayout
var _gates: GateDesks
var _flights: FlightSim
var _view: BuildView
var _gate_changes := 0
var _plant_a := Vector2i.ZERO
var _plant_b := Vector2i.ZERO
var _seat_cell := Vector2i.ZERO
var _wall_cell := Vector2i.ZERO
var _extra_floor := Vector2i.ZERO


func before() -> void:
	_mode = BuildMode.new()
	_mode.site = SITE
	_mode.starter_shell = true
	add_child(_mode)
	LandKit.own_all(_mode.land_tool.land)

	_roof = RoofView.new()
	_roof.build_mode = _mode
	add_child(_roof)

	_gaps = GapMarkers.new()
	_gaps.build_mode = _mode
	add_child(_gaps)

	_flights = FlightSim.new()
	add_child(_flights)
	_flights.open_airport()

	_gates = GateDesks.new()
	_gates.build_mode = _mode
	_gates.flights = _flights
	_gates.changed.connect(func() -> void: _gate_changes += 1)
	add_child(_gates)

	_layout = TerminalLayout.new()
	_layout.site = SITE
	_mode.grid.graph_changed.connect(
		func(_cells: Array[Vector2i]) -> void: _layout.rebuild(_mode.grid)
	)

	_view = _mode.get_node("BuildView") as BuildView
	_pick_test_cells()

	SiteRoutes.forget()
	EnclosureGaps.forget()
	_layout.rebuild(_mode.grid)


func after() -> void:
	_gates.free()
	_flights.free()
	_gaps.free()
	_roof.free()
	_mode.free()


func _pick_test_cells() -> void:
	var grid := _mode.grid
	for y in range(2, grid.size.y - 2):
		for x in range(2, grid.size.x - 4):
			var c := Vector2i(x, y)
			if (
				grid.is_passenger_cell(c)
				and grid.is_passenger_cell(c + Vector2i(1, 0))
				and grid.is_passenger_cell(c + Vector2i(2, 0))
				and grid.object_at(c) == 0
				and grid.object_at(c + Vector2i(1, 0)) == 0
				and grid.object_at(c + Vector2i(2, 0)) == 0
			):
				if _seat_cell == Vector2i.ZERO:
					_seat_cell = c
				elif c.y >= _seat_cell.y + 2 and _plant_a == Vector2i.ZERO:
					_plant_a = c
					_plant_b = c + Vector2i(1, 0)
			if (
				_wall_cell == Vector2i.ZERO
				and grid.is_indoor(c)
				and grid.has_wall(c, BuildGrid.Side.NORTH)
				and grid.wall_kind(c, BuildGrid.Side.NORTH) == BuildGrid.WallKind.PLAIN
				and (
					grid.wall_kind(c + Vector2i(-1, 0), BuildGrid.Side.NORTH)
					!= BuildGrid.WallKind.DOOR
				)
				and (
					grid.wall_kind(c + Vector2i(1, 0), BuildGrid.Side.NORTH)
					!= BuildGrid.WallKind.DOOR
				)
			):
				_wall_cell = c
			if (
				_extra_floor == Vector2i.ZERO
				and grid.floor_at(c) == BuildGrid.FLOOR_NONE
				and grid.floor_at(c + Vector2i(-1, 0)) != BuildGrid.FLOOR_NONE
				and grid.object_at(c + Vector2i(-1, 0)) == 0
			):
				_extra_floor = c


func _warm_outdoor_caches() -> void:
	var road := SiteRoutes.edge_cells(_mode.grid, SITE, SiteDefinition.ROAD_STEP)
	SiteRoutes.distances(_mode.grid, SITE, road)
	var stand := _layout.live_stand(_mode.grid)
	if not stand.is_empty():
		StandPlacement.to_door(_mode.grid, SITE, stand)
	EnclosureGaps.gap_runs(_mode.grid)


func test_indoor_object_place_and_remove_skips_full_grid_rebuilds() -> void:
	_warm_outdoor_caches()
	var searches_0 := SiteRoutes.searches
	var gap_comp_0 := EnclosureGaps.computations
	var gap_rebuilds_0 := _gaps.rebuilds
	var floor_rebuilds_0 := _view.floor_rebuilds
	var wall_rebuilds_0 := _view.wall_rebuilds
	var roof_scans_0 := _roof.mask_scans
	var roof_rebuilds_0 := _roof.mesh_rebuilds
	var gate_changes_0 := _gate_changes
	var objs_0 := _view.object_node_count()

	var t0 := Time.get_ticks_usec()
	var placed := _mode.apply_edit(BuildEdit.place_object(&"seat_row", _seat_cell, 0))
	var dt_ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("256x150 indoor PLACE_OBJECT dt_ms=%.2f" % dt_ms)
	assert_bool(placed.ok).override_failure_message(placed.reason_text()).is_true()
	assert_float(dt_ms).is_less(50.0)
	assert_int(_view.object_node_count()).is_equal(objs_0 + 1)

	assert_int(SiteRoutes.searches - searches_0).is_equal(0)
	assert_int(EnclosureGaps.computations - gap_comp_0).is_equal(0)
	assert_int(_gaps.rebuilds - gap_rebuilds_0).is_equal(0)
	assert_int(_view.floor_rebuilds - floor_rebuilds_0).is_equal(0)
	assert_int(_view.wall_rebuilds - wall_rebuilds_0).is_equal(0)
	assert_int(_roof.mask_scans - roof_scans_0).is_equal(0)
	assert_int(_roof.mesh_rebuilds - roof_rebuilds_0).is_equal(0)
	assert_int(_gate_changes - gate_changes_0).is_equal(0)

	var removed := _mode.apply_edit(BuildEdit.remove_object(placed.object_id))
	assert_bool(removed.ok).is_true()
	assert_int(_view.object_node_count()).is_equal(objs_0)
	assert_int(SiteRoutes.searches - searches_0).is_equal(0)
	assert_int(EnclosureGaps.computations - gap_comp_0).is_equal(0)
	assert_int(_gaps.rebuilds - gap_rebuilds_0).is_equal(0)
	assert_int(_view.floor_rebuilds - floor_rebuilds_0).is_equal(0)
	assert_int(_view.wall_rebuilds - wall_rebuilds_0).is_equal(0)
	assert_int(_roof.mask_scans - roof_scans_0).is_equal(0)


func test_wall_floor_and_undo_update_views_and_caches_accurately() -> void:
	_warm_outdoor_caches()
	var roofed_before := _roof.roofed_cell_count()
	assert_int(roofed_before).is_greater(0)

	var searches_0 := SiteRoutes.searches
	var gap_comp_0 := EnclosureGaps.computations
	var wall_rebuilds_0 := _view.wall_rebuilds
	var roof_rebuilds_0 := _roof.mesh_rebuilds

	# Opening an outer wall creates a gap, clears the roof, and invalidates SiteRoutes.
	var open_res := _mode.apply_edit(BuildEdit.remove_wall(_wall_cell, BuildGrid.Side.NORTH))
	assert_bool(open_res.ok).override_failure_message(open_res.reason_text()).is_true()
	assert_int(SiteRoutes.searches - searches_0).is_greater(0)
	assert_int(EnclosureGaps.computations - gap_comp_0).is_equal(1)
	assert_int(_view.wall_rebuilds - wall_rebuilds_0).is_greater(0)
	assert_int(_roof.mesh_rebuilds - roof_rebuilds_0).is_equal(1)
	assert_int(_roof.roofed_cell_count()).is_equal(0)
	assert_int(_gaps.strip_count()).is_equal(1)
	assert_int(_gaps.sign_count()).is_equal(1)

	# Undo closes the wall back and restores the roof and gap markers.
	var undo_res := _mode.undo()
	assert_bool(undo_res.ok).is_true()
	assert_int(_roof.roofed_cell_count()).is_equal(roofed_before)
	assert_int(_gaps.strip_count()).is_equal(0)
	assert_int(_gaps.sign_count()).is_equal(0)

	# Painting and removing floor updates BuildView floors & invalidates SiteRoutes.
	var floor_rebuilds_0 := _view.floor_rebuilds
	var searches_1 := SiteRoutes.searches
	var paint_res := _mode.apply_edit(BuildEdit.paint_floor(_extra_floor, BuildGrid.FLOOR_TILE, 1))
	assert_bool(paint_res.ok).override_failure_message(paint_res.reason_text()).is_true()
	assert_int(_view.floor_rebuilds - floor_rebuilds_0).is_equal(1)
	assert_int(SiteRoutes.searches - searches_1).is_greater(0)
	assert_bool(_mode.undo().ok).is_true()


func test_check_followed_by_apply_keeps_staff_reach_accurate() -> void:
	var edit := BuildEdit.place_object(&"plant_pot_1a", _plant_a, 0)
	var chk := _mode.check(edit)
	assert_bool(chk.ok).is_true()
	var app := _mode.grid.apply(edit)
	assert_bool(app.ok).is_true()
	var reach := _mode.grid.staff_reach()
	assert_bool(reach.has(_plant_b)).is_true()
	assert_bool(reach.has(_plant_a)).is_false()
	assert_bool(_mode.grid.apply(BuildEdit.remove_object(app.object_id)).ok).is_true()
	assert_bool(_mode.grid.staff_reach().has(_plant_a)).is_true()


func test_snapshot_reload_rebuilds_all_views_and_caches() -> void:
	var placed := _mode.apply_edit(BuildEdit.place_object(&"plant_pot_1a", _plant_a, 0))
	assert_bool(placed.ok).is_true()
	var snap := _mode.grid.to_snapshot()
	assert_bool(_mode.apply_edit(BuildEdit.remove_object(placed.object_id)).ok).is_true()
	var objs_before := _view.object_node_count()

	var floor_rebuilds_0 := _view.floor_rebuilds
	var wall_rebuilds_0 := _view.wall_rebuilds
	var roof_scans_0 := _roof.mask_scans
	var gap_rebuilds_0 := _gaps.rebuilds

	assert_bool(_mode.grid.from_snapshot(snap)).is_true()
	await get_tree().process_frame
	assert_int(_view.floor_rebuilds - floor_rebuilds_0).is_greater(0)
	assert_int(_view.wall_rebuilds - wall_rebuilds_0).is_greater(0)
	assert_int(_roof.mask_scans - roof_scans_0).is_greater(0)
	assert_int(_gaps.rebuilds - gap_rebuilds_0).is_greater(0)
	assert_int(_view.object_node_count()).is_equal(objs_before + 1)

	# Clean up restored plant so suite stays tidy.
	var obj_id := _mode.grid.object_at(_plant_a)
	if obj_id != 0:
		_mode.grid.apply(BuildEdit.remove_object(obj_id))


func test_door_object_updates_enclosure_roof_and_layout() -> void:
	var roofed_before := _roof.roofed_cell_count()
	assert_int(roofed_before).is_greater(0)
	var gap_comp_0 := EnclosureGaps.computations
	var wall_rebuilds_0 := _view.wall_rebuilds

	# Place a second entrance on the south wall.
	var south_cell := Vector2i.ZERO
	for y in range(2, _mode.grid.size.y - 2):
		for x in range(2, _mode.grid.size.x - 2):
			var c := Vector2i(x, y)
			if (
				_mode.grid.is_indoor(c)
				and _mode.grid.object_at(c) == 0
				and _mode.grid.floor_at(c + Vector2i(0, 1)) == BuildGrid.FLOOR_NONE
				and _mode.grid.wall_kind(c, BuildGrid.Side.SOUTH) == BuildGrid.WallKind.PLAIN
				and (
					_mode.grid.wall_kind(c + Vector2i(-1, 0), BuildGrid.Side.SOUTH)
					!= BuildGrid.WallKind.DOOR
				)
				and (
					_mode.grid.wall_kind(c + Vector2i(1, 0), BuildGrid.Side.SOUTH)
					!= BuildGrid.WallKind.DOOR
				)
			):
				south_cell = c
				break
		if south_cell != Vector2i.ZERO:
			break
	assert_that(south_cell).is_not_equal(Vector2i.ZERO)
	var door_res := _mode.apply_edit(BuildEdit.place_object(&"entrance_door", south_cell, 2))
	assert_bool(door_res.ok).override_failure_message(door_res.reason_text()).is_true()
	assert_int(_view.wall_rebuilds - wall_rebuilds_0).is_greater(0)
	assert_int(EnclosureGaps.computations - gap_comp_0).is_greater(0)
	assert_int(_roof.roofed_cell_count()).is_equal(roofed_before)
	assert_bool(_layout.entrances.has(door_res.object_id)).is_true()
	assert_bool(_mode.undo().ok).is_true()
	assert_int(_roof.roofed_cell_count()).is_equal(roofed_before)
	assert_bool(_layout.entrances.has(door_res.object_id)).is_false()


func test_reach_handoff_distinguishes_wall_kind_and_clears_on_direct_check() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(12, 12))
	var desk := PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(6, 3), 0)
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 11), 2)
	var wall_edits: Array[BuildEdit] = []
	for x in 12:
		if x != 10:
			wall_edits.append(
				BuildEdit.place_wall(Vector2i(x, 5), BuildGrid.Side.SOUTH, BuildGrid.WallKind.PLAIN)
			)
	for res in grid.apply_batch(wall_edits):
		assert_bool(res.ok).override_failure_message(res.reason_text()).is_true()

	# Door on the last gap keeps the desk spot reachable; plain wall at the same
	# edge immediately after must NOT reuse the door's cached reach result.
	var door_edit := BuildEdit.place_wall(
		Vector2i(10, 5), BuildGrid.Side.SOUTH, BuildGrid.WallKind.DOOR
	)
	var door_check := grid.validate(door_edit)
	assert_bool(door_check.ok).override_failure_message(door_check.reason_text()).is_true()

	var plain_edit := BuildEdit.place_wall(
		Vector2i(10, 5), BuildGrid.Side.SOUTH, BuildGrid.WallKind.PLAIN
	)
	var plain_check := grid.validate(plain_edit)
	assert_bool(plain_check.ok).is_false()
	assert_int(plain_check.reason).is_equal(BuildResult.Reason.STAFF_SPOT)
	assert_int(plain_check.blocking_object_id).is_equal(desk)

	var plain_apply := grid.apply(plain_edit)
	assert_bool(plain_apply.ok).is_false()
	assert_int(plain_apply.reason).is_equal(BuildResult.Reason.STAFF_SPOT)

	# Direct staff_reach_problem() calls invalidate the validate() handoff cache so
	# a subsequent apply() never adopts another edit's _last_after reach map.
	var spot_a := Vector2i(2, 2)
	var spot_b := Vector2i(3, 3)
	var edit_a := BuildEdit.place_object(&"plant_pot_1a", spot_a, 0)
	var edit_b := BuildEdit.place_object(&"plant_pot_1a", spot_b, 0)
	assert_bool(grid.validate(edit_a).ok).is_true()
	assert_object(grid.staff_reach_problem([edit_b])).is_null()
	var applied_a := grid.apply(edit_a)
	assert_bool(applied_a.ok).is_true()
	assert_bool(grid.staff_reach().has(spot_a)).is_false()
	assert_bool(grid.staff_reach().has(spot_b)).is_true()
