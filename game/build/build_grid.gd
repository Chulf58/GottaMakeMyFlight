class_name BuildGrid
extends RefCounted
## The indoor build grid: 1 m cells in packed arrays, the source of truth for
## floors, walls and placed objects. Nodes only draw it. Cell (x, y) covers
## world x in [origin.x + x, +1) and world z in [origin.z + y, +1); the grid
## is centred on the world origin. North is -y (world -z).
##
## Every change goes through validate() and apply() with a BuildEdit, so the
## preview, the click and a snapshot load share one set of rules. apply()
## then relinks the A* graph around the changed cells only.

## After an accepted edit: the cells GridPathing relinked, so every committed
## path through one of them may be stale. After a snapshot load: every cell.
signal graph_changed(cells: Array[Vector2i])

enum Side { NORTH, EAST, SOUTH, WEST }

const DEFAULT_SIZE := Vector2i(64, 64)
const MAX_SIDE_CELLS := 256
const FLOOR_NONE := 0
const FLOOR_TILE := 1
const MAX_FLOOR_TYPE := 1
const MAX_ZONE_ID := 2147483647
## Grid step for each Side.
const SIDE_STEP: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)
]
const SNAPSHOT_KEYS := [
	"width", "height", "floor", "zone", "h_walls", "v_walls", "objects", "next_object_id"
]
const OBJECT_KEYS := ["id", "def", "anchor", "facing"]

var size := Vector2i.ZERO
## World position of the north-west corner of cell (0, 0).
var origin := Vector3.ZERO

var _floor := PackedByteArray()
var _zone := PackedInt32Array()
## 1 where a wall runs along the north edge of cell (x, y), at x + y * size.x.
## Row y == size.y holds the south border.
var _h_walls := PackedByteArray()
## 1 where a wall runs along the west edge of cell (x, y), at
## x + y * (size.x + 1). Column x == size.x holds the east border.
var _v_walls := PackedByteArray()
## Id of the object standing on each cell, 0 for none.
var _occupant := PackedInt32Array()
## Id of the object whose interaction cell this is, 0 for none.
var _reserved := PackedInt32Array()
## Object id -> {"def": StringName, "anchor": Vector2i, "facing": int}.
var _objects: Dictionary = {}
var _next_object_id := 1
var _pathing := GridPathing.new()


func _init(grid_size := DEFAULT_SIZE) -> void:
	_reset(grid_size)
	_pathing.rebuild(self)


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


func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	return _pathing.find_path(self, from, to)


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


## Checks an edit without changing anything.
func validate(edit: BuildEdit) -> BuildResult:
	var result: BuildResult
	match edit.kind:
		BuildEdit.Kind.PAINT_FLOOR:
			result = _check_paint_floor(edit)
		BuildEdit.Kind.REMOVE_FLOOR:
			result = _check_remove_floor(edit.cell)
		BuildEdit.Kind.PLACE_WALL:
			result = _check_place_wall(edit.cell, edit.side)
		BuildEdit.Kind.REMOVE_WALL:
			result = _check_remove_wall(edit.cell, edit.side)
		BuildEdit.Kind.PLACE_OBJECT:
			result = _check_place_object(edit.def_id, edit.cell, edit.facing)
		BuildEdit.Kind.REMOVE_OBJECT:
			if _objects.has(edit.object_id):
				result = BuildResult.accepted()
			else:
				result = BuildResult.refused(BuildResult.Reason.NO_OBJECT)
	return result


## Validates the edit and, if it is accepted, applies it and relinks the A*
## graph around its dirty cells. A refused edit changes nothing.
func apply(edit: BuildEdit) -> BuildResult:
	var result := validate(edit)
	if not result.ok:
		return result
	match edit.kind:
		BuildEdit.Kind.PAINT_FLOOR:
			_floor[_index(edit.cell)] = edit.floor_type
			_zone[_index(edit.cell)] = edit.zone_id
			result.dirty_cells = [edit.cell]
		BuildEdit.Kind.REMOVE_FLOOR:
			_floor[_index(edit.cell)] = FLOOR_NONE
			_zone[_index(edit.cell)] = 0
			result.dirty_cells = [edit.cell]
		BuildEdit.Kind.PLACE_WALL, BuildEdit.Kind.REMOVE_WALL:
			var value := 1 if edit.kind == BuildEdit.Kind.PLACE_WALL else 0
			_set_wall(edit.cell, edit.side, value)
			result.dirty_cells = _edge_cells(edit.cell, edit.side)
		BuildEdit.Kind.PLACE_OBJECT:
			result.object_id = _next_object_id
			_next_object_id += 1
			result.dirty_cells = _insert_object(
				result.object_id, edit.def_id, edit.cell, edit.facing
			)
		BuildEdit.Kind.REMOVE_OBJECT:
			result.object_id = edit.object_id
			result.dirty_cells = _erase_object(edit.object_id)
	graph_changed.emit(_pathing.update(self, result.dirty_cells))
	return result


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
		}
		objects.append(entry)
	return {
		"width": size.x,
		"height": size.y,
		"floor": Array(_floor),
		"zone": Array(_zone),
		"h_walls": Array(_h_walls),
		"v_walls": Array(_v_walls),
		"objects": objects,
		"next_object_id": _next_object_id,
	}


