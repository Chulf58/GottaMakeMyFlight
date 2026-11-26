class_name TestBeltWallHatch
extends GdUnitTestSuite
## End-to-end rules for auto-cutting rubber-flap suitcase hatches through
## interior plain walls on belt drags (decision
## baggage-belts-auto-cut-rubber-flap-hatch-through-interior-plain-walls).

var _mode: BuildMode
var _finances: Finances


func before() -> void:
	_finances = Finances.new()
	add_child(_finances)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(14, 14)
	_mode.finances = _finances
	add_child(_mode)
	_reset_room_and_divider()


func after() -> void:
	_mode.free()
	_finances.free()


func _reset_room_and_divider() -> void:
	_mode.grid.from_snapshot(BuildGrid.new(Vector2i(14, 14)).to_snapshot())
	_mode.undo_history().clear()
	_finances.wallet.balance = 50000
	var edits: Array[BuildEdit] = []
	for y in range(2, 12):
		for x in range(2, 12):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	for x in range(2, 12):
		edits.append(BuildEdit.place_wall(Vector2i(x, 2), BuildGrid.Side.NORTH))
		edits.append(BuildEdit.place_wall(Vector2i(x, 11), BuildGrid.Side.SOUTH))
	for y in range(2, 12):
		edits.append(BuildEdit.place_wall(Vector2i(2, y), BuildGrid.Side.WEST))
		edits.append(BuildEdit.place_wall(Vector2i(11, y), BuildGrid.Side.EAST))
		var divider := BuildEdit.place_wall(Vector2i(6, y), BuildGrid.Side.EAST)
		divider.paid = PriceTable.price_of_wall(BuildGrid.WallKind.PLAIN)
		edits.append(divider)
	_mode.grid.apply_batch(edits)
	_mode.set_tool(BuildMode.Tool.BELT)


func test_belt_drag_across_interior_plain_wall_cuts_only_the_crossed_edge() -> void:
	_reset_room_and_divider()
	# Lay two parallel runs alongside row y=5 BEFORE dragging across y=6.
	assert_bool(_mode.lay_belt(Vector2i(4, 5), Vector2i(6, 5)).ok).is_true()
	assert_bool(_mode.lay_belt(Vector2i(7, 5), Vector2i(9, 5)).ok).is_true()
	assert_bool(_mode.grid.has_belt_hatch(Vector2i(6, 5), BuildGrid.Side.EAST)).is_false()

	# Drag across the interior PLAIN wall on row y=6 (between (6,6) and (7,6)).
	assert_bool(_mode.lay_belt(Vector2i(4, 6), Vector2i(9, 6)).ok).is_true()
	assert_bool(_mode.grid.has_belt_hatch(Vector2i(6, 6), BuildGrid.Side.EAST)).is_true()
	assert_bool(_mode.grid.has_belt_hatch(Vector2i(7, 6), BuildGrid.Side.WEST)).is_true()
	# Only that exact crossed edge is hatched; parallel y=5 and y=7 stay sealed.
	assert_bool(_mode.grid.has_belt_hatch(Vector2i(6, 5), BuildGrid.Side.EAST)).is_false()
	assert_bool(_mode.grid.has_belt_hatch(Vector2i(6, 7), BuildGrid.Side.EAST)).is_false()
	assert_int(_mode.grid.wall_kind(Vector2i(6, 6), BuildGrid.Side.EAST)).is_equal(
		BuildGrid.WallKind.PLAIN
	)
	var routes := BagRoutes.build(_mode.grid)
	assert_bool(routes.joined(Vector2i(6, 6), Vector2i(1, 0))).is_true()
	assert_bool(routes.joined(Vector2i(6, 5), Vector2i(1, 0))).is_false()


