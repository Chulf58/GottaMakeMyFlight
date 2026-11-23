class_name TestBaggagePortOverlay
extends GdUnitTestSuite
## 3D belt-port connection overlay (ruling 1b70fa33): visible only when BELT or
## BAG_ROOM tool is active or a Bag Room is selected, highlighting check-in
## desk outlets (green=connected, amber=unconnected) and bag room belt ends.

var _port: SubViewport
var _mode: BuildMode
var _selection: BuiltSelection
var _overlay: BaggagePortOverlay


func before_test() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(20, 20)
	_port.add_child(_mode)
	_mode.set_process(false)
	var edits: Array[BuildEdit] = []
	for y in range(2, 14):
		for x in range(2, 16):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	_mode.grid.apply_batch(edits)
	_selection = BuiltSelection.new()
	_overlay = _mode.get_node("RoomView/BaggagePortOverlay") as BaggagePortOverlay
	_overlay.selection = _selection


func after_test() -> void:
	_port.free()


func test_overlay_is_hidden_outside_belt_bag_room_and_bag_room_selection() -> void:
	var bag_room := _mode.grid.apply(BuildEdit.place_room(Rect2i(10, 3, 3, 3), &"bag_room")).room_id
	var cafe_room := _mode.grid.apply(BuildEdit.place_room(Rect2i(3, 3, 4, 4), &"cafe")).room_id
	PassengerTestWorld.place(_mode.grid, &"checkin_desk", Vector2i(3, 10), 0)
	PassengerTestWorld.place(_mode.grid, &"baggage_belt_end", Vector2i(10, 4), 0)

	_mode.set_tool(BuildMode.Tool.NONE)
	_overlay.refresh()
	assert_bool(_overlay.is_active()).is_false()
	assert_array(_overlay.markers()).is_empty()

	_mode.set_tool(BuildMode.Tool.WALL)
	_overlay.refresh()
	assert_bool(_overlay.is_active()).is_false()

	_mode.set_tool(BuildMode.Tool.BELT)
	_overlay.refresh()
	assert_bool(_overlay.is_active()).is_true()
	assert_int(_overlay.markers().size()).is_equal(2)

	_mode.set_tool(BuildMode.Tool.BAG_ROOM)
	_overlay.refresh()
	assert_bool(_overlay.is_active()).is_true()

	_mode.set_tool(BuildMode.Tool.NONE)
	_selection.kind = BuiltSelection.Kind.ROOM
	_selection.id = cafe_room
	_overlay.refresh()
	assert_bool(_overlay.is_active()).is_false()

	_selection.id = bag_room
	_overlay.refresh()
	assert_bool(_overlay.is_active()).is_true()

	_selection.clear()
	_overlay.refresh()
	assert_bool(_overlay.is_active()).is_false()


func test_overlay_colors_connected_desk_and_end_green_and_unconnected_amber() -> void:
	_mode.grid.apply(BuildEdit.place_room(Rect2i(10, 4, 3, 3), &"bag_room"))
	var desk1 := PassengerTestWorld.place(_mode.grid, &"checkin_desk", Vector2i(3, 9), 0)
	var desk2 := PassengerTestWorld.place(_mode.grid, &"checkin_desk", Vector2i(6, 9), 0)
	var seg1 := BeltShaper.plan_line(_mode.grid, Vector2i(4, 8), Vector2i(4, 5), 0)
	assert_bool(seg1.result.ok).is_true()
	_mode.grid.apply_batch(seg1.edits)
	var seg2 := BeltShaper.plan_line(_mode.grid, Vector2i(4, 5), Vector2i(10, 5), 0)
	assert_bool(seg2.result.ok).is_true()
	_mode.grid.apply_batch(seg2.edits)

	_mode.set_tool(BuildMode.Tool.BELT)
	_overlay.refresh()
	assert_bool(_overlay.is_active()).is_true()

	var by_obj := {}
	for m in _overlay.markers():
		by_obj[m["object_id"]] = m
	assert_bool(by_obj.has(desk1)).is_true()
	assert_bool(by_obj.has(desk2)).is_true()
	assert_bool(by_obj[desk1]["connected"]).is_true()
	assert_that(by_obj[desk1]["color"]).is_equal(BaggagePortOverlay.CONNECTED_COLOR)
	assert_bool(by_obj[desk2]["connected"]).is_false()
	assert_that(by_obj[desk2]["color"]).is_equal(BaggagePortOverlay.UNCONNECTED_COLOR)

	var end_id := _mode.grid.object_at(Vector2i(10, 5))
	assert_bool(by_obj.has(end_id)).is_true()
	assert_str(String(by_obj[end_id]["kind"])).is_equal("belt_end")
	assert_bool(by_obj[end_id]["connected"]).is_true()
	assert_that(by_obj[end_id]["color"]).is_equal(BaggagePortOverlay.CONNECTED_COLOR)
	var ring := _overlay.get_node("BeltEndMarker_%d" % end_id) as MeshInstance3D
	var end_arrow := _overlay.get_node("BeltEndArrow_%d" % end_id) as MeshInstance3D
	(
		assert_float(
			Vector2(ring.position.x, ring.position.z).distance_to(
				Vector2(end_arrow.position.x, end_arrow.position.z)
			)
		)
		. is_less(1.0)
	)
