class_name TestBuildMenuToilets
extends GdUnitTestSuite
## The toilet in the build menu (Toilets 5/5): a Toilets tray right after
## Shops holding the Toilet room tool, the toilet stall and the sink, with
## their prices, the stall's daily upkeep as its hint, the rendered stall and
## sink thumbnails and the room's placeholder tile.

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


func _category_named(category_name: String) -> int:
	var all := BuildMenu.categories()
	for i in all.size():
		if all[i]["name"] == category_name:
			return i
	return BuildMenu.NO_CATEGORY


func _texts(control: Control) -> Array:
	var out := []
	for label in control.find_children("*", "Label", true, false):
		out.append((label as Label).text)
	return out


func _picture(tool: BuildMode.Tool) -> TextureRect:
	return _menu.card(tool).find_children("*", "TextureRect", true, false)[0] as TextureRect


func test_the_toilets_tray_follows_shops_and_holds_the_room_stall_and_sink() -> void:
	var all := BuildMenu.categories()
	var shops := _category_named("Shops")
	var toilets := _category_named("Toilets")
	print("shops %d toilets %d remove %d" % [shops, toilets, BuildMenu.remove_category()])
	assert_int(toilets).is_equal(shops + 1)
	assert_array(all[toilets]["tools"]).is_equal(TOILET_TOOLS)
	assert_str(_menu.category_button(toilets).text).is_equal("Toilets")
	assert_str(_menu.category_button(toilets + 1).text).is_equal("Kiosk")
	assert_int(BuildMenu.remove_category()).is_equal(BuildMenu.REMOVE_CATEGORY)
	assert_str(all[BuildMenu.REMOVE_CATEGORY]["name"]).is_equal("Remove")


func test_the_toilet_cards_show_name_size_price_and_hint() -> void:
	_menu.category_button(_category_named("Toilets")).pressed.emit()
	for tool in TOILET_TOOLS:
		assert_bool(_menu.card(tool).is_visible_in_tree()).is_true()
		print("tool %d card: %s" % [tool, _texts(_menu.card(tool))])
	var stall_price := PriceTable.price_of_object(&"toilet_stall")
	var sink_price := PriceTable.price_of_object(&"toilet_sink")
	assert_int(stall_price).is_greater(0)
	assert_int(sink_price).is_greater(0)
	assert_int(BuildMenu.tool_price(BuildMode.Tool.TOILET_STALL)).is_equal(stall_price)
	assert_int(BuildMenu.tool_price(BuildMode.Tool.TOILET_SINK)).is_equal(sink_price)
	assert_int(BuildMenu.tool_price(BuildMode.Tool.TOILET_ROOM)).is_equal(0)
	var upkeep := "Upkeep %d/day" % PriceTable.TOILET_STALL_UPKEEP
	assert_array(_texts(_menu.card(BuildMode.Tool.TOILET_ROOM))).is_equal(
		["Toilet", "2x3 min", BuildMenu.PRICE_TEXT, "Click"]
	)
	assert_array(_texts(_menu.card(BuildMode.Tool.TOILET_STALL))).is_equal(
		["Toilet stall", "1x2", BuildMenu.PRICE_TEXT, upkeep]
	)
	assert_array(_texts(_menu.card(BuildMode.Tool.TOILET_SINK))).is_equal(
		["Sink", "1x1", BuildMenu.PRICE_TEXT, "Click"]
	)


func test_the_upkeep_hint_is_in_the_plain_hint_style() -> void:
	var upkeep := "Upkeep %d/day" % PriceTable.TOILET_STALL_UPKEEP
	var found: Label = null
	for label in _menu.card(BuildMode.Tool.TOILET_STALL).find_children("*", "Label", true, false):
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
	print(
		(
			"stall %s sink %s room %s"
			% [
				menu.card_price_text(BuildMode.Tool.TOILET_STALL),
				menu.card_price_text(BuildMode.Tool.TOILET_SINK),
				menu.card_price_text(BuildMode.Tool.TOILET_ROOM),
			]
		)
	)
	assert_str(menu.card_price_text(BuildMode.Tool.TOILET_STALL)).is_equal(stall)
	assert_str(menu.card_price_text(BuildMode.Tool.TOILET_SINK)).is_equal(sink)
	assert_str(menu.card_price_text(BuildMode.Tool.TOILET_ROOM)).is_equal(BuildMenu.PRICE_TEXT)
	port.free()


func test_the_stall_and_sink_cards_use_their_rendered_thumbnails() -> void:
	for tool in [BuildMode.Tool.TOILET_STALL, BuildMode.Tool.TOILET_SINK]:
		var name: String = BuildMenu.item(tool)[1]
		assert_bool(BuildMenu.PLACEHOLDER_THUMBNAILS.has(name)).is_false()
		var picture := _picture(tool)
		assert_object(picture.texture).override_failure_message(name).is_not_null()
		assert_str(picture.texture.resource_path).is_equal(BuildMenu.THUMBNAIL_DIR % name)
		assert_int(picture.find_children("*", "ColorRect", true, false).size()).is_equal(0)
	# The room has no rendered picture yet: the plain tile, like the cafe room.
	var room := _picture(BuildMode.Tool.TOILET_ROOM)
	assert_object(room.texture).is_null()
	assert_int(room.find_children("*", "ColorRect", true, false).size()).is_equal(1)


func test_picking_a_toilet_card_picks_its_tool_and_opens_the_toilets_tray() -> void:
	for tool in TOILET_TOOLS:
		_menu.card(tool).pressed.emit()
		assert_int(_mode.tool).is_equal(tool)
		assert_int(_menu.open_category()).is_equal(_category_named("Toilets"))
		assert_bool(_menu.card(tool).button_pressed).is_true()


func test_the_toilets_tray_fits_its_reserved_space_and_the_bar_fits_the_screen() -> void:
	_menu.category_button(_category_named("Toilets")).pressed.emit()
	var need := _menu.tray().get_combined_minimum_size()
	var bar := _menu.bar().get_combined_minimum_size()
	# The game's layout width: 1920 px at the 1.25 UI scale (project.godot).
	var layout_w := 1920.0 / 1.25
	print("toilets tray needs %s, bar needs %s of %.0f" % [need, bar, layout_w])
	assert_float(need.x).is_less_equal(BuildMenu.COLUMN_W)
	assert_float(need.y).is_less_equal(BuildMenu.TRAY_H)
	assert_float(bar.x).is_less_equal(layout_w - 2.0 * BuildMenu.MARGIN)
