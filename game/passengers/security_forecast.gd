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
## runs out, nobody joins, and nobody reaches a cell that the next tick reads
## (_reach_counts(): a queue member walking on counts only when it moves its
## line's free cell, an admitted passenger walking on only on or off its
## station's line or on its way back from the berth). A walker with no way to the
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
## freed later (a passenger boarding or visiting a facility) is not foreseen.
## The front's own boarding opening is: it then needs no place
## (GateCapacity.placed()) and is admitted on that tick. Otherwise only the station itself
## is played, and no admission waits for a place.

## Far enough that a replay this long has gone wrong.
const HORIZON := 200000

## Ticks played by every replay so far: the work the forecast costs, which
## TestHoldLineForecast bounds per forecast.
static var steps_played := 0
## The last waiting passenger's own clearance (clearance()): [key, ticks].
static var _waiting_memo := []
## While a tick's boundary is forecast (begin_boundary()): its sim, whether a
## passenger waits for a place there, and its population replays by
## [station (-1: every station, while one waits), scarce].
static var _boundary_sim: PassengerSim = null
static var _boundary_waiting := false
static var _boundary := {}
## The candidates' clearances forecast at the boundary, by [candidate id and
## traits, station, join tick, scarce] (clearance()).
static var _candidates := {}
## Replays set up so far, for tests that count the work.
static var replays_played := 0
## Set by TestForecastSkipExact: every replay plays every tick until its
## passenger is cleared or HORIZON, never asking _next_event() whether
## anything can happen, the reference the skipped ticks are checked against.
static var every_tick := false

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
## The copied claims on the lines' tails (PassengerSim._claims).
var _claims := {}
## What StationQueue.arrive() keeps from one tick to the next: the grid and
## the lines do not change in a replay.
var _known := {}
## By station: its line's index (StationQueue.line_index()), for _frees().
var _indexes := {}
## The copied gate places, or null when no admission waits for one.
var _places: GateCapacity
## Passenger id -> its copy.
var _units := {}
## The copies' ids, ascending: the order PassengerSim steps passengers in.
var _order: Array[int] = []
## The ids of _order the replay steps: all but the waiting copies standing
## where they wait, which nothing moves until they have a place, and the
## copies cleared or gone from the replay (_cleared, _left).
var _active: Array[int] = []
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
## Whether a walker reached a new cell that counts (_reach_counts()), a queue
## member moved its line's free cell (_free_moved()) or someone joined the
## queue on the tick just played: the next tick can then change something.
## True at the start, as
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
	if sim == _boundary_sim and sim._by_id.get(p.id) == p:
		var mine := p.station == station or PassengerStations.is_seeking(sim, p, false)
		if mine:
			return _from_population(sim, station, p)
	if sim._by_id.get(p.id) == p and PassengerStations.is_seeking(sim, p, false):
		return _waiting_clearance(sim, station, p)
	var scarce := sim.gates.scarce(sim, station, p)
	var key := []
	if sim == _boundary_sim and p.station != station:
		# At the boundary one state answers every ask: the same candidate on
		# the same terms has the same clearance (VisitForecast asks again).
		key = [p.id, p.carry_on, p.liquids, p.alarm, p.late, station, join_tick, scarce]
		if _candidates.has(key):
			return _candidates[key]
	var replay := SecurityForecast.new()
	replays_played += 1
	# One committed to `station` is replayed where it is; any other is the
	# candidate.
	replay._setup(sim, station, scarce, 0 if p.station == station else p.id)
	var ticks := JourneyForecast.NEVER
	if replay._units.has(p.id) or replay._opens[station]:
		if not replay._units.has(p.id):
			replay._add_walker(p, maxi(join_tick, sim.tick + 1), station)
		ticks = replay._run(p.id)
	# The runtime holds the replay as its host: let go, or neither is freed.
	replay._runtime.bind(null)
	if not key.is_empty():
		_candidates[key] = ticks
	return ticks


## Starts forecasting `sim` at one boundary of its tick: until end_boundary(),
## the clearance of a passenger of the sim committed to its station or waiting
## for a place comes from one population replay per [station, scarce], run on
## for each passenger asked about, with no candidate (_from_population()).
static func begin_boundary(sim: PassengerSim) -> void:
	end_boundary()
	_boundary_sim = sim
	_boundary_waiting = false
	for p in sim._passengers:
		if PassengerStations.is_seeking(sim, p, false):
			_boundary_waiting = true
			break


## Ends the boundary begin_boundary() started and lets go of its replays.
static func end_boundary() -> void:
	for replay: SecurityForecast in _boundary.values():
		# The runtime holds the replay as its host: let go, or neither is freed.
		replay._runtime.bind(null)
	_boundary.clear()
	_candidates.clear()
	_boundary_sim = null


