class_name PassengerGates
extends RefCounted
## The gate and exit half of PassengerSim: claiming a seat or standing room at
## the gate, sitting and getting up, the pending walkers' admission to their
## boarding file, choosing an exit and stepping out onto the apron. Static
## helpers over a sim; the state stays on the sim.

## A body's width, in metres: how far a passenger stepping onto the boarding
## route stays from the walkers in the files.
const BODY_M := 0.45


## Gate access needs clearance: only a cleared passenger claims a seat.
static func to_gate(sim: PassengerSim, p: Passenger) -> void:
	if not p.cleared:
		push_error("PassengerSim: passenger %d reached the gate without clearance" % p.id)
		return
	if sim.tick >= p.boarding_tick:
		# Boarding is open: the walk to a gate place is cut, at the cell it
		# stands on (on a cell boundary) or the one it is walking to, and from
		# rest it steps onto the route when no filed walker is within a body's
		# width (the security exit cell: hand_off_clear()).
		if p.is_moving():
			if p.seg_mm == 0:
				p.clear_path()
			elif p.path.size() > p.path_index + 2:
				p.path = p.path.slice(0, p.path_index + 2)
		if not p.is_moving() and hand_off_clear(sim, p):
			sim._release_seat(p)
			sim._set_stage(p, Passenger.Stage.TO_EXIT)
		return
	if p.seat_object == 0:
		GateCapacity.to_spot(sim, p)
		return
	if p.is_moving():
		return
	if p.at == p.seat_front:
		p.clear_path()
		sim._set_stage(p, Passenger.Stage.SITTING_DOWN)
	else:
		sim._release_seat(p)


## Whether passenger `p`, about to turn to the exit from where it stands (the
## security exit cell, a gate seat's front cell), has a clear slot: no walker in
## a boarding file or waiting for one within a body's width, and none that can
## close in this tick within a run step more. Walkers that can close in are
## those on the move (walking, on the apron, or shifting to or from a wait
## spot) and those of `p`'s own flight; a stopped walker of another flight
## outside a body's width does not hold `p`, because the forecast does not
## model a wait for it. Nothing here waits on `p`: a filed or pending walker is
## never held for a passenger outside the files, so the wait ends.
static func hand_off_clear(sim: PassengerSim, p: Passenger) -> bool:
	var at := sim.world_position(p)
	var shifting := sim.files.waiters.ids()
	var near := BODY_M
	var reach := BODY_M + PassengerSim.RUN_MM / 1000.0
	for id in sim.passenger_ids():
		if id == p.id or not sim.files.holds(id):
			continue
		var other := sim.get_passenger(id)
		var moves := other.is_moving() or other.stage == Passenger.Stage.APRON
		# A waiter on its spot is free to walk back once admitted, which happens
		# before the tick's moves.
		var waiting := sim.files.is_pending(id) and sim.files.waiters.at_spot(other)
		moves = moves or (shifting.has(id) and not waiting)
		var there := sim.world_position(other)
		var apart := Vector2(at.x, at.z).distance_to(Vector2(there.x, there.z))
		if apart < (reach if moves or other.flight_id == p.flight_id else near):
			return false
	return true


## The cells of the gate desk of `p`'s flight, empty when there is none to
## wait near (GateReach).
static func gate_cells(sim: PassengerSim, p: Passenger) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if sim.layout.by_gate:
		out.assign(sim.layout.gate_desks.get(sim.flights.flight_gate(p.flight_id), out))
	return out


## Where a passenger with a gate seat stands on this tick, in world space.
static func seat_point(sim: PassengerSim, p: Passenger) -> Vector3:
	var front := sim.grid.cell_to_world(p.seat_front)
	var seat := sim.grid.cell_to_world(p.seat_cell)
	var spot := seat + (front - seat) * PassengerSim.SIT_FORWARD_M
	var shuffle := clampf((sim.tick - p.stage_tick) / float(PassengerSim.SHUFFLE_TICKS), 0.0, 1.0)
	if p.stage == Passenger.Stage.SITTING_DOWN:
		return front.lerp(spot, shuffle)
	if p.stage == Passenger.Stage.STANDING_UP:
		var left := PassengerSim.STAND_UP_TICKS - (sim.tick - p.stage_tick)
		return front.lerp(spot, clampf(left / float(PassengerSim.SHUFFLE_TICKS), 0.0, 1.0))
	return spot


