class_name TestBuildMenuSecurity
extends GdUnitTestSuite
## The security lane parts in the build menu (decision security-lane-parts-
## are-placed-separately-tray-table-x-ray-b): a Lane tray right after
## Security holding the four parts in flow order, each with a placeholder
## tile until its thumbnail is rendered, and a build tool per part.

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
	SecurityLanes.PICKUP_TABLE
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


func _category_named(category_name: String) -> int:
	for i in BuildMenu.CATEGORIES.size():
		if BuildMenu.CATEGORIES[i]["name"] == category_name:
			return i
	return BuildMenu.NO_CATEGORY


func _texts(control: Control) -> Array:
	var out := []
	for label in control.find_children("*", "Label", true, false):
		out.append((label as Label).text)
	return out


func test_the_lane_tray_follows_security_and_security_keeps_the_scanner() -> void:
	var security := _category_named("Security")
	var lane := _category_named("Lane")
	assert_int(lane).is_equal(security + 1)
	assert_array(BuildMenu.CATEGORIES[security]["tools"]).is_equal([BuildMode.Tool.SCANNER])
	assert_array(BuildMenu.CATEGORIES[lane]["tools"]).is_equal(LANE_TOOLS)
	assert_str(BuildMenu.CATEGORIES[BuildMenu.REMOVE_CATEGORY]["name"]).is_equal("Remove")


func test_each_lane_tool_places_its_part() -> void:
	for i in LANE_TOOLS.size():
		assert_that(BuildMode.TOOL_OBJECTS[LANE_TOOLS[i]]).is_equal(LANE_DEFS[i])


func test_the_lane_cards_show_size_price_and_a_placeholder_tile() -> void:
	for tool in LANE_TOOLS:
		var card := _menu.card(tool)
		assert_object(card).override_failure_message("tool %d" % tool).is_not_null()
		var texts := _texts(card)
		print("tool %d card: %s" % [tool, texts])
		assert_array(texts).contains([BuildMenu.ITEMS[tool][0], "1x1"])
		var price := PriceTable.price_of_object(BuildMode.TOOL_OBJECTS[tool])
		assert_int(BuildMenu.tool_price(tool)).is_equal(price)
		assert_bool(BuildMenu.PLACEHOLDER_THUMBNAILS.has(BuildMenu.ITEMS[tool][1])).is_true()
		var picture := card.find_children("*", "TextureRect", true, false)[0] as TextureRect
		assert_int(picture.find_children("*", "ColorRect", true, false).size()).is_equal(1)


func test_picking_a_lane_card_picks_its_tool_and_opens_the_lane_tray() -> void:
	for tool in LANE_TOOLS:
		_menu.card(tool).pressed.emit()
		assert_int(_mode.tool).is_equal(tool)
		assert_int(_menu.open_category()).is_equal(_category_named("Lane"))
		assert_bool(_menu.card(tool).button_pressed).is_true()
