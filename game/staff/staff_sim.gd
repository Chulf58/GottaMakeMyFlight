# gdlint:disable = max-public-methods
# StaffSim is the staff data API; shift queries (is_off_shift, off_shift_count) took it past 20.
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
## Cleaners (Role.CLEANER) work no station. An idle cleaner takes the nearest
## job nobody holds, a mess or a full bin (CleanerJobs.nearest()), claims it
## (MessSim.claim(); a bin by being its job) so no other cleaner takes it, walks
## to it (TO_STATION), works it on duty for CleanerJobs.work_ticks() and then
## cleans the mess (MessSim.clean()) or empties the bin (MessSim.empty_bin())
## and takes the next. A cleaner whose job goes (an edit took the mess's floor
## or the bin, MessSim.claim_dropped) or that has no way to it any more lets go
## of it and searches again. A fired cleaner lets go of its job and walks out
## at once; it never waits like a server mid-service.
##
## PassengerSim steps it at the start of each tick, so every passenger step
## reads one staff state. Members are handled in id order, distances are whole
## millimetres and nothing is random, so a snapshot loaded at a tick boundary
## plays out exactly like continuous play. A search that finds no station is
## retried on the member's beat (once a simulated second, staggered by id).
##
## The player can close a station and open it again (`closures`,
## StationClosures): a closed station admits nobody and gets no new posting,
## and its members finish the service admitted before and are then released
## idle where they stand. A scanner fault (`faults`, StationFaults) stops a
## security station admitting until its repair tick, with its staff kept
## posted; step() clears it first on that tick.

## Hiring, firing and loading, or the player closed or opened a station; the
## counts or which stations are open may have changed.
signal staff_changed
## A member was hired into the pool (hire() only, never a load).
signal hired(id: int, role: StaffMember.Role)
signal member_state_changed(id: int, state: StaffMember.State)
signal member_energy_changed(id: int, energy: int)
signal member_trained(id: int, level: int)

## 2: members save their post (slot).
## 3: shop servers (Role.SHOP) at counters; a version 2 save has none.
## 4: cleaners (Role.CLEANER) and each member's job and work left.
## 5: the stations the player closed ("closed", StationClosures).
## 6: the scanner faults and their repair ticks ("faults", StationFaults).
## 7: airside ramp agents (Role.RAMP) with ramp_job, ramp_shuttle_id, ramp_flight_id.
## 8: overnight off-shift states (LEAVING_SHIFT, OFF_SHIFT).
## 9: soft staff energy and break room states (TO_BREAK, ON_BREAK).
## 10: per-member training level (StaffMember.level).
## Only this version loads; older saves are refused (no migrations before a
## release).
const SAVE_VERSION := 10
## Empty gap ahead before staff walk out for an overnight off-shift: 2 game hours.
const SHIFT_GAP_TICKS := 2400
## How early staff return from off-shift before first morning activity: 30 game min.
const RETURN_LEAD_TICKS := 600
## Who fire() lets go first: [state, slot] pairs, off-shift and idle first, then
## a helper before a primary in the same state, so firing keeps stations open
## where it can.
const FIRE_ORDER := [
	[StaffMember.State.OFF_SHIFT, StaffMember.Slot.PRIMARY],
	[StaffMember.State.IDLE, StaffMember.Slot.PRIMARY],
	[StaffMember.State.LEAVING_SHIFT, StaffMember.Slot.PRIMARY],
	[StaffMember.State.ON_BREAK, StaffMember.Slot.PRIMARY],
	[StaffMember.State.TO_BREAK, StaffMember.Slot.PRIMARY],
	[StaffMember.State.TO_STATION, StaffMember.Slot.HELPER],
	[StaffMember.State.ON_DUTY, StaffMember.Slot.HELPER],
	[StaffMember.State.TO_STATION, StaffMember.Slot.PRIMARY],
	[StaffMember.State.ON_DUTY, StaffMember.Slot.PRIMARY],
]

