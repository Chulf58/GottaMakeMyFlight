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
## leaves early. The deadline is worked out again after any grid edit, once a
## second on the guest's beat, and every tick for a landside guest, whose
## journey on runs through the scanner queues. A visit whose cafe, counter or
## seat is gone ends the same way.
##
## Hunger (point 5) rises once a simulated second; at HUNGRY_AT the passenger
## heads for the nearest reachable cafe if the forecast allows, and otherwise
## its mood drops every few seconds. A walking passenger who comes near a cafe
## with lots of time to spare drops in too (browsing, airside from further
## away), with a cooldown between tries.
##
## Money (points 6 and 7) is settled once, synchronously, when a served guest
## stands up or leaves: the amount is worked out in whole numbers, credited to
## PassengerSim.wallet, the visit is marked settled, and only then is `paid`
## emitted. A full visit pays the room type's base spend nudged by mood and
## the airside bonus, resets hunger and lifts mood; leaving early pays part of
## it and resets hunger; giving up before being served pays nothing.
##
## Visits, queues and seats are handled in id and key order, with integer
## quantities only, so a save loaded at a tick boundary plays on exactly.

## After the money is in the wallet, for the '+$' pop over the counter.
signal paid(passenger_id: int, room_id: int, amount: int)

## Ticks to make an order once the guest is at the front.
const ORDER_TICKS := 60
## Ticks a guest stays seated when nothing hurries it.
const DWELL_TICKS := 120
## The approach cell is about a metre from the seated root, so the shuffle in
## and out takes longer than at a gate seat.
const SHUFFLE_TICKS := 12
## Seats tried per visit, nearest the counter first.
const SEAT_TRIES := 4
const HUNGER_START_MIN := 40
const HUNGER_START_MAX := 70
const HUNGER_MAX := 100
const HUNGRY_AT := 50
## A hungry passenger with no visit loses a mood point every this many beats.
const HUNGRY_MOOD_BEATS := 5
## A refused hungry passenger tries again after this long.
const HUNGER_RETRY_TICKS := 100
## Browsing: how near a cafe's order spot a walking passenger must pass, by
## octile distance first and then by path; airside passengers browse more.
const BROWSE_REACH_MM := 5000
const AIRSIDE_BROWSE_REACH_MM := 8000
## A browser drops in only with this much spare beyond the margin. Boarding
## caps the spare: in the reference flight a passenger who reaches the gate
## early has about 220 ticks beyond the margin, whatever it does before.
const BROWSE_SPARE_TICKS := 100
const BROWSE_COOLDOWN_TICKS := 600
## Spend in whole percent: mood 0 spends 80% of the base, 100 spends 120%.
const MOOD_SPEND_MIN := 80
const MOOD_SPEND_SPAN := 40
const AIRSIDE_SPEND_PERCENT := 125
## A guest who leaves early pays this share.
const SHORT_SPEND_PERCENT := 50
const SERVED_MOOD_BONUS := 10
## The stages a visit may start from: heading for security after check-in,
## heading for the gate, or waiting at it.
const START_STAGES: Array[Passenger.Stage] = [
	Passenger.Stage.TO_SECURITY,
	Passenger.Stage.TO_GATE,
	Passenger.Stage.STANDING,
	Passenger.Stage.SEATED,
]

var layout := CafeLayout.new()
## Set by any grid edit: every visit's deadline is worked out again on the
## next tick. PassengerSim.to_snapshot() reconciles first when it is set, so a
## save never holds it set.
var deadlines_stale := false

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
## in a queue it can reach, or the whole visit does not fit. A browsing
## passenger only looks at cafes within its reach and needs
## BROWSE_SPARE_TICKS more to spare.
func try_visit(p: Passenger, browsing := false) -> bool:
	if not START_STAGES.has(p.stage) or _visits.has(p.id):
		return false
	refresh()
	var plan := _plan(p, _reach_mm(p) if browsing else 0)
	if plan.is_empty():
		return false
	var arrival := CafeForecast.visit_arrival(_sim, p, plan["legs"])
	if browsing:
		arrival += BROWSE_SPARE_TICKS
	if not CafeForecast.admits(_sim, p, arrival):
		return false
	_commit(p, plan)
	return true


