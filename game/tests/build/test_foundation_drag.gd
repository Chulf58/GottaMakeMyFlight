class_name TestFoundationDrag
extends GdUnitTestSuite
## Comprehensive tests for Two Point Build UX Slice 1: Expand Terminal /
## Foundation Drag (`BuildMode.Tool.FOUNDATION` + `FoundationDrag`).

const NORTH := BuildGrid.Side.NORTH
const EAST := BuildGrid.Side.EAST
const SOUTH := BuildGrid.Side.SOUTH
const WEST := BuildGrid.Side.WEST

var _port: SubViewport
var _finances: Finances
var _mode: BuildMode


func before_test() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_finances = Finances.new()
	_finances.wallet.credit(100000, Wallet.Category.FEES)
	_port.add_child(_finances)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(24, 24)
	_mode.initial_tool = BuildMode.Tool.NONE
	_mode.finances = _finances
	_port.add_child(_mode)
	_mode.set_process(false)


func after_test() -> void:
	_port.free()


func _at(cell: Vector2i) -> Vector3:
	return _mode.grid.cell_to_world(cell)


func _set_balance(amount: int) -> void:
	assert_bool(_finances.wallet.from_snapshot({"balance": str(amount)})).is_true()


func _drag_foundation(from: Vector2i, to: Vector2i) -> AreaDrag.Outcome:
	_mode.set_tool(BuildMode.Tool.FOUNDATION)
	_mode.begin_area(_at(from))
	_mode.move_area(_at(to))
	return _mode.finish_area()


func _build_terminal(rect: Rect2i, with_door_on_east := false) -> void:
	var edits: Array[BuildEdit] = []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	for x in range(rect.position.x, rect.end.x):
		edits.append(BuildEdit.place_wall(Vector2i(x, rect.position.y), NORTH))
		edits.append(BuildEdit.place_wall(Vector2i(x, rect.end.y - 1), SOUTH))
	for y in range(rect.position.y, rect.end.y):
		edits.append(BuildEdit.place_wall(Vector2i(rect.position.x, y), WEST))
		edits.append(BuildEdit.place_wall(Vector2i(rect.end.x - 1, y), EAST))
	if with_door_on_east and rect.size.y >= 3:
		var mid_y := rect.position.y + rect.size.y / 2
		edits.append(
			BuildEdit.place_wall(Vector2i(rect.end.x - 1, mid_y), EAST, BuildGrid.WallKind.DOOR)
		)
	var res := BuildTransaction.commit_composite(_mode.grid, edits, _finances.wallet)
	assert_bool(res.ok).override_failure_message(res.reason_text()).is_true()


func test_detached_foundation_lays_floor_and_four_walls_with_one_atomic_undo() -> void:
	var start_bal := _finances.wallet.balance
	var rect := Rect2i(4, 5, 4, 3)
	var preview := FoundationDrag.plan(_mode.grid, rect, _finances.wallet)
	assert_bool(preview.ok).is_true()
	var expected_cost := (
		12 * PriceTable.FLOOR_PRICE + 14 * PriceTable.WALL_PRICES[BuildGrid.WallKind.PLAIN]
	)
	assert_int(preview.net_cost).is_equal(expected_cost)

	var commits := []
	_mode.player_committed.connect(func(info: Dictionary) -> void: commits.append(info))
	var outcome := _drag_foundation(Vector2i(4, 5), Vector2i(7, 7))
	assert_bool(outcome != null and outcome.ok).is_true()
	assert_int(outcome.placed).is_equal(12)
	assert_int(start_bal - _finances.wallet.balance).is_equal(expected_cost)
	assert_int(commits.size()).is_equal(1)
	assert_int(_mode.undo_history().size()).is_equal(1)

	for y in range(5, 8):
		for x in range(4, 8):
			assert_int(_mode.grid.floor_at(Vector2i(x, y))).is_equal(BuildGrid.FLOOR_TILE)
	for x in range(4, 8):
		assert_int(_mode.grid.wall_kind(Vector2i(x, 5), NORTH)).is_equal(BuildGrid.WallKind.PLAIN)
		assert_int(_mode.grid.wall_kind(Vector2i(x, 7), SOUTH)).is_equal(BuildGrid.WallKind.PLAIN)
	for y in range(5, 8):
		assert_int(_mode.grid.wall_kind(Vector2i(4, y), WEST)).is_equal(BuildGrid.WallKind.PLAIN)
		assert_int(_mode.grid.wall_kind(Vector2i(7, y), EAST)).is_equal(BuildGrid.WallKind.PLAIN)
	# No interior walls inside the new rectangle.
	assert_int(_mode.grid.wall_kind(Vector2i(5, 6), EAST)).is_equal(BuildGrid.WallKind.NONE)
	assert_int(_mode.grid.wall_kind(Vector2i(5, 6), SOUTH)).is_equal(BuildGrid.WallKind.NONE)

	# Single Undo removes all floors and walls and refunds exact cost.
	var undone := _mode.undo()
	assert_bool(undone != null and undone.ok).is_true()
	assert_int(_finances.wallet.balance).is_equal(start_bal)
	for y in range(5, 8):
		for x in range(4, 8):
			assert_int(_mode.grid.floor_at(Vector2i(x, y))).is_equal(BuildGrid.FLOOR_NONE)
			for s in 4:
				assert_int(_mode.grid.wall_kind(Vector2i(x, y), s)).is_equal(
					BuildGrid.WallKind.NONE
				)