## clearance() of `p` from the boundary's population replay.
static func _from_population(sim: PassengerSim, station: int, p: Passenger) -> int:
	var scarce := sim.gates.scarce(sim, station, p)
	var key := [-1 if _boundary_waiting else station, scarce]
	if not _boundary.has(key):
		var made := SecurityForecast.new()
		replays_played += 1
		made._setup(sim, station, scarce)
		_boundary[key] = made
	var replay: SecurityForecast = _boundary[key]
	return replay._run(p.id) if replay._units.has(p.id) else JourneyForecast.NEVER


## clearance() of passenger `p` of the sim, waiting for a place: it takes the
## line the sim's own rule (PassengerStations.estimate()) gives it, whichever
## station is asked about, so one replay answers for every station. The
## answer is kept for the next ask about it on the same tick with the queues
## as they were (JourneyForecast asks once per scanner in a row).
static func _waiting_clearance(sim: PassengerSim, station: int, p: Passenger) -> int:
	var scarce := sim.gates.scarce(sim, station, p)
	var key := [sim.get_instance_id(), sim.tick, p.id, scarce, sim._incoming.duplicate()]
	for at: int in sim.layout.scanners:
		if sim._queues.has(at):
			key.append(StationQueue.members(sim._queues[at]))
	if not _waiting_memo.is_empty() and _waiting_memo[0] == key:
		return _waiting_memo[1]
	var replay := SecurityForecast.new()
	replays_played += 1
	replay._setup(sim, station, scarce)
	var ticks := replay._run(p.id) if replay._units.has(p.id) else JourneyForecast.NEVER
	# The runtime holds the replay as its host: let go, or neither is freed.
	replay._runtime.bind(null)
	_waiting_memo = [key, ticks]
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
			replays_played += 1
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
	# Nothing is played for it from now on.
	_active.erase(p.id)


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
	_claims = sim._claims.duplicate()
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
	if not copy.is_moving():
		_active.erase(copy.id)


## Steps copy `id` from now on (_active).
func _activate(id: int) -> void:
	var at := _active.bsearch(id)
	if at >= _active.size() or _active[at] != id:
		_active.insert(at, id)


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
## yet waits, and so does every one who has waited less. `counts` holds, by
## station, the walkers on their way to it.
func _place_waiting(counts: Dictionary) -> void:
	var slots := {}
	var room := 0
	for at in _stations:
		if _opens[at]:
			slots[at] = StationQueue.size_of(_queues[at]) + int(counts.get(at, 0))
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
		_activate(id)
		var u: Passenger = _units[id]
		if id == _candidate:
			var own := _candidate_station
			if slots[own] >= (_lines[own] as Array).size():
				# Taken by one who chose before it on this tick: it waits on.
				_wait(id, _keys[id])
				continue
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
			# Every free cell was taken by one who chose before it on this
			# tick, or none can be walked to: it waits on.
			_wait(id, _keys[id])
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
	for id: int in _active:
		var u: Passenger = _units[id]
		if u.stage == Passenger.Stage.TO_SECURITY and u.station == station and not _left.has(id):
			out.append(u)
	return out


func _add(p: Passenger) -> Passenger:
	var copy := Passenger.new()
	copy.id = p.id
	copy.stage = p.stage
	copy.stage_tick = p.stage_tick
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
	_activate(copy.id)
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
		steps_played += 1
	return mini(int(_cleared[target]) - _sim.tick, JourneyForecast.NEVER)