func test_drag_connecting_existing_belts_across_plain_wall_opens_hatch_at_zero_cost() -> void:
	_reset_room_and_divider()
	assert_bool(_mode.lay_belt(Vector2i(6, 4), Vector2i(6, 5)).ok).is_true()
	assert_bool(_mode.lay_belt(Vector2i(7, 4), Vector2i(7, 5)).ok).is_true()
	assert_bool(_mode.grid.has_belt_hatch(Vector2i(6, 5), BuildGrid.Side.EAST)).is_false()

	var before_bal := _mode.wallet().balance
	BuildGhost.draw_belt(_mode, Vector2i(6, 5), Vector2i(7, 5))
	var live_ghost := 0
	for child in _mode._ghost.get_children():
		if not child.is_queued_for_deletion():
			live_ghost += 1
	assert_int(live_ghost).is_greater(0)

	var res := _mode.lay_belt(Vector2i(6, 5), Vector2i(7, 5))
	assert_bool(res.ok).is_true()
	assert_int(_mode.wallet().balance).is_equal(before_bal)
	assert_bool(_mode.grid.has_belt_hatch(Vector2i(6, 5), BuildGrid.Side.EAST)).is_true()
	assert_bool(_mode.grid.has_belt_hatch(Vector2i(6, 4), BuildGrid.Side.EAST)).is_false()
	var routes := BagRoutes.build(_mode.grid)
	assert_bool(routes.joined(Vector2i(6, 5), Vector2i(1, 0))).is_true()
	assert_bool(routes.joined(Vector2i(6, 4), Vector2i(1, 0))).is_false()


func test_glass_door_and_outer_perimeter_walls_block_belts() -> void:
	_reset_room_and_divider()
	_mode.grid.apply(
		BuildEdit.place_wall(Vector2i(6, 7), BuildGrid.Side.EAST, BuildGrid.WallKind.GLASS)
	)
	var glass_res := _mode.lay_belt(Vector2i(5, 7), Vector2i(8, 7))
	assert_bool(glass_res.ok).is_false()
	assert_int(glass_res.reason).is_equal(BuildResult.Reason.BELT_WALL)
	assert_bool(_mode.grid.has_belt_hatch(Vector2i(6, 7), BuildGrid.Side.EAST)).is_false()

	# Interior DOOR wall between plain walls (6, 8) and (6, 10) must refuse BELT_WALL.
	(
		assert_bool(
			(
				_mode
				. grid
				. apply(
					BuildEdit.place_wall(
						Vector2i(6, 9), BuildGrid.Side.EAST, BuildGrid.WallKind.DOOR
					)
				)
				. ok
			)
		)
		. is_true()
	)
	var door_plan := BeltShaper.plan_line(_mode.grid, Vector2i(5, 9), Vector2i(8, 9), 0)
	assert_bool(door_plan.result.ok).is_false()
	assert_int(door_plan.result.reason).is_equal(BuildResult.Reason.BELT_WALL)
	assert_that(door_plan.wall_cell).is_equal(Vector2i(6, 9))
	assert_int(door_plan.wall_side).is_equal(BuildGrid.Side.EAST)
	var door_res := _mode.lay_belt(Vector2i(5, 9), Vector2i(8, 9))
	assert_bool(door_res.ok).is_false()
	assert_int(door_res.reason).is_equal(BuildResult.Reason.BELT_WALL)
	assert_bool(_mode.grid.has_belt_hatch(Vector2i(6, 9), BuildGrid.Side.EAST)).is_false()

	# Perimeter wall at x=11 EAST has no floor on (12, 6): outer wall must block.
	var outer_res := _mode.lay_belt(Vector2i(10, 6), Vector2i(12, 6))
	assert_bool(outer_res.ok).is_false()
	assert_int(outer_res.reason).is_equal(BuildResult.Reason.BELT_WALL)
	assert_bool(_mode.grid.has_belt_hatch(Vector2i(11, 6), BuildGrid.Side.EAST)).is_false()

	# Hatch creation that would produce a fourth link on a merge is refused.
	assert_bool(_mode.lay_belt(Vector2i(6, 3), Vector2i(6, 5)).ok).is_true()
	assert_bool(_mode.lay_belt(Vector2i(4, 4), Vector2i(5, 4)).ok).is_true()
	assert_bool(_mode.lay_belt(Vector2i(7, 4), Vector2i(8, 4)).ok).is_true()
	var four_res := _mode.lay_belt(Vector2i(6, 4), Vector2i(7, 4))
	assert_bool(four_res.ok).is_false()
	assert_int(four_res.reason).is_equal(BuildResult.Reason.BELT_CROSSING)
	assert_bool(_mode.grid.has_belt_hatch(Vector2i(6, 4), BuildGrid.Side.EAST)).is_false()