## A walker setting off for the exit from its standing spot: on the spot until
## it moves, then walking from the spot to its path's next cell.
static func off_spot(sim: PassengerSim, p: Passenger) -> Vector3:
	var spot := sim.standing.world_of(sim.grid, sim.standing.spot_of(p.id))
	if not p.is_moving():
		return spot
	var next := p.path[p.path_index + 1]
	var t := p.seg_mm / float(Passenger.segment_mm(p.at, next))
	return spot.lerp(sim.grid.origin + Vector3(next.x + 0.5, 0.0, next.y + 0.5), t)


static func step_sitting(sim: PassengerSim, p: Passenger) -> void:
	if sim.tick - p.stage_tick >= PassengerSim.SIT_DOWN_TICKS:
		sim._set_stage(p, Passenger.Stage.SEATED)


## SEATED and STANDING at the gate: boarding starts, or a standing passenger
## looks for a seat.
static func step_waiting(sim: PassengerSim, p: Passenger) -> void:
	if sim.tick >= p.boarding_tick:
		var next := Passenger.Stage.STANDING_UP
		if p.stage == Passenger.Stage.STANDING:
			next = Passenger.Stage.TO_EXIT
		sim._set_stage(p, next)
	elif p.stage == Passenger.Stage.STANDING:
		GateCapacity.seat_from_spot(sim, p)


static func step_stand_up(sim: PassengerSim, p: Passenger) -> void:
	if sim.tick - p.stage_tick >= ParkRecovery.stand_up_ticks(p):
		var visit := StageKinds.visit_facility(sim, p)
		# Up for the exit: it stays on its front cell until no filed walker
		# is within a body's width (hand_off_clear()).
		var for_exit := visit == StageKinds.Facility.NONE and sim.tick >= p.boarding_tick
		if for_exit and not hand_off_clear(sim, p):
			return
		sim._release_seat(p)
		# Up for a facility visit, or (its visit dropped) back to the
		# gate while boarding has not started.
		match visit:
			StageKinds.Facility.CAFE:
				sim.cafes.depart(p)
			StageKinds.Facility.TOILET:
				sim.toilets.depart(p)
			StageKinds.Facility.SHOP:
				sim.shops.depart(p)
			_:
				if sim.tick < p.boarding_tick:
					sim._set_stage(p, Passenger.Stage.TO_GATE)
				else:
					sim._set_stage(p, Passenger.Stage.TO_EXIT)


## Brings seat claims and standing spots in line with the layout after an
## edit: a removed seat leaves its passenger standing, and a standing spot the
## edit removed is dropped.
static func reconcile_seats(sim: PassengerSim) -> void:
	for p in sim._passengers:
		ParkRecovery.note_sitting(sim, p)
		if p.seat_object != 0 and not GateRelocation.holds_seat(sim, p, sim._set_stage):
			sim._release_seat(p)
			if p.stage in [Passenger.Stage.SITTING_DOWN, Passenger.Stage.SEATED]:
				# Plans again: another seat or a standing spot (its roller collected
				# first when it had a roller, ParkRecovery).
				ParkRecovery.on_seat_lost(sim, p)
				p.clear_path()
				sim._set_stage(p, Passenger.Stage.TO_GATE)
	if sim.standing.stale:
		sim.standing.rebuild(sim)
		# A claim whose spot the edit removed is dropped; the passenger plans
		# again this tick.
		for id in sim.standing.drop_invalid():
			var p: Passenger = sim._by_id[id]
			p.stand_from = Passenger.NO_CELL
			# One setting off for the exit just walks on from its cell.
			if p.stage == Passenger.Stage.TO_EXIT:
				continue
			p.clear_path()
			sim._set_stage(p, Passenger.Stage.TO_GATE)


static func to_exit(sim: PassengerSim, p: Passenger) -> void:
	if p.exit_object != 0 and not exits_for(sim, p).has(p.exit_object):
		drop_exit(sim, p)
	if p.exit_object == 0:
		if p.stuck == Passenger.Stuck.NONE or sim._retry_now(p):
			choose_exit(sim, p)
		return
	# A pending walker waits for admit_pending(), at the start of a tick.
	if p.is_moving() or sim.files.is_pending(p.id):
		return
	if p.at == sim.layout.door_cell(sim.grid, p.exit_object):
		step_out(sim, p)
	else:
		drop_exit(sim, p)