var sim: PassengerSim
## Set on the copy StaffPosts plays a step on for a helper forecast: it shares
## the live MessSim, so its cleaners take no job, finish none and let go of
## no claim.
var forecast := false
## The stations the player closed, and what the inspect window asks of them.
var closures: StationClosures
## The security stations a scanner fault stopped, and their repair ticks.
var faults: StationFaults
var ramp_dispatch: RampDispatch

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
var _gate_desks: Array[int] = []
var _gate_desks_dirty := true
var _last_unclaimed_sig := 0


func _init() -> void:
	closures = StationClosures.new(self)
	faults = StationFaults.new(self)


## Called by PassengerSim.bind() once its layout is built.
func bind(with_sim: PassengerSim) -> void:
	sim = with_sim
	sim.grid.graph_changed.connect(_on_graph_changed)
	sim.grid.edit_applied.connect(_on_edit_applied)
	sim.messes.claim_dropped.connect(_on_claim_dropped)
	_counters_dirty = true
	_gate_desks_dirty = true
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
	if role == StaffMember.Role.CLEANER:
		m.patrol_wait = CleanerJobs.PATROL_PAUSE_TICKS
	if role != StaffMember.Role.RAMP and is_off_shift():
		m.state = StaffMember.State.OFF_SHIFT
	_members.append(m)
	_by_id[m.id] = m
	staff_changed.emit()
	hired.emit(m.id, role)
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
	if role == StaffMember.Role.RAMP:
		return _fire_ramp()
	for entry: Array in FIRE_ORDER:
		var state: StaffMember.State = entry[0]
		for i in range(_members.size() - 1, -1, -1):
			var m := _members[i]
			if m.role != role or m.state != state or m.slot != entry[1] or m.leaving:
				continue
			# A helper or a cleaner serves nobody, so it never waits for a service.
			var serving := (
				state == StaffMember.State.ON_DUTY
				and not m.is_helper()
				and m.role != StaffMember.Role.CLEANER
			)
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


## Members of `role` walking to or resting inside a Break Room.
func on_break_count(role: StaffMember.Role) -> int:
	var n := 0
	for m in _members:
		n += int(m.role == role and m.is_on_break())
	return n


## Members of `role` walking out for or currently in an overnight off-shift.
func off_shift_count(role: StaffMember.Role) -> int:
	var n := 0
	for m in _members:
		n += int(
			(
				m.role == role
				and (
					m.state == StaffMember.State.OFF_SHIFT
					or m.state == StaffMember.State.LEAVING_SHIFT
				)
			)
		)
	return n


## True while any hired member is walking out for or resting in an overnight
## off-shift.
func is_off_shift() -> bool:
	for m in _members:
		if m.state == StaffMember.State.OFF_SHIFT or m.state == StaffMember.State.LEAVING_SHIFT:
			return true
	return false


## Every member on the roster or still walking out, for drawing and saving.
func member_ids() -> Array[int]:
	var ids: Array[int] = []
	for m in _members:
		ids.append(m.id)
	return ids


func get_member(id: int) -> StaffMember:
	return _by_id.get(id)


## Roles whose work speed scales with training level (L1-L3).
## Gate and Ramp agents gate/dispatch fixed flight timelines with no per-agent timed service loop.
static func is_role_trainable(role: int) -> bool:
	return (
		role
		in [
			StaffMember.Role.CHECKIN,
			StaffMember.Role.SECURITY,
			StaffMember.Role.SHOP,
			StaffMember.Role.CLEANER,
		]
	)