func test_passengers_staff_enclosure_and_screening_stay_solid_across_hatch() -> void:
	_reset_room_and_divider()
	assert_bool(_mode.lay_belt(Vector2i(5, 6), Vector2i(8, 6)).ok).is_true()
	var a := Vector2i(6, 6)
	var b := Vector2i(7, 6)
	assert_bool(_mode.grid.has_belt_hatch(a, BuildGrid.Side.EAST)).is_true()
	assert_bool(_mode.grid.can_step(a, b)).is_false()
	assert_bool(_mode.grid.can_step(b, a)).is_false()
	assert_array(_mode.grid.find_path(Vector2i(5, 5), Vector2i(8, 5))).is_empty()
	assert_array(_mode.grid.find_staff_path(Vector2i(5, 5), Vector2i(8, 5))).is_empty()
	assert_bool(_mode.grid.is_indoor(a)).is_true()
	assert_bool(_mode.grid.is_indoor(b)).is_true()
	var outside := TerminalEnclosure.outside_cells(
		_mode.grid, _mode.grid._h_walls, _mode.grid._v_walls
	)
	assert_int(outside[_mode.grid._index(a)]).is_equal(0)
	assert_int(outside[_mode.grid._index(b)]).is_equal(0)
	assert_int(outside[_mode.grid._index(Vector2i(0, 0))]).is_equal(1)
	assert_bool(ScreenCoverage.blocks_sight(_mode.grid.wall_kind(a, BuildGrid.Side.EAST))).is_true()
	assert_int(_mode.grid.wall_paid(a, BuildGrid.Side.EAST)).is_equal(
		PriceTable.price_of_wall(BuildGrid.WallKind.PLAIN)
	)


func test_baggage_sim_carries_checked_bag_through_hatched_wall() -> void:
	_reset_room_and_divider()
	# Desk at (3, 7) facing 0 occupies (3..4, 7); belt outlet points North into (4, 6).
	var desk_res := _mode.grid.apply(BuildEdit.place_object(&"checkin_desk", Vector2i(3, 7), 0))
	assert_bool(desk_res.ok).is_true()
	var room_res := _mode.grid.apply(BuildEdit.place_room(Rect2i(8, 5, 3, 3), BeltShaper.BAG_ROOM))
	assert_bool(room_res.ok).is_true()
	assert_bool(_mode.lay_belt(Vector2i(4, 6), Vector2i(8, 6)).ok).is_true()
	assert_bool(_mode.grid.has_belt_hatch(Vector2i(6, 6), BuildGrid.Side.EAST)).is_true()

	var routes := BagRoutes.build(_mode.grid)
	assert_bool(routes.desk_connected(desk_res.object_id)).is_true()
	assert_bool(routes.has_route(Vector2i(6, 6))).is_true()
	assert_that(routes.step_from(Vector2i(6, 6))).is_equal(Vector2i(1, 0))

	var clock := auto_free(SimClock.new()) as SimClock
	clock.seed_rng(1)
	var flights := auto_free(FlightSim.new()) as FlightSim
	flights.bind_clock(clock)
	flights.add_flight("FL1", PassengerTestWorld.starts_with(3900, 4000))
	var sim := auto_free(BaggageSim.new()) as BaggageSim
	sim.bind(clock, flights, _mode.grid)
	var bag: Bag = sim.check_in(1, "FL1", desk_res.object_id)
	assert_object(bag).is_not_null()

	var saw_west := false
	var saw_east := false
	for _tick in range(160):
		clock.tick += 1
		sim.on_tick(clock.tick)
		if bag.cell == Vector2i(6, 6):
			saw_west = true
		elif bag.cell == Vector2i(7, 6):
			saw_east = true
		if bag.state == Bag.State.IN_ROOM:
			break
	assert_bool(saw_west).is_true()
	assert_bool(saw_east).is_true()
	assert_int(bag.state).is_equal(Bag.State.IN_ROOM)


