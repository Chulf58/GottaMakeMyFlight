class_name CafeSnapshot
extends RefCounted
## The JSON shape of CafeSim's state inside a passenger save (key "cafe"), and
## its checks on load: every visit with its queue place, reserved seat, where
## the journey resumes, service and dwell progress and settlement, and every
## counter queue in order. Seat holders and the layout are rebuilt.
##
## A load is refused, changing nothing, unless the state is one continuous play
## can reach: ids positive; each visit's seat (and, until served, its counter)
## present in the cafe layout rebuilt from the saved grid; each queue in the
## visit's room at an existing counter; served, outcome, settled and amount
## agreeing with the guest's stage; an order in progress, or a seated guest's
## dwell, that started on the guest's stage tick and ends after the saved tick;
## and the visit resuming on the guest's side of security. A save never holds
## stale cafe state: between a grid edit and the next tick's reconcile,
## PassengerSim.to_snapshot() refuses (SaveGame waits for that tick), so
## "deadlines_stale" is always false and a piece missing from the rebuilt
## layout is refused outright, whatever it was.

const VISIT_INT_FIELDS := [
	"passenger",
	"room",
	"counter",
	"resume_stage",
	"deadline",
	"service_end",
	"dwell_end",
	"outcome",
	"amount"
]
const VISIT_BOOL_FIELDS := ["served", "settled"]
const QUEUE_KEYS := ["counter", "room", "lane", "serving"]
const RESUME_STAGES := [Passenger.Stage.TO_SECURITY, Passenger.Stage.TO_GATE]
## Stages before the order is made: getting up from a gate seat, walking to
## the queue, queuing and ordering.
const UNSERVED_STAGES := [
	Passenger.Stage.STANDING_UP,
	Passenger.Stage.CAFE_WALK,
	Passenger.Stage.CAFE_QUEUE,
	Passenger.Stage.CAFE_ORDER,
]


static func save(cafes: CafeSim) -> Dictionary:
	var visits := []
	for id in cafes.visit_ids():
		var visit := cafes.visit_of(id)
		var record := {"seat_key": visit.seat_key}
		for field in VISIT_INT_FIELDS + VISIT_BOOL_FIELDS:
			record[field] = visit.get(field)
		visits.append(record)
	return {
		"visits": visits, "queues": cafes.queue_records(), "deadlines_stale": cafes.deadlines_stale
	}


## {"visits": {passenger id: CafeVisit}, "queues": {counter id: queue},
## "deadlines_stale": bool} from a save(), or a dictionary with "error".
## `passengers` maps each saved passenger's id to its Passenger, so each visit
## can be checked against its passenger's stage; `grid` holds the saved grid
## and `tick` is the saved tick.
static func load(data: Variant, passengers: Dictionary, grid: BuildGrid, tick: int) -> Dictionary:
	if typeof(data) != TYPE_DICTIONARY or not (data.has("visits") and data.has("queues")):
		return {"error": "cafe must hold visits and queues"}
	if not data.has("deadlines_stale") or typeof(data["deadlines_stale"]) != TYPE_BOOL:
		return {"error": "cafe deadlines_stale must be true or false"}
	if data["deadlines_stale"]:
		return {"error": "cafe deadlines_stale must be false: a save settles the cafe first"}
	if typeof(data["visits"]) != TYPE_ARRAY or typeof(data["queues"]) != TYPE_ARRAY:
		return {"error": "cafe visits and queues must be arrays"}
	var visits := {}
	var seats := {}
	for entry in data["visits"]:
		var visit := _visit(entry)
		if visit == null or visits.has(visit.passenger) or seats.has(visit.seat_key):
			return {"error": "cafe visit %s is malformed or repeated" % str(entry).left(80)}
		if not passengers.has(visit.passenger):
			return {"error": "cafe visit of unknown passenger %d" % visit.passenger}
		visits[visit.passenger] = visit
		seats[visit.seat_key] = true
	for id in passengers:
		var stage: Passenger.Stage = (passengers[id] as Passenger).stage
		var at_cafe := Passenger.in_cafe(stage)
		if at_cafe and not visits.has(id):
			return {"error": "passenger %d is at the cafe with no visit" % id}
		if visits.has(id) and not (at_cafe or stage == Passenger.Stage.STANDING_UP):
			return {"error": "passenger %d has a visit but is not at the cafe" % id}
	var terminal := TerminalLayout.new()
	terminal.rebuild(grid)
	var cafes := CafeLayout.new()
	cafes.rebuild(grid, terminal)
	for id in visits:
		var problem := _visit_problem(visits[id], passengers[id], cafes, tick)
		if problem != "":
			return {"error": "cafe visit of passenger %d: %s" % [id, problem]}
	var queues := _queues(data["queues"], visits, cafes)
	if queues.has("error"):
		return queues
	for id in visits:
		var ordering := (passengers[id] as Passenger).stage == Passenger.Stage.CAFE_ORDER
		var visit: CafeVisit = visits[id]
		var serving: int = queues.get(visit.counter, {}).get("serving", 0)
		if ordering != (serving == id):
			return {"error": "cafe guest %d orders but is not served, or the reverse" % id}
	return {"visits": visits, "queues": queues, "deadlines_stale": false}


