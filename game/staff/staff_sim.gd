class_name StaffSim
extends Node
## The staff pool as plain data. The player hires check-in agents, security
## officers and shop servers by role; nobody places them. An idle member walks
## on its own to the nearest usable desk, scanner or counter (ShopCounters) of
## its role that nobody else has claimed
## (the shortest grid path, ties to the lower station id), entering through
## the entrance nearest that station when it comes from the pool. It walks to the
## station's staff spot (StaffSpots: behind a desk, beside a scanner; a
## security lane's primary officer spot), and a
## station counts as staffed only while its member is on duty standing there;
## until then PassengerSim keeps it closed. That member holds the station's
## primary post. A spare officer helps at a security lane from its helper
## post; who goes where is the station-wide pass in StaffPosts, played at the
## start of every step. A station whose spot an old save
## left blocked, or that no entrance has a way to, is never staffed. A member
## whose station is removed or stops being usable goes idle where it stands;
## one whose cell is built over goes back to the pool. One on duty whose
## station's spot moved (a counter's can, ShopCounters) walks to the new
## spot, or walks out if it was leaving. A fired member walks
## out to the nearest entrance it has a way to and is removed there (at once
## when it is in the pool or has no way out); while it walks it is no longer
## staff.
##
## PassengerSim steps it at the start of each tick, so every passenger step
## reads one staff state. Members are handled in id order, distances are whole
## millimetres and nothing is random, so a snapshot loaded at a tick boundary
## plays out exactly like continuous play. A search that finds no station is
## retried on the member's beat (once a simulated second, staggered by id).

## Hiring, firing and loading; the counts may have changed.
signal staff_changed
signal member_state_changed(id: int, state: StaffMember.State)

## 2: members save their post (slot); StaffSnapshot migrates version 1.
## 3: shop servers (Role.SHOP) at counters; a version 2 save has none.
const SAVE_VERSION := 3
## Who fire() lets go first: [state, slot] pairs, a helper before a primary
## in the same state, so firing keeps stations open where it can.
const FIRE_ORDER := [
	[StaffMember.State.IDLE, StaffMember.Slot.PRIMARY],
	[StaffMember.State.TO_STATION, StaffMember.Slot.HELPER],
	[StaffMember.State.ON_DUTY, StaffMember.Slot.HELPER],
	[StaffMember.State.TO_STATION, StaffMember.Slot.PRIMARY],
	[StaffMember.State.ON_DUTY, StaffMember.Slot.PRIMARY],
]

var sim: PassengerSim

var _members: Array[StaffMember] = []
var _by_id: Dictionary = {}
var _next_id := 1
## Derived: station id -> the member walking to its primary post or on duty
## there.
var _claims: Dictionary = {}
## Derived: lane station id -> the member walking to its helper post or on
## duty there.
var _helpers: Dictionary = {}
## Derived from the grid: the usable counters (ShopCounters.counters()), worked
## out again after an edit when _counters_dirty is set.
var _counters: Array[int] = []
var _counters_dirty := true


## Called by PassengerSim.bind() once its layout is built.
func bind(with_sim: PassengerSim) -> void:
	sim = with_sim
	sim.grid.graph_changed.connect(_on_graph_changed)
	sim.grid.edit_applied.connect(_on_edit_applied)
	_counters_dirty = true
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


## Lets one member of `role` go, in FIRE_ORDER: an idle one if any, else a
## helper walking or on duty, else a primary walking, else one on duty; the
## highest id within each. It walks out (WALKING_OUT)
## and stops counting at once. A primary on duty with a passenger in service
## does not leave yet: it is marked leaving, its station takes nobody new
## (is_open() is false) and it walks out on the first tick after that service
## ends, so the station is never unstaffed while it serves. At a security
## station every admitted passenger is in service, whatever its phase. Until
## then it still counts in count() and on_duty_count(), and in leaving_count().
## Returns false, changing nothing, when every member of that role is already
## leaving or walking out, or none is hired.
func fire(role: StaffMember.Role) -> bool:
	for entry: Array in FIRE_ORDER:
		var state: StaffMember.State = entry[0]
		for i in range(_members.size() - 1, -1, -1):
			var m := _members[i]
			if m.role != role or m.state != state or m.slot != entry[1] or m.leaving:
				continue
			# A helper serves nobody itself, so it never waits for a service.
			var serving := state == StaffMember.State.ON_DUTY and not m.is_helper()
			if serving and _in_service(m.station):
				m.leaving = true
			elif _send_out(m):
				return true
			staff_changed.emit()
			return true
	return false


