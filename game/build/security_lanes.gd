class_name SecurityLanes
extends RefCounted
## Security lanes: the one source of lane geometry, and the recogniser that
## finds whole lanes in a BuildGrid (decision security-lane-technical-design-
## one-station-per-lane-with-int, point 6). Recognition is derived and never
## stored: TerminalLayout makes a new instance on every rebuild.
##
## GEOMETRY CONTRACT. geometry(anchor, facing, mirror) names every cell of a
## lane rooted at an arch placed at `anchor` and `facing`. Placement,
## recognition, routing, staffing and views all read lane cells from it (or
## from lane(), which returns the same dictionary for a recognised lane), and
## never work them out themselves. The lane frame turns with the arch: y runs
## along the lane, +y being the arch's front where the queue comes from (the
## landside), and x runs across it, +x being the side the parts stand on. A
## RIGHT lane has its parts on the arch's +x side at facing 0, a LEFT lane on
## its -x side. At facing 0, RIGHT (A arch, T tray table, X X-ray belt, P
## pickup table, Q queue entry, u unpack, p pickup, e exit, b berth, r return
## route, o primary officer spot, h helper officer spot):
##
##       x: -1  0  1  2
##   y -2:   h  e
##   y -1:   b  p  P
##   y  0:   r  A  X  o
##   y  1:   r  u  T
##   y  2:      Q
##
## Keys: "arch", "tray_table", "xray_belt", "pickup_table" (the part cells);
## "queue_entry" (where the queue's first waiting passenger stands);
## "unpack" (the main service position, the arch's interaction cell, beside
## the tray table); "pickup" (beside the pickup table, the passage exit);
## "exit" (where a cleared passenger steps off the lane); "berth" (the repack
## berth, beside the pickup cell); "return_route" (the cells from the berth
## back to the unpack cell, in walking order, both ends excluded);
## "primary_spot" (beside the X-ray belt) and "helper_spot" (beside the
## berth), where the two officers stand; "passage" ([unpack, arch, pickup],
## equal to BuildGrid.passage_cells() of the arch); "front" (the grid step
## toward the queue), "side" (the grid step toward the parts), "facing",
## "mirror" and "anchor". lane() adds "arch_id" and "parts" (def id -> object
## id, the arch included). Every part is one cell and has the arch's facing.
##
## RECOGNITION. rebuild() takes the arches in id order. For each it builds the
## RIGHT candidate, then the LEFT one, and judges each candidate whole before
## claiming anything: every part present on its cell with the arch's facing,
## no plain or glass wall between a part and the cell it serves, the passage
## open, and every other named cell free floor (no object, no interaction
## cell, no staff spot, no cell an earlier lane claimed) joined by routing
## steps: queue entry to unpack, pickup to berth, berth along the return
## route to unpack, pickup to exit, and each officer spot open to its part
## with a routing step out. The first whole candidate claims its parts and
## all its cells at once, so a part or cell belongs to at most one lane and
## a lower arch id wins. An incomplete arch claims nothing. It is reported
## (status(), candidate()) on the side with more of its parts present, RIGHT
## on a tie; status() names the first missing part in flow order, then
## parts that face different ways, then the first blocked cell in flow
## order. Because a lane's return route runs where a mirrored lane's parts
## would stand, an arch never has a whole lane on both sides.
##
## REMOVAL POLICY. Nothing is remembered between rebuilds. When a part, the
## arch or a cell of a lane's room goes, the next rebuild reports that arch
## incomplete (or drops it with its arch), and the freed parts and cells may
## go to another arch in the same rebuild. A lane counts as the same lane
## only while its arch, mirror and part objects are unchanged: broken()
## names every arch whose lane was whole before an edit and is gone or
## different after it. The security runtime then stops admissions, releases
## every reservation and returns uncleared passengers to security selection
## without clearance.

enum Status {
	COMPLETE,
	NO_TRAY_TABLE,
	NO_XRAY_BELT,
	NO_PICKUP_TABLE,
	PARTS_FACING,
	WALL_IN_LANE,
	NO_PASSAGE,
	NO_QUEUE_ROOM,
	NO_BERTH_ROOM,
	NO_RETURN_ROOM,
	NO_EXIT_ROOM,
	NO_PRIMARY_SPOT,
	NO_HELPER_SPOT,
	NO_ARCH,
}

