class_name StaffBreakRooms
extends RefCounted
## Ready break rooms, rest spots inside them, and prestige-scaled recovery
## bonuses for StaffSim (Slice S3-P2b; decision b764f946).

const ROOM_TYPE := &"break_room"


static func is_ready(grid: BuildGrid, room_id: int) -> bool:
	if grid == null or room_id <= 0:
		return false
	var status := RoomRules.status(grid, room_id)
	return status != null and status.ok and status.type_id == ROOM_TYPE


static func ready_rooms(grid: BuildGrid) -> Array[int]:
	var out: Array[int] = []
	if grid == null:
		return out
	var ids := grid.room_ids()
	ids.sort()
	for id in ids:
		if is_ready(grid, id):
			out.append(id)
	return out


## Walkable floor cells inside ready break room `room_id`, non-interaction
## cells first so staff do not linger in doorways unless no other cell exists.
static func spots_in(grid: BuildGrid, room_id: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not is_ready(grid, room_id):
		return out
	var room := grid.get_room(room_id)
	var area: Rect2i = room["rect"]
	var interaction := {}
	for obj_id in grid.object_ids():
		var cell := grid.interaction_cell(obj_id)
		if cell != BuildObjectDef.NO_CELL:
			interaction[cell] = true
	var fallback: Array[Vector2i] = []
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var cell := Vector2i(x, y)
			if grid.room_at(cell) != room_id or not grid.is_walkable(cell):
				continue
			if interaction.has(cell):
				fallback.append(cell)
			else:
				out.append(cell)
	out.append_array(fallback)
	return out


static func recovery_bonus_percent(grid: BuildGrid, room_id: int) -> int:
	if not is_ready(grid, room_id):
		return 0
	var level := int(RoomPrestige.evaluate_room(grid, room_id)["level"])
	return RoomPrestige.break_recovery_bonus_percent(level)


## Nearest reachable spot in a ready break room for `m`: {"room", "spot", "path"},
## or {} if no ready break room is reachable. Prefers unoccupied rest spots.
static func nearest_break(staff: StaffSim, m: StaffMember) -> Dictionary:
	if staff == null or staff.sim == null or staff.sim.grid == null:
		return {}
	var grid := staff.sim.grid
	var rooms := ready_rooms(grid)
	if rooms.is_empty():
		return {}
	var taken := {}
	for id in staff.member_ids():
		if id == m.id:
			continue
		var other := staff.get_member(id)
		if other.is_on_break() and other.break_spot != StaffMember.NO_CELL:
			taken[other.break_spot] = true
	var best := {}
	var best_mm := 0
	for room_id in rooms:
		var spots := spots_in(grid, room_id)
		if spots.is_empty():
			continue
		var ordered: Array[Vector2i] = []
		for spot in spots:
			if not taken.has(spot):
				ordered.append(spot)
		if ordered.is_empty():
			ordered = spots
		for spot in ordered:
			var way := StaffPosts.path_in(staff, m, spot)
			if way.is_empty():
				continue
			var mm := Passenger.path_mm(way)
			if best.is_empty() or mm < best_mm:
				best = {"room": room_id, "spot": spot, "path": way}
				best_mm = mm
			break
	return best
