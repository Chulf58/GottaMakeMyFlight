class_name TestRemoveWallDrag
extends GdUnitTestSuite
## Reliable single-wall picking (full-height + cutaway, corners, near furniture)
## with clear red hover highlight, and drag-to-remove multiple walls in
## Tool.REMOVE without touching floor tiles (board a6836c88).

const PORT_SIZE := Vector2i(1280, 720)
const NORTH := BuildGrid.Side.NORTH
const EAST := BuildGrid.Side.EAST
const SOUTH := BuildGrid.Side.SOUTH
const WEST := BuildGrid.Side.WEST

var _port: SubViewport
var _camera: Camera3D
var _finances: Finances
var _mode: BuildMode


func before_test() -> void:
	_port = SubViewport.new()
	_port.size = PORT_SIZE
	add_child(_port)
	_camera = Camera3D.new()
	_port.add_child(_camera)
	_camera.make_current()
	_camera.position = Vector3(6.0, 14.0, 13.0)
	_camera.look_at(Vector3(6.0, 0.5, 5.0), Vector3.UP)
	_finances = Finances.new()
	_port.add_child(_finances)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(14, 14)
	_mode.grid_centred = false
	_mode.finances = _finances
	_port.add_child(_mode)
	var edits: Array[BuildEdit] = []
	for y in range(1, 12):
		for x in range(1, 12):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	_mode.grid.apply_batch(edits)
	_mode.set_process(false)
	_mode.set_tool(BuildMode.Tool.REMOVE)


func after_test() -> void:
	_port.free()


func _view() -> BuildView:
	return _mode.get_node("BuildView") as BuildView


func _at(cell: Vector2i) -> Vector3:
	return _mode.grid.cell_to_world(cell)


func _ground_at_world(world_pt: Vector3) -> Vector3:
	var screen := _camera.unproject_position(world_pt)
	var from := _camera.project_ray_origin(screen)
	var dir := _camera.project_ray_normal(screen)
	var hit: Variant = _mode.grid_point(from, dir)
	assert_object(hit).is_not_null()
	return hit


func _place_walls(edges: Array) -> void:
	for edge in edges:
		var edit := BuildEdit.place_wall(edge[0], edge[1])
		assert_bool(BuildTransaction.commit_plan(_mode.grid, [edit], _finances.wallet).ok).is_true()


func _click(pressed: bool, button := MOUSE_BUTTON_LEFT) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.position = _mode.pointer_override
	return ev


func _motion() -> InputEventMouseMotion:
	var ev := InputEventMouseMotion.new()
	ev.position = _mode.pointer_override
	return ev


func test_single_wall_pick_works_on_full_cutaway_stub_and_near_corner() -> void:
	_place_walls([[Vector2i(5, 5), NORTH]])
	await await_idle_frame()

	# 1. Cutaway stub (steep camera angle hitting top-back of stub at y=0.30, z=4.93).
	_view().cutaway_enabled = true
	_camera.position = Vector3(5.5, 18.0, 9.0)
	_camera.look_at(Vector3(5.5, 0.0, 5.0), Vector3.UP)
	_view().update_cutaway(_camera.global_basis.z)
	assert_bool(_view().cut_edges().has(Vector3i(5, 5, NORTH))).is_true()
	var stub_hit := _ground_at_world(Vector3(5.5, InteriorKit.STUB_HEIGHT, 4.93))
	var stub_edit := _mode.edit_at(stub_hit)
	assert_int(stub_edit.kind).is_equal(BuildEdit.Kind.REMOVE_WALL)
	assert_that(stub_edit.cell).is_equal(Vector2i(5, 5))
	assert_int(stub_edit.side).is_equal(NORTH)

	# 2. Hover highlight is clear red.
	_mode._update_ghost(stub_hit)
	var ghost := _mode.get_node("Ghost") as Node3D
	assert_bool(ghost.visible).is_true()
	var box := ghost.get_child(0) as MeshInstance3D
	var tint := (box.material_override as StandardMaterial3D).albedo_color
	assert_that(tint).is_equal(BuildMode.WALL_REMOVE_TINT)

	# 3. Near a corner where perpendicular edge has no wall, nearest walled edge still wins.
	var near_corner := _mode.grid.origin + Vector3(5.96, 0.0, 5.10)
	var corner_edit := _mode.edit_at(near_corner)
	assert_int(corner_edit.kind).is_equal(BuildEdit.Kind.REMOVE_WALL)
	assert_that(corner_edit.cell).is_equal(Vector2i(5, 5))
	assert_int(corner_edit.side).is_equal(NORTH)

	# 4. Full-height wall is also picked cleanly.
	_view().cutaway_enabled = false
	var full_hit := _ground_at_world(Vector3(5.5, 1.5, 5.0))
	assert_int(_mode.edit_at(full_hit).kind).is_equal(BuildEdit.Kind.REMOVE_WALL)


