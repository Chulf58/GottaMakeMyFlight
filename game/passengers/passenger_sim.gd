# gdlint:disable = max-public-methods
class_name PassengerSim
extends Node
## The passengers as plain data, driven by SimClock ticks after FlightSim.
## Each tick: due spawns, then stations and lanes are reconciled with the
## layout, passengers of a flight whose doors have closed are marked missed,
## stations finish and start service, walkers waiting to join a boarding file
## join where they fit (BoardingFiles), and every passenger takes one step of
## its journey: check-in, security, a gate seat (or standing room), the exit
## door and the apron walk to the plane. Passengers and stations are handled
## in id order and every quantity is an integer, so a snapshot loaded at a
## tick boundary plays out exactly like continuous play.
##
## Stations are chosen by the earliest estimated service completion (walk,
## the service in progress and the queued workload), ties to the lower id,
## and the choice is kept until the station goes or the route is lost. Lanes
## are TerminalLayout's fixed, bounded lanes; past a full lane a queue goes
## on in its station's holding list, each holder on its own cell of the hold
## line (TerminalLayout.line_of()), and a station whose line is full is not
## chosen (PassengerStations). Generic routing never crosses a
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
## Emitted when an arriving passenger spawns on a deboarding flight.
signal arrival_spawned(id: int)
signal outcome(id: int, made: bool)
## Emitted when an arriving passenger completes its terminal walk-out to the road.
signal arrival_finished(id: int)
## Every journey stage change, after it is made (the debug hook logs it).
signal stage_changed(id: int, stage: Passenger.Stage)
## A passenger finished check-in at desk `desk` (an object id) and handed
## over its bag (BaggageSim).
signal checked_in(id: int, desk: int)

## The history of SAVE_VERSION is in PassengerSimSave.
const SAVE_VERSION := 45
## 1.96 m/s; the Toon walk clips cover 1.92-1.95 m/s.
const WALK_MM := 98
## 3.5 m/s, a jog (user-ruled); the Toon run clips cover 4.17-5.30 m/s,
## so they play at about 0.66x (male) and 0.84x (female).
const RUN_MM := 175
## Brisk stair climb pace for remote-stand bus riders unloading during DOORS_CLOSED grace.
const BRISK_APRON_MM := 270
const CHECKIN_TICKS := 60
## The sit clips last 1.2 s.
const SIT_DOWN_TICKS := 24
const STAND_UP_TICKS := 24
const DEFAULT_PASSENGERS := 24
const FOLLOW_WALK_STAGES := [
	Passenger.Stage.TO_GATE,
	Passenger.Stage.TO_AIRSIDE_EXIT,
	Passenger.Stage.TO_ROAD_EXIT,
	Passenger.Stage.TO_PARKED_CAR,
	Passenger.Stage.TO_CURB_PICKUP,
	Passenger.Stage.TO_CLAIM,
	Passenger.Stage.CAFE_WALK,
	Passenger.Stage.TOILET_WALK,
	Passenger.Stage.SHOP_WALK,
]
## The last scheduled spawn of a flight is this many ticks before doors close
## (68 s: clears check-in and security with positive slack before doors close).
const LAST_SPAWN_LEAD_TICKS := 1360
## A made passenger (or legacy direct MISSED override) is kept this long, then
## retired; walk-out MISSED passengers stay until reaching the road or timing out.
const SETTLED_KEEP_TICKS := 200
## How long a missed passenger pauses in dismay before walking out (~1.5 s).
const MISSED_DISMAY_TICKS := 30
## How long a missed passenger with no route to any entrance waits before retiring.
const MISSED_NO_ROUTE_TIMEOUT_TICKS := 100
## Upper bound on a missed passenger's walk-out from outcome_tick before forced retirement.
const MISSED_MAX_WALK_OUT_TICKS := 6000
## Stuck passengers retry once a simulated second, staggered by id; mood and
## the lateness forecast update on the same beat.
const BEAT_TICKS := 20
## Stuck or waiting passengers inside a Departure Board's sight fan retry
## wayfinding more often without staff.
const WAYFINDING_RETRY_TICKS := 5
## Stuck mood loss per beat inside a Departure Board's sight fan (lighter relief
## than a staffed Info desk's CALM_STUCK_LOSS).
const BOARD_STUCK_LOSS := 2
const SEAT_TRIES := 4
const MOOD_MAX := 100
## A passenger standing at the gate loses a mood point every this many beats.
const STANDING_MOOD_BEATS := 4
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
## Optional apron shuttle sim tracking passengers in Passenger.Stage.ON_BUS.
@export var bus_shuttle: Node
## Optional baggage sim for arrivals bag-claim linking; BaggageSim.bind() also wires it.
@export var baggage: BaggageSim:
	set(value):
		if (
			is_instance_valid(baggage)
			and baggage.inbound_bag_lost.is_connected(_on_inbound_bag_lost)
		):
			baggage.inbound_bag_lost.disconnect(_on_inbound_bag_lost)
		baggage = value
		if (
			is_instance_valid(baggage)
			and not baggage.inbound_bag_lost.is_connected(_on_inbound_bag_lost)
		):
			baggage.inbound_bag_lost.connect(_on_inbound_bag_lost)
