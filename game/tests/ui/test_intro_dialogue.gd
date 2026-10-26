class_name TestIntroDialogue
extends GdUnitTestSuite
## The intro dialogue PassengerHud opens a new game with: it pauses the clock,
## is modal while open, closes on Continue, Space or Enter and then starts the
## clock at 1x, and opens once per session.

## Held W (pan forward) and Q (rotate left); TycoonCamera polls them each frame.
const CAMERA_ACTIONS: Array[StringName] = [&"cam_forward", &"cam_rotate_left"]

## The HUD, BuildMode and BuildMenu live in a 1920x1080 SubViewport so layout
## and pushed input see a real screen size.
var _port: SubViewport
var _world: PassengerTestWorld
var _hud: PassengerHud
var _mode: BuildMode
var _menu: BuildMenu
var _shown_before: bool


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_shown_before = IntroDialogue.shown_this_session
	IntroDialogue.shown_this_session = false
	var grid := PassengerTestWorld.floored(Vector2i(8, 6))
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(10, 20))
	_port = SubViewport.new()
	_port.size = Vector2i(1920, 1080)
	add_child(_port)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(10, 10)
	_port.add_child(_mode)
	_menu = BuildMenu.new()
	_menu.build_mode = _mode
	_port.add_child(_menu)
	_hud = PassengerHud.new()
	_hud.clock = _world.clock
	_hud.flights = _world.flights
	_hud.sim = _world.sim
	_hud.build_mode = _mode
	_port.add_child(_hud)


func after_test() -> void:
	for action in CAMERA_ACTIONS:
		Input.action_release(action)
	_port.free()
	_world.free_all()
	IntroDialogue.shown_this_session = _shown_before


func _key(code: Key, shift := false, echo := false, pressed := true) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.shift_pressed = shift
	event.echo = echo
	event.pressed = pressed
	return event


func _tap(code: Key, shift := false) -> void:
	_port.push_input(_key(code, shift))
	_port.push_input(_key(code, shift, false, false))


