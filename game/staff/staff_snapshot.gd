class_name StaffSnapshot
extends RefCounted
## The JSON shape of StaffSim's state, and its checks on load. Each member's
## committed path, progress and pending replan are saved, so nothing is
## planned differently after a load; station claims are rebuilt from the
## members. Cells are saved as [x, y].
##
## Only the current version (StaffSim.SAVE_VERSION, 11) loads: an older save is
## refused, never migrated (no save migrations before the first release,
## decision old-saves-are-not-supported-until-after-a-release-no-save-mi).
##
## "closed" lists the stations the player closed (StationClosures.live_ids()):
## whole numbers in rising order, each an object on the grid that is a
## closable station (StationClosures.closable_def()).
##
## "faults" lists the scanner faults (StationFaults.live()) as [station,
## repair tick] pairs in rising station order, each station an object on the
## grid that can fault (StationFaults.checked()).
##
## Each member saves its post ("slot", StaffMember.Slot). A helper must be a
## security officer at a whole security lane and never leaving; a member with
## no station holds the primary slot; each post (station and slot) is claimed
## at most once; a member on duty stands on its post's staff spot. A shop
## server's station must be a usable counter (ShopCounters). An on-duty member
## on a free spot that no entrance reaches loads idle where it stands (walking
## out if it was leaving), since the station can never be staffed.
##
## Cleaners (StaffMember.Role.CLEANER) save their job, whether it is a bin and
## the work left. A cleaner has no station, slot or leaving flag; idle or
## walking out it has no job, walking to its job it has no work left yet, and
## on duty it stands still on its job's spot (CleanerJobs.spot_of(): the
## mess's approach cell or the bin's) with work left of at most the job's
## full time. Every other member has no job. The jobs are checked against the
## messes, which load first: a mess job must be a saved mess claimed by that
## cleaner, a bin job a full bin on the grid that no other cleaner holds, and
## every claimed mess must be the job of the cleaner it names.

const KEYS := ["save_version", "next_id", "members", "closed", "faults"]
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
	"job",
	"job_bin",
	"work_left",
	"bag_carry",
	"bag_target",
	"ramp_job",
	"ramp_shuttle_id",
	"ramp_flight_id",
	"energy",
	"energy_ticks",
	"break_room",
	"break_spot",
	"level",
	"display_name",
	"quirks",
]
const INT_FIELDS := ["id", "role", "state", "station", "slot", "path_index", "seg_mm", "level"]
const BOOL_FIELDS := ["needs_replan", "search_failed", "leaving", "job_bin"]


static func save(
	members: Array[StaffMember],
	next_id: int,
	closed: Array[int],
	faults: Array,
	last_unclaimed_sig := 0,
) -> Dictionary:
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
					"job": m.job,
					"job_bin": m.job_bin,
					"work_left": m.work_left,
					"bag_carry": m.bag_carry,
					"bag_target": m.bag_target,
					"patrol_wait": m.patrol_wait,
					"ramp_job": m.ramp_job,
					"ramp_shuttle_id": m.ramp_shuttle_id,
					"ramp_flight_id": m.ramp_flight_id,
					"energy": m.energy,
					"energy_ticks": m.energy_ticks,
					"break_room": m.break_room,
					"break_spot": [m.break_spot.x, m.break_spot.y],
					"level": m.level,
					"display_name": m.display_name,
					"quirks": m.quirks.duplicate(),
				}
			)
		)
	return {
		"save_version": StaffSim.SAVE_VERSION,
		"next_id": next_id,
		"members": records,
		"closed": closed.duplicate(),
		"faults": faults.duplicate(true),
		"last_unclaimed_sig": last_unclaimed_sig,
	}


