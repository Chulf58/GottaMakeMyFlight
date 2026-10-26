class_name MissSignals
extends RefCounted
## Why passengers miss, read from PassengerSim for the on-screen markers.
## It only reads the sim. A station is full when its lane is at capacity or
## passengers wait in its holding area (stuck QUEUE_FULL). A desk refills its
## lane from holding on the tick a slot frees, so a full desk stays full while
## anyone is held; a scanner can be one short for the rest of a tick, after it
## moves its front into the passage, and the holding count covers that tick.
## A passenger is marked late while its forecast says late and it has not
## yet made or missed the flight.


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


static func late_ids(sim: PassengerSim) -> Array[int]:
	var out: Array[int] = []
	for id in sim.passenger_ids():
		var p := sim.get_passenger(id)
		if p.late and not p.is_done():
			out.append(id)
	return out
