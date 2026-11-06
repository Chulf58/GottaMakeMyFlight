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
## holding to lane, admission; then the line rules of StationQueue.arrive():
## walkers entering the line join its queue and the rest head for its tail;
## then each passenger in id order: a member moving up the line, every walker
## walking at the pace the sim gives it, Passenger.pace_mm(): a run while late,
## board b13ac401), but skips the ticks on which nothing can change: no work
## runs out and nobody reaches a cell or joins. A walker with no way to the
## line chooses again in the sim; it leaves the replay, and one forecast for it
## is NEVER. Read between
## ticks it is exact while no one turns late or stops being late (lateness is
## taken as it is now). Whether the station is open is taken as it
## is now: a closed station admits nobody new. Staff are not stepped: a lane's
## helper speeds the replayed repacks from the tick StaffPosts.helper_from()
## gives (now when on duty, its arrival when walking there, read after the
## next staff step when that step will plan its path again or move it to
## another post), and that tick is an event the replay does not skip past.
##
## Waiting passengers (PassengerStations.seekers_before(): done at a desk while
## every line is full, or walking to security with no station) are replayed as
## the sim plays them. They wait where they are until a place is free for them:
## the free places of the open lines (PassengerStations._room()) go to them by
## how long they have waited, the oldest first, and each then chooses its line
## by the sim's own estimate (PassengerStations.estimate(), in id order as the
## sim steps them) and walks there from where it waits. While any wait,
## every security station is played, so the places freed anywhere are seen.
## The candidate (clearance()) takes its place among them by its own wait, on
## its station only, and enters the line there by the line rules.
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
## By station, for the tick being played: its queue's members (StationQueue.members()) with
## id -> index, built when first asked for and dropped when a queue changes
## (_drop_members()).
var _members := {}
var _member_at := {}
## The copied gate places, or null when no admission waits for one.
var _places: GateCapacity
## Passenger id -> its copy.
var _units := {}
## The copies' ids, ascending: the order PassengerSim steps passengers in.
var _order: Array[int] = []
## Passenger id -> the tick the candidate (clearance()), on its way with a
## place, reaches it; it is not walked.
var _joins := {}
## Ids of walkers that left the replay: no free cell was left for them.
var _left := {}
## The ids of the copies waiting for a place (the waiting passengers and the
## candidate, _add_waiting()), by how long they have waited
## (PassengerStations.wait_key()), the oldest first.
var _waiting: Array[int] = []
## Copy id -> its wait key, for the waiting copies.
var _keys := {}
## The candidate's id (clearance()), or 0 when there is none; the station it
## is forecast at, and the ticks it walks from where it waits to that line.
var _candidate := 0
var _candidate_station := 0
var _candidate_walk := 0
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
	# One committed to `station` is replayed where it is; any other is the
	# candidate, even one waiting for a place.
	replay._setup(
		sim, station, sim.gates.scarce(sim, station, p), 0 if p.station == station else p.id
	)
	var ticks := JourneyForecast.NEVER
	if replay._units.has(p.id) or replay._opens[station]:
		if not replay._units.has(p.id):
			replay._add_walker(p, maxi(join_tick, sim.tick + 1), station)
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


## Copies `station`'s state, and every security station's when gate places
## are `scarce` (GateCapacity.scarce(), the places are copied too) or when a
## passenger waits for a place. `candidate` (0: none) is left out: clearance()
## adds it.
func _setup(sim: PassengerSim, station: int, scarce: bool, candidate := 0) -> void:
	_sim = sim
	tick = sim.tick
	layout = sim.layout
	_candidate = candidate
	var waiting: Array[Passenger] = []
	for p in sim._passengers:
		if p.id != candidate and PassengerStations.is_seeking(sim, p, false):
			waiting.append(p)
	_stations = [station]
	if scarce:
		_places = sim.gates.copy(sim)
	if scarce or not waiting.is_empty():
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
		var walking := walker.stage == Passenger.Stage.TO_SECURITY and id != candidate
		if walking and _opens.has(walker.station):
			_add(walker)
	for p in waiting:
		_add_waiting(p)


