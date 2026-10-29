class_name TestRoomPanelToilet
extends GdUnitTestSuite
## The room panel over a toilet (Toilets 5/5; decision toilet-design-queue-
## free-reservable-stalls-per-stall-daily-u, point 2): the stalls, the sinks
## and the upkeep per day as one room total, never seats and base spend.

var _port: SubViewport
var _mode: BuildMode
var _menu: BuildMenu


func before_test() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(20, 20)
	_port.add_child(_mode)
	_mode.set_process(false)
	_menu = BuildMenu.new()
	_menu.build_mode = _mode
	_port.add_child(_menu)
	var edits: Array[BuildEdit] = []
	for y in range(2, 12):
		for x in range(2, 14):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	_mode.grid.apply_batch(edits)


func after_test() -> void:
	_port.free()


func _texts() -> Array:
	var out := []
	for label in _menu.room_panel().find_children("*", "Label", true, false):
		if (label as Label).is_visible_in_tree():
			out.append((label as Label).text)
	return out


## A 4x3 toilet room at (3, 3) with the pointer over it.
func _toilet() -> int:
	var room_id := _mode.grid.apply(BuildEdit.place_room(Rect2i(3, 3, 4, 3), &"toilet")).room_id
	_mode.set_tool(BuildMode.Tool.NONE)
	_mode.update_room_focus(_mode.grid.cell_to_world(Vector2i(4, 4)))
	return room_id


func _place(def_id: StringName, anchor: Vector2i) -> void:
	assert_bool(_mode.grid.apply(BuildEdit.place_object(def_id, anchor, 0)).ok).is_true()


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func test_an_empty_toilet_lists_what_it_needs_and_its_counts() -> void:
	var room_id := _toilet()
	assert_bool(_menu.room_panel().visible).is_true()
	assert_int(_menu.room_panel().room_id()).is_equal(room_id)
	var texts := _texts()
	print(texts)
	(
		assert_array(texts)
		. contains(
			[
				"Toilet",
				"Needs a toilet stall",
				"Needs a sink",
				"Stalls 0",
				"Sinks 0",
				"Upkeep $0 per day once ready",
			]
		)
	)
	for text: String in texts:
		assert_str(text).not_contains("Seats")
		assert_str(text).not_contains("Base spend")


func test_a_ready_toilet_shows_its_upkeep_as_one_room_total() -> void:
	var room_id := _toilet()
	_place(&"toilet_stall", Vector2i(3, 3))
	_place(&"toilet_stall", Vector2i(4, 3))
	_place(&"toilet_sink", Vector2i(6, 3))
	await _settle()
	var texts := _texts()
	print(texts)
	var total := RoomRules.daily_upkeep(_mode.grid, room_id)
	assert_int(total).is_equal(2 * PriceTable.TOILET_STALL_UPKEEP)
	assert_array(texts).contains(
		["Toilet", "Ready", "Stalls 2", "Sinks 1", "Upkeep $%d per day" % total]
	)
	assert_array(texts).not_contains(["Upkeep $%d per day once ready" % total])


func test_a_toilet_not_ready_shows_the_upkeep_it_will_cost() -> void:
	var room_id := _toilet()
	_place(&"toilet_stall", Vector2i(3, 3))
	await _settle()
	var texts := _texts()
	print(texts)
	# Not ready (no sink): nothing is charged yet, and the panel says what will be.
	assert_int(RoomRules.daily_upkeep(_mode.grid, room_id)).is_equal(0)
	var once := "Upkeep $%d per day once ready" % PriceTable.TOILET_STALL_UPKEEP
	assert_array(texts).contains(["Needs a sink", "Stalls 1", "Sinks 0", once])
