class_name TestRoomDragAutoExtend
extends GdUnitTestSuite
## Auto-extending flush same-type room drags via RoomResize (decision
## 3e0dd9cd, board 42d4d48a) and clear resize edge hover affordances.

const NORTH := BuildGrid.Side.NORTH
const EAST := BuildGrid.Side.EAST
const SOUTH := BuildGrid.Side.SOUTH
const WEST := BuildGrid.Side.WEST
const BASE_ROOM := Rect2i(6, 6, 3, 3)

var _finances: Finances
var _mode: BuildMode
var _room_id := 0


func before_test() -> void:
	_finances = Finances.new()
	add_child(_finances)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(20, 20)
	_mode.grid_centred = false
	_mode.finances = _finances
	add_child(_mode)
	_mode.set_process(false)
	var edits: Array[BuildEdit] = []
	for y in range(2, 16):
		for x in range(2, 16):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	_mode.grid.apply_batch(edits)
	_drag_room(BuildMode.Tool.CAFE_ROOM, BASE_ROOM)
	_room_id = _mode.grid.room_at(BASE_ROOM.position)
	assert_int(_room_id).is_greater(0)


func after_test() -> void:
	_mode.free()
	_finances.free()


func _at(cell: Vector2i) -> Vector3:
	return _mode.grid.cell_to_world(cell)


func _drag_room(tool: BuildMode.Tool, rect: Rect2i) -> void:
	_mode.set_tool(tool)
	_mode.begin_area(_at(rect.position))
	_mode.move_area(_at(rect.end - Vector2i.ONE))
	_mode.finish_area()


func _ghost() -> Node3D:
	return _mode.get_node("Ghost") as Node3D


func _set_balance(amount: int) -> void:
	assert_bool(_finances.wallet.from_snapshot({"balance": str(amount)})).is_true()


func test_flush_same_type_drag_expands_on_east_west_north_and_south_and_drops_middle_wall() -> void:
	var wall_price := PriceTable.price_of_wall(BuildGrid.WallKind.PLAIN)
	var wall_refund := PriceTable.refund_of(wall_price)

	# 1. East flush drag (9, 6, 2, 3) -> union (6, 6, 5, 3).
	var bal := _finances.wallet.balance
	_drag_room(BuildMode.Tool.CAFE_ROOM, Rect2i(9, 6, 2, 3))
	assert_array(_mode.grid.room_ids()).is_equal([_room_id])
	assert_that(_mode.grid.get_room(_room_id)["rect"]).is_equal(Rect2i(6, 6, 5, 3))
	for y in range(6, 9):
		assert_bool(_mode.grid.has_wall(Vector2i(8, y), EAST)).is_false()
		assert_bool(_mode.grid.has_wall(Vector2i(10, y), EAST)).is_true()
	# Removes 3 middle walls (-3*refund), adds 7 outer walls (2 N, 2 S, 3 E) (+7*price).
	assert_int(bal - _finances.wallet.balance).is_equal(7 * wall_price - 3 * wall_refund)

	# 2. West flush drag (4, 6, 2, 3) -> union (4, 6, 7, 3).
	_drag_room(BuildMode.Tool.CAFE_ROOM, Rect2i(4, 6, 2, 3))
	assert_array(_mode.grid.room_ids()).is_equal([_room_id])
	assert_that(_mode.grid.get_room(_room_id)["rect"]).is_equal(Rect2i(4, 6, 7, 3))
	for y in range(6, 9):
		assert_bool(_mode.grid.has_wall(Vector2i(6, y), WEST)).is_false()
		assert_bool(_mode.grid.has_wall(Vector2i(4, y), WEST)).is_true()

	# 3. North flush drag (4, 4, 7, 2) -> union (4, 4, 7, 5).
	_drag_room(BuildMode.Tool.CAFE_ROOM, Rect2i(4, 4, 7, 2))
	assert_array(_mode.grid.room_ids()).is_equal([_room_id])
	assert_that(_mode.grid.get_room(_room_id)["rect"]).is_equal(Rect2i(4, 4, 7, 5))
	for x in range(4, 11):
		assert_bool(_mode.grid.has_wall(Vector2i(x, 6), NORTH)).is_false()
		assert_bool(_mode.grid.has_wall(Vector2i(x, 4), NORTH)).is_true()

	# 4. South flush drag (4, 9, 7, 2) -> union (4, 4, 7, 7).
	_drag_room(BuildMode.Tool.CAFE_ROOM, Rect2i(4, 9, 7, 2))
	assert_array(_mode.grid.room_ids()).is_equal([_room_id])
	assert_that(_mode.grid.get_room(_room_id)["rect"]).is_equal(Rect2i(4, 4, 7, 7))
	for x in range(4, 11):
		assert_bool(_mode.grid.has_wall(Vector2i(x, 8), SOUTH)).is_false()
		assert_bool(_mode.grid.has_wall(Vector2i(x, 10), SOUTH)).is_true()


