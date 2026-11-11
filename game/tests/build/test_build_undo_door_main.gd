class_name TestBuildUndoDoorMain
extends GdUnitTestSuite
## Ctrl+Z after a door placement in the running game (board 095d80eb): a door
## put on the starter terminal's plain wall must still be undoable after the
## sim runs on, and the undo must take the door away. One boot of main.tscn
## for the file.

const MAIN := "res://main/main.tscn"
const NORTH := BuildGrid.Side.NORTH

var _main: Node
var _alerts_path := SaveTestKit.run_path("undo_door_alerts")
var _departures_path := SaveTestKit.run_path("undo_door_departures")
var _mode: BuildMode
var _clock: SimClock


func before() -> void:
	_main = load(MAIN).instantiate()
	var hud := _main.get_node("PassengerHud") as PassengerHud
	hud.alert_settings_path = _alerts_path
	hud.departures_settings_path = _departures_path
	add_child(_main)
	_clock = _main.get_node("SimClock")
	_clock.set_paused(true)
	_mode = _main.get_node("BuildMode")
	hud.press_starter_terminal()
	StaffTestKit.staff_all(_main.get_node("Staff"))


func after() -> void:
	_main.free()
	DirAccess.remove_absolute(_alerts_path)
	DirAccess.remove_absolute(_departures_path)


## Places an exit door on a plain north wall of the terminal the way a click
## does; returns the cell it took, or (-1, -1).
func _place_exit_door() -> Vector2i:
	_mode.set_tool(BuildMode.Tool.EXIT)
	var grid := _mode.grid
	for y in grid.size.y:
		for x in grid.size.x:
			var cell := Vector2i(x, y)
			if grid.floor_at(cell) == BuildGrid.FLOOR_NONE:
				continue
			if grid.wall_kind(cell, NORTH) != BuildGrid.WallKind.PLAIN:
				continue
			if grid.floor_at(cell + Vector2i(0, -1)) != BuildGrid.FLOOR_NONE:
				continue
			var result := _mode.apply_at(grid.cell_to_world(cell) + Vector3(0.0, 0.0, -0.5))
			if result != null and result.ok:
				return cell
	return Vector2i(-1, -1)


func test_a_door_placed_on_the_starter_terminal_survives_the_sim_and_undoes() -> void:
	var before_steps := _mode.undo_history().size()
	var cell := _place_exit_door()
	print("door cell: %s, history before %d" % [cell, before_steps])
	assert_vector(cell).is_not_equal(Vector2i(-1, -1))
	assert_int(_mode.undo_history().size()).is_equal(before_steps + 1)
	var door := _mode.grid.object_at(cell)
	assert_int(door).is_not_equal(0)
	_clock.set_paused(false)
	for i in 30:
		_clock.advance(SimClock.STEP)
		await get_tree().process_frame
	_clock.set_paused(true)
	print("history after the sim ran: %d" % _mode.undo_history().size())
	assert_int(_mode.undo_history().size()).is_equal(before_steps + 1)
	var undone := _mode.undo()
	assert_object(undone).is_not_null()
	print("undo: %s" % [undone.reason_text() if not undone.ok else "ok"])
	assert_bool(undone.ok).is_true()
	assert_dict(_mode.grid.get_object(door)).is_empty()
	assert_int(_mode.grid.wall_kind(cell, NORTH)).is_equal(BuildGrid.WallKind.PLAIN)


## What the playtest saw (input log: Esc, then Ctrl+Z 53 ms later). Esc drops
## the tool and closes the tray, which ends build mode. This test used to pin
## that the Ctrl+Z then had nothing to undo; the 2026-11-11 ruling (decision
## build-mode-pauses-the-game-while-a-build-tray-is-open-closin) replaced that:
## the history survives until the sim clock advances a tick, so the Ctrl+Z
## after the Esc undoes the door and no tray opens.
func test_escape_then_ctrl_z_undoes_the_door_until_a_tick_runs() -> void:
	var menu := _main.get_node("BuildMenu") as BuildMenu
	_mode.clear_undo()
	var cell := _place_exit_door()
	assert_vector(cell).is_not_equal(Vector2i(-1, -1))
	assert_bool(menu.build_session.active).is_true()
	assert_int(_mode.undo_history().size()).is_equal(1)
	_mode._unhandled_input(_key(KEY_ESCAPE, false))
	assert_bool(menu.build_session.active).is_false()
	assert_int(_mode.undo_history().size()).is_equal(1)
	_mode._unhandled_input(_key(KEY_Z, true))
	print("status after Esc, Ctrl+Z: %s" % _mode.status_text())
	assert_str(_mode.status_text()).contains(UndoStack.UNDONE)
	assert_int(_mode.grid.object_at(cell)).is_equal(0)
	assert_bool(menu.build_session.active).is_false()
	assert_bool(menu.is_tray_open()).is_false()


## The other half of the same rule: once a tick has run after the Esc, the
## history is gone and the Ctrl+Z has nothing to undo.
func test_escape_then_a_tick_then_ctrl_z_has_nothing_to_undo() -> void:
	var menu := _main.get_node("BuildMenu") as BuildMenu
	_mode.clear_undo()
	var cell := _place_exit_door()
	assert_vector(cell).is_not_equal(Vector2i(-1, -1))
	_mode._unhandled_input(_key(KEY_ESCAPE, false))
	assert_bool(menu.build_session.active).is_false()
	_clock.set_paused(false)
	_clock.advance(SimClock.STEP)
	_clock.set_paused(true)
	assert_int(_mode.undo_history().size()).is_equal(0)
	_mode._unhandled_input(_key(KEY_Z, true))
	print("status after Esc, tick, Ctrl+Z: %s" % _mode.status_text())
	assert_str(_mode.status_text()).is_equal(UndoStack.NOTHING_TO_UNDO)
	assert_int(_mode.grid.object_at(cell)).is_not_equal(0)


func _key(code: Key, ctrl: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.ctrl_pressed = ctrl
	event.pressed = true
	return event
