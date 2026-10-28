class_name TestBuildModeDoorPlacement
extends GdUnitTestSuite
## Placing an entrance or exit the way a player does: paint a room, draw walls
## round it, pick the tool and click an edge cell without pressing R. Every
## edit goes through BuildMode.apply_at() or the ghost's check().

const NORTH := BuildGrid.Side.NORTH
const EAST := BuildGrid.Side.EAST
const SOUTH := BuildGrid.Side.SOUTH
const WEST := BuildGrid.Side.WEST
## The middle-ish cell of each edge of the x 2..7, y 2..7 room, by side.
const EDGE_CELLS := {
	NORTH: Vector2i(4, 2),
	EAST: Vector2i(7, 4),
	SOUTH: Vector2i(4, 7),
	WEST: Vector2i(2, 4),
}

var _mode: BuildMode


## A 10x10 grid with floor on x 2..7, y 2..7 and no floor around it.
func before_test() -> void:
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(10, 10)
	add_child(_mode)
	_mode.set_tool(BuildMode.Tool.FLOOR)
	for y in range(2, 8):
		for x in range(2, 8):
			_mode.apply_at(_mode.grid.cell_to_world(Vector2i(x, y)))


func after_test() -> void:
	_mode.free()


## A ground point just inside `side` of `cell`, so the nearest edge is `side`.
func _near_edge(cell: Vector2i, side: int) -> Vector3:
	var step := BuildGrid.SIDE_STEP[side]
	return _mode.grid.cell_to_world(cell) + Vector3(step.x * 0.45, 0.0, step.y * 0.45)


## Plain walls drawn with the wall tool all round the room.
func _wall_round_the_room() -> void:
	_mode.set_tool(BuildMode.Tool.WALL)
	for i in range(2, 8):
		_mode.apply_at(_near_edge(Vector2i(i, 2), NORTH))
		_mode.apply_at(_near_edge(Vector2i(i, 7), SOUTH))
		_mode.apply_at(_near_edge(Vector2i(2, i), WEST))
		_mode.apply_at(_near_edge(Vector2i(7, i), EAST))


func _back_side(object_id: int) -> int:
	var turn: int = _mode.grid.get_object(object_id)["facing"]
	return BuildGrid.SIDE_STEP.find(BuildObjectDef.rotate_offset(Vector2i(0, -1), turn))


func _assert_one_door_per_edge(tool: BuildMode.Tool) -> void:
	_mode.set_tool(tool)
	for side in EDGE_CELLS:
		var cell: Vector2i = EDGE_CELLS[side]
		var result := _mode.apply_at(_mode.grid.cell_to_world(cell))
		var why := "%s edge %s: reason %d" % [tool, cell, result.reason]
		assert_int(result.reason).override_failure_message(why).is_equal(BuildResult.Reason.NONE)
		if result.ok:
			assert_int(_back_side(result.object_id)).is_equal(side)
	assert_int(_mode.grid.object_ids().size()).is_equal(4)


func test_an_unwalled_room_takes_an_entrance_on_every_edge_without_turning() -> void:
	_assert_one_door_per_edge(BuildMode.Tool.ENTRANCE)


func test_a_walled_room_takes_an_exit_on_every_edge_in_place_of_the_wall() -> void:
	_wall_round_the_room()
	_assert_one_door_per_edge(BuildMode.Tool.EXIT)
	for side in EDGE_CELLS:
		var cell: Vector2i = EDGE_CELLS[side]
		assert_bool(_mode.grid.has_wall(cell, side)).is_false()
		var along := Vector2i(1, 0) if side == NORTH or side == SOUTH else Vector2i(0, 1)
		assert_bool(_mode.grid.has_wall(cell + along, side)).is_true()
		assert_bool(_mode.grid.has_wall(cell - along, side)).is_true()
	var layout := TerminalLayout.new()
	layout.rebuild(_mode.grid)
	assert_int(layout.open_exits(_mode.grid).size()).is_equal(4)


func test_the_ghost_shows_a_walled_edge_cell_as_placeable() -> void:
	_wall_round_the_room()
	_mode.set_tool(BuildMode.Tool.ENTRANCE)
	var point := _mode.grid.cell_to_world(EDGE_CELLS[SOUTH])
	var edit := _mode.edit_at(point)
	assert_bool(_mode.check(edit).ok).is_true()
	_mode._update_ghost(point)
	assert_bool(_mode._ghost.visible).is_true()
	assert_str(_mode.status_text()).is_equal("Facing auto")
	assert_array(_mode.grid.object_ids()).is_empty()


