# gdlint:disable = max-public-methods
# ShopSim is the kiosk visit API: NeedsPolicy asks it whether a visit is
# wanted and viable before one starts, and the sim, the views and the save
# each read it, so it has more than 20 public methods.
class_name ShopSim
extends RefCounted
## Kiosk visits, owned by PassengerSim and stepped inside its tick (decision
## boredom-and-shops-design-boredom-need-while-waiting-kiosk-sh, point 2). A
## kiosk's browse slots (ShopLayout) are its use slots, with no queue and no
## checkout: a visit reserves its slot when it is committed, so a passenger
## still walking there holds it. A visit is committed only when VisitForecast
## admits the whole of it on real routes. The passenger walks to the slot,
## browses there facing the display for BROWSE_TICKS and its journey goes on
## where it left off: TO_SECURITY landside, TO_GATE airside. A passenger
## seated at a gate stands up first.
##
## A kiosk is open only while a shop server is on duty at one of its counters
## (ShopCounters.room_open(); ruling store-mechanics-draw-a-room-then-furnish-
## it-required-pieces, point 3); a closed kiosk gets no visit. When it closes,
## a passenger still walking there (or getting up for it) gives up, unpaid; one
## already browsing finishes and pays, as a service under way ends first.
##
## Two things start a visit, both through NeedsPolicy: boredom at or over
## BoredomSim.BORED_AT (wants_relief(), retrying after RETRY_TICKS when no slot
## is free or there is no time), and spare time (wants_browse()): a passenger
## walking past a kiosk within its reach, airside further, with SPARE_TICKS
## more to spare than the visit needs, who tries again after
## BROWSE_COOLDOWN_TICKS. Every visit ends with that cooldown too.
##
## Every shop type runs on this pipeline (RoomTypes.RoomType.shop: the kiosk,
## the pharmacy, duty free and fashion); what differs per type is its data: the
## browse piece and its slots (ShopLayout), the counter or till that opens it
## (ShopCounters.COUNTER_ROOMS) and its base spend. "Kiosk" below stands for
## any of them.
##
## Money is settled once, when the browse finishes: spend() of the base spend
## of the visited room's type, nudged by mood, with the airside bonus, credited to
## PassengerSim.wallet as Wallet.Category.SHOP; then boredom is reset and
## `paid` is emitted. A browse that does not finish (its deadline passed, its
## slot or kiosk gone) pays nothing and leaves boredom as it was.
##
## Every phase checks the visit's deadline: the last tick the passenger can
## leave the slot and still reach the plane door VisitForecast.MARGIN_TICKS
## before the doors close. A browse that completes on that tick settles; one
## that would complete after it ends unpaid. It is worked out again after any grid edit, once a
## second on the passenger's beat, and every tick for a landside visit.
##
## Visits and slots are handled in id and key order with integer quantities
## only, so a save loaded at a tick boundary plays on exactly. Who owns which
## visit and slot, the choice of slot and the reconcile walk are
## FacilitySlots', shared with ToiletSim; the browse, its outcome and the
## money are here.

## After the money is in the wallet, for the '+$' pop over the kiosk.
signal paid(passenger_id: int, room_id: int, amount: int)

## Ticks spent browsing at the slot.
const BROWSE_TICKS := 120
## The tick between the end of the walk and the first tick of the browse: the
## walk step sees the passenger standing at the slot only on the tick after it
## arrived.
const ARRIVE_TICKS := 1
## A bored passenger who could not start a visit tries again after this long.
const RETRY_TICKS := 100
## After a visit, or a spare-time browse that could not start, no visit is
## considered for this long.
const BROWSE_COOLDOWN_TICKS := 600
## Spare-time browsing: how near a browse slot a walking passenger must pass,
## by octile distance first and then by path; airside passengers browse more.
const BROWSE_REACH_MM := 5000
const AIRSIDE_BROWSE_REACH_MM := 8000
## A spare-time browser drops in only with this much spare beyond the margin.
const SPARE_TICKS := 100
## The phases that check the deadline: all of them.
const CHECKED_STAGES: Array[Passenger.Stage] = [
	Passenger.Stage.SHOP_WALK,
	Passenger.Stage.SHOP_BROWSE,
]

