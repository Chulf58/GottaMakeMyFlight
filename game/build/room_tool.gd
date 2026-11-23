class_name RoomTool
extends RefCounted
## The room tools' rules, called by BuildMode (decision
## store-mechanics-draw-a-room-then-furnish-it-required-pieces: draw a room,
## then furnish it, upgraded by B2 Smart Room Drag 593876df). A room tool marks
## a press-drag-release rectangle, automatically laying missing interior floor
## tiles and missing perimeter walls around the room rectangle in ONE atomic
## composite commit (reusing existing floor/walls/doors on shared borders).
## A single click marks nothing, so a stray click never makes a one-cell room.


## Every outer edge of `area` as [cell, BuildGrid.Side] pairs with `cell` inside `area`.
static func perimeter_edges(area: Rect2i) -> Array:
	var out: Array = []
	if area.size.x <= 0 or area.size.y <= 0:
		return out
	for x in range(area.position.x, area.end.x):
		out.append([Vector2i(x, area.position.y), BuildGrid.Side.NORTH])
		out.append([Vector2i(x, area.end.y - 1), BuildGrid.Side.SOUTH])
	for y in range(area.position.y, area.end.y):
		out.append([Vector2i(area.position.x, y), BuildGrid.Side.WEST])
		out.append([Vector2i(area.end.x - 1, y), BuildGrid.Side.EAST])
	return out


## Composite edits for Smart Room Drag: missing interior floor tiles, then
## missing perimeter walls (reusing existing walls/doors and open entrance/exit
## ways out), then PLACE_ROOM.
static func plan(grid: BuildGrid, area: Rect2i, type: StringName) -> Array[BuildEdit]:
	var edits: Array[BuildEdit] = []
	if (
		RoomTypes.get_type(type) == null
		or area.size.x <= 0
		or area.size.y <= 0
		or not grid.in_bounds(area.position)
		or not grid.in_bounds(area.end - Vector2i.ONE)
	):
		edits.append(BuildEdit.place_room(area, type))
		return edits
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var cell := Vector2i(x, y)
			if grid.floor_at(cell) == BuildGrid.FLOOR_NONE:
				edits.append(
					BuildEdit.paint_floor(cell, BuildGrid.FLOOR_TILE, BuildMode.TERMINAL_ZONE)
				)
	for edge in perimeter_edges(area):
		var cell: Vector2i = edge[0]
		var side: int = edge[1]
		if grid.wall_kind(cell, side) != BuildGrid.WallKind.NONE:
			continue
		if DoorPlacement.on_a_way_out(grid, cell, side):
			continue
		edits.append(BuildEdit.place_wall(cell, side, BuildGrid.WallKind.PLAIN))
	edits.append(BuildEdit.place_room(area, type))
	return edits


static func _precheck(grid: BuildGrid, area: Rect2i, type: StringName) -> BuildResult:
	if RoomTypes.get_type(type) == null:
		return BuildResult.refused(BuildResult.Reason.UNKNOWN_ROOM_TYPE)
	if (
		area.size.x <= 0
		or area.size.y <= 0
		or not grid.in_bounds(area.position)
		or not grid.in_bounds(area.end - Vector2i.ONE)
	):
		return BuildResult.refused(BuildResult.Reason.OUT_OF_BOUNDS)
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			if grid.room_at(Vector2i(x, y)) != 0:
				return BuildResult.refused(BuildResult.Reason.ROOM_OVERLAP)
	return BuildResult.accepted()


## Whether the grid and wallet/unlocks would accept Smart Room Drag of `area` as `type`.
static func check(
	grid: BuildGrid,
	area: Rect2i,
	type: StringName,
	wallet: Wallet = null,
	unlocks: BuildUnlocks = null,
	require_unlocks := false
) -> BuildResult:
	var pre := _precheck(grid, area, type)
	if not pre.ok:
		return pre
	return BuildTransaction.check_composite(
		grid, plan(grid, area, type), wallet, unlocks, require_unlocks
	)


## Marks `area` as a room of `type` with auto-floor and perimeter walls in ONE
## atomic composite commit through BuildTransaction.
static func mark(
	grid: BuildGrid,
	area: Rect2i,
	type: StringName,
	wallet: Wallet = null,
	unlocks: BuildUnlocks = null,
	require_unlocks := false
) -> BuildResult:
	var pre := _precheck(grid, area, type)
	if not pre.ok:
		grid._emit_or_hold(
			func() -> void: grid.edit_refused.emit(BuildEdit.place_room(area, type), pre)
		)
		return pre
	return BuildTransaction.commit_composite(
		grid, plan(grid, area, type), wallet, unlocks, require_unlocks
	)


## Combined composite cost (missing floor + missing perimeter walls) as
## Vector2i(cost, needed) for BuildMenu's live price badge.
static func preview_price(grid: BuildGrid, area: Rect2i, type: StringName) -> Vector2i:
	if (
		RoomTypes.get_type(type) == null
		or area.size.x <= 0
		or area.size.y <= 0
		or not grid.in_bounds(area.position)
		or not grid.in_bounds(area.end - Vector2i.ONE)
	):
		return Vector2i.ZERO
	var needed := BuildTransaction.needed(grid, plan(grid, area, type))
	return Vector2i(maxi(0, needed), maxi(0, needed))


## The status line while a rectangle is dragged: "Cafe 4 x 3", followed by
## the reason the grid/wallet would refuse it.
static func drag_label(
	grid: BuildGrid,
	area: Rect2i,
	type: StringName,
	wallet: Wallet = null,
	unlocks: BuildUnlocks = null,
	require_unlocks := false
) -> String:
	var text := BuildWords.room_size(
		DisplayWords.room_type(RoomTypes.get_type(type).display_name), area.size.x, area.size.y
	)
	var result := check(grid, area, type, wallet, unlocks, require_unlocks)
	if not result.ok:
		text += "  " + result.reason_text()
	return text


## The status line after a release: "Cafe marked: Needs a counter", or the
## refusal.
static func message(grid: BuildGrid, result: BuildResult, type: StringName) -> String:
	if not result.ok:
		return result.reason_text()
	var status := RoomRules.status(grid, result.room_id)
	return BuildWords.room_marked(
		DisplayWords.room_type(RoomTypes.get_type(type).display_name),
		DisplayWords.ready() if status.ok else DisplayWords.notes(status)[0]
	)


## The status line while a room tool waits for a drag.
static func hint(type: StringName) -> String:
	return BuildWords.room_hint(RoomTypes.get_type(type).display_name)