func test_wall_remove_drag_deletes_straight_row_atomically_with_refund_and_keeps_floor() -> void:
	var row: Array = []
	for x in range(3, 8):
		row.append([Vector2i(x, 5), NORTH])
	_place_walls(row)
	await await_idle_frame()
	var bal := _finances.wallet.balance
	var wall_refund := PriceTable.refund_of(PriceTable.price_of_wall(BuildGrid.WallKind.PLAIN))

	# Drag across the horizontal cutaway wall stub line from (3, 5) N to (7, 5) N.
	var p_start := _camera.unproject_position(Vector3(3.5, 0.15, 5.0))
	var p_end := _camera.unproject_position(Vector3(7.5, 0.15, 5.0))
	_mode.pointer_override = p_start
	_mode._unhandled_input(_click(true))
	assert_bool(_mode.is_dragging()).is_true()
	_mode.pointer_override = p_end
	_mode._unhandled_input(_motion())
	_mode._update_ghost(_ground_at_world(Vector3(7.5, 0.15, 5.0)))

	# Ghost previews all 5 walls in red.
	var ghost := _mode.get_node("Ghost") as Node3D
	assert_int(ghost.get_child_count()).is_equal(5)
	for child in ghost.get_children():
		var mat := (child as MeshInstance3D).material_override as StandardMaterial3D
		assert_that(mat.albedo_color).is_equal(BuildMode.WALL_REMOVE_TINT)

	# Release deletes all 5 walls, refunds 5*refund, and preserves all floor tiles.
	_mode._unhandled_input(_click(false))
	for x in range(3, 8):
		assert_bool(_mode.grid.has_wall(Vector2i(x, 5), NORTH)).is_false()
		assert_int(_mode.grid.floor_at(Vector2i(x, 5))).is_equal(BuildGrid.FLOOR_TILE)
		assert_int(_mode.grid.floor_at(Vector2i(x, 4))).is_equal(BuildGrid.FLOOR_TILE)
	assert_int(_finances.wallet.balance).is_equal(bal + 5 * wall_refund)

	# Single undo restores all 5 walls and exact balance.
	assert_bool(_mode.undo().ok).is_true()
	for x in range(3, 8):
		assert_bool(_mode.grid.has_wall(Vector2i(x, 5), NORTH)).is_true()
	assert_int(_finances.wallet.balance).is_equal(bal)


func test_wall_remove_drag_supports_l_path_and_door_walls_without_clearing_floor() -> void:
	# North wall (3..5, 4) N with middle DOOR at (4, 4) N, plus East wall (5, 4..6) E.
	_place_walls(
		[
			[Vector2i(3, 4), NORTH],
			[Vector2i(4, 4), NORTH],
			[Vector2i(5, 4), NORTH],
			[Vector2i(5, 4), EAST],
			[Vector2i(5, 5), EAST],
			[Vector2i(5, 6), EAST],
		]
	)
	(
		assert_bool(
			(
				_mode
				. grid
				. apply(BuildEdit.place_wall(Vector2i(4, 4), NORTH, BuildGrid.WallKind.DOOR))
				. ok
			)
		)
		. is_true()
	)
	await await_idle_frame()
	var bal := _finances.wallet.balance

	# Drag from (3, 4) N to (5, 6) E along the L-corner.
	_mode.begin_area(_mode.grid.origin + Vector3(3.5, 0.0, 4.05))
	_mode.move_area(_mode.grid.origin + Vector3(5.95, 0.0, 6.5))
	var outcome := _mode.finish_area()
	assert_object(outcome).is_not_null()
	assert_int(outcome.placed).is_equal(6)
	for cell in [Vector2i(3, 4), Vector2i(4, 4), Vector2i(5, 4)]:
		assert_bool(_mode.grid.has_wall(cell, NORTH)).is_false()
	for cell in [Vector2i(5, 4), Vector2i(5, 5), Vector2i(5, 6)]:
		assert_bool(_mode.grid.has_wall(cell, EAST)).is_false()
	# Underlying floor stays intact.
	for y in range(4, 7):
		for x in range(3, 7):
			assert_int(_mode.grid.floor_at(Vector2i(x, y))).is_equal(BuildGrid.FLOOR_TILE)

	# One undo restores plain walls and the door wall atomically.
	assert_bool(_mode.undo().ok).is_true()
	assert_int(_mode.grid.wall_kind(Vector2i(4, 4), NORTH)).is_equal(BuildGrid.WallKind.DOOR)
	assert_bool(_mode.grid.has_wall(Vector2i(5, 6), EAST)).is_true()
	assert_int(_finances.wallet.balance).is_equal(bal)


