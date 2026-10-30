class_name PassengerSim
extends Node
## The passengers as plain data, driven by SimClock ticks after FlightSim.
## Each tick: due spawns, then stations and lanes are reconciled with the
## layout, passengers of a flight whose doors have closed are marked missed,
## stations finish and start service, and every passenger takes one step of
## its journey: check-in, security, a gate seat (or standing room), the exit
## door and the apron walk to the plane. Passengers and stations are handled
## in id order and every quantity is an integer, so a snapshot loaded at a
## tick boundary plays out exactly like continuous play.
##
## Stations are chosen by the earliest estimated service completion (walk,
## the service in progress and the queued workload), ties to the lower id,
## and the choice is kept until the station goes or the route is lost. Lanes
## are TerminalLayout's fixed, bounded lanes; a passenger arriving at a full
## lane waits in its station's holding list. Generic routing never crosses a
## scanner; the passenger being serviced walks its passage, and only cleared
## passengers claim seats or head for the exit. Security service, at a basic
## scanner or a security lane, is SecurityRuntime's from admission on, and a
## security station's estimate is SecurityForecast's replay.
##
## With a LandsideSim (`landside`), scheduled passengers are arrival bookings
## (ArrivalBookings, `arrivals`) that come by car or taxi and become
## passengers when they get out; each tick starts with the bookings' step,
## right after the tick is taken. Without one they spawn at the entrance on
## their drawn tick.

signal passenger_spawned(id: int)
signal outcome(id: int, made: bool)
## Every journey stage change, after it is made (the debug hook logs it).
signal stage_changed(id: int, stage: Passenger.Stage)
## A passenger finished check-in at desk `desk` (an object id) and handed
## over its bag (BaggageSim).
signal checked_in(id: int, desk: int)

## 3: the walks outside carry heights ([x, y, z] apron points).
## 4: hunger, the cafe cooldown and the cafe visits, queues and seats.
## 5: durable made and missed totals, per-flight results and the flights
## already scheduled; settled passengers are retired, so none of these are
## rebuilt from the passenger list.
## 6: each passenger and pending arrival carries its arrival type.
## 7: each passenger carries its security traits (bags, liquids, alarm). A
## version 6 save is migrated with zero bags and no flags; older ones are
## refused.
## 8: security service state (SecurityRuntime): each passenger's phase,
## remaining work and resolved incident, and per station the admitted and
## returning passengers, the main position and the berth. A version 7 save
## keeps a basic scanner's service in progress exactly as it was.
## 9: a lane's unpack work starts at 3 + 4 per bag, not 6 + 8. A version 8
## save has its unpack work left scaled to the new start.
## 10: each passenger's toilet need and toilet cooldown, and the toilet visits
## under "toilet" (ToiletSnapshot). Versions 6 to 9 are migrated: each
## passenger gets ToiletSim.migrated_need() of its id, and nobody is on a
## toilet visit.
## 11: each passenger's boredom (BoredomSim). Versions 6 to 10 are migrated:
## each passenger gets BoredomSim.start_of() of its id; a version 10 save keeps
## its toilet needs, cooldowns and visits as saved. Version 11 also holds each
## passenger's kiosk cooldown and the kiosk visits under "shop" (ShopSnapshot);
## an older save gets no cooldown and no kiosk visits.
## 12: the help visits and cooldowns of the info desks, under "info_desk"
## (InfoDesk.to_list()). A version 11 save is refused; a migrated older save has
## none.
## 13: each shop visit saves whether it is a fallback (ShopSnapshot). Versions
## 11 and 12 are refused, with no migration (decision old-saves-are-not-
## supported-until-after-a-release-no-save-mi).
## 14: each standing passenger's claimed standing spot, under "standing"
## (StandingSpots.to_list()). Version 13 is refused, with no migration; a
## migrated older save has no claims.
const SAVE_VERSION := 14
## 1.96 m/s; the Toon walk clips cover 1.92-1.95 m/s.
const WALK_MM := 98
## 3.5 m/s, a jog (user-ruled); the Toon run clips cover 4.17-5.30 m/s,
## so they play at about 0.66x (male) and 0.84x (female).
const RUN_MM := 175
const CHECKIN_TICKS := 60
## The sit clips last 1.2 s.
const SIT_DOWN_TICKS := 24
const STAND_UP_TICKS := 24
const DEFAULT_PASSENGERS := 24
## The last scheduled spawn of a flight is this many ticks before doors close.
const LAST_SPAWN_LEAD_TICKS := 800
## A made or missed passenger is kept this long, then retired (a missed one
## stays drawn for PassengerViews.MISSED_LINGER_TICKS, which is the same).
const SETTLED_KEEP_TICKS := 200
## Stuck passengers retry once a simulated second, staggered by id; mood and
## the lateness forecast update on the same beat.
const BEAT_TICKS := 20
const SEAT_TRIES := 4
const MOOD_MAX := 100
## Seated, the feet stand this far in front of the seat cell's centre.
const SIT_FORWARD_M := 0.45
const SHUFFLE_TICKS := 8
const QUEUE_STAGES := [Passenger.Stage.CHECKIN_QUEUE, Passenger.Stage.SECURITY_QUEUE]

@export var clock: SimClock
@export var flights: FlightSim
## In a scene the grid comes from BuildMode; tests call bind() instead.
@export var build_mode: BuildMode
## The scene's wallet owner; cafe visits pay into its Wallet.
@export var finances: Finances
## The staff pool (StaffSim), stepped at the start of each tick. A desk or
## scanner is open only while a member is on duty at it (StaffSim.is_open()); with no
## StaffSim every station stays closed.
@export var staff: StaffSim
## The road and car parks passengers arrive through; tests may leave it unset.
@export var landside: LandsideSim
@export var auto_schedule := true

