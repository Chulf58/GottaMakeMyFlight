class_name TestBuildMenuNoRotateCard
extends GdUnitTestSuite
## The build trays carry no Rotate card (board 6bd94761, user: "There is a
## \"rotate R\" card in the build menus. Lets get rid of that"). R still turns
## the ghost through the build_rotate action, which BuildMode handles.

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
	_menu = BuildMenu.new()
	_menu.build_mode = _mode
	_port.add_child(_menu)


func after() -> void:
	_port.free()


func test_no_tray_holds_a_rotate_card() -> void:
	var rows := 0
	for i in BuildMenu.categories().size():
		_menu.press_category(i)
		var tray := _menu.tray()
		rows += 1
		assert_array(tray.find_children("CardRotate", "", true, false)).is_empty()
		for label in tray.find_children("*", "Label", true, false):
			var text := (label as Label).text
			assert_str(text).is_not_equal("Rotate")
			assert_str(text).is_not_equal("Key R")
	assert_int(rows).is_equal(BuildMenu.categories().size())


func test_a_paging_tray_still_has_its_next_card() -> void:
	var paging := 0
	for i in BuildMenu.categories().size():
		if BuildMenu.next_page(i) == BuildMenu.NO_CATEGORY:
			continue
		paging += 1
		var tool: BuildMode.Tool = BuildMenu.categories()[i]["tools"][0]
		var next := _menu.card(tool).get_parent().find_child("CardNext", true, false) as Control
		assert_object(next).is_not_null()
		# Full height: a half-height Next card (the old Rotate and Next stack) fails.
		assert_float(next.custom_minimum_size.y).is_equal(BuildMenu.CARD_SIZE.y)
	assert_int(paging).is_greater(0)


func test_the_r_key_still_turns_the_ghost() -> void:
	_menu.card(BuildMode.Tool.CART).pressed.emit()
	var before_facing := _mode.facing
	var press := InputEventAction.new()
	press.action = &"build_rotate"
	press.pressed = true
	_port.push_input(press)
	assert_int(_mode.facing).is_equal((before_facing + 1) % 4)
