class_name TestBuildUxControls
extends GdUnitTestSuite
## Regression tests for Build-UX playtest fixes:
## (1) 51ee969d: short right-click cancels an active drag/move or clears the
## armed tool to Tool.NONE while keeping BuildMenu's open tray open; right-drag
## (> CLICK_SLOP_PX) leaves the tool armed for camera orbiting; Esc closes tray.
## (2) 665f9cd1: Move on BuiltSelection.Kind.OBJECT (including inside a
## starter-kit room) uses ObjectMoveTool to move only that object at $0 net
## cost with overlap-self support, R rotate, undo, and cancel, while Kind.ROOM
## keeps "Move room" -> RoomMoveTool.

var _port: SubViewport
var _finances: Finances
var _mode: BuildMode
var _menu: BuildMenu
var _sim: PassengerSim
var _camera: TycoonCamera
var _eye: Camera3D
var _selection: BuiltSelection
var _card: BuiltItemCard
var _actions: BuiltItemActions


func before_test() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1536, 864)
	add_child(_port)
	_camera = TycoonCamera.new()
	_camera.settings_path = SaveTestKit.run_path("build_ux_controls_cam")
	_eye = Camera3D.new()
	_eye.name = "Camera3D"
	_camera.add_child(_eye)
	_port.add_child(_camera)
	_camera.set_process(false)
	_finances = Finances.new()
	_port.add_child(_finances)
	_finances.start_new_game()
	_mode = BuildMode.new()
	_mode.initial_tool = BuildMode.Tool.NONE
	_mode.grid_size = Vector2i(24, 24)
	_mode.finances = _finances
	_port.add_child(_mode)
	_mode.set_process(false)
	_menu = BuildMenu.new()
	_menu.build_mode = _mode
	_port.add_child(_menu)
	_sim = PassengerSim.new()
	_sim.grid = _mode.grid
	_port.add_child(_sim)
	_selection = BuiltSelection.new()
	_card = BuiltItemCard.new()
	_card.sim = _sim
	_card.selection = _selection
	_card.build_mode = _mode
	_card.visible = true
	_port.add_child(_card)
	_actions = BuiltItemActions.new()
	_actions.card = _card
	_actions.session = _menu.build_session
	_port.add_child(_actions)
	_paint_floor(Rect2i(1, 1, 18, 18))
	_eye.look_at_from_position(Vector3(0.0, 22.0, 3.0), Vector3.ZERO)


func after_test() -> void:
	var cam_path := _camera.settings_path
	_port.free()
	DirAccess.remove_absolute(cam_path)


func _paint_floor(area: Rect2i) -> void:
	var edits: Array[BuildEdit] = []
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	_mode.grid.apply_batch(edits)


