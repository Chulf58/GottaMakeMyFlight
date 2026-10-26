class_name TestBuildModeDoorTools
extends GdUnitTestSuite
## BuildMode's glass, door, entrance and exit tools, the view drawing the
## grid's wall kinds, and the door objects' kit piece.

const NORTH := BuildGrid.Side.NORTH
const SOUTH := BuildGrid.Side.SOUTH

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


func _view() -> BuildView:
	return _mode.get_node("BuildView") as BuildView


## A ground point just inside `side` of `cell`, so the nearest edge is `side`.
func _near_edge(cell: Vector2i, side: int) -> Vector3:
	var step := BuildGrid.SIDE_STEP[side]
	return _mode.grid.cell_to_world(cell) + Vector3(step.x * 0.45, 0.0, step.y * 0.45)


func _wall_line(y: int) -> void:
	_mode.set_tool(BuildMode.Tool.WALL)
	for x in range(2, 8):
		_mode.apply_at(_near_edge(Vector2i(x, y), NORTH))


func _place(tool: BuildMode.Tool, cell: Vector2i, turns: int) -> BuildResult:
	_mode.set_tool(tool)
	while _mode.facing != turns:
		_mode.rotate_facing()
	return _mode.apply_at(_mode.grid.cell_to_world(cell))


func test_glass_tool_places_glass_on_the_nearest_edge() -> void:
	_mode.set_tool(BuildMode.Tool.GLASS)
	assert_bool(_mode.apply_at(_near_edge(Vector2i(3, 3), NORTH)).ok).is_true()
	assert_int(_mode.grid.wall_kind(Vector2i(3, 3), NORTH)).is_equal(BuildGrid.WallKind.GLASS)


func test_door_tool_turns_a_wall_between_plain_walls_into_a_door() -> void:
	_wall_line(5)
	_mode.set_tool(BuildMode.Tool.DOOR)
	assert_bool(_mode.apply_at(_near_edge(Vector2i(4, 5), NORTH)).ok).is_true()
	assert_int(_mode.grid.wall_kind(Vector2i(4, 5), NORTH)).is_equal(BuildGrid.WallKind.DOOR)
	var lone := _mode.apply_at(_near_edge(Vector2i(4, 3), NORTH))
	assert_int(lone.reason).is_equal(BuildResult.Reason.DOOR_NEEDS_WALLS)
	assert_int(_mode.grid.wall_kind(Vector2i(4, 3), NORTH)).is_equal(BuildGrid.WallKind.NONE)


func test_entrance_tool_needs_the_terminal_edge_with_the_front_facing_in() -> void:
	var inside := _place(BuildMode.Tool.ENTRANCE, Vector2i(4, 4), 2)
	assert_int(inside.reason).is_equal(BuildResult.Reason.DOOR_NOT_ON_EDGE)
	# Turned along the edge, the back faces floor.
	var sideways := _place(BuildMode.Tool.ENTRANCE, Vector2i(4, 7), 1)
	assert_int(sideways.reason).is_equal(BuildResult.Reason.DOOR_NOT_ON_EDGE)
	# Turned out, the front cell has no floor, which validate() refuses first.
	var facing_out := _place(BuildMode.Tool.ENTRANCE, Vector2i(4, 7), 0)
	assert_int(facing_out.reason).is_equal(BuildResult.Reason.INTERACTION_BLOCKED)
	assert_array(_mode.grid.object_ids()).is_empty()
	var placed := _place(BuildMode.Tool.ENTRANCE, Vector2i(4, 7), 2)
	assert_bool(placed.ok).is_true()
	assert_str(str(_mode.grid.get_object(placed.object_id)["def"])).is_equal("entrance_door")


## A plain wall there is taken down by the placement instead (see
## test_build_mode_door_placement.gd), so this uses glass.
func test_exit_tool_refuses_a_glass_wall_on_the_way_out() -> void:
	_mode.grid.apply(BuildEdit.place_wall(Vector2i(6, 2), NORTH, BuildGrid.WallKind.GLASS))
	var walled := _place(BuildMode.Tool.EXIT, Vector2i(6, 2), 0)
	assert_int(walled.reason).is_equal(BuildResult.Reason.DOOR_WALLED)
	assert_array(_mode.grid.object_ids()).is_empty()
	_mode.grid.apply(BuildEdit.remove_wall(Vector2i(6, 2), NORTH))
	var placed := _place(BuildMode.Tool.EXIT, Vector2i(6, 2), 0)
	assert_bool(placed.ok).is_true()
	assert_str(str(_mode.grid.get_object(placed.object_id)["def"])).is_equal("exit_door")


