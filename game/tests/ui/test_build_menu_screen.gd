class_name TestBuildMenuScreen
extends GdUnitTestSuite
## The screen stand in the Operations domain tab: Gate desk, Seats and Screen
## sit in order in Operations, with Screen's daily upkeep in its hover popup and
## its rendered thumbnail on the card.

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


func _hover_texts(tool: BuildMode.Tool) -> Array:
	var card := _menu.card(tool) as ItemCardButton
	var popup: Control = auto_free(card._make_custom_tooltip(card.tooltip_text))
	return _texts(popup)


func test_operations_holds_gate_desk_seats_then_screen_in_order() -> void:
	var ops := BuildMenu.category_index("operations")
	var tools: Array = BuildMenu.categories()[ops]["tools"]
	var i_gate := tools.find(BuildMode.Tool.GATE_DESK)
	var i_bus_gate := tools.find(BuildMode.Tool.BUS_GATE_DESK)
	var i_remote := tools.find(BuildMode.Tool.REMOTE_STAND)
	var i_seats := tools.find(BuildMode.Tool.SEATS)
	var i_screen := tools.find(BuildMode.Tool.SCREEN)
	assert_int(i_gate).is_greater_equal(0)
	assert_int(i_bus_gate).is_equal(i_gate + 1)
	assert_int(i_remote).is_equal(i_bus_gate + 1)
	assert_int(i_seats).is_equal(i_remote + 1)
	assert_int(i_screen).is_equal(i_seats + 1)
	assert_int(BuildMenu.category_of(BuildMode.Tool.SCREEN)).is_equal(ops)
	assert_str(str(BuildMode.TOOL_OBJECTS[BuildMode.Tool.SCREEN])).is_equal(
		str(ScreenCoverage.SCREEN_ID)
	)


func test_the_screen_card_shows_its_price_thumbnail_and_hover_upkeep() -> void:
	_menu.category_button(BuildMenu.category_index("operations")).pressed.emit()
	var card := _menu.card(BuildMode.Tool.SCREEN)
	assert_object(card).is_not_null()
	assert_array(_texts(card)).contains(["Screen"])
	assert_array(_hover_texts(BuildMode.Tool.SCREEN)).contains(
		[BuildMenuCatalog.upkeep_text(PriceTable.SCREEN_UPKEEP)]
	)
	assert_int(BuildMenu.tool_price(BuildMode.Tool.SCREEN)).is_equal(
		PriceTable.price_of_object(ScreenCoverage.SCREEN_ID)
	)
	assert_bool(BuildMenu.PLACEHOLDER_THUMBNAILS.has("screen_stand")).is_false()
	var picture := card.find_children("*", "TextureRect", true, false)[0] as TextureRect
	assert_object(picture.texture).is_not_null()
	assert_str(picture.texture.resource_path).is_equal(BuildMenu.THUMBNAIL_DIR % "screen_stand")
	assert_int(picture.find_children("*", "ColorRect", true, false).size()).is_equal(0)
