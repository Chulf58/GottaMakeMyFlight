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
	assert_str(button.tooltip_text).is_equal("Staff")
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
	await await_idle_frame()
	var card := _panel.card()
	assert_float(card.anchor_left).is_equal(0.5)
	assert_float(card.anchor_top).is_equal(1.0)
	var rect := card.get_global_rect()
	var bar := _menu.bar().get_global_rect()
	# Five role columns centred at 1280 px sit well clear of the 16 px left edge.
	assert_float(rect.position.x).is_greater(144.0)
	assert_float(rect.end.x).is_less_equal(1280.0)
	assert_float(rect.end.y).is_less_equal(bar.position.y)
	var cols := (card.get_child(0) as Control).get_children()
	assert_int(cols.size()).is_equal(StaffPanel.ROLES.size())
	var col_rects: Array[Rect2] = []
	var btn_rects: Array[Rect2] = []
	for i in cols.size():
		var col_rect := (cols[i] as Control).get_global_rect()
		assert_bool(col_rect.has_area()).is_true()
		assert_bool(rect.encloses(col_rect)).is_true()
		for prev in col_rects:
			assert_bool(prev.intersects(col_rect)).is_false()
		col_rects.append(col_rect)
	for role in StaffPanel.ROLES:
		var hire_rect := _panel.hire_button(role).get_global_rect()
		var fire_rect := _panel.fire_button(role).get_global_rect()
		assert_bool(hire_rect.has_area() and fire_rect.has_area()).is_true()
		assert_bool(hire_rect.intersects(fire_rect)).is_false()
		for prev in btn_rects:
			assert_bool(prev.intersects(hire_rect)).is_false()
			assert_bool(prev.intersects(fire_rect)).is_false()
		btn_rects.append(hire_rect)
		btn_rects.append(fire_rect)


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
	assert_str(hint.text).is_equal(Checklist.TITLE_CLOSED)
	_menu.staff_button.pressed.emit()
	assert_bool(hint.is_visible_in_tree()).is_true()
	assert_str(hint.text).is_equal(Checklist.TITLE_CLOSED)


func test_the_hint_sits_above_the_bar_and_clear_of_the_card() -> void:
	_menu.staff_button.pressed.emit()
	await get_tree().process_frame
	var hint := _panel.hint_card().get_global_rect()
	var card := _panel.card().get_global_rect()
	var bar := _menu.bar().get_global_rect()
	assert_float(hint.end.y).is_less_equal(card.position.y)
	assert_float(hint.end.y).is_less(bar.position.y)
	assert_float(hint.position.y).is_greater_equal(0.0)
	assert_float(hint.position.x).is_greater_equal(0.0)
	assert_float(hint.end.x).is_less_equal(1280.0)


