class_name CleanerJobs
extends RefCounted
## What a cleaner (StaffMember.Role.CLEANER) works on, and how long it takes
## (decision cleaner-staff-and-messes-visits-leave-messes-bins-fill-pooled-
## cleaners-nearest-mess). Cleaners are a pool with no station: an idle cleaner
## takes the nearest job nobody has claimed, a mess (MessSim) or a full bin, by
## the length of the staff path to the cell it works from (its spot: a mess's
## approach cell, the first walkable cell around a bin). StaffSim claims the
## job, walks the cleaner there, puts it on duty for work_ticks() and then
## cleans the mess or empties the bin.
##
## The search is bounded: the unclaimed jobs a cleaner may have a way to (the
## same staff reach region; every job when the grid has no entrance and so no
## regions) are tried nearest first in a straight line (Chebyshev, from where
## it stands or, in the pool, from the nearest entrance door) until
## SEARCH_CANDIDATES of them have a path, and the shortest of those paths
## wins; ties go to a mess before a bin, then to the lower id. A job it has no
## way to never uses up the bound, so one it can reach is always found. A job
## outside the bound can lose to a nearer one by a straight line that is
## longer by path. Nothing is random.

## Ticks of cleaning, by MessSim.Kind (LITTER, SPILL, TOILET). Tuning values: a
## check-in takes PassengerSim.CHECKIN_TICKS (60).
const CLEAN_TICKS: Array[int] = [30, 45, 60]
## Extra ticks for grown litter.
const GROWN_EXTRA_TICKS := 30
## Ticks to empty a full bin.
const EMPTY_TICKS := 40
## How many jobs with a path one search compares.
const SEARCH_CANDIDATES := 6


## How long `m` works at its job once it arrives: by the mess's kind (more for
## grown litter), or EMPTY_TICKS for a bin. 0 with no job.
static func work_ticks(staff: StaffSim, m: StaffMember) -> int:
	if m.job == 0:
		return 0
	if m.job_bin:
		return EMPTY_TICKS
	var mess := staff.sim.messes.get_mess(m.job)
	if mess.is_empty():
		return 0
	return clean_ticks(int(mess["kind"]), mess["grown"])


## Ticks of cleaning a mess of `kind` (MessSim.Kind) takes, grown or not.
static func clean_ticks(kind: int, grown: bool) -> int:
	return CLEAN_TICKS[kind] + (GROWN_EXTRA_TICKS if grown else 0)


## Whether `m`'s job is still there: its mess, or a bin on the grid.
static func exists(staff: StaffSim, m: StaffMember) -> bool:
	if m.job_bin:
		return staff.sim.grid.get_object(m.job).get("def", &"") == MessSim.BIN_ID
	return not staff.sim.messes.get_mess(m.job).is_empty()


## The cell the job is on: the mess's cell or the bin's anchor; NO_CELL with
## no job, or one that is gone.
static func job_cell(staff: StaffSim, m: StaffMember) -> Vector2i:
	if m.job == 0 or not exists(staff, m):
		return StaffMember.NO_CELL
	if m.job_bin:
		return staff.sim.grid.get_object(m.job)["anchor"]
	return staff.sim.messes.get_mess(m.job)["cell"]


## The cell `m` works its job from (spot_of()), or NO_CELL.
static func job_spot(staff: StaffSim, m: StaffMember) -> Vector2i:
	if m.job == 0 or not exists(staff, m):
		return StaffMember.NO_CELL
	return spot_of(staff, m.job, m.job_bin)


## The cell a cleaner works job `id` from: a mess's approach cell, or the
## first walkable cell around bin `id` (MessSim.approach_for()).
static func spot_of(staff: StaffSim, id: int, bin: bool) -> Vector2i:
	if bin:
		var anchor: Vector2i = staff.sim.grid.get_object(id)["anchor"]
		return MessSim.approach_for(staff.sim.grid, anchor)
	return staff.sim.messes.get_mess(id)["approach"]


## The cleaner whose job is emptying `bin`, or 0. A bin's claim is its
## cleaner's job; nothing else holds it.
static func bin_holder(staff: StaffSim, bin: int) -> int:
	for id in staff.member_ids():
		var m := staff.get_member(id)
		if m.job_bin and m.job == bin:
			return id
	return 0


## The job idle `m` takes now: {"job", "bin", "path"} with the path from
## where it stands (from an entrance's door cell in the pool), or {} for none.
static func nearest(staff: StaffSim, m: StaffMember) -> Dictionary:
	var starts := _starts(staff, m)
	if starts.is_empty():
		return {}
	var bin_claims := {}
	for id in staff.member_ids():
		var other := staff.get_member(id)
		if other.job_bin:
			bin_claims[other.job] = id
	var found: Array = []
	var messes := staff.sim.messes
	for id in messes.mess_ids():
		var mess := messes.get_mess(id)
		if int(mess["claimed_by"]) == 0:
			_consider(staff, found, starts, id, false, mess["approach"])
	for bin in messes.full_bins():
		if not bin_claims.has(bin):
			_consider(staff, found, starts, bin, true, spot_of(staff, bin, true))
	found.sort_custom(_before)
	var best := {}
	var best_mm := 0
	var reached := 0
	for entry: Array in found:
		var way := StaffPosts.path_in(staff, m, entry[3])
		if way.is_empty():
			continue
		var mm := Passenger.path_mm(way)
		if best.is_empty() or mm < best_mm:
			best = {"job": entry[2], "bin": entry[1], "path": way}
			best_mm = mm
		reached += 1
		if reached == SEARCH_CANDIDATES:
			break
	return best


## Where a search measures from: the member's cell, or every entrance's door
## cell for one in the pool.
static func _starts(staff: StaffSim, m: StaffMember) -> Array[Vector2i]:
	var starts: Array[Vector2i] = []
	if not m.in_pool():
		starts.append(m.at)
		return starts
	for door in staff.sim.layout.entrances:
		starts.append(staff.sim.layout.door_cell(staff.sim.grid, door))
	return starts


## Adds job `id` worked from `spot` to `found` as [distance, bin, id, spot],
## unless no start shares its staff reach region (no way there).
static func _consider(
	staff: StaffSim,
	found: Array,
	starts: Array[Vector2i],
	id: int,
	bin: bool,
	spot: Vector2i,
) -> void:
	if spot == StaffMember.NO_CELL:
		return
	var reach := staff.sim.grid.staff_reach()
	var distance := -1
	for start in starts:
		if not reach.is_empty() and (not reach.has(start) or reach.get(spot) != reach[start]):
			continue
		var d := maxi(absi(spot.x - start.x), absi(spot.y - start.y))
		if distance < 0 or d < distance:
			distance = d
	if distance >= 0:
		found.append([distance, bin, id, spot])


## Nearer first, then a mess before a bin, then the lower id.
static func _before(a: Array, b: Array) -> bool:
	if a[0] != b[0]:
		return a[0] < b[0]
	if a[1] != b[1]:
		return not a[1]
	return a[2] < b[2]
