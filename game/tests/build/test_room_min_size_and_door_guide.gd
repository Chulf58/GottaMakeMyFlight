class_name TestRoomMinSizeAndDoorGuide
extends GdUnitTestSuite
## Regression tests for Two Point Build UX Slice 2:
## 1) RoomTool.final_rect() & too_small_note() across fresh drags, rotated drags,
##    and RoomResize.auto_extend(), surfaced in drag_label(), BuildStatus, and BuildGhost.
## 2) Non-refusal of undersized RoomTool.mark().
## 3) Guided Door promotion in BuildMenuCatalog.room_context_entries() and automatic
##    BuildMenu pulse on first missing tool after room commit, clearing on click or Ready.

const NORTH := BuildGrid.Side.NORTH
const SOUTH := BuildGrid.Side.SOUTH

var _port: SubViewport
var _finances: Finances
var _mode: BuildMode
var _menu: BuildMenu


func before_test() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_finances = Finances.new()
	_finances.wallet.credit(50000, Wallet.Category.FEES)
	_port.add_child(_finances)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(20, 20)
	_mode.initial_tool = BuildMode.Tool.NONE
	_mode.finances = _finances
	_port.add_child(_mode)
	_mode.set_process(false)
	_menu = BuildMenu.new()
	_menu.build_mode = _mode
	_port.add_child(_menu)
	var edits: Array[BuildEdit] = []
	for y in range(2, 16):
		for x in range(2, 16):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	_mode.grid.apply_batch(edits)


func after_test() -> void:
	_port.free()


func _at(cell: Vector2i) -> Vector3:
	return _mode.grid.cell_to_world(cell)


func _drag_preview(tool: BuildMode.Tool, from: Vector2i, to: Vector2i) -> void:
	_mode.set_tool(tool)
	_mode.begin_area(_at(from))
	_mode.move_area(_at(to))
	_mode._update_ghost(_at(to))


func _drag_commit(tool: BuildMode.Tool, from: Vector2i, to: Vector2i) -> void:
	_mode.set_tool(tool)
	_mode.begin_area(_at(from))
	_mode.move_area(_at(to))
	_mode.finish_area()


func _ghost_materials() -> Array[Material]:
	var mats: Array[Material] = []
	for child in _mode._ghost.get_children():
		if child is MeshInstance3D and not child.is_queued_for_deletion():
			mats.append((child as MeshInstance3D).material_override)
	return mats


func _entry_tools(entries: Array[Dictionary]) -> Array[BuildMode.Tool]:
	var out: Array[BuildMode.Tool] = []
	for entry: Dictionary in entries:
		out.append(entry["tool"])
	return out


func _entry_for(entries: Array[Dictionary], tool: BuildMode.Tool) -> Dictionary:
	for entry: Dictionary in entries:
		if entry["tool"] == tool:
			return entry
	return {}


func test_final_rect_and_too_small_note_across_fresh_rotated_and_auto_extend() -> void:
	var small_cafe := Rect2i(3, 3, 2, 2)
	assert_that(RoomTool.final_rect(_mode.grid, small_cafe, &"cafe")).is_equal(small_cafe)
	assert_str(RoomTool.too_small_note(_mode.grid, small_cafe, &"cafe")).is_equal(
		"Too small: a cafe needs at least 3x3"
	)
	assert_str(RoomTool.drag_label(_mode.grid, small_cafe, &"cafe")).is_equal(
		"Cafe 2 x 2  Too small: a cafe needs at least 3x3"
	)

	# Toilet min_size is 2x3; rotated 3x2 fits and produces no warning.
	var rotated_toilet := Rect2i(3, 3, 3, 2)
	assert_str(RoomTool.too_small_note(_mode.grid, rotated_toilet, &"toilet")).is_empty()
	assert_str(RoomTool.drag_label(_mode.grid, rotated_toilet, &"toilet")).is_equal("Toilet 3 x 2")

	# Flush 1x3 drag against existing 2x3 cafe merges to 3x3 -> valid, no warning!
	assert_bool(RoomTool.mark(_mode.grid, Rect2i(3, 3, 2, 3), &"cafe").ok).is_true()
	var extend_drag := Rect2i(5, 3, 1, 3)
	assert_that(RoomTool.final_rect(_mode.grid, extend_drag, &"cafe")).is_equal(Rect2i(3, 3, 3, 3))
	assert_str(RoomTool.too_small_note(_mode.grid, extend_drag, &"cafe")).is_empty()
	_drag_preview(BuildMode.Tool.CAFE_ROOM, Vector2i(5, 3), Vector2i(5, 5))
	assert_str(_mode.status_text()).is_equal("Cafe 3 x 3")
	_mode.cancel_area()

	# Flush 1x2 drag against existing 1x2 cafe merges to 2x2 -> still too small, warns via BuildStatus!
	assert_bool(RoomTool.mark(_mode.grid, Rect2i(8, 3, 1, 2), &"cafe").ok).is_true()
	_drag_preview(BuildMode.Tool.CAFE_ROOM, Vector2i(9, 3), Vector2i(9, 4))
	assert_str(_mode.status_text()).is_equal("Cafe 2 x 2  Too small: a cafe needs at least 3x3")
	_mode.cancel_area()


