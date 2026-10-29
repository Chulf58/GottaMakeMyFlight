class_name ShopCounters
extends RefCounted
## The stations of shop staff (ruling store-mechanics-draw-a-room-then-
## furnish-it-required-pieces, point 3): the counters of ready cafes and
## kiosks, where a server stands at each, and whether a kiosk is open.
## StaffSim treats every counter here as a station of StaffMember.Role.SHOP,
## as it treats a desk as one of Role.CHECKIN: it is open only while a server
## is on duty on its staff spot and not leaving (StaffSim.is_open()).
##
## A counter counts while it stands wholly inside a ready room of its type
## (RoomRules, and the rule FacilitySlots.piece_inside() states): a
## cafe_counter in a cafe, a kiosk_counter in a kiosk.
##
## Its staff spot is derived from the grid and never stored or reserved in
## BuildGrid. The interior kit's Mount_Staff stands behind the till, but a room
## is often drawn with its counter against the room's edge, so the spot is the
## first cell of SPOTS (in the counter's frame) that is walkable floor of the
## same room, no object's interaction cell, not walled off from the counter
## and not the spot of a counter with a lower id in that room. A counter with
## no such cell can never be staffed (blocked()) and its Closed sign says so.
## An edit can move a spot; StaffSim then walks the server to the new one.
##
## An info desk (decision info-desk-helps-stuck-passengers-a-short-help-visit-
## with-a-m) is a counter that needs no room: it is usable wherever it stands,
## on open floor or inside any room, and is staffed from the same SHOP pool. Its
## staff spot is chosen the same way, on floor of the room it stands in (open
## floor when it stands in none). It belongs to no room's type, so a kiosk's
## room_open() never counts it.

## Counter piece -> the room type it works in (empty for a roomless counter).
const COUNTER_ROOMS := {
	&"cafe_counter": &"cafe",
	&"kiosk_counter": &"kiosk",
	&"info_desk": &"",
}
## The counters that need no room.
const ROOMLESS: Array[StringName] = [&"info_desk"]
## Where a server may stand, at facing 0 and in this order: behind the till,
## beside its west end, beside its east end; each with the footprint cell it
## works next to.
const SPOTS: Array[Array] = [
	[Vector2i(0, -1), Vector2i(0, 0)],
	[Vector2i(-1, 0), Vector2i(0, 0)],
	[Vector2i(2, 0), Vector2i(1, 0)],
]


static func is_counter(grid: BuildGrid, id: int) -> bool:
	var record := grid.get_object(id)
	return not record.is_empty() and COUNTER_ROOMS.has(StringName(record["def"]))


## Whether `id` is a counter that needs no room (an info desk).
static func is_roomless(grid: BuildGrid, id: int) -> bool:
	return is_counter(grid, id) and ROOMLESS.has(StringName(grid.get_object(id)["def"]))


## The room `counter` stands in, or 0 (also for an object that is no counter).
static func room_of(grid: BuildGrid, counter: int) -> int:
	if not is_counter(grid, counter):
		return 0
	return grid.room_at(grid.get_object(counter)["anchor"])


## Whether `counter` stands wholly inside a ready room of its type.
static func usable(grid: BuildGrid, counter: int) -> bool:
	if is_roomless(grid, counter):
		return true
	var room := room_of(grid, counter)
	if room == 0:
		return false
	var status := RoomRules.status(grid, room)
	var def_id := StringName(grid.get_object(counter)["def"])
	if not status.ok or status.type_id != COUNTER_ROOMS[def_id]:
		return false
	return FacilitySlots.piece_inside(grid, counter, grid.get_room(room)["rect"])