## The apron walk after an exit door with no terminal shell connection
## (ShellRoutes.departure()), world points: the forecourt layout's walk into
## the Toon terminal's south face, out of its airside face near gate C, through
## the 2.3 m gap between that face (z -100) and the parked plane's nose
## (z -102.3), and to the plane's port door (the plane at the stand at
## (-18, 0, -117) spans x -32.2 to -3.8 with its wings). Inside the shell the
## gate doors' authored routes are used instead (ShellDoorConnection.route).
var apron_waypoints := PackedVector3Array(
	[
		Vector3(-14.5, 0.0, -41.0),
		Vector3(-18.3, 0.0, -99.0),
		Vector3(-14.5, 0.0, -101.0),
		Vector3(-14.5, 0.0, -106.5),
	]
)
var layout := TerminalLayout.new()
## Path lengths for the routed forecasts and exit choice, cleared on edits.
var routes := RouteCache.new()
## Cafe visits, their counter queues and seats (CafeSim).
var cafes := CafeSim.new()
## Toilet visits and stall reservations (ToiletSim).
var toilets := ToiletSim.new()
## The boredom need (BoredomSim), raised on each beat.
var boredom := BoredomSim.new()
## What decor calms (DecorEffect), applied on each beat.
var decor := DecorEffect.new()
## Help visits to staffed info desks for stuck passengers (InfoDesk).
var info_desks := InfoDesk.new()
## Kiosk visits and browse slot reservations (ShopSim).
var shops := ShopSim.new()
## Security service after admission, at every scanner and lane.
var security := SecurityRuntime.new()
## Arrival bookings by car and taxi, used while `landside` is set.
var arrivals := ArrivalBookings.new()
## Standing spots near the gate and the passengers' claims on them, for when
## every gate seat is taken (StandingSpots).
var standing := StandingSpots.new()
## Where cafe visits pay: the Finances node's wallet in a scene; tests set it.
var wallet: Wallet
var grid: BuildGrid
## The terminal shell whose Toon doors give the walks outside (ShellRoutes):
## from BuildMode in a scene; tests set it. Null: no road walk, and exits
## walk apron_waypoints.
var shell: ShellDefinition
var tick := 0
var last_batch_seed := 0
## Scheduled passengers dropped when their flight's doors closed, by flight id:
## {"no_entrance": n, "late": n}. "no_entrance" counts those dropped while the
## terminal had no entrance, "late" those who simply had not arrived yet.
var no_shows := {}
## What a flight's settled passengers did, by flight id, kept after they are
## retired: {"made": n, "missed": n, "causes": {Vector2i(missed_stage,
## missed_stuck): n}}. Dropped, with no_shows, when FlightSim prunes the flight.
var flight_results := {}
## Settled passengers kept because they still held something (a bug).
var retire_refused := 0
var tick_usec_last := 0
var tick_usec_max := 0
var tick_usec_total := 0
var ticks_measured := 0

var _passengers: Array[Passenger] = []
var _by_id: Dictionary = {}
var _next_id := 1
## Pending spawns {"tick", "flight", "variant"}, in tick order.
var _schedule: Array[Dictionary] = []
## Flights whose arrivals are scheduled and whose doors have not closed.
var _scheduled: Dictionary = {}
## Station id -> {"lane": Array[int], "holding": Array[int], "serving": int}.
var _queues: Dictionary = {}
## Derived: station id -> passengers walking to it.
var _incoming: Dictionary = {}
## Derived: seat key -> passenger id.
var _seat_claims: Dictionary = {}
var _made := 0
var _missed := 0


func _ready() -> void:
	if finances != null:
		wallet = finances.wallet
	if clock == null or flights == null or build_mode == null:
		return
	if staff == null:
		push_error("PassengerSim: no StaffSim is set, so every desk and scanner stays closed")
	shell = build_mode.shell
	bind(clock, flights, build_mode.grid)
	if auto_schedule:
		for id in flights.flight_ids():
			schedule_flight(id, _booked_passengers(id))


func bind(with_clock: SimClock, with_flights: FlightSim, with_grid: BuildGrid) -> void:
	clock = with_clock
	flights = with_flights
	grid = with_grid
	tick = clock.tick
	layout.rebuild(grid)
	# Before the sim's own handler, so nothing reads a route an edit outdated.
	routes.bind(grid)
	security.bind(self, _security_admitted, _security_cleared)
	cafes.bind(self, _set_stage, _leave_station, _release_seat)
	toilets.bind(self, _set_stage, _leave_station, _release_seat)
	boredom.bind(self)
	decor.bind(self)
	info_desks.bind(self)
	shops.bind(self, _set_stage, _leave_station, _release_seat)
	arrivals.bind(self, _spawn)
	clock.ticked.connect(on_tick)
	grid.graph_changed.connect(_on_graph_changed)
	# A room edit relinks no cells, so it fires edit_applied alone; it can
	# still put a room over a standing spot.
	grid.edit_applied.connect(_on_edit_applied)
	if auto_schedule:
		flights.occurrence_added.connect(_on_occurrence_added)
	# After the layout handler above, so staff read a rebuilt layout on edits.
	if staff != null:
		staff.bind(self)


## Schedules `count` passengers for a flight from the saved sim RNG. Each
## draws an arrival type and arrives in that type's window (ArrivalTypes):
## relaxed ones before the flight's first state, typical ones from just after
## it to LAST_SPAWN_LEAD_TICKS before its doors close, rushed ones late in
## that, never before the next tick. With a LandsideSim they are booked in
## parties that share a car or taxi instead (ArrivalBookings.schedule()). A
## flight is scheduled once: a second call, or a flight whose doors have
## closed, is refused with an error.
func schedule_flight(flight_id: String, count: int) -> bool:
	if _scheduled.has(flight_id) or flights.is_doors_closed(flight_id):
		push_error("PassengerSim.schedule_flight: '%s' is scheduled or closed" % flight_id)
		return false
	_scheduled[flight_id] = true
	if landside != null:
		arrivals.schedule(flight_id, count)
		return true
	for i in count:
		var arrival := ArrivalTypes.draw(clock.rng)
		var span := ArrivalTypes.window(arrival, flights, flight_id, clock.tick)
		var at := clock.rng.randi_range(span.x, span.y)
		_add_spawn(at, flight_id, clock.rng.randi_range(0, 1), arrival)
	return true


## The debug batch: `count` passengers for the first flight still boarding,
## one per tick from the next tick, through the normal spawn schedule. The
## seed decides their characters and is kept in last_batch_seed, but only once
## the batch is scheduled. Returns false (with an error, last_batch_seed
## unchanged) when every flight has closed its doors.
func spawn_batch(count: int, seed: int) -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var flight_id := ""
	for id in flights.flight_ids():
		if not flights.is_doors_closed(id):
			flight_id = id
			break
	if flight_id == "":
		push_error("PassengerSim.spawn_batch: no flight is open for passengers")
		return false
	last_batch_seed = seed
	for i in count:
		_add_spawn(tick + 1 + i, flight_id, rng.randi_range(0, 1))
	return true


## Spawns one passenger at the entrance now and returns its id, or 0 (with an
## error) when there is no entrance. `variant` -1 draws one from the sim RNG.
func spawn_now(flight_id: String, variant := -1) -> int:
	if layout.entrances.is_empty():
		push_error("PassengerSim.spawn_now: the terminal has no entrance")
		return 0
	if variant < 0:
		variant = clock.rng.randi_range(0, 1)
	return _spawn(flight_id, variant).id


