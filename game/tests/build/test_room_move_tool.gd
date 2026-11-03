class_name TestRoomMoveTool
extends GdUnitTestSuite
## The tool that picks a built room up, shows its ghost, turns it and sets it
## down (RoomMoveTool, over RoomMove). The grid: tile floor on columns 1 to 12,
## rows 1 to 10; a cafe on columns 2 to 9, rows 2 to 7 (8 x 6, so its middle is
## outside the band of its edge) with a bin at (2, 2) and a 2 x 2 pot at
## (4, 3); a second room, a toilet, on columns 11 to 12, rows 1 to 2.

const FLOORED := Rect2i(1, 1, 12, 10)
const CAFE := Rect2i(2, 2, 8, 6)
const TOILET := Rect2i(11, 1, 2, 2)
const MIDDLE := Vector2i(5, 4)
const BIN_PAID := 37
const POT_PAID := 91

var _mode: BuildMode
var _mover: RoomMoveTool
var _finances: Finances
var _room := 0
var _bin := 0
var _pot := 0


func before_test() -> void:
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(24, 16)
	_finances = Finances.new()
	add_child(_finances)
	_finances.start_new_game()
	_mode.finances = _finances
	add_child(_mode)
	_mode.set_process(false)
	_mover = _mode.room_mover
	_mover.set_process(false)
	var floor_edits: Array[BuildEdit] = []
	for y in range(FLOORED.position.y, FLOORED.end.y):
		for x in range(FLOORED.position.x, FLOORED.end.x):
			floor_edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 3))
	_mode.grid.apply_batch(floor_edits)
	_room = _mode.grid.apply(BuildEdit.place_room(CAFE, &"cafe")).room_id
	assert_bool(_mode.grid.apply(BuildEdit.place_room(TOILET, &"toilet")).ok).is_true()
	_bin = _place(&"trash_can", Vector2i(2, 2), BIN_PAID)
	_pot = _place(&"plant_pot_2a", Vector2i(4, 3), POT_PAID)
	_mode.set_tool(BuildMode.Tool.CAFE_ROOM)


func after_test() -> void:
	_mode.free()
	_finances.free()


func _place(def_id: StringName, anchor: Vector2i, paid: int) -> int:
	var edit := BuildEdit.place_object(def_id, anchor, 0)
	edit.paid = paid
	return _mode.grid.apply(edit).object_id


func _at(cell: Vector2i) -> Vector3:
	return _mode.grid.cell_to_world(cell)


func _rect() -> Rect2i:
	return _mode.grid.get_room(_room)["rect"]


func _pick_up() -> void:
	_mode.begin_area(_at(MIDDLE))
	assert_bool(_mover.active).is_true()


func _ghost_meshes() -> Array[Node]:
	return _mover.ghost_node().find_children("*", "MeshInstance3D", true, false)


func _ghost_colour() -> Color:
	var slab := _mover.ghost_node().get_node("Room") as MeshInstance3D
	return (slab.material_override as StandardMaterial3D).albedo_color


func test_a_press_inside_the_room_picks_it_up_with_its_room_tool() -> void:
	_pick_up()
	_mover.hover_at(Vector2i(8, 7))
	var meshes := _ghost_meshes()
	print(
		(
			"pick up: room=%d ghost meshes=%d status=%s"
			% [_mover.room_id, meshes.size(), _mover.status_text()]
		)
	)
	assert_int(_mover.room_id).is_equal(_room)
	# The room's slab and its two pieces, and the original stays, dimmed.
	assert_int(meshes.size()).is_greater_equal(3)
	assert_int(_mover.get_node("RoomMoveDim").get_child_count()).is_equal(1)
	assert_that(_rect()).is_equal(CAFE)
	assert_that(_ghost_colour()).is_equal(BuildMode.VALID_TINT)
	assert_bool(_mover.refusal() == null).is_true()
	assert_str(_mover.status_text()).contains("click to set down")


