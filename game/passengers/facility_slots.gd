class_name FacilitySlots
extends RefCounted
## The core ToiletSim and ShopSim share (decision
## boredom-and-shops-design-boredom-need-while-waiting-kiosk-sh, point 5):
## which passenger owns which visit, who holds each use slot, the choice of
## the free slot nearest by path, reserving and releasing a slot, and the walk
## over the visits that brings them in line with the grid after an edit. Each
## facility keeps its own phases and poses, what an interrupted use leaves
## behind and what a visit pays. CafeSim, with its queues and seats, does not
## use it.
##
## A visit is any object with a `passenger` id, a `deadline` and a
## `slot_key()`; a slot is held by one visit from its commit on, walk
## included. The layout is the facility's own (ToiletLayout, ShopLayout), any
## object with `rebuild(grid)`, rebuilt only when an edit made it stale.
## Visits are walked in passenger id order and slots in a fixed order, so a
## save loaded at a tick boundary plays on exactly.

## Set by any grid edit: reconcile() works every visit's deadline out again
## on the next tick. Saved as it is, so a loaded game does the same.
var deadlines_stale := false

var _sim: PassengerSim
var _layout: RefCounted
## Passenger id -> visit.
var _visits: Dictionary = {}
## Derived: slot key -> passenger id.
var _holders: Dictionary = {}
var _layout_dirty := true


## Whether the whole footprint of an object, and its interaction cell when it
## has one, lie in `area`: the rule RoomRules counts a room's pieces by.
static func piece_inside(grid: BuildGrid, id: int, area: Rect2i) -> bool:
	var record := grid.get_object(id)
	var def := BuildCatalog.get_def(record["def"])
	for cell in def.footprint(record["anchor"], record["facing"]):
		if not area.has_point(cell):
			return false
	var spot := grid.interaction_cell(id)
	return spot == BuildObjectDef.NO_CELL or area.has_point(spot)


## Wires the sim and the facility's layout in; any edit of the sim's grid
## makes the layout and every deadline stale.
func bind(sim: PassengerSim, layout: RefCounted) -> void:
	_sim = sim
	_layout = layout
	_layout_dirty = true
	if not sim.grid.edit_applied.is_connected(_on_edit_applied):
		sim.grid.edit_applied.connect(_on_edit_applied)


## Rebuilds the layout when an edit made it stale.
func refresh() -> void:
	if not _layout_dirty:
		return
	_layout.rebuild(_sim.grid)
	_layout_dirty = false


func visit_of(passenger_id: int) -> Variant:
	return _visits.get(passenger_id)


func ids() -> Array[int]:
	var out: Array[int] = []
	out.assign(_visits.keys())
	out.sort()
	return out


## The passenger holding a slot, walkers included, or 0.
func holder(key: Variant) -> int:
	return _holders.get(key, 0)


func is_free(key: Variant) -> bool:
	return not _holders.has(key)


## Gives `visit` to its passenger and holds its slot for it.
func reserve(visit: Variant) -> void:
	_visits[visit.passenger] = visit
	_holders[visit.slot_key()] = visit.passenger


## Drops `visit`, and frees its slot when the slot is still held for it.
func release(visit: Variant) -> void:
	_visits.erase(visit.passenger)
	var key: Variant = visit.slot_key()
	if _holders.get(key, 0) == visit.passenger:
		_holders.erase(key)


## Installs visits a snapshot load checked; rederive() then rebuilds the slot
## holders and the layout.
func restore(visits: Dictionary, stale: bool) -> void:
	_visits = visits
	deadlines_stale = stale


## Rebuilds the layout and the slot holders from the visits after a load, in
## passenger id order.
func rederive() -> void:
	_layout_dirty = true
	refresh()
	_holders.clear()
	for id in ids():
		_holders[_visits[id].slot_key()] = id


## The free slot nearest `p` by path, with the walk: {"entry", "route"}, or
## empty when no free slot can be reached. `slots` holds one {"key", "order",
## "entry"} per slot, its entry carrying the "approach" cell the passenger
## walks to, and `order` an array that orders slots at the same distance.
## Slots are tried by octile distance and then `order`; octile distance (less
## a diagonal step for a passenger partway along one) is a lower bound on the
## path, so slots further than the best path so far are skipped. On an equal
## path the slot tried first wins, or the one with the lower `order` when
## `tie_by_order` is set. Only slots within `reach_mm` by path count when it
## is above 0.
func nearest(p: Passenger, slots: Array, reach_mm := 0, tie_by_order := false) -> Dictionary:
	var free: Array = []
	for slot: Dictionary in slots:
		if _holders.has(slot["key"]):
			continue
		var octile := Passenger.octile_mm(p.at, slot["entry"]["approach"])
		if reach_mm > 0 and octile - Passenger.DIAGONAL_MM > reach_mm:
			continue
		free.append([octile, slot["order"], slot["entry"]])
	free.sort()
	var best := {}
	var best_order: Array = []
	for item: Array in free:
		if not best.is_empty() and item[0] - Passenger.DIAGONAL_MM > int(best["route"]["mm"]):
			break
		var route := VisitRoute.plan(_sim.grid, p, item[2]["approach"])
		if route.is_empty() or (reach_mm > 0 and int(route["mm"]) > reach_mm):
			continue
		var mm := int(route["mm"])
		var better: bool = best.is_empty() or mm < int(best["route"]["mm"])
		if tie_by_order and not better and mm == int(best["route"]["mm"]):
			better = item[1] < best_order
		if better:
			best = {"entry": item[2], "route": route}
			best_order = item[1]
	return best


## Rebuilds the layout and brings every visit in line with it, in passenger
## id order, at the start of a tick before anyone steps. `keep` takes the
## passenger and its visit: it refreshes the visit's slot entry and returns
## true, or ends a visit whose slot is gone and returns false. After an edit
## each kept visit's deadline is `live_deadline` of the passenger and visit.
func reconcile(keep: Callable, live_deadline: Callable) -> void:
	refresh()
	for id in ids():
		var visit: Variant = _visits.get(id)
		var p := _sim.get_passenger(id)
		if keep.call(p, visit) and deadlines_stale:
			visit.deadline = live_deadline.call(p, visit)
	deadlines_stale = false


func _on_edit_applied(_edit: BuildEdit, _result: BuildResult) -> void:
	_layout_dirty = true
	deadlines_stale = true
