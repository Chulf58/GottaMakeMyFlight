class_name TestTemplatesPage
extends GdUnitTestSuite
## The Templates page inside the build tray (decisions room-templates-store-
## rooms-with-their-pieces-kept-in-each-sa and hud-layout-templates-tab-
## refinement-320-px-right-rail-compac): its button sits inside the bottom
## icon bar between the domain tabs and Remove (no detached TemplatesDock),
## opens the 106 px tray with no tool picked and build mode on, and renders
## uniform 80x96 preview cards with size/lock badges.

var _port: SubViewport
var _finances: Finances
var _mode: BuildMode
var _menu: BuildMenu
var _page: TemplatesPage
var _room := 0


func before() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1536, 864)
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


func test_the_button_sits_in_the_bar_between_landside_and_remove_and_opens_the_page() -> void:
	await await_idle_frame()
	assert_object(_menu.find_child("TemplatesDock", true, false)).is_null()
	var found := _menu.bar().find_child(TemplatesPage.BUTTON_NAME, true, false)
	assert_object(found).is_same(_page.button)
	var row := _page.button.get_parent()
	var names: Array[String] = []
	for child in row.get_children():
		names.append(String(child.name))
	assert_int(names.find(TemplatesPage.BUTTON_NAME)).is_equal(names.find("BarLandside") + 1)
	assert_int(names.find("BarRemove")).is_equal(names.find(TemplatesPage.BUTTON_NAME) + 1)
	_mode.set_tool(BuildMode.Tool.FLOOR)
	_menu.press_category(BuildMenu.TEMPLATES_PAGE)
	await await_idle_frame()
	assert_bool(_menu.is_tray_open()).is_true()
	assert_bool(_page.visible).is_true()
	assert_bool(_page.button.button_pressed).is_true()
	assert_int(_mode.tool).is_equal(BuildMode.Tool.NONE)
	assert_bool(_menu.build_session.active).is_true()
	assert_float(_menu.tray_height()).is_equal(BuildMenu.TRAY_H)
	assert_float(_menu.tray().size.y).is_equal(BuildMenu.TRAY_H)
	_menu.press_category(BuildMenu.TEMPLATES_PAGE)
	assert_bool(_menu.is_tray_open()).is_false()
	assert_bool(_page.visible).is_false()


func test_save_room_then_its_card_arms_the_paste_with_preview_and_cost() -> void:
	_menu.press_category(BuildMenu.TEMPLATES_PAGE)
	assert_int(_page.card_count()).is_equal(0)
	assert_vector(_page.save_card().custom_minimum_size).is_equal(BuildMenu.CARD_SIZE)
	_page.save_card().pressed.emit()
	assert_bool(_mode.templates.capturing).is_true()
	assert_bool(_page.save_card().button_pressed).is_true()
	assert_str(_menu.status_label().text).is_equal(TemplatePaste.PICK_ROOM)
	_mode.templates.click(Vector2i(4, 4))
	assert_int(_page.card_count()).is_equal(1)
	var card := _page.card(0)
	assert_vector(card.custom_minimum_size).is_equal(BuildMenu.CARD_SIZE)
	var pic := card.find_children("*", "TextureRect", true, false)[0] as TextureRect
	assert_object(pic.texture).is_not_null()
	assert_str(pic.texture.resource_path).is_equal(BuildMenuCatalog.THUMBNAIL_DIR % "cafe_room")
	assert_int(pic.find_children("*", "ColorRect", true, false).size()).is_equal(0)
	var texts: Array[String] = []
	for label in card.find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	var price := PriceTable.price_of_object(&"cafe_counter") + 20 * PriceTable.price_of_floor()
	assert_array(texts).contains(["Cafe 5x4", "5x4", str(price)])
	_page.card(0).pressed.emit()
	assert_int(_mode.templates.armed).is_equal(0)
	assert_bool(_page.card(0).button_pressed).is_true()
	assert_bool(_page.visible).is_true()
	assert_bool(RotateHint.applies(_mode)).is_true()
	assert_str(_menu.status_label().text).is_equal(TemplatePaste.PLACE_HINT % "Cafe 5x4")
	_mode.status_changed.emit("")
	assert_str(_menu.status_label().text).is_equal(TemplatePaste.PLACE_HINT % "Cafe 5x4")
	_mode.status_changed.emit(UndoStack.UNDONE)
	assert_str(_menu.status_label().text).is_equal(UndoStack.UNDONE)
	_menu.press_category(BuildMenu.TEMPLATES_PAGE)
	assert_int(_mode.templates.armed).is_equal(-1)