## Trains member `id` up one level (L1->L2->L3), debiting `wallet` when set.
func train(id: int, wallet: Wallet = null) -> bool:
	var m := get_member(id)
	if (
		m == null
		or not is_role_trainable(m.role)
		or m.leaving
		or m.state == StaffMember.State.WALKING_OUT
		or m.state == StaffMember.State.LEAVING_SHIFT
	):
		return false
	if m.level < StaffMember.LEVEL_MIN or m.level >= StaffMember.LEVEL_MAX:
		return false
	var cost := PriceTable.staff_train_cost(m.level)
	if cost <= 0:
		return false
	if wallet != null and not wallet.spend(cost, Wallet.Category.BUILD):
		return false
	m.level += 1
	member_trained.emit(id, m.level)
	staff_changed.emit()
	return true


## Whether a member is on duty at the station's `slot` post. Only the primary
## post opens a station, and a helper alone never does; a helper on duty
## speeds up a lane's repacks (SecurityRuntime.rate()).
func is_staffed(station: int, slot := StaffMember.Slot.PRIMARY) -> bool:
	var id := staff_at(station, slot)
	return id != 0 and (_by_id[id] as StaffMember).state == StaffMember.State.ON_DUTY


## Whether passengers are served at a desk, scanner or counter: it is usable
## (TerminalLayout.is_usable(), or one of the usable counters) and a member is
## on duty there who is not leaving, and the player has not closed it
## (closures), and no scanner fault stops it (faults). Closed stations are
## what a closed sign marks.
func is_open(station: int) -> bool:
	return not faults.is_faulted(station) and _serves(station)


## Whether `station` would be open (is_open()) if it had no scanner fault
## (StationFaults.open_but_for_fault()).
func _serves(station: int) -> bool:
	if closures.is_closed(station) or not _usable(station) or not is_staffed(station):
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


## Clears the scanner faults repaired by this tick, lets go of posts that
## went, plays the station-wide pass (StaffPosts.run()), works the cleaners'
## jobs (_work_jobs()) and walks every walking member, in id order.
func step() -> void:
	faults.clear_due(sim.tick)
	_reconcile()
	_recall_shift_if_due()
	if not forecast:
		StaffBreaks.step_energy(self)
		StaffBreaks.update_breaks(self, _begin_break, _end_break)
	StaffPosts.run(self, _post, _repost)
	if not forecast:
		_work_jobs()
	_leave_shift_if_quiet()
	for m: StaffMember in _members.duplicate():
		if (
			m.state == StaffMember.State.TO_STATION
			or m.state == StaffMember.State.TO_BREAK
			or _walking_to_exit(m)
			or _patrolling(m)
		):
			_walk(m)
	for m in _members:
		if (
			m.role != StaffMember.Role.RAMP
			and m.state == StaffMember.State.IDLE
			and not m.is_moving()
			and not m.in_pool()
			and sim.grid.is_belt_cell(m.at)
		):
			m.at = StaffMember.NO_CELL
			m.clear_path()


## JSON-safe state for a save, exactly as the members stand: it only reads.
## Edits reconcile at once (_on_graph_changed), so between ticks the one
## thing left for the next step() is a leaving member whose service ended
## during the tick. It is saved still leaving and on duty, and the loaded
## game's next step() lets it go on the same tick as one never saved.
func to_snapshot() -> Dictionary:
	return StaffSnapshot.save(
		_members, _next_id, closures.live_ids(), faults.live(), _last_unclaimed_sig
	)


## Restores a to_snapshot() dictionary, including one that went through JSON.
## Load it after PassengerSim.from_snapshot(), whose layout it is checked
## against. Pushes an error and returns false, leaving the staff unchanged,
## when anything is missing, mistyped or inconsistent.
func from_snapshot(data: Dictionary) -> bool:
	var loaded := StaffSnapshot.load(data, sim)
	if loaded.has("error"):
		push_error("StaffSim.from_snapshot: %s" % loaded["error"])
		return false
	for m: StaffMember in loaded["members"]:
		if (
			m.role != StaffMember.Role.RAMP
			and m.state == StaffMember.State.IDLE
			and not m.is_moving()
			and not m.in_pool()
			and sim != null
			and sim.grid != null
			and sim.grid.is_belt_cell(m.at)
		):
			push_error("StaffSim.from_snapshot: member %d is idle on a belt cell" % m.id)
			return false
	_next_id = loaded["next_id"]
	_members.assign(loaded["members"])
	closures.assign(loaded["closed"])
	faults.assign(loaded["faults"])
	_counters_dirty = true
	_gate_desks_dirty = true
	rederive()
	_last_unclaimed_sig = (
		int(loaded["last_unclaimed_sig"])
		if loaded.has("last_unclaimed_sig")
		else CleanerJobs.unclaimed_signature(self)
	)
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


