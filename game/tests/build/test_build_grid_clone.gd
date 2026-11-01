class_name TestBuildGridClone
extends GdUnitTestSuite
## BuildGrid.clone(), the copy every trial check runs on (BuildUndo.
## trial_copy_of(): an undo, a template paste preview, the starter shell). On
## the 86x150 site a copy through to_snapshot() and from_snapshot() took about
## 0.7 s, most of it building the passenger A* graph three times, so moving the
## paste preview over the grid or undoing froze the game. The clone copies the
## grid's data and builds the A* graph only when a path is first asked for.
## Each case checks the clone is the same grid: the same snapshot, the same
## class with the same site and guard, its own data, and the same paths.
## The budgets are what a frame can take; the asserts allow more so a slow
## test machine does not fail them.

const SITE := preload("res://build/terminal_site.tres")
const CLONE_TARGET_MS := 20
const CLONE_ALLOWED_MS := 60
const UNDO_TARGET_MS := 100
const UNDO_ALLOWED_MS := 200
## Well east of the starter shell and the plane's area.
const FREE_CELL := Vector2i(60, 30)

var _grid: SiteGrid


func before() -> void:
	_grid = SiteGrid.new(SITE)
	assert_bool(StarterShell.place(_grid, SITE.starter_offset)).is_true()
	_grid.guard = _no_problem


func _no_problem(_on_grid: BuildGrid, _edit: BuildEdit) -> BuildResult:
	return null


func _ms_since(started: int) -> float:
	return (Time.get_ticks_usec() - started) / 1000.0


func test_a_clone_has_the_same_snapshot_class_site_and_guard() -> void:
	var started := Time.get_ticks_usec()
	var copy := _grid.clone()
	var ms := _ms_since(started)
	print("clone of the %s site grid: %.1f ms (target %d)" % [_grid.size, ms, CLONE_TARGET_MS])
	assert_object(copy).is_instanceof(SiteGrid)
	assert_object((copy as SiteGrid).site).is_same(SITE)
	assert_bool((copy as SiteGrid).guard == _grid.guard).is_true()
	assert_dict(copy.to_snapshot()).is_equal(_grid.to_snapshot())
	assert_float(ms).is_less(CLONE_ALLOWED_MS)


func test_a_trial_copy_is_a_clone() -> void:
	var started := Time.get_ticks_usec()
	var copy := BuildUndo.trial_copy_of(_grid)
	var ms := _ms_since(started)
	print("trial copy: %.1f ms (target %d)" % [ms, CLONE_TARGET_MS])
	assert_object(copy).is_instanceof(SiteGrid)
	assert_dict(copy.to_snapshot()).is_equal(_grid.to_snapshot())
	assert_float(ms).is_less(CLONE_ALLOWED_MS)


func test_an_edit_on_the_clone_leaves_the_grid_as_it_was() -> void:
	var before_edit := _grid.to_snapshot()
	var copy := _grid.clone()
	var floor := BuildEdit.paint_floor(FREE_CELL, BuildGrid.FLOOR_TILE, 1)
	floor.paid = PriceTable.price_of_floor()
	assert_bool(copy.apply(floor).ok).is_true()
	var wall := BuildEdit.place_wall(FREE_CELL, BuildGrid.Side.NORTH)
	assert_bool(copy.apply(wall).ok).is_true()
	print(
		(
			"clone: floor at %s %d, paid %d, north wall %d; grid: floor %d, north wall %d"
			% [
				FREE_CELL,
				copy.floor_at(FREE_CELL),
				copy.floor_paid(FREE_CELL),
				copy.wall_kind(FREE_CELL, BuildGrid.Side.NORTH),
				_grid.floor_at(FREE_CELL),
				_grid.wall_kind(FREE_CELL, BuildGrid.Side.NORTH)
			]
		)
	)
	assert_int(copy.floor_at(FREE_CELL)).is_equal(BuildGrid.FLOOR_TILE)
	assert_int(copy.floor_paid(FREE_CELL)).is_equal(PriceTable.price_of_floor())
	assert_int(copy.wall_kind(FREE_CELL, BuildGrid.Side.NORTH)).is_equal(BuildGrid.WallKind.PLAIN)
	assert_dict(_grid.to_snapshot()).is_equal(before_edit)


func test_a_clone_finds_the_same_paths_before_and_after_an_edit() -> void:
	var copy := _grid.clone()
	var from := ReferenceTerminal.ENTRANCE_CELL + SITE.starter_offset
	var to := ReferenceTerminal.EXIT_CELL + SITE.starter_offset + Vector2i(0, 1)
	var path := copy.find_path(from, to)
	var on_live := _grid.find_path(from, to)
	print(
		(
			"path %s -> %s: %d cells on the clone, %d on the grid"
			% [from, to, path.size(), on_live.size()]
		)
	)
	assert_int(path.size()).is_greater(2)
	assert_array(path).is_equal(on_live)
	# The floor taken up under the middle of the path on the clone (its graph
	# built, so relinked) and on a copy loaded after: the same new path.
	@warning_ignore("integer_division")
	var gap := path[path.size() / 2]
	var taken := copy.apply(BuildEdit.remove_floor(gap))
	assert_bool(taken.ok).override_failure_message(taken.reason_text()).is_true()
	var loaded := BuildGrid.new(_grid.size, _grid.origin)
	assert_bool(loaded.from_snapshot(copy.to_snapshot())).is_true()
	var around := copy.find_path(from, to)
	print("floor taken up at %s: %d cells on the clone" % [gap, around.size()])
	assert_array(around).is_not_equal(path)
	assert_array(around).is_equal(loaded.find_path(from, to))


func test_an_undo_on_the_site_grid_is_within_the_budget() -> void:
	var grid := _grid.clone() as SiteGrid
	# A live grid has its passenger graph built, so the undo relinks it.
	var entrance := ReferenceTerminal.ENTRANCE_CELL + SITE.starter_offset
	assert_array(grid.find_path(entrance, entrance + Vector2i(0, -3))).is_not_empty()
	assert_bool(grid.apply(BuildEdit.paint_floor(FREE_CELL, BuildGrid.FLOOR_TILE, 1)).ok).is_true()
	var receipt := BuildReceipt.new()
	grid.recorder = receipt
	assert_bool(grid.apply(BuildEdit.remove_floor(FREE_CELL)).ok).is_true()
	grid.recorder = null
	var started := Time.get_ticks_usec()
	var result := BuildUndo.commit(grid, receipt, null)
	var ms := _ms_since(started)
	print("undo on the site grid: %s in %.1f ms (target %d)" % [result.ok, ms, UNDO_TARGET_MS])
	assert_bool(result.ok).is_true()
	assert_int(grid.floor_at(FREE_CELL)).is_equal(BuildGrid.FLOOR_TILE)
	assert_float(ms).is_less(UNDO_ALLOWED_MS)
