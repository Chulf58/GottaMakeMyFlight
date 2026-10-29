# gdlint:disable = max-public-methods
# BuildGrid is the one grid data API; its accessors outgrew the 20-method cap
# when wall kinds were added (wall_kind).
class_name BuildGrid
extends RefCounted
## The indoor build grid: 1 m cells in packed arrays, the source of truth for
## floors, walls and placed objects. Nodes only draw it. Cell (x, y) covers
## world x in [origin.x + x, +1) and world z in [origin.z + y, +1), with its
## floor at world y origin.y. The origin is set at creation; by default the
## grid is centred on the world origin at height 0. North is -y (world -z).
##
## Every change goes through validate() and apply() with a BuildEdit, so the
## preview, the click and a snapshot load share one set of rules. apply()
## then relinks the A* graph around the changed cells only (once for a whole
## list of edits, see apply_batch()).
##
## Each floor cell, wall edge and object keeps the purchase price it was
## placed with (BuildEdit.paid), so a removal refunds a share of what was
## actually paid (BuildTransaction). The grid itself never touches money.

## After an accepted edit: the cells GridPathing relinked, so every committed
## path through one of them may be stale. After a snapshot load: every cell.
signal graph_changed(cells: Array[Vector2i])
## After apply() or apply_batch() changed the grid data for one edit, before
## the graph is relinked (at once for apply(), at the end for a batch).
signal edit_applied(edit: BuildEdit, result: BuildResult)
## After apply() or apply_batch() refused an edit, and from callers whose own
## rules refuse an edit before it reaches the grid (AreaDrag, BuildMode), so a
## refusal is visible without parsing the UI.
signal edit_refused(edit: BuildEdit, result: BuildResult)

enum Side { NORTH, EAST, SOUTH, WEST }
## What stands on a cell edge. The value is stored in the wall arrays as is,
## so a snapshot from before kinds (only 0 and 1) loads every wall as plain.
## Plain and glass walls block passengers; a door lets them through.
enum WallKind { NONE, PLAIN, GLASS, DOOR }

const DEFAULT_SIZE := Vector2i(64, 64)
const MAX_SIDE_CELLS := 256
const FLOOR_NONE := 0
const FLOOR_TILE := 1
const MAX_FLOOR_TYPE := 1
const MAX_ZONE_ID := 2147483647
## Furthest a snapshot's origin may be from the world origin on any axis, in
## metres. Well past the airfield, and still centimetre-exact in a float.
const MAX_ORIGIN_M := 10000.0
const MAX_WALL_KIND := WallKind.DOOR
## Grid step for each Side.
const SIDE_STEP: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)
]
const SNAPSHOT_KEYS := [
	"width", "height", "floor", "zone", "h_walls", "v_walls", "objects", "next_object_id"
]
const OBJECT_KEYS := ["id", "def", "anchor", "facing"]
## Each entry of the optional "rooms" snapshot key. "rect" is [x, y, w, h].
const ROOM_KEYS := ["id", "type", "rect"]
## The optional snapshot keys holding the purchase price saved on each floor
## cell and wall edge, laid out like "floor", "h_walls" and "v_walls". They
## come together; a snapshot saved before prices has none and loads with
## nothing paid. Each object entry may carry its own "paid".
const PAID_KEYS := ["floor_paid", "h_walls_paid", "v_walls_paid"]
## Highest purchase price a piece can carry (the int32 the arrays hold).
const MAX_PAID := 2147483647

var size := Vector2i.ZERO
## World position of the north-west corner of cell (0, 0).
var origin := Vector3.ZERO
## When false, validate() skips staff_reach_problem(). Only RepairPlan's search
## copy turns it off: it checks reach on its finished plan instead.
var check_staff_reach := true
## While set, every edit the grid accepts is added to it with its inverse,
## read before the edit changes anything (BuildReceipt), and a snapshot load
## marks it replaced. BuildMode sets it for one player action (UndoStack).
var recorder: BuildReceipt = null

var _floor := PackedByteArray()
var _zone := PackedInt32Array()
## The WallKind on the north edge of cell (x, y), at x + y * size.x. Row
## y == size.y holds the south border.
var _h_walls := PackedByteArray()
## The WallKind on the west edge of cell (x, y), at x + y * (size.x + 1).
## Column x == size.x holds the east border.
var _v_walls := PackedByteArray()
## Id of the object standing on each cell, 0 for none.
var _occupant := PackedInt32Array()
## Id of the object whose interaction cell this is, 0 for none.
var _reserved := PackedInt32Array()
## The staff spot of every desk and scanner (StaffSpots), kept apart from
## _reserved. Derived from _objects.
var _spots := StaffSpots.new()
## The security lanes as the grid stands (SecurityLanes), recognised when an
## edit that could block an officer spot is first checked after a change;
## null until then.
var _lanes: SecurityLanes = null
## The cells staff can reach from an entrance (StaffSpots.reach()), worked out
## when first asked after a change; _staff_reach_known goes false on every
## change to the grid data.
var _staff_reach := {}
var _staff_reach_known := false
## The reach the last staff_reach_problem() flood found for its edits, and the
## edit validate() accepted with it: _commit() keeps it as the grid's reach.
var _last_after := {}
var _last_after_known := false
var _handoff_edit: BuildEdit = null
## True inside an apply_batch() whose whole batch keeps reach.
var _reach_cleared := false
## Object id -> {"def": StringName, "anchor": Vector2i, "facing": int}.
var _objects: Dictionary = {}
var _next_object_id := 1
## Room id -> {"type": StringName (a RoomTypes id), "rect": Rect2i}. A room
## marks floor cells as a store type; it never changes walkability.
var _rooms: Dictionary = {}
## Id of the room each cell belongs to, 0 for none. Derived from _rooms.
var _room_at := PackedInt32Array()
var _next_room_id := 1
## The purchase price saved on each floor cell and wall edge (same layout as
## _floor, _h_walls and _v_walls), 0 where nothing was paid. Objects keep
## theirs in their record as "paid".
var _floor_paid := PackedInt32Array()
var _h_paid := PackedInt32Array()
var _v_paid := PackedInt32Array()
var _pathing := GridPathing.new()
## The staff A* graph (GridPathing with `staff` set), built when a staff path
## is first asked for and kept up to date by the same relinks from then on;
## null until then, and after a load or a rebuild.
var _staff_pathing: GridPathing = null
## Signal emissions held back by hold_signals(), in the order they happened.
var _held: Array[Callable] = []
var _hold_depth := 0


## `grid_origin` is the world position of cell (0, 0)'s north-west corner, a
## Vector3; null centres the grid on the world origin at height 0.
func _init(grid_size := DEFAULT_SIZE, grid_origin: Variant = null) -> void:
	_reset(grid_size, centred_origin(grid_size) if grid_origin == null else grid_origin)
	_pathing.rebuild(self)


## The origin that centres a grid of `grid_size` on the world origin at y 0.
static func centred_origin(grid_size: Vector2i) -> Vector3:
	return Vector3(-grid_size.x / 2.0, 0.0, -grid_size.y / 2.0)


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y


