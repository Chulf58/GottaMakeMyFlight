class_name TestHoverTargetPassengers
extends GdUnitTestSuite
## HoverTarget in main.tscn (decision calm-view-technical-design-shared-hover-
## target-reusing-click, part 1): the hovered passenger is the one a click at the
## same point selects (PassengerHud's click order: a built object under the
## cursor needs the drawn body, open floor takes the 40 px circle); a sign over a
## passenger wins inside its rect and takes the click; a click on a passenger
## pins them until a click elsewhere, Esc, their view going or a load; and
## PassengerViews.draw() resolves the target before it lays anything out.

const SEED := 6_113_312
const FLIGHT_ID := "GMF101"
## Beside the click: off the drawn body, inside the 40 px circle.
const BESIDE_M := 0.6
const FAR_AWAY := Vector3(500.0, 0.0, 500.0)

var _settings_path := SaveTestKit.run_path("hover_target_alerts")

var _main: Node
var _hud: PassengerHud
var _mode: BuildMode
var _sim: PassengerSim
var _views: PassengerViews
var _hover: HoverTarget
var _eye: Camera3D
var _inspect: PassengerInspect
var _desk := 0
var _plain_cell := Vector2i(-1, -1)
var _stood: Array[int] = []
var _signs := FakeSignProvider.new()


func before() -> void:
	_main = load(SaveTestKit.MAIN).instantiate()
	(_main.get_node("SimClock") as SimClock).seed_rng(SEED)
	(_main.get_node("SimClock") as SimClock).set_paused(true)
	(_main.get_node("PassengerHud") as PassengerHud).alert_settings_path = _settings_path
	add_child(_main)
	_hud = _main.get_node("PassengerHud")
	_mode = _main.get_node("BuildMode")
	_sim = _main.get_node("PassengerSim")
	_views = _main.get_node("PassengerViews")
	_hover = _main.get_node("HoverTarget")
	(_main.get_node("TycoonCamera") as TycoonCamera).set_process(false)
	_eye = _main.get_node("TycoonCamera/Camera3D")
	_inspect = _hud.find_child("PassengerInspect", true, false) as PassengerInspect
	_hud.press_starter_terminal()
	StaffTestKit.staff_all(_main.get_node("Staff"))
	_desk = _sim.layout.desks[0]
	_plain_cell = _find_plain_cell()


func after() -> void:
	_main.free()
	DirAccess.remove_absolute(_settings_path)


func before_test() -> void:
	_mode.set_tool(BuildMode.Tool.NONE)
	_views.selected_id = 0
	_inspect.built_card.selection.clear()
	_hover.unregister_provider(_signs)
	_signs.signs.clear()
	_hover.set_process(true)
	_hover.pointer_override = Vector2(-1.0, -1.0)
	_hover.refresh()
	_hud.refresh()


func _find_plain_cell() -> Vector2i:
	var grid := _mode.grid
	var offset := ReferenceTerminal.offset_on(grid)
	var low := Vector2i(ReferenceTerminal.FLOOR_MIN.x + 1, ReferenceTerminal.DIVIDER_Y + 1) + offset
	var high := ReferenceTerminal.FLOOR_MAX + offset - Vector2i.ONE
	for y in range(low.y, high.y):
		for x in range(low.x, high.x):
			if _is_bare(grid, Rect2i(x - 2, y - 2, 5, 5)):
				return Vector2i(x, y)
	fail("no bare floor cell in the starter terminal")
	return Vector2i(-1, -1)


static func _is_bare(grid: BuildGrid, area: Rect2i) -> bool:
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var cell := Vector2i(x, y)
			if (
				grid.floor_at(cell) == BuildGrid.FLOOR_NONE
				or grid.object_at(cell) != 0
				or grid.room_at(cell) != 0
			):
				return false
	return true


func _look_at(target: Vector3) -> void:
	_eye.look_at_from_position(target + Vector3(0.0, 30.0, 4.0), target)


func _stand(at: Vector3) -> int:
	for earlier in _stood:
		if _views.node_for(earlier) != null:
			_views.node_for(earlier).position = FAR_AWAY
	var passenger := _sim.spawn_now(FLIGHT_ID)
	_stood.append(passenger)
	_views.sync()
	_views.node_for(passenger).position = at
	return passenger


