class_name TestBuildMenuItemInfo
extends GdUnitTestSuite
## The hover card on every build tray item (decisions build-menu-items-show-a-
## hover-card-with-a-description and build-menu-rework-six-domain-tabs-
## progress-tab-and-card-u): all 76 menu tools have a 3-part ItemInfo and render a
## non-empty 280 px custom tooltip popup with footprint size, Click/Drag,
## upkeep/needs, description, and live lock requirement.

const UI_SCALE := 1.25

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
	_menu.scale = Vector2.ONE * UI_SCALE
	_port.add_child(_menu)
	_mode.set_tool(BuildMode.Tool.NONE)


func after() -> void:
	_port.free()


func _tray_tools() -> Array:
	return BuildMenuCatalog.all_catalog_tools()


func _card_for(tool: BuildMode.Tool) -> ItemCardButton:
	if BuildMenuCatalog.is_room_only_tool(tool):
		_menu.enter_room_context(BuildMenuCatalog.room_owners_of(tool)[0])
	else:
		for i in BuildMenu.categories().size():
			if BuildMenu.categories()[i]["tools"].has(tool):
				if _menu.open_category() != i:
					_menu.press_category(i)
				break
	return _menu.card(tool) as ItemCardButton


func _texts(control: Control) -> Array:
	var out := []
	for label in control.find_children("*", "Label", true, false):
		out.append((label as Label).text)
	return out


func test_every_tray_item_has_a_three_part_description() -> void:
	var tools := _tray_tools()
	var checked := 0
	for tool in tools:
		var info := ItemInfo.of(tool)
		assert_int(info.size()).is_equal(3)
		for part in info:
			assert_str(part).is_not_empty()
		checked += 1
	assert_int(checked).is_equal(81)


func test_every_description_belongs_to_a_tray_item() -> void:
	var tools := _tray_tools()
	for tool in ItemInfo.tools():
		assert_bool(tools.has(tool)).is_true()
	assert_int(ItemInfo.tools().size()).is_equal(81)


func test_all_79_tools_produce_a_hover_card_with_details_and_three_parts() -> void:
	var checked := 0
	for tool in _tray_tools():
		var card := _card_for(tool)
		assert_object(card).is_not_null()
		var info := ItemInfo.of(tool)
		assert_str(card.tooltip_text).is_not_empty()
		var shown := card._make_custom_tooltip(card.tooltip_text) as Control
		assert_object(shown).is_not_null()
		var texts := _texts(shown)
		assert_array(texts).contains([BuildMenu.item(tool)[0], info[0], info[1], info[2]])
		assert_array(texts).contains([ItemCardButton.HOW_HEADING, ItemCardButton.NEEDS_HEADING])
		var footprint := BuildMenuCatalog.size_text(tool)
		if footprint != "":
			assert_array(texts).contains([footprint])
		assert_array(texts).contains([BuildMenuCatalog.no_key_hint(tool)])
		var upkeep := BuildMenuCatalog.running_cost(tool)
		if upkeep > 0:
			assert_array(texts).contains([BuildMenuCatalog.upkeep_text(upkeep)])
		if BuildMenuCatalog.CARD_NEEDS.has(tool):
			assert_array(texts).contains([BuildMenuCatalog.CARD_NEEDS[tool]])
		shown.free()
		checked += 1
	assert_int(checked).is_equal(81)


func test_hover_card_renders_when_only_details_or_partial_info_exist() -> void:
	var details_only: ItemCardButton = auto_free(ItemCardButton.new())
	details_only.set_info("Custom", [], [["2x1", &"HudHint"], ["Click", &"HudHint"]])
	assert_str(details_only.tooltip_text).is_not_empty()
	var popup: Control = auto_free(details_only._make_custom_tooltip(details_only.tooltip_text))
	assert_object(popup).is_not_null()
	assert_array(_texts(popup)).contains(["Custom", "2x1", "Click"])


func test_hover_card_is_in_the_hud_theme_and_shows_only_on_hover() -> void:
	var card := _card_for(BuildMode.Tool.DESK)
	var shown := card._make_custom_tooltip(card.tooltip_text) as Control
	assert_object(shown.theme).is_same(BuildMenu.HUD_THEME)
	assert_array(_texts(card)).not_contains([ItemInfo.of(BuildMode.Tool.DESK)[0]])
	shown.free()


func _shown_in_popup(card: ItemCardButton) -> PopupPanel:
	var popup := PopupPanel.new()
	add_child(popup)
	auto_free(popup)
	popup.add_child(card._make_custom_tooltip(card.tooltip_text))
	await get_tree().process_frame
	await get_tree().process_frame
	return popup


