class_name TestStarterKitDoorFacing
extends GdUnitTestSuite
## Regression tests for board item 836a44fd:
## 1) StarterRoomKits.door_edge() returns rotated door cell, side, and outside.
## 2) StarterKitTool ghost draws the door threshold tile and entry arrow across
##    all 4 rotations, plus a red block bar when the doorway is blocked.
## 3) StarterKitTool refuses placement when the kit's door opens onto
##    out-of-bounds, FLOOR_NONE (outer wall / outdoor ground), or a blocking
##    non-walk-through object on the outside cell.
## 4) Rotating so the door faces indoor floor makes placement valid, and
##    snapping onto an existing interior plain wall with indoor floor beyond
##    punches the doorway through cleanly.

const NORTH := BuildGrid.Side.NORTH
const EAST := BuildGrid.Side.EAST
const SOUTH := BuildGrid.Side.SOUTH
const WEST := BuildGrid.Side.WEST

var _finances: Finances
var _mode: BuildMode


func before_test() -> void:
	_finances = Finances.new()
	add_child(_finances)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(20, 20)
	_mode.finances = _finances
	add_child(_mode)
	_mode.set_process(false)
	_paint_floor(Rect2i(2, 2, 12, 12))


func after_test() -> void:
	_mode.free()
	_finances.free()


func _paint_floor(area: Rect2i) -> void:
	var edits: Array[BuildEdit] = []
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	_mode.grid.apply_batch(edits)


func _ghost_door_markers() -> Dictionary:
	var tiles: Array[Node] = []
	var arrows: Array[Node] = []
	var bars: Array[Node] = []
	for child in _mode.starter_kit._ghost.get_children():
		if child.is_queued_for_deletion():
			continue
		if child.get_meta("door_entry", false):
			var role: String = child.get_meta("role", "")
			if role == StationUseCells.PASSENGER:
				tiles.append(child)
			elif role == StationUseCells.ARROW:
				arrows.append(child)
		elif child.get_meta("role", "") == "DoorBlockBar":
			bars.append(child)
	return {"tiles": tiles, "arrows": arrows, "bars": bars}


func test_door_edge_rotates_cleanly_across_all_turns() -> void:
	var expected := {
		&"toilet":
		[
			{"cell": Vector2i(7, 8), "side": SOUTH, "outside": Vector2i(7, 9)},
			{"cell": Vector2i(6, 7), "side": WEST, "outside": Vector2i(5, 7)},
			{"cell": Vector2i(7, 6), "side": NORTH, "outside": Vector2i(7, 5)},
			{"cell": Vector2i(8, 7), "side": EAST, "outside": Vector2i(9, 7)},
		],
		&"kiosk":
		[
			{"cell": Vector2i(7, 8), "side": SOUTH, "outside": Vector2i(7, 9)},
			{"cell": Vector2i(6, 7), "side": WEST, "outside": Vector2i(5, 7)},
			{"cell": Vector2i(8, 6), "side": NORTH, "outside": Vector2i(8, 5)},
			{"cell": Vector2i(8, 8), "side": EAST, "outside": Vector2i(9, 8)},
		],
	}
	for kit_id: StringName in expected:
		for turns in 4:
			var edge: Dictionary = StarterRoomKits.door_edge(kit_id, Vector2i(7, 7), turns)
			var want: Dictionary = expected[kit_id][turns]
			assert_that(edge).is_equal(want)