## A real click pushed through the viewport, the dispatch frame waited for.
func _click_screen(screen: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = screen
	motion.global_position = screen
	_mode.pointer_override = screen
	get_viewport().push_input(motion, true)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = screen
	click.global_position = screen
	get_viewport().push_input(click, true)
	await await_idle_frame()
	_mode.pointer_override = Vector2(-1.0, -1.0)
	_hud.refresh()


func _hovered_at(screen: Vector2) -> int:
	_hover.pointer_override = screen
	_hover.refresh()
	return _hover.hovered_passenger()


## Hover at `screen`, then a real click there: [hovered id, selected id].
func _hover_then_click(screen: Vector2) -> Array[int]:
	var hovered := _hovered_at(screen)
	await _click_screen(screen)
	return [hovered, _views.selected_id]


func test_beside_a_desk_hover_and_click_both_take_the_desk_not_the_queue() -> void:
	var centre := _mode.grid.cell_to_world(_mode.grid.get_object(_desk)["anchor"])
	_look_at(centre)
	var point := _eye.unproject_position(centre + Vector3(0.0, 0.4, 0.0))
	var passenger := _stand(centre + Vector3(BESIDE_M, 0.0, 0.0))
	var circle := _views.pick(_eye, point)
	var got := await _hover_then_click(point)
	print("control circle %d; hovered %d clicked %d" % [circle, got[0], got[1]])
	assert_int(circle).is_equal(passenger)
	assert_int(got[0]).is_equal(0)
	assert_int(got[1]).is_equal(0)


func test_on_a_body_at_the_desk_hover_and_click_take_the_same_passenger() -> void:
	var centre := _mode.grid.cell_to_world(_mode.grid.get_object(_desk)["anchor"])
	_look_at(centre)
	var passenger := _stand(centre)
	var got := await _hover_then_click(_eye.unproject_position(centre + Vector3.UP))
	print("passenger %d; hovered %d clicked %d" % [passenger, got[0], got[1]])
	assert_int(got[0]).is_equal(passenger)
	assert_int(got[1]).is_equal(passenger)


func test_on_open_floor_hover_and_click_take_the_passenger_beside_the_point() -> void:
	var centre := _mode.grid.cell_to_world(_plain_cell)
	_look_at(centre)
	var passenger := _stand(centre + Vector3(BESIDE_M, 0.0, 0.0))
	var got := await _hover_then_click(_eye.unproject_position(centre))
	print("passenger %d; hovered %d clicked %d" % [passenger, got[0], got[1]])
	assert_int(got[0]).is_equal(passenger)
	assert_int(got[1]).is_equal(passenger)


func test_a_sign_over_a_passenger_wins_inside_its_rect_and_takes_the_click() -> void:
	var centre := _mode.grid.cell_to_world(_plain_cell)
	_look_at(centre)
	var passenger := _stand(centre)
	var head := _eye.unproject_position(centre + Vector3.UP)
	_signs.add(&"sign", Rect2(head - Vector2(10.0, 10.0), Vector2(20.0, 20.0)), "Closed by you")
	_hover.register_provider(_signs)
	var outside := head + Vector2(10.0 + HoverTarget.SIGN_MARGIN_PX + 4.0, 0.0)
	var on_sign := _hovered_at(head)
	var sign_kind := _hover.hovered_target().kind
	var beside := _hovered_at(outside)
	await _click_screen(head)
	var pinned := _hover.pinned_target()
	print(
		(
			"on sign: passenger %d kind %d; beside: %d; after click pinned %s selected %d"
			% [on_sign, sign_kind, beside, pinned.key if pinned else null, _views.selected_id]
		)
	)
	assert_int(on_sign).is_equal(0)
	assert_int(sign_kind).is_equal(HoverTarget.Kind.SIGN)
	assert_int(beside).is_equal(passenger)
	assert_that(pinned.key if pinned else null).is_equal(&"sign")
	assert_int(_views.selected_id).is_equal(0)


func test_a_clicked_passenger_stays_pinned_while_hovering_elsewhere_until_a_click_elsewhere(
) -> void:
	var centre := _mode.grid.cell_to_world(_plain_cell)
	_look_at(centre)
	var passenger := _stand(centre)
	await _click_screen(_eye.unproject_position(centre + Vector3.UP))
	_views.node_for(passenger).position = centre
	_hover.refresh()
	var pinned := _hover.pinned_passenger()
	var hovered_away := _hovered_at(Vector2(20.0, 20.0))
	var still := _hover.pinned_passenger()
	_views.node_for(passenger).position = centre
	await _click_screen(_eye.unproject_position(centre + Vector3(4.0, 0.0, 0.0)))
	_hover.refresh()
	print(
		(
			"pinned %d, hovered away %d, still %d, after click elsewhere %d"
			% [pinned, hovered_away, still, _hover.pinned_passenger()]
		)
	)
	assert_int(pinned).is_equal(passenger)
	assert_int(hovered_away).is_equal(0)
	assert_int(still).is_equal(passenger)
	assert_int(_hover.pinned_passenger()).is_equal(0)


func test_a_sign_click_ends_the_selection_and_follow_and_one_esc_clears_the_sign() -> void:
	var centre := _mode.grid.cell_to_world(_plain_cell)
	_look_at(centre)
	var passenger := _stand(centre)
	var rig := _main.get_node("TycoonCamera") as TycoonCamera
	var menu := _main.get_node("GameMenu") as GameMenu
	var head := _eye.unproject_position(centre + Vector3.UP)
	await _click_screen(head)
	var selected := _views.selected_id
	var following := rig.is_following()
	var sign_at := head + Vector2(120.0, 0.0)
	_signs.add(&"sign", Rect2(sign_at - Vector2(10.0, 10.0), Vector2(20.0, 20.0)), "Closed")
	_hover.register_provider(_signs)
	await _click_screen(sign_at)
	_hover.refresh()
	var pinned := _hover.pinned_target()
	var pinned_key: Variant = pinned.key if pinned else null
	var esc := InputEventAction.new()
	esc.action = &"build_tool_none"
	esc.pressed = true
	get_viewport().push_input(esc)
	await await_idle_frame()
	_hover.refresh()
	print(
		(
			(
				"before: selected %d following %s; after sign click: selected %d following %s "
				+ "item %d pinned %s; after one Esc: pinned %s menu open %s"
			)
			% [
				selected,
				following,
				_views.selected_id,
				rig.is_following(),
				_inspect.built_card.selection.kind,
				pinned_key,
				_hover.pinned_target(),
				menu.is_open()
			]
		)
	)
	assert_int(selected).is_equal(passenger)
	assert_bool(following).is_true()
	assert_that(pinned_key).is_equal(&"sign")
	assert_int(_views.selected_id).is_equal(0)
	assert_bool(rig.is_following()).is_false()
	assert_int(_inspect.built_card.selection.kind).is_equal(BuiltSelection.Kind.NONE)
	assert_object(_hover.pinned_target()).is_null()
	assert_bool(menu.is_open()).is_false()


func test_esc_clears_a_pinned_passenger() -> void:
	var centre := _mode.grid.cell_to_world(_plain_cell)
	_look_at(centre)
	var passenger := _stand(centre)
	await _click_screen(_eye.unproject_position(centre + Vector3.UP))
	_hover.refresh()
	var pinned := _hover.pinned_passenger()
	var esc := InputEventAction.new()
	esc.action = &"build_tool_none"
	esc.pressed = true
	get_viewport().push_input(esc)
	await await_idle_frame()
	_hover.refresh()
	print("pinned %d, after Esc %d" % [pinned, _hover.pinned_passenger()])
	assert_int(pinned).is_equal(passenger)
	assert_int(_hover.pinned_passenger()).is_equal(0)


func test_a_pinned_passenger_whose_view_goes_is_cleared() -> void:
	var centre := _mode.grid.cell_to_world(_plain_cell)
	_look_at(centre)
	var passenger := _stand(centre)
	await _click_screen(_eye.unproject_position(centre + Vector3.UP))
	_hover.refresh()
	var pinned := _hover.pinned_passenger()
	_sim.get_passenger(passenger).stage = Passenger.Stage.MADE
	_views.sync()
	_hover.refresh()
	print("pinned %d, after boarding %d" % [pinned, _hover.pinned_passenger()])
	assert_int(pinned).is_equal(passenger)
	assert_object(_views.node_for(passenger)).is_null()
	assert_int(_hover.pinned_passenger()).is_equal(0)


func test_a_load_clears_a_pinned_passenger() -> void:
	var centre := _mode.grid.cell_to_world(_plain_cell)
	_look_at(centre)
	var passenger := _stand(centre)
	await _click_screen(_eye.unproject_position(centre + Vector3.UP))
	_hover.refresh()
	var pinned := _hover.pinned_passenger()
	_hover.save_game.loaded.emit(true)
	_hover.refresh()
	print("pinned %d, after a load %d" % [pinned, _hover.pinned_passenger()])
	assert_int(pinned).is_equal(passenger)
	assert_int(_hover.pinned_passenger()).is_equal(0)


func test_passenger_views_draw_resolves_the_target_before_its_layout() -> void:
	var centre := _mode.grid.cell_to_world(_plain_cell)
	_look_at(centre)
	var passenger := _stand(centre)
	# HoverTarget's own frame step is off: only PassengerViews.draw() resolves.
	_hover.set_process(false)
	_hover.pointer_override = _eye.unproject_position(centre + Vector3.UP)
	var before := _hover.hovered_passenger()
	# What the bubble and icon layout would read, at the moment it begins.
	var seen := {}
	var record := func() -> void:
		seen["passenger"] = _hover.hovered_passenger()
		seen["frame"] = _hover.resolved_frame()
	_views.layout_started.connect(record)
	_views.draw()
	_views.layout_started.disconnect(record)
	var frame := Engine.get_process_frames()
	print(
		(
			"before draw %d; at layout start: passenger %s frame %s; now frame %d"
			% [before, seen.get("passenger"), seen.get("frame"), frame]
		)
	)
	assert_int(before).is_equal(0)
	assert_that(seen.get("passenger")).is_equal(passenger)
	assert_that(seen.get("frame")).is_equal(frame)


func test_in_a_real_frame_passenger_views_resolves_the_target() -> void:
	var centre := _mode.grid.cell_to_world(_plain_cell)
	_look_at(centre)
	var passenger := _stand(centre)
	_hover.set_process(false)
	_hover.pointer_override = _eye.unproject_position(centre + Vector3.UP)
	var before := _hover.hovered_passenger()
	await await_idle_frame()
	print("before the frame %d, after %d" % [before, _hover.hovered_passenger()])
	assert_int(before).is_equal(0)
	assert_int(_hover.hovered_passenger()).is_equal(passenger)
