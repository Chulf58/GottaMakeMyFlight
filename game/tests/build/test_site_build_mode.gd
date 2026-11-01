class_name TestSiteBuildMode
extends GdUnitTestSuite
## BuildMode on the airport site (main.tscn's BuildMode.site): the grid takes
## the site's frame and starts empty; a room painted, walled and given an
## entrance with the tools is closed in and roofed (RoofView), and undo takes
## the entrance, the walls and the floor back one action at a time, the indoor
## cells and the roof following; a save in another frame is refused and a
## save in the site's frame loads with its indoor cells worked out again.

const SITE := preload("res://build/terminal_site.tres")
## A 3 x 3 room on the plot's south edge, its entrance in the south wall.
const ROOM := Rect2i(40, 36, 3, 3)
const ENTRANCE := Vector2i(41, 38)

var _mode: BuildMode
var _roof: RoofView


func before_test() -> void:
	_mode = auto_free(BuildMode.new())
	_mode.site = SITE
	add_child(_mode)
	_roof = auto_free(RoofView.new())
	add_child(_roof)
	_roof.bind(_mode.grid)


func _use(tool: BuildMode.Tool, turns: int) -> void:
	_mode.set_tool(tool)
	while _mode.facing != turns:
		_mode.rotate_facing()


func _click_cell(cell: Vector2i) -> void:
	var result := _mode.apply_at(_mode.grid.cell_to_world(cell))
	assert_bool(result != null and result.ok).override_failure_message("%s" % cell).is_true()


func _click_edge(cell: Vector2i, side: int) -> void:
	var step := BuildGrid.SIDE_STEP[side]
	var point := _mode.grid.cell_to_world(cell) + Vector3(step.x * 0.45, 0.0, step.y * 0.45)
	var result := _mode.apply_at(point)
	var what := "%s %d" % [cell, side]
	assert_bool(result != null and result.ok).override_failure_message(what).is_true()


## The room's outer edges as [cell, side], the entrance's gap left out.
func _outer_edges() -> Array:
	var edges := []
	for y in range(ROOM.position.y, ROOM.end.y):
		for x in range(ROOM.position.x, ROOM.end.x):
			var cell := Vector2i(x, y)
			for side in 4:
				if ROOM.has_point(cell + BuildGrid.SIDE_STEP[side]):
					continue
				if cell == ENTRANCE and side == BuildGrid.Side.SOUTH:
					continue
				edges.append([cell, side])
	return edges


func _indoor_count() -> int:
	var count := 0
	for y in _mode.grid.size.y:
		for x in _mode.grid.size.x:
			count += int(_mode.grid.is_indoor(Vector2i(x, y)))
	return count


## Paints the room, walls it and places the entrance, one action each.
func _build_room() -> int:
	_use(BuildMode.Tool.FLOOR, 0)
	for y in range(ROOM.position.y, ROOM.end.y):
		for x in range(ROOM.position.x, ROOM.end.x):
			_click_cell(Vector2i(x, y))
	_use(BuildMode.Tool.WALL, 0)
	var walls := _outer_edges()
	for edge in walls:
		_click_edge(edge[0], edge[1])
	assert_int(_indoor_count()).is_equal(0)
	assert_int(_roof.roofed_cell_count()).is_equal(0)
	_use(BuildMode.Tool.ENTRANCE, 2)
	_click_cell(ENTRANCE)
	return walls.size()


func test_the_grid_takes_the_site_frame_and_starts_empty() -> void:
	assert_that(_mode.grid.size).is_equal(SITE.grid_size)
	assert_vector(_mode.grid.origin).is_equal(SITE.grid_origin)
	assert_int(_mode.grid.object_ids().size()).is_equal(0)
	assert_float(StartView.area_for(_mode.grid).size.x).is_greater(0.0)


func test_a_walled_room_with_its_entrance_is_indoor_and_roofed() -> void:
	var walls := _build_room()
	print("walls %d, indoor %d, roofed %d" % [walls, _indoor_count(), _roof.roofed_cell_count()])
	assert_int(walls).is_equal(11)
	assert_int(_indoor_count()).is_equal(9)
	assert_int(_roof.roofed_cell_count()).is_equal(9)


func test_undo_takes_back_the_entrance_the_walls_and_the_floor() -> void:
	var walls := _build_room()
	var actions := _mode.undo_history().size()
	assert_int(_indoor_count()).is_equal(9)
	# The entrance: its gap opens, the room is outdoor and the roof goes.
	assert_bool(_mode.undo().ok).is_true()
	assert_int(_mode.grid.object_ids().size()).is_equal(0)
	assert_int(_indoor_count()).is_equal(0)
	assert_int(_roof.roofed_cell_count()).is_equal(0)
	# The walls, newest first.
	var edges := _outer_edges()
	for i in walls:
		var edge: Array = edges[walls - 1 - i]
		assert_bool(_mode.grid.has_wall(edge[0], edge[1])).is_true()
		assert_bool(_mode.undo().ok).is_true()
		assert_bool(_mode.grid.has_wall(edge[0], edge[1])).is_false()
	# The last floor cell painted.
	var last := ROOM.end - Vector2i.ONE
	assert_int(_mode.grid.floor_at(last)).is_not_equal(BuildGrid.FLOOR_NONE)
	assert_bool(_mode.undo().ok).is_true()
	assert_int(_mode.grid.floor_at(last)).is_equal(BuildGrid.FLOOR_NONE)
	print("actions %d, left %d" % [actions, _mode.undo_history().size()])
	assert_int(_mode.undo_history().size()).is_equal(actions - walls - 2)


func test_a_save_in_another_frame_is_refused_and_the_site_frame_loads() -> void:
	_build_room()
	var saved := JSON.parse_string(JSON.stringify(_mode.grid.to_snapshot())) as Dictionary
	var before := JSON.stringify(_mode.grid.to_snapshot())
	var other := BuildGrid.new()
	other.apply(BuildEdit.paint_floor(Vector2i(3, 3), BuildGrid.FLOOR_TILE, 1))
	var foreign := JSON.parse_string(JSON.stringify(other.to_snapshot())) as Dictionary
	assert_str(SITE.snapshot_problem(foreign)).contains("another frame than the site")
	assert_bool(_mode.load_snapshot(foreign)).is_false()
	assert_str(JSON.stringify(_mode.grid.to_snapshot())).is_equal(before)
	# Control: the site-frame save loads into a fresh BuildMode, closed in again.
	var fresh: BuildMode = auto_free(BuildMode.new())
	fresh.site = SITE
	add_child(fresh)
	assert_str(SITE.snapshot_problem(saved)).is_empty()
	assert_bool(fresh.load_snapshot(saved)).is_true()
	assert_bool(fresh.grid.is_indoor(ENTRANCE)).is_true()
	assert_str(JSON.stringify(fresh.grid.to_snapshot())).is_equal(before)
