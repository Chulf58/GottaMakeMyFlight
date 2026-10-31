class_name TestTemplatesPage
extends GdUnitTestSuite
## The Templates page of the build tray (decision room-templates-store-rooms-
## with-their-pieces-kept-in-each-sa): its button sits at the left edge above
## the icon bar, outside it, and opens the page in the tray with no tool
## picked and build mode on; the Save room card arms saving, a saved room
## gets a card with its name, size and price, the card arms its paste, the
## paste's status reaches the menu's line, and the button closes the page.

var _port: SubViewport
var _finances: Finances
var _mode: BuildMode
var _menu: BuildMenu
var _page: TemplatesPage
var _room := 0


func before() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_finances = Finances.new()
	_port.add_child(_finances)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(20, 20)
	_mode.finances = _finances
	_port.add_child(_mode)
	_mode.set_process(false)
	_menu = BuildMenu.new()
	_menu.build_mode = _mode
	_port.add_child(_menu)
	_page = _menu.templates_page
	var edits: Array[BuildEdit] = []
	for y in range(2, 12):
		for x in range(2, 14):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	_mode.grid.apply_batch(edits)
	_room = _mode.grid.apply(BuildEdit.place_room(Rect2i(3, 3, 5, 4), &"cafe")).room_id
	_mode.grid.apply(BuildEdit.place_object(&"cafe_counter", Vector2i(4, 3), 0))


func after() -> void:
	_port.free()


func test_the_button_sits_outside_the_bar_and_opens_the_page() -> void:
	await await_idle_frame()
	assert_object(_menu.bar().find_child(TemplatesPage.BUTTON_NAME, true, false)).is_null()
	var found := _menu.find_child(TemplatesPage.BUTTON_NAME, true, false)
	assert_object(found).is_same(_page.button)
	var dock := _page.dock.get_global_rect()
	var bar := _menu.bar().get_global_rect()
	assert_float(dock.position.x).is_equal(BuildMenu.MARGIN)
	assert_float(dock.end.y).is_equal(bar.position.y - BuildMenu.GAP)
	_mode.set_tool(BuildMode.Tool.FLOOR)
	_menu.press_category(BuildMenu.TEMPLATES_PAGE)
	assert_bool(_menu.is_tray_open()).is_true()
	assert_bool(_page.visible).is_true()
	assert_bool(_page.button.button_pressed).is_true()
	assert_int(_mode.tool).is_equal(BuildMode.Tool.NONE)
	assert_bool(_menu.build_session.active).is_true()
	_menu.press_category(BuildMenu.TEMPLATES_PAGE)
	assert_bool(_menu.is_tray_open()).is_false()
	assert_bool(_page.visible).is_false()


func test_save_room_then_its_card_arms_the_paste_with_status_and_cost() -> void:
	_menu.press_category(BuildMenu.TEMPLATES_PAGE)
	assert_int(_page.card_count()).is_equal(0)
	_page.save_card().pressed.emit()
	assert_bool(_mode.templates.capturing).is_true()
	assert_bool(_page.save_card().button_pressed).is_true()
	assert_str(_menu.status_label().text).is_equal(TemplatePaste.PICK_ROOM)
	_mode.templates.click(Vector2i(4, 4))
	assert_int(_page.card_count()).is_equal(1)
	var texts: Array[String] = []
	for label in _page.card(0).find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	# The card shows a paste on bare ground: the counter and 20 floor tiles.
	var price := PriceTable.price_of_object(&"cafe_counter") + 20 * PriceTable.price_of_floor()
	assert_array(texts).contains(["Cafe 5x4", "5x4", str(price)])
	_page.card(0).pressed.emit()
	assert_int(_mode.templates.armed).is_equal(0)
	assert_bool(_page.card(0).button_pressed).is_true()
	assert_bool(_page.visible).is_true()
	assert_str(_menu.status_label().text).is_equal(TemplatePaste.PLACE_HINT % "Cafe 5x4")
	# BuildMode's own hover clears its line with no tool; the paste's text stays.
	_mode.status_changed.emit("")
	assert_str(_menu.status_label().text).is_equal(TemplatePaste.PLACE_HINT % "Cafe 5x4")
	_mode.status_changed.emit(UndoStack.UNDONE)
	assert_str(_menu.status_label().text).is_equal(UndoStack.UNDONE)
	_menu.press_category(BuildMenu.TEMPLATES_PAGE)
	assert_int(_mode.templates.armed).is_equal(-1)
