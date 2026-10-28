class_name TestBuildUndoHistory
extends GdUnitTestSuite
## The undo history (decision
## build-mode-undo-design-action-receipts-with-before-values-at, point 5): 20
## steps, one per build action, never one for an undo or a refused action. It is
## kept when the tool changes (closing the build menu picks none) and cleared on
## a load, on a new game, when a rescue grant pays and when an edit reaches the
## grid from outside BuildMode. The rescue grant itself is in
## test_rescue_grant_undo.gd.

var _mode: BuildMode
var _finances: Finances


func before_test() -> void:
	_finances = Finances.new()
	add_child(_finances)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(10, 10)
	_mode.finances = _finances
	add_child(_mode)


func after_test() -> void:
	_mode.free()
	_finances.free()


func _paint(cell: Vector2i) -> BuildResult:
	_mode.set_tool(BuildMode.Tool.FLOOR)
	return _mode.apply_at(_mode.grid.cell_to_world(cell))


func _steps() -> int:
	return _mode.undo_history().size()


func test_the_history_keeps_the_last_twenty_actions() -> void:
	for i in 25:
		assert_bool(_paint(Vector2i(i % 10, i / 10)).ok).is_true()
	print("after 25 clicks: %d steps" % _steps())
	assert_int(_steps()).is_equal(UndoStack.CAPACITY)
	for i in UndoStack.CAPACITY:
		assert_bool(_mode.undo().ok).is_true()
	assert_object(_mode.undo()).is_null()
	for i in 25:
		var floored := _mode.grid.floor_at(Vector2i(i % 10, i / 10)) != BuildGrid.FLOOR_NONE
		assert_bool(floored).is_equal(i < 5)


func _key_z(ctrl: bool) -> InputEventKey:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_Z
	key.ctrl_pressed = ctrl
	key.pressed = true
	return key


## Ctrl+Z is build_undo and picks no tool (ruling
## hud-keys-build-tools-on-1-9-and-0-space-toggles-pause-shift); a bare Z does
## nothing.
func test_ctrl_z_undoes_and_a_bare_z_does_not() -> void:
	_paint(Vector2i(1, 1))
	_paint(Vector2i(2, 1))
	_mode._unhandled_input(_key_z(false))
	assert_int(_steps()).is_equal(2)
	_mode._unhandled_input(_key_z(true))
	assert_int(_steps()).is_equal(1)
	assert_int(_mode.grid.floor_at(Vector2i(2, 1))).is_equal(BuildGrid.FLOOR_NONE)
	assert_int(_mode.tool).is_equal(BuildMode.Tool.FLOOR)
	for action in BuildMode.TOOL_ACTIONS:
		assert_bool(_key_z(true).is_action_pressed(action)).is_false()


func test_an_undo_and_a_refused_action_add_no_step() -> void:
	_paint(Vector2i(1, 1))
	_paint(Vector2i(2, 1))
	assert_int(_steps()).is_equal(2)
	assert_bool(_mode.undo().ok).is_true()
	assert_int(_steps()).is_equal(1)
	_mode.set_tool(BuildMode.Tool.DESK)
	var refused := _mode.apply_at(_mode.grid.cell_to_world(Vector2i(6, 6)))
	assert_bool(refused.ok).is_false()
	assert_int(_steps()).is_equal(1)


func test_changing_tool_keeps_the_history() -> void:
	_paint(Vector2i(1, 1))
	_mode.set_tool(BuildMode.Tool.NONE)
	_mode.set_tool(BuildMode.Tool.WALL)
	assert_int(_steps()).is_equal(1)


func test_a_load_clears_the_history() -> void:
	_paint(Vector2i(1, 1))
	assert_bool(_mode.load_snapshot(_mode.grid.to_snapshot())).is_true()
	assert_int(_steps()).is_equal(0)


func test_an_edit_from_outside_build_mode_clears_the_history() -> void:
	_paint(Vector2i(1, 1))
	assert_bool(_mode.grid.apply(BuildEdit.paint_floor(Vector2i(5, 5), 1, 1)).ok).is_true()
	assert_int(_steps()).is_equal(0)
	# An outside edit with no dirty cells, a room, clears it too.
	_paint(Vector2i(2, 1))
	var room := BuildEdit.place_room(Rect2i(1, 1, 2, 1), &"cafe")
	assert_bool(_mode.grid.apply(room).ok).is_true()
	assert_int(_steps()).is_equal(0)


func test_a_rescue_grant_payment_clears_the_history() -> void:
	_paint(Vector2i(1, 1))
	assert_bool(_finances.wallet.credit(500, Wallet.Category.GRANT)).is_true()
	assert_int(_steps()).is_equal(0)


func test_other_money_keeps_the_history() -> void:
	_paint(Vector2i(1, 1))
	assert_bool(_finances.wallet.credit(500, Wallet.Category.FEES)).is_true()
	assert_bool(_finances.wallet.spend(100, Wallet.Category.WAGES)).is_true()
	assert_int(_steps()).is_equal(1)


## A new game credits the starting budget; a BuildMode whose Finances has not
## set up yet sees it arrive.
func test_a_new_game_clears_the_history() -> void:
	_mode.free()
	_finances.free()
	_finances = Finances.new()
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(10, 10)
	_mode.finances = _finances
	add_child(_mode)
	assert_bool(_finances.wallet.from_snapshot({"balance": "1000"})).is_true()
	_paint(Vector2i(1, 1))
	assert_int(_steps()).is_equal(1)
	assert_bool(_finances.start_new_game()).is_true()
	assert_int(_steps()).is_equal(0)
	# Into the tree like before_test()'s, so it is no orphan; after_test() frees it.
	add_child(_finances)
