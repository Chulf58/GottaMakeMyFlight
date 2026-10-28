class_name BuildResult
extends RefCounted
## Outcome of validating or applying one BuildEdit. A refusal is data: the UI
## shows reason_text(), and later systems (stuck passengers, tutorials) read
## the reason code instead of parsing a log line.

enum Reason {
	NONE,
	OUT_OF_BOUNDS,
	NO_FLOOR,
	BAD_FLOOR_TYPE,
	BAD_ZONE,
	BAD_FACING,
	UNKNOWN_OBJECT,
	OVERLAP,
	WALL_IN_FOOTPRINT,
	INTERACTION_BLOCKED,
	INTERACTION_RESERVED,
	OCCUPIED,
	WALL_EXISTS,
	NO_WALL,
	NO_OBJECT,
	BAD_WALL_KIND,
	DOOR_NEEDS_WALLS,
	WALL_HOLDS_DOOR,
	DOOR_NOT_ON_EDGE,
	DOOR_WALLED,
	DOOR_NOT_AT_SHELL_DOOR,
	UNKNOWN_ROOM_TYPE,
	ROOM_OVERLAP,
	IN_ROOM,
	NO_ROOM,
	CANT_AFFORD,
	UNPRICED,
	WALLET_FULL,
	BELT_CROSSING,
	BELT_WALL,
	NOT_A_BELT,
	STAFF_SPOT,
}

const REASON_TEXT := {
	Reason.NONE: "",
	Reason.OUT_OF_BOUNDS: "Outside the building area",
	Reason.NO_FLOOR: "Needs floor",
	Reason.BAD_FLOOR_TYPE: "Unknown floor type",
	Reason.BAD_ZONE: "Zone id must be 0 or more",
	Reason.BAD_FACING: "Facing must be 0 to 3",
	Reason.UNKNOWN_OBJECT: "Unknown object",
	Reason.OVERLAP: "Overlaps another object",
	Reason.WALL_IN_FOOTPRINT: "A wall runs through it",
	Reason.INTERACTION_BLOCKED: "The spot in front is blocked",
	Reason.INTERACTION_RESERVED: "Blocks the spot in front of another object",
	Reason.OCCUPIED: "An object stands here",
	Reason.WALL_EXISTS: "There is already a wall here",
	Reason.NO_WALL: "No wall here",
	Reason.NO_OBJECT: "No such object",
	Reason.BAD_WALL_KIND: "Unknown wall kind",
	Reason.DOOR_NEEDS_WALLS: "A door needs a plain wall on each side",
	Reason.WALL_HOLDS_DOOR: "A door stands beside this wall",
	Reason.DOOR_NOT_ON_EDGE: "Entrances and exits need the outside edge, with no floor behind them",
	Reason.DOOR_WALLED: "Keep the edge behind an entrance or exit open",
	Reason.DOOR_NOT_AT_SHELL_DOOR: "Use a landside door for an entrance, a gate door for an exit",
	Reason.UNKNOWN_ROOM_TYPE: "Unknown room type",
	Reason.ROOM_OVERLAP: "Overlaps another room",
	Reason.IN_ROOM: "A room covers this floor; remove the room first",
	Reason.NO_ROOM: "No such room",
	Reason.CANT_AFFORD: "Not enough money",
	Reason.UNPRICED: "This piece has no price",
	Reason.WALLET_FULL: "The money is at its limit; the refund would not fit",
	Reason.BELT_CROSSING: "Belts cannot cross; a belt joins at most three others",
	Reason.BELT_WALL: "A wall is in the way of the belt",
	Reason.NOT_A_BELT: "Only a belt piece changes shape",
	Reason.STAFF_SPOT: "Keep the staff spot behind a desk or beside a scanner free, with a way in",
}

var ok: bool = true
var reason: Reason = Reason.NONE
## The object a placement created, or the one a removal removed.
var object_id: int = 0
## The room a placement created, or the one a removal removed.
var room_id: int = 0
## The object that caused a refusal, when one did.
var blocking_object_id: int = 0
## Cells whose walkability or step links may have changed. Empty on refusal.
var dirty_cells: Array[Vector2i] = []


static func accepted() -> BuildResult:
	return BuildResult.new()


static func refused(why: Reason, blocker := 0) -> BuildResult:
	var result := BuildResult.new()
	result.ok = false
	result.reason = why
	result.blocking_object_id = blocker
	return result


func reason_text() -> String:
	return REASON_TEXT[reason]
