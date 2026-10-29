class_name InfoDesk
extends RefCounted
## A staffed info desk helps stuck passengers (decision info-desk-helps-stuck-
## passengers-a-short-help-visit-with-a-m, user-ruled "Calm and re-route"). A
## passenger who cannot find what it needs or whose route is blocked (the
## HELPABLE statuses, while it walks to check-in, to security or to the exit)
## and stands within RANGE_CELLS of a desk with a server on duty (StaffSim,
## the SHOP role, ShopCounters) walks to the desk's interaction cell, is helped
## there for HELP_TICKS, gains BOOST mood and plans its route again. A desk
## nobody staffs does nothing, and neither does one out of range or one with no
## walk of at most MAX_WALK_MM to it.
##
## The visit is not a journey stage: the passenger keeps its stage and its
## stuck status and PassengerSim skips the stage's own logic while the visit
## is held (holds()), so the walk is the visit's and nothing else re-plans it
## or starts a cafe, toilet or kiosk visit under it. When the visit ends the
## stuck status is cleared and the passenger chooses a station or an exit again
## on the next tick: with a route now, it goes on; with none it is stuck again
## and waits.
##
## A passenger that waits with no route in range of a staffed desk loses mood
## more slowly (CALM_STUCK_LOSS a second instead of STUCK_LOSS), visit or not,
## and is helped again only COOLDOWN_TICKS after its last visit, so a boost
## can never keep a hopeless wait from costing mood. A desk that closes or
## goes under a walker ends its visit with no boost; a passenger already being
## helped is helped to the end, as a service under way ends first.
##
## All state is integer ticks and ids, handled by passenger id on the
## passenger's own beat, so a save loaded at a tick boundary plays on exactly.
## It is saved by PassengerSim under "info_desk" (to_list() and checked()).
## Tuned by test_info_desk_tuning.

## After the boost is paid and the passenger is released to plan again.
signal helped(passenger_id: int, desk: int)

## How near a desk a stuck passenger must stand, in cells by octile distance.
## A desk is a landmark, so this is further than a kiosk's browse reach (5 m
## landside, 8 m airside): a lost passenger looks for one. The same 10 m is the
## reach of the calm.
const RANGE_CELLS := 10
const RANGE_MM := RANGE_CELLS * Passenger.STRAIGHT_MM
## The longest walk to a desk, so a desk across a maze is not a help: twice the
## range, 20 m, 10 seconds at WALK_MM.
const MAX_WALK_MM := 2 * RANGE_MM
## Ticks at the desk: 3 s, a check-in transaction (PassengerSim.CHECKIN_TICKS).
const HELP_TICKS := 60
## Mood gained when the help ends: 5 s of an uncalmed stuck loss, a visible
## lift on the 70 a passenger starts with that is never most of it.
const BOOST := 15
## Mood lost each beat (a simulated second) while stuck: the base rate, and
## the calmed one, the same 1 a second as waiting in a queue.
const STUCK_LOSS := 3
const CALM_STUCK_LOSS := 1
## Ticks after a visit before the passenger may be helped again: 30 s, the
## kiosk browse cooldown (ShopSim.BROWSE_COOLDOWN_TICKS). The boost is 15 and a
## calm wait loses 30 in that time, so a hopeless wait still costs mood.
const COOLDOWN_TICKS := 600
## The stuck statuses a desk helps. QUEUE_FULL is a wait for room, not lost.
const HELPABLE: Array[Passenger.Stuck] = [
	Passenger.Stuck.NO_CHECKIN,
	Passenger.Stuck.NO_SECURITY,
	Passenger.Stuck.NO_ROUTE,
	Passenger.Stuck.EXIT_BLOCKED,
]
## The stages whose stuck status is helped: walking to check-in, security, exit.
const HELP_STAGES: Array[Passenger.Stage] = [
	Passenger.Stage.TO_CHECKIN,
	Passenger.Stage.TO_SECURITY,
	Passenger.Stage.TO_EXIT,
]
## A visit's `end` while the passenger is still walking to the desk.
const WALKING := -1
## to_list() with nobody on a visit or on cooldown.
const EMPTY := {"visits": [], "cooldowns": []}