func test_removing_belt_heals_hatch_and_undo_restores_belt_and_hatch() -> void:
	_reset_room_and_divider()
	assert_bool(_mode.lay_belt(Vector2i(5, 6), Vector2i(8, 6)).ok).is_true()
	assert_bool(_mode.grid.has_belt_hatch(Vector2i(6, 6), BuildGrid.Side.EAST)).is_true()

	# Undo initial belt drag cleanly clears the hatch back to PLAIN.
	assert_bool(_mode.undo().ok).is_true()
	assert_bool(_mode.grid.has_belt_hatch(Vector2i(6, 6), BuildGrid.Side.EAST)).is_false()
	assert_array(_mode.grid.object_ids()).is_empty()

	# Re-lay, then delete the west-adjacent belt with REMOVE tool.
	assert_bool(_mode.lay_belt(Vector2i(5, 6), Vector2i(8, 6)).ok).is_true()
	assert_bool(_mode.grid.has_belt_hatch(Vector2i(6, 6), BuildGrid.Side.EAST)).is_true()
	_mode.set_tool(BuildMode.Tool.REMOVE)
	var removed := _mode.apply_at(_mode.grid.cell_to_world(Vector2i(6, 6)))
	assert_bool(removed.ok).is_true()
	assert_bool(_mode.grid.has_belt_hatch(Vector2i(6, 6), BuildGrid.Side.EAST)).is_false()
	assert_int(_mode.grid.wall_kind(Vector2i(6, 6), BuildGrid.Side.EAST)).is_equal(
		BuildGrid.WallKind.PLAIN
	)
	var after_remove := BeltShaper.Scene.new(_mode.grid)
	assert_bool(after_remove.open(Vector2i(6, 6), Vector2i(1, 0))).is_false()

	# Undo removing that belt: restores BOTH the belt AND the hatch cleanly.
	assert_bool(_mode.undo().ok).is_true()
	assert_int(_mode.grid.object_at(Vector2i(6, 6))).is_greater(0)
	assert_bool(_mode.grid.has_belt_hatch(Vector2i(6, 6), BuildGrid.Side.EAST)).is_true()
	var routes := BagRoutes.build(_mode.grid)
	assert_bool(routes.joined(Vector2i(6, 6), Vector2i(1, 0))).is_true()


func test_replacing_or_removing_hatched_wall_heals_and_undoes_cleanly() -> void:
	_reset_room_and_divider()
	assert_bool(_mode.lay_belt(Vector2i(5, 6), Vector2i(8, 6)).ok).is_true()
	assert_bool(_mode.grid.has_belt_hatch(Vector2i(6, 6), BuildGrid.Side.EAST)).is_true()

	_mode.set_tool(BuildMode.Tool.GLASS)
	var edge_pos := BuildView.wall_transform(_mode.grid, Vector2i(6, 6), BuildGrid.Side.EAST).origin
	assert_bool(_mode.apply_at(edge_pos).ok).is_true()
	assert_bool(_mode.grid.has_belt_hatch(Vector2i(6, 6), BuildGrid.Side.EAST)).is_false()
	assert_int(_mode.grid.wall_kind(Vector2i(6, 6), BuildGrid.Side.EAST)).is_equal(
		BuildGrid.WallKind.GLASS
	)
	assert_bool(_mode.undo().ok).is_true()
	assert_int(_mode.grid.wall_kind(Vector2i(6, 6), BuildGrid.Side.EAST)).is_equal(
		BuildGrid.WallKind.PLAIN
	)
	assert_bool(_mode.grid.has_belt_hatch(Vector2i(6, 6), BuildGrid.Side.EAST)).is_true()


