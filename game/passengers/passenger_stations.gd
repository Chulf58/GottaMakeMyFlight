class_name PassengerStations
extends RefCounted
## The station half of PassengerSim: choosing a desk or scanner, walking to it,
## joining and moving in its lane, the station's tick, closing a station and
## the estimates both the choice and the lateness forecast use. Static helpers
## over a sim's queues; the state stays on the sim.
##
## Full queues (decision full-queue-design-a-derived-hold-line-behind-each-
## lane-gives): a station is chosen only while its line (TerminalLayout.
## line_of()) has a cell for every passenger in or walking to its queue, and
## each queue member stands on its own line cell. Free places go to the
## passengers seeking that kind of station by how long they have waited:
## seekers_before(). When every open security line is full, a passenger done
## at check-in stays on the desk cell, still the desk's occupant, until a
## security place is free for it; the desk waits meanwhile.

## The ticks a lane's main position is held by the walk through its arch, at a
## walk (estimate()): a lane admits about every 29 ticks, unpack included
## (TestSecurityTierBalance's stream).
const LANE_ARCH_TICKS := 20


## Passengers in front of a newcomer to `station`: its lane, holding area and
## walkers on the way. At a desk the one being served is in the lane too.
static func slot(sim: PassengerSim, station: int) -> int:
	var count: int = sim._incoming.get(station, 0)
	if sim._queues.has(station):
		count += (sim._queues[station]["lane"] as Array).size()
		count += (sim._queues[station]["holding"] as Array).size()
	return count


## Ticks until a passenger who walks `walk_mm` to the back of `station`'s
## queue is done there (PassengerSim.station_eta()).
static func eta(sim: PassengerSim, station: int, walk_mm: int, p: Passenger = null) -> int:
	if not sim._is_open(station):
		return JourneyForecast.NEVER
	if sim.layout.passages.has(station):
		var candidate := p
		if candidate == null:
			candidate = Passenger.new()
			candidate.id = sim._next_id
		var join := sim.tick + candidate.pace_ticks(walk_mm) + 1
		return SecurityForecast.clearance(sim, station, candidate, join)
	var waiting := slot(sim, station)
	var left := 0
	if sim._queues.has(station) and sim._queues[station]["serving"] != 0:
		left = sim._serving_left(sim._queues[station])
		waiting -= 1
	var walk := p.pace_ticks(walk_mm) if p != null else JourneyForecast.walk_ticks(walk_mm)
	return (
		walk
		+ left
		+ maxi(waiting, 0) * PassengerSim.CHECKIN_TICKS
		+ PassengerSim.CHECKIN_TICKS
		+ QueueRipple.desk_waits(sim, station, null)
	)


## Ticks until the passenger's service at its current or next station ends
## (PassengerSim.wait_ticks()).
static func wait_ticks(sim: PassengerSim, p: Passenger) -> int:
	if StageKinds.leg(p.stage) == StageKinds.Leg.SECURITY:
		if p.station == 0 and not sim._any_open(sim.layout.scanners):
			return JourneyForecast.NEVER
		return SecurityRuntime.BASIC_SCAN_TICKS if p.station == 0 else SecurityForecast.eta(sim, p)
	if p.stage == Passenger.Stage.CHECKIN:
		return maxi(0, p.service_end - sim.tick)
	if p.station == 0 and not sim._any_open(sim.layout.desks):
		return JourneyForecast.NEVER
	if p.station == 0 or not sim._queues.has(p.station):
		return PassengerSim.CHECKIN_TICKS
	var q: Dictionary = sim._queues[p.station]
	var lane: Array = q["lane"]
	var holding: Array = q["holding"]
	var ahead: int = lane.size() + holding.size() + maxi(sim._incoming.get(p.station, 0) - 1, 0)
	if p.stage in PassengerSim.QUEUE_STAGES:
		var at := lane.find(p.id)
		ahead = at if at >= 0 else lane.size() + holding.find(p.id)
	if q["serving"] != 0:
		ahead -= 1
	var waits := QueueRipple.desk_waits(sim, p.station, p)
	return (
		sim._serving_left(q)
		+ maxi(ahead, 0) * PassengerSim.CHECKIN_TICKS
		+ PassengerSim.CHECKIN_TICKS
		+ waits
	)