@export var auto_schedule := true

## The apron walk after an exit door with no site (a test grid,
## OutsideWalks.departure()), world points: a fixed walk the boarding window
## was measured on (test_boarding_window.gd), from the forecourt to a plane
## door at (-14.5, 0, -106.5). On the site the walks outside are SiteRoutes'
## instead, to the door at the live stand (ApronStand).
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
## Messes left by visits, bins and their mood cost (MessSim), stepped each
## tick and applied on each beat.
var messes := MessSim.new()
## Help visits to staffed info desks for stuck passengers (InfoDesk).
var info_desks := InfoDesk.new()
## Sight-fan coverage of unstaffed Departure Boards (&"info_screen").
var departure_boards := ScreenCoverage.new(ScreenCoverage.INFO_SCREEN_ID)
## Kiosk visits and browse slot reservations (ShopSim).
var shops := ShopSim.new()
## Security service after admission, at every scanner and lane.
var security := SecurityRuntime.new()
## Arrival bookings by car and taxi, used while `landside` is set.
var arrivals := ArrivalBookings.new()
## Standing spots near the gate and the passengers' claims on them, for when
## every gate seat is taken (StandingSpots).
var standing := StandingSpots.new()
## Gate places reserved at security admission (GateCapacity).
var gates := GateCapacity.new()
## The ordered files walkers keep to on the way out to the plane, so they do
## not walk through each other (BoardingFiles).
var files := BoardingFiles.new()
## The line arrivals wait in outside the entrance while check-in is full, and
## the claims of those admitted and walking in (EntranceLine).
var entrance := EntranceLine.new()
## Where cafe visits pay: the Finances node's wallet in a scene; tests set it.
var wallet: Wallet
var grid: BuildGrid
## The airport site whose open ground gives the walks outside (OutsideWalks,
## SiteRoutes): from BuildMode in a scene; tests set it. Setting it rebuilds
## the layout, whose doors then need a walk outside to be in service. Null (a
## test grid): no road walk, and exits walk apron_waypoints.
var site: SiteDefinition:
	set(value):
		site = value
		layout.site = value
		files.clear_derived()
		if grid != null:
			layout.rebuild(grid)
var tick := 0
## Counts every change to the passengers' state: each tick, spawn, stage change,
## settled outcome and snapshot load. A reader that caches something derived
## from passenger state (the departures board's late counts) compares this one
## int instead of scanning the passengers. Code that writes a Passenger field
## directly (debug, tests) calls mark_changed().
var revision := 0
var last_batch_seed := 0
## Why the last spawn_now() was refused; "" when it was not.
var spawn_refusal := ""
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
## Passenger ids that PassengerGates.choose_exits() advanced on this tick.
var _chose_exit: Dictionary = {}
var _next_id := 1
## Pending spawns {"tick", "flight", "variant"}, in tick order.
var _schedule: Array[Dictionary] = []
## Pending arriving spawns {"tick", "flight", "variant"}, in tick order.
var _arrival_schedule: Array[Dictionary] = []
## Flights whose arrivals are scheduled and whose doors have not closed.
var _scheduled: Dictionary = {}
## Occurrence id -> extra passengers added when it is scheduled
## (BookingOverrides); saved.
var _booking_overrides: Dictionary = {}
## Station id -> {"lane": Array[int], "holding": Array[int], "serving": int}.
var _queues: Dictionary = {}
## Derived: station id -> passengers walking to it.
var _incoming: Dictionary = {}
## Station -> the walker holding its claim on the line's tail
## (StationQueue.arrive()); saved.
var _claims: Dictionary = {}
## The passengers whose beat fell on this tick, forecast for lateness at the
## tick's boundary (_settle_lateness()).
var _late_due: Array[Passenger] = []
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
	site = build_mode.site
	bind(clock, flights, build_mode.grid)
	if auto_schedule:
		for id in flights.flight_ids():
			schedule_flight(id, PassengerLifecycle.booked_passengers(self, id))


func bind(with_clock: SimClock, with_flights: FlightSim, with_grid: BuildGrid) -> void:
	clock = with_clock
	flights = with_flights
	grid = with_grid
	tick = clock.tick
	layout.rebuild(grid)
	# Before the sim's own handler, so nothing reads a route an edit outdated.
	routes.bind(grid)
	security.bins.day = GameCalendar.day_of(tick, SimClock.epoch_of(clock))
	security.bind(self, _security_admitted, _security_cleared, gates.placed.bind(self))
	cafes.bind(self, _set_stage, _leave_station, _release_seat)
	toilets.bind(self, _set_stage, _leave_station, _release_seat)
	grid.set_meta(RoomMove.EXIT_CELLS_META, move_exit_cells)
	boredom.bind(self)
	decor.bind(self)
	messes.bind(self)
	info_desks.bind(self)
	departure_boards.bind(grid)
	shops.bind(self, _set_stage, _leave_station, _release_seat)
	arrivals.bind(self, _spawn)
	clock.ticked.connect(on_tick)
	grid.graph_changed.connect(_on_graph_changed)
	# A room edit relinks no cells, so it fires edit_applied alone; it can
	# still put a room over a standing spot.
	grid.edit_applied.connect(_on_edit_applied)
	if auto_schedule:
		flights.occurrence_added.connect(_on_occurrence_added)
		flights.deboarding_started.connect(_on_deboarding_started)
	flights.contract_ended.connect(_on_contract_ended)
	# After the layout handler above, so staff read a rebuilt layout on edits.
	if staff != null:
		staff.bind(self)
	if (
		is_instance_valid(baggage)
		and not baggage.inbound_bag_lost.is_connected(_on_inbound_bag_lost)
	):
		baggage.inbound_bag_lost.connect(_on_inbound_bag_lost)


