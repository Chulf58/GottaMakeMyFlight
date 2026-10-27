class_name MissSignals
extends RefCounted
## Why passengers miss, read from PassengerSim for the queue-full and closed
## signs. It only reads the sim. A station is full when its lane is at capacity or
## passengers wait in its holding area (stuck QUEUE_FULL). A desk refills its
## lane from holding on the tick a slot frees, so a full desk stays full while
## anyone is held; a scanner can be one short for the rest of a tick, after it
## moves its front into the passage, and the holding count covers that tick.


static func is_full(capacity: int, lane: int, holding: int) -> bool:
	if capacity <= 0:
		return false
	return holding > 0 or lane >= capacity


## Station id -> passengers held outside its lane, for every full desk or
## scanner.
static func full_stations(sim: PassengerSim) -> Dictionary:
	var out := {}
	for station: int in sim.layout.lanes:
		var capacity := (sim.layout.lanes[station] as Array).size()
		var held := sim.holding_of(station).size()
		if is_full(capacity, sim.queue_of(station).size(), held):
			out[station] = held
	return out


## Every usable desk and scanner with nobody on duty (StaffSim.is_open()), in
## id order. A station the layout cannot use (walled in, no open passage) is
## broken rather than closed, so it is not listed. Without a StaffSim nothing is
## staffed by design, so nothing is listed.
static func closed_stations(sim: PassengerSim) -> Array[int]:
	var out: Array[int] = []
	if sim.staff == null:
		return out
	var stations: Array[int] = []
	stations.append_array(sim.layout.desks)
	stations.append_array(sim.layout.scanners)
	stations.sort()
	for station in stations:
		if sim.layout.is_usable(station) and not sim.staff.is_open(station):
			out.append(station)
	return out
