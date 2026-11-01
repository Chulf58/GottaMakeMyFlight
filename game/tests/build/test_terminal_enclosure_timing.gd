class_name TestTerminalEnclosureTiming
extends GdUnitTestSuite
## Prints how long working out the indoor cells takes (TerminalEnclosure) on
## the Toon shell's 66x30 grid and on the largest grid, 256x256, and how long
## a wall edit that floods or closes every cell takes with its relink. Floor
## covers each grid inside a ring of walls one cell in from the border, with
## interior walls every 8 cells (each with a one-cell gap). The numbers are
## printed for the record; the asserts only prove each run did its work.

const ROOM := 8


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
func _flood_usec(grid: BuildGrid, border_closed: bool) -> int:
	var h: PackedByteArray = grid.get("_h_walls")
	var v: PackedByteArray = grid.get("_v_walls")
	var runs: Array[int] = []
	for i in 5:
		var started := Time.get_ticks_usec()
		TerminalEnclosure.outside_cells(grid, h, v, border_closed)
		runs.append(Time.get_ticks_usec() - started)
	runs.sort()
	return runs[2]


func _measure(size: Vector2i) -> void:
	var grid := _site(size)
	var indoor := _indoor(grid)
	var gap := Vector2i(1, size.y / 2)
	var started := Time.get_ticks_usec()
	grid.apply(BuildEdit.remove_wall(gap, BuildGrid.Side.WEST))
	var open_usec := Time.get_ticks_usec() - started
	var opened := _indoor(grid)
	# With the gap open the flood fills the whole grid: the slowest case.
	var open_flood_usec := _flood_usec(grid, false)
	started = Time.get_ticks_usec()
	grid.apply(BuildEdit.place_wall(gap, BuildGrid.Side.WEST))
	var close_usec := Time.get_ticks_usec() - started
	print(
		(
			(
				"enclosure %dx%d: flood %d usec open, %d usec closed (shell border %d usec),"
				+ " indoor %d -> %d -> %d; opening edit with relink %d usec, closing edit %d usec"
			)
			% [
				size.x,
				size.y,
				open_flood_usec,
				_flood_usec(grid, false),
				_flood_usec(grid, true),
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


func test_time_the_shell_sized_grid() -> void:
	_measure(Vector2i(66, 30))


func test_time_the_largest_grid() -> void:
	_measure(Vector2i(BuildGrid.MAX_SIDE_CELLS, BuildGrid.MAX_SIDE_CELLS))