## {"next_id", "members", "closed", "faults"} restored, or {"error"}. The sim's layout
## and grid must already hold the saved world. `saved` itself is never changed. The
## cleaners' jobs are checked against `messes`, a {"messes", "bins"} state as
## MessSim.checked() returns it, or, when it is empty, the sim's own MessSim
## (MessSim.claim_state()).
static func load(saved: Dictionary, sim: PassengerSim, messes := {}) -> Dictionary:
	# The version first: an older save lacks the keys added since ("closed").
	if not saved.has("save_version"):
		return {"error": "missing 'save_version'"}
	if not WholeNumber.is_whole(saved["save_version"]):
		return {"error": "save_version is not a whole number"}
	if int(saved["save_version"]) != StaffSim.SAVE_VERSION:
		return {
			"error": "save_version %s is not %d" % [saved["save_version"], StaffSim.SAVE_VERSION]
		}
	for key in KEYS:
		if not saved.has(key):
			return {"error": "missing '%s'" % key}
	var data := saved
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
			var post := Vector2i(m.station, m.slot)
			if claimed.has(post):
				return {
					"error": "station %d's %s post is claimed twice" % [m.station, _slot_name(m)]
				}
			claimed[post] = true
		members.append(m)
	var state := messes if not messes.is_empty() else sim.messes.claim_state()
	var problem := _jobs_problem(members, state, sim.grid)
	if problem != "":
		return {"error": problem}
	var closed: Variant = _closed(data["closed"], sim.grid)
	if closed is String:
		return {"error": closed}
	var faults: Variant = StationFaults.checked(data["faults"], sim.grid)
	if faults is String:
		return {"error": faults}
	var out := {"next_id": next_id, "members": members, "closed": closed, "faults": faults}
	if data.has("last_unclaimed_sig"):
		var raw_sig: Variant = data["last_unclaimed_sig"]
		if (
			not typeof(raw_sig) in [TYPE_INT, TYPE_FLOAT]
			or not is_finite(float(raw_sig))
			or float(raw_sig) != floor(float(raw_sig))
		):
			return {"error": "last_unclaimed_sig is not a whole number"}
		out["last_unclaimed_sig"] = int(raw_sig)
	return out


## The saved closed stations as ids, or a String naming what is wrong: a list
## of whole numbers in rising order, each an object on `grid` of a closable
## kind (StationClosures.closable_def()).
static func _closed(value: Variant, grid: BuildGrid) -> Variant:
	if typeof(value) != TYPE_ARRAY:
		return "closed is not a list"
	var out: Array[int] = []
	for entry: Variant in value:
		if not WholeNumber.is_whole(entry):
			return "a closed station is not a whole number"
		var id := int(entry)
		if not out.is_empty() and id <= out[out.size() - 1]:
			return "closed station %d is out of order or listed twice" % id
		var record := grid.get_object(id)
		if record.is_empty():
			return "closed station %d is no object on the grid" % id
		if not StationClosures.closable_def(StringName(record["def"])):
			return "closed station %d is no station the player can close" % id
		out.append(id)
	return out


## Whether the cleaners' jobs and the claimed messes in `state` ({"messes",
## "bins"}, see load()) agree: "" or what is wrong.
static func _jobs_problem(
	members: Array[StaffMember], state: Dictionary, grid: BuildGrid
) -> String:
	var messes: Dictionary = state["messes"]
	var holders := {}
	var bins_held := {}
	for m in members:
		if m.job == 0:
			continue
		var spot: Vector2i
		var most := CleanerJobs.EMPTY_TICKS
		if m.job_bin:
			if bins_held.has(m.job):
				return "bin %d is the job of two cleaners" % m.job
			bins_held[m.job] = true
			var bin := grid.get_object(m.job)
			if bin.get("def", &"") != MessSim.BIN_ID:
				return "cleaner %d's job %d is not a bin on the grid" % [m.id, m.job]
			if int(state["bins"].get(m.job, 0)) < MessSim.BIN_EMPTY_MIN:
				return "cleaner %d's bin %d is not at or above half full" % [m.id, m.job]
			spot = MessSim.approach_for(grid, bin["anchor"])
		else:
			if not messes.has(m.job):
				return "cleaner %d's job is mess %d, which is not saved" % [m.id, m.job]
			var mess: Dictionary = messes[m.job]
			if int(mess["claimed_by"]) != m.id:
				return "cleaner %d's mess %d is not claimed by it" % [m.id, m.job]
			holders[m.job] = m.id
			spot = mess["approach"]
			most = CleanerJobs.clean_ticks(int(mess["kind"]), mess["grown"])
		if m.state != StaffMember.State.ON_DUTY:
			continue
		if m.at != spot:
			return "cleaner %d works away from its job's spot %s" % [m.id, spot]
		if m.work_left > most:
			return (
				"cleaner %d has %d ticks of work left, more than its job's %d"
				% [m.id, m.work_left, most]
			)
	for id: int in messes:
		var by := int(messes[id]["claimed_by"])
		if by != 0 and holders.get(id, 0) != by:
			return "mess %d is claimed by %d, which is no cleaner on that job" % [id, by]
	return ""


static func _slot_name(m: StaffMember) -> String:
	return "helper" if m.slot == StaffMember.Slot.HELPER else "primary"


