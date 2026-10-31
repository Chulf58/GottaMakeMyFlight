class_name RoomResize
extends RefCounted
## Resizing a built room by dragging one of its edges (decision
## resize-rooms-first-drag-a-room-s-edge-to-grow-or-shrink-it-f). With a room
## tool picked, a press in the outer band of a room of that tool's type grabs
## the nearest edge; the pointer then moves that edge to the nearest grid line,
## and the release gives the room its new rectangle in one RESIZE_ROOM edit.
## The room keeps its type and id, furniture stays where it is (a piece left
## outside makes the room not ready through RoomRules), and the edit is one
## undo step with the old rectangle as its inverse (BuildReceipt).
##
## Refused whole, with a status reason, when the grown strip has no floor, runs
## into another room (the grid's rules) or the edge would cross a wall
## (BuildResult.Reason.ROOM_WALL). BuildMode owns the input and the ghost.

## How far in from a room's outer edge a press still grabs that edge, in metres.
const EDGE_BAND := 0.3

var active := false
var room_id := 0
## The BuildGrid.Side of the edge being dragged.
var side := BuildGrid.Side.NORTH
## The cell under the pointer when it last moved, for the status note.
var pointer_cell := Vector2i.ZERO
## What the last finish() said, for the status line.
var note := ""

var _type: StringName = &""
var _original := Rect2i()
var _target := Rect2i()


## Whether the grid would accept room `id` taking `area`: the grid's rules,
## then that no wall lies on a grid line the moving edge crosses.
static func check(grid: BuildGrid, id: int, area: Rect2i) -> BuildResult:
	var result := grid.validate(BuildEdit.resize_room(id, area))
	if result.ok and wall_crossed(grid, grid.get_room(id)["rect"], area):
		return BuildResult.refused(BuildResult.Reason.ROOM_WALL)
	return result


## Whether growing `old` into `area` moves an edge across a wall: a wall on any
## grid line from the old edge out to, but not including, the new edge, along
## the room's span. The new edge itself may stand on a wall, which then bounds
## the room. Shrinking crosses nothing.
static func wall_crossed(grid: BuildGrid, old: Rect2i, area: Rect2i) -> bool:
	for x in range(area.position.x + 1, old.position.x + 1):
		if _column_line_walled(grid, x, old):
			return true
	for x in range(old.end.x, area.end.x):
		if _column_line_walled(grid, x, old):
			return true
	for y in range(area.position.y + 1, old.position.y + 1):
		if _row_line_walled(grid, y, old):
			return true
	for y in range(old.end.y, area.end.y):
		if _row_line_walled(grid, y, old):
			return true
	return false


## The room edge a press at `point` grabs: Side of the nearest edge of `rect`
## when the point is within EDGE_BAND of it, else -1.
static func edge_side(grid: BuildGrid, rect: Rect2i, point: Vector3) -> int:
	var local := Vector2(point.x - grid.origin.x, point.z - grid.origin.z)
	var distances := {
		BuildGrid.Side.NORTH: local.y - rect.position.y,
		BuildGrid.Side.EAST: rect.end.x - local.x,
		BuildGrid.Side.SOUTH: rect.end.y - local.y,
		BuildGrid.Side.WEST: local.x - rect.position.x,
	}
	var best := -1
	var best_distance := EDGE_BAND
	for edge in distances:
		if distances[edge] >= 0.0 and distances[edge] <= best_distance:
			best = edge
			best_distance = distances[edge]
	return best


static func _column_line_walled(grid: BuildGrid, line: int, rows: Rect2i) -> bool:
	for y in range(rows.position.y, rows.end.y):
		if grid.has_wall(Vector2i(line - 1, y), BuildGrid.Side.EAST):
			return true
	return false


static func _row_line_walled(grid: BuildGrid, line: int, columns: Rect2i) -> bool:
	for x in range(columns.position.x, columns.end.x):
		if grid.has_wall(Vector2i(x, line - 1), BuildGrid.Side.SOUTH):
			return true
	return false


## Grabs an edge of the room of `type` under `point`. False, and nothing
## started, when the point is on no such room or not in the band of its edge.
func begin(grid: BuildGrid, point: Vector3, type: StringName) -> bool:
	var cell := grid.world_to_cell(point)
	var id := grid.room_at(cell)
	if id == 0 or grid.get_room(id)["type"] != type:
		return false
	var rect: Rect2i = grid.get_room(id)["rect"]
	var grabbed := edge_side(grid, rect, point)
	if grabbed < 0:
		return false
	active = true
	room_id = id
	side = grabbed as BuildGrid.Side
	pointer_cell = cell
	note = ""
	_type = type
	_original = rect
	_target = rect
	return true


## Moves the grabbed edge to the grid line nearest `point`, kept inside the
## grid and leaving the room at least one cell. True when the rectangle changed.
func move(grid: BuildGrid, point: Vector3) -> bool:
	pointer_cell = grid.world_to_cell(point)
	var local := Vector2(point.x - grid.origin.x, point.z - grid.origin.z)
	var low := _original.position
	var high := _original.end
	match side:
		BuildGrid.Side.WEST:
			low.x = clampi(roundi(local.x), 0, high.x - 1)
		BuildGrid.Side.EAST:
			high.x = clampi(roundi(local.x), low.x + 1, grid.size.x)
		BuildGrid.Side.NORTH:
			low.y = clampi(roundi(local.y), 0, high.y - 1)
		BuildGrid.Side.SOUTH:
			high.y = clampi(roundi(local.y), low.y + 1, grid.size.y)
	var moved := Rect2i(low, high - low)
	if moved == _target:
		return false
	_target = moved
	return true


func cancel() -> void:
	active = false


## The room's rectangle as the drag stands now.
func rect() -> Rect2i:
	return _target


## The room's rectangle when the edge was grabbed.
func original() -> Rect2i:
	return _original


## The status line while dragging: "Cafe 6 x 3", followed by the reason the
## grid would refuse it.
func label(grid: BuildGrid) -> String:
	var text := (
		"%s %d x %d" % [RoomTypes.get_type(_type).display_name, _target.size.x, _target.size.y]
	)
	var result := check(grid, room_id, _target)
	if not result.ok:
		text += "  " + result.reason_text()
	return text


## Ends the drag and gives the room its new rectangle through
## BuildTransaction (a resize costs nothing, so `wallet` never pays). Null,
## with nothing done, when the edge never moved. A refusal changes nothing and
## the grid emits edit_refused for it. `note` holds the status line text.
func finish(grid: BuildGrid, wallet: Wallet = null) -> BuildResult:
	active = false
	if _target == _original:
		return null
	var edit := BuildEdit.resize_room(room_id, _target)
	var result := check(grid, room_id, _target)
	if result.ok:
		var plan: Array[BuildEdit] = [edit]
		result = BuildTransaction.commit_plan(grid, plan, wallet)
	else:
		grid.edit_refused.emit(edit, result)
	note = _message(grid, result)
	return result


## "Cafe resized to 6 x 3: Needs a counter", or the refusal's reason.
func _message(grid: BuildGrid, result: BuildResult) -> String:
	if not result.ok:
		return result.reason_text()
	var status := RoomRules.status(grid, room_id)
	var room_name := RoomTypes.get_type(_type).display_name
	var size := _target.size
	return "%s resized to %d x %d: %s" % [room_name, size.x, size.y, status.headline()]