func test_a_press_in_the_edge_band_or_in_another_type_picks_nothing_up() -> void:
	_mode.begin_area(_mode.grid.origin + Vector3(CAFE.position.x + 0.1, 0.0, 5.0))
	assert_bool(_mover.active).is_false()
	_mode.cancel_area()
	_mode.set_tool(BuildMode.Tool.TOILET_ROOM)
	_mode.begin_area(_at(MIDDLE))
	assert_bool(_mover.active).is_false()


func test_r_turns_the_ghost_a_quarter_and_the_room_it_makes() -> void:
	_pick_up()
	_mover.hover_at(Vector2i(6, 5))
	var before := _mover.plan_at(Vector2i(6, 5)).to_rect
	_mover.rotate_turns()
	_mover.hover_at(Vector2i(6, 5))
	var slab := _mover.ghost_node().get_node("Room") as MeshInstance3D
	var size := (slab.mesh as BoxMesh).size
	print("turn: before=%s turns=%d slab=%s" % [before, _mover.turns, size])
	assert_int(_mover.turns).is_equal(1)
	assert_that(before.size).is_equal(Vector2i(8, 6))
	assert_float(size.x).is_equal_approx(6.0 - 0.04, 0.001)
	assert_float(size.z).is_equal_approx(8.0 - 0.04, 0.001)
	_mover.set_down(Vector2i(6, 5))
	assert_that(_rect().size).is_equal(Vector2i(6, 8))


func test_a_refused_set_down_changes_nothing_and_keeps_the_room_in_hand() -> void:
	_pick_up()
	var balance := _finances.wallet.balance
	var undo_depth := _mode.undo_history().size()
	var bin_before := _mode.grid.get_object(_bin)
	# Centre (10, 3) puts the cafe on the toilet room.
	_mover.hover_at(Vector2i(10, 3))
	var result := _mover.set_down(Vector2i(10, 3))
	print("refused: reason=%s status=%s" % [result.reason, _mover.status_text()])
	assert_bool(result.ok).is_false()
	assert_int(result.reason).is_equal(BuildResult.Reason.ROOM_OVERLAP)
	assert_bool(_mover.active).is_true()
	assert_that(_ghost_colour()).is_equal(BuildMode.INVALID_TINT)
	assert_int(_mover.refusal().reason).is_equal(BuildResult.Reason.ROOM_OVERLAP)
	assert_str(_mover.status_text()).contains("Cafe")
	assert_that(_rect()).is_equal(CAFE)
	assert_int(_finances.wallet.balance).is_equal(balance)
	assert_int(_mode.undo_history().size()).is_equal(undo_depth)
	assert_that(_mode.grid.get_object(_bin)).is_equal(bin_before)


func test_cancel_drops_the_room_with_no_change_on_esc_right_click_and_tool_change() -> void:
	var balance := _finances.wallet.balance
	var undo_depth := _mode.undo_history().size()
	for how in 3:
		_pick_up()
		_mover.hover_at(Vector2i(8, 7))
		match how:
			0:
				var esc := InputEventKey.new()
				esc.physical_keycode = KEY_ESCAPE
				esc.pressed = true
				_mover._unhandled_input(esc)
			1:
				var click := InputEventMouseButton.new()
				click.button_index = MOUSE_BUTTON_RIGHT
				click.pressed = true
				_mover._unhandled_input(click)
			2:
				_mode.set_tool(BuildMode.Tool.FLOOR)
		assert_bool(_mover.active).is_false()
		assert_int(_mover.ghost_node().get_child_count()).is_equal(0)
		assert_int(_mover.get_node("RoomMoveDim").get_child_count()).is_equal(0)
		assert_that(_rect()).is_equal(CAFE)
		_mode.set_tool(BuildMode.Tool.CAFE_ROOM)
	assert_int(_finances.wallet.balance).is_equal(balance)
	assert_int(_mode.undo_history().size()).is_equal(undo_depth)