## One tick as PassengerSim plays it for this station and its passengers.
func _step() -> void:
	GateCapacity.recover_all(self, _runtime, _stations, _places)
	# Promotion keeps the members' order; only an admission changes them.
	var queued := 0
	for at in _stations:
		_runtime.advance(at)
		StationQueue.promote(_queues[at], _cells[at])
		queued += StationQueue.size_of(_queues[at])
	GateCapacity.admit_all(self, _runtime, _stations, _queues, _cells, _opens, _places)
	for at in _stations:
		queued -= StationQueue.size_of(_queues[at])
	if queued != 0:
		_drop_members()
	if _joins.has(_candidate) and _joins[_candidate] <= tick:
		# The candidate has reached its place: a walker standing there.
		_joins.erase(_candidate)
		_changed = true
	var walkers: Array[Passenger] = []
	var before := []
	for id in _active:
		var u: Passenger = _units[id]
		var walker := u.stage == Passenger.Stage.TO_SECURITY and u.station != 0
		if walker and not _joins.has(id) and not _left.has(id):
			walkers.append(u)
			before.append([u.at, u.path_end()])
	var stranded: Array = []
	var joined := StationQueue.arrive(
		_sim.grid, _queues, _cells, _lines, walkers, _units, tick, stranded, _claims, _known
	)
	for u in joined:
		u.stage = Passenger.Stage.SECURITY_QUEUE
		_changed = true
		_drop_members()
	for u: Passenger in stranded:
		# A committed walker with no way to the line chooses again in the sim.
		_left[u.id] = true
		_active.erase(u.id)
		_changed = true
	# A walker the pass sent on, turned round or set off changes the next
	# tick's order and cells, so that tick is played.
	for i in walkers.size():
		if _changed:
			break
		var u := walkers[i]
		_changed = u.at != before[i][0] or u.path_end() != before[i][1]
	if not _waiting.is_empty():
		# The walkers each line has now, the candidate on its way among them.
		var counts := {}
		for u in walkers:
			if u.stage == Passenger.Stage.TO_SECURITY and not _left.has(u.id):
				counts[u.station] = counts.get(u.station, 0) + 1
		if _joins.has(_candidate):
			var own: int = _units[_candidate].station
			counts[own] = counts.get(own, 0) + 1
		_place_waiting(counts)
	# Queue member id -> what it held of its line before it set off or reached
	# a cell on this tick (_holds()).
	var held := {}
	# _active holds no copy cleared or gone from the replay.
	for id in _active:
		var u: Passenger = _units[id]
		if u.stage == Passenger.Stage.SECURITY_QUEUE and _move_up(u) and not _changed:
			held[id] = _holds(u.station, u.at, u.at)
		if u.is_moving():
			var from := u.at
			var step := u.path_index
			QueueRipple.walk(u, u.pace_mm(), tick)
			if u.at != from and not _changed:
				_changed = _reach_counts(u, from)
				if not _changed and u.stage == Passenger.Stage.SECURITY_QUEUE and not held.has(id):
					held[id] = _holds(u.station, from, u.path[step + 1])
	if not _changed and not held.is_empty():
		_changed = _free_moved(held)


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
## (StationQueue.path_to()): true when it sets off.
func _move_up(u: Passenger) -> bool:
	if not _misplaced(u):
		return false
	var members := _members_of(u.station)
	var line: Array = _lines[u.station]
	if not QueueRipple.may_step(self, u, members, line, tick, false):
		return false
	var path := StationQueue.path_to(_sim.grid, line, u.at, _member_at[u.station][u.id])
	if path.size() < 2:
		return false
	# The cell it steps onto is taken from now; when that moves the line's free
	# cell, the next tick is played (_step()).
	u.set_path(path)
	return true


## A queue member standing still away from its place on the line: it moves
## up on the next tick.
func _misplaced(u: Passenger) -> bool:
	if u.stage != Passenger.Stage.SECURITY_QUEUE or u.is_moving():
		return false
	_members_of(u.station)
	var index: int = _member_at[u.station].get(u.id, -1)
	var line: Array = _lines[u.station]
	return index >= 0 and index < line.size() and u.at != line[index]


## What a queue member of `station` standing on `at` and stepping onto `onto`
## (`at` when standing still) holds of its line's free cell
## (StationQueue.free_index()): one past the line index of each, 0 off the
## line.
func _holds(station: int, at: Vector2i, onto: Vector2i) -> int:
	if not _indexes.has(station):
		_indexes[station] = StationQueue.line_index(_lines[station])
	var index: Dictionary = _indexes[station]
	return maxi(int(index.get(at, -1)), int(index.get(onto, -1))) + 1


## Whether a line's free cell (StationQueue.free_index()) moved on this tick,
## when the queue members of `held` set off or reached a cell (id -> what each
## held before, _holds()) and nobody joined or left the queue: the line rules
## of the next tick then read another tail.
func _free_moved(held: Dictionary) -> bool:
	var stations := {}
	for id: int in held:
		stations[(_units[id] as Passenger).station] = true
	for station: int in stations:
		var queue: Dictionary = _queues[station]
		var rest := StationQueue.size_of(queue)
		var before := 0
		var after := 0
		for id: int in StationQueue.members(queue):
			var p: Passenger = _units[id]
			var now := _holds(station, p.at, p.path[p.path_index + 1] if p.is_moving() else p.at)
			if held.has(id):
				before = maxi(before, held[id])
				after = maxi(after, now)
			else:
				rest = maxi(rest, now)
		if maxi(rest, before) != maxi(rest, after):
			return true
	return false


## Whether walker `u`, which stepped from `was` onto a new cell on this tick,
## can change the next tick by it. One that stopped there can, and so can a
## walker to the queue (the line rules read its next step). A queue member
## walking on changes the next tick only through its line's free cell, which
## _step() compares. An admitted passenger walking on can only through
## _cell_counts().
func _reach_counts(u: Passenger, was: Vector2i) -> bool:
	if not u.is_moving() or u.stage == Passenger.Stage.TO_SECURITY:
		return true
	if u.stage == Passenger.Stage.SECURITY_QUEUE:
		return false
	return _cell_counts(u, was, u.at)


