class_name AlertSources
extends RefCounted
## The causes of the alert cards that are read straight from the sim (AlertBoard
## holds the cause format). Each reuses the check the world already draws, so a
## card and the sign over the station never disagree:
## - a full check-in or security queue is MissSignals.full_stations(), less the
##   closed stations, exactly the stations with a queue-full sign. One
##   card for all full desks and one for all full security lanes, pointing at
##   the fullest first; a queue that is full only for a moment does not raise
##   it (QUEUE_HOLD_TICKS each way). When a full station's lane is shorter than
##   TerminalLayout.LANE_SLOTS, the detail says the queue is short and to move
##   the station away from the wall (decision first-time-hints-gain-place-
##   gate-desk-and-place-seats-the-hi): such a lane fills at one or two waiting.
## - passengers with no walkable route are the ones whose bubble says "I can't
##   get there" (Passenger.Stuck.NO_ROUTE): one card, pointing at them.
## - passengers waiting for a gate place (GateCapacity.shortage()): one card,
##   pointing at them.
## - stations closed with nobody on duty, and stations whose staff spot staff
##   cannot use (closed_stations()): one card each, pointing at them. The
##   nobody-on-duty card asks to hire only for stations nobody is assigned to;
##   when every such station has a hired member walking to it, it says they
##   are on the way.
## The dirty terminal card is DirtyAlert.cause(), which keeps its own band.
## It only reads the sim.

const QUEUE_CHECKIN := &"queue_full_checkin"
const QUEUE_SECURITY := &"queue_full_security"
const NO_ROUTE := &"no_route"
const GATE_FULL := &"gate_full"
const NO_STAFF := &"stations_no_staff"
const STAFF_SPOT := &"staff_spot_unusable"
const RAMP_BAGGAGE := &"ramp_baggage"
const RAMP_PUSHBACK := &"ramp_pushback"
const BAGGAGE_CONNECT := &"baggage_connect"
const CHARTER_GAP := &"charter_gap"
## Three game minutes (one real second is one game minute at 1x).
const QUEUE_HOLD_TICKS := 3 * GameCalendar.TICKS_PER_MINUTE
## A stuck passenger re-plans now and then; a minute each way keeps a passing
## re-plan off the stack.
const ROUTE_HOLD_TICKS := GameCalendar.TICKS_PER_MINUTE
## The most places one card's clicks step through.
const MAX_TARGETS := 8

## The words are built in static functions, which cannot call tr() (an Object
## method), so they go through this instance's tr() and tr_n().
static var _translator := RefCounted.new()


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
		var detail := (
			(
				_translator
				. tr_n(
					"{count} desk full · {waiting} waiting · short queue: move the desk away from the wall",
					"{count} desks full · {waiting} waiting · short queue: move a desk away from the wall",
					desks.size()
				)
			)
			if _any_short(sim, desks)
			else _translator.tr_n(
				"{count} desk full · {waiting} waiting",
				"{count} desks full · {waiting} waiting",
				desks.size()
			)
		)
		var title := _translator.tr("Check-in queue full")
		out.append(_queue_cause(sim, full, desks, QUEUE_CHECKIN, title, detail))
	if not lanes.is_empty():
		var detail := (
			(
				_translator
				. tr_n(
					"{count} lane full · {waiting} waiting · short queue: move the scanner away from the wall",
					"{count} lanes full · {waiting} waiting · short queue: move a scanner away from the wall",
					lanes.size()
				)
			)
			if _any_short(sim, lanes)
			else _translator.tr_n(
				"{count} lane full · {waiting} waiting",
				"{count} lanes full · {waiting} waiting",
				lanes.size()
			)
		)
		var title := _translator.tr("Security queue full")
		out.append(_queue_cause(sim, full, lanes, QUEUE_SECURITY, title, detail))
	return out