## A StaffMember, or a String naming what is wrong with the record.
static func _member(record: Variant, sim: PassengerSim) -> Variant:
	if typeof(record) != TYPE_DICTIONARY:
		return "a member is not a dictionary"
	for key in MEMBER_KEYS:
		if not record.has(key):
			return "a member has no '%s'" % key
	for key in ["job", "work_left", "bag_target", "ramp_shuttle_id"]:
		if not WholeNumber.is_whole(record[key]) or int(record[key]) < 0:
			return "member field '%s' is not a whole number of 0 or more" % key
	if not WholeNumber.is_whole(record["bag_carry"]):
		return "member field 'bag_carry' is not a whole number"
	if not WholeNumber.is_whole(record["ramp_job"]):
		return "member field 'ramp_job' is not a whole number"
	if typeof(record["ramp_flight_id"]) != TYPE_STRING:
		return "member field 'ramp_flight_id' is not a string"
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
	if not StaffMember.BagCarry.values().has(int(record["bag_carry"])):
		return "member %d has an unknown bag_carry" % m.id
	if not StaffMember.RampJob.values().has(int(record["ramp_job"])):
		return "member %d has an unknown ramp_job" % m.id
	m.role = int(record["role"]) as StaffMember.Role
	m.state = int(record["state"]) as StaffMember.State
	m.station = int(record["station"])
	m.slot = int(record["slot"]) as StaffMember.Slot
	m.path_index = int(record["path_index"])
	m.seg_mm = int(record["seg_mm"])
	m.needs_replan = record["needs_replan"]
	m.search_failed = record["search_failed"]
	m.leaving = record["leaving"]
	m.job = int(record["job"])
	m.job_bin = record["job_bin"]
	m.work_left = int(record["work_left"])
	m.bag_carry = int(record["bag_carry"]) as StaffMember.BagCarry
	m.bag_target = int(record["bag_target"])
	m.ramp_job = int(record["ramp_job"]) as StaffMember.RampJob
	m.ramp_shuttle_id = int(record["ramp_shuttle_id"])
	m.ramp_flight_id = record["ramp_flight_id"]
	m.level = int(record["level"])
	if m.level < StaffMember.LEVEL_MIN or m.level > StaffMember.LEVEL_MAX:
		return "member %d level %d is out of range" % [m.id, m.level]
	if typeof(record["display_name"]) != TYPE_STRING:
		return "member %d display_name is not a string" % m.id
	m.display_name = String(record["display_name"]).strip_edges()
	if m.display_name == "":
		return "member %d display_name is empty" % m.id
	if typeof(record["quirks"]) != TYPE_ARRAY:
		return "member %d quirks is not a list" % m.id
	var raw_quirks: Array = record["quirks"]
	if raw_quirks.is_empty() or raw_quirks.size() > 2:
		return "member %d quirks count %d is out of range" % [m.id, raw_quirks.size()]
	var seen_quirks := {}
	for q: Variant in raw_quirks:
		if typeof(q) != TYPE_STRING:
			return "member %d has a malformed quirk" % m.id
		var q_str := String(q)
		if not StaffNames.QUIRKS.has(q_str) or seen_quirks.has(q_str):
			return "member %d has an invalid or duplicate quirk '%s'" % [m.id, q_str]
		seen_quirks[q_str] = true
		m.quirks.append(q_str)
	if not WholeNumber.is_whole(record["energy"]):
		return "member %d energy is not a whole number" % m.id
	m.energy = int(record["energy"])
	if m.energy < StaffMember.ENERGY_MIN or m.energy > StaffMember.ENERGY_MAX:
		return "member %d energy %d is out of range" % [m.id, m.energy]
	if not WholeNumber.is_whole(record["energy_ticks"]) or int(record["energy_ticks"]) < 0:
		return "member %d energy_ticks is not a whole number of 0 or more" % m.id
	m.energy_ticks = int(record["energy_ticks"])
	if not WholeNumber.is_whole(record["break_room"]) or int(record["break_room"]) < 0:
		return "member %d break_room is not a whole number of 0 or more" % m.id
	m.break_room = int(record["break_room"])
	var break_spot: Variant = _cell(record["break_spot"])
	if break_spot == null:
		return "member %d break_spot is malformed" % m.id
	m.break_spot = break_spot
	if m.break_spot != StaffMember.NO_CELL and not sim.grid.in_bounds(m.break_spot):
		return "member %d break_spot is off the grid" % m.id
	# Saves from before the flag existed have none: not backing out.
	if record.has("backing_out"):
		if typeof(record["backing_out"]) != TYPE_BOOL:
			return "member field 'backing_out' is not true or false"
		m.backing_out = record["backing_out"]
	if record.has("patrol_wait"):
		if not WholeNumber.is_whole(record["patrol_wait"]) or int(record["patrol_wait"]) < 0:
			return "member field 'patrol_wait' is not a whole number of 0 or more"
		m.patrol_wait = int(record["patrol_wait"])
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
	if m.role != StaffMember.Role.CLEANER and m.role != StaffMember.Role.RAMP:
		_release_unreachable(m, sim)
	var problem := _place_problem(m)
	if problem == "" and m.role == StaffMember.Role.RAMP:
		problem = _ramp_problem(m)
	elif problem == "" and m.role == StaffMember.Role.CLEANER:
		problem = _cleaner_problem(m, sim)
		if (
			problem == ""
			and (
				m.ramp_job != StaffMember.RampJob.NONE
				or m.ramp_shuttle_id != 0
				or m.ramp_flight_id != ""
			)
		):
			problem = "is no ramp agent but has a ramp job"
	elif problem == "":
		problem = _duty_problem(m, sim)
		if (
			problem == ""
			and (
				m.job != 0
				or m.job_bin
				or m.work_left != 0
				or m.bag_carry != StaffMember.BagCarry.NONE
				or m.bag_target != 0
			)
		):
			problem = "is no cleaner but has a job"
		if (
			problem == ""
			and (
				m.ramp_job != StaffMember.RampJob.NONE
				or m.ramp_shuttle_id != 0
				or m.ramp_flight_id != ""
			)
		):
			problem = "is no ramp agent but has a ramp job"
	if problem == "":
		problem = _energy_break_problem(m, sim)
	if problem != "":
		return "member %d %s" % [m.id, problem]
	return m