func _click(at: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		_port.push_input(event)


func test_a_hud_built_outside_the_running_scene_does_not_open_the_intro() -> void:
	# The control for every test below: they open it by hand.
	assert_bool(_hud.intro() != null).is_false()
	assert_bool(IntroDialogue.shown_this_session).is_false()


func test_opening_the_intro_pauses_the_clock() -> void:
	assert_bool(_world.clock.paused).is_false()
	assert_bool(_hud.open_intro()).is_true()
	assert_bool(_hud.intro() != null).is_true()
	assert_bool(_world.clock.paused).is_true()
	var tick := _world.clock.tick
	_world.clock.advance(1.0)
	assert_int(_world.clock.tick).is_equal(tick)


func test_the_intro_shows_the_portrait_nameplate_and_instructions() -> void:
	_hud.open_intro()
	var intro := _hud.intro()
	assert_bool(intro.is_visible_in_tree()).is_true()
	var portrait_node := intro.find_child("Portrait", true, false) as TextureRect
	assert_object(portrait_node.texture).is_same(IntroDialogue.PORTRAIT)
	assert_bool(portrait_node.is_visible_in_tree()).is_true()
	var name_label := intro.find_child("Name", true, false) as Label
	assert_str(name_label.text).is_equal("TERMINAL MANAGER")
	assert_bool(name_label.is_visible_in_tree()).is_true()
	var text := intro.body_text()
	assert_str(text).contains("check-in")
	assert_str(text).contains("security")
	assert_str(text).contains("gate")
	assert_str(text).contains("Space")
	assert_str(text).contains("Shift+1/2/3")
	assert_str(text).contains("clock starts when you close this")
	var screen := Rect2(Vector2.ZERO, Vector2(_port.size))
	var rects := intro.part_rects()
	for part in ["box", "nameplate", "portrait", "continue"]:
		var rect: Rect2 = rects[part]
		(
			assert_bool(rect.has_area() and screen.encloses(rect))
			. override_failure_message("%s rect %s is not on the screen" % [part, rect])
			. is_true()
		)
	# The portrait overlaps the box's left edge, as in the ruled layout.
	var portrait: Rect2 = rects["portrait"]
	var box: Rect2 = rects["box"]
	assert_bool(portrait.intersects(box)).is_true()
	assert_float(portrait.position.x).is_less(box.position.x)


func test_on_a_smaller_screen_the_box_still_clears_the_build_tray() -> void:
	_port.size = Vector2i(1280, 720)
	_hud.open_intro()
	var rects := _hud.intro().part_rects()
	var screen := Rect2(Vector2.ZERO, Vector2(_port.size))
	var box: Rect2 = rects["box"]
	# BOX_BOTTOM is the build bar, tray and status line height, in screen pixels.
	assert_float(box.end.y).is_less_equal(720.0 - IntroDialogue.BOX_BOTTOM)
	for part in ["box", "nameplate", "portrait", "continue"]:
		var rect: Rect2 = rects[part]
		(
			assert_bool(screen.encloses(rect))
			. override_failure_message("%s off screen" % part)
			. is_true()
		)


func test_continue_starts_the_clock_at_1x() -> void:
	_world.clock.set_speed(3)
	_hud.open_intro()
	var button: Button = _hud.intro().continue_button()
	_click(button.get_global_rect().get_center())
	assert_bool(_hud.intro() != null).is_false()
	assert_bool(_world.clock.paused).is_false()
	assert_int(_world.clock.speed).is_equal(1)
	var tick := _world.clock.tick
	_world.clock.advance(1.0)
	assert_int(_world.clock.tick).is_greater(tick)


func test_space_closes_the_intro_without_also_toggling_the_pause() -> void:
	_hud.open_intro()
	_tap(KEY_SPACE)
	assert_bool(_hud.intro() != null).is_false()
	assert_bool(_world.clock.paused).is_false()
	# The next Space is the HUD's pause toggle again.
	_tap(KEY_SPACE)
	assert_bool(_world.clock.paused).is_true()


func test_enter_closes_the_intro() -> void:
	_hud.open_intro()
	_tap(KEY_ENTER)
	assert_bool(_hud.intro() != null).is_false()
	assert_bool(_world.clock.paused).is_false()


## A real TycoonCamera in the viewport, handed to the HUD before the intro opens.
func _add_camera() -> TycoonCamera:
	var rig := (
		(load("res://camera/tycoon_camera.tscn") as PackedScene).instantiate() as TycoonCamera
	)
	_port.add_child(rig)
	_hud.camera = rig
	return rig


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _wheel_up() -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_WHEEL_UP
	event.pressed = true
	event.position = Vector2(_port.size) / 2.0
	event.global_position = event.position
	_port.push_input(event)


func test_keys_and_held_camera_keys_behind_the_open_intro_do_nothing() -> void:
	var rig := _add_camera()
	await _frames(2)
	var start := rig.position
	var start_yaw := rig.yaw
	# BuildMode starts on the Floor tool; key 2 would pick Wall.
	assert_int(_mode.tool).is_equal(BuildMode.Tool.FLOOR)
	_hud.open_intro()
	_tap(KEY_2)
	_tap(KEY_3, true)
	_port.push_input(_key(KEY_SPACE, false, true))
	for action in CAMERA_ACTIONS:
		Input.action_press(action)
	await _frames(5)
	assert_int(_mode.tool).is_equal(BuildMode.Tool.FLOOR)
	assert_int(_world.clock.speed).is_equal(1)
	assert_bool(_world.clock.paused).is_true()
	assert_bool(_hud.intro() != null).is_true()
	assert_vector(rig.position).is_equal(start)
	assert_float(rig.yaw).is_equal(start_yaw)
	# Control: the same held keys move the camera once the intro is closed.
	_hud.dismiss_intro()
	await _frames(5)
	assert_vector(rig.position).is_not_equal(start)
	assert_float(rig.yaw).is_not_equal(start_yaw)


func test_the_wheel_does_not_zoom_behind_the_open_intro() -> void:
	var rig := _add_camera()
	await _frames(2)
	var start := rig.target_distance
	_hud.open_intro()
	_wheel_up()
	assert_float(rig.target_distance).is_equal(start)
	# Control: the same notch zooms once the intro is closed.
	_hud.dismiss_intro()
	_wheel_up()
	assert_float(rig.target_distance).is_less(start)


func test_freeing_the_dialogue_directly_starts_the_clock_once() -> void:
	_world.clock.set_speed(3)
	_hud.open_intro()
	_hud.intro().free()
	assert_bool(_hud.intro() != null).is_false()
	assert_bool(_world.clock.paused).is_false()
	assert_int(_world.clock.speed).is_equal(1)
	# The emptied layer goes next frame; that must not reset the speed again.
	_world.clock.set_speed(2)
	await _frames(2)
	assert_int(_world.clock.speed).is_equal(2)
	assert_object(_hud.find_child("IntroLayer", false, false)).is_null()


func test_freeing_the_intro_layer_directly_starts_the_clock_and_frees_the_camera() -> void:
	var rig := _add_camera()
	await _frames(2)
	var start := rig.position
	_hud.open_intro()
	_hud.intro().get_parent().free()
	assert_bool(_hud.intro() != null).is_false()
	assert_bool(_world.clock.paused).is_false()
	assert_int(_world.clock.speed).is_equal(1)
	Input.action_press(CAMERA_ACTIONS[0])
	await _frames(5)
	assert_vector(rig.position).is_not_equal(start)


func test_a_click_on_the_build_bar_is_blocked_while_open_and_works_after() -> void:
	# BuildMode starts on Floor, which opens the first tray; start closed.
	_mode.set_tool(BuildMode.Tool.NONE)
	assert_int(_menu.open_category()).is_equal(BuildMenu.NO_CATEGORY)
	# Containers lay their buttons out on the next frame.
	await get_tree().process_frame
	var at := _menu.category_button(1).get_global_rect().get_center()
	_hud.open_intro()
	_click(at)
	assert_int(_menu.open_category()).is_equal(BuildMenu.NO_CATEGORY)
	_hud.dismiss_intro()
	_click(at)
	assert_int(_menu.open_category()).is_equal(1)


func test_the_intro_opens_once_per_session() -> void:
	assert_bool(_hud.open_intro()).is_true()
	_hud.dismiss_intro()
	assert_bool(IntroDialogue.shown_this_session).is_true()
	_world.clock.set_paused(false)
	assert_bool(_hud.open_intro()).is_false()
	assert_bool(_hud.intro() != null).is_false()
	assert_bool(_world.clock.paused).is_false()


func test_dismissing_with_nothing_open_changes_nothing() -> void:
	_world.clock.set_paused(true)
	_hud.dismiss_intro()
	assert_bool(_world.clock.paused).is_true()


func test_should_show_needs_a_first_showing_the_running_scene_and_no_playtest() -> void:
	assert_bool(IntroDialogue.should_show(false, true, false)).is_true()
	assert_bool(IntroDialogue.should_show(true, true, false)).is_false()
	assert_bool(IntroDialogue.should_show(false, false, false)).is_false()
	assert_bool(IntroDialogue.should_show(false, true, true)).is_false()