## Whether any of `stations` has a lane shorter than a full one
## (TerminalLayout.LANE_SLOTS): a wall, a door or another lane cut it short.
static func _any_short(sim: PassengerSim, stations: Array[int]) -> bool:
	for station in stations:
		if (sim.layout.lanes[station] as Array).size() < TerminalLayout.LANE_SLOTS:
			return true
	return false


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
	var detail := _translator.tr_n(
		"{count} passenger can't get where they are going",
		"{count} passengers can't get where they are going",
		count
	)
	return [
		{
			"key": NO_ROUTE,
			"title": _translator.tr("No walkable route"),
			"detail": detail.format({"count": count}),
			"targets": targets,
			"show_after": ROUTE_HOLD_TICKS,
			"clear_after": ROUTE_HOLD_TICKS,
		}
	]


## The gate-full cause, or none: passengers waiting for a gate seat or
## standing spot (GateCapacity.shortage()), at a security queue front, inside
## security or on the way to the gate. One card, pointing at them. It is a
## card only, with no sign in the world (the queue-full sign, decision
## queue-full-marker-a-red-sign-with-a-queue-full-n-waiting-cap, still shows
## over a security queue that fills behind a held front).
static func gate_full(sim: PassengerSim) -> Array[Dictionary]:
	var held := sim.gates.shortage(sim)
	if held.is_empty():
		return []
	var targets: Array[Vector3] = []
	for id in held:
		if targets.size() < MAX_TARGETS:
			var at := sim.world_position(sim.get_passenger(id))
			targets.append(Vector3(at.x, 0.0, at.z))
	var detail := _translator.tr_n(
		"{count} passenger waits for a gate seat or a place to stand",
		"{count} passengers wait for a gate seat or a place to stand",
		held.size()
	)
	return [
		{
			"key": GATE_FULL,
			"title": _translator.tr("Gate full"),
			"detail": detail.format({"count": held.size()}),
			"targets": targets,
			"show_after": ROUTE_HOLD_TICKS,
			"clear_after": ROUTE_HOLD_TICKS,
		}
	]


## The closed-station causes: none, one or both of NO_STAFF (desks, scanners
## and shop counters with nobody on duty) and STAFF_SPOT (their staff spot is
## blocked or staff have no way to it), read from the same reasons as the
## station signs (MissSignals.staff_reason), so the station's words that moved
## into its hover tooltip still reach the player (decision calm-view-technical-
## design-shared-hover-target-reusing-click, part 3). A station the player
## closed is left out: closing it was their choice. Pointing at the stations in
## id order. Nothing without a StaffSim.
static func closed_stations(sim: PassengerSim) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if sim.staff == null:
		return out
	var stations := MissSignals.closed_stations(sim)
	stations.append_array(ShopCounters.closed(sim))
	stations.sort()
	var idle: Array[int] = []
	var coming: Array[int] = []
	var spots: Array[int] = []
	for station in stations:
		match MissSignals.staff_reason(sim, station):
			MissSignals.NO_STAFF_REASON:
				(coming if _member_walking_to(sim, station) else idle).append(station)
			MissSignals.SPOT_BLOCKED_REASON, MissSignals.UNREACHABLE_REASON:
				spots.append(station)
	if not idle.is_empty() or not coming.is_empty():
		# Hiring is asked only for stations nobody is assigned to; when every
		# closed station has a member walking to it, the card says so instead.
		var detail := (
			_translator.tr_n(
				"{count} station is closed · hire staff on the Staff card",
				"{count} stations are closed · hire staff on the Staff card",
				idle.size()
			)
			if not idle.is_empty()
			else _translator.tr_n(
				"{count} station is closed · staff are on the way",
				"{count} stations are closed · staff are on the way",
				coming.size()
			)
		)
		var shown := idle if not idle.is_empty() else coming
		var title := _translator.tr("Nobody on duty")
		out.append(
			_station_cause(
				sim,
				shown,
				NO_STAFF,
				title,
				detail.format({"count": shown.size()}),
				QUEUE_HOLD_TICKS
			)
		)
	if not spots.is_empty():
		var detail := _translator.tr_n(
			"{count} station is closed · staff can't reach the staff spot",
			"{count} stations are closed · staff can't reach the staff spot",
			spots.size()
		)
		var title := _translator.tr("Staff can't get to work")
		out.append(
			_station_cause(
				sim,
				spots,
				STAFF_SPOT,
				title,
				detail.format({"count": spots.size()}),
				ROUTE_HOLD_TICKS
			)
		)
	return out