## Whether admitted passenger `u`, walking on past `to` after a step from
## `from`, changes what the next tick reads: the line rules read the line
## cells admitted passengers stand on (StationQueue.tail()), and a returning
## passenger gives up the berth once it has stepped off it
## (SecurityRuntime._advance_one()). Nothing else reads where an admitted
## passenger is while it walks on.
func _cell_counts(u: Passenger, from: Vector2i, to: Vector2i) -> bool:
	if u.security_phase == SecurityRuntime.Phase.RETURN:
		return true
	var line: Array = _lines[u.station]
	return line.has(from) or line.has(to)


## The walk, in mm, that moving admitted passenger `u` makes past the cell it
## steps onto before it reaches a cell that counts (_cell_counts(), or the end
## of its path): the ticks it walks through the cells between are not played.
func _walk_on_mm(u: Passenger) -> int:
	var mm := 0
	var i := u.path_index + 1
	while i + 1 < u.path.size() and not _cell_counts(u, u.path[i - 1], u.path[i]):
		mm += Passenger.segment_mm(u.path[i], u.path[i + 1])
		i += 1
	return mm


## The next tick on which something can change, or -1 when nothing will:
## work running out, a walker reaching a cell (it counts from the tick after,
## so a cell reached on this tick makes the next one count; a walker to the
## queue from the tick it reaches it; an admitted passenger walking on from
## the tick after the first cell that counts, _walk_on_mm()), a walker
## joining the queue, or the boarding of a front held for a gate place
## opening.
func _next_event() -> int:
	if _changed:
		_changed = false
		return tick + 1
	var best := -1
	for at in _stations:
		# The repack rate changes on the tick the helper arrives.
		if _helper_from[at] > tick and (best < 0 or _helper_from[at] < best):
			best = _helper_from[at]
	for station: int in _claims:
		# The claim on a tail passes to a walker PASS_TICKS sooner there
		# (StationQueue._pass_claim()). While both walk, each one's ticks to
		# the tail fall by one a tick until it reaches a cell, an event of its
		# own, so the claim cannot pass between; a claimant standing still
		# can be passed by any tick, so every tick is played.
		var holder: Passenger = _units.get(_claims[station])
		var walking := holder != null and holder.stage == Passenger.Stage.TO_SECURITY
		if walking and not holder.is_moving() and not _left.has(holder.id):
			return tick + 1
	for id in _active:
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
			var to_cell := left - u.seg_mm
			if u.stage == Passenger.Stage.SECURITY:
				to_cell += _walk_on_mm(u)
			at = tick + u.pace_ticks(to_cell) + 1
			# A walker to the queue may join on the tick it reaches the line
			# (StationQueue.arrive()), so that tick is played, not skipped. So
			# is the tick a queue member reaches a cell: one behind it, stepped
			# after it, sees it there on that tick (QueueRipple.may_step()),
			# and its halt_tick is set when its walk ends there.
			if u.stage in [Passenger.Stage.TO_SECURITY, Passenger.Stage.SECURITY_QUEUE]:
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
			at = tick + 1 if every_tick else _move_up_at(u)
		elif u.stuck == Passenger.Stuck.GATE_FULL and u.boarding_tick > tick:
			# A front held for a gate place needs none once its boarding opens
			# (GateCapacity.placed()), and is admitted on that tick.
			at = u.boarding_tick
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
	return tick + 1 if every_tick else best


## The next tick misplaced queue member `u` may step up on
## (QueueRipple.may_step()), or -1 when it waits on the one ahead walking or
## setting off, which happens on a tick the replay plays (its cell reached,
## its own move-up). Behind a roller that one has not stood STAND_TICKS yet,
## it is the tick it has.
func _move_up_at(u: Passenger) -> int:
	var members := _members_of(u.station)
	var line: Array = _lines[u.station]
	if QueueRipple.may_step(self, u, members, line, tick + 1, false):
		return tick + 1
	var index: int = _member_at[u.station][u.id]
	var ahead: Passenger = _units[members[index - 1]]
	if ahead.is_moving() or ahead.at != line[index - 1]:
		return -1
	return ahead.halt_tick + QueueRipple.STAND_TICKS


## Plays `ticks` ticks on which nothing changes: work runs down and walkers
## move, none of them reaching a new cell.
func _skip(ticks: int) -> void:
	if ticks <= 0:
		return
	for id in _active:
		if _cleared.has(id) or _left.has(id):
			continue
		var u: Passenger = _units[id]
		if u.stage == Passenger.Stage.SECURITY and _works(u):
			u.security_work -= ticks * _runtime.rate(u.station, u.security_phase)
		if u.is_moving():
			u.walk(ticks * u.pace_mm())


static func _works(u: Passenger) -> bool:
	return SecurityRuntime.WORK_PHASES.has(u.security_phase as SecurityRuntime.Phase)
