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
## passengers claim seats or head for the exit.

signal passenger_spawned(id: int)
signal outcome(id: int, made: bool)

const SAVE_VERSION := 1
## 1.96 m/s; the Toon walk clips cover 1.92-1.95 m/s.
const WALK_MM := 98
## 4.5 m/s; the Toon run clips cover 4.17-5.30 m/s.
const RUN_MM := 225
const CHECKIN_TICKS := 60
const SECURITY_TICKS := 40
## The sit clips last 1.2 s.
const SIT_DOWN_TICKS := 24
const STAND_UP_TICKS := 24
const DEFAULT_PASSENGERS := 24
## The last scheduled spawn of a flight is this many ticks before doors close.
const LAST_SPAWN_LEAD_TICKS := 800
## Stuck passengers retry once a simulated second, staggered by id; mood and
## the lateness forecast update on the same beat.
const BEAT_TICKS := 20
const SEAT_TRIES := 4
const MOOD_MAX := 100
## Seated, the feet stand this far in front of the seat cell's centre.
const SIT_FORWARD_M := 0.45
const SHUFFLE_TICKS := 8
const QUEUE_STAGES := [Passenger.Stage.CHECKIN_QUEUE, Passenger.Stage.SECURITY_QUEUE]
const SEAT_STAGES := [
	Passenger.Stage.SITTING_DOWN, Passenger.Stage.SEATED, Passenger.Stage.STANDING_UP
]

@export var clock: SimClock
@export var flights: FlightSim
## In a scene the grid comes from BuildMode; tests call bind() instead.
@export var build_mode: BuildMode
@export var auto_schedule := true

## The authored apron walk after the exit door, world points. Defaults: into
## the Toon terminal's south face, out of its airside face at gate C's door,
## through the 2.3 m gap between that face (z -100) and the parked plane's
## nose (z -102.3), and to the plane's port door (the plane at the stand at
## (-18, 0, -117) spans x -32.2 to -3.8 with its wings).
var apron_waypoints := PackedVector3Array(
	[
		Vector3(-14.5, 0.0, -41.0),
		Vector3(-18.3, 0.0, -99.0),
		Vector3(-14.5, 0.0, -101.0),
		Vector3(-14.5, 0.0, -106.5),
	]
)
var layout := TerminalLayout.new()
var grid: BuildGrid
var tick := 0
var last_batch_seed := 0
var tick_usec_last := 0
var tick_usec_max := 0
var tick_usec_total := 0
var ticks_measured := 0

var _passengers: Array[Passenger] = []
var _by_id: Dictionary = {}
var _next_id := 1
## Pending spawns {"tick", "flight", "variant"}, in tick order.
var _schedule: Array[Dictionary] = []
## Station id -> {"lane": Array[int], "holding": Array[int], "serving": int}.
var _queues: Dictionary = {}
## Derived: station id -> passengers walking to it.
var _incoming: Dictionary = {}
## Derived: seat key -> passenger id.
var _seat_claims: Dictionary = {}
var _made := 0
var _missed := 0


func _ready() -> void:
	if clock == null or flights == null or build_mode == null:
		return
	bind(clock, flights, build_mode.grid)
	if auto_schedule:
		for id in flights.flight_ids():
			schedule_flight(id, DEFAULT_PASSENGERS)


func bind(with_clock: SimClock, with_flights: FlightSim, with_grid: BuildGrid) -> void:
	clock = with_clock
	flights = with_flights
	grid = with_grid
	tick = clock.tick
	layout.rebuild(grid)
	clock.ticked.connect(on_tick)
	grid.graph_changed.connect(_on_graph_changed)


## Schedules `count` passengers for a flight between tick 1 and
## LAST_SPAWN_LEAD_TICKS before its doors close, from the saved sim RNG.
func schedule_flight(flight_id: String, count: int) -> void:
	var last := maxi(1, flights.doors_close_tick(flight_id) - LAST_SPAWN_LEAD_TICKS)
	for i in count:
		var at := clock.rng.randi_range(1, last)
		_add_spawn(at, flight_id, clock.rng.randi_range(0, 1))


