class_name TestBaggageBayDoor
extends GdUnitTestSuite
## Regression tests for Bag Room Rethink Slice B1:
## 2-cell exterior apron-facing Roll-Up Bay Door (baggage_bay_door), placement
## rules, apron cell protection, passenger ways_out exclusion, enclosure/cutaway/
## snapshot round-trip, RoomRules bay door requirement, and 4x3 Starter Bag Room kit.

const NORTH := BuildGrid.Side.NORTH
const EAST := BuildGrid.Side.EAST
const SOUTH := BuildGrid.Side.SOUTH

var _port: SubViewport
var _finances: Finances
var _mode: BuildMode


func before_test() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_finances = Finances.new()
	_finances.wallet.credit(100000, Wallet.Category.FEES)
	_port.add_child(_finances)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(24, 24)
	_mode.initial_tool = BuildMode.Tool.NONE
	_mode.finances = _finances
	_port.add_child(_mode)
	_mode.set_process(false)
	var edits: Array[BuildEdit] = []
	for y in range(4, 14):
		for x in range(4, 14):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	_mode.grid.apply_batch(edits)
	EnclosureKit.close_floor(_mode.grid)


func after_test() -> void:
	_port.free()


func _at(cell: Vector2i) -> Vector3:
	return _mode.grid.cell_to_world(cell)


func test_bay_door_catalog_exclusion_and_tier_2_metadata() -> void:
	var def := BuildCatalog.get_def(BuildCatalog.BAY_DOOR_ID)
	assert_object(def).is_not_null()
	assert_that(def.size).is_equal(Vector2i(2, 1))
	assert_float(def.height).is_equal_approx(2.5, 0.001)
	assert_bool(def.walk_through).is_true()
	assert_bool(BuildCatalog.is_bay_door(BuildCatalog.BAY_DOOR_ID)).is_true()
	assert_bool(BuildCatalog.is_any_door(BuildCatalog.BAY_DOOR_ID)).is_true()
	assert_bool(BuildCatalog.closes_enclosure(BuildCatalog.BAY_DOOR_ID)).is_true()
	assert_bool(BuildCatalog.is_door(BuildCatalog.BAY_DOOR_ID)).is_false()
	assert_int(BuildCatalog.object_price(BuildCatalog.BAY_DOOR_ID)).is_equal(350)
	assert_int(BuildUnlocks.tier_of(BuildMode.Tool.BAY_DOOR)).is_equal(2)


func test_exterior_placement_removes_plain_walls_closes_enclosure_and_excludes_ways_out() -> void:
	# Click slightly north of the north exterior wall line to check wall-line snapping.
	var anchor_cell := Vector2i(6, 4)
	var wall_mid := _at(anchor_cell) + Vector3(0.5, 0.0, -0.52)
	(
		assert_that(BuildMode.object_anchor(_mode.grid, BuildCatalog.BAY_DOOR_ID, wall_mid, 0))
		. is_equal(anchor_cell)
	)

	_mode.set_tool(BuildMode.Tool.BAY_DOOR)
	_mode.facing = 0
	var placed := _mode.apply_at(wall_mid)
	assert_bool(placed.ok).override_failure_message(placed.reason_text()).is_true()
	assert_int(_mode.grid.wall_kind(Vector2i(6, 4), NORTH)).is_equal(BuildGrid.WallKind.NONE)
	assert_int(_mode.grid.wall_kind(Vector2i(7, 4), NORTH)).is_equal(BuildGrid.WallKind.NONE)
	assert_bool(_mode.grid.is_indoor(Vector2i(6, 4))).is_true()
	assert_bool(_mode.grid.is_indoor(Vector2i(7, 4))).is_true()
	assert_array(EnclosureGaps.gap_edges(_mode.grid)).is_empty()
	assert_array(DoorPlacement.ways_out(_mode.grid)).is_empty()
	assert_int(DoorPlacement.enclosure_ways(_mode.grid).size()).is_equal(2)

	assert_bool(_mode.undo().ok).is_true()
	assert_int(_mode.grid.wall_kind(Vector2i(6, 4), NORTH)).is_equal(BuildGrid.WallKind.PLAIN)
	assert_int(_mode.grid.wall_kind(Vector2i(7, 4), NORTH)).is_equal(BuildGrid.WallKind.PLAIN)
	assert_bool(_mode.grid.is_indoor(Vector2i(6, 4))).is_true()


