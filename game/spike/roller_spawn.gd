extends RefCounted
## The roller draw shared by roller_trail_probe.gd and the probes that extend it
## (roller_park_walls_probe.gd, door_tuck_probe.gd). Each spawn_now() takes an
## entrance place, so a run of non-roller draws can fill the entrance; spawn_now()
## then returns 0 and get_passenger(0) is Nil (board e4be6104). Load with
## preload(); no class_name.

const MAX_DRAWS := 200


## A new guest of `sim` with a roller as bag 0, or null when the entrance has no
## room (the caller prints SPAWN_SKIPPED and skips the spawn).
static func draw(sim: PassengerSim) -> Passenger:
	var p: Passenger = null
	for attempt in MAX_DRAWS:
		var id := sim.spawn_now(FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0))
		if id == 0:
			return null
		p = sim.get_passenger(id)
		if SecurityLooks.bag_kind(p, 0) == SecurityLooks.Kind.ROLLER:
			break
		p.carry_on = 0
	return p