## At its door, `p` steps out onto the apron if its apron file has room, or
## waits at the door (BoardingFiles.join_plane()).
static func step_out(sim: PassengerSim, p: Passenger) -> void:
	if not sim.files.join_plane(sim, p):
		return
	p.apron = (sim.files.apron_of(sim, p.exit_object, p)["points"] as Array).duplicate()
	p.apron_mm = 0
	sim._set_stage(p, Passenger.Stage.APRON)


## The exit choice is given up, and with it the place in the boarding files.
static func drop_exit(sim: PassengerSim, p: Passenger) -> void:
	p.exit_object = 0
	sim.files.leave(p.id)


## The pending walkers join their next file where they now fit, in
## BoardingFiles.pending_order(): before anyone steps, so each walks this tick.
static func admit_pending(sim: PassengerSim) -> void:
	for p in sim.files.pending_order(sim):
		# Its exit closed or went while it waited: it gives up its place and
		# chooses an exit again on its step (to_exit()).
		if not exits_for(sim, p).has(p.exit_object):
			drop_exit(sim, p)
		elif sim.files.door_of(p.id) != 0:
			step_out(sim, p)
		else:
			sim.files.join_door(sim, p)


## Every walker heading out with no exit yet chooses one and files or turns
## pending (to_exit()), in passenger-list order, before anyone steps: a walker
## early in the list that joined and walked first would step ahead of the
## walkers later in the list that file in front of it and hold it back. The
## walkers waiting on a re-plan are re-planned first, in the same order (as
## PassengerSim._step() would), so a re-filed one is in its file before anyone
## steps. A walker handled here is left out of to_exit() in its own step
## (sim._chose_exit): one advance a tick, so it steps out on the next tick.
## Those held back by a help visit keep to their own step.
static func choose_exits(sim: PassengerSim) -> void:
	sim._chose_exit.clear()
	for p in sim._passengers:
		if not p.is_done() and p.stage == Passenger.Stage.TO_EXIT and p.needs_replan:
			PassengerEdits.replan(sim, p)
	for p in sim._passengers:
		if (
			not p.is_done()
			and p.stage == Passenger.Stage.TO_EXIT
			and p.exit_object == 0
			and not p.needs_replan
			and not sim.info_desks.holds(p)
		):
			sim._chose_exit[p.id] = true
			to_exit(sim, p)


static func choose_exit(sim: PassengerSim, p: Passenger) -> void:
	var exits := exits_for(sim, p)
	if exits.is_empty():
		p.stuck = Passenger.Stuck.EXIT_BLOCKED
		p.clear_path()
		return
	# The routed forecasts price the same door (JourneyForecast.nearest_exit()).
	var door := JourneyForecast.nearest_exit(sim, p.at, p).x
	var path: Array[Vector2i] = []
	if door != 0:
		path = sim.grid.find_path(p.at, sim.layout.door_cell(sim.grid, door))
	if path.is_empty():
		p.stuck = Passenger.Stuck.NO_ROUTE
		return
	p.exit_object = door
	p.stuck = Passenger.Stuck.NONE
	p.set_path(path)
	sim.files.join_door(sim, p)


## The open exits `p` may leave by: with gates, its flight's gate's exit
## (TerminalLayout.open_exits_for()).
static func exits_for(sim: PassengerSim, p: Passenger) -> Array[int]:
	var gate := sim.flights.flight_gate(p.flight_id) if sim.layout.by_gate else ""
	return sim.layout.open_exits_for(sim.grid, gate)


## The walk from an exit door's cell to the plane door (OutsideWalks).
static func apron_points(sim: PassengerSim, exit_door: int) -> Array[Vector3]:
	return OutsideWalks.departure(sim, exit_door)


## The apron walk from an exit door to the plane, in millimetres.
static func apron_length_mm(sim: PassengerSim, exit_door: int) -> int:
	var walk := Passenger.new()
	walk.apron = apron_points(sim, exit_door)
	return walk.apron_total_mm()