func test_build_ghost_tints_amber_on_undersized_green_on_valid_and_red_on_refused() -> void:
	assert_that(BuildGhost.WARN_TINT).is_not_equal(BuildMode.VALID_TINT)
	assert_that(BuildGhost.WARN_TINT).is_not_equal(BuildMode.INVALID_TINT)

	# Undersized valid 2x2 Cafe -> amber warning material.
	_drag_preview(BuildMode.Tool.CAFE_ROOM, Vector2i(3, 3), Vector2i(4, 4))
	var warn_mats := _ghost_materials()
	assert_array(warn_mats).is_not_empty()
	for mat in warn_mats:
		assert_object(mat).is_same(BuildGhost._warn_material)
	_mode.cancel_area()

	# Valid 3x3 Cafe -> green valid material.
	_drag_preview(BuildMode.Tool.CAFE_ROOM, Vector2i(3, 3), Vector2i(5, 5))
	var ok_mats := _ghost_materials()
	assert_array(ok_mats).is_not_empty()
	for mat in ok_mats:
		assert_object(mat).is_same(_mode._valid_material)
	_mode.cancel_area()

	# Commit a 2x3 Cafe and verify auto-extend 1x3 -> 3x3 uses green valid material.
	assert_bool(RoomTool.mark(_mode.grid, Rect2i(8, 3, 2, 3), &"cafe").ok).is_true()
	_drag_preview(BuildMode.Tool.CAFE_ROOM, Vector2i(10, 3), Vector2i(10, 5))
	for mat in _ghost_materials():
		assert_object(mat).is_same(_mode._valid_material)
	_mode.cancel_area()

	# Overlapping drag (starting outside existing room and crossing into it) -> red invalid material.
	_drag_preview(BuildMode.Tool.CAFE_ROOM, Vector2i(7, 3), Vector2i(9, 5))
	var bad_mats := _ghost_materials()
	assert_array(bad_mats).is_not_empty()
	for mat in bad_mats:
		assert_object(mat).is_same(_mode._invalid_material)
	_mode.cancel_area()

	# Undersized auto-extend (1x2 flush against 1x2 Cafe -> 2x2) -> amber warning material.
	assert_bool(RoomTool.mark(_mode.grid, Rect2i(12, 3, 1, 2), &"cafe").ok).is_true()
	_drag_preview(BuildMode.Tool.CAFE_ROOM, Vector2i(13, 3), Vector2i(13, 4))
	var ext_warn_mats := _ghost_materials()
	assert_array(ext_warn_mats).is_not_empty()
	for mat in ext_warn_mats:
		assert_object(mat).is_same(BuildGhost._warn_material)
	_mode.cancel_area()


func test_room_tool_mark_still_commits_undersized_rooms() -> void:
	var res := RoomTool.mark(_mode.grid, Rect2i(3, 3, 2, 2), &"cafe", _finances.wallet)
	assert_bool(res.ok).is_true()
	assert_int(res.room_id).is_greater(0)
	var status := RoomRules.status(_mode.grid, res.room_id)
	assert_bool(status.too_small).is_true()
	assert_bool(status.ok).is_false()


