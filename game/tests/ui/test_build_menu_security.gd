class_name TestBuildMenuSecurity
extends GdUnitTestSuite
## The security scanner and lane parts in the Operations domain tab: Scanner
## followed by Tray table, X-ray belt, Arch and Pickup table in flow order,
## each with its rendered thumbnail and 1x1 size in its hover popup.

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


func test_scanner_and_lane_parts_sit_in_flow_order_in_operations() -> void:
	var ops := BuildMenu.category_index("operations")
	var tools: Array = BuildMenu.categories()[ops]["tools"]
	var i_scanner := tools.find(BuildMode.Tool.SCANNER)
	assert_int(i_scanner).is_greater_equal(0)
	for offset in LANE_TOOLS.size():
		assert_int(tools[i_scanner + 1 + offset]).is_equal(LANE_TOOLS[offset])
	assert_int(BuildMenu.remove_category()).is_equal(BuildMenu.REMOVE_CATEGORY)
	assert_str(BuildMenu.categories()[BuildMenu.remove_category()]["name"]).is_equal("Remove")


func test_every_tool_with_a_card_is_in_exactly_one_category() -> void:
	var tools: Array = BuildMenu.ITEMS.keys() + BuildMenu.LANE_ITEMS.keys()
	for tool in tools:
		var count := 0
		for category in BuildMenu.categories():
			if category["tools"].has(tool):
				count += 1
		assert_int(count).override_failure_message("tool %d" % tool).is_equal(1)


func test_each_lane_tool_places_its_part() -> void:
	for i in LANE_TOOLS.size():
		assert_that(BuildMode.TOOL_OBJECTS[LANE_TOOLS[i]]).is_equal(LANE_DEFS[i])


func test_the_lane_cards_show_name_price_thumbnail_and_hover_size() -> void:
	for tool in LANE_TOOLS:
		var card := _menu.card(tool)
		assert_object(card).override_failure_message("tool %d" % tool).is_not_null()
		assert_array(_texts(card)).contains([BuildMenu.LANE_ITEMS[tool][0]])
		assert_array(_hover_texts(tool)).contains(["1x1", "Click"])
		var price := PriceTable.price_of_object(BuildMode.TOOL_OBJECTS[tool])
		assert_int(BuildMenu.tool_price(tool)).is_equal(price)
		assert_bool(BuildMenu.PLACEHOLDER_THUMBNAILS.has(BuildMenu.LANE_ITEMS[tool][1])).is_false()
		var picture := card.find_children("*", "TextureRect", true, false)[0] as TextureRect
		assert_object(picture.texture).override_failure_message("tool %d" % tool).is_not_null()
		var path := BuildMenu.THUMBNAIL_DIR % BuildMenu.LANE_ITEMS[tool][1]
		assert_str(picture.texture.resource_path).is_equal(path)
		assert_int(picture.find_children("*", "ColorRect", true, false).size()).is_equal(0)


func test_picking_a_lane_card_picks_its_tool_and_opens_operations() -> void:
	var ops := BuildMenu.category_index("operations")
	for tool in LANE_TOOLS:
		_menu.card(tool).pressed.emit()
		assert_int(_mode.tool).is_equal(tool)
		assert_int(_menu.open_category()).is_equal(ops)
		assert_bool(_menu.card(tool).button_pressed).is_true()


func test_the_operations_tray_fits_its_reserved_space() -> void:
	_menu.category_button(BuildMenu.category_index("operations")).pressed.emit()
	var need := _menu.tray().get_combined_minimum_size()
	assert_float(need.x).is_less_equal(BuildMenu.COLUMN_W)
	assert_float(need.y).is_less_equal(BuildMenu.TRAY_H)