func test_bay_door_refuses_interior_south_landside_glass_courtyard_and_blocked_apron() -> void:
	# Interior wall (floor on approach side).
	var interior := DoorPlacement.check(
		_mode.grid, BuildEdit.place_object(BuildCatalog.BAY_DOOR_ID, Vector2i(6, 6), 0)
	)
	assert_bool(interior.ok).is_false()
	assert_int(interior.reason).is_equal(BuildResult.Reason.DOOR_NOT_ON_EDGE)

	# South curb / landside exterior edge (out == ROAD_STEP).
	var landside := DoorPlacement.check(
		_mode.grid, BuildEdit.place_object(BuildCatalog.BAY_DOOR_ID, Vector2i(6, 13), 2)
	)
	assert_bool(landside.ok).is_false()
	assert_int(landside.reason).is_equal(BuildResult.Reason.BAY_DOOR_NEEDS_APRON)

	# Hollow enclosed courtyard (3x3 unfloored inside 10x10 terminal) has no open-apron path.
	for cy in range(7, 10):
		for cx in range(7, 10):
			_mode.grid.apply(BuildEdit.remove_floor(Vector2i(cx, cy)))
	EnclosureKit.close_floor(_mode.grid)
	var courtyard := DoorPlacement.check(
		_mode.grid, BuildEdit.place_object(BuildCatalog.BAY_DOOR_ID, Vector2i(7, 10), 0)
	)
	assert_bool(courtyard.ok).is_false()
	assert_int(courtyard.reason).is_equal(BuildResult.Reason.BAY_DOOR_NEEDS_APRON)

	# Glass wall along exterior blocks bay door.
	_mode.grid.apply(BuildEdit.remove_wall(Vector2i(8, 4), NORTH))
	_mode.grid.apply(BuildEdit.place_wall(Vector2i(8, 4), NORTH, BuildGrid.WallKind.GLASS))
	var glass := DoorPlacement.check(
		_mode.grid, BuildEdit.place_object(BuildCatalog.BAY_DOOR_ID, Vector2i(8, 4), 0)
	)
	assert_bool(glass.ok).is_false()
	assert_int(glass.reason).is_equal(BuildResult.Reason.DOOR_WALLED)

	# Exterior obstacle / object on either apron approach cell blocks bay door.
	var trophy_id := _mode.grid._next_object_id
	_mode.grid._next_object_id += 1
	_mode.grid._insert_object(trophy_id, &"award_trophy", Vector2i(6, 3), 0, 0)
	var blocked := DoorPlacement.check(
		_mode.grid, BuildEdit.place_object(BuildCatalog.BAY_DOOR_ID, Vector2i(5, 4), 0)
	)
	assert_bool(blocked.ok).is_false()
	assert_int(blocked.reason).is_equal(BuildResult.Reason.BAY_DOOR_APPROACH_BLOCKED)


func test_placed_bay_door_protects_apron_cells_from_floor_walls_and_objects() -> void:
	_mode.set_tool(BuildMode.Tool.BAY_DOOR)
	_mode.facing = 0
	assert_bool(_mode.apply_at(_at(Vector2i(6, 4))).ok).is_true()

	for apron in [Vector2i(6, 3), Vector2i(7, 3)]:
		var paint := DoorPlacement.check(
			_mode.grid, BuildEdit.paint_floor(apron, BuildGrid.FLOOR_TILE, 1)
		)
		assert_bool(paint.ok).is_false()
		assert_int(paint.reason).is_equal(BuildResult.Reason.BAY_DOOR_APPROACH_BLOCKED)

		var obj_edge := DoorPlacement.edge_problem(
			_mode.grid, BuildEdit.place_object(&"award_trophy", apron, 0)
		)
		assert_object(obj_edge).is_not_null()
		assert_int(obj_edge.reason).is_equal(BuildResult.Reason.BAY_DOOR_APPROACH_BLOCKED)

		var back_wall := DoorPlacement.check(_mode.grid, BuildEdit.place_wall(apron, SOUTH))
		assert_bool(back_wall.ok).is_false()
		assert_int(back_wall.reason).is_equal(BuildResult.Reason.DOOR_WALLED)

		var far_wall := DoorPlacement.check(_mode.grid, BuildEdit.place_wall(apron, NORTH))
		assert_bool(far_wall.ok).is_false()
		assert_int(far_wall.reason).is_equal(BuildResult.Reason.DOOR_WALLED)

	var mid_wall := DoorPlacement.check(_mode.grid, BuildEdit.place_wall(Vector2i(6, 3), EAST))
	assert_bool(mid_wall.ok).is_false()
	assert_int(mid_wall.reason).is_equal(BuildResult.Reason.DOOR_WALLED)