func on_tick(new_tick: int) -> void:
	var started := Time.get_ticks_usec()
	tick = new_tick
	arrivals.step()
	_spawn_due()
	if staff != null:
		staff.step()
	_reconcile()
	_close_doors()
	var stations: Array = layout.lanes.keys()
	stations.sort()
	for station in stations:
		_step_station(station)
	cafes.step_counters()
	for p in _passengers:
		if not p.is_done():
			_step(p)
	_retire_settled()
	_prune_results()
	tick_usec_last = Time.get_ticks_usec() - started
	tick_usec_max = maxi(tick_usec_max, tick_usec_last)
	tick_usec_total += tick_usec_last
	ticks_measured += 1


func get_passenger(id: int) -> Passenger:
	return _by_id.get(id)


func passenger_ids() -> Array[int]:
	var ids: Array[int] = []
	for p in _passengers:
		ids.append(p.id)
	return ids


func made_count() -> int:
	return _made


## Passengers who missed their flight, the ones still on the road when its
## doors closed (ArrivalBookings.missed_total) included.
func missed_count() -> int:
	return _missed + arrivals.missed_total


## Passengers still on their way: spawned and neither made nor missed.
func active_count() -> int:
	var count := 0
	for p in _passengers:
		count += int(not p.is_done())
	return count


## Scheduled passengers not yet in the terminal: pending spawns and arrival
## bookings still on their way.
func pending_spawns() -> int:
	return _schedule.size() + arrivals.pending()


## The lane at a station in order, front first. A desk keeps the passenger it
## is serving at the front; a scanner's serviced passenger is in its passage.
func queue_of(station: int) -> Array[int]:
	var out: Array[int] = []
	if _queues.has(station):
		out.assign(_queues[station]["lane"])
	return out


func holding_of(station: int) -> Array[int]:
	var out: Array[int] = []
	if _queues.has(station):
		out.assign(_queues[station]["holding"])
	return out


## Passengers in front of a newcomer to `station`: its lane, holding area and
## walkers on the way. At a desk the one being served is in the lane too.
func _station_slot(station: int) -> int:
	var count: int = _incoming.get(station, 0)
	if _queues.has(station):
		count += (_queues[station]["lane"] as Array).size()
		count += (_queues[station]["holding"] as Array).size()
	return count


## Ticks until a passenger who walks `walk_mm` to the back of `station`'s
## queue is done there. At a desk: the walk, the service in progress, the
## passengers waiting and its own service. At a security station: until `p`
## (the candidate; a passenger with no carry-on when null) is cleared at the
## security exit (SecurityForecast). Station choice and the lateness forecast
## both use it. A closed station never finishes (JourneyForecast.NEVER).
func station_eta(station: int, walk_mm: int, p: Passenger = null) -> int:
	if not _is_open(station):
		return JourneyForecast.NEVER
	if layout.passages.has(station):
		var candidate := p
		if candidate == null:
			candidate = Passenger.new()
			candidate.id = _next_id
		var join := tick + JourneyForecast.walk_ticks(walk_mm) + 1
		return SecurityForecast.clearance(self, station, candidate, join)
	var waiting := _station_slot(station)
	var left := 0
	if _queues.has(station) and _queues[station]["serving"] != 0:
		left = _serving_left(_queues[station])
		waiting -= 1
	return (
		JourneyForecast.walk_ticks(walk_mm)
		+ left
		+ maxi(waiting, 0) * CHECKIN_TICKS
		+ CHECKIN_TICKS
	)


## Ticks until the passenger's service at its current or next station ends:
## for a security stage, until it is cleared at the security exit
## (SecurityForecast.eta()).
func wait_ticks(p: Passenger) -> int:
	if StageKinds.leg(p.stage) == StageKinds.Leg.SECURITY:
		if p.station == 0 and not _any_open(layout.scanners):
			return JourneyForecast.NEVER
		return SecurityRuntime.BASIC_SCAN_TICKS if p.station == 0 else SecurityForecast.eta(self, p)
	if p.stage == Passenger.Stage.CHECKIN:
		return maxi(0, p.service_end - tick)
	if p.station == 0 and not _any_open(layout.desks):
		return JourneyForecast.NEVER
	if p.station == 0 or not _queues.has(p.station):
		return CHECKIN_TICKS
	var q: Dictionary = _queues[p.station]
	var lane: Array = q["lane"]
	var holding: Array = q["holding"]
	var ahead: int = lane.size() + holding.size() + maxi(_incoming.get(p.station, 0) - 1, 0)
	if p.stage in QUEUE_STAGES:
		var at := lane.find(p.id)
		ahead = at if at >= 0 else lane.size() + holding.find(p.id)
	if q["serving"] != 0:
		ahead -= 1
	return _serving_left(q) + maxi(ahead, 0) * CHECKIN_TICKS + CHECKIN_TICKS


## SecurityRuntime admitted `p` at its station.
func _security_admitted(p: Passenger) -> void:
	_set_stage(p, Passenger.Stage.SECURITY)


## SecurityRuntime cleared `p` at its station's exit.
func _security_cleared(p: Passenger) -> void:
	p.station = 0
	p.cleared = true
	_set_stage(p, Passenger.Stage.TO_GATE)


## Whether a desk or scanner serves (StaffSim.is_open()); never without staff.
func _is_open(station: int) -> bool:
	return staff != null and staff.is_open(station)


func _any_open(stations: Array[int]) -> bool:
	for station in stations:
		if _is_open(station):
			return true
	return false


## Where the passenger stands on this tick, in world space.
func world_position(p: Passenger) -> Vector3:
	var where := StageKinds.location(p.stage)
	if StageKinds.is_outside(p.stage) and not p.apron.is_empty():
		return p.apron_position()
	if where == StageKinds.Location.FACILITY_SEAT:
		var in_stall := Passenger.in_toilet(p.stage)
		return toilets.stall_position(p) if in_stall else cafes.seat_position(p)
	if where == StageKinds.Location.GATE_SEAT and p.seat_cell != Passenger.NO_CELL:
		var front := grid.cell_to_world(p.seat_front)
		var seat := grid.cell_to_world(p.seat_cell)
		var spot := seat + (front - seat) * SIT_FORWARD_M
		var shuffle := clampf((tick - p.stage_tick) / float(SHUFFLE_TICKS), 0.0, 1.0)
		if p.stage == Passenger.Stage.SITTING_DOWN:
			return front.lerp(spot, shuffle)
		if p.stage == Passenger.Stage.STANDING_UP:
			var left := STAND_UP_TICKS - (tick - p.stage_tick)
			return front.lerp(spot, clampf(left / float(SHUFFLE_TICKS), 0.0, 1.0))
		return spot
	var at := p.grid_position()
	var here := grid.origin + Vector3(at.x, 0.0, at.y)
	if p.stage == Passenger.Stage.STANDING and standing.spot_of(p.id) != StandingSpots.NO_SPOT:
		# Arrived at the spot's cell, it steps over onto the spot.
		var point := standing.world_of(grid, standing.spot_of(p.id))
		here = here.lerp(point, clampf((tick - p.stage_tick) / float(SHUFFLE_TICKS), 0.0, 1.0))
	return here