func test_ghost_shows_door_entry_tile_and_arrow_across_all_rotations() -> void:
	_mode.starter_kit.arm(&"toilet")
	var centre := Vector2i(7, 7)
	for turns in 4:
		_mode.starter_kit.turns = turns
		_mode.starter_kit._key = ""
		_mode.starter_kit._hover(centre)
		var door: Dictionary = StarterRoomKits.door_edge(&"toilet", centre, turns)
		var markers := _ghost_door_markers()
		assert_int((markers["tiles"] as Array).size()).is_equal(1)
		assert_int((markers["arrows"] as Array).size()).is_equal(1)
		assert_int((markers["bars"] as Array).size()).is_equal(0)

		var tile: Node3D = markers["tiles"][0]
		assert_that(tile.get_meta("cell")).is_equal(door["outside"])
		assert_bool(tile.get_meta("blocked")).is_false()

		var arrow: Node3D = markers["arrows"][0]
		var door_world := _mode.grid.cell_to_world(door["cell"])
		var outside_world := _mode.grid.cell_to_world(door["outside"])
		var expected_pos := (door_world + outside_world) * 0.5 + Vector3(0.0, 0.115, 0.0)
		assert_vector(arrow.position).is_equal_approx(expected_pos, Vector3(0.01, 0.01, 0.01))
		# _arrow() tip points along local -Z (Vector3.FORWARD); verify world forward points inward.
		var world_forward := (arrow.global_transform.basis * Vector3.FORWARD).normalized()
		var inward := (door_world - outside_world).normalized()
		assert_vector(world_forward).is_equal_approx(inward, Vector3(0.001, 0.001, 0.001))


func test_refuses_door_facing_outer_wall_or_out_of_bounds_and_draws_block_bar() -> void:
	# Outer wall along the south border of floor (y = 13 SOUTH, y = 14 is FLOOR_NONE).
	for x in range(2, 14):
		(
			assert_bool(
				(
					_mode
					. grid
					. apply(BuildEdit.place_wall(Vector2i(x, 13), SOUTH, BuildGrid.WallKind.PLAIN))
					. ok
				)
			)
			. is_true()
		)

	# Toilet at (7, 12) turns=0 -> door (7, 13) SOUTH -> outside (7, 14) FLOOR_NONE.
	var balance := _finances.wallet.balance
	var before_snap := _mode.grid.to_snapshot()
	_mode.starter_kit.arm(&"toilet")
	_mode.starter_kit.turns = 0
	var centre := Vector2i(7, 12)
	var planned := _mode.starter_kit.plan_at(centre)
	assert_bool((planned["result"] as BuildResult).ok).is_false()
	assert_int((planned["result"] as BuildResult).reason).is_equal(BuildResult.Reason.NO_FLOOR)
	assert_that(_mode.starter_kit.preview_price_at(centre)).is_equal(Vector2i.ZERO)

	var placed := _mode.starter_kit.place_at(centre)
	assert_bool(placed.ok).is_false()
	assert_int(placed.reason).is_equal(BuildResult.Reason.NO_FLOOR)
	assert_that(_mode.grid.to_snapshot()).is_equal(before_snap)
	assert_int(_finances.wallet.balance).is_equal(balance)

	# Hover shows red blocked threshold tile + red DoorBlockBar on the door edge.
	_mode.starter_kit._key = ""
	_mode.starter_kit._hover(centre)
	var markers := _ghost_door_markers()
	assert_int((markers["tiles"] as Array).size()).is_equal(1)
	assert_bool((markers["tiles"][0] as Node).get_meta("blocked")).is_true()
	assert_int((markers["bars"] as Array).size()).is_equal(1)
	var bar: Node3D = markers["bars"][0]
	assert_that(bar.get_meta("cell")).is_equal(Vector2i(7, 13))
	assert_int(bar.get_meta("side")).is_equal(SOUTH)

	# Starter Cafe facing bare outdoor ground (FLOOR_NONE) is also refused.
	_mode.starter_kit.arm(&"cafe")
	var cafe_res := _mode.starter_kit.place_at(Vector2i(7, 12))
	assert_bool(cafe_res.ok).is_false()
	assert_that(_mode.grid.to_snapshot()).is_equal(before_snap)

	# Door opening out of grid bounds (y = 0 NORTH -> outside y = -1) is refused.
	_paint_floor(Rect2i(4, 0, 4, 2))
	var oob_snap := _mode.grid.to_snapshot()
	_mode.starter_kit.arm(&"toilet")
	_mode.starter_kit.turns = 2
	var oob_res := _mode.starter_kit.place_at(Vector2i(5, 1))
	assert_bool(oob_res.ok).is_false()
	assert_int(oob_res.reason).is_equal(BuildResult.Reason.OUT_OF_BOUNDS)
	assert_that(_mode.grid.to_snapshot()).is_equal(oob_snap)


