class_name IncidentSnapshot
extends RefCounted
## The shape check of the "incidents" SaveGame part (IncidentDirector). The
## part is required: a save without it is refused (SaveGame._shape_problem).
## load() checks a to_snapshot() dictionary, also one that went through JSON
## (whole numbers come back as floats), and returns the loaded state with
## ints, or {"error": reason}. It reads nothing of the world: a scheduled
## incident's fire tick at or behind the clock fires on the next tick.
##
## {"save_version", "enabled", "last_rolled_day" (-1 before the first roll),
##  "next_major_day", "next_id", "incidents": [{"id", "kind", "roll_day",
##  "state", "fire_tick", "cell": [x, y], "mess_id", "place", "outcome"}]}
## A scheduled incident has no cell ([-1, -1]), no mess (0) and no place ("");
## an active one has all three, its place one of IncidentCatalogue.SPILL_PLACES;
## a done one has all three or none, and none when its outcome is NO_PLACE.
## The outcome is "" or, on a done incident only, NO_PLACE (it never happened).
## links_problem() checks an active spill against the staged messes.

const SAVE_VERSION := 1
const KEYS: Array[String] = [
	"save_version", "enabled", "last_rolled_day", "next_major_day", "next_id", "incidents"
]
const INCIDENT_KEYS: Array[String] = [
	"id", "kind", "roll_day", "state", "fire_tick", "cell", "mess_id", "place", "outcome"
]
const NO_CELL := Vector2i(-1, -1)
## The outcome of a spill that was due with nowhere to happen.
const NO_PLACE := "no_place"
const OUTCOMES: Array[String] = ["", NO_PLACE]


## The JSON-safe form of one incident.
static func save_incident(incident: Dictionary) -> Dictionary:
	var cell: Vector2i = incident["cell"]
	return {
		"id": incident["id"],
		"kind": incident["kind"],
		"roll_day": incident["roll_day"],
		"state": incident["state"],
		"fire_tick": incident["fire_tick"],
		"cell": [cell.x, cell.y],
		"mess_id": incident["mess_id"],
		"place": incident["place"],
		"outcome": incident["outcome"],
	}


## "" or why the loaded part (load()) does not match the staged messes
## (MessSim.checked()): every active spill names a SPILL mess at its own cell.
static func links_problem(incidents: Dictionary, messes: Dictionary) -> String:
	var by_id: Dictionary = messes["messes"]
	for incident: Dictionary in incidents["incidents"]:
		if incident["state"] != IncidentCatalogue.ACTIVE:
			continue
		var id: int = incident["id"]
		var mess_id: int = incident["mess_id"]
		if not by_id.has(mess_id):
			return "incident %d names no mess %d" % [id, mess_id]
		var mess: Dictionary = by_id[mess_id]
		if int(mess["kind"]) != MessSim.Kind.SPILL:
			return "incident %d: mess %d is not a spill" % [id, mess_id]
		if mess["cell"] != incident["cell"]:
			return "incident %d: mess %d is not at the incident's cell" % [id, mess_id]
	return ""


static func load(data: Dictionary) -> Dictionary:
	var problem := _top_problem(data)
	if problem != "":
		return {"error": problem}
	var next_id := int(data["next_id"])
	var incidents: Array[Dictionary] = []
	var ids := {}
	for entry: Variant in data["incidents"]:
		var loaded := _incident(entry, next_id)
		if loaded.has("error"):
			return loaded
		if ids.has(loaded["id"]):
			return {"error": "incident id %d is saved twice" % loaded["id"]}
		ids[loaded["id"]] = true
		incidents.append(loaded)
	return {
		"enabled": data["enabled"],
		"last_rolled_day": int(data["last_rolled_day"]),
		"next_major_day": int(data["next_major_day"]),
		"next_id": next_id,
		"incidents": incidents,
	}


static func _top_problem(data: Dictionary) -> String:
	var problem := _keys_problem(data, KEYS, "")
	for field: Array in [["save_version", 1], ["last_rolled_day", -1], ["next_major_day", 0]]:
		if problem == "":
			problem = _whole_problem(data, field[0], field[1], "")
	if problem == "":
		problem = _whole_problem(data, "next_id", 1, "")
	if problem == "" and int(data["save_version"]) != SAVE_VERSION:
		problem = "save_version must be %d" % SAVE_VERSION
	if problem == "" and typeof(data["enabled"]) != TYPE_BOOL:
		problem = "enabled must be a bool"
	if problem == "" and typeof(data["incidents"]) != TYPE_ARRAY:
		problem = "incidents must be an array"
	return problem


