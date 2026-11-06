class_name SecurityForecast
extends RefCounted
## The security forecast (decision security-lane-technical-design-one-
## station-per-lane-with-int, point 3): the ticks until a passenger is cleared
## at a station's security exit, found by replaying the station on a copy of
## its state with the same SecurityRuntime and the same queue rules as
## PassengerSim: the passengers walking to it (each on its own path, as far
## along as it is), its lane and holding list, and its admitted passengers
## with their phases, remaining work, berth and returns. Nothing in the sim
## changes.
##
## The replay steps tick by tick as PassengerSim does (station first: phases,
## holding to lane, admission; then the joins of walkers reaching the next
## free cell of the line, StationQueue.arrive(); then each passenger in id
## order: a walker heading on for the free cell, StationQueue.head_for(), a
## member moving up the line, every walker walking at the pace the sim gives
## it, Passenger.pace_mm(): a run while late, board b13ac401), but skips the
## ticks on which nothing can change: no work runs out and nobody reaches a
## cell or joins. A walker with no free cell left chooses again in the sim; it
## leaves the replay, and one forecast for it is NEVER. Read between
## ticks it is exact while no one turns late or stops being late (lateness is
## taken as it is now). Whether the station is open is taken as it
## is now: a closed station admits nobody new. Staff are not stepped: a lane's
## helper speeds the replayed repacks from the tick StaffPosts.helper_from()
## gives (now when on duty, its arrival when walking there, read after the
## next staff step when that step will plan its path again or move it to
## another post), and that tick is an event the replay does not skip past.
##
## Gate places (decision gate-full-design-passengers-reserve-a-gate-seat-or-
## standing, point 5): while GateCapacity.scarce() says the free room could
## run out first, the replay plays every security station at once, against a
## copy of the sim's gate places (GateCapacity.copy()), with the same
## admission order as the sim (GateCapacity.admit_all(): earliest boarding
## tick first). A front with no place then waits as in the sim, and a place
## freed later (a passenger boarding or visiting a facility) is not foreseen,
## so a front that never gets one is NEVER. Otherwise only the station itself
## is played, and no admission waits for a place.

## Far enough that a replay this long has gone wrong.
const HORIZON := 200000

## What SecurityRuntime reads from its host (see its header).
var tick := 0
var layout: TerminalLayout

var _sim: PassengerSim
var _runtime := SecurityRuntime.new()
## The stations played, ascending: the forecast's own, or every security
## station while gate places are scarce.
var _stations: Array[int] = []
## By station: whether it is open, the first tick a helper is on duty there
## (-1: never), its lane cells, its line (TerminalLayout.line_of()) and its
## {"lane", "holding"} queue.
var _opens := {}
var _helper_from := {}
var _cells := {}
var _lines := {}
var _queues := {}
## The copied gate places, or null when no admission waits for one.
var _places: GateCapacity
## Passenger id -> its copy.
var _units := {}
## The copies' ids, ascending: the order PassengerSim steps passengers in.
var _order: Array[int] = []
## Passenger id -> the tick it joins the queue, for a candidate (clearance()),
## which is not walked.
var _joins := {}
## Ids of walkers that left the replay: no free cell was left for them.
var _left := {}
## Ids of the waiting passengers walked as committed (_add_seekers()): the
## candidate joins behind them.
var _seekers := {}
## Passenger id -> the tick it was cleared.
var _cleared := {}
## Whether a walker reached a new cell or joined the queue on the tick just
## played: the next tick can then change something. True at the start, as
## the sim's state may be waiting on its next tick (a passenger who joined
## the queue on the first lane cell is admitted on it).
var _changed := true


