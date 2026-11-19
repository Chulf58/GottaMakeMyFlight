class_name TestAlertStackRoom
extends GdUnitTestSuite
## On the real main scene, a drawn alert card is cut from the screen share the
## camera frames into (PanelRoom, decision panel-room-as-built-camera-frames-
## the-terminal-in-the-screen), so a click on a card lands the problem below
## the stack, not under it. A card coming or going only shifts the view: it is
## no panel opening or closing, so it never zooms.

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


func _free_pixels() -> Rect2:
	var size := get_viewport().get_visible_rect().size
	var free := _room().free_fraction()
	return Rect2(free.position * size, free.size * size)


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


func test_a_drawn_card_is_cut_from_the_camera_room_and_never_zooms() -> void:
	(
		assert_bool(_stack.cards_on())
		. override_failure_message("alert cards are switched off in the test settings file")
		. is_true()
	)
	assert_bool(_stack.room_rect().has_area()).is_false()
	var key := _room().open_key()
	var distance := _camera.target_distance
	var before := _camera.room
	_spills()
	_hud.refresh()
	await _settle()
	assert_array(_stack.card_keys()).is_equal([DirtyAlert.KEY])
	var cards := _stack.room_rect()
	assert_bool(cards.has_area()).is_true()
	assert_bool(_room().open_rects().has(cards)).is_true()
	var free := _free_pixels()
	print(
		(
			"ALERT_ROOM cards=%s free=%s before=%s key=%d/%d distance=%.2f/%.2f"
			% [cards, free, before, key, _room().open_key(), distance, _camera.target_distance]
		)
	)
	assert_bool(free.intersects(cards)).is_false()
	assert_bool(_camera.room.is_equal_approx(before)).is_false()
	assert_int(_room().open_key()).is_equal(key)
	assert_float(_camera.target_distance).is_equal(distance)
	_clean()
	_hud.refresh()
	await _settle()
	print(
		(
			"ALERT_ROOM_AFTER cards=%s keys=%s room=%s free=%s"
			% [_stack.room_rect(), _stack.card_keys(), _camera.room, _room().free_fraction()]
		)
	)
	assert_bool(_stack.room_rect().has_area()).is_false()
	assert_bool(_camera.room.is_equal_approx(before)).is_true()


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


## Board D3c: a card already up when a build tray opens must not zoom the view
## out. The tray's refit fits the start area to the screen share without the
## rail; before, the card's cut took the top strip of the screen and the camera
## went about half as far again (32 m to 50 m in the D3c probe).
func test_a_card_up_when_the_tray_opens_does_not_zoom() -> void:
	var menu := _main.get_node("BuildMenu") as BuildMenu
	var mode := _main.get_node("BuildMode") as BuildMode
	var check_in := _category("Check-in")
	_camera.frame_start_view(StartView.area_for(mode.grid), _room().free_fraction())
	_room().mark_sent()
	await _settle()
	var closed := _camera.target_distance
	menu.press_category(check_in)
	await _settle()
	var opened := _camera.target_distance
	var opened_room := _camera.room
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
			"ALERT_TRAY closed=%.3f opened=%.3f with_card=%.3f cards=%s room=%s/%s"
			% [closed, opened, _camera.target_distance, cards, opened_room, _camera.room]
		)
	)
	# Controls: the tray opening refits the distance, and the card is drawn
	# and cut from the room (the view shifts), so the case below is engaged.
	assert_bool(menu.is_tray_open()).is_true()
	assert_float(absf(opened - closed)).is_greater(0.05)
	assert_bool(cards.has_area()).is_true()
	assert_bool(_room().open_rects().has(cards)).is_true()
	assert_bool(_camera.room.is_equal_approx(opened_room)).is_false()
	assert_float(_camera.target_distance).is_equal_approx(opened, 0.01)
	menu.press_category(check_in)
	await _settle()
	assert_float(_camera.target_distance).is_equal_approx(closed, 0.01)


## Board D3c: on the start view a card's shift stops where the start area's
## south corners reach the tray stack's top, and the area stays inside the free
## share's left and right edges. With no card the room is the free share as is.
func test_a_card_never_pushes_the_start_area_under_the_tray() -> void:
	var menu := _main.get_node("BuildMenu") as BuildMenu
	var mode := _main.get_node("BuildMode") as BuildMode
	var check_in := _category("Check-in")
	_camera.frame_start_view(StartView.area_for(mode.grid), _room().free_fraction())
	_room().mark_sent()
	menu.press_category(check_in)
	await _settle()
	assert_bool(_camera.room.is_equal_approx(_room().free_fraction())).is_true()
	var bare := _corners(mode.grid)
	_spills()
	_hud.refresh()
	await _settle()
	assert_array(_stack.card_keys()).is_equal([DirtyAlert.KEY])
	var size := get_viewport().get_visible_rect().size
	var tray_top := size.y - menu.stack_top()
	var fit := _room().fit_fraction()
	var with_card := _corners(mode.grid)
	print(
		(
			"ALERT_CLAMP tray_top=%.1f fit=%s room=%s free=%s bare=%s card=%s"
			% [tray_top, fit, _camera.room, _room().free_fraction(), bare, with_card]
		)
	)
	# Control: the card still shifts the view, down from where it was.
	assert_float(with_card[0].y).is_greater(bare[0].y + 1.0)
	for at in with_card:
		assert_float(at.y).is_less_equal(tray_top + 0.5)
		assert_float(at.x).is_between(fit.position.x * size.x - 0.5, fit.end.x * size.x + 0.5)
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


func _category(_category_name: String) -> int:
	return BuildMenu.category_of(BuildMode.Tool.DESK)