func test_rotating_away_from_outer_wall_onto_indoor_floor_places_cleanly() -> void:
	for x in range(2, 14):
		(
			assert_bool(
				(
					_mode
					. grid
					. apply(BuildEdit.place_wall(Vector2i(x, 13), SOUTH, BuildGrid.WallKind.PLAIN))
					. ok
				)
			)
			. is_true()
		)

	_mode.starter_kit.arm(&"toilet")
	var centre := Vector2i(7, 12)
	var before_snap := _mode.grid.to_snapshot()
	assert_bool(_mode.starter_kit.place_at(centre).ok).is_false()
	assert_that(_mode.grid.to_snapshot()).is_equal(before_snap)

	# Rotate once (turns=1 -> door WEST at (6, 12), outside (5, 12) is indoor floor).
	_mode.starter_kit.rotate_turns()
	assert_int(_mode.starter_kit.turns).is_equal(1)
	_mode.starter_kit._hover(centre)
	var markers := _ghost_door_markers()
	assert_int((markers["bars"] as Array).size()).is_equal(0)
	assert_bool((markers["tiles"][0] as Node).get_meta("blocked")).is_false()

	var placed := _mode.starter_kit.place_at(centre)
	assert_bool(placed.ok).override_failure_message(placed.reason_text()).is_true()
	assert_int(_mode.grid.wall_kind(Vector2i(6, 12), WEST)).is_equal(BuildGrid.WallKind.DOOR)
	assert_bool(RoomRules.status(_mode.grid, placed.room_id).ok).is_true()


func test_refuses_door_blocked_by_non_walkthrough_object_outside() -> void:
	# Place a non-walk-through bin right on the outside threshold cell (7, 9).
	(
		assert_bool(_mode.grid.apply(BuildEdit.place_object(&"trash_can", Vector2i(7, 9), 0)).ok)
		. is_true()
	)
	var before_snap := _mode.grid.to_snapshot()
	var balance := _finances.wallet.balance

	_mode.starter_kit.arm(&"toilet")
	_mode.starter_kit.turns = 0
	var centre := Vector2i(7, 7)
	var res := _mode.starter_kit.place_at(centre)
	assert_bool(res.ok).is_false()
	assert_int(res.reason).is_equal(BuildResult.Reason.DOOR_FRONT_BLOCKED)
	assert_that(_mode.grid.to_snapshot()).is_equal(before_snap)
	assert_int(_finances.wallet.balance).is_equal(balance)

	_mode.starter_kit._key = ""
	_mode.starter_kit._hover(centre)
	var markers := _ghost_door_markers()
	assert_bool((markers["tiles"][0] as Node).get_meta("blocked")).is_true()
	assert_int((markers["bars"] as Array).size()).is_equal(1)


func test_snapping_kit_door_onto_existing_interior_plain_wall_succeeds() -> void:
	# Existing interior plain wall along (6..8, 8) SOUTH, with walkable indoor floor at (6..8, 9).
	for x in range(6, 9):
		(
			assert_bool(
				(
					_mode
					. grid
					. apply(BuildEdit.place_wall(Vector2i(x, 8), SOUTH, BuildGrid.WallKind.PLAIN))
					. ok
				)
			)
			. is_true()
		)

	_mode.starter_kit.arm(&"toilet")
	_mode.starter_kit.turns = 0
	var centre := Vector2i(7, 7)
	var res := _mode.starter_kit.place_at(centre)
	assert_bool(res.ok).override_failure_message(res.reason_text()).is_true()
	assert_int(_mode.grid.wall_kind(Vector2i(7, 8), SOUTH)).is_equal(BuildGrid.WallKind.DOOR)
	assert_bool(RoomRules.status(_mode.grid, res.room_id).ok).is_true()
