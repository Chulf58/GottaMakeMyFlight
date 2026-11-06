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
## list of edits, see apply_batch()). The graph is built on a load and when a
## path is first asked for, not by a new grid or a clone(): a check that never
## asks for a path does not pay for it (about 0.2 s on the 86x150 site).
##
## Each floor cell, wall edge and object keeps the purchase price it was
## placed with (BuildEdit.paid), so a removal refunds a share of what was
## actually paid (BuildTransaction). The grid itself never touches money.

## After an accepted edit: the cells GridPathing relinked, and every floored
## cell whose indoor state the edit changed (TerminalEnclosure), so every
## committed path through one of them may be stale. After a snapshot load:
## every cell.
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
## 1 where TerminalEnclosure's flood from outside reaches a cell, 0 where
## walls close it in (is_indoor()). Derived from the walls and door objects,
## never saved; worked out again after an edit to either.
var _outside := PackedByteArray()
## Set by _commit() when an edit changed a wall or a door object, so the
## enclosure is worked out again before the graph is relinked.
var _enclosure_stale := false
## Every cell an edit changed since the grid was reset or loaded (and, after a
## load, every floored or walled one), as one rectangle, zero sized for none.
## It only grows between loads. No wall or door stands outside it, so the flood
## runs on it one cell wider only (flood_area()).
var _built := Rect2i()
## The passenger A* graph, kept up to date by every relink once built; null
## until a load or the first find_path() builds it.
var _pathing: GridPathing = null
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


## Whether `cell` is floor that walls close in on every side
## (TerminalEnclosure).
func is_indoor(cell: Vector2i) -> bool:
	if not in_bounds(cell):
		return false
	var i := _index(cell)
	return _floor[i] != FLOOR_NONE and _outside[i] == 0


## The one passenger-cell eligibility rule: a passenger may stand on, queue
## on, sit in front of or walk to `cell` only when it is walkable and indoor.
## Staff are not bound by it (can_staff_route()).
func is_passenger_cell(cell: Vector2i) -> bool:
	return is_walkable(cell) and is_indoor(cell)


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


## A step passengers may take: can_route() between two indoor cells. The
## passenger A* graph walks only these steps (GridPathing). can_route() stays
## physical, for the rules about the structure (SecurityLanes).
func can_passenger_route(from: Vector2i, to: Vector2i) -> bool:
	return can_route(from, to) and is_indoor(from) and is_indoor(to)


## A step staff may take: any can_step(), so staff walk through a security
## scanner or arch along its axis like screened airport staff (decision
## staff-may-walk-through-security-scanners-and-lanes-so-shop-s). Passengers
## route by can_route() and never do.
func can_staff_route(from: Vector2i, to: Vector2i) -> bool:
	return can_step(from, to)


func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if _pathing == null:
		_pathing = GridPathing.new()
		_pathing.rebuild(self)
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
	var result := GridRules.check(self, edit)
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
	return GridReach.staff_reach_problem(self, edits)


## StationUseCells.answers() with `def_id` written in under an unused id as
## GridReach._reach_after() does (unchecked, silent, A* untouched), then put
## back; {} when off the grid.
func trial_answers(def_id: StringName, at: Vector2i, turn: int) -> Dictionary:
	var def := BuildCatalog.get_def(def_id)
	var cells := def.footprint(at, turn) + [def.interaction_cell(at, turn)]
	if not cells.all(func(c: Vector2i) -> bool: return in_bounds(c) or c == BuildObjectDef.NO_CELL):
		return {}
	var kept := [_occupant.duplicate(), _reserved.duplicate()]
	_insert_object(_next_object_id, def_id, at, turn)
	var out := StationUseCells.answers(self, _next_object_id)
	_erase_object(_next_object_id)
	_occupant = kept[0]
	_reserved = kept[1]
	return out


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
	# (GridReach.batch_keeps_reach()); otherwise each edit is checked as it comes.
	_reach_cleared = check_staff_reach and GridReach.batch_keeps_reach(self, edits)
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
	_reach_cleared = check_staff_reach and GridReach.batch_keeps_reach(self, edits)
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
			_enclosure_stale = true
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
			# A door object's back edge closes the wall line it stands in.
			_enclosure_stale = _enclosure_stale or BuildCatalog.is_door(edit.def_id)
		BuildEdit.Kind.REMOVE_OBJECT:
			result.object_id = edit.object_id
			var def_id: StringName = _objects[edit.object_id]["def"]
			_enclosure_stale = _enclosure_stale or BuildCatalog.is_door(def_id)
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
		BuildEdit.Kind.RESIZE_ROOM:
			result.room_id = edit.room_id
			_resize_room(edit.room_id, Rect2i(edit.cell, edit.room_size))
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
	return BuildGridSave.to_snapshot(self)


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
	if not BuildGridSave.load_into(self, data):
		return false
	if recorder != null:
		recorder.replaced = true
	var every: Array[Vector2i] = []
	for y in size.y:
		for x in size.x:
			every.append(Vector2i(x, y))
	_emit_or_hold(func() -> void: graph_changed.emit(every))
	return true


