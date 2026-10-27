class_name TestBuildMenuBaggage
extends GdUnitTestSuite
## The baggage tools in the build menu (decision hud-layout-bottom-category-bar-
## with-an-item-tray-time-and-fl: baggage is added as more categories): a Belts
## and a Bag room category before Remove, a card per tool, and picking a tool
## opens its category.

const BAGGAGE_TOOLS := [
	BuildMode.Tool.BELT,
	BuildMode.Tool.BELT_CORNER,
	BuildMode.Tool.BELT_FEED,
	BuildMode.Tool.BAG_ROOM,
	BuildMode.Tool.BELT_END,
	BuildMode.Tool.CART,
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


func _category_named(category_name: String) -> int:
	for i in BuildMenu.CATEGORIES.size():
		if BuildMenu.CATEGORIES[i]["name"] == category_name:
			return i
	return BuildMenu.NO_CATEGORY


func test_belts_and_bag_room_sit_before_remove_and_remove_stays_last() -> void:
	var belts := _category_named("Belts")
	var room := _category_named("Bag room")
	assert_int(belts).is_not_equal(BuildMenu.NO_CATEGORY)
	assert_int(room).is_equal(belts + 1)
	assert_int(BuildMenu.REMOVE_CATEGORY).is_equal(BuildMenu.CATEGORIES.size() - 1)
	assert_str(BuildMenu.CATEGORIES[BuildMenu.REMOVE_CATEGORY]["name"]).is_equal("Remove")
	assert_int(room).is_less(BuildMenu.REMOVE_CATEGORY)
	assert_array(BuildMenu.CATEGORIES[belts]["tools"]).is_equal(
		[BuildMode.Tool.BELT, BuildMode.Tool.BELT_CORNER, BuildMode.Tool.BELT_FEED]
	)
	assert_array(BuildMenu.CATEGORIES[room]["tools"]).is_equal(
		[BuildMode.Tool.BAG_ROOM, BuildMode.Tool.BELT_END, BuildMode.Tool.CART]
	)


func test_every_tool_with_a_card_is_in_exactly_one_category() -> void:
	for tool in BuildMenu.ITEMS:
		var count := 0
		for category in BuildMenu.CATEGORIES:
			if category["tools"].has(tool):
				count += 1
		assert_int(count).override_failure_message("tool %d" % tool).is_equal(1)


func test_every_baggage_tool_has_a_card_with_its_size_and_a_click_hint() -> void:
	var sizes := {
		BuildMode.Tool.BELT: "1x1",
		BuildMode.Tool.BELT_CORNER: "1x1",
		BuildMode.Tool.BELT_FEED: "1x1",
		BuildMode.Tool.BAG_ROOM: "2x2 min",
		BuildMode.Tool.BELT_END: "1x1",
		BuildMode.Tool.CART: "1x2",
	}
	for tool in BAGGAGE_TOOLS:
		var card := _menu.card(tool)
		assert_object(card).override_failure_message("tool %d" % tool).is_not_null()
		var texts := _texts(card)
		assert_array(texts).contains([BuildMenu.ITEMS[tool][0], sizes[tool], "Click"])
		assert_object(card.find_children("*", "TextureRect", true, false)[0]).is_not_null()


func test_picking_a_baggage_tool_opens_its_category_and_marks_its_card() -> void:
	for tool in BAGGAGE_TOOLS:
		_menu.card(tool).pressed.emit()
		assert_int(_mode.tool).is_equal(tool)
		assert_int(_menu.open_category()).is_equal(BuildMenu.category_of(tool))
		assert_bool(_menu.is_tray_open()).is_true()
		assert_bool(_menu.card(tool).button_pressed).is_true()


func test_the_baggage_trays_have_a_rotate_card_that_turns_the_piece() -> void:
	for pick in [BuildMode.Tool.BELT_CORNER, BuildMode.Tool.CART]:
		_menu.card(pick).pressed.emit()
		var shown: Array[Button] = []
		for button in _menu.tray().find_children("CardRotate", "Button", true, false):
			if (button as Control).is_visible_in_tree():
				shown.append(button)
		assert_array(shown).override_failure_message("tool %d" % pick).has_size(1)
		var before := _mode.facing
		shown[0].pressed.emit()
		assert_int(_mode.facing).is_equal((before + 1) % 4)
