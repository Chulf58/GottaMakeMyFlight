class_name ToiletSim
extends RefCounted
## Toilet visits, owned by PassengerSim and stepped inside its tick (decision
## toilet-design-queue-free-reservable-stalls-per-stall-daily-u, points 1, 5
## and 7). Each usable stall (ToiletLayout) is one use slot with no queue: a
## visit reserves its stall when it is committed, so a passenger still
## walking there holds it. A visit is committed only when VisitForecast admits
## the whole of it; the passenger walks to the stall's approach cell, steps in
## to the turn spot, sits down, uses it for USE_TICKS, stands up and steps
## back out, and its journey goes on where it left off: TO_SECURITY landside,
## TO_GATE airside. A passenger seated at a gate stands up first. Using the
## stall resets the toilet need; there is no money and no mood bonus.
##
## The toilet need (point 5) rises once a simulated second. From NEED_AT the
## passenger looks for the stall nearest by path; when every stall is
## reserved, none can be reached, or the forecast says there is no time, it
## carries on and tries again after RETRY_TICKS, losing a mood point every
## MOOD_BEATS seconds while the need stays high (decision
## a-passenger-with-a-high-need-detours-to-the-nearest-facility). A detour
## never costs the flight.
##
## Priority between needs: on a passenger's beat PassengerSim asks ToiletSim
## before CafeSim, so a passenger whose toilet need and hunger are both high
## tries a toilet first, and goes to a cafe only on a beat when no toilet
## visit starts.
##
## Every phase before standing up checks the visit's deadline: the last tick
## the passenger can start to stand up and still reach the plane door
## VisitForecast.MARGIN_TICKS before the doors close. It is worked out again
## after any grid edit, once a second on the passenger's beat, and every tick
## for a landside visit. Past it, a walker gives up and goes on; one stepping
## in turns back; one sitting down stands up again; one using the stall
## stands up (its need is reset). A visit whose stall is gone ends at once.
##
## Visits and stalls are handled in id order with integer quantities only, so
## a save loaded at a tick boundary plays on exactly.

const NEED_START_MIN := 30
const NEED_START_MAX := 90
const NEED_MAX := 100
## The need rises this much once a simulated second.
const NEED_RISE := 1
const NEED_AT := 70
## A passenger with a high need and no visit loses a mood point every this
## many beats.
const MOOD_BEATS := 5
## A passenger who could not start a visit tries again after this long.
const RETRY_TICKS := 100
## Ticks on the stall seat.
const USE_TICKS := 100
## The step from the approach cell's centre to Mount_Turn (1.15 m) and back,
## at a walk.
const ENTER_TICKS := 12
const EXIT_TICKS := 12
## The shuffle between Mount_Turn and Mount_Use while sitting down or
## standing up.
const SHUFFLE_TICKS := 12
## From starting to stand up to being back on the approach cell.
const LEAVE_TICKS := PassengerSim.STAND_UP_TICKS + EXIT_TICKS
## The phases that check the deadline: everything before standing up.
const CHECKED_STAGES: Array[Passenger.Stage] = [
	Passenger.Stage.TOILET_WALK,
	Passenger.Stage.TOILET_ENTER,
	Passenger.Stage.TOILET_SITTING_DOWN,
	Passenger.Stage.TOILET_USE,
]
## The phases spent inside the stall, off the approach cell.
const STALL_STAGES: Array[Passenger.Stage] = [
	Passenger.Stage.TOILET_ENTER,
	Passenger.Stage.TOILET_SITTING_DOWN,
	Passenger.Stage.TOILET_USE,
	Passenger.Stage.TOILET_STANDING_UP,
	Passenger.Stage.TOILET_EXIT,
]
## The timed phases and how long each lasts from its stage tick.
const PHASE_TICKS := {
	Passenger.Stage.TOILET_ENTER: ENTER_TICKS,
	Passenger.Stage.TOILET_SITTING_DOWN: PassengerSim.SIT_DOWN_TICKS,
	Passenger.Stage.TOILET_USE: USE_TICKS,
	Passenger.Stage.TOILET_STANDING_UP: PassengerSim.STAND_UP_TICKS,
	Passenger.Stage.TOILET_EXIT: EXIT_TICKS,
}

