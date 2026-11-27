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
			if (
				grid.room_at(cell) != room_id
				or not grid.is_walkable(cell)
				or grid.is_belt_cell(cell)
			):
				continue
			if interaction.has(cell):
				fallback.append(cell)
			else:
				out.append(cell)
	out.append_array(fallback)
	return out


## Reachable indoor seats inside ready break room `room_id`, in deterministic
## object_id and slot order. Each seat holds {"object_id", "index", "def",
## "cell", "approach", "front", "seat_pos", "yaw", "kind"}.
static func seats_in(grid: BuildGrid, room_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not is_ready(grid, room_id):
		return out
	var area: Rect2i = grid.get_room(room_id)["rect"]
	var ids := grid.object_ids()
	ids.sort()
	for obj_id in ids:
		var record := grid.get_object(obj_id)
		var def_id := StringName(record["def"])
		var def := BuildCatalog.get_def(def_id)
		if def == null:
			continue
		var facing: int = record["facing"]
		var cells := def.footprint(record["anchor"], facing)
		if not _cells_in_room(grid, area, room_id, cells):
			continue
		if def_id == &"lounge_sofa" or def_id == &"lounge_armchair":
			_append_activity_seats(grid, room_id, obj_id, record, cells, out)
		elif GateChairs.is_gate_seat_def(def_id):
			_append_gate_seats(grid, room_id, obj_id, record, def_id, cells, out)
		elif not def.seats.is_empty():
			_append_def_seats(grid, room_id, obj_id, record, def, def_id, out)
	return out


## Seat descriptor for resting staff at `spot` in `room_id`, adjusted for `role`,
## or {} if `spot` is a standing spot or its seat is gone.
static func seat_for(grid: BuildGrid, room_id: int, spot: Vector2i, role: int = -1) -> Dictionary:
	if grid == null or room_id <= 0 or spot == StaffMember.NO_CELL:
		return {}
	for seat in seats_in(grid, room_id):
		if seat["approach"] == spot:
			return _apply_role_seat_shift(seat, role)
	return {}


static func recovery_bonus_percent(grid: BuildGrid, room_id: int) -> int:
	if not is_ready(grid, room_id):
		return 0
	var level := int(RoomPrestige.evaluate_room(grid, room_id)["level"])
	return RoomPrestige.break_recovery_bonus_percent(level)


## Nearest reachable spot in a ready break room for `m`: {"room", "spot", "path"},
## or {} if no ready break room is reachable or every seat and floor spot is
## claimed. Prefers unoccupied indoor seats, then unoccupied standing floor spots.
static func nearest_break(staff: StaffSim, m: StaffMember) -> Dictionary:
	if staff == null or staff.sim == null or staff.sim.grid == null:
		return {}
	var grid := staff.sim.grid
	var rooms := ready_rooms(grid)
	if rooms.is_empty():
		return {}
	var taken := _taken_spots(staff, m.id)
	var seat_pick := _best_seat_break(staff, m, grid, rooms, taken)
	if not seat_pick.is_empty():
		return seat_pick
	return _best_floor_break(staff, m, grid, rooms, taken)


static func _taken_spots(staff: StaffSim, skip_id: int) -> Dictionary:
	var taken := {}
	for id in staff.member_ids():
		if id == skip_id:
			continue
		var other := staff.get_member(id)
		if other.is_on_break() and other.break_spot != StaffMember.NO_CELL:
			taken[other.break_spot] = true
	return taken


static func _best_seat_break(
	staff: StaffSim,
	m: StaffMember,
	grid: BuildGrid,
	rooms: Array[int],
	taken: Dictionary,
) -> Dictionary:
	var best := {}
	var best_mm := 0
	for room_id in rooms:
		var tried := {}
		for seat in seats_in(grid, room_id):
			var spot: Vector2i = seat["approach"]
			if taken.has(spot) or tried.has(spot):
				continue
			tried[spot] = true
			var way := StaffPosts.path_in(staff, m, spot)
			if way.is_empty():
				continue
			var mm := Passenger.path_mm(way)
			if best.is_empty() or mm < best_mm:
				best = {"room": room_id, "spot": spot, "path": way}
				best_mm = mm
	return best


static func _best_floor_break(
	staff: StaffSim,
	m: StaffMember,
	grid: BuildGrid,
	rooms: Array[int],
	taken: Dictionary,
) -> Dictionary:
	var best := {}
	var best_mm := 0
	for room_id in rooms:
		for spot in spots_in(grid, room_id):
			if taken.has(spot):
				continue
			var way := StaffPosts.path_in(staff, m, spot)
			if way.is_empty():
				continue
			var mm := Passenger.path_mm(way)
			if best.is_empty() or mm < best_mm:
				best = {"room": room_id, "spot": spot, "path": way}
				best_mm = mm
			break
	return best


static func _cells_in_room(
	grid: BuildGrid, area: Rect2i, room_id: int, cells: Array[Vector2i]
) -> bool:
	for cell in cells:
		if not area.has_point(cell) or grid.room_at(cell) != room_id:
			return false
	return true


static func _seat_approach_ok(
	grid: BuildGrid, room_id: int, seat_cell: Vector2i, approach: Vector2i
) -> bool:
	if (
		not grid.in_bounds(approach)
		or grid.room_at(approach) != room_id
		or not grid.is_walkable(approach)
		or grid.is_belt_cell(approach)
	):
		return false
	var side := BuildGrid.SIDE_STEP.find(seat_cell - approach)
	if side >= 0:
		var wall := grid.wall_kind(approach, side)
		return wall == BuildGrid.WallKind.NONE or wall == BuildGrid.WallKind.DOOR
	return true


static func _append_activity_seats(
	grid: BuildGrid,
	room_id: int,
	obj_id: int,
	record: Dictionary,
	cells: Array[Vector2i],
	out: Array[Dictionary],
) -> void:
	var facing: int = record["facing"]
	var front := TerminalLayout.front_of(facing)
	var yaw := atan2(float(front.x), float(front.y))
	for i in cells.size():
		var cell := cells[i]
		var approach := cell + front
		if not _seat_approach_ok(grid, room_id, cell, approach):
			continue
		var seat_pos := ActivityPoses.spot_of(grid, record, i)
		(
			out
			. append(
				{
					"object_id": obj_id,
					"index": i,
					"def": StringName(record["def"]),
					"cell": cell,
					"approach": approach,
					"front": front,
					"seat_pos": seat_pos,
					"yaw": yaw,
					"kind": &"activity",
				}
			)
		)


static func _append_gate_seats(
	grid: BuildGrid,
	room_id: int,
	obj_id: int,
	record: Dictionary,
	def_id: StringName,
	cells: Array[Vector2i],
	out: Array[Dictionary],
) -> void:
	var facing: int = record["facing"]
	var front := TerminalLayout.seat_front_of(def_id, facing)
	var yaw := atan2(float(front.x), float(front.y))
	for i in cells.size():
		if not GateChairs.has_chair(def_id, i):
			continue
		var cell := cells[i]
		var approach := cell + front
		if not _seat_approach_ok(grid, room_id, cell, approach):
			continue
		var seat_w := grid.cell_to_world(cell)
		var front_w := grid.cell_to_world(approach)
		var side := BuildObjectDef.rotate_point(GateChairs.chair_offset(def_id, i), facing)
		var seat_pos := (
			seat_w + (front_w - seat_w) * PassengerSim.SIT_FORWARD_M + Vector3(side.x, 0.0, side.y)
		)
		(
			out
			. append(
				{
					"object_id": obj_id,
					"index": i,
					"def": def_id,
					"cell": cell,
					"approach": approach,
					"front": front,
					"seat_pos": seat_pos,
					"yaw": yaw,
					"kind": &"gate_chair",
				}
			)
		)


static func _append_def_seats(
	grid: BuildGrid,
	room_id: int,
	obj_id: int,
	record: Dictionary,
	def: BuildObjectDef,
	def_id: StringName,
	out: Array[Dictionary],
) -> void:
	for seat in def.seat_descriptors(record["anchor"], record["facing"]):
		var cell: Vector2i = seat["cell"]
		var approach: Vector2i = seat["approach"]
		if not _seat_approach_ok(grid, room_id, cell, approach):
			continue
		var front: Vector2i = seat["facing"]
		(
			out
			. append(
				{
					"object_id": obj_id,
					"index": int(seat["index"]),
					"def": def_id,
					"cell": cell,
					"approach": approach,
					"front": front,
					"seat_pos": BuildObjectDef.seat_root_world(grid, seat),
					"yaw": atan2(float(front.x), float(front.y)),
					"kind": &"def_seat",
				}
			)
		)


static func _apply_role_seat_shift(seat: Dictionary, role: int) -> Dictionary:
	var out := seat.duplicate()
	var kind := StringName(seat.get("kind", &""))
	var def_id := StringName(seat.get("def", &""))
	var male := role == StaffMember.Role.SECURITY or role == StaffMember.Role.RAMP
	var front: Vector2i = seat["front"]
	var out_dir := Vector3(float(front.x), 0.0, float(front.y)).normalized()
	if kind == &"gate_chair":
		var shift := Vector2(0.03, 0.0) if male else Vector2(0.07, 0.02)
		out["seat_pos"] = (seat["seat_pos"] as Vector3) + out_dir * shift.x + Vector3.UP * shift.y
	elif kind == &"def_seat":
		if def_id == &"bar_counter":
			var lift := 0.15 if male else 0.17
			out["seat_pos"] = (seat["seat_pos"] as Vector3) + Vector3.UP * lift
		elif not male:
			var fwd := 0.02 if def_id == &"restaurant_booth" else 0.0
			out["seat_pos"] = (seat["seat_pos"] as Vector3) + out_dir * fwd + Vector3.UP * 0.02
	return out
