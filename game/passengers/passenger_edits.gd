class_name PassengerEdits
extends RefCounted
## How PassengerSim answers a grid edit: replanning a walker whose committed
## path was touched, rebuilding the layout and what derives from it, and the
## plane stand moving. Static helpers over a sim; the signal handlers stay
## methods on the sim.

const MAX_RECOVERY_STEPS := 8
const _STATION_OR_VISIT_OCCUPANCY := [
	Passenger.Stage.CHECKIN,
	Passenger.Stage.SECURITY,
	Passenger.Stage.CAFE_ORDER,
	Passenger.Stage.SHOP_BROWSE,
]


## An edit touched the committed path. Finish the current step if it is still
## open and plan on from its end; otherwise turn back to the cell just left,
## or step/relocate off a cell that is no longer a passenger cell.
## Arrival checks in each stage handle a target that is no longer reachable.
static func replan(sim: PassengerSim, p: Passenger) -> void:
	p.needs_replan = false
	if not _is_recoverable(p):
		return
	if not p.is_moving():
		if not _is_open_passenger_cell(sim.grid, p.at):
			_relocate_stationary(sim, p)
		return
	var target := p.path_end()
	var here := p.at
	var next := p.path[p.path_index + 1]
	var keep := p.seg_mm
	var path: Array[Vector2i] = []
	if not _is_open_passenger_cell(sim.grid, here):
		var recovered := _recover_from(sim, p, here, next)
		if recovered != Passenger.NO_CELL:
			keep = 0
			path = _route(sim, p, recovered, target)
	elif keep == 0:
		path = _route(sim, p, here, target)
	elif sim.grid.can_passenger_route(here, next):
		path = _route(sim, p, next, target)
		if path.is_empty():
			path.append(next)
		path.push_front(here)
	else:
		keep = Passenger.segment_mm(here, next) - keep
		p.at = next
		path = _route(sim, p, here, target)
		if path.is_empty():
			path.append(here)
		path.push_front(next)
	if path.size() < 2:
		p.clear_path()
		# No way on to its door: the walker chooses an exit again.
		if p.stage == Passenger.Stage.TO_EXIT and p.exit_object != 0:
			if p.at == sim.layout.door_cell(sim.grid, p.exit_object):
				if sim.files.holds(p.id):
					sim.files.reroute(sim, p)
			else:
				PassengerGates.drop_exit(sim, p)
		return
	p.set_path(path)
	p.seg_mm = keep
	if p.stage != Passenger.Stage.TO_EXIT or p.exit_object == 0:
		return
	# No way on to its door: it chooses an exit again (PassengerGates.to_exit()).
	if p.path_end() != sim.layout.door_cell(sim.grid, p.exit_object):
		PassengerGates.drop_exit(sim, p)
	# A new way to the door changes the walk left: the walker takes its place
	# in the door file again, or waits.
	elif sim.files.holds(p.id):
		sim.files.reroute(sim, p)


## Moves any recoverable passenger still standing on a non-passenger cell onto
## the nearest valid same-side passenger cell and replans its route.
static func recover_stranded(sim: PassengerSim) -> void:
	if sim.grid == null:
		return
	for p in sim._passengers:
		if p.is_done() or not _is_recoverable(p) or _is_open_passenger_cell(sim.grid, p.at):
			continue
		if (
			p.is_moving()
			and not p.needs_replan
			and _is_recovery_target(sim.grid, p.path[p.path_index + 1])
		):
			continue
		replan(sim, p)


static func _is_recoverable(p: Passenger) -> bool:
	return (
		StageKinds.location(p.stage) == StageKinds.Location.FLOOR
		and not _STATION_OR_VISIT_OCCUPANCY.has(p.stage)
	)


static func _recover_from(
	sim: PassengerSim, p: Passenger, here: Vector2i, next: Vector2i
) -> Vector2i:
	var dest := (
		next
		if p.seg_mm > 0 and _step_edge_open(sim.grid, here, next)
		else _recovery_cell(sim.grid, p, here)
	)
	if dest != Passenger.NO_CELL:
		_move_to_cell(sim, p, dest)
	return dest


