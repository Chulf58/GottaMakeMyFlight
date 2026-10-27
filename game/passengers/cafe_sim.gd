class_name CafeSim
extends RefCounted
## Cafe visits, owned by PassengerSim and stepped inside its tick (decision
## cafe-visit-design-forecast-the-whole-itinerary-abandon-by-a). A visit is
## committed only when CafeForecast admits the whole itinerary and a seat is
## reserved for it. The guest walks to the back of a counter's queue, orders
## when it reaches the front, walks to the reserved seat, sits for a dwell
## and stands up; then its journey goes on where it left off: TO_SECURITY
## landside, TO_GATE airside. A guest seated at a gate stands up first.
##
## Counters keep their own queue and lifecycle and never use the station
## loop. A queue holds every guest committed to the counter, walkers too, in
## commit order, never more than the counter's lane has cells; each guest
## stands on the lane cell of its place.
##
## Every phase before standing up checks the visit's deadline. A guest past it
## who has not been served gives up (no charge); one who has been served
## leaves early. The deadline is worked out again after any grid edit, and a
## visit whose cafe, counter or seat is gone ends the same way.
##
## Visits, queues and seats are handled in id and key order, with integer
## quantities only, so a save loaded at a tick boundary plays on exactly.

## Ticks to make an order once the guest is at the front.
const ORDER_TICKS := 60
## Ticks a guest stays seated when nothing hurries it.
const DWELL_TICKS := 240
## The approach cell is about a metre from the seated root, so the shuffle in
## and out takes longer than at a gate seat.
const SHUFFLE_TICKS := 12
## Seats tried per visit, nearest the counter first.
const SEAT_TRIES := 4
## The stages a visit may start from: heading for security after check-in,
## heading for the gate, or waiting at it.
const START_STAGES: Array[Passenger.Stage] = [
	Passenger.Stage.TO_SECURITY,
	Passenger.Stage.TO_GATE,
	Passenger.Stage.STANDING,
	Passenger.Stage.SEATED,
]

var layout := CafeLayout.new()

var _sim: PassengerSim
var _set_stage: Callable
var _leave_station: Callable
var _release_gate_seat: Callable
## Passenger id -> CafeVisit.
var _visits: Dictionary = {}
## Counter id -> {"room": int, "lane": Array[int], "serving": int}.
var _queues: Dictionary = {}
## Derived: seat key -> passenger id.
var _seats: Dictionary = {}
var _layout_dirty := true
var _deadlines_dirty := false


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


func visit_of(passenger_id: int) -> CafeVisit:
	return _visits.get(passenger_id)


func visit_ids() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(_visits.keys())
	ids.sort()
	return ids


## A counter's queue, front first, walkers included.
func queue_of(counter_id: int) -> Array[int]:
	var out: Array[int] = []
	if _queues.has(counter_id):
		out.assign(_queues[counter_id]["lane"])
	return out


## The passenger a counter is serving, or 0.
func serving_at(counter_id: int) -> int:
	return _queues[counter_id]["serving"] if _queues.has(counter_id) else 0


## The passenger holding a seat, or 0.
func seat_holder(key: String) -> int:
	return _seats.get(key, 0)


## Commits `p` to a visit at the nearest usable cafe when the forecast allows
## it. False when it may not start one now, no cafe has a free seat and room
## in a queue it can reach, or the whole visit does not fit.
func try_visit(p: Passenger) -> bool:
	if not START_STAGES.has(p.stage) or _visits.has(p.id):
		return false
	refresh()
	var plan := _plan(p)
	if plan.is_empty():
		return false
	var arrival := CafeForecast.visit_arrival(_sim, p, plan["legs"])
	if not CafeForecast.admits(_sim, p, arrival):
		return false
	_commit(p, plan)
	return true


## Rebuilds the layout after an edit and brings visits and queues in line
## with it. Called at the start of every tick, before anyone steps.
func reconcile() -> void:
	refresh()
	for id in visit_ids():
		var visit: CafeVisit = _visits.get(id)
		if visit == null:
			continue
		var p := _sim.get_passenger(id)
		var seat := layout.seat(visit.room, visit.seat_key)
		var counter := layout.counter(visit.room, visit.counter)
		if seat.is_empty() or (counter.is_empty() and not visit.served):
			_leave_early(p, visit)
			continue
		visit.seat = seat
		if _deadlines_dirty:
			visit.deadline = CafeForecast.deadline(_sim, p, seat["approach"], visit.resume_stage)
	var counters: Array = _queues.keys()
	counters.sort()
	for counter_id in counters:
		var q: Dictionary = _queues[counter_id]
		var cells: Array = layout.counter(q["room"], counter_id).get("lane", [])
		while (q["lane"] as Array).size() > cells.size():
			var last: int = (q["lane"] as Array).back()
			_abandon(_sim.get_passenger(last), _visits[last])
		if (q["lane"] as Array).is_empty() and q["serving"] == 0:
			_queues.erase(counter_id)
	_deadlines_dirty = false


