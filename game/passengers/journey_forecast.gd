class_name JourneyForecast
extends RefCounted
## Whether a passenger will make its flight at a walk. The forecast covers the
## whole remaining journey: the committed path, the queue wait and service at
## the stations still ahead (after the road walk to the entrance, inside a
## terminal shell), security up to its exit (SecurityForecast, which walks the
## passage itself, so it is not added again here), waiting at the gate until
## boarding opens, standing up, the walk to the nearest open exit and the
## apron walk to the plane door, with the wait behind the walkers known now
## in the boarding files (BoardingFiles.queued()). Legs not yet planned use octile distance,
## which a wall can make far shorter than the real walk; a routed forecast
## (VisitForecast's) walks them along the grid's path instead, and a scanner
## or exit it cannot reach does not count. Everything is at walking pace, so
## running raises the slack, and a gap between RUN_ON_SLACK and RUN_OFF_SLACK
## keeps the late flag from flickering.

## Start running when the forecast leaves less than this many ticks spare.
const RUN_ON_SLACK := 40
## Stop running only once this many ticks are spare again.
const RUN_OFF_SLACK := 240
## The forecast when no way to the plane exists.
const NEVER := 1000000
## A walk that never ends, in millimetres.
const NEVER_MM := NEVER * PassengerSim.WALK_MM


static func next_late(was_late: bool, slack: int) -> bool:
	if was_late:
		return slack < RUN_OFF_SLACK
	return slack < RUN_ON_SLACK


static func walk_ticks(mm: int) -> int:
	@warning_ignore("integer_division")
	return (maxi(mm, 0) + PassengerSim.WALK_MM - 1) / PassengerSim.WALK_MM


## The tick the passenger would reach the plane door at a walk.
static func arrival_tick(sim: PassengerSim, p: Passenger) -> int:
	return arrival_from(sim, p, sim.tick)


## arrival_tick() for a passenger whose state holds from tick `now` on (a
## facility visit forecasts the journey after the visit this way). Queues and
## stations are read as they are on the sim's current tick. With `routed`, the
## walks not yet planned follow the grid's paths. With `in_files`, the wait in
## the boarding files behind the walkers known now is counted
## (BoardingFiles.queued()); without, the walk is the passenger's own.
## A passenger on a facility visit is its facility's to forecast (VisitForecast
## with the visit's own legs): asked here, it is an error and NEVER.
static func arrival_from(
	sim: PassengerSim, p: Passenger, now: int, routed := false, in_files := true
) -> int:
	if p.is_done():
		return p.outcome_tick
	if StageKinds.leg(p.stage) == StageKinds.Leg.VISIT:
		push_error(
			(
				"JourneyForecast: passenger %d is on a facility visit (%s); its facility forecasts it"
				% [p.id, Passenger.Stage.keys()[p.stage]]
			)
		)
		return NEVER
	var own := own_times(sim, p, now, routed)
	if own.is_empty():
		return NEVER
	if not in_files:
		return own["plane_tick"]
	return mini(sim.files.queued(sim, p, own), NEVER)


## The passenger's own way out with no wait in the boarding files: {"door":
## the exit door, "door_tick": the tick it reaches the door's cell (-1 once on
## the apron), "plane_tick": the tick it reaches the plane door, "plane": the
## plane's key (BoardingFiles.plane_key(), null with no walk outside), "trail":
## the distance out on the apron}; empty when it has no way to the plane.
static func own_times(sim: PassengerSim, p: Passenger, now: int, routed: bool) -> Dictionary:
	if p.stage == Passenger.Stage.APRON:
		var plane: Variant = null if p.apron.is_empty() else BoardingFiles.plane_key(p.apron.back())
		return {
			"door": p.exit_object,
			"door_tick": -1,
			"plane_tick": now + walk_ticks(p.apron_total_mm() - p.apron_mm),
			"plane": plane,
			"trail": p.apron_mm,
		}
	if p.stage == Passenger.Stage.TO_EXIT and p.exit_object != 0:
		var apron := sim.files.apron_of(sim, p.exit_object)
		return _times(
			p.exit_object,
			now + walk_ticks(p.remaining_mm()),
			now + walk_ticks(p.remaining_mm() + apron["mm"]),
			apron["plane"]
		)
	var leg := _to_gate(sim, p, routed)
	if leg.x >= NEVER:
		return {}
	var leave := maxi(now + leg.x, p.boarding_tick)
	if p.stage == Passenger.Stage.TO_EXIT:
		leave = now
	match p.stage:
		Passenger.Stage.SITTING_DOWN, Passenger.Stage.SEATED:
			leave += PassengerSim.STAND_UP_TICKS
		Passenger.Stage.STANDING_UP:
			leave += maxi(0, PassengerSim.STAND_UP_TICKS - (now - p.stage_tick))
	var exit := _exit_of(sim, Vector2i(leg.y, leg.z), routed)
	if exit.x == 0:
		return {}
	var plane_tick := leave + walk_ticks(exit.y + exit.z)
	if plane_tick >= NEVER:
		return {}
	var plane: Variant = sim.files.apron_of(sim, exit.x)["plane"]
	return _times(exit.x, leave + walk_ticks(exit.y), plane_tick, plane)