## Members of `role` still employed, those leaving included and those walking
## out not: wages (Settlement) and the hired count read this.
func count(role: StaffMember.Role) -> int:
	var n := 0
	for m in _members:
		n += int(m.role == role and m.state != StaffMember.State.WALKING_OUT)
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


## Every member on the roster or still walking out, for drawing and saving.
func member_ids() -> Array[int]:
	var ids: Array[int] = []
	for m in _members:
		ids.append(m.id)
	return ids


func get_member(id: int) -> StaffMember:
	return _by_id.get(id)


## Whether a member is on duty at the station's `slot` post. Only the primary
## post opens a station, and a helper alone never does; a helper on duty
## speeds up a lane's repacks (SecurityRuntime.rate()).
func is_staffed(station: int, slot := StaffMember.Slot.PRIMARY) -> bool:
	var id := staff_at(station, slot)
	return id != 0 and (_by_id[id] as StaffMember).state == StaffMember.State.ON_DUTY


## Whether passengers are served at a desk, scanner or counter: it is usable
## (TerminalLayout.is_usable(), or one of the usable counters) and a member is
## on duty there who is not leaving. Closed stations are what a closed sign
## marks.
func is_open(station: int) -> bool:
	if not _usable(station) or not is_staffed(station):
		return false
	return not (_by_id[_claims[station]] as StaffMember).leaving


## The member walking to or on duty at the station's `slot` post, or 0.
func staff_at(station: int, slot := StaffMember.Slot.PRIMARY) -> int:
	var claims := _helpers if slot == StaffMember.Slot.HELPER else _claims
	return claims.get(station, 0)


## Where the member working `station` in `slot` stands (StaffPosts.spot()),
## or BuildObjectDef.NO_CELL.
func spot_of(station: int, slot := StaffMember.Slot.PRIMARY) -> Vector2i:
	return StaffPosts.spot(sim.grid, sim.layout, station, slot)


## Whether staff can never work `station` because an old save left its staff
## spot blocked (StaffPosts.blocked()); such a station stays closed.
func spot_blocked(station: int) -> bool:
	return StaffPosts.blocked(sim.grid, sim.layout, station)


## Whether no entrance has a way to `station`'s `slot` spot
## (StaffPosts.unreachable()), so nobody is sent there; without its primary
## the station stays closed.
func spot_unreachable(station: int, slot := StaffMember.Slot.PRIMARY) -> bool:
	return StaffPosts.unreachable(sim.grid, sim.layout, station, slot)


## Where a member on the floor stands on this tick, in world space.
func world_position(m: StaffMember) -> Vector3:
	var at := m.grid_position()
	return sim.grid.origin + Vector3(at.x, 0.0, at.y)


## Lets go of posts that went, plays the station-wide pass (StaffPosts.run())
## and walks every walking member, in id order.
func step() -> void:
	_reconcile()
	StaffPosts.run(self, _post, _repost)
	for m: StaffMember in _members.duplicate():
		if m.state == StaffMember.State.TO_STATION or m.state == StaffMember.State.WALKING_OUT:
			_walk(m)


## JSON-safe state for a save, exactly as the members stand: it only reads.
## Edits reconcile at once (_on_graph_changed), so between ticks the one
## thing left for the next step() is a leaving member whose service ended
## during the tick. It is saved still leaving and on duty, and the loaded
## game's next step() lets it go on the same tick as one never saved.
func to_snapshot() -> Dictionary:
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
	_counters_dirty = true
	rederive()
	staff_changed.emit()
	return true


## Rebuilds what is derived from the member records.
func rederive() -> void:
	_by_id.clear()
	_claims.clear()
	_helpers.clear()
	for m in _members:
		_by_id[m.id] = m
		if m.station != 0:
			_claims_of(m)[m.station] = m.id


## The desks, the scanners or the usable counters, by role.
func stations_of(role: StaffMember.Role) -> Array[int]:
	match role:
		StaffMember.Role.CHECKIN:
			return sim.layout.desks
		StaffMember.Role.SHOP:
			return _shop_counters()
	return sim.layout.scanners


## The usable counters, worked out again only after an edit.
func _shop_counters() -> Array[int]:
	if _counters_dirty:
		_counters = ShopCounters.counters(sim.grid)
		_counters_dirty = false
	return _counters


## Whether passengers can use `station`: a desk or scanner the layout can use,
## or one of the usable counters.
func _usable(station: int) -> bool:
	if ShopCounters.is_counter(sim.grid, station):
		return _shop_counters().has(station)
	return sim.layout.is_usable(station)