## Schedules `count` passengers for a flight from the saved sim RNG. Each
## draws an arrival type and arrives in that type's window (ArrivalTypes):
## relaxed ones before the flight's first state, typical ones from just after
## it to LAST_SPAWN_LEAD_TICKS before its doors close, rushed ones late in
## that, never before the next tick. With a LandsideSim they are booked in
## parties that share a car or taxi instead (ArrivalBookings.schedule()). A
## flight is scheduled once: a second call, or a flight whose doors have
## closed, is refused with an error. The flight's extra passengers
## (set_booking_override()) are added to `count`, once. The starter occurrence
## the airport opened with has its first party arrive at once (FirstParty).
func schedule_flight(flight_id: String, count: int) -> bool:
	if _scheduled.has(flight_id) or flights.is_doors_closed(flight_id):
		push_error("PassengerSim.schedule_flight: '%s' is scheduled or closed" % flight_id)
		return false
	_scheduled[flight_id] = true
	count += BookingOverrides.take(self, flight_id)
	# The contract's arrival traits, resolved once for both ways of arriving.
	var contract := BookingOverrides.contract_of(self, flight_id)
	var shares := ArrivalTypes.shares_for(
		contract.get(FlightContract.TRAITS_KEY, {}), FlightContract.is_charter(contract)
	)
	var at_once := FirstParty.due(self, flight_id)
	if landside != null:
		arrivals.schedule(flight_id, count, shares, at_once)
		return true
	for i in count:
		var arrival := ArrivalTypes.draw(clock.rng, shares)
		var span := ArrivalTypes.window(arrival, flights, flight_id, clock.tick)
		var at := clock.rng.randi_range(span.x, span.y)
		if at_once and i == 0:
			at = clock.tick + 1
		PassengerLifecycle.add_spawn(self, at, flight_id, clock.rng.randi_range(0, 1), arrival)
	return true


## Books `extra` more passengers on a contract occurrence, added when its
## passengers are scheduled (an occurrence is scheduled as it is issued, so this
## is for one not issued yet: "<contract>-d<day>"). Replaces an earlier
## override. Refused (ok false, with a reason) for an occurrence already
## scheduled or departed, a flight with no contract, extra under 1 or a booking
## past the plane class maximum. Always returns {"ok", "reason", "headroom"},
## the most extra passengers the occurrence can take.
func set_booking_override(flight_id: String, extra: int) -> Dictionary:
	return BookingOverrides.set_extra(self, flight_id, extra)


## The most extra passengers `flight_id` can take: the plane class maximum
## less the contract's booked passengers (0 for a flight with no contract).
func booking_headroom(flight_id: String) -> int:
	return BookingOverrides.headroom(self, flight_id)


## The extra passengers waiting for `flight_id` to be scheduled; 0 when none.
func booking_override_of(flight_id: String) -> int:
	return BookingOverrides.extra_of(self, flight_id)


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
		PassengerLifecycle.add_spawn(self, tick + 1 + i, flight_id, rng.randi_range(0, 1))
	return true


## Spawns one passenger at the entrance now and returns its id, or 0 (with an
## error) when there is no entrance. `variant` -1 draws one from the sim RNG.
## It takes the entrance line's admission like any arrival (EntranceLine): with
## check-in full it waits in the line, and with the line full too it is
## refused, 0, with the reason in spawn_refusal and a warning.
func spawn_now(flight_id: String, variant := -1) -> int:
	spawn_refusal = ""
	if layout.passenger_entrances.is_empty():
		push_error("PassengerSim.spawn_now: the terminal has no entrance")
		return 0
	if entrance.room_for_arrivals(self) <= 0:
		spawn_refusal = "check-in is full and the line outside the entrance is full"
		push_warning("PassengerSim.spawn_now: refused, %s" % spawn_refusal)
		return 0
	if variant < 0:
		variant = clock.rng.randi_range(0, 1)
	return _spawn(flight_id, variant).id


