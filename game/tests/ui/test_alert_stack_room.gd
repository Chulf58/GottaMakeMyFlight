class_name TestAlertStackRoom
extends GdUnitTestSuite
## On the real main scene, spawning or clearing right-rail alert cards leaves
## TycoonCamera position, zoom, and room (WHOLE_VIEW) completely steady, both
## with and without a build tray open (decision panel-room-camera-shifting-
## disabled-camera-stays-steady-for-panels-and-alerts, 66acd8b0). AlertStack
## rectangles still report through PanelRoom.open_rects() for SelectReveal, and
## clicking an alert card still glides the problem below the rail.

const SEED := 5_120_311

var _settings_path := SaveTestKit.run_path("alert_stack_room_setting")

var _main: Node
var _camera: TycoonCamera
var _hud: PassengerHud
var _stack: AlertStack
var _sim: PassengerSim


func before() -> void:
	_main = load(SaveTestKit.MAIN).instantiate()
	(_main.get_node("SimClock") as SimClock).seed_rng(SEED)
	(_main.get_node("SimClock") as SimClock).set_paused(true)
	# Its own settings file, so a player's alerts-off choice cannot fail this.
	(_main.get_node("PassengerHud") as PassengerHud).alert_settings_path = _settings_path
	add_child(_main)
	_camera = _main.get_node("TycoonCamera")
	_hud = _main.get_node("PassengerHud")
	_sim = _main.get_node("PassengerSim")
	_stack = _hud.find_child("AlertStack", false, false) as AlertStack


func after() -> void:
	_main.free()
	DirAccess.remove_absolute(_settings_path)


func before_test() -> void:
	_clean()
	_hud.refresh()
	await _settle()


func _room() -> PanelRoom:
	return _hud.get_node("PanelRoom")


func _settle() -> void:
	# Past PanelRoom's refit window, so a panel that opened while booting cannot
	# be what zooms the camera.
	for i in PanelRoom.REFIT_FRAMES + 2:
		await get_tree().process_frame
	for i in 200:
		_camera._process(0.05)


func _clean() -> void:
	for id in _sim.messes.mess_ids():
		_sim.messes.clean(id)


## DirtyAlert.SHOW_AT spills on floored, object-free cells three apart.
func _spills() -> void:
	var grid := _sim.grid
	var placed: Array[Vector2i] = []
	for y in grid.size.y:
		for x in grid.size.x:
			var c := Vector2i(x, y)
			if placed.size() == DirtyAlert.SHOW_AT:
				return
			if grid.floor_at(c) == BuildGrid.FLOOR_NONE or grid.object_at(c) != 0:
				continue
			if placed.any(func(p: Vector2i) -> bool: return maxi(absi(p.x - x), absi(p.y - y)) < 3):
				continue
			if _sim.messes.add(MessSim.Kind.SPILL, c) != 0:
				placed.append(c)


func test_a_drawn_card_keeps_the_camera_steady_and_never_zooms() -> void:
	(
		assert_bool(_stack.cards_on())
		. override_failure_message("alert cards are switched off in the test settings file")
		. is_true()
	)
	assert_bool(_stack.room_rect().has_area()).is_false()
	var key := _room().open_key()
	var distance := _camera.target_distance
	var before := _camera.room
	var eye := (_camera.get_node("Camera3D") as Camera3D).global_position
	var pos := _camera.position
	_spills()
	_hud.refresh()
	await _settle()
	assert_array(_stack.card_keys()).is_equal([DirtyAlert.KEY])
	var cards := _stack.room_rect()
	assert_bool(cards.has_area()).is_true()
	assert_bool(_room().open_rects().has(cards)).is_true()
	print(
		(
			"ALERT_ROOM cards=%s room=%s before=%s key=%d/%d distance=%.2f/%.2f"
			% [
				cards,
				_camera.room,
				before,
				key,
				_room().open_key(),
				distance,
				_camera.target_distance
			]
		)
	)
	assert_bool(_camera.room.is_equal_approx(TycoonCamera.WHOLE_VIEW)).is_true()
	assert_bool(_camera.room.is_equal_approx(before)).is_true()
	assert_vector(_camera.position).is_equal_approx(pos, Vector3.ONE * 0.001)
	assert_vector((_camera.get_node("Camera3D") as Camera3D).global_position).is_equal_approx(
		eye, Vector3.ONE * 0.001
	)
	assert_int(_room().open_key()).is_equal(key)
	assert_float(_camera.target_distance).is_equal(distance)
	_clean()
	_hud.refresh()
	await _settle()
	print(
		(
			"ALERT_ROOM_AFTER cards=%s keys=%s room=%s"
			% [_stack.room_rect(), _stack.card_keys(), _camera.room]
		)
	)
	assert_bool(_stack.room_rect().has_area()).is_false()
	assert_bool(_camera.room.is_equal_approx(before)).is_true()
	assert_vector((_camera.get_node("Camera3D") as Camera3D).global_position).is_equal_approx(
		eye, Vector3.ONE * 0.001
	)