## What the passenger's thought bubble says, or "" for nothing.
func bubble_text(p: Passenger) -> String:
	const STUCK_TEXT := {
		Passenger.Stuck.NO_CHECKIN: "Where is check-in?",
		Passenger.Stuck.NO_SECURITY: "Where is security?",
		Passenger.Stuck.QUEUE_FULL: "Queue full",
		Passenger.Stuck.NO_ROUTE: "I can't get there",
		Passenger.Stuck.EXIT_BLOCKED: "The exit is blocked",
	}
	if p.stage == Passenger.Stage.MISSED:
		return "Missed my flight!"
	if p.stuck != Passenger.Stuck.NONE:
		# A usable station that stands unstaffed is closed, not missing.
		if p.stuck == Passenger.Stuck.NO_CHECKIN and layout.desks.any(layout.is_usable):
			return "Check-in is closed"
		if p.stuck == Passenger.Stuck.NO_SECURITY and layout.scanners.any(layout.is_usable):
			return "Security is closed"
		return STUCK_TEXT[p.stuck]
	if p.late and not p.is_done():
		return "I'm late!"
	return ""


## The apron walk from an exit door to the plane, in millimetres.
func apron_length_mm(exit_door: int) -> int:
	var walk := Passenger.new()
	walk.apron = _apron_points(exit_door)
	return walk.apron_total_mm()


## JSON-safe state for a save. Reads only: it changes nothing in the sim or
## the wallet. A save never holds cafe state an edit left stale, so between a
## grid edit and the next tick (cafes.deadlines_stale) it pushes an error and
## returns {}. The next tick's reconcile settles the cafe, and SaveGame waits
## for it; a caller that must save sooner runs CafeSim.reconcile() itself.
## Toilet deadlines left stale by that edit are saved stale and worked out
## again on the loaded game's next tick (ToiletSnapshot).
func to_snapshot() -> Dictionary:
	if cafes.deadlines_stale:
		push_error("PassengerSim.to_snapshot: a grid edit settles on the next tick; save after it")
		return {}
	var data := PassengerSnapshot.save(
		self, _passengers, _schedule, _queues, _next_id, [_made, _missed], _scheduled.keys()
	)
	data["info_desk"] = info_desks.to_list()
	data["standing"] = standing.to_list()
	return data


## Restores a to_snapshot() dictionary, including one that went through JSON.
## Pushes an error and returns false, leaving the sim unchanged, when anything
## is missing, mistyped or inconsistent. The layout is rebuilt from the grid,
## which must already hold the saved grid.
func from_snapshot(data: Dictionary) -> bool:
	var loaded := PassengerSnapshot.load(data, grid)
	if loaded.has("error"):
		push_error("PassengerSim.from_snapshot: %s" % loaded["error"])
		return false
	var by_id := {}
	for p: Passenger in loaded["passengers"]:
		by_id[p.id] = p
	# A save migrated from before version 12 (PassengerSnapshot) has no info
	# desk state: none is live. A version 12 save must carry it.
	var desk_state := InfoDesk.checked(
		data.get("info_desk", InfoDesk.EMPTY), by_id, loaded["tick"], grid
	)
	if not data.has("info_desk") and int(data["save_version"]) >= SAVE_VERSION:
		desk_state = {"error": "missing key 'info_desk'"}
	if desk_state.has("error"):
		push_error("PassengerSim.from_snapshot: %s" % desk_state["error"])
		return false
	# Standing claims are restored as saved, against spots derived from the
	# loaded grid; a save migrated from before version 14 has none.
	layout.rebuild(grid)
	var spots := StandingSpots.new()
	spots.rebuild(self)
	var current := int(data["save_version"]) >= SAVE_VERSION
	var claims := spots.checked(data.get("standing", []), by_id, current)
	if not data.has("standing") and current:
		claims = {"error": "missing key 'standing'"}
	if claims.has("error"):
		push_error("PassengerSim.from_snapshot: %s" % claims["error"])
		return false
	spots.restore(claims["claims"])
	standing = spots
	tick = loaded["tick"]
	_next_id = loaded["next_id"]
	last_batch_seed = loaded["last_batch_seed"]
	no_shows = loaded["no_shows"]
	flight_results = loaded["flight_results"]
	_scheduled = loaded["scheduled"]
	_made = loaded["made"]
	_missed = loaded["missed"]
	_schedule = loaded["schedule"]
	_queues = loaded["queues"]
	security.restore(loaded["security"])
	cafes.restore(loaded["cafe"])
	toilets.restore(loaded["toilet"])
	shops.restore(loaded["shop"])
	info_desks.restore(desk_state)
	_passengers = loaded["passengers"]
	_by_id.clear()
	for p in _passengers:
		_by_id[p.id] = p
	layout.rebuild(grid)
	routes.clear()
	_rederive()
	return true


func _add_spawn(
	at_tick: int, flight_id: String, variant: int, arrival := ArrivalTypes.Type.TYPICAL
) -> void:
	var entry := {"tick": at_tick, "flight": flight_id, "variant": variant, "arrival": arrival}
	var i := _schedule.size()
	while i > 0 and _schedule[i - 1]["tick"] > at_tick:
		i -= 1
	_schedule.insert(i, entry)


## An occurrence was issued: its booked passengers arrive within its window.
func _on_occurrence_added(flight_id: String) -> void:
	schedule_flight(flight_id, _booked_passengers(flight_id))


## A contract flight's booked passengers; DEFAULT_PASSENGERS for a one-off one.
## An occurrence issued before this sim subscribed (a new game's starter
## contract) is still a contract flight.
func _booked_passengers(flight_id: String) -> int:
	var contract := flights.contract_of(flights.flight_contract_id(flight_id))
	return DEFAULT_PASSENGERS if contract.is_empty() else contract["booked_passengers"]


func _spawn_due() -> void:
	if layout.entrances.is_empty():
		return
	while not _schedule.is_empty() and _schedule[0]["tick"] <= tick:
		var entry: Dictionary = _schedule.pop_front()
		_spawn(entry["flight"], entry["variant"], entry["arrival"])


