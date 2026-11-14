class_name TestHoverTargetSelectSign
extends GdUnitTestSuite
## On the real main scene, a click on a station's own problem sign selects that
## station exactly as a click on the station does, and pins nothing; a sign that
## marks no object (a wall gap) still pins and takes the click. Hovering a sign
## shows its text either way. The sign click also leaves the same state as a click
## on the station itself: while a passenger or vehicle is followed, with the
## station under the inspect card, after Esc, and with a build tool, a template
## paste or a room move holding the clicks.

const SEED := 6_113_312
const FLIGHT_ID := "GMF101"
const VIEW_DISTANCE := 40.0
const DECIDE_FRAMES := 4
const FLOOR_SIGN := Rect2(700.0, 120.0, 30.0, 30.0)
## Points on the desk to click, from its middle outwards, relative to its anchor.
const STATION_POINTS: Array[Vector3] = [
	Vector3(0.0, 0.4, 0.0),
	Vector3(0.0, 0.0, 0.0),
	Vector3(0.0, 0.8, 0.0),
	Vector3(0.3, 0.4, 0.0),
	Vector3(-0.3, 0.4, 0.0),
	Vector3(0.0, 0.4, 0.3),
	Vector3(0.0, 0.4, -0.3),
]
const ROOM_SIZE := Vector2i(3, 3)

var _settings_path := SaveTestKit.run_path("select_sign_alerts")
var _camera_settings_path := SaveTestKit.run_path("select_sign_camera")

var _main: Node
var _hud: PassengerHud
var _mode: BuildMode
var _sim: PassengerSim
var _rig: TycoonCamera
var _eye: Camera3D
var _inspect: PassengerInspect
var _hover: HoverTarget
var _markers: MissMarkers
var _views: PassengerViews
var _cars: LandsideViews
var _menu: GameMenu
var _desk := 0
var _home := Vector3.ZERO
var _car := 0
var _room := 0


func before() -> void:
	_main = load(SaveTestKit.MAIN).instantiate()
	(_main.get_node("SimClock") as SimClock).seed_rng(SEED)
	(_main.get_node("SimClock") as SimClock).set_paused(true)
	(_main.get_node("PassengerHud") as PassengerHud).alert_settings_path = _settings_path
	(_main.get_node("TycoonCamera") as TycoonCamera).settings_path = _camera_settings_path
	add_child(_main)
	_hud = _main.get_node("PassengerHud")
	_mode = _main.get_node("BuildMode")
	_sim = _main.get_node("PassengerSim")
	_rig = _main.get_node("TycoonCamera")
	_eye = _main.get_node("TycoonCamera/Camera3D")
	_inspect = _hud.find_child("PassengerInspect", true, false) as PassengerInspect
	_hover = HoverTarget.find(get_tree())
	_markers = _main.find_children("*", "MissMarkers", true, false)[0] as MissMarkers
	_views = _main.get_node("PassengerViews")
	_cars = _main.get_node("LandsideViews")
	_menu = _main.get_node("GameMenu")
	_hud.press_starter_terminal()
	_markers.sync()
	_desk = _sim.layout.desks[0]
	_rig.position = Vector3(_desk_world().x, 0.0, _desk_world().z)
	_rig.distance = VIEW_DISTANCE
	for i in 60:
		_rig._process(0.1)
	# The panel room reports its free area a few frames after the panels lay
	# out, and the real _process then eases the focus toward its middle, which
	# moves every sign under the pointer. The view is held where it was set.
	_rig.set_process(false)
	_home = _rig.position
	await await_idle_frame()


func after() -> void:
	_main.free()
	DirAccess.remove_absolute(_settings_path)
	DirAccess.remove_absolute(_camera_settings_path)


func before_test() -> void:
	await _reset()


## The world back to no selection, no follow, no glide, no held tool.
func _reset() -> void:
	_menu.close()
	await await_idle_frame()
	_mode.room_mover.cancel()
	_mode.templates.disarm()
	_mode.set_tool(BuildMode.Tool.NONE)
	_selection().clear()
	_views.selected_id = 0
	_cars.select(0)
	# follow(null) also ends any glide a case left running.
	_rig.follow(null)
	_rig.position = _home
	_hover.pointer_override = Vector2(-1.0, -1.0)
	_hud.refresh()


