class_name BuildGridSnapshot
extends RefCounted
## Shape checks for a BuildGrid snapshot, run before anything is loaded.
## Rule checks (overlaps, unknown objects, bad facings) are left to the
## placement rules, which BuildGrid.from_snapshot() runs on every object.


## A description of the first structural problem, or "" when the snapshot
## has the right keys, types, lengths and value ranges.
static func problem(data: Dictionary) -> String:
	for key in BuildGrid.SNAPSHOT_KEYS:
		if not data.has(key):
			return "missing key '%s'" % key
	for key in ["width", "height"]:
		if not _is_whole_in(data[key], 1, BuildGrid.MAX_SIDE_CELLS):
			return "%s must be a whole number from 1 to %d" % [key, BuildGrid.MAX_SIDE_CELLS]
	var problem_text := _cells_problem(data, int(data["width"]), int(data["height"]))
	if problem_text != "":
		return problem_text
	return _objects_problem(data["objects"], data["next_object_id"])


static func _cells_problem(data: Dictionary, width: int, height: int) -> String:
	var checks := [
		["floor", width * height, BuildGrid.MAX_FLOOR_TYPE],
		["zone", width * height, BuildGrid.MAX_ZONE_ID],
		["h_walls", width * (height + 1), 1],
		["v_walls", (width + 1) * height, 1],
	]
	for check in checks:
		var values: Variant = data[check[0]]
		if typeof(values) != TYPE_ARRAY or (values as Array).size() != check[1]:
			return "%s must be an array of %d values" % [check[0], check[1]]
		for value in values:
			if not _is_whole_in(value, 0, check[2]):
				return "%s values must be whole numbers from 0 to %d" % [check[0], check[2]]
	return ""


static func _objects_problem(objects: Variant, next_id: Variant) -> String:
	if typeof(objects) != TYPE_ARRAY:
		return "objects must be an array"
	var seen := {}
	for entry in objects:
		var entry_problem := _object_problem(entry)
		if entry_problem != "":
			return entry_problem
		var object_id := int(entry["id"])
		if seen.has(object_id):
			return "object id %d appears twice" % object_id
		seen[object_id] = true
	var highest: int = seen.keys().max() if not seen.is_empty() else 0
	if not _is_whole_in(next_id, highest + 1, BuildGrid.MAX_ZONE_ID):
		return "next_object_id must be a whole number above every object id"
	return ""


static func _object_problem(entry: Variant) -> String:
	var shape := _object_keys_problem(entry)
	if shape != "":
		return shape
	if not _is_whole_in(entry["id"], 1, BuildGrid.MAX_ZONE_ID):
		return "object id must be a whole number, 1 or more"
	if typeof(entry["def"]) != TYPE_STRING:
		return "object def must be a string"
	var anchor: Variant = entry["anchor"]
	var anchor_ok := typeof(anchor) == TYPE_ARRAY and (anchor as Array).size() == 2
	if not anchor_ok or not _is_whole(anchor[0]) or not _is_whole(anchor[1]):
		return "object anchor must be two whole numbers"
	if not _is_whole(entry["facing"]):
		return "object facing must be a whole number"
	return ""


static func _object_keys_problem(entry: Variant) -> String:
	if typeof(entry) != TYPE_DICTIONARY:
		return "each object must be a dictionary"
	for key in BuildGrid.OBJECT_KEYS:
		if not (entry as Dictionary).has(key):
			return "object is missing key '%s'" % key
	return ""


static func _is_whole_in(value: Variant, low: int, high: int) -> bool:
	return _is_whole(value) and value >= low and value <= high


static func _is_whole(value: Variant) -> bool:
	return WholeNumber.is_whole(value)