func floor_at(cell: Vector2i) -> int:
	return _floor[_index(cell)] if in_bounds(cell) else FLOOR_NONE


func zone_at(cell: Vector2i) -> int:
	return _zone[_index(cell)] if in_bounds(cell) else 0


func has_wall(cell: Vector2i, side: int) -> bool:
	if not in_bounds(cell) or side < 0 or side > 3:
		return false
	return _wall_value(cell, side) != 0


## The WallKind on an edge, NONE when there is no wall or the edge is unknown.
func wall_kind(cell: Vector2i, side: int) -> int:
	if not in_bounds(cell) or side < 0 or side > 3:
		return WallKind.NONE
	return _wall_value(cell, side)


## The purchase price saved on a floor cell, 0 for none.
func floor_paid(cell: Vector2i) -> int:
	return _floor_paid[_index(cell)] if in_bounds(cell) else 0


## The purchase price saved on a wall edge, 0 for none or an unknown edge.
func wall_paid(cell: Vector2i, side: int) -> int:
	if not in_bounds(cell) or side < 0 or side > 3:
		return 0
	if side == Side.NORTH or side == Side.SOUTH:
		return _h_paid[_h_index(cell, side)]
	return _v_paid[_v_index(cell, side)]


## Id of the object standing on `cell`, 0 for none.
func object_at(cell: Vector2i) -> int:
	return _occupant[_index(cell)] if in_bounds(cell) else 0


## A copy of the object record, or an empty dictionary for an unknown id.
func get_object(object_id: int) -> Dictionary:
	return _objects.get(object_id, {}).duplicate()


func object_ids() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(_objects.keys())
	return ids


## Id of the room `cell` belongs to, 0 for none.
func room_at(cell: Vector2i) -> int:
	return _room_at[_index(cell)] if in_bounds(cell) else 0


## A copy of the room record ({"type", "rect"}), or an empty dictionary.
func get_room(room_id: int) -> Dictionary:
	return _rooms.get(room_id, {}).duplicate()


func room_ids() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(_rooms.keys())
	ids.sort()
	return ids


## Where a passenger stands to use the object, or BuildObjectDef.NO_CELL.
func interaction_cell(object_id: int) -> Vector2i:
	if not _objects.has(object_id):
		return BuildObjectDef.NO_CELL
	var record: Dictionary = _objects[object_id]
	return _def_of(object_id).interaction_cell(record["anchor"], record["facing"])


## A cell is walkable when it has floor and no object, or a walk-through one.
func is_walkable(cell: Vector2i) -> bool:
	if not in_bounds(cell) or _floor[_index(cell)] == FLOOR_NONE:
		return false
	var occupant := _occupant[_index(cell)]
	return occupant == 0 or _def_of(occupant).walk_through


## Whether a passenger may step from `from` to the neighbouring cell `to`.
## A diagonal step needs both orthogonal detours open, so it never cuts the
## corner of a wall or an object.
func can_step(from: Vector2i, to: Vector2i) -> bool:
	var step := to - from
	if step == Vector2i.ZERO or absi(step.x) > 1 or absi(step.y) > 1:
		return false
	if not is_walkable(from) or not is_walkable(to):
		return false
	if step.x == 0 or step.y == 0:
		return _straight_step_open(from, to)
	var across := from + Vector2i(step.x, 0)
	var down := from + Vector2i(0, step.y)
	if not is_walkable(across) or not is_walkable(down):
		return false
	return (
		_straight_step_open(from, across)
		and _straight_step_open(across, to)
		and _straight_step_open(from, down)
		and _straight_step_open(down, to)
	)


## A step generic routing may take: can_step() allows it and neither cell is
## a security object, which only its serviced passenger walks through.
func can_route(from: Vector2i, to: Vector2i) -> bool:
	return can_step(from, to) and not _is_security_cell(from) and not _is_security_cell(to)


## A step staff may take: any can_step(), so staff walk through a security
## scanner or arch along its axis like screened airport staff (decision
## staff-may-walk-through-security-scanners-and-lanes-so-shop-s). Passengers
## route by can_route() and never do.
func can_staff_route(from: Vector2i, to: Vector2i) -> bool:
	return can_step(from, to)


func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	return _pathing.find_path(self, from, to)


## The path staff walk from `from` to `to` over can_staff_route() steps, both
## cells included, or empty when there is none.
func find_staff_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if _staff_pathing == null:
		_staff_pathing = GridPathing.new(true)
		_staff_pathing.rebuild(self)
	return _staff_pathing.find_path(self, from, to)