func test_auto_extend_previews_union_in_ghost_and_undoes_atomically() -> void:
	var bal := _finances.wallet.balance
	var steps := _mode.undo_history().size()
	_mode.set_tool(BuildMode.Tool.CAFE_ROOM)
	_mode.begin_area(_at(Vector2i(9, 6)))
	_mode.move_area(_at(Vector2i(10, 8)))
	_mode._update_ghost(_at(Vector2i(10, 8)))

	# Status shows merged room dimensions (5 x 3), not the 2 x 3 strip.
	assert_str(_mode.status_text()).is_equal("Cafe 5 x 3")

	# Ghost slab covers the full 5 x 3 merged rectangle, with outer walls and NO middle wall.
	var ghost := _ghost()
	assert_bool(ghost.visible).is_true()
	var found_merged_slab := false
	var middle_x := _mode.grid.origin.x + 9.0
	for child in ghost.get_children():
		var mesh_inst := child as MeshInstance3D
		if mesh_inst == null or not (mesh_inst.mesh is BoxMesh):
			continue
		var sz := (mesh_inst.mesh as BoxMesh).size
		if is_equal_approx(sz.x, 4.96) and is_equal_approx(sz.z, 2.96):
			found_merged_slab = true
		if sz.y > 1.0:
			assert_float(absf(mesh_inst.position.x - middle_x)).is_greater(0.1)
	assert_bool(found_merged_slab).is_true()

	_mode.finish_area()
	assert_int(_mode.undo_history().size()).is_equal(steps + 1)
	assert_that(_mode.grid.get_room(_room_id)["rect"]).is_equal(Rect2i(6, 6, 5, 3))
	assert_str(_mode.status_text()).starts_with("Cafe resized to 5 x 3:")

	# Single undo restores original rect, middle wall, outer walls, and exact wallet balance.
	assert_bool(_mode.undo().ok).is_true()
	assert_array(_mode.grid.room_ids()).is_equal([_room_id])
	assert_that(_mode.grid.get_room(_room_id)["rect"]).is_equal(BASE_ROOM)
	for y in range(6, 9):
		assert_bool(_mode.grid.has_wall(Vector2i(8, y), EAST)).is_true()
		assert_bool(_mode.grid.has_wall(Vector2i(10, y), EAST)).is_false()
	assert_int(_finances.wallet.balance).is_equal(bal)


func test_different_type_partial_and_offset_drags_do_not_auto_merge() -> void:
	# 1. Different room type flush along EAST edge -> stays separate room with shared wall.
	_drag_room(BuildMode.Tool.TOILET_ROOM, Rect2i(9, 6, 2, 3))
	assert_int(_mode.grid.room_ids().size()).is_equal(2)
	assert_that(_mode.grid.get_room(_room_id)["rect"]).is_equal(BASE_ROOM)
	for y in range(6, 9):
		assert_bool(_mode.grid.has_wall(Vector2i(8, y), EAST)).is_true()

	# 2. Partial height (2 instead of 3) same-type flush against WEST edge -> separate room.
	_drag_room(BuildMode.Tool.CAFE_ROOM, Rect2i(4, 6, 2, 2))
	assert_int(_mode.grid.room_ids().size()).is_equal(3)
	assert_that(_mode.grid.get_room(_room_id)["rect"]).is_equal(BASE_ROOM)
	assert_bool(_mode.grid.has_wall(Vector2i(6, 6), WEST)).is_true()

	# 3. Offset same-type (same height 3, shifted down by 1) against SOUTH/NORTH -> separate room.
	_drag_room(BuildMode.Tool.CAFE_ROOM, Rect2i(7, 9, 3, 2))
	assert_int(_mode.grid.room_ids().size()).is_equal(4)
	assert_that(_mode.grid.get_room(_room_id)["rect"]).is_equal(BASE_ROOM)