static func _times(door: int, door_tick: int, plane_tick: int, plane: Variant) -> Dictionary:
	return {
		"door": door, "door_tick": door_tick, "plane_tick": plane_tick, "plane": plane, "trail": 0
	}


## Ticks until the passenger stands at the gate (x), and the gate cell (y, z).
static func _to_gate(sim: PassengerSim, p: Passenger, routed: bool) -> Vector3i:
	var pos := p.path_end()
	var mm := p.remaining_mm()
	var wait := 0
	var road_ticks := 0
	if p.stage == Passenger.Stage.SPAWNED:
		# The road walk to the entrance, inside a terminal shell, is a leg of
		# its own: the walk drops leftover distance where it meets the grid.
		road_ticks = walk_ticks(p.apron_total_mm() - p.apron_mm)
	var leg := StageKinds.leg(p.stage)
	var choosing := p.stage == Passenger.Stage.TO_SECURITY and p.station == 0
	if leg == StageKinds.Leg.CHECKIN or choosing:
		# The scanner is chosen as station choice will: soonest clearance.
		var scanner := _soonest_scanner(sim, pos, p, routed)
		if scanner.y == 0:
			return Vector3i(NEVER, pos.x, pos.y)
		if not choosing:
			wait += sim.wait_ticks(p)
		wait += scanner.x
		pos = sim.security.exit_cell(scanner.y)
	elif leg == StageKinds.Leg.SECURITY:
		# Walking to, queuing at or inside its station: the replay walks it
		# all, up to the security exit.
		var clear := SecurityForecast.eta(sim, p)
		if clear >= NEVER:
			return Vector3i(NEVER, pos.x, pos.y)
		wait += clear
		mm = 0
		pos = sim.security.exit_cell(p.station)
	elif StageKinds.location(p.stage) == StageKinds.Location.GATE_SEAT:
		pos = p.seat_front
		mm = 0
	return Vector3i(road_ticks + walk_ticks(mm) + wait, pos.x, pos.y)


## The scanner where `p`, standing at `from`, is cleared soonest (the walk is
## octile, as no path is committed yet, or the grid's path when `routed`),
## with that clearance in ticks (x) and its id (y); id 0 when none is usable
## (or, routed, none can be walked to). Ties go to the lower id.
static func _soonest_scanner(
	sim: PassengerSim, from: Vector2i, p: Passenger, routed: bool
) -> Vector2i:
	var best := Vector2i.ZERO
	for id in sim.layout.scanners:
		if not sim.layout.is_usable(id):
			continue
		var walk_mm := _walk_mm(sim, from, sim.layout.passages[id][0], routed)
		if walk_mm >= NEVER_MM:
			continue
		var eta := sim.station_eta(id, walk_mm, p)
		if best.y == 0 or eta < best.x:
			best = Vector2i(eta, id)
	return best


## The open exit a passenger at `from` heads for, chosen as
## PassengerSim._choose_exit() chooses it: the shortest walk inside along the
## grid's path, ties to the earlier door in TerminalLayout.open_exits(). Its id
## (x) and that walk in mm (y); x is 0 when no open exit can be walked to.
static func nearest_exit(sim: PassengerSim, from: Vector2i) -> Vector2i:
	var best := Vector2i.ZERO
	for door in sim.layout.open_exits(sim.grid):
		var mm := sim.routes.walk_mm(from, sim.layout.door_cell(sim.grid, door))
		if mm < NEVER_MM and (best.x == 0 or mm < best.y):
			best = Vector2i(door, mm)
	return best


## The exit a passenger at `from` walks out of: its id (x, 0 when there is no
## way), the walk to its cell (y) and its apron walk to the plane (z).
## Unrouted: octile distance to each open exit, the least walk plus apron, ties
## to the earlier door in TerminalLayout.open_exits(). Routed: the exit
## nearest_exit() picks, as the passenger will, and that exit's apron.
static func _exit_of(sim: PassengerSim, from: Vector2i, routed: bool) -> Vector3i:
	if routed:
		var door := nearest_exit(sim, from)
		if door.x == 0:
			return Vector3i.ZERO
		return Vector3i(door.x, door.y, sim.files.apron_of(sim, door.x)["mm"])
	var best := Vector3i.ZERO
	for door in sim.layout.open_exits(sim.grid):
		var mm := Passenger.octile_mm(from, sim.layout.door_cell(sim.grid, door))
		var apron: int = sim.files.apron_of(sim, door)["mm"]
		if best.x == 0 or mm + apron < best.y + best.z:
			best = Vector3i(door, mm, apron)
	return best


## Millimetres from `from` to `to`: octile, or with `routed` the length of
## the grid's path (PassengerSim.routes), NEVER_MM when there is none.
static func _walk_mm(sim: PassengerSim, from: Vector2i, to: Vector2i, routed: bool) -> int:
	if not routed:
		return Passenger.octile_mm(from, to)
	return sim.routes.walk_mm(from, to)
