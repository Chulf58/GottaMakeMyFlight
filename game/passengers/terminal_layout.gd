class_name TerminalLayout
extends RefCounted
## What passengers use in a BuildGrid, derived from it after every edit:
## check-in desks and scanners with their queue lanes, scanner passages, gate
## seats and doors. Lanes are fixed and bounded: from a station's interaction
## cell (slot 0, where service happens) straight out along its front, up to
## LANE_SLOTS cells, stopping at a closed step, a cell another lane already
## took, another object's interaction cell or a staff spot (StaffSpots), which
## passengers may cross but never queue on. Stations claim cells in id order.
##
## A security lane (SecurityLanes) is one station keyed by its arch: a whole
## lane's arch is listed in scanners with its passage, and the cells it keeps
## clear (SecurityLanes.kept_clear_cells()) stop other queues like a staff
## spot. An arch without a whole lane is in neither list, so is_usable() is
## false for it.

const LANE_SLOTS := 6

var desks: Array[int] = []
var scanners: Array[int] = []
var entrances: Array[int] = []
var exits: Array[int] = []
## Station id -> lane cells, slot 0 first.
var lanes: Dictionary = {}
## Scanner id -> BuildGrid.passage_cells(), empty when the passage is closed.
var passages: Dictionary = {}
## One entry per seat: {key, object_id, cell, front, facing}, in id order.
var seats: Array[Dictionary] = []
## The security lanes, recognised anew on every rebuild, so a caller holding
## the previous instance can compare the two (SecurityLanes.broken()).
var security_lanes := SecurityLanes.new()


static func front_of(facing: int) -> Vector2i:
	return BuildObjectDef.rotate_offset(Vector2i(0, 1), facing)


func rebuild(grid: BuildGrid) -> void:
	desks.clear()
	scanners.clear()
	entrances.clear()
	exits.clear()
	lanes.clear()
	passages.clear()
	seats.clear()
	security_lanes = SecurityLanes.new()
	security_lanes.rebuild(grid)
	var ids := grid.object_ids()
	ids.sort()
	var reserved := {}
	for id in ids:
		var spot := grid.interaction_cell(id)
		if spot != BuildObjectDef.NO_CELL:
			reserved[spot] = id
	for id in ids:
		var staff_spot := StaffSpots.spot_of(grid, id)
		if staff_spot != BuildObjectDef.NO_CELL and not reserved.has(staff_spot):
			reserved[staff_spot] = id
	for arch in security_lanes.complete_arches():
		for cell in SecurityLanes.kept_clear_cells(security_lanes.lane(arch)):
			if not reserved.has(cell):
				reserved[cell] = arch
	for id in ids:
		match StringName(grid.get_object(id)["def"]):
			&"checkin_desk":
				desks.append(id)
			&"security_scanner":
				scanners.append(id)
				passages[id] = grid.passage_cells(id)
			&"security_arch":
				if security_lanes.is_complete(id):
					scanners.append(id)
					passages[id] = security_lanes.lane(id)["passage"]
			&"entrance_door":
				entrances.append(id)
			&"exit_door":
				exits.append(id)
			&"seat_row":
				_add_seats(grid, id)
	var taken := {}
	for id in ids:
		if desks.has(id) or scanners.has(id):
			lanes[id] = _lane(grid, id, reserved, taken)


## Whether passengers can be served at a station: it has a lane and, for a
## scanner, an open passage.
func is_usable(station: int) -> bool:
	if not lanes.has(station) or (lanes[station] as Array).is_empty():
		return false
	return not passages.has(station) or not (passages[station] as Array).is_empty()


func door_cell(grid: BuildGrid, door: int) -> Vector2i:
	var record := grid.get_object(door)
	return record["anchor"] if not record.is_empty() else BuildObjectDef.NO_CELL


## The grid step out of the terminal through a door: its back side.
func door_outward(grid: BuildGrid, door: int) -> Vector2i:
	return -front_of(grid.get_object(door)["facing"])


## An exit is open when nothing closes its outward edge: no wall on it, and
## no floor beyond it (the door must stand on the terminal's boundary).
func is_exit_open(grid: BuildGrid, door: int) -> bool:
	var cell := door_cell(grid, door)
	if cell == BuildObjectDef.NO_CELL:
		return false
	var out := door_outward(grid, door)
	if grid.has_wall(cell, BuildGrid.SIDE_STEP.find(out)):
		return false
	var beyond := cell + out
	return not grid.in_bounds(beyond) or grid.floor_at(beyond) == BuildGrid.FLOOR_NONE


func open_exits(grid: BuildGrid) -> Array[int]:
	var open: Array[int] = []
	for door in exits:
		if is_exit_open(grid, door):
			open.append(door)
	return open


func seat_index(key: String) -> int:
	for i in seats.size():
		if seats[i]["key"] == key:
			return i
	return -1


func _lane(
	grid: BuildGrid, station: int, reserved: Dictionary, taken: Dictionary
) -> Array[Vector2i]:
	var lane: Array[Vector2i] = []
	var cell := grid.interaction_cell(station)
	if cell == BuildObjectDef.NO_CELL or taken.has(cell) or not grid.is_walkable(cell):
		return lane
	var front := front_of(grid.get_object(station)["facing"])
	lane.append(cell)
	taken[cell] = true
	while lane.size() < LANE_SLOTS:
		var next := cell + front
		if not grid.in_bounds(next) or taken.has(next) or reserved.has(next):
			break
		if not grid.can_route(cell, next):
			break
		lane.append(next)
		taken[next] = true
		cell = next
	return lane


func _add_seats(grid: BuildGrid, id: int) -> void:
	var record := grid.get_object(id)
	var def := BuildCatalog.get_def(record["def"])
	var facing: int = record["facing"]
	var cells := def.footprint(record["anchor"], facing)
	for i in cells.size():
		var front := cells[i] + front_of(facing)
		if grid.is_walkable(front):
			seats.append(
				{
					"key": "%d:%d" % [id, i],
					"object_id": id,
					"cell": cells[i],
					"front": front,
					"facing": facing
				}
			)
