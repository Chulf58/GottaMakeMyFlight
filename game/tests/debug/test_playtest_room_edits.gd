class_name TestPlaytestRoomEdits
extends GdUnitTestSuite
## PlaytestState for rooms: a room edit is logged with what identifies it (the
## type and rectangle it marks, or the room id it removes), and grid_summary()
## lists every room with its status, all JSON-safe.


func _cafe_grid() -> BuildGrid:
	var grid := BuildGrid.new(Vector2i(12, 10))
	var edits: Array[BuildEdit] = []
	for y in range(1, 9):
		for x in range(1, 11):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	grid.apply_batch(edits)
	return grid


func test_a_place_room_edit_carries_its_type_and_rectangle() -> void:
	var data := PlaytestState.edit_data(BuildEdit.place_room(Rect2i(2, 3, 4, 5), &"cafe"))
	assert_dict(data).is_equal(
		{"kind": "PLACE_ROOM", "cell": [2, 3], "room_type": "cafe", "rect": [2, 3, 4, 5]}
	)


func test_a_remove_room_edit_carries_the_room_id_and_no_cell() -> void:
	var data := PlaytestState.edit_data(BuildEdit.remove_room(7))
	assert_dict(data).is_equal({"kind": "REMOVE_ROOM", "room_id": 7})


func test_the_grid_summary_lists_rooms_with_their_status() -> void:
	var grid := _cafe_grid()
	var ready := grid.apply(BuildEdit.place_room(Rect2i(1, 1, 5, 4), &"cafe")).room_id
	grid.apply(BuildEdit.place_object(&"cafe_counter", Vector2i(2, 1), 0))
	grid.apply(BuildEdit.place_object(&"cafe_table", Vector2i(2, 4), 0))
	var bare := grid.apply(BuildEdit.place_room(Rect2i(6, 5, 3, 3), &"cafe")).room_id
	var summary := PlaytestState.grid_summary(grid)
	var expected := [
		{"id": ready, "type": "cafe", "rect": [1, 1, 5, 4], "ready": true, "notes": []},
		{
			"id": bare,
			"type": "cafe",
			"rect": [6, 5, 3, 3],
			"ready": false,
			"notes": ["Needs a counter", "Needs a table"],
		},
	]
	assert_array(summary["rooms"]).is_equal(expected)
	var parsed: Variant = JSON.parse_string(JSON.stringify(summary))
	assert_array((parsed as Dictionary)["rooms"]).has_size(2)


func test_a_grid_with_no_rooms_summarises_an_empty_list() -> void:
	assert_array(PlaytestState.grid_summary(_cafe_grid())["rooms"]).is_empty()
