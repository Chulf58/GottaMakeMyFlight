class_name StaffSnapshot
extends RefCounted
## The JSON shape of StaffSim's state, and its checks on load. Each member's
## committed path, progress and pending replan are saved, so nothing is
## planned differently after a load; station claims are rebuilt from the
## members. Cells are saved as [x, y].
##
## A save from before staff spots (a version 1 save) has its on-duty members
## on the station's service cell (lane slot 0). Such a member loads standing
## on the station's
## staff spot, or, when an old layout left that spot blocked or out of reach
## from every entrance, idle where it stood (walking out if it was leaving),
## since the station can never be staffed. An on-duty member on a free spot
## that no entrance reaches loads the same way.
##
## Version 2 saves each member's post ("slot", StaffMember.Slot). A version 1
## save comes from before helpers and before security lanes could be built or
## loaded, so every member in it works a primary post: _migrated_v1() gives
## each member record slot PRIMARY before the version 2 checks. Only a
## version 1 save has the service-cell migration above: in a version 2 save a
## member on duty away from its post's spot is refused. A version 2 save
## missing a slot is refused. A helper must be a security officer at a
## whole security lane and never leaving; a member with no station holds the
## primary slot; each post (station and slot) is claimed at most once.

const KEYS := ["save_version", "next_id", "members"]
const MEMBER_KEYS := [
	"id",
	"role",
	"state",
	"station",
	"slot",
	"at",
	"path",
	"path_index",
	"seg_mm",
	"needs_replan",
	"search_failed",
	"leaving",
]
const INT_FIELDS := ["id", "role", "state", "station", "slot", "path_index", "seg_mm"]
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
					"slot": m.slot,
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
## must already hold the saved world. `saved` itself is never changed.
static func load(saved: Dictionary, sim: PassengerSim) -> Dictionary:
	for key in KEYS:
		if not saved.has(key):
			return {"error": "missing '%s'" % key}
	if not WholeNumber.is_whole(saved["save_version"]):
		return {"error": "save_version is not a whole number"}
	var data := saved
	var v1 := int(saved["save_version"]) == 1
	if v1:
		var migrated: Variant = _migrated_v1(saved)
		if migrated is String:
			return {"error": migrated}
		data = migrated
	elif int(saved["save_version"]) != StaffSim.SAVE_VERSION:
		return {
			"error":
			"save_version %s is not 1 or %d" % [saved["save_version"], StaffSim.SAVE_VERSION]
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
		var parsed: Variant = _member(record, sim, v1)
		if parsed is String:
			return {"error": parsed}
		var m: StaffMember = parsed
		if m.id <= last_id or m.id >= next_id:
			return {"error": "member %d is out of order or not below next_id" % m.id}
		last_id = m.id
		if m.station != 0:
			var post := Vector2i(m.station, m.slot)
			if claimed.has(post):
				return {
					"error": "station %d's %s post is claimed twice" % [m.station, _slot_name(m)]
				}
			claimed[post] = true
		members.append(m)
	return {"next_id": next_id, "members": members}


## A deep copy of a version 1 save with slot PRIMARY on every member record
## (version 1 had no helpers), or a String naming what is wrong. Anything
## else wrong is left for the version 2 checks.
static func _migrated_v1(saved: Dictionary) -> Variant:
	var data: Dictionary = saved.duplicate(true)
	data["save_version"] = StaffSim.SAVE_VERSION
	if typeof(data["members"]) != TYPE_ARRAY:
		return data
	for record: Variant in data["members"]:
		if typeof(record) != TYPE_DICTIONARY:
			continue
		if (record as Dictionary).has("slot"):
			return "a version 1 member has a 'slot', which version 1 never saved"
		record["slot"] = StaffMember.Slot.PRIMARY
	return data


static func _slot_name(m: StaffMember) -> String:
	return "helper" if m.slot == StaffMember.Slot.HELPER else "primary"


## A StaffMember, or a String naming what is wrong with the record. `v1`: the
## record comes from a version 1 save, the only kind the service-cell
## migration applies to.
static func _member(record: Variant, sim: PassengerSim, v1: bool) -> Variant:
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
	if not StaffMember.Slot.values().has(int(record["slot"])):
		return "member %d has an unknown slot" % m.id
	m.role = int(record["role"]) as StaffMember.Role
	m.state = int(record["state"]) as StaffMember.State
	m.station = int(record["station"])
	m.slot = int(record["slot"]) as StaffMember.Slot
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
	if v1:
		_migrate_service_cell(m, sim)
	_release_unreachable(m, sim)
	var problem := _place_problem(m)
	if problem == "":
		problem = _duty_problem(m, sim)
	if problem != "":
		return "member %d %s" % [m.id, problem]
	return m


## Moves a member an old save has on duty on its station's service cell onto
## the station's staff spot, or, when the spot is blocked, lets it stand idle
## there (or walk out, if it was leaving). Anything else is left for the
## checks.
static func _migrate_service_cell(m: StaffMember, sim: PassengerSim) -> void:
	if m.state != StaffMember.State.ON_DUTY or m.path_index != m.path.size() - 1 or m.seg_mm != 0:
		return
	var lane: Array = sim.layout.lanes.get(m.station, [])
	if lane.is_empty() or m.at != lane[0] or m.path[m.path_index] != m.at:
		return
	var stations := sim.layout.desks if m.role == StaffMember.Role.CHECKIN else sim.layout.scanners
	if not stations.has(m.station):
		return
	var here: Array[Vector2i] = [m.at]
	var never := _never_staffed(m, sim)
	if not never:
		m.at = StaffPosts.spot(sim.grid, sim.layout, m.station, m.slot)
		here = [m.at]
	m.set_path(here)
	if not never:
		return
	_stand_down(m)


## An on-duty member of an old save, standing on its station's free spot,
## when staff can no longer reach that spot from any entrance (a layout saved
## before the reach rule): it stands idle there, or walks out if it was
## leaving, as StaffSim would release it.
static func _release_unreachable(m: StaffMember, sim: PassengerSim) -> void:
	if m.state != StaffMember.State.ON_DUTY or m.is_moving():
		return
	if StaffPosts.blocked(sim.grid, sim.layout, m.station):
		return
	if StaffPosts.unreachable(sim.grid, sim.layout, m.station, m.slot):
		_stand_down(m)


## Whether staff can never work `m`'s post: its spot is blocked, or no
## entrance has a way to it.
static func _never_staffed(m: StaffMember, sim: PassengerSim) -> bool:
	if StaffPosts.blocked(sim.grid, sim.layout, m.station):
		return true
	return StaffPosts.unreachable(sim.grid, sim.layout, m.station, m.slot)


## Leaves the member idle where it stands, or walking out if it was leaving.
static func _stand_down(m: StaffMember) -> void:
	m.station = 0
	m.slot = StaffMember.Slot.PRIMARY
	m.state = StaffMember.State.IDLE
	if m.leaving:
		m.leaving = false
		m.state = StaffMember.State.WALKING_OUT
		m.needs_replan = true


## Whether the member's cell, path and progress agree.
static func _place_problem(m: StaffMember) -> String:
	var walking := (
		m.state == StaffMember.State.TO_STATION or m.state == StaffMember.State.WALKING_OUT
	)
	if (
		m.backing_out
		and (not walking or m.in_pool() or m.path_index != 0 or m.path.size() < 2 or m.seg_mm <= 0)
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


## Whether the member's state, station, post and replan flag agree with the
## layout.
static func _duty_problem(m: StaffMember, sim: PassengerSim) -> String:
	if m.station == 0 and m.slot != StaffMember.Slot.PRIMARY:
		return "has no station but a helper slot"
	if m.slot == StaffMember.Slot.HELPER:
		if m.role != StaffMember.Role.SECURITY:
			return "is a helper but not a security officer"
		if not sim.layout.security_lanes.is_complete(m.station):
			return "helps at station %d, which is not a whole security lane" % m.station
		if m.leaving:
			return "is a helper but leaving"
	if m.state == StaffMember.State.IDLE:
		if m.station != 0 or m.is_moving() or m.needs_replan or m.leaving:
			return "is idle but has a station or a walk"
		return ""
	if m.state == StaffMember.State.WALKING_OUT:
		if m.station != 0 or m.leaving:
			return "is walking out but has a station or is leaving"
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
	if StaffPosts.blocked(sim.grid, sim.layout, m.station):
		return "is on duty at station %d, whose staff spot is blocked" % m.station
	if m.at != StaffPosts.spot(sim.grid, sim.layout, m.station, m.slot):
		return "is on duty away from its post's staff spot"
	return ""


static func _cell(value: Variant) -> Variant:
	if typeof(value) != TYPE_ARRAY or value.size() != 2:
		return null
	if not WholeNumber.is_whole(value[0]) or not WholeNumber.is_whole(value[1]):
		return null
	return Vector2i(int(value[0]), int(value[1]))


static func _adjacent(a: Vector2i, b: Vector2i) -> bool:
	return maxi(absi(a.x - b.x), absi(a.y - b.y)) == 1