const ARCH := &"security_arch"
const TRAY_TABLE := &"tray_table"
const XRAY_BELT := &"xray_belt"
const PICKUP_TABLE := &"pickup_table"
## The parts in flow order.
const PART_IDS: Array[StringName] = [TRAY_TABLE, XRAY_BELT, ARCH, PICKUP_TABLE]
const RIGHT := 1
const LEFT := -1
## The order candidates are tried in: the fixed mirror preference.
const MIRRORS: Array[int] = [RIGHT, LEFT]
## Lane-frame cells at mirror RIGHT (see the contract above).
const FRAME := {
	"arch": Vector2i(0, 0),
	"tray_table": Vector2i(1, 1),
	"xray_belt": Vector2i(1, 0),
	"pickup_table": Vector2i(1, -1),
	"queue_entry": Vector2i(0, 2),
	"unpack": Vector2i(0, 1),
	"pickup": Vector2i(0, -1),
	"exit": Vector2i(0, -2),
	"berth": Vector2i(-1, -1),
	"primary_spot": Vector2i(2, 0),
	"helper_spot": Vector2i(-1, -2),
}
const RETURN_FRAME: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(-1, 1)]
## The parts other than the arch, in flow order, with the status naming each
## missing and the walk cell each serves.
const SIDE_PARTS := [
	[TRAY_TABLE, Status.NO_TRAY_TABLE, "unpack"],
	[XRAY_BELT, Status.NO_XRAY_BELT, "arch"],
	[PICKUP_TABLE, Status.NO_PICKUP_TABLE, "pickup"],
]
## What the lane-incomplete hint says for each status.
const STATUS_TEXT := {
	Status.COMPLETE: "Lane ready",
	Status.NO_TRAY_TABLE: "Needs a tray table",
	Status.NO_XRAY_BELT: "Needs an X-ray belt",
	Status.NO_PICKUP_TABLE: "Needs a pickup table",
	Status.PARTS_FACING: "Parts face different ways",
	Status.WALL_IN_LANE: "A wall cuts through the lane",
	Status.NO_PASSAGE: "Clear the way through the arch",
	Status.NO_QUEUE_ROOM: "Clear the floor for the queue",
	Status.NO_BERTH_ROOM: "Clear the floor for the repack spot",
	Status.NO_RETURN_ROOM: "Clear the way back from the repack spot",
	Status.NO_EXIT_ROOM: "Clear the way out past the pickup table",
	Status.NO_PRIMARY_SPOT: "Clear the officer's spot by the X-ray belt",
	Status.NO_HELPER_SPOT: "Clear the helper's spot by the repack spot",
	Status.NO_ARCH: "No arch",
}
const NEIGHBOURS: Array[Vector2i] = [
	Vector2i(0, -1),
	Vector2i(1, -1),
	Vector2i(1, 0),
	Vector2i(1, 1),
	Vector2i(0, 1),
	Vector2i(-1, 1),
	Vector2i(-1, 0),
	Vector2i(-1, -1),
]

## The security lane feature flag, off in the game: a whole lane cannot be
## staffed until the lane staffing item (Security 5/8) lands, and RepairPlan
## would count it as a working security leg. While it is off, BuildMode will
## not pick or use a lane part tool, BuildMenu shows no Lane tray, and
## BuildGrid.from_snapshot() refuses a snapshot holding a lane part, so no
## lane can be built or loaded. Tests turn it on and back off.
static var enabled := false

## Every arch on the grid, in id order.
var arches: Array[int] = []
## Arch id -> the lane() dictionary of its whole lane.
var _lanes := {}
## Arch id -> the candidate it is reported on (its lane when whole).
var _candidates := {}
## Arch id -> Status.
var _status := {}
## Part object id -> the arch whose lane owns it.
var _piece_owner := {}
## Cell -> the arch whose lane claimed it.
var _cell_owner := {}


## The named cells of a lane rooted at an arch at `anchor` and `facing`, on
## the `mirror` side (RIGHT or LEFT). See the contract at the top.
static func geometry(anchor: Vector2i, facing: int, mirror: int) -> Dictionary:
	var lane := {
		"anchor": anchor,
		"facing": facing,
		"mirror": mirror,
		"front": BuildObjectDef.rotate_offset(Vector2i(0, 1), facing),
		"side": BuildObjectDef.rotate_offset(Vector2i(mirror, 0), facing),
	}
	for key in FRAME:
		lane[key] = _cell(anchor, facing, mirror, FRAME[key])
	var route: Array[Vector2i] = []
	for offset in RETURN_FRAME:
		route.append(_cell(anchor, facing, mirror, offset))
	lane["return_route"] = route
	var passage: Array[Vector2i] = [lane["unpack"], lane["arch"], lane["pickup"]]
	lane["passage"] = passage
	return lane


