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
		if result.pieces.get(need[0], 0) == 0:
			result.notes.append(need[1])
	if not has_opening(grid, area):
		result.notes.append(NO_OPENING)
	result.seats = result.pieces.get(type.seat_piece, 0) * type.seats_per_piece
	result.upkeep = result.pieces.get(type.upkeep_piece, 0) * type.upkeep_per_piece
	result.ok = result.notes.is_empty()
	return result


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
		var record := grid.get_object(object_id)
		var def := BuildCatalog.get_def(record["def"])
		var inside := true
		for cell in def.footprint(record["anchor"], record["facing"]):
			inside = inside and area.has_point(cell)
		var spot := grid.interaction_cell(object_id)
		if spot != BuildObjectDef.NO_CELL:
			inside = inside and area.has_point(spot)
		if inside:
			counts[def.id] = counts.get(def.id, 0) + 1
	return counts


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