## A copy of waiting passenger `p` (PassengerStations.is_seeking()): it stands
## where it is, finishing the step it is on, with no station until a place is
## free for it (_place_waiting()).
func _add_waiting(p: Passenger) -> void:
	var copy := _add(p)
	copy.stage = Passenger.Stage.TO_SECURITY
	copy.station = 0
	copy.security_phase = SecurityRuntime.Phase.NONE
	copy.security_work = 0
	_wait(copy.id, PassengerStations.wait_key(p, false))


## Puts `id` among the waiting copies by its wait `key`.
func _wait(id: int, key: Vector2i) -> void:
	_keys[id] = key
	var at := 0
	while at < _waiting.size() and _keys[_waiting[at]] < key:
		at += 1
	_waiting.insert(at, id)


## Whether a copy may be cleared: it holds a copied gate place, or none is
## replayed.
func _placed(p: Passenger) -> bool:
	return _places == null or _places.placed(p, self)


## Gives the free places of the played lines to the waiting copies, the oldest
## first, as PassengerStations._room_now() and choose() do: those with a place
## choose in id order, each the line PassengerStations.estimate() finishes it
## soonest at among those with a free cell (ties to the lower station id), and
## set off for it from where they are; the candidate takes a free cell of its
## own station only, reached when its walk is over (_joins). One with no place
## yet waits, and so does every one who has waited less.
func _place_waiting() -> void:
	if _waiting.is_empty():
		return
	var slots := {}
	var room := 0
	for at in _stations:
		if _opens[at]:
			slots[at] = StationQueue.size_of(_queues[at]) + _walkers_to(at)
			room += maxi((_lines[at] as Array).size() - int(slots[at]), 0)
	var placed: Array[int] = []
	var at := 0
	while room > 0 and at < _waiting.size():
		var id: int = _waiting[at]
		if id == _candidate:
			var own := _candidate_station
			if not slots.has(own) or slots[own] >= (_lines[own] as Array).size():
				break
		placed.append(id)
		room -= 1
		at += 1
	if placed.is_empty():
		return
	_waiting = _waiting.slice(placed.size())
	placed.sort()
	for id in placed:
		var u: Passenger = _units[id]
		if id == _candidate:
			var own := _candidate_station
			u.station = own
			u.at = _lines[own][slots[own]]
			_joins[id] = tick + _candidate_walk
			# Its walk ends on the tick before it gets there (QueueRipple.walk()).
			u.halt_tick = _joins[id] - 1
			slots[own] += 1
			continue
		var best := -1
		var best_eta := 0
		var best_path: Array[Vector2i] = []
		for station: int in _stations:
			var line: Array = _lines[station]
			if not slots.has(station) or slots[station] >= line.size():
				continue
			var path := StationQueue.approach(_sim.grid, line, u.at, slots[station])
			if path.is_empty():
				continue
			var walk := u.pace_ticks(Passenger.path_mm(path))
			var eta := PassengerStations.estimate(
				_runtime, self, station, _members_of(station), _walkers_of(station), walk, u
			)
			if best < 0 or eta < best_eta:
				best = station
				best_eta = eta
				best_path = path
		if best < 0:
			# No way to any line: it waits on, as one with no route does.
			_left[id] = true
			continue
		u.station = best
		u.clear_path()
		if best_path.size() >= 2:
			u.set_path(best_path)
		slots[best] += 1
	_changed = true


## The copies walking to `station`.
func _walkers_of(station: int) -> Array[Passenger]:
	var out: Array[Passenger] = []
	for id: int in _order:
		var u: Passenger = _units[id]
		if u.stage == Passenger.Stage.TO_SECURITY and u.station == station and not _left.has(id):
			out.append(u)
	return out


## The copies walking to `station`, the candidate with a place among them.
func _walkers_to(station: int) -> int:
	var count := 0
	for id: int in _order:
		var u: Passenger = _units[id]
		var walking := u.stage == Passenger.Stage.TO_SECURITY and u.station == station
		count += int(walking and not _left.has(id))
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