## The debug batch: `count` passengers for the first flight still boarding,
## one per tick from the next tick, through the normal spawn schedule. The
## seed decides their characters and is kept in last_batch_seed.
func spawn_batch(count: int, seed: int) -> void:
	last_batch_seed = seed
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var flight_id := ""
	for id in flights.flight_ids():
		if not flights.is_doors_closed(id):
			flight_id = id
			break
	if flight_id == "":
		push_error("PassengerSim.spawn_batch: no flight is open for passengers")
		return
	for i in count:
		_add_spawn(tick + 1 + i, flight_id, rng.randi_range(0, 1))


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
	_spawn_due()
	_reconcile()
	_close_doors()
	var stations: Array = layout.lanes.keys()
	stations.sort()
	for station in stations:
		_step_station(station)
	for p in _passengers:
		if not p.is_done():
			_step(p)
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


func missed_count() -> int:
	return _missed


## Passengers still on their way: spawned and neither made nor missed.
func active_count() -> int:
	return _passengers.size() - _made - _missed


func pending_spawns() -> int:
	return _schedule.size()


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


## Ticks until the passenger's service at its current or next station ends.
func wait_ticks(p: Passenger) -> int:
	var desk_stage := p.stage <= Passenger.Stage.CHECKIN
	var service := CHECKIN_TICKS if desk_stage else SECURITY_TICKS
	if p.stage == Passenger.Stage.CHECKIN or p.stage == Passenger.Stage.SECURITY:
		return maxi(0, p.service_end - tick)
	if p.station == 0 or not _queues.has(p.station):
		return service
	var q: Dictionary = _queues[p.station]
	var lane: Array = q["lane"]
	var holding: Array = q["holding"]
	var ahead: int = lane.size() + holding.size() + maxi(_incoming.get(p.station, 0) - 1, 0)
	if p.stage in QUEUE_STAGES:
		var at := lane.find(p.id)
		ahead = at if at >= 0 else lane.size() + holding.find(p.id)
	if desk_stage and q["serving"] != 0:
		ahead -= 1
	return _serving_left(q) + maxi(ahead, 0) * service + service


## Where the passenger stands on this tick, in world space.
func world_position(p: Passenger) -> Vector3:
	if not p.apron.is_empty() and p.stage >= Passenger.Stage.APRON:
		var xz := p.apron_position()
		return Vector3(xz.x, 0.0, xz.y)
	if p.stage in SEAT_STAGES and p.seat_cell != Passenger.NO_CELL:
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
	return grid.origin + Vector3(at.x, 0.0, at.y)


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
		return STUCK_TEXT[p.stuck]
	if p.late and not p.is_done():
		return "I'm late!"
	return ""


## The apron walk from an exit door to the plane, in millimetres.
func apron_length_mm(exit_door: int) -> int:
	var walk := Passenger.new()
	walk.apron = _apron_points(exit_door)
	return walk.apron_total_mm()


func to_snapshot() -> Dictionary:
	return PassengerSnapshot.save(self, _passengers, _schedule, _queues, _next_id)


## Restores a to_snapshot() dictionary, including one that went through JSON.
## Pushes an error and returns false, leaving the sim unchanged, when anything
## is missing, mistyped or inconsistent. The layout is rebuilt from the grid,
## which must already hold the saved grid.
func from_snapshot(data: Dictionary) -> bool:
	var loaded := PassengerSnapshot.load(data, grid)
	if loaded.has("error"):
		push_error("PassengerSim.from_snapshot: %s" % loaded["error"])
		return false
	tick = loaded["tick"]
	_next_id = loaded["next_id"]
	last_batch_seed = loaded["last_batch_seed"]
	_schedule = loaded["schedule"]
	_queues = loaded["queues"]
	_passengers = loaded["passengers"]
	_by_id.clear()
	for p in _passengers:
		_by_id[p.id] = p
	layout.rebuild(grid)
	_rederive()
	return true


func _add_spawn(at_tick: int, flight_id: String, variant: int) -> void:
	var entry := {"tick": at_tick, "flight": flight_id, "variant": variant}
	var i := _schedule.size()
	while i > 0 and _schedule[i - 1]["tick"] > at_tick:
		i -= 1
	_schedule.insert(i, entry)


func _spawn_due() -> void:
	if layout.entrances.is_empty():
		return
	while not _schedule.is_empty() and _schedule[0]["tick"] <= tick:
		var entry: Dictionary = _schedule.pop_front()
		_spawn(entry["flight"], entry["variant"])


