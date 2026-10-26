class_name TestBuildViewCutaway
extends GdUnitTestSuite
## WallCutaway: which walls drop at each camera yaw quadrant.

const NORTH := BuildGrid.Side.NORTH
const WEST := BuildGrid.Side.WEST

var _grid: BuildGrid
var _cutaway: WallCutaway


## A 3x3 room of floor (cells 2..4) walled all round, on an 8x8 grid.
func before() -> void:
	_grid = BuildGrid.new(Vector2i(8, 8))
	for y in range(2, 5):
		for x in range(2, 5):
			_grid.apply(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	for i in range(2, 5):
		_grid.apply(BuildEdit.place_wall(Vector2i(i, 2), NORTH))
		_grid.apply(BuildEdit.place_wall(Vector2i(i, 4), BuildGrid.Side.SOUTH))
		_grid.apply(BuildEdit.place_wall(Vector2i(2, i), WEST))
		_grid.apply(BuildEdit.place_wall(Vector2i(4, i), BuildGrid.Side.EAST))


func before_test() -> void:
	_cutaway = WallCutaway.new()


## The camera's direction toward the eye for a TycoonCamera yaw (yaw 0 looks
## from +z), tilted 45 degrees.
func _toward_eye(yaw_degrees: float) -> Vector3:
	return Basis(Vector3.UP, deg_to_rad(yaw_degrees)) * Vector3(0.0, 1.0, 1.0).normalized()


## Which room sides are cut, as a sorted list of "north", "south", "west", "east".
func _cut_sides() -> Array:
	var sides := {}
	for i in range(2, 5):
		if _cutaway.is_cut(_grid, Vector2i(i, 2), NORTH):
			sides["north"] = true
		if _cutaway.is_cut(_grid, Vector2i(i, 5), NORTH):
			sides["south"] = true
		if _cutaway.is_cut(_grid, Vector2i(2, i), WEST):
			sides["west"] = true
		if _cutaway.is_cut(_grid, Vector2i(5, i), WEST):
			sides["east"] = true
	var result := sides.keys()
	result.sort()
	return result


func test_each_quadrant_drops_the_two_camera_side_walls() -> void:
	var expected := {
		45.0: ["east", "south"],
		135.0: ["east", "north"],
		-135.0: ["north", "west"],
		-45.0: ["south", "west"],
	}
	for yaw in expected:
		_cutaway.update(_toward_eye(yaw))
		assert_array(_cut_sides()).override_failure_message("yaw %s" % yaw).is_equal(expected[yaw])


func test_every_wall_of_a_side_drops_together() -> void:
	_cutaway.update(_toward_eye(45.0))
	for i in range(2, 5):
		assert_bool(_cutaway.is_cut(_grid, Vector2i(i, 5), NORTH)).is_true()
		assert_bool(_cutaway.is_cut(_grid, Vector2i(5, i), WEST)).is_true()
		assert_bool(_cutaway.is_cut(_grid, Vector2i(i, 2), NORTH)).is_false()
		assert_bool(_cutaway.is_cut(_grid, Vector2i(2, i), WEST)).is_false()


func test_both_forms_of_an_edge_agree() -> void:
	_cutaway.update(_toward_eye(45.0))
	assert_bool(_cutaway.is_cut(_grid, Vector2i(3, 4), BuildGrid.Side.SOUTH)).is_true()
	assert_bool(_cutaway.is_cut(_grid, Vector2i(4, 3), BuildGrid.Side.EAST)).is_true()
	assert_bool(_cutaway.is_cut(_grid, Vector2i(3, 1), BuildGrid.Side.SOUTH)).is_false()


func test_edge_on_axis_keeps_its_last_side() -> void:
	_cutaway.update(_toward_eye(0.0))
	assert_array(_cut_sides()).is_equal(["south"])
	assert_bool(_cutaway.update(_toward_eye(45.0))).is_true()
	assert_array(_cut_sides()).is_equal(["east", "south"])
	# Back to 3 degrees off straight south: x is inside the deadband and stays.
	assert_bool(_cutaway.update(_toward_eye(3.0))).is_false()
	assert_array(_cut_sides()).is_equal(["east", "south"])
	assert_bool(_cutaway.update(_toward_eye(-10.0))).is_true()
	assert_array(_cut_sides()).is_equal(["south", "west"])


func test_a_camera_looking_straight_down_changes_nothing() -> void:
	_cutaway.update(_toward_eye(45.0))
	assert_bool(_cutaway.update(Vector3.UP)).is_false()
	assert_array(_cut_sides()).is_equal(["east", "south"])


func test_a_wall_with_bare_ground_behind_it_stays_full() -> void:
	# A free-standing wall on grass, north of the room, seen from the north.
	var grid := BuildGrid.new(Vector2i(8, 8))
	grid.apply(BuildEdit.place_wall(Vector2i(6, 1), NORTH))
	_cutaway.update(_toward_eye(180.0))
	assert_bool(_cutaway.is_cut(grid, Vector2i(6, 1), NORTH)).is_false()


func test_a_partition_drops_when_floor_is_behind_it() -> void:
	var grid := BuildGrid.new(Vector2i(8, 8))
	for y in 3:
		grid.apply(BuildEdit.paint_floor(Vector2i(1, y), BuildGrid.FLOOR_TILE, 1))
	grid.apply(BuildEdit.place_wall(Vector2i(1, 1), NORTH))
	_cutaway.update(_toward_eye(0.0))
	assert_bool(_cutaway.is_cut(grid, Vector2i(1, 1), NORTH)).is_true()
	_cutaway.update(_toward_eye(180.0))
	assert_bool(_cutaway.is_cut(grid, Vector2i(1, 1), NORTH)).is_true()


func test_posts_go_on_corners_and_ends_not_mid_run() -> void:
	var edges := WallCutaway.wall_edges(_grid)
	assert_int(edges.size()).is_equal(12)
	var full := {}
	for edge in edges:
		full[edge] = true
	# The south-east corner joins two cut walls: a stub post.
	full[Vector3i(4, 5, NORTH)] = false
	full[Vector3i(5, 4, WEST)] = false
	var posts := WallCutaway.posts(edges, full)
	assert_array(posts.keys()).contains_exactly_in_any_order(
		[Vector2i(2, 2), Vector2i(5, 2), Vector2i(2, 5), Vector2i(5, 5)]
	)
	assert_bool(posts[Vector2i(5, 5)]).is_false()
	assert_bool(posts[Vector2i(2, 2)]).is_true()
	# A T-junction and a free end get posts too.
	edges.append(Vector3i(3, 2, WEST))
	posts = WallCutaway.posts(edges, full)
	assert_bool(posts.has(Vector2i(3, 2))).is_true()
	assert_bool(posts.has(Vector2i(3, 3))).is_true()