var layout := ShopLayout.new()
## Set by any grid edit: every visit's deadline is worked out again on the
## next tick. Saved as it is, so a loaded game does the same.
var deadlines_stale: bool:
	get:
		return _core.deadlines_stale
	set(value):
		_core.deadlines_stale = value

var _sim: PassengerSim
var _set_stage: Callable
var _leave_station: Callable
var _release_gate_seat: Callable
## The visits (passenger id -> ShopVisit) and slot holders, keyed by slot key.
var _core := FacilitySlots.new()


## Wires the sim's own stage, station and gate-seat helpers in, so a stage
## change still emits PassengerSim.stage_changed.
func bind(
	sim: PassengerSim, set_stage: Callable, leave_station: Callable, release_gate_seat: Callable
) -> void:
	_sim = sim
	_set_stage = set_stage
	_leave_station = leave_station
	_release_gate_seat = release_gate_seat
	_core.bind(sim, layout)


## What a finished browse pays, in whole money: `base` nudged by mood with the
## airside bonus, as a full cafe visit is (CafeSim.spend()).
static func spend(base: int, mood: int, airside: bool) -> int:
	return CafeSim.spend(base, mood, airside, CafeVisit.Outcome.COMPLETE)


func visit_of(passenger_id: int) -> ShopVisit:
	return _core.visit_of(passenger_id)


func visit_ids() -> Array[int]:
	return _core.ids()


## The passenger holding a slot, walkers included, or 0.
func slot_holder(key: String) -> int:
	return _core.holder(key)


## Whether `p` is bored and may start a visit now.
func wants_relief(p: Passenger) -> bool:
	return BoredomSim.is_bored(p) and _may_start(p)


## Whether `p`, not bored, is walking past a kiosk within its browse reach and
## may start a visit now.
func wants_browse(p: Passenger) -> bool:
	if BoredomSim.is_bored(p) or not _may_start(p):
		return false
	var walking := (
		p.is_moving() and p.stage in [Passenger.Stage.TO_SECURITY, Passenger.Stage.TO_GATE]
	)
	return walking and _passing_shop(p)


## The visit `p` would start now, without starting it: {"slot", "route"} for
## the free slot nearest by path (within its reach when `browsing`) when the
## forecast admits the whole visit, with SPARE_TICKS more when browsing; else
## empty. Changes nothing but the derived layout.
func plan_visit(p: Passenger, browsing := false) -> Dictionary:
	if not CafeSim.START_STAGES.has(p.stage):
		return {}
	if StageKinds.visit_facility(_sim, p) != StageKinds.Facility.NONE:
		return {}
	refresh()
	var plan := _plan(p, _reach_mm(p) if browsing else 0)
	if plan.is_empty():
		return {}
	var slot: Dictionary = plan["slot"]
	var arrival := VisitForecast.arrival(
		_sim, p, _visit_ticks(p, plan["route"]["mm"]), slot["approach"], 0, _resume_stage(p)
	)
	if browsing:
		arrival += SPARE_TICKS
	if not VisitForecast.admits(_sim, p, arrival):
		return {}
	return plan


## Starts the visit a plan_visit() returned on this tick.
func commit_visit(p: Passenger, plan: Dictionary) -> void:
	var slot: Dictionary = plan["slot"]
	var visit := ShopVisit.new()
	visit.passenger = p.id
	visit.room = slot["room"]
	visit.display = slot["display"]
	visit.index = slot["index"]
	visit.slot = slot
	visit.resume_stage = _resume_stage(p)
	visit.deadline = VisitForecast.deadline(_sim, p, slot["approach"], 0, visit.resume_stage)
	_core.reserve(visit)
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


## A wanted visit could not start: `p` carries on and tries again after
## RETRY_TICKS, or BROWSE_COOLDOWN_TICKS after a spare-time browse.
func refuse(p: Passenger, browsing := false) -> void:
	p.shop_cooldown = _sim.tick + (BROWSE_COOLDOWN_TICKS if browsing else RETRY_TICKS)


## Once a simulated second per passenger: a visit under way has its deadline
## forecast again. Boredom itself is BoredomSim's.
func beat(p: Passenger) -> void:
	var visit := visit_of(p.id)
	if visit != null and (CHECKED_STAGES.has(p.stage) or p.stage == Passenger.Stage.STANDING_UP):
		visit.deadline = _live_deadline(p, visit)