func _selection() -> BuiltSelection:
	return _inspect.built_card.selection


func _desk_world() -> Vector3:
	return _mode.grid.cell_to_world(_mode.grid.get_object(_desk)["anchor"])


## The centre of the Closed sign over the desk, in viewport px.
func _closed_sign_centre() -> Vector2:
	var key := "closed:%d" % _desk
	for entry in _markers.hover_signs():
		if entry["key"] == key:
			assert_int(entry["select"]).is_equal(_desk)
			return (entry["rect"] as Rect2).get_center()
	fail("no closed sign for desk %d: %s" % [_desk, _markers.hover_signs()])
	return Vector2(-1.0, -1.0)


func _hover_at(point: Vector2) -> void:
	_hover.pointer_override = point
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	get_viewport().push_input(motion, true)
	await await_idle_frame()


func _click_at(point: Vector2) -> void:
	await _hover_at(point)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = point
	click.global_position = point
	get_viewport().push_input(click, true)
	for i in DECIDE_FRAMES:
		await await_idle_frame()


func test_hovering_a_closed_desks_padlock_shows_its_text() -> void:
	var at := _closed_sign_centre()
	await _hover_at(at)
	var shown := _hover.shown_target()
	print("hover at %s: %s" % [at, shown.key if shown != null else null])
	assert_object(shown).is_not_null()
	assert_str(shown.key).is_equal("closed:%d" % _desk)
	assert_str(shown.text).is_not_empty()


func test_clicking_a_closed_desks_padlock_selects_the_desk_and_pins_nothing() -> void:
	var at := _closed_sign_centre()
	await _click_at(at)
	print("click at %s: selection %d, pinned %s" % [at, _selection().id, _hover.pinned_target()])
	assert_int(_selection().kind).is_equal(BuiltSelection.Kind.OBJECT)
	assert_int(_selection().id).is_equal(_desk)
	assert_bool(_inspect.visible).is_true()
	assert_object(_hover.pinned_target()).is_null()
	var status := _inspect.built_card.field_text("status")
	print("card status: %s; sign: %s" % [status, _markers.closed_text(_desk)])
	assert_str(status).starts_with("Status: Closed")


func test_clicking_a_sign_that_marks_no_object_still_pins_it() -> void:
	var provider := FakeSignProvider.new()
	provider.add(&"gap", FLOOR_SIGN, "A gap in the wall")
	_hover.register_provider(provider)
	_selection().select_object(_desk)
	_hud.refresh()
	await _click_at(FLOOR_SIGN.get_center())
	var pinned := _hover.pinned_target()
	print("click at the gap sign: pinned %s, selection %d" % [pinned, _selection().id])
	_hover.unregister_provider(provider)
	assert_object(pinned).is_not_null()
	assert_that(pinned.key).is_equal(&"gap")
	assert_bool(_selection().is_selected()).is_false()


## The state a click leaves, compared between a sign click and a station click.
func _snapshot() -> Dictionary:
	return {
		"kind": _selection().kind,
		"id": _selection().id,
		"passenger": _views.selected_id != 0,
		"vehicle": _cars.selected_id != 0,
		"following": _rig.is_following(),
		"gliding": _rig.is_gliding(),
		"menu": _menu.is_open(),
		"card": _inspect.visible,
		"pinned": _hover.pinned_target() != null,
	}


## The click on the station itself: a point on the desk that no sign covers.
func _click_station() -> void:
	var signs := _markers.hover_signs()
	for offset in STATION_POINTS:
		var at := _eye.unproject_position(_desk_world() + offset)
		var covered := false
		for entry in signs:
			var grown := (entry["rect"] as Rect2).grow(HoverTarget.SIGN_MARGIN_PX)
			covered = covered or grown.has_point(at)
		if not covered:
			await _click_at(at)
			return
	fail("every point on the desk is under a sign: %s" % [signs])