## A station's tick: finished service, holding passengers moving into the
## lane, then the next admission. Security stations go to SecurityRuntime and
## are admitted after every station's step (GateCapacity.admit()).
static func step(sim: PassengerSim, station: int) -> void:
	var q := sim._queue(station)
	var cells: Array = sim.layout.lanes[station]
	if sim.layout.passages.has(station):
		sim.security.advance(station)
		promote(sim, q, cells)
		return
	if q["serving"] != 0:
		var served: Passenger = sim._by_id[q["serving"]]
		var done := sim.tick >= served.service_end and not served.is_moving()
		if done and not security_full(sim, served):
			q["serving"] = 0
			served.station = 0
			(q["lane"] as Array).erase(served.id)
			sim._set_stage(served, Passenger.Stage.TO_SECURITY)
			sim.checked_in.emit(served.id, station)
	promote(sim, q, cells)
	if q["serving"] != 0 or (q["lane"] as Array).is_empty() or not sim._is_open(station):
		return
	var front: Passenger = sim._by_id[q["lane"][0]]
	if front.at != cells[0] or front.is_moving():
		return
	q["serving"] = front.id
	front.service_end = sim.tick + PassengerSim.CHECKIN_TICKS
	sim._set_stage(front, Passenger.Stage.CHECKIN)


## Whether `p`, waiting where it is for want of a place (QUEUE_FULL), has
## one now: it chooses at once, not on its next beat, so a station that clears
## its line fast is not left idle.
static func _room_now(sim: PassengerSim, p: Passenger) -> bool:
	if p.stuck != Passenger.Stuck.QUEUE_FULL:
		return false
	var to_desk := p.stage == Passenger.Stage.TO_CHECKIN
	var room := _room(sim, sim.layout.desks if to_desk else sim.layout.scanners)
	return room > 0 and room > seekers_before(sim, p, to_desk)


## Whether passenger `p`, done at a desk, waits on it: a security station is
## open and every free place on the open security lines goes to a passenger
## who has waited longer (seekers_before()).
static func security_full(sim: PassengerSim, p: Passenger) -> bool:
	var room := _room(sim, sim.layout.scanners)
	return room >= 0 and room <= seekers_before(sim, p, false)


## The free places on the lines of the open, usable `stations`: cells no
## passenger in or walking to the queue has. -1 when none is open.
static func _room(sim: PassengerSim, stations: Array[int]) -> int:
	var room := -1
	for station in stations:
		if sim._is_open(station) and sim.layout.is_usable(station):
			var free := sim.layout.line_of(station).size() - slot(sim, station)
			room = maxi(room, 0) + maxi(free, 0)
	return room


## The passengers seeking a desk (`to_desk`) or a security station without
## one who have waited longer than `p`: by the tick they began waiting, then
## id (wait_key()). A security seeker is one done at a desk and still on it,
## or one walking to security with no station; a desk seeker walks to check-in
## with no desk. Seekers stuck for want of a route or of an open station are
## left out: they take no place.
static func seekers_before(sim: PassengerSim, p: Passenger, to_desk: bool) -> int:
	var mine := wait_key(p, to_desk)
	var count := 0
	for other in sim._passengers:
		if other != p and is_seeking(sim, other, to_desk) and wait_key(other, to_desk) < mine:
			count += 1
	return count


## Since when `p` has waited for a place: a security seeker since its
## check-in ended, a desk seeker since it turned to check-in; then its id.
static func wait_key(p: Passenger, to_desk: bool) -> Vector2i:
	return Vector2i(p.stage_tick if to_desk else p.service_end, p.id)


static func is_seeking(sim: PassengerSim, p: Passenger, to_desk: bool) -> bool:
	if not to_desk and p.stage == Passenger.Stage.CHECKIN:
		return sim.tick >= p.service_end
	var stage := Passenger.Stage.TO_CHECKIN if to_desk else Passenger.Stage.TO_SECURITY
	if p.stage != stage or p.station != 0:
		return false
	return p.stuck == Passenger.Stuck.NONE or p.stuck == Passenger.Stuck.QUEUE_FULL