var layout := ToiletLayout.new()
## Set by any grid edit: every visit's deadline is worked out again on the
## next tick. Saved as it is, so a loaded game does the same.
var deadlines_stale := false

var _sim: PassengerSim
var _set_stage: Callable
var _leave_station: Callable
var _release_gate_seat: Callable
## Passenger id -> ToiletVisit.
var _visits: Dictionary = {}
## Derived: stall object id -> passenger id.
var _stalls: Dictionary = {}
var _layout_dirty := true


## Wires the sim's own stage, station and gate-seat helpers in, so a stage
## change still emits PassengerSim.stage_changed.
func bind(
	sim: PassengerSim, set_stage: Callable, leave_station: Callable, release_gate_seat: Callable
) -> void:
	_sim = sim
	_set_stage = set_stage
	_leave_station = leave_station
	_release_gate_seat = release_gate_seat
	_layout_dirty = true
	if not sim.grid.edit_applied.is_connected(_on_edit_applied):
		sim.grid.edit_applied.connect(_on_edit_applied)


## A need a passenger saved before toilets existed starts with: spread over
## the start range by its id, so a migrated save draws nothing from the sim
## RNG and loads the same every time.
static func migrated_need(passenger_id: int) -> int:
	var span := NEED_START_MAX - NEED_START_MIN + 1
	return NEED_START_MIN + posmod(passenger_id * 7919, span)


func visit_of(passenger_id: int) -> ToiletVisit:
	return _visits.get(passenger_id)


func visit_ids() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(_visits.keys())
	ids.sort()
	return ids


## The passenger holding a stall, walkers included, or 0.
func stall_holder(stall_id: int) -> int:
	return _stalls.get(stall_id, 0)


## Commits `p` to a visit at the free stall nearest by path when the forecast
## allows it. False when it may not start one now, no free stall can be
## reached, or the whole visit does not fit before its doors close.
func try_visit(p: Passenger) -> bool:
	if not CafeSim.START_STAGES.has(p.stage) or _visits.has(p.id):
		return false
	if StageKinds.visit_facility(_sim, p) != StageKinds.Facility.NONE:
		return false
	refresh()
	var plan := _plan(p)
	if plan.is_empty():
		return false
	var stall: Dictionary = plan["stall"]
	var route: Dictionary = plan["route"]
	var resume := _resume_stage(p)
	var arrival := VisitForecast.arrival(
		_sim, p, _visit_ticks(p, route["mm"]), stall["approach"], LEAVE_TICKS, resume
	)
	if not VisitForecast.admits(_sim, p, arrival):
		return false
	_commit(p, stall, route)
	return true


## Once a simulated second per passenger: the need rises, a high need with
## no visit costs mood, and a passenger with a high need may start a visit.
func beat(p: Passenger) -> void:
	p.toilet_need = mini(p.toilet_need + NEED_RISE, NEED_MAX)
	var visit: ToiletVisit = _visits.get(p.id)
	if visit != null:
		# The abandon-now forecast with live queues, once a second per visit.
		if CHECKED_STAGES.has(p.stage) or p.stage == Passenger.Stage.STANDING_UP:
			visit.deadline = _live_deadline(p, visit)
		return
	if p.toilet_need < NEED_AT:
		return
	@warning_ignore("integer_division")
	var beat_number := _sim.tick / PassengerSim.BEAT_TICKS
	if posmod(beat_number, MOOD_BEATS) == 0:
		p.mood = maxi(p.mood - 1, 0)
	if _sim.tick < p.toilet_cooldown or not CafeSim.START_STAGES.has(p.stage):
		return
	if not try_visit(p):
		p.toilet_cooldown = _sim.tick + RETRY_TICKS