## Ticks from now until `p` is cleared at `station`'s exit, or
## JourneyForecast.NEVER. A passenger not yet committed to `station` is the
## candidate: it joins the back of the queue on `join_tick`, on the line cell
## a newcomer walks to.
static func clearance(sim: PassengerSim, station: int, p: Passenger, join_tick: int) -> int:
	if not sim.layout.is_usable(station):
		return JourneyForecast.NEVER
	var replay := SecurityForecast.new()
	replay._setup(sim, station, sim.gates.scarce(sim, station, p))
	var ticks := JourneyForecast.NEVER
	if replay._units.has(p.id) or replay._opens[station]:
		if not replay._units.has(p.id):
			# Where a newcomer walks: behind the lane, holding list and walkers.
			var queue: Dictionary = replay._queues[station]
			var ahead: int = queue["lane"].size() + queue["holding"].size()
			var line: Array = replay._lines[station]
			var slot := mini(ahead + replay._walkers_to(station), line.size() - 1)
			replay._add_walker(p, maxi(join_tick, sim.tick + 1), line[slot], station)
		ticks = replay._run(p.id)
	# The runtime holds the replay as its host: let go, or neither is freed.
	replay._runtime.bind(null)
	return ticks


## eta() of each of `ids` (passengers committed to `station`: walking to,
## queuing at or inside it) from as few replays as eta() would play: id ->
## ticks until cleared (JourneyForecast.NEVER for one it never clears). The
## replay does not depend on which passenger it is run for, only on whether
## the gate places are replayed (GateCapacity.scarce(), asked for each id as
## eta() asks it), so one replay per answer to that is run on until each of
## its ids is cleared. Ids not in the replay are left out; none when the
## station cannot be used. It sets up, plays and lets go of the replays.
static func clearances(sim: PassengerSim, station: int, ids: Array) -> Dictionary:
	var out := {}
	if not sim.layout.passages.has(station) or not sim.layout.is_usable(station):
		return out
	var replays := {}
	for id: int in ids:
		var scarce := sim.gates.scarce(sim, station, sim.get_passenger(id))
		if not replays.has(scarce):
			var made := SecurityForecast.new()
			made._setup(sim, station, scarce)
			replays[scarce] = made
		var replay: SecurityForecast = replays[scarce]
		if replay._units.has(id):
			out[id] = replay._run(id)
	for replay: SecurityForecast in replays.values():
		# The runtime holds the replay as its host: let go, or neither is freed.
		replay._runtime.bind(null)
	return out


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


## Copies `station`'s state, and with `scarce` (GateCapacity.scarce()) every
## security station's and the gate places.
func _setup(sim: PassengerSim, station: int, scarce: bool) -> void:
	_sim = sim
	tick = sim.tick
	layout = sim.layout
	_stations = [station]
	if scarce:
		_places = sim.gates.copy(sim)
		_stations.clear()
		for other: int in sim.layout.passages:
			if sim.layout.is_usable(other):
				_stations.append(other)
		_stations.sort()
	_runtime.bind(self, _on_admitted, _on_cleared, _placed)
	var records := {}
	for at in _stations:
		_opens[at] = sim.staff != null and sim.staff.is_open(at)
		_helper_from[at] = StaffPosts.helper_from(sim.staff, at) if sim.staff != null else -1
		_cells[at] = sim.layout.lanes[at]
		_lines[at] = sim.layout.line_of(at)
		var record := sim.security.record_of(at)
		if not record.is_empty():
			records[at] = record
		_queues[at] = {"lane": sim.queue_of(at), "holding": sim.holding_of(at)}
	_runtime.helper_from = _helper_from
	_runtime.restore(records)
	for at in _stations:
		for id: int in records.get(at, {}).get("admitted", []):
			_add(sim.get_passenger(id))
		for id: int in _queues[at]["lane"] + _queues[at]["holding"]:
			_add(sim.get_passenger(id))
	for id in sim.passenger_ids():
		var walker := sim.get_passenger(id)
		if _opens.has(walker.station) and walker.stage == Passenger.Stage.TO_SECURITY:
			_add(walker)
	_add_seekers(sim)