func test_expand_adjacent_outside_opens_door_and_plain_seams_preserves_interior_and_rooms() -> void:
	# Base terminal (3,3)-(6,7) [4x5] with a WallKind.DOOR + adjacent PLAIN walls on x=6 EAST,
	# an interior divider wall at x=4 EAST, and a Cafe room at (3,3,2,2).
	_build_terminal(Rect2i(3, 3, 4, 5), true)
	assert_bool(_mode.grid.apply(BuildEdit.place_wall(Vector2i(4, 6), EAST)).ok).is_true()
	assert_bool(_mode.grid.apply(BuildEdit.place_room(Rect2i(3, 3, 2, 2), &"cafe")).ok).is_true()
	# Add a glass wall on (6,3) EAST to verify GLASS seam walls stay intact.
	(
		assert_bool(
			(
				_mode
				. grid
				. apply(BuildEdit.place_wall(Vector2i(6, 3), EAST, BuildGrid.WallKind.GLASS))
				. ok
			)
		)
		. is_true()
	)
	var before_bal := _finances.wallet.balance
	var preview := FoundationDrag.plan(_mode.grid, Rect2i(7, 3, 3, 5), _finances.wallet)
	assert_bool(preview.ok).is_true()

	var outcome := _drag_foundation(Vector2i(7, 3), Vector2i(9, 7))
	assert_bool(outcome != null and outcome.ok).is_true()
	assert_int(outcome.placed).is_equal(15)
	assert_int(before_bal - _finances.wallet.balance).is_equal(preview.net_cost)

	# Seam DOOR (6,5) EAST and seam PLAIN walls (6,4),(6,6),(6,7) EAST were removed cleanly!
	for y in range(4, 8):
		assert_int(_mode.grid.wall_kind(Vector2i(6, y), EAST)).is_equal(BuildGrid.WallKind.NONE)
	# Glass seam wall on (6,3) EAST stayed untouched.
	assert_int(_mode.grid.wall_kind(Vector2i(6, 3), EAST)).is_equal(BuildGrid.WallKind.GLASS)
	# Existing interior wall inside original terminal stayed untouched.
	assert_int(_mode.grid.wall_kind(Vector2i(4, 6), EAST)).is_equal(BuildGrid.WallKind.PLAIN)
	# New outer perimeter walls added on N/S/E of expansion (none on W seam!).
	for x in range(7, 10):
		assert_int(_mode.grid.wall_kind(Vector2i(x, 3), NORTH)).is_equal(BuildGrid.WallKind.PLAIN)
		assert_int(_mode.grid.wall_kind(Vector2i(x, 7), SOUTH)).is_equal(BuildGrid.WallKind.PLAIN)
	for y in range(3, 8):
		assert_int(_mode.grid.wall_kind(Vector2i(9, y), EAST)).is_equal(BuildGrid.WallKind.PLAIN)

	# Undo restores both PLAIN walls and the DOOR wall in one step without DOOR_NEEDS_WALLS error!
	assert_bool(_mode.undo().ok).is_true()
	assert_int(_finances.wallet.balance).is_equal(before_bal)
	assert_int(_mode.grid.wall_kind(Vector2i(6, 5), EAST)).is_equal(BuildGrid.WallKind.DOOR)
	assert_int(_mode.grid.wall_kind(Vector2i(6, 4), EAST)).is_equal(BuildGrid.WallKind.PLAIN)
	assert_int(_mode.grid.floor_at(Vector2i(7, 3))).is_equal(BuildGrid.FLOOR_NONE)