func test_wall_cutaway_keeps_bay_door_visible_and_snapshot_round_trips() -> void:
	_mode.set_tool(BuildMode.Tool.BAY_DOOR)
	_mode.facing = 0
	var res := _mode.apply_at(_at(Vector2i(6, 4)))
	assert_bool(res.ok).is_true()

	var node := _mode.object_node(res.object_id)
	assert_object(node).is_not_null()
	assert_bool(node.visible).is_true()

	var snap := _mode.grid.to_snapshot()
	var loaded := BuildGrid.new(_mode.grid.size)
	assert_bool(loaded.from_snapshot(snap)).is_true()
	assert_int(loaded.object_at(Vector2i(6, 4))).is_equal(res.object_id)
	assert_int(loaded.object_at(Vector2i(7, 4))).is_equal(res.object_id)
	assert_bool(loaded.is_indoor(Vector2i(6, 4))).is_true()
	assert_array(DoorPlacement.ways_out(loaded)).is_empty()
	assert_int(DoorPlacement.enclosure_ways(loaded).size()).is_equal(2)


func test_room_rules_and_starter_4x3_bag_room_kit_rules() -> void:
	# Indoor bag room (belt end + south door, no bay door) is missing ONLY bay door.
	var indoor_rect := Rect2i(6, 6, 3, 3)
	var room_id := _mode.grid.apply(BuildEdit.place_room(indoor_rect, &"bag_room")).room_id
	PassengerTestWorld.place(_mode.grid, &"baggage_belt_end", Vector2i(6, 7), 0)
	var missing_bay := RoomRules.status(_mode.grid, room_id)
	assert_bool(missing_bay.ok).is_false()
	assert_bool(missing_bay.has_bay_door).is_false()
	assert_array(missing_bay.notes).is_equal([RoomRules.NO_BAY_DOOR])

	# Too small bag room reports NO_BAY_DOOR right after TOO_SMALL.
	var tiny := _mode.grid.apply(BuildEdit.place_room(Rect2i(10, 8, 1, 2), &"bag_room")).room_id
	var tiny_status := RoomRules.status(_mode.grid, tiny)
	assert_str(tiny_status.notes[1]).is_equal(RoomRules.NO_BAY_DOOR)

	# Bay door + belt end WITHOUT interior opening still requires NO_OPENING.
	var sealed := _mode.grid.apply(BuildEdit.place_room(Rect2i(10, 4, 3, 3), &"bag_room")).room_id
	for x in range(10, 13):
		_mode.grid.apply(BuildEdit.place_wall(Vector2i(x, 6), SOUTH))
	for y in range(4, 7):
		_mode.grid.apply(BuildEdit.place_wall(Vector2i(10, y), BuildGrid.Side.WEST))
		_mode.grid.apply(BuildEdit.place_wall(Vector2i(12, y), EAST))
	PassengerTestWorld.place(_mode.grid, &"baggage_belt_end", Vector2i(10, 5), 0)
	(
		assert_bool(
			(
				_mode
				. grid
				. apply(BuildEdit.place_object(BuildCatalog.BAY_DOOR_ID, Vector2i(11, 4), 0))
				. ok
			)
		)
		. is_true()
	)
	var sealed_status := RoomRules.status(_mode.grid, sealed)
	assert_bool(sealed_status.has_bay_door).is_true()
	assert_bool(sealed_status.ok).is_false()
	assert_array(sealed_status.notes).is_equal([RoomRules.NO_OPENING])

	# Clear room fixtures and place 4x3 Starter Bag Room kit against north exterior wall.
	_mode.grid.apply(BuildEdit.remove_room(room_id))
	_mode.grid.apply(BuildEdit.remove_room(tiny))
	_mode.grid.apply(BuildEdit.remove_object(_mode.grid.object_at(Vector2i(6, 7))))
	_mode.grid.apply(BuildEdit.remove_object(_mode.grid.object_at(Vector2i(11, 4))))
	_mode.grid.apply(BuildEdit.remove_object(_mode.grid.object_at(Vector2i(10, 5))))
	_mode.grid.apply(BuildEdit.remove_room(sealed))
	for x in range(10, 13):
		_mode.grid.apply(BuildEdit.remove_wall(Vector2i(x, 6), SOUTH))
	for y in range(4, 7):
		_mode.grid.apply(BuildEdit.remove_wall(Vector2i(10, y), BuildGrid.Side.WEST))
		_mode.grid.apply(BuildEdit.remove_wall(Vector2i(12, y), EAST))

	var kit := StarterRoomKits.get_kit(&"bag_room")
	assert_that(kit["size"]).is_equal(Vector2i(4, 3))

	# Refuses indoor placement away from apron wall.
	_mode.starter_kit.arm(&"bag_room")
	_mode.starter_kit.turns = 0
	var indoor_kit := _mode.starter_kit.place_at(Vector2i(8, 8))
	assert_bool(indoor_kit.ok).is_false()
	assert_int(indoor_kit.reason).is_equal(BuildResult.Reason.KIT_NEEDS_APRON_WALL)

	# Places on north exterior wall (y = 4..6) with bay door, cart, belt end, south door.
	var stamped := _mode.starter_kit.place_at(Vector2i(7, 5))
	assert_bool(stamped.ok).override_failure_message(stamped.reason_text()).is_true()
	var status := RoomRules.status(_mode.grid, stamped.room_id)
	assert_bool(status.ok).override_failure_message(str(status.notes)).is_true()
	assert_bool(status.has_bay_door).is_true()
	assert_bool(RoomRules.bag_room_dispatch_ready(_mode.grid, stamped.room_id)).is_true()


