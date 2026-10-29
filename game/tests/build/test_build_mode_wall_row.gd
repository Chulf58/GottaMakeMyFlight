class_name TestBuildModeWallRow
extends GdUnitTestSuite
## BuildMode's Wall and Glass tools: press, drag a straight row, release lays
## the whole row as one undo step; Esc or right-click cancels; a click lays one
## edge; a refused edge is skipped and reported; a row stops where the money
## runs out (decision floor-and-remove-tools-drag-a-rectangle-press-drag-release).

const NORTH := BuildGrid.Side.NORTH
const WEST := BuildGrid.Side.WEST
const PORT_SIZE := Vector2i(1280, 720)

var _mode: BuildMode
var _finances: Finances
var _port: SubViewport
var _camera: Camera3D
var _changes := 0


func before_test() -> void:
	_finances = Finances.new()
	add_child(_finances)
	_port = SubViewport.new()
	_port.size = PORT_SIZE
	add_child(_port)
	_camera = Camera3D.new()
	_port.add_child(_camera)
	_camera.make_current()
	_camera.position = Vector3(6.0, 20.0, 6.0)
	_camera.look_at(Vector3(6.0, 0.0, 6.0), Vector3.FORWARD)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(12, 12)
	_mode.grid_centred = false
	_mode.finances = _finances
	_port.add_child(_mode)
	_mode.set_tool(BuildMode.Tool.WALL)
	_changes = 0
	_mode.grid_changed.connect(func() -> void: _changes += 1)


func after_test() -> void:
	_port.free()
	_finances.free()


func _at(cell: Vector2i) -> Vector3:
	return _mode.grid.cell_to_world(cell)


## A ground point 0.45 m from the middle of `cell` toward `side`.
func _near_edge(cell: Vector2i, side: int) -> Vector3:
	var step := BuildGrid.SIDE_STEP[side]
	return _at(cell) + Vector3(step.x * 0.45, 0.0, step.y * 0.45)


func _wall_price() -> int:
	return PriceTable.price_of_wall(BuildGrid.WallKind.PLAIN)


func _set_balance(amount: int) -> void:
	assert_bool(_finances.wallet.from_snapshot({"balance": str(amount)})).is_true()


func _drag(from: Vector2i, to: Vector2i, side := NORTH) -> void:
	_mode.begin_row(_near_edge(from, side))
	_mode.move_row(_near_edge(to, side))


func _walls_on(row: Array[Vector2i], side := NORTH) -> int:
	var count := 0
	for cell in row:
		if _mode.grid.has_wall(cell, side):
			count += 1
	return count