static func _relocate_stationary(sim: PassengerSim, p: Passenger) -> void:
	var dest := _recovery_cell(sim.grid, p, p.at)
	if dest == Passenger.NO_CELL:
		return
	_move_to_cell(sim, p, dest)
	p.clear_path()
	if p.stage == Passenger.Stage.TO_EXIT and p.exit_object != 0:
		PassengerGates.drop_exit(sim, p)
		sim.files.waiters.forget(p.id)


static func _recovery_cell(grid: BuildGrid, p: Passenger, from: Vector2i) -> Vector2i:
	if not _is_security_object(grid, from):
		return _nearest_passenger_cell(grid, from)
	var obj := grid.object_at(from)
	var record := grid.get_object(obj)
	var def := BuildCatalog.get_def(record["def"])
	var seed := grid.interaction_cell(obj)
	if p.cleared:
		var back := BuildObjectDef.rotate_offset(Vector2i(0, -1), record["facing"])
		seed += back * (def.size.y + 1)
	if _is_recovery_target(grid, seed):
		return seed
	return _nearest_passenger_cell(grid, seed)


static func _move_to_cell(sim: PassengerSim, p: Passenger, cell: Vector2i) -> void:
	p.at = cell
	sim.standing.release(p.id)
	p.stand_from = Passenger.NO_CELL
	sim.files.waiters.forget(p.id)
	if p.stuck == Passenger.Stuck.NO_ROUTE and not sim.info_desks.holds(p):
		p.stuck = Passenger.Stuck.NONE


static func _nearest_passenger_cell(grid: BuildGrid, from: Vector2i) -> Vector2i:
	if not grid.in_bounds(from):
		return Passenger.NO_CELL
	var seen := {from: true}
	var queue: Array[Vector2i] = [from]
	var depth: Array[int] = [0]
	var head := 0
	while head < queue.size():
		var cur := queue[head]
		var d := depth[head]
		head += 1
		if d >= MAX_RECOVERY_STEPS:
			continue
		for step in BuildGrid.SIDE_STEP:
			var nxt := cur + step
			if not grid.in_bounds(nxt) or seen.has(nxt):
				continue
			if not _recovery_edge_open(grid, cur, nxt):
				continue
			if _is_recovery_target(grid, nxt):
				return nxt
			seen[nxt] = true
			queue.append(nxt)
			depth.append(d + 1)
	return Passenger.NO_CELL


static func _step_edge_open(grid: BuildGrid, from: Vector2i, to: Vector2i) -> bool:
	if _is_security_object(grid, from) or not _is_recovery_target(grid, to):
		return false
	var step := to - from
	if step == Vector2i.ZERO or absi(step.x) > 1 or absi(step.y) > 1:
		return false
	if step.x == 0 or step.y == 0:
		return _recovery_edge_open(grid, from, to)
	var across := from + Vector2i(step.x, 0)
	var down := from + Vector2i(0, step.y)
	return (
		_recovery_edge_open(grid, from, across)
		and grid.can_passenger_route(across, to)
		and _recovery_edge_open(grid, from, down)
		and grid.can_passenger_route(down, to)
	)


static func _recovery_edge_open(grid: BuildGrid, from: Vector2i, to: Vector2i) -> bool:
	var side := BuildGrid.SIDE_STEP.find(to - from)
	if side < 0 or grid.wall_kind(from, side) != BuildGrid.WallKind.NONE:
		return false
	if _is_security_object(grid, to):
		return false
	return not _crosses_door_back(grid, from, to) and not _crosses_door_back(grid, to, from)


static func _crosses_door_back(grid: BuildGrid, cell: Vector2i, outside: Vector2i) -> bool:
	var obj := grid.object_at(cell)
	if obj == 0:
		return false
	var record := grid.get_object(obj)
	if not BuildCatalog.is_door(record["def"]):
		return false
	return cell + DoorPlacement.back_step(record["facing"]) == outside


static func _is_security_object(grid: BuildGrid, cell: Vector2i) -> bool:
	var obj := grid.object_at(cell)
	return obj != 0 and BuildCatalog.is_security(grid.get_object(obj)["def"])