var _sim: PassengerSim
## Passenger id -> {"desk": the desk's object id, "end": the tick the help ends,
## WALKING until the passenger stands at the desk}.
var _visits: Dictionary = {}
## Passenger id -> the first tick it may be helped again.
var _cooldowns: Dictionary = {}


func bind(sim: PassengerSim) -> void:
	_sim = sim


## Whether `p` is on a help visit now.
func holds(p: Passenger) -> bool:
	return _visits.has(p.id)


## The desk `p` is walking to or being helped at, or 0.
func desk_of(p: Passenger) -> int:
	return int((_visits.get(p.id, {}) as Dictionary).get("desk", 0))


## The mood a stuck passenger loses this beat: calmed when a staffed desk is in
## range.
func stuck_loss(p: Passenger) -> int:
	return CALM_STUCK_LOSS if not _in_range(p).is_empty() else STUCK_LOSS


## Staffed info desks (object ids, in id order): those with a server on duty
## who is not leaving.
func open_desks() -> Array[int]:
	var out: Array[int] = []
	if _sim.staff == null:
		return out
	for id in _sim.staff.stations_of(StaffMember.Role.SHOP):
		if ShopCounters.is_roomless(_sim.grid, id) and _sim.staff.is_open(id):
			out.append(id)
	return out


## Once a simulated second per passenger, after its needs: a stuck passenger in
## range of a staffed desk, not on cooldown, sets off for it.
func beat(p: Passenger) -> void:
	if _visits.has(p.id) or not wants_help(p):
		return
	var plan := _plan(p)
	if plan.is_empty():
		return
	var desk: int = plan["desk"]
	var route: Dictionary = plan["route"]
	if not route.is_empty():
		VisitRoute.start(p, route)
	_visits[p.id] = {"desk": desk, "end": WALKING}


## Whether `p` is stuck in a way a desk helps and may be helped now.
func wants_help(p: Passenger) -> bool:
	return (
		HELPABLE.has(p.stuck)
		and HELP_STAGES.has(p.stage)
		and _sim.tick >= int(_cooldowns.get(p.id, 0))
	)


## One tick of a passenger on a visit: it walks to the desk, is helped there,
## and is released with the boost.
func step(p: Passenger) -> void:
	var visit: Dictionary = _visits[p.id]
	var desk: int = visit["desk"]
	if not HELP_STAGES.has(p.stage):
		# Something else took the passenger on: the visit has nothing to hold.
		_visits.erase(p.id)
	elif not ShopCounters.is_roomless(_sim.grid, desk):
		_drop(p)
	elif visit["end"] != WALKING:
		if _sim.tick >= int(visit["end"]):
			_finish(p, desk)
	elif _sim.staff == null or not _sim.staff.is_open(desk):
		_drop(p)
	else:
		_walk(p, visit, desk)


## One tick of the walk to the desk's interaction cell, and the start of the
## help on arrival.
func _walk(p: Passenger, visit: Dictionary, desk: int) -> void:
	if p.is_moving():
		return
	var target := _sim.grid.interaction_cell(desk)
	if p.at == target:
		p.clear_path()
		visit["end"] = _sim.tick + HELP_TICKS
		return
	var path := _sim.grid.find_path(p.at, target)
	if path.is_empty():
		_drop(p)
		return
	p.set_path(path)


## Forgets a passenger that made or missed its flight.
func cleanup(p: Passenger) -> void:
	_visits.erase(p.id)
	_cooldowns.erase(p.id)


## The visits and cooldowns as JSON-safe lists, in passenger id order:
## {"visits": [[id, desk, end]], "cooldowns": [[id, tick]]}.
func to_list() -> Dictionary:
	var visits := []
	var ids: Array = _visits.keys()
	ids.sort()
	for id: int in ids:
		visits.append([id, _visits[id]["desk"], _visits[id]["end"]])
	var cooldowns := []
	ids = _cooldowns.keys()
	ids.sort()
	for id: int in ids:
		cooldowns.append([id, _cooldowns[id]])
	return {"visits": visits, "cooldowns": cooldowns}