func _cells_x(from: int, to: int, y: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x in range(from, to + 1):
		cells.append(Vector2i(x, y))
	return cells


func _cells_z(x: int, from: int, to: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(from, to + 1):
		cells.append(Vector2i(x, y))
	return cells


func test_a_drag_along_x_lays_every_edge_on_release_and_nothing_before() -> void:
	_drag(Vector2i(2, 4), Vector2i(6, 4))
	assert_int(_walls_on(_cells_x(2, 6, 4))).is_equal(0)
	var outcome := _mode.finish_row()
	assert_int(outcome.placed).is_equal(5)
	assert_int(_walls_on(_cells_x(2, 6, 4))).is_equal(5)
	assert_bool(_mode.grid.has_wall(Vector2i(7, 4), NORTH)).is_false()
	assert_bool(_mode.grid.has_wall(Vector2i(1, 4), NORTH)).is_false()
	assert_int(_changes).is_equal(1)


func test_a_drag_along_z_lays_every_edge_on_release_and_nothing_before() -> void:
	_drag(Vector2i(4, 2), Vector2i(4, 5), WEST)
	assert_int(_walls_on(_cells_z(4, 2, 5), WEST)).is_equal(0)
	var outcome := _mode.finish_row()
	assert_int(outcome.placed).is_equal(4)
	assert_int(_walls_on(_cells_z(4, 2, 5), WEST)).is_equal(4)
	assert_bool(_mode.grid.has_wall(Vector2i(4, 6), WEST)).is_false()


func test_a_diagonal_drag_snaps_to_the_longer_axis() -> void:
	_drag(Vector2i(2, 4), Vector2i(7, 6))
	_mode.finish_row()
	assert_int(_walls_on(_cells_x(2, 7, 4))).is_equal(6)
	assert_bool(_mode.grid.has_wall(Vector2i(7, 6), NORTH)).is_false()
	assert_bool(_mode.grid.has_wall(Vector2i(2, 5), NORTH)).is_false()
	# Dominant along z: the walls turn to the vertical (WEST) edges, not NORTH.
	_drag(Vector2i(9, 2), Vector2i(10, 8))
	_mode.finish_row()
	assert_int(_walls_on(_cells_z(9, 2, 8), WEST)).is_equal(7)
	assert_int(_walls_on(_cells_z(9, 2, 8))).is_equal(0)


func test_a_drag_that_never_left_its_cell_lays_the_one_edge() -> void:
	_drag(Vector2i(3, 3), Vector2i(3, 3))
	var outcome := _mode.finish_row()
	assert_int(outcome.placed).is_equal(1)
	assert_bool(_mode.grid.has_wall(Vector2i(3, 3), NORTH)).is_true()
	assert_str(_mode.status_text()).is_equal("Placed 1 for %d" % _wall_price())


func test_the_whole_row_is_one_undo_step() -> void:
	var before := _finances.wallet.balance
	_drag(Vector2i(2, 4), Vector2i(6, 4))
	_mode.finish_row()
	assert_int(_mode.undo_history().size()).is_equal(1)
	assert_int(_finances.wallet.balance).is_equal(before - 5 * _wall_price())
	assert_bool(_mode.undo().ok).is_true()
	assert_int(_walls_on(_cells_x(2, 6, 4))).is_equal(0)
	assert_int(_finances.wallet.balance).is_equal(before)
	assert_int(_mode.undo_history().size()).is_equal(0)


func test_cancelling_places_nothing() -> void:
	_drag(Vector2i(2, 4), Vector2i(6, 4))
	_mode.cancel_area()
	assert_object(_mode.finish_row()).is_null()
	assert_int(_walls_on(_cells_x(2, 6, 4))).is_equal(0)
	assert_int(_mode.undo_history().size()).is_equal(0)
	assert_int(_changes).is_equal(0)


func test_an_edge_the_rules_refuse_is_skipped_and_reported() -> void:
	assert_bool(_mode.grid.apply(BuildEdit.place_wall(Vector2i(4, 4), NORTH)).ok).is_true()
	_drag(Vector2i(2, 4), Vector2i(6, 4))
	var outcome := _mode.finish_row()
	var why := BuildResult.refused(BuildResult.Reason.WALL_EXISTS).reason_text()
	print("status '%s'" % _mode.status_text())
	assert_int(outcome.placed).is_equal(4)
	assert_int(outcome.skipped).is_equal(1)
	assert_int(_walls_on(_cells_x(2, 6, 4))).is_equal(5)
	assert_str(_mode.status_text()).is_equal(
		"Placed 4 for %d, skipped 1: %s" % [4 * _wall_price(), why]
	)


func test_running_out_of_money_stops_the_row_at_that_edge() -> void:
	_set_balance(3 * _wall_price() + _wall_price() / 2)
	_drag(Vector2i(2, 4), Vector2i(6, 4))
	var outcome := _mode.finish_row()
	print("status '%s' balance %d" % [_mode.status_text(), _finances.wallet.balance])
	assert_int(outcome.placed).is_equal(3)
	assert_int(outcome.skipped).is_equal(2)
	assert_int(_walls_on(_cells_x(2, 4, 4))).is_equal(3)
	assert_int(_walls_on(_cells_x(5, 6, 4))).is_equal(0)
	assert_int(_finances.wallet.balance).is_equal(_wall_price() / 2)
	assert_str(_mode.status_text()).contains("skipped 2: Not enough money")
	assert_int(_mode.undo_history().size()).is_equal(1)


func test_a_row_with_no_money_at_all_places_nothing() -> void:
	_set_balance(_wall_price() - 1)
	_drag(Vector2i(2, 4), Vector2i(4, 4))
	var outcome := _mode.finish_row()
	assert_int(outcome.placed).is_equal(0)
	assert_int(_walls_on(_cells_x(2, 4, 4))).is_equal(0)
	assert_int(_mode.undo_history().size()).is_equal(0)
	assert_int(_finances.wallet.balance).is_equal(_wall_price() - 1)


func test_glass_lays_a_row_the_same_way() -> void:
	_mode.set_tool(BuildMode.Tool.GLASS)
	var before := _finances.wallet.balance
	_drag(Vector2i(2, 4), Vector2i(5, 4))
	assert_int(_walls_on(_cells_x(2, 5, 4))).is_equal(0)
	var outcome := _mode.finish_row()
	assert_int(outcome.placed).is_equal(4)
	for cell in _cells_x(2, 5, 4):
		assert_int(_mode.grid.wall_kind(cell, NORTH)).is_equal(BuildGrid.WallKind.GLASS)
	assert_int(_finances.wallet.balance).is_equal(
		before - 4 * PriceTable.price_of_wall(BuildGrid.WallKind.GLASS)
	)
	assert_bool(_mode.undo().ok).is_true()
	assert_int(_walls_on(_cells_x(2, 5, 4))).is_equal(0)


func test_the_ghost_is_the_whole_row_with_its_length_and_cost() -> void:
	_drag(Vector2i(2, 4), Vector2i(6, 4))
	_mode._process(0.0)
	var ghost := _mode.get_node("Ghost") as Node3D
	assert_int(ghost.get_child_count()).is_equal(5)
	assert_str(_mode.status_text()).is_equal("Wall row of 5, cost %d" % (5 * _wall_price()))
	assert_int(_walls_on(_cells_x(2, 6, 4))).is_equal(0)


func test_the_ghost_tints_an_edge_that_would_be_skipped() -> void:
	assert_bool(_mode.grid.apply(BuildEdit.place_wall(Vector2i(4, 4), NORTH)).ok).is_true()
	_drag(Vector2i(2, 4), Vector2i(6, 4))
	_mode._process(0.0)
	var ghost := _mode.get_node("Ghost") as Node3D
	var tints: Array[Color] = []
	for box in ghost.get_children():
		tints.append(((box as MeshInstance3D).material_override as StandardMaterial3D).albedo_color)
	assert_int(tints.size()).is_equal(5)
	assert_that(tints[2]).is_equal(BuildMode.INVALID_TINT)
	assert_that(tints[1]).is_equal(BuildMode.VALID_TINT)
	assert_str(_mode.status_text()).contains("1 blocked")


func test_the_ghost_marks_the_edges_the_wallet_cannot_pay_for() -> void:
	_set_balance(2 * _wall_price())
	_drag(Vector2i(2, 4), Vector2i(5, 4))
	_mode._process(0.0)
	var ghost := _mode.get_node("Ghost") as Node3D
	var boxes := ghost.get_children()
	var tint := func(i: int) -> Color:
		return ((boxes[i] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color
	assert_that(tint.call(1)).is_equal(BuildMode.VALID_TINT)
	assert_that(tint.call(2)).is_equal(BuildMode.INVALID_TINT)
	assert_that(tint.call(3)).is_equal(BuildMode.INVALID_TINT)
	assert_str(_mode.status_text()).contains("cost %d" % (2 * _wall_price()))


# The input path: the same drag, driven by mouse events.


## A viewport point over the near edge of a cell, set as the pointer.
func _point_at(cell: Vector2i, side := NORTH) -> Vector2:
	_mode.pointer_override = _camera.unproject_position(_near_edge(cell, side))
	return _mode.pointer_override


func _click(pressed: bool, button := MOUSE_BUTTON_LEFT) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = _mode.pointer_override
	return event


func _motion() -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = _mode.pointer_override
	return event


func _escape() -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	return event


func test_mouse_press_drag_release_lays_the_row_on_release() -> void:
	_point_at(Vector2i(2, 4))
	_mode._unhandled_input(_click(true))
	assert_int(_walls_on(_cells_x(2, 6, 4))).is_equal(0)
	for x in range(3, 7):
		_point_at(Vector2i(x, 4))
		_mode._unhandled_input(_motion())
	assert_int(_walls_on(_cells_x(2, 6, 4))).is_equal(0)
	_mode._unhandled_input(_click(false))
	assert_int(_walls_on(_cells_x(2, 6, 4))).is_equal(5)
	assert_int(_mode.undo_history().size()).is_equal(1)


func test_escape_mid_drag_places_nothing() -> void:
	_point_at(Vector2i(2, 4))
	_mode._unhandled_input(_click(true))
	_point_at(Vector2i(5, 4))
	_mode._unhandled_input(_motion())
	_mode._unhandled_input(_escape())
	_mode._unhandled_input(_click(false))
	assert_int(_walls_on(_cells_x(2, 6, 4))).is_equal(0)
	assert_int(_mode.undo_history().size()).is_equal(0)
	assert_int(_finances.wallet.balance).is_equal(PriceTable.STARTING_BUDGET)


func test_right_click_mid_drag_places_nothing() -> void:
	_point_at(Vector2i(2, 4))
	_mode._unhandled_input(_click(true))
	_point_at(Vector2i(5, 4))
	_mode._unhandled_input(_motion())
	_mode._unhandled_input(_click(true, MOUSE_BUTTON_RIGHT))
	_mode._unhandled_input(_click(false))
	assert_int(_walls_on(_cells_x(2, 6, 4))).is_equal(0)
	assert_int(_mode.undo_history().size()).is_equal(0)


func test_a_click_that_slips_across_a_cell_border_is_still_one_edge() -> void:
	# Pressed 0.05 m inside the north edge of (3, 4), then a 3 px slip over it.
	var press := _near_edge(Vector2i(3, 4), NORTH) + Vector3(0.0, 0.0, 0.05)
	_mode.pointer_override = _camera.unproject_position(press)
	_mode._unhandled_input(_click(true))
	var slipped := _camera.unproject_position(press + Vector3(0.0, 0.0, -0.2))
	assert_float(slipped.distance_to(_mode.pointer_override)).is_less(BuildMode.CLICK_SLOP_PX)
	_mode.pointer_override = slipped
	_mode._unhandled_input(_motion())
	_mode._unhandled_input(_click(false))
	assert_int(_walls_on(_cells_z(3, 3, 4))).is_equal(1)
	assert_bool(_mode.grid.has_wall(Vector2i(3, 4), NORTH)).is_true()


func test_a_drag_past_the_slop_still_follows_the_pointer() -> void:
	_point_at(Vector2i(2, 4))
	_mode._unhandled_input(_click(true))
	var far := _point_at(Vector2i(5, 4))
	var pressed_at := _camera.unproject_position(_near_edge(Vector2i(2, 4), NORTH))
	assert_float(far.distance_to(pressed_at)).is_greater(BuildMode.CLICK_SLOP_PX)
	_mode._unhandled_input(_motion())
	_mode._unhandled_input(_click(false))
	assert_int(_walls_on(_cells_x(2, 5, 4))).is_equal(4)