func _spawn(flight_id: String, variant: int) -> Passenger:
	var p := Passenger.new()
	p.id = _next_id
	_next_id += 1
	p.flight_id = flight_id
	p.variant = variant
	p.spawn_tick = tick
	p.stage_tick = tick
	p.boarding_tick = flights.boarding_window(flight_id).x
	p.at = layout.door_cell(grid, layout.entrances[0])
	p.clear_path()
	_passengers.append(p)
	_by_id[p.id] = p
	passenger_spawned.emit(p.id)
	return p


func _close_doors() -> void:
	for p in _passengers:
		if not p.is_done() and flights.is_doors_closed(p.flight_id):
			_finish(p, false)


func _finish(p: Passenger, made: bool) -> void:
	_leave_station(p)
	_release_seat(p)
	_set_stage(p, Passenger.Stage.MADE if made else Passenger.Stage.MISSED)
	p.stuck = Passenger.Stuck.NONE
	p.late = false
	p.outcome_tick = tick
	if made:
		_made += 1
	else:
		_missed += 1
		p.mood = 0
		p.clear_path()
	outcome.emit(p.id, made)


func _step_station(station: int) -> void:
	var q := _queue(station)
	var cells: Array = layout.lanes[station]
	var scanner := layout.passages.has(station)
	if q["serving"] != 0:
		var served: Passenger = _by_id[q["serving"]]
		if tick >= served.service_end and not served.is_moving():
			q["serving"] = 0
			served.station = 0
			if scanner:
				served.cleared = true
				_set_stage(served, Passenger.Stage.TO_GATE)
			else:
				(q["lane"] as Array).erase(served.id)
				_set_stage(served, Passenger.Stage.TO_SECURITY)
	while not (q["holding"] as Array).is_empty() and (q["lane"] as Array).size() < cells.size():
		var moved: int = (q["holding"] as Array).pop_front()
		(q["lane"] as Array).append(moved)
		_by_id[moved].stuck = Passenger.Stuck.NONE
	if q["serving"] != 0 or (q["lane"] as Array).is_empty() or not layout.is_usable(station):
		return
	var front: Passenger = _by_id[q["lane"][0]]
	if front.at != cells[0] or front.is_moving():
		return
	q["serving"] = front.id
	if scanner:
		(q["lane"] as Array).pop_front()
		front.service_end = tick + SECURITY_TICKS
		var passage: Array[Vector2i] = []
		passage.assign(layout.passages[station])
		front.set_path(passage)
		_set_stage(front, Passenger.Stage.SECURITY)
	else:
		front.service_end = tick + CHECKIN_TICKS
		_set_stage(front, Passenger.Stage.CHECKIN)


func _step(p: Passenger) -> void:
	if p.needs_replan:
		_replan(p)
	match p.stage:
		Passenger.Stage.SPAWNED:
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
		Passenger.Stage.STANDING_UP:
			if tick - p.stage_tick >= STAND_UP_TICKS:
				_release_seat(p)
				_set_stage(p, Passenger.Stage.TO_EXIT)
		Passenger.Stage.TO_EXIT:
			_to_exit(p)
	_move(p)
	if posmod(tick, BEAT_TICKS) == posmod(p.id, BEAT_TICKS) and not p.is_done():
		_beat(p)


func _move(p: Passenger) -> void:
	var speed := RUN_MM if p.late else WALK_MM
	if p.stage == Passenger.Stage.APRON:
		var total := p.apron_total_mm()
		p.odometer_mm += mini(speed, total - p.apron_mm)
		p.apron_mm = mini(p.apron_mm + speed, total)
		if p.apron_mm >= total:
			_finish(p, true)
	elif p.is_moving():
		p.walk(speed)


## Mood and the lateness forecast, once a simulated second per passenger.
func _beat(p: Passenger) -> void:
	var change := 0
	if p.stage in QUEUE_STAGES:
		change -= 1
	if p.stuck != Passenger.Stuck.NONE:
		change -= 3
	if p.stage == Passenger.Stage.SEATED:
		change += 1
	if p.late:
		change -= 1
	p.mood = clampi(p.mood + change, 0, MOOD_MAX)
	# With no way to the plane the passenger is stuck, not late: it does not run.
	var arrival := JourneyForecast.arrival_tick(self, p)
	if arrival >= JourneyForecast.NEVER:
		p.late = false
		return
	p.late = JourneyForecast.next_late(p.late, flights.doors_close_tick(p.flight_id) - arrival)