## The passengers waiting for a security place (PassengerStations.
## seekers_before(): done at a desk while every line is full, or walking to
## security with no station), by how long they have waited. With one station
## played every one of them goes to it: free places go by waiting age, so a
## newcomer has a place only once all of them have one (an estimate that
## leans late where several stations share them). With every station played
## (gate places scarce) each goes to the station whose line is least full for
## its length. They walk to it from where they are, as committed walkers do.
func _add_seekers(sim: PassengerSim) -> void:
	var seekers: Array[Passenger] = []
	for p in sim._passengers:
		if PassengerStations.is_seeking(sim, p, false):
			seekers.append(p)
	if seekers.is_empty():
		return
	seekers.sort_custom(
		func(a: Passenger, b: Passenger) -> bool:
			return PassengerStations.wait_key(a, false) < PassengerStations.wait_key(b, false)
	)
	var loads := {}
	var sizes := {}
	for at in sim.layout.scanners:
		if sim._is_open(at) and sim.layout.is_usable(at):
			loads[at] = PassengerStations.slot(sim, at)
			sizes[at] = maxi(sim.layout.line_of(at).size(), 1)
	for p in seekers:
		var best := -1
		for at: int in loads:
			# The least full for its line's length: places free in proportion.
			if best < 0 or loads[at] * sizes[best] < loads[best] * sizes[at]:
				best = at
		if best < 0:
			return
		if _stations.size() == 1:
			# One station played: a newcomer gets a place only after every
			# passenger waiting longer has one, wherever that is, so all of them
			# are counted ahead of it here.
			best = _stations[0]
		loads[best] += 1
		if not _opens.has(best):
			continue
		var line: Array = _lines[best]
		var copy := _add(p)
		_seekers[copy.id] = true
		copy.stage = Passenger.Stage.TO_SECURITY
		copy.station = best
		copy.security_phase = SecurityRuntime.Phase.NONE
		copy.security_work = 0
		var path := StationQueue.approach(
			_sim.grid, line, copy.at, mini(loads[best] - 1, line.size() - 1)
		)
		copy.clear_path()
		if path.size() >= 2:
			copy.set_path(path)


## Whether a copy may be cleared: it holds a copied gate place, or none is
## replayed.
func _placed(p: Passenger) -> bool:
	return _places == null or _places.placed(p, self)


## Whether a waiting passenger (_add_seekers()) has not joined a queue yet:
## the candidate, a newcomer, gets a place only after every one of them, at
## whichever station played (`_station` is the candidate's, kept for the
## call sites).
func _seekers_ahead(_station: int) -> bool:
	for id: int in _seekers:
		var u: Passenger = _units[id]
		if u.stage == Passenger.Stage.TO_SECURITY and not _left.has(id):
			return true
	return false


## The copies walking to `station`.
func _walkers_to(station: int) -> int:
	var count := 0
	for id: int in _order:
		var u: Passenger = _units[id]
		count += int(u.stage == Passenger.Stage.TO_SECURITY and u.station == station)
	return count


func _add(p: Passenger) -> Passenger:
	var copy := Passenger.new()
	copy.id = p.id
	copy.stage = p.stage
	copy.station = p.station
	copy.at = p.at
	copy.path = p.path.duplicate()
	copy.path_index = p.path_index
	copy.seg_mm = p.seg_mm
	copy.flight_id = p.flight_id
	copy.boarding_tick = p.boarding_tick
	copy.stuck = p.stuck
	copy.carry_on = p.carry_on
	copy.late = p.late
	copy.halt_tick = p.halt_tick
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


## The candidate walking to the queue: it stands on `cell` and joins on
## `join`.
func _add_walker(p: Passenger, join: int, cell: Vector2i, station: int) -> void:
	var copy := _add(p)
	copy.stage = Passenger.Stage.TO_SECURITY
	copy.station = station
	copy.security_phase = SecurityRuntime.Phase.NONE
	copy.security_work = 0
	copy.at = cell
	copy.clear_path()
	# Its walk ends on the tick before it joins (QueueRipple.walk()).
	copy.halt_tick = join - 1
	_joins[copy.id] = join


func _run(target: int) -> int:
	while not _cleared.has(target):
		if _left.has(target):
			return JourneyForecast.NEVER
		var next := _next_event()
		if next < 0 or next - _sim.tick >= HORIZON:
			return JourneyForecast.NEVER
		_skip(next - tick - 1)
		tick = next
		_step()
	return mini(int(_cleared[target]) - _sim.tick, JourneyForecast.NEVER)


