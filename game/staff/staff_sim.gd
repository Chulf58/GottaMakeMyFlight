class_name StaffSim
extends Node
## The staff pool as plain data. The player hires check-in agents and security
## officers by role; nobody places them. An idle member walks on its own to
## the nearest usable desk or scanner of its role that nobody else has claimed
## (the shortest grid path, ties to the lower station id), entering through
## the terminal's first entrance when it comes from the pool. A station counts
## as staffed only while its member is on duty at its service cell; until then
## PassengerSim keeps it closed. A member whose station is removed or stops
## being usable goes idle where it stands; one whose cell is built over goes
## back to the pool.
##
## PassengerSim steps it at the start of each tick, so every passenger step
## reads one staff state. Members are handled in id order, distances are whole
## millimetres and nothing is random, so a snapshot loaded at a tick boundary
## plays out exactly like continuous play. A search that finds no station is
## retried on the member's beat (once a simulated second, staggered by id).

## Hiring, firing and loading; the counts may have changed.
signal staff_changed
signal member_state_changed(id: int, state: StaffMember.State)

const SAVE_VERSION := 1

var sim: PassengerSim

var _members: Array[StaffMember] = []
var _by_id: Dictionary = {}
var _next_id := 1
## Derived: station id -> the member walking to it or on duty there.
var _claims: Dictionary = {}


## Called by PassengerSim.bind() once its layout is built.
func bind(with_sim: PassengerSim) -> void:
	sim = with_sim
	sim.grid.graph_changed.connect(_on_graph_changed)
	_reconcile()


## Hires a member of `role` into the pool and returns its id, or 0 with an
## error for an unknown role. It sets out on the next tick.
func hire(role: StaffMember.Role) -> int:
	if not StaffMember.Role.values().has(role):
		push_error("StaffSim.hire: unknown role %d" % role)
		return 0
	var m := StaffMember.new()
	m.id = _next_id
	_next_id += 1
	m.role = role
	_members.append(m)
	_by_id[m.id] = m
	staff_changed.emit()
	return m.id


## Lets one member of `role` go: an idle one if any, else one still walking,
## else one on duty; the highest id within each. A member on duty with a
## passenger in service is not gone at once: it is marked leaving, its station
## takes nobody new (is_open() is false) and it leaves on the first tick after
## that service ends, so the station is never unstaffed while it serves.
## Until then it still counts in count() and on_duty_count(), and in
## leaving_count(). Returns false, changing nothing, when every member of
## that role is already leaving or none is hired.
func fire(role: StaffMember.Role) -> bool:
	for state in [StaffMember.State.IDLE, StaffMember.State.TO_STATION, StaffMember.State.ON_DUTY]:
		for i in range(_members.size() - 1, -1, -1):
			var m := _members[i]
			if m.role != role or m.state != state or m.leaving:
				continue
			if state == StaffMember.State.ON_DUTY and _in_service(m.station):
				m.leaving = true
			else:
				_remove(m)
			staff_changed.emit()
			return true
	return false


## Members of `role` still employed, those leaving included.
func count(role: StaffMember.Role) -> int:
	var n := 0
	for m in _members:
		n += int(m.role == role)
	return n


## Members of `role` fired mid-service who have not left yet.
func leaving_count(role: StaffMember.Role) -> int:
	var n := 0
	for m in _members:
		n += int(m.role == role and m.leaving)
	return n


func on_duty_count(role: StaffMember.Role) -> int:
	var n := 0
	for m in _members:
		n += int(m.role == role and m.state == StaffMember.State.ON_DUTY)
	return n


func member_ids() -> Array[int]:
	var ids: Array[int] = []
	for m in _members:
		ids.append(m.id)
	return ids


func get_member(id: int) -> StaffMember:
	return _by_id.get(id)


## Whether a member is on duty at the station: only then is it open.
func is_staffed(station: int) -> bool:
	var id: int = _claims.get(station, 0)
	return id != 0 and (_by_id[id] as StaffMember).state == StaffMember.State.ON_DUTY