func test_expand_from_inside_terminal_outward_opens_seam_and_preserves_room_walls() -> void:
	# Existing terminal (3,3)-(6,6) [4x4], with a room at (5,3,2,2) owning east wall at (6,3..4) EAST
	# and an interior wall at (4,5) EAST inside the drag overlap.
	_build_terminal(Rect2i(3, 3, 4, 4))
	assert_bool(_mode.grid.apply(BuildEdit.place_wall(Vector2i(4, 5), EAST)).ok).is_true()
	assert_bool(_mode.grid.apply(BuildEdit.place_room(Rect2i(5, 3, 2, 2), &"cafe")).ok).is_true()
	# Remove north wall on (4,3) to verify pre-existing open edges on old floor are NOT walled up.
	assert_bool(_mode.grid.apply(BuildEdit.remove_wall(Vector2i(4, 3), NORTH)).ok).is_true()

	# Drag from 1 cell INSIDE existing terminal (4,3) outward to (9,6)!
	var outcome := _drag_foundation(Vector2i(4, 3), Vector2i(9, 6))
	assert_bool(outcome != null and outcome.ok).is_true()
	assert_int(outcome.placed).is_equal(12)

	# Room walls at (6,3) EAST and (6,4) EAST are preserved!
	assert_int(_mode.grid.wall_kind(Vector2i(6, 3), EAST)).is_equal(BuildGrid.WallKind.PLAIN)
	assert_int(_mode.grid.wall_kind(Vector2i(6, 4), EAST)).is_equal(BuildGrid.WallKind.PLAIN)
	# Non-room seam walls at (6,5) EAST and (6,6) EAST are opened!
	assert_int(_mode.grid.wall_kind(Vector2i(6, 5), EAST)).is_equal(BuildGrid.WallKind.NONE)
	assert_int(_mode.grid.wall_kind(Vector2i(6, 6), EAST)).is_equal(BuildGrid.WallKind.NONE)
	# Interior wall between two already-floored cells (4,5)-(5,5) is untouched!
	assert_int(_mode.grid.wall_kind(Vector2i(4, 5), EAST)).is_equal(BuildGrid.WallKind.PLAIN)
	# Pre-existing open edge on (4,3) NORTH stays open (not walled up!).
	assert_int(_mode.grid.wall_kind(Vector2i(4, 3), NORTH)).is_equal(BuildGrid.WallKind.NONE)


func test_refuses_expanding_through_entrance_door_or_bay_door() -> void:
	_build_terminal(Rect2i(4, 6, 6, 4))
	# Place an entrance door on (6, 9) facing north (facing 2: back step SOUTH -> (6, 10)).
	assert_bool(_mode.grid.apply(BuildEdit.remove_wall(Vector2i(6, 9), SOUTH)).ok).is_true()
	(
		assert_bool(
			_mode.grid.apply(BuildEdit.place_object(&"entrance_door", Vector2i(6, 9), 2)).ok
		)
		. is_true()
	)
	var before_bal := _finances.wallet.balance
	var door_outcome := _drag_foundation(Vector2i(5, 10), Vector2i(8, 12))
	assert_bool(door_outcome.ok).is_false()
	assert_str(door_outcome.message()).is_equal(BuildWords.foundation_door_seal())
	assert_int(_finances.wallet.balance).is_equal(before_bal)
	assert_int(_mode.grid.floor_at(Vector2i(5, 10))).is_equal(BuildGrid.FLOOR_NONE)

	# Place a bay door on (5, 6)-(6, 6) facing south (facing 0: back step NORTH -> (5, 5), (6, 5)).
	assert_bool(_mode.grid.apply(BuildEdit.remove_wall(Vector2i(5, 6), NORTH)).ok).is_true()
	assert_bool(_mode.grid.apply(BuildEdit.remove_wall(Vector2i(6, 6), NORTH)).ok).is_true()
	(
		assert_bool(
			_mode.grid.apply(BuildEdit.place_object(&"baggage_bay_door", Vector2i(5, 6), 0)).ok
		)
		. is_true()
	)
	var bay_outcome := _drag_foundation(Vector2i(4, 3), Vector2i(7, 5))
	assert_bool(bay_outcome.ok).is_false()
	assert_str(bay_outcome.message()).is_equal(BuildWords.foundation_door_seal())
	assert_int(_finances.wallet.balance).is_equal(before_bal)
	assert_int(_mode.grid.floor_at(Vector2i(4, 3))).is_equal(BuildGrid.FLOOR_NONE)


