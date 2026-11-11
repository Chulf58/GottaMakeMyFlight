class_name TestBuildUndoAfterEsc
extends GdUnitTestSuite
## The undo history survives ending build mode (Esc or closing the tray) until
## the sim clock advances a tick (user-ruled 2026-11-11, decision build-mode-
## pauses-the-game-while-a-build-tray-is-open-closin): Esc then Ctrl+Z still
## undoes the last build and refunds it, because nothing can have happened while
## the clock has not moved. One tick, a load or an outside edit and it is gone.
## Keys go through the viewport, as the player's do.

const STRUCTURE := 0
const DOOR_CELL := Vector2i(9, 4)

var _port: SubViewport
var _clock: SimClock
var _finances: Finances
var _mode: BuildMode
var _save: SaveGame
var _menu: BuildMenu


## A 14x14 grid with floor on columns 0 to 9, so (9, 4) is an edge cell.
func before_test() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_clock = SimClock.new()
	_port.add_child(_clock)
	_finances = Finances.new()
	_port.add_child(_finances)
	_mode = BuildMode.new()
	_mode.initial_tool = BuildMode.Tool.NONE
	_mode.grid_size = Vector2i(14, 14)
	_mode.finances = _finances
	_port.add_child(_mode)
	var edits: Array[BuildEdit] = []
	for y in 14:
		for x in 10:
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	_mode.grid.apply_batch(edits)
	_mode.clear_undo()
	_save = SaveGame.new()
	_port.add_child(_save)
	_menu = BuildMenu.new()
	_menu.build_mode = _mode
	_menu.clock = _clock
	_menu.save_game = _save
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


func _balance() -> int:
	return _finances.wallet.balance


## Opens the tray, takes the clock and places an entrance on DOOR_CELL. Returns
## the balance before the door.
func _build_a_door() -> int:
	_menu.press_category(STRUCTURE)
	_menu.build_session.sync()
	_mode.set_tool(BuildMode.Tool.ENTRANCE)
	var before := _balance()
	var result := _mode.apply_at(_mode.grid.cell_to_world(DOOR_CELL))
	assert_bool(result.ok).override_failure_message("door refused: %d" % result.reason).is_true()
	assert_int(_balance()).is_less(before)
	return before


func _esc() -> void:
	_port.push_input(_key(KEY_ESCAPE))


func _ctrl_z() -> void:
	_port.push_input(_key(KEY_Z, true))


func _tick() -> void:
	_clock.advance(SimClock.STEP)


func test_esc_then_ctrl_z_undoes_the_door_and_refunds_it() -> void:
	var before := _build_a_door()
	_esc()
	assert_bool(_menu.build_session.active).is_false()
	assert_int(_mode.undo_history().size()).is_equal(1)
	_ctrl_z()
	assert_int(_mode.undo_history().size()).is_equal(0)
	assert_int(_mode.grid.object_ids().size()).is_equal(0)
	assert_int(_balance()).is_equal(before)
	assert_str(_mode.status_text()).contains(UndoStack.UNDONE)
	# No tray opened and the clock was not taken for the undo.
	assert_bool(_menu.is_tray_open()).is_false()
	assert_bool(_menu.build_session.active).is_false()
	assert_bool(_clock.paused).is_false()


func test_closing_the_tray_by_its_button_then_ctrl_z_undoes_too() -> void:
	var before := _build_a_door()
	_menu.press_category(STRUCTURE)
	_mode.set_tool(BuildMode.Tool.NONE)
	assert_bool(_menu.is_tray_open()).is_false()
	assert_bool(_menu.build_session.active).is_false()
	_ctrl_z()
	assert_int(_mode.grid.object_ids().size()).is_equal(0)
	assert_int(_balance()).is_equal(before)


func test_esc_then_one_tick_then_ctrl_z_has_nothing_to_undo() -> void:
	var before := _build_a_door()
	var paid := before - _balance()
	_esc()
	_tick()
	assert_int(_mode.undo_history().size()).is_equal(0)
	_ctrl_z()
	assert_str(_mode.status_text()).contains(UndoStack.NOTHING_TO_UNDO)
	assert_int(_mode.grid.object_ids().size()).is_equal(1)
	assert_int(_balance()).is_equal(before - paid)


func test_a_paused_clock_runs_no_tick_so_the_history_waits() -> void:
	var before := _build_a_door()
	_esc()
	_clock.set_paused(true)
	_tick()
	assert_int(_mode.undo_history().size()).is_equal(1)
	_ctrl_z()
	assert_int(_balance()).is_equal(before)


func test_reopening_build_mode_before_a_tick_keeps_the_history() -> void:
	var before := _build_a_door()
	_esc()
	_menu.press_category(STRUCTURE)
	_menu.build_session.sync()
	assert_int(_mode.undo_history().size()).is_equal(1)
	_ctrl_z()
	assert_int(_mode.grid.object_ids().size()).is_equal(0)
	assert_int(_balance()).is_equal(before)


func test_a_tick_after_reopening_and_closing_again_still_clears() -> void:
	_build_a_door()
	_esc()
	_menu.press_category(STRUCTURE)
	_menu.build_session.sync()
	_esc()
	_tick()
	assert_int(_mode.undo_history().size()).is_equal(0)


func test_a_load_after_esc_clears_the_history_without_a_tick() -> void:
	_build_a_door()
	_esc()
	assert_int(_mode.undo_history().size()).is_equal(1)
	_save.loaded.emit(true)
	assert_int(_mode.undo_history().size()).is_equal(0)
	_tick()
	assert_int(_mode.undo_history().size()).is_equal(0)


func test_a_rescue_grant_after_esc_still_clears_the_history() -> void:
	_build_a_door()
	_esc()
	assert_int(_mode.undo_history().size()).is_equal(1)
	assert_bool(_finances.wallet.credit(1000, Wallet.Category.GRANT)).is_true()
	assert_int(_mode.undo_history().size()).is_equal(0)
