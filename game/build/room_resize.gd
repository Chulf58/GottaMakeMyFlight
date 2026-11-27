class_name RoomResize
extends RefCounted
## Resizing a built room by dragging one of its edges (decision
## resize-rooms-first-drag-a-room-s-edge-to-grow-or-shrink-it-f, upgraded by
## B2 boundary-aware resize 593876df). Works both with the room's tool picked
## and from always-on resize handles on a selected room in Tool.NONE.
##
## Expanding/shrinking moves outer perimeter walls owned exclusively by the room
## and fills newly added floor cells automatically as ONE atomic composite
## transaction, while preserving shared walls/doors belonging to neighboring
## rooms or terminal perimeter, and keeping existing furniture intact (or
## refusing cleanly if a shrink's new wall would clip furniture or block its
## interaction cell).

## How far in from a room's outer edge a press still grabs that edge, in metres.
const EDGE_BAND := 0.3
## How close to a resize handle midpoint a click in Tool.NONE grabs that handle.
const HANDLE_HIT_RADIUS := 0.45

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


## World positions of the 4 edge resize handles (North, East, South, West) of `rect`.
static func handle_positions(grid: BuildGrid, rect: Rect2i) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if not rect.has_area():
		return out
	var ox := grid.origin.x
	var oz := grid.origin.z
	var y := grid.origin.y
	var cx := ox + (rect.position.x + rect.end.x) * 0.5
	var cz := oz + (rect.position.y + rect.end.y) * 0.5
	out.append(Vector3(cx, y, oz + rect.position.y))
	out.append(Vector3(ox + rect.end.x, y, cz))
	out.append(Vector3(cx, y, oz + rect.end.y))
	out.append(Vector3(ox + rect.position.x, y, cz))
	return out


## The BuildGrid.Side of the handle hit at `point` on `rect` in Tool.NONE, or -1.
static func handle_hit(grid: BuildGrid, rect: Rect2i, point: Vector3) -> int:
	if not rect.has_area():
		return -1
	var positions := handle_positions(grid, rect)
	var best := -1
	var best_dist := HANDLE_HIT_RADIUS
	for s in 4:
		var hp := positions[s]
		var dist := maxf(absf(point.x - hp.x), absf(point.z - hp.z))
		if dist <= best_dist:
			best = s
			best_dist = dist
	if best >= 0:
		return best
	var cell := grid.world_to_cell(point)
	if grid.in_bounds(cell) and grid.object_at(cell) != 0:
		return -1
	return edge_side(grid, rect, point)


## Canonical edge key for `(cell, edge_side)` so two cells sharing an edge match.
static func _edge_key(cell: Vector2i, edge_side: int) -> Vector3i:
	match edge_side:
		BuildGrid.Side.SOUTH:
			return Vector3i(cell.x, cell.y + 1, BuildGrid.Side.NORTH)
		BuildGrid.Side.EAST:
			return Vector3i(cell.x + 1, cell.y, BuildGrid.Side.WEST)
	return Vector3i(cell.x, cell.y, edge_side)


## Canonical edge key -> {"cell": inside cell, "side": outward side, "outside": outside cell}.
static func _perimeter_map(area: Rect2i) -> Dictionary:
	var map := {}
	if not area.has_area():
		return map
	for x in range(area.position.x, area.end.x):
		var n := Vector2i(x, area.position.y)
		map[_edge_key(n, BuildGrid.Side.NORTH)] = {
			"cell": n, "side": BuildGrid.Side.NORTH, "outside": n + Vector2i(0, -1)
		}
		var s := Vector2i(x, area.end.y - 1)
		map[_edge_key(s, BuildGrid.Side.SOUTH)] = {
			"cell": s, "side": BuildGrid.Side.SOUTH, "outside": s + Vector2i(0, 1)
		}
	for y in range(area.position.y, area.end.y):
		var w := Vector2i(area.position.x, y)
		map[_edge_key(w, BuildGrid.Side.WEST)] = {
			"cell": w, "side": BuildGrid.Side.WEST, "outside": w + Vector2i(-1, 0)
		}
		var e := Vector2i(area.end.x - 1, y)
		map[_edge_key(e, BuildGrid.Side.EAST)] = {
			"cell": e, "side": BuildGrid.Side.EAST, "outside": e + Vector2i(1, 0)
		}
	return map


