class_name StaffSpots
extends RefCounted
## The staff spot: the cell a staff member stands on to work a station, behind
## a check-in desk's counter or beside a security scanner's landside half. It
## is derived from the station's anchor and facing and never stored; cell_of()
## is the one function the grid, StaffSim and StaffCharacters use for it.
##
## An instance is BuildGrid's staff-spot reservation, kept apart from the
## interaction-cell reservation: spot cell -> the stations whose spot it is.
## A layout saved before spots existed may give two stations one spot, so a
## cell keeps every owner, and removing one station leaves the other's spot
## protected. BuildGrid.validate() asks edit_problem() about every edit, so a
## rectangle drag, a belt line and a click meet the same rules; a snapshot
## load does not, so an old save still loads, and blocked() tells StaffSim
## which stations it can never staff.
##
## Reach (decision desk-belts-run-one-row-back-desk-then-the-agent-row-then-the,
## v3): reach() is every cell staff can walk to from an entrance door, by the
## steps StaffSim's paths take (BuildGrid.can_route). BuildGrid refuses an
## edit that takes a spot out of that set (reach_problem()), and unreachable()
## names a station whose spot an old save, or a layout built before its
## entrance, left outside it.

## Per station type, in the object's frame at facing 0: "spot" is where the
## member stands and "beside" the footprint cell it works next to.
const LAYOUT := {
	&"checkin_desk": {"spot": Vector2i(0, -1), "beside": Vector2i(0, 0)},
	&"security_scanner": {"spot": Vector2i(1, 1), "beside": Vector2i(0, 1)},
}
const ENTRANCE := &"entrance_door"
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

## Spot cell -> Array of station ids whose spot it is.
var _owners: Dictionary = {}


static func has_spot(def_id: StringName) -> bool:
	return LAYOUT.has(def_id)


## The spot of a station of `def_id` at `anchor` and `facing`, or
## BuildObjectDef.NO_CELL for an object no staff work at.
static func cell_of(def_id: StringName, anchor: Vector2i, facing: int) -> Vector2i:
	if not LAYOUT.has(def_id):
		return BuildObjectDef.NO_CELL
	return anchor + BuildObjectDef.rotate_offset(LAYOUT[def_id]["spot"], facing)


## The footprint cell the member works next to, or BuildObjectDef.NO_CELL.
static func beside_of(def_id: StringName, anchor: Vector2i, facing: int) -> Vector2i:
	if not LAYOUT.has(def_id):
		return BuildObjectDef.NO_CELL
	return anchor + BuildObjectDef.rotate_offset(LAYOUT[def_id]["beside"], facing)


## The spot of the object `station` on the grid, or BuildObjectDef.NO_CELL.
static func spot_of(grid: BuildGrid, station: int) -> Vector2i:
	var record := grid.get_object(station)
	if record.is_empty():
		return BuildObjectDef.NO_CELL
	return cell_of(StringName(record["def"]), record["anchor"], record["facing"])


## Whether staff can never work `station` as the grid stands: its spot is off
## the floor, under an object, an interaction cell, another station's spot,
## walled off from the station, or has no neighbour a member can step from.
## Only an old save can hold such a station; edits refuse every cause. False
## for an object that is not a station.
static func blocked(grid: BuildGrid, station: int) -> bool:
	var record := grid.get_object(station)
	if record.is_empty() or not has_spot(StringName(record["def"])):
		return false
	var def_id := StringName(record["def"])
	var spot := cell_of(def_id, record["anchor"], record["facing"])
	if not grid.in_bounds(spot) or grid.floor_at(spot) == BuildGrid.FLOOR_NONE:
		return true
	if grid.object_at(spot) != 0:
		return true
	for other in grid.object_ids():
		if grid.interaction_cell(other) == spot:
			return true
		if other != station and spot_of(grid, other) == spot:
			return true
	if _walled(grid, spot, beside_of(def_id, record["anchor"], record["facing"])):
		return true
	return not _routable(grid, spot, {}, [])


## Whether staff cannot walk from any entrance to `station`'s spot (it is not
## in BuildGrid.staff_reach()). False with no entrance on the grid, and for an
## object that is not a station. A blocked spot under an object is unreachable
## too; callers that tell the two apart ask blocked() first.
static func unreachable(grid: BuildGrid, station: int) -> bool:
	var spot := spot_of(grid, station)
	if spot == BuildObjectDef.NO_CELL:
		return false
	var reach := grid.staff_reach()
	return not reach.is_empty() and not reach.has(spot)