## Rebuilds the layout when an edit made it stale.
func refresh() -> void:
	if not _layout_dirty:
		return
	layout.rebuild(_sim.grid, _sim.layout)
	_layout_dirty = false


## Finishes orders that are ready and starts the next at each counter.
func step_counters() -> void:
	var counters: Array = _queues.keys()
	counters.sort()
	for counter_id in counters:
		var q: Dictionary = _queues[counter_id]
		if q["serving"] != 0:
			var served := _sim.get_passenger(q["serving"])
			var visit: CafeVisit = _visits[served.id]
			if _sim.tick >= visit.service_end:
				q["serving"] = 0
				(q["lane"] as Array).erase(served.id)
				_serve(served, visit)
		if q["serving"] != 0 or (q["lane"] as Array).is_empty():
			continue
		var cells: Array = layout.counter(q["room"], counter_id).get("lane", [])
		var front := _sim.get_passenger(q["lane"][0])
		if cells.is_empty() or front.stage != Passenger.Stage.CAFE_QUEUE:
			continue
		if front.at != cells[0] or front.is_moving():
			continue
		q["serving"] = front.id
		(_visits[front.id] as CafeVisit).service_end = _sim.tick + ORDER_TICKS
		_set_stage.call(front, Passenger.Stage.CAFE_ORDER)


## One tick of a guest in a cafe stage.
func step(p: Passenger) -> void:
	var visit: CafeVisit = _visits.get(p.id)
	if visit == null:
		push_error("CafeSim: passenger %d is in a cafe stage with no visit" % p.id)
		_set_stage.call(p, Passenger.Stage.TO_GATE if p.cleared else Passenger.Stage.TO_SECURITY)
		return
	var stage := p.stage
	if stage != Passenger.Stage.CAFE_STANDING_UP and _sim.tick >= visit.deadline:
		_leave_early(p, visit)
		return
	match stage:
		Passenger.Stage.CAFE_WALK, Passenger.Stage.CAFE_QUEUE:
			_queue_step(p, visit)
		Passenger.Stage.CAFE_TO_SEAT:
			_seat_step(p, visit)
		Passenger.Stage.CAFE_SITTING_DOWN:
			if _sim.tick - p.stage_tick >= PassengerSim.SIT_DOWN_TICKS:
				visit.dwell_end = _sim.tick + DWELL_TICKS
				_set_stage.call(p, Passenger.Stage.CAFE_SEATED)
		Passenger.Stage.CAFE_SEATED:
			if _sim.tick >= visit.dwell_end:
				visit.outcome = CafeVisit.Outcome.COMPLETE
				_stand(p, visit)
		Passenger.Stage.CAFE_STANDING_UP:
			if _sim.tick - p.stage_tick >= PassengerSim.STAND_UP_TICKS:
				_end(p, visit)


## A guest who got up from a gate seat for the cafe sets off for its queue.
func depart(p: Passenger) -> void:
	var visit: CafeVisit = _visits[p.id]
	var route := _route(p, _slot_cell(p, visit))
	if _sim.tick >= visit.deadline or route.is_empty():
		_abandon(p, visit)
		return
	_walk(p, route)


## Drops the visit of a passenger who made or missed the flight.
func cleanup(p: Passenger) -> void:
	var visit: CafeVisit = _visits.get(p.id)
	if visit == null:
		return
	if visit.served and visit.outcome == CafeVisit.Outcome.NONE:
		visit.outcome = CafeVisit.Outcome.SHORT
	_remove(visit)


## Where a guest sitting down, seated or standing up at a cafe seat stands.
func seat_position(p: Passenger) -> Vector3:
	var visit: CafeVisit = _visits.get(p.id)
	if visit == null or visit.seat.is_empty():
		var at := p.grid_position()
		return _sim.grid.origin + Vector3(at.x, 0.0, at.y)
	var approach := _sim.grid.cell_to_world(visit.seat["approach"])
	var root := BuildObjectDef.seat_root_world(_sim.grid, visit.seat)
	var shuffle := clampf((_sim.tick - p.stage_tick) / float(SHUFFLE_TICKS), 0.0, 1.0)
	match p.stage:
		Passenger.Stage.CAFE_SITTING_DOWN:
			return approach.lerp(root, shuffle)
		Passenger.Stage.CAFE_STANDING_UP:
			var left := PassengerSim.STAND_UP_TICKS - (_sim.tick - p.stage_tick)
			return approach.lerp(root, clampf(left / float(SHUFFLE_TICKS), 0.0, 1.0))
	return root