func _click_sign() -> void:
	await _click_at(_closed_sign_centre())


## Runs `held` (the setup), the sign click, `then` when given (Esc), and takes a
## snapshot; then a reset and the same again with the station click. Returns both
## snapshots: by sign, by station.
func _compare(held: Callable, then := Callable()) -> Array[Dictionary]:
	await held.call()
	await _click_sign()
	if then.is_valid():
		await then.call()
	var by_sign := _snapshot()
	await _reset()
	await held.call()
	await _click_station()
	if then.is_valid():
		await then.call()
	var by_station := _snapshot()
	print("by sign: %s\nby station: %s" % [by_sign, by_station])
	return [by_sign, by_station]


func _esc() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	get_viewport().push_input(event, true)
	await await_idle_frame()


func _follow_passenger() -> void:
	var id := _sim.spawn_now(FLIGHT_ID)
	_views.sync()
	_views.selected_id = id
	_rig.follow(_views.follow_anchor)
	_hud.refresh()
	assert_int(_views.selected_id).is_equal(id)
	assert_bool(_rig.is_following()).is_true()


## Follows one car; the first call adds it and every later call reuses it (a
## second car added to this world was not drawn).
func _follow_vehicle() -> void:
	if not _cars.has_vehicle(_car):
		var land: LandsideSim = _main.get_node("LandsideSim")
		_car = land.add_vehicle(LandsideVehicle.Kind.CAR, LandsideVehicle.Intent.DROP, [])
		_cars.sync()
		_cars.draw()
	assert_bool(_cars.has_vehicle(_car)).is_true()
	_cars.select(_car)
	_rig.follow(_cars.follow_anchor)
	_hud.refresh()
	assert_int(_cars.selected_id).is_equal(_car)
	assert_bool(_rig.is_following()).is_true()


func test_a_sign_click_while_following_a_passenger_stops_the_follow_like_a_station_click() -> void:
	var both := await _compare(_follow_passenger)
	assert_dict(both[0]).is_equal(both[1])
	assert_int(both[0]["id"]).is_equal(_desk)
	assert_bool(both[0]["passenger"]).is_false()
	assert_bool(both[0]["following"]).is_false()


func test_a_sign_click_while_following_a_vehicle_stops_the_follow_like_a_station_click() -> void:
	var both := await _compare(_follow_vehicle)
	assert_dict(both[0]).is_equal(both[1])
	assert_int(both[0]["id"]).is_equal(_desk)
	assert_bool(both[0]["vehicle"]).is_false()
	assert_bool(both[0]["following"]).is_false()


func _nothing() -> void:
	pass


## Parks the camera so the desk sits under the middle of the inspect card the
## desk's own selection opens, with the sign above it still clear of the card.
func _park_desk_under_card() -> void:
	_selection().select_object(_desk)
	_hud.refresh()
	var window := _inspect.get_global_rect()
	_selection().clear()
	_hud.refresh()
	assert_bool(window.has_area()).is_true()
	var at := window.get_center()
	var landing: Variant = BuildMode.ground_point(
		_eye.project_ray_origin(at), _eye.project_ray_normal(at), 0.0
	)
	assert_bool(landing != null).is_true()
	var move: Vector3 = _desk_world() - (landing as Vector3)
	_rig.position += Vector3(move.x, 0.0, move.z)
	await await_idle_frame()
	print("window %s, sign %s" % [window, _closed_sign_centre()])
	assert_bool(window.has_point(_eye.unproject_position(_desk_world()))).is_true()
	assert_bool(window.has_point(_closed_sign_centre())).is_false()


func test_a_sign_click_with_the_station_under_the_card_runs_the_reveal_glide_like_a_station_click(
) -> void:
	var both := await _compare(_park_desk_under_card)
	assert_dict(both[0]).is_equal(both[1])
	assert_int(both[0]["id"]).is_equal(_desk)
	assert_bool(both[0]["gliding"]).is_true()


