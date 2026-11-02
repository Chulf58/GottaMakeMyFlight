class_name TerminalEnclosure
extends RefCounted
## Which cells walls close in. A flood fill starts from a ring outside the
## grid and crosses only cell edges with no wall on them that are not an
## entrance or exit door object's back edge (DoorPlacement.ways_out()): the
## door object fills that gap. Every cell the flood reaches is outside; a
## floored cell it never reaches is indoor (BuildGrid.is_indoor()). Plain,
## glass and door walls all close an edge, and objects never close or open
## one. Floor plays no part in the flood, so painting or removing floor never
## changes which cells are outside.
##
## A grid-border edge is open unless a wall or a door's back edge closes it.
##
## Pure: it reads the grid and the wall arrays it is given and changes
## nothing. BuildGrid keeps the result as derived data, never saved.


## One byte per cell at x + y * size.x: 1 where the flood from outside
## reaches, 0 where walls close the cell in. `h_walls` and `v_walls` are
## BuildGrid's wall arrays (its layout: the north edge of (x, y) at
## x + y * size.x, the west edge at x + y * (size.x + 1)).
static func outside_cells(
	grid: BuildGrid, h_walls: PackedByteArray, v_walls: PackedByteArray
) -> PackedByteArray:
	return outside_within(grid, h_walls, v_walls, Rect2i(Vector2i.ZERO, grid.size))


## outside_cells() with the flood kept to `within`, a rectangle of the grid:
## every cell outside it is outside. That holds only when `within` holds every
## cell beside a wall or a door object's back edge, with one cell to spare on
## each side that is not on the grid border (BuildGrid keeps it so with
## flood_area()). The cells along such a side then have no wall on any edge,
## so each is outside and seeds the flood; along the grid border the border
## edges decide, as in outside_cells(). The work grows with `within`, not the
## grid: a small terminal on the 86x150 site floods a few hundred cells.
static func outside_within(
	grid: BuildGrid, h_walls: PackedByteArray, v_walls: PackedByteArray, within: Rect2i
) -> PackedByteArray:
	var w := grid.size.x
	var h := grid.size.y
	var outside := PackedByteArray()
	outside.resize(w * h)
	outside.fill(1)
	within = within.intersection(Rect2i(Vector2i.ZERO, grid.size))
	if within.size.x <= 0 or within.size.y <= 0:
		return outside
	var x0 := within.position.x
	var x1 := within.end.x
	var y0 := within.position.y
	var y1 := within.end.y
	for y in range(y0, y1):
		var row := y * w
		for x in range(x0, x1):
			outside[row + x] = 0
	# A door object's back edge closes like a wall: mark it on copies.
	var h_closed := h_walls.duplicate()
	var v_closed := v_walls.duplicate()
	for way in DoorPlacement.ways_out(grid):
		var cell: Vector2i = way[0]
		match BuildGrid.SIDE_STEP.find(way[1]):
			BuildGrid.Side.NORTH:
				h_closed[cell.y * w + cell.x] = 1
			BuildGrid.Side.SOUTH:
				h_closed[(cell.y + 1) * w + cell.x] = 1
			BuildGrid.Side.WEST:
				v_closed[cell.y * (w + 1) + cell.x] = 1
			BuildGrid.Side.EAST:
				v_closed[cell.y * (w + 1) + cell.x + 1] = 1
	var queue := PackedInt32Array()
	queue.resize(within.size.x * within.size.y)
	var tail := 0
	for i in _side_seeds(h_closed, v_closed, w, h, within):
		if outside[i] == 0:
			outside[i] = 1
			queue[tail] = i
			tail += 1
	# Cells outside `within` are already 1, so the flood never leaves it.
	var head := 0
	while head < tail:
		var i := queue[head]
		head += 1
		var x := i % w
		@warning_ignore("integer_division")
		var y := i / w
		if y > 0 and outside[i - w] == 0 and h_closed[i] == 0:
			outside[i - w] = 1
			queue[tail] = i - w
			tail += 1
		if y < h - 1 and outside[i + w] == 0 and h_closed[i + w] == 0:
			outside[i + w] = 1
			queue[tail] = i + w
			tail += 1
		var west := y * (w + 1) + x
		if x > 0 and outside[i - 1] == 0 and v_closed[west] == 0:
			outside[i - 1] = 1
			queue[tail] = i - 1
			tail += 1
		if x < w - 1 and outside[i + 1] == 0 and v_closed[west + 1] == 0:
			outside[i + 1] = 1
			queue[tail] = i + 1
			tail += 1
	return outside


## The floored cells whose outside state differs between `before` and
## `after` (two outside_cells() results for a grid `width` cells wide whose
## floor array is `floors`), as indices in index order: the cells that became
## indoor or stopped being indoor. Only `within` is compared, so every cell
## outside it must be outside in both.
static func flipped_floor_indices(
	width: int,
	floors: PackedByteArray,
	before: PackedByteArray,
	after: PackedByteArray,
	within: Rect2i
) -> PackedInt32Array:
	var out := PackedInt32Array()
	if before == after:
		return out
	for y in range(within.position.y, within.end.y):
		var row := y * width
		for i in range(row + within.position.x, row + within.end.x):
			if before[i] != after[i] and floors[i] != BuildGrid.FLOOR_NONE:
				out.append(i)
	return out


## The smallest rectangle holding every floored cell and both cells beside
## every wall (one on the grid's south or east border), zero sized when there
## are none, for a grid `size` with BuildGrid's floor and wall arrays.
@warning_ignore("integer_division")
static func built_area(
	size: Vector2i, floors: PackedByteArray, h_walls: PackedByteArray, v_walls: PackedByteArray
) -> Rect2i:
	var w := size.x
	var low := Vector2i(w, size.y)
	var high := Vector2i(-1, -1)
	for i in floors.size():
		if floors[i] != BuildGrid.FLOOR_NONE:
			low = low.min(Vector2i(i % w, i / w))
			high = high.max(Vector2i(i % w, i / w))
	for i in h_walls.size():
		if h_walls[i] != BuildGrid.WallKind.NONE:
			var y := i / w
			low = low.min(Vector2i(i % w, maxi(y - 1, 0)))
			high = high.max(Vector2i(i % w, mini(y, size.y - 1)))
	for i in v_walls.size():
		if v_walls[i] != BuildGrid.WallKind.NONE:
			var x := i % (w + 1)
			low = low.min(Vector2i(maxi(x - 1, 0), i / (w + 1)))
			high = high.max(Vector2i(mini(x, w - 1), i / (w + 1)))
	if high.x < 0:
		return Rect2i()
	return Rect2i(low, high - low + Vector2i.ONE)


## The cells (as indices) the flood starts from on the sides of `within`, some
## more than once: along a side on the grid border, each cell whose border
## edge is open; along any other side, every cell.
static func _side_seeds(
	h_closed: PackedByteArray, v_closed: PackedByteArray, w: int, h: int, within: Rect2i
) -> PackedInt32Array:
	var seeds := PackedInt32Array()
	var top := within.position.y
	var bottom := within.end.y - 1
	var left := within.position.x
	var right := within.end.x - 1
	for x in range(left, within.end.x):
		if top > 0 or h_closed[x] == 0:
			seeds.append(top * w + x)
		if bottom < h - 1 or h_closed[h * w + x] == 0:
			seeds.append(bottom * w + x)
	for y in range(top, within.end.y):
		if left > 0 or v_closed[y * (w + 1)] == 0:
			seeds.append(y * w + left)
		if right < w - 1 or v_closed[y * (w + 1) + w] == 0:
			seeds.append(y * w + right)
	return seeds
