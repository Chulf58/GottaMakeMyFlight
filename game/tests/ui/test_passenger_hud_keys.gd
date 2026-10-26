class_name TestPassengerHudKeys
extends GdUnitTestSuite
## PassengerHud's speed keys (Space, Shift+1/2/3) next to BuildMode's tool
## keys, the collapsed Debug panel and the follow text's place.

## The HUD and mode live in a 1280x720 SubViewport so layout and pushed
## input see a real screen size, not the headless window.
var _port: SubViewport
var _world: PassengerTestWorld
var _hud: PassengerHud
var _mode: BuildMode


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(8, 6))
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(10, 20))
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(10, 10)
	_port.add_child(_mode)
	_hud = PassengerHud.new()
	_hud.clock = _world.clock
	_hud.flights = _world.flights
	_hud.sim = _world.sim
	_hud.build_mode = _mode
	_port.add_child(_hud)


func after_test() -> void:
	_port.free()
	_world.free_all()


func _key(code: Key, shift := false, echo := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.shift_pressed = shift
	event.echo = echo
	event.pressed = true
	return event


func _push(event: InputEvent) -> void:
	_port.push_input(event)


func test_space_toggles_the_pause_and_keeps_the_speed() -> void:
	_hud.press_speed(2)
	_push(_key(KEY_SPACE))
	assert_bool(_world.clock.paused).is_true()
	assert_int(_world.clock.speed).is_equal(2)
	_push(_key(KEY_SPACE))
	assert_bool(_world.clock.paused).is_false()
	assert_int(_world.clock.speed).is_equal(2)


func test_a_held_space_does_not_toggle_again() -> void:
	_push(_key(KEY_SPACE))
	_push(_key(KEY_SPACE, false, true))
	assert_bool(_world.clock.paused).is_true()


func test_shift_numbers_set_the_speed_and_leave_the_build_tool() -> void:
	_mode.set_tool(BuildMode.Tool.WALL)
	_world.clock.set_paused(true)
	_push(_key(KEY_3, true))
	assert_int(_world.clock.speed).is_equal(3)
	assert_bool(_world.clock.paused).is_false()
	_push(_key(KEY_1, true))
	assert_int(_world.clock.speed).is_equal(1)
	assert_int(_mode.tool).is_equal(BuildMode.Tool.WALL)


func test_plain_numbers_still_pick_build_tools() -> void:
	_mode.set_tool(BuildMode.Tool.WALL)
	_world.clock.set_speed(2)
	_push(_key(KEY_1))
	assert_int(_mode.tool).is_equal(BuildMode.Tool.FLOOR)
	assert_int(_world.clock.speed).is_equal(2)


func test_the_debug_panel_starts_closed_and_its_toggle_opens_it() -> void:
	assert_bool(_hud.is_debug_open()).is_false()
	var toggle := _hud.find_child("DebugToggle", true, false) as Button
	toggle.button_pressed = true
	assert_bool(_hud.is_debug_open()).is_true()
	var panel := _hud.find_child("DebugPanel", true, false) as Control
	var texts := PackedStringArray()
	for label in panel.find_children("*", "Button", true, false):
		texts.append((label as Button).text)
	assert_array(Array(texts)).contains(["Spawn 300 passengers", "Starter terminal"])


func test_the_follow_text_stays_bottom_left_and_left_of_the_build_column() -> void:
	var label := _hud.find_child("FollowText", true, false) as Label
	var width := float(_port.size.x)
	assert_float(label.anchor_top).is_equal(1.0)
	assert_float(label.offset_left).is_equal(16.0)
	assert_float(label.offset_bottom).is_equal(-PassengerHud.FOLLOW_BOTTOM)
	assert_int(label.grow_vertical).is_equal(Control.GROW_DIRECTION_BEGIN)
	assert_float(label.offset_right).is_less_equal((width - BuildMenu.COLUMN_W) / 2.0)
	assert_float(PassengerHud.FOLLOW_BOTTOM).is_greater(BuildMenu.MARGIN + BuildMenu.BAR_H)


func test_time_counts_up_from_the_clock() -> void:
	_world.clock.tick = 125 * SimClock.TICK_RATE
	assert_str(_hud.time_text()).is_equal("Time 2:05")


func test_the_pause_button_pauses_and_resumes_at_the_same_speed() -> void:
	_hud.press_speed(3)
	var pause := (
		_hud.find_child("FlightPanel", true, false).find_children("*", "Button", true, false)[0]
		as Button
	)
	assert_str(pause.text).is_equal("Pause")
	pause.pressed.emit()
	assert_bool(_world.clock.paused).is_true()
	_hud.refresh()
	assert_bool(pause.button_pressed).is_true()
	pause.pressed.emit()
	assert_bool(_world.clock.paused).is_false()
	assert_int(_world.clock.speed).is_equal(3)


func test_long_debug_text_wraps_inside_the_debug_width() -> void:
	_hud.set_debug_open(true)
	_hud.press_debug_spawn()
	_hud.press_starter_terminal()
	_hud.refresh()
	await get_tree().process_frame
	var panel := _hud.find_child("DebugPanel", true, false) as Control
	assert_str(_hud.seed_text()).is_not_empty()
	assert_float(panel.get_global_rect().size.x).is_equal(PassengerHud.DEBUG_W)