## Whether `def_id` is one of the four lane parts.
static func is_part(def_id: StringName) -> bool:
	return PART_IDS.has(def_id)


## Every cell a lane names: its four part cells, its walk and officer cells
## and its return route.
static func lane_cells(lane: Dictionary) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for key in FRAME:
		cells.append(lane[key])
	cells.append_array(lane["return_route"])
	return cells


## The floor cells a lane keeps for its own walking and its officers, where
## no other station's queue may wait: pickup, exit, berth, the return route
## and both officer spots. Its queue entry and unpack cell are its own queue.
static func kept_clear_cells(lane: Dictionary) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [
		lane["pickup"], lane["exit"], lane["berth"], lane["primary_spot"], lane["helper_spot"]
	]
	cells.append_array(lane["return_route"])
	return cells


## The removal policy: the arches whose lane is whole in `before` and either
## not whole in `after` or whole with another mirror or other part objects.
## `before` may be null (nothing was recognised yet).
static func broken(before: SecurityLanes, after: SecurityLanes) -> Array[int]:
	var out: Array[int] = []
	if before == null:
		return out
	for arch in before.complete_arches():
		var was := before.lane(arch)
		var now := after.lane(arch)
		if now.is_empty() or now["mirror"] != was["mirror"] or now["parts"] != was["parts"]:
			out.append(arch)
	return out


static func _cell(anchor: Vector2i, facing: int, mirror: int, offset: Vector2i) -> Vector2i:
	return anchor + BuildObjectDef.rotate_offset(Vector2i(offset.x * mirror, offset.y), facing)


func rebuild(grid: BuildGrid) -> void:
	arches.clear()
	_lanes.clear()
	_candidates.clear()
	_status.clear()
	_piece_owner.clear()
	_cell_owner.clear()
	var ids := grid.object_ids()
	ids.sort()
	var others := {}
	for id in ids:
		for cell in [grid.interaction_cell(id), StaffSpots.spot_of(grid, id)]:
			if cell != BuildObjectDef.NO_CELL:
				others[cell] = true
		if StringName(grid.get_object(id)["def"]) == ARCH:
			arches.append(id)
	for arch in arches:
		var best := {}
		for mirror in MIRRORS:
			var candidate := _evaluate(grid, arch, mirror, others)
			if candidate["status"] == Status.COMPLETE:
				_claim(candidate["lane"])
				best = candidate
				break
			if best.is_empty() or candidate["present"] > best["present"]:
				best = candidate
		_candidates[arch] = best["lane"]
		_status[arch] = best["status"]


func is_complete(arch: int) -> bool:
	return _lanes.has(arch)


## The whole lane of `arch` (geometry() plus "arch_id" and "parts"), or an
## empty dictionary when the arch is not a whole lane.
func lane(arch: int) -> Dictionary:
	return _lanes.get(arch, {})


## The candidate `arch` is reported on, whole or not: geometry() plus
## "arch_id" and "parts" (the parts found on it). Empty for no arch.
func candidate(arch: int) -> Dictionary:
	return _candidates.get(arch, {})


## The arches with a whole lane, in id order.
func complete_arches() -> Array[int]:
	var out: Array[int] = []
	for arch in arches:
		if _lanes.has(arch):
			out.append(arch)
	return out


## COMPLETE, what an incomplete arch lacks first, or NO_ARCH for an id that
## is not an arch.
func status(arch: int) -> int:
	return _status.get(arch, Status.NO_ARCH)


func status_text(arch: int) -> String:
	return STATUS_TEXT[status(arch)]


## The arch whose whole lane owns the part `object_id`, or 0.
func lane_of_piece(object_id: int) -> int:
	return _piece_owner.get(object_id, 0)


## The arch whose whole lane names `cell`, or 0.
func lane_at(cell: Vector2i) -> int:
	return _cell_owner.get(cell, 0)