## An on-duty member standing on its station's free spot when staff can no
## longer reach that spot from any entrance: it stands idle there, or walks
## out if it was leaving, as StaffSim would release it.
static func _release_unreachable(m: StaffMember, sim: PassengerSim) -> void:
	if m.state != StaffMember.State.ON_DUTY or m.is_moving():
		return
	if StaffPosts.blocked(sim.grid, sim.layout, m.station):
		return
	if StaffPosts.unreachable(sim.grid, sim.layout, m.station, m.slot):
		_stand_down(m)


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
		m.state == StaffMember.State.TO_STATION
		or m.state == StaffMember.State.TO_BREAK
		or m.is_walking_to_exit()
	)
	if (
		m.backing_out
		and (not walking or m.in_pool() or m.path_index != 0 or m.path.size() < 2 or m.seg_mm <= 0)
	):
		return "is backing out but not partway through the first step of a walk"
	if m.in_pool():
		if not m.path.is_empty() or m.path_index != 0 or m.seg_mm != 0 or m.needs_replan:
			return "is in the pool but has a walk"
		if m.role == StaffMember.Role.RAMP:
			return ""
		if m.state == StaffMember.State.IDLE or m.state == StaffMember.State.OFF_SHIFT:
			return ""
		return "is in the pool but not idle or off shift"
	if m.path_index < 0 or m.path_index >= m.path.size() or m.path[m.path_index] != m.at:
		return "does not stand on its path"
	var length := 0
	if m.is_moving():
		length = Passenger.segment_mm(m.at, m.path[m.path_index + 1])
	if m.seg_mm < 0 or (m.seg_mm > 0 and m.seg_mm >= length):
		return "is further along its step than the step is long"
	return ""


static func _ramp_problem(m: StaffMember) -> String:
	if (
		not m.in_pool()
		or m.station != 0
		or m.slot != StaffMember.Slot.PRIMARY
		or m.search_failed
		or m.backing_out
	):
		return "is a ramp agent with indoor position or station state"
	if (
		m.job != 0
		or m.job_bin
		or m.work_left != 0
		or m.bag_carry != StaffMember.BagCarry.NONE
		or m.bag_target != 0
	):
		return "is a ramp agent with a cleaner job"
	match m.ramp_job:
		StaffMember.RampJob.NONE:
			if m.state != StaffMember.State.IDLE or m.leaving:
				return "is an idle ramp agent with wrong state or leaving"
			if m.ramp_shuttle_id != 0 or m.ramp_flight_id != "":
				return "is an idle ramp agent with a job id"
		StaffMember.RampJob.SHUTTLE:
			if (
				m.state != StaffMember.State.ON_DUTY
				or m.ramp_shuttle_id < 1
				or m.ramp_flight_id != ""
			):
				return "has an invalid shuttle assignment"
		StaffMember.RampJob.PUSHBACK:
			if (
				m.state != StaffMember.State.ON_DUTY
				or m.ramp_shuttle_id != 0
				or m.ramp_flight_id == ""
			):
				return "has an invalid pushback assignment"
		StaffMember.RampJob.MARSHAL:
			if (
				m.state != StaffMember.State.ON_DUTY
				or m.leaving
				or m.ramp_shuttle_id != 0
				or m.ramp_flight_id == ""
			):
				return "has an invalid marshal assignment"
	return ""


