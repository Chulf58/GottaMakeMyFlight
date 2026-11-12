class_name IncidentPlan
extends RefCounted
## The saved "plan" of a major incident (IncidentSnapshot): what the fire
## decided, as plain whole numbers and ids, so a load plays the incident on
## exactly. Empty for a minor, for a scheduled major and for a major that was
## never held (outcome not_held). Keys by kind:
##   inspector: window_from, window_to (the visit may land in), visit_tick
##   rush:      flights [{flight, extra, departs}], total, until (tick)
##   vip:       flight, departs, bonus, target (the marked passenger id, 0
##              until one is marked)
##   favour:    flight, departs, extra, bonus

const INT_KEYS := {
	IncidentCatalogue.INSPECTOR: ["window_from", "window_to", "visit_tick"],
	IncidentCatalogue.RUSH: ["total", "until"],
	IncidentCatalogue.VIP: ["departs", "bonus", "target"],
	IncidentCatalogue.FAVOUR: ["departs", "extra", "bonus"],
}
const STRING_KEYS := {
	IncidentCatalogue.INSPECTOR: [],
	IncidentCatalogue.RUSH: [],
	IncidentCatalogue.VIP: ["flight"],
	IncidentCatalogue.FAVOUR: ["flight"],
}
const FLIGHT_KEYS := ["flight", "extra", "departs"]


## The plan checked and read with whole numbers as ints (also from JSON):
## {"plan": …} or {"error": why}. An empty plan is allowed when `may_be_empty`.
static func load(kind: String, plan: Variant, may_be_empty: bool) -> Dictionary:
	if typeof(plan) != TYPE_DICTIONARY:
		return {"error": "plan must be a dictionary"}
	var data: Dictionary = plan
	if data.is_empty():
		if may_be_empty:
			return {"plan": {}}
		return {"error": "a %s incident that happened needs its plan" % kind}
	if not INT_KEYS.has(kind):
		return {"error": "a %s incident has no plan" % kind}
	var ints: Array = INT_KEYS[kind]
	var strings: Array = STRING_KEYS[kind]
	var out := {}
	var expected := ints.size() + strings.size() + (1 if kind == IncidentCatalogue.RUSH else 0)
	if data.size() != expected:
		return {"error": "%s plan has %d keys, not %d" % [kind, data.size(), expected]}
	for key: String in ints:
		if not data.has(key) or not WholeNumber.is_whole(data[key]) or int(data[key]) < 0:
			return {"error": "%s plan %s must be a whole number, 0 or more" % [kind, key]}
		out[key] = int(data[key])
	for key: String in strings:
		if not data.has(key) or typeof(data[key]) != TYPE_STRING or data[key] == "":
			return {"error": "%s plan %s must be a text" % [kind, key]}
		out[key] = data[key]
	if kind == IncidentCatalogue.RUSH:
		var flights := _flights(data.get("flights"))
		if flights.has("error"):
			return flights
		out["flights"] = flights["flights"]
	return {"plan": out}


static func _flights(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or (value as Array).is_empty():
		return {"error": "rush plan flights must be a list of at least one"}
	var out: Array[Dictionary] = []
	for entry: Variant in value:
		if typeof(entry) != TYPE_DICTIONARY or (entry as Dictionary).size() != FLIGHT_KEYS.size():
			return {"error": "a rush plan flight is malformed"}
		var flight: Dictionary = entry
		var id: Variant = flight.get("flight")
		if typeof(id) != TYPE_STRING or id == "":
			return {"error": "a rush plan flight needs an id"}
		for key: String in ["extra", "departs"]:
			if not WholeNumber.is_whole(flight.get(key)) or int(flight[key]) < 1:
				return {"error": "a rush plan flight %s must be a whole number, 1 or more" % key}
		out.append({"flight": id, "extra": int(flight["extra"]), "departs": int(flight["departs"])})
	return {"flights": out}
