class_name TestBuildMenuStores
extends GdUnitTestSuite
## The store rooms and their pieces in the build menu (decision store-rooms-
## and-retail-pieces-go-on-stores-pages-behind-the-furniture-button): three
## Stores pages, one per store, behind the Shops group button since HUD 6/7
## (decision hud-6-7-furniture-groups-five-icon-buttons-decor-food-servic; it
## was the Furniture button before), the last group before Remove, with the
## F4-2 page pattern. Each page holds the room tool,
## its counter or till and its shelf or rail, so the pharmacy counter and
## shelf left the Care page for the pharmacy's. Every card shows a rendered
## thumbnail (render_kit_thumbnails.py), never a placeholder tile.

## Page name -> [room id, its tools in card order, the card names].
const PAGES := {
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
		["Duty free", "Till", "Shelf"],
	],
	"Fashion":
	[
		&"fashion",
		[BuildMode.Tool.FASHION_ROOM, BuildMode.Tool.FASHION_TILL, BuildMode.Tool.FASHION_RAIL],
		["Fashion store", "Till", "Clothes rail"],
	],
}
const PAGE_ORDER := ["Pharmacy", "Duty free", "Fashion"]

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


func _index(category_name: String) -> int:
	var all := BuildMenu.categories()
	for i in all.size():
		if all[i]["name"] == category_name:
			return i
	return BuildMenu.NO_CATEGORY


func _texts(control: Control) -> Array:
	var out := []
	for label in control.find_children("*", "Label", true, false):
		out.append((label as Label).text)
	return out


func _next_button(page: int) -> Button:
	var tool: BuildMode.Tool = BuildMenu.categories()[page]["tools"][0]
	return _menu.card(tool).get_parent().find_child("CardNext", true, false) as Button


# Was "three Stores pages follow Fun in the Furniture group"; since HUD 6/7 they
# are the Shops group: the pharmacy page carries the Shops button and the
# other two are its later pages, the last before Remove.
func test_three_stores_pages_make_the_shops_group_before_remove() -> void:
	var all := BuildMenu.categories()
	var shops := BuildMenu.group_index("Shops")
	assert_int(shops).is_equal(_index("Pharmacy"))
	assert_bool(_menu.category_button(shops).visible).is_true()
	assert_str(_menu.category_button(shops).tooltip_text).is_equal("Shops")
	for n in PAGE_ORDER.size():
		var page := _index(PAGE_ORDER[n])
		print("store page %s at %d" % [PAGE_ORDER[n], page])
		assert_int(page).is_equal(shops + n)
		assert_bool(all[page].get("page", false)).is_equal(n > 0)
		assert_bool(_menu.category_button(page).visible).is_equal(n == 0)
		assert_int(BuildMenu.group_start(page)).is_equal(shops)
	assert_int(BuildMenu.REMOVE_CATEGORY).is_equal(_index("Fashion") + 1)
	assert_str(all[BuildMenu.REMOVE_CATEGORY]["name"]).is_equal("Remove")


func test_each_page_holds_its_room_then_its_counter_and_browse_piece() -> void:
	for page_name in PAGE_ORDER:
		var page := _index(page_name)
		var tools: Array = PAGES[page_name][1]
		assert_array(BuildMenu.categories()[page]["tools"]).is_equal(tools)
		for tool in tools:
			assert_int(BuildMenu.category_of(tool)).is_equal(page)
	# The pharmacy pieces left the Care page.
	var care: Array = BuildMenu.categories()[_index("Care")]["tools"]
	assert_bool(care.has(BuildMode.Tool.PHARMACY_COUNTER)).is_false()
	assert_bool(care.has(BuildMode.Tool.PHARMACY_SHELF)).is_false()
	assert_int(care.size()).is_greater(0)


