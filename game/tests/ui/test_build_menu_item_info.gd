class_name TestBuildMenuItemInfo
extends GdUnitTestSuite
## The hover card on every build tray item (decisions build-menu-items-show-a-
## hover-card-with-a-description and build-menu-rework-six-domain-tabs-
## progress-tab-and-card-u): all 79 tools have a 3-part ItemInfo and render a
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
	assert_int(checked).is_equal(77)


func test_every_description_belongs_to_a_tray_item() -> void:
	var tools := _tray_tools()
	for tool in ItemInfo.tools():
		assert_bool(tools.has(tool)).is_true()
	assert_int(ItemInfo.tools().size()).is_equal(77)


func test_all_77_tools_produce_a_hover_card_with_details_and_three_parts() -> void:
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
	assert_int(checked).is_equal(77)


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


func test_the_real_tooltip_path_places_the_popup_above_the_card_at_ui_scale() -> void:
	var card := _card_for(BuildMode.Tool.DESK)
	await await_idle_frame()
	var transform := card.get_screen_transform()
	assert_float(transform.get_scale().y).is_equal_approx(UI_SCALE, 0.001)
	var popup := await _shown_in_popup(card)
	assert_int(popup.size.y).is_greater(0)
	var top := transform.origin
	assert_int(popup.position.x).is_equal(roundi(top.x))
	assert_int(popup.position.y + popup.size.y).is_equal(roundi(top.y - ItemCardButton.CARD_GAP))
	var item_rect := Rect2(top, card.size * UI_SCALE)
	(
		assert_bool(Rect2(Vector2(popup.position), Vector2(popup.size)).intersects(item_rect))
		. is_false()
	)


func test_the_popup_stays_inside_the_window_sideways() -> void:
	var card := _card_for(BuildMode.Tool.DESK)
	await await_idle_frame()
	var wide := Vector2(float(_port.size.x) + 400.0, 100.0)
	assert_int(card.card_screen_position(wide).x).is_equal(0)
	var narrow := card.card_screen_position(Vector2(100.0, 100.0))
	assert_int(narrow.x).is_less_equal(_port.size.x - 100)


func test_an_item_with_no_info_has_no_hover_card() -> void:
	var bare := ItemCardButton.new()
	bare.set_info("Nothing", [])
	assert_str(bare.tooltip_text).is_empty()
	assert_object(bare._make_custom_tooltip("")).is_null()
	bare.free()
