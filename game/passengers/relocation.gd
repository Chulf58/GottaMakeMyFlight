class_name Relocation
extends RefCounted
## A visitor's way back into its visit after the piece it was using moved with
## its room (decision move-rooms-technical-design-roommove-plan-of-existing-
## edits, parts 4 to 6; ruling moving-a-room-with-its-furniture-is-free-and-
## keeps-paid-pric, points 2 and 4). Held by a cafe, toilet or shop visit (a
## kiosk display stand or an activity piece: ShopSim's browser or sitter is
## "physically at" the piece while it browses; its exit is ActivityPoses.
## exit_ticks(), none for a display stand, and the stay it still owes is
## `left`, browse_ticks() at most).
##
## Each visit keeps the placement of its piece ({"def", "anchor", "facing"}) as
## it last saw it. When the sim's reconcile finds the piece at another
## placement while the visitor is physically at it (sitting down, seated or
## standing up at a cafe seat; stepping in, using or stepping out of a toilet
## stall), the visit gets a Relocation: `source` is that old placement, and the
## visitor's seat or stall geometry stays the one derived from it. The visitor
## finishes its exit there with no settling (a sit-down or step-in is turned
## back partway, as an early leave turns it back), then the visit admits it
## again with the normal forecast (walk to the piece's new spot, sit down or
## step in, the service still owed, the way on to the plane) and it walks to
## the new spot, or it gives up unpaid. The piece's id is the destination, so a
## second move while the exit runs only changes where the walk goes, and a move
## undone before any tick never reaches reconcile at all.
##
## While a visitor still uses a piece at a placement the grid no longer holds,
## ghosts() lists it, so the view draws a stand-in of the piece at the old spot
## and nobody sits on air while build mode is paused (decision part 5).

## The placement the visitor is leaving: {"def": StringName, "anchor":
## Vector2i, "facing": int}. Never changed once set.
var source: Dictionary = {}
## True while the visitor finishes its exit at `source`; false once it has left
## and walks to the piece's new spot.
var exiting := true
## Service ticks still owed at the new spot, or -1 when the visit was already
## over and the visitor only finishes leaving.
var left := -1


## A new relocation leaving `from` with `owed` service ticks still to do.
static func leaving(from: Dictionary, owed: int) -> Relocation:
	var out := Relocation.new()
	out.source = from
	out.left = owed
	return out


## Object `id`'s placement on `grid`, or empty when there is no such object.
static func placement(grid: BuildGrid, id: int) -> Dictionary:
	var record := grid.get_object(id)
	if record.is_empty():
		return {}
	return {
		"def": StringName(record["def"]),
		"anchor": record["anchor"] as Vector2i,
		"facing": int(record["facing"]),
	}


## Whether a visitor using a piece last seen at `seen` must relocate: the grid
## holds the piece (`live`) at another placement. A removed piece is not a move.
static func moved(seen: Dictionary, live: Dictionary) -> bool:
	return not seen.is_empty() and not live.is_empty() and seen != live


## Whether the visitor will walk back into its visit after its exit.
func returns() -> bool:
	return left >= 0


## Whether object `id` on `grid` is still a `def_id` piece of room `room_id`
## (FacilitySlots.piece_inside()), and the room still the kind that uses it (a
## toilet for a toilet_stall, a food room with seats for a cafe_table), ready
## or not: a piece a visitor can return to once the room is usable. After a
## move the walls stay behind, so the room is often not ready yet while the
## visitor leaves the old spot.
static func destination_ok(grid: BuildGrid, id: int, def_id: StringName, room_id: int) -> bool:
	var record := grid.get_object(id)
	var room := grid.get_room(room_id)
	if record.is_empty() or room.is_empty() or record["def"] != def_id:
		return false
	var type := RoomTypes.get_type(room["type"])
	var kind_ok := false
	if def_id == &"toilet_stall":
		kind_ok = room["type"] == &"toilet"
	elif def_id == &"cafe_table":
		kind_ok = type != null and type.food and not type.walk_on
	else:
		kind_ok = type != null and type.shop and type.seat_piece == def_id
	return kind_ok and FacilitySlots.piece_inside(grid, id, room["rect"])


## Keeps a visitor leaving the old spot from walking back to a piece that is no
## longer one of its room's (removed, or its room gone): its return becomes a
## final exit (left -1), and the visit ends when the exit does.
func drop_return_unless(grid: BuildGrid, id: int, def_id: StringName, room_id: int) -> void:
	if exiting and returns() and not destination_ok(grid, id, def_id, room_id):
		left = -1


## The JSON shape of a save.
func to_record() -> Dictionary:
	var anchor: Vector2i = source["anchor"]
	return {
		"def": String(source["def"]),
		"anchor": [anchor.x, anchor.y],
		"facing": source["facing"],
		"exiting": exiting,
		"left": left,
	}


