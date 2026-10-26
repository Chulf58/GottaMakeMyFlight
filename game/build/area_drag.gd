class_name AreaDrag
extends RefCounted
## The rectangle drag of the Floor and Remove tools. A drag starts on a cell,
## follows the pointer's cell (inclusive, in any direction, kept inside the
## grid) and is applied once on release by fill_floor() or clear(). BuildMode
## owns the input and the ghost; this class owns the rectangle and what
## applying it does, so the click and the drag use the same edits and rules.
##
## Each rectangle is one BuildGrid.apply_batch(): every cell is validated and
## applied in order, and the A* graph is relinked and graph_changed emitted once
## at the end. The cost is measured in test_area_drag.gd.


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

	func _count(results: Array[BuildResult]) -> void:
		for result in results:
			if result.ok:
				placed += 1
			else:
				_refuse(result)

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


## Fills every cell of `area` with floor. Cells that already have floor, of any
## zone, count as unchanged; a cell the rules refuse (DoorPlacement.check()) is skipped.
static func fill_floor(grid: BuildGrid, area: Rect2i, zone: int) -> Outcome:
	var outcome := Outcome.new()
	# Painting floor never changes what DoorPlacement.check() reads, so
	# checking every cell before the batch gives the same answers as checking
	# between the edits.
	var edits: Array[BuildEdit] = []
	for cell in _cells(area):
		if grid.floor_at(cell) != BuildGrid.FLOOR_NONE:
			outcome.unchanged += 1
			continue
		var edit := BuildEdit.paint_floor(cell, BuildGrid.FLOOR_TILE, zone)
		var result := DoorPlacement.check(grid, edit)
		if result.ok:
			edits.append(edit)
		else:
			outcome._refuse(result)
			# Never handed to apply_batch(), which logs the refusals it makes itself.
			grid.edit_refused.emit(edit, result)
	outcome._count(grid.apply_batch(edits))
	return outcome


## Removes, in each cell of `area`, what one Remove click on the middle of the
## cell removes: the object standing there (the whole object, even where it
## reaches past the rectangle), otherwise the room the cell is in (the whole
## room), otherwise the floor. Walls are never touched, because a click only
## takes a wall near a cell's edge. Objects go first, so the floor in front of
## a removed desk is free to go. A cell with no floor and no object counts as
## unchanged; the floor under an object or a room stays, as it does for a
## click, so a second drag takes the floor of a removed room.
static func clear(grid: BuildGrid, area: Rect2i) -> Outcome:
	var outcome := Outcome.new()
	outcome.removing = true
	var cells := _cells(area)
	# Read every cell before the first edit: removing an object clears its
	# occupancy, which must not turn its other cells into plain floor.
	var held := {}
	var objects: Array[int] = []
	var rooms: Array[int] = []
	for cell in cells:
		var object_id := grid.object_at(cell)
		var room_id := grid.room_at(cell)
		if object_id == 0 and room_id == 0:
			continue
		held[cell] = true
		if object_id != 0 and not objects.has(object_id):
			objects.append(object_id)
		elif object_id == 0 and not rooms.has(room_id):
			rooms.append(room_id)
	# DoorPlacement.check() adds nothing to a removal, so the batch's own
	# in-order validation is the whole rule: a floor cell in front of a removed
	# desk is judged after the desk is gone.
	var edits: Array[BuildEdit] = []
	for object_id in objects:
		edits.append(BuildEdit.remove_object(object_id))
	for room_id in rooms:
		edits.append(BuildEdit.remove_room(room_id))
	for cell in cells:
		if held.has(cell):
			continue
		if grid.in_bounds(cell) and grid.floor_at(cell) == BuildGrid.FLOOR_NONE:
			outcome.unchanged += 1
			continue
		edits.append(BuildEdit.remove_floor(cell))
	outcome._count(grid.apply_batch(edits))
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
