class_name TestTerminalEnclosure
extends GdUnitTestSuite
## Indoor floor is the floor walls close in (TerminalEnclosure, decision
## player-built-terminal-technical-design-site-plot-indoor-mask-passenger-
## eligibility, point 2). A 4x3 box of floor at x 2-5, y 2-4 on a 12x10 grid,
## walled on all four sides, is the subject of most cases.

const BOX := Rect2i(2, 2, 4, 3)

var _grid: BuildGrid
## Every cell graph_changed named since the case cleared it.
var _emitted: Array[Vector2i] = []


func before_test() -> void:
	_emitted.clear()
	_grid = BuildGrid.new(Vector2i(12, 10))
	var edits: Array[BuildEdit] = []
	for y in range(BOX.position.y, BOX.end.y):
		for x in range(BOX.position.x, BOX.end.x):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	for result in _grid.apply_batch(edits):
		assert_bool(result.ok).is_true()
	assert_int(EnclosureKit.close_floor(_grid)).is_equal(14)


func _on_graph_changed(cells: Array[Vector2i]) -> void:
	_emitted.append_array(cells)


func _indoor_count() -> int:
	var count := 0
	for y in _grid.size.y:
		for x in _grid.size.x:
			if _grid.is_indoor(Vector2i(x, y)):
				count += 1
	return count


func _apply(edit: BuildEdit) -> BuildResult:
	var result := _grid.apply(edit)
	assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()
	return result


func test_a_closed_box_is_indoor_and_bare_ground_is_not() -> void:
	assert_int(_indoor_count()).is_equal(12)
	assert_bool(EnclosureKit.all_indoor(_grid)).is_true()
	# No floor, so never indoor.
	assert_bool(_grid.is_indoor(Vector2i(8, 8))).is_false()
	assert_bool(_grid.is_indoor(Vector2i(-1, 0))).is_false()


func test_one_missing_wall_lets_the_outside_into_the_whole_box() -> void:
	assert_int(_indoor_count()).is_equal(12)
	_apply(BuildEdit.remove_wall(Vector2i(5, 3), BuildGrid.Side.EAST))
	assert_int(_indoor_count()).is_equal(0)
	_apply(BuildEdit.place_wall(Vector2i(5, 3), BuildGrid.Side.EAST))
	assert_int(_indoor_count()).is_equal(12)


## An entrance stands in a gap of the wall line with no wall on its back edge
## (DoorPlacement): that back edge is open in the wall arrays, but the door
## object fills the gap, so the box stays closed. Taking the door object away
## lets the outside in through the gap.
func test_a_door_object_fills_the_gap_its_open_back_edge_leaves() -> void:
	_apply(BuildEdit.remove_wall(Vector2i(3, 4), BuildGrid.Side.SOUTH))
	assert_int(_indoor_count()).is_equal(0)
	var door := _apply(BuildEdit.place_object(&"entrance_door", Vector2i(3, 4), 2)).object_id
	assert_int(DoorPlacement.ways_out(_grid).size()).is_equal(1)
	assert_bool(_grid.has_wall(Vector2i(3, 4), BuildGrid.Side.SOUTH)).is_false()
	assert_int(_indoor_count()).is_equal(12)
	_apply(BuildEdit.remove_object(door))
	assert_int(_indoor_count()).is_equal(0)


func test_glass_and_door_walls_close_an_edge() -> void:
	_apply(BuildEdit.place_wall(Vector2i(2, 3), BuildGrid.Side.WEST, BuildGrid.WallKind.GLASS))
	assert_int(_grid.wall_kind(Vector2i(2, 3), BuildGrid.Side.WEST)).is_equal(
		BuildGrid.WallKind.GLASS
	)
	_apply(BuildEdit.place_wall(Vector2i(4, 2), BuildGrid.Side.NORTH, BuildGrid.WallKind.DOOR))
	assert_int(_grid.wall_kind(Vector2i(4, 2), BuildGrid.Side.NORTH)).is_equal(
		BuildGrid.WallKind.DOOR
	)
	assert_int(_indoor_count()).is_equal(12)
	# Control: the same edge with no wall at all opens the box.
	_apply(BuildEdit.remove_wall(Vector2i(2, 3), BuildGrid.Side.WEST))
	assert_int(_indoor_count()).is_equal(0)