static func ramp(
	sim: PassengerSim, baggage: BaggageSim = null, dispatch: RampDispatch = null
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if sim == null or sim.staff == null:
		return out
	var resolved_dispatch := dispatch if dispatch != null else sim.staff.ramp_dispatch
	var resolved_baggage := baggage
	if resolved_baggage == null and resolved_dispatch != null:
		resolved_baggage = resolved_dispatch.baggage
	if resolved_baggage != null:
		var waiting_carts := resolved_baggage.waiting_for_ramp_carts()
		if not waiting_carts.is_empty():
			var reason := resolved_baggage.waiting_for_ramp_reason(sim.staff)
			if reason == "none_hired" or reason == "all_busy":
				var targets: Array[Vector3] = []
				for cart_id in waiting_carts:
					if targets.size() >= MAX_TARGETS:
						break
					targets.append(object_point(sim.grid, cart_id))
				var detail := (
					_translator.tr("No ramp agents hired · hire one on Staff")
					if reason == "none_hired"
					else _translator.tr("All ramp agents busy · hire another on Staff")
				)
				(
					out
					. append(
						{
							"key": RAMP_BAGGAGE,
							"title": _translator.tr("Ramp agent needed for baggage"),
							"detail": detail,
							"targets": targets,
							"show_after": 0,
							"clear_after": ROUTE_HOLD_TICKS,
							"coral": true,
						}
					)
				)
	if resolved_dispatch != null:
		var emergencies := resolved_dispatch.recent_emergencies()
		if not emergencies.is_empty():
			var targets: Array[Vector3] = []
			for entry in emergencies:
				var stand: Dictionary = entry.get("stand", {})
				if stand.is_empty():
					continue
				var pt := StandPlacement.stand_point(stand)
				var point := Vector3(pt.x, 0.0, pt.z)
				if not targets.has(point) and targets.size() < MAX_TARGETS:
					targets.append(point)
			(
				out
				. append(
					{
						"key": RAMP_PUSHBACK,
						"title": _translator.tr("Ramp agent needed for pushback"),
						"detail":
						(
							_translator
							. tr("Emergency tug called (-{fee}) · Hire a ramp agent on Staff")
							. format({"fee": PriceTable.EMERGENCY_PUSHBACK_FEE})
						),
						"targets": targets,
						"show_after": 0,
						"clear_after": ROUTE_HOLD_TICKS,
						"coral": true,
					}
				)
			)
	out.append_array(baggage_connect(sim, resolved_baggage))
	return out


## Non-blocking info alert when at least one Bag Room exists with 0 connected
## check-in desks (ruling 1b70fa33).
static func baggage_connect(sim: PassengerSim, baggage: BaggageSim = null) -> Array[Dictionary]:
	if sim == null or sim.grid == null:
		return []
	var targets: Array[Vector3] = []
	for room_id in sim.grid.room_ids():
		var room := sim.grid.get_room(room_id)
		if room.is_empty() or StringName(room["type"]) != BeltShaper.BAG_ROOM:
			continue
		if targets.size() < MAX_TARGETS:
			var area: Rect2i = room["rect"]
			var middle := (
				sim.grid.cell_to_world(area.position)
				+ Vector3((area.size.x - 1) / 2.0, 0.0, (area.size.y - 1) / 2.0)
			)
			targets.append(Vector3(middle.x, 0.0, middle.z))
	if targets.is_empty():
		return []
	var connected := (
		baggage.has_connected_bag_room()
		if baggage != null
		else BagRoutes.build(sim.grid).connected_desk_count() > 0
	)
	if connected:
		return []
	return [
		{
			"key": BAGGAGE_CONNECT,
			"title": _translator.tr("Bag room needs a belt"),
			"detail":
			_translator.tr("Drag a belt from the back of a check-in desk into your Bag Room."),
			"targets": targets,
			"show_after": 0,
			"clear_after": 0,
			"subtle": true,
		}
	]


## Subtle non-blocking gap chip when a same-day charter fits an open daytime gap.
static func charter_gap(desk: OfferDesk, flights: FlightSim = null) -> Array[Dictionary]:
	if desk == null or not desk.has_fitting_charter():
		return []
	var resolved := flights if flights != null else desk.flights
	if resolved == null or resolved.opened_tick < 0:
		return []
	for charter in desk.board.open_charters():
		if desk.clock != null and desk.clock.tick > int(charter["cutoff_tick"]):
			continue
		if not FlightFit.fits(resolved, OfferBoard.terms_of(charter)):
			continue
		var time := GameCalendar.clock_text(
			GameCalendar.tick_at(0, int(charter["departure_minute"]), 0), 0
		)
		return [
			{
				"key": CHARTER_GAP,
				"title": _translator.tr("Charter available"),
				"detail":
				_translator.tr("One-off {time} flight to {destination} · click to review").format(
					{"time": time, "destination": charter["destination"]}
				),
				"targets": [],
				"show_after": 0,
				"clear_after": 0,
				"subtle": true,
			}
		]
	return []


## Whether a hired member is walking to `station` to take it up, not yet on duty.
static func _member_walking_to(sim: PassengerSim, station: int) -> bool:
	var id := sim.staff.staff_at(station)
	return id != 0 and sim.staff.get_member(id).state == StaffMember.State.TO_STATION


static func _station_cause(
	sim: PassengerSim,
	stations: Array[int],
	key: StringName,
	title: String,
	detail: String,
	hold: int
) -> Dictionary:
	var targets: Array[Vector3] = []
	for station in stations:
		if targets.size() < MAX_TARGETS:
			targets.append(object_point(sim.grid, station))
	return {
		"key": key,
		"title": title,
		"detail": detail,
		"targets": targets,
		"show_after": hold,
		"clear_after": hold,
	}


## The ground point under the middle of object `id`'s footprint.
static func object_point(grid: BuildGrid, id: int) -> Vector3:
	var record := grid.get_object(id)
	var def := BuildCatalog.get_def(StringName(record["def"]))
	var cells := def.footprint(record["anchor"], record["facing"])
	var centre := BuildView.object_transform(grid, cells, record["facing"]).origin
	return Vector3(centre.x, 0.0, centre.z)


## One card for `stations` (all full, ids of one kind): fullest first, then by id.
## `detail` is the words with {count} and {waiting} still to fill.
static func _queue_cause(
	sim: PassengerSim,
	full: Dictionary,
	stations: Array[int],
	key: StringName,
	title: String,
	detail: String
) -> Dictionary:
	stations.sort_custom(
		func(a: int, b: int) -> bool: return full[a] > full[b] or (full[a] == full[b] and a < b)
	)
	var waiting := 0
	var targets: Array[Vector3] = []
	for station in stations:
		waiting += MissMarkers.waiting_at(sim, station, int(full[station]))
		if targets.size() < MAX_TARGETS:
			targets.append(object_point(sim.grid, station))
	# A full station always has someone waiting (its lane is at capacity or
	# passengers are held), so the count is never zero.
	return {
		"key": key,
		"title": title,
		"detail": detail.format({"count": stations.size(), "waiting": waiting}),
		"targets": targets,
		"show_after": QUEUE_HOLD_TICKS,
		"clear_after": QUEUE_HOLD_TICKS,
	}
