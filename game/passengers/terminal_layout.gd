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
## Every cell a passenger uses here passes the one eligibility rule,
## BuildGrid.is_passenger_cell(): walkable floor that walls close in. A lane
## head, a seat front, a passage cell or an exit door cell on floor that is
## not walled in is not in service.
##
## A security lane (SecurityLanes) is one station keyed by its arch: a whole
## lane's arch is listed in scanners with its passage, and the cells it keeps
## clear (SecurityLanes.kept_clear_cells()) stop other queues like a staff
## spot. An arch without a whole lane is in neither list, so is_usable() is
## false for it.
##
## On the airport site (`site`) an entrance or exit is in service only
## while it has a walk outside (SiteRoutes): an entrance to the road, an exit
## to the plane door at the live stand (`stand`, ApronStand). A door with none
## is listed in out_of_service, not refused, because building passes through
## such states (decision player-built-terminal-
## technical-design-site-plot-indoor-mask-passenger-eligibility, point 6).
##
## With gate desks (`by_gate`; decision gates-technical-design-gate-desks-
## link-to-north-exits-one-st, point 7) each gate's exit walks to its own
## gate's stand (exit_stands) and passengers leave only through the exit of
## their flight's gate (open_exits_for()); an exit no gate holds is out of
## service.

const LANE_SLOTS := 6

## The airport site whose open ground passengers walk outside, or null (in a
## Toon shell or a test grid), when no door needs a walk outside.
var site: SiteDefinition
## The live plane stand on a site (StandPlacement), set by ApronStand; empty
## means the starter stand (StandPlacement.starter_stand()).
var stand: Dictionary = {}
## Set by PassengerSim.set_gate_stands(): exits go by gate.
var by_gate := false
## With by_gate: exit door id -> the live stand of its gate, and exit door id
## -> that gate's letter.
var exit_stands: Dictionary = {}
var exit_gates: Dictionary = {}
## With by_gate: gate letter -> the cells of the gate desk linked to its exit
## (GateReach), found on each rebuild; a gate with no desk in reach is absent.
var gate_desks: Dictionary = {}
var desks: Array[int] = []
var scanners: Array[int] = []
## Every entrance door, in id order. Staff come in through any of them: staff
## access is physical.
var entrances: Array[int] = []
## The entrances passengers may come in through, in id order: those whose cell
## is a passenger cell (walled in) and, on a site, that have a walk in from the
## road. Passengers spawn and arrive only here.
var passenger_entrances: Array[int] = []
var exits: Array[int] = []
## On a site, door id -> its walk outside (SiteRoutes.door_cells()) for each
## entrance and exit that has one.
var outside_routes: Dictionary = {}
## On a site, the entrances and exits with no walk outside, in id order.
var out_of_service: Array[int] = []
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
	passenger_entrances.clear()
	exits.clear()
	outside_routes.clear()
	out_of_service.clear()
	lanes.clear()
	passages.clear()
	seats.clear()
	gate_desks = GateReach.desks_of(grid, exit_gates) if by_gate else {}
	security_lanes = SecurityLanes.new()
	security_lanes.rebuild(grid)
	var ids := grid.object_ids()
	ids.sort()
	_route_doors(grid, ids)
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
				passages[id] = _eligible_passage(grid, grid.passage_cells(id))
			&"security_arch":
				if security_lanes.is_complete(id):
					scanners.append(id)
					passages[id] = _eligible_passage(grid, security_lanes.lane(id)["passage"])
			&"entrance_door":
				entrances.append(id)
				if grid.is_passenger_cell(door_cell(grid, id)) and _has_way_out(id):
					passenger_entrances.append(id)
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


