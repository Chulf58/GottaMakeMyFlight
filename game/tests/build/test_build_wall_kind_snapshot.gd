class_name TestBuildWallKindSnapshot
extends GdUnitTestSuite
## Wall kinds in the BuildGrid snapshot. The kind is the wall value itself
## (0 none, 1 plain, 2 glass, 3 door), so a snapshot written before kinds
## existed, with only 0 and 1, loads with every wall plain.

const NORTH := BuildGrid.Side.NORTH


## A 4x3 floored grid with a wall along the north edge of row 1: glass at
## x = 0, a door at x = 2, plain elsewhere.
func _kinded_grid() -> BuildGrid:
	var grid := _plain_grid()
	grid.apply(BuildEdit.place_wall(Vector2i(0, 1), NORTH, BuildGrid.WallKind.GLASS))
	grid.apply(BuildEdit.place_wall(Vector2i(2, 1), NORTH, BuildGrid.WallKind.DOOR))
	return grid


func _plain_grid() -> BuildGrid:
	var grid := BuildGrid.new(Vector2i(4, 3))
	for y in 3:
		for x in 4:
			grid.apply(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	for x in 4:
		grid.apply(BuildEdit.place_wall(Vector2i(x, 1), NORTH))
	return grid


func _through_json(data: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(data))
	assert_bool(parsed is Dictionary).is_true()
	return parsed


func test_kinds_round_trip_through_json() -> void:
	var snapshot := _kinded_grid().to_snapshot()
	var other := BuildGrid.new()
	assert_bool(other.from_snapshot(_through_json(snapshot))).is_true()
	assert_str(JSON.stringify(other.to_snapshot())).is_equal(JSON.stringify(snapshot))
	assert_int(other.wall_kind(Vector2i(0, 1), NORTH)).is_equal(BuildGrid.WallKind.GLASS)
	assert_int(other.wall_kind(Vector2i(1, 1), NORTH)).is_equal(BuildGrid.WallKind.PLAIN)
	assert_int(other.wall_kind(Vector2i(2, 1), NORTH)).is_equal(BuildGrid.WallKind.DOOR)
	assert_array(other.find_path(Vector2i(2, 2), Vector2i(2, 0))).is_not_empty()


func test_a_snapshot_from_before_kinds_loads_every_wall_as_plain() -> void:
	var old := _plain_grid().to_snapshot()
	var values: Array = old["h_walls"] + old["v_walls"]
	assert_bool(values.all(func(v: int) -> bool: return v == 0 or v == 1)).is_true()
	assert_int(values.count(1)).is_equal(4)
	var other := BuildGrid.new()
	assert_bool(other.from_snapshot(_through_json(old))).is_true()
	for x in 4:
		assert_int(other.wall_kind(Vector2i(x, 1), NORTH)).is_equal(BuildGrid.WallKind.PLAIN)
	assert_array(other.find_path(Vector2i(2, 2), Vector2i(2, 0))).is_empty()


func test_an_unknown_kind_or_a_door_without_its_walls_is_rejected() -> void:
	var good := _kinded_grid().to_snapshot()
	var other := BuildGrid.new()
	assert_bool(other.from_snapshot(good)).is_true()
	var before := JSON.stringify(other.to_snapshot())
	var unknown := good.duplicate(true)
	unknown["h_walls"][4] = 4
	var lone_door := good.duplicate(true)
	# Row 1's north edges sit at 4..7; take away the plain wall at x = 3.
	lone_door["h_walls"][7] = 0
	var door_by_glass := good.duplicate(true)
	door_by_glass["h_walls"][5] = BuildGrid.WallKind.GLASS
	for bad in [unknown, lone_door, door_by_glass]:
		assert_bool(other.from_snapshot(bad)).is_false()
		assert_str(JSON.stringify(other.to_snapshot())).is_equal(before)