## Once a simulated second per passenger: hunger rises, unmet hunger costs
## mood, and a hungry or browsing passenger may start a visit.
func beat(p: Passenger) -> void:
	p.hunger = mini(p.hunger + 1, HUNGER_MAX)
	var visit: CafeVisit = _visits.get(p.id)
	if visit != null:
		# The abandon-now forecast with live queues, once a second per guest.
		if not visit.seat.is_empty():
			visit.deadline = CafeForecast.live_deadline(
				_sim, p, visit.seat["approach"], visit.resume_stage
			)
		return
	var hungry := p.hunger >= HUNGRY_AT
	@warning_ignore("integer_division")
	var beat_number := _sim.tick / PassengerSim.BEAT_TICKS
	if hungry and posmod(beat_number, HUNGRY_MOOD_BEATS) == 0:
		p.mood = maxi(p.mood - 1, 0)
	if _sim.tick < p.cafe_cooldown or not START_STAGES.has(p.stage):
		return
	if hungry:
		if not try_visit(p):
			p.cafe_cooldown = _sim.tick + HUNGER_RETRY_TICKS
		return
	var walking := (
		p.is_moving() and p.stage in [Passenger.Stage.TO_SECURITY, Passenger.Stage.TO_GATE]
	)
	if walking and _passing_cafe(p):
		if not try_visit(p, true):
			p.cafe_cooldown = _sim.tick + BROWSE_COOLDOWN_TICKS


## What a visit pays, in whole money: `base` x mood% x airside% x the share
## for the outcome, rounded once (half up).
static func spend(base: int, mood: int, airside: bool, outcome: CafeVisit.Outcome) -> int:
	if outcome == CafeVisit.Outcome.NONE:
		return 0
	# Everything in hundredths of a percent until the one rounding.
	var mood_part := MOOD_SPEND_MIN * PassengerSim.MOOD_MAX + mood * MOOD_SPEND_SPAN
	var side := AIRSIDE_SPEND_PERCENT if airside else 100
	var share := 100 if outcome == CafeVisit.Outcome.COMPLETE else SHORT_SPEND_PERCENT
	var scale := PassengerSim.MOOD_MAX * 100 * 100 * 100
	@warning_ignore("integer_division")
	return (base * mood_part * side * share + scale / 2) / scale


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
		if seat.is_empty() and visit.served:
			# No chair to get up from: a served guest pays and goes on at once,
			# so no visit outlives its seat.
			if visit.outcome == CafeVisit.Outcome.NONE:
				visit.outcome = CafeVisit.Outcome.SHORT
			_end(p, visit)
			continue
		if seat.is_empty() or (counter.is_empty() and not visit.served):
			_leave_early(p, visit)
			continue
		visit.seat = seat
		if deadlines_stale:
			visit.deadline = CafeForecast.live_deadline(
				_sim, p, seat["approach"], visit.resume_stage
			)
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
	deadlines_stale = false


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
	if stage != Passenger.Stage.CAFE_STANDING_UP:
		if visit.resume_stage == Passenger.Stage.TO_SECURITY and not visit.seat.is_empty():
			# The rest of a landside journey runs through the scanners, whose
			# queues can fill between beats: forecast it again every tick.
			visit.deadline = CafeForecast.live_deadline(
				_sim, p, visit.seat["approach"], visit.resume_stage
			)
		if _sim.tick >= visit.deadline:
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
	_settle(p, visit)
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


## The queues for a save, in counter id order.
func queue_records() -> Array:
	var out := []
	var counters: Array = _queues.keys()
	counters.sort()
	for counter_id in counters:
		var q: Dictionary = _queues[counter_id]
		(
			out
			. append(
				{
					"counter": counter_id,
					"room": q["room"],
					"lane": (q["lane"] as Array).duplicate(),
					"serving": q["serving"],
				}
			)
		)
	return out


## Installs visits and queues a CafeSnapshot.load() checked; rederive() then
## rebuilds the seats and the layout.
func restore(state: Dictionary) -> void:
	_visits = state["visits"]
	_queues = state["queues"]
	deadlines_stale = state["deadlines_stale"]


## The grid direction from a queuing or ordering guest to its counter, or
## zero for anyone else.
func counter_facing(p: Passenger) -> Vector2i:
	var visit: CafeVisit = _visits.get(p.id)
	if visit == null or not p.stage in [Passenger.Stage.CAFE_QUEUE, Passenger.Stage.CAFE_ORDER]:
		return Vector2i.ZERO
	var counter := _sim.grid.get_object(visit.counter)
	if counter.is_empty():
		return Vector2i.ZERO
	return -TerminalLayout.front_of(counter["facing"])


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
## ties to the lower room id. With `reach_mm` above 0, only cafes whose order
## spot is that near, by octile distance and then by path. Empty when there
## is none.
func _plan(p: Passenger, reach_mm := 0) -> Dictionary:
	var best := {}
	for cafe in layout.cafes:
		var counter := _soonest_counter(cafe)
		if counter.is_empty():
			continue
		var lane: Array = counter["lane"]
		if reach_mm > 0 and Passenger.octile_mm(p.at, lane[0]) > reach_mm:
			continue
		var seat := _free_seat(cafe, lane[0])
		if seat.is_empty():
			continue
		var route := _route(p, lane[queue_of(counter["id"]).size()])
		if route.is_empty():
			continue
		var mm: int = route["mm"]
		if reach_mm > 0 and mm > reach_mm:
			continue
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


