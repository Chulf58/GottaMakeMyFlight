class_name TestBuildMenuItemInfo
extends GdUnitTestSuite
## The hover card on every build tray item (decision build-menu-items-show-a-
## hover-card-with-a-description, board 702a474e): what the item is, how it
## works, and what it needs or costs to run. The text is ItemInfo's;
## ItemCardButton shows it. The menu sits under the project's 1.25 UI scale, as
## in game.

## project.godot stretches the HUD by 1.25; the menu carries it here.
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


## Every tool that has a card in some tray, once each. Remove is a bar button
## with no tray, so it has no card.
func _tray_tools() -> Array:
	var tools: Array = []
	for category in BuildMenu.categories():
		for tool in category["tools"]:
			if tool != BuildMode.Tool.REMOVE and not tools.has(tool):
				tools.append(tool)
	return tools


func _card_for(tool: BuildMode.Tool) -> ItemCardButton:
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
	print("item descriptions checked: %d of %d tray items" % [checked, tools.size()])
	assert_int(checked).is_greater(70)


func test_every_description_belongs_to_a_tray_item() -> void:
	var tools := _tray_tools()
	for tool in ItemInfo.TEXT:
		assert_bool(tools.has(tool)).is_true()
	assert_int(ItemInfo.TEXT.size()).is_equal(tools.size())


func test_every_card_holds_a_hover_card_with_the_three_parts() -> void:
	var checked := 0
	for tool in _tray_tools():
		var card := _card_for(tool)
		assert_object(card).is_not_null()
		var info := ItemInfo.of(tool)
		# Godot only asks for the hover card when the tooltip text is not empty.
		assert_str(card.tooltip_text).is_not_empty()
		var shown := card._make_custom_tooltip(card.tooltip_text) as Control
		assert_object(shown).is_not_null()
		var texts := _texts(shown)
		assert_array(texts).contains([BuildMenu.item(tool)[0], info[0], info[1], info[2]])
		assert_array(texts).contains([ItemCardButton.HOW_HEADING, ItemCardButton.NEEDS_HEADING])
		shown.free()
		checked += 1
	print("hover cards checked: %d" % checked)
	assert_int(checked).is_greater(70)


func test_hover_card_is_in_the_hud_theme_and_shows_only_on_hover() -> void:
	var card := _card_for(BuildMode.Tool.DESK)
	var shown := card._make_custom_tooltip(card.tooltip_text) as Control
	assert_object(shown.theme).is_same(BuildMenu.HUD_THEME)
	# Nothing extra is on the card itself: no info label sits in the tray card.
	assert_array(_texts(card)).not_contains([ItemInfo.of(BuildMode.Tool.DESK)[0]])
	shown.free()


## The tooltip popup Godot would hold the card in, with the card in it, after
## the deferred placement has run.
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
	# Left edges line up; the popup's bottom edge sits CARD_GAP above the card's
	# top edge in screen units (the gap and the popup's height are not scaled).
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
