class_name RoomRules
extends RefCounted
## Whether a room is ready, and what it still needs (decision
## store-mechanics-draw-a-room-then-furnish-it-required-pieces). The status is
## derived from the grid every time it is asked for and never stored.
##
## A room is ready when it is at least its type's minimum size, holds each
## required piece, and has a door or open side to the walkway. A piece counts
## when its whole footprint and its interaction cell (if it has one) lie in
## the room. The walkway test is one open step (BuildGrid.can_step) from a room
## cell to a floor cell outside every room.
##
## Ready is a building check, not a promise to passengers: it does not ask
## whether the walkway reaches the entrance or whether the counter and seats
## can be reached from the opening. Passenger code must check its own paths.

const READY := "Ready"
const NO_OPENING := "Needs a door or open side to the walkway"
const TOO_SMALL := "Too small: a %s needs at least %dx%d"


## One room's status, for the room label and the info panel.
class RoomStatus:
	extends RefCounted
	var room_id := 0
	var type_id: StringName = &""
	var type_name := ""
	var ok := false
	## What the room still needs, most basic first. Empty when it is ready.
	var notes := PackedStringArray()
	var seats := 0
	var base_spend := 0
	## What the room costs to run per game day once it is ready: its type's
	## upkeep piece count times the per-piece upkeep. Shown as one room total.
	var upkeep := 0
	## BuildCatalog id -> how many of that piece count for the room.
	var pieces: Dictionary = {}

	## "Ready", or the first note.
	func headline() -> String:
		return READY if ok else notes[0]


## The room's status, or null for an unknown room id.
static func status(grid: BuildGrid, room_id: int) -> RoomStatus:
	var room := grid.get_room(room_id)
	if room.is_empty():
		return null
	var type := RoomTypes.get_type(room["type"])
	var area: Rect2i = room["rect"]
	var result := RoomStatus.new()
	result.room_id = room_id
	result.type_id = type.id
	result.type_name = type.display_name
	result.base_spend = type.base_spend
	result.pieces = pieces_in(grid, area)
	if not type.fits(area.size):
		result.notes.append(
			TOO_SMALL % [type.display_name.to_lower(), type.min_size.x, type.min_size.y]
		)
	for need in type.required:
		if _count(result.pieces, type.pieces_for(need[0])) == 0:
			result.notes.append(need[1])
	if not has_opening(grid, area):
		result.notes.append(NO_OPENING)
	if type.table_pieces.is_empty():
		result.seats = result.pieces.get(type.seat_piece, 0) * type.seats_per_piece
	else:
		# A food room: each table piece in it gives the seats of its catalog entry
		# a guest can reach (reachable_seats()).
		for object_id in grid.object_ids():
			var piece := StringName(grid.get_object(object_id)["def"])
			if type.table_pieces.has(piece) and piece_inside(grid, object_id, area):
				result.seats += reachable_seats(grid, object_id).size()
	result.upkeep = result.pieces.get(type.upkeep_piece, 0) * type.upkeep_per_piece
	result.ok = result.notes.is_empty()
	return result


## How many of the pieces `ids` the count table `pieces` holds in all.
static func _count(pieces: Dictionary, ids: Array[StringName]) -> int:
	var total := 0
	for id in ids:
		total += pieces.get(id, 0)
	return total


## The seat descriptors (BuildObjectDef.seat_descriptors) of object
## `object_id` a guest can step into: its approach cell is walkable and no
## wall but a door stands between it and the seat's cell. A booth with an end
## against a wall keeps only the two seats at its open end (decision
## restaurant-booth-against-a-wall-counts-only-reachable-seats). The room's
## seat count and the piece's info come from here; CafeLayout also asks that
## the approach cell is indoor, as every passenger cell must be.
static func reachable_seats(grid: BuildGrid, object_id: int) -> Array[Dictionary]:
	var record := grid.get_object(object_id)
	var def := BuildCatalog.get_def(record["def"])
	var out: Array[Dictionary] = []
	for seat in def.seat_descriptors(record["anchor"], record["facing"]):
		var approach: Vector2i = seat["approach"]
		var side := BuildGrid.SIDE_STEP.find(seat["cell"] - approach)
		var wall := grid.wall_kind(approach, side)
		if (
			grid.is_walkable(approach)
			and (wall == BuildGrid.WallKind.NONE or wall == BuildGrid.WallKind.DOOR)
		):
			out.append(seat)
	return out


## What room `room_id` is charged at midnight (Settlement): its upkeep when it is
## ready, 0 when it is not or there is no such room.
static func daily_upkeep(grid: BuildGrid, room_id: int) -> int:
	var result := status(grid, room_id)
	if result == null or not result.ok:
		return 0
	return result.upkeep


## BuildCatalog id -> count of the objects wholly inside `area`, their
## interaction cell included.
static func pieces_in(grid: BuildGrid, area: Rect2i) -> Dictionary:
	var counts := {}
	for object_id in grid.object_ids():
		if piece_inside(grid, object_id, area):
			var def_id := StringName(grid.get_object(object_id)["def"])
			counts[def_id] = counts.get(def_id, 0) + 1
	return counts


## Whether object `object_id` lies wholly inside `area`, its interaction cell
## included: the rule a piece counts for a room by.
static func piece_inside(grid: BuildGrid, object_id: int, area: Rect2i) -> bool:
	var record := grid.get_object(object_id)
	var def := BuildCatalog.get_def(record["def"])
	for cell in def.footprint(record["anchor"], record["facing"]):
		if not area.has_point(cell):
			return false
	var spot := grid.interaction_cell(object_id)
	return spot == BuildObjectDef.NO_CELL or area.has_point(spot)


## Whether some room cell on the edge of `area` has an open step to a floor
## cell outside every room.
static func has_opening(grid: BuildGrid, area: Rect2i) -> bool:
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var cell := Vector2i(x, y)
			for step in BuildGrid.SIDE_STEP:
				var outside: Vector2i = cell + step
				if area.has_point(outside) or grid.room_at(outside) != 0:
					continue
				if grid.can_step(cell, outside):
					return true
	return false