## A wall across the box, closed or with a door wall in it, leaves both halves
## indoor: only the outside makes floor outdoor.
func test_an_interior_divider_keeps_both_sides_indoor() -> void:
	for x in range(BOX.position.x, BOX.end.x):
		_apply(BuildEdit.place_wall(Vector2i(x, 3), BuildGrid.Side.NORTH))
	assert_int(_indoor_count()).is_equal(12)
	_apply(BuildEdit.place_wall(Vector2i(3, 3), BuildGrid.Side.NORTH, BuildGrid.WallKind.DOOR))
	assert_int(_indoor_count()).is_equal(12)
	assert_int(_grid.find_path(Vector2i(3, 2), Vector2i(3, 4)).size()).is_equal(3)


## Floor plays no part in the flood: floor painted inside a closed ring of
## walls is indoor at once, and the edit relinks it for passengers.
func test_floor_painted_inside_closed_walls_is_indoor() -> void:
	_apply(BuildEdit.remove_floor(Vector2i(3, 3)))
	assert_bool(_grid.is_indoor(Vector2i(3, 3))).is_false()
	assert_int(_indoor_count()).is_equal(11)
	_apply(BuildEdit.paint_floor(Vector2i(3, 3), BuildGrid.FLOOR_TILE, 1))
	assert_bool(_grid.is_passenger_cell(Vector2i(3, 3))).is_true()
	assert_int(_grid.find_path(Vector2i(2, 3), Vector2i(4, 3)).size()).is_equal(3)