## One tick as PassengerSim plays it for this station and its passengers.
func _step() -> void:
	GateCapacity.recover_all(self, _runtime, _stations, _places)
	for at in _stations:
		_runtime.advance(at)
		StationQueue.promote(_queues[at], _cells[at])
	GateCapacity.admit_all(self, _runtime, _stations, _queues, _cells, _opens, _places)
	var walkers: Array[Passenger] = []
	for id in _order:
		var u: Passenger = _units[id]
		if u.stage == Passenger.Stage.TO_SECURITY and not _joins.has(id) and not _left.has(id):
			walkers.append(u)
	for u in StationQueue.arrive(_sim.grid, _queues, _cells, _lines, walkers, _units, tick):
		u.stage = Passenger.Stage.SECURITY_QUEUE
		_changed = true
	for id in _order:
		var u: Passenger = _units[id]
		if _cleared.has(id) or _left.has(id):
			continue
		if u.stage == Passenger.Stage.TO_SECURITY and _joins.has(id):
			if _joins[id] <= tick and not _seekers_ahead(u.station):
				_joins.erase(id)
				StationQueue.join(_queues[u.station], _cells[u.station], id)
				u.stage = Passenger.Stage.SECURITY_QUEUE
				_changed = true
		elif u.stage == Passenger.Stage.TO_SECURITY:
			_seek(u)
		elif u.stage == Passenger.Stage.SECURITY_QUEUE:
			_move_up(u)
		if u.is_moving():
			var was := u.at
			QueueRipple.walk(u, u.pace_mm(), tick)
			_changed = _changed or u.at != was


## PassengerStations.seek() on a standing walker copy: it heads for the next
## free cell of the line or waits for a walker heading for one ahead of it,
## joins when it stands there, or leaves the replay when none is left.
func _seek(u: Passenger) -> void:
	if u.is_moving():
		return
	var queue: Dictionary = _queues[u.station]
	var n := StationQueue.size_of(queue)
	var ends: Array[Vector2i] = []
	for id in _order:
		var other: Passenger = _units[id]
		var walking := other.stage == Passenger.Stage.TO_SECURITY and other.is_moving()
		if other != u and walking and other.station == u.station and not _left.has(id):
			ends.append(other.path_end())
	var line: Array = _lines[u.station]
	var free := StationQueue.free_index(queue, line, _units)
	var target := StationQueue.walker_free(
		free, StationQueue.admitted_at(_units, u.station, line)
	)
	if not StationQueue.head_for(_sim.grid, u, line, n, target, ends):
		# A committed walker with no place left chooses again in the sim; a
		# waiting passenger (_add_seekers()) waits on for one.
		if not _seekers.has(u.id):
			_left[u.id] = true
			_changed = true
		return
	if not u.is_moving() and target == free and free < line.size() and u.at == line[free]:
		StationQueue.join(queue, _cells[u.station], u.id)
		u.stage = Passenger.Stage.SECURITY_QUEUE
		_changed = true
	elif u.is_moving():
		# Set off for the free cell; a walker that only waits changes nothing.
		_changed = true


## Whether standing walker `u` waits on its line cell for another walker
## heading for a cell ahead of it (StationQueue.head_for()).
func _waits(u: Passenger) -> bool:
	var line: Array = _lines[u.station]
	var members_free := StationQueue.free_index(_queues[u.station], line, _units)
	var free := StationQueue.walker_free(
		members_free, StationQueue.admitted_at(_units, u.station, line)
	)
	if free != members_free and line.find(u.at) == free:
		# Behind an admitted passenger: it moves on when that one does.
		return true
	if free >= line.size():
		return StationQueue.size_of(_queues[u.station]) < line.size() or _seekers.has(u.id)
	var here := line.find(u.at)
	if here <= free:
		return false
	for id in _order:
		var other: Passenger = _units[id]
		if other == u or other.station != u.station or _left.has(id):
			continue
		if other.stage == Passenger.Stage.TO_SECURITY and other.is_moving():
			var there := line.find(other.path_end())
			if there >= free and there < here:
				return true
	return false


