class_name TestBuildMenuMoneyPage
extends GdUnitTestSuite
## The currency exchange and ATM in the build menu (F4-5b; decision store-
## rooms-and-retail-pieces-go-on-stores-pages-behind-the-furniture-button): one
## Money page after the Fashion page, behind the Furniture bar button, holding
## the exchange room, its counter, the ATM room and the ATM, four cards and the
## Rotate and Next column. The exchange counter and the ATM left the Desks page
## for it. Every card shows a rendered thumbnail, never a placeholder tile.

const TOOLS := [
	BuildMode.Tool.EXCHANGE_ROOM,
	BuildMode.Tool.EXCHANGE,
	BuildMode.Tool.ATM_ROOM,
	BuildMode.Tool.ATM,
]
const NAMES := ["Exchange", "Counter", "ATM", "Cash machine"]
## Room tool -> its RoomTypes id.
const ROOMS := {BuildMode.Tool.EXCHANGE_ROOM: &"exchange", BuildMode.Tool.ATM_ROOM: &"atm"}

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


func test_the_money_page_follows_fashion_in_the_furniture_group_before_remove() -> void:
	var all := BuildMenu.categories()
	var page := _index("Money")
	print("money page at %d, remove at %d" % [page, BuildMenu.REMOVE_CATEGORY])
	assert_int(page).is_equal(_index("Fashion") + 1)
	assert_bool(all[page].get("page", false)).is_true()
	assert_bool(_menu.category_button(page).visible).is_false()
	assert_int(BuildMenu.group_start(page)).is_equal(_index("Furniture"))
	# The Dining page (F4-6) follows it; Remove comes after that.
	assert_int(BuildMenu.REMOVE_CATEGORY).is_equal(page + 2)
	assert_int(_index("Dining")).is_equal(page + 1)
	assert_array(all[page]["tools"]).is_equal(TOOLS)
	for tool in TOOLS:
		assert_int(BuildMenu.category_of(tool)).is_equal(page)
	# The exchange counter and the ATM left the Desks page.
	var desks: Array = all[_index("Desks")]["tools"]
	assert_bool(desks.has(BuildMode.Tool.EXCHANGE)).is_false()
	assert_bool(desks.has(BuildMode.Tool.ATM)).is_false()
	assert_int(desks.size()).is_greater(0)


func test_the_cards_carry_their_names_sizes_and_prices() -> void:
	_menu.press_category(_index("Money"))
	for n in TOOLS.size():
		var tool: BuildMode.Tool = TOOLS[n]
		var texts := _texts(_menu.card(tool))
		print("money card %d: %s" % [tool, texts])
		assert_str(BuildMenu.item(tool)[0]).is_equal(NAMES[n])
		assert_array(texts).contains([NAMES[n]])
		if ROOMS.has(tool):
			var room := RoomTypes.get_type(ROOMS[tool])
			assert_str(str(BuildMode.TOOL_ROOMS[tool])).is_equal(str(room.id))
			assert_str(room.display_name).is_equal(NAMES[n])
			assert_array(texts).contains(["%dx%d min" % [room.min_size.x, room.min_size.y]])
			# A room is dragged out, as the other room cards say.
			assert_array(texts).contains([BuildMenu.PRICE_TEXT, "Drag"])
			assert_array(texts).not_contains(["Click"])
		else:
			var def := BuildCatalog.get_def(BuildMode.tool_object(tool))
			assert_array(texts).contains(["%dx%d" % [def.size.x, def.size.y]])
			assert_int(BuildMenu.tool_price(tool)).is_equal(PriceTable.price_of_object(def.id))
			assert_int(BuildMenu.tool_price(tool)).is_greater(0)


func test_every_money_card_shows_its_rendered_thumbnail() -> void:
	assert_array(BuildMenu.PLACEHOLDER_THUMBNAILS).is_empty()
	assert_str(BuildMenu.item(BuildMode.Tool.EXCHANGE_ROOM)[1]).is_equal("exchange_room")
	assert_str(BuildMenu.item(BuildMode.Tool.ATM_ROOM)[1]).is_equal("atm_room")
	for tool in TOOLS:
		var path := BuildMenu.THUMBNAIL_DIR % BuildMenu.item(tool)[1]
		assert_bool(ResourceLoader.exists(path)).override_failure_message(path).is_true()
		var picture := (
			_menu.card(tool).find_children("*", "TextureRect", true, false)[0] as TextureRect
		)
		assert_object(picture.texture).override_failure_message(path).is_not_null()
		assert_int(picture.texture.get_width()).is_equal(256)
		assert_int(picture.find_children("*", "ColorRect", true, false).size()).is_equal(0)


func test_the_money_tray_fits_the_column_with_rotate_and_next() -> void:
	var page := _index("Money")
	_menu.press_category(page)
	var need := _menu.tray().get_combined_minimum_size()
	print("money tray needs %s of %s x %s" % [need, BuildMenu.COLUMN_W, BuildMenu.TRAY_H])
	assert_float(need.x).is_less_equal(BuildMenu.COLUMN_W)
	assert_float(need.y).is_less_equal(BuildMenu.TRAY_H)
	var next := _menu.card(TOOLS[0]).get_parent().find_child("CardNext", true, false) as Button
	assert_object(next).is_not_null()
	# Next goes to the Dining page, the last of the group, which goes back round.
	next.pressed.emit()
	assert_int(_menu.open_category()).is_equal(_index("Dining"))


func test_picking_a_money_tool_opens_its_page_and_presses_its_card() -> void:
	for tool in TOOLS:
		_mode.set_tool(tool)
		assert_int(_menu.open_category()).is_equal(_index("Money"))
		assert_bool(_menu.card(tool).button_pressed).is_true()
		assert_bool(_menu.category_button(_index("Furniture")).button_pressed).is_true()