## Rebuilds the layout after an edit and brings visits in line with it: a
## visit whose slot is gone ends unpaid, and every deadline is forecast again.
## Called at the start of every tick, before anyone steps.
func reconcile() -> void:
	_core.reconcile(_keep, _live_deadline)


## Rebuilds the layout when an edit made it stale.
func refresh() -> void:
	_core.refresh()


## One tick of a passenger in a kiosk stage.
func step(p: Passenger) -> void:
	var visit := visit_of(p.id)
	if visit == null:
		push_error("ShopSim: passenger %d is in a kiosk stage with no visit" % p.id)
		_set_stage.call(p, Passenger.Stage.TO_GATE if p.cleared else Passenger.Stage.TO_SECURITY)
		return
	if visit.resume_stage == Passenger.Stage.TO_SECURITY:
		# The rest of a landside journey runs through the scanners, whose
		# queues can fill between beats: forecast it again every tick.
		visit.deadline = _live_deadline(p, visit)
	# A browse that completes on the deadline tick itself still settles: the
	# deadline is the last tick the passenger may leave the slot.
	var browsed := (
		p.stage == Passenger.Stage.SHOP_BROWSE and _sim.tick - p.stage_tick >= BROWSE_TICKS
	)
	if browsed and _sim.tick <= visit.deadline:
		_settle(p, visit)
		_end(p, visit)
		return
	if _sim.tick >= visit.deadline:
		_end(p, visit)
		return
	if p.stage == Passenger.Stage.SHOP_WALK:
		_walk_step(p, visit)


## A passenger who got up from a gate seat for the kiosk sets off for it.
func depart(p: Passenger) -> void:
	var visit := visit_of(p.id)
	var route := VisitRoute.plan(_sim.grid, p, visit.slot.get("approach", p.at))
	if _sim.tick >= visit.deadline or visit.slot.is_empty() or route.is_empty():
		_end(p, visit)
		return
	_walk(p, route)


## Drops the visit of a passenger who made or missed the flight.
func cleanup(p: Passenger) -> void:
	var visit := visit_of(p.id)
	if visit != null:
		_core.release(visit)


## The grid direction a browsing passenger faces (towards the display), or
## zero otherwise.
func browse_facing(p: Passenger) -> Vector2i:
	var visit := visit_of(p.id)
	if visit == null or visit.slot.is_empty() or p.stage != Passenger.Stage.SHOP_BROWSE:
		return Vector2i.ZERO
	return visit.slot["facing"]


## The lower-case name of the shop type `passenger_id` is visiting ("kiosk",
## "pharmacy"), or empty with no visit or when its room is gone.
func store_name(passenger_id: int) -> String:
	var visit := visit_of(passenger_id)
	if visit == null:
		return ""
	var room := _sim.grid.get_room(visit.room)
	if room.is_empty():
		return ""
	return RoomTypes.get_type(room["type"]).display_name.to_lower()


## Installs visits a ShopSnapshot.load() checked; rederive() then rebuilds the
## slot holders and the layout.
func restore(state: Dictionary) -> void:
	_core.restore(state["visits"], state["deadlines_stale"])


## Rebuilds what is derived from the visits after a load.
func rederive() -> void:
	_core.rederive()
	for id in visit_ids():
		var visit := visit_of(id)
		visit.slot = layout.slot(visit.display, visit.index)


func _may_start(p: Passenger) -> bool:
	return (
		_sim.tick >= p.shop_cooldown
		and CafeSim.START_STAGES.has(p.stage)
		and StageKinds.visit_facility(_sim, p) == StageKinds.Facility.NONE
	)


func _reach_mm(p: Passenger) -> int:
	return AIRSIDE_BROWSE_REACH_MM if p.cleared else BROWSE_REACH_MM


## Whether some free slot is within the passenger's browse reach, by octile
## distance (the cheap first test; _plan() checks the path).
func _passing_shop(p: Passenger) -> bool:
	refresh()
	var reach := _reach_mm(p)
	for shop in layout.shops:
		if not ShopCounters.room_open(_sim, shop["room"]):
			continue
		for slot in shop["slots"]:
			if _core.is_free(slot["key"]) and Passenger.octile_mm(p.at, slot["approach"]) <= reach:
				return true
	return false