## PassengerStations.queue_move() on the copy, along the line as there
## (StationQueue.path_to()).
func _move_up(u: Passenger) -> void:
	var members := StationQueue.members(_queues[u.station])
	var line: Array = _lines[u.station]
	if not _misplaced(u) or not QueueRipple.may_step(self, u, members, line, tick, false):
		return
	var path := StationQueue.path_to(_sim.grid, line, u.at, members.find(u.id))
	if path.size() >= 2:
		u.set_path(path)


## A queue member standing still away from its place on the line: it moves
## up on the next tick. A candidate joining a full line (clearance()) has no
## place yet and waits where it stands until one is free.
func _misplaced(u: Passenger) -> bool:
	if u.stage != Passenger.Stage.SECURITY_QUEUE:
		return false
	var index: int = StationQueue.members(_queues[u.station]).find(u.id)
	var line: Array = _lines[u.station]
	return index >= 0 and index < line.size() and not u.is_moving() and u.at != line[index]


## The next tick on which something can change, or -1 when nothing will:
## work running out, a walker reaching a cell (it counts from the tick after,
## so a cell reached on this tick makes the next one count; a walker to the
## queue from the tick it reaches it) or a walker joining the queue.
func _next_event() -> int:
	if _changed:
		_changed = false
		return tick + 1
	var best := -1
	for at in _stations:
		# The repack rate changes on the tick the helper arrives.
		if _helper_from[at] > tick and (best < 0 or _helper_from[at] < best):
			best = _helper_from[at]
	for id in _order:
		if _cleared.has(id) or _left.has(id):
			continue
		var u: Passenger = _units[id]
		var at := -1
		if _joins.has(id):
			# Behind waiting passengers it joins once they have: their joins
			# are events of their own.
			if not _seekers_ahead(u.station):
				at = maxi(_joins[id], tick + 1)
		elif u.stage == Passenger.Stage.TO_SECURITY and not u.is_moving():
			# A standing walker heads on or joins on the next tick, unless it
			# waits for another (StationQueue.head_for()), which is that one's
			# event.
			if not _waits(u):
				at = tick + 1
		elif u.is_moving():
			var left := Passenger.segment_mm(u.path[u.path_index], u.path[u.path_index + 1])
			at = tick + u.pace_ticks(left - u.seg_mm) + 1
			# A walker to the queue may join on the tick it reaches the line
			# (StationQueue.arrive()), so that tick is played, not skipped.
			if u.stage == Passenger.Stage.TO_SECURITY:
				at -= 1
			# Stepping off the pickup cell, it frees it half way
			# (SecurityRuntime._pickup_free()).
			var off := (
				u.security_phase in [SecurityRuntime.Phase.LEAVE, SecurityRuntime.Phase.TO_BERTH]
			)
			if off and u.seg_mm * 2 < left:
				@warning_ignore("integer_division")
				at = mini(at, tick + u.pace_ticks((left + 1) / 2 - u.seg_mm) + 1)
		elif u.stage == Passenger.Stage.SECURITY_QUEUE and _misplaced(u):
			at = tick + 1
		# Work that has run out waits on something else, which is its own event.
		if u.stage == Passenger.Stage.SECURITY and _works(u) and u.security_work > 0:
			var rate := maxi(1, _runtime.rate(u.station, u.security_phase))
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
		if _cleared.has(id) or _left.has(id):
			continue
		var u: Passenger = _units[id]
		if u.stage == Passenger.Stage.SECURITY and _works(u):
			u.security_work -= ticks * _runtime.rate(u.station, u.security_phase)
		if u.is_moving():
			u.walk(ticks * u.pace_mm())


static func _works(u: Passenger) -> bool:
	return SecurityRuntime.WORK_PHASES.has(u.security_phase as SecurityRuntime.Phase)