static func promote(sim: PassengerSim, q: Dictionary, cells: Array) -> void:
	for moved in StationQueue.promote(q, cells):
		sim._by_id[moved].stuck = Passenger.Stuck.NONE


## Walking to a desk or scanner: choose one, walk there, join its lane.
static func seek(sim: PassengerSim, p: Passenger) -> void:
	if p.station != 0 and not sim._is_open(p.station):
		sim._leave_station(p)
	if p.station == 0:
		if p.stuck == Passenger.Stuck.NONE or sim._retry_now(p) or _room_now(sim, p):
			choose(sim, p)
		return
	# A committed walker is sent and joined by the line's pass (arrive()).


## The line rules for every committed walker before anyone steps
## (StationQueue.arrive()), as SecurityForecast plays them: walkers entering a
## line join its queue, the rest head for its tail, and one with no way there
## leaves its station and chooses again.
static func arrive(sim: PassengerSim) -> void:
	var walkers: Array[Passenger] = []
	var lines := {}
	for p in sim._passengers:
		if p.station == 0 or p.is_done():
			continue
		if p.stage != Passenger.Stage.TO_CHECKIN and p.stage != Passenger.Stage.TO_SECURITY:
			continue
		if not sim._is_open(p.station) or not sim.layout.is_usable(p.station):
			continue
		sim._queue(p.station)
		lines[p.station] = sim.layout.line_of(p.station)
		walkers.append(p)
	if walkers.is_empty():
		return
	var stranded: Array = []
	var joined := StationQueue.arrive(
		sim.grid,
		sim._queues,
		sim.layout.lanes,
		lines,
		walkers,
		sim._by_id,
		sim.tick,
		stranded,
		sim._claims
	)
	for p in joined:
		_joined(sim, p)
	for p: Passenger in stranded:
		sim._leave_station(p)
		choose(sim, p)


## The station choice's estimate for security station `station` in `sim`
## (estimate()), for `p` walking `walk_ticks` to its line.
static func sim_estimate(sim: PassengerSim, station: int, walk_ticks: int, p: Passenger) -> int:
	var walkers: Array[Passenger] = []
	for other in sim._passengers:
		if other != p and other.station == station and other.stage == Passenger.Stage.TO_SECURITY:
			walkers.append(other)
	var members := StationQueue.members(sim._queue(station))
	return estimate(sim.security, sim, station, members, walkers, walk_ticks, p)


## When `p`, walking `walk_ticks` to the back of security station `station`'s
## line, would be done at its main position: the station choice of the sim and
## of SecurityForecast alike (decision hold-line-rebuild-the-security-line-
## follows-where-people-sta, point 2; decision passenger-sim-design-bounded-
## queue-lanes-journey-forecast-committed-paths). A closed form, never a
## replay: the main position's current work, then each member of the queue
## (`members`, ids on `host`) and each walker committed to it (`walkers`)
## held there in turn (hold_ticks()), or the walk when that is longer, then
## its own hold. `runtime` is the station's SecurityRuntime.
static func estimate(
	runtime: SecurityRuntime,
	host: Object,
	station: int,
	members: Array,
	walkers: Array,
	walk_ticks: int,
	p: Passenger
) -> int:
	var lane := runtime.is_lane(station)
	var busy := 0
	var record := runtime.record_of(station)
	if not record.is_empty() and record["main"] != 0:
		var main: Passenger = host.get_passenger(record["main"])
		if SecurityRuntime.WORK_PHASES.has(main.security_phase as SecurityRuntime.Phase):
			var rate := maxi(1, runtime.rate(station, main.security_phase))
			@warning_ignore("integer_division")
			busy = (main.security_work + rate - 1) / rate
	for id: int in members:
		busy += hold_ticks(lane, host.get_passenger(id))
	for w: Passenger in walkers:
		busy += hold_ticks(lane, w)
	return maxi(walk_ticks, busy) + hold_ticks(lane, p)