## The grid direction a seated guest faces, or zero with no seat.
func seat_facing(p: Passenger) -> Vector2i:
	var visit: CafeVisit = _visits.get(p.id)
	if visit == null or visit.seat.is_empty():
		return Vector2i.ZERO
	return visit.seat["facing"]


## Rebuilds what is derived from the visits after a load.
func rederive() -> void:
	_layout_dirty = true
	refresh()
	_seats.clear()
	for id in visit_ids():
		var visit: CafeVisit = _visits[id]
		_seats[visit.seat_key] = id
		visit.seat = layout.seat(visit.room, visit.seat_key)


## The best visit for `p`: the cafe nearest by path whose soonest counter has
## room in its queue and which has a free seat reachable from that counter,
## ties to the lower room id. Empty when there is none.
func _plan(p: Passenger) -> Dictionary:
	var best := {}
	for cafe in layout.cafes:
		var counter := _soonest_counter(cafe)
		if counter.is_empty():
			continue
		var lane: Array = counter["lane"]
		var seat := _free_seat(cafe, lane[0])
		if seat.is_empty():
			continue
		var route := _route(p, lane[queue_of(counter["id"]).size()])
		if route.is_empty():
			continue
		var mm := Passenger.path_mm(route["path"]) - int(route["keep"])
		if best.is_empty() or mm < best["mm"]:
			best = {
				"mm": mm, "room": cafe["room"], "counter": counter, "seat": seat, "route": route
			}
	if best.is_empty():
		return best
	var counter_id: int = best["counter"]["id"]
	best["legs"] = {
		"pre_ticks": PassengerSim.STAND_UP_TICKS if p.stage == Passenger.Stage.SEATED else 0,
		"to_queue_mm": best["mm"],
		"order_ticks": _order_eta(counter_id),
		"to_seat_mm": best["seat"]["mm"],
		"dwell_ticks": DWELL_TICKS,
		"leave_cell": best["seat"]["approach"],
		"resume_stage": _resume_stage(p),
	}
	return best


## The counter with room in its queue that would serve a newcomer soonest,
## ties to the lower id; empty when every queue is full.
func _soonest_counter(cafe: Dictionary) -> Dictionary:
	var best := {}
	var best_eta := 0
	for counter in cafe["counters"]:
		if queue_of(counter["id"]).size() >= (counter["lane"] as Array).size():
			continue
		var eta := _order_eta(counter["id"])
		if best.is_empty() or eta < best_eta:
			best = counter
			best_eta = eta
	return best


## Ticks until a newcomer joining a counter's queue now has its order: the
## order in progress, the guests ahead and its own.
func _order_eta(counter_id: int) -> int:
	var left := 0
	var ahead := queue_of(counter_id).size()
	var serving := serving_at(counter_id)
	if serving != 0:
		left = maxi(0, (_visits[serving] as CafeVisit).service_end - _sim.tick)
		ahead -= 1
	return left + ahead * ORDER_TICKS + ORDER_TICKS


## The free seat nearest `from` that can be walked to from it, with the walk
## in "mm"; empty when none of the nearest SEAT_TRIES can.
func _free_seat(cafe: Dictionary, from: Vector2i) -> Dictionary:
	var free: Array = []
	for seat in cafe["seats"]:
		if not _seats.has(seat["key"]):
			free.append([Passenger.octile_mm(from, seat["approach"]), free.size(), seat])
	free.sort()
	for i in mini(free.size(), SEAT_TRIES):
		var seat: Dictionary = free[i][2]
		var path := _sim.grid.find_path(from, seat["approach"])
		if path.is_empty():
			continue
		var out := seat.duplicate()
		out["mm"] = Passenger.path_mm(path)
		return out
	return {}


## A path from where `p` is to `target`: {"path", "keep"}, where "keep" is the
## progress along the step already under way (the path then runs on from that
## step's far cell). Empty when there is no way.
func _route(p: Passenger, target: Vector2i) -> Dictionary:
	if p.is_moving() and p.seg_mm > 0:
		var next := p.path[p.path_index + 1]
		if _sim.grid.can_route(p.at, next):
			var rest := _sim.grid.find_path(next, target)
			if rest.is_empty():
				return {}
			rest.push_front(p.at)
			return {"path": rest, "keep": p.seg_mm}
	var path := _sim.grid.find_path(p.at, target)
	if path.is_empty():
		return {}
	return {"path": path, "keep": 0}


func _resume_stage(p: Passenger) -> Passenger.Stage:
	if p.stage == Passenger.Stage.TO_SECURITY:
		return Passenger.Stage.TO_SECURITY
	return Passenger.Stage.TO_GATE