static func _incident(entry: Variant, next_id: int) -> Dictionary:
	if typeof(entry) != TYPE_DICTIONARY:
		return {"error": "an incident is not a dictionary"}
	var data: Dictionary = entry
	var problem := _keys_problem(data, INCIDENT_KEYS, "incident ")
	for field: Array in [["id", 1], ["roll_day", 0], ["fire_tick", 0], ["mess_id", 0]]:
		if problem == "":
			problem = _whole_problem(data, field[0], field[1], "incident ")
	if problem == "" and int(data["id"]) >= next_id:
		problem = "incident id %d is not below next_id %d" % [int(data["id"]), next_id]
	if problem == "":
		problem = _kind_problem(data)
	var cell: Variant = _cell_of(data.get("cell"))
	if problem == "" and cell == null:
		problem = "incident %d cell must be two whole numbers" % int(data["id"])
	if problem == "":
		problem = _state_problem(data, cell)
	if problem != "":
		return {"error": problem}
	return {
		"id": int(data["id"]),
		"kind": data["kind"],
		"roll_day": int(data["roll_day"]),
		"state": data["state"],
		"fire_tick": int(data["fire_tick"]),
		"cell": cell,
		"mess_id": int(data["mess_id"]),
		"place": data["place"],
		"outcome": data["outcome"],
	}


static func _kind_problem(data: Dictionary) -> String:
	if typeof(data["kind"]) != TYPE_STRING or not IncidentCatalogue.kinds().has(data["kind"]):
		return "incident %d has an unknown kind %s" % [int(data["id"]), str(data["kind"])]
	var states := IncidentCatalogue.states_for(data["kind"])
	if typeof(data["state"]) != TYPE_STRING or not states.has(data["state"]):
		return (
			"incident %d (%s) cannot be in state %s"
			% [int(data["id"]), data["kind"], data["state"]]
		)
	if typeof(data["place"]) != TYPE_STRING:
		return "incident %d place must be a string" % int(data["id"])
	if typeof(data["outcome"]) != TYPE_STRING or not OUTCOMES.has(data["outcome"]):
		return "incident %d has an unknown outcome %s" % [int(data["id"]), str(data["outcome"])]
	if data["outcome"] != "" and data["state"] != IncidentCatalogue.DONE:
		return "incident %d has an outcome but is not done" % int(data["id"])
	return ""


## A scheduled incident has not happened, so it has no cell, mess or place; an
## active one has all three.
static func _state_problem(data: Dictionary, cell: Vector2i) -> String:
	var id := int(data["id"])
	var placed: bool = cell != NO_CELL or int(data["mess_id"]) != 0 or data["place"] != ""
	if data["state"] == IncidentCatalogue.SCHEDULED and placed:
		return "incident %d is scheduled but has a cell, mess or place" % id
	var whole: bool = cell != NO_CELL and int(data["mess_id"]) > 0 and data["place"] != ""
	if data["state"] == IncidentCatalogue.ACTIVE and not whole:
		return "incident %d is active but lacks its cell, mess or place" % id
	# Done after it happened (whole), or before it was placed (nothing); one
	# that never happened (NO_PLACE) has nothing.
	if data["state"] == IncidentCatalogue.DONE:
		if data["outcome"] == NO_PLACE and placed:
			return "incident %d did not happen but has a cell, mess or place" % id
		if placed and not whole:
			return "incident %d is done but only partly placed" % id
	if whole and not IncidentCatalogue.SPILL_PLACES.has(data["place"]):
		return "incident %d place %s is not a spill place" % [id, data["place"]]
	return ""


static func _keys_problem(data: Dictionary, keys: Array[String], what: String) -> String:
	for key in data.keys():
		if not keys.has(key):
			return "%sunknown key '%s'" % [what, key]
	for key in keys:
		if not data.has(key):
			return "%smissing key '%s'" % [what, key]
	return ""


static func _whole_problem(data: Dictionary, key: String, least: int, what: String) -> String:
	var value: Variant = data[key]
	if not WholeNumber.is_whole(value) or int(value) < least:
		return "%s%s must be a whole number, %d or more" % [what, key, least]
	return ""


## [x, y] of whole numbers as a Vector2i, else null.
static func _cell_of(value: Variant) -> Variant:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 2:
		return null
	for part: Variant in value:
		if not WholeNumber.is_whole(part):
			return null
	return Vector2i(int(value[0]), int(value[1]))
