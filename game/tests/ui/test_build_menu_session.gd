class_name TestBuildMenuSession
extends GdUnitTestSuite
## Build mode (decision build-mode-pauses-the-game-while-a-build-tray-is-open-
## closin): a tray open or a tool picked pauses the sim; closing it gives the
## clock back as the player had it and clears the undo history. Space or a
## speed key while building ends it, and the Staff panel is not build mode.
## The clock is taken on the session's next sync(), which the tests call.

const STRUCTURE := 0

var _port: SubViewport
var _clock: SimClock
var _mode: BuildMode
var _menu: BuildMenu


func before_test() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_clock = SimClock.new()
	_port.add_child(_clock)
	_mode = BuildMode.new()
	_mode.initial_tool = BuildMode.Tool.NONE
	_mode.grid_size = Vector2i(20, 20)
	_port.add_child(_mode)
	_menu = BuildMenu.new()
	_menu.build_mode = _mode
	_menu.clock = _clock
	_port.add_child(_menu)


func after_test() -> void:
	_port.free()


func _key(code: Key, ctrl := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.ctrl_pressed = ctrl
	event.pressed = true
	return event


## What the HUD's keys do: 0 pauses, 1 to 3 run at that speed.
func _press_speed(value: int) -> void:
	_clock.set_paused(value == 0)
	if value > 0:
		_clock.set_speed(value)


func _sync() -> void:
	_menu.build_session.sync()


func _paint(cell: Vector2i) -> BuildResult:
	_mode.set_tool(BuildMode.Tool.FLOOR)
	return _mode.apply_at(_mode.grid.cell_to_world(cell))


func _steps() -> int:
	return _mode.undo_history().size()


func test_opening_a_tray_by_click_pauses_the_sim() -> void:
	_press_speed(2)
	_menu.press_category(STRUCTURE)
	_sync()
	assert_bool(_menu.build_session.active).is_true()
	assert_bool(_clock.paused).is_true()


func test_a_tool_key_pauses_the_sim() -> void:
	_press_speed(1)
	_port.push_input(_key(KEY_1))
	_sync()
	assert_int(_mode.tool).is_equal(BuildMode.Tool.FLOOR)
	assert_bool(_clock.paused).is_true()


func test_a_closed_menu_leaves_the_sim_running() -> void:
	_press_speed(2)
	_sync()
	assert_bool(_menu.build_session.active).is_false()
	assert_bool(_clock.paused).is_false()


func test_esc_ends_build_mode_and_restores_the_speed() -> void:
	_press_speed(3)
	_menu.press_category(STRUCTURE)
	_sync()
	_port.push_input(_key(KEY_ESCAPE))
	assert_bool(_menu.is_tray_open()).is_false()
	assert_bool(_menu.build_session.active).is_false()
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.speed).is_equal(3)


func test_clicking_the_open_category_again_ends_build_mode() -> void:
	_press_speed(2)
	_menu.press_category(STRUCTURE)
	_sync()
	_menu.press_category(STRUCTURE)
	assert_bool(_menu.build_session.active).is_false()
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.speed).is_equal(2)


func test_a_game_paused_before_stays_paused_after() -> void:
	_press_speed(2)
	_press_speed(0)
	_menu.press_category(STRUCTURE)
	_sync()
	_menu.press_category(STRUCTURE)
	assert_bool(_clock.paused).is_true()
	assert_int(_clock.speed).is_equal(2)


func test_switching_category_or_tool_stays_in_one_build_mode() -> void:
	_press_speed(2)
	_menu.press_category(STRUCTURE)
	_sync()
	_menu.press_category(1)
	_menu.press_card(BuildMode.Tool.WALL)
	_sync()
	assert_bool(_clock.paused).is_true()
	_port.push_input(_key(KEY_ESCAPE))
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.speed).is_equal(2)


func test_closing_build_mode_clears_the_undo_history() -> void:
	_menu.press_category(STRUCTURE)
	assert_bool(_paint(Vector2i(1, 1)).ok).is_true()
	assert_bool(_paint(Vector2i(2, 1)).ok).is_true()
	assert_int(_steps()).is_equal(2)
	_port.push_input(_key(KEY_ESCAPE))
	print("history after closing: %d steps" % _steps())
	assert_int(_steps()).is_equal(0)


func test_undo_works_inside_build_mode() -> void:
	_menu.press_category(STRUCTURE)
	_sync()
	assert_bool(_paint(Vector2i(1, 1)).ok).is_true()
	_port.push_input(_key(KEY_Z, true))
	assert_int(_steps()).is_equal(0)
	assert_int(_mode.grid.floor_at(Vector2i(1, 1))).is_equal(BuildGrid.FLOOR_NONE)


func test_ctrl_z_outside_build_mode_changes_nothing() -> void:
	_menu.press_category(STRUCTURE)
	assert_bool(_paint(Vector2i(1, 1)).ok).is_true()
	_port.push_input(_key(KEY_ESCAPE))
	_port.push_input(_key(KEY_Z, true))
	assert_int(_mode.grid.floor_at(Vector2i(1, 1))).is_not_equal(BuildGrid.FLOOR_NONE)
	assert_str(_mode.status_text()).contains(UndoStack.NOTHING_TO_UNDO)
	assert_object(_mode.undo()).is_null()


func test_unpausing_while_building_ends_build_mode_and_keeps_the_clock_running() -> void:
	_press_speed(2)
	_menu.press_category(STRUCTURE)
	_sync()
	_clock.set_paused(false)
	_sync()
	assert_bool(_menu.build_session.active).is_false()
	assert_bool(_menu.is_tray_open()).is_false()
	assert_int(_mode.tool).is_equal(BuildMode.Tool.NONE)
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.speed).is_equal(2)


func test_a_speed_key_while_building_ends_build_mode_at_that_speed() -> void:
	_press_speed(1)
	_menu.press_category(STRUCTURE)
	_sync()
	_press_speed(3)
	_sync()
	assert_bool(_menu.build_session.active).is_false()
	assert_bool(_menu.is_tray_open()).is_false()
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.speed).is_equal(3)


func test_a_speed_key_in_a_game_paused_before_ends_build_mode() -> void:
	_press_speed(2)
	_press_speed(0)
	_menu.press_category(STRUCTURE)
	_sync()
	_press_speed(2)
	_sync()
	assert_bool(_menu.build_session.active).is_false()
	assert_bool(_clock.paused).is_false()


func test_ending_by_the_clock_clears_the_undo_history() -> void:
	_menu.press_category(STRUCTURE)
	_sync()
	assert_bool(_paint(Vector2i(1, 1)).ok).is_true()
	_clock.set_paused(false)
	_sync()
	assert_int(_steps()).is_equal(0)


func test_the_staff_panel_is_not_build_mode() -> void:
	_press_speed(2)
	_menu.press_category(STRUCTURE)
	_sync()
	_menu.press_staff()
	assert_bool(_menu.build_session.active).is_false()
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.speed).is_equal(2)
	_sync()
	assert_bool(_clock.paused).is_false()


func test_remove_is_build_mode() -> void:
	_press_speed(1)
	_menu.press_category(_menu.remove_category())
	_sync()
	assert_bool(_menu.build_session.active).is_true()
	assert_bool(_clock.paused).is_true()


func test_a_menu_with_no_clock_still_clears_undo() -> void:
	var bare := BuildMenu.new()
	bare.build_mode = _mode
	_port.add_child(bare)
	bare.press_category(STRUCTURE)
	assert_bool(_paint(Vector2i(1, 1)).ok).is_true()
	bare.press_category(STRUCTURE)
	assert_int(_steps()).is_equal(0)
