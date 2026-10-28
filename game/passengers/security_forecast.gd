class_name SecurityForecast
extends RefCounted
## The security forecast (decision security-lane-technical-design-one-
## station-per-lane-with-int, point 3): the ticks until a passenger is cleared
## at a station's security exit, found by replaying the station on a copy of
## its state with the same SecurityRuntime and the same queue rules as
## PassengerSim: the passengers walking to it (incoming work, each with its id
## and the tick it joins, ordered by that tick, then id), its lane and holding
## list, and its admitted passengers with their phases, remaining work, berth
## and returns. Nothing in the sim changes.
##
## The replay steps tick by tick as PassengerSim does (station first: phases,
## holding to lane, admission; then each passenger in id order: joining, moving
## up the lane, walking at WALK_MM), but skips the ticks on which nothing can
## change: no work runs out and nobody reaches a cell or joins. Read between
## ticks it is exact for passengers who walk; a late passenger runs, so it
## arrives sooner than forecast. Whether the station is open is taken as it
## is now: a closed station admits nobody new. Staff are not stepped: a lane's
## helper speeds the replayed repacks from the tick StaffPosts.helper_from()
## gives (now when on duty, its arrival when walking there), and that tick is
## an event the replay does not skip past.

## Far enough that a replay this long has gone wrong.
const HORIZON := 200000

## What SecurityRuntime reads from its host (see its header).
var tick := 0
var layout: TerminalLayout

var _sim: PassengerSim
var _station := 0
var _runtime := SecurityRuntime.new()
var _open := false
## The first tick a helper is on duty at the station, or -1 (never).
var _helper_from := -1
var _cells: Array = []
var _queue := {"lane": [], "holding": []}
## Passenger id -> its copy.
var _units := {}
## The copies' ids, ascending: the order PassengerSim steps passengers in.
var _order: Array[int] = []
## Passenger id -> the tick it joins the queue, for copies still walking to it.
var _joins := {}
## Passenger id -> the tick it was cleared.
var _cleared := {}
## Whether a walker reached a new cell or joined the queue on the tick just
## played: the next tick can then change something. True at the start, as
## the sim's state may be waiting on its next tick (a passenger who joined
## the queue on the first lane cell is admitted on it).
var _changed := true


## Ticks from now until `p` is cleared at `station`'s exit, or
## JourneyForecast.NEVER. A passenger not yet committed to `station` is the
## candidate: it joins the back of the queue on `join_tick`, on the lane cell
## a newcomer walks to.
static func clearance(sim: PassengerSim, station: int, p: Passenger, join_tick: int) -> int:
	if not sim.layout.is_usable(station):
		return JourneyForecast.NEVER
	var replay := SecurityForecast.new()
	replay._setup(sim, station)
	var ticks := JourneyForecast.NEVER
	if replay._units.has(p.id) or replay._open:
		if not replay._units.has(p.id):
			# Where a newcomer walks: behind the lane, holding list and walkers.
			var ahead: int = replay._queue["lane"].size() + replay._queue["holding"].size()
			var slot := mini(ahead + replay._joins.size(), replay._cells.size() - 1)
			replay._add_walker(p, maxi(join_tick, sim.tick + 1), replay._cells[slot])
		ticks = replay._run(p.id)
	# The runtime holds the replay as its host: let go, or neither is freed.
	replay._runtime.bind(null)
	return ticks


## Ticks until `p`, walking to, queuing at or inside its security station, is
## cleared at that station's exit; JourneyForecast.NEVER when it has no
## security station or never will be.
static func eta(sim: PassengerSim, p: Passenger) -> int:
	if p.station == 0 or not sim.layout.passages.has(p.station):
		return JourneyForecast.NEVER
	return clearance(sim, p.station, p, sim.tick + 1)


func get_passenger(id: int) -> Passenger:
	return _units[id]


func _on_admitted(p: Passenger) -> void:
	p.stage = Passenger.Stage.SECURITY


func _on_cleared(p: Passenger) -> void:
	p.stage = Passenger.Stage.TO_GATE
	_cleared[p.id] = tick


func _setup(sim: PassengerSim, station: int) -> void:
	_sim = sim
	_station = station
	tick = sim.tick
	layout = sim.layout
	_open = sim.staff != null and sim.staff.is_open(station)
	if sim.staff != null:
		_helper_from = StaffPosts.helper_from(sim.staff, station)
	_runtime.helper_from = {station: _helper_from}
	_cells = sim.layout.lanes[station]
	_runtime.bind(self, _on_admitted, _on_cleared)
	var record := sim.security.record_of(station)
	if not record.is_empty():
		_runtime.restore({station: record})
		for id: int in record["admitted"]:
			_add(sim.get_passenger(id))
	_queue["lane"] = sim.queue_of(station)
	_queue["holding"] = sim.holding_of(station)
	for id: int in _queue["lane"] + _queue["holding"]:
		_add(sim.get_passenger(id))
	for id in sim.passenger_ids():
		var walker := sim.get_passenger(id)
		if walker.station == station and walker.stage == Passenger.Stage.TO_SECURITY:
			var arrive := sim.tick + JourneyForecast.walk_ticks(walker.remaining_mm())
			_add_walker(walker, arrive + 1, walker.path_end())