func test_the_hint_chrome_lets_clicks_through_while_actionable_rows_accept_clicks() -> void:
	assert_int(_panel.hint_card().mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	var saw_actionable := false
	for node in _panel.hint_card().find_children("*", "Control", true, false):
		var control := node as Control
		var rc := control as ChecklistCard.RowControl
		if rc != null and not rc.action.is_empty():
			saw_actionable = true
			assert_int(rc.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
		else:
			assert_int(control.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_bool(saw_actionable).is_true()

	var hint_rect := _panel.hint_card().get_global_rect()
	_panel.fade_for(Rect2(hint_rect.get_center(), Vector2(24.0, 24.0)), 10.0)
	for node in _panel.hint_card().find_children("*", "Control", true, false):
		assert_int((node as Control).mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)

	_panel.fade_for(Rect2(), 10.0)
	(
		_panel
		. checklist()
		. show_lines(
			"Test:",
			[
				Checklist.line("Empty action", false, "No jump"),
				Checklist.line("With action", false, "Jumps", {"kind": "staff", "role": CHECKIN}),
			]
		)
	)
	var rows := _panel.checklist().rows()
	assert_int(rows.size()).is_equal(2)
	assert_int((rows[0] as Control).mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int((rows[1] as Control).mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	for node in _panel.hint_card().find_children("*", "Control", true, false):
		var control := node as Control
		var rc := control as ChecklistCard.RowControl
		var expected := (
			Control.MOUSE_FILTER_STOP
			if rc != null and not rc.action.is_empty()
			else Control.MOUSE_FILTER_IGNORE
		)
		assert_int(control.mouse_filter).is_equal(expected)


func test_the_hint_clears_the_tray_status_and_cost_lines_with_a_tray_open() -> void:
	_menu.category_button(2).pressed.emit()
	await get_tree().process_frame
	_menu.status_label().text = "Facing auto"
	_menu.status_label().visible = true
	_menu.preview_label().text = "Cost 400   Short by 300"
	_menu.preview_label().visible = true
	await get_tree().process_frame
	assert_bool(_menu.is_tray_open()).is_true()
	var hint := _panel.hint_card().get_global_rect()
	assert_bool(hint.intersects(_menu.tray().get_global_rect())).is_false()
	assert_bool(hint.intersects(_menu.status_label().get_global_rect())).is_false()
	assert_bool(hint.intersects(_menu.preview_label().get_global_rect())).is_false()
	assert_float(hint.end.y).is_less_equal(_menu.preview_label().get_global_rect().position.y)
	assert_float(hint.position.y).is_greater_equal(0.0)


func test_status_card_clears_open_staff_card_and_drops_when_staff_closes() -> void:
	_mode.set_tool(BuildMode.Tool.NONE)
	_menu._on_wages_paid(60, 0)
	_menu.refresh_preview()
	await await_idle_frame()
	var bar_rect := _menu.bar().get_global_rect()
	assert_float(_menu.status_card().get_global_rect().end.y).is_equal(
		bar_rect.position.y - BuildMenu.GAP
	)
	_menu.press_staff()
	await await_idle_frame()
	await await_idle_frame()
	var staff_rect := _panel.card().get_global_rect()
	var card_rect := _menu.status_card().get_global_rect()
	assert_bool(_menu.staff_open).is_true()
	assert_bool(_panel.card().visible).is_true()
	assert_bool(_menu.status_card().visible).is_true()
	assert_float(card_rect.end.y).is_equal(staff_rect.position.y - BuildMenu.GAP)
	assert_bool(card_rect.intersects(staff_rect)).is_false()
	assert_float(_menu.stack_top()).is_equal(720.0 - card_rect.position.y)
	_menu.press_staff()
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(_menu.staff_open).is_false()
	assert_float(_menu.status_card().get_global_rect().end.y).is_equal(
		bar_rect.position.y - BuildMenu.GAP
	)


func _right_btn(pressed: bool, pos: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	return ev


func _right_motion(pos: Vector2, rel: Vector2) -> InputEventMouseMotion:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	ev.relative = rel
	ev.button_mask = MOUSE_BUTTON_MASK_RIGHT
	return ev


func test_short_right_click_closes_staff_panel_while_right_drag_orbits_camera() -> void:
	var cam := TycoonCamera.new()
	cam.settings_path = SaveTestKit.run_path("staff_panel_rclick_cam")
	var eye := Camera3D.new()
	eye.name = "Camera3D"
	cam.add_child(eye)
	_port.add_child(cam)
	cam.set_process(false)

	# 1. Right-drag beyond CLICK_SLOP_PX orbits camera and keeps StaffPanel open.
	_menu.press_staff()
	await await_idle_frame()
	assert_bool(_menu.staff_open).is_true()
	assert_bool(_panel.card().visible).is_true()
	var world_pt := Vector2(120.0, 120.0)
	var start_yaw := cam.yaw
	_port.push_input(_right_btn(true, world_pt))
	_port.push_input(_right_motion(world_pt + Vector2(30.0, 0.0), Vector2(30.0, 0.0)))
	_port.push_input(_right_btn(false, world_pt + Vector2(30.0, 0.0)))
	await await_idle_frame()
	assert_bool(_menu.staff_open).is_true()
	assert_bool(_panel.card().visible).is_true()
	assert_float(cam.yaw).is_not_equal(start_yaw)

	# 2. Out-and-back right-drag (beyond slop then returning to origin) also keeps StaffPanel open.
	_port.push_input(_right_btn(true, world_pt))
	_port.push_input(_right_motion(world_pt + Vector2(24.0, 0.0), Vector2(24.0, 0.0)))
	_port.push_input(_right_motion(world_pt, Vector2(-24.0, 0.0)))
	_port.push_input(_right_btn(false, world_pt))
	await await_idle_frame()
	assert_bool(_menu.staff_open).is_true()
	assert_bool(_panel.card().visible).is_true()

	# 3. Short right-click on the world closes StaffPanel and clears Staff button state.
	_port.push_input(_right_btn(true, world_pt))
	_port.push_input(_right_btn(false, world_pt + Vector2(2.0, 2.0)))
	await await_idle_frame()
	assert_bool(_menu.staff_open).is_false()
	assert_bool(_panel.card().visible).is_false()
	assert_bool(_menu.staff_button.button_pressed).is_false()

	# 4. Short right-click directly on StaffCard also closes StaffPanel.
	_menu.press_staff()
	await await_idle_frame()
	assert_bool(_menu.staff_open).is_true()
	var card_center := _panel.card().get_global_rect().get_center()
	_port.push_input(_right_btn(true, card_center))
	_port.push_input(_right_btn(false, card_center))
	await await_idle_frame()
	assert_bool(_menu.staff_open).is_false()
	assert_bool(_panel.card().visible).is_false()
	assert_bool(_menu.staff_button.button_pressed).is_false()

	var cam_path := cam.settings_path
	cam.free()
	DirAccess.remove_absolute(cam_path)


func test_right_click_ignores_modal_and_passes_through_when_staff_closed() -> void:
	var game_menu := GameMenu.new()
	game_menu.name = "GameMenu"
	game_menu.clock = _w.clock
	_port.add_child(game_menu)

	# 1. With GameMenu open over StaffPanel, short right-click does NOT close StaffPanel.
	_menu.press_staff()
	await await_idle_frame()
	assert_bool(_menu.staff_open).is_true()
	assert_bool(game_menu.open()).is_true()
	await await_idle_frame()
	assert_bool(game_menu.is_open()).is_true()
	var pt := Vector2(120.0, 120.0)
	_port.push_input(_right_btn(true, pt))
	_port.push_input(_right_btn(false, pt))
	await await_idle_frame()
	assert_bool(_menu.staff_open).is_true()
	assert_bool(_panel.card().visible).is_true()
	game_menu.close()
	await await_idle_frame()

	# 2. Close StaffPanel, then verify right-click passes through to _unhandled_input.
	_menu.press_staff()
	await await_idle_frame()
	assert_bool(_menu.staff_open).is_false()
	var spy := _UnhandledRightClickSpy.new()
	_port.add_child(spy)
	_port.push_input(_right_btn(true, pt))
	_port.push_input(_right_btn(false, pt))
	await await_idle_frame()
	assert_int(spy.releases).is_equal(1)

	spy.free()
	game_menu.free()


class _UnhandledRightClickSpy:
	extends Node

	var releases := 0

	func _unhandled_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb != null and not mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			releases += 1
