class_name TestBuildMenuItemInfo
extends GdUnitTestSuite
## The hover card on every build tray item (decision build-menu-items-show-a-
## hover-card-with-a-description, board 702a474e): what the item is, how it
## works, and what it needs or costs to run. The text is the fourth entry of
## the item (BuildMenu.item()); ItemCardButton shows it.

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
		var info: Array = BuildMenu.item(tool)[3]
		assert_int(info.size()).is_equal(3)
		for part in info:
			assert_str(part).is_not_empty()
		checked += 1
	print("item descriptions checked: %d of %d tray items" % [checked, tools.size()])
	assert_int(checked).is_greater(70)


func test_every_card_holds_a_hover_card_with_the_three_parts() -> void:
	var checked := 0
	for tool in _tray_tools():
		var card := _card_for(tool)
		assert_object(card).is_not_null()
		var item := BuildMenu.item(tool)
		# Godot only asks for the hover card when the tooltip text is not empty.
		assert_str(card.tooltip_text).is_not_empty()
		var shown := card._make_custom_tooltip(card.tooltip_text) as Control
		assert_object(shown).is_not_null()
		var texts := _texts(shown)
		assert_array(texts).contains([item[0], item[3][0], item[3][1], item[3][2]])
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
	var item := BuildMenu.item(BuildMode.Tool.DESK)
	assert_array(_texts(card)).not_contains([item[3][0]])
	shown.free()


func test_hover_card_opens_above_the_item_card_inside_the_window() -> void:
	var card := _card_for(BuildMode.Tool.DESK)
	await await_idle_frame()
	var size := Vector2(300.0, 200.0)
	var at := card.card_screen_position(size)
	var top := card.get_screen_transform() * Vector2.ZERO
	assert_float(float(at.y) + size.y + ItemCardButton.CARD_GAP).is_equal_approx(top.y, 1.5)
	assert_int(at.x).is_greater_equal(0)
	var room := _port.get_visible_rect().size.x - size.x
	assert_float(float(at.x)).is_less_equal(room)


func test_an_item_with_no_info_has_no_hover_card() -> void:
	var bare := ItemCardButton.new()
	bare.set_info("Nothing", [])
	assert_str(bare.tooltip_text).is_empty()
	assert_object(bare._make_custom_tooltip("")).is_null()
	bare.free()