## {"lane": the candidate, "status": Status, "present": parts found}.
func _evaluate(grid: BuildGrid, arch: int, mirror: int, others: Dictionary) -> Dictionary:
	var record := grid.get_object(arch)
	var lane := geometry(record["anchor"], record["facing"], mirror)
	lane["arch_id"] = arch
	var parts := {ARCH: arch}
	var present := 0
	var missing: int = Status.COMPLETE
	var turned := false
	for entry in SIDE_PARTS:
		var cell: Vector2i = lane[entry[0]]
		var id := grid.object_at(cell)
		var part := grid.get_object(id)
		if (
			id == 0
			or StringName(part["def"]) != entry[0]
			or part["anchor"] != cell
			or _piece_owner.has(id)
		):
			if missing == Status.COMPLETE:
				missing = entry[1]
			continue
		present += 1
		parts[entry[0]] = id
		turned = turned or part["facing"] != record["facing"]
	lane["parts"] = parts
	var found := missing
	if found == Status.COMPLETE:
		found = Status.PARTS_FACING if turned else _room_status(grid, lane, others)
	return {"lane": lane, "status": found, "present": present}


## The first thing wrong with a candidate whose parts are all in place, or
## COMPLETE.
func _room_status(grid: BuildGrid, lane: Dictionary, others: Dictionary) -> int:
	for entry in SIDE_PARTS:
		if _walled(grid, lane[entry[0]], lane[entry[2]]):
			return Status.WALL_IN_LANE
	var pickup: Vector2i = lane["pickup"]
	if grid.passage_cells(lane["arch_id"]) != lane["passage"] or not _free(grid, pickup, others):
		return Status.NO_PASSAGE
	if not _free_step(grid, lane["queue_entry"], lane["unpack"], others):
		return Status.NO_QUEUE_ROOM
	var walk := _repack_walk_status(grid, lane, others)
	if walk != Status.COMPLETE:
		return walk
	if not _officer_spot_open(grid, lane["primary_spot"], lane["xray_belt"], others):
		return Status.NO_PRIMARY_SPOT
	var helper_open := _officer_spot_open(grid, lane["helper_spot"], lane["berth"], others)
	return Status.COMPLETE if helper_open else Status.NO_HELPER_SPOT


## The berth, the return route back to the unpack cell and the exit, in
## walking order: the first one blocked, or COMPLETE.
func _repack_walk_status(grid: BuildGrid, lane: Dictionary, others: Dictionary) -> int:
	var pickup: Vector2i = lane["pickup"]
	var from: Vector2i = lane["berth"]
	if not _free_step(grid, from, pickup, others):
		return Status.NO_BERTH_ROOM
	for cell: Vector2i in lane["return_route"]:
		if not _free_step(grid, cell, from, others):
			return Status.NO_RETURN_ROOM
		from = cell
	if not grid.can_route(from, lane["unpack"]):
		return Status.NO_RETURN_ROOM
	if not _free_step(grid, lane["exit"], pickup, others):
		return Status.NO_EXIT_ROOM
	return Status.COMPLETE


func _claim(lane: Dictionary) -> void:
	var arch: int = lane["arch_id"]
	_lanes[arch] = lane
	for part in lane["parts"]:
		_piece_owner[lane["parts"][part]] = arch
	for cell in lane_cells(lane):
		_cell_owner[cell] = arch


## Free floor no earlier lane claimed: no object, no interaction cell and no
## staff spot.
func _free(grid: BuildGrid, cell: Vector2i, others: Dictionary) -> bool:
	if not grid.in_bounds(cell) or grid.floor_at(cell) == BuildGrid.FLOOR_NONE:
		return false
	return grid.object_at(cell) == 0 and not others.has(cell) and not _cell_owner.has(cell)


## `cell` is free and a routing step joins it to `to`.
func _free_step(grid: BuildGrid, cell: Vector2i, to: Vector2i, others: Dictionary) -> bool:
	return _free(grid, cell, others) and grid.can_route(cell, to)


## An officer spot is free, not walled off from the cell it works beside, and
## has a routing step out.
func _officer_spot_open(
	grid: BuildGrid, spot: Vector2i, beside: Vector2i, others: Dictionary
) -> bool:
	if not _free(grid, spot, others) or _walled(grid, spot, beside):
		return false
	return NEIGHBOURS.any(
		func(offset: Vector2i) -> bool: return grid.can_route(spot, spot + offset)
	)


## Whether a plain or glass wall stands between two side-by-side cells.
static func _walled(grid: BuildGrid, a: Vector2i, b: Vector2i) -> bool:
	var kind := grid.wall_kind(a, BuildGrid.SIDE_STEP.find(b - a))
	return kind == BuildGrid.WallKind.PLAIN or kind == BuildGrid.WallKind.GLASS