## The ticks passenger `p` holds a station's main position: the scan at a basic
## scanner, the unpack and the walk through the arch at a lane.
static func hold_ticks(lane: bool, p: Passenger) -> int:
	if not lane:
		return SecurityRuntime.work_for(SecurityRuntime.Phase.SCAN, p)
	return SecurityRuntime.work_for(SecurityRuntime.Phase.UNPACK, p) + LANE_ARCH_TICKS


static func choose(sim: PassengerSim, p: Passenger) -> void:
	var to_desk := p.stage == Passenger.Stage.TO_CHECKIN
	var candidates := sim.layout.desks if to_desk else sim.layout.scanners
	if candidates.is_empty():
		p.stuck = Passenger.Stuck.NO_CHECKIN if to_desk else Passenger.Stuck.NO_SECURITY
		return
	var best := 0
	var best_eta := 0
	var best_path: Array[Vector2i] = []
	if not sim._any_open(candidates) and candidates.any(sim.layout.is_usable):
		# Usable but none staffed, so all closed: wait where you stand.
		p.stuck = Passenger.Stuck.NO_CHECKIN if to_desk else Passenger.Stuck.NO_SECURITY
		p.clear_path()
		return
	var room := _room(sim, candidates)
	if room >= 0 and room <= seekers_before(sim, p, to_desk):
		_wait_full(p)
		return
	var full := false
	# Ties go to the lower station id.
	var ordered := candidates.duplicate()
	ordered.sort()
	for station: int in ordered:
		if not sim._is_open(station):
			continue
		var line := sim.layout.line_of(station)
		var at := slot(sim, station)
		if at >= line.size():
			full = full or not line.is_empty()
			continue
		var path := StationQueue.approach(sim.grid, line, p.at, at)
		if path.is_empty():
			continue
		var station_eta := (
			eta(sim, station, Passenger.path_mm(path), p)
			if to_desk
			else sim_estimate(sim, station, p.pace_ticks(Passenger.path_mm(path)), p)
		)
		if best == 0 or station_eta < best_eta:
			best = station
			best_eta = station_eta
			best_path = path
	if best == 0:
		if full:
			_wait_full(p)
		else:
			p.stuck = Passenger.Stuck.NO_ROUTE
		return
	p.stuck = Passenger.Stuck.NONE
	p.station = best
	sim._incoming[best] = sim._incoming.get(best, 0) + 1
	p.set_path(best_path)


## Every line it could join is full, or its free places go to passengers who
## have waited longer: it waits where it is, finishing the step it is on.
static func _wait_full(p: Passenger) -> void:
	p.stuck = Passenger.Stuck.QUEUE_FULL
	if p.is_moving():
		var stop: Array[Vector2i] = []
		stop.assign(p.path.slice(0, p.path_index + 2))
		var index := p.path_index
		var walked := p.seg_mm
		p.path = stop
		p.path_index = index
		p.seg_mm = walked


static func join(sim: PassengerSim, p: Passenger) -> void:
	StationQueue.join(sim._queue(p.station), sim.layout.lanes[p.station], p.id)
	_joined(sim, p)


## `p` has just joined its station's queue: it walks there no longer.
static func _joined(sim: PassengerSim, p: Passenger) -> void:
	sim._incoming[p.station] = sim._incoming.get(p.station, 0) - 1
	var held := sim.holding_of(p.station).has(p.id)
	p.stuck = Passenger.Stuck.QUEUE_FULL if held else Passenger.Stuck.NONE
	var to_desk := p.stage == Passenger.Stage.TO_CHECKIN
	sim._set_stage(p, Passenger.Stage.CHECKIN_QUEUE if to_desk else Passenger.Stage.SECURITY_QUEUE)


## A queue member steps up to its place, line[index] (StationQueue.path_to()),
## under the QueueRipple rule.
static func queue_move(sim: PassengerSim, p: Passenger) -> void:
	var index := StationQueue.members(sim._queue(p.station)).find(p.id)
	if index < 0 or p.is_moving() or not QueueRipple.sim_may_step(sim, p):
		return
	var line := sim.layout.line_of(p.station)
	if p.at != line[index]:
		var path := StationQueue.path_to(sim.grid, line, p.at, index)
		if path.is_empty():
			requeue(sim, p)
		else:
			p.set_path(path)