func test_the_ghost_check_and_the_click_agree() -> void:
	_mode.set_tool(BuildMode.Tool.ENTRANCE)
	var inside := _mode.edit_at(_mode.grid.cell_to_world(Vector2i(4, 4)))
	assert_bool(_mode.grid.validate(inside).ok).is_true()
	assert_int(_mode.check(inside).reason).is_equal(BuildResult.Reason.DOOR_NOT_ON_EDGE)


func test_tool_built_doors_give_the_terminal_an_entrance_and_an_open_exit() -> void:
	_place(BuildMode.Tool.ENTRANCE, Vector2i(4, 7), 2)
	_place(BuildMode.Tool.EXIT, Vector2i(6, 2), 0)
	var layout := TerminalLayout.new()
	layout.rebuild(_mode.grid)
	assert_int(layout.entrances.size()).is_equal(1)
	assert_int(layout.open_exits(_mode.grid).size()).is_equal(1)


func test_view_draws_the_wall_kinds_the_grid_stores() -> void:
	_wall_line(5)
	_mode.set_tool(BuildMode.Tool.DOOR)
	_mode.apply_at(_near_edge(Vector2i(4, 5), NORTH))
	_mode.set_tool(BuildMode.Tool.GLASS)
	_mode.apply_at(_near_edge(Vector2i(2, 5), NORTH))
	_view().cutaway_enabled = false
	var counts := _view().piece_counts()
	assert_int(counts.get("wall_door", 0)).is_equal(1)
	assert_int(counts.get("wall_glass", 0)).is_equal(1)
	assert_int(counts.get("wall", 0)).is_equal(4)


func test_entrance_and_exit_draw_a_door_on_their_back_edge() -> void:
	for id in [&"entrance_door", &"exit_door"]:
		assert_str(InteriorKit.object_piece(id)).is_equal("wall_door")
		var node := auto_free(BuildView.make_object_node(BuildCatalog.get_def(id), null)) as Node3D
		assert_int(node.get_child_count()).is_equal(1)
		var piece := node.get_child(0) as Node3D
		assert_that(piece.position).is_equal(Vector3(0.0, 0.0, -0.5))
		var meshes := node.find_children("*", "MeshInstance3D", true, false)
		assert_int(meshes.size()).is_equal(InteriorKit.meshes("wall_door").size())
		for mesh in meshes:
			assert_bool((mesh as MeshInstance3D).mesh is BoxMesh).is_false()


func test_a_standing_door_keeps_its_way_out_open() -> void:
	assert_bool(_place(BuildMode.Tool.EXIT, Vector2i(6, 2), 0).ok).is_true()
	assert_bool(_place(BuildMode.Tool.ENTRANCE, Vector2i(4, 7), 2).ok).is_true()
	# Plain walls beside the exit's back edge, so a door there passes the door rule.
	for x in [5, 7]:
		_mode.grid.apply(BuildEdit.place_wall(Vector2i(x, 2), NORTH))
	for kind in [BuildGrid.WallKind.PLAIN, BuildGrid.WallKind.GLASS, BuildGrid.WallKind.DOOR]:
		for edge in [[Vector2i(6, 2), NORTH], [Vector2i(6, 1), SOUTH]]:
			var walled := _mode.check(BuildEdit.place_wall(edge[0], edge[1], kind))
			assert_int(walled.reason).is_equal(BuildResult.Reason.DOOR_WALLED)
	var entrance_wall := _mode.check(BuildEdit.place_wall(Vector2i(4, 7), SOUTH))
	assert_int(entrance_wall.reason).is_equal(BuildResult.Reason.DOOR_WALLED)
	_mode.set_tool(BuildMode.Tool.WALL)
	var by_tool := _mode.apply_at(_near_edge(Vector2i(6, 2), NORTH))
	assert_int(by_tool.reason).is_equal(BuildResult.Reason.DOOR_WALLED)
	assert_bool(_mode.grid.has_wall(Vector2i(6, 2), NORTH)).is_false()
	_mode.set_tool(BuildMode.Tool.GLASS)
	var glass := _mode.apply_at(_near_edge(Vector2i(4, 8), NORTH))
	assert_int(glass.reason).is_equal(BuildResult.Reason.DOOR_WALLED)
	_mode.set_tool(BuildMode.Tool.FLOOR)
	for beyond in [Vector2i(6, 1), Vector2i(4, 8)]:
		var floor := _mode.apply_at(_mode.grid.cell_to_world(beyond))
		assert_int(floor.reason).is_equal(BuildResult.Reason.DOOR_NOT_ON_EDGE)
		assert_int(_mode.grid.floor_at(beyond)).is_equal(BuildGrid.FLOOR_NONE)
	# Other edges and cells near the doors stay free to build on.
	assert_bool(_mode.check(BuildEdit.place_wall(Vector2i(6, 2), BuildGrid.Side.EAST)).ok).is_true()
	assert_bool(_mode.check(BuildEdit.paint_floor(Vector2i(5, 1), 1, 1)).ok).is_true()