## A relocation from a to_record() dictionary (also after JSON), or null when
## it is malformed: an unknown piece, a facing outside 0 to 3, or a service
## left below -1.
static func from_record(data: Variant) -> Relocation:
	if typeof(data) != TYPE_DICTIONARY:
		return null
	for key in ["def", "anchor", "facing", "exiting", "left"]:
		if not data.has(key):
			return null
	var anchor: Variant = data["anchor"]
	var ok: bool = (
		typeof(data["def"]) == TYPE_STRING
		and BuildCatalog.get_def(StringName(data["def"])) != null
		and typeof(anchor) == TYPE_ARRAY
		and anchor.size() == 2
		and WholeNumber.is_whole(anchor[0])
		and WholeNumber.is_whole(anchor[1])
		and WholeNumber.is_whole(data["facing"])
		and typeof(data["exiting"]) == TYPE_BOOL
		and WholeNumber.is_whole(data["left"])
	)
	if not ok or int(data["facing"]) < 0 or int(data["facing"]) > 3 or int(data["left"]) < -1:
		return null
	var out := Relocation.new()
	out.source = {
		"def": StringName(data["def"]),
		"anchor": Vector2i(int(anchor[0]), int(anchor[1])),
		"facing": int(data["facing"]),
	}
	out.exiting = data["exiting"]
	out.left = int(data["left"])
	return out


## The cafe seat descriptor (CafeLayout seat entry) of seat `key`
## ("<table id>:<seat index>") at placement `at`, or empty when the piece has
## no such seat.
static func seat_at(at: Dictionary, key: String) -> Dictionary:
	var parts := key.split(":")
	var def := BuildCatalog.get_def(at.get("def", &""))
	if parts.size() != 2 or def == null:
		return {}
	var index := int(parts[1])
	var seats := def.seat_descriptors(at["anchor"], at["facing"])
	if index < 0 or index >= seats.size():
		return {}
	var seat: Dictionary = seats[index]
	seat["key"] = key
	seat["object_id"] = int(parts[0])
	return seat


## The cells visitors at their pieces need clear to leave them: each cafe
## guest's seat and its approach cell while it sits down, sits or stands up,
## and each toilet user's stall cells and approach cell while it is inside. A
## room move that sets a piece down on one is refused (RoomMove's keep_clear,
## decision part 3), in id order, each cell once.
static func exit_cells(sim: PassengerSim) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for id in sim.cafes.visit_ids():
		var seat := sim.cafes.visit_of(id).seat
		var p := sim.get_passenger(id)
		if CafeSim.SEAT_STAGES.has(p.stage) and not seat.is_empty():
			_add(out, [seat["cell"], seat["approach"]])
	for id in sim.toilets.visit_ids():
		var stall := sim.toilets.visit_of(id).stall
		var p := sim.get_passenger(id)
		if ToiletSim.STALL_STAGES.has(p.stage) and not stall.is_empty():
			_add(out, [stall["use_cell"], stall["turn_cell"], stall["approach"]])
	for id in sim.shops.visit_ids():
		var visit := sim.shops.visit_of(id)
		if sim.get_passenger(id).stage == Passenger.Stage.SHOP_BROWSE and not visit.slot.is_empty():
			var approach: Vector2i = visit.slot["approach"]
			_add(out, [approach])
			if ActivityPoses.KINDS.has(visit.piece.get("def", &"")):
				# A sitter or shower user is also on the piece's own cell.
				_add(out, [approach + (visit.slot["facing"] as Vector2i)])
	return out


## The pieces drawn as stand-ins at their old spot: each placement a visitor
## at its piece (exit_cells()'s stages) still uses while the grid holds the
## piece elsewhere, also between a move and the next tick. {"id", "def",
## "anchor", "facing"} each, in id order of their visitors, each once.
static func ghosts(sim: PassengerSim) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in sim.cafes.visit_ids():
		var visit := sim.cafes.visit_of(id)
		if CafeSim.SEAT_STAGES.has(sim.get_passenger(id).stage):
			var seat_id := int(visit.seat.get("object_id", 0))
			_ghost(out, sim.grid, seat_id, visit.piece, visit.relocation)
	for id in sim.toilets.visit_ids():
		var visit := sim.toilets.visit_of(id)
		if ToiletSim.STALL_STAGES.has(sim.get_passenger(id).stage):
			_ghost(out, sim.grid, visit.stall_id, visit.piece, visit.relocation)
	for id in sim.shops.visit_ids():
		var visit := sim.shops.visit_of(id)
		if sim.get_passenger(id).stage == Passenger.Stage.SHOP_BROWSE:
			_ghost(out, sim.grid, visit.display, visit.piece, visit.relocation)
	return out


## Adds the stand-in of piece `id` last seen at `seen`: when the grid holds the
## piece elsewhere, or, for a visitor still leaving the old spot (`moving`),
## anywhere else or nowhere, so a piece removed while its visitor gets up is
## still drawn under it.
static func _ghost(
	out: Array[Dictionary], grid: BuildGrid, id: int, seen: Dictionary, moving: Relocation
) -> void:
	var live := placement(grid, id)
	var leaving := moving != null and moving.exiting and not seen.is_empty() and live != seen
	if id == 0 or not (leaving or moved(seen, live)):
		return
	var entry := seen.duplicate()
	entry["id"] = id
	if not out.has(entry):
		out.append(entry)


static func _add(out: Array[Vector2i], cells: Array) -> void:
	for cell: Vector2i in cells:
		if not out.has(cell):
			out.append(cell)
