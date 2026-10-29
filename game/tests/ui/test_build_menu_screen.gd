class_name TestBuildMenuScreen
extends GdUnitTestSuite
## The screen stand in the build menu (Boredom 4/5): a Screen card in the Gates
## tray after Seats, with its price, its daily upkeep as its hint and its
## rendered thumbnail (Boredom 5/5); the tray keeps its Rotate card.

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


func _gates() -> int:
	var all := BuildMenu.categories()
	for i in all.size():
		if all[i]["name"] == "Gates":
			return i
	return BuildMenu.NO_CATEGORY


func _texts(control: Control) -> Array:
	var out := []
	for label in control.find_children("*", "Label", true, false):
		out.append((label as Label).text)
	return out


func test_the_gates_tray_holds_seats_then_the_screen() -> void:
	var gates := _gates()
	assert_int(gates).is_not_equal(BuildMenu.NO_CATEGORY)
	assert_array(BuildMenu.categories()[gates]["tools"]).is_equal(
		[BuildMode.Tool.SEATS, BuildMode.Tool.SCREEN]
	)
	assert_int(BuildMenu.category_of(BuildMode.Tool.SCREEN)).is_equal(gates)
	assert_str(str(BuildMode.TOOL_OBJECTS[BuildMode.Tool.SCREEN])).is_equal(
		str(ScreenCoverage.SCREEN_ID)
	)


func test_the_screen_card_shows_its_price_and_upkeep() -> void:
	_menu.category_button(_gates()).pressed.emit()
	var card := _menu.card(BuildMode.Tool.SCREEN)
	assert_object(card).is_not_null()
	var texts := _texts(card)
	print("screen card: %s" % [texts])
	assert_array(texts).contains(["Screen"])
	assert_array(texts).contains([BuildMenu.RUNNING_COST_TEXT % PriceTable.SCREEN_UPKEEP])
	assert_int(BuildMenu.tool_price(BuildMode.Tool.SCREEN)).is_equal(
		PriceTable.price_of_object(ScreenCoverage.SCREEN_ID)
	)
	# Its rendered thumbnail since Boredom 5/5, no longer a plain tile.
	assert_bool(BuildMenu.PLACEHOLDER_THUMBNAILS.has("screen_stand")).is_false()
	var picture := card.find_children("*", "TextureRect", true, false)[0] as TextureRect
	assert_object(picture.texture).is_not_null()
	assert_str(picture.texture.resource_path).is_equal(BuildMenu.THUMBNAIL_DIR % "screen_stand")
	assert_int(picture.find_children("*", "ColorRect", true, false).size()).is_equal(0)
	var row := card.get_parent()
	assert_object(row.get_node_or_null("CardRotate")).is_not_null()