## Rebuilds the layout after an edit and brings visits in line with it: a
## visit whose stall is gone ends, and every deadline is forecast again.
## Called at the start of every tick, before anyone steps.
func reconcile() -> void:
	refresh()
	for id in visit_ids():
		var visit: ToiletVisit = _visits.get(id)
		var p := _sim.get_passenger(id)
		var stall := layout.stall(visit.stall_id)
		if stall.is_empty():
			_stall_gone(p, visit)
			continue
		visit.stall = stall
		visit.room = stall["room"]
		if deadlines_stale:
			visit.deadline = _live_deadline(p, visit)
	deadlines_stale = false


## Rebuilds the layout when an edit made it stale.
func refresh() -> void:
	if not _layout_dirty:
		return
	layout.rebuild(_sim.grid)
	_layout_dirty = false


## One tick of a passenger in a toilet stage.
func step(p: Passenger) -> void:
	var visit: ToiletVisit = _visits.get(p.id)
	if visit == null:
		push_error("ToiletSim: passenger %d is in a toilet stage with no visit" % p.id)
		_set_stage.call(p, Passenger.Stage.TO_GATE if p.cleared else Passenger.Stage.TO_SECURITY)
		return
	if CHECKED_STAGES.has(p.stage):
		if visit.resume_stage == Passenger.Stage.TO_SECURITY:
			# The rest of a landside journey runs through the scanners, whose
			# queues can fill between beats: forecast it again every tick.
			visit.deadline = _live_deadline(p, visit)
		if _sim.tick >= visit.deadline:
			_leave_early(p, visit)
			return
	var spent := _sim.tick - p.stage_tick
	match p.stage:
		Passenger.Stage.TOILET_WALK:
			_walk_step(p, visit)
		Passenger.Stage.TOILET_ENTER:
			if spent >= ENTER_TICKS:
				_set_stage.call(p, Passenger.Stage.TOILET_SITTING_DOWN)
		Passenger.Stage.TOILET_SITTING_DOWN:
			if spent >= PassengerSim.SIT_DOWN_TICKS:
				_set_stage.call(p, Passenger.Stage.TOILET_USE)
		Passenger.Stage.TOILET_USE:
			if spent >= USE_TICKS:
				p.toilet_need = 0
				_set_stage.call(p, Passenger.Stage.TOILET_STANDING_UP)
		Passenger.Stage.TOILET_STANDING_UP:
			if spent >= PassengerSim.STAND_UP_TICKS:
				_set_stage.call(p, Passenger.Stage.TOILET_EXIT)
		Passenger.Stage.TOILET_EXIT:
			if spent >= EXIT_TICKS:
				_end(p, visit)


## A passenger who got up from a gate seat for the toilet sets off for it.
func depart(p: Passenger) -> void:
	var visit: ToiletVisit = _visits[p.id]
	var route := VisitRoute.plan(_sim.grid, p, visit.stall.get("approach", p.at))
	if _sim.tick >= visit.deadline or visit.stall.is_empty() or route.is_empty():
		_end(p, visit)
		return
	_walk(p, route)


## Drops the visit of a passenger who made or missed the flight.
func cleanup(p: Passenger) -> void:
	var visit: ToiletVisit = _visits.get(p.id)
	if visit != null:
		_remove(visit)


## Where a passenger inside a stall is drawn: from the approach cell to the
## turn spot stepping in, to the use spot sitting down, and back out again.
func stall_position(p: Passenger) -> Vector3:
	var visit: ToiletVisit = _visits.get(p.id)
	if visit == null or visit.stall.is_empty():
		var at := p.grid_position()
		return _sim.grid.origin + Vector3(at.x, 0.0, at.y)
	var approach := _sim.grid.cell_to_world(visit.stall["approach"])
	var turn: Vector3 = visit.stall["turn"]
	var use: Vector3 = visit.stall["use"]
	var spent := _sim.tick - p.stage_tick
	var at := approach
	match p.stage:
		Passenger.Stage.TOILET_ENTER:
			at = approach.lerp(turn, clampf(spent / float(ENTER_TICKS), 0.0, 1.0))
		Passenger.Stage.TOILET_SITTING_DOWN:
			at = turn.lerp(use, clampf(spent / float(SHUFFLE_TICKS), 0.0, 1.0))
		Passenger.Stage.TOILET_USE:
			at = use
		Passenger.Stage.TOILET_STANDING_UP:
			var left := PassengerSim.STAND_UP_TICKS - spent
			at = turn.lerp(use, clampf(left / float(SHUFFLE_TICKS), 0.0, 1.0))
		Passenger.Stage.TOILET_EXIT:
			at = turn.lerp(approach, clampf(spent / float(EXIT_TICKS), 0.0, 1.0))
	return at