## An exit is open when its cell is a passenger cell (walled in) and nothing
## closes its outward edge: no wall on it, and no floor beyond it (the door
## must stand on the terminal's boundary). On a site it also needs its walk
## out to the plane.
func is_exit_open(grid: BuildGrid, door: int) -> bool:
	if not _has_way_out(door):
		return false
	var cell := door_cell(grid, door)
	if cell == BuildObjectDef.NO_CELL or not grid.is_passenger_cell(cell):
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


## The open exits a passenger of a flight at gate `gate` may leave by: with
## by_gate the open exit of that gate, if any; otherwise every open exit.
func open_exits_for(grid: BuildGrid, gate: String) -> Array[int]:
	var open := open_exits(grid)
	if not by_gate:
		return open
	return open.filter(func(door: int) -> bool: return exit_gates.get(door, "") == gate)


## The stand exits walk to on a site: `stand`, or the starter stand.
func live_stand(grid: BuildGrid) -> Dictionary:
	return stand if not stand.is_empty() else StandPlacement.starter_stand(grid, site)


## The stand exit `door` walks to: with by_gate its gate's ({} for an exit no
## gate holds), otherwise live_stand().
func stand_of(grid: BuildGrid, door: int) -> Dictionary:
	if by_gate:
		return exit_stands.get(door, {})
	return live_stand(grid)


## Whether door `door` has the walk outside a site asks for.
func _has_way_out(door: int) -> bool:
	return site == null or outside_routes.has(door)


## Finds each entrance's walk in from the road and each exit's walk out to the
## plane over the site's open ground; a door with none is out of service.
func _route_doors(grid: BuildGrid, ids: Array[int]) -> void:
	if site == null:
		return
	var fields := {}
	for id in ids:
		var record := grid.get_object(id)
		var def := StringName(record["def"])
		if def != &"entrance_door" and def != &"exit_door":
			continue
		var edge := SiteDefinition.PLANE_STEP
		var key: Variant = edge
		if def == &"entrance_door":
			edge = SiteDefinition.ROAD_STEP
			key = edge
			if not fields.has(key):
				var road := SiteRoutes.edge_cells(grid, site, edge)
				fields[key] = SiteRoutes.distances(grid, site, road)
		else:
			var to_stand := stand_of(grid, id)
			if to_stand.is_empty():
				out_of_service.append(id)
				continue
			key = StandPlacement.door_point(to_stand)
			if not fields.has(key):
				fields[key] = StandPlacement.to_door(grid, site, to_stand)
		var out := DoorPlacement.back_step(record["facing"])
		var cells := SiteRoutes.door_cells(grid, site, record["anchor"], out, edge, fields[key])
		if cells.is_empty():
			out_of_service.append(id)
		else:
			outside_routes[id] = cells


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
	if cell == BuildObjectDef.NO_CELL or taken.has(cell) or not grid.is_passenger_cell(cell):
		return lane
	var front := front_of(grid.get_object(station)["facing"])
	lane.append(cell)
	taken[cell] = true
	while lane.size() < LANE_SLOTS:
		var next := cell + front
		if not grid.in_bounds(next) or taken.has(next) or reserved.has(next):
			break
		if not grid.can_passenger_route(cell, next):
			break
		lane.append(next)
		taken[next] = true
		cell = next
	return lane


## `cells`, or empty (a closed passage) when any of them is not a passenger
## cell.
static func _eligible_passage(grid: BuildGrid, cells: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell: Vector2i in cells:
		if not grid.is_passenger_cell(cell):
			out.clear()
			return out
		out.append(cell)
	return out


func _add_seats(grid: BuildGrid, id: int) -> void:
	var record := grid.get_object(id)
	var def := BuildCatalog.get_def(record["def"])
	var facing: int = record["facing"]
	var cells := def.footprint(record["anchor"], facing)
	for i in cells.size():
		var front := cells[i] + front_of(facing)
		if grid.is_passenger_cell(front):
			seats.append(
				{
					"key": "%d:%d" % [id, i],
					"object_id": id,
					"cell": cells[i],
					"front": front,
					"facing": facing
				}
			)