## A new passenger at the entrance, or, with a `walk` (where it got out of
## a car or taxi, ArrivalBookings), walking from there: the walk replaces the
## road start of the entrance's shell route, or ends at the entrance's cell
## when the entrance has none.
func _spawn(
	flight_id: String, variant: int, arrival := ArrivalTypes.Type.TYPICAL, walk: Array[Vector3] = []
) -> Passenger:
	var p := Passenger.new()
	p.id = _next_id
	_next_id += 1
	p.flight_id = flight_id
	p.variant = variant
	p.arrival_type = arrival
	p.spawn_tick = tick
	p.stage_tick = tick
	p.boarding_tick = flights.boarding_window(flight_id).x
	p.hunger = clock.rng.randi_range(CafeSim.HUNGER_START_MIN, CafeSim.HUNGER_START_MAX)
	CarryOnTraits.draw(clock.rng, p)
	p.toilet_need = clock.rng.randi_range(ToiletSim.NEED_START_MIN, ToiletSim.NEED_START_MAX)
	p.boredom = BoredomSim.start_of(p.id)
	p.at = layout.door_cell(grid, layout.entrances[0])
	p.clear_path()
	p.apron = ShellRoutes.arrival(self, layout.entrances[0])
	if not walk.is_empty():
		var road := p.apron
		p.apron = walk.duplicate()
		if road.is_empty():
			p.apron.append(grid.cell_to_world(p.at))
		else:
			p.apron.append_array(road.slice(1))
	_passengers.append(p)
	_by_id[p.id] = p
	passenger_spawned.emit(p.id)
	return p


## Missed passengers are the ones already in the terminal. Those still on the
## schedule for a closed flight will never board, so they are dropped and
## counted as no-shows, with the cause that holds now.
func _close_doors() -> void:
	var cause := "no_entrance" if layout.entrances.is_empty() else "late"
	var kept: Array[Dictionary] = []
	for entry in _schedule:
		if flights.is_doors_closed(entry["flight"]):
			var counts: Dictionary = no_shows.get(entry["flight"], {"no_entrance": 0, "late": 0})
			counts[cause] += 1
			no_shows[entry["flight"]] = counts
		else:
			kept.append(entry)
	if kept.size() != _schedule.size():
		_schedule = kept
	for flight_id in _scheduled.keys():
		if flights.is_doors_closed(flight_id):
			_scheduled.erase(flight_id)
	for p in _passengers:
		if not p.is_done() and flights.is_doors_closed(p.flight_id):
			_finish(p, false)


func _finish(p: Passenger, made: bool) -> void:
	if not made:
		p.missed_stage = p.stage
		p.missed_stuck = p.stuck
	_leave_station(p)
	_release_seat(p)
	cafes.cleanup(p)
	toilets.cleanup(p)
	shops.cleanup(p)
	info_desks.cleanup(p)
	_set_stage(p, Passenger.Stage.MADE if made else Passenger.Stage.MISSED)
	p.stuck = Passenger.Stuck.NONE
	p.late = false
	p.outcome_tick = tick
	var result: Dictionary = flight_results.get(p.flight_id, {"made": 0, "missed": 0, "causes": {}})
	if made:
		_made += 1
		result["made"] += 1
	else:
		_missed += 1
		result["missed"] += 1
		var cause := Vector2i(p.missed_stage, p.missed_stuck)
		result["causes"][cause] = int(result["causes"].get(cause, 0)) + 1
		p.mood = 0
		p.clear_path()
	flight_results[p.flight_id] = result
	outcome.emit(p.id, made)


## Retires the settled passengers kept for SETTLED_KEEP_TICKS. One that still
## holds a station, seat, cafe or toilet visit or queue place is a bug: it is
## reported and kept, so nothing is left pointing at a passenger that is gone.
func _retire_settled() -> void:
	for i in range(_passengers.size() - 1, -1, -1):
		var p := _passengers[i]
		if not p.is_done() or tick - p.outcome_tick <= SETTLED_KEEP_TICKS:
			continue
		var leftover := _settled_leftovers(p)
		if leftover != "":
			retire_refused += 1
			push_error("PassengerSim: settled passenger %d still holds %s" % [p.id, leftover])
			continue
		_by_id.erase(p.id)
		_passengers.remove_at(i)


## What a settled passenger still holds, or "" when it holds nothing.
func _settled_leftovers(p: Passenger) -> String:
	var held := PackedStringArray()
	if p.station != 0:
		held.append("a station")
	if p.seat_object != 0 or _seat_claims.values().has(p.id):
		held.append("a seat")
	if cafes.visit_of(p.id) != null:
		held.append("a cafe visit")
	if toilets.visit_of(p.id) != null:
		held.append("a toilet visit")
	if shops.visit_of(p.id) != null:
		held.append("a kiosk visit")
	if security.holds(p.id):
		held.append("a security place")
	if standing.spot_of(p.id) != StandingSpots.NO_SPOT:
		held.append("a standing spot")
	for q in _queues.values():
		if (q["lane"] as Array).has(p.id) or (q["holding"] as Array).has(p.id):
			held.append("a queue place")
		elif q["serving"] == p.id:
			held.append("a service")
	for record in cafes.queue_records():
		if (record["lane"] as Array).has(p.id) or record["serving"] == p.id:
			held.append("a cafe queue place")
	return ", ".join(held)


## Drops the results, no-shows and transport misses of flights FlightSim no
## longer lists.
func _prune_results() -> void:
	if flight_results.is_empty() and no_shows.is_empty() and arrivals.missed_by_flight.is_empty():
		return
	var live := flights.flight_ids()
	arrivals.prune(live)
	for results in [flight_results, no_shows]:
		for flight_id in results.keys():
			if not live.has(flight_id):
				results.erase(flight_id)


## A station's tick: finished service, holding passengers moving into the
## lane, then the next admission. Security stations go to SecurityRuntime.
func _step_station(station: int) -> void:
	var q := _queue(station)
	var cells: Array = layout.lanes[station]
	if layout.passages.has(station):
		security.advance(station)
		_promote(q, cells)
		security.admit(station, q, cells, _is_open(station))
		return
	if q["serving"] != 0:
		var served: Passenger = _by_id[q["serving"]]
		if tick >= served.service_end and not served.is_moving():
			q["serving"] = 0
			served.station = 0
			(q["lane"] as Array).erase(served.id)
			_set_stage(served, Passenger.Stage.TO_SECURITY)
			checked_in.emit(served.id, station)
	_promote(q, cells)
	if q["serving"] != 0 or (q["lane"] as Array).is_empty() or not _is_open(station):
		return
	var front: Passenger = _by_id[q["lane"][0]]
	if front.at != cells[0] or front.is_moving():
		return
	q["serving"] = front.id
	front.service_end = tick + CHECKIN_TICKS
	_set_stage(front, Passenger.Stage.CHECKIN)


