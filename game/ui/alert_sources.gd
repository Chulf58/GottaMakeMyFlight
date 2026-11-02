class_name AlertSources
extends RefCounted
## The causes of the alert cards that are read straight from the sim (AlertBoard
## holds the cause format). Each reuses the check the world already draws, so a
## card and the sign over the station never disagree:
## - a full check-in or security queue is MissSignals.full_stations(), less the
##   closed stations, exactly the stations with a red "Queue full" sign. One
##   card for all full desks and one for all full security lanes, pointing at
##   the fullest first; a queue that is full only for a moment does not raise
##   it (QUEUE_HOLD_TICKS each way).
## - passengers with no walkable route are the ones whose bubble says "I can't
##   get there" (Passenger.Stuck.NO_ROUTE): one card, pointing at them.
## The dirty terminal card is DirtyAlert.cause(), which keeps its own band.
## It only reads the sim.

const QUEUE_CHECKIN := &"queue_full_checkin"
const QUEUE_SECURITY := &"queue_full_security"
const NO_ROUTE := &"no_route"
## Three game minutes (one real second is one game minute at 1x).
const QUEUE_HOLD_TICKS := 3 * GameCalendar.TICKS_PER_MINUTE
## A stuck passenger re-plans now and then; a minute each way keeps a passing
## re-plan off the stack.
const ROUTE_HOLD_TICKS := GameCalendar.TICKS_PER_MINUTE
## The most places one card's clicks step through.
const MAX_TARGETS := 8


## The queue-full causes: none, one or both of QUEUE_CHECKIN and QUEUE_SECURITY.
static func queue_full(sim: PassengerSim) -> Array[Dictionary]:
	var full := MissSignals.full_stations(sim)
	# A closed station shows its Closed sign, not the queue-full one.
	for station in MissSignals.closed_stations(sim):
		full.erase(station)
	var desks: Array[int] = []
	var lanes: Array[int] = []
	for station: int in full:
		(desks if sim.layout.desks.has(station) else lanes).append(station)
	var out: Array[Dictionary] = []
	if not desks.is_empty():
		out.append(_queue_cause(sim, full, desks, QUEUE_CHECKIN, "Check-in queue full", "desk"))
	if not lanes.is_empty():
		out.append(_queue_cause(sim, full, lanes, QUEUE_SECURITY, "Security queue full", "lane"))
	return out


## The no-route cause, or none.
static func no_route(sim: PassengerSim) -> Array[Dictionary]:
	var targets: Array[Vector3] = []
	var count := 0
	for id in sim.passenger_ids():
		var p := sim.get_passenger(id)
		if p.is_done() or p.stuck != Passenger.Stuck.NO_ROUTE:
			continue
		count += 1
		if targets.size() < MAX_TARGETS:
			var at := sim.world_position(p)
			targets.append(Vector3(at.x, 0.0, at.z))
	if count == 0:
		return []
	var who := "1 passenger can't" if count == 1 else "%d passengers can't" % count
	return [
		{
			"key": NO_ROUTE,
			"title": "No walkable route",
			"detail": "%s get where they are going" % who,
			"targets": targets,
			"show_after": ROUTE_HOLD_TICKS,
			"clear_after": ROUTE_HOLD_TICKS,
		}
	]


## The ground point under the middle of object `id`'s footprint.
static func object_point(grid: BuildGrid, id: int) -> Vector3:
	var record := grid.get_object(id)
	var def := BuildCatalog.get_def(StringName(record["def"]))
	var cells := def.footprint(record["anchor"], record["facing"])
	var centre := BuildView.object_transform(grid, cells, record["facing"]).origin
	return Vector3(centre.x, 0.0, centre.z)


## One card for `stations` (all full, ids of one kind): fullest first, then by id.
static func _queue_cause(
	sim: PassengerSim,
	full: Dictionary,
	stations: Array[int],
	key: StringName,
	title: String,
	noun: String
) -> Dictionary:
	stations.sort_custom(
		func(a: int, b: int) -> bool: return full[a] > full[b] or (full[a] == full[b] and a < b)
	)
	var held := 0
	var targets: Array[Vector3] = []
	for station in stations:
		held += int(full[station])
		if targets.size() < MAX_TARGETS:
			targets.append(object_point(sim.grid, station))
	var detail := "%d %s%s full" % [stations.size(), noun, "" if stations.size() == 1 else "s"]
	if held > 0:
		detail += " · +%d waiting" % held
	return {
		"key": key,
		"title": title,
		"detail": detail,
		"targets": targets,
		"show_after": QUEUE_HOLD_TICKS,
		"clear_after": QUEUE_HOLD_TICKS,
	}