## Walking to a desk or scanner: choose one, walk there, join its lane.
func _seek(p: Passenger) -> void:
	if p.station != 0 and not layout.is_usable(p.station):
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
	var service := CHECKIN_TICKS if to_desk else SECURITY_TICKS
	for station in candidates:
		if not layout.is_usable(station):
			continue
		var q := _queue(station)
		var cells: Array = layout.lanes[station]
		var ahead: int = (
			(q["lane"] as Array).size() + (q["holding"] as Array).size() + _incoming.get(station, 0)
		)
		var path := grid.find_path(p.at, cells[mini(ahead, cells.size() - 1)])
		if path.is_empty():
			continue
		var eta := (
			JourneyForecast.walk_ticks(Passenger.path_mm(path))
			+ _serving_left(q)
			+ ahead * service
			+ service
		)
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
	var q := _queue(p.station)
	if (q["lane"] as Array).size() < (layout.lanes[p.station] as Array).size():
		(q["lane"] as Array).append(p.id)
		p.stuck = Passenger.Stuck.NONE
	else:
		(q["holding"] as Array).append(p.id)
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
		if not path.is_empty():
			p.set_path(path)


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
		if not _claim_seat(p):
			p.clear_path()
			_set_stage(p, Passenger.Stage.STANDING)
		return
	if p.is_moving():
		return
	if p.at == p.seat_front:
		p.clear_path()
		_set_stage(p, Passenger.Stage.SITTING_DOWN)
	else:
		_release_seat(p)


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
	var best_path: Array[Vector2i] = []
	for door in exits:
		var path := grid.find_path(p.at, layout.door_cell(grid, door))
		if path.is_empty():
			continue
		if best_path.is_empty() or Passenger.path_mm(path) < Passenger.path_mm(best_path):
			best_path = path
			p.exit_object = door
	if best_path.is_empty():
		p.stuck = Passenger.Stuck.NO_ROUTE
		return
	p.stuck = Passenger.Stuck.NONE
	p.set_path(best_path)


## Door centre, its outward edge, one metre out, then the authored waypoints.
func _apron_points(exit_door: int) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var cell := layout.door_cell(grid, exit_door)
	if cell == BuildObjectDef.NO_CELL:
		return points
	var out := Vector2(layout.door_outward(grid, exit_door))
	var centre_3d := grid.cell_to_world(cell)
	var centre := Vector2(centre_3d.x, centre_3d.z)
	points.append(centre)
	points.append(centre + out * 0.5)
	points.append(centre + out * 1.5)
	for point in apron_waypoints:
		points.append(Vector2(point.x, point.z))
	return points


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
	layout.rebuild(grid)


## Brings queues and seat claims in line with the layout after an edit: a
## station that is gone sends its passengers back to choose again, a lane
## that got shorter moves its last passengers to the front of holding, and a
## removed seat leaves its passenger standing.
func _reconcile() -> void:
	var stations: Array = _queues.keys()
	stations.sort()
	for station in stations:
		var q: Dictionary = _queues[station]
		if not layout.is_usable(station):
			var members: Array = (q["lane"] as Array) + (q["holding"] as Array)
			if q["serving"] != 0 and not members.has(q["serving"]):
				members.append(q["serving"])
			_queues.erase(station)
			for id in members:
				_send_back(_by_id[id])
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
				_set_stage(p, Passenger.Stage.STANDING)


func _seat_exists(p: Passenger) -> bool:
	for seat in layout.seats:
		if seat["object_id"] == p.seat_object and seat["cell"] == p.seat_cell:
			return true
	return false


func _send_back(p: Passenger) -> void:
	var to_desk := p.stage <= Passenger.Stage.CHECKIN
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
	p.stage = stage
	p.stage_tick = tick


## Rebuilds what is derived from the passengers after a load.
func _rederive() -> void:
	_incoming.clear()
	_seat_claims.clear()
	_made = 0
	_missed = 0
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
		_made += int(p.stage == Passenger.Stage.MADE)
		_missed += int(p.stage == Passenger.Stage.MISSED)
