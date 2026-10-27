class_name CafeLayout
extends RefCounted
## The cafes passengers can use, derived from the grid (decision
## cafe-visit-design-forecast-the-whole-itinerary-abandon-by-a, point 9): Rooms
## owns the room, its furniture and whether it is ready; this layout owns the
## usable counters, their queue lanes and the seats; CafeSim owns who is
## queuing and sitting. Rebuilt after every grid edit, after TerminalLayout.
##
## A cafe is a ready cafe room (RoomRules). Its counters are the cafe_counter
## pieces RoomRules counts for it; each has a fixed lane from its order spot
## (slot 0) straight out along its front, up to LANE_SLOTS cells, stopping at
## a closed step, a station lane, another object's interaction cell or a seat's
## approach cell. A counter with no lane is left out. Its seats are the chairs
## of the cafe_table pieces in the room whose approach cell is walkable.

const LANE_SLOTS := 4

## One entry per cafe, in room id order: {"room": int, "counters": Array of
## {"id": int, "lane": Array[Vector2i]} in id order, "seats": Array of seat
## entries in key order}. A seat entry is a BuildObjectDef seat descriptor
## plus "key" ("<table id>:<seat index>") and "object_id".
var cafes: Array[Dictionary] = []


func rebuild(grid: BuildGrid, terminal: TerminalLayout) -> void:
	cafes.clear()
	var rooms := grid.room_ids()
	rooms.sort()
	var ids := grid.object_ids()
	ids.sort()
	var taken := {}
	for station in terminal.lanes:
		for cell in terminal.lanes[station]:
			taken[cell] = true
	for id in ids:
		var spot := grid.interaction_cell(id)
		if spot != BuildObjectDef.NO_CELL:
			taken[spot] = true
	for room_id in rooms:
		var status := RoomRules.status(grid, room_id)
		if status.type_id != &"cafe" or not status.ok:
			continue
		var area: Rect2i = grid.get_room(room_id)["rect"]
		var seats := _seats(grid, ids, area)
		var approaches := {}
		for seat in seats:
			approaches[seat["approach"]] = true
		var counters: Array[Dictionary] = []
		for id in ids:
			if grid.get_object(id)["def"] != &"cafe_counter" or not _inside(grid, id, area):
				continue
			var lane := _lane(grid, id, taken, approaches)
			for cell in lane:
				taken[cell] = true
			if not lane.is_empty():
				counters.append({"id": id, "lane": lane})
		if not counters.is_empty() and not seats.is_empty():
			cafes.append({"room": room_id, "counters": counters, "seats": seats})


## The cafe entry for a room, or an empty dictionary when it is not usable.
func cafe(room_id: int) -> Dictionary:
	for entry in cafes:
		if entry["room"] == room_id:
			return entry
	return {}


## A counter entry of a cafe, or an empty dictionary.
func counter(room_id: int, counter_id: int) -> Dictionary:
	for entry in cafe(room_id).get("counters", []):
		if entry["id"] == counter_id:
			return entry
	return {}


## A seat entry of a cafe by key, or an empty dictionary.
func seat(room_id: int, key: String) -> Dictionary:
	for entry in cafe(room_id).get("seats", []):
		if entry["key"] == key:
			return entry
	return {}


## Whether the whole footprint and interaction cell of an object lie in `area`
## (the rule RoomRules counts pieces by).
static func _inside(grid: BuildGrid, id: int, area: Rect2i) -> bool:
	var record := grid.get_object(id)
	var def := BuildCatalog.get_def(record["def"])
	for cell in def.footprint(record["anchor"], record["facing"]):
		if not area.has_point(cell):
			return false
	var spot := grid.interaction_cell(id)
	return spot == BuildObjectDef.NO_CELL or area.has_point(spot)


static func _seats(grid: BuildGrid, ids: Array[int], area: Rect2i) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in ids:
		var record := grid.get_object(id)
		var def := BuildCatalog.get_def(record["def"])
		if def.seats.is_empty() or not _inside(grid, id, area):
			continue
		for seat in def.seat_descriptors(record["anchor"], record["facing"]):
			if not grid.is_walkable(seat["approach"]):
				continue
			seat["key"] = "%d:%d" % [id, seat["index"]]
			seat["object_id"] = id
			out.append(seat)
	return out


static func _lane(
	grid: BuildGrid, counter_id: int, taken: Dictionary, approaches: Dictionary
) -> Array[Vector2i]:
	var lane: Array[Vector2i] = []
	var cell := grid.interaction_cell(counter_id)
	if not grid.is_walkable(cell) or approaches.has(cell):
		return lane
	var front := TerminalLayout.front_of(grid.get_object(counter_id)["facing"])
	lane.append(cell)
	while lane.size() < LANE_SLOTS:
		var next := cell + front
		if not grid.in_bounds(next) or taken.has(next) or approaches.has(next):
			break
		if not grid.can_route(cell, next):
			break
		lane.append(next)
		cell = next
	return lane
