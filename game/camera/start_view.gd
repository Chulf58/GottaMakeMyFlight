class_name StartView
extends RefCounted
## The ground area the start camera frames: the cells the player has built
## (a floor, or a wall on one of a cell's edges, which counts for both cells
## it touches; an object needs a floor, so it adds no cell of its own), or,
## with nothing built, the starter terminal's floor when it fits the grid.
## TycoonCamera.frame_start_view turns the area into a view.


## The area in world x and z (a Rect2's y is z), or the whole grid when
## nothing is built and no starter terminal fits it.
static func area_for(grid: BuildGrid, shell: ShellDefinition = null) -> Rect2:
	var cells := _built_cells(grid)
	var whole := Rect2i(Vector2i.ZERO, grid.size)
	if cells.size == Vector2i.ZERO:
		cells = _starter_cells(shell)
	if cells.size == Vector2i.ZERO or not whole.encloses(cells):
		cells = whole
	var north_west := grid.origin + Vector3(cells.position.x, 0.0, cells.position.y)
	return Rect2(Vector2(north_west.x, north_west.z), Vector2(cells.size))


static func _built_cells(grid: BuildGrid) -> Rect2i:
	var found := false
	var low := Vector2i.ZERO
	var high := Vector2i.ZERO
	for y in grid.size.y:
		for x in grid.size.x:
			var cell := Vector2i(x, y)
			if not _is_built(grid, cell):
				continue
			low = cell if not found else low.min(cell)
			high = cell if not found else high.max(cell)
			found = true
	return Rect2i(low, high - low + Vector2i.ONE) if found else Rect2i()


static func _is_built(grid: BuildGrid, cell: Vector2i) -> bool:
	if grid.floor_at(cell) != BuildGrid.FLOOR_NONE:
		return true
	for side in BuildGrid.SIDE_STEP.size():
		if grid.has_wall(cell, side):
			return true
	return false


static func _starter_cells(shell: ShellDefinition) -> Rect2i:
	var found := false
	var low := Vector2i.ZERO
	var high := Vector2i.ZERO
	for edit in ReferenceTerminal.edits(shell):
		if edit.kind != BuildEdit.Kind.PAINT_FLOOR:
			continue
		low = edit.cell if not found else low.min(edit.cell)
		high = edit.cell if not found else high.max(edit.cell)
		found = true
	return Rect2i(low, high - low + Vector2i.ONE) if found else Rect2i()