## The grid direction a passenger sitting down, seated or standing up in a
## stall faces (out of the door, as Mount_Use does), or zero otherwise.
func use_facing(p: Passenger) -> Vector2i:
	var visit: ToiletVisit = _visits.get(p.id)
	if visit == null or visit.stall.is_empty():
		return Vector2i.ZERO
	if StageKinds.pose(p.stage) == StageKinds.Pose.UPRIGHT or not Passenger.in_toilet(p.stage):
		return Vector2i.ZERO
	return visit.stall["front"]


## Installs visits a ToiletSnapshot.load() checked; rederive() then rebuilds
## the stall holders and the layout.
func restore(state: Dictionary) -> void:
	_visits = state["visits"]
	deadlines_stale = state["deadlines_stale"]


## Rebuilds what is derived from the visits after a load.
func rederive() -> void:
	_layout_dirty = true
	refresh()
	_stalls.clear()
	for id in visit_ids():
		var visit: ToiletVisit = _visits[id]
		_stalls[visit.stall_id] = id
		visit.stall = layout.stall(visit.stall_id)


## The free stall nearest `p` by path, ties to the lower stall id, with the
## walk: {"stall", "route"}. Empty when no free stall can be reached. Octile
## distance (less a diagonal step for a passenger partway along one) is a
## lower bound on the path, so stalls further than the best path are skipped.
func _plan(p: Passenger) -> Dictionary:
	var free: Array = []
	for stall in layout.stalls:
		if not _stalls.has(stall["id"]):
			free.append([Passenger.octile_mm(p.at, stall["approach"]), stall["id"], stall])
	free.sort()
	var best := {}
	for entry in free:
		if not best.is_empty() and entry[0] - Passenger.DIAGONAL_MM > int(best["route"]["mm"]):
			break
		var route := VisitRoute.plan(_sim.grid, p, entry[2]["approach"])
		if route.is_empty():
			continue
		var better: bool = best.is_empty() or int(route["mm"]) < int(best["route"]["mm"])
		if not better and int(route["mm"]) == int(best["route"]["mm"]):
			better = int(entry[1]) < int(best["stall"]["id"])
		if better:
			best = {"stall": entry[2], "route": route}
	return best


## Ticks from now until a visit walking `walk_mm` starts to stand up.
func _visit_ticks(p: Passenger, walk_mm: int) -> int:
	var pre := PassengerSim.STAND_UP_TICKS if p.stage == Passenger.Stage.SEATED else 0
	return (
		pre
		+ JourneyForecast.walk_ticks(walk_mm)
		+ ENTER_TICKS
		+ PassengerSim.SIT_DOWN_TICKS
		+ USE_TICKS
	)


func _live_deadline(p: Passenger, visit: ToiletVisit) -> int:
	if visit.stall.is_empty():
		return visit.deadline
	return VisitForecast.live_deadline(
		_sim, p, visit.stall["approach"], LEAVE_TICKS, visit.resume_stage
	)


func _resume_stage(p: Passenger) -> Passenger.Stage:
	if p.stage == Passenger.Stage.TO_SECURITY:
		return Passenger.Stage.TO_SECURITY
	return Passenger.Stage.TO_GATE


