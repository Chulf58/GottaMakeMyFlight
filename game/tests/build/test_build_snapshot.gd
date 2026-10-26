class_name TestBuildSnapshot
extends GdUnitTestSuite


func _built_grid() -> BuildGrid:
	var grid := BuildGrid.new(Vector2i(10, 8))
	for y in 8:
		for x in 10:
			grid.apply(
				BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1 if x < 5 else 2)
			)
	for y in 6:
		grid.apply(BuildEdit.place_wall(Vector2i(5, y), BuildGrid.Side.WEST))
	grid.apply(BuildEdit.place_wall(Vector2i(0, 0), BuildGrid.Side.NORTH))
	grid.apply(BuildEdit.place_object(&"checkin_desk", Vector2i(1, 1), 0))
	grid.apply(BuildEdit.place_object(&"security_scanner", Vector2i(7, 3), 1))
	grid.apply(BuildEdit.place_object(&"seat_row", Vector2i(2, 5), 2))
	grid.apply(BuildEdit.remove_floor(Vector2i(9, 7)))
	return grid


func _through_json(data: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(data))
	assert_bool(parsed is Dictionary).is_true()
	return parsed


func test_snapshot_round_trips_through_json() -> void:
	var grid := _built_grid()
	var snapshot := grid.to_snapshot()
	var other := BuildGrid.new()
	assert_bool(other.from_snapshot(_through_json(snapshot))).is_true()
	assert_str(JSON.stringify(other.to_snapshot())).is_equal(JSON.stringify(snapshot))
	assert_that(other.size).is_equal(Vector2i(10, 8))
	assert_int(other.zone_at(Vector2i(7, 0))).is_equal(2)
	assert_int(other.floor_at(Vector2i(9, 7))).is_equal(BuildGrid.FLOOR_NONE)
	assert_bool(other.has_wall(Vector2i(4, 2), BuildGrid.Side.EAST)).is_true()
	var desk_id := grid.object_at(Vector2i(1, 1))
	assert_int(other.object_at(Vector2i(2, 1))).is_equal(desk_id)
	assert_that(other.interaction_cell(desk_id)).is_equal(Vector2i(1, 2))
	var expected := grid.find_path(Vector2i(0, 7), Vector2i(9, 0))
	assert_array(expected).is_not_empty()
	assert_array(other.find_path(Vector2i(0, 7), Vector2i(9, 0))).has_size(expected.size())


func test_object_ids_keep_counting_after_a_load() -> void:
	var grid := _built_grid()
	var other := BuildGrid.new()
	other.from_snapshot(_through_json(grid.to_snapshot()))
	var placed := other.apply(BuildEdit.place_object(&"seat_row", Vector2i(6, 6), 0))
	assert_bool(placed.ok).is_true()
	assert_int(placed.object_id).is_greater(grid.object_at(Vector2i(2, 5)))
	assert_int(placed.object_id).is_greater(grid.object_at(Vector2i(7, 3)))


func test_malformed_snapshot_is_rejected_and_grid_unchanged() -> void:
	var good := _through_json(_built_grid().to_snapshot())
	var other := BuildGrid.new(Vector2i(4, 4))
	other.apply(BuildEdit.paint_floor(Vector2i(1, 1), BuildGrid.FLOOR_TILE, 3))
	var before := JSON.stringify(other.to_snapshot())
	var bad_cases: Array[Dictionary] = []
	for key in good.keys():
		var missing := good.duplicate(true)
		missing.erase(key)
		bad_cases.append(missing)
	var mutations := [
		["width", 0],
		["height", 2.5],
		["width", "ten"],
		["floor", [1, 1]],
		["zone", "nope"],
		["next_object_id", -1],
		["objects", {}],
	]
	for mutation in mutations:
		var changed := good.duplicate(true)
		changed[mutation[0]] = mutation[1]
		bad_cases.append(changed)
	var bad_floor := good.duplicate(true)
	bad_floor["floor"][3] = 42
	bad_cases.append(bad_floor)
	var bad_wall := good.duplicate(true)
	bad_wall["h_walls"][0] = 2
	bad_cases.append(bad_wall)
	bad_cases.append(_with_object_change(good, "def", "rocket"))
	bad_cases.append(_with_object_change(good, "facing", 5))
	bad_cases.append(_with_object_change(good, "anchor", [1]))
	bad_cases.append(_with_object_change(good, "id", 0))
	var overlap := good.duplicate(true)
	var copy: Dictionary = overlap["objects"][0].duplicate(true)
	copy["id"] = 99
	overlap["objects"].append(copy)
	bad_cases.append(overlap)
	var stale_counter := good.duplicate(true)
	stale_counter["next_object_id"] = 1
	bad_cases.append(stale_counter)
	for bad in bad_cases:
		assert_bool(other.from_snapshot(bad)).is_false()
		assert_str(JSON.stringify(other.to_snapshot())).is_equal(before)
	assert_int(other.floor_at(Vector2i(1, 1))).is_equal(BuildGrid.FLOOR_TILE)
	assert_array(other.find_path(Vector2i(1, 1), Vector2i(1, 1))).has_size(1)


func _with_object_change(good: Dictionary, key: String, value: Variant) -> Dictionary:
	var changed := good.duplicate(true)
	changed["objects"][0][key] = value
	return changed
