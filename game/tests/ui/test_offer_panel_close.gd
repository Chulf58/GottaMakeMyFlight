class_name TestOfferPanelClose
extends GdUnitTestSuite
## OfferPanel closes on Esc and when the player picks a build tool or opens a
## category; the Offers button still toggles it, also when clicked for real.

var _port: SubViewport
var _desk: OfferDesk
var _sim: FlightSim
var _mode: BuildMode
var _menu: BuildMenu
var _panel: OfferPanel


func before_test() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(20, 20)
	_port.add_child(_mode)
	_menu = BuildMenu.new()
	_menu.build_mode = _mode
	_port.add_child(_menu)
	_desk = OfferDesk.new()
	_sim = FlightSim.new()
	_port.add_child(_desk)
	_port.add_child(_sim)
	_load(TestOfferBoard.day_records(0, [600, 660, 1200]))
	_panel = OfferPanel.new()
	_panel.desk = _desk
	_panel.flights = _sim
	_panel.build_mode = _mode
	_port.add_child(_panel)


func _load(offers: Array) -> void:
	assert_bool(_desk.board.from_snapshot(TestOfferBoard.save_of(offers))).is_true()


func after_test() -> void:
	_port.free()


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	return event


func test_esc_closes_the_open_sheet() -> void:
	_panel.open()
	_port.push_input(_key(KEY_ESCAPE))
	assert_bool(_panel.is_open()).is_false()


func test_esc_with_the_sheet_open_leaves_a_selected_tool_selected() -> void:
	_mode.set_tool(BuildMode.Tool.WALL)
	_panel.open()
	_port.push_input(_key(KEY_ESCAPE))
	assert_bool(_panel.is_open()).is_false()
	assert_int(_mode.tool).is_equal(BuildMode.Tool.WALL)


func test_esc_closes_a_sheet_that_has_no_build_mode_to_watch() -> void:
	var bare := OfferPanel.new()
	bare.desk = _desk
	bare.flights = _sim
	_port.add_child(bare)
	_panel.free()
	bare.open()
	_port.push_input(_key(KEY_ESCAPE))
	assert_bool(bare.is_open()).is_false()


func test_esc_with_the_sheet_closed_changes_nothing() -> void:
	_mode.set_tool(BuildMode.Tool.WALL)
	_port.push_input(_key(KEY_ESCAPE))
	assert_bool(_panel.is_open()).is_false()
	assert_int(_mode.tool).is_equal(BuildMode.Tool.NONE)


func test_picking_a_tool_card_closes_the_sheet() -> void:
	_panel.open()
	_menu.press_card(BuildMode.Tool.WALL)
	assert_bool(_panel.is_open()).is_false()
	assert_int(_mode.tool).is_equal(BuildMode.Tool.WALL)


func test_a_tool_key_closes_the_sheet() -> void:
	_panel.open()
	_port.push_input(_key(KEY_3))
	assert_int(_mode.tool).is_equal(BuildMode.Tool.DESK)
	assert_bool(_panel.is_open()).is_false()


func test_opening_a_category_closes_the_sheet() -> void:
	_panel.open()
	_menu.press_category(1)
	assert_bool(_panel.is_open()).is_false()


func test_picking_remove_closes_the_sheet() -> void:
	_panel.open()
	_menu.press_category(BuildMenu.REMOVE_CATEGORY)
	assert_bool(_panel.is_open()).is_false()


func test_the_button_still_toggles_the_sheet() -> void:
	_panel.toggle_button().pressed.emit()
	assert_bool(_panel.is_open()).is_true()
	_panel.toggle_button().pressed.emit()
	assert_bool(_panel.is_open()).is_false()
	_panel.toggle_button().pressed.emit()
	assert_bool(_panel.is_open()).is_true()


func test_a_panel_with_no_build_mode_still_works() -> void:
	var bare := OfferPanel.new()
	bare.desk = _desk
	bare.flights = _sim
	_port.add_child(bare)
	bare.open()
	assert_bool(bare.is_open()).is_true()
	bare.close()
	assert_bool(bare.is_open()).is_false()


## A press and a release of `button` at a point of the port.
func _mouse(button: MouseButton, at: Vector2) -> void:
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.pressed = down
		event.position = at
		event.global_position = at
		_port.push_input(event)


## Smoke playtest 8 (note 5): a real click on the Offers button closes the open
## sheet, also after the wheel turned over the sheet. (The playtest sent wheel
## presses with no release, which leaves the sheet holding Godot's mouse focus,
## so its next click never reached the button; a real wheel always releases.)
func test_a_real_click_on_the_button_closes_the_sheet_after_scrolling_over_it() -> void:
	await await_idle_frame()
	var at := _panel.toggle_button().get_global_rect().get_center()
	_mouse(MOUSE_BUTTON_LEFT, at)
	await await_idle_frame()
	assert_bool(_panel.is_open()).is_true()
	var sheet := _panel.get_node("OfferColumn/OfferSheet") as Control
	for i in 4:
		_mouse(MOUSE_BUTTON_WHEEL_UP, sheet.get_global_rect().get_center())
	await await_idle_frame()
	_mouse(MOUSE_BUTTON_LEFT, _panel.toggle_button().get_global_rect().get_center())
	await await_idle_frame()
	assert_bool(_panel.is_open()).is_false()