## A to_list() dictionary checked against the loaded passenger ids ({id: true}):
## the same dictionary with whole numbers made ints, or {"error": why}. Changes
## nothing.
static func checked(data: Variant, ids: Dictionary) -> Dictionary:
	if typeof(data) != TYPE_DICTIONARY:
		return {"error": "info_desk must be a dictionary"}
	for key in ["visits", "cooldowns"]:
		if not data.has(key) or typeof(data[key]) != TYPE_ARRAY:
			return {"error": "info_desk %s must be a list" % key}
	var out := {"visits": [], "cooldowns": []}
	var seen := {}
	for entry in data["visits"]:
		var row := _row(entry, 3)
		if row.is_empty() or not ids.has(row[0]) or seen.has(row[0]):
			return {"error": "info_desk visit %s is malformed, repeated or unknown" % str(entry)}
		if row[1] < 1 or row[2] < WALKING:
			return {"error": "info_desk visit %s has a desk or end out of range" % str(entry)}
		seen[row[0]] = true
		out["visits"].append(row)
	seen = {}
	for entry in data["cooldowns"]:
		var row := _row(entry, 2)
		if row.is_empty() or not ids.has(row[0]) or seen.has(row[0]) or row[1] < 0:
			return {"error": "info_desk cooldown %s is malformed, repeated or unknown" % str(entry)}
		seen[row[0]] = true
		out["cooldowns"].append(row)
	return out


## Installs a checked() dictionary.
func restore(state: Dictionary) -> void:
	_visits.clear()
	_cooldowns.clear()
	for row: Array in state["visits"]:
		_visits[row[0]] = {"desk": row[1], "end": row[2]}
	for row: Array in state["cooldowns"]:
		_cooldowns[row[0]] = row[1]


## `entry` as `size` ints, or empty when it is not a list of that many whole numbers.
static func _row(entry: Variant, size: int) -> Array[int]:
	var row: Array[int] = []
	if typeof(entry) != TYPE_ARRAY or entry.size() != size:
		return row
	for value in entry:
		if not WholeNumber.is_whole(value):
			row.clear()
			return row
		row.append(int(value))
	return row


## The staffed desks within RANGE_MM of `p` by octile distance, in id order.
func _in_range(p: Passenger) -> Array[int]:
	var out: Array[int] = []
	for desk in open_desks():
		var cell := _sim.grid.interaction_cell(desk)
		if cell != BuildObjectDef.NO_CELL and Passenger.octile_mm(p.at, cell) <= RANGE_MM:
			out.append(desk)
	return out


## The desk to go to and the walk: {"desk", "route"} for the staffed desk in
## range with the shortest walk (the lower id on a tie), the route empty when
## `p` already stands at its cell; else empty.
func _plan(p: Passenger) -> Dictionary:
	var best := {}
	var best_mm := MAX_WALK_MM + 1
	for desk in _in_range(p):
		var cell := _sim.grid.interaction_cell(desk)
		if p.at == cell and not p.is_moving():
			return {"desk": desk, "route": {}}
		var route := VisitRoute.plan(_sim.grid, p, cell)
		if not route.is_empty() and int(route["mm"]) < best_mm:
			best_mm = route["mm"]
			best = {"desk": desk, "route": route}
	return best


## The help is done: the boost, then the passenger plans its route again.
func _finish(p: Passenger, desk: int) -> void:
	p.mood = mini(p.mood + BOOST, PassengerSim.MOOD_MAX)
	p.stuck = Passenger.Stuck.NONE
	p.clear_path()
	_visits.erase(p.id)
	_cooldowns[p.id] = _sim.tick + COOLDOWN_TICKS
	helped.emit(p.id, desk)


## The visit ends with no help: the desk is gone or closed, the walk is cut off
## or the passenger is no longer on a stage a desk helps.
func _drop(p: Passenger) -> void:
	p.clear_path()
	_visits.erase(p.id)
	_cooldowns[p.id] = _sim.tick + COOLDOWN_TICKS
