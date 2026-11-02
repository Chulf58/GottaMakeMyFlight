class_name TestAlertStackRoom
extends GdUnitTestSuite
## On the real main scene, a drawn alert card is cut from the screen share the
## camera frames into (PanelRoom, decision panel-room-as-built-camera-frames-
## the-terminal-in-the-screen), so a click on a card lands the problem below
## the stack, not under it. A card coming or going only shifts the view: it is
## no panel opening or closing, so it never zooms.

const SEED := 5_120_311

var _main: Node
var _camera: TycoonCamera
var _hud: PassengerHud
var _stack: AlertStack
var _sim: PassengerSim


func before() -> void:
	_main = SaveTestKit.boot(self, SEED)
	_camera = _main.get_node("TycoonCamera")
	_hud = _main.get_node("PassengerHud")
	_sim = _main.get_node("PassengerSim")
	_stack = _hud.find_child("AlertStack", false, false) as AlertStack


func after() -> void:
	_main.free()


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
		. override_failure_message("alert cards are switched off in user://hud_settings.cfg")
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
