class_name JourneyForecast
extends RefCounted
## Whether a passenger will make its flight at a walk. The forecast covers the
## whole remaining journey: the committed path, the queue wait and service at
## the stations still ahead, the scanner passage, waiting at the gate until
## boarding opens, standing up, the walk to the nearest open exit and the
## apron walk to the plane door. Legs not yet planned use octile distance.
## Everything is at walking pace, so running raises the slack, and a gap
## between RUN_ON_SLACK and RUN_OFF_SLACK keeps the late flag from flickering.

## Start running when the forecast leaves less than this many ticks spare.
const RUN_ON_SLACK := 40
## Stop running only once this many ticks are spare again.
const RUN_OFF_SLACK := 240
## The forecast when no way to the plane exists.
const NEVER := 1000000


static func next_late(was_late: bool, slack: int) -> bool:
	if was_late:
		return slack < RUN_OFF_SLACK
	return slack < RUN_ON_SLACK


static func walk_ticks(mm: int) -> int:
	@warning_ignore("integer_division")
	return (maxi(mm, 0) + PassengerSim.WALK_MM - 1) / PassengerSim.WALK_MM


## The tick the passenger would reach the plane door at a walk.
static func arrival_tick(sim: PassengerSim, p: Passenger) -> int:
	var now := sim.tick
	if p.is_done():
		return p.outcome_tick
	if p.stage == Passenger.Stage.APRON:
		return now + walk_ticks(p.apron_total_mm() - p.apron_mm)
	if p.stage == Passenger.Stage.TO_EXIT and p.exit_object != 0:
		return now + walk_ticks(p.remaining_mm() + sim.apron_length_mm(p.exit_object))
	var leg := _to_gate(sim, p)
	if leg.x >= NEVER:
		return NEVER
	var leave := maxi(now + leg.x, p.boarding_tick)
	if p.stage == Passenger.Stage.TO_EXIT:
		leave = now
	match p.stage:
		Passenger.Stage.SITTING_DOWN, Passenger.Stage.SEATED:
			leave += PassengerSim.STAND_UP_TICKS
		Passenger.Stage.STANDING_UP:
			leave += maxi(0, PassengerSim.STAND_UP_TICKS - (now - p.stage_tick))
	var gate := Vector2i(leg.y, leg.z)
	return mini(leave + walk_ticks(_exit_mm(sim, gate)), NEVER)


## Ticks until the passenger stands at the gate (x), and the gate cell (y, z).
static func _to_gate(sim: PassengerSim, p: Passenger) -> Vector3i:
	var pos := p.path_end()
	var mm := p.remaining_mm()
	var wait := 0
	if p.stage <= Passenger.Stage.CHECKIN:
		# The scanner is chosen as station choice will: soonest estimated finish.
		var scanner := _soonest_scanner(sim, pos)
		if scanner.y == 0:
			return Vector3i(NEVER, pos.x, pos.y)
		wait += sim.wait_ticks(p) + scanner.x
		var passage: Array = sim.layout.passages[scanner.y]
		mm += _passage_mm(passage)
		pos = passage[passage.size() - 1]
	elif p.stage < Passenger.Stage.SECURITY:
		wait += sim.wait_ticks(p)
		var passage: Array = sim.layout.passages.get(p.station, [])
		if passage.is_empty():
			return Vector3i(NEVER, pos.x, pos.y)
		mm += Passenger.octile_mm(pos, passage[0]) + _passage_mm(passage)
		pos = passage[passage.size() - 1]
	elif p.stage == Passenger.Stage.SECURITY:
		wait += sim.wait_ticks(p)
	elif (
		p.stage
		in [Passenger.Stage.SITTING_DOWN, Passenger.Stage.SEATED, Passenger.Stage.STANDING_UP]
	):
		pos = p.seat_front
		mm = 0
	return Vector3i(walk_ticks(mm) + wait, pos.x, pos.y)


static func _passage_mm(passage: Array) -> int:
	var cells: Array[Vector2i] = []
	cells.assign(passage)
	return Passenger.path_mm(cells)


## The scanner with the soonest estimated finish for a passenger standing at
## `from` (the walk is octile, as no path exists yet) and that finish in ticks
## (x), and its id (y); id 0 when none is usable. Ties go to the lower id.
static func _soonest_scanner(sim: PassengerSim, from: Vector2i) -> Vector2i:
	var best := Vector2i.ZERO
	for id in sim.layout.scanners:
		if not sim.layout.is_usable(id):
			continue
		var walk_mm := Passenger.octile_mm(from, sim.layout.passages[id][0])
		var eta := sim.station_eta(id, walk_mm)
		if best.y == 0 or eta < best.x:
			best = Vector2i(eta, id)
	return best


## Octile distance to the nearest open exit plus its apron walk.
static func _exit_mm(sim: PassengerSim, from: Vector2i) -> int:
	var best := NEVER * PassengerSim.WALK_MM
	for door in sim.layout.open_exits(sim.grid):
		var mm := Passenger.octile_mm(from, sim.layout.door_cell(sim.grid, door))
		best = mini(best, mm + sim.apron_length_mm(door))
	return best