func test_build_view_draws_hatch_piece_and_cuts_away_into_jamb_stubs() -> void:
	_reset_room_and_divider()
	assert_bool(_mode.lay_belt(Vector2i(5, 6), Vector2i(8, 6)).ok).is_true()
	var view := auto_free(BuildView.new()) as BuildView
	add_child(view)
	view.cutaway_enabled = true
	view.refresh(_mode.grid)

	# View looking strictly South from North: interior East-West edge is uncut -> full hatch mesh.
	view.update_cutaway(Vector3(0.0, 1.0, -1.0).normalized())
	assert_int(view.piece_counts().get("wall_belt_hatch", 0)).is_equal(1)
	var edge := Vector3i(7, 6, BuildGrid.Side.WEST)
	assert_float(view.sight_height(edge)).is_equal_approx(BuildView.WALL_HEIGHT, 0.001)
	assert_bool(view.sight_blocked(edge, 0.0, 0.5)).is_true()

	# View looking West from East: East edge cuts away cleanly to two narrow jamb stubs.
	view.update_cutaway(Vector3(1.0, 1.0, 0.0).normalized())
	assert_int(view.piece_counts().get("wall_belt_hatch", 0)).is_equal(0)
	assert_float(view.sight_height(edge)).is_equal_approx(InteriorKit.STUB_HEIGHT, 0.001)
	assert_bool(view.sight_blocked(edge, 0.0, InteriorKit.STUB_HEIGHT + 0.01)).is_false()


func test_snapshot_clone_cropped_and_malformed_hatch_validation() -> void:
	_reset_room_and_divider()
	assert_bool(_mode.lay_belt(Vector2i(5, 6), Vector2i(8, 6)).ok).is_true()
	var snap := _mode.grid.to_snapshot()
	assert_int(int(snap["save_version"])).is_equal(BuildGridSave.SAVE_VERSION)
	assert_int(BuildGridSave.SAVE_VERSION).is_equal(3)
	assert_int(SaveGame.SAVE_VERSION).is_greater_equal(44)
	assert_bool(snap.has("v_hatches")).is_true()
	assert_bool(snap.has("h_hatches")).is_true()
	var loaded := BuildGrid.new()
	assert_bool(loaded.from_snapshot(snap)).is_true()
	assert_bool(loaded.has_belt_hatch(Vector2i(6, 6), BuildGrid.Side.EAST)).is_true()
	assert_bool(loaded.has_belt_hatch(Vector2i(6, 5), BuildGrid.Side.EAST)).is_false()
	assert_that(loaded.to_snapshot()).is_equal(snap)

	var cloned := _mode.grid.clone()
	assert_bool(cloned.has_belt_hatch(Vector2i(6, 6), BuildGrid.Side.EAST)).is_true()

	var cropped := _mode.grid.cropped(Rect2i(5, 5, 4, 3))
	assert_bool(cropped.has_belt_hatch(Vector2i(1, 1), BuildGrid.Side.EAST)).is_true()
	assert_bool(cropped.has_belt_hatch(Vector2i(0, 1), BuildGrid.Side.WEST)).is_false()
	assert_bool(cropped.has_belt_hatch(Vector2i(3, 1), BuildGrid.Side.EAST)).is_false()

	# Version 2 grid snapshots (explicit version 2 or pre-hatch v2 lacking keys) are refused.
	var old_v2 := snap.duplicate(true)
	old_v2["save_version"] = 2
	assert_str(BuildGridSnapshot.problem(old_v2)).contains("save_version")
	assert_bool(BuildGrid.new().from_snapshot(old_v2)).is_false()

	var legacy_v2 := snap.duplicate(true)
	legacy_v2.erase("save_version")
	legacy_v2.erase("h_hatches")
	legacy_v2.erase("v_hatches")
	assert_str(BuildGridSnapshot.problem(legacy_v2)).contains("missing key")
	assert_bool(BuildGrid.new().from_snapshot(legacy_v2)).is_false()

	var bad_missing_hatch := snap.duplicate(true)
	bad_missing_hatch.erase("h_hatches")
	assert_str(BuildGridSnapshot.problem(bad_missing_hatch)).contains("missing key 'h_hatches'")

	var bad_value := snap.duplicate(true)
	bad_value["v_hatches"][0] = 2
	assert_str(BuildGridSnapshot.problem(bad_value)).contains("0 to 1")

	var bad_orphan := snap.duplicate(true)
	# (6, 5) EAST has plain wall with floor on both sides, but NO belts.
	bad_orphan["v_hatches"][5 * 15 + 7] = 1
	var reject_orphan := BuildGrid.new()
	assert_bool(reject_orphan.from_snapshot(bad_orphan)).is_false()
