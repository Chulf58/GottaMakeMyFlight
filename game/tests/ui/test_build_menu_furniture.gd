class_name TestBuildMenuFurniture
extends GdUnitTestSuite
## The 29 furniture pieces across the domain tabs (Facilities, Food & Drink,
## Shops, Decor & Parking): every card shows its name, price and rendered
## thumbnail on the face, with footprint size and daily upkeep in its hover
## popup, and no CardNext paging buttons remain.

var _port: SubViewport
var _mode: BuildMode
var _menu: BuildMenu


func before_test() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1536, 864)
	add_child(_port)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(20, 20)
	_port.add_child(_mode)
	_mode.set_process(false)
	_menu = BuildMenu.new()
	_menu.build_mode = _mode
	_port.add_child(_menu)
	_mode.set_tool(BuildMode.Tool.NONE)


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


func _tool_for(id: StringName) -> BuildMode.Tool:
	for tool in FurnitureTools.OBJECTS:
		if FurnitureTools.OBJECTS[tool] == id:
			return tool
	return BuildMode.Tool.NONE


func test_every_furniture_tool_sits_in_a_domain_tab_with_no_paging_cards() -> void:
	assert_array(_menu.tray().find_children("CardNext", "Button", true, false)).is_empty()
	for tool in FurnitureTools.OBJECTS:
		var cat := BuildMenu.category_of(tool)
		assert_int(cat).is_between(2, 5)
		assert_bool(_menu.category_button(cat).visible).is_true()


func test_every_furniture_card_shows_name_price_thumbnail_and_hover_size() -> void:
	assert_array(BuildMenu.PLACEHOLDER_THUMBNAILS).is_empty()
	for tool in FurnitureTools.OBJECTS:
		_menu.press_category(BuildMenu.category_of(tool))
		var card := _menu.card(tool)
		assert_object(card).override_failure_message("tool %d" % tool).is_not_null()
		var id: StringName = FurnitureTools.OBJECTS[tool]
		var def := BuildCatalog.get_def(id)
		var texts := _texts(card)
		assert_str(BuildMenu.item(tool)[0]).is_not_empty()
		assert_array(texts).contains([BuildMenu.item(tool)[0]])
		assert_array(_hover_texts(tool)).contains(["%dx%d" % [def.size.x, def.size.y]])
		assert_int(BuildMenu.tool_price(tool)).is_equal(PriceTable.price_of_object(id))
		var path := BuildMenu.THUMBNAIL_DIR % BuildMenu.item(tool)[1]
		assert_bool(ResourceLoader.exists(path)).override_failure_message(path).is_true()
		var picture := card.find_children("*", "TextureRect", true, false)[0] as TextureRect
		assert_object(picture.texture).override_failure_message(path).is_not_null()
		assert_int(picture.get_child_count()).is_equal(0)


func test_the_price_slot_of_each_card_reads_its_price_with_a_wallet() -> void:
	var finances := Finances.new()
	add_child(finances)
	var mode := BuildMode.new()
	mode.finances = finances
	_port.add_child(mode)
	mode.set_process(false)
	var menu := BuildMenu.new()
	menu.build_mode = mode
	_port.add_child(menu)
	for tool in FurnitureTools.OBJECTS:
		var texts := _texts(menu.card(tool))
		var price := PriceTable.price_of_object(FurnitureTools.OBJECTS[tool])
		assert_array(texts).override_failure_message("tool %d" % tool).contains([str(price)])
	finances.free()


func test_the_podium_and_the_info_screen_show_their_upkeep_in_hover_popup() -> void:
	var podium_tool := _tool_for(&"prize_podium")
	var info_tool := _tool_for(&"info_screen")
	assert_array(_hover_texts(podium_tool)).contains(
		[BuildMenuCatalog.upkeep_text(PriceTable.PRIZE_CAR_UPKEEP)]
	)
	assert_array(_hover_texts(info_tool)).contains(
		[BuildMenuCatalog.upkeep_text(PriceTable.INFO_SCREEN_UPKEEP)]
	)
	assert_array(_hover_texts(_tool_for(&"bush"))).contains(["Click"])


func test_picking_a_piece_by_tool_opens_its_domain_tab() -> void:
	var tool := _tool_for(&"prize_podium")
	var cat := BuildMenu.category_index("decor")
	_mode.set_tool(tool)
	assert_int(_menu.open_category()).is_equal(cat)
	assert_bool(_menu.card(tool).button_pressed).is_true()
	assert_bool(_menu.category_button(cat).button_pressed).is_true()


func test_remove_still_picks_the_remove_tool_and_has_no_tray() -> void:
	_menu.press_category(BuildMenu.category_index("decor"))
	_menu.press_category(BuildMenu.remove_category())
	assert_int(_mode.tool).is_equal(BuildMode.Tool.REMOVE)
	assert_bool(_menu.is_tray_open()).is_false()
	assert_bool(_menu.category_button(BuildMenu.remove_category()).button_pressed).is_true()