## Every cell staff can walk to from an entrance door's cell, as cell -> the
## region it lies in: a flood over BuildGrid.can_route() steps, the links
## StaffSim's A* paths use. Two cells have a way between them exactly when
## their regions are equal; each region is numbered from 1 by the first
## entrance (in object id order) that reaches it. Empty when the grid has no
## entrance. Each reachable cell is visited once and tries its eight
## neighbours.
static func reach(grid: BuildGrid) -> Dictionary:
	var seen := {}
	var region := 0
	for id in grid.object_ids():
		var record := grid.get_object(id)
		if StringName(record["def"]) != ENTRANCE:
			continue
		var door: Vector2i = record["anchor"]
		if not grid.is_walkable(door) or seen.has(door):
			continue
		region += 1
		seen[door] = region
		var queue: Array[Vector2i] = [door]
		var head := 0
		while head < queue.size():
			var cell := queue[head]
			head += 1
			for offset in NEIGHBOURS:
				var next := cell + offset
				if not seen.has(next) and grid.can_route(cell, next):
					seen[next] = region
					queue.append(next)
	return seen


## Registers `station`'s spot (BuildGrid places an object, or loads one).
func add(station: int, cell: Vector2i) -> void:
	if cell == BuildObjectDef.NO_CELL:
		return
	if not _owners.has(cell):
		_owners[cell] = []
	(_owners[cell] as Array).append(station)


## Drops `station`'s claim on its spot; other owners keep theirs.
func remove(station: int, cell: Vector2i) -> void:
	if not _owners.has(cell):
		return
	var owners: Array = _owners[cell]
	owners.erase(station)
	if owners.is_empty():
		_owners.erase(cell)


func has(cell: Vector2i) -> bool:
	return _owners.has(cell)


## A refusal when `edit` would block a staff spot, or null. BuildGrid calls it
## only for an edit its other rules accept.
func edit_problem(grid: BuildGrid, edit: BuildEdit) -> BuildResult:
	match edit.kind:
		BuildEdit.Kind.PLACE_OBJECT:
			return _place_problem(grid, edit.def_id, edit.cell, edit.facing)
		BuildEdit.Kind.REMOVE_FLOOR:
			if has(edit.cell):
				return _refused(edit.cell)
			return _cut_off_problem(grid, {edit.cell: true}, [], BuildObjectDef.NO_CELL)
		BuildEdit.Kind.PLACE_WALL:
			return _wall_problem(grid, edit.cell, edit.side, edit.wall_kind)
	return null


## Whether some spot, a standing station's or one of the `fresh` spots of
## stations being placed, is in `before` (a reach() set): only then can an
## edit cut one off.
func any_reached(before: Dictionary, fresh: Array[Vector2i]) -> bool:
	for spot in _owners:
		if before.has(spot):
			return true
	return fresh.any(func(spot: Vector2i) -> bool: return before.has(spot))


## A refusal when a spot staff reach now (`before`) is not in `after`, the
## reach() of the grid as the edit would leave it, or null. A standing
## station's spot names that station; a `fresh` spot (a station being placed
## whose cell staff reach now) names none. A spot staff cannot reach already
## is left alone.
func reach_problem(before: Dictionary, after: Dictionary, fresh: Array[Vector2i]) -> BuildResult:
	for spot: Vector2i in _owners:
		if before.has(spot) and not after.has(spot):
			return _refused(spot)
	for spot in fresh:
		if before.has(spot) and not after.has(spot):
			return BuildResult.refused(BuildResult.Reason.STAFF_SPOT)
	return null


func _place_problem(
	grid: BuildGrid, def_id: StringName, anchor: Vector2i, facing: int
) -> BuildResult:
	var def := BuildCatalog.get_def(def_id)
	var cells := def.footprint(anchor, facing)
	var blocked_cells := {}
	var taken: Array[Vector2i] = cells.duplicate()
	taken.append(def.interaction_cell(anchor, facing))
	for cell in taken:
		if has(cell):
			return _refused(cell)
	for cell in cells:
		blocked_cells[cell] = true
	var spot := cell_of(def_id, anchor, facing)
	if spot != BuildObjectDef.NO_CELL:
		var problem := _new_spot_problem(grid, def_id, anchor, facing)
		if problem != null:
			return problem
	return _cut_off_problem(grid, blocked_cells, [], spot)