func test_dragging_from_floor_still_clears_floor_normally() -> void:
	_place_walls([[Vector2i(5, 5), NORTH]])
	await await_idle_frame()
	# Press on empty center of (2, 2) (not on a wall) and drag to (3, 3).
	_mode.begin_area(_at(Vector2i(2, 2)))
	_mode.move_area(_at(Vector2i(3, 3)))
	var outcome := _mode.finish_area()
	assert_int(outcome.placed).is_equal(4)
	assert_int(_mode.grid.floor_at(Vector2i(2, 2))).is_equal(BuildGrid.FLOOR_NONE)
	assert_int(_mode.grid.floor_at(Vector2i(3, 3))).is_equal(BuildGrid.FLOOR_NONE)
	assert_bool(_mode.grid.has_wall(Vector2i(5, 5), NORTH)).is_true()


func test_wall_remove_drag_cancels_cleanly_on_escape() -> void:
	_place_walls([[Vector2i(3, 5), NORTH], [Vector2i(4, 5), NORTH]])
	await await_idle_frame()
	var p_start := _camera.unproject_position(Vector3(3.5, 0.15, 5.0))
	var p_end := _camera.unproject_position(Vector3(4.5, 0.15, 5.0))
	_mode.pointer_override = p_start
	_mode._unhandled_input(_click(true))
	_mode.pointer_override = p_end
	_mode._unhandled_input(_motion())
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	_mode._unhandled_input(esc)
	_mode._unhandled_input(_click(false))
	assert_bool(_mode.grid.has_wall(Vector2i(3, 5), NORTH)).is_true()
	assert_bool(_mode.grid.has_wall(Vector2i(4, 5), NORTH)).is_true()


func test_wall_remove_drag_deletes_vertical_row_atomically_and_undoes() -> void:
	_camera.position = Vector3(2.0, 14.0, 9.0)
	_camera.look_at(Vector3(6.0, 0.5, 5.0), Vector3.UP)
	var col: Array = []
	for y in range(3, 7):
		col.append([Vector2i(6, y), WEST])
	_place_walls(col)
	await await_idle_frame()
	var bal := _finances.wallet.balance
	var wall_refund := PriceTable.refund_of(PriceTable.price_of_wall(BuildGrid.WallKind.PLAIN))

	_mode.begin_area(_ground_at_world(Vector3(6.0, 0.15, 3.5)))
	_mode.move_area(_ground_at_world(Vector3(6.0, 0.15, 6.5)))
	var outcome := _mode.finish_area()
	assert_int(outcome.placed).is_equal(4)
	for y in range(3, 7):
		assert_bool(_mode.grid.has_wall(Vector2i(6, y), WEST)).is_false()
		assert_int(_mode.grid.floor_at(Vector2i(6, y))).is_equal(BuildGrid.FLOOR_TILE)
	assert_int(_finances.wallet.balance).is_equal(bal + 4 * wall_refund)

	assert_bool(_mode.undo().ok).is_true()
	for y in range(3, 7):
		assert_bool(_mode.grid.has_wall(Vector2i(6, y), WEST)).is_true()
	assert_int(_finances.wallet.balance).is_equal(bal)


