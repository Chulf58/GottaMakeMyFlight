class_name TestTerminalEnclosureTiming
extends GdUnitTestSuite
## Prints how long working out the indoor cells takes (TerminalEnclosure) on
## the airport site's 86x40 grid and on the largest grid, 256x256, and how long
## a wall edit that floods or closes every cell takes with its relink. Floor
## covers each grid inside a ring of walls one cell in from the border, with
## interior walls every 8 cells (each with a one-cell gap). The numbers are
## printed for the record. The 86x40 opening edit has a budget that fails;
## the other asserts prove each run did its work. The whole airport site, with
## its passenger and staff graphs built as in a game, has the same budget for
## the edit that opens its floor and the one that closes it (L4, board
## ee9914e6).

const SITE := preload("res://build/terminal_site.tres")
const ROOM := 8
## Runs per timed edit on the full site; the median is judged.
const SITE_RUNS := 5
## The most a wall edit that floods the whole 86x40 floor may take, in usec:
## under one 60 fps frame. Measured about 3.6 ms on the old 66x30 grid on
## 2026-11-01.
const SITE_EDIT_BUDGET_USEC := 15000


## A grid of `size` floored inside a walled ring one cell in from the border,
## with room walls every ROOM cells, each wall run left with a gap.
func _site(size: Vector2i) -> BuildGrid:
	var grid := BuildGrid.new(size)
	var edits: Array[BuildEdit] = []
	for y in range(1, size.y - 1):
		for x in range(1, size.x - 1):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
			if x % ROOM == 0 and y % ROOM != 4:
				edits.append(BuildEdit.place_wall(Vector2i(x, y), BuildGrid.Side.WEST))
			if y % ROOM == 0 and x % ROOM != 4:
				edits.append(BuildEdit.place_wall(Vector2i(x, y), BuildGrid.Side.NORTH))
	grid.apply_batch(edits)
	EnclosureKit.close_floor(grid)
	return grid


func _indoor(grid: BuildGrid) -> int:
	var count := 0
	for y in grid.size.y:
		for x in grid.size.x:
			if grid.is_indoor(Vector2i(x, y)):
				count += 1
	return count


## The median of five runs of TerminalEnclosure.outside_cells(), in usec.
func _flood_usec(grid: BuildGrid) -> int:
	var h: PackedByteArray = grid.get("_h_walls")
	var v: PackedByteArray = grid.get("_v_walls")
	var runs: Array[int] = []
	for i in 5:
		var started := Time.get_ticks_usec()
		TerminalEnclosure.outside_cells(grid, h, v)
		runs.append(Time.get_ticks_usec() - started)
	runs.sort()
	return runs[2]


## Builds the site, opens and closes its outer wall, prints the timings and
## returns how long the opening edit took, in usec.
func _measure(size: Vector2i) -> int:
	var grid := _site(size)
	var indoor := _indoor(grid)
	var gap := Vector2i(1, size.y / 2)
	var started := Time.get_ticks_usec()
	grid.apply(BuildEdit.remove_wall(gap, BuildGrid.Side.WEST))
	var open_usec := Time.get_ticks_usec() - started
	var opened := _indoor(grid)
	# With the gap open the flood fills the whole grid: the slowest case.
	var open_flood_usec := _flood_usec(grid)
	started = Time.get_ticks_usec()
	grid.apply(BuildEdit.place_wall(gap, BuildGrid.Side.WEST))
	var close_usec := Time.get_ticks_usec() - started
	print(
		(
			(
				"enclosure %dx%d: flood %d usec open, %d usec closed,"
				+ " indoor %d -> %d -> %d; opening edit with relink %d usec, closing edit %d usec"
			)
			% [
				size.x,
				size.y,
				open_flood_usec,
				_flood_usec(grid),
				indoor,
				opened,
				_indoor(grid),
				open_usec,
				close_usec
			]
		)
	)
	assert_int(indoor).is_equal((size.x - 2) * (size.y - 2))
	assert_int(opened).is_equal(0)
	assert_int(_indoor(grid)).is_equal(indoor)
	return open_usec


## The site-sized grid has a budget: one wall edit that lets the outside into
## the whole floor, relink included, stays under SITE_EDIT_BUDGET_USEC.
func test_time_the_site_sized_grid() -> void:
	assert_int(_measure(Vector2i(86, 40))).is_less(SITE_EDIT_BUDGET_USEC)


## The largest grid is a printed measurement only (about 130 ms for the
## opening edit on 2026-11-01, about 33 ms with both graphs built after the
## land-plots change). No site grid is that large: the budget is held on the
## full airport site (test_time_the_full_site_with_its_graphs_built()).
func test_time_the_largest_grid() -> void:
	assert_int(_measure(Vector2i(BuildGrid.MAX_SIDE_CELLS, BuildGrid.MAX_SIDE_CELLS))).is_greater(0)


## The full site (SiteDefinition.grid_size, 86x150) floored and walled like the
## others, its passenger and staff A* graphs built: the wall edit that lets the
## outside into the whole floor, and the one that closes it again, each stay
## under SITE_EDIT_BUDGET_USEC, median of SITE_RUNS. Measured 2026-11-01 on
## the same machine: about 13.3 ms opening and 10.1 ms closing before the
## flood was kept to the built area and the points switched by index, about
## 6.7 ms and 3.3 ms after.
func test_time_the_full_site_with_its_graphs_built() -> void:
	var size: Vector2i = SITE.grid_size
	var grid := _site(size)
	var indoor := _indoor(grid)
	assert_int(indoor).is_equal((size.x - 2) * (size.y - 2))
	# Both graphs exist from here on, so every edit relinks them as in a game.
	assert_array(grid.find_path(Vector2i(2, 2), Vector2i(3, 3))).is_not_empty()
	assert_array(grid.find_staff_path(Vector2i(2, 2), Vector2i(3, 3))).is_not_empty()
	var gap := Vector2i(1, size.y / 2)
	var opens: Array[int] = []
	var closes: Array[int] = []
	for i in SITE_RUNS:
		var started := Time.get_ticks_usec()
		assert_bool(grid.apply(BuildEdit.remove_wall(gap, BuildGrid.Side.WEST)).ok).is_true()
		opens.append(Time.get_ticks_usec() - started)
		assert_int(_indoor(grid)).is_equal(0)
		assert_array(grid.find_path(Vector2i(2, 2), Vector2i(3, 3))).is_empty()
		started = Time.get_ticks_usec()
		assert_bool(grid.apply(BuildEdit.place_wall(gap, BuildGrid.Side.WEST)).ok).is_true()
		closes.append(Time.get_ticks_usec() - started)
		assert_int(_indoor(grid)).is_equal(indoor)
	opens.sort()
	closes.sort()
	var open_usec := opens[SITE_RUNS / 2]
	var close_usec := closes[SITE_RUNS / 2]
	print(
		(
			(
				"full site %dx%d, graphs built: opening edit %.2f ms, closing edit %.2f ms"
				+ " (median of %d; runs %s / %s usec)"
			)
			% [size.x, size.y, open_usec / 1000.0, close_usec / 1000.0, SITE_RUNS, opens, closes]
		)
	)
	assert_int(open_usec).is_less(SITE_EDIT_BUDGET_USEC)
	assert_int(close_usec).is_less(SITE_EDIT_BUDGET_USEC)