## Sends idle `m` along `path` (from where it stands, or from an entrance's
## door cell when it is in the pool) to its `slot` post at `station`.
## StaffPosts.run() calls it.
func _post(m: StaffMember, station: int, slot: StaffMember.Slot, path: Array[Vector2i]) -> void:
	m.search_failed = false
	m.at = path[0]
	m.station = station
	m.slot = slot
	_claims_of(m)[station] = m.id
	m.set_path(path)
	_set_state(m, StaffMember.State.TO_STATION)


## Moves a member already on the floor, walking or on duty, to its `slot`
## post at `station`: it plans a way there on its next step, keeping a step
## in progress (_replan()). StaffPosts.run() calls it to promote or recall a
## helper.
func _repost(m: StaffMember, station: int, slot: StaffMember.Slot) -> void:
	_unclaim(m)
	m.station = station
	m.slot = slot
	_claims_of(m)[station] = m.id
	m.search_failed = false
	_set_state(m, StaffMember.State.TO_STATION)
	m.needs_replan = true


## The claims a member's post is kept in: primaries or helpers.
func _claims_of(m: StaffMember) -> Dictionary:
	return _helpers if m.slot == StaffMember.Slot.HELPER else _claims


## Gives up the member's post: no station, and the primary slot.
func _unclaim(m: StaffMember) -> void:
	var claims := _claims_of(m)
	if claims.get(m.station, 0) == m.id:
		claims.erase(m.station)
	m.station = 0
	m.slot = StaffMember.Slot.PRIMARY


## Members of a station that is gone, not usable, or whose staff spot is
## blocked or out of reach from every entrance go idle, as do helpers of a
## station that is no longer a whole lane; members standing on a
## cell that is no longer walkable give up their station and go back to the
## pool (one walking out is gone); members on duty away from their post's
## spot, which moved, walk to it (_off_spot()); leaving members whose service
## has ended walk out. Every primary post still claimed afterwards is one
## staff can work: the first step of the pass (StaffPosts).
func _reconcile() -> void:
	for i in range(_members.size() - 1, -1, -1):
		var m := _members[i]
		if m.station != 0:
			var workable := StaffPosts.workable(sim.grid, sim.layout, m.station, m.slot)
			if not workable or not stations_of(m.role).has(m.station):
				_release(m)
		if not m.in_pool() and not sim.grid.is_walkable(m.at) and not _backing_out(m):
			if m.state == StaffMember.State.WALKING_OUT:
				_leave(m)
				continue
			if m.station != 0:
				_release(m)
			m.at = StaffMember.NO_CELL
			m.clear_path()
		if m.state == StaffMember.State.ON_DUTY and m.at != spot_of(m.station, m.slot):
			_off_spot(m)
		if m.leaving and not (m.state == StaffMember.State.ON_DUTY and _in_service(m.station)):
			if not _send_out(m):
				staff_changed.emit()


## A member on duty whose post's spot moved under it (an edit moved a
## counter's spot, ShopCounters) walks to the new spot; one leaving walks out
## instead, since the order it waited for is finished without it.
func _off_spot(m: StaffMember) -> void:
	if m.leaving:
		if not _send_out(m):
			staff_changed.emit()
		return
	_set_state(m, StaffMember.State.TO_STATION)
	m.needs_replan = true


## Whether the member is backing out of a cell that went (_replan() marked it):
## `at` is that cell until the member reaches the one it left, if that stands.
func _backing_out(m: StaffMember) -> bool:
	return m.backing_out and m.is_moving() and sim.grid.is_walkable(m.path[1])


func _remove(m: StaffMember) -> void:
	_unclaim(m)
	_members.erase(m)
	_by_id.erase(m.id)


## A member walking out is gone: it reached the entrance or has no way there.
func _leave(m: StaffMember) -> void:
	_remove(m)
	staff_changed.emit()


## A fired member gives up its station and walks out to the nearest entrance
## it has a way to (_target()), keeping a step in progress. One in the pool,
## or with no entrance or no path to one, is removed at once, and that removal has already emitted
## staff_changed: returns true then, so the caller does not emit it again.
func _send_out(m: StaffMember) -> bool:
	_unclaim(m)
	m.leaving = false
	m.search_failed = false
	if m.in_pool() or sim.layout.entrances.is_empty():
		_leave(m)
		return true
	_set_state(m, StaffMember.State.WALKING_OUT)
	m.needs_replan = true
	_replan(m)
	return not _by_id.has(m.id)