func on_tick(new_tick: int) -> void:
	var started := Time.get_ticks_usec()
	tick = new_tick
	var day := GameCalendar.day_of(new_tick, SimClock.epoch_of(clock))
	if day != security.bins.day:
		security.bins.reset(day)
	mark_changed()
	entrance.step(self)
	arrivals.step()
	PassengerLifecycle.spawn_due(self)
	PassengerArrivals.spawn_due(self)
	PassengerArrivals.gate_boarding(self)
	if staff != null:
		staff.step()
	_reconcile()
	messes.step()
	PassengerLifecycle.close_doors(self)
	var stations: Array = layout.lanes.keys()
	stations.sort()
	gates.recover(self)
	for station in stations:
		PassengerStations.step(self, station)
	gates.admit(self)
	cafes.step_counters()
	PassengerGates.admit_pending(self)
	PassengerStations.arrive(self)
	PassengerGates.choose_exits(self)
	for p in _passengers:
		if not p.is_done():
			_step(p)
		elif p.stage == Passenger.Stage.MISSED and p.missed_phase != Passenger.MissedPhase.NONE:
			PassengerLifecycle.step_missed(self, p)
	# The tick's boundary: every forecast that decides something on the next
	# tick, against one state (SecurityForecast.begin_boundary()).
	SecurityForecast.begin_boundary(self)
	_settle_lateness()
	cafes.refresh_live_deadlines()
	SecurityForecast.end_boundary()
	PassengerLifecycle.retire_settled(self)
	PassengerLifecycle.prune_results(self)
	tick_usec_last = Time.get_ticks_usec() - started
	tick_usec_max = maxi(tick_usec_max, tick_usec_last)
	tick_usec_total += tick_usec_last
	ticks_measured += 1


## Moves `revision`: the passengers' state changed. The sim calls it itself
## wherever it changes that state; call it after writing a Passenger field
## directly, so a cache keyed on `revision` reads again.
func mark_changed() -> void:
	revision += 1


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


## Passengers still present in the terminal or on outside walks: active
## passengers plus missed passengers walking out to the road.
func present_count() -> int:
	var count := 0
	for p in _passengers:
		if (
			not p.is_done()
			or (
				p.stage == Passenger.Stage.MISSED
				and p.missed_phase != Passenger.MissedPhase.NONE
				and p.missed_phase != Passenger.MissedPhase.DONE
			)
		):
			count += 1
	return count


## Scheduled passengers not yet in the terminal: pending spawns and arrival
## bookings still on their way.
func pending_spawns() -> int:
	return _schedule.size() + arrivals.pending()


## Earliest pending spawn tick across _schedule and arrival bookings, or -1
## when none.
func next_spawn_tick() -> int:
	var next := -1
	if not _schedule.is_empty():
		next = int(_schedule[0]["tick"])
	if not _arrival_schedule.is_empty():
		var arr_tick := int(_arrival_schedule[0]["tick"])
		next = arr_tick if next < 0 else mini(next, arr_tick)
	for id in arrivals.booking_ids():
		var b := arrivals.get_booking(id)
		if b != null:
			next = b.unload_tick if next < 0 else mini(next, b.unload_tick)
	return next


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


## Ticks until a passenger who walks `walk_mm` to the back of `station`'s
## queue is done there. At a desk: the walk (at `p`'s pace), the service in progress, the
## passengers waiting and its own service. At a security station: until `p`
## (the candidate; a passenger with no carry-on when null) is cleared at the
## security exit (SecurityForecast). Station choice and the lateness forecast
## both use it. A closed station never finishes (JourneyForecast.NEVER).
func station_eta(station: int, walk_mm: int, p: Passenger = null) -> int:
	return PassengerStations.eta(self, station, walk_mm, p)


## Ticks until the passenger's service at its current or next station ends:
## for a security stage, until it is cleared at the security exit
## (SecurityForecast.eta()).
func wait_ticks(p: Passenger) -> int:
	return PassengerStations.wait_ticks(self, p)


## SecurityRuntime admitted `p` at its station.
func _security_admitted(p: Passenger) -> void:
	_set_stage(p, Passenger.Stage.SECURITY)


## SecurityRuntime cleared `p` at its station's exit.
func _security_cleared(p: Passenger) -> void:
	p.station = 0
	p.cleared = true
	gates.on_cleared(self, p)
	_set_stage(p, Passenger.Stage.TO_GATE)


## Whether a desk or scanner serves (StaffSim.is_open()); never without staff.
func _is_open(station: int) -> bool:
	return staff != null and staff.is_open(station)


func _any_open(stations: Array[int]) -> bool:
	for station in stations:
		if _is_open(station):
			return true
	return false


## The cells visitors need clear to leave the pieces they use: RoomMove's
## keep_clear, set on the grid by bind() (Relocation.exit_cells()).
func move_exit_cells() -> Array[Vector2i]:
	return Relocation.exit_cells(self)