func test_a_corner_cell_puts_the_back_on_the_side_nearest_the_cursor() -> void:
	_mode.set_tool(BuildMode.Tool.ENTRANCE)
	var corner := Vector2i(2, 2)
	assert_int(_mode.edit_at(_near_edge(corner, NORTH)).facing).is_equal(0)
	assert_int(_mode.edit_at(_near_edge(corner, WEST)).facing).is_equal(3)
	var result := _mode.apply_at(_near_edge(corner, WEST))
	assert_bool(result.ok).is_true()
	assert_int(_back_side(result.object_id)).is_equal(WEST)


func test_an_edge_that_works_wins_over_a_nearer_one_that_does_not() -> void:
	_mode.grid.apply(BuildEdit.place_wall(Vector2i(2, 2), NORTH, BuildGrid.WallKind.GLASS))
	_mode.set_tool(BuildMode.Tool.EXIT)
	var result := _mode.apply_at(_near_edge(Vector2i(2, 2), NORTH))
	assert_bool(result.ok).is_true()
	assert_int(_back_side(result.object_id)).is_equal(WEST)


func test_r_overrides_the_automatic_facing_until_the_tool_is_picked_again() -> void:
	_mode.set_tool(BuildMode.Tool.ENTRANCE)
	_mode.rotate_facing()
	assert_int(_mode.facing).is_equal(1)
	assert_str(_mode.status_text()).is_equal("Facing 1")
	var sideways := _mode.apply_at(_mode.grid.cell_to_world(EDGE_CELLS[SOUTH]))
	assert_int(sideways.reason).is_equal(BuildResult.Reason.DOOR_NOT_ON_EDGE)
	_mode.set_tool(BuildMode.Tool.ENTRANCE)
	assert_bool(_mode.apply_at(_mode.grid.cell_to_world(EDGE_CELLS[SOUTH])).ok).is_true()


func test_a_glass_wall_behind_the_door_is_not_replaced() -> void:
	var cell: Vector2i = EDGE_CELLS[NORTH]
	_mode.grid.apply(BuildEdit.place_wall(cell, NORTH, BuildGrid.WallKind.GLASS))
	_mode.set_tool(BuildMode.Tool.EXIT)
	var result := _mode.apply_at(_mode.grid.cell_to_world(cell))
	assert_int(result.reason).is_equal(BuildResult.Reason.DOOR_WALLED)
	assert_int(_mode.grid.wall_kind(cell, NORTH)).is_equal(BuildGrid.WallKind.GLASS)
	assert_array(_mode.grid.object_ids()).is_empty()
	assert_str(_mode.status_text()).is_equal("Take down the glass or door wall behind the exit")


func test_a_plain_wall_that_holds_a_door_wall_is_not_replaced() -> void:
	_wall_round_the_room()
	_mode.set_tool(BuildMode.Tool.DOOR)
	assert_bool(_mode.apply_at(_near_edge(Vector2i(5, 2), NORTH)).ok).is_true()
	_mode.set_tool(BuildMode.Tool.EXIT)
	var result := _mode.apply_at(_mode.grid.cell_to_world(Vector2i(4, 2)))
	assert_int(result.reason).is_equal(BuildResult.Reason.WALL_HOLDS_DOOR)
	assert_int(_mode.grid.wall_kind(Vector2i(4, 2), NORTH)).is_equal(BuildGrid.WallKind.PLAIN)
	assert_int(_mode.grid.wall_kind(Vector2i(5, 2), NORTH)).is_equal(BuildGrid.WallKind.DOOR)
	assert_array(_mode.grid.object_ids()).is_empty()


func test_the_status_line_says_what_to_do() -> void:
	_mode.set_tool(BuildMode.Tool.ENTRANCE)
	_mode.apply_at(_mode.grid.cell_to_world(Vector2i(4, 4)))
	assert_str(_mode.status_text()).is_equal("Put the entrance on the outside edge of the floor")
	_mode.set_tool(BuildMode.Tool.SEATS)
	assert_bool(_mode.apply_at(_mode.grid.cell_to_world(Vector2i(3, 3))).ok).is_true()
	_mode.set_tool(BuildMode.Tool.EXIT)
	var blocked := _mode.apply_at(_mode.grid.cell_to_world(EDGE_CELLS[NORTH]))
	assert_int(blocked.reason).is_equal(BuildResult.Reason.INTERACTION_BLOCKED)
	assert_str(_mode.status_text()).is_equal("Clear the floor in front of the exit")