## Whether a cleaner's state, job and bag-carry fields agree (see the class
## notes; jobs themselves are checked by _jobs_problem()).
static func _cleaner_problem(m: StaffMember, sim: PassengerSim) -> String:
	if m.station != 0 or m.slot != StaffMember.Slot.PRIMARY or m.leaving:
		return "is a cleaner with a station, a helper slot or leaving"
	if m.job == 0 and m.job_bin:
		return "has a bin job with no bin"
	if m.bag_carry == StaffMember.BagCarry.NONE:
		if m.bag_target != 0:
			return "has a bag target without carrying a bag"
	else:
		if m.job != 0 or m.job_bin:
			return "carries a bag while holding a cleaning job"
		if m.bag_target < 1:
			return "carries a bag with no target"
		if m.bag_carry == StaffMember.BagCarry.TO_BIN:
			var rec := sim.grid.get_object(m.bag_target)
			if rec.get("def", &"") != MessSim.BIN_ID:
				return "carries a bag to bin %d which is not on the grid" % m.bag_target
			if MessSim.approach_for(sim.grid, rec["anchor"]) == MessSim.NO_CELL:
				return "carries a bag to bin %d with no approach" % m.bag_target
		elif (
			not sim.layout.entrances.has(m.bag_target)
			or sim.layout.door_cell(sim.grid, m.bag_target) == StaffMember.NO_CELL
		):
			return "carries a bag to unknown entrance %d" % m.bag_target
	match m.state:
		StaffMember.State.IDLE, StaffMember.State.WALKING_OUT, StaffMember.State.LEAVING_SHIFT:
			if m.job != 0 or m.work_left != 0 or m.bag_carry != StaffMember.BagCarry.NONE:
				return "is a cleaner with no job to do but has one"
			if (
				m.state == StaffMember.State.IDLE
				and m.in_pool()
				and (m.is_moving() or m.needs_replan)
			):
				return "is idle in the pool but has a walk"
		StaffMember.State.OFF_SHIFT:
			if (
				m.job != 0
				or m.work_left != 0
				or m.bag_carry != StaffMember.BagCarry.NONE
				or not m.in_pool()
			):
				return "is an off-shift cleaner with a job or indoor position"
		StaffMember.State.TO_STATION:
			var active := (m.job != 0) or (m.bag_carry != StaffMember.BagCarry.NONE)
			if not active or m.work_left != 0:
				return "walks to no job, or has work left before it gets there"
			if m.bag_carry != StaffMember.BagCarry.NONE:
				if m.path.is_empty():
					return "carries a bag without a path"
				var bag_spot := (
					MessSim.approach_for(sim.grid, sim.grid.get_object(m.bag_target)["anchor"])
					if m.bag_carry == StaffMember.BagCarry.TO_BIN
					else sim.layout.door_cell(sim.grid, m.bag_target)
				)
				if not m.needs_replan and (not m.is_moving() or m.path_end() != bag_spot):
					return "carries a bag on a path not leading to %s" % bag_spot
		StaffMember.State.ON_DUTY:
			var active := (m.job != 0) or (m.bag_carry != StaffMember.BagCarry.NONE)
			if not active or m.work_left < 1:
				return "is cleaning with no job or no work left"
			if m.is_moving() or m.needs_replan:
				return "is on duty but walking"
			if m.bag_carry != StaffMember.BagCarry.NONE:
				var spot := (
					MessSim.approach_for(sim.grid, sim.grid.get_object(m.bag_target)["anchor"])
					if m.bag_carry == StaffMember.BagCarry.TO_BIN
					else sim.layout.door_cell(sim.grid, m.bag_target)
				)
				if m.at != spot:
					return "disposes a bag away from its spot %s" % spot
				if m.work_left > CleanerJobs.TOSS_BAG_TICKS:
					return "has %d bag disposal ticks left above max" % m.work_left
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
	if m.is_on_break():
		return ""
	if m.state == StaffMember.State.OFF_SHIFT:
		if m.station != 0 or not m.in_pool() or m.leaving:
			return "is off shift but has a station, indoor position or leaving"
		return ""
	if m.is_walking_to_exit():
		if m.station != 0 or m.leaving:
			return "is walking out but has a station or is leaving"
		return ""
	if not _of_role(m, sim):
		return "works at station %d, which is not one of its role" % m.station
	if m.leaving and m.state != StaffMember.State.ON_DUTY:
		return "is leaving but not on duty"
	if m.state != StaffMember.State.ON_DUTY:
		return ""
	if m.is_moving() or m.needs_replan:
		return "is on duty but walking"
	if not StaffPosts.usable(sim.grid, sim.layout, m.station):
		return "is on duty at station %d, which is not usable" % m.station
	if StaffPosts.blocked(sim.grid, sim.layout, m.station):
		return "is on duty at station %d, whose staff spot is blocked" % m.station
	if m.at != StaffPosts.spot(sim.grid, sim.layout, m.station, m.slot):
		return "is on duty away from its post's staff spot"
	return ""


