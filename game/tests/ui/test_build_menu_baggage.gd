class_name TestBuildMenuBaggage
extends GdUnitTestSuite
## The baggage tools in the build menu (decision baggage-belts-are-one-auto-
## shaping-belt-tool-one-baggage-tray): one Baggage category before Remove
## with a tray holding Belt, Bag room and Bag cart, each with a rendered
## thumbnail, and picking a tool opens the category.

const BAGGAGE_TOOLS := [BuildMode.Tool.BELT, BuildMode.Tool.BAG_ROOM, BuildMode.Tool.CART]

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


func test_one_baggage_category_sits_before_remove_and_remove_stays_last() -> void:
	var baggage := _category_named("Baggage")
	assert_int(baggage).is_not_equal(BuildMenu.NO_CATEGORY)
	assert_int(baggage).is_equal(BuildMenu.REMOVE_CATEGORY - 1)
	assert_int(BuildMenu.REMOVE_CATEGORY).is_equal(BuildMenu.CATEGORIES.size() - 1)
	assert_str(BuildMenu.CATEGORIES[BuildMenu.REMOVE_CATEGORY]["name"]).is_equal("Remove")
	assert_array(BuildMenu.CATEGORIES[baggage]["tools"]).is_equal(BAGGAGE_TOOLS)
	assert_int(_category_named("Belts")).is_equal(BuildMenu.NO_CATEGORY)


func test_every_tool_with_a_card_is_in_exactly_one_category() -> void:
	for tool in BuildMenu.ITEMS:
		var count := 0
		for category in BuildMenu.CATEGORIES:
			if category["tools"].has(tool):
				count += 1
		assert_int(count).override_failure_message("tool %d" % tool).is_equal(1)


func test_the_baggage_cards_show_size_price_and_a_rendered_thumbnail() -> void:
	var sizes := {
		BuildMode.Tool.BELT: "Drag a line",
		BuildMode.Tool.BAG_ROOM: "2x2 min",
		BuildMode.Tool.CART: "1x2",
	}
	for tool in BAGGAGE_TOOLS:
		var card := _menu.card(tool)
		assert_object(card).override_failure_message("tool %d" % tool).is_not_null()
		assert_array(_texts(card)).contains([BuildMenu.ITEMS[tool][0], sizes[tool], "Click"])
		var picture := card.find_children("*", "TextureRect", true, false)[0] as TextureRect
		# A rendered PNG, not the placeholder tile.
		assert_object(picture.texture).override_failure_message("tool %d" % tool).is_not_null()
		assert_bool(BuildMenu.PLACEHOLDER_THUMBNAILS.has(BuildMenu.ITEMS[tool][1])).is_false()
	var belt_price := PriceTable.price_of_object(&"baggage_belt")
	assert_int(BuildMenu.tool_price(BuildMode.Tool.BELT)).is_equal(belt_price)


func test_picking_a_baggage_tool_opens_its_category_and_marks_its_card() -> void:
	for tool in BAGGAGE_TOOLS:
		_menu.card(tool).pressed.emit()
		assert_int(_mode.tool).is_equal(tool)
		assert_int(_menu.open_category()).is_equal(_category_named("Baggage"))
		assert_bool(_menu.is_tray_open()).is_true()
		assert_bool(_menu.card(tool).button_pressed).is_true()


func test_the_baggage_tray_has_a_rotate_card_that_turns_the_piece() -> void:
	_menu.card(BuildMode.Tool.CART).pressed.emit()
	var shown: Array[Button] = []
	for button in _menu.tray().find_children("CardRotate", "Button", true, false):
		if (button as Control).is_visible_in_tree():
			shown.append(button)
	assert_array(shown).has_size(1)
	var before := _mode.facing
	shown[0].pressed.emit()
	assert_int(_mode.facing).is_equal((before + 1) % 4)