func test_auto_extend_respects_wall_in_footprint_and_wallet_refusals() -> void:
	# Place a wall strictly inside the dragged strip on line x = 10.
	assert_bool(_mode.grid.apply(BuildEdit.place_wall(Vector2i(9, 7), EAST)).ok).is_true()
	var bal := _finances.wallet.balance
	_mode.set_tool(BuildMode.Tool.CAFE_ROOM)
	_mode.begin_area(_at(Vector2i(9, 6)))
	_mode.move_area(_at(Vector2i(11, 8)))
	_mode._update_ghost(_at(Vector2i(11, 8)))
	assert_str(_mode.status_text()).contains("wall is in the way")
	_mode.finish_area()
	assert_that(_mode.grid.get_room(_room_id)["rect"]).is_equal(BASE_ROOM)
	assert_int(_finances.wallet.balance).is_equal(bal)

	# Clear that wall and check insufficient funds refuses cleanly.
	assert_bool(_mode.grid.apply(BuildEdit.remove_wall(Vector2i(9, 7), EAST)).ok).is_true()
	_set_balance(1)
	_drag_room(BuildMode.Tool.CAFE_ROOM, Rect2i(9, 6, 2, 3))
	assert_that(_mode.grid.get_room(_room_id)["rect"]).is_equal(BASE_ROOM)
	assert_str(_mode.status_text()).is_equal("Not enough money")
	assert_int(_finances.wallet.balance).is_equal(1)

	# Plane/site guard refusal on a SiteGrid in the extended strip rolls back atomically.
	const SITE := preload("res://build/terminal_site.tres")
	var site_mode := auto_free(BuildMode.new()) as BuildMode
	site_mode.site = SITE
	site_mode.finances = _finances
	add_child(site_mode)
	site_mode.set_process(false)
	LandKit.own_all(site_mode.land_tool.land)
	_set_balance(20000)
	var base := Rect2i(SITE.starter_offset + Vector2i(6, 6), Vector2i(3, 3))
	site_mode.set_tool(BuildMode.Tool.CAFE_ROOM)
	site_mode.begin_area(site_mode.grid.cell_to_world(base.position))
	site_mode.move_area(site_mode.grid.cell_to_world(base.end - Vector2i.ONE))
	site_mode.finish_area()
	var site_room := site_mode.grid.room_at(base.position)
	assert_int(site_room).is_greater(0)

	var guard_col := base.end.x + 1
	(site_mode.grid as SiteGrid).guard = func(_g: BuildGrid, edit: BuildEdit) -> BuildResult:
		if edit.cell.x == guard_col:
			return BuildResult.refused(BuildResult.Reason.PLANE_AREA)
		return null
	var site_bal := _finances.wallet.balance
	var ext_pos := Vector2i(base.end.x, base.position.y)
	site_mode.begin_area(site_mode.grid.cell_to_world(ext_pos))
	site_mode.move_area(site_mode.grid.cell_to_world(ext_pos + Vector2i(1, 2)))
	site_mode.finish_area()
	assert_that(site_mode.grid.get_room(site_room)["rect"]).is_equal(base)
	assert_str(site_mode.status_text()).is_equal(
		BuildResult.REASON_TEXT[BuildResult.Reason.PLANE_AREA]
	)
	assert_int(_finances.wallet.balance).is_equal(site_bal)


func _live_ghost_children() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for child in _ghost().get_children():
		if not child.is_queued_for_deletion() and child is MeshInstance3D:
			out.append(child as MeshInstance3D)
	return out


func test_hovering_room_edge_shows_clear_resize_affordance_with_room_tool_and_selection() -> void:
	var east_edge := _mode.grid.origin + Vector3(BASE_ROOM.end.x - 0.1, 0.0, 7.5)
	_mode.set_tool(BuildMode.Tool.CAFE_ROOM)
	_mode._update_ghost(east_edge)
	assert_bool(_ghost().visible).is_true()
	var hover_count := 0
	var handle_count := 0
	for child in _live_ghost_children():
		var col := (child.material_override as StandardMaterial3D).albedo_color
		if col == BuildMode.RESIZE_HOVER_TINT:
			hover_count += 1
		elif col == BuildMode.RESIZE_HANDLE_TINT:
			handle_count += 1
	assert_int(hover_count).is_equal(2)
	assert_int(handle_count).is_equal(3)

	# Leaving the edge with the room tool clears and hides the resize hover affordance.
	_mode._update_ghost(_at(Vector2i(7, 7)))
	assert_bool(_ghost().visible).is_false()

	# Selected room in Tool.NONE hovering its east handle also highlights the edge clearly.
	_mode.set_tool(BuildMode.Tool.NONE)
	_mode.set_selected_room(_room_id)
	var east_handle := RoomResize.handle_positions(_mode.grid, BASE_ROOM)[EAST]
	_mode._update_ghost(east_handle)
	assert_bool(_ghost().visible).is_true()
	assert_int(_live_ghost_children().size()).is_equal(5)

	# Moving away from edges in Tool.NONE hides the hover highlight.
	_mode._update_ghost(_at(Vector2i(7, 7)))
	assert_bool(_ghost().visible).is_false()