## Every usable counter, in id order.
static func counters(grid: BuildGrid) -> Array[int]:
	var ready := {}
	for room in grid.room_ids():
		var status := RoomRules.status(grid, room)
		if status.ok:
			ready[room] = status.type_id
	var ids := grid.object_ids()
	ids.sort()
	var out: Array[int] = []
	for id in ids:
		if is_roomless(grid, id):
			out.append(id)
			continue
		var room := room_of(grid, id)
		if room == 0:
			continue
		var def_id := StringName(grid.get_object(id)["def"])
		if ready.get(room, &"") != COUNTER_ROOMS[def_id]:
			continue
		if FacilitySlots.piece_inside(grid, id, grid.get_room(room)["rect"]):
			out.append(id)
	return out


## Where the server of `counter` stands, or BuildObjectDef.NO_CELL when no
## cell will do (or `counter` is no counter in a room).
static func spot(grid: BuildGrid, counter: int) -> Vector2i:
	var room := room_of(grid, counter)
	if room == 0 and not is_roomless(grid, counter):
		return BuildObjectDef.NO_CELL
	return _spots(grid, room).get(counter, BuildObjectDef.NO_CELL)


## Whether `counter` is a counter in a room with no cell a server can stand on.
static func blocked(grid: BuildGrid, counter: int) -> bool:
	var placed := room_of(grid, counter) != 0 or is_roomless(grid, counter)
	return placed and spot(grid, counter) == BuildObjectDef.NO_CELL


## Whether a passenger is being served at `counter` now: an order in progress
## at a cafe counter. A kiosk counter serves nobody itself (browsers pay as
## they finish), so a kiosk server fired leaves at once.
static func in_service(sim: PassengerSim, counter: int) -> bool:
	return sim.cafes.serving_at(counter) != 0


## Whether some counter in room `room_id` is open: a kiosk sells only then.
## Never without a StaffSim.
static func room_open(sim: PassengerSim, room_id: int) -> bool:
	if sim.staff == null:
		return false
	for counter in sim.staff.stations_of(StaffMember.Role.SHOP):
		if is_roomless(sim.grid, counter):
			continue
		if room_of(sim.grid, counter) == room_id and sim.staff.is_open(counter):
			return true
	return false


## Every usable counter that is not open, in id order, for the Closed signs.
## None without a StaffSim, as MissSignals.closed_stations() lists none.
static func closed(sim: PassengerSim) -> Array[int]:
	var out: Array[int] = []
	if sim.staff == null:
		return out
	for counter in sim.staff.stations_of(StaffMember.Role.SHOP):
		if not sim.staff.is_open(counter):
			out.append(counter)
	return out


## Counter id -> its staff spot, for every counter in room `room` that has one,
## handed out in counter id order.
static func _spots(grid: BuildGrid, room: int) -> Dictionary:
	var taken := {}
	var ids := grid.object_ids()
	ids.sort()
	for id in ids:
		var cell := grid.interaction_cell(id)
		if cell != BuildObjectDef.NO_CELL:
			taken[cell] = true
	var out := {}
	for id in ids:
		# Room 0 is open floor: only a roomless counter stands there.
		if room_of(grid, id) != room or (room == 0 and not is_roomless(grid, id)):
			continue
		var record := grid.get_object(id)
		var anchor: Vector2i = record["anchor"]
		var facing: int = record["facing"]
		for entry in SPOTS:
			var cell: Vector2i = anchor + BuildObjectDef.rotate_offset(entry[0], facing)
			var beside: Vector2i = anchor + BuildObjectDef.rotate_offset(entry[1], facing)
			if taken.has(cell) or grid.room_at(cell) != room or not grid.is_walkable(cell):
				continue
			if _walled(grid, cell, beside):
				continue
			out[id] = cell
			taken[cell] = true
			break
	return out


## Whether a plain or glass wall stands between `cell` and the footprint cell
## `beside` it.
static func _walled(grid: BuildGrid, cell: Vector2i, beside: Vector2i) -> bool:
	var kind := grid.wall_kind(cell, BuildGrid.SIDE_STEP.find(beside - cell))
	return kind == BuildGrid.WallKind.PLAIN or kind == BuildGrid.WallKind.GLASS
