class_name CafeSnapshot
extends RefCounted
## The JSON shape of CafeSim's state inside a passenger save (key "cafe"), and
## its checks on load: every visit with its queue place, reserved seat, where
## the journey resumes, service and dwell progress and settlement, and every
## counter queue in order. Seat holders and the layout are rebuilt.

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
## can be checked against its passenger's stage.
static func load(data: Variant, passengers: Dictionary) -> Dictionary:
	if typeof(data) != TYPE_DICTIONARY or not (data.has("visits") and data.has("queues")):
		return {"error": "cafe must hold visits and queues"}
	if not data.has("deadlines_stale") or typeof(data["deadlines_stale"]) != TYPE_BOOL:
		return {"error": "cafe deadlines_stale must be true or false"}
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
	var queues := _queues(data["queues"], visits)
	if queues.has("error"):
		return queues
	return {"visits": visits, "queues": queues, "deadlines_stale": data["deadlines_stale"]}


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
## dictionary with "error". Every guest named has a visit and is in one queue.
static func _queues(list: Array, visits: Dictionary) -> Dictionary:
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
			if (visits[id] as CafeVisit).counter != int(entry["counter"]):
				return {"error": "cafe guest %d queues at a counter it did not choose" % id}
	# A guest queues until it is served, and never after.
	for id in visits:
		if (visits[id] as CafeVisit).served == placed.has(id):
			return {"error": "cafe guest %d is in a queue it should not be in, or missing" % id}
	return queues
