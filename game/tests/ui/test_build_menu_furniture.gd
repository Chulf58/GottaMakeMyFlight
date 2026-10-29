class_name TestBuildMenuFurniture
extends GdUnitTestSuite
## The 29 furniture pieces in the build menu (Furniture 4/4 F4-2). The bar has
## no room for more buttons, and a tray holds at most four cards beside its
## Rotate card inside COLUMN_W, so the pieces sit on eight pages of one
## Furniture category: its button opens the first page, and a Next card on
## each page opens the following one (the last goes back to the first). Every
## card shows its name, size, price, a rendered thumbnail and, where the piece
## has a running cost, its upkeep.
##
## The three Stores pages (decision store-rooms-and-retail-pieces-go-on-stores-
## pages-behind-the-furniture-button; TestBuildMenuStores) follow the eight
## furniture pages behind the same button, so the group has eleven pages and
## the pharmacy counter and shelf sit on the pharmacy's Stores page, not Care.

## The pages behind the Furniture button: eight furniture pages, then three
## Stores pages (was 8 before the Stores pages joined the group).
const PAGE_COUNT := 11
const MAX_CARDS_PER_PAGE := 4
## The store tools on the Stores pages that are not furniture pieces.
const STORE_TOOLS := [
	BuildMode.Tool.PHARMACY_ROOM,
	BuildMode.Tool.DUTY_FREE_ROOM,
	BuildMode.Tool.DUTY_FREE_TILL,
	BuildMode.Tool.DUTY_FREE_SHELF,
	BuildMode.Tool.FASHION_ROOM,
	BuildMode.Tool.FASHION_TILL,
	BuildMode.Tool.FASHION_RAIL,
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
	_mode.set_process(false)
	_menu = BuildMenu.new()
	_menu.build_mode = _mode
	_port.add_child(_menu)
	_mode.set_tool(BuildMode.Tool.NONE)


func after_test() -> void:
	_port.free()


func _texts(control: Control) -> Array:
	var out := []
	for label in control.find_children("*", "Label", true, false):
		out.append((label as Label).text)
	return out


func _leader() -> int:
	var all := BuildMenu.categories()
	for i in all.size():
		if all[i]["name"] == "Furniture":
			return i
	return BuildMenu.NO_CATEGORY


func _pages() -> Array[int]:
	var out: Array[int] = []
	var first := _leader()
	for i in range(first, first + PAGE_COUNT):
		out.append(i)
	return out


func _next_button(page: int) -> Button:
	var tool: BuildMode.Tool = BuildMenu.categories()[page]["tools"][0]
	return _menu.card(tool).get_parent().find_child("CardNext", true, false) as Button


func test_one_furniture_button_on_the_bar_leads_all_its_pages_before_remove() -> void:
	var first := _leader()
	assert_int(first).is_not_equal(BuildMenu.NO_CATEGORY)
	var all := BuildMenu.categories()
	assert_str(all[first - 1]["name"]).is_equal("Baggage")
	assert_int(all.size()).is_equal(first + PAGE_COUNT + 1)
	assert_int(BuildMenu.REMOVE_CATEGORY).is_equal(all.size() - 1)
	assert_int(BuildMenu.remove_category()).is_equal(all.size() - 1)
	assert_str(all[BuildMenu.REMOVE_CATEGORY]["name"]).is_equal("Remove")
	for i in all.size():
		var is_page := first < i and i < first + PAGE_COUNT
		assert_bool(all[i].get("page", false)).override_failure_message("cat %d" % i).is_equal(
			is_page
		)
		assert_bool(_menu.category_button(i).visible).is_equal(not is_page)


func test_the_pages_hold_every_furniture_tool_once_and_at_most_four_cards() -> void:
	var seen := {}
	for page in _pages():
		var tools: Array = BuildMenu.categories()[page]["tools"]
		assert_int(tools.size()).is_between(1, MAX_CARDS_PER_PAGE)
		for tool in tools:
			# A furniture piece, or (on a Stores page) a store room or retail piece.
			var known: bool = FurnitureTools.OBJECTS.has(tool) or STORE_TOOLS.has(tool)
			assert_bool(known).override_failure_message("tool %d" % tool).is_true()
			assert_bool(seen.has(tool)).override_failure_message("tool %d twice" % tool).is_false()
			seen[tool] = true
			assert_int(BuildMenu.category_of(tool)).is_equal(page)
	for tool in FurnitureTools.OBJECTS:
		assert_bool(seen.has(tool)).override_failure_message("tool %d missing" % tool).is_true()
	for tool in STORE_TOOLS:
		assert_bool(seen.has(tool)).override_failure_message("tool %d missing" % tool).is_true()
	assert_int(seen.size()).is_equal(FurnitureTools.OBJECTS.size() + STORE_TOOLS.size())


func test_every_furniture_card_shows_name_size_price_and_a_rendered_thumbnail() -> void:
	assert_array(BuildMenu.PLACEHOLDER_THUMBNAILS).is_empty()
	# Every furniture piece, wherever its page (the store tools: TestBuildMenuStores).
	for tool in FurnitureTools.OBJECTS:
		_menu.press_category(BuildMenu.category_of(tool))
		var card := _menu.card(tool)
		assert_object(card).override_failure_message("tool %d" % tool).is_not_null()
		var id: StringName = FurnitureTools.OBJECTS[tool]
		var def := BuildCatalog.get_def(id)
		var texts := _texts(card)
		print("%s card: %s" % [id, texts])
		assert_str(BuildMenu.item(tool)[0]).is_not_empty()
		assert_array(texts).contains([BuildMenu.item(tool)[0]])
		assert_array(texts).contains(["%dx%d" % [def.size.x, def.size.y]])
		assert_int(BuildMenu.tool_price(tool)).is_equal(PriceTable.price_of_object(id))
		var path := BuildMenu.THUMBNAIL_DIR % BuildMenu.item(tool)[1]
		assert_bool(ResourceLoader.exists(path)).override_failure_message(path).is_true()
		var picture := card.find_children("*", "TextureRect", true, false)[0] as TextureRect
		assert_object(picture.texture).override_failure_message(path).is_not_null()
		assert_int(picture.get_child_count()).is_equal(0)


func test_the_price_slot_of_each_card_reads_its_price_with_a_wallet() -> void:
	var finances := Finances.new()
	add_child(finances)
	var mode := BuildMode.new()
	mode.finances = finances
	_port.add_child(mode)
	mode.set_process(false)
	var menu := BuildMenu.new()
	menu.build_mode = mode
	_port.add_child(menu)
	for tool in FurnitureTools.OBJECTS:
		var texts := _texts(menu.card(tool))
		var price := PriceTable.price_of_object(FurnitureTools.OBJECTS[tool])
		assert_array(texts).override_failure_message("tool %d" % tool).contains([str(price)])
	finances.free()


func test_the_podium_and_the_info_screen_show_their_upkeep() -> void:
	var podium := _menu.card(_tool_for(&"prize_podium"))
	var info := _menu.card(_tool_for(&"info_screen"))
	assert_array(_texts(podium)).contains(
		[BuildMenu.RUNNING_COST_TEXT % PriceTable.PRIZE_CAR_UPKEEP]
	)
	assert_array(_texts(info)).contains(
		[BuildMenu.RUNNING_COST_TEXT % PriceTable.INFO_SCREEN_UPKEEP]
	)
	# A plain piece says "Click".
	assert_array(_texts(_menu.card(_tool_for(&"bush")))).contains(["Click"])


func _tool_for(id: StringName) -> BuildMode.Tool:
	for tool in FurnitureTools.OBJECTS:
		if FurnitureTools.OBJECTS[tool] == id:
			return tool
	return BuildMode.Tool.NONE


func test_every_page_tray_fits_the_column_and_the_reserved_height() -> void:
	for page in _pages():
		_menu.press_category(page)
		var need := _menu.tray().get_combined_minimum_size()
		print("furniture page %d tray needs %s" % [page, need])
		assert_float(need.x).is_less_equal(BuildMenu.COLUMN_W)
		assert_float(need.y).is_less_equal(BuildMenu.TRAY_H)
		assert_object(_next_button(page)).is_not_null()
		var column := _menu.card(BuildMenu.categories()[page]["tools"][0]).get_parent()
		assert_object(column.find_child("CardRotate", true, false)).is_not_null()


func test_the_next_card_opens_the_following_page_and_the_last_goes_back_to_the_first() -> void:
	var pages := _pages()
	_menu.press_category(pages[0])
	for n in PAGE_COUNT:
		assert_int(_menu.open_category()).is_equal(pages[n])
		_next_button(pages[n]).pressed.emit()
		assert_int(_menu.open_category()).is_equal(pages[(n + 1) % PAGE_COUNT])
		assert_int(_mode.tool).is_equal(BuildMode.Tool.NONE)


func test_the_furniture_button_stays_pressed_on_every_page_and_reopens_the_first() -> void:
	var first := _leader()
	for page in _pages():
		_menu.press_category(page)
		for i in BuildMenu.categories().size():
			assert_bool(_menu.category_button(i).button_pressed).is_equal(i == first)
	# From the last page the Furniture button leads back to the first page.
	_menu.press_category(first)
	assert_int(_menu.open_category()).is_equal(first)
	_menu.press_category(first)
	assert_bool(_menu.is_tray_open()).is_false()


func test_picking_a_piece_by_tool_opens_its_page() -> void:
	var tool := _tool_for(&"prize_podium")
	_mode.set_tool(tool)
	assert_int(_menu.open_category()).is_equal(BuildMenu.category_of(tool))
	assert_bool(_menu.card(tool).button_pressed).is_true()
	assert_bool(_menu.category_button(_leader()).button_pressed).is_true()


func test_remove_still_picks_the_remove_tool_and_has_no_tray() -> void:
	_menu.press_category(_leader() + 3)
	_menu.press_category(BuildMenu.remove_category())
	assert_int(_mode.tool).is_equal(BuildMode.Tool.REMOVE)
	assert_bool(_menu.is_tray_open()).is_false()
	assert_bool(_menu.category_button(BuildMenu.remove_category()).button_pressed).is_true()