## The desks, the scanners, the usable counters or the gate desks, by role. A
## cleaner has no station: none.
func stations_of(role: StaffMember.Role) -> Array[int]:
	match role:
		StaffMember.Role.CHECKIN:
			return sim.layout.desks
		StaffMember.Role.SHOP:
			return _shop_counters()
		StaffMember.Role.GATE:
			return _gate_desk_ids()
		StaffMember.Role.CLEANER, StaffMember.Role.RAMP:
			var none: Array[int] = []
			return none
	return sim.layout.scanners


## The usable counters, worked out again only after an edit.
func _shop_counters() -> Array[int]:
	if _counters_dirty:
		_counters = ShopCounters.counters(sim.grid)
		_counters_dirty = false
	return _counters


## The gate desks on the grid, worked out again only after an edit.
func _gate_desk_ids() -> Array[int]:
	if _gate_desks_dirty:
		_gate_desks = GateDesks.desk_ids(sim.grid)
		_gate_desks_dirty = false
	return _gate_desks


## Whether passengers can use `station`: a desk or scanner the layout can use,
## one of the usable counters, or an indoor linked gate desk.
func _usable(station: int) -> bool:
	if ShopCounters.is_counter(sim.grid, station):
		return _shop_counters().has(station)
	if GateDesks.is_desk(sim.grid, station):
		return StaffPosts.gate_desk_usable(sim.grid, sim.layout, station)
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


## Gives up the member's post: no station, and the primary slot; a cleaner
## lets go of its job and its claim on it.
func _unclaim(m: StaffMember) -> void:
	var claims := _claims_of(m)
	if claims.get(m.station, 0) == m.id:
		claims.erase(m.station)
	m.station = 0
	m.slot = StaffMember.Slot.PRIMARY
	m.break_room = 0
	m.break_spot = StaffMember.NO_CELL
	if m.job == 0:
		return
	# A bin's claim is the job itself (CleanerJobs.bin_holder()).
	if not m.job_bin and not forecast:
		sim.messes.release(m.job, m.id)
	m.job = 0
	m.job_bin = false
	m.work_left = 0


## Each cleaner, in id order: one on duty works a tick at its job and, done,
## cleans the mess or empties the bin and goes idle; an idle one takes the
## nearest job nobody holds (CleanerJobs.nearest()) and sets out, or patrols
## indoor corridors/bins after PATROL_PAUSE_TICKS while waiting.
func _work_jobs() -> void:
	var unclaimed_sig := CleanerJobs.unclaimed_signature(self)
	var new_unclaimed := unclaimed_sig != 0 and unclaimed_sig != _last_unclaimed_sig
	_last_unclaimed_sig = unclaimed_sig
	for m in _members:
		if m.role != StaffMember.Role.CLEANER:
			continue
		if m.state == StaffMember.State.ON_DUTY:
			var steps := StaffMember.steps_on_tick(sim.tick, m.work_speed_percent())
			if steps > 0:
				m.work_left = maxi(m.work_left - steps, 0)
			if m.work_left > 0:
				continue
			_finish_job(m)
		if m.state != StaffMember.State.IDLE:
			continue
		if new_unclaimed:
			m.search_failed = false
		if not (m.search_failed and not StaffPosts.on_beat(m, sim.tick)):
			var pick := CleanerJobs.nearest(self, m)
			if not pick.is_empty():
				_take_job(m, pick["job"], pick["bin"], pick["path"])
				continue
			m.search_failed = true
		if m.is_moving():
			continue
		if not m.in_pool() and sim.grid.is_belt_cell(m.at):
			m.patrol_wait = 0
		if m.patrol_wait > 0:
			m.patrol_wait -= 1
			continue
		var patrol := CleanerJobs.patrol_path(self, m, sim.tick)
		if patrol.size() >= 2:
			m.at = patrol[0]
			m.set_path(patrol)
		else:
			m.patrol_wait = CleanerJobs.PATROL_PAUSE_TICKS


