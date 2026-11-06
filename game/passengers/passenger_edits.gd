class_name PassengerEdits
extends RefCounted
## How PassengerSim answers a grid edit: replanning a walker whose committed
## path was touched, rebuilding the layout and what derives from it, and the
## plane stand moving. Static helpers over a sim; the signal handlers stay
## methods on the sim.


## An edit touched the committed path. Finish the current step if it is still
## open and plan on from its end; otherwise turn back to the cell just left.
## Arrival checks in each stage handle a target that is no longer reachable.
static func replan(sim: PassengerSim, p: Passenger) -> void:
	p.needs_replan = false
	if not p.is_moving():
		return
	var target := p.path_end()
	var here := p.at
	var next := p.path[p.path_index + 1]
	var keep := p.seg_mm
	var path: Array[Vector2i] = []
	if keep == 0:
		path = sim.grid.find_path(here, target)
	elif sim.grid.can_passenger_route(here, next):
		path = sim.grid.find_path(next, target)
		if path.is_empty():
			path.append(next)
		path.push_front(here)
	else:
		keep = Passenger.segment_mm(here, next) - keep
		p.at = next
		path = sim.grid.find_path(here, target)
		if path.is_empty():
			path.append(here)
		path.push_front(next)
	if path.size() < 2:
		p.clear_path()
		# No way on to its door: the walker chooses an exit again.
		if p.stage == Passenger.Stage.TO_EXIT and p.exit_object != 0:
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


static func graph_changed(sim: PassengerSim, cells: Array[Vector2i]) -> void:
	var touched := {}
	for cell in cells:
		touched[cell] = true
	for p in sim._passengers:
		if p.is_done() or p.stage == Passenger.Stage.SECURITY or p.stage == Passenger.Stage.APRON:
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
	sim: PassengerSim, exit_stands: Dictionary, exit_gates: Dictionary, gate_desk_ids: Dictionary
) -> void:
	sim.layout.by_gate = true
	sim.layout.exit_stands = exit_stands
	sim.layout.exit_gates = exit_gates
	sim.layout.gate_desk_ids = gate_desk_ids
	sim._on_graph_changed([] as Array[Vector2i])


## Any accepted edit: the standing spots are derived again on the next tick.
static func edit_applied(sim: PassengerSim) -> void:
	sim.standing.stale = true
	sim.files.clear_derived()
