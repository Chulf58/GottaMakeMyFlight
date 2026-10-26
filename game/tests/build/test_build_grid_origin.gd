class_name TestBuildGridOrigin
extends GdUnitTestSuite
## BuildGrid at an explicit world origin: the 66x30 grid the Toon shell will
## use, at (-33.5, 0.3, -94.8). Cell and world conversions, walls, objects and
## the snapshot keep that frame, and a snapshot saved before grids had an
## origin loads centred at floor height 0.

const SHELL_SIZE := Vector2i(66, 30)
const SHELL_ORIGIN := Vector3(-33.5, 0.3, -94.8)
const EPS := Vector3(0.0001, 0.0001, 0.0001)
const WEST := BuildGrid.Side.WEST


func _shell_grid() -> BuildGrid:
	return BuildGrid.new(SHELL_SIZE, SHELL_ORIGIN)


## Floor on x 4..19, y 2..11, a west wall along x 12 for y 2..7, a desk at
## (6, 4) facing north and a seat row at (15, 9) facing south.
func _built_shell_grid() -> BuildGrid:
	var grid := _shell_grid()
	var edits: Array[BuildEdit] = []
	for y in range(2, 12):
		for x in range(4, 20):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	for y in range(2, 8):
		edits.append(BuildEdit.place_wall(Vector2i(12, y), WEST))
	edits.append(BuildEdit.place_object(&"checkin_desk", Vector2i(6, 4), 0))
	edits.append(BuildEdit.place_object(&"seat_row", Vector2i(15, 9), 2))
	for edit in edits:
		assert_bool(grid.apply(edit).ok).is_true()
	return grid


func _through_json(data: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(data))
	assert_bool(parsed is Dictionary).is_true()
	return parsed


func test_the_default_grid_is_centred_at_floor_height_zero() -> void:
	assert_that(BuildGrid.new().origin).is_equal(Vector3(-32, 0, -32))
	assert_that(BuildGrid.new(Vector2i(10, 8)).origin).is_equal(Vector3(-5, 0, -4))
	assert_that(BuildGrid.centred_origin(Vector2i(7, 3))).is_equal(Vector3(-3.5, 0, -1.5))


func test_an_explicit_origin_and_size_are_kept() -> void:
	var grid := _shell_grid()
	assert_that(grid.size).is_equal(SHELL_SIZE)
	assert_that(grid.origin).is_equal(SHELL_ORIGIN)


func test_cell_to_world_and_back_on_the_shell_grid() -> void:
	var grid := _shell_grid()
	var first := grid.cell_to_world(Vector2i(0, 0))
	assert_vector(first).is_equal_approx(Vector3(-33.0, 0.3, -94.3), EPS)
	var last := grid.cell_to_world(Vector2i(65, 29))
	assert_vector(last).is_equal_approx(Vector3(32.0, 0.3, -65.3), EPS)
	for cell in [Vector2i(0, 0), Vector2i(65, 29), Vector2i(33, 15), Vector2i(0, 29)]:
		assert_that(grid.world_to_cell(grid.cell_to_world(cell))).is_equal(cell)
	var corner := SHELL_ORIGIN + Vector3(12, 0, 7)
	assert_that(grid.world_to_cell(corner + Vector3(0.01, 0, 0.01))).is_equal(Vector2i(12, 7))
	assert_that(grid.world_to_cell(corner + Vector3(0.99, 0, 0.99))).is_equal(Vector2i(12, 7))
	var outside := grid.world_to_cell(SHELL_ORIGIN - Vector3(0.01, 0, 0.01))
	assert_that(outside).is_equal(Vector2i(-1, -1))
	# The world origin is in a centred grid but 94 m south of this one's edge.
	assert_that(grid.world_to_cell(Vector3.ZERO)).is_equal(Vector2i(33, 94))
	assert_bool(grid.in_bounds(grid.world_to_cell(Vector3.ZERO))).is_false()


func test_walls_and_objects_are_found_from_world_points() -> void:
	var grid := _built_shell_grid()
	var near_west := grid.cell_to_world(Vector2i(12, 4)) + Vector3(-0.45, 0, 0.1)
	var cell := grid.world_to_cell(near_west)
	assert_that(cell).is_equal(Vector2i(12, 4))
	assert_int(grid.nearest_side(near_west)).is_equal(WEST)
	assert_bool(grid.has_wall(cell, grid.nearest_side(near_west))).is_true()
	var desk := grid.object_at(Vector2i(6, 4))
	assert_int(desk).is_greater(0)
	var desk_east := grid.cell_to_world(Vector2i(7, 4)) + Vector3(0.3, 0, -0.3)
	assert_int(grid.object_at(grid.world_to_cell(desk_east))).is_equal(desk)


func test_the_snapshot_keeps_the_origin_through_json() -> void:
	var grid := _built_shell_grid()
	var snapshot := grid.to_snapshot()
	var saved: Array = snapshot["origin"]
	assert_array(saved).has_size(3)
	assert_float(saved[1]).is_equal_approx(0.3, 0.0001)
	var other := BuildGrid.new()
	assert_bool(other.from_snapshot(_through_json(snapshot))).is_true()
	assert_that(other.size).is_equal(SHELL_SIZE)
	assert_that(other.origin).is_equal(grid.origin)
	assert_str(JSON.stringify(other.to_snapshot())).is_equal(JSON.stringify(snapshot))
	var desk := grid.object_at(Vector2i(6, 4))
	var desk_east := grid.cell_to_world(Vector2i(7, 4))
	assert_int(other.object_at(other.world_to_cell(desk_east))).is_equal(desk)
	assert_bool(other.has_wall(Vector2i(11, 5), BuildGrid.Side.EAST)).is_true()
	var expected := grid.find_path(Vector2i(4, 11), Vector2i(19, 2))
	assert_array(expected).is_not_empty()
	assert_array(other.find_path(Vector2i(4, 11), Vector2i(19, 2))).is_equal(expected)


func test_a_snapshot_without_an_origin_loads_centred_at_floor_height_zero() -> void:
	var old := _through_json(_built_shell_grid().to_snapshot())
	old.erase("origin")
	assert_str(BuildGridSnapshot.problem(old)).is_empty()
	var other := BuildGrid.new(Vector2i(4, 4), SHELL_ORIGIN)
	assert_bool(other.from_snapshot(old)).is_true()
	assert_that(other.size).is_equal(SHELL_SIZE)
	assert_that(other.origin).is_equal(Vector3(-33, 0, -15))
	assert_int(other.floor_at(Vector2i(19, 11))).is_equal(BuildGrid.FLOOR_TILE)


func test_a_malformed_origin_is_rejected_and_the_grid_is_unchanged() -> void:
	var good := _through_json(_built_shell_grid().to_snapshot())
	var other := BuildGrid.new(Vector2i(4, 4))
	var before := JSON.stringify(other.to_snapshot())
	var too_far := BuildGrid.MAX_ORIGIN_M + 1.0
	var bad_origins := [
		"(0, 0, 0)",
		null,
		[1.0, 2.0],
		[1.0, 2.0, 3.0, 4.0],
		[1.0, "2", 3.0],
		[1.0, NAN, 3.0],
		[INF, 0.0, 0.0],
		[0.0, 0.0, -too_far],
	]
	for bad in bad_origins:
		var data := good.duplicate(true)
		data["origin"] = bad
		assert_str(BuildGridSnapshot.problem(data)).contains("origin")
		assert_bool(other.from_snapshot(data)).is_false()
		assert_str(JSON.stringify(other.to_snapshot())).is_equal(before)