## Claims job `job` (a bin when `bin`) for idle cleaner `m` and sends it along
## `path`, which starts where it stands or at an entrance's door cell.
func _take_job(m: StaffMember, job: int, bin: bool, path: Array[Vector2i]) -> void:
	if not bin and not sim.messes.claim(job, m.id):
		push_error("StaffSim: mess %d was taken before cleaner %d could claim it" % [job, m.id])
		return
	m.search_failed = false
	m.needs_replan = false
	m.patrol_wait = 0
	m.job = job
	m.job_bin = bin
	if m.is_moving() and m.seg_mm > 0 and not m.in_pool():
		var here := m.at
		var next := m.path[m.path_index + 1]
		var keep := m.seg_mm
		var spot: Vector2i = path[path.size() - 1]
		if sim.grid.can_staff_route(here, next):
			var tail := _path(next, spot)
			if not tail.is_empty():
				tail.push_front(here)
				m.set_path(tail)
				m.seg_mm = keep
				_set_state(m, StaffMember.State.TO_STATION)
				return
	m.at = path[0]
	m.set_path(path)
	_set_state(m, StaffMember.State.TO_STATION)


## A cleaner's work is done: the mess is cleaned or the bin emptied, and it
## stands idle where it is.
func _finish_job(m: StaffMember) -> void:
	if m.job_bin:
		sim.messes.empty_bin(m.job)
	else:
		sim.messes.clean(m.job)
	m.job = 0
	m.job_bin = false
	m.work_left = 0
	m.search_failed = false
	m.patrol_wait = CleanerJobs.PATROL_PAUSE_TICKS
	m.clear_path()
	_set_state(m, StaffMember.State.IDLE)


## Members of a station that is gone, not usable, or whose staff spot is
## blocked or out of reach from every entrance go idle, as do helpers of a
## station that is no longer a whole lane; members standing on a
## cell that is no longer walkable give up their station and go back to the
## pool (one walking out is gone); members on duty away from their post's
## spot, which moved, walk to it (_off_spot()); leaving members whose service
## has ended walk out. Every primary post still claimed afterwards is one
## staff can work: the first step of the pass (StaffPosts). Members of a
## station the player closed go idle where they stand once no service there
## is left to finish (StationClosures.release_due()). A cleaner whose
## job went (its bin was removed) goes idle where it stands; one at work off
## its job's spot, which an edit moved, walks to it and starts over.
func _reconcile() -> void:
	for i in range(_members.size() - 1, -1, -1):
		var m := _members[i]
		if m.role == StaffMember.Role.RAMP:
			continue
		if m.station != 0:
			var workable := StaffPosts.workable(sim.grid, sim.layout, m.station, m.slot)
			if not workable or not stations_of(m.role).has(m.station):
				_release(m)
		if closures.release_due(m):
			_release(m)
		if m.is_on_break():
			if (
				not StaffBreakRooms.is_ready(sim.grid, m.break_room)
				or m.break_spot == StaffMember.NO_CELL
				or not sim.grid.is_walkable(m.break_spot)
				or sim.grid.room_at(m.break_spot) != m.break_room
			):
				_end_break(m)
		if m.job != 0 and not CleanerJobs.exists(self, m):
			_release(m)
		if not m.in_pool() and not sim.grid.is_staff_walkable(m.at) and not _backing_out(m):
			if m.state == StaffMember.State.WALKING_OUT:
				_leave(m)
				continue
			if m.state == StaffMember.State.LEAVING_SHIFT:
				_enter_off_shift(m)
				continue
			if m.station != 0 or m.job != 0:
				_release(m)
			m.at = StaffMember.NO_CELL
			m.clear_path()
		elif (
			m.state == StaffMember.State.IDLE
			and not m.is_moving()
			and not m.in_pool()
			and sim.grid.is_belt_cell(m.at)
		):
			m.at = StaffMember.NO_CELL
			m.clear_path()
		var cleaner := m.role == StaffMember.Role.CLEANER
		if (
			cleaner
			and m.state == StaffMember.State.ON_DUTY
			and m.at != CleanerJobs.job_spot(self, m)
		):
			# An edit moved the job's spot (a bin's first free side): walk to
			# it and start the work over there.
			m.work_left = 0
			_set_state(m, StaffMember.State.TO_STATION)
			m.needs_replan = true
		if (
			m.state == StaffMember.State.ON_DUTY
			and not cleaner
			and m.at != spot_of(m.station, m.slot)
		):
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
	return m.backing_out and m.is_moving() and sim.grid.is_staff_walkable(m.path[1])