## A refusal when a new station's own spot is unusable, or null.
func _new_spot_problem(
	grid: BuildGrid, def_id: StringName, anchor: Vector2i, facing: int
) -> BuildResult:
	var spot := cell_of(def_id, anchor, facing)
	if not grid.in_bounds(spot) or grid.floor_at(spot) == BuildGrid.FLOOR_NONE:
		return BuildResult.refused(BuildResult.Reason.STAFF_SPOT)
	if grid.object_at(spot) != 0:
		return BuildResult.refused(BuildResult.Reason.STAFF_SPOT, grid.object_at(spot))
	if has(spot):
		return _refused(spot)
	for other in grid.object_ids():
		if grid.interaction_cell(other) == spot:
			return BuildResult.refused(BuildResult.Reason.STAFF_SPOT, other)
	if _walled(grid, spot, beside_of(def_id, anchor, facing)):
		return BuildResult.refused(BuildResult.Reason.STAFF_SPOT)
	return null


## A new plain or glass wall on an open edge (none or a door) may not stand
## between a spot and its station, nor take a spot's last way out.
func _wall_problem(grid: BuildGrid, cell: Vector2i, side: int, kind: int) -> BuildResult:
	var closes := kind == BuildGrid.WallKind.PLAIN or kind == BuildGrid.WallKind.GLASS
	var existing := grid.wall_kind(cell, side)
	if not closes or (existing != BuildGrid.WallKind.NONE and existing != BuildGrid.WallKind.DOOR):
		return null
	var other := cell + BuildGrid.SIDE_STEP[side]
	for pair in [[cell, other], [other, cell]]:
		for station in _owners.get(pair[0], []):
			var record := grid.get_object(station)
			var beside := beside_of(StringName(record["def"]), record["anchor"], record["facing"])
			if beside == pair[1]:
				return BuildResult.refused(BuildResult.Reason.STAFF_SPOT, station)
	return _cut_off_problem(grid, {}, [cell, other], BuildObjectDef.NO_CELL)


## Refuses when a registered spot near the change that has a routable
## neighbour now would have none once `gone` cells are unwalkable and the
## `shut` edge ([a, b], or empty) is closed; `fresh`, a station's new spot,
## must have one. A spot with none already (an old save) is left alone.
func _cut_off_problem(
	grid: BuildGrid, gone: Dictionary, shut: Array, fresh: Vector2i
) -> BuildResult:
	var near: Array[Vector2i] = []
	near.assign(gone.keys())
	near.append_array(shut)
	var checked := {}
	for cell in near:
		for offset in NEIGHBOURS + [Vector2i.ZERO]:
			var spot: Vector2i = cell + offset
			if checked.has(spot) or not has(spot):
				continue
			checked[spot] = true
			if _routable(grid, spot, {}, []) and not _routable(grid, spot, gone, shut):
				return _refused(spot)
	if fresh != BuildObjectDef.NO_CELL and not _routable(grid, fresh, gone, shut):
		return BuildResult.refused(BuildResult.Reason.STAFF_SPOT)
	return null


func _refused(spot: Vector2i) -> BuildResult:
	var owners: Array = _owners.get(spot, [])
	var station: int = owners[0] if not owners.is_empty() else 0
	return BuildResult.refused(BuildResult.Reason.STAFF_SPOT, station)


## Whether a plain or glass wall stands between the spot and its station.
static func _walled(grid: BuildGrid, spot: Vector2i, beside: Vector2i) -> bool:
	var kind := grid.wall_kind(spot, BuildGrid.SIDE_STEP.find(beside - spot))
	return kind == BuildGrid.WallKind.PLAIN or kind == BuildGrid.WallKind.GLASS


## Whether some neighbour of `spot` can be reached by a routing step
## (BuildGrid.can_route) that uses none of the `gone` cells and does not cross
## the `shut` edge. A diagonal step uses both cells beside it.
static func _routable(grid: BuildGrid, spot: Vector2i, gone: Dictionary, shut: Array) -> bool:
	for offset in NEIGHBOURS:
		var next := spot + offset
		if not grid.can_route(spot, next):
			continue
		var cells: Array[Vector2i] = [next]
		var edges := [[spot, next]]
		if offset.x != 0 and offset.y != 0:
			var across := spot + Vector2i(offset.x, 0)
			var down := spot + Vector2i(0, offset.y)
			cells.append_array([across, down])
			edges = [[spot, across], [across, next], [spot, down], [down, next]]
		if cells.any(func(cell: Vector2i) -> bool: return gone.has(cell)):
			continue
		if not shut.is_empty() and edges.any(func(e: Array) -> bool: return _same_edge(e, shut)):
			continue
		return true
	return false


static func _same_edge(a: Array, b: Array) -> bool:
	return (a[0] == b[0] and a[1] == b[1]) or (a[0] == b[1] and a[1] == b[0])