## Whether passengers are served at a desk or scanner: it is usable
## (TerminalLayout.is_usable()) and a member is on duty there who is not
## leaving. Closed stations are what a closed sign marks.
func is_open(station: int) -> bool:
	if not sim.layout.is_usable(station) or not is_staffed(station):
		return false
	return not (_by_id[_claims[station]] as StaffMember).leaving


## The member walking to or on duty at the station, or 0.
func staff_at(station: int) -> int:
	return _claims.get(station, 0)


## Where a member on the floor stands on this tick, in world space.
func world_position(m: StaffMember) -> Vector3:
	var at := m.grid_position()
	return sim.grid.origin + Vector3(at.x, 0.0, at.y)


func step() -> void:
	_reconcile()
	for m in _members:
		if m.state == StaffMember.State.IDLE and (not m.search_failed or _beat(m)):
			_assign(m)
		if m.state == StaffMember.State.TO_STATION:
			_walk(m)


func to_snapshot() -> Dictionary:
	_reconcile()
	return StaffSnapshot.save(_members, _next_id)


## Restores a to_snapshot() dictionary, including one that went through JSON.
## Load it after PassengerSim.from_snapshot(), whose layout it is checked
## against. Pushes an error and returns false, leaving the staff unchanged,
## when anything is missing, mistyped or inconsistent.
func from_snapshot(data: Dictionary) -> bool:
	var loaded := StaffSnapshot.load(data, sim)
	if loaded.has("error"):
		push_error("StaffSim.from_snapshot: %s" % loaded["error"])
		return false
	_next_id = loaded["next_id"]
	_members.assign(loaded["members"])
	rederive()
	staff_changed.emit()
	return true


## Rebuilds what is derived from the member records.
func rederive() -> void:
	_by_id.clear()
	_claims.clear()
	for m in _members:
		_by_id[m.id] = m
		if m.station != 0:
			_claims[m.station] = m.id


## The desks or the scanners, by role.
func stations_of(role: StaffMember.Role) -> Array[int]:
	return sim.layout.desks if role == StaffMember.Role.CHECKIN else sim.layout.scanners


func _beat(m: StaffMember) -> bool:
	return posmod(sim.tick, PassengerSim.BEAT_TICKS) == posmod(m.id, PassengerSim.BEAT_TICKS)


## Members of a station that is gone or not usable go idle; members standing on
## a cell that is no longer walkable give up their station and go back to the
## pool; leaving members whose service has ended go.
func _reconcile() -> void:
	for i in range(_members.size() - 1, -1, -1):
		var m := _members[i]
		if m.station != 0:
			var usable := sim.layout.is_usable(m.station)
			if not usable or not stations_of(m.role).has(m.station):
				_release(m)
		if not m.in_pool() and not sim.grid.is_walkable(m.at) and not _backing_out(m):
			if m.station != 0:
				_release(m)
			m.at = StaffMember.NO_CELL
			m.clear_path()
		if m.leaving and not (m.state == StaffMember.State.ON_DUTY and _in_service(m.station)):
			_remove(m)
			staff_changed.emit()


## Whether the member turned back from a cell that went (_replan()): `at` is
## that cell until the member reaches the one it left, which still stands.
func _backing_out(m: StaffMember) -> bool:
	return (
		m.state == StaffMember.State.TO_STATION
		and m.is_moving()
		and m.path_index == 0
		and m.seg_mm > 0
		and sim.grid.is_walkable(m.path[1])
	)


func _remove(m: StaffMember) -> void:
	if _claims.get(m.station, 0) == m.id:
		_claims.erase(m.station)
	_members.erase(m)
	_by_id.erase(m.id)


## Whether a passenger is being checked in or screened at the station now.
func _in_service(station: int) -> bool:
	for id in sim.passenger_ids():
		var p := sim.get_passenger(id)
		if p.station != station:
			continue
		if p.stage == Passenger.Stage.CHECKIN or p.stage == Passenger.Stage.SECURITY:
			return true
	return false