func _promote(q: Dictionary, cells: Array) -> void:
	for moved in StationQueue.promote(q, cells):
		_by_id[moved].stuck = Passenger.Stuck.NONE


func _step(p: Passenger) -> void:
	if p.needs_replan:
		_replan(p)
	match StageKinds.facility(p.stage):
		StageKinds.Facility.CAFE:
			cafes.step(p)
		StageKinds.Facility.TOILET:
			toilets.step(p)
		StageKinds.Facility.SHOP:
			shops.step(p)
	# A help visit holds the passenger: its stage's own logic would plan again.
	if info_desks.holds(p):
		info_desks.step(p)
	else:
		_advance(p)
	_move(p)
	if posmod(tick, BEAT_TICKS) == posmod(p.id, BEAT_TICKS) and not p.is_done():
		_beat(p)


## One tick of the journey stage's own logic.
func _advance(p: Passenger) -> void:
	match p.stage:
		Passenger.Stage.SPAWNED:
			# In from the road first, when the entrance has one (ShellRoutes).
			if p.apron_mm >= p.apron_total_mm():
				p.apron = []
				p.apron_mm = 0
				_set_stage(p, Passenger.Stage.TO_CHECKIN)
				_seek(p)
		Passenger.Stage.TO_CHECKIN, Passenger.Stage.TO_SECURITY:
			_seek(p)
		Passenger.Stage.CHECKIN_QUEUE, Passenger.Stage.SECURITY_QUEUE:
			_queue_move(p)
		Passenger.Stage.TO_GATE:
			_to_gate(p)
		Passenger.Stage.SITTING_DOWN:
			if tick - p.stage_tick >= SIT_DOWN_TICKS:
				_set_stage(p, Passenger.Stage.SEATED)
		Passenger.Stage.SEATED, Passenger.Stage.STANDING:
			if tick >= p.boarding_tick:
				var next := Passenger.Stage.STANDING_UP
				if p.stage == Passenger.Stage.STANDING:
					next = Passenger.Stage.TO_EXIT
				_set_stage(p, next)
			elif p.stage == Passenger.Stage.STANDING:
				_seat_from_spot(p)
		Passenger.Stage.STANDING_UP:
			if tick - p.stage_tick >= STAND_UP_TICKS:
				_release_seat(p)
				# Up for a facility visit, or (its visit dropped) back to the
				# gate while boarding has not started.
				match StageKinds.visit_facility(self, p):
					StageKinds.Facility.CAFE:
						cafes.depart(p)
					StageKinds.Facility.TOILET:
						toilets.depart(p)
					StageKinds.Facility.SHOP:
						shops.depart(p)
					_:
						if tick < p.boarding_tick:
							_set_stage(p, Passenger.Stage.TO_GATE)
						else:
							_set_stage(p, Passenger.Stage.TO_EXIT)
		Passenger.Stage.TO_EXIT:
			_to_exit(p)


func _move(p: Passenger) -> void:
	var speed := RUN_MM if p.late else WALK_MM
	if p.stage == Passenger.Stage.APRON or p.stage == Passenger.Stage.SPAWNED:
		var total := p.apron_total_mm()
		p.odometer_mm += mini(speed, total - p.apron_mm)
		p.apron_mm = mini(p.apron_mm + speed, total)
		if p.stage == Passenger.Stage.APRON and p.apron_mm >= total:
			_finish(p, true)
	elif p.is_moving():
		p.walk(speed)


## Mood and the lateness forecast, once a simulated second per passenger.
func _beat(p: Passenger) -> void:
	var change := 0
	if p.stage in QUEUE_STAGES:
		change -= 1
	if p.stuck != Passenger.Stuck.NONE:
		change -= info_desks.stuck_loss(p)
	# A bored passenger gets nothing from its seat (BoredomSim).
	if p.stage == Passenger.Stage.SEATED and not BoredomSim.is_bored(p):
		change += 1
	if p.late:
		change -= 1
	p.mood = clampi(p.mood + change, 0, MOOD_MAX)
	decor.beat(p)
	# Every need rises first, then NeedsPolicy picks which one, if any, the
	# passenger acts on, by its priority table.
	toilets.beat(p)
	cafes.beat(p)
	boredom.beat(p)
	shops.beat(p)
	if not info_desks.holds(p):
		NeedsPolicy.arbitrate(self, p)
		info_desks.beat(p)
	# A visiting guest walks: its visit's deadline keeps the margin for the rest.
	if StageKinds.visit_facility(self, p) != StageKinds.Facility.NONE:
		p.late = false
		return
	# With no way to the plane the passenger is stuck, not late: it does not run.
	var arrival := JourneyForecast.arrival_tick(self, p)
	if arrival >= JourneyForecast.NEVER:
		p.late = false
		return
	p.late = JourneyForecast.next_late(p.late, flights.doors_close_tick(p.flight_id) - arrival)


## Walking to a desk or scanner: choose one, walk there, join its lane.
func _seek(p: Passenger) -> void:
	if p.station != 0 and not _is_open(p.station):
		_leave_station(p)
	if p.station == 0:
		if p.stuck == Passenger.Stuck.NONE or _retry_now(p):
			_choose_station(p)
		return
	if p.is_moving():
		return
	if (layout.lanes[p.station] as Array).has(p.at):
		_join(p)
	else:
		_leave_station(p)
		_choose_station(p)


func _choose_station(p: Passenger) -> void:
	var to_desk := p.stage == Passenger.Stage.TO_CHECKIN
	var candidates := layout.desks if to_desk else layout.scanners
	if candidates.is_empty():
		p.stuck = Passenger.Stuck.NO_CHECKIN if to_desk else Passenger.Stuck.NO_SECURITY
		return
	var best := 0
	var best_eta := 0
	var best_path: Array[Vector2i] = []
	if not _any_open(candidates) and candidates.any(layout.is_usable):
		# Usable but none staffed, so all closed: wait where you stand.
		p.stuck = Passenger.Stuck.NO_CHECKIN if to_desk else Passenger.Stuck.NO_SECURITY
		p.clear_path()
		return
	for station in candidates:
		if not _is_open(station):
			continue
		var cells: Array = layout.lanes[station]
		var path := grid.find_path(p.at, cells[mini(_station_slot(station), cells.size() - 1)])
		if path.is_empty():
			continue
		var eta := station_eta(station, Passenger.path_mm(path), p)
		if best == 0 or eta < best_eta:
			best = station
			best_eta = eta
			best_path = path
	if best == 0:
		p.stuck = Passenger.Stuck.NO_ROUTE
		return
	p.stuck = Passenger.Stuck.NONE
	p.station = best
	_incoming[best] = _incoming.get(best, 0) + 1
	p.set_path(best_path)


