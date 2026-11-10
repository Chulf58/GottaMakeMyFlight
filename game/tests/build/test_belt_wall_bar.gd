class_name TestBeltWallBar
extends GdUnitTestSuite
## A Belt line refused by a wall names the wall edge that blocks it on its plan,
## and the ghost draws a red bar there that shows through other pieces (decision
## a-belt-refused-by-a-wall-draws-a-red-bar-on-the-blocking-wal). The edge comes
## from BeltShaper.plan_line(), never from a wall test of the ghost's own
## (anti_pattern a-build-ghost-or-preview-that-copies-the-sim-s-cell-rules-dr).

const WALL_CELL := Vector2i(5, 4)

var _mode: BuildMode


func before() -> void:
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(16, 16)
	add_child(_mode)
	var edits: Array[BuildEdit] = []
	for y in 16:
		for x in 16:
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	_mode.grid.apply_batch(edits)
	_mode.grid.apply(BuildEdit.place_wall(WALL_CELL, BuildGrid.Side.EAST))
	_mode.set_tool(BuildMode.Tool.BELT)


## The ghost skips a redraw for the hover key it drew last; each case draws afresh.
func before_test() -> void:
	_mode._hover_key = ""
	BuildGhost.clear(_mode)


func after() -> void:
	_mode.free()


## The ghost's blocking-wall bars that are not on their way out (clear() queues
## them). Found by material: a name would be taken by a queued sibling.
func _live_bars() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for child in _mode._ghost.get_children():
		if child.is_queued_for_deletion() or not child is MeshInstance3D:
			continue
		if (child as MeshInstance3D).material_override == _mode._wall_block_material:
			out.append(child as MeshInstance3D)
	return out


func test_a_line_across_a_wall_names_the_blocking_edge() -> void:
	var plan := BeltShaper.plan_line(_mode.grid, Vector2i(3, 4), Vector2i(8, 4), 0)
	print(
		"reason=%d wall_cell=%s wall_side=%d" % [plan.result.reason, plan.wall_cell, plan.wall_side]
	)
	assert_int(plan.result.reason).is_equal(BuildResult.Reason.BELT_WALL)
	assert_that(plan.wall_cell).is_equal(WALL_CELL)
	assert_int(plan.wall_side).is_equal(BuildGrid.Side.EAST)


func test_a_line_laid_the_other_way_names_the_same_edge_from_its_side() -> void:
	var plan := BeltShaper.plan_line(_mode.grid, Vector2i(8, 4), Vector2i(3, 4), 0)
	print("wall_cell=%s wall_side=%d" % [plan.wall_cell, plan.wall_side])
	assert_that(plan.wall_cell).is_equal(Vector2i(6, 4))
	assert_int(plan.wall_side).is_equal(BuildGrid.Side.WEST)
	# The same edge: the grid holds a wall there seen from either side.
	assert_bool(_mode.grid.has_wall(plan.wall_cell, plan.wall_side)).is_true()


func test_a_clear_line_names_no_edge() -> void:
	var plan := BeltShaper.plan_line(_mode.grid, Vector2i(3, 6), Vector2i(8, 6), 0)
	print("ok=%s cells=%d wall_side=%d" % [plan.result.ok, plan.cells.size(), plan.wall_side])
	assert_bool(plan.result.ok).is_true()
	assert_int(plan.cells.size()).is_equal(6)
	assert_int(plan.wall_side).is_equal(-1)


func test_the_ghost_draws_a_see_through_red_bar_on_the_blocking_edge() -> void:
	BuildGhost.draw_belt(_mode, Vector2i(3, 4), Vector2i(8, 4))
	var bars := _live_bars()
	assert_int(bars.size()).is_equal(1)
	var bar := bars[0]
	var edge := BuildView.wall_transform(_mode.grid, WALL_CELL, BuildGrid.Side.EAST)
	print("bar=%s edge=%s" % [bar.transform.origin, edge.origin])
	assert_float(bar.transform.origin.x).is_equal_approx(edge.origin.x, 0.001)
	assert_float(bar.transform.origin.z).is_equal_approx(edge.origin.z, 0.001)
	var material := bar.material_override as StandardMaterial3D
	assert_bool(material.no_depth_test).is_true()
	assert_that(material.albedo_color).is_equal(BuildMode.INVALID_TINT)
	# Thicker than the wall it covers, so it reads at range.
	assert_float((bar.mesh as BoxMesh).size.z).is_greater(BuildView.WALL_THICKNESS * 1.5)


func test_a_clear_line_draws_no_bar() -> void:
	BuildGhost.draw_belt(_mode, Vector2i(3, 4), Vector2i(8, 4))
	assert_int(_live_bars().size()).is_equal(1)
	BuildGhost.draw_belt(_mode, Vector2i(3, 6), Vector2i(8, 6))
	assert_int(_live_bars().size()).is_equal(0)
	# Control: the clear line drew its pieces.
	var live := 0
	for child in _mode._ghost.get_children():
		if not child.is_queued_for_deletion():
			live += 1
	print("live ghost children=%d" % live)
	assert_int(live).is_greater(0)