func test_esc_after_a_sign_click_leaves_the_state_a_station_click_and_esc_leave() -> void:
	var both := await _compare(_nothing, _esc)
	assert_dict(both[0]).is_equal(both[1])
	assert_int(both[0]["kind"]).is_equal(BuiltSelection.Kind.NONE)
	assert_bool(both[0]["card"]).is_false()
	assert_bool(both[0]["menu"]).is_false()
	# The control: a second Esc opens the menu, so the first one found the card.
	await _esc()
	assert_bool(_menu.is_open()).is_true()


func test_esc_after_a_sign_click_stops_the_reveal_glide_like_a_station_click() -> void:
	var both := await _compare(_park_desk_under_card, _esc)
	assert_dict(both[0]).is_equal(both[1])
	assert_bool(both[0]["gliding"]).is_false()
	assert_int(both[0]["kind"]).is_equal(BuiltSelection.Kind.NONE)
	assert_bool(both[0]["menu"]).is_false()


func _hold_a_tool() -> void:
	_follow_passenger()
	_mode.set_tool(BuildMode.Tool.FLOOR)


func _hold_a_template_paste() -> void:
	_follow_passenger()
	_mode.templates.arm_capture()


## Lifts a room and then drops the tool, so the room move alone holds the clicks
## (the tool a Move button sets would hold them by itself).
func _hold_a_room_move() -> void:
	_follow_passenger()
	if _room == 0:
		var area := _free_room_area()
		assert_bool(_mode.grid.apply(BuildEdit.place_room(area, &"cafe")).ok).is_true()
		_room = _mode.grid.room_at(area.position)
	var rect: Rect2i = _mode.grid.get_room(_room)["rect"]
	_mode.set_tool_for_move(BuildMode.Tool.CAFE_ROOM)
	var lifted := _mode.room_mover.pick_up(_mode.grid.cell_to_world(rect.get_center()), &"cafe")
	assert_bool(lifted).is_true()
	_mode.tool = BuildMode.Tool.NONE
	assert_bool(BuiltSelection.clicks_taken(_mode)).is_true()


## The first 3 by 3 block of free landside-hall floor.
func _free_room_area() -> Rect2i:
	var grid := _mode.grid
	var offset := ReferenceTerminal.offset_on(grid)
	var low := Vector2i(ReferenceTerminal.FLOOR_MIN.x + 1, ReferenceTerminal.DIVIDER_Y + 1) + offset
	var high := ReferenceTerminal.FLOOR_MAX + offset - Vector2i.ONE
	for y in range(low.y, high.y - ROOM_SIZE.y + 2):
		for x in range(low.x, high.x - ROOM_SIZE.x + 2):
			var area := Rect2i(Vector2i(x, y), ROOM_SIZE)
			if _is_free(grid, area.grow(1)):
				return area
	fail("no free floor for a room")
	return Rect2i()


static func _is_free(grid: BuildGrid, area: Rect2i) -> bool:
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


## With a build interaction holding the clicks, the sign click and the station click
## both leave the followed passenger and the empty selection alone. The control: with
## the hold released, the same sign click selects the station.
func _assert_a_held_click_is_left_alone(hold: Callable) -> void:
	var both := await _compare(hold)
	assert_dict(both[0]).is_equal(both[1])
	assert_int(both[0]["kind"]).is_equal(BuiltSelection.Kind.NONE)
	assert_bool(both[0]["passenger"]).is_true()
	assert_bool(both[0]["following"]).is_true()
	assert_bool(both[0]["pinned"]).is_false()
	await _reset()
	await _click_sign()
	assert_int(_selection().id).is_equal(_desk)


func test_a_sign_click_with_a_build_tool_picked_is_ignored_like_a_station_click() -> void:
	await _assert_a_held_click_is_left_alone(_hold_a_tool)


func test_a_sign_click_with_a_template_paste_armed_is_ignored_like_a_station_click() -> void:
	await _assert_a_held_click_is_left_alone(_hold_a_template_paste)


func test_a_sign_click_during_a_room_move_is_ignored_like_a_station_click() -> void:
	await _assert_a_held_click_is_left_alone(_hold_a_room_move)