func test_the_room_cards_carry_the_room_type_name_and_minimum_size() -> void:
	for page_name in PAGE_ORDER:
		var room: RoomTypes.RoomType = RoomTypes.get_type(PAGES[page_name][0])
		var tool: BuildMode.Tool = PAGES[page_name][1][0]
		assert_str(str(BuildMode.TOOL_ROOMS[tool])).is_equal(str(room.id))
		_menu.press_category(_index(page_name))
		var texts := _texts(_menu.card(tool))
		print("%s room card: %s" % [room.id, texts])
		assert_str(BuildMenu.item(tool)[0]).is_equal(room.display_name)
		assert_array(texts).contains([room.display_name])
		assert_array(texts).contains(["%dx%d min" % [room.min_size.x, room.min_size.y]])
		# A room is dragged out, as the kiosk room card says.
		assert_array(texts).contains([BuildMenu.PRICE_TEXT, "Drag"])
		assert_array(texts).not_contains(["Click"])


func test_the_piece_cards_show_name_catalog_size_and_price() -> void:
	for page_name in PAGE_ORDER:
		_menu.press_category(_index(page_name))
		var tools: Array = PAGES[page_name][1]
		for n in range(1, tools.size()):
			var tool: BuildMode.Tool = tools[n]
			var id := BuildMode.tool_object(tool)
			var def := BuildCatalog.get_def(id)
			assert_object(def).override_failure_message(str(id)).is_not_null()
			var texts := _texts(_menu.card(tool))
			print("%s card: %s" % [id, texts])
			assert_str(BuildMenu.item(tool)[0]).is_equal(PAGES[page_name][2][n])
			assert_array(texts).contains([PAGES[page_name][2][n]])
			assert_array(texts).contains(["%dx%d" % [def.size.x, def.size.y]])
			assert_int(BuildMenu.tool_price(tool)).is_equal(PriceTable.price_of_object(id))
			assert_int(BuildMenu.tool_price(tool)).is_greater(0)


func test_every_store_card_shows_its_rendered_thumbnail() -> void:
	assert_array(BuildMenu.PLACEHOLDER_THUMBNAILS).is_empty()
	for page_name in PAGE_ORDER:
		for tool in PAGES[page_name][1]:
			var path := BuildMenu.THUMBNAIL_DIR % BuildMenu.item(tool)[1]
			assert_bool(ResourceLoader.exists(path)).override_failure_message(path).is_true()
			var picture := (
				_menu.card(tool).find_children("*", "TextureRect", true, false)[0] as TextureRect
			)
			assert_object(picture.texture).override_failure_message(path).is_not_null()
			assert_int(picture.texture.get_width()).is_equal(256)
			assert_int(picture.find_children("*", "ColorRect", true, false).size()).is_equal(0)


func test_each_store_tray_fits_the_column_with_rotate_and_next() -> void:
	for page_name in PAGE_ORDER:
		var page := _index(page_name)
		_menu.press_category(page)
		var need := _menu.tray().get_combined_minimum_size()
		print("store page %s tray needs %s" % [page_name, need])
		assert_float(need.x).is_less_equal(BuildMenu.COLUMN_W)
		assert_float(need.y).is_less_equal(BuildMenu.TRAY_H)
		assert_object(_next_button(page)).is_not_null()


# Was Fun through the stores, Money, Dining and Activities back to the first
# furniture page; since HUD 6/7 Next stays inside the Shops group.
func test_next_runs_through_the_stores_and_back_to_the_pharmacy_page() -> void:
	var shops := BuildMenu.group_index("Shops")
	_menu.category_button(shops).pressed.emit()
	var want := PAGE_ORDER.slice(1)
	want.append(PAGE_ORDER[0])
	for page_name in want:
		_next_button(_menu.open_category()).pressed.emit()
		assert_int(_menu.open_category()).is_equal(_index(page_name))
		assert_bool(_menu.category_button(shops).button_pressed).is_true()
		assert_int(_mode.tool).is_equal(BuildMode.Tool.NONE)


func test_picking_a_store_tool_opens_its_page_and_presses_its_card() -> void:
	for page_name in PAGE_ORDER:
		for tool in PAGES[page_name][1]:
			_mode.set_tool(tool)
			assert_int(_menu.open_category()).is_equal(_index(page_name))
			assert_bool(_menu.card(tool).button_pressed).is_true()
			# The Shops group button since HUD 6/7 (was Furniture).
			var shops := BuildMenu.group_index("Shops")
			assert_bool(_menu.category_button(shops).button_pressed).is_true()