func _commit(p: Passenger, plan: Dictionary) -> void:
	var seat: Dictionary = plan["seat"]
	var counter_id: int = plan["counter"]["id"]
	var visit := CafeVisit.new()
	visit.passenger = p.id
	visit.room = plan["room"]
	visit.counter = counter_id
	visit.seat_key = seat["key"]
	visit.seat = layout.seat(visit.room, visit.seat_key)
	visit.resume_stage = _resume_stage(p)
	visit.deadline = CafeForecast.deadline(_sim, p, seat["approach"], visit.resume_stage)
	_visits[p.id] = visit
	_seats[visit.seat_key] = p.id
	if not _queues.has(counter_id):
		_queues[counter_id] = {"room": visit.room, "lane": [], "serving": 0}
	(_queues[counter_id]["lane"] as Array).append(p.id)
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
	_walk(p, plan["route"])


func _walk(p: Passenger, route: Dictionary) -> void:
	var path: Array[Vector2i] = []
	path.assign(route["path"])
	p.set_path(path)
	p.seg_mm = route["keep"]
	_set_stage.call(p, Passenger.Stage.CAFE_WALK)


## The lane cell of the guest's place in its counter's queue.
func _slot_cell(p: Passenger, visit: CafeVisit) -> Vector2i:
	var lane: Array = layout.counter(visit.room, visit.counter).get("lane", [])
	if lane.is_empty():
		return p.at
	var index := queue_of(visit.counter).find(p.id)
	return lane[clampi(index, 0, lane.size() - 1)]


func _queue_step(p: Passenger, visit: CafeVisit) -> void:
	if p.is_moving():
		return
	var target := _slot_cell(p, visit)
	if p.at == target:
		if p.stage == Passenger.Stage.CAFE_WALK:
			_set_stage.call(p, Passenger.Stage.CAFE_QUEUE)
		return
	var path := _sim.grid.find_path(p.at, target)
	if path.is_empty():
		_abandon(p, visit)
		return
	p.set_path(path)


func _serve(p: Passenger, visit: CafeVisit) -> void:
	visit.served = true
	var path := _sim.grid.find_path(p.at, visit.seat.get("approach", p.at))
	if visit.seat.is_empty() or path.is_empty():
		visit.outcome = CafeVisit.Outcome.SHORT
		_end(p, visit)
		return
	p.set_path(path)
	_set_stage.call(p, Passenger.Stage.CAFE_TO_SEAT)


func _seat_step(p: Passenger, visit: CafeVisit) -> void:
	if p.is_moving():
		return
	var approach: Vector2i = visit.seat["approach"]
	if p.at == approach:
		p.clear_path()
		_set_stage.call(p, Passenger.Stage.CAFE_SITTING_DOWN)
		return
	var path := _sim.grid.find_path(p.at, approach)
	if path.is_empty():
		visit.outcome = CafeVisit.Outcome.SHORT
		_end(p, visit)
		return
	p.set_path(path)


## The deadline passed or the cafe, counter or seat went away. A guest not yet
## served gives up; a served one leaves early, standing up first if it sits.
func _leave_early(p: Passenger, visit: CafeVisit) -> void:
	if p.stage == Passenger.Stage.STANDING_UP:
		# Still getting up from a gate seat: drop the visit, the gate takes over.
		_remove(visit)
		return
	if not visit.served:
		_abandon(p, visit)
		return
	visit.outcome = CafeVisit.Outcome.SHORT
	match p.stage:
		Passenger.Stage.CAFE_SITTING_DOWN, Passenger.Stage.CAFE_SEATED:
			_stand(p, visit)
		Passenger.Stage.CAFE_STANDING_UP:
			pass
		_:
			_end(p, visit)


func _stand(p: Passenger, _visit: CafeVisit) -> void:
	_set_stage.call(p, Passenger.Stage.CAFE_STANDING_UP)


## The visit is over: the guest goes on with its journey.
func _end(p: Passenger, visit: CafeVisit) -> void:
	_remove(visit)
	_resume(p, visit)


## Gives up before being served: no charge and nothing changes for the guest.
func _abandon(p: Passenger, visit: CafeVisit) -> void:
	_remove(visit)
	_resume(p, visit)


func _resume(p: Passenger, visit: CafeVisit) -> void:
	p.station = 0
	p.stuck = Passenger.Stuck.NONE
	p.clear_path()
	_set_stage.call(p, visit.resume_stage)


func _remove(visit: CafeVisit) -> void:
	_visits.erase(visit.passenger)
	if _seats.get(visit.seat_key, 0) == visit.passenger:
		_seats.erase(visit.seat_key)
	if _queues.has(visit.counter):
		var q: Dictionary = _queues[visit.counter]
		(q["lane"] as Array).erase(visit.passenger)
		if q["serving"] == visit.passenger:
			q["serving"] = 0


func _on_edit_applied(_edit: BuildEdit, _result: BuildResult) -> void:
	_layout_dirty = true
	_deadlines_dirty = true