## A copy of this grid to try edits on: the same data as from_snapshot() of
## to_snapshot() would give (objects in id order), copied as it stands rather
## than placed again, and of the same class (_blank_copy()). Its A* graphs are
## built when a path is first asked for; its signals are its own, and it has
## no recorder. On the 86x150 site a snapshot copy took about 0.7 s.
func clone() -> BuildGrid:
	return BuildGridSave.clone(self)


## A plain BuildGrid of only `area` of this grid, cell (0, 0) at `area`'s
## corner: the grid from_snapshot() of RepairPlan's crop of to_snapshot()
## gives, copied as it stands rather than placed again. Its passenger A* graph
## is built when a path is first asked for. On the 86x150 site a crop through a
## load took about 20 ms, most of it building that graph. Every object and room
## must lie inside `area`; otherwise pushes an error and returns null.
func cropped(area: Rect2i) -> BuildGrid:
	return BuildGridSave.cropped(self, area)


## An empty grid of this grid's class for clone() to fill. A subclass whose
## constructor takes other arguments overrides it (SiteGrid).
func _blank_copy() -> BuildGrid:
	return BuildGrid.new(size, origin)


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
	# No walls and no doors yet: every cell is outside.
	_outside = _zeros_bytes(cells)
	_outside.fill(1)
	_built = Rect2i()
	_enclosure_stale = false


func _insert_room(room_id: int, type: StringName, area: Rect2i) -> void:
	_rooms[room_id] = {"type": type, "rect": area}
	_fill_room_cells(area, room_id)


func _resize_room(room_id: int, area: Rect2i) -> void:
	_fill_room_cells(_rooms[room_id]["rect"], 0)
	_rooms[room_id]["rect"] = area
	_fill_room_cells(area, room_id)


func _erase_room(room_id: int) -> void:
	_fill_room_cells(_rooms[room_id]["rect"], 0)
	_rooms.erase(room_id)


func _fill_room_cells(area: Rect2i, value: int) -> void:
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			_room_at[_index(Vector2i(x, y))] = value


## A refusal when the interaction cell is unusable, or null. The cell must be
## free floor that no other object claims, with no wall between it and the
## footprint. The build ghost asks it too (StationUseCells).
func interaction_problem(spot: Vector2i, cells: Array[Vector2i]) -> BuildResult:
	return GridRules.interaction_problem(self, spot, cells)


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


## The part of the grid the flood from outside runs on: _built one cell wider
## each way, inside the grid (TerminalEnclosure.outside_within()).
func flood_area() -> Rect2i:
	if _built.size == Vector2i.ZERO:
		return Rect2i()
	return _built.grow(1).intersection(Rect2i(Vector2i.ZERO, size))


## Relinks both A* graphs around `dirty` cells (the staff one once built) and
## returns the cells relinked. When an edit left the enclosure stale it is
## worked out again first, on flood_area() only, and every floored cell whose
## indoor state changed, however far from the edit, has its passenger point
## switched and is returned too: one removed wall can let the outside into a
## whole hall. Those points are switched by index straight from the flood
## (GridPathing.set_outside()); on the 86x150 site that took the edit opening
## a whole-site hall from about 13 ms to about 7 ms (board ee9914e6, L4).
func _relink_paths(dirty: Array[Vector2i]) -> Array[Vector2i]:
	for cell in dirty:
		var one := Rect2i(cell, Vector2i.ONE)
		_built = one if _built.size == Vector2i.ZERO else _built.merge(one)
	var flipped := PackedInt32Array()
	if _enclosure_stale:
		_enclosure_stale = false
		var area := flood_area()
		var after := TerminalEnclosure.outside_within(self, _h_walls, _v_walls, area)
		flipped = TerminalEnclosure.flipped_floor_indices(size.x, _floor, _outside, after, area)
		_outside = after
	if _staff_pathing != null and not dirty.is_empty():
		_staff_pathing.update(self, dirty)
	# With no graph yet, the cells it would relink: the one built later links
	# the grid as it is then.
	var cells := (
		GridPathing.neighbourhood(self, dirty) if _pathing == null else _pathing.update(self, dirty)
	)
	if flipped.is_empty():
		return cells
	if _pathing != null:
		_pathing.set_outside(flipped, _outside)
	var seen := {}
	for cell in cells:
		seen[cell.x + cell.y * size.x] = true
	for i in flipped:
		if not seen.has(i):
			@warning_ignore("integer_division")
			cells.append(Vector2i(i % size.x, i / size.x))
	return cells


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
