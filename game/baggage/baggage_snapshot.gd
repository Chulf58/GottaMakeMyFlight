class_name BaggageSnapshot
extends RefCounted
## The bags' part of a whole-world save (SaveGame part "baggage"): the bags,
## the per-flight results and the totals. No route is saved: BagRoutes
## rebuilds the field from the saved grid, and a save is taken only after the
## tick that reconciled the last edit, so every saved bag already fits it.
##
## load() checks the part alone; grid_problem() checks the bags against the
## field built from a grid (BaggageSim.from_snapshot and SaveLinks run it).
## The passenger and desk ids on a bag are historical and never checked
## against the other parts: a settled passenger is retired and a desk can be
## demolished while its bags remain.

const SAVE_VERSION := 1
const KEYS := ["save_version", "tick", "next_id", "bags", "results", "loaded_total", "missed_total"]
const BAG_KEYS := [
	"id",
	"passenger",
	"flight",
	"desk",
	"state",
	"cause",
	"cell",
	"from",
	"remain_mm",
	"from_desk",
	"wait_tick",
	"created_tick",
	"cutoff_tick",
	"rest_tick",
	"outcome_tick",
]
const RESULT_KEYS := ["loaded", "missed", "causes"]
## The whole-number fields of a saved bag that are ticks or ids, at least 0.
const COUNT_FIELDS := ["id", "passenger", "desk", "wait_tick", "created_tick"]


static func save(sim: BaggageSim, next_id: int) -> Dictionary:
	var bags := []
	for bag in sim.bags():
		(
			bags
			. append(
				{
					"id": bag.id,
					"passenger": bag.passenger,
					"flight": bag.flight,
					"desk": bag.desk,
					"state": bag.state,
					"cause": bag.cause,
					"cell": [bag.cell.x, bag.cell.y],
					"from": [bag.from_step.x, bag.from_step.y],
					"remain_mm": bag.remain_mm,
					"from_desk": bag.from_desk,
					"wait_tick": bag.wait_tick,
					"created_tick": bag.created_tick,
					"cutoff_tick": bag.cutoff_tick,
					"rest_tick": bag.rest_tick,
					"outcome_tick": bag.outcome_tick,
				}
			)
		)
	return {
		"save_version": SAVE_VERSION,
		"tick": sim.tick,
		"next_id": next_id,
		"bags": bags,
		"results": sim.results.duplicate(true),
		"loaded_total": sim.loaded_total,
		"missed_total": sim.missed_total,
	}


## {"error": reason}, or {"tick", "next_id", "bags": Array[Bag], "results",
## "loaded_total", "missed_total"} with every number an int.
static func load(data: Dictionary) -> Dictionary:
	var problem := _top_problem(data)
	var bags: Array[Bag] = []
	var results := {}
	if problem == "":
		problem = _read_bags(data["bags"], int(data["tick"]), int(data["next_id"]), bags)
	if problem == "":
		problem = _read_results(data["results"], results)
	if problem == "":
		problem = _totals_problem(data, bags, results)
	if problem != "":
		return {"error": problem}
	return {
		"tick": int(data["tick"]),
		"next_id": int(data["next_id"]),
		"bags": bags,
		"results": results,
		"loaded_total": int(data["loaded_total"]),
		"missed_total": int(data["missed_total"]),
	}


## "" or the first bag that does not fit the field `routes`: a bag on a belt
## whose state is not the one the field gives it (BaggageSim.belt_state), a
## bag in the room not on a root, or two bags on one cell.
static func grid_problem(bags: Array[Bag], routes: BagRoutes) -> String:
	var taken := {}
	for bag in bags:
		if bag.state == Bag.State.IN_ROOM and not routes.is_root(bag.cell):
			return "bag %d is in the room at %s, which is no bag room's end" % [bag.id, bag.cell]
		if not bag.on_belt():
			continue
		var state := BaggageSim.belt_state(bag, routes)
		if state != bag.state:
			return (
				"bag %d is %s at %s but the belts make it %s"
				% [bag.id, Bag.State.keys()[bag.state], bag.cell, Bag.State.keys()[state]]
			)
		for cell in [bag.cell, bag.physical_cell()]:
			if taken.get(cell, bag.id) != bag.id:
				return "bags %d and %d are on one belt cell %s" % [taken[cell], bag.id, cell]
			taken[cell] = bag.id
	return ""


