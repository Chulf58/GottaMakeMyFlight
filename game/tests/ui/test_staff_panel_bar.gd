class_name TestStaffPanelBar
extends GdUnitTestSuite
## The staff panel lives in the bottom category bar (decision hud-layout-bottom-
## category-bar-with-an-item-tray-time-and-fl): a Staff button on the bar opens
## the hiring card above it, like a tray, and the "Airport closed: ..." hint
## stays on screen whether the card is open or not.

const CHECKIN := StaffMember.Role.CHECKIN

var _port: SubViewport
var _mode: BuildMode
var _menu: BuildMenu
var _w: PassengerTestWorld
var _gate: AirportGate
var _panel: StaffPanel


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


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
	_w = PassengerTestWorld.reference_world()
	_w.auto_staff = false
	_gate = auto_free(AirportGate.new())
	_gate.bind(_w.flights, _w.staff)
	_panel = auto_free(StaffPanel.new())
	_panel.staff = _w.staff
	_panel.gate = _gate
	_panel.menu = _menu
	_port.add_child(_panel)


func after_test() -> void:
	_port.free()
	_w.free_all()
	_w = null


func test_the_bar_has_a_staff_button_and_the_card_starts_closed() -> void:
	var button := _menu.staff_button
	assert_bool(_menu.bar().is_ancestor_of(button)).is_true()
	assert_str(button.text).is_equal("Staff")
	assert_bool(_menu.staff_open).is_false()
	assert_bool(_panel.card().visible).is_false()
	assert_bool(button.button_pressed).is_false()


func test_the_staff_button_opens_the_card_above_the_bar_in_the_trays_place() -> void:
	_menu.staff_button.pressed.emit()
	assert_bool(_menu.staff_open).is_true()
	assert_bool(_panel.card().visible).is_true()
	assert_bool(_menu.is_tray_open()).is_false()
	assert_bool(_menu.staff_button.button_pressed).is_true()
	var card := _panel.card().get_global_rect()
	var bar := _menu.bar().get_global_rect()
	assert_float(card.end.y).is_less_equal(bar.position.y)
	assert_float(card.end.y).is_greater(bar.position.y - BuildMenu.GAP - 1.0)
	assert_float(card.get_center().x).is_equal_approx(bar.get_center().x, 1.0)


func test_the_card_is_no_longer_at_the_left_edge() -> void:
	_menu.staff_button.pressed.emit()
	var card := _panel.card()
	assert_float(card.anchor_left).is_equal(0.5)
	assert_float(card.anchor_top).is_equal(1.0)
	assert_float(card.get_global_rect().position.x).is_greater(200.0)


func test_the_staff_button_toggles_and_a_category_closes_the_card() -> void:
	_menu.staff_button.pressed.emit()
	_menu.staff_button.pressed.emit()
	assert_bool(_menu.staff_open).is_false()
	assert_bool(_panel.card().visible).is_false()
	_menu.staff_button.pressed.emit()
	_menu.category_button(2).pressed.emit()
	assert_bool(_menu.staff_open).is_false()
	assert_bool(_panel.card().visible).is_false()
	assert_bool(_menu.staff_button.button_pressed).is_false()
	assert_int(_menu.open_category()).is_equal(2)
	assert_bool(_menu.is_tray_open()).is_true()


func test_opening_staff_closes_an_open_tray_and_a_tool_key_closes_the_card() -> void:
	_menu.category_button(2).pressed.emit()
	_menu.staff_button.pressed.emit()
	assert_int(_menu.open_category()).is_equal(BuildMenu.NO_CATEGORY)
	assert_bool(_menu.is_tray_open()).is_false()
	assert_bool(_menu.category_button(2).button_pressed).is_false()
	_mode.set_tool(BuildMode.Tool.DESK)
	assert_bool(_menu.staff_open).is_false()
	assert_bool(_panel.card().visible).is_false()


func test_hire_through_the_card_in_the_bar() -> void:
	_menu.staff_button.pressed.emit()
	_panel.hire_button(CHECKIN).pressed.emit()
	assert_int(_w.staff.count(CHECKIN)).is_equal(1)


func test_the_closed_hint_stays_visible_with_the_card_closed_and_open() -> void:
	var hint := _panel.hint_label()
	assert_bool(_panel.card().visible).is_false()
	assert_bool(hint.is_visible_in_tree()).is_true()
	assert_str(hint.text).starts_with("Airport closed:")
	_menu.staff_button.pressed.emit()
	assert_bool(hint.is_visible_in_tree()).is_true()
	assert_str(hint.text).starts_with("Airport closed:")


func test_the_hint_sits_above_the_bar_and_clear_of_the_card() -> void:
	_menu.staff_button.pressed.emit()
	await get_tree().process_frame
	var hint := _panel.hint_label().get_global_rect()
	var card := _panel.card().get_global_rect()
	var bar := _menu.bar().get_global_rect()
	assert_float(hint.end.y).is_less_equal(card.position.y)
	assert_float(hint.end.y).is_less(bar.position.y)
	assert_float(hint.position.y).is_greater_equal(0.0)
	assert_float(hint.position.x).is_greater_equal(0.0)
	assert_float(hint.end.x).is_less_equal(1280.0)


func test_the_hint_does_not_take_mouse_input() -> void:
	assert_int(_panel.hint_label().mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)


func test_the_hint_clears_the_tray_status_and_cost_lines_with_a_tray_open() -> void:
	_menu.category_button(2).pressed.emit()
	await get_tree().process_frame
	_menu.status_label().text = "Facing auto"
	_menu.status_label().visible = true
	_menu.preview_label().text = "Cost 400   Short by 300"
	_menu.preview_label().visible = true
	await get_tree().process_frame
	assert_bool(_menu.is_tray_open()).is_true()
	var hint := _panel.hint_label().get_global_rect()
	assert_bool(hint.intersects(_menu.tray().get_global_rect())).is_false()
	assert_bool(hint.intersects(_menu.status_label().get_global_rect())).is_false()
	assert_bool(hint.intersects(_menu.preview_label().get_global_rect())).is_false()
	assert_float(hint.end.y).is_less_equal(_menu.preview_label().get_global_rect().position.y)
	assert_float(hint.position.y).is_greater_equal(0.0)
