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
## SEARCH_CANDIDATES of them have a path or MAX_PATH_TRIES paths were tried,
## whichever comes first, and the shortest path found wins; ties go to a mess
## before a bin, then to the lower id. A few jobs it has no way to never hide
## a reachable one behind them; more than MAX_PATH_TRIES - 1 nearer
## unreachable jobs can, until some are cleaned (the bounded cost, paid once a
## beat while its searches fail). A job outside the bound can lose to a nearer
## one by a straight line that is longer by path. Nothing is random.

## Ticks of cleaning, by MessSim.Kind (LITTER, SPILL, TOILET). Tuning values: a
## check-in takes PassengerSim.CHECKIN_TICKS (60).
const CLEAN_TICKS: Array[int] = [30, 45, 60]
## Extra ticks for grown litter.
const GROWN_EXTRA_TICKS := 30
## Ticks to empty a full bin.
const EMPTY_TICKS := 40
## Ticks to pause between idle corridor/bin patrol waypoints.
const PATROL_PAUSE_TICKS := 50
const PATROL_MIN_CELLS := 4
const PATROL_MAX_CELLS := 24
## How many jobs with a path one search compares.
const SEARCH_CANDIDATES := 6
## The most paths one search tries, found or not: a cleaner with no way to
## most jobs (no entrance, so no reach regions to filter by) stops here.
const MAX_PATH_TRIES := 12

## How many paths nearest() has tried, for tests and profiling.
static var path_calls := 0


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
	for i in mini(found.size(), MAX_PATH_TRIES):
		var entry: Array = found[i]
		path_calls += 1
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


## Deterministic hash of currently unclaimed messes and unheld full bins so
## idle/patrolling cleaners wake up on the exact tick a new job appears.
static func unclaimed_signature(staff: StaffSim) -> int:
	if staff == null or staff.sim == null:
		return 0
	var bin_claims := {}
	for id in staff.member_ids():
		var other := staff.get_member(id)
		if other.job_bin:
			bin_claims[other.job] = id
	var h := 17
	var any := false
	var messes := staff.sim.messes
	for id in messes.mess_ids():
		var mess := messes.get_mess(id)
		if int(mess["claimed_by"]) == 0:
			h = h * 31 + id
			any = true
	for bin in messes.full_bins():
		if not bin_claims.has(bin):
			h = h * 37 + bin
			any = true
	return h if any else 0


## Picks a deterministic indoor corridor/bin patrol path for idle cleaner `m`,
## or [] when no reachable indoor patrol point exists.
static func patrol_path(staff: StaffSim, m: StaffMember, tick: int) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if staff == null or staff.sim == null or staff.sim.grid == null:
		return empty
	var starts := _starts(staff, m)
	if starts.is_empty():
		return empty
	var grid := staff.sim.grid
	var reach := grid.staff_reach()
	var seen := {}
	var waypoints: Array[Vector2i] = []
	for id in grid.object_ids():
		var rec := grid.get_object(id)
		if StringName(rec.get("def", &"")) == MessSim.BIN_ID:
			var spot := MessSim.approach_for(grid, rec["anchor"])
			if spot != StaffMember.NO_CELL and _reachable_waypoint(grid, reach, starts, spot):
				if not seen.has(spot):
					seen[spot] = true
					waypoints.append(spot)
	if not reach.is_empty():
		for cell: Vector2i in reach:
			if (cell.x % 4 != 0 or cell.y % 4 != 0) or seen.has(cell):
				continue
			if not grid.is_indoor(cell) or not grid.is_walkable(cell):
				continue
			if grid.object_at(cell) != 0:
				continue
			if _within_patrol_band(starts, cell, PATROL_MIN_CELLS, PATROL_MAX_CELLS):
				seen[cell] = true
				waypoints.append(cell)
	elif not m.in_pool():
		var x0 := maxi(0, m.at.x - PATROL_MAX_CELLS)
		var x1 := mini(grid.size.x - 1, m.at.x + PATROL_MAX_CELLS)
		var y0 := maxi(0, m.at.y - PATROL_MAX_CELLS)
		var y1 := mini(grid.size.y - 1, m.at.y + PATROL_MAX_CELLS)
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				if x % 4 != 0 or y % 4 != 0:
					continue
				var cell := Vector2i(x, y)
				if seen.has(cell) or not grid.is_indoor(cell) or not grid.is_walkable(cell):
					continue
				if grid.object_at(cell) != 0:
					continue
				if _within_patrol_band(starts, cell, PATROL_MIN_CELLS, PATROL_MAX_CELLS):
					seen[cell] = true
					waypoints.append(cell)
	if waypoints.is_empty():
		return empty
	waypoints.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y if a.y != b.y else a.x < b.x
	)
	var base_idx := posmod(tick + m.id * 37 + m.at.x * 13 + m.at.y * 29, waypoints.size())
	var tries := mini(4, waypoints.size())
	for step in tries:
		var target := waypoints[(base_idx + step) % waypoints.size()]
		if not m.in_pool() and target == m.at:
			continue
		var way := StaffPosts.path_in(staff, m, target)
		if way.size() >= 2:
			return way
	return empty


static func _reachable_waypoint(
	grid: BuildGrid, reach: Dictionary, starts: Array[Vector2i], cell: Vector2i
) -> bool:
	if not grid.is_indoor(cell) or not grid.is_walkable(cell):
		return false
	if reach.is_empty():
		return true
	for start in starts:
		if reach.has(start) and reach.get(cell) == reach[start]:
			return true
	return false


static func _within_patrol_band(
	starts: Array[Vector2i], cell: Vector2i, min_d: int, max_d: int
) -> bool:
	for start in starts:
		var d := maxi(absi(cell.x - start.x), absi(cell.y - start.y))
		if d >= min_d and d <= max_d:
			return true
	return false