func test_locked_template_card_shows_lock_badge_and_updates_when_unlocked() -> void:
	var port := SubViewport.new()
	port.size = Vector2i(1536, 864)
	add_child(port)
	var unlocks := BuildUnlocks.new()
	unlocks.manual = true
	port.add_child(unlocks)
	var mode := BuildMode.new()
	mode.grid_size = Vector2i(20, 20)
	mode.unlocks = unlocks
	mode.require_unlocks = true
	port.add_child(mode)
	mode.set_process(false)
	var menu := BuildMenu.new()
	menu.build_mode = mode
	port.add_child(menu)
	var tpl := RoomTemplate.new()
	tpl.name = "Cafe 5x4"
	tpl.room_type = &"cafe"
	tpl.size = Vector2i(5, 4)
	for i in 20:
		tpl.floors.append(Vector2i(BuildGrid.FLOOR_TILE, 1))
	tpl.pieces.append({"def": &"cafe_counter", "anchor": Vector2i(1, 0), "facing": 0})
	mode.templates.library.add(tpl)
	menu.press_category(BuildMenu.TEMPLATES_PAGE)
	var card := menu.templates_page.card(0) as ItemCardButton
	var badge := card.get_node("TemplateBadge").get_child(0) as Label
	assert_str(badge.text).is_equal("Locked")
	assert_object(card.modulate).is_equal(BuildMenu.LOCKED_TINT)
	assert_str(card.requirement_now()).contains("Unlocks at")
	# Clicking a locked template card must NOT arm TemplatePaste or leave the card pressed.
	card.button_pressed = true
	card.pressed.emit()
	assert_int(mode.templates.armed).is_equal(-1)
	assert_bool(mode.templates.is_active()).is_false()
	assert_bool(card.button_pressed).is_false()
	assert_str(menu.status_label().text).contains("Unlocks at")
	# Unlock tier 2 (opens cafe) -> badge flips cleanly back to size and clicking arms paste.
	unlocks._tier = 2
	unlocks.tier_changed.emit(2)
	assert_str(badge.text).is_equal("5x4")
	assert_object(card.modulate).is_equal(Color.WHITE)
	assert_str(card.requirement_now()).is_empty()
	card.pressed.emit()
	assert_int(mode.templates.armed).is_equal(0)
	assert_str(menu.status_label().text).is_equal(TemplatePaste.PLACE_HINT % "Cafe 5x4")
	port.free()


func test_ten_plus_templates_show_horizontal_scrollbar_without_clipping_cards() -> void:
	var port := SubViewport.new()
	port.size = Vector2i(1280, 720)
	add_child(port)
	var mode := BuildMode.new()
	mode.grid_size = Vector2i(20, 20)
	port.add_child(mode)
	mode.set_process(false)
	var menu := BuildMenu.new()
	menu.build_mode = mode
	port.add_child(menu)
	for i in 10:
		var tpl := RoomTemplate.new()
		tpl.name = "Cafe %d" % i
		tpl.room_type = &"cafe"
		tpl.size = Vector2i(3, 3)
		for k in 9:
			tpl.floors.append(Vector2i(BuildGrid.FLOOR_TILE, 1))
		mode.templates.library.add(tpl)
	menu.press_category(BuildMenu.TEMPLATES_PAGE)
	await get_tree().process_frame
	await get_tree().process_frame
	var page := menu.templates_page
	var hbar := page.get_h_scroll_bar()
	assert_bool(hbar.visible).is_true()
	assert_float(menu.tray().size.y).is_equal_approx(menu.tray_height(), 0.5)
	assert_float(menu.tray().size.y).is_greater(BuildMenu.TRAY_H)
	var tray_rect := menu.tray().get_global_rect().grow(0.5)
	assert_bool(tray_rect.encloses(page.save_card().get_global_rect())).is_true()
	assert_bool(tray_rect.encloses(hbar.get_global_rect())).is_true()
	port.free()