func test_a_jump_lands_the_problem_below_the_stack() -> void:
	_spills()
	_hud.refresh()
	await _settle()
	var target: Vector3 = (_stack.board().alert(DirtyAlert.KEY)["targets"] as Array)[0]
	assert_bool(_stack.press_card(DirtyAlert.KEY)).is_true()
	await _settle()
	assert_bool(_camera.is_gliding()).is_false()
	var eye: Camera3D = _camera.get_node("Camera3D")
	var at := eye.unproject_position(target)
	var cards := _stack.room_rect()
	print("ALERT_JUMP target=%s screen=%s cards=%s" % [target, at, cards])
	assert_float(at.y).is_greater(cards.end.y)
	assert_bool(get_viewport().get_visible_rect().has_point(at)).is_true()


## Under ruling 66acd8b0, neither a drawn alert card nor opening a build tray
## zooms or shifts TycoonCamera.
func test_a_card_up_when_the_tray_opens_does_not_zoom_or_shift() -> void:
	var menu := _main.get_node("BuildMenu") as BuildMenu
	var mode := _main.get_node("BuildMode") as BuildMode
	var eye := _camera.get_node("Camera3D") as Camera3D
	var check_in := _operations_category()
	_camera.frame_start_view(StartView.area_for(mode.grid))
	_room().mark_sent()
	await _settle()
	var closed := _camera.target_distance
	var eye_closed := eye.global_position
	menu.press_category(check_in)
	await _settle()
	assert_bool(menu.is_tray_open()).is_true()
	assert_float(_camera.target_distance).is_equal_approx(closed, 0.01)
	assert_bool(_camera.room.is_equal_approx(TycoonCamera.WHOLE_VIEW)).is_true()
	assert_vector(eye.global_position).is_equal_approx(eye_closed, Vector3.ONE * 0.001)
	menu.press_category(check_in)
	await _settle()
	_spills()
	_hud.refresh()
	await _settle()
	assert_array(_stack.card_keys()).is_equal([DirtyAlert.KEY])
	menu.press_category(check_in)
	await _settle()
	var cards := _stack.room_rect()
	print(
		(
			"ALERT_TRAY closed=%.3f with_card=%.3f cards=%s room=%s"
			% [closed, _camera.target_distance, cards, _camera.room]
		)
	)
	assert_bool(menu.is_tray_open()).is_true()
	assert_bool(cards.has_area()).is_true()
	assert_bool(_room().open_rects().has(cards)).is_true()
	assert_bool(_camera.room.is_equal_approx(TycoonCamera.WHOLE_VIEW)).is_true()
	assert_float(_camera.target_distance).is_equal_approx(closed, 0.01)
	assert_vector(eye.global_position).is_equal_approx(eye_closed, Vector3.ONE * 0.001)
	menu.press_category(check_in)
	await _settle()
	assert_float(_camera.target_distance).is_equal_approx(closed, 0.01)
	assert_vector(eye.global_position).is_equal_approx(eye_closed, Vector3.ONE * 0.001)


## Under ruling 66acd8b0, spawning an alert card while a build tray is open
## leaves the camera room (WHOLE_VIEW), distance, and screen projection steady.
func test_a_card_with_the_tray_open_leaves_the_view_steady() -> void:
	var menu := _main.get_node("BuildMenu") as BuildMenu
	var mode := _main.get_node("BuildMode") as BuildMode
	var eye := _camera.get_node("Camera3D") as Camera3D
	var check_in := _operations_category()
	_camera.frame_start_view(StartView.area_for(mode.grid))
	_room().mark_sent()
	menu.press_category(check_in)
	await _settle()
	assert_bool(_camera.room.is_equal_approx(TycoonCamera.WHOLE_VIEW)).is_true()
	var bare := _corners(mode.grid)
	var eye_before := eye.global_position
	var dist_before := _camera.distance
	_spills()
	_hud.refresh()
	await _settle()
	assert_array(_stack.card_keys()).is_equal([DirtyAlert.KEY])
	assert_bool(_room().open_rects().has(_stack.room_rect())).is_true()
	var with_card := _corners(mode.grid)
	print("ALERT_STEADY room=%s bare=%s card=%s" % [_camera.room, bare, with_card])
	assert_bool(_camera.room.is_equal_approx(TycoonCamera.WHOLE_VIEW)).is_true()
	assert_float(_camera.distance).is_equal_approx(dist_before, 0.001)
	assert_vector(eye.global_position).is_equal_approx(eye_before, Vector3.ONE * 0.001)
	for i in bare.size():
		assert_vector(with_card[i]).is_equal_approx(bare[i], Vector2.ONE * 0.01)
	menu.press_category(check_in)
	await _settle()


## The start area's corners on the screen, floor and wall tops, south first:
## SW, SE (floor), SW, SE (wall tops), then the north ones.
func _corners(grid: BuildGrid) -> Array[Vector2]:
	var area := StartView.area_for(grid)
	var eye := _camera.get_node("Camera3D") as Camera3D
	var out: Array[Vector2] = []
	for z in [area.end.y, area.position.y]:
		for height in [0.0, _camera.frame_height]:
			for x in [area.position.x, area.end.x]:
				out.append(eye.unproject_position(Vector3(x, grid.origin.y + height, z)))
	return out


func _operations_category() -> int:
	return BuildMenu.category_of(BuildMode.Tool.DESK)