func test_wall_remove_drag_rolls_back_atomically_on_guard_or_wallet_full_and_door_refusal() -> void:
	# 1. Refused door via SiteGrid.guard marks both door and adjacent holding walls invalid in preview,
	# and atomic apply leaves all 4 walls untouched (including (6, 4) N!).
	const SITE := preload("res://build/terminal_site.tres")
	var site_mode := auto_free(BuildMode.new()) as BuildMode
	site_mode.site = SITE
	site_mode.finances = _finances
	_port.add_child(site_mode)
	site_mode.set_process(false)
	site_mode.set_tool(BuildMode.Tool.REMOVE)
	var site_grid := site_mode.grid as SiteGrid
	var origin_cell := SITE.starter_offset
	for x in range(3, 7):
		var c := origin_cell + Vector2i(x, 4)
		assert_bool(site_grid.apply(BuildEdit.paint_floor(c, BuildGrid.FLOOR_TILE, 1)).ok).is_true()
		(
			assert_bool(
				(
					BuildTransaction
					. commit_plan(site_grid, [BuildEdit.place_wall(c, NORTH)], _finances.wallet)
					. ok
				)
			)
			. is_true()
		)
	var door_cell := origin_cell + Vector2i(4, 4)
	(
		assert_bool(
			site_grid.apply(BuildEdit.place_wall(door_cell, NORTH, BuildGrid.WallKind.DOOR)).ok
		)
		. is_true()
	)
	site_grid.guard = func(_g: BuildGrid, edit: BuildEdit) -> BuildResult:
		if edit.kind == BuildEdit.Kind.REMOVE_WALL and edit.cell == door_cell:
			return BuildResult.refused(BuildResult.Reason.PLANE_AREA)
		return null
	var site_edges: Array[Vector3i] = [
		Vector3i(origin_cell.x + 3, origin_cell.y + 4, NORTH),
		Vector3i(door_cell.x, door_cell.y, NORTH),
		Vector3i(origin_cell.x + 5, origin_cell.y + 4, NORTH),
		Vector3i(origin_cell.x + 6, origin_cell.y + 4, NORTH),
	]
	var prev := WallRowDrag.RemoveDrag.preview(
		site_grid, site_edges, site_mode.check, _finances.wallet
	)
	assert_array(prev.valid).is_equal([false, false, false, true])
	assert_int(prev.blocked).is_equal(3)

	var site_bal := _finances.wallet.balance
	var ordered: Array[BuildEdit] = [
		BuildEdit.remove_wall(door_cell, NORTH),
		BuildEdit.remove_wall(origin_cell + Vector2i(3, 4), NORTH),
		BuildEdit.remove_wall(origin_cell + Vector2i(5, 4), NORTH),
		BuildEdit.remove_wall(origin_cell + Vector2i(6, 4), NORTH),
	]
	var dirty: Array[Vector2i] = []
	var refused := WallRowDrag.RemoveDrag.apply(
		site_grid, ordered, site_mode.check, _finances.wallet, dirty
	)
	assert_int(refused.placed).is_equal(0)
	assert_int(refused.skipped).is_equal(4)
	for x in range(3, 7):
		assert_bool(site_grid.has_wall(origin_cell + Vector2i(x, 4), NORTH)).is_true()
	assert_int(_finances.wallet.balance).is_equal(site_bal)

	# 2. Dragging across a wall that holds an unselected door rolls back atomically.
	_place_walls(
		[
			[Vector2i(3, 4), NORTH],
			[Vector2i(4, 4), NORTH],
			[Vector2i(5, 4), NORTH],
			[Vector2i(6, 4), NORTH],
		]
	)
	(
		assert_bool(
			(
				_mode
				. grid
				. apply(BuildEdit.place_wall(Vector2i(4, 4), NORTH, BuildGrid.WallKind.DOOR))
				. ok
			)
		)
		. is_true()
	)
	await await_idle_frame()
	var bal := _finances.wallet.balance
	_mode.begin_area(_mode.grid.origin + Vector3(5.5, 0.0, 4.05))
	_mode.move_area(_mode.grid.origin + Vector3(6.5, 0.0, 4.05))
	var door_hold := _mode.finish_area()
	assert_int(door_hold.placed).is_equal(0)
	assert_int(door_hold.skipped).is_equal(2)
	assert_bool(_mode.grid.has_wall(Vector2i(5, 4), NORTH)).is_true()
	assert_bool(_mode.grid.has_wall(Vector2i(6, 4), NORTH)).is_true()
	assert_int(_finances.wallet.balance).is_equal(bal)

	# 3. WALLET_FULL refuses atomically without partial wall removal or partial refund.
	assert_bool(_finances.wallet.from_snapshot({"balance": str(Wallet.MAX_BALANCE - 5)})).is_true()
	var full_bal := _finances.wallet.balance
	var edges: Array[Vector3i] = [
		Vector3i(3, 4, NORTH),
		Vector3i(4, 4, NORTH),
		Vector3i(5, 4, NORTH),
		Vector3i(6, 4, NORTH),
	]
	var full_prev := WallRowDrag.RemoveDrag.preview(
		_mode.grid, edges, _mode.check, _finances.wallet
	)
	assert_array(full_prev.valid).is_equal([false, false, false, false])
	assert_str(full_prev.first_reason).is_equal(
		BuildResult.REASON_TEXT[BuildResult.Reason.WALLET_FULL]
	)
	_mode.begin_area(_mode.grid.origin + Vector3(3.5, 0.0, 4.05))
	_mode.move_area(_mode.grid.origin + Vector3(6.5, 0.0, 4.05))
	var full_res := _mode.finish_area()
	assert_int(full_res.placed).is_equal(0)
	for x in range(3, 7):
		assert_bool(_mode.grid.has_wall(Vector2i(x, 4), NORTH)).is_true()
	assert_int(_finances.wallet.balance).is_equal(full_bal)