## Composite edits to resize `id` from its current rect to `area`:
## fills missing new floor cells, removes exclusive old perimeter walls no longer
## on the boundary (preserving shared neighbor-room and terminal-perimeter walls),
## resizes the room, and adds missing perimeter walls on the new boundary.
static func plan(grid: BuildGrid, id: int, area: Rect2i) -> Array[BuildEdit]:
	var edits: Array[BuildEdit] = []
	var room := grid.get_room(id)
	if room.is_empty():
		edits.append(BuildEdit.resize_room(id, area))
		return edits
	var old: Rect2i = room["rect"]
	if (
		not area.has_area()
		or not grid.in_bounds(area.position)
		or not grid.in_bounds(area.end - Vector2i.ONE)
	):
		edits.append(BuildEdit.resize_room(id, area))
		return edits
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var cell := Vector2i(x, y)
			if not old.has_point(cell) and grid.floor_at(cell) == BuildGrid.FLOOR_NONE:
				edits.append(
					BuildEdit.paint_floor(cell, BuildGrid.FLOOR_TILE, BuildMode.TERMINAL_ZONE)
				)
	var old_map := _perimeter_map(old)
	var new_map := _perimeter_map(area)
	var door_removals: Array[BuildEdit] = []
	var wall_removals: Array[BuildEdit] = []
	for key in old_map:
		if new_map.has(key):
			continue
		var info: Dictionary = old_map[key]
		var cell: Vector2i = info["cell"]
		var edge: int = info["side"]
		var outside: Vector2i = info["outside"]
		var kind := grid.wall_kind(cell, edge)
		if kind == BuildGrid.WallKind.NONE:
			continue
		if not grid.in_bounds(outside):
			continue
		if (
			grid.floor_at(outside) != BuildGrid.FLOOR_NONE
			and grid.zone_at(cell) != grid.zone_at(outside)
		):
			continue
		var out_room := grid.room_at(outside)
		if out_room != 0 and out_room != id:
			continue
		if not area.has_point(outside) and grid.floor_at(outside) == BuildGrid.FLOOR_NONE:
			continue
		var rem := BuildEdit.remove_wall(cell, edge)
		if kind == BuildGrid.WallKind.DOOR:
			door_removals.append(rem)
		else:
			wall_removals.append(rem)
	edits.append_array(door_removals)
	edits.append_array(wall_removals)
	edits.append(BuildEdit.resize_room(id, area))
	for key in new_map:
		var info: Dictionary = new_map[key]
		var cell: Vector2i = info["cell"]
		var edge: int = info["side"]
		if grid.wall_kind(cell, edge) != BuildGrid.WallKind.NONE:
			continue
		if DoorPlacement.on_a_way_out(grid, cell, edge):
			continue
		edits.append(BuildEdit.place_wall(cell, edge, BuildGrid.WallKind.PLAIN))
	return edits


static func _precheck(grid: BuildGrid, id: int, area: Rect2i) -> BuildResult:
	var room := grid.get_room(id)
	if room.is_empty():
		return BuildResult.refused(BuildResult.Reason.NO_ROOM)
	if (
		not area.has_area()
		or not grid.in_bounds(area.position)
		or not grid.in_bounds(area.end - Vector2i.ONE)
	):
		return BuildResult.refused(BuildResult.Reason.OUT_OF_BOUNDS)
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var occ := grid.room_at(Vector2i(x, y))
			if occ != 0 and occ != id:
				return BuildResult.refused(BuildResult.Reason.ROOM_OVERLAP)
	if wall_crossed(grid, room["rect"], area):
		return BuildResult.refused(BuildResult.Reason.ROOM_WALL)
	return BuildResult.accepted()


## Whether the grid and wallet would accept room `id` taking `area`:
## boundary-aware composite validation plus no wall strictly inside the grown strip.
static func check(grid: BuildGrid, id: int, area: Rect2i, wallet: Wallet = null) -> BuildResult:
	var pre := _precheck(grid, id, area)
	if not pre.ok:
		return pre
	return BuildTransaction.check_composite(grid, plan(grid, id, area), wallet)


## Net cost preview Vector2i(max(0, net), max(0, net)) for BuildMenu's cost line.
static func preview_price(grid: BuildGrid, id: int, area: Rect2i) -> Vector2i:
	var pre := _precheck(grid, id, area)
	if not pre.ok:
		return Vector2i.ZERO
	var staged := BuildTransaction.preview_composite(grid, plan(grid, id, area))
	if not (staged["result"] as BuildResult).ok:
		return Vector2i.ZERO
	var net: int = staged["net"]
	return Vector2i(maxi(0, net), maxi(0, net))


## Whether growing `old` into `area` moves an edge across an external wall:
## a wall on any grid line strictly between the old edge and the new edge along
## the room's span. The old edge itself moves if exclusively owned; the new
## edge may stand on a wall, which then bounds the room. Shrinking crosses nothing.
static func wall_crossed(grid: BuildGrid, old: Rect2i, area: Rect2i) -> bool:
	for x in range(area.position.x + 1, old.position.x):
		if _column_line_walled(grid, x, old):
			return true
	for x in range(old.end.x + 1, area.end.x):
		if _column_line_walled(grid, x, old):
			return true
	for y in range(area.position.y + 1, old.position.y):
		if _row_line_walled(grid, y, old):
			return true
	for y in range(old.end.y + 1, area.end.y):
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
	return _start(id, type, rect, grabbed as BuildGrid.Side, cell)


## Grabs a handle of the selected room `id` in Tool.NONE. False if `point` does
## not hit a handle/edge of `id`.
func begin_handle(grid: BuildGrid, id: int, point: Vector3) -> bool:
	var room := grid.get_room(id)
	if room.is_empty():
		return false
	var rect: Rect2i = room["rect"]
	var grabbed := handle_hit(grid, rect, point)
	if grabbed < 0:
		return false
	return _start(
		id, StringName(room["type"]), rect, grabbed as BuildGrid.Side, grid.world_to_cell(point)
	)