## The shortest way from where `p` stands to `target`: {"path", "keep", "mm",
## "from"}. Partway along a step, the passenger either finishes it and goes on
## from its far cell, or turns back; "from" is the cell the path starts at
## (the step's far cell when turning back), "keep" the progress already made
## from it along the path's first step, and "mm" the walk still to do. Empty
## when there is no way.
func _route(p: Passenger, target: Vector2i) -> Dictionary:
	var here := _sim.grid.find_path(p.at, target)
	var stay := {}
	if not here.is_empty():
		stay = {"path": here, "keep": 0, "from": p.at, "mm": Passenger.path_mm(here)}
	if not p.is_moving() or p.seg_mm == 0:
		return stay
	var next := p.path[p.path_index + 1]
	if not _sim.grid.can_route(p.at, next):
		return stay
	var step_mm := Passenger.segment_mm(p.at, next)
	var best := {}
	if not here.is_empty():
		var back := here.duplicate()
		back.push_front(next)
		var back_mm := p.seg_mm + Passenger.path_mm(here)
		best = {"path": back, "keep": step_mm - p.seg_mm, "from": next, "mm": back_mm}
	var ahead := _sim.grid.find_path(next, target)
	if not ahead.is_empty():
		var on_mm := step_mm - p.seg_mm + Passenger.path_mm(ahead)
		if best.is_empty() or on_mm <= int(best["mm"]):
			ahead.push_front(p.at)
			best = {"path": ahead, "keep": p.seg_mm, "from": p.at, "mm": on_mm}
	return best


func _reach_mm(p: Passenger) -> int:
	return AIRSIDE_BROWSE_REACH_MM if p.cleared else BROWSE_REACH_MM


## Whether some cafe's order spot is within the passenger's browse reach, by
## octile distance (the cheap first test; _plan() checks the path).
func _passing_cafe(p: Passenger) -> bool:
	refresh()
	var reach := _reach_mm(p)
	for cafe in layout.cafes:
		for counter in cafe["counters"]:
			if Passenger.octile_mm(p.at, counter["lane"][0]) <= reach:
				return true
	return false


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
	p.at = route["from"]
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


## A served guest gets up: the visit is paid for as it does.
func _stand(p: Passenger, visit: CafeVisit) -> void:
	_settle(p, visit)
	_set_stage.call(p, Passenger.Stage.CAFE_STANDING_UP)


## The visit is over: the guest goes on with its journey.
func _end(p: Passenger, visit: CafeVisit) -> void:
	_settle(p, visit)
	_remove(visit)
	_resume(p, visit)


## Pays for a served visit once: the amount goes into the wallet, the visit
## is marked settled, the guest's hunger and mood change, and then `paid` is
## emitted. A visit with no outcome (not served) pays nothing. Without a
## wallet, or when the wallet refuses, nothing is settled and an error says so.
func _settle(p: Passenger, visit: CafeVisit) -> void:
	if visit.settled or visit.outcome == CafeVisit.Outcome.NONE:
		return
	var base := RoomTypes.get_type(&"cafe").base_spend
	var airside := visit.resume_stage == Passenger.Stage.TO_GATE
	var amount := spend(base, p.mood, airside, visit.outcome)
	if _sim.wallet == null:
		push_error("CafeSim: no wallet to pay passenger %d's %d into" % [p.id, amount])
		return
	if not _sim.wallet.credit(amount):
		push_error("CafeSim: the wallet refused passenger %d's %d" % [p.id, amount])
		return
	visit.amount = amount
	visit.settled = true
	p.hunger = 0
	if visit.outcome == CafeVisit.Outcome.COMPLETE:
		p.mood = mini(p.mood + SERVED_MOOD_BONUS, PassengerSim.MOOD_MAX)
	paid.emit(p.id, visit.room, amount)


## Gives up before being served: no charge and nothing changes for the guest.
func _abandon(p: Passenger, visit: CafeVisit) -> void:
	_remove(visit)
	_resume(p, visit)


func _resume(p: Passenger, visit: CafeVisit) -> void:
	p.cafe_cooldown = _sim.tick + BROWSE_COOLDOWN_TICKS
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
	deadlines_stale = true
