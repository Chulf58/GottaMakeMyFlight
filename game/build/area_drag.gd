class_name AreaDrag
extends RefCounted
## The rectangle drag of the Floor and Remove tools. A drag starts on a cell,
## follows the pointer's cell (inclusive, in any direction, kept inside the
## grid) and is applied once on release by fill_floor() or clear(). BuildMode
## owns the input and the ghost; this class owns the rectangle and what
## applying it does, so the click and the drag use the same edits and rules.
##
## BuildGrid has no batch edit: every cell is one grid.apply(), which relinks
## the A* graph around that cell and emits graph_changed. The cost is measured
## in test_area_drag.gd.


## What applying a rectangle did, for the status line.
class Outcome:
	extends RefCounted
	## Cells painted, or objects and floor cells removed.
	var placed := 0
	## Cells the rules refused.
	var skipped := 0
	## Cells already as the tool leaves them (floored for Floor, empty for Remove).
	var unchanged := 0
	## The reason text of the first refusal, in row order.
	var first_reason := ""
	var removing := false

	func message() -> String:
		var verb := "Removed" if removing else "Placed"
		if placed == 0 and skipped == 0:
			return "Nothing to remove" if removing else "Nothing to place"
		var text := "%s %d" % [verb, placed]
		if skipped > 0:
			text += ", skipped %d: %s" % [skipped, first_reason]
		return text

	func _refuse(result: BuildResult) -> void:
		skipped += 1
		if first_reason == "":
			first_reason = result.reason_text()


var active := false
## Where the press landed, so a drag that never leaves its cell can be applied
## as the single click it is.
var press_point := Vector3.ZERO

var _start := Vector2i.ZERO
var _end := Vector2i.ZERO
var _limit := Vector2i.ZERO


## Fills every cell of `area` with floor. Cells that already have it count as
## unchanged; a cell the rules refuse (DoorPlacement.check()) is skipped.
static func fill_floor(grid: BuildGrid, area: Rect2i, zone: int) -> Outcome:
	var outcome := Outcome.new()
	for cell in _cells(area):
		if grid.floor_at(cell) == BuildGrid.FLOOR_TILE and grid.zone_at(cell) == zone:
			outcome.unchanged += 1
			continue
		var edit := BuildEdit.paint_floor(cell, BuildGrid.FLOOR_TILE, zone)
		var result := DoorPlacement.check(grid, edit)
		if result.ok:
			grid.apply(edit)
			outcome.placed += 1
		else:
			outcome._refuse(result)
	return outcome


## Removes, in each cell of `area`, what one Remove click on the middle of the
## cell removes: the object standing there (the whole object, even where it
## reaches past the rectangle), otherwise the floor. Walls are never touched,
## because a click only takes a wall near a cell's edge. Objects go first, so
## the floor in front of a removed desk is free to go. A cell with no floor
## and no object counts as unchanged; the floor under an object stays, as it
## does for a click.
static func clear(grid: BuildGrid, area: Rect2i) -> Outcome:
	var outcome := Outcome.new()
	outcome.removing = true
	var cells := _cells(area)
	var held := {}
	for cell in cells:
		var object_id := grid.object_at(cell)
		if object_id == 0:
			continue
		held[cell] = true
		var edit := BuildEdit.remove_object(object_id)
		var result := DoorPlacement.check(grid, edit)
		if result.ok:
			grid.apply(edit)
			outcome.placed += 1
		else:
			outcome._refuse(result)
	for cell in cells:
		if held.has(cell):
			continue
		if grid.in_bounds(cell) and grid.floor_at(cell) == BuildGrid.FLOOR_NONE:
			outcome.unchanged += 1
			continue
		var edit := BuildEdit.remove_floor(cell)
		var result := DoorPlacement.check(grid, edit)
		if result.ok:
			grid.apply(edit)
			outcome.placed += 1
		else:
			outcome._refuse(result)
	return outcome


static func _cells(area: Rect2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			cells.append(Vector2i(x, y))
	return cells


## Starts a drag on `cell`. `grid_size` bounds the rectangle.
func begin(cell: Vector2i, point: Vector3, grid_size: Vector2i) -> void:
	active = true
	press_point = point
	_limit = grid_size
	_start = cell
	_end = cell


## Moves the far corner to `cell`, kept inside the grid. True when the
## rectangle changed.
func move(cell: Vector2i) -> bool:
	var clamped := cell.clamp(Vector2i.ZERO, _limit - Vector2i.ONE)
	if clamped == _end:
		return false
	_end = clamped
	return true


func cancel() -> void:
	active = false


## The cells from the start cell to the current cell, both included.
func rect() -> Rect2i:
	var low := _start.min(_end)
	return Rect2i(low, _start.max(_end) - low + Vector2i.ONE)


## The cell the pointer is on, the rectangle's far corner.
func end_cell() -> Vector2i:
	return _end


func is_single_cell() -> bool:
	return _start == _end


## The rectangle's size in cells, as "12 x 8".
func size_label() -> String:
	var size := rect().size
	return "%d x %d" % [size.x, size.y]
