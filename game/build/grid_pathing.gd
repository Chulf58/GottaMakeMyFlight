class_name GridPathing
extends RefCounted
## The passenger A* graph over a BuildGrid. One AStar2D point per cell, at
## the cell's grid coordinates, so diagonal links cost sqrt(2). A link exists
## exactly when BuildGrid.can_route() allows the step, so a door wall links
## like an open edge and a plain or glass wall does not; an AStarGrid2D cannot
## hold that, because walls sit on cell edges and a door blocks its sides.
## Security scanners are never linked: only the passenger a scanner serves
## walks through it, along BuildGrid.passage_cells(), so generic routing can
## never cross security. After an edit only the links around the dirty cells
## are rebuilt.

const NEIGHBOURS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
	Vector2i(1, 1),
	Vector2i(1, -1),
	Vector2i(-1, 1),
	Vector2i(-1, -1),
]

var _astar := AStar2D.new()
var _width := 0


func rebuild(grid: BuildGrid) -> void:
	_astar.clear()
	_width = grid.size.x
	_astar.reserve_space(grid.size.x * grid.size.y)
	for y in grid.size.y:
		for x in grid.size.x:
			_astar.add_point(_id(Vector2i(x, y)), Vector2(x, y))
	for y in grid.size.y:
		for x in grid.size.x:
			_relink(grid, Vector2i(x, y))


## Every in-bounds cell within one step of a dirty cell, each once. A
## diagonal link depends on the 2x2 block it crosses, and every such block
## touching a dirty cell lies inside that cell's 3x3 neighbourhood. These are
## the cells update() relinks, and so the cells whose links may have changed.
static func neighbourhood(grid: BuildGrid, dirty_cells: Array[Vector2i]) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var seen := {}
	for cell in dirty_cells:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var near := cell + Vector2i(dx, dy)
				if grid.in_bounds(near) and not seen.has(near):
					seen[near] = true
					cells.append(near)
	return cells


## Relinks the neighbourhood of the dirty cells and returns it.
func update(grid: BuildGrid, dirty_cells: Array[Vector2i]) -> Array[Vector2i]:
	var cells := neighbourhood(grid, dirty_cells)
	for cell in cells:
		_relink(grid, cell)
	return cells


## Cells from `from` to `to`, both included, or an empty array when either
## cell is not walkable or no route exists.
func find_path(grid: BuildGrid, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if not grid.is_walkable(from) or not grid.is_walkable(to):
		return cells
	for id in _astar.get_id_path(_id(from), _id(to)):
		@warning_ignore("integer_division")
		cells.append(Vector2i(id % _width, id / _width))
	return cells


func _relink(grid: BuildGrid, cell: Vector2i) -> void:
	var id := _id(cell)
	for offset in NEIGHBOURS:
		var other := cell + offset
		if not grid.in_bounds(other):
			continue
		var other_id := _id(other)
		var linked := _astar.are_points_connected(id, other_id)
		var open := grid.can_route(cell, other)
		if open and not linked:
			_astar.connect_points(id, other_id)
		elif linked and not open:
			_astar.disconnect_points(id, other_id)


func _id(cell: Vector2i) -> int:
	return cell.y * _width + cell.x