func _remove(m: StaffMember) -> void:
	_unclaim(m)
	_members.erase(m)
	_by_id.erase(m.id)


func _fire_ramp() -> bool:
	for job in [
		StaffMember.RampJob.NONE,
		StaffMember.RampJob.MARSHAL,
		StaffMember.RampJob.PUSHBACK,
		StaffMember.RampJob.SHUTTLE,
	]:
		for i in range(_members.size() - 1, -1, -1):
			var m := _members[i]
			if m.role != StaffMember.Role.RAMP or m.ramp_job != job or m.leaving:
				continue
			if job == StaffMember.RampJob.NONE or job == StaffMember.RampJob.MARSHAL:
				m.ramp_job = StaffMember.RampJob.NONE
				m.ramp_shuttle_id = 0
				m.ramp_flight_id = ""
				_remove(m)
			else:
				m.leaving = true
			staff_changed.emit()
			return true
	return false


func _set_ramp_job(
	m: StaffMember, job: StaffMember.RampJob, shuttle_id := 0, flight_id := ""
) -> void:
	if m == null or m.role != StaffMember.Role.RAMP:
		return
	if job == StaffMember.RampJob.NONE:
		m.ramp_job = StaffMember.RampJob.NONE
		m.ramp_shuttle_id = 0
		m.ramp_flight_id = ""
		if m.leaving:
			m.leaving = false
			_remove(m)
		else:
			_set_state(m, StaffMember.State.IDLE)
		staff_changed.emit()
		return
	if m.leaving:
		return
	m.ramp_job = job
	m.ramp_shuttle_id = shuttle_id if job == StaffMember.RampJob.SHUTTLE else 0
	m.ramp_flight_id = (
		flight_id
		if (job == StaffMember.RampJob.PUSHBACK or job == StaffMember.RampJob.MARSHAL)
		else ""
	)
	m.at = StaffMember.NO_CELL
	m.station = 0
	m.path.clear()
	_set_state(m, StaffMember.State.ON_DUTY)
	staff_changed.emit()


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
	if m.role == StaffMember.Role.CLEANER:
		m.patrol_wait = CleanerJobs.PATROL_PAUSE_TICKS
	m.clear_path()
	_set_state(m, StaffMember.State.IDLE)


## One tick of walking to a station's spot, a patrol waypoint, or out to the
## entrance. On the spot the member goes on duty; at patrol end it pauses idle.
func _begin_break(m: StaffMember, room_id: int, spot: Vector2i, path: Array[Vector2i]) -> void:
	_unclaim(m)
	m.search_failed = false
	m.needs_replan = false
	m.patrol_wait = 0
	m.break_room = room_id
	m.break_spot = spot
	if not m.in_pool() and m.at == spot and not m.is_moving():
		m.clear_path()
		_set_state(m, StaffMember.State.ON_BREAK)
		return
	m.at = path[0]
	m.set_path(path)
	_set_state(m, StaffMember.State.TO_BREAK)