## The free slot of an open kiosk nearest `p` by path, with the walk:
## {"slot", "route"} (FacilitySlots.nearest()). Slots at the same octile distance are tried in
## display id and then index order, and on an equal path the one tried first
## wins. Only slots within `reach_mm` by path count when it is above 0. Empty
## when no free slot can be reached.
func _plan(p: Passenger, reach_mm := 0) -> Dictionary:
	var slots: Array = []
	for shop in layout.shops:
		if not ShopCounters.room_open(_sim, shop["room"]):
			continue
		for slot in shop["slots"]:
			slots.append(
				{"key": slot["key"], "order": [slot["display"], slot["index"]], "entry": slot}
			)
	var best := _core.nearest(p, slots, reach_mm)
	if best.is_empty():
		return {}
	return {"slot": best["entry"], "route": best["route"]}


## Ticks from now until a visit walking `walk_mm` leaves its slot.
func _visit_ticks(p: Passenger, walk_mm: int) -> int:
	var pre := PassengerSim.STAND_UP_TICKS if p.stage == Passenger.Stage.SEATED else 0
	return pre + JourneyForecast.walk_ticks(walk_mm) + ARRIVE_TICKS + BROWSE_TICKS


func _live_deadline(p: Passenger, visit: ShopVisit) -> int:
	if visit.slot.is_empty():
		return visit.deadline
	return VisitForecast.live_deadline(_sim, p, visit.slot["approach"], 0, visit.resume_stage)


func _resume_stage(p: Passenger) -> Passenger.Stage:
	if p.stage == Passenger.Stage.TO_SECURITY:
		return Passenger.Stage.TO_SECURITY
	return Passenger.Stage.TO_GATE


func _walk(p: Passenger, route: Dictionary) -> void:
	VisitRoute.start(p, route)
	_set_stage.call(p, Passenger.Stage.SHOP_WALK)


func _walk_step(p: Passenger, visit: ShopVisit) -> void:
	if p.is_moving():
		return
	var approach: Vector2i = visit.slot["approach"]
	if p.at == approach:
		p.clear_path()
		_set_stage.call(p, Passenger.Stage.SHOP_BROWSE)
		return
	var path := _sim.grid.find_path(p.at, approach)
	if path.is_empty():
		_end(p, visit)
		return
	p.set_path(path)


## The browse finished: the money goes into the wallet, then boredom is reset
## and `paid` is emitted. Without a wallet, or when the wallet refuses,
## nothing is settled and an error says so.
func _settle(p: Passenger, visit: ShopVisit) -> void:
	var airside := visit.resume_stage == Passenger.Stage.TO_GATE
	var type := RoomTypes.get_type(_sim.grid.get_room(visit.room)["type"])
	var amount := spend(type.base_spend, p.mood, airside)
	if _sim.wallet == null:
		push_error("ShopSim: no wallet to pay passenger %d's %d into" % [p.id, amount])
		return
	if not _sim.wallet.credit(amount, Wallet.Category.SHOP):
		push_error("ShopSim: the wallet refused passenger %d's %d" % [p.id, amount])
		return
	p.boredom = 0
	paid.emit(p.id, visit.room, amount)


## FacilitySlots.reconcile()'s check of one visit: its slot entry is brought
## up to date, or the slot or its kiosk is gone, or the kiosk closed before
## the browse began, and the visit ends unpaid (one still getting up from a
## gate seat lets the gate take over).
func _keep(p: Passenger, visit: ShopVisit) -> bool:
	var slot := layout.slot(visit.display, visit.index)
	var closed := (
		p.stage != Passenger.Stage.SHOP_BROWSE and not ShopCounters.room_open(_sim, visit.room)
	)
	if slot.is_empty() or int(slot["room"]) != visit.room or closed:
		if p.stage == Passenger.Stage.STANDING_UP:
			_core.release(visit)
		else:
			_end(p, visit)
		return false
	visit.slot = slot
	return true


## The visit is over, finished or not: the passenger goes on with its journey.
func _end(p: Passenger, visit: ShopVisit) -> void:
	_core.release(visit)
	p.shop_cooldown = _sim.tick + BROWSE_COOLDOWN_TICKS
	p.station = 0
	p.stuck = Passenger.Stuck.NONE
	p.clear_path()
	_set_stage.call(p, visit.resume_stage)
