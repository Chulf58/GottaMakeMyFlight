class_name TestBuildMenuStores
extends GdUnitTestSuite
## The store rooms and retail pieces in the Shops domain tab: kiosk, pharmacy,
## duty free and fashion sit in order under Shops, each room followed by its
## counter/till and browse piece, with rendered thumbnails.

const STORES := {
	"Pharmacy":
	[
		&"pharmacy",
		[
			BuildMode.Tool.PHARMACY_ROOM,
			BuildMode.Tool.PHARMACY_COUNTER,
			BuildMode.Tool.PHARMACY_SHELF,
		],
		["Pharmacy", "Counter", "Shelf"],
	],
	"Duty free":
	[
		&"duty_free",
		[
			BuildMode.Tool.DUTY_FREE_ROOM,
			BuildMode.Tool.DUTY_FREE_TILL,
			BuildMode.Tool.DUTY_FREE_SHELF,
		],
		["Duty free", "Duty Free Till", "Duty Free Shelf"],
	],
	"Fashion":
	[
		&"fashion",
		[BuildMode.Tool.FASHION_ROOM, BuildMode.Tool.FASHION_TILL, BuildMode.Tool.FASHION_RAIL],
		["Fashion store", "Fashion Till", "Clothes rail"],
	],
}
const STORE_ORDER := ["Pharmacy", "Duty free", "Fashion"]

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


func test_all_stores_live_in_the_shops_tab_in_order() -> void:
	var shops := BuildMenu.category_index("shops")
	assert_int(shops).is_equal(4)
	assert_bool(_menu.category_button(shops).visible).is_true()
	assert_str(_menu.category_button(shops).tooltip_text).is_equal("Shops")
	var expected := [
		BuildMode.Tool.KIOSK_ROOM,
		BuildMode.Tool.KIOSK_COUNTER,
		BuildMode.Tool.KIOSK_DISPLAY,
	]
	for store_name in STORE_ORDER:
		expected.append_array(STORES[store_name][1])
	assert_array(BuildMenu.categories()[shops]["tools"]).is_equal(expected)


func test_the_room_cards_carry_the_room_type_name_and_hover_minimum_size() -> void:
	var shops := BuildMenu.category_index("shops")
	_menu.press_category(shops)
	for store_name in STORE_ORDER:
		var room: RoomTypes.RoomType = RoomTypes.get_type(STORES[store_name][0])
		var tool: BuildMode.Tool = STORES[store_name][1][0]
		assert_str(str(BuildMode.TOOL_ROOMS[tool])).is_equal(str(room.id))
		var texts := _texts(_menu.card(tool))
		var hover := _hover_texts(tool)
		assert_str(BuildMenu.item(tool)[0]).is_equal(room.display_name)
		assert_array(texts).contains([room.display_name, BuildMenu.PRICE_TEXT])
		assert_array(hover).contains(["%dx%d min" % [room.min_size.x, room.min_size.y], "Drag"])


func test_the_piece_cards_show_name_price_and_hover_catalog_size() -> void:
	var shops := BuildMenu.category_index("shops")
	_menu.press_category(shops)
	for store_name in STORE_ORDER:
		var tools: Array = STORES[store_name][1]
		for n in range(1, tools.size()):
			var tool: BuildMode.Tool = tools[n]
			var id := BuildMode.tool_object(tool)
			var def := BuildCatalog.get_def(id)
			assert_object(def).override_failure_message(str(id)).is_not_null()
			var texts := _texts(_menu.card(tool))
			var hover := _hover_texts(tool)
			assert_str(BuildMenu.item(tool)[0]).is_equal(STORES[store_name][2][n])
			assert_array(texts).contains([STORES[store_name][2][n]])
			assert_array(hover).contains(["%dx%d" % [def.size.x, def.size.y], "Click"])
			assert_int(BuildMenu.tool_price(tool)).is_equal(PriceTable.price_of_object(id))
			assert_int(BuildMenu.tool_price(tool)).is_greater(0)


func test_every_store_card_shows_its_rendered_thumbnail() -> void:
	assert_array(BuildMenu.PLACEHOLDER_THUMBNAILS).is_empty()
	for store_name in STORE_ORDER:
		for tool in STORES[store_name][1]:
			var path := BuildMenu.THUMBNAIL_DIR % BuildMenu.item(tool)[1]
			assert_bool(ResourceLoader.exists(path)).override_failure_message(path).is_true()
			var picture := (
				_menu.card(tool).find_children("*", "TextureRect", true, false)[0] as TextureRect
			)
			assert_object(picture.texture).override_failure_message(path).is_not_null()
			assert_int(picture.texture.get_width()).is_equal(256)
			assert_int(picture.find_children("*", "ColorRect", true, false).size()).is_equal(0)


func test_picking_a_store_tool_opens_shops_and_presses_its_card() -> void:
	var shops := BuildMenu.category_index("shops")
	for store_name in STORE_ORDER:
		for tool in STORES[store_name][1]:
			_mode.set_tool(tool)
			assert_int(_menu.open_category()).is_equal(shops)
			assert_bool(_menu.card(tool).button_pressed).is_true()
			assert_bool(_menu.category_button(shops).button_pressed).is_true()