func _end_break(m: StaffMember) -> void:
	_release(m)


func _walk(m: StaffMember) -> void:
	var state := m.state
	if m.needs_replan:
		_replan(m)
		if not _by_id.has(m.id) or m.state != state:
			return
	m.walk(PassengerSim.WALK_MM)
	if m.is_moving():
		return
	if state == StaffMember.State.IDLE:
		m.clear_path()
		m.patrol_wait = CleanerJobs.PATROL_PAUSE_TICKS
		return
	if m.at != _target(m):
		_plan(m)
	elif state == StaffMember.State.WALKING_OUT:
		_leave(m)
	elif state == StaffMember.State.LEAVING_SHIFT:
		_enter_off_shift(m)
	elif state == StaffMember.State.TO_BREAK:
		_set_state(m, StaffMember.State.ON_BREAK)
	else:
		m.work_left = CleanerJobs.work_ticks(self, m)
		_set_state(m, StaffMember.State.ON_DUTY)


## Where a walking member is headed: its post's spot at its station, a
## cleaner's job spot (CleanerJobs.job_spot()), a patrolling cleaner's end cell,
## a break room spot, or, when it walks out, the door cell of the entrance with
## the shortest path.
func _target(m: StaffMember) -> Vector2i:
	if m.state == StaffMember.State.TO_BREAK:
		return m.break_spot
	if not _walking_to_exit(m):
		if m.role == StaffMember.Role.CLEANER:
			if m.state == StaffMember.State.IDLE:
				return m.path_end()
			return CleanerJobs.job_spot(self, m)
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
## walking to a station gives it up and goes idle; one walking out is gone;
## one leaving shift goes off-shift in place. Returns whether it has a path.
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
	elif m.state == StaffMember.State.LEAVING_SHIFT:
		_enter_off_shift(m)
	else:
		_release(m)


## An edit touched the rest of the path. The step in progress is kept, as
## PassengerEdits.replan() keeps a passenger's: while it can still be taken the
## member finishes it and plans on from its end; when the edit closed it, or
## removed the cell it was entering, the member turns back to the cell it just
## left, from where it is; with no way on it walks to the end of what it has
## and plans again there. A member walking out with no way on is gone at once;
## one leaving shift enters OFF_SHIFT in place.
func _replan(m: StaffMember) -> void:
	m.needs_replan = false
	var target := _target(m)
	var out := _walking_to_exit(m)
	if m.backing_out:
		# Already turned back: only what comes after the cell it left changes.
		var back := m.path[1]
		var tail := _path(back, target)
		if out and tail.is_empty():
			_no_way(m)
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
	if sim.grid.can_staff_route(here, next):
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
		_no_way(m)
		return
	m.set_path(path)
	m.seg_mm = keep
	m.backing_out = not sim.grid.is_staff_walkable(m.path[0])


func _walking_to_exit(m: StaffMember) -> bool:
	return m.is_walking_to_exit()


func _patrolling(m: StaffMember) -> bool:
	return (
		m.role == StaffMember.Role.CLEANER
		and m.state == StaffMember.State.IDLE
		and (m.is_moving() or m.needs_replan)
	)


func _can_shift() -> bool:
	return not forecast and sim != null and sim.flights != null and sim.flights.opened_tick >= 0


func _next_activity_tick() -> int:
	var next := sim.flights.next_morning_activity_tick()
	var spawn := sim.next_spawn_tick()
	if spawn >= 0:
		next = spawn if next < 0 else mini(next, spawn)
	return next