## Whether the member's station is one of its role: a desk, a scanner, a
## usable counter (ShopCounters.usable()), or a gate desk (GateDesks.is_desk()).
static func _of_role(m: StaffMember, sim: PassengerSim) -> bool:
	match m.role:
		StaffMember.Role.CHECKIN:
			return sim.layout.desks.has(m.station)
		StaffMember.Role.SHOP:
			return ShopCounters.usable(sim.grid, m.station)
		StaffMember.Role.GATE:
			return GateDesks.is_desk(sim.grid, m.station)
	return sim.layout.scanners.has(m.station)


static func _energy_break_problem(m: StaffMember, sim: PassengerSim) -> String:
	if m.state == StaffMember.State.ON_DUTY:
		if m.energy_ticks >= StaffMember.DRAIN_INTERVAL_TICKS:
			return "has on-duty energy_ticks %d at or above drain interval" % m.energy_ticks
	elif m.state == StaffMember.State.ON_BREAK:
		if m.energy_ticks >= StaffMember.RECOVERY_THRESHOLD:
			return "has on-break energy_ticks %d at or above recovery threshold" % m.energy_ticks
	elif m.role == StaffMember.Role.RAMP and m.state == StaffMember.State.IDLE:
		if m.energy_ticks >= StaffMember.RECOVERY_THRESHOLD:
			return "has idle ramp energy_ticks %d at or above recovery threshold" % m.energy_ticks
	elif m.energy_ticks != 0:
		return "has non-zero energy_ticks outside duty or break"
	if not m.is_on_break():
		if m.break_room != 0 or m.break_spot != StaffMember.NO_CELL:
			return "holds break_room or break_spot while not on break"
		return ""
	if (
		m.role == StaffMember.Role.RAMP
		or m.in_pool()
		or m.station != 0
		or m.leaving
		or m.job != 0
		or m.bag_carry != StaffMember.BagCarry.NONE
	):
		return "has invalid role, station, pool or leaving state on break"
	if not StaffBreakRooms.is_ready(sim.grid, m.break_room):
		return "is on break in break_room %d, which is not ready" % m.break_room
	if m.break_spot == StaffMember.NO_CELL or not sim.grid.is_walkable(m.break_spot):
		return "has an unwalkable break_spot"
	if sim.grid.room_at(m.break_spot) != m.break_room:
		return "has a break_spot outside its break_room"
	if m.state == StaffMember.State.TO_BREAK:
		if not m.needs_replan and m.path_end() != m.break_spot:
			return "walks to break but its path does not end at break_spot"
	elif m.at != m.break_spot or m.is_moving() or m.needs_replan:
		return "is on break away from break_spot or still moving"
	return ""


static func _cell(value: Variant) -> Variant:
	if typeof(value) != TYPE_ARRAY or value.size() != 2:
		return null
	if not WholeNumber.is_whole(value[0]) or not WholeNumber.is_whole(value[1]):
		return null
	return Vector2i(int(value[0]), int(value[1]))


static func _adjacent(a: Vector2i, b: Vector2i) -> bool:
	return maxi(absi(a.x - b.x), absi(a.y - b.y)) == 1