func test_set_down_moves_room_and_pieces_as_one_undo_step() -> void:
	_pick_up()
	var undo_depth := _mode.undo_history().size()
	var bin_before := _mode.grid.get_object(_bin)
	# Centre (8, 7): columns 5 to 12, rows 5 to 10, all floored.
	_mover.hover_at(Vector2i(8, 7))
	var result := _mover.set_down(Vector2i(8, 7))
	print("set down: ok=%s rect=%s depth=%d" % [result.ok, _rect(), _mode.undo_history().size()])
	assert_bool(result.ok).is_true()
	assert_bool(_mover.active).is_false()
	assert_that(_rect()).is_equal(Rect2i(5, 5, 8, 6))
	var bin_now := _mode.grid.get_object(_bin)
	assert_that(bin_now["anchor"]).is_equal((bin_before["anchor"] as Vector2i) + Vector2i(3, 3))
	assert_int(bin_now["paid"]).is_equal(BIN_PAID)
	assert_int(_mode.grid.get_object(_pot)["paid"]).is_equal(POT_PAID)
	assert_int(_mode.undo_history().size()).is_equal(undo_depth + 1)
	_mode.undo()
	assert_that(_rect()).is_equal(CAFE)
	assert_that(_mode.grid.get_object(_bin)).is_equal(bin_before)
	assert_int(_mode.undo_history().size()).is_equal(undo_depth)


func test_the_cost_line_is_only_the_new_floor_the_spot_needs() -> void:
	_pick_up()
	_mover.hover_at(Vector2i(8, 7))
	assert_that(_mover.preview_price()).is_equal(Vector2i.ZERO)
	# Centre (14, 8): columns 10 to 17, rows 6 to 11; most of it is bare ground.
	_mover.hover_at(Vector2i(16, 5))
	var planned := _mover.plan_at(Vector2i(16, 5))
	var price := _mover.preview_price()
	print("cost: plan=%d price=%s" % [planned.cost, price])
	assert_int(planned.cost).is_greater(0)
	assert_that(price).is_equal(Vector2i(planned.cost, planned.cost))
	var before := _finances.wallet.balance
	_mover.set_down(Vector2i(16, 5))
	assert_int(before - _finances.wallet.balance).is_equal(planned.cost)


func test_a_click_on_the_spot_it_was_lifted_from_drops_it_without_an_undo_step() -> void:
	_pick_up()
	var undo_depth := _mode.undo_history().size()
	var result := _mover.set_down(Vector2i(5, 4))
	assert_bool(result == null).is_true()
	assert_bool(_mover.active).is_false()
	assert_that(_rect()).is_equal(CAFE)
	assert_int(_mode.undo_history().size()).is_equal(undo_depth)


func _piece_meshes(object_id: int) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	var node := _mode.object_node(object_id)
	assert_object(node).is_not_null()
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		meshes.append(mesh as MeshInstance3D)
	return meshes


func test_an_edit_inside_the_held_room_cancels_the_move() -> void:
	_pick_up()
	_mover.hover_at(Vector2i(8, 7))
	assert_bool(_mover.active).is_true()
	# A bin placed in the room after pick-up: the ghost no longer shows the room.
	_place(&"trash_can", Vector2i(7, 6), BIN_PAID)
	_mover.hover_at(Vector2i(8, 7))
	assert_bool(_mover.active).is_false()
	assert_that(_rect()).is_equal(CAFE)
	# A removal, then a click before the next hover: the set-down cancels.
	_mode.set_tool(BuildMode.Tool.CAFE_ROOM)
	_pick_up()
	_mover.hover_at(Vector2i(8, 7))
	var balance := _finances.wallet.balance
	var undo_depth := _mode.undo_history().size()
	var bin_before := _mode.grid.get_object(_bin)
	_mode.grid.apply(BuildEdit.remove_object(_pot))
	var result := _mover.set_down(Vector2i(8, 7))
	print("edit in room: result null=%s active=%s" % [result == null, _mover.active])
	assert_bool(result == null).is_true()
	assert_bool(_mover.active).is_false()
	assert_that(_rect()).is_equal(CAFE)
	assert_that(_mode.grid.get_object(_bin)).is_equal(bin_before)
	assert_int(_finances.wallet.balance).is_equal(balance)
	assert_int(_mode.undo_history().size()).is_equal(undo_depth)