## Floor touching the grid border with no wall there is outdoor, unless the
## border counts as walled (the Toon shell's facade, BuildGrid.shell_border).
func test_the_shell_border_closes_the_grid_edge() -> void:
	var grid := BuildGrid.new(Vector2i(4, 3))
	for y in 3:
		for x in 4:
			grid.apply(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	assert_bool(grid.is_indoor(Vector2i(1, 1))).is_false()
	assert_int(grid.find_path(Vector2i(0, 0), Vector2i(3, 2)).size()).is_equal(0)
	grid.graph_changed.connect(_on_graph_changed)
	grid.set_shell_border(true)
	assert_bool(grid.is_indoor(Vector2i(1, 1))).is_true()
	assert_int(_emitted.size()).is_equal(12)
	assert_int(grid.find_path(Vector2i(0, 0), Vector2i(3, 2)).size()).is_equal(4)


## One removed wall changes cells far from the edit; every one of them is
## relinked and named in graph_changed, not only the edit's neighbourhood.
func test_opening_a_wall_relinks_every_cell_that_changed() -> void:
	var grid := BuildGrid.new(Vector2i(20, 5))
	for x in range(1, 19):
		grid.apply(BuildEdit.paint_floor(Vector2i(x, 2), BuildGrid.FLOOR_TILE, 1))
	EnclosureKit.close_floor(grid)
	var far := Vector2i(1, 2)
	var near := Vector2i(18, 2)
	assert_int(grid.find_path(far, near).size()).is_equal(18)
	grid.graph_changed.connect(_on_graph_changed)
	grid.apply(BuildEdit.remove_wall(near, BuildGrid.Side.EAST))
	assert_bool(_emitted.has(far)).is_true()
	assert_int(grid.find_path(far, Vector2i(2, 2)).size()).is_equal(0)
	_emitted.clear()
	grid.apply(BuildEdit.place_wall(near, BuildGrid.Side.EAST))
	assert_bool(_emitted.has(far)).is_true()
	assert_int(grid.find_path(far, near).size()).is_equal(18)


## Staff access stays physical: staff walk floor that is not walled in.
func test_staff_paths_ignore_enclosure() -> void:
	_apply(BuildEdit.remove_wall(Vector2i(5, 3), BuildGrid.Side.EAST))
	assert_int(_grid.find_path(Vector2i(2, 2), Vector2i(5, 4)).size()).is_equal(0)
	assert_int(_grid.find_staff_path(Vector2i(2, 2), Vector2i(5, 4)).size()).is_equal(4)
	assert_bool(_grid.can_route(Vector2i(2, 2), Vector2i(3, 2))).is_true()
	assert_bool(_grid.can_passenger_route(Vector2i(2, 2), Vector2i(3, 2))).is_false()


## The mask is derived, never saved: a snapshot loaded into another grid, and
## through JSON, gives the same indoor cells, an open gap included.
func test_a_snapshot_load_derives_the_same_indoor_cells() -> void:
	var closed := BuildGrid.new(Vector2i(12, 10))
	var saved: Dictionary = JSON.parse_string(JSON.stringify(_grid.to_snapshot()))
	assert_bool(closed.from_snapshot(saved)).is_true()
	assert_bool(closed.is_indoor(Vector2i(3, 3))).is_true()
	assert_int(closed.find_path(Vector2i(2, 2), Vector2i(5, 4)).size()).is_equal(4)
	assert_bool(saved.has("indoor")).is_false()
	_apply(BuildEdit.remove_wall(Vector2i(2, 2), BuildGrid.Side.NORTH))
	var opened := BuildGrid.new(Vector2i(12, 10))
	assert_bool(opened.from_snapshot(_grid.to_snapshot())).is_true()
	assert_bool(opened.is_indoor(Vector2i(3, 3))).is_false()


## Undoing a wall removal (BuildUndo, which first tries it on a copy of the
## grid) closes the box again; undoing the wall's return opens it.
func test_undo_keeps_the_indoor_cells_right() -> void:
	_grid.recorder = BuildReceipt.new()
	_apply(BuildEdit.remove_wall(Vector2i(5, 3), BuildGrid.Side.EAST))
	var opening := _grid.recorder
	_grid.recorder = null
	assert_int(_indoor_count()).is_equal(0)
	assert_bool(BuildUndo.commit(_grid, opening, null).ok).is_true()
	assert_int(_indoor_count()).is_equal(12)
	assert_int(_grid.find_path(Vector2i(2, 2), Vector2i(5, 4)).size()).is_equal(4)
	_apply(BuildEdit.remove_wall(Vector2i(2, 2), BuildGrid.Side.NORTH))
	_grid.recorder = BuildReceipt.new()
	_apply(BuildEdit.place_wall(Vector2i(2, 2), BuildGrid.Side.NORTH))
	var closing := _grid.recorder
	_grid.recorder = null
	assert_int(_indoor_count()).is_equal(12)
	assert_bool(BuildUndo.commit(_grid, closing, null).ok).is_true()
	assert_int(_indoor_count()).is_equal(0)
	# The same shell border on the copy BuildUndo checks against.
	var shell := BuildGrid.new(Vector2i(4, 3))
	shell.set_shell_border(true)
	shell.apply(BuildEdit.paint_floor(Vector2i(1, 1), BuildGrid.FLOOR_TILE, 1))
	shell.recorder = BuildReceipt.new()
	shell.apply(BuildEdit.paint_floor(Vector2i(2, 1), BuildGrid.FLOOR_TILE, 1))
	var painting := shell.recorder
	shell.recorder = null
	assert_bool(BuildUndo.commit(shell, painting, null).ok).is_true()
	assert_bool(shell.is_indoor(Vector2i(1, 1))).is_true()
	assert_bool(shell.is_indoor(Vector2i(2, 1))).is_false()


## A load keeps the grid's own shell border.
func test_a_snapshot_load_keeps_the_shell_border() -> void:
	var shell := BuildGrid.new(Vector2i(4, 3))
	shell.set_shell_border(true)
	var bare := BuildGrid.new(Vector2i(4, 3))
	bare.apply(BuildEdit.paint_floor(Vector2i(1, 1), BuildGrid.FLOOR_TILE, 1))
	assert_bool(bare.is_indoor(Vector2i(1, 1))).is_false()
	assert_bool(shell.from_snapshot(bare.to_snapshot())).is_true()
	assert_bool(shell.shell_border).is_true()
	assert_bool(shell.is_indoor(Vector2i(1, 1))).is_true()
