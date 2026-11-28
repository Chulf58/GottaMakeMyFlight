class_name TestBuildMenuBaggage
extends GdUnitTestSuite
## The baggage tools in the Operations domain tab: Belt, Bag room and Bag cart
## sit in Operations with rendered thumbnails, hover popup sizes/needs, and
## Remove stays last.

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


func _hover_texts(tool: BuildMode.Tool) -> Array:
	var card := _menu.card(tool) as ItemCardButton
	var popup: Control = auto_free(card._make_custom_tooltip(card.tooltip_text))
	return _texts(popup)


func test_baggage_tools_sit_in_operations_and_remove_stays_last() -> void:
	var ops := BuildMenu.category_index("operations")
	assert_int(ops).is_equal(1)
	assert_int(ops).is_less(BuildMenu.REMOVE_CATEGORY)
	assert_int(BuildMenu.REMOVE_CATEGORY).is_equal(BuildMenu.CATEGORIES.size() - 1)
	assert_str(BuildMenu.CATEGORIES[BuildMenu.REMOVE_CATEGORY]["name"]).is_equal("Remove")
	var tab_tools: Array = BuildMenu.CATEGORIES[ops]["tools"]
	for tool in [BuildMode.Tool.BELT, BuildMode.Tool.BAG_ROOM, BuildMode.Tool.BAY_DOOR]:
		assert_bool(tab_tools.has(tool)).is_true()
		assert_int(BuildMenu.category_of(tool)).is_equal(ops)
	assert_bool(tab_tools.has(BuildMode.Tool.CART)).is_false()
	assert_array(BuildMenuCatalog.ROOM_TOOLS[&"bag_room"]).is_equal(
		[BuildMode.Tool.BAY_DOOR, BuildMode.Tool.BELT, BuildMode.Tool.CART]
	)


func test_every_tool_with_a_card_is_in_exactly_one_category() -> void:
	for tool in BuildMenu.ITEMS:
		var count := 0
		for category in BuildMenu.CATEGORIES:
			if category["tools"].has(tool):
				count += 1
		if BuildMenuCatalog.is_room_only_tool(tool):
			assert_int(count).override_failure_message("room tool %d" % tool).is_equal(0)
			assert_bool(BuildMenuCatalog.room_owners_of(tool).is_empty()).is_false()
		else:
			assert_int(count).override_failure_message("tool %d" % tool).is_equal(1)


func test_the_baggage_cards_show_name_thumbnail_and_hover_size_and_needs() -> void:
	var sizes := {
		BuildMode.Tool.BELT: "Drag a line",
		BuildMode.Tool.BAG_ROOM: "2x2 min",
		BuildMode.Tool.CART: "1x2",
	}
	var hints := {
		BuildMode.Tool.BELT: "Drag",
		BuildMode.Tool.BAG_ROOM: "Needs belt end",
		BuildMode.Tool.CART: "Click",
	}
	for tool in BAGGAGE_TOOLS:
		var card := _menu.card(tool)
		assert_object(card).override_failure_message("tool %d" % tool).is_not_null()
		assert_array(_texts(card)).contains([BuildMenu.ITEMS[tool][0]])
		assert_array(_hover_texts(tool)).contains([sizes[tool], hints[tool]])
		var picture := card.find_children("*", "TextureRect", true, false)[0] as TextureRect
		assert_object(picture.texture).override_failure_message("tool %d" % tool).is_not_null()
		assert_bool(BuildMenu.PLACEHOLDER_THUMBNAILS.has(BuildMenu.ITEMS[tool][1])).is_false()
	var belt_price := PriceTable.price_of_object(&"baggage_belt")
	assert_int(BuildMenu.tool_price(BuildMode.Tool.BELT)).is_equal(belt_price)


func test_picking_a_baggage_tool_opens_operations_and_marks_its_card() -> void:
	var ops := BuildMenu.category_index("operations")
	_menu.card(BuildMode.Tool.BELT).pressed.emit()
	assert_int(_mode.tool).is_equal(BuildMode.Tool.BELT)
	assert_int(_menu.open_category()).is_equal(ops)
	assert_bool(_menu.is_tray_open()).is_true()
	assert_bool(_menu.card(BuildMode.Tool.BELT).button_pressed).is_true()
	for tool in [BuildMode.Tool.BAG_ROOM, BuildMode.Tool.CART]:
		_menu.card(tool).pressed.emit()
		assert_int(_mode.tool).is_equal(tool)
		assert_bool(_menu.is_room_context()).is_true()
		assert_str(String(_menu.room_context_type())).is_equal("bag_room")
		assert_bool(_menu.is_tray_open()).is_true()
		assert_bool(_menu.card(tool).button_pressed).is_true()
