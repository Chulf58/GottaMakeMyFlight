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
	LANE_WALL,
	LANDSIDE_NOT_ON_SPOT,
	LANDSIDE_SPOT_TAKEN,
	LANDSIDE_OCCUPIED,
	ROOM_WALL,
	PLANE_AREA,
	LAND_NOT_OWNED,
	LAND_OWNED,
	LAND_NOT_TOUCHING,
	GATE_NO_EXIT,
	GATE_STAND_OVERLAP,
	GATE_IN_USE,
	GATE_FLIGHTS_STUCK,
	DOOR_FRONT_BLOCKED,
	MOVE_STRADDLES,
	MOVE_UNMOVABLE,
	MOVE_NO_FIT,
	MOVE_EXIT_BLOCKED,
	MOVE_CHANGED,
	LOCKED,
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
	Reason.STAFF_SPOT:
	(
		"Keep the staff spot behind a desk, beside a scanner or at a lane officer's post"
		+ " free, with a way in"
	),
	Reason.LANE_WALL: "A wall is in the way of the lane. Remove the wall first",
	Reason.LANDSIDE_NOT_ON_SPOT: "Put it on one of the marked landside spots",
	Reason.LANDSIDE_SPOT_TAKEN: "Every spot of this kind nearby is already built",
	Reason.LANDSIDE_OCCUPIED: "Cars are still in it. Close it and wait until it is empty",
	Reason.ROOM_WALL: "A wall is in the way of the room",
	Reason.PLANE_AREA: "A plane uses this apron. Build here after it takes off",
	Reason.LAND_NOT_OWNED: "You do not own this land. Buy the plot with Buy land first",
	Reason.LAND_OWNED: "You already own this plot",
	Reason.LAND_NOT_TOUCHING: "Buy a plot next to land you own",
	Reason.GATE_NO_EXIT: "Put a gate desk within 4 cells of a north exit no other gate uses",
	Reason.GATE_STAND_OVERLAP:
	"Gates need %d m between exits. Widen the terminal" % StandPlacement.EXIT_SPACING_CELLS,
	Reason.GATE_IN_USE: "A flight is still due at this gate. Remove it after the flight leaves",
	Reason.GATE_FLIGHTS_STUCK:
	"No other gate is free for these flights. Move them in Departures first",
	Reason.DOOR_FRONT_BLOCKED: "Something is in front of the door",
	Reason.MOVE_STRADDLES: "A piece sits across the room's edge",
	Reason.MOVE_UNMOVABLE: "Desks, scanners and lane parts cannot move with a room",
	Reason.MOVE_NO_FIT: "A piece does not fit at the new spot",
	Reason.MOVE_EXIT_BLOCKED: "Keep the way out clear for the passengers leaving the room",
	Reason.MOVE_CHANGED: "The room changed since it was picked up. Pick it up again",
	Reason.LOCKED: "Not unlocked yet",
}

var ok: bool = true
var reason: Reason = Reason.NONE
## The object a placement created, or the one a removal removed.
var object_id: int = 0
## The room a placement created, or the one a removal removed.
var room_id: int = 0
## The object that caused a refusal, when one did.
var blocking_object_id: int = 0
## What a refusal names beyond its reason (the flights or gate it is about),
## or "". reason_text() adds it after the reason.
var detail := ""
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
	if detail != "":
		return "%s: %s" % [REASON_TEXT[reason], detail]
	return REASON_TEXT[reason]