func _recall_shift_if_due() -> void:
	if not _can_shift():
		return
	var next_tick := _next_activity_tick()
	var due := (
		sim.active_count() > 0
		or sim.flights.has_moving_flight()
		or next_tick < 0
		or next_tick - sim.tick <= RETURN_LEAD_TICKS
	)
	if not due:
		return
	for m in _members:
		if m.state == StaffMember.State.OFF_SHIFT:
			m.search_failed = false
			_set_state(m, StaffMember.State.IDLE)
		elif m.state == StaffMember.State.LEAVING_SHIFT:
			_recall_leaving(m)


func _recall_leaving(m: StaffMember) -> void:
	if m.backing_out:
		if m.path.size() >= 2 and sim.grid.is_staff_walkable(m.path[1]):
			m.at = m.path[1]
		else:
			m.at = StaffMember.NO_CELL
	m.clear_path()
	m.needs_replan = false
	m.search_failed = false
	_set_state(m, StaffMember.State.IDLE)


func _leave_shift_if_quiet() -> void:
	if not _can_shift():
		return
	if sim.active_count() > 0 or sim.flights.has_moving_flight():
		return
	var next_tick := _next_activity_tick()
	if next_tick < 0 or next_tick - sim.tick <= SHIFT_GAP_TICKS:
		return
	for m in _members:
		if m.role == StaffMember.Role.RAMP or m.leaving:
			continue
		if m.state == StaffMember.State.OFF_SHIFT or _walking_to_exit(m):
			continue
		if m.role == StaffMember.Role.CLEANER and m.job != 0 and not m.search_failed:
			continue
		_begin_leave_shift(m)


func _begin_leave_shift(m: StaffMember) -> void:
	_unclaim(m)
	m.search_failed = false
	if m.in_pool() or sim.layout.entrances.is_empty():
		_enter_off_shift(m)
		return
	_set_state(m, StaffMember.State.LEAVING_SHIFT)
	m.needs_replan = true
	_replan(m)


func _enter_off_shift(m: StaffMember) -> void:
	_unclaim(m)
	m.at = StaffMember.NO_CELL
	m.clear_path()
	m.needs_replan = false
	m.search_failed = false
	var prev := m.energy
	m.energy = StaffMember.ENERGY_MAX
	m.energy_ticks = 0
	if m.energy != prev:
		member_energy_changed.emit(m.id, m.energy)
	_set_state(m, StaffMember.State.OFF_SHIFT)


func _path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	return StaffPosts.path(sim.grid, from, to)


func _set_state(m: StaffMember, state: StaffMember.State) -> void:
	if m.state == state:
		return
	m.state = state
	m.energy_ticks = 0
	member_state_changed.emit(m.id, state)


## An edit touched a walking member's path: it plans again on its next step.
## Stations that went are let go at once, so a save never names one.
func _on_graph_changed(cells: Array[Vector2i]) -> void:
	_counters_dirty = true
	_gate_desks_dirty = true
	var touched := {}
	for cell in cells:
		touched[cell] = true
	for m in _members:
		if (
			m.state != StaffMember.State.TO_STATION
			and m.state != StaffMember.State.TO_BREAK
			and not _walking_to_exit(m)
			and not _patrolling(m)
		):
			continue
		for i in range(m.path_index, m.path.size()):
			if touched.has(m.path[i]):
				m.needs_replan = true
				break
	_reconcile()


## A claimed mess went by an edit or remove(): its cleaner lets go of the job
## and stands idle where it is, searching again on its next step.
func _on_claim_dropped(id: int, cleaner: int) -> void:
	var m: StaffMember = _by_id.get(cleaner)
	if m == null or m.job != id or m.job_bin:
		return
	_release(m)


## Any edit can change which counters are usable. A room edit changes no walk
## graph, so graph_changed never follows it: posts are reconciled here then.
func _on_edit_applied(_edit: BuildEdit, result: BuildResult) -> void:
	_counters_dirty = true
	_gate_desks_dirty = true
	if result.dirty_cells.is_empty():
		_reconcile()