## The cells a passenger walks to pass through a walk-through object: its
## interaction cell, the footprint along the object's axis and the cell beyond.
## Empty when the object is unknown or not walk-through, or a step is closed.
func passage_cells(object_id: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if not _objects.has(object_id) or not _def_of(object_id).walk_through:
		return cells
	var record: Dictionary = _objects[object_id]
	var def := _def_of(object_id)
	var entry := def.interaction_cell(record["anchor"], record["facing"])
	if entry == BuildObjectDef.NO_CELL:
		return cells
	var back := BuildObjectDef.rotate_offset(Vector2i(0, -1), record["facing"])
	cells.append(entry)
	for i in def.size.y + 1:
		var next := cells[cells.size() - 1] + back
		if not can_step(cells[cells.size() - 1], next):
			cells.clear()
			return cells
		cells.append(next)
	return cells


## Checks an edit without changing anything. An edit the other rules accept
## is then checked against the staff spots (StaffSpots.edit_problem()), then
## against the officer spots of whole security lanes
## (SecurityLanes.officer_spot_problem()), then,
## unless `check_reach` is false, against staff reach (staff_reach_problem());
## a snapshot load skips all three, so an old save still loads. BeltShaper passes
## false per cell and checks a whole line's reach at once.
func validate(edit: BuildEdit, check_reach := true) -> BuildResult:
	_handoff_edit = null
	var result: BuildResult
	match edit.kind:
		BuildEdit.Kind.PAINT_FLOOR:
			result = _check_paint_floor(edit)
		BuildEdit.Kind.REMOVE_FLOOR:
			result = _check_remove_floor(edit.cell)
		BuildEdit.Kind.PLACE_WALL:
			result = _check_place_wall(edit.cell, edit.side, edit.wall_kind)
		BuildEdit.Kind.REMOVE_WALL:
			result = _check_remove_wall(edit.cell, edit.side)
		BuildEdit.Kind.PLACE_OBJECT:
			if _restored_id_taken(edit.object_id, _objects, _next_object_id):
				result = BuildResult.refused(BuildResult.Reason.OVERLAP, edit.object_id)
			else:
				result = _check_place_object(edit.def_id, edit.cell, edit.facing)
		BuildEdit.Kind.REMOVE_OBJECT:
			if _objects.has(edit.object_id):
				result = BuildResult.accepted()
			else:
				result = BuildResult.refused(BuildResult.Reason.NO_OBJECT)
		BuildEdit.Kind.PLACE_ROOM:
			if _restored_id_taken(edit.room_id, _rooms, _next_room_id):
				result = BuildResult.refused(BuildResult.Reason.ROOM_OVERLAP)
			else:
				result = _check_place_room(Rect2i(edit.cell, edit.room_size), edit.room_type)
		BuildEdit.Kind.REMOVE_ROOM:
			if _rooms.has(edit.room_id):
				result = BuildResult.accepted()
			else:
				result = BuildResult.refused(BuildResult.Reason.NO_ROOM)
		BuildEdit.Kind.RESHAPE_BELT:
			result = _check_reshape_belt(edit)
	if result.ok:
		var spot_problem := _spots.edit_problem(self, edit)
		if spot_problem == null:
			spot_problem = _officer_spot_problem(edit)
		if spot_problem == null and check_reach:
			spot_problem = staff_reach_problem([edit] as Array[BuildEdit])
			if spot_problem == null and _last_after_known:
				# Once this edit is committed its trial reach is the grid's.
				_handoff_edit = edit
		if spot_problem != null:
			result = spot_problem
	return result


## Whether a placement that brings an object or room back under its own id
## (`id` above 0, an undo) cannot have it: the id is in use or was never
## handed out. A placement with id 0 gets a fresh one.
static func _restored_id_taken(id: int, records: Dictionary, next_id: int) -> bool:
	return id != 0 and (id < 0 or id >= next_id or records.has(id))


## SecurityLanes.officer_spot_problem() for an edit that places an object or
## a wall or removes floor, on the lanes recognised as the grid stands.
func _officer_spot_problem(edit: BuildEdit) -> BuildResult:
	var kinds := [
		BuildEdit.Kind.PLACE_OBJECT, BuildEdit.Kind.PLACE_WALL, BuildEdit.Kind.REMOVE_FLOOR
	]
	if not kinds.has(edit.kind):
		return null
	return _recognised_lanes().officer_spot_problem(self, edit)


## The security lanes as the grid stands, recognised on first use after a
## change.
func _recognised_lanes() -> SecurityLanes:
	if _lanes == null:
		_lanes = SecurityLanes.new()
		_lanes.rebuild(self)
	return _lanes


## The cells staff can reach from an entrance door (StaffSpots.reach()), as
## cell -> its region (equal regions have a way between them); empty with no
## entrance. Kept until the grid next changes, so
## asking again is free. Read it, never change it.
func staff_reach() -> Dictionary:
	if not _staff_reach_known:
		_staff_reach = StaffSpots.reach(self)
		_staff_reach_known = true
	return _staff_reach


## STAFF_SPOT when applying `edits` together would cut a staff spot staff can
## reach now off from every entrance: a standing station's (naming it), an
## officer spot of a whole security lane as the grid stands (naming its arch),
## or a spot the edits bring, when staff reach its cell now: a placed
## station's, or an officer spot of a lane a placed part completes (naming
## its arch when the arch already stands). Null
## otherwise, always with no entrance on the grid, and with check_staff_reach
## off or inside an apply_batch() whose whole batch passed. Each edit must
## already be accepted on the grid as it stands, and no two may touch the same
## cell: validate() passes one edit, BeltShaper a belt line's placements. Only
## removing floor, placing a wall, placing an object or removing an entrance
## can take cells away (removing the last entrance takes them all); those are
## tried on the grid data, the reach worked out (one flood fill), and the data
## put back. The cost is that flood, and only when some spot is reached now.
func staff_reach_problem(edits: Array[BuildEdit]) -> BuildResult:
	_last_after_known = false
	if not check_staff_reach or _reach_cleared:
		return null
	var fresh: Array[Vector2i] = []
	var narrows := false
	var parts := false
	for edit in edits:
		match edit.kind:
			BuildEdit.Kind.PLACE_OBJECT:
				narrows = true
				parts = parts or SecurityLanes.is_part(edit.def_id)
				var spot := StaffSpots.cell_of(edit.def_id, edit.cell, edit.facing)
				if spot != BuildObjectDef.NO_CELL:
					fresh.append(spot)
			BuildEdit.Kind.REMOVE_FLOOR, BuildEdit.Kind.PLACE_WALL:
				narrows = true
			BuildEdit.Kind.REMOVE_OBJECT:
				narrows = narrows or _is_entrance(edit.object_id)
	if not narrows:
		return null
	var before := staff_reach()
	if before.is_empty() or not (parts or _any_spot_reached(before, fresh)):
		return null
	var lane_spots := {}
	_last_after = _reach_after(edits, lane_spots)
	_last_after_known = true
	return _reach_problem(before, _last_after, fresh, lane_spots)


## Whether applying all of `edits` leaves every staff spot staff reach now
## (and every spot an edit places whose cell they reach now) still reached,
## judged with one flood: then no edit in the batch can break the reach rule,
## since the batch only takes cells away and each step leaves at least what
## the whole batch leaves. False, so each edit is checked on its own, when
## the batch places or removes an entrance, or places an object the grid
## refuses as it stands or on a cell an earlier placement in it takes. Edits
## that only add cells (floor, wall removals, rooms, belt reshapes) are left
## out of the trial; a spot that only they bring into reach is judged with the
## batch as one action.
func _batch_keeps_reach(edits: Array[BuildEdit]) -> bool:
	var trial: Array[BuildEdit] = []
	var fresh: Array[Vector2i] = []
	var claimed := {}
	var parts := false
	for edit in edits:
		match edit.kind:
			BuildEdit.Kind.REMOVE_FLOOR, BuildEdit.Kind.PLACE_WALL:
				if not in_bounds(edit.cell) or edit.side < 0 or edit.side > 3:
					return false
				trial.append(edit)
			BuildEdit.Kind.REMOVE_OBJECT:
				if _is_entrance(edit.object_id):
					return false
			BuildEdit.Kind.PLACE_OBJECT:
				if not _trial_placement(edit, claimed):
					return false
				trial.append(edit)
				parts = parts or SecurityLanes.is_part(edit.def_id)
				var spot := StaffSpots.cell_of(edit.def_id, edit.cell, edit.facing)
				if spot != BuildObjectDef.NO_CELL:
					fresh.append(spot)
	if trial.is_empty():
		return true
	var before := staff_reach()
	if before.is_empty() or not (parts or _any_spot_reached(before, fresh)):
		return true
	var lane_spots := {}
	var after := _reach_after(trial, lane_spots)
	return _reach_problem(before, after, fresh, lane_spots) == null


## Whether staff reach (`before`) some staff spot now: a station's, a whole
## lane's officer spot, or one of the `fresh` spots of stations being placed.
func _any_spot_reached(before: Dictionary, fresh: Array[Vector2i]) -> bool:
	return _spots.any_reached(before, fresh) or _recognised_lanes().any_reached(before)


## The staff reach rule on a station's spot (StaffSpots.reach_problem()), on
## a whole lane's officer spots (SecurityLanes.reach_problem()), then on the
## officer spots of lanes the edits complete (`lane_spots`, spot -> arch, from
## _reach_after()): one staff reach now that `after` loses is refused, naming
## the arch when it already stands, as a placed station's spot names none.
func _reach_problem(
	before: Dictionary, after: Dictionary, fresh: Array[Vector2i], lane_spots: Dictionary
) -> BuildResult:
	var problem := _spots.reach_problem(before, after, fresh)
	if problem == null:
		problem = _recognised_lanes().reach_problem(before, after)
	if problem != null:
		return problem
	for spot: Vector2i in lane_spots:
		if before.has(spot) and not after.has(spot):
			var arch: int = lane_spots[spot]
			return BuildResult.refused(
				BuildResult.Reason.STAFF_SPOT, arch if _objects.has(arch) else 0
			)
	return null


## Whether a placement can join _batch_keeps_reach()'s trial: not an
## entrance, accepted on the grid as it stands, and on cells (footprint and
## interaction cell) no earlier placement in `claimed` takes. Claims its cells.
func _trial_placement(edit: BuildEdit, claimed: Dictionary) -> bool:
	if edit.def_id == StaffSpots.ENTRANCE:
		return false
	if not _check_place_object(edit.def_id, edit.cell, edit.facing).ok:
		return false
	var def := BuildCatalog.get_def(edit.def_id)
	var cells := def.footprint(edit.cell, edit.facing)
	var front := def.interaction_cell(edit.cell, edit.facing)
	if front != BuildObjectDef.NO_CELL:
		cells.append(front)
	if cells.any(func(cell: Vector2i) -> bool: return claimed.has(cell)):
		return false
	for cell in cells:
		claimed[cell] = true
	return true


func _is_entrance(object_id: int) -> bool:
	return _objects.has(object_id) and _objects[object_id]["def"] == StaffSpots.ENTRANCE


## StaffSpots.reach() of the grid as `edits` would leave it. Each edit that can
## take cells away is written into the grid data (an object under an unused
## id), the flood runs, and every write is undone in reverse order, so the
## grid is exactly as it was. Nothing is emitted and the A* graph is untouched.
## When an edit places a lane part, the lanes are recognised on the written
## grid too, and the officer spots of lanes whole there and not as the grid
## stands go into `lane_spots` (spot -> arch).
func _reach_after(edits: Array[BuildEdit], lane_spots: Dictionary) -> Dictionary:
	var standing := _recognised_lanes()
	var parts := false
	var undo := []
	var trial_id := _next_object_id
	for edit in edits:
		match edit.kind:
			BuildEdit.Kind.REMOVE_FLOOR:
				undo.append([edit, _floor[_index(edit.cell)]])
				_floor[_index(edit.cell)] = FLOOR_NONE
			BuildEdit.Kind.PLACE_WALL:
				undo.append([edit, _wall_value(edit.cell, edit.side)])
				_set_wall(edit.cell, edit.side, edit.wall_kind)
			BuildEdit.Kind.PLACE_OBJECT:
				undo.append([edit, trial_id])
				_insert_object(trial_id, edit.def_id, edit.cell, edit.facing)
				trial_id += 1
				parts = parts or SecurityLanes.is_part(edit.def_id)
			BuildEdit.Kind.REMOVE_OBJECT:
				# Only an entrance's removal takes cells away; it has no spot.
				if _is_entrance(edit.object_id):
					undo.append([edit, _objects[edit.object_id]])
					_erase_object(edit.object_id)
	var reach := StaffSpots.reach(self)
	if parts:
		var trial_lanes := SecurityLanes.new()
		trial_lanes.rebuild(self)
		lane_spots.merge(trial_lanes.new_officer_spots(standing))
	for i in range(undo.size() - 1, -1, -1):
		var edit: BuildEdit = undo[i][0]
		match edit.kind:
			BuildEdit.Kind.REMOVE_FLOOR:
				_floor[_index(edit.cell)] = undo[i][1]
			BuildEdit.Kind.PLACE_WALL:
				_set_wall(edit.cell, edit.side, undo[i][1])
			BuildEdit.Kind.PLACE_OBJECT:
				_erase_object(undo[i][1])
			BuildEdit.Kind.REMOVE_OBJECT:
				var record: Dictionary = undo[i][1]
				_insert_object(edit.object_id, record["def"], record["anchor"], record["facing"])
				_objects[edit.object_id] = record
	return reach


## Validates the edit and, if it is accepted, applies it and relinks the A*
## graph around its dirty cells. A refused edit changes nothing, and an edit
## with no dirty cells (a room) relinks and emits nothing.
func apply(edit: BuildEdit) -> BuildResult:
	var result := _commit(edit)
	if result.ok and not result.dirty_cells.is_empty():
		var relinked := _relink_paths(result.dirty_cells)
		_emit_or_hold(func() -> void: graph_changed.emit(relinked))
	return result


## Applies a list of edits in order: each is validated and applied against the
## grid as the earlier ones left it, and a refused edit changes nothing and
## does not stop the rest. The A* graph is then relinked once around the union
## of the cells the accepted edits changed and graph_changed is emitted once
## with the cells relinked; with no accepted edit nothing is relinked or
## emitted. Returns one result per edit, in order. No state outlives the call.
func apply_batch(edits: Array[BuildEdit]) -> Array[BuildResult]:
	var results: Array[BuildResult] = []
	var dirty: Array[Vector2i] = []
	# One flood for the whole batch when it keeps every reached spot reached
	# (_batch_keeps_reach()); otherwise each edit is checked as it comes.
	_reach_cleared = check_staff_reach and _batch_keeps_reach(edits)
	for edit in edits:
		var result := _commit(edit)
		results.append(result)
		if result.ok:
			dirty.append_array(result.dirty_cells)
	_reach_cleared = false
	if not dirty.is_empty():
		var relinked := _relink_paths(dirty)
		_emit_or_hold(func() -> void: graph_changed.emit(relinked))
	return results


## Applies `edits` in order and stops at the first refusal, which it returns;
## the edits before it stay applied. Each edit is first put to `rule` (when
## valid, called as rule(grid, edit) and returning a refusal or null) on the
## grid as the earlier edits left it, then to validate(). Staff reach is judged
## as in apply_batch(), with one flood when the whole list keeps it. The A*
## graph is relinked once and graph_changed emitted once for the applied edits.
## Returns an accepted result with their dirty cells when every edit applied.
## BuildUndo runs it on a copy of the grid first, so a refusal never leaves a
## part of an undo on the live grid.
func apply_sequence(edits: Array[BuildEdit], rule: Callable) -> BuildResult:
	var result := BuildResult.accepted()
	var dirty: Array[Vector2i] = []
	_reach_cleared = check_staff_reach and _batch_keeps_reach(edits)
	for edit in edits:
		var problem: BuildResult = rule.call(self, edit) if rule.is_valid() else null
		if problem != null:
			result = problem
			break
		result = _commit(edit)
		if not result.ok:
			break
		dirty.append_array(result.dirty_cells)
	_reach_cleared = false
	if not dirty.is_empty():
		var relinked := _relink_paths(dirty)
		_emit_or_hold(func() -> void: graph_changed.emit(relinked))
	if not result.ok:
		return result
	var whole := BuildResult.accepted()
	whole.dirty_cells = dirty
	return whole


## Validates the edit and, if it is accepted, changes the grid data and fills
## in the result's dirty cells. Does not relink the A* graph.
func _commit(edit: BuildEdit) -> BuildResult:
	var result := validate(edit)
	if not result.ok:
		_emit_or_hold(func() -> void: edit_refused.emit(edit, result))
		return result
	var inverse := BuildReceipt.inverse_before(self, edit) if recorder != null else null
	match edit.kind:
		BuildEdit.Kind.PAINT_FLOOR:
			_floor[_index(edit.cell)] = edit.floor_type
			_zone[_index(edit.cell)] = edit.zone_id
			_floor_paid[_index(edit.cell)] = edit.paid
			result.dirty_cells = [edit.cell]
		BuildEdit.Kind.REMOVE_FLOOR:
			_floor[_index(edit.cell)] = FLOOR_NONE
			_zone[_index(edit.cell)] = 0
			_floor_paid[_index(edit.cell)] = 0
			result.dirty_cells = [edit.cell]
		BuildEdit.Kind.PLACE_WALL, BuildEdit.Kind.REMOVE_WALL:
			var placing := edit.kind == BuildEdit.Kind.PLACE_WALL
			_set_wall(edit.cell, edit.side, edit.wall_kind if placing else WallKind.NONE)
			_set_wall_paid(edit.cell, edit.side, edit.paid if placing else 0)
			result.dirty_cells = _edge_cells(edit.cell, edit.side)
		BuildEdit.Kind.PLACE_OBJECT:
			# An undo brings a removed object back under its own id.
			result.object_id = edit.object_id
			if edit.object_id == 0:
				result.object_id = _next_object_id
				_next_object_id += 1
			result.dirty_cells = _insert_object(
				result.object_id, edit.def_id, edit.cell, edit.facing, edit.paid
			)
		BuildEdit.Kind.REMOVE_OBJECT:
			result.object_id = edit.object_id
			result.dirty_cells = _erase_object(edit.object_id)
		BuildEdit.Kind.PLACE_ROOM:
			result.room_id = edit.room_id
			if edit.room_id == 0:
				result.room_id = _next_room_id
				_next_room_id += 1
			_insert_room(result.room_id, edit.room_type, Rect2i(edit.cell, edit.room_size))
		BuildEdit.Kind.REMOVE_ROOM:
			result.room_id = edit.room_id
			_erase_room(edit.room_id)
		BuildEdit.Kind.RESHAPE_BELT:
			# Same id, anchor and saved price; every belt piece is one cell.
			result.object_id = object_at(edit.cell)
			var record: Dictionary = _objects[result.object_id]
			record["def"] = edit.def_id
			record["facing"] = edit.facing
			result.dirty_cells = [edit.cell]
	if _handoff_edit == edit:
		_staff_reach = _last_after
	_staff_reach_known = _handoff_edit == edit
	_handoff_edit = null
	_lanes = null
	if recorder != null:
		recorder.record(edit, result, inverse)
	_emit_or_hold(func() -> void: edit_applied.emit(edit, result))
	return result


## Holds back edit_applied, edit_refused and graph_changed from apply() and
## apply_batch() until release_signals(), so a caller can settle money for the
## outcome before any listener runs. The grid data changes at once; only the
## signals wait, in order. Also holds the graph_changed of from_snapshot().
## Holds nest: signals go out at the outermost release. Returns a mark for
## release_signals(): how many signals were already held.
func hold_signals() -> int:
	_hold_depth += 1
	return _held.size()


## Ends one hold. At the outermost release, emits every held signal in the
## order they happened and goes back to emitting at once. With `drop_from` (a
## hold_signals() mark), the signals held since that mark are discarded first,
## for a caller that put the grid back to how it was.
func release_signals(drop_from := -1) -> void:
	if drop_from >= 0 and drop_from < _held.size():
		_held.resize(drop_from)
	_hold_depth -= 1
	if _hold_depth > 0:
		return
	var held := _held
	_held = []
	for emit in held:
		emit.call()


func _emit_or_hold(emit: Callable) -> void:
	if _hold_depth > 0:
		_held.append(emit)
	else:
		emit.call()


func cell_to_world(cell: Vector2i) -> Vector3:
	return origin + Vector3(cell.x + 0.5, 0.0, cell.y + 0.5)


func world_to_cell(world: Vector3) -> Vector2i:
	return Vector2i(floori(world.x - origin.x), floori(world.z - origin.z))


## The edge of the cell under `world` that the point is closest to.
func nearest_side(world: Vector3) -> Side:
	var cell := world_to_cell(world)
	var fx := world.x - origin.x - cell.x
	var fy := world.z - origin.z - cell.y
	var distances := [fy, 1.0 - fx, 1.0 - fy, fx]
	var best := 0
	for side in range(1, 4):
		if distances[side] < distances[best]:
			best = side
	return best as Side


## JSON-safe state for a save. Occupancy, reservations and the A* graph are
## derived, so they are rebuilt on load rather than stored.
func to_snapshot() -> Dictionary:
	var objects := []
	var ids := object_ids()
	ids.sort()
	for object_id in ids:
		var record: Dictionary = _objects[object_id]
		var anchor: Vector2i = record["anchor"]
		var entry := {
			"id": object_id,
			"def": str(record["def"]),
			"anchor": [anchor.x, anchor.y],
			"facing": record["facing"],
			"paid": record["paid"],
		}
		objects.append(entry)
	var rooms := []
	for room_id in room_ids():
		var area: Rect2i = _rooms[room_id]["rect"]
		(
			rooms
			. append(
				{
					"id": room_id,
					"type": str(_rooms[room_id]["type"]),
					"rect": [area.position.x, area.position.y, area.size.x, area.size.y],
				}
			)
		)
	return {
		"width": size.x,
		"height": size.y,
		"floor": Array(_floor),
		"zone": Array(_zone),
		"h_walls": Array(_h_walls),
		"v_walls": Array(_v_walls),
		"objects": objects,
		"next_object_id": _next_object_id,
		"origin": [origin.x, origin.y, origin.z],
		"rooms": rooms,
		"next_room_id": _next_room_id,
		"floor_paid": Array(_floor_paid),
		"h_walls_paid": Array(_h_paid),
		"v_walls_paid": Array(_v_paid),
	}


## Restores a to_snapshot() dictionary, including one that went through JSON
## (which turns ints into floats). The grid takes the snapshot's size and
## origin; one saved before grids had an origin loads centred at height 0, and
## one saved before rooms loads with none, and one saved before purchase
## prices loads with nothing paid (so removing its pieces refunds nothing).
## Loading never spends or credits money.
## Every object is re-placed through the placement rules. Pushes an error and
## returns false, leaving the grid unchanged, when anything is missing,
## malformed or breaks a rule.
func from_snapshot(data: Dictionary) -> bool:
	var problem := BuildGridSnapshot.problem(data)
	var loaded: BuildGrid = null
	if problem == "":
		var loaded_size := Vector2i(int(data["width"]), int(data["height"]))
		var at := centred_origin(loaded_size)
		if data.has("origin"):
			at = Vector3(data["origin"][0], data["origin"][1], data["origin"][2])
		loaded = BuildGrid.new(loaded_size, at)
		problem = loaded._load_cells(data)
	if problem != "":
		push_error("BuildGrid.from_snapshot: %s" % problem)
		return false
	size = loaded.size
	origin = loaded.origin
	_floor = loaded._floor
	_zone = loaded._zone
	_h_walls = loaded._h_walls
	_v_walls = loaded._v_walls
	_occupant = loaded._occupant
	_reserved = loaded._reserved
	_spots = loaded._spots
	_objects = loaded._objects
	_next_object_id = loaded._next_object_id
	_rooms = loaded._rooms
	_room_at = loaded._room_at
	_next_room_id = loaded._next_room_id
	_floor_paid = loaded._floor_paid
	_h_paid = loaded._h_paid
	_v_paid = loaded._v_paid
	_pathing = loaded._pathing
	_staff_pathing = loaded._staff_pathing
	_staff_reach_known = false
	_lanes = null
	if recorder != null:
		recorder.replaced = true
	var every: Array[Vector2i] = []
	for y in size.y:
		for x in size.x:
			every.append(Vector2i(x, y))
	_emit_or_hold(func() -> void: graph_changed.emit(every))
	return true


func _reset(grid_size: Vector2i, grid_origin: Vector3) -> void:
	size = grid_size
	origin = grid_origin
	var cells := size.x * size.y
	_floor = _zeros_bytes(cells)
	_h_walls = _zeros_bytes(size.x * (size.y + 1))
	_v_walls = _zeros_bytes((size.x + 1) * size.y)
	_zone = _zeros_ints(cells)
	_occupant = _zeros_ints(cells)
	_reserved = _zeros_ints(cells)
	_spots = StaffSpots.new()
	_staff_reach_known = false
	_lanes = null
	_objects = {}
	_next_object_id = 1
	_room_at = _zeros_ints(cells)
	_rooms = {}
	_next_room_id = 1
	_floor_paid = _zeros_ints(cells)
	_h_paid = _zeros_ints(size.x * (size.y + 1))
	_v_paid = _zeros_ints((size.x + 1) * size.y)


## Fills this fresh grid from a structurally valid snapshot and returns a
## problem string, or "" on success.
func _load_cells(data: Dictionary) -> String:
	for i in _floor.size():
		_floor[i] = int(data["floor"][i])
		_zone[i] = int(data["zone"][i])
	for i in _h_walls.size():
		_h_walls[i] = int(data["h_walls"][i])
	for i in _v_walls.size():
		_v_walls[i] = int(data["v_walls"][i])
	var door_problem := _door_walls_problem()
	if door_problem != "":
		return door_problem
	var paid_problem := _load_paid(data)
	if paid_problem != "":
		return paid_problem
	var room_problem := _load_rooms(data)
	if room_problem != "":
		return room_problem
	for entry in data["objects"]:
		var anchor := Vector2i(int(entry["anchor"][0]), int(entry["anchor"][1]))
		var def_id := StringName(entry["def"])
		var problem := _load_object_problem(entry, def_id, anchor)
		if problem != "":
			return problem
		var paid := int(entry.get("paid", 0))
		_insert_object(int(entry["id"]), def_id, anchor, int(entry["facing"]), paid)
	_next_object_id = int(data["next_object_id"])
	_pathing.rebuild(self)
	_staff_pathing = null
	return ""


## Why a snapshot's object entry cannot be loaded, or "".
func _load_object_problem(entry: Dictionary, def_id: StringName, anchor: Vector2i) -> String:
	var id := int(entry["id"])
	var check := _check_place_object(def_id, anchor, int(entry["facing"]))
	if not check.ok:
		return "object %d refused: %s" % [id, check.reason_text()]
	var paid := int(entry.get("paid", 0))
	# No price history yet, so today's price caps what was paid. A belt
	# piece keeps its price when it changes shape (RESHAPE_BELT), so the
	# dearest belt piece caps every belt piece.
	if paid > 0 and paid > _paid_cap(def_id):
		return "object %d paid %d, more than its price" % [id, paid]
	return ""


## Fills the saved purchase prices from the optional PAID_KEYS and returns a
## problem string, or "". Floor and walls must already be loaded. A price on a
## cell with no floor or an edge with no wall could never have been paid, and
## neither could one above today's PriceTable price for the piece: there is no
## price history, so today's price is the cap.
func _load_paid(data: Dictionary) -> String:
	if not data.has(PAID_KEYS[0]):
		return ""
	for i in _floor_paid.size():
		_floor_paid[i] = int(data["floor_paid"][i])
		var cap := 0 if _floor[i] == FLOOR_NONE else PriceTable.price_of_floor()
		if _floor_paid[i] > cap:
			return "floor_paid %d at index %d is more than %d" % [_floor_paid[i], i, cap]
	for i in _h_paid.size():
		_h_paid[i] = int(data["h_walls_paid"][i])
		var problem := _wall_paid_problem("h_walls_paid", i, _h_paid[i], _h_walls[i])
		if problem != "":
			return problem
	for i in _v_paid.size():
		_v_paid[i] = int(data["v_walls_paid"][i])
		var problem := _wall_paid_problem("v_walls_paid", i, _v_paid[i], _v_walls[i])
		if problem != "":
			return problem
	return ""


func _wall_paid_problem(key: String, i: int, paid: int, kind: int) -> String:
	var cap := 0 if kind == WallKind.NONE else PriceTable.price_of_wall(kind)
	if paid > cap:
		return "%s %d at index %d is more than %d" % [key, paid, i, cap]
	return ""


## Re-places the snapshot's rooms through the placement rules and returns a
## problem string, or "". The floor must already be loaded.
func _load_rooms(data: Dictionary) -> String:
	if not data.has("rooms"):
		return ""
	for entry in data["rooms"]:
		var r: Array = entry["rect"]
		var area := Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
		var type := StringName(entry["type"])
		var check := _check_place_room(area, type)
		if not check.ok:
			return "room %d refused: %s" % [int(entry["id"]), check.reason_text()]
		_insert_room(int(entry["id"]), type, area)
	_next_room_id = int(data["next_room_id"])
	return ""


func _check_paint_floor(edit: BuildEdit) -> BuildResult:
	if not in_bounds(edit.cell):
		return BuildResult.refused(BuildResult.Reason.OUT_OF_BOUNDS)
	if edit.floor_type < 1 or edit.floor_type > MAX_FLOOR_TYPE:
		return BuildResult.refused(BuildResult.Reason.BAD_FLOOR_TYPE)
	if edit.zone_id < 0:
		return BuildResult.refused(BuildResult.Reason.BAD_ZONE)
	return BuildResult.accepted()


func _check_remove_floor(cell: Vector2i) -> BuildResult:
	if not in_bounds(cell):
		return BuildResult.refused(BuildResult.Reason.OUT_OF_BOUNDS)
	var i := _index(cell)
	if _floor[i] == FLOOR_NONE:
		return BuildResult.refused(BuildResult.Reason.NO_FLOOR)
	if _occupant[i] != 0:
		return BuildResult.refused(BuildResult.Reason.OCCUPIED, _occupant[i])
	if _reserved[i] != 0:
		return BuildResult.refused(BuildResult.Reason.INTERACTION_RESERVED, _reserved[i])
	if _room_at[i] != 0:
		return BuildResult.refused(BuildResult.Reason.IN_ROOM)
	return BuildResult.accepted()


## A room needs a known type and a non-empty rectangle of floor cells inside
## the grid that no other room covers. Its minimum size is not a placement
## rule: RoomRules shows it as a note, so a tuning change never refuses a save.
func _check_place_room(area: Rect2i, type: StringName) -> BuildResult:
	if RoomTypes.get_type(type) == null:
		return BuildResult.refused(BuildResult.Reason.UNKNOWN_ROOM_TYPE)
	var has_cells := area.size.x > 0 and area.size.y > 0
	if not has_cells or not in_bounds(area.position) or not in_bounds(area.end - Vector2i.ONE):
		return BuildResult.refused(BuildResult.Reason.OUT_OF_BOUNDS)
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var i := _index(Vector2i(x, y))
			if _floor[i] == FLOOR_NONE:
				return BuildResult.refused(BuildResult.Reason.NO_FLOOR)
			if _room_at[i] != 0:
				return BuildResult.refused(BuildResult.Reason.ROOM_OVERLAP)
	return BuildResult.accepted()


func _insert_room(room_id: int, type: StringName, area: Rect2i) -> void:
	_rooms[room_id] = {"type": type, "rect": area}
	_fill_room_cells(area, room_id)


func _erase_room(room_id: int) -> void:
	_fill_room_cells(_rooms[room_id]["rect"], 0)
	_rooms.erase(room_id)


func _fill_room_cells(area: Rect2i, value: int) -> void:
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			_room_at[_index(Vector2i(x, y))] = value


## A wall of `kind` on an empty edge, or in place of a wall of another kind.
## A door needs a plain wall in line on both sides, and a plain wall beside a
## door cannot change while the door stands.
func _check_place_wall(cell: Vector2i, side: int, kind: int) -> BuildResult:
	if not in_bounds(cell) or side < 0 or side > 3:
		return BuildResult.refused(BuildResult.Reason.OUT_OF_BOUNDS)
	var problem := _wall_kind_problem(cell, side, kind)
	if problem == null and _wall_value(cell, side) == WallKind.NONE:
		problem = _wall_object_problem(cell, side)
	return problem if problem != null else BuildResult.accepted()


## A refusal when `kind` cannot go on the edge as things stand, or null.
func _wall_kind_problem(cell: Vector2i, side: int, kind: int) -> BuildResult:
	if kind < WallKind.PLAIN or kind > MAX_WALL_KIND:
		return BuildResult.refused(BuildResult.Reason.BAD_WALL_KIND)
	var existing := _wall_value(cell, side)
	if existing == kind:
		return BuildResult.refused(BuildResult.Reason.WALL_EXISTS)
	if kind == WallKind.DOOR and not _between_plain_walls(cell, side):
		return BuildResult.refused(BuildResult.Reason.DOOR_NEEDS_WALLS)
	if existing == WallKind.PLAIN and _beside_door(cell, side):
		return BuildResult.refused(BuildResult.Reason.WALL_HOLDS_DOOR)
	return null


## A refusal when a new wall on the edge would cut through an object or shut
## an object off from its interaction cell, or null.
func _wall_object_problem(cell: Vector2i, side: int) -> BuildResult:
	var other := cell + SIDE_STEP[side]
	if not in_bounds(other):
		return null
	var here := _occupant[_index(cell)]
	var there := _occupant[_index(other)]
	if here != 0 and here == there:
		return BuildResult.refused(BuildResult.Reason.WALL_IN_FOOTPRINT, here)
	for pair in [[here, other], [there, cell]]:
		if pair[0] != 0 and _reserved[_index(pair[1])] == pair[0]:
			return BuildResult.refused(BuildResult.Reason.INTERACTION_BLOCKED, pair[0])
	return null


func _check_remove_wall(cell: Vector2i, side: int) -> BuildResult:
	if not in_bounds(cell) or side < 0 or side > 3:
		return BuildResult.refused(BuildResult.Reason.OUT_OF_BOUNDS)
	var existing := _wall_value(cell, side)
	if existing == WallKind.NONE:
		return BuildResult.refused(BuildResult.Reason.NO_WALL)
	if existing == WallKind.PLAIN and _beside_door(cell, side):
		return BuildResult.refused(BuildResult.Reason.WALL_HOLDS_DOOR)
	return BuildResult.accepted()


## The two edges in line with an edge, one at either end, as [cell, side]
## pairs on the same side. Either may lie outside the grid.
func _inline_edges(cell: Vector2i, side: int) -> Array:
	var along := Vector2i(1, 0) if side == Side.NORTH or side == Side.SOUTH else Vector2i(0, 1)
	return [[cell - along, side], [cell + along, side]]


func _between_plain_walls(cell: Vector2i, side: int) -> bool:
	for edge in _inline_edges(cell, side):
		if wall_kind(edge[0], edge[1]) != WallKind.PLAIN:
			return false
	return true


func _beside_door(cell: Vector2i, side: int) -> bool:
	for edge in _inline_edges(cell, side):
		if wall_kind(edge[0], edge[1]) == WallKind.DOOR:
			return true
	return false


## A problem string for the first door edge without a plain wall in line on
## both sides, or "". Visits every edge once: north and west of each cell, the
## south of the last row and the east of the last column.
func _door_walls_problem() -> String:
	for y in size.y:
		for x in size.x:
			var cell := Vector2i(x, y)
			var sides := [Side.NORTH, Side.WEST]
			if y == size.y - 1:
				sides.append(Side.SOUTH)
			if x == size.x - 1:
				sides.append(Side.EAST)
			for side in sides:
				var is_door := _wall_value(cell, side) == WallKind.DOOR
				if is_door and not _between_plain_walls(cell, side):
					return "door at %s side %d needs a plain wall on each side" % [cell, side]
	return ""


func _check_place_object(def_id: StringName, anchor: Vector2i, facing: int) -> BuildResult:
	var def := BuildCatalog.get_def(def_id)
	if def == null:
		return BuildResult.refused(BuildResult.Reason.UNKNOWN_OBJECT)
	if facing < 0 or facing > 3:
		return BuildResult.refused(BuildResult.Reason.BAD_FACING)
	var cells := def.footprint(anchor, facing)
	var problem := _footprint_problem(cells)
	if problem != null:
		return problem
	problem = _interaction_problem(def.interaction_cell(anchor, facing), cells)
	if problem != null:
		return problem
	return BuildResult.accepted()


## A refusal for the first footprint cell that cannot take an object, or null.
func _footprint_problem(cells: Array[Vector2i]) -> BuildResult:
	for cell in cells:
		if not in_bounds(cell):
			return BuildResult.refused(BuildResult.Reason.OUT_OF_BOUNDS)
	for cell in cells:
		var i := _index(cell)
		if _floor[i] == FLOOR_NONE:
			return BuildResult.refused(BuildResult.Reason.NO_FLOOR)
		if _occupant[i] != 0:
			return BuildResult.refused(BuildResult.Reason.OVERLAP, _occupant[i])
		if _reserved[i] != 0:
			return BuildResult.refused(BuildResult.Reason.INTERACTION_RESERVED, _reserved[i])
		for side in [Side.EAST, Side.SOUTH]:
			if cells.has(cell + SIDE_STEP[side]) and _wall_value(cell, side) != 0:
				return BuildResult.refused(BuildResult.Reason.WALL_IN_FOOTPRINT)
	return null


## A refusal when the interaction cell is unusable, or null. The cell must be
## free floor that no other object claims, with no wall between it and the
## footprint.
func _interaction_problem(spot: Vector2i, cells: Array[Vector2i]) -> BuildResult:
	if spot == BuildObjectDef.NO_CELL:
		return null
	if not in_bounds(spot) or _floor[_index(spot)] == FLOOR_NONE:
		return BuildResult.refused(BuildResult.Reason.INTERACTION_BLOCKED)
	var i := _index(spot)
	if _occupant[i] != 0:
		return BuildResult.refused(BuildResult.Reason.INTERACTION_BLOCKED, _occupant[i])
	if _reserved[i] != 0:
		return BuildResult.refused(BuildResult.Reason.INTERACTION_RESERVED, _reserved[i])
	for side in 4:
		if cells.has(spot + SIDE_STEP[side]) and _wall_value(spot, side) != 0:
			return BuildResult.refused(BuildResult.Reason.INTERACTION_BLOCKED)
	return null


## The most a saved object of `def_id` can have been bought for.
static func _paid_cap(def_id: StringName) -> int:
	if not BuildCatalog.is_belt(def_id):
		return PriceTable.price_of_object(def_id)
	var cap := 0
	for id in BuildCatalog.BELT_IDS:
		cap = maxi(cap, PriceTable.price_of_object(id))
	return cap


## A belt piece on the cell can become any belt piece at any facing.
func _check_reshape_belt(edit: BuildEdit) -> BuildResult:
	if not in_bounds(edit.cell):
		return BuildResult.refused(BuildResult.Reason.OUT_OF_BOUNDS)
	var object_id := object_at(edit.cell)
	if object_id == 0:
		return BuildResult.refused(BuildResult.Reason.NO_OBJECT)
	var was_belt := BuildCatalog.is_belt(_objects[object_id]["def"])
	if not was_belt or not BuildCatalog.is_belt(edit.def_id):
		return BuildResult.refused(BuildResult.Reason.NOT_A_BELT, object_id)
	if edit.facing < 0 or edit.facing > 3:
		return BuildResult.refused(BuildResult.Reason.BAD_FACING)
	return BuildResult.accepted()


func _insert_object(
	object_id: int, def_id: StringName, anchor: Vector2i, facing: int, paid := 0
) -> Array[Vector2i]:
	_objects[object_id] = {"def": def_id, "anchor": anchor, "facing": facing, "paid": paid}
	var def := BuildCatalog.get_def(def_id)
	var cells := def.footprint(anchor, facing)
	for cell in cells:
		_occupant[_index(cell)] = object_id
	var spot := def.interaction_cell(anchor, facing)
	if spot != BuildObjectDef.NO_CELL:
		_reserved[_index(spot)] = object_id
	_spots.add(object_id, StaffSpots.cell_of(def_id, anchor, facing))
	return cells


func _erase_object(object_id: int) -> Array[Vector2i]:
	var record: Dictionary = _objects[object_id]
	var def := _def_of(object_id)
	var cells := def.footprint(record["anchor"], record["facing"])
	for cell in cells:
		_occupant[_index(cell)] = 0
	var spot := def.interaction_cell(record["anchor"], record["facing"])
	if spot != BuildObjectDef.NO_CELL:
		_reserved[_index(spot)] = 0
	_spots.remove(object_id, StaffSpots.cell_of(record["def"], record["anchor"], record["facing"]))
	_objects.erase(object_id)
	return cells


## An orthogonal step between two walkable cells: no wall on the shared edge
## other than a door, and a walk-through object is only entered or left along
## its axis.
func _straight_step_open(from: Vector2i, to: Vector2i) -> bool:
	var step := to - from
	var wall := _wall_value(from, SIDE_STEP.find(step))
	if wall != WallKind.NONE and wall != WallKind.DOOR:
		return false
	return _passes_through(from, step) and _passes_through(to, step)


func _passes_through(cell: Vector2i, step: Vector2i) -> bool:
	var occupant := _occupant[_index(cell)]
	if occupant == 0:
		return true
	var axis := _def_of(occupant).through_axis(_objects[occupant]["facing"])
	return step == axis or step == -axis


## Relinks both A* graphs around `dirty` cells (the staff one once built) and
## returns the cells relinked.
func _relink_paths(dirty: Array[Vector2i]) -> Array[Vector2i]:
	if _staff_pathing != null:
		_staff_pathing.update(self, dirty)
	return _pathing.update(self, dirty)


func _is_security_cell(cell: Vector2i) -> bool:
	var occupant := _occupant[_index(cell)]
	return occupant != 0 and BuildCatalog.is_security(_objects[occupant]["def"])


func _def_of(object_id: int) -> BuildObjectDef:
	return BuildCatalog.get_def(_objects[object_id]["def"])


func _index(cell: Vector2i) -> int:
	return cell.y * size.x + cell.x


func _wall_value(cell: Vector2i, side: int) -> int:
	match side:
		Side.NORTH:
			return _h_walls[cell.y * size.x + cell.x]
		Side.SOUTH:
			return _h_walls[(cell.y + 1) * size.x + cell.x]
		Side.WEST:
			return _v_walls[cell.y * (size.x + 1) + cell.x]
	return _v_walls[cell.y * (size.x + 1) + cell.x + 1]


func _set_wall(cell: Vector2i, side: int, value: int) -> void:
	match side:
		Side.NORTH:
			_h_walls[cell.y * size.x + cell.x] = value
		Side.SOUTH:
			_h_walls[(cell.y + 1) * size.x + cell.x] = value
		Side.WEST:
			_v_walls[cell.y * (size.x + 1) + cell.x] = value
		Side.EAST:
			_v_walls[cell.y * (size.x + 1) + cell.x + 1] = value


func _set_wall_paid(cell: Vector2i, side: int, value: int) -> void:
	if side == Side.NORTH or side == Side.SOUTH:
		_h_paid[_h_index(cell, side)] = value
	else:
		_v_paid[_v_index(cell, side)] = value


## Index of a north or south edge in the _h_walls layout.
func _h_index(cell: Vector2i, side: int) -> int:
	return (cell.y + (1 if side == Side.SOUTH else 0)) * size.x + cell.x


## Index of a west or east edge in the _v_walls layout.
func _v_index(cell: Vector2i, side: int) -> int:
	return cell.y * (size.x + 1) + cell.x + (1 if side == Side.EAST else 0)


## The in-bounds cells on either side of an edge.
func _edge_cells(cell: Vector2i, side: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [cell]
	var other := cell + SIDE_STEP[side]
	if in_bounds(other):
		cells.append(other)
	return cells


static func _zeros_bytes(count: int) -> PackedByteArray:
	var array := PackedByteArray()
	array.resize(count)
	array.fill(0)
	return array


static func _zeros_ints(count: int) -> PackedInt32Array:
	var array := PackedInt32Array()
	array.resize(count)
	array.fill(0)
	return array
