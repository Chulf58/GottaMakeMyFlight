class_name TestRepairEnclosure
extends GdUnitTestSuite
## RepairEnclosure, the walls a repair adds so its floor is closed in: every
## open floor edge of the floor joined to the repair's cells gets a plain wall,
## except a door's way out, none inside a shell facade, and a wall the plan
## places and later takes down is left out with its removal.


## A 3x2 patch of floor at (4, 4) on a 12x12 grid, an entrance on its south
## edge at (5, 5) facing out, and a separate floor cell at (9, 9).
func _patch() -> BuildGrid:
	var grid := BuildGrid.new(Vector2i(12, 12))
	for cell in [Vector2i(4, 4), Vector2i(5, 4), Vector2i(6, 4), Vector2i(4, 5), Vector2i(5, 5)]:
		grid.apply(BuildEdit.paint_floor(cell, BuildGrid.FLOOR_TILE, 1))
	grid.apply(BuildEdit.paint_floor(Vector2i(6, 5), BuildGrid.FLOOR_TILE, 1))
	grid.apply(BuildEdit.paint_floor(Vector2i(9, 9), BuildGrid.FLOOR_TILE, 1))
	(
		assert_bool(grid.apply(BuildEdit.place_object(&"entrance_door", Vector2i(5, 5), 2)).ok)
		. is_true()
	)
	return grid


func test_the_joined_floor_is_walled_in_except_the_door_way_out() -> void:
	var grid := _patch()
	var walls := RepairEnclosure.walls_for(grid, [Vector2i(4, 4)])
	print(
		"walls: %s" % [walls.map(func(e: BuildEdit) -> String: return "%s:%d" % [e.cell, e.side])]
	)
	# The 3x2 outline has 10 edges, less the door's south edge.
	assert_int(walls.size()).is_equal(9)
	for edit in walls:
		assert_int(edit.kind).is_equal(BuildEdit.Kind.PLACE_WALL)
		assert_bool(edit.cell == Vector2i(5, 5) and edit.side == BuildGrid.Side.SOUTH).is_false()
		assert_bool(edit.cell == Vector2i(9, 9)).is_false()
	for result in grid.apply_batch(walls):
		assert_bool(result.ok).is_true()
	for cell in [Vector2i(4, 4), Vector2i(6, 5), Vector2i(5, 5)]:
		assert_bool(grid.is_indoor(cell)).is_true()
	assert_bool(grid.is_indoor(Vector2i(9, 9))).is_false()
	assert_array(RepairEnclosure.walls_for(grid, [Vector2i(5, 5)])).is_empty()


## Floor taken up inside the walls leaves a hole the outside cannot reach.
func test_a_hole_already_closed_in_gets_no_wall() -> void:
	var grid := BuildGrid.new(Vector2i(12, 12))
	for y in range(4, 7):
		for x in range(4, 7):
			grid.apply(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	assert_int(EnclosureKit.close_floor(grid)).is_equal(12)
	assert_bool(grid.apply(BuildEdit.remove_floor(Vector2i(5, 5))).ok).is_true()
	assert_array(RepairEnclosure.walls_for(grid, [Vector2i(4, 4)])).is_empty()
	# Its control: an open edge of the ring is walled.
	assert_bool(grid.apply(BuildEdit.remove_wall(Vector2i(4, 4), BuildGrid.Side.WEST)).ok).is_true()
	var walls := RepairEnclosure.walls_for(grid, [Vector2i(4, 4)])
	assert_int(walls.size()).is_equal(1)
	assert_vector(Vector2(walls[0].cell)).is_equal(Vector2(4, 4))
	assert_int(walls[0].side).is_equal(BuildGrid.Side.WEST)


func test_inside_a_shell_facade_no_wall_is_wanted() -> void:
	var grid := _patch()
	grid.set_shell_border(true)
	assert_array(RepairEnclosure.walls_for(grid, [Vector2i(4, 4)])).is_empty()


func test_a_wall_placed_and_taken_down_again_is_left_out_with_its_removal() -> void:
	var kept_wall := BuildEdit.place_wall(Vector2i(1, 1), BuildGrid.Side.EAST)
	var floor_edit := BuildEdit.paint_floor(Vector2i(3, 4), BuildGrid.FLOOR_TILE, 1)
	var player_wall_down := BuildEdit.remove_wall(Vector2i(7, 7), BuildGrid.Side.WEST)
	var plan: Array[BuildEdit] = [
		BuildEdit.place_wall(Vector2i(3, 3), BuildGrid.Side.SOUTH),
		kept_wall,
		floor_edit,
		player_wall_down,
		# The same edge as the first wall, named from the cell below it.
		BuildEdit.remove_wall(Vector2i(3, 4), BuildGrid.Side.NORTH),
	]
	var out := RepairEnclosure.without_undone_walls(plan)
	assert_array(out).contains_exactly([kept_wall, floor_edit, player_wall_down])