func test_an_undo_while_the_room_is_held_cancels_the_move() -> void:
	var history := _mode.undo_history()
	history.begin_action()
	var late_bin := _place(&"trash_can", Vector2i(7, 6), BIN_PAID)
	history.end_action()
	_pick_up()
	_mover.hover_at(Vector2i(8, 7))
	var undone := _mode.undo()
	print("undo: ok=%s" % undone.ok)
	assert_bool(undone.ok).is_true()
	assert_dict(_mode.grid.get_object(late_bin)).is_empty()
	assert_bool(_mover.active).is_true()
	var result := _mover.set_down(Vector2i(8, 7))
	assert_bool(result == null).is_true()
	assert_bool(_mover.active).is_false()
	assert_that(_rect()).is_equal(CAFE)


func test_a_change_between_the_preview_and_the_set_down_is_refused_with_no_change() -> void:
	_pick_up()
	# Centre (16, 5): columns 13 to 20, rows 3 to 8, all bare ground.
	_mover.hover_at(Vector2i(16, 5))
	assert_bool(_mover.refusal() == null).is_true()
	assert_int(_mover.preview_price().x).is_greater(0)
	var balance := _finances.wallet.balance
	var undo_depth := _mode.undo_history().size()
	var bin_before := _mode.grid.get_object(_bin)
	# Floor a cell of the previewed spot after the preview: the plan is out of date.
	_mode.grid.apply(BuildEdit.paint_floor(Vector2i(15, 5), BuildGrid.FLOOR_TILE, 3))
	var floor_before := _mode.grid.floor_at(Vector2i(14, 5))
	var result := _mover.set_down(Vector2i(16, 5))
	print("stale: reason=%s status=%s" % [result.reason, _mover.status_text()])
	assert_bool(result.ok).is_false()
	assert_int(result.reason).is_equal(BuildResult.Reason.MOVE_CHANGED)
	assert_bool(_mover.active).is_true()
	assert_that(_rect()).is_equal(CAFE)
	assert_that(_mode.grid.get_object(_bin)).is_equal(bin_before)
	assert_int(_mode.grid.floor_at(Vector2i(14, 5))).is_equal(floor_before)
	assert_int(_finances.wallet.balance).is_equal(balance)
	assert_int(_mode.undo_history().size()).is_equal(undo_depth)


func test_every_piece_of_the_original_is_dimmed_while_held_and_restored_after() -> void:
	await await_idle_frame()
	var originals := {}
	for id in [_bin, _pot]:
		var meshes := _piece_meshes(id)
		assert_int(meshes.size()).is_greater(0)
		for mesh in meshes:
			originals[mesh] = mesh.material_override
	for how in 2:
		_pick_up()
		var dimmed := 0
		for mesh in originals:
			if (mesh as MeshInstance3D).material_override != originals[mesh]:
				dimmed += 1
		print("dimmed %d of %d meshes (how=%d)" % [dimmed, originals.size(), how])
		assert_int(dimmed).is_equal(originals.size())
		assert_int(_mover.get_node("RoomMoveDim").get_child_count()).is_equal(1)
		if how == 0:
			_mover.cancel()
		else:
			_mover.hover_at(Vector2i(8, 7))
			assert_bool(_mover.set_down(Vector2i(8, 7)).ok).is_true()
		for mesh in originals:
			assert_object((mesh as MeshInstance3D).material_override).is_equal(originals[mesh])
		assert_int(_mover.get_node("RoomMoveDim").get_child_count()).is_equal(0)
