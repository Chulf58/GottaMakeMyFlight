class_name StaffPosts
extends RefCounted
## A station's staff posts, and the station-wide pass that fills them
## (decision security-lane-technical-design-one-station-per-lane-with-int,
## point 5; ruling security-lane-staffing-one-officer-opens-a-lane-and-a-second).
##
## Every desk and scanner has a PRIMARY post: the station is open only while
## a member is on duty there (StaffSim.is_open()). A whole security lane also
## has a HELPER post: an officer on duty there speeds up the lane's repacks
## (SecurityRuntime.rate()). A desk's or basic scanner's primary spot is its
## StaffSpots spot. A lane's arch has no StaffSpots spot; its primary spot
## (beside the X-ray belt) and helper spot (beside the berth) come from the
## lane geometry (SecurityLanes.lane()). Only a recognised lane is a station,
## and recognition already requires both officer spots to be free and open,
## so a lane's spots are never blocked.
##
## THE PASS (run()) is played at the start of each StaffSim.step(), after
## StaffSim has let go of posts that went (station gone or not usable, spot
## blocked or out of reach), so every primary still claimed is valid and
## stays. Then, in order:
## 1. an on-duty helper whose lane has no primary walks to the primary spot;
## 2. each idle member, in id order, takes the nearest vacant primary post of
##    its role (one whose last search failed waits for its beat);
## 3. each primary vacancy still open, in station id order, recalls the
##    nearest helper;
## 4. each idle officer left with no post becomes the helper at the nearest
##    lane that has a primary and no helper.
## Distances are path lengths in whole millimetres; ties go to the lower
## station or member id. A vacancy is only one staff can work: usable, its
## spot not blocked and reachable from an entrance. So a vacancy no entrance
## reaches never recalls a helper, and a helper is only posted where no
## vacancy is left that a member could reach: a helper never leaves a station
## closed.


## The cell a member working `station` in `slot` stands on, or
## BuildObjectDef.NO_CELL: a whole lane's officer spots, else (primary only)
## the StaffSpots spot. A helper has a spot only at a whole lane.
static func spot(
	grid: BuildGrid, layout: TerminalLayout, station: int, slot: StaffMember.Slot
) -> Vector2i:
	var lane := layout.security_lanes.lane(station)
	if not lane.is_empty():
		return lane["helper_spot" if slot == StaffMember.Slot.HELPER else "primary_spot"]
	if slot == StaffMember.Slot.HELPER:
		return BuildObjectDef.NO_CELL
	return StaffSpots.spot_of(grid, station)


## Whether an old save left `station`'s spot blocked (StaffSpots.blocked()).
## Never for a whole lane, whose recognition requires free officer spots.
static func blocked(grid: BuildGrid, layout: TerminalLayout, station: int) -> bool:
	if layout.security_lanes.is_complete(station):
		return false
	return StaffSpots.blocked(grid, station)


## Whether staff cannot walk from any entrance to the `slot` spot of
## `station` (it is not in BuildGrid.staff_reach()). False with no entrance on
## the grid and when there is no such spot.
static func unreachable(
	grid: BuildGrid, layout: TerminalLayout, station: int, slot: StaffMember.Slot
) -> bool:
	var cell := spot(grid, layout, station, slot)
	if cell == BuildObjectDef.NO_CELL:
		return false
	var reach := grid.staff_reach()
	return not reach.is_empty() and not reach.has(cell)


## Whether staff can work `station` in `slot` as the grid stands: it is
## usable, has that spot, and the spot is neither blocked nor out of reach.
static func workable(
	grid: BuildGrid, layout: TerminalLayout, station: int, slot: StaffMember.Slot
) -> bool:
	if not layout.is_usable(station) or spot(grid, layout, station, slot) == BuildObjectDef.NO_CELL:
		return false
	return not blocked(grid, layout, station) and not unreachable(grid, layout, station, slot)


## The first tick on which a helper is on duty at `station`, read from where
## it stands now, or -1 when none will be without a new decision: the
## current tick for one on duty, and for one walking there the tick its
## committed path brings it onto the helper spot. StaffSim steps before the
## passengers, so a helper arriving on a tick already counts for that tick's
## security work. A helper whose path is about to be planned again (an edit
## touched it) or does not end on the spot gives -1.
static func helper_from(staff: StaffSim, station: int) -> int:
	var id := staff.staff_at(station, StaffMember.Slot.HELPER)
	if id == 0:
		return -1
	var m := staff.get_member(id)
	if m.state == StaffMember.State.ON_DUTY:
		return staff.sim.tick
	var spot := staff.spot_of(station, StaffMember.Slot.HELPER)
	if m.state != StaffMember.State.TO_STATION or m.needs_replan or m.path_end() != spot:
		return -1
	var mm := -m.seg_mm
	for i in range(m.path_index, m.path.size() - 1):
		mm += Passenger.segment_mm(m.path[i], m.path[i + 1])
	# Each step walks WALK_MM and carries what is left over to the next cell,
	# so it arrives on the step whose total first reaches the rest of the path.
	return staff.sim.tick + maxi(JourneyForecast.walk_ticks(mm), 1)