func test_the_real_tooltip_path_places_the_popup_in_lower_right_corner() -> void:
	var card := _card_for(BuildMode.Tool.DESK)
	await await_idle_frame()
	var transform := card.get_screen_transform()
	assert_float(transform.get_scale().y).is_equal_approx(UI_SCALE, 0.001)
	var popup := await _shown_in_popup(card)
	assert_int(popup.size.y).is_greater(0)
	var popup_rect := Rect2(Vector2(popup.position), Vector2(popup.size))
	var screen := Rect2(Vector2.ZERO, Vector2(_port.size))
	var tray_rect := _menu.get_transform() * _menu.tray().get_global_rect()
	assert_bool(screen.encloses(popup_rect)).is_true()
	assert_int(popup.position.x + popup.size.x).is_equal(_port.size.x - HudLayout.MARGIN)
	assert_bool(_menu.is_tray_open()).is_true()
	assert_bool(popup_rect.intersects(tray_rect)).is_false()
	var item_rect := Rect2(transform.origin, card.size * UI_SCALE)
	assert_bool(popup_rect.intersects(item_rect)).is_false()


func test_the_popup_stays_inside_the_window_sideways() -> void:
	var card := _card_for(BuildMode.Tool.DESK)
	await await_idle_frame()
	var wide := Vector2(float(_port.size.x) + 400.0, 100.0)
	assert_int(card.card_screen_position(wide).x).is_equal(0)
	var narrow := card.card_screen_position(Vector2(100.0, 100.0))
	assert_int(narrow.x).is_equal(_port.size.x - HudLayout.MARGIN - 100)
	assert_int(narrow.y).is_less_equal(_port.size.y - HudLayout.MARGIN - 100)


func test_lower_right_popup_clears_tray_and_stacks_above_right_floor_inspect_cards() -> void:
	var port: SubViewport = auto_free(SubViewport.new())
	port.size = Vector2i(1536, 864)
	add_child(port)
	var mode := BuildMode.new()
	mode.grid_size = Vector2i(20, 20)
	port.add_child(mode)
	mode.set_process(false)
	var menu := BuildMenu.new()
	menu.build_mode = mode
	port.add_child(menu)
	mode.set_tool(BuildMode.Tool.NONE)
	menu.press_category(1)
	await get_tree().process_frame
	await get_tree().process_frame

	var card := menu.card(BuildMode.Tool.DESK) as ItemCardButton
	var card_sz := Vector2(304.0, 220.0)
	var pos := Vector2(card.card_screen_position(card_sz))
	var tip_rect := Rect2(pos, card_sz)
	assert_float(tip_rect.end.x).is_equal_approx(float(1536 - HudLayout.MARGIN), 1.0)
	assert_float(tip_rect.end.y).is_equal_approx(float(864 - HudLayout.MARGIN), 1.0)
	assert_bool(tip_rect.intersects(menu.tray().get_global_rect())).is_false()
	assert_bool(tip_rect.intersects(menu.bar().get_global_rect())).is_false()

	# When a RIGHT_FLOOR_GROUP inspect card is visible bottom-right, tooltip stacks above it.
	var inspect := PanelContainer.new()
	inspect.add_to_group(BottomDocks.RIGHT_FLOOR_GROUP)
	inspect.position = Vector2(float(1536 - HudLayout.MARGIN) - HudLayout.RAIL_W, 560.0)
	inspect.size = Vector2(HudLayout.RAIL_W, 288.0)
	port.add_child(inspect)
	await get_tree().process_frame

	var stacked_pos := Vector2(card.card_screen_position(card_sz))
	var stacked_rect := Rect2(stacked_pos, card_sz)
	assert_float(stacked_rect.end.x).is_equal_approx(float(1536 - HudLayout.MARGIN), 1.0)
	assert_float(stacked_rect.end.y).is_less_equal(
		inspect.get_global_rect().position.y - float(HudLayout.GAP) + 1.0
	)
	assert_bool(stacked_rect.intersects(inspect.get_global_rect())).is_false()

	# TemplatesPage ItemCardButton also docks in the lower-right corner.
	menu.press_category(BuildMenu.TEMPLATES_PAGE)
	await get_tree().process_frame
	var save_card := menu.templates_page.save_card() as ItemCardButton
	var tpl_rect := Rect2(Vector2(save_card.card_screen_position(card_sz)), card_sz)
	assert_float(tpl_rect.end.x).is_equal_approx(float(1536 - HudLayout.MARGIN), 1.0)
	assert_bool(tpl_rect.intersects(inspect.get_global_rect())).is_false()
	assert_bool(tpl_rect.intersects(menu.tray().get_global_rect())).is_false()


func test_an_item_with_no_info_has_no_hover_card() -> void:
	var bare := ItemCardButton.new()
	bare.set_info("Nothing", [])
	assert_str(bare.tooltip_text).is_empty()
	assert_object(bare._make_custom_tooltip("")).is_null()
	bare.free()