## Where the passenger stands on this tick, in world space.
func world_position(p: Passenger) -> Vector3:
	if p.stage == Passenger.Stage.ON_BUS and bus_shuttle != null:
		return bus_shuttle.bus_position_for_passenger(p.id)
	var where := StageKinds.location(p.stage)
	if (StageKinds.is_outside(p.stage) or p.walking_outside()) and not p.apron.is_empty():
		return p.apron_position()
	if where == StageKinds.Location.FACILITY_SEAT:
		var in_stall := Passenger.in_toilet(p.stage)
		return toilets.stall_position(p) if in_stall else cafes.seat_position(p)
	if where == StageKinds.Location.GATE_SEAT and p.seat_cell != Passenger.NO_CELL:
		return PassengerGates.seat_point(self, p)
	var at := p.grid_position()
	var here := grid.origin + Vector3(at.x, 0.0, at.y)
	if p.stage == Passenger.Stage.STANDING and standing.spot_of(p.id) != StandingSpots.NO_SPOT:
		# Arrived at the spot's cell, it steps over onto the spot.
		var point := standing.world_of(grid, standing.spot_of(p.id))
		here = here.lerp(point, clampf((tick - p.stage_tick) / float(SHUFFLE_TICKS), 0.0, 1.0))
	elif p.stage == Passenger.Stage.TO_EXIT and standing.spot_of(p.id) != StandingSpots.NO_SPOT:
		here = PassengerGates.off_spot(self, p)
	return here + files.waiters.shift(p)


## What the passenger's thought bubble says, or "" for nothing.
func bubble_text(p: Passenger) -> String:
	const STUCK_TEXT := {
		Passenger.Stuck.NO_CHECKIN: "Where is check-in?",
		Passenger.Stuck.NO_SECURITY: "Where is security?",
		Passenger.Stuck.QUEUE_FULL: "Queue full",
		Passenger.Stuck.NO_ROUTE: "I can't get there",
		Passenger.Stuck.EXIT_BLOCKED: "The exit is blocked",
		Passenger.Stuck.GATE_FULL: "The gate is full",
	}
	const GATE_STAGES := [
		Passenger.Stage.TO_GATE,
		Passenger.Stage.SITTING_DOWN,
		Passenger.Stage.SEATED,
		Passenger.Stage.STANDING,
		Passenger.Stage.STANDING_UP,
		Passenger.Stage.TO_EXIT,
	]
	if p.stage == Passenger.Stage.MISSED:
		return "Missed my flight!"
	if (
		p.stage in GATE_STAGES
		and tick >= p.boarding_tick
		and (p.stuck == Passenger.Stuck.NONE or p.stuck == Passenger.Stuck.EXIT_BLOCKED)
		and not PassengerGates.gate_open(self, p)
	):
		return "Gate is closed"
	# Waiting outside while every check-in desk is closed (EntranceLine).
	var closed_outside := entrance.waiting(p.id) and not _any_open(layout.desks)
	if p.stuck != Passenger.Stuck.NONE or closed_outside:
		# A usable station that stands unstaffed is closed, not missing.
		var unstaffed := (
			p.stuck == Passenger.Stuck.NO_CHECKIN and layout.desks.any(layout.is_usable)
		)
		var text: String = STUCK_TEXT.get(p.stuck, "")
		if closed_outside or unstaffed:
			text = "Check-in is closed"
		elif p.stuck == Passenger.Stuck.NO_SECURITY and layout.scanners.any(layout.is_usable):
			text = "Security is closed"
		return text
	if p.late and not p.is_done():
		return "I'm late!"
	return SecuritySearchReasons.bubble_of(p)


## The apron walk from an exit door to the door of a plane drawn with `model`
## ("" for the ground walk to the stand's door), in millimetres.
func apron_length_mm(exit_door: int, model := "") -> int:
	return PassengerGates.apron_length_mm(self, exit_door, model)


## JSON-safe state for a save. Reads only: it changes nothing in the sim or
## the wallet. A save never holds cafe state an edit left stale, so between a
## grid edit and the next tick (cafes.deadlines_stale) it pushes an error and
## returns {}. The next tick's reconcile settles the cafe, and SaveGame waits
## for it; a caller that must save sooner runs CafeSim.reconcile() itself.
## Toilet deadlines left stale by that edit are saved stale and worked out
## again on the loaded game's next tick (ToiletSnapshot).
func to_snapshot() -> Dictionary:
	return PassengerSimSave.to_snapshot(self)


## Restores a to_snapshot() dictionary, including one that went through JSON.
## Pushes an error and returns false, leaving the sim unchanged, when anything
## is missing, mistyped or inconsistent. The layout is rebuilt from the grid,
## which must already hold the saved grid.
func from_snapshot(data: Dictionary) -> bool:
	var loaded := PassengerSimSave.from_snapshot(self, data)
	if loaded:
		mark_changed()
	return loaded


## The standing spots derived from the loaded grid and the saved claims,
## checked against `by_id` (the loaded passengers by id): {"spots":
## StandingSpots, "claims": {passenger: spot}} or {"error": why}. Needs the
## layout rebuilt from the grid. Changes no sim state: from_snapshot() installs
## the result, and SaveGame's staging runs the same check, so the two agree.
func checked_standing(data: Dictionary, by_id: Dictionary) -> Dictionary:
	return PassengerSimSave.checked_standing(self, data, by_id)


## The info desk state in `data` checked against `by_id` (the loaded
## passengers by id) at the saved tick `at`: InfoDesk.checked()'s dictionary or
## {"error": why}. Changes no sim state: from_snapshot() installs the result,
## and SaveGame's staging runs the same check.
func checked_info_desks(data: Dictionary, by_id: Dictionary, at: int) -> Dictionary:
	return PassengerSimSave.checked_info_desks(self, data, by_id, at)


