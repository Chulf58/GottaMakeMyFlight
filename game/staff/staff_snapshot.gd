class_name StaffSnapshot
extends RefCounted
## The JSON shape of StaffSim's state, and its checks on load. Each member's
## committed path, progress and pending replan are saved, so nothing is
## planned differently after a load; station claims are rebuilt from the
## members. Cells are saved as [x, y].

const KEYS := ["save_version", "next_id", "members"]
const MEMBER_KEYS := [
	"id",
	"role",
	"state",
	"station",
	"at",
	"path",
	"path_index",
	"seg_mm",
	"needs_replan",
	"search_failed",
	"leaving",
]
const INT_FIELDS := ["id", "role", "state", "station", "path_index", "seg_mm"]
const BOOL_FIELDS := ["needs_replan", "search_failed", "leaving"]


static func save(members: Array[StaffMember], next_id: int) -> Dictionary:
	var records := []
	for m in members:
		var path := []
		for cell in m.path:
			path.append([cell.x, cell.y])
		(
			records
			. append(
				{
					"id": m.id,
					"role": m.role,
					"state": m.state,
					"station": m.station,
					"at": [m.at.x, m.at.y],
					"path": path,
					"path_index": m.path_index,
					"seg_mm": m.seg_mm,
					"needs_replan": m.needs_replan,
					"search_failed": m.search_failed,
					"leaving": m.leaving,
					"backing_out": m.backing_out,
				}
			)
		)
	return {"save_version": StaffSim.SAVE_VERSION, "next_id": next_id, "members": records}


## {"next_id", "members"} restored, or {"error"}. The sim's layout and grid
## must already hold the saved world.
static func load(data: Dictionary, sim: PassengerSim) -> Dictionary:
	for key in KEYS:
		if not data.has(key):
			return {"error": "missing '%s'" % key}
	if not WholeNumber.is_whole(data["save_version"]):
		return {"error": "save_version is not a whole number"}
	if int(data["save_version"]) != StaffSim.SAVE_VERSION:
		return {
			"error": "save_version %s is not %d" % [data["save_version"], StaffSim.SAVE_VERSION]
		}
	if not WholeNumber.is_whole(data["next_id"]) or int(data["next_id"]) < 1:
		return {"error": "next_id is not a whole number of at least 1"}
	if typeof(data["members"]) != TYPE_ARRAY:
		return {"error": "members is not a list"}
	var next_id := int(data["next_id"])
	var members: Array[StaffMember] = []
	var claimed := {}
	var last_id := 0
	for record in data["members"]:
		var parsed: Variant = _member(record, sim)
		if parsed is String:
			return {"error": parsed}
		var m: StaffMember = parsed
		if m.id <= last_id or m.id >= next_id:
			return {"error": "member %d is out of order or not below next_id" % m.id}
		last_id = m.id
		if m.station != 0:
			if claimed.has(m.station):
				return {"error": "station %d is claimed twice" % m.station}
			claimed[m.station] = true
		members.append(m)
	return {"next_id": next_id, "members": members}


