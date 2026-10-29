class_name ScreenCoverage
extends RefCounted
## Where screen stands can be watched from (decisions boredom-screens-are-
## floor-standing-screen-stands-placed-like and boredom-and-shops-design-
## boredom-need-while-waiting-kiosk-sh, point 3). A screen stand stands on one
## floor cell and faces like a seat row; it covers a fan of cells in front of
## it: RANGE rows deep, the first row three cells wide and every later row
## 2 * MAX_HALF_WIDTH + 1 wide. A cell in the fan is covered when it has floor
## and the screen can be seen from it.
##
## Seeing is its own rule, not walking (BuildGrid.can_step): the straight line
## from the screen's cell centre to the cell's centre is followed cell by cell,
## and a plain wall on any edge it crosses blocks it. Glass and door walls let
## the picture through, and no object blocks it. A line through a cell corner
## is blocked only when both ways round the corner are. Placed screens just
## work: there is no power. A passenger in two fans is covered once
## (BoredomSim relief does not stack).
##
## Each screen is charged SCREEN_UPKEEP a day by Settlement, inside a room or
## not (decision shops-and-food-stalls-earn-per-visit-toilets-and-screens-cos).
## The covered cells are derived from the grid, so nothing is saved.

const SCREEN_ID := &"screen_stand"
## How many rows in front of the screen it covers.
const RANGE := 5
## How far the fan reaches to each side of the screen's axis, from the second
## row on.
const MAX_HALF_WIDTH := 2

var _grid: BuildGrid
var _covered: Dictionary = {}
var _dirty := true


## The fan in front of a screen at `anchor` and `facing`, before floor and
## sight are checked, nearest row first.
static func area(anchor: Vector2i, facing: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for row in range(1, RANGE + 1):
		var half := mini(row, MAX_HALF_WIDTH)
		for side in range(-half, half + 1):
			out.append(anchor + BuildObjectDef.rotate_offset(Vector2i(side, row), facing))
	return out


## The cells a screen at `anchor` and `facing` covers on `grid`: the fan cells
## with floor that it can be seen from.
static func covered_cells(grid: BuildGrid, anchor: Vector2i, facing: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell in area(anchor, facing):
		if grid.in_bounds(cell) and grid.floor_at(cell) != BuildGrid.FLOOR_NONE:
			if sight_clear(grid, anchor, cell):
				out.append(cell)
	return out


## Whether a wall of `kind` (a BuildGrid.WallKind) blocks sight: only a plain
## one does.
static func blocks_sight(kind: int) -> bool:
	return kind == BuildGrid.WallKind.PLAIN


## Whether nothing blocks the straight line between the centres of `from` and
## `to` (see the class notes).
static func sight_clear(grid: BuildGrid, from: Vector2i, to: Vector2i) -> bool:
	var delta := to - from
	var step := Vector2i(signi(delta.x), signi(delta.y))
	var count := delta.abs()
	var done := Vector2i.ZERO
	var at := from
	while done.x < count.x or done.y < count.y:
		var lead := (1 + 2 * done.x) * count.y - (1 + 2 * done.y) * count.x
		if lead == 0:
			var across := Vector2i(step.x, 0)
			var down := Vector2i(0, step.y)
			var by_x := _edge_open(grid, at, across) and _edge_open(grid, at + across, down)
			var by_y := _edge_open(grid, at, down) and _edge_open(grid, at + down, across)
			if not by_x and not by_y:
				return false
			at += step
			done += Vector2i.ONE
		elif lead < 0:
			if not _edge_open(grid, at, Vector2i(step.x, 0)):
				return false
			at.x += step.x
			done.x += 1
		else:
			if not _edge_open(grid, at, Vector2i(0, step.y)):
				return false
			at.y += step.y
			done.y += 1
	return true


## The ids of every screen stand on `grid`, ascending.
static func screen_ids(grid: BuildGrid) -> Array[int]:
	var out: Array[int] = []
	for id in grid.object_ids():
		if grid.get_object(id)["def"] == SCREEN_ID:
			out.append(id)
	return out


## What `grid`'s screens cost to run for one game day.
static func daily_upkeep(grid: BuildGrid) -> int:
	return screen_ids(grid).size() * PriceTable.SCREEN_UPKEEP


static func _edge_open(grid: BuildGrid, cell: Vector2i, step: Vector2i) -> bool:
	return not blocks_sight(grid.wall_kind(cell, BuildGrid.SIDE_STEP.find(step)))


## Follows `grid`: the covered cells are worked out again after any edit.
func bind(grid: BuildGrid) -> void:
	_grid = grid
	_dirty = true
	grid.graph_changed.connect(func(_cells: Array[Vector2i]) -> void: _dirty = true)


## Whether any screen covers `cell`; none without a grid.
func covers(cell: Vector2i) -> bool:
	return cells().has(cell)


## Every covered cell, as cell -> true.
func cells() -> Dictionary:
	if _grid == null:
		return {}
	if _dirty:
		_covered.clear()
		for id in screen_ids(_grid):
			var record := _grid.get_object(id)
			for cell in covered_cells(_grid, record["anchor"], record["facing"]):
				_covered[cell] = true
		_dirty = false
	return _covered