func _join(p: Passenger) -> void:
	_incoming[p.station] = _incoming.get(p.station, 0) - 1
	if StationQueue.join(_queue(p.station), layout.lanes[p.station], p.id):
		p.stuck = Passenger.Stuck.NONE
	else:
		p.stuck = Passenger.Stuck.QUEUE_FULL
	var to_desk := p.stage == Passenger.Stage.TO_CHECKIN
	_set_stage(p, Passenger.Stage.CHECKIN_QUEUE if to_desk else Passenger.Stage.SECURITY_QUEUE)


func _queue_move(p: Passenger) -> void:
	var index := (_queue(p.station)["lane"] as Array).find(p.id)
	if index < 0 or p.is_moving():
		return
	var target: Vector2i = layout.lanes[p.station][index]
	if p.at != target:
		var path := grid.find_path(p.at, target)
		if path.is_empty():
			_requeue(p)
		else:
			p.set_path(path)


## A queued passenger with no way back to its lane cell would hold up the
## passengers behind it. It leaves the queue and chooses a station again.
func _requeue(p: Passenger) -> void:
	_leave_station(p)
	_send_back(p)
	p.stuck = Passenger.Stuck.NO_ROUTE


## Gate access needs clearance: only a cleared passenger claims a seat.
func _to_gate(p: Passenger) -> void:
	if not p.cleared:
		push_error("PassengerSim: passenger %d reached the gate without clearance" % p.id)
		return
	if tick >= p.boarding_tick:
		_release_seat(p)
		_set_stage(p, Passenger.Stage.TO_EXIT)
		return
	if p.seat_object == 0:
		_to_spot(p)
		return
	if p.is_moving():
		return
	if p.at == p.seat_front:
		p.clear_path()
		_set_stage(p, Passenger.Stage.SITTING_DOWN)
	else:
		_release_seat(p)


## No seat: a free seat first, else the nearest free standing spot
## (StandingSpots), walked to and then stood on. With neither the passenger is
## held where it is (StandingSpots.is_held()) and tries again on the tick it
## got here and once a beat after.
func _to_spot(p: Passenger) -> void:
	var spot := standing.spot_of(p.id)
	if spot == StandingSpots.NO_SPOT:
		if p.stage_tick != tick and not _retry_now(p):
			return
		if _claim_seat(p):
			return
		spot = _claim_spot(p)
		if spot == StandingSpots.NO_SPOT:
			p.clear_path()
			return
	if p.is_moving():
		return
	if p.at == standing.cell_of(spot):
		p.clear_path()
		_set_stage(p, Passenger.Stage.STANDING)
	else:
		# Its path ended elsewhere (an edit): plan again on the next beat.
		standing.release(p.id)


## Claims the nearest free spot that `p` has a path to (StandingSpots.TRIES
## nearest tried) and commits that path; NO_SPOT when none.
func _claim_spot(p: Passenger) -> int:
	var tries := 0
	for spot in standing.free_nearest(p.at):
		var target := standing.cell_of(spot)
		var path: Array[Vector2i] = [p.at]
		if target != p.at:
			path = grid.find_path(p.at, target)
		if not path.is_empty():
			standing.claim(p.id, spot)
			p.set_path(path)
			return spot
		tries += 1
		if tries >= StandingSpots.TRIES:
			break
	return StandingSpots.NO_SPOT


## A standing passenger takes a freed gate seat on its beat, which gives up
## its spot.
func _seat_from_spot(p: Passenger) -> void:
	if standing.spot_of(p.id) == StandingSpots.NO_SPOT or not _retry_now(p):
		return
	if _claim_seat(p):
		standing.release(p.id)
		_set_stage(p, Passenger.Stage.TO_GATE)


func _claim_seat(p: Passenger) -> bool:
	var free: Array = []
	for seat in layout.seats:
		if not _seat_claims.has(seat["key"]):
			free.append([Passenger.octile_mm(p.at, seat["front"]), free.size(), seat])
	free.sort()
	for i in mini(free.size(), SEAT_TRIES):
		var seat: Dictionary = free[i][2]
		var path := grid.find_path(p.at, seat["front"])
		if path.is_empty():
			continue
		_seat_claims[seat["key"]] = p.id
		p.seat_object = seat["object_id"]
		p.seat_cell = seat["cell"]
		p.seat_front = seat["front"]
		p.set_path(path)
		return true
	return false


func _release_seat(p: Passenger) -> void:
	if p.seat_object == 0:
		return
	for key in _seat_claims.keys():
		if _seat_claims[key] == p.id:
			_seat_claims.erase(key)
	p.seat_object = 0
	p.seat_cell = Passenger.NO_CELL
	p.seat_front = Passenger.NO_CELL


func _to_exit(p: Passenger) -> void:
	if p.exit_object != 0 and not layout.open_exits(grid).has(p.exit_object):
		p.exit_object = 0
	if p.exit_object == 0:
		if p.stuck == Passenger.Stuck.NONE or _retry_now(p):
			_choose_exit(p)
		return
	if p.is_moving():
		return
	if p.at == layout.door_cell(grid, p.exit_object):
		p.apron = _apron_points(p.exit_object)
		p.apron_mm = 0
		_set_stage(p, Passenger.Stage.APRON)
	else:
		p.exit_object = 0


func _choose_exit(p: Passenger) -> void:
	var exits := layout.open_exits(grid)
	if exits.is_empty():
		p.stuck = Passenger.Stuck.EXIT_BLOCKED
		p.clear_path()
		return
	# The routed forecasts price the same door (JourneyForecast.nearest_exit()).
	var door := JourneyForecast.nearest_exit(self, p.at).x
	var path: Array[Vector2i] = []
	if door != 0:
		path = grid.find_path(p.at, layout.door_cell(grid, door))
	if path.is_empty():
		p.stuck = Passenger.Stuck.NO_ROUTE
		return
	p.exit_object = door
	p.stuck = Passenger.Stuck.NONE
	p.set_path(path)


## The walk from an exit door's cell to the plane door (ShellRoutes.departure()).
func _apron_points(exit_door: int) -> Array[Vector3]:
	return ShellRoutes.departure(self, exit_door)


## An edit touched the committed path. Finish the current step if it is still
## open and plan on from its end; otherwise turn back to the cell just left.
## Arrival checks in each stage handle a target that is no longer reachable.
func _replan(p: Passenger) -> void:
	p.needs_replan = false
	if not p.is_moving():
		return
	var target := p.path_end()
	var here := p.at
	var next := p.path[p.path_index + 1]
	var keep := p.seg_mm
	var path: Array[Vector2i] = []
	if keep == 0:
		path = grid.find_path(here, target)
	elif grid.can_route(here, next):
		path = grid.find_path(next, target)
		if path.is_empty():
			path.append(next)
		path.push_front(here)
	else:
		keep = Passenger.segment_mm(here, next) - keep
		p.at = next
		path = grid.find_path(here, target)
		if path.is_empty():
			path.append(here)
		path.push_front(next)
	if path.size() < 2:
		p.clear_path()
		return
	p.set_path(path)
	p.seg_mm = keep


