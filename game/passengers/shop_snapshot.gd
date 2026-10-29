class_name ShopSnapshot
extends RefCounted
## The JSON shape of ShopSim's state inside a passenger save (key "shop"), and
## its checks on load: every visit with its reserved browse slot (display id
## and index), room, where the journey resumes and its deadline. Slot holders
## and the layout are rebuilt; how far a browse has got is the passenger's
## stage tick.
##
## A load is refused, changing nothing, unless the state is one continuous play
## can reach: ids positive; one visit per passenger and per slot; each visit's
## slot usable in the kiosk layout rebuilt from the saved grid, in the room
## saved; every passenger in a kiosk stage holding a visit, and a visit held
## only in a kiosk stage or while getting up from a gate seat; the visit
## resuming on the passenger's side of security; a browser standing on its slot
## with no walk; and a browse that started on the stage tick and ends after the
## saved tick. "deadlines_stale" is kept as ToiletSnapshot keeps it.

const VISIT_FIELDS := ["passenger", "room", "display", "slot", "resume_stage", "deadline"]
const RESUME_STAGES := [Passenger.Stage.TO_SECURITY, Passenger.Stage.TO_GATE]


static func save(shops: ShopSim) -> Dictionary:
	var visits := []
	for id in shops.visit_ids():
		var visit := shops.visit_of(id)
		(
			visits
			. append(
				{
					"passenger": visit.passenger,
					"room": visit.room,
					"display": visit.display,
					"slot": visit.index,
					"resume_stage": visit.resume_stage,
					"deadline": visit.deadline,
				}
			)
		)
	return {"visits": visits, "deadlines_stale": shops.deadlines_stale}


## {"visits": {passenger id: ShopVisit}, "deadlines_stale": bool} from a
## save(), or a dictionary with "error". `passengers` maps each saved
## passenger's id to its Passenger; `grid` holds the saved grid and `tick` is
## the saved tick.
static func load(data: Variant, passengers: Dictionary, grid: BuildGrid, tick: int) -> Dictionary:
	if typeof(data) != TYPE_DICTIONARY or not data.has("visits"):
		return {"error": "shop must hold visits"}
	if not data.has("deadlines_stale") or typeof(data["deadlines_stale"]) != TYPE_BOOL:
		return {"error": "shop deadlines_stale must be true or false"}
	if typeof(data["visits"]) != TYPE_ARRAY:
		return {"error": "shop visits must be an array"}
	var visits := {}
	var slots := {}
	for entry in data["visits"]:
		var visit := _visit(entry)
		if visit == null or visits.has(visit.passenger) or slots.has(visit.slot_key()):
			return {"error": "shop visit %s is malformed or repeated" % str(entry).left(80)}
		if not passengers.has(visit.passenger):
			return {"error": "shop visit of unknown passenger %d" % visit.passenger}
		visits[visit.passenger] = visit
		slots[visit.slot_key()] = true
	for id in passengers:
		var stage: Passenger.Stage = (passengers[id] as Passenger).stage
		var inside := StageKinds.facility(stage) == StageKinds.Facility.SHOP
		if inside and not visits.has(id):
			return {"error": "passenger %d is at a shop with no visit" % id}
		if visits.has(id) and not (inside or stage == Passenger.Stage.STANDING_UP):
			return {"error": "passenger %d has a shop visit but is not at a shop" % id}
	var layout := ShopLayout.new()
	layout.rebuild(grid)
	for id in visits:
		var problem := _visit_problem(visits[id], passengers[id], layout, tick)
		if problem != "":
			return {"error": "shop visit of passenger %d: %s" % [id, problem]}
	return {"visits": visits, "deadlines_stale": data["deadlines_stale"]}


## Why a visit cannot be what continuous play left by `tick`, or "" when it
## can.
static func _visit_problem(visit: ShopVisit, p: Passenger, layout: ShopLayout, tick: int) -> String:
	var slot := layout.slot(visit.display, visit.index)
	if slot.is_empty():
		return "no such browse slot"
	if int(slot["room"]) != visit.room:
		return "the slot is not in room %d" % visit.room
	if (visit.resume_stage == Passenger.Stage.TO_GATE) != p.cleared:
		return "it resumes on the other side of security"
	if p.stage == Passenger.Stage.SHOP_BROWSE:
		if p.at != slot["approach"] or p.is_moving():
			return "it is browsing but not on its slot"
		if p.stage_tick > tick or p.stage_tick + ShopSim.BROWSE_TICKS <= tick:
			return "the browse does not run past the saved tick"
	return ""


static func _visit(entry: Variant) -> ShopVisit:
	if typeof(entry) != TYPE_DICTIONARY:
		return null
	for field in VISIT_FIELDS:
		if not entry.has(field) or not WholeNumber.is_whole(entry[field]):
			return null
	var visit := ShopVisit.new()
	visit.passenger = int(entry["passenger"])
	visit.room = int(entry["room"])
	visit.display = int(entry["display"])
	visit.index = int(entry["slot"])
	visit.deadline = int(entry["deadline"])
	var resume := int(entry["resume_stage"])
	if not RESUME_STAGES.has(resume) or visit.passenger < 1:
		return null
	if visit.room < 1 or visit.display < 1 or visit.index < 0:
		return null
	visit.resume_stage = resume as Passenger.Stage
	return visit
