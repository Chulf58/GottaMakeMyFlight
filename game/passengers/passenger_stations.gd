class_name PassengerStations
extends RefCounted
## The station half of PassengerSim: choosing a desk or scanner, walking to it,
## joining and moving in its lane, the station's tick, closing a station and
## the estimates both the choice and the lateness forecast use. Static helpers
## over a sim's queues; the state stays on the sim.


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
		if sim.tick >= served.service_end and not served.is_moving():
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


static func promote(sim: PassengerSim, q: Dictionary, cells: Array) -> void:
	for moved in StationQueue.promote(q, cells):
		sim._by_id[moved].stuck = Passenger.Stuck.NONE


## Walking to a desk or scanner: choose one, walk there, join its lane.
static func seek(sim: PassengerSim, p: Passenger) -> void:
	if p.station != 0 and not sim._is_open(p.station):
		sim._leave_station(p)
	if p.station == 0:
		if p.stuck == Passenger.Stuck.NONE or sim._retry_now(p):
			choose(sim, p)
		return
	if p.is_moving():
		return
	if (sim.layout.lanes[p.station] as Array).has(p.at):
		join(sim, p)
	else:
		sim._leave_station(p)
		choose(sim, p)


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
	for station in candidates:
		if not sim._is_open(station):
			continue
		var cells: Array = sim.layout.lanes[station]
		var path := sim.grid.find_path(p.at, cells[mini(slot(sim, station), cells.size() - 1)])
		if path.is_empty():
			continue
		var station_eta := eta(sim, station, Passenger.path_mm(path), p)
		if best == 0 or station_eta < best_eta:
			best = station
			best_eta = station_eta
			best_path = path
	if best == 0:
		p.stuck = Passenger.Stuck.NO_ROUTE
		return
	p.stuck = Passenger.Stuck.NONE
	p.station = best
	sim._incoming[best] = sim._incoming.get(best, 0) + 1
	p.set_path(best_path)


static func join(sim: PassengerSim, p: Passenger) -> void:
	sim._incoming[p.station] = sim._incoming.get(p.station, 0) - 1
	if StationQueue.join(sim._queue(p.station), sim.layout.lanes[p.station], p.id):
		p.stuck = Passenger.Stuck.NONE
	else:
		p.stuck = Passenger.Stuck.QUEUE_FULL
	var to_desk := p.stage == Passenger.Stage.TO_CHECKIN
	sim._set_stage(p, Passenger.Stage.CHECKIN_QUEUE if to_desk else Passenger.Stage.SECURITY_QUEUE)


static func queue_move(sim: PassengerSim, p: Passenger) -> void:
	var index := (sim._queue(p.station)["lane"] as Array).find(p.id)
	if index < 0 or p.is_moving() or not QueueRipple.sim_may_step(sim, p):
		return
	var target: Vector2i = sim.layout.lanes[p.station][index]
	if p.at != target:
		var path := sim.grid.find_path(p.at, target)
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
## closes, and a lane that got shorter moves its last passengers to the front
## of holding.
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
		var cells: Array = sim.layout.lanes[station]
		while (q["lane"] as Array).size() > cells.size():
			var last: int = (q["lane"] as Array).pop_back()
			(q["holding"] as Array).push_front(last)
			sim._by_id[last].stuck = Passenger.Stuck.QUEUE_FULL


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
