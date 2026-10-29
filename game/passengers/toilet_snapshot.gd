class_name ToiletSnapshot
extends RefCounted
## The JSON shape of ToiletSim's state inside a passenger save (key "toilet"),
## and its checks on load: every visit with its reserved stall, room, where
## the journey resumes and its deadline. Stall holders and the layout are
## rebuilt; how far a timed phase has got is the passenger's stage tick.
##
## A load is refused, changing nothing, unless the state is one continuous play
## can reach: ids positive; one visit per passenger and per stall; each
## visit's stall usable in the toilet layout rebuilt from the saved grid, in
## the room saved; every passenger in a toilet stage holding a visit, and a
## visit held only in a toilet stage or while getting up from a gate seat;
## the visit resuming on the passenger's side of security; a passenger inside
## the stall standing on its approach cell with no walk; and a timed phase that
## started on the stage tick and ends after the saved tick.
##
## SaveGame waits for the tick after a grid edit, so in play a save holds
## "deadlines_stale" false. A caller that settles only the cafe by hand
## (CafeSim.reconcile()) can save it true; it is kept, so the loaded game
## works the deadlines out again on its next tick as the saved one would. A
## visit whose stall that edit removed is still refused.

const VISIT_FIELDS := ["passenger", "room", "stall", "resume_stage", "deadline"]
const RESUME_STAGES := [Passenger.Stage.TO_SECURITY, Passenger.Stage.TO_GATE]


static func save(toilets: ToiletSim) -> Dictionary:
	var visits := []
	for id in toilets.visit_ids():
		var visit := toilets.visit_of(id)
		(
			visits
			. append(
				{
					"passenger": visit.passenger,
					"room": visit.room,
					"stall": visit.stall_id,
					"resume_stage": visit.resume_stage,
					"deadline": visit.deadline,
				}
			)
		)
	return {"visits": visits, "deadlines_stale": toilets.deadlines_stale}


## {"visits": {passenger id: ToiletVisit}, "deadlines_stale": bool} from a
## save(), or a dictionary with "error". `passengers` maps each saved
## passenger's id to its Passenger; `grid` holds the saved grid and `tick` is
## the saved tick.
static func load(data: Variant, passengers: Dictionary, grid: BuildGrid, tick: int) -> Dictionary:
	if typeof(data) != TYPE_DICTIONARY or not data.has("visits"):
		return {"error": "toilet must hold visits"}
	if not data.has("deadlines_stale") or typeof(data["deadlines_stale"]) != TYPE_BOOL:
		return {"error": "toilet deadlines_stale must be true or false"}
	if typeof(data["visits"]) != TYPE_ARRAY:
		return {"error": "toilet visits must be an array"}
	var visits := {}
	var stalls := {}
	for entry in data["visits"]:
		var visit := _visit(entry)
		if visit == null or visits.has(visit.passenger) or stalls.has(visit.stall_id):
			return {"error": "toilet visit %s is malformed or repeated" % str(entry).left(80)}
		if not passengers.has(visit.passenger):
			return {"error": "toilet visit of unknown passenger %d" % visit.passenger}
		visits[visit.passenger] = visit
		stalls[visit.stall_id] = true
	for id in passengers:
		var stage: Passenger.Stage = (passengers[id] as Passenger).stage
		var inside := Passenger.in_toilet(stage)
		if inside and not visits.has(id):
			return {"error": "passenger %d is at a toilet with no visit" % id}
		if visits.has(id) and not (inside or stage == Passenger.Stage.STANDING_UP):
			return {"error": "passenger %d has a toilet visit but is not at a toilet" % id}
	var layout := ToiletLayout.new()
	layout.rebuild(grid)
	for id in visits:
		var problem := _visit_problem(visits[id], passengers[id], layout, tick)
		if problem != "":
			return {"error": "toilet visit of passenger %d: %s" % [id, problem]}
	return {"visits": visits, "deadlines_stale": data["deadlines_stale"]}


## Why a visit cannot be what continuous play left by `tick`, or "" when it
## can.
static func _visit_problem(
	visit: ToiletVisit, p: Passenger, layout: ToiletLayout, tick: int
) -> String:
	var stall := layout.stall(visit.stall_id)
	if stall.is_empty():
		return "no such toilet stall"
	if int(stall["room"]) != visit.room:
		return "the stall is not in room %d" % visit.room
	if (visit.resume_stage == Passenger.Stage.TO_GATE) != p.cleared:
		return "it resumes on the other side of security"
	if ToiletSim.STALL_STAGES.has(p.stage) and (p.at != stall["approach"] or p.is_moving()):
		return "it is inside the stall but not on its approach cell"
	if ToiletSim.PHASE_TICKS.has(p.stage):
		var length: int = ToiletSim.PHASE_TICKS[p.stage]
		if p.stage_tick > tick or p.stage_tick + length <= tick:
			return "stage %d does not run past the saved tick" % p.stage
	return ""


static func _visit(entry: Variant) -> ToiletVisit:
	if typeof(entry) != TYPE_DICTIONARY:
		return null
	for field in VISIT_FIELDS:
		if not entry.has(field) or not WholeNumber.is_whole(entry[field]):
			return null
	var visit := ToiletVisit.new()
	visit.passenger = int(entry["passenger"])
	visit.room = int(entry["room"])
	visit.stall_id = int(entry["stall"])
	visit.deadline = int(entry["deadline"])
	var resume := int(entry["resume_stage"])
	if not RESUME_STAGES.has(resume) or visit.passenger < 1:
		return null
	if visit.room < 1 or visit.stall_id < 1:
		return null
	visit.resume_stage = resume as Passenger.Stage
	return visit
