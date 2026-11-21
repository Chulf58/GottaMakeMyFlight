class_name TestBuildMenuDiningPage
extends GdUnitTestSuite
## The food rooms in the Food & Drink domain tab: bar, restaurant and
## grab-and-go stall rooms sit alongside Cafe and food counters/tables.

const TOOLS := [
	BuildMode.Tool.BAR_ROOM,
	BuildMode.Tool.RESTAURANT_ROOM,
	BuildMode.Tool.STALL_ROOM,
]
const ROOMS := {
	BuildMode.Tool.BAR_ROOM: &"bar",
	BuildMode.Tool.RESTAURANT_ROOM: &"restaurant",
	BuildMode.Tool.STALL_ROOM: &"stall",
}

var _port: SubViewport
var _mode: BuildMode
var _menu: BuildMenu


func before() -> void:
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


func before_test() -> void:
	_mode.set_tool(BuildMode.Tool.NONE)


func after() -> void:
	_port.free()


func _texts(control: Control) -> Array:
	var out := []
	for label in control.find_children("*", "Label", true, false):
		out.append((label as Label).text)
	return out


func _hover_texts(tool: BuildMode.Tool) -> Array:
	var card := _menu.card(tool) as ItemCardButton
	var popup: Control = auto_free(card._make_custom_tooltip(card.tooltip_text))
	return _texts(popup)


func test_food_rooms_live_in_the_food_and_drink_tab() -> void:
	var food := BuildMenu.category_index("food")
	assert_int(food).is_equal(3)
	for tool in TOOLS:
		assert_int(BuildMenu.category_of(tool)).is_equal(food)


func test_the_cards_carry_the_room_names_and_hover_minimum_sizes() -> void:
	_menu.press_category(BuildMenu.category_index("food"))
	for tool in TOOLS:
		var room := RoomTypes.get_type(ROOMS[tool])
		var texts := _texts(_menu.card(tool))
		var hover := _hover_texts(tool)
		assert_str(str(BuildMode.TOOL_ROOMS[tool])).is_equal(str(room.id))
		assert_array(texts).contains([BuildMenu.PRICE_TEXT])
		assert_array(hover).contains(["%dx%d min" % [room.min_size.x, room.min_size.y], "Drag"])
		assert_bool(room.display_name.contains(BuildMenu.item(tool)[0].split("-")[0])).is_true()


func test_every_dining_card_shows_a_real_thumbnail() -> void:
	assert_array(BuildMenu.PLACEHOLDER_THUMBNAILS).is_empty()
	for tool in TOOLS:
		var path := BuildMenu.THUMBNAIL_DIR % BuildMenu.item(tool)[1]
		assert_bool(ResourceLoader.exists(path)).override_failure_message(path).is_true()
		var picture := (
			_menu.card(tool).find_children("*", "TextureRect", true, false)[0] as TextureRect
		)
		assert_object(picture.texture).override_failure_message(path).is_not_null()


func test_the_food_tray_fits_the_column_and_reserved_height() -> void:
	var food := BuildMenu.category_index("food")
	_menu.press_category(food)
	var need := _menu.tray().get_combined_minimum_size()
	assert_float(need.x).is_less_equal(BuildMenu.COLUMN_W)
	assert_float(need.y).is_less_equal(BuildMenu.TRAY_FILTERED_H)
	assert_float(need.y).is_equal_approx(_menu.tray_height(), 0.5)


func test_picking_a_dining_tool_opens_food_and_presses_its_card() -> void:
	var food := BuildMenu.category_index("food")
	for tool in TOOLS:
		_mode.set_tool(tool)
		assert_int(_menu.open_category()).is_equal(food)
		assert_bool(_menu.card(tool).button_pressed).is_true()