## Restores a to_snapshot() dictionary, including one that went through JSON
## (which turns ints into floats). Every object is re-placed through the
## placement rules. Pushes an error and returns false, leaving the grid
## unchanged, when anything is missing, malformed or breaks a rule.
func from_snapshot(data: Dictionary) -> bool:
	var problem := BuildGridSnapshot.problem(data)
	var loaded: BuildGrid = null
	if problem == "":
		loaded = BuildGrid.new(Vector2i(int(data["width"]), int(data["height"])))
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
	_objects = loaded._objects
	_next_object_id = loaded._next_object_id
	_pathing = loaded._pathing
	var every: Array[Vector2i] = []
	for y in size.y:
		for x in size.x:
			every.append(Vector2i(x, y))
	graph_changed.emit(every)
	return true


func _reset(grid_size: Vector2i) -> void:
	size = grid_size
	origin = Vector3(-size.x / 2.0, 0.0, -size.y / 2.0)
	var cells := size.x * size.y
	_floor = _zeros_bytes(cells)
	_h_walls = _zeros_bytes(size.x * (size.y + 1))
	_v_walls = _zeros_bytes((size.x + 1) * size.y)
	_zone = _zeros_ints(cells)
	_occupant = _zeros_ints(cells)
	_reserved = _zeros_ints(cells)
	_objects = {}
	_next_object_id = 1


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
	for entry in data["objects"]:
		var anchor := Vector2i(int(entry["anchor"][0]), int(entry["anchor"][1]))
		var def_id := StringName(entry["def"])
		var check := _check_place_object(def_id, anchor, int(entry["facing"]))
		if not check.ok:
			return "object %d refused: %s" % [int(entry["id"]), check.reason_text()]
		_insert_object(int(entry["id"]), def_id, anchor, int(entry["facing"]))
	_next_object_id = int(data["next_object_id"])
	_pathing.rebuild(self)
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
	return BuildResult.accepted()


func _check_place_wall(cell: Vector2i, side: int) -> BuildResult:
	if not in_bounds(cell) or side < 0 or side > 3:
		return BuildResult.refused(BuildResult.Reason.OUT_OF_BOUNDS)
	if _wall_value(cell, side) != 0:
		return BuildResult.refused(BuildResult.Reason.WALL_EXISTS)
	var other := cell + SIDE_STEP[side]
	if not in_bounds(other):
		return BuildResult.accepted()
	var here := _occupant[_index(cell)]
	var there := _occupant[_index(other)]
	if here != 0 and here == there:
		return BuildResult.refused(BuildResult.Reason.WALL_IN_FOOTPRINT, here)
	for pair in [[here, other], [there, cell]]:
		if pair[0] != 0 and _reserved[_index(pair[1])] == pair[0]:
			return BuildResult.refused(BuildResult.Reason.INTERACTION_BLOCKED, pair[0])
	return BuildResult.accepted()


func _check_remove_wall(cell: Vector2i, side: int) -> BuildResult:
	if not in_bounds(cell) or side < 0 or side > 3:
		return BuildResult.refused(BuildResult.Reason.OUT_OF_BOUNDS)
	if _wall_value(cell, side) == 0:
		return BuildResult.refused(BuildResult.Reason.NO_WALL)
	return BuildResult.accepted()


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


func _insert_object(
	object_id: int, def_id: StringName, anchor: Vector2i, facing: int
) -> Array[Vector2i]:
	_objects[object_id] = {"def": def_id, "anchor": anchor, "facing": facing}
	var def := BuildCatalog.get_def(def_id)
	var cells := def.footprint(anchor, facing)
	for cell in cells:
		_occupant[_index(cell)] = object_id
	var spot := def.interaction_cell(anchor, facing)
	if spot != BuildObjectDef.NO_CELL:
		_reserved[_index(spot)] = object_id
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
	_objects.erase(object_id)
	return cells


## An orthogonal step between two walkable cells: no wall on the shared edge,
## and a walk-through object is only entered or left along its axis.
func _straight_step_open(from: Vector2i, to: Vector2i) -> bool:
	var step := to - from
	if _wall_value(from, SIDE_STEP.find(step)) != 0:
		return false
	return _passes_through(from, step) and _passes_through(to, step)


func _passes_through(cell: Vector2i, step: Vector2i) -> bool:
	var occupant := _occupant[_index(cell)]
	if occupant == 0:
		return true
	var axis := _def_of(occupant).through_axis(_objects[occupant]["facing"])
	return step == axis or step == -axis


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