func _mouse_btn(button: MouseButton, pressed: bool, pos: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	return ev


func _mouse_motion(pos: Vector2, rel: Vector2, mask := 0) -> InputEventMouseMotion:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	ev.relative = rel
	ev.button_mask = mask
	return ev


func _key(code: Key, ctrl := false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.ctrl_pressed = ctrl
	ev.pressed = true
	return ev


func _right_click(pos: Vector2, drag_delta := Vector2.ZERO) -> void:
	_port.push_input(_mouse_btn(MOUSE_BUTTON_RIGHT, true, pos))
	if drag_delta != Vector2.ZERO:
		_port.push_input(_mouse_motion(pos + drag_delta, drag_delta, MOUSE_BUTTON_MASK_RIGHT))
	_port.push_input(_mouse_btn(MOUSE_BUTTON_RIGHT, false, pos + drag_delta))


func _place_starter_kiosk(centre: Vector2i) -> int:
	assert_bool(_mode.starter_kit.try_arm(&"kiosk")).is_true()
	var result := _mode.starter_kit.place_at(centre)
	assert_bool(result.ok).is_true()
	_mode.starter_kit.disarm()
	return result.room_id


func _find_object_in_room(room_id: int, def_id: StringName) -> int:
	var rect: Rect2i = _mode.grid.get_room(room_id)["rect"]
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var oid := _mode.grid.object_at(Vector2i(x, y))
			if oid != 0 and _mode.grid.get_object(oid)["def"] == def_id:
				return oid
	return 0


func test_short_right_click_deselects_tool_while_keeping_tray_open() -> void:
	var ops := BuildMenu.category_index("operations")
	_menu.press_category(ops)
	_menu.press_card(BuildMode.Tool.DESK)
	assert_int(_mode.tool).is_equal(BuildMode.Tool.DESK)
	assert_bool(_menu.is_tray_open()).is_true()
	assert_int(_menu.open_category()).is_equal(ops)
	assert_bool(_menu.card(BuildMode.Tool.DESK).button_pressed).is_true()

	# Small jitter within CLICK_SLOP_PX still counts as a short right-click.
	_right_click(Vector2(200.0, 200.0), Vector2(3.0, 0.0))

	assert_int(_mode.tool).is_equal(BuildMode.Tool.NONE)
	assert_bool(_menu.is_tray_open()).is_true()
	assert_int(_menu.open_category()).is_equal(ops)
	assert_bool(_menu.card(BuildMode.Tool.DESK).button_pressed).is_false()

	# Esc still closes the tray as before.
	_port.push_input(_key(KEY_ESCAPE))
	assert_bool(_menu.is_tray_open()).is_false()
	assert_int(_menu.open_category()).is_equal(BuildMenu.NO_CATEGORY)


func test_right_drag_over_slop_keeps_armed_tool_and_orbits_camera() -> void:
	_menu.press_card(BuildMode.Tool.DESK)
	assert_int(_mode.tool).is_equal(BuildMode.Tool.DESK)
	var yaw_before := _camera.yaw

	_right_click(Vector2(200.0, 200.0), Vector2(24.0, 0.0))

	assert_int(_mode.tool).is_equal(BuildMode.Tool.DESK)
	assert_bool(_menu.is_tray_open()).is_true()
	assert_float(_camera.yaw).is_not_equal(yaw_before)


func test_short_right_click_keeps_room_context_tray_open_when_deselecting_furniture() -> void:
	_menu.press_card(BuildMode.Tool.KIOSK_COUNTER)
	assert_int(_mode.tool).is_equal(BuildMode.Tool.KIOSK_COUNTER)
	assert_bool(_menu.is_room_context()).is_true()

	_right_click(Vector2(200.0, 200.0))

	assert_int(_mode.tool).is_equal(BuildMode.Tool.NONE)
	assert_bool(_menu.is_tray_open()).is_true()
	assert_bool(_menu.is_room_context()).is_true()
	assert_bool(_menu.card(BuildMode.Tool.KIOSK_COUNTER).button_pressed).is_false()


func test_move_counter_inside_starter_kiosk_uses_object_mover_and_keeps_room() -> void:
	var kiosk_id := _place_starter_kiosk(Vector2i(8, 8))
	var room_before := _mode.grid.get_room(kiosk_id)
	var counter_id := _find_object_in_room(kiosk_id, &"kiosk_counter")
	var display_id := _find_object_in_room(kiosk_id, &"kiosk_display")
	assert_int(counter_id).is_not_equal(0)
	assert_int(display_id).is_not_equal(0)
	var counter_before := _mode.grid.get_object(counter_id)
	var display_before := _mode.grid.get_object(display_id)
	var wallet_before := _finances.wallet.balance
	_mode.clear_undo()

	_selection.select_object(counter_id)
	_card.refresh()
	_actions.refresh()

	assert_str(_actions.move_text()).is_equal(BuiltItemActions.MOVE)
	assert_bool(_actions.move_disabled()).is_false()
	assert_bool(_actions.press_move()).is_true()
	assert_bool(_mode.object_mover.active).is_true()
	assert_bool(_mode.room_mover.active).is_false()
	assert_bool(BuiltSelection.clicks_taken(_mode)).is_true()
	assert_bool(RotateHint.applies(_mode)).is_true()

	# Starter Kiosk at centre (8, 8) has rect (6, 7, 5, 4):
	# counter at (6, 8) facing 0 (occupies (6, 8) & (7, 8), front (6, 9), rear (6, 7));
	# display at (10, 8) facing 1 (occupies (10, 8) & (10, 9)).
	# Rotate facing 0 -> 1 (1x2 vertical at (7, 7) -> (7, 7) & (7, 8), overlapping (7, 8))
	# so both footprint and front/rear service cells remain inside the 5x4 kiosk room.
	_mode.object_mover.rotate_turns()
	assert_int(_mode.object_mover.turns).is_equal(1)
	_mode.object_mover.hover_at(Vector2i(7, 7))
	assert_bool(_mode.object_mover.refusal() == null).is_true()
	var moved := _mode.object_mover.set_down(Vector2i(7, 7))

	assert_bool(moved != null and moved.ok).is_true()
	assert_bool(_mode.object_mover.active).is_false()
	assert_int(_finances.wallet.balance).is_equal(wallet_before)
	assert_that(_mode.grid.get_room(kiosk_id)).is_equal(room_before)
	assert_that(_mode.grid.get_object(display_id)).is_equal(display_before)
	var counter_after := _mode.grid.get_object(counter_id)
	assert_bool(counter_after.is_empty()).is_false()
	assert_that(counter_after["anchor"]).is_equal(Vector2i(7, 7))
	assert_int(counter_after["facing"]).is_equal(1)
	assert_int(counter_after["paid"]).is_equal(counter_before["paid"])
	assert_int(_mode.undo_history().size()).is_equal(1)

	# Undo restores exact anchor, facing, id, paid, and $0 net balance.
	var undone := _mode.undo()
	assert_bool(undone != null and undone.ok).is_true()
	assert_int(_finances.wallet.balance).is_equal(wallet_before)
	assert_that(_mode.grid.get_object(counter_id)).is_equal(counter_before)
	assert_that(_mode.grid.get_object(display_id)).is_equal(display_before)


func test_object_move_cancels_on_short_right_click_and_esc_but_survives_right_drag() -> void:
	var kiosk_id := _place_starter_kiosk(Vector2i(8, 8))
	var counter_id := _find_object_in_room(kiosk_id, &"kiosk_counter")
	var counter_before := _mode.grid.get_object(counter_id)

	_selection.select_object(counter_id)
	_card.refresh()
	_actions.refresh()
	assert_bool(_actions.press_move()).is_true()
	assert_bool(_mode.object_mover.active).is_true()

	# Right-drag > slop must NOT cancel object_mover.
	_right_click(Vector2(200.0, 200.0), Vector2(20.0, 0.0))
	assert_bool(_mode.object_mover.active).is_true()

	# Short right-click cancels object_mover leaving original object untouched.
	_right_click(Vector2(200.0, 200.0))
	assert_bool(_mode.object_mover.active).is_false()
	assert_that(_mode.grid.get_object(counter_id)).is_equal(counter_before)

	# Esc also cancels object_mover cleanly.
	assert_bool(_actions.press_move()).is_true()
	assert_bool(_mode.object_mover.active).is_true()
	_port.push_input(_key(KEY_ESCAPE))
	assert_bool(_mode.object_mover.active).is_false()
	assert_that(_mode.grid.get_object(counter_id)).is_equal(counter_before)


func test_move_on_room_selection_keeps_move_room_and_room_mover() -> void:
	var kiosk_id := _place_starter_kiosk(Vector2i(8, 8))
	_selection.kind = BuiltSelection.Kind.ROOM
	_selection.id = kiosk_id
	_card.refresh()
	_actions.refresh()

	assert_str(_actions.move_text()).is_equal(BuiltItemActions.MOVE_ROOM)
	assert_bool(_actions.move_disabled()).is_false()
	assert_bool(_actions.press_move()).is_true()
	assert_bool(_mode.room_mover.active).is_true()
	assert_bool(_mode.object_mover.active).is_false()
	assert_int(_mode.room_mover.room_id).is_equal(kiosk_id)


func test_short_right_click_cancels_active_drag_before_deselecting_tool() -> void:
	var building := BuildMenu.category_index("building")
	_menu.press_category(building)
	_menu.press_card(BuildMode.Tool.FLOOR)
	assert_int(_mode.tool).is_equal(BuildMode.Tool.FLOOR)

	_mode.begin_area(_mode.grid.cell_to_world(Vector2i(2, 2)))
	_mode.move_area(_mode.grid.cell_to_world(Vector2i(4, 4)))
	assert_bool(_mode.is_dragging()).is_true()

	# First right-click cancels the drag while keeping the tool armed and tray open.
	_right_click(Vector2(200.0, 200.0))
	assert_bool(_mode.is_dragging()).is_false()
	assert_int(_mode.tool).is_equal(BuildMode.Tool.FLOOR)
	assert_bool(_menu.is_tray_open()).is_true()

	# Second short right-click clears the tool while keeping the tray open.
	_right_click(Vector2(200.0, 200.0))
	assert_int(_mode.tool).is_equal(BuildMode.Tool.NONE)
	assert_bool(_menu.is_tray_open()).is_true()
	assert_int(_menu.open_category()).is_equal(building)


func test_object_move_refuses_overlap_and_exposes_ghost_bounds_and_reason() -> void:
	var kiosk_id := _place_starter_kiosk(Vector2i(8, 8))
	var counter_id := _find_object_in_room(kiosk_id, &"kiosk_counter")
	var display_id := _find_object_in_room(kiosk_id, &"kiosk_display")
	var display_anchor: Vector2i = _mode.grid.get_object(display_id)["anchor"]
	var counter_before := _mode.grid.get_object(counter_id)
	var reason := GhostReason.new()
	reason.build_mode = _mode
	_port.add_child(reason)

	_selection.select_object(counter_id)
	_card.refresh()
	_actions.refresh()
	assert_bool(_actions.press_move()).is_true()

	# Hover onto display stand -> refused, keeps object_mover active, GhostReason sees refusal.
	var display_world := _mode.grid.cell_to_world(display_anchor) + Vector3(0.5, 0.0, 0.0)
	_mode.object_mover.hover_at(display_world)
	assert_bool(_mode.object_mover.refusal() != null).is_true()
	assert_bool(reason.refusal() != null).is_true()
	assert_bool(GhostBounds.build_rect(_mode, _eye).has_area()).is_true()

	var refused := _mode.object_mover.set_down(display_world)
	assert_bool(refused != null and not refused.ok).is_true()
	assert_bool(_mode.object_mover.active).is_true()
	assert_that(_mode.grid.get_object(counter_id)).is_equal(counter_before)
	_mode.object_mover.cancel()


func test_out_and_back_right_drag_keeps_armed_tool() -> void:
	var building := BuildMenu.category_index("building")
	_menu.press_category(building)
	_menu.press_card(BuildMode.Tool.WALL)
	assert_int(_mode.tool).is_equal(BuildMode.Tool.WALL)

	var origin := Vector2(200.0, 200.0)
	_port.push_input(_mouse_btn(MOUSE_BUTTON_RIGHT, true, origin))
	_port.push_input(
		_mouse_motion(origin + Vector2(28.0, 0.0), Vector2(28.0, 0.0), MOUSE_BUTTON_MASK_RIGHT)
	)
	_port.push_input(_mouse_motion(origin, Vector2(-28.0, 0.0), MOUSE_BUTTON_MASK_RIGHT))
	_port.push_input(_mouse_btn(MOUSE_BUTTON_RIGHT, false, origin))

	assert_int(_mode.tool).is_equal(BuildMode.Tool.WALL)
	assert_bool(_menu.is_tray_open()).is_true()

	_right_click(origin)
	assert_int(_mode.tool).is_equal(BuildMode.Tool.NONE)
	assert_bool(_menu.is_tray_open()).is_true()


func test_right_drag_keeps_room_mover_and_starter_kit_active_until_short_right_click() -> void:
	var shops := BuildMenu.category_index("shops")
	_menu.press_category(shops)
	assert_bool(_menu.is_tray_open()).is_true()
	assert_bool(_mode.starter_kit.try_arm(&"kiosk")).is_true()
	_right_click(Vector2(200.0, 200.0), Vector2(24.0, 0.0))
	assert_bool(_mode.starter_kit.is_active()).is_true()
	_right_click(Vector2(200.0, 200.0))
	assert_bool(_mode.starter_kit.is_active()).is_false()
	assert_bool(_menu.is_tray_open()).is_true()

	var kiosk_id := _place_starter_kiosk(Vector2i(8, 8))
	(
		assert_bool(_mode.room_mover.pick_up(_mode.grid.cell_to_world(Vector2i(8, 8)), &"kiosk"))
		. is_true()
	)
	assert_int(_mode.room_mover.room_id).is_equal(kiosk_id)
	assert_bool(_mode.room_mover.active).is_true()
	_right_click(Vector2(200.0, 200.0), Vector2(24.0, 0.0))
	assert_bool(_mode.room_mover.active).is_true()
	_right_click(Vector2(200.0, 200.0))
	assert_bool(_mode.room_mover.active).is_false()


func test_object_move_refuses_in_service_station_and_kept_clear_exit_cell() -> void:
	var kiosk_id := _place_starter_kiosk(Vector2i(8, 8))
	var counter_id := _find_object_in_room(kiosk_id, &"kiosk_counter")
	var display_id := _find_object_in_room(kiosk_id, &"kiosk_display")
	var counter_before := _mode.grid.get_object(counter_id)

	var visit := ShopVisit.new()
	visit.passenger = 1
	visit.room = kiosk_id
	visit.display = display_id
	visit.index = 0
	_sim.shops._core.reserve(visit)

	_selection.select_object(counter_id)
	_card.refresh()
	_actions.refresh()
	assert_bool(_actions.move_disabled()).is_true()
	assert_str(_actions.reason_text()).contains(ObjectMoveTool.IN_SERVICE_TEXT)
	assert_bool(_mode.object_mover.pick_up(counter_id, _sim)).is_false()
	assert_bool(_mode.object_mover.active).is_false()
	assert_that(_mode.grid.get_object(counter_id)).is_equal(counter_before)

	# Clear visit and verify EXIT_CELLS_META blocks dropping onto a passenger exit cell.
	_sim.shops._core.release(visit)
	_actions.refresh()
	assert_bool(_actions.move_disabled()).is_false()
	assert_bool(_actions.press_move()).is_true()

	var blocked_cell := Vector2i(3, 3)
	var prev_meta: Variant = _mode.grid.get_meta(RoomMove.EXIT_CELLS_META, Callable())
	_mode.grid.set_meta(RoomMove.EXIT_CELLS_META, func() -> Array[Vector2i]: return [blocked_cell])
	var result := _mode.object_mover.set_down(_mode.grid.cell_to_world(blocked_cell))
	_mode.grid.set_meta(RoomMove.EXIT_CELLS_META, prev_meta)
	assert_bool(result != null and not result.ok).is_true()
	assert_int(result.reason).is_equal(BuildResult.Reason.MOVE_EXIT_BLOCKED)
	assert_bool(_mode.object_mover.active).is_true()
	_mode.object_mover.cancel()


func test_object_move_cancels_when_held_object_edited_externally() -> void:
	var kiosk_id := _place_starter_kiosk(Vector2i(8, 8))
	var counter_id := _find_object_in_room(kiosk_id, &"kiosk_counter")
	var display_id := _find_object_in_room(kiosk_id, &"kiosk_display")

	assert_bool(_mode.object_mover.pick_up(counter_id, _sim)).is_true()
	assert_bool(_mode.grid.apply(BuildEdit.remove_object(counter_id)).ok).is_true()
	_mode.object_mover.hover_at(_mode.grid.cell_to_world(Vector2i(2, 2)))
	assert_bool(_mode.object_mover.active).is_false()

	# External edit before set_down cancels cleanly and returns null without touching the grid.
	assert_bool(_mode.object_mover.pick_up(display_id, _sim)).is_true()
	assert_bool(_mode.grid.apply(BuildEdit.remove_object(display_id)).ok).is_true()
	var res := _mode.object_mover.set_down(_mode.grid.cell_to_world(Vector2i(2, 2)))
	assert_object(res).is_null()
	assert_bool(_mode.object_mover.active).is_false()
	assert_int(_mode.grid.object_at(Vector2i(2, 2))).is_equal(0)


func test_object_move_refuses_gate_desk_with_due_flight() -> void:
	const SITE := preload("res://build/terminal_site.tres")
	var site_grid := SiteGrid.new(SITE)
	assert_bool(StarterShell.place(site_grid, SITE.starter_offset)).is_true()
	var flights := FlightSim.new()
	flights.open_airport()
	var gates := GateDesks.new()
	gates.bind(site_grid, flights)
	site_grid.guard = gates.edit_problem

	var desk_cell := ReferenceTerminal.GATE_DESK_CELL + SITE.starter_offset
	var placed := site_grid.apply(BuildEdit.place_object(GateDesks.DESK, desk_cell, 0))
	assert_bool(placed.ok).is_true()
	assert_object(ObjectMoveTool.never_moves_refusal(site_grid, placed.object_id)).is_null()

	assert_bool(flights.add_flight("ONE", FlightSim.schedule_starts(1000), "A")).is_true()
	var refusal := ObjectMoveTool.never_moves_refusal(site_grid, placed.object_id)
	assert_object(refusal).is_not_null()
	assert_int(refusal.reason).is_equal(BuildResult.Reason.GATE_IN_USE)
	gates.free()
	flights.free()


func test_object_move_refuses_reserved_display_stall_table_and_gate_seat() -> void:
	# 1. Reserved kiosk_display (ShopVisit.display).
	var kiosk_id := _place_starter_kiosk(Vector2i(8, 8))
	var display_id := _find_object_in_room(kiosk_id, &"kiosk_display")
	var shop_visit := ShopVisit.new()
	shop_visit.passenger = 1
	shop_visit.room = kiosk_id
	shop_visit.display = display_id
	shop_visit.index = 0
	_sim.shops._core.reserve(shop_visit)
	_assert_in_use_refused(display_id)
	_sim.shops._core.release(shop_visit)
	_assert_move_enabled(display_id)

	# 2. Reserved toilet_stall (ToiletVisit.stall_id).
	var toilet_room := _mode.grid.apply(BuildEdit.place_room(Rect2i(2, 2, 3, 3), &"toilet"))
	assert_bool(toilet_room.ok).is_true()
	var stall := _mode.grid.apply(BuildEdit.place_object(&"toilet_stall", Vector2i(3, 3), 0))
	assert_bool(stall.ok).is_true()
	var toilet_visit := ToiletVisit.new()
	toilet_visit.passenger = 2
	toilet_visit.room = toilet_room.room_id
	toilet_visit.stall_id = stall.object_id
	_sim.toilets._core.reserve(toilet_visit)
	_assert_in_use_refused(stall.object_id)
	_sim.toilets._core.release(toilet_visit)
	_assert_move_enabled(stall.object_id)

	# 3. Reserved cafe dining table (CafeVisit.seat["object_id"]).
	var cafe_room := _mode.grid.apply(BuildEdit.place_room(Rect2i(13, 2, 4, 4), &"cafe"))
	assert_bool(cafe_room.ok).is_true()
	var table := _mode.grid.apply(BuildEdit.place_object(&"cafe_table", Vector2i(14, 3), 0))
	assert_bool(table.ok).is_true()
	var cafe_visit := CafeVisit.new()
	cafe_visit.passenger = 3
	cafe_visit.room = cafe_room.room_id
	cafe_visit.seat = {"object_id": table.object_id}
	_sim.cafes._visits[3] = cafe_visit
	_assert_in_use_refused(table.object_id)
	_sim.cafes._visits.erase(3)
	_assert_move_enabled(table.object_id)

	# 4. Occupied gate seat_row (Passenger.seat_object).
	var row := _mode.grid.apply(BuildEdit.place_object(&"seat_row", Vector2i(2, 13), 0))
	assert_bool(row.ok).is_true()
	var pax := Passenger.new()
	pax.id = 99
	pax.stage = Passenger.Stage.SEATED
	pax.seat_object = row.object_id
	_sim._passengers.append(pax)
	_sim._by_id[pax.id] = pax
	_assert_in_use_refused(row.object_id)
	pax.seat_object = 0
	_assert_move_enabled(row.object_id)


func _assert_in_use_refused(object_id: int) -> void:
	_selection.select_object(object_id)
	_card.refresh()
	_actions.refresh()
	assert_bool(_actions.move_disabled()).is_true()
	assert_str(_actions.reason_text()).contains("Can't move while in use")
	assert_bool(_mode.object_mover.pick_up(object_id, _sim)).is_false()
	assert_bool(_mode.object_mover.active).is_false()


func _assert_move_enabled(object_id: int) -> void:
	_selection.select_object(object_id)
	_card.refresh()
	_actions.refresh()
	assert_bool(_actions.move_disabled()).is_false()