## The boarding files in `data` checked against `by_id`, with this sim's grid
## and layout (rebuilt from the grid): {"files": BoardingFiles} or {"error":
## why}. Changes no sim state: from_snapshot() installs the result, and
## SaveGame's staging runs the same check.
func checked_boarding(data: Dictionary, by_id: Dictionary) -> Dictionary:
	return PassengerSimSave.checked_boarding(self, data, by_id)


## A contract ended: its days are never issued, so their overrides go.
func _on_contract_ended(contract_id: String) -> void:
	BookingOverrides.clear_contract(self, contract_id)


## An occurrence was issued: its booked passengers arrive within its window.
func _on_occurrence_added(flight_id: String) -> void:
	if not auto_schedule:
		return
	schedule_flight(flight_id, PassengerLifecycle.booked_passengers(self, flight_id))


func _on_deboarding_started(flight_id: String, count: int) -> void:
	if not auto_schedule:
		return
	PassengerArrivals.schedule_deboarding(self, flight_id, count)


func _on_inbound_bag_lost(bag_id: int, passenger_id: int, _flight_id: String) -> void:
	PassengerArrivals.on_inbound_bag_lost(self, bag_id, passenger_id)


## A new passenger at the entrance, or, with a `walk` (where it got out of
## a car or taxi, ArrivalBookings), walking from there: the walk replaces the
## road start of the entrance's walk in (OutsideWalks), or ends at the
## entrance's cell when the entrance has none.
func _spawn(
	flight_id: String, variant: int, arrival := ArrivalTypes.Type.TYPICAL, walk: Array[Vector3] = []
) -> Passenger:
	mark_changed()
	var p := PassengerLifecycle.spawn(self, flight_id, variant, arrival, walk)
	p.checked_bag_color = Bag.color_for_passenger(p.id)
	return p


func _finish(p: Passenger, made: bool) -> void:
	mark_changed()
	PassengerLifecycle.finish(self, p, made)


func _step(p: Passenger) -> void:
	if p.needs_replan:
		PassengerEdits.replan(self, p)
	var from := p.stage
	match StageKinds.facility(p.stage):
		StageKinds.Facility.CAFE:
			cafes.step(p)
		StageKinds.Facility.TOILET:
			toilets.step(p)
		StageKinds.Facility.SHOP:
			shops.step(p)
	# A help visit or bin detour holds the passenger: its stage's own logic would plan again.
	if info_desks.holds(p):
		info_desks.step(p)
	elif p.bin_detour_bin > 0:
		BinDetour.step(self, p)
	elif not VisitHandBack.is_hand_back(from, p.stage):
		_advance(p)
	_move(p)
	if posmod(tick, BEAT_TICKS) == posmod(p.id, BEAT_TICKS) and not p.is_done():
		_beat(p)


## One tick of the journey stage's own logic.
func _advance(p: Passenger) -> void:
	match p.stage:
		Passenger.Stage.SPAWNED:
			# In from the road first, when the entrance has one (OutsideWalks).
			# An entrance passengers may not use is not entered: with no site the
			# walker waits at its door until the gap is closed again; on a site
			# OutsideWalks.revalidate() sends it to another entrance first.
			# One waiting in the line outside stands at its place (EntranceLine).
			if p.apron_mm < p.apron_total_mm() or entrance.waiting(p.id):
				pass
			elif not OutsideWalks.may_enter(self, p):
				p.stuck = Passenger.Stuck.NO_ROUTE
			else:
				p.stuck = Passenger.Stuck.NONE
				p.apron = []
				p.apron_mm = 0
				var claimed := entrance.entered(p)
				_set_stage(p, Passenger.Stage.TO_CHECKIN)
				PassengerStations.choose(self, p, claimed)
		Passenger.Stage.TO_CHECKIN, Passenger.Stage.TO_SECURITY:
			PassengerStations.seek(self, p)
		Passenger.Stage.CHECKIN_QUEUE, Passenger.Stage.SECURITY_QUEUE:
			PassengerStations.queue_move(self, p)
		Passenger.Stage.TO_GATE:
			if not ParkRecovery.collecting(self, p):
				PassengerGates.to_gate(self, p)
		Passenger.Stage.SITTING_DOWN:
			PassengerGates.step_sitting(self, p)
		Passenger.Stage.SEATED, Passenger.Stage.STANDING:
			PassengerGates.step_waiting(self, p)
		Passenger.Stage.STANDING_UP:
			PassengerGates.step_stand_up(self, p)
		Passenger.Stage.TO_EXIT:
			if not _chose_exit.has(p.id):
				PassengerGates.to_exit(self, p)
		Passenger.Stage.DEPLANING, Passenger.Stage.TO_AIRSIDE_EXIT, Passenger.Stage.TO_ROAD_EXIT:
			PassengerArrivals.advance(self, p)
		Passenger.Stage.TO_PARKED_CAR, Passenger.Stage.TO_CURB_PICKUP, Passenger.Stage.WAIT_CURB_PICKUP:
			PassengerArrivals.advance(self, p)
		Passenger.Stage.TO_CLAIM, Passenger.Stage.AT_CLAIM:
			PassengerArrivals.advance(self, p)


