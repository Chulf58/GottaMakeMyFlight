class_name TestBuildMenuMoneyPage
extends GdUnitTestSuite
## The standalone currency exchange and ATM cards in the Facilities domain tab.

const TOOLS := [
	BuildMode.Tool.EXCHANGE,
	BuildMode.Tool.ATM,
]
const NAMES := ["Exchange", "ATM"]
const THUMBS := ["currency_exchange", "atm"]

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


func before_test() -> void:
	_mode.set_tool(BuildMode.Tool.NONE)


func after() -> void:
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


func test_exchange_and_atm_tools_live_in_facilities_in_order() -> void:
	var facilities := BuildMenu.category_index("facilities")
	var tab_tools: Array = BuildMenu.categories()[facilities]["tools"]
	for tool in TOOLS:
		assert_int(BuildMenu.category_of(tool)).is_equal(facilities)
		assert_bool(tab_tools.has(tool)).is_true()


func test_the_cards_carry_their_names_prices_and_hover_sizes() -> void:
	var facilities := BuildMenu.category_index("facilities")
	_menu.press_category(facilities)
	for n in TOOLS.size():
		var tool: BuildMode.Tool = TOOLS[n]
		var texts := _texts(_menu.card(tool))
		var hover := _hover_texts(tool)
		assert_str(BuildMenu.item(tool)[0]).is_equal(NAMES[n])
		assert_array(texts).contains([NAMES[n]])
		var def := BuildCatalog.get_def(BuildMode.tool_object(tool))
		assert_array(hover).contains(["%dx%d" % [def.size.x, def.size.y], "Click"])
		assert_int(BuildMenu.tool_price(tool)).is_equal(PriceTable.price_of_object(def.id))
		assert_int(BuildMenu.tool_price(tool)).is_greater(0)


func test_every_money_card_shows_its_rendered_thumbnail() -> void:
	assert_array(BuildMenu.PLACEHOLDER_THUMBNAILS).is_empty()
	for n in TOOLS.size():
		var tool: BuildMode.Tool = TOOLS[n]
		assert_str(BuildMenu.item(tool)[1]).is_equal(THUMBS[n])
		var path := BuildMenu.THUMBNAIL_DIR % BuildMenu.item(tool)[1]
		assert_bool(ResourceLoader.exists(path)).override_failure_message(path).is_true()
		var picture := (
			_menu.card(tool).find_children("*", "TextureRect", true, false)[0] as TextureRect
		)
		assert_object(picture.texture).override_failure_message(path).is_not_null()
		assert_int(picture.texture.get_width()).is_equal(256)
		assert_int(picture.find_children("*", "ColorRect", true, false).size()).is_equal(0)


func test_picking_a_money_tool_opens_facilities_and_presses_its_card() -> void:
	var facilities := BuildMenu.category_index("facilities")
	for tool in TOOLS:
		_mode.set_tool(tool)
		assert_int(_menu.open_category()).is_equal(facilities)
		assert_bool(_menu.card(tool).button_pressed).is_true()
		assert_bool(_menu.category_button(facilities).button_pressed).is_true()
