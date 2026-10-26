class_name TestRoomSnapshot
extends GdUnitTestSuite
## Rooms in the BuildGrid snapshot: the optional "rooms" and "next_room_id"
## keys round-trip through JSON, an older save without them loads with no
## rooms, and a malformed or rule-breaking room refuses the whole load.


func _grid_with_rooms() -> BuildGrid:
	var grid := BuildGrid.new(Vector2i(12, 10))
	var edits: Array[BuildEdit] = []
	for y in range(1, 9):
		for x in range(1, 11):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	grid.apply_batch(edits)
	grid.apply(BuildEdit.place_room(Rect2i(1, 1, 4, 3), &"cafe"))
	var gone := grid.apply(BuildEdit.place_room(Rect2i(6, 1, 3, 3), &"cafe"))
	grid.apply(BuildEdit.remove_room(gone.room_id))
	grid.apply(BuildEdit.place_room(Rect2i(6, 5, 3, 3), &"cafe"))
	grid.apply(BuildEdit.place_object(&"cafe_counter", Vector2i(2, 1), 0))
	return grid


func _through_json(data: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(data))
	assert_bool(parsed is Dictionary).is_true()
	return parsed


func test_rooms_round_trip_through_json() -> void:
	var grid := _grid_with_rooms()
	var snapshot := grid.to_snapshot()
	(
		assert_array(snapshot["rooms"])
		. is_equal(
			[
				{"id": 1, "type": "cafe", "rect": [1, 1, 4, 3]},
				{"id": 3, "type": "cafe", "rect": [6, 5, 3, 3]},
			]
		)
	)
	assert_int(snapshot["next_room_id"]).is_equal(4)
	var other := BuildGrid.new()
	assert_bool(other.from_snapshot(_through_json(snapshot))).is_true()
	assert_str(JSON.stringify(other.to_snapshot())).is_equal(JSON.stringify(snapshot))
	assert_int(other.room_at(Vector2i(4, 3))).is_equal(1)
	assert_int(other.room_at(Vector2i(8, 7))).is_equal(3)
	assert_int(other.room_at(Vector2i(7, 2))).is_equal(0)
	var next := other.apply(BuildEdit.place_room(Rect2i(6, 1, 3, 3), &"cafe"))
	assert_int(next.room_id).is_equal(4)


func test_a_save_from_before_rooms_loads_with_none() -> void:
	var data := _through_json(_grid_with_rooms().to_snapshot())
	data.erase("rooms")
	data.erase("next_room_id")
	var other := BuildGrid.new()
	assert_bool(other.from_snapshot(data)).is_true()
	assert_array(other.room_ids()).is_empty()
	assert_int(other.apply(BuildEdit.place_room(Rect2i(1, 1, 3, 3), &"cafe")).room_id).is_equal(1)


func test_a_loaded_room_keeps_its_floor_protected() -> void:
	var other := BuildGrid.new()
	other.from_snapshot(_through_json(_grid_with_rooms().to_snapshot()))
	var result := other.apply(BuildEdit.remove_floor(Vector2i(1, 1)))
	assert_int(result.reason).is_equal(BuildResult.Reason.IN_ROOM)


func test_malformed_rooms_are_rejected_and_the_grid_is_unchanged() -> void:
	var good := _through_json(_grid_with_rooms().to_snapshot())
	var cases: Array[Dictionary] = []
	var only_rooms := good.duplicate(true)
	only_rooms.erase("next_room_id")
	cases.append(only_rooms)
	var only_next := good.duplicate(true)
	only_next.erase("rooms")
	cases.append(only_next)
	var mutations := [
		["rooms", {}],
		["rooms", ["cafe"]],
		["rooms", [{"id": 1, "type": "cafe"}]],
		["rooms", [{"id": 0, "type": "cafe", "rect": [1, 1, 3, 3]}]],
		["rooms", [{"id": 1, "type": 5, "rect": [1, 1, 3, 3]}]],
		["rooms", [{"id": 1, "type": "cafe", "rect": [1, 1, 3]}]],
		["rooms", [{"id": 1, "type": "cafe", "rect": [1, 1, 3.5, 3]}]],
		["rooms", [{"id": 1, "type": "cafe", "rect": [1, 1, 0, 3]}]],
		[
			"rooms",
			[
				{"id": 1, "type": "cafe", "rect": [1, 1, 3, 3]},
				{"id": 1, "type": "cafe", "rect": [6, 5, 3, 3]},
			]
		],
		["next_room_id", 2],
		["next_room_id", "four"],
	]
	for mutation in mutations:
		var changed := good.duplicate(true)
		changed[mutation[0]] = mutation[1]
		cases.append(changed)
	# Shape is fine but a placement rule breaks: overlap, no floor, out of the
	# grid, unknown type.
	var rule_breaks := [
		[
			{"id": 1, "type": "cafe", "rect": [1, 1, 3, 3]},
			{"id": 2, "type": "cafe", "rect": [2, 2, 3, 3]}
		],
		[{"id": 1, "type": "cafe", "rect": [0, 0, 3, 3]}],
		[{"id": 1, "type": "cafe", "rect": [10, 8, 3, 3]}],
		[{"id": 1, "type": "spa", "rect": [1, 1, 3, 3]}],
	]
	for rooms in rule_breaks:
		var changed := good.duplicate(true)
		changed["rooms"] = rooms
		changed["next_room_id"] = 3
		cases.append(changed)
	var other := BuildGrid.new(Vector2i(4, 4))
	other.apply(BuildEdit.paint_floor(Vector2i(1, 1), BuildGrid.FLOOR_TILE, 1))
	var before := JSON.stringify(other.to_snapshot())
	for data in cases:
		assert_bool(other.from_snapshot(data)).is_false()
		assert_str(JSON.stringify(other.to_snapshot())).is_equal(before)
	print("rejected %d malformed room snapshots" % cases.size())
	assert_int(cases.size()).is_equal(17)