func test_bay_door_refuses_approach_walls_isolated_cell_and_facing_gap() -> void:
	var candidate := BuildEdit.place_object(BuildCatalog.BAY_DOOR_ID, Vector2i(6, 4), 0)
	# (a1) Pre-existing wall between approach cells (ap0 <-> ap1).
	assert_bool(_mode.grid.apply(BuildEdit.place_wall(Vector2i(6, 3), EAST)).ok).is_true()
	var mid_walled := DoorPlacement.check(_mode.grid, candidate)
	assert_bool(mid_walled.ok).is_false()
	assert_int(mid_walled.reason).is_equal(BuildResult.Reason.DOOR_WALLED)
	assert_bool(_mode.grid.apply(BuildEdit.remove_wall(Vector2i(6, 3), EAST)).ok).is_true()

	# (a2) Pre-existing wall beyond an approach cell (ap0 <-> ap0 + out).
	assert_bool(_mode.grid.apply(BuildEdit.place_wall(Vector2i(6, 3), NORTH)).ok).is_true()
	var out_walled := DoorPlacement.check(_mode.grid, candidate)
	assert_bool(out_walled.ok).is_false()
	assert_int(out_walled.reason).is_equal(BuildResult.Reason.DOOR_WALLED)
	assert_bool(_mode.grid.apply(BuildEdit.remove_wall(Vector2i(6, 3), NORTH)).ok).is_true()

	# (a3) _reaches_open_apron checks bounds for ALL starts and requires BOTH to reach open apron.
	for cy in range(9, 12):
		for cx in range(10, 13):
			_mode.grid.apply(BuildEdit.remove_floor(Vector2i(cx, cy)))
	EnclosureKit.close_floor(_mode.grid)
	var top_y := _mode.grid.flood_area().position.y
	(
		assert_bool(
			DoorPlacement._reaches_open_apron(_mode.grid, [Vector2i(6, top_y), Vector2i(-1, top_y)])
		)
		. is_false()
	)
	(
		assert_bool(
			DoorPlacement._reaches_open_apron(_mode.grid, [Vector2i(6, top_y), Vector2i(11, 10)])
		)
		. is_false()
	)
	(
		assert_bool(
			DoorPlacement._reaches_open_apron(_mode.grid, [Vector2i(6, top_y), Vector2i(7, top_y)])
		)
		. is_true()
	)

	# (b) Two bay doors sharing exterior apron clearance (L-corner or 1-cell facing gap) refuse.
	for cy in range(4, 7):
		for cx in range(6, 14):
			_mode.grid.apply(BuildEdit.remove_wall(Vector2i(cx, 4), NORTH))
			_mode.grid.apply(BuildEdit.remove_floor(Vector2i(cx, cy)))
	EnclosureKit.close_floor(_mode.grid)
	var east_bay := BuildEdit.place_object(BuildCatalog.BAY_DOOR_ID, Vector2i(5, 5), 1)
	assert_bool(DoorPlacement.check(_mode.grid, east_bay).ok).is_true()
	for edit in DoorPlacement.edits_for(_mode.grid, east_bay):
		assert_bool(_mode.grid.apply(edit).ok).is_true()
	var corner_north := DoorPlacement.check(
		_mode.grid, BuildEdit.place_object(BuildCatalog.BAY_DOOR_ID, Vector2i(6, 7), 0)
	)
	assert_bool(corner_north.ok).is_false()
	assert_int(corner_north.reason).is_equal(BuildResult.Reason.BAY_DOOR_APPROACH_BLOCKED)

	# Paint a wing across a 1-cell gap (x = 7..8, y = 4..5, no west wall yet) facing east_bay.
	for cy in range(4, 6):
		for cx in range(7, 9):
			_mode.grid.apply(BuildEdit.paint_floor(Vector2i(cx, cy), BuildGrid.FLOOR_TILE, 1))
	var facing_west := DoorPlacement.check(
		_mode.grid, BuildEdit.place_object(BuildCatalog.BAY_DOOR_ID, Vector2i(7, 5), 3)
	)
	assert_bool(facing_west.ok).is_false()
	assert_int(facing_west.reason).is_equal(BuildResult.Reason.BAY_DOOR_APPROACH_BLOCKED)