func _commit(p: Passenger, stall: Dictionary, route: Dictionary) -> void:
	var visit := ToiletVisit.new()
	visit.passenger = p.id
	visit.room = stall["room"]
	visit.stall_id = stall["id"]
	visit.stall = stall
	visit.resume_stage = _resume_stage(p)
	visit.deadline = VisitForecast.deadline(
		_sim, p, stall["approach"], LEAVE_TICKS, visit.resume_stage
	)
	_visits[p.id] = visit
	_stalls[visit.stall_id] = p.id
	p.late = false
	p.stuck = Passenger.Stuck.NONE
	match p.stage:
		Passenger.Stage.TO_SECURITY:
			_leave_station.call(p)
		Passenger.Stage.SEATED:
			# Up from the gate seat first; PassengerSim calls depart() after.
			_set_stage.call(p, Passenger.Stage.STANDING_UP)
			return
		_:
			_release_gate_seat.call(p)
	_walk(p, route)


func _walk(p: Passenger, route: Dictionary) -> void:
	VisitRoute.start(p, route)
	_set_stage.call(p, Passenger.Stage.TOILET_WALK)


func _walk_step(p: Passenger, visit: ToiletVisit) -> void:
	if p.is_moving():
		return
	var approach: Vector2i = visit.stall["approach"]
	if p.at == approach:
		p.clear_path()
		_set_stage.call(p, Passenger.Stage.TOILET_ENTER)
		return
	var path := _sim.grid.find_path(p.at, approach)
	if path.is_empty():
		_end(p, visit)
		return
	p.set_path(path)


## The deadline passed: a walker gives up, one stepping in turns back, one
## sitting down gets up again and one using the stall stands up.
func _leave_early(p: Passenger, visit: ToiletVisit) -> void:
	match p.stage:
		Passenger.Stage.TOILET_WALK:
			_end(p, visit)
		Passenger.Stage.TOILET_ENTER:
			_turn_back(p, Passenger.Stage.TOILET_EXIT, ENTER_TICKS)
		Passenger.Stage.TOILET_SITTING_DOWN:
			_turn_back(p, Passenger.Stage.TOILET_STANDING_UP, PassengerSim.SIT_DOWN_TICKS)
		Passenger.Stage.TOILET_USE:
			p.toilet_need = 0
			_set_stage.call(p, Passenger.Stage.TOILET_STANDING_UP)


## Reverses a timed phase partway through: the reverse phase starts as far
## along as the forward one had got to its end, so the way back takes as long
## as the way in so far.
func _turn_back(p: Passenger, reverse: Passenger.Stage, length: int) -> void:
	var spent := mini(_sim.tick - p.stage_tick, length)
	_set_stage.call(p, reverse)
	p.stage_tick = _sim.tick - (length - spent)


## The stall went away under the visit: a walker gives up; one inside the
## stall is back on the approach cell at once (its need reset if it was using
## the stall); one still getting up from a gate seat lets the gate take over.
func _stall_gone(p: Passenger, visit: ToiletVisit) -> void:
	match p.stage:
		Passenger.Stage.STANDING_UP:
			_remove(visit)
		Passenger.Stage.TOILET_WALK:
			_end(p, visit)
		_:
			if p.stage == Passenger.Stage.TOILET_USE:
				p.toilet_need = 0
			_end(p, visit)


## The visit is over, or given up before the stall: the passenger goes on
## with its journey.
func _end(p: Passenger, visit: ToiletVisit) -> void:
	_remove(visit)
	_resume(p, visit)


func _resume(p: Passenger, visit: ToiletVisit) -> void:
	p.toilet_cooldown = _sim.tick + RETRY_TICKS
	p.station = 0
	p.stuck = Passenger.Stuck.NONE
	p.clear_path()
	_set_stage.call(p, visit.resume_stage)


func _remove(visit: ToiletVisit) -> void:
	_visits.erase(visit.passenger)
	if _stalls.get(visit.stall_id, 0) == visit.passenger:
		_stalls.erase(visit.stall_id)


func _on_edit_applied(_edit: BuildEdit, _result: BuildResult) -> void:
	_layout_dirty = true
	deadlines_stale = true