## Whether a passenger is being checked in or screened at the station now: at
## a security station any passenger SecurityRuntime has admitted there, in
## whatever phase (Stage.SECURITY until it is cleared). StaffPosts.in_service()
## answers it, so the helper forecast reads the same rule.
func _in_service(station: int) -> bool:
	return StaffPosts.in_service(sim, station)


func _release(m: StaffMember) -> void:
	_unclaim(m)
	m.needs_replan = false
	m.search_failed = false
	m.clear_path()
	_set_state(m, StaffMember.State.IDLE)


## One tick of walking to a station's spot or out to the entrance. On the
## spot the member goes on duty; at the entrance a member walking out is gone.
func _walk(m: StaffMember) -> void:
	var state := m.state
	if m.needs_replan:
		_replan(m)
		if not _by_id.has(m.id) or m.state != state:
			return
	m.walk(PassengerSim.WALK_MM)
	if m.is_moving():
		return
	if m.at != _target(m):
		_plan(m)
	elif state == StaffMember.State.WALKING_OUT:
		_leave(m)
	else:
		_set_state(m, StaffMember.State.ON_DUTY)


## Where a walking member is headed: its post's spot at its station, or, when
## it walks out, the door cell of the entrance with the shortest path from
## where it stands (the lower entrance id on a tie; NO_CELL when it reaches
## none).
func _target(m: StaffMember) -> Vector2i:
	if m.state != StaffMember.State.WALKING_OUT:
		return spot_of(m.station, m.slot)
	var best := StaffMember.NO_CELL
	var best_mm := 0
	for door in sim.layout.entrances:
		var cell := sim.layout.door_cell(sim.grid, door)
		var path := _path(m.at, cell)
		if path.is_empty():
			continue
		var mm := Passenger.path_mm(path)
		if best == StaffMember.NO_CELL or mm < best_mm:
			best = cell
			best_mm = mm
	return best


## A new path from where the member stands to its target. With none, a member
## walking to a station gives it up and goes idle; one walking out is gone.
## Returns whether it has a path.
func _plan(m: StaffMember) -> bool:
	var path := _path(m.at, _target(m))
	if path.is_empty():
		_no_way(m)
		return false
	m.set_path(path)
	return true


func _no_way(m: StaffMember) -> void:
	if m.state == StaffMember.State.WALKING_OUT:
		_leave(m)
	else:
		_release(m)


## An edit touched the rest of the path. The step in progress is kept, as
## PassengerSim._replan() keeps a passenger's: while it can still be taken the
## member finishes it and plans on from its end; when the edit closed it, or
## removed the cell it was entering, the member turns back to the cell it just
## left, from where it is; with no way on it walks to the end of what it has
## and plans again there. A member walking out with no way on is gone at once.
func _replan(m: StaffMember) -> void:
	m.needs_replan = false
	var target := _target(m)
	var out := m.state == StaffMember.State.WALKING_OUT
	if m.backing_out:
		# Already turned back: only what comes after the cell it left changes.
		var back := m.path[1]
		var tail := _path(back, target)
		if out and tail.is_empty():
			_leave(m)
			return
		var onward: Array[Vector2i] = [m.at, back]
		onward.append_array(tail.slice(1))
		var offset := m.seg_mm
		m.set_path(onward)
		m.seg_mm = offset
		return
	if not m.is_moving() or m.seg_mm == 0:
		_plan(m)
		return
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
	if out and path[path.size() - 1] != target:
		_leave(m)
		return
	m.set_path(path)
	m.seg_mm = keep
	m.backing_out = not sim.grid.is_walkable(m.path[0])


func _path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	return StaffPosts.path(sim.grid, from, to)


func _set_state(m: StaffMember, state: StaffMember.State) -> void:
	if m.state == state:
		return
	m.state = state
	member_state_changed.emit(m.id, state)


## An edit touched a walking member's path: it plans again on its next step.
## Stations that went are let go at once, so a save never names one.
func _on_graph_changed(cells: Array[Vector2i]) -> void:
	_counters_dirty = true
	var touched := {}
	for cell in cells:
		touched[cell] = true
	for m in _members:
		if m.state != StaffMember.State.TO_STATION and m.state != StaffMember.State.WALKING_OUT:
			continue
		for i in range(m.path_index, m.path.size()):
			if touched.has(m.path[i]):
				m.needs_replan = true
				break
	_reconcile()


## Any edit can change which counters are usable. A room edit changes no walk
## graph, so graph_changed never follows it: posts are reconciled here then.
func _on_edit_applied(_edit: BuildEdit, result: BuildResult) -> void:
	_counters_dirty = true
	if result.dirty_cells.is_empty():
		_reconcile()