func test_refuses_unowned_land_plane_area_and_unaffordable_wallet_atomically() -> void:
	# 1) Unaffordable wallet leaves zero floors, zero walls, unchanged balance.
	_set_balance(50)
	var unaff := _drag_foundation(Vector2i(4, 4), Vector2i(6, 6))
	assert_bool(unaff.ok).is_false()
	assert_str(unaff.message()).is_equal(BuildResult.REASON_TEXT[BuildResult.Reason.CANT_AFFORD])
	assert_int(_finances.wallet.balance).is_equal(50)
	assert_int(_mode.grid.floor_at(Vector2i(4, 4))).is_equal(BuildGrid.FLOOR_NONE)
	for s in 4:
		assert_int(_mode.grid.wall_kind(Vector2i(4, 4), s)).is_equal(BuildGrid.WallKind.NONE)

	# 2) SiteGrid unowned land & plane area refusal leaves zero partial state.
	_set_balance(100000)
	var site := preload("res://build/terminal_site.tres") as SiteDefinition
	var sg := SiteGrid.new(site)
	var land := LandPlots.for_site(site)
	land.own_start(site)
	sg.land = land
	var plane_y := site.starter_offset.y
	sg.guard = func(_g: BuildGrid, edit: BuildEdit) -> BuildResult:
		if edit.cell.y < plane_y:
			return BuildResult.refused(BuildResult.Reason.PLANE_AREA)
		return null
	# Drag wholly on unowned plot -> refused LAND_NOT_OWNED, zero partial edits.
	var unowned_cell := Vector2i(0, plane_y)
	assert_bool(land.owns_cell(unowned_cell)).is_false()
	var unowned_out := FoundationDrag.apply(sg, Rect2i(0, plane_y, 3, 3), _finances.wallet)
	assert_bool(unowned_out.ok).is_false()
	assert_str(unowned_out.message()).is_equal(
		BuildResult.REASON_TEXT[BuildResult.Reason.LAND_NOT_OWNED]
	)
	assert_int(_finances.wallet.balance).is_equal(100000)
	assert_int(sg.floor_at(unowned_cell)).is_equal(BuildGrid.FLOOR_NONE)

	# Drag wholly inside owned plane area -> refused PLANE_AREA, zero partial edits.
	var owned_top := site.starter_offset + Vector2i(2, -4)
	assert_bool(land.owns_cell(owned_top)).is_true()
	var plane_out := FoundationDrag.apply(
		sg, Rect2i(owned_top.x, owned_top.y, 3, 3), _finances.wallet
	)
	assert_bool(plane_out.ok).is_false()
	assert_str(plane_out.message()).is_equal(BuildResult.REASON_TEXT[BuildResult.Reason.PLANE_AREA])
	assert_int(_finances.wallet.balance).is_equal(100000)
	assert_int(sg.floor_at(owned_top)).is_equal(BuildGrid.FLOOR_NONE)