static func _top_problem(data: Dictionary) -> String:
	var problem := ""
	for key in data.keys():
		if problem == "" and not KEYS.has(key):
			problem = "unknown key '%s'" % key
	for key in KEYS:
		if problem == "" and not data.has(key):
			problem = "missing key '%s'" % key
	if problem != "":
		return problem
	if not WholeNumber.is_whole(data["save_version"]) or int(data["save_version"]) != SAVE_VERSION:
		return "save_version must be %d" % SAVE_VERSION
	for key in ["tick", "loaded_total", "missed_total"]:
		if not _is_count(data[key]):
			return "%s must be a whole number of at least 0" % key
	if not WholeNumber.is_whole(data["next_id"]) or int(data["next_id"]) < 1:
		return "next_id must be a whole number of at least 1"
	if typeof(data["bags"]) != TYPE_ARRAY or typeof(data["results"]) != TYPE_DICTIONARY:
		return "bags must be a list and results a dictionary"
	return ""


static func _read_bags(saved: Array, tick: int, next_id: int, out: Array[Bag]) -> String:
	var last_id := 0
	# Passenger id -> bag id: one bag per passenger, whether or not the
	# passenger is still in the passengers part.
	var owners := {}
	for entry in saved:
		if typeof(entry) != TYPE_DICTIONARY:
			return "a bag is not a dictionary"
		var bag := Bag.new()
		var problem := _read_bag(entry, bag)
		if problem == "":
			problem = _bag_rules(bag, tick)
		if problem == "" and (bag.id <= last_id or bag.id >= next_id):
			problem = "ids must rise and stay under next_id"
		if problem == "" and owners.has(bag.passenger):
			problem = "passenger %d already has bag %d" % [bag.passenger, owners[bag.passenger]]
		if problem != "":
			return "bag %s: %s" % [entry.get("id", "?"), problem]
		last_id = bag.id
		owners[bag.passenger] = bag.id
		out.append(bag)
	return ""


static func _read_bag(entry: Dictionary, bag: Bag) -> String:
	var problem := _keys_problem(entry, BAG_KEYS)
	if problem == "":
		problem = _field_problem(entry)
	if problem != "":
		return problem
	bag.id = int(entry["id"])
	bag.passenger = int(entry["passenger"])
	bag.flight = entry["flight"]
	bag.desk = int(entry["desk"])
	bag.state = int(entry["state"]) as Bag.State
	bag.cause = int(entry["cause"]) as Bag.Cause
	bag.cell = Vector2i(int(entry["cell"][0]), int(entry["cell"][1]))
	bag.from_step = Vector2i(int(entry["from"][0]), int(entry["from"][1]))
	bag.remain_mm = int(entry["remain_mm"])
	bag.from_desk = entry["from_desk"]
	bag.wait_tick = int(entry["wait_tick"])
	bag.created_tick = int(entry["created_tick"])
	bag.cutoff_tick = int(entry["cutoff_tick"])
	bag.rest_tick = int(entry["rest_tick"])
	bag.outcome_tick = int(entry["outcome_tick"])
	return ""


## "" when `entry` has exactly `keys`, else the first unknown or missing one.
static func _keys_problem(entry: Dictionary, keys: Array) -> String:
	var problem := ""
	for key in entry.keys():
		if problem == "" and not keys.has(key):
			problem = "unknown key '%s'" % key
	for key in keys:
		if problem == "" and not entry.has(key):
			problem = "missing key '%s'" % key
	return problem


## The type and range of each saved bag field.
static func _field_problem(entry: Dictionary) -> String:
	var problem := ""
	for key in COUNT_FIELDS + ["remain_mm"]:
		if problem == "" and not _is_count(entry[key]):
			problem = "%s must be a whole number of at least 0" % key
	for key in ["rest_tick", "outcome_tick"]:
		if problem == "" and (not WholeNumber.is_whole(entry[key]) or int(entry[key]) < -1):
			problem = "%s must be a whole number of at least -1" % key
	if problem == "" and not WholeNumber.is_whole(entry["cutoff_tick"]):
		problem = "cutoff_tick must be a whole number"
	if problem == "" and typeof(entry["from_desk"]) != TYPE_BOOL:
		problem = "from_desk must be true or false"
	if problem != "":
		return problem
	if typeof(entry["flight"]) != TYPE_STRING or entry["flight"] == "":
		problem = "flight must be a flight id"
	elif not _is_member(entry["state"], Bag.State.values()):
		problem = "state is not a bag state"
	elif not _is_member(entry["cause"], Bag.Cause.values()):
		problem = "cause is not a bag cause"
	elif not _is_pair(entry["cell"]) or not _is_pair(entry["from"]):
		problem = "cell and from must be [x, y] whole numbers"
	return problem


