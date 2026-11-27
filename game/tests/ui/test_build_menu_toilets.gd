class_name TestBuildMenuToilets
extends GdUnitTestSuite
## The toilet tools in the Facilities domain tab and contextual room tray:
## Facilities leads with standalone items before rooms, while Toilet, Toilet
## stall and Sink carry their prices, rendered thumbnails, and hover popup
## sizes and daily upkeep.

const TOILET_TOOLS := [
	BuildMode.Tool.TOILET_ROOM,
	BuildMode.Tool.TOILET_STALL,
	BuildMode.Tool.TOILET_SINK,
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


func after_test() -> void:
	_port.free()


func _texts(control: Control) -> Array:
	var out := []
	for label in control.find_children("*", "Label", true, false):
		out.append((label as Label).text)
	return out


func _hover(tool: BuildMode.Tool) -> Control:
	var card := _menu.card(tool) as ItemCardButton
	return auto_free(card._make_custom_tooltip(card.tooltip_text))


func _picture(tool: BuildMode.Tool) -> TextureRect:
	return _menu.card(tool).find_children("*", "TextureRect", true, false)[0] as TextureRect


func test_toilet_tools_sit_in_the_facilities_tab_and_room_context() -> void:
	var facilities := BuildMenu.category_index("facilities")
	assert_int(facilities).is_equal(2)
	var tools: Array = BuildMenu.categories()[facilities]["tools"]
	assert_bool(tools.has(BuildMode.Tool.TOILET_ROOM)).is_true()
	assert_bool(BuildMenuCatalog.is_room_tool(BuildMode.Tool.TOILET_ROOM)).is_true()
	assert_array(BuildMenuCatalog.ROOM_TOOLS[&"toilet"]).is_equal(
		[BuildMode.Tool.TOILET_STALL, BuildMode.Tool.TOILET_SINK]
	)
	assert_str(_menu.category_button(facilities).tooltip_text).is_equal("Facilities")
	assert_int(BuildMenu.remove_category()).is_equal(BuildMenu.REMOVE_CATEGORY)


func test_the_toilet_cards_show_name_and_price_with_size_and_upkeep_in_hover() -> void:
	_menu.category_button(BuildMenu.category_index("facilities")).pressed.emit()
	assert_bool(_menu.card(BuildMode.Tool.TOILET_ROOM).is_visible_in_tree()).is_true()
	assert_bool(_menu.card(BuildMode.Tool.TOILET_STALL).is_visible_in_tree()).is_false()
	assert_bool(_menu.card(BuildMode.Tool.TOILET_SINK).is_visible_in_tree()).is_false()
	_menu.enter_room_context(&"toilet")
	for tool in TOILET_TOOLS:
		assert_bool(_menu.card(tool).is_visible_in_tree()).is_true()
	var stall_price := PriceTable.price_of_object(&"toilet_stall")
	var sink_price := PriceTable.price_of_object(&"toilet_sink")
	assert_int(stall_price).is_greater(0)
	assert_int(sink_price).is_greater(0)
	assert_int(BuildMenu.tool_price(BuildMode.Tool.TOILET_STALL)).is_equal(stall_price)
	assert_int(BuildMenu.tool_price(BuildMode.Tool.TOILET_SINK)).is_equal(sink_price)
	assert_int(BuildMenu.tool_price(BuildMode.Tool.TOILET_ROOM)).is_equal(0)
	var upkeep := "Upkeep %d/day" % PriceTable.TOILET_STALL_UPKEEP
	assert_array(_texts(_menu.card(BuildMode.Tool.TOILET_ROOM))).is_equal(
		["Toilet", BuildMenu.PRICE_TEXT, "Room"]
	)
	assert_array(_texts(_menu.card(BuildMode.Tool.TOILET_STALL))).is_equal(
		["Toilet stall", BuildMenu.PRICE_TEXT, "★"]
	)
	assert_array(_texts(_menu.card(BuildMode.Tool.TOILET_SINK))).is_equal(
		["Sink", BuildMenu.PRICE_TEXT, "★"]
	)
	assert_array(_texts(_hover(BuildMode.Tool.TOILET_ROOM))).contains(["2x3 min", "Drag"])
	assert_array(_texts(_hover(BuildMode.Tool.TOILET_STALL))).contains(["1x2", "Click", upkeep])
	assert_array(_texts(_hover(BuildMode.Tool.TOILET_SINK))).contains(["1x1", "Click"])


func test_the_upkeep_chip_in_hover_is_in_the_plain_hint_style() -> void:
	var upkeep := "Upkeep %d/day" % PriceTable.TOILET_STALL_UPKEEP
	var popup := _hover(BuildMode.Tool.TOILET_STALL)
	var found: Label = null
	for label in popup.find_children("*", "Label", true, false):
		if (label as Label).text == upkeep:
			found = label
	assert_object(found).is_not_null()
	assert_str(String(found.theme_type_variation)).is_equal("HudHint")


func test_with_a_wallet_the_stall_and_sink_cards_show_their_prices() -> void:
	var port := SubViewport.new()
	add_child(port)
	var finances := Finances.new()
	port.add_child(finances)
	assert_bool(finances.wallet.from_snapshot({"balance": "5000"})).is_true()
	var mode := BuildMode.new()
	mode.grid_size = Vector2i(8, 8)
	mode.finances = finances
	port.add_child(mode)
	mode.set_process(false)
	var menu := BuildMenu.new()
	menu.build_mode = mode
	port.add_child(menu)
	var stall := str(PriceTable.price_of_object(&"toilet_stall"))
	var sink := str(PriceTable.price_of_object(&"toilet_sink"))
	assert_str(menu.card_price_text(BuildMode.Tool.TOILET_STALL)).is_equal(stall)
	assert_str(menu.card_price_text(BuildMode.Tool.TOILET_SINK)).is_equal(sink)
	assert_str(menu.card_price_text(BuildMode.Tool.TOILET_ROOM)).is_equal(BuildMenu.PRICE_TEXT)
	port.free()


func test_the_room_stall_and_sink_cards_use_their_rendered_thumbnails() -> void:
	for tool in TOILET_TOOLS:
		var thumb_name: String = BuildMenu.item(tool)[1]
		assert_bool(BuildMenu.PLACEHOLDER_THUMBNAILS.has(thumb_name)).is_false()
		var picture := _picture(tool)
		assert_object(picture.texture).override_failure_message(thumb_name).is_not_null()
		assert_str(picture.texture.resource_path).is_equal(BuildMenu.THUMBNAIL_DIR % thumb_name)
		assert_int(picture.find_children("*", "ColorRect", true, false).size()).is_equal(0)


func test_picking_a_toilet_card_picks_its_tool_and_opens_facilities() -> void:
	for tool in TOILET_TOOLS:
		_menu.enter_room_context(&"toilet")
		_menu.card(tool).pressed.emit()
		assert_int(_mode.tool).is_equal(tool)
		assert_bool(_menu.is_room_context()).is_true()
		assert_str(String(_menu.room_context_type())).is_equal("toilet")
		assert_bool(_menu.card(tool).button_pressed).is_true()


func test_the_facilities_tray_fits_its_reserved_space_and_the_bar_fits_the_screen() -> void:
	_menu.category_button(BuildMenu.category_index("facilities")).pressed.emit()
	var need := _menu.tray().get_combined_minimum_size()
	var bar := _menu.bar().get_combined_minimum_size()
	var layout_w := 1920.0 / 1.25
	assert_float(need.x).is_less_equal(BuildMenu.COLUMN_W)
	assert_float(need.y).is_less_equal(BuildMenu.tray_height_for_rows(3))
	assert_float(need.y).is_equal_approx(_menu.tray_height(), 0.5)
	assert_float(bar.x).is_less_equal(layout_w - 2.0 * BuildMenu.MARGIN)
