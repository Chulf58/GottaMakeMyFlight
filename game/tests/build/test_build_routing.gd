class_name TestBuildRouting
extends GdUnitTestSuite
## Generic routing around security, the edit neighbourhood that invalidates
## committed paths, and the terminal door objects.

var _changes: Array = []


func _floored_grid(size: Vector2i) -> BuildGrid:
	var grid := BuildGrid.new(size)
	for y in size.y:
		for x in size.x:
			grid.apply(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	return grid


func _on_graph_changed(cells: Array[Vector2i]) -> void:
	_changes.append(cells)


func test_routing_never_enters_a_scanner_even_beside_an_open_gap() -> void:
	var grid := _floored_grid(Vector2i(8, 7))
	for x in 8:
		if x != 3 and x != 6:
			grid.apply(BuildEdit.place_wall(Vector2i(x, 4), BuildGrid.Side.NORTH))
	(
		assert_bool(grid.apply(BuildEdit.place_object(&"security_scanner", Vector2i(3, 3), 0)).ok)
		. is_true()
	)
	# Straight through the scanner would be shorter; the route takes the gap at x = 6.
	var path := grid.find_path(Vector2i(3, 0), Vector2i(3, 6))
	assert_bool(path.is_empty()).is_false()
	assert_bool(path.has(Vector2i(3, 3))).is_false()
	assert_bool(path.has(Vector2i(3, 4))).is_false()
	assert_int(_crossing_x(path, 4)).is_equal(6)


func test_scanner_passage_runs_entry_through_footprint_to_exit() -> void:
	var grid := _floored_grid(Vector2i(6, 7))
	var placed := grid.apply(BuildEdit.place_object(&"security_scanner", Vector2i(2, 2), 0))
	var expected: Array[Vector2i] = [Vector2i(2, 4), Vector2i(2, 3), Vector2i(2, 2), Vector2i(2, 1)]
	assert_array(grid.passage_cells(placed.object_id)).is_equal(expected)
	grid.apply(BuildEdit.place_wall(Vector2i(2, 2), BuildGrid.Side.NORTH))
	assert_array(grid.passage_cells(placed.object_id)).is_empty()


func test_scanner_is_listed_as_a_security_object() -> void:
	assert_bool(BuildCatalog.is_security(&"security_scanner")).is_true()
	assert_bool(BuildCatalog.is_security(&"checkin_desk")).is_false()
	assert_bool(BuildCatalog.is_security(&"exit_door")).is_false()


## A diagonal link depends on the two cells beside it, so an edit reports the
## same 3x3 neighbourhood GridPathing relinks, not only the edited cell.
func test_an_edit_reports_the_relinked_neighbourhood() -> void:
	var grid := _floored_grid(Vector2i(6, 6))
	_changes.clear()
	grid.graph_changed.connect(_on_graph_changed)
	grid.apply(BuildEdit.place_object(&"seat_row", Vector2i(2, 2), 1))
	assert_int(_changes.size()).is_equal(1)
	var cells: Array[Vector2i] = _changes[0]
	assert_bool(cells.has(Vector2i(1, 1))).is_true()
	assert_bool(cells.has(Vector2i(3, 5))).is_true()
	assert_bool(cells.has(Vector2i(4, 2))).is_false()
	var expected := GridPathing.neighbourhood(
		grid, [Vector2i(2, 2), Vector2i(2, 3), Vector2i(2, 4)]
	)
	assert_array(cells).contains_exactly_in_any_order(expected)


func test_a_refused_edit_reports_nothing() -> void:
	var grid := BuildGrid.new(Vector2i(4, 4))
	_changes.clear()
	grid.graph_changed.connect(_on_graph_changed)
	assert_bool(grid.apply(BuildEdit.place_object(&"seat_row", Vector2i(0, 0), 0)).ok).is_false()
	assert_int(_changes.size()).is_equal(0)


func test_exit_and_entrance_doors_are_one_cell_walk_through_markers() -> void:
	for id in [&"exit_door", &"entrance_door"]:
		var def := BuildCatalog.get_def(id)
		assert_object(def).is_not_null()
		assert_that(def.size).is_equal(Vector2i.ONE)
		assert_bool(def.walk_through).is_true()
		assert_bool(def.has_interaction).is_true()
		assert_that(def.interaction_offset).is_equal(Vector2i(0, 1))
		assert_bool(BuildCatalog.is_door(id)).is_true()
	assert_bool(BuildCatalog.is_door(&"seat_row")).is_false()


func test_a_door_on_the_floor_edge_can_be_routed_into_along_its_axis() -> void:
	var grid := BuildGrid.new(Vector2i(5, 5))
	for y in range(1, 5):
		for x in 5:
			grid.apply(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	var door := grid.apply(BuildEdit.place_object(&"exit_door", Vector2i(2, 1), 0))
	assert_bool(door.ok).is_true()
	var path := grid.find_path(Vector2i(0, 4), Vector2i(2, 1))
	assert_that(path[path.size() - 2]).is_equal(Vector2i(2, 2))
	assert_bool(grid.can_route(Vector2i(1, 1), Vector2i(2, 1))).is_false()


## The x of the first step that crosses from row y - 1 into row y, or -1.
func _crossing_x(path: Array[Vector2i], y: int) -> int:
	for i in range(1, path.size()):
		if path[i - 1].y == y - 1 and path[i].y == y:
			return path[i].x
	return -1