func _add(p: Passenger) -> Passenger:
	var copy := Passenger.new()
	copy.id = p.id
	copy.stage = p.stage
	copy.station = p.station
	copy.at = p.at
	copy.path = p.path.duplicate()
	copy.path_index = p.path_index
	copy.seg_mm = p.seg_mm
	copy.carry_on = p.carry_on
	copy.liquids = p.liquids
	copy.alarm = p.alarm
	copy.incident_resolved = p.incident_resolved
	copy.security_phase = p.security_phase
	copy.security_work = p.security_work
	_units[copy.id] = copy
	var at := _order.bsearch(copy.id)
	if at >= _order.size() or _order[at] != copy.id:
		_order.insert(at, copy.id)
	return copy


## A passenger walking to the queue: it stands on `cell` and joins on `join`.
func _add_walker(p: Passenger, join: int, cell: Vector2i) -> void:
	var copy := _add(p)
	copy.stage = Passenger.Stage.TO_SECURITY
	copy.station = _station
	copy.security_phase = SecurityRuntime.Phase.NONE
	copy.security_work = 0
	copy.at = cell
	copy.clear_path()
	_joins[copy.id] = join


func _run(target: int) -> int:
	while not _cleared.has(target):
		var next := _next_event()
		if next < 0 or next - _sim.tick >= HORIZON:
			return JourneyForecast.NEVER
		_skip(next - tick - 1)
		tick = next
		_step()
	return mini(int(_cleared[target]) - _sim.tick, JourneyForecast.NEVER)


## One tick as PassengerSim plays it for this station and its passengers.
func _step() -> void:
	_runtime.advance(_station)
	StationQueue.promote(_queue, _cells)
	_runtime.admit(_station, _queue, _cells, _open)
	for id in _order:
		var u: Passenger = _units[id]
		if _cleared.has(id):
			continue
		if u.stage == Passenger.Stage.TO_SECURITY and _joins[id] <= tick:
			_joins.erase(id)
			StationQueue.join(_queue, _cells, id)
			u.stage = Passenger.Stage.SECURITY_QUEUE
			_changed = true
		elif u.stage == Passenger.Stage.SECURITY_QUEUE:
			_move_up(u)
		if u.is_moving():
			var was := u.at
			u.walk(PassengerSim.WALK_MM)
			_changed = _changed or u.at != was


## PassengerSim._queue_move() on the copy. The lane is a straight line of
## cells, so between two of its cells the path is the lane itself; elsewhere
## the grid's path is used as there.
func _move_up(u: Passenger) -> void:
	if not _misplaced(u):
		return
	var index: int = (_queue["lane"] as Array).find(u.id)
	var from := _cells.find(u.at)
	var path: Array[Vector2i] = []
	if from >= 0:
		var step := -1 if index < from else 1
		for i in range(from, index + step, step):
			path.append(_cells[i])
	else:
		path = _sim.grid.find_path(u.at, _cells[index])
	if path.size() >= 2:
		u.set_path(path)


## A lane member standing still away from its lane place: it moves up on the
## next tick.
func _misplaced(u: Passenger) -> bool:
	var index: int = (_queue["lane"] as Array).find(u.id)
	return index >= 0 and not u.is_moving() and u.at != _cells[index]


## The next tick on which something can change, or -1 when nothing will:
## work running out, a walker reaching a cell (it counts from the tick after,
## so a cell reached on this tick makes the next one count) or a walker
## joining the queue.
func _next_event() -> int:
	if _changed:
		_changed = false
		return tick + 1
	var best := -1
	if _helper_from > tick:
		# The repack rate changes on the tick the helper arrives.
		best = _helper_from
	for id in _order:
		if _cleared.has(id):
			continue
		var u: Passenger = _units[id]
		var at := -1
		if _joins.has(id):
			at = _joins[id]
		elif u.is_moving():
			var left := Passenger.segment_mm(u.path[u.path_index], u.path[u.path_index + 1])
			at = tick + JourneyForecast.walk_ticks(left - u.seg_mm) + 1
		elif u.stage == Passenger.Stage.SECURITY_QUEUE and _misplaced(u):
			at = tick + 1
		if u.stage == Passenger.Stage.SECURITY and _works(u):
			var rate := maxi(1, _runtime.rate(_station, u.security_phase))
			@warning_ignore("integer_division")
			var ends := tick + maxi(1, (u.security_work + rate - 1) / rate)
			at = ends if at < 0 else mini(at, ends)
		if at >= 0 and (best < 0 or at < best):
			best = at
	return best


## Plays `ticks` ticks on which nothing changes: work runs down and walkers
## move, none of them reaching a new cell.
func _skip(ticks: int) -> void:
	if ticks <= 0:
		return
	for id in _order:
		if _cleared.has(id):
			continue
		var u: Passenger = _units[id]
		if u.stage == Passenger.Stage.SECURITY and _works(u):
			u.security_work -= ticks * _runtime.rate(_station, u.security_phase)
		if u.is_moving():
			u.walk(ticks * PassengerSim.WALK_MM)


static func _works(u: Passenger) -> bool:
	return SecurityRuntime.WORK_PHASES.has(u.security_phase as SecurityRuntime.Phase)
