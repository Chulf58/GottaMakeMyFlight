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
## With `border_closed` every grid-border edge counts as walled: the Toon
## shell's facade stands there (BuildGrid.shell_border). Without it a border
## edge is open unless a wall or a door's back edge closes it.
##
## Pure: it reads the grid and the wall arrays it is given and changes
## nothing. BuildGrid keeps the result as derived data, never saved.


## One byte per cell at x + y * size.x: 1 where the flood from outside
## reaches, 0 where walls close the cell in. `h_walls` and `v_walls` are
## BuildGrid's wall arrays (its layout: the north edge of (x, y) at
## x + y * size.x, the west edge at x + y * (size.x + 1)).
static func outside_cells(
	grid: BuildGrid, h_walls: PackedByteArray, v_walls: PackedByteArray, border_closed: bool
) -> PackedByteArray:
	var w := grid.size.x
	var h := grid.size.y
	var outside := PackedByteArray()
	outside.resize(w * h)
	outside.fill(0)
	if border_closed or w == 0 or h == 0:
		return outside
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
	queue.resize(w * h)
	var tail := 0
	for i in _border_seeds(h_closed, v_closed, w, h):
		if outside[i] == 0:
			outside[i] = 1
			queue[tail] = i
			tail += 1
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
## floor array is `floors`), in index order: the cells that became indoor or
## stopped being indoor.
static func flipped_floor_cells(
	width: int, floors: PackedByteArray, before: PackedByteArray, after: PackedByteArray
) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if before == after:
		return cells
	for i in after.size():
		if before[i] != after[i] and floors[i] != BuildGrid.FLOOR_NONE:
			@warning_ignore("integer_division")
			cells.append(Vector2i(i % width, i / width))
	return cells


## The cells (as indices) whose grid-border edge is open, some more than once.
static func _border_seeds(
	h_closed: PackedByteArray, v_closed: PackedByteArray, w: int, h: int
) -> PackedInt32Array:
	var seeds := PackedInt32Array()
	for x in w:
		if h_closed[x] == 0:
			seeds.append(x)
		if h_closed[h * w + x] == 0:
			seeds.append((h - 1) * w + x)
	for y in h:
		if v_closed[y * (w + 1)] == 0:
			seeds.append(y * w)
		if v_closed[y * (w + 1) + w] == 0:
			seeds.append(y * w + w - 1)
	return seeds
