class_name TestKioskUi
extends GdUnitTestSuite
## The kiosk in the build menu and the room panel (Boredom 2/5; decision
## store-mechanics-draw-a-room-then-furnish-it-required-pieces): a Kiosk tray
## right after Toilets with the Kiosk room tool, the counter and the display
## stand, their prices and placeholder tiles; over a kiosk room the panel
## lists what it still needs, its browse spots and its one spend number.

const KIOSK_TOOLS := [
	BuildMode.Tool.KIOSK_ROOM,
	BuildMode.Tool.KIOSK_COUNTER,
	BuildMode.Tool.KIOSK_DISPLAY,
]

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


func _category_named(category_name: String) -> int:
	var all := BuildMenu.categories()
	for i in all.size():
		if all[i]["name"] == category_name:
			return i
	return BuildMenu.NO_CATEGORY


func _texts(control: Control) -> Array:
	var out := []
	for label in control.find_children("*", "Label", true, false):
		if (label as Label).is_visible_in_tree():
			out.append((label as Label).text)
	return out


func test_the_kiosk_tray_follows_toilets_and_holds_the_room_counter_and_display() -> void:
	var all := BuildMenu.categories()
	var toilets := _category_named("Toilets")
	var kiosk := _category_named("Kiosk")
	assert_int(kiosk).is_equal(toilets + 1)
	assert_array(all[kiosk]["tools"]).is_equal(KIOSK_TOOLS)
	assert_str(_menu.category_button(kiosk + 1).text).is_equal("Baggage")
	assert_str(all[BuildMenu.REMOVE_CATEGORY]["name"]).is_equal("Remove")
	_menu.category_button(kiosk).pressed.emit()
	for tool in KIOSK_TOOLS:
		assert_bool(_menu.card(tool).is_visible_in_tree()).is_true()
		print("tool %d card: %s" % [tool, _texts(_menu.card(tool))])
		var picture := (
			_menu.card(tool).find_children("*", "TextureRect", true, false)[0] as TextureRect
		)
		assert_object(picture.texture).is_null()
	for def_id: StringName in [&"kiosk_counter", &"kiosk_display"]:
		assert_int(PriceTable.price_of_object(def_id)).is_greater(0)
	var counter := BuildMenu.tool_price(BuildMode.Tool.KIOSK_COUNTER)
	assert_int(counter).is_equal(PriceTable.price_of_object(&"kiosk_counter"))
	assert_int(BuildMenu.tool_price(BuildMode.Tool.KIOSK_ROOM)).is_equal(0)
	assert_array(_texts(_menu.card(BuildMode.Tool.KIOSK_ROOM))).contains(["Kiosk", "3x3 min"])


func test_the_room_panel_over_a_kiosk_lists_needs_then_spots_and_spend() -> void:
	var rect := Rect2i(3, 3, 4, 4)
	assert_bool(_mode.grid.apply(BuildEdit.place_room(rect, &"kiosk")).ok).is_true()
	_mode.set_tool(BuildMode.Tool.NONE)
	_mode.update_room_focus(_mode.grid.cell_to_world(Vector2i(4, 4)))
	var empty := _texts(_menu.room_panel())
	print("empty kiosk: %s" % [empty])
	assert_array(empty).contains(["Kiosk", "Needs a kiosk counter", "Needs a display stand"])
	assert_array(empty).contains(["Browse spots 0"])
	for piece: Array in [[&"kiosk_counter", Vector2i(3, 3)], [&"kiosk_display", Vector2i(5, 5)]]:
		assert_bool(_mode.grid.apply(BuildEdit.place_object(piece[0], piece[1], 0)).ok).is_true()
	await get_tree().process_frame
	await get_tree().process_frame
	var ready := _texts(_menu.room_panel())
	print("furnished kiosk: %s" % [ready])
	var spend := "Base spend $%d per visit" % RoomTypes.get_type(&"kiosk").base_spend
	assert_array(ready).contains(["Browse spots 2", spend])
	assert_array(ready).not_contains(["Needs a kiosk counter", "Needs a display stand"])
	assert_array(ready).not_contains(["Seats 2"])
