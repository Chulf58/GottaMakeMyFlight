class_name IncidentFault
extends RefCounted
## The scanner fault, a minor incident (decision scanner-fault-incident-
## design-stationfaults-beside-stationcl): one security station, a basic
## scanner or a lane's X-ray, stops admitting passengers until its repair,
## 20 to 40 game minutes after it fires (IncidentTuning.FAULT_MIN_TICKS to
## FAULT_MAX_TICKS). The fault itself is StaffSim's (StationFaults): its
## staff stay posted, its queue and the passengers walking to it choose again
## on the next tick, and it admits again on the repair tick.
##
## It may stop only a station that is open now and leaves its passengers
## somewhere to go (stations()): another open security station with a line,
## and for each passenger it would send away (one in its queue or holding
## list, or one walking to it) a way to that other line, found as
## PassengerStations.choose() finds it (StationQueue.set_off()). With none,
## the fault does not happen when it is due (done with NO_PLACE, no card).
##
## The station and the repair tick are drawn from the incident's own stream
## (IncidentRoll, purpose "fault:<id>": the station first, then the minutes),
## never from SimClock.rng, and kept in the plan {"station", "repair_tick"}.


## The stations a fault may stop now, in id order: every open security
## station whose passengers can each reach another open one.
static func stations(sim: PassengerSim) -> Array[int]:
	var out: Array[int] = []
	if sim.staff == null:
		return out
	var open: Array[int] = []
	for station: int in sim.layout.scanners:
		if sim._is_open(station) and not sim.layout.line_of(station).is_empty():
			open.append(station)
	open.sort()
	for station in open:
		var others := open.filter(func(other: int) -> bool: return other != station)
		if others.is_empty():
			continue
		var stranded := false
		for p in affected(sim, station):
			if not has_way(sim, p, others):
				stranded = true
				break
		if not stranded:
			out.append(station)
	return out


## The passengers a fault at `station` sends to choose again: those in its
## queue or holding list and those walking to it, in id order.
static func affected(sim: PassengerSim, station: int) -> Array[Passenger]:
	var out: Array[Passenger] = []
	for p in sim._passengers:
		if p.station != station:
			continue
		if p.stage == Passenger.Stage.TO_SECURITY or p.stage == Passenger.Stage.SECURITY_QUEUE:
			out.append(p)
	return out


## Whether `p` has a way from where it stands to the line of one of
## `others`, the way PassengerStations.choose() would walk it.
static func has_way(sim: PassengerSim, p: Passenger, others: Array) -> bool:
	for other: int in others:
		var line := sim.layout.line_of(other)
		var queue: Dictionary = sim._queues.get(other, {"lane": [], "holding": [], "serving": 0})
		var at := PassengerStations.slot(sim, other)
		if not StationQueue.set_off(sim.grid, queue, line, sim._by_id, p.at, at).is_empty():
			return true
	return false


## Fires `incident` on `tick`: picks its station and repair tick from its own
## stream of `world_seed`, stops the station (StationFaults.add()) and keeps both
## in its plan. False, changing nothing, when no station may fault.
static func fire(sim: PassengerSim, incident: Dictionary, world_seed: int, tick: int) -> bool:
	var eligible := stations(sim)
	if eligible.is_empty():
		return false
	var purpose := "fault:%d" % incident["id"]
	var draws := IncidentRoll.stream(
		world_seed, incident["roll_day"], IncidentCatalogue.VERSION, purpose
	)
	var station: int = eligible[draws.below(eligible.size())]
	var spread := IncidentTuning.FAULT_MAX_TICKS - IncidentTuning.FAULT_MIN_TICKS + 1
	var repair := tick + IncidentTuning.FAULT_MIN_TICKS + draws.below(spread)
	if not sim.staff.faults.add(station, repair):
		return false
	incident["plan"] = {"station": station, "repair_tick": repair}
	return true


## Whether the fault of active `incident` is repaired by `tick`.
static func is_over(incident: Dictionary, tick: int) -> bool:
	return tick >= int(incident["plan"]["repair_tick"])


## "" or why the saved incidents and the saved staff faults disagree: an
## active fault whose station is on `grid` must be among `faults`
## ([[station, repair tick], ...], StationFaults.live()) with its own repair
## tick. One whose station is gone has none (a save keeps no fault of it).
static func links_problem(incidents: Array, faults: Array, grid: BuildGrid) -> String:
	var by_station := {}
	for pair: Array in faults:
		by_station[int(pair[0])] = int(pair[1])
	for incident: Dictionary in incidents:
		if incident["kind"] != IncidentCatalogue.FAULT:
			continue
		if incident["state"] != IncidentCatalogue.ACTIVE:
			continue
		var station := int(incident["plan"]["station"])
		var repair := int(incident["plan"]["repair_tick"])
		if grid.get_object(station).is_empty():
			continue
		if by_station.get(station, -1) != repair:
			return (
				"incident %d: station %d is not saved faulted until %d"
				% [incident["id"], station, repair]
			)
	return ""