## Why a visit cannot be what continuous play left by `tick`, or "" when it
## can.
static func _visit_problem(visit: CafeVisit, p: Passenger, cafes: CafeLayout, tick: int) -> String:
	var stage := p.stage
	var unserved := UNSERVED_STAGES.has(stage)
	var standing := stage == Passenger.Stage.CAFE_STANDING_UP
	var key := visit.seat_key.split(":")
	var key_ok := key.size() == 2 and key[0].is_valid_int() and key[1].is_valid_int()
	key_ok = key_ok and int(key[0]) >= 1 and int(key[1]) >= 0
	var checks := [
		[visit.room >= 1 and visit.counter >= 1, "room and counter ids must be 1 or more"],
		[key_ok, "seat key must be <table>:<seat>"],
		[
			(visit.resume_stage == Passenger.Stage.TO_GATE) == p.cleared,
			"it resumes on the other side of security"
		],
		[not cafes.seat(visit.room, visit.seat_key).is_empty(), "no such cafe seat"],
		[
			visit.served or not cafes.counter(visit.room, visit.counter).is_empty(),
			"no such cafe counter"
		],
		[visit.served != unserved, "served does not match stage %d" % stage],
		[(visit.outcome != CafeVisit.Outcome.NONE) == standing, "outcome does not match stage"],
		[not visit.settled or standing, "settled before standing up"],
		[visit.settled or visit.amount == 0, "an amount on a visit not settled"],
		[
			(
				stage != Passenger.Stage.CAFE_ORDER
				or _runs_past(visit.service_end, p.stage_tick, CafeSim.ORDER_TICKS, tick)
			),
			"the order does not end ORDER_TICKS after it started and after the saved tick"
		],
		[
			(
				stage != Passenger.Stage.CAFE_SEATED
				or _runs_past(visit.dwell_end, p.stage_tick, CafeSim.DWELL_TICKS, tick)
			),
			"the dwell does not end DWELL_TICKS after it started and after the saved tick"
		],
	]
	for check in checks:
		if not check[0]:
			return check[1]
	return ""


## Whether a span of `length` ticks that started at `start` (the guest's stage
## tick) ends at `end`, and has started but not ended by `tick`: the step that
## ends it runs on the tick it ends, so a save never holds it at or past then.
static func _runs_past(end: int, start: int, length: int, tick: int) -> bool:
	return end == start + length and start <= tick and end > tick


static func _visit(entry: Variant) -> CafeVisit:
	if typeof(entry) != TYPE_DICTIONARY or not entry.has("seat_key"):
		return null
	if typeof(entry["seat_key"]) != TYPE_STRING:
		return null
	var visit := CafeVisit.new()
	visit.seat_key = entry["seat_key"]
	for field in VISIT_INT_FIELDS:
		if not entry.has(field) or not WholeNumber.is_whole(entry[field]):
			return null
		visit.set(field, int(entry[field]))
	for field in VISIT_BOOL_FIELDS:
		if not entry.has(field) or typeof(entry[field]) != TYPE_BOOL:
			return null
		visit.set(field, entry[field])
	var outcome_ok := visit.outcome >= 0 and visit.outcome < CafeVisit.Outcome.size()
	var settled_ok := not visit.settled or visit.outcome != CafeVisit.Outcome.NONE
	if (
		not RESUME_STAGES.has(visit.resume_stage)
		or not outcome_ok
		or not settled_ok
		or visit.amount < 0
		or visit.passenger < 1
	):
		return null
	return visit


## Counter id -> {"room", "lane", "serving"} from the saved list, or a
## dictionary with "error". Every guest named has a visit and is in one queue,
## in its own room at the counter it chose, which is in the layout with a lane
## cell for each guest.
static func _queues(list: Array, visits: Dictionary, cafes: CafeLayout) -> Dictionary:
	var queues := {}
	var placed := {}
	for entry in list:
		var ok := typeof(entry) == TYPE_DICTIONARY
		for key in QUEUE_KEYS:
			ok = ok and entry.has(key)
		ok = ok and WholeNumber.is_whole(entry["counter"]) and WholeNumber.is_whole(entry["room"])
		ok = ok and WholeNumber.is_whole(entry["serving"]) and typeof(entry["lane"]) == TYPE_ARRAY
		if not ok or queues.has(int(entry["counter"])):
			return {"error": "a cafe queue is malformed or repeated"}
		if int(entry["counter"]) < 1 or int(entry["room"]) < 1:
			return {"error": "a cafe queue's counter and room ids must be 1 or more"}
		var lane := []
		for id in entry["lane"]:
			if not WholeNumber.is_whole(id) or not visits.has(int(id)) or placed.has(int(id)):
				return {"error": "a cafe queue names guest %s with no visit or twice" % str(id)}
			placed[int(id)] = true
			lane.append(int(id))
		var serving := int(entry["serving"])
		if serving != 0 and not lane.has(serving):
			return {"error": "a cafe counter serves guest %d who is not in its queue" % serving}
		queues[int(entry["counter"])] = {
			"room": int(entry["room"]), "lane": lane, "serving": serving
		}
		for id in lane:
			var visit: CafeVisit = visits[id]
			if visit.counter != int(entry["counter"]) or visit.room != int(entry["room"]):
				return {"error": "cafe guest %d queues at a counter it did not choose" % id}
		var counter := int(entry["counter"])
		var cells: Array = cafes.counter(int(entry["room"]), counter).get("lane", [])
		if cells.is_empty() or lane.size() > cells.size():
			return {"error": "cafe counter %d has no lane for its queue" % counter}
	# A guest queues until it is served, and never after.
	for id in visits:
		if (visits[id] as CafeVisit).served == placed.has(id):
			return {"error": "cafe guest %d is in a queue it should not be in, or missing" % id}
	return queues