static func _bag_rules(bag: Bag, tick: int) -> String:
	var problem := ""
	if bag.created_tick > tick or bag.wait_tick > tick or bag.wait_tick < bag.created_tick:
		problem = "it was made or began waiting after the saved tick"
	elif bag.is_settled() != (bag.outcome_tick >= 0):
		problem = "only a settled bag has an outcome tick"
	elif bag.is_settled() and (bag.outcome_tick < bag.created_tick or bag.outcome_tick > tick):
		problem = "its outcome tick is outside its life"
	elif not bag.is_settled() and tick >= bag.cutoff_tick:
		problem = "it is still unsettled after its cutoff"
	elif (bag.state == Bag.State.MISSED) != (bag.cause != Bag.Cause.NONE):
		problem = "a missed bag, and only a missed one, has a cause"
	elif (
		bag.state == Bag.State.IN_ROOM
		and (bag.rest_tick < bag.created_tick or bag.rest_tick > tick)
	):
		problem = "a bag in the room needs a rest tick in its life"
	else:
		problem = _edge_rules(bag)
	return problem


## Where a bag may be along its edge, by state. A bag on a belt came in by
## one side and is within one cell of its centre (half a cell from a desk).
## A missed bag keeps the place it stopped at. A bag at a desk, in the room
## or loaded is at no edge.
static func _edge_rules(bag: Bag) -> String:
	var problem := ""
	var side := BuildGrid.SIDE_STEP.has(bag.from_step)
	var stopped := bag.on_belt() or bag.state == Bag.State.MISSED
	if not side and bag.from_step != Vector2i.ZERO:
		problem = "it came in by no side"
	elif bag.on_belt() and not side:
		problem = "a bag on a belt came in by one side"
	elif bag.remain_mm > Bag.CELL_MM or (bag.remain_mm > 0 and not (stopped and side)):
		problem = "remain_mm is outside its edge"
	elif bag.from_desk and bag.remain_mm * 2 > Bag.CELL_MM:
		problem = "a bag from a desk rides half a cell"
	return problem


static func _read_results(saved: Dictionary, out: Dictionary) -> String:
	for flight in saved.keys():
		var problem := ""
		if typeof(flight) != TYPE_STRING or typeof(saved[flight]) != TYPE_DICTIONARY:
			problem = "results must map flight ids to dictionaries"
		else:
			problem = _read_result(saved[flight], out, flight)
		if problem != "":
			return "results for %s: %s" % [flight, problem]
	return ""


static func _read_result(entry: Dictionary, out: Dictionary, flight: String) -> String:
	var problem := _keys_problem(entry, RESULT_KEYS)
	if problem == "" and (not _is_count(entry["loaded"]) or not _is_count(entry["missed"])):
		problem = "loaded and missed must be whole counts"
	if problem == "" and typeof(entry["causes"]) != TYPE_DICTIONARY:
		problem = "causes must be a dictionary"
	if problem != "":
		return problem
	var causes := {}
	var summed := 0
	for key in entry["causes"].keys():
		var count: Variant = entry["causes"][key]
		if (
			problem == ""
			and (key == "none" or not Bag.CAUSE_NAMES.has(key) or not _is_count(count))
		):
			problem = "'%s' is not a cause with a count" % key
		elif problem == "":
			causes[key] = int(count)
			summed += int(count)
	if problem == "" and summed != int(entry["missed"]):
		problem = "the causes must add up to the missed bags"
	if problem == "":
		out[flight] = {
			"loaded": int(entry["loaded"]), "missed": int(entry["missed"]), "causes": causes
		}
	return problem


## The totals cover the results, and each flight's results cover its settled
## bags still kept.
static func _totals_problem(data: Dictionary, bags: Array[Bag], results: Dictionary) -> String:
	var kept := {}
	for bag in bags:
		if bag.is_settled():
			var counts: Array = kept.get(bag.flight, [0, 0])
			counts[0 if bag.state == Bag.State.LOADED else 1] += 1
			kept[bag.flight] = counts
	var sums := [0, 0]
	for flight in results:
		sums[0] += results[flight]["loaded"]
		sums[1] += results[flight]["missed"]
	for flight in kept:
		var result: Dictionary = results.get(flight, {"loaded": 0, "missed": 0})
		if result["loaded"] < kept[flight][0] or result["missed"] < kept[flight][1]:
			return "results for %s count fewer bags than are kept settled" % flight
	if int(data["loaded_total"]) < sums[0] or int(data["missed_total"]) < sums[1]:
		return "the totals are below the results"
	return ""


static func _is_count(value: Variant) -> bool:
	return WholeNumber.is_whole(value) and int(value) >= 0


static func _is_pair(value: Variant) -> bool:
	return (
		typeof(value) == TYPE_ARRAY
		and value.size() == 2
		and WholeNumber.is_whole(value[0])
		and WholeNumber.is_whole(value[1])
	)


static func _is_member(value: Variant, members: Array) -> bool:
	return WholeNumber.is_whole(value) and members.has(int(value))