func test_repair_plan_excludes_bay_apron_and_passenger_doors_skip_bay_door() -> void:
	_mode.set_tool(BuildMode.Tool.BAY_DOOR)
	_mode.facing = 0
	var bay_res := _mode.apply_at(_at(Vector2i(6, 4)))
	assert_bool(bay_res.ok).is_true()

	var ent_edit := BuildEdit.place_object(&"entrance_door", Vector2i(10, 13), 2)
	var ent_id := 0
	for edit in DoorPlacement.edits_for(_mode.grid, ent_edit):
		var applied := _mode.grid.apply(edit)
		assert_bool(applied.ok).is_true()
		if applied.object_id != 0:
			ent_id = applied.object_id

	# (c) RepairPlan excludes both bay exterior apron cells in _no_floor.
	var plan := RepairPlan.new()
	plan._grid = _mode.grid
	plan._layout.rebuild(_mode.grid)
	plan._refresh_sets(RepairPlan.Leg.EXIT)
	assert_bool(plan._no_floor.has(Vector2i(6, 3))).is_true()
	assert_bool(plan._no_floor.has(Vector2i(7, 3))).is_true()
	assert_bool(plan._no_floor.has(Vector2i(9, 3))).is_false()

	# (d) Passenger sliding-door helpers exclude baggage_bay_door.
	assert_array(PullSide.door_leaves(_mode.grid, bay_res.object_id)).is_empty()
	assert_int(PullSide.door_leaves(_mode.grid, ent_id).size()).is_equal(2)
	assert_array(DoorSteer.doors_near(_mode.grid, _at(Vector2i(6, 4)))).is_empty()
	assert_float(CorridorLane._door_weight(_mode.grid, Vector2(6.5, 4.5))).is_equal_approx(
		1.0, 0.001
	)