## The pass described at the top, on `staff`'s members. It changes posts only
## through StaffSim's own two moves: `post` (member, station, slot, path)
## sends an idle member out, and `repost` (member, station, slot) moves one
## already on the floor.
static func run(staff: StaffSim, post: Callable, repost: Callable) -> void:
	_promote(staff, repost)
	var spare: Array[StaffMember] = []
	for m in _members(staff):
		if m.state != StaffMember.State.IDLE or (m.search_failed and not _on_beat(staff, m)):
			continue
		if not _take_nearest(staff, m, StaffMember.Slot.PRIMARY, post):
			spare.append(m)
	_recall(staff, repost)
	for m in spare:
		var security := m.role == StaffMember.Role.SECURITY
		if security and _take_nearest(staff, m, StaffMember.Slot.HELPER, post):
			continue
		m.search_failed = true


## Whether `slot` at `station` is free for a member to take: a primary post
## nobody holds, or a helper post nobody holds at a lane whose primary post
## is held. Either way staff must be able to work it.
static func is_vacant(staff: StaffSim, station: int, slot: StaffMember.Slot) -> bool:
	if staff.staff_at(station, slot) != 0:
		return false
	if slot == StaffMember.Slot.HELPER and staff.staff_at(station) == 0:
		return false
	return workable(staff.sim.grid, staff.sim.layout, station, slot)


## The grid path from `from` to `to` that staff walk (BuildGrid.find_path()):
## just `from` when the two are one cell, empty when `to` is NO_CELL or there
## is no way.
static func path(grid: BuildGrid, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if to == StaffMember.NO_CELL:
		var none: Array[Vector2i] = []
		return none
	if from == to:
		var here: Array[Vector2i] = [from]
		return here
	return grid.find_path(from, to)


## The path to `to` from where `m` stands, or, for a member in the pool, the
## shortest from any entrance's door cell (the lower entrance id on a tie).
static func _path_in(staff: StaffSim, m: StaffMember, to: Vector2i) -> Array[Vector2i]:
	var grid := staff.sim.grid
	if not m.in_pool():
		return path(grid, m.at, to)
	var best: Array[Vector2i] = []
	var best_mm := 0
	for door in staff.sim.layout.entrances:
		var way := path(grid, staff.sim.layout.door_cell(grid, door), to)
		if way.is_empty():
			continue
		var mm := Passenger.path_mm(way)
		if best.is_empty() or mm < best_mm:
			best = way
			best_mm = mm
	return best


## Every member, in id order.
static func _members(staff: StaffSim) -> Array[StaffMember]:
	var out: Array[StaffMember] = []
	for id in staff.member_ids():
		out.append(staff.get_member(id))
	return out


## Whether this tick is the member's beat (once a simulated second,
## staggered by id), when a member whose last search failed searches again.
static func _on_beat(staff: StaffSim, m: StaffMember) -> bool:
	var beat := PassengerSim.BEAT_TICKS
	return posmod(staff.sim.tick, beat) == posmod(m.id, beat)


## Step 1: on-duty helpers of lanes with a vacant primary post move over.
static func _promote(staff: StaffSim, repost: Callable) -> void:
	for station in staff.stations_of(StaffMember.Role.SECURITY):
		var id := staff.staff_at(station, StaffMember.Slot.HELPER)
		if id == 0 or not is_vacant(staff, station, StaffMember.Slot.PRIMARY):
			continue
		var m := staff.get_member(id)
		if m.state != StaffMember.State.ON_DUTY:
			continue
		if path(staff.sim.grid, m.at, staff.spot_of(station)).is_empty():
			continue
		repost.call(m, station, StaffMember.Slot.PRIMARY)


## Steps 2 and 4: sends idle `m` to the vacant `slot` post of its role with
## the shortest path (from an entrance when it is in the pool). False when
## there is none it can reach.
static func _take_nearest(
	staff: StaffSim, m: StaffMember, slot: StaffMember.Slot, post: Callable
) -> bool:
	var best := 0
	var best_mm := 0
	var best_path: Array[Vector2i] = []
	for station in staff.stations_of(m.role):
		if not is_vacant(staff, station, slot):
			continue
		var way := _path_in(staff, m, staff.spot_of(station, slot))
		if way.is_empty():
			continue
		var mm := Passenger.path_mm(way)
		if best == 0 or mm < best_mm:
			best = station
			best_mm = mm
			best_path = way
	if best == 0:
		return false
	post.call(m, best, slot, best_path)
	return true


## Step 3: each primary vacancy still open recalls the helper with the
## shortest path from where it stands (the lower id on a tie).
static func _recall(staff: StaffSim, repost: Callable) -> void:
	for station in staff.stations_of(StaffMember.Role.SECURITY):
		if not is_vacant(staff, station, StaffMember.Slot.PRIMARY):
			continue
		var target := staff.spot_of(station)
		var best: StaffMember = null
		var best_mm := 0
		for m in _members(staff):
			if not m.is_helper():
				continue
			var way := path(staff.sim.grid, m.at, target)
			if way.is_empty():
				continue
			var mm := Passenger.path_mm(way)
			if best == null or mm < best_mm:
				best = m
				best_mm = mm
		if best != null:
			repost.call(best, station, StaffMember.Slot.PRIMARY)