func _on_graph_changed(cells: Array[Vector2i]) -> void:
	var touched := {}
	for cell in cells:
		touched[cell] = true
	for p in _passengers:
		if p.is_done() or p.stage == Passenger.Stage.SECURITY or p.stage == Passenger.Stage.APRON:
			continue
		for i in range(p.path_index, p.path.size()):
			if touched.has(p.path[i]):
				p.needs_replan = true
				break
	var before := layout.security_lanes
	layout.rebuild(grid)
	# Rebuilt on the next tick (_reconcile), once however many edits came.
	standing.stale = true
	# A lane that broke or changed (SecurityLanes.broken()) ends its service at
	# once: its admitted passengers go back to choosing, without clearance.
	for arch in SecurityLanes.broken(before, layout.security_lanes):
		for id in security.drop(arch):
			_send_back(_by_id[id])


## Any accepted edit: the standing spots are derived again on the next tick.
func _on_edit_applied(_edit: BuildEdit, _result: BuildResult) -> void:
	standing.stale = true


## Brings queues and seat claims in line with the layout after an edit: a
## station that is gone sends its passengers back to choose again, a lane
## that got shorter moves its last passengers to the front of holding, and a
## removed seat leaves its passenger standing.
func _reconcile() -> void:
	var stations: Array = _queues.keys()
	for station in security.records.keys():
		if not stations.has(station):
			stations.append(station)
	stations.sort()
	for station in stations:
		var q: Dictionary = _queues.get(station, {"lane": [], "holding": [], "serving": 0})
		if not layout.is_usable(station):
			var members: Array = (q["lane"] as Array) + (q["holding"] as Array)
			if q["serving"] != 0 and not members.has(q["serving"]):
				members.append(q["serving"])
			members.append_array(security.drop(station))
			_queues.erase(station)
			for id in members:
				_send_back(_by_id[id])
			continue
		if not _queues.has(station):
			continue
		if not _is_open(station):
			_close_queue(station, q)
			continue
		var cells: Array = layout.lanes[station]
		while (q["lane"] as Array).size() > cells.size():
			var last: int = (q["lane"] as Array).pop_back()
			(q["holding"] as Array).push_front(last)
			_by_id[last].stuck = Passenger.Stuck.QUEUE_FULL
	for p in _passengers:
		if p.seat_object != 0 and not _seat_exists(p):
			_release_seat(p)
			if p.stage in [Passenger.Stage.SITTING_DOWN, Passenger.Stage.SEATED]:
				# Plans again: another seat or a standing spot.
				p.clear_path()
				_set_stage(p, Passenger.Stage.TO_GATE)
	if standing.stale:
		standing.rebuild(self)
		# A claim whose spot the edit removed is dropped; the passenger plans
		# again this tick.
		for id in standing.drop_invalid():
			var p: Passenger = _by_id[id]
			p.clear_path()
			_set_stage(p, Passenger.Stage.TO_GATE)
	cafes.reconcile()
	toilets.reconcile()
	shops.reconcile()


## A station without staff on duty: the passenger in service is finished (at
## a security station every admitted passenger, SecurityRuntime), and
## everyone else in its lane or holding list stops and chooses again.
func _close_queue(station: int, q: Dictionary) -> void:
	var serving: int = q["serving"]
	var members: Array = (q["lane"] as Array) + (q["holding"] as Array)
	members.erase(serving)
	q["lane"] = [serving] if serving != 0 and not layout.passages.has(station) else []
	q["holding"] = []
	for id in members:
		var p: Passenger = _by_id[id]
		_send_back(p)
		p.clear_path()


func _seat_exists(p: Passenger) -> bool:
	for seat in layout.seats:
		if seat["object_id"] == p.seat_object and seat["cell"] == p.seat_cell:
			return true
	return false


func _send_back(p: Passenger) -> void:
	var to_desk := StageKinds.leg(p.stage) == StageKinds.Leg.CHECKIN
	p.station = 0
	p.stuck = Passenger.Stuck.NONE
	if p.is_moving() and p.stage == Passenger.Stage.SECURITY:
		p.clear_path()
	_set_stage(p, Passenger.Stage.TO_CHECKIN if to_desk else Passenger.Stage.TO_SECURITY)


func _leave_station(p: Passenger) -> void:
	if p.station == 0:
		return
	if p.stage == Passenger.Stage.TO_CHECKIN or p.stage == Passenger.Stage.TO_SECURITY:
		_incoming[p.station] = _incoming.get(p.station, 0) - 1
	if _queues.has(p.station):
		var q: Dictionary = _queues[p.station]
		(q["lane"] as Array).erase(p.id)
		(q["holding"] as Array).erase(p.id)
		if q["serving"] == p.id:
			q["serving"] = 0
	security.release(p)
	p.station = 0


func _queue(station: int) -> Dictionary:
	if not _queues.has(station):
		_queues[station] = {"lane": [], "holding": [], "serving": 0}
	return _queues[station]


func _serving_left(q: Dictionary) -> int:
	if q["serving"] == 0:
		return 0
	return maxi(0, (_by_id[q["serving"]] as Passenger).service_end - tick)


func _retry_now(p: Passenger) -> bool:
	return posmod(tick, BEAT_TICKS) == posmod(p.id, BEAT_TICKS)


func _set_stage(p: Passenger, stage: Passenger.Stage) -> void:
	# A standing spot is held only on the way to the gate and standing there:
	# departure, a visit or the doors closing gives it up.
	if stage != Passenger.Stage.TO_GATE and stage != Passenger.Stage.STANDING:
		standing.release(p.id)
	p.stage = stage
	p.stage_tick = tick
	stage_changed.emit(p.id, stage)


## Rebuilds what is derived from the passengers after a load.
func _rederive() -> void:
	_incoming.clear()
	_seat_claims.clear()
	for p in _passengers:
		var walking := (
			p.stage == Passenger.Stage.TO_CHECKIN or p.stage == Passenger.Stage.TO_SECURITY
		)
		if walking and p.station != 0:
			_incoming[p.station] = _incoming.get(p.station, 0) + 1
		if p.seat_object != 0:
			for seat in layout.seats:
				if seat["object_id"] == p.seat_object and seat["cell"] == p.seat_cell:
					_seat_claims[seat["key"]] = p.id
	cafes.rederive()
	toilets.rederive()
	shops.rederive()