static func _is_open_passenger_cell(grid: BuildGrid, cell: Vector2i) -> bool:
	return grid.is_passenger_cell(cell) and not _is_security_object(grid, cell)


static func _is_recovery_target(grid: BuildGrid, cell: Vector2i) -> bool:
	if not _is_open_passenger_cell(grid, cell):
		return false
	for step in GridPathing.NEIGHBOURS:
		if grid.can_passenger_route(cell, cell + step):
			return true
	return false


## replan()'s path from `from` to `target`: a guest walking to its gate chair
## front (TO_GATE, the target its seat_front) walks round the other fronts as
## its seat claim did (GateRowWalk.path()); any other walk is the plain path.
static func _route(
	sim: PassengerSim, p: Passenger, from: Vector2i, target: Vector2i
) -> Array[Vector2i]:
	if p.stage == Passenger.Stage.TO_GATE and target == p.seat_front:
		return GateRowWalk.path(sim, from, target, p.seat_cell)
	return sim.grid.find_path(from, target)


static func graph_changed(sim: PassengerSim, cells: Array[Vector2i]) -> void:
	var touched := {}
	for cell in cells:
		touched[cell] = true
	for p in sim._passengers:
		if (
			p.stage == Passenger.Stage.MISSED
			and (
				p.missed_phase == Passenger.MissedPhase.TO_ENTRANCE
				or p.missed_phase == Passenger.MissedPhase.STUCK_WAIT
			)
		):
			p.needs_replan = true
			continue
		if (
			p.is_done()
			or p.stage == Passenger.Stage.SECURITY
			or p.stage == Passenger.Stage.APRON
			or p.stage == Passenger.Stage.ON_BUS
		):
			continue
		for i in range(p.path_index, p.path.size()):
			if touched.has(p.path[i]):
				p.needs_replan = true
				break
	var before := sim.layout.security_lanes
	sim.layout.rebuild(sim.grid)
	sim.files.clear_derived()
	# Rebuilt on the next tick (PassengerSim._reconcile), once however many edits came.
	sim.standing.stale = true
	# A lane that broke or changed (SecurityLanes.broken()) ends its service at
	# once: its admitted passengers go back to choosing, without clearance.
	for arch in SecurityLanes.broken(before, sim.layout.security_lanes):
		for id in sim.security.drop(arch):
			sim._send_back(sim._by_id[id])
	# The line outside the entrance takes its NO_ROUTE marks off first, so a
	# mark left after the check below is that check's own (EntranceLine.unmark()).
	sim.entrance.unmark(sim)
	sim.entrance.invalidate()
	# Walkers outside keep a walk that is still there, or stop (site only).
	OutsideWalks.revalidate(sim)


## The live plane stand moved (ApronStand): exits walk to its door from now
## on, so the doors' walks outside are found again, as after an edit.
static func set_stand(sim: PassengerSim, stand: Dictionary) -> void:
	sim.layout.stand = stand
	sim._on_graph_changed([] as Array[Vector2i])


## The gate stands changed (ApronStand with gate desks): each gate's exit
## walks to its own stand (exit id -> stand, exit id -> gate letter), and its
## passengers wait by its gate desk (gate letter -> desk object id).
static func set_gate_stands(
	sim: PassengerSim,
	exit_stands: Dictionary,
	exit_gates: Dictionary,
	gate_desk_ids: Dictionary,
	bus_exits: Dictionary = {}
) -> void:
	sim.layout.by_gate = true
	sim.layout.exit_stands = exit_stands
	sim.layout.exit_gates = exit_gates
	sim.layout.gate_desk_ids = gate_desk_ids
	sim.layout.bus_exits = bus_exits
	sim._on_graph_changed([] as Array[Vector2i])


## Any accepted edit: the standing spots are derived again on the next tick.
static func edit_applied(sim: PassengerSim) -> void:
	sim.standing.stale = true
	# A desk placed or taken away: the line's check-in room is found again.
	sim.entrance.invalidate()
	sim.files.clear_derived()