## A StaffMember, or a String naming what is wrong with the record.
static func _member(record: Variant, sim: PassengerSim) -> Variant:
	if typeof(record) != TYPE_DICTIONARY:
		return "a member is not a dictionary"
	for key in MEMBER_KEYS:
		if not record.has(key):
			return "a member has no '%s'" % key
	for key in INT_FIELDS:
		if not WholeNumber.is_whole(record[key]):
			return "member field '%s' is not a whole number" % key
	for key in BOOL_FIELDS:
		if typeof(record[key]) != TYPE_BOOL:
			return "member field '%s' is not true or false" % key
	var m := StaffMember.new()
	m.id = int(record["id"])
	if m.id < 1:
		return "member id %d is below 1" % m.id
	if not StaffMember.Role.values().has(int(record["role"])):
		return "member %d has an unknown role" % m.id
	if not StaffMember.State.values().has(int(record["state"])):
		return "member %d has an unknown state" % m.id
	m.role = int(record["role"]) as StaffMember.Role
	m.state = int(record["state"]) as StaffMember.State
	m.station = int(record["station"])
	m.path_index = int(record["path_index"])
	m.seg_mm = int(record["seg_mm"])
	m.needs_replan = record["needs_replan"]
	m.search_failed = record["search_failed"]
	m.leaving = record["leaving"]
	# Saves from before the flag existed have none: not backing out.
	if record.has("backing_out"):
		if typeof(record["backing_out"]) != TYPE_BOOL:
			return "member field 'backing_out' is not true or false"
		m.backing_out = record["backing_out"]
	var at: Variant = _cell(record["at"])
	if at == null:
		return "member %d stands on no cell" % m.id
	m.at = at
	if typeof(record["path"]) != TYPE_ARRAY:
		return "member %d has no path list" % m.id
	for entry in record["path"]:
		var cell: Variant = _cell(entry)
		if cell == null or not sim.grid.in_bounds(cell):
			return "member %d has a path cell off the grid" % m.id
		if not m.path.is_empty() and not _adjacent(m.path[m.path.size() - 1], cell):
			return "member %d has a path that jumps" % m.id
		m.path.append(cell)
	var problem := _place_problem(m)
	if problem == "":
		problem = _duty_problem(m, sim)
	if problem != "":
		return "member %d %s" % [m.id, problem]
	return m


## Whether the member's cell, path and progress agree.
static func _place_problem(m: StaffMember) -> String:
	if (
		m.backing_out
		and (
			m.state != StaffMember.State.TO_STATION
			or m.in_pool()
			or m.path_index != 0
			or m.path.size() < 2
			or m.seg_mm <= 0
		)
	):
		return "is backing out but not partway through the first step of a walk"
	if m.in_pool():
		if not m.path.is_empty() or m.path_index != 0 or m.seg_mm != 0 or m.needs_replan:
			return "is in the pool but has a walk"
		return "" if m.state == StaffMember.State.IDLE else "is in the pool but not idle"
	if m.path_index < 0 or m.path_index >= m.path.size() or m.path[m.path_index] != m.at:
		return "does not stand on its path"
	var length := 0
	if m.is_moving():
		length = Passenger.segment_mm(m.at, m.path[m.path_index + 1])
	if m.seg_mm < 0 or (m.seg_mm > 0 and m.seg_mm >= length):
		return "is further along its step than the step is long"
	return ""


## Whether the member's state, station and replan flag agree with the layout.
static func _duty_problem(m: StaffMember, sim: PassengerSim) -> String:
	if m.state == StaffMember.State.IDLE:
		if m.station != 0 or m.is_moving() or m.needs_replan or m.leaving:
			return "is idle but has a station or a walk"
		return ""
	var stations := sim.layout.desks
	if m.role == StaffMember.Role.SECURITY:
		stations = sim.layout.scanners
	if not stations.has(m.station):
		return "works at station %d, which is not one of its role" % m.station
	if m.leaving and m.state != StaffMember.State.ON_DUTY:
		return "is leaving but not on duty"
	if m.state != StaffMember.State.ON_DUTY:
		return ""
	if m.is_moving() or m.needs_replan:
		return "is on duty but walking"
	if not sim.layout.is_usable(m.station):
		return "is on duty at station %d, which is not usable" % m.station
	if m.at != sim.layout.lanes[m.station][0]:
		return "is on duty away from its station service cell"
	return ""


static func _cell(value: Variant) -> Variant:
	if typeof(value) != TYPE_ARRAY or value.size() != 2:
		return null
	if not WholeNumber.is_whole(value[0]) or not WholeNumber.is_whole(value[1]):
		return null
	return Vector2i(int(value[0]), int(value[1]))


static func _adjacent(a: Vector2i, b: Vector2i) -> bool:
	return maxi(absi(a.x - b.x), absi(a.y - b.y)) == 1