func _start(
	id: int, type: StringName, rect: Rect2i, grabbed: BuildGrid.Side, cell: Vector2i
) -> bool:
	active = true
	room_id = id
	side = grabbed
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
## grid or wallet would refuse it.
func label(grid: BuildGrid, wallet: Wallet = null) -> String:
	var text := BuildWords.room_size(
		DisplayWords.room_type(RoomTypes.get_type(_type).display_name),
		_target.size.x,
		_target.size.y
	)
	var result := check(grid, room_id, _target, wallet)
	if not result.ok:
		text += "  " + result.reason_text()
	return text


## Ends the drag and applies boundary-aware resize as ONE atomic composite
## transaction through BuildTransaction. Null with nothing done when the edge
## never moved. `note` holds the status line text.
func finish(grid: BuildGrid, wallet: Wallet = null) -> BuildResult:
	active = false
	if _target == _original:
		return null
	var result := commit_area(grid, room_id, _target, wallet)
	note = status_message(grid, room_id, _type, _target, result)
	return result


## Commits a room resize to `area` as ONE atomic composite transaction.
static func commit_area(
	grid: BuildGrid, id: int, area: Rect2i, wallet: Wallet = null
) -> BuildResult:
	var pre := _precheck(grid, id, area)
	if not pre.ok:
		grid._emit_or_hold(
			func() -> void: grid.edit_refused.emit(BuildEdit.resize_room(id, area), pre)
		)
		return pre
	return BuildTransaction.commit_composite(grid, plan(grid, id, area), wallet)


## "Cafe resized to 6 x 3: Needs a counter", or the refusal's reason.
static func status_message(
	grid: BuildGrid, id: int, type: StringName, area: Rect2i, result: BuildResult
) -> String:
	if not result.ok:
		return result.reason_text()
	var status := RoomRules.status(grid, id)
	var room_name := DisplayWords.room_type(RoomTypes.get_type(type).display_name)
	var size := area.size
	return "%s resized to %d x %d: %s" % [room_name, size.x, size.y, status.headline()]


## Status line for an auto-extending room drag: "Cafe 6 x 3" plus refusal reason.
static func extend_label(
	grid: BuildGrid, id: int, type: StringName, area: Rect2i, wallet: Wallet = null
) -> String:
	var text := BuildWords.room_size(
		DisplayWords.room_type(RoomTypes.get_type(type).display_name), area.size.x, area.size.y
	)
	var result := check(grid, id, area, wallet)
	if not result.ok:
		text += "  " + result.reason_text()
	return text


## If `drag_rect` is flush along a full edge of an existing room of `type` with
## no overlap (so their union is an exact rectangle), returns
## `{"room_id": id, "rect": union_rect}`, else `{}`.
static func auto_extend(grid: BuildGrid, drag_rect: Rect2i, type: StringName) -> Dictionary:
	if not drag_rect.has_area():
		return {}
	for id in grid.room_ids():
		var room := grid.get_room(id)
		if room.is_empty() or StringName(room["type"]) != type:
			continue
		var r: Rect2i = room["rect"]
		if r.intersects(drag_rect):
			continue
		var match_ew := (
			r.position.y == drag_rect.position.y
			and r.size.y == drag_rect.size.y
			and (drag_rect.end.x == r.position.x or drag_rect.position.x == r.end.x)
		)
		var match_ns := (
			r.position.x == drag_rect.position.x
			and r.size.x == drag_rect.size.x
			and (drag_rect.end.y == r.position.y or drag_rect.position.y == r.end.y)
		)
		if match_ew or match_ns:
			return {"room_id": id, "rect": r.merge(drag_rect)}
	return {}


## When hovering a resizable room edge (either via a matching room tool in
## `TOOL_ROOMS` or a selected room's handle/edge in `Tool.NONE`), returns
## `{"room_id": id, "rect": rect, "side": side}` with `side >= 0`, else `{}`.
static func hover_edge(
	grid: BuildGrid, tool: int, selected_room_id: int, point: Variant
) -> Dictionary:
	if point == null:
		return {}
	var p: Vector3 = point
	if tool == BuildMode.Tool.NONE and selected_room_id != 0:
		var room := grid.get_room(selected_room_id)
		if room.is_empty():
			return {}
		var rect: Rect2i = room["rect"]
		var hit_side := handle_hit(grid, rect, p)
		if hit_side >= 0:
			return {"room_id": selected_room_id, "rect": rect, "side": hit_side}
		return {}
	if BuildMode.TOOL_ROOMS.has(tool):
		var type: StringName = BuildMode.TOOL_ROOMS[tool]
		var cell := grid.world_to_cell(p)
		var id := grid.room_at(cell)
		if id == 0 or StringName(grid.get_room(id)["type"]) != type:
			return {}
		var rect: Rect2i = grid.get_room(id)["rect"]
		var hit_side := edge_side(grid, rect, p)
		if hit_side >= 0:
			return {"room_id": id, "rect": rect, "side": hit_side}
	return {}
