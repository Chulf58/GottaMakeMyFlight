class_name TestBuildMenuSessionLoad
extends GdUnitTestSuite
## A successful load ends build mode without giving back the clock held from
## before the load: the loaded clock is the player's (decision build-mode-pauses-
## the-game-while-a-build-tray-is-open-closin). A failed load changes nothing.

const STRUCTURE := 0

var _port: SubViewport
var _clock: SimClock
var _mode: BuildMode
var _save: SaveGame
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
	_save = SaveGame.new()
	_port.add_child(_save)
	_menu = BuildMenu.new()
	_menu.build_mode = _mode
	_menu.clock = _clock
	_menu.save_game = _save
	_port.add_child(_menu)


func after_test() -> void:
	_port.free()


## Building from a running 2x clock, then a load that leaves the clock paused at
## the same 2x: the state a restore of the held clock would undo.
func _build_from_running_2x_then_load_paused_2x() -> void:
	_clock.set_paused(false)
	_clock.set_speed(2)
	_menu.press_category(STRUCTURE)
	_menu.build_session.sync()
	_mode.set_tool(BuildMode.Tool.FLOOR)
	assert_bool(_mode.apply_at(_mode.grid.cell_to_world(Vector2i(1, 1))).ok).is_true()
	assert_int(_mode.undo_history().size()).is_equal(1)
	assert_bool(_clock.paused).is_true()
	_save.loaded.emit(true)


func test_a_load_paused_at_the_held_speed_stays_paused() -> void:
	_build_from_running_2x_then_load_paused_2x()
	_mode.set_tool(BuildMode.Tool.NONE)
	assert_bool(_clock.paused).is_true()
	assert_int(_clock.speed).is_equal(2)
	_menu.build_session.sync()
	assert_bool(_clock.paused).is_true()


func test_a_load_ends_build_mode_closes_the_tray_and_clears_undo() -> void:
	_build_from_running_2x_then_load_paused_2x()
	assert_bool(_menu.build_session.active).is_false()
	assert_bool(_menu.is_tray_open()).is_false()
	assert_int(_mode.tool).is_equal(BuildMode.Tool.NONE)
	assert_int(_mode.undo_history().size()).is_equal(0)
	assert_bool(_menu.build_frame.is_showing()).is_false()


func test_a_load_before_the_first_sync_drops_the_pending_hold() -> void:
	_menu.press_category(STRUCTURE)
	_save.loaded.emit(true)
	_menu.build_session.sync()
	assert_bool(_menu.build_session.active).is_false()
	assert_bool(_clock.paused).is_false()


func test_build_mode_starts_again_after_a_load() -> void:
	_build_from_running_2x_then_load_paused_2x()
	_clock.set_paused(false)
	_menu.press_category(STRUCTURE)
	_menu.build_session.sync()
	assert_bool(_clock.paused).is_true()
	_menu.press_category(STRUCTURE)
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.speed).is_equal(2)


func test_a_failed_load_leaves_build_mode_alone() -> void:
	_clock.set_speed(2)
	_menu.press_category(STRUCTURE)
	_menu.build_session.sync()
	_save.loaded.emit(false)
	assert_bool(_menu.build_session.active).is_true()
	assert_bool(_menu.is_tray_open()).is_true()
	assert_bool(_clock.paused).is_true()