## The candidate: it waits for a place on `station`'s line among the waiting
## copies (_place_waiting()); with one, it takes as long to reach it as from
## now to `join`, and is not walked.
func _add_walker(p: Passenger, join: int, station: int) -> void:
	var copy := _add(p)
	copy.stage = Passenger.Stage.TO_SECURITY
	copy.station = 0
	copy.security_phase = SecurityRuntime.Phase.NONE
	copy.security_work = 0
	copy.clear_path()
	_candidate = copy.id
	_candidate_station = station
	_candidate_walk = join - (tick + 1)
	# It waits as long as the passenger it stands for, when that one is in the
	# sim (a forecast's copy of it may not carry its check-in end).
	var own: Passenger = _sim._by_id.get(p.id, p)
	_wait(copy.id, PassengerStations.wait_key(own, false))


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
	_drop_members()
	if _joins.has(_candidate) and _joins[_candidate] <= tick:
		# The candidate has reached its place: a walker standing there.
		_joins.erase(_candidate)
		_changed = true
	var walkers: Array[Passenger] = []
	var before := []
	for id in _order:
		var u: Passenger = _units[id]
		var walker := u.stage == Passenger.Stage.TO_SECURITY and u.station != 0
		if walker and not _joins.has(id) and not _left.has(id):
			walkers.append(u)
			before.append([u.at, u.path_end()])
	var stranded: Array = []
	var joined := StationQueue.arrive(
		_sim.grid, _queues, _cells, _lines, walkers, _units, tick, stranded
	)
	for u in joined:
		u.stage = Passenger.Stage.SECURITY_QUEUE
		_changed = true
		_drop_members()
	for u: Passenger in stranded:
		# A committed walker with no way to the line chooses again in the sim.
		_left[u.id] = true
		_changed = true
	# A walker the pass sent on, turned round or set off changes the next
	# tick's order and cells, so that tick is played.
	for i in walkers.size():
		if _changed:
			break
		var u := walkers[i]
		_changed = u.at != before[i][0] or u.path_end() != before[i][1]
	_place_waiting()
	for id in _order:
		var u: Passenger = _units[id]
		if _cleared.has(id) or _left.has(id):
			continue
		if u.stage == Passenger.Stage.SECURITY_QUEUE:
			_move_up(u)
		if u.is_moving():
			var was := u.at
			QueueRipple.walk(u, u.pace_mm(), tick)
			_changed = _changed or u.at != was


## The members of `station`'s queue and their indexes (StationQueue.members()),
## for the tick being played.
func _members_of(station: int) -> Array:
	if not _members.has(station):
		var members := StationQueue.members(_queues[station])
		var index := {}
		for i in members.size():
			index[members[i]] = i
		_members[station] = members
		_member_at[station] = index
	return _members[station]


## Drops the members cached by _members_of(): a queue has changed.
func _drop_members() -> void:
	_members.clear()
	_member_at.clear()


## PassengerStations.queue_move() on the copy, along the line as there
## (StationQueue.path_to()).
func _move_up(u: Passenger) -> void:
	if not _misplaced(u):
		return
	var members := _members_of(u.station)
	var line: Array = _lines[u.station]
	if not QueueRipple.may_step(self, u, members, line, tick, false):
		return
	var path := StationQueue.path_to(_sim.grid, line, u.at, _member_at[u.station][u.id])
	if path.size() >= 2:
		u.set_path(path)
		# The cell it steps onto is taken from now: the line's pass on the
		# next tick may send a walker on.
		_changed = true


## A queue member standing still away from its place on the line: it moves
## up on the next tick.
func _misplaced(u: Passenger) -> bool:
	if u.stage != Passenger.Stage.SECURITY_QUEUE or u.is_moving():
		return false
	_members_of(u.station)
	var index: int = _member_at[u.station].get(u.id, -1)
	var line: Array = _lines[u.station]
	return index >= 0 and index < line.size() and u.at != line[index]


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
			at = maxi(_joins[id], tick + 1)
		elif u.stage == Passenger.Stage.TO_SECURITY and not u.is_moving():
			# Waiting for a place or for the line to move: the line's pass sets
			# it off on the tick after another's event changes either.
			pass
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
		elif u.stage == Passenger.Stage.SECURITY and not (_works(u) and u.security_work > 0):
			# Standing inside with no work left: it waits for a cell or a place
			# that frees on a tick of its own, which is played.
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