func _move(p: Passenger) -> void:
	if p.stage == Passenger.Stage.ON_BUS:
		return
	# A walker outside with no walk left stands where it is (OutsideWalks).
	if (
		(StageKinds.is_outside(p.stage) or p.walking_outside())
		and p.stuck == Passenger.Stuck.NO_ROUTE
	):
		return
	var speed := p.pace_mm()
	if (
		p.stage == Passenger.Stage.APRON
		and layout.bus_exits.has(p.exit_object)
		and flights != null
		and flights.is_doors_closed(p.flight_id)
	):
		speed = maxi(speed, BRISK_APRON_MM)
	if files.holds(p.id) or files.waiters.back_mm(p.id) > 0:
		speed = files.step_of(self, p, speed)
	# The line outside moves up together at a walk, so it keeps its spacing.
	if entrance.waiting(p.id):
		speed = mini(speed, WALK_MM)
		if p.apron.size() >= 2 and p.apron_mm < p.apron_total_mm():
			speed = OutsideWalks.follow_step(self, p, speed)
	elif p.stage == Passenger.Stage.SPAWNED and entrance.has_claim(p.id):
		# Admitted walkers reach the door one at a time, a gap apart.
		speed = entrance.step_of(p, speed, self)
		speed = OutsideWalks.follow_step(self, p, speed)
	elif (
		p.stage == Passenger.Stage.DEPLANING
		or p.walking_outside()
		or (p.stage == Passenger.Stage.SPAWNED and p.apron_mm < p.apron_total_mm())
		or p.stage in FOLLOW_WALK_STAGES
	):
		speed = OutsideWalks.follow_step(self, p, speed)
	if p.stage == Passenger.Stage.DEPLANING or p.walking_outside():
		PassengerArrivals.step_outside(self, p, speed)
	elif p.stage == Passenger.Stage.APRON or p.stage == Passenger.Stage.SPAWNED:
		var total := p.apron_total_mm()
		p.odometer_mm += mini(speed, total - p.apron_mm)
		p.apron_mm = mini(p.apron_mm + speed, total)
		if p.stage == Passenger.Stage.APRON and p.apron_mm >= total:
			_finish(p, true)
		elif p.stage == Passenger.Stage.APRON:
			files.moved(p)
	elif p.is_moving():
		QueueRipple.walk(p, speed, tick)
	# A spot kept on setting off is given up once the walker is off its cell.
	var spot := standing.spot_of(p.id)
	if p.stage == Passenger.Stage.TO_EXIT and spot != StandingSpots.NO_SPOT:
		if p.path_index > 0 or p.at != standing.cell_of(spot):
			standing.release(p.id)
			p.stand_from = Passenger.NO_CELL


## Mood and the lateness forecast, once a simulated second per passenger.
func _beat(p: Passenger) -> void:
	if p.stage == Passenger.Stage.ON_BUS:
		if p.is_departing():
			_late_due.append(p)
		return
	var change := 0
	if p.stage in QUEUE_STAGES:
		change -= 1
	# On the road in (the line outside the entrance) a stuck passenger is out of
	# the terminal's reach: no stuck mood loss and no info desk help.
	var on_road := (
		p.stage == Passenger.Stage.SPAWNED
		or p.stage == Passenger.Stage.DEPLANING
		or p.walking_outside()
	)
	if p.stuck != Passenger.Stuck.NONE and not on_road:
		var loss := info_desks.stuck_loss(p)
		if loss > BOARD_STUCK_LOSS and departure_boards.covers(p.at):
			loss = BOARD_STUCK_LOSS
		change -= loss
	# A bored passenger gets nothing from its seat (BoredomSim).
	if p.stage == Passenger.Stage.SEATED and not BoredomSim.is_bored(p):
		change += 1
	if p.late:
		change -= 1
	# Standing at the gate for want of a seat wears on a passenger (user ruling
	# 342df92a): a seat gains a point a beat, standing on a spot loses one every
	# few.
	@warning_ignore("integer_division")
	if (
		p.stage == Passenger.Stage.STANDING
		and standing.spot_of(p.id) != StandingSpots.NO_SPOT
		and posmod(tick / BEAT_TICKS, STANDING_MOOD_BEATS) == 0
	):
		change -= 1
	p.mood = clampi(p.mood + change, 0, MOOD_MAX)
	PassengerThoughts.queued(p, tick)
	decor.beat(p)
	messes.beat(p)
	# Every need rises first, then NeedsPolicy picks which one, if any, the
	# passenger acts on, by its priority table. Deplaning arrivals wait outside
	# on the apron before entering the terminal, so skip need mood penalties there.
	if p.stage != Passenger.Stage.DEPLANING:
		toilets.beat(p)
		cafes.beat(p)
		if p.is_departing():
			boredom.beat(p)
		shops.beat(p)
	if not on_road and not info_desks.holds(p) and p.bin_detour_bin == 0:
		NeedsPolicy.arbitrate(self, p)
		info_desks.beat(p)
	if p.is_departing():
		_late_due.append(p)