## A queued passenger with no way back to its lane cell would hold up the
## passengers behind it. It leaves the queue and chooses a station again.
static func requeue(sim: PassengerSim, p: Passenger) -> void:
	sim._leave_station(p)
	sim._send_back(p)
	p.stuck = Passenger.Stuck.NO_ROUTE


## Brings the queues in line with the layout after an edit: a station that is
## gone sends its passengers back to choose again, a station without staff
## closes, a lane that got shorter moves its last passengers to the front
## of holding, and a line that got shorter sends back the passengers past its
## end to choose again, each finishing the step it is on.
static func reconcile(sim: PassengerSim) -> void:
	var stations: Array = sim._queues.keys()
	for station in sim.security.records.keys():
		if not stations.has(station):
			stations.append(station)
	stations.sort()
	for station in stations:
		var q: Dictionary = sim._queues.get(station, {"lane": [], "holding": [], "serving": 0})
		if not sim.layout.is_usable(station):
			var members: Array = (q["lane"] as Array) + (q["holding"] as Array)
			if q["serving"] != 0 and not members.has(q["serving"]):
				members.append(q["serving"])
			members.append_array(sim.security.drop(station))
			sim._queues.erase(station)
			for id in members:
				sim._send_back(sim._by_id[id])
			continue
		if not sim._queues.has(station):
			continue
		if not sim._is_open(station):
			close_queue(sim, station, q)
			continue
		fit_line(sim, station, q)


## Fits the queue of usable `station` and the walkers heading to it to its
## line as the layout now stands (after an edit, or on a load): a lane that got
## shorter moves its last members to the front of holding, the members past a
## shorter line's end are sent back to choose again, and a walker heading for
## a cell no longer on the line finishes the step it is on and then heads for
## the next free cell from there (seek()). Each sent back finishes its step.
static func fit_line(sim: PassengerSim, station: int, q: Dictionary) -> void:
	var cells: Array = sim.layout.lanes[station]
	while (q["lane"] as Array).size() > cells.size():
		var last: int = (q["lane"] as Array).pop_back()
		(q["holding"] as Array).push_front(last)
		sim._by_id[last].stuck = Passenger.Stuck.QUEUE_FULL
	var line := sim.layout.line_of(station)
	while StationQueue.size_of(q) > line.size():
		var out: Passenger = sim._by_id[(q["holding"] as Array).pop_back()]
		sim._send_back(out)
		_wait_full(out)
		out.stuck = Passenger.Stuck.NONE
	for p in sim._passengers:
		var walking := (
			p.stage == Passenger.Stage.TO_CHECKIN or p.stage == Passenger.Stage.TO_SECURITY
		)
		if walking and p.station == station and p.is_moving() and not line.has(p.path_end()):
			var stop: Array[Vector2i] = []
			stop.assign(p.path.slice(0, p.path_index + 2))
			if stop.size() < p.path.size():
				var index := p.path_index
				var walked := p.seg_mm
				p.path = stop
				p.path_index = index
				p.seg_mm = walked


## fit_line() for every usable station with a queue, as after a load.
static func fit_lines(sim: PassengerSim) -> void:
	var stations: Array = sim._queues.keys()
	stations.sort()
	for station: int in stations:
		if sim.layout.is_usable(station):
			fit_line(sim, station, sim._queues[station])


## A station without staff on duty: the passenger in service is finished (at
## a security station every admitted passenger, SecurityRuntime), and
## everyone else in its lane or holding list stops and chooses again.
static func close_queue(sim: PassengerSim, station: int, q: Dictionary) -> void:
	var serving: int = q["serving"]
	var members: Array = (q["lane"] as Array) + (q["holding"] as Array)
	members.erase(serving)
	q["lane"] = [serving] if serving != 0 and not sim.layout.passages.has(station) else []
	q["holding"] = []
	for id in members:
		var p: Passenger = sim._by_id[id]
		sim._send_back(p)
		p.clear_path()