func test_preview_net_cost_accounts_for_seam_refunds_and_skips_blocked_single_edges() -> void:
	# Build (3,3)-(5,6) [3x4] paid terminal, then put a WallKind.DOOR on (5,4) EAST
	# with PLAIN walls on (5,3) EAST and (5,5) EAST.
	_build_terminal(Rect2i(3, 3, 3, 4))
	(
		assert_bool(
			_mode.grid.apply(BuildEdit.place_wall(Vector2i(5, 4), EAST, BuildGrid.WallKind.DOOR)).ok
		)
		. is_true()
	)

	# Expand only rows 3..3 (adjacent to the standing DOOR at (5,4) EAST which is NOT in rect):
	# removing seam PLAIN wall (5,3) EAST fails WALL_HOLDS_DOOR -> skipped cleanly!
	var before_bal := _finances.wallet.balance
	var plan := FoundationDrag.plan(_mode.grid, Rect2i(6, 3, 2, 1), _finances.wallet)
	assert_bool(plan.ok).is_true()
	assert_int(plan.skipped).is_equal(1)
	assert_str(plan.first_reason).is_equal(
		BuildResult.REASON_TEXT[BuildResult.Reason.WALL_HOLDS_DOOR]
	)

	var outcome := _drag_foundation(Vector2i(6, 3), Vector2i(7, 3))
	assert_bool(outcome.ok).is_true()
	assert_int(outcome.placed).is_equal(2)
	assert_int(outcome.skipped).is_equal(1)
	assert_str(outcome.message()).contains("skipped 1:")
	assert_int(before_bal - _finances.wallet.balance).is_equal(plan.net_cost)
	# The plain wall beside the door stayed intact.
	assert_int(_mode.grid.wall_kind(Vector2i(5, 3), EAST)).is_equal(BuildGrid.WallKind.PLAIN)

	# Now expand alongside a paid plain seam wall with no adjacent door: preview net cost
	# equals floor + new outer walls - 50% refund of the removed seam wall!
	_build_terminal(Rect2i(10, 10, 3, 3))
	var seam_refund := PriceTable.refund_of(PriceTable.WALL_PRICES[BuildGrid.WallKind.PLAIN])
	var exp_rect := Rect2i(13, 10, 2, 3)
	var exp_plan := FoundationDrag.plan(_mode.grid, exp_rect, _finances.wallet)
	# 6 floor tiles + 7 new outer plain walls (2N + 2S + 3E) - 3 seam plain wall refunds.
	var expected_net := (
		6 * PriceTable.FLOOR_PRICE
		+ 7 * PriceTable.WALL_PRICES[BuildGrid.WallKind.PLAIN]
		- 3 * seam_refund
	)
	assert_int(exp_plan.net_cost).is_equal(expected_net)
	var bal2 := _finances.wallet.balance
	var exp_out := _drag_foundation(Vector2i(13, 10), Vector2i(14, 12))
	assert_bool(exp_out.ok).is_true()
	assert_int(bal2 - _finances.wallet.balance).is_equal(expected_net)


func test_ghost_preview_and_menu_cost_and_single_click_behavior() -> void:
	var menu := BuildMenu.new()
	menu.build_mode = _mode
	_port.add_child(menu)

	# Single click with FOUNDATION does nothing (no 1x1 box).
	_mode.set_tool(BuildMode.Tool.FOUNDATION)
	_mode.begin_area(_at(Vector2i(5, 5)))
	assert_object(_mode.finish_area()).is_null()
	assert_int(_mode.grid.floor_at(Vector2i(5, 5))).is_equal(BuildGrid.FLOOR_NONE)

	# Dragging draws slab + outer walls and updates status + BuildMenu cost line.
	_mode.begin_area(_at(Vector2i(5, 5)))
	_mode.move_area(_at(Vector2i(7, 6)))
	BuildGhost.draw_area(_mode)
	var ghost := _mode.get_node("Ghost") as Node3D
	# 1 floor slab + 10 outer walls = 11 mesh children.
	assert_int(ghost.get_child_count()).is_equal(11)
	var expected_cost := (
		6 * PriceTable.FLOOR_PRICE + 10 * PriceTable.WALL_PRICES[BuildGrid.WallKind.PLAIN]
	)
	assert_str(_mode.status_text()).is_equal("3 x 2 · $%d" % expected_cost)
	assert_str(menu.preview_text()).is_equal("Cost %d" % expected_cost)

	# Unaffordable drag turns status into refusal and shows shortfall in menu cost line.
	_set_balance(100)
	_mode._on_balance_changed(100)
	BuildGhost.draw_area(_mode)
	assert_bool(_mode.status_is_refusal).is_true()
	assert_str(_mode.status_text()).contains(
		BuildResult.REASON_TEXT[BuildResult.Reason.CANT_AFFORD]
	)
	assert_str(menu.preview_text()).is_equal(
		"Cost %d   Short by %d" % [expected_cost, expected_cost - 100]
	)
	_mode.cancel_area()