func test_room_context_entries_promote_door_when_unopened_and_preserve_bag_room_bay_door() -> void:
	# Sealed lounge: SOFA (missing mandatory) -> DOOR (missing) -> optional items -> LOUNGE_ROOM.
	var lounge_res := RoomTool.mark(_mode.grid, Rect2i(3, 3, 4, 4), &"lounge", _finances.wallet)
	assert_bool(lounge_res.ok).is_true()
	var sealed_lounge := BuildMenuCatalog.room_context_entries(
		&"lounge", _mode.grid, lounge_res.room_id
	)
	(
		assert_array(_entry_tools(sealed_lounge))
		. is_equal(
			[
				BuildMode.Tool.SOFA,
				BuildMode.Tool.DOOR,
				BuildMode.Tool.ARMCHAIR,
				BuildMode.Tool.WORK_DESK,
				BuildMode.Tool.LOUNGE_ROOM,
			]
		)
	)
	assert_bool(_entry_for(sealed_lounge, BuildMode.Tool.DOOR)["missing"]).is_true()
	assert_bool(_entry_for(sealed_lounge, BuildMode.Tool.DOOR)["mandatory"]).is_false()

	# Place SOFA so only DOOR is missing -> DOOR moves to index 0!
	_mode.grid.apply(BuildEdit.place_object(&"lounge_sofa", Vector2i(4, 4), 0))
	var need_door_only := BuildMenuCatalog.room_context_entries(
		&"lounge", _mode.grid, lounge_res.room_id
	)
	(
		assert_array(_entry_tools(need_door_only))
		. is_equal(
			[
				BuildMode.Tool.DOOR,
				BuildMode.Tool.SOFA,
				BuildMode.Tool.ARMCHAIR,
				BuildMode.Tool.WORK_DESK,
				BuildMode.Tool.LOUNGE_ROOM,
			]
		)
	)

	# Place a DOOR -> has_opening becomes true -> DOOR moves back to optional position!
	var door_edits := DoorPlacement.edits_for(
		_mode.grid, BuildEdit.place_wall(Vector2i(4, 6), SOUTH, BuildGrid.WallKind.DOOR)
	)
	assert_bool(BuildTransaction.commit_plan(_mode.grid, door_edits, _finances.wallet).ok).is_true()
	var opened_lounge := BuildMenuCatalog.room_context_entries(
		&"lounge", _mode.grid, lounge_res.room_id
	)
	(
		assert_array(_entry_tools(opened_lounge))
		. is_equal(
			[
				BuildMode.Tool.SOFA,
				BuildMode.Tool.ARMCHAIR,
				BuildMode.Tool.WORK_DESK,
				BuildMode.Tool.DOOR,
				BuildMode.Tool.LOUNGE_ROOM,
			]
		)
	)
	assert_bool(_entry_for(opened_lounge, BuildMode.Tool.DOOR)["missing"]).is_false()

	# Sealed bag_room preserves BAY_DOOR front-sorting while promoting DOOR ahead of optional CART.
	var bag_res := RoomTool.mark(_mode.grid, Rect2i(9, 3, 3, 3), &"bag_room", _finances.wallet)
	assert_bool(bag_res.ok).is_true()
	var sealed_bag := BuildMenuCatalog.room_context_entries(
		&"bag_room", _mode.grid, bag_res.room_id
	)
	(
		assert_array(_entry_tools(sealed_bag))
		. is_equal(
			[
				BuildMode.Tool.BAY_DOOR,
				BuildMode.Tool.BELT,
				BuildMode.Tool.DOOR,
				BuildMode.Tool.CART,
				BuildMode.Tool.BAG_ROOM,
			]
		)
	)
	# Open edge (remove wall) restores normal optional DOOR position.
	_mode.grid.apply(BuildEdit.remove_wall(Vector2i(10, 5), SOUTH))
	var open_bag := BuildMenuCatalog.room_context_entries(&"bag_room", _mode.grid, bag_res.room_id)
	(
		assert_array(_entry_tools(open_bag))
		. is_equal(
			[
				BuildMode.Tool.BAY_DOOR,
				BuildMode.Tool.BELT,
				BuildMode.Tool.CART,
				BuildMode.Tool.DOOR,
				BuildMode.Tool.BAG_ROOM,
			]
		)
	)


func test_build_menu_pulses_first_missing_tool_after_room_commit_and_clears_on_click_or_ready(
) -> void:
	# New bag_room commit pulses BAY_DOOR first, and clicking BAY_DOOR clears the pulse.
	_menu.press_category(BuildMenu.category_index("baggage"))
	_drag_commit(BuildMode.Tool.BAG_ROOM, Vector2i(9, 3), Vector2i(11, 5))
	await await_idle_frame()
	assert_bool(_menu.is_room_context()).is_true()
	assert_int(_menu.pulsed_tool()).is_equal(BuildMode.Tool.BAY_DOOR)
	_menu.card(BuildMode.Tool.BAY_DOOR).pressed.emit()
	await await_idle_frame()
	assert_int(_menu.pulsed_tool()).is_equal(BuildMode.Tool.NONE)

	# New lounge commit pulses SOFA first, and becoming Ready clears the pulse without clicking.
	_menu.press_category(BuildMenu.category_index("facilities"))
	_drag_commit(BuildMode.Tool.LOUNGE_ROOM, Vector2i(3, 3), Vector2i(6, 6))
	await await_idle_frame()
	assert_int(_menu.pulsed_tool()).is_equal(BuildMode.Tool.SOFA)

	var sofa_res := _mode.grid.apply(BuildEdit.place_object(&"lounge_sofa", Vector2i(4, 4), 0))
	assert_bool(sofa_res.ok).is_true()
	await await_idle_frame()
	# Still missing entrance, so pulse remains until room becomes Ready.
	assert_int(_menu.pulsed_tool()).is_equal(BuildMode.Tool.SOFA)
	var door_edits := DoorPlacement.edits_for(
		_mode.grid, BuildEdit.place_wall(Vector2i(4, 6), SOUTH, BuildGrid.WallKind.DOOR)
	)
	assert_bool(BuildTransaction.commit_plan(_mode.grid, door_edits, _finances.wallet).ok).is_true()
	await await_idle_frame()
	assert_int(_menu.pulsed_tool()).is_equal(BuildMode.Tool.NONE)