func _release(m: StaffMember) -> void:
	if _claims.get(m.station, 0) == m.id:
		_claims.erase(m.station)
	m.station = 0
	m.needs_replan = false
	m.search_failed = false
	m.clear_path()
	_set_state(m, StaffMember.State.IDLE)


## The nearest unclaimed usable station of the member's role, by path length
## from where it stands (from the entrance when it is in the pool).
func _assign(m: StaffMember) -> void:
	var start := m.at
	if m.in_pool():
		if sim.layout.entrances.is_empty():
			m.search_failed = true
			return
		start = sim.layout.door_cell(sim.grid, sim.layout.entrances[0])
	var best := 0
	var best_mm := 0
	var best_path: Array[Vector2i] = []
	for station in stations_of(m.role):
		if _claims.has(station) or not sim.layout.is_usable(station):
			continue
		var path := _path(start, sim.layout.lanes[station][0])
		if path.is_empty():
			continue
		var mm := Passenger.path_mm(path)
		if best == 0 or mm < best_mm:
			best = station
			best_mm = mm
			best_path = path
	if best == 0:
		m.search_failed = true
		return
	m.search_failed = false
	m.at = start
	m.station = best
	_claims[best] = m.id
	m.set_path(best_path)
	_set_state(m, StaffMember.State.TO_STATION)


func _walk(m: StaffMember) -> void:
	if m.needs_replan:
		_replan(m)
		if m.state != StaffMember.State.TO_STATION:
			return
	m.walk(PassengerSim.WALK_MM)
	if m.is_moving():
		return
	if m.at == sim.layout.lanes[m.station][0]:
		_set_state(m, StaffMember.State.ON_DUTY)
	else:
		_plan(m)


## A new path from where the member stands to its station's service cell. With
## none, the member gives the station up and goes idle. Returns whether it has
## a path.
func _plan(m: StaffMember) -> bool:
	var path := _path(m.at, sim.layout.lanes[m.station][0])
	if path.is_empty():
		_release(m)
		return false
	m.set_path(path)
	return true


## An edit touched the rest of the path. The step in progress is kept, as
## PassengerSim._replan() keeps a passenger's: while it can still be taken the
## member finishes it and plans on from its end; when the edit closed it, or
## removed the cell it was entering, the member turns back to the cell it just
## left, from where it is; with no way on it walks to the end of what it has
## and plans again there.
func _replan(m: StaffMember) -> void:
	m.needs_replan = false
	if not m.is_moving() or m.seg_mm == 0:
		_plan(m)
		return
	var target: Vector2i = sim.layout.lanes[m.station][0]
	var here := m.at
	var next := m.path[m.path_index + 1]
	var keep := m.seg_mm
	var path: Array[Vector2i] = []
	if sim.grid.can_route(here, next):
		path = _path(next, target)
		if path.is_empty():
			path.append(next)
		path.push_front(here)
	else:
		# Closed, or the cell itself is gone: back to the cell it left.
		keep = Passenger.segment_mm(here, next) - keep
		m.at = next
		path = _path(here, target)
		if path.is_empty():
			path.append(here)
		path.push_front(next)
	m.set_path(path)
	m.seg_mm = keep


func _path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if from == to:
		var here: Array[Vector2i] = [from]
		return here
	return sim.grid.find_path(from, to)


func _set_state(m: StaffMember, state: StaffMember.State) -> void:
	if m.state == state:
		return
	m.state = state
	member_state_changed.emit(m.id, state)


## An edit touched a walking member's path: it plans again on its next step.
## Stations that went are let go at once, so a save never names one.
func _on_graph_changed(cells: Array[Vector2i]) -> void:
	var touched := {}
	for cell in cells:
		touched[cell] = true
	for m in _members:
		if m.state != StaffMember.State.TO_STATION:
			continue
		for i in range(m.path_index, m.path.size()):
			if touched.has(m.path[i]):
				m.needs_replan = true
				break
	_reconcile()