## The lateness of every passenger whose beat fell on this tick, forecast at
## one boundary, after every passenger has stepped (decision hold-line-
## rebuild-the-security-line-follows-where-people-sta): all against the same
## state, from one security replay per mode (SecurityForecast.
## begin_boundary()), and set together once all are forecast.
func _settle_lateness() -> void:
	if _late_due.is_empty():
		return
	var late: Array[bool] = []
	for p in _late_due:
		late.append(_late_now(p))
	for i in _late_due.size():
		_late_due[i].late = late[i]
	_late_due.clear()


## Whether `p` is late now: a visiting guest walks (its visit's deadline keeps
## the margin for the rest), and one with no way to the plane is stuck, not
## late.
func _late_now(p: Passenger) -> bool:
	if (
		p.is_done()
		or p.is_arriving()
		or StageKinds.visit_facility(self, p) != StageKinds.Facility.NONE
	):
		return false
	var arrival := JourneyForecast.arrival_tick(self, p)
	if arrival >= JourneyForecast.NEVER:
		return false
	return JourneyForecast.next_late(p.late, flights.doors_close_tick(p.flight_id) - arrival)


## Gives up the claim on the seat `p` holds but leaves it the seat (it gets up
## from a chair that moved, GateRelocation).
func drop_seat_claim(p: Passenger) -> void:
	for key in _seat_claims.keys():
		if _seat_claims[key] == p.id:
			_seat_claims.erase(key)


func _release_seat(p: Passenger) -> void:
	if p.seat_object == 0:
		return
	drop_seat_claim(p)
	p.forget_seat()


## The open exits `p` may leave by: with gates, its flight's gate's exit
## (TerminalLayout.open_exits_for()).
func exits_for(p: Passenger) -> Array[int]:
	return PassengerGates.exits_for(self, p)


func _on_graph_changed(cells: Array[Vector2i]) -> void:
	PassengerEdits.graph_changed(self, cells)


## The live plane stand moved (ApronStand): exits walk to its door from now
## on, so the doors' walks outside are found again, as after an edit.
func set_stand(stand: Dictionary) -> void:
	PassengerEdits.set_stand(self, stand)


## The gate stands changed (ApronStand with gate desks): each gate's exit
## walks to its own stand (exit id -> stand, exit id -> gate letter), and its
## passengers wait by its gate desk (gate letter -> desk object id).
func set_gate_stands(
	exit_stands: Dictionary,
	exit_gates: Dictionary,
	gate_desk_ids: Dictionary,
	bus_exits: Dictionary = {}
) -> void:
	PassengerEdits.set_gate_stands(self, exit_stands, exit_gates, gate_desk_ids, bus_exits)
	if staff != null:
		staff._on_graph_changed([] as Array[Vector2i])


## Any accepted edit: the standing spots are derived again on the next tick.
func _on_edit_applied(_edit: BuildEdit, _result: BuildResult) -> void:
	PassengerEdits.edit_applied(self)


## Brings queues and seat claims in line with the layout after an edit: a
## station that is gone sends its passengers back to choose again, a lane
## that got shorter moves its last passengers to the front of holding, and a
## removed seat leaves its passenger standing.
func _reconcile() -> void:
	PassengerStations.reconcile(self)
	security.bins.prune(grid)
	PassengerGates.reconcile_seats(self)
	cafes.reconcile()
	BinDetour.reconcile(self)
	toilets.reconcile()
	shops.reconcile()
	PassengerEdits.recover_stranded(self)


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
	var period := WAYFINDING_RETRY_TICKS if departure_boards.covers(p.at) else BEAT_TICKS
	return posmod(tick, period) == posmod(p.id, period)


func _set_stage(p: Passenger, stage: Passenger.Stage) -> void:
	mark_changed()
	gates.stage_set(self, p, stage)
	# A standing spot is held only on the way to the gate and standing there,
	# and kept on setting off from it for the exit until the walker is off its
	# cell (_move()), so it does not jump to the cell's centre; a visit or the
	# doors closing gives it up.
	var setting_off := stage == Passenger.Stage.TO_EXIT and p.stage == Passenger.Stage.STANDING
	if stage != Passenger.Stage.TO_GATE and stage != Passenger.Stage.STANDING and not setting_off:
		standing.release(p.id)
		p.stand_from = Passenger.NO_CELL
	# The boarding files hold walkers heading out and on the apron only; one
	# that turns to the exit chooses its door afresh.
	if stage != Passenger.Stage.TO_EXIT and stage != Passenger.Stage.APRON:
		files.leave(p.id)
		files.forget(p.id)
	elif stage == Passenger.Stage.TO_EXIT and p.stage != Passenger.Stage.TO_EXIT:
		p.exit_object = 0
		files.leave(p.id)
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
		# One getting up from a moved row has dropped its claim (GateRelocation).
		if p.seat_object != 0 and not p.seat_exiting:
			for seat in layout.seats:
				if seat["object_id"] == p.seat_object and seat["cell"] == p.seat_cell:
					_seat_claims[seat["key"]] = p.id
	files.clear_derived()
	cafes.rederive()
	toilets.rederive()
	shops.rederive()
