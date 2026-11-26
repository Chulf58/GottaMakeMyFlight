class_name TestBuildMenuSecurity
extends GdUnitTestSuite
## The security tools in the Operations domain tab: Scanner, 1-click Security
## lane kit, Search table and Confiscation bin in progression order, while the
## 4 loose core lane parts stay hidden from the Build Menu yet mapped in
## BuildMode.TOOL_OBJECTS.

const LANE_TOOLS := [
	BuildMode.Tool.TRAY_TABLE,
	BuildMode.Tool.XRAY_BELT,
	BuildMode.Tool.ARCH,
	BuildMode.Tool.PICKUP_TABLE,
]
const LANE_DEFS := [
	SecurityLanes.TRAY_TABLE,
	SecurityLanes.XRAY_BELT,
	SecurityLanes.ARCH,
	SecurityLanes.PICKUP_TABLE,
]
const SECURITY_MENU_TOOLS := [
	BuildMode.Tool.SCANNER,
	BuildMode.Tool.SECURITY_LANE,
	BuildMode.Tool.SEARCH_TABLE,
	BuildMode.Tool.CONFISCATION_BIN,
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
	_menu = BuildMenu.new()
	_menu.build_mode = _mode
	_port.add_child(_menu)


func after_test() -> void:
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


func test_scanner_and_security_kit_sit_in_progression_order_in_operations() -> void:
	var ops := BuildMenu.category_index("operations")
	var tools: Array = BuildMenu.categories()[ops]["tools"]
	for hidden_tool: BuildMode.Tool in LANE_TOOLS:
		assert_bool(tools.has(hidden_tool)).is_false()
	var i_scanner := tools.find(BuildMode.Tool.SCANNER)
	assert_int(i_scanner).is_greater_equal(0)
	for offset in SECURITY_MENU_TOOLS.size():
		assert_int(tools[i_scanner + offset]).is_equal(SECURITY_MENU_TOOLS[offset])
	assert_int(BuildMenu.remove_category()).is_equal(BuildMenu.REMOVE_CATEGORY)
	assert_str(BuildMenu.categories()[BuildMenu.remove_category()]["name"]).is_equal("Remove")


func test_every_tool_with_a_card_is_in_exactly_one_category() -> void:
	for tool in BuildMenu.ITEMS.keys():
		var count := 0
		for category in BuildMenu.categories():
			if category["tools"].has(tool):
				count += 1
		if BuildMenuCatalog.is_room_only_tool(tool):
			assert_int(count).override_failure_message("room tool %d" % tool).is_equal(0)
			assert_bool(BuildMenuCatalog.room_owners_of(tool).is_empty()).is_false()
		else:
			assert_int(count).override_failure_message("tool %d" % tool).is_equal(1)
	for tool in LANE_TOOLS:
		assert_array(BuildMenuCatalog.item(tool)).is_empty()
		for category in BuildMenu.categories():
			assert_bool(category["tools"].has(tool)).is_false()


func test_each_lane_tool_places_its_part() -> void:
	for i in LANE_TOOLS.size():
		assert_that(BuildMode.TOOL_OBJECTS[LANE_TOOLS[i]]).is_equal(LANE_DEFS[i])


func test_the_security_lane_card_shows_name_price_thumbnail_and_hover_size() -> void:
	var tool := BuildMode.Tool.SECURITY_LANE
	var card := _menu.card(tool)
	assert_object(card).is_not_null()
	assert_array(_texts(card)).contains([BuildMenu.ITEMS[tool][0]])
	assert_array(_hover_texts(tool)).contains(["2x3", "Click"])
	assert_int(BuildMenu.tool_price(tool)).is_equal(SecurityLaneStamp.price())
	assert_bool(BuildMenu.PLACEHOLDER_THUMBNAILS.has(BuildMenu.ITEMS[tool][1])).is_false()
	var picture := card.find_children("*", "TextureRect", true, false)[0] as TextureRect
	assert_object(picture.texture).is_not_null()
	var path := BuildMenu.THUMBNAIL_DIR % BuildMenu.ITEMS[tool][1]
	assert_str(picture.texture.resource_path).is_equal(path)
	assert_int(picture.find_children("*", "ColorRect", true, false).size()).is_equal(0)


func test_picking_a_security_card_picks_its_tool_and_opens_operations() -> void:
	var ops := BuildMenu.category_index("operations")
	for tool in SECURITY_MENU_TOOLS:
		_menu.card(tool).pressed.emit()
		assert_int(_mode.tool).is_equal(tool)
		assert_int(_menu.open_category()).is_equal(ops)
		assert_bool(_menu.card(tool).button_pressed).is_true()


func test_the_operations_tray_fits_its_reserved_space() -> void:
	_menu.category_button(BuildMenu.category_index("operations")).pressed.emit()
	var need := _menu.tray().get_combined_minimum_size()
	assert_float(need.x).is_less_equal(BuildMenu.COLUMN_W)
	assert_float(need.y).is_less_equal(BuildMenu.tray_height_for_rows(2))
	assert_float(need.y).is_equal_approx(_menu.tray_height(), 0.5)
