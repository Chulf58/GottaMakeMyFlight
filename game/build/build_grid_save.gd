class_name BuildGridSave
extends RefCounted
## Saving, loading, copying and cropping a BuildGrid: static helpers split out
## of build_grid.gd (decision
## how-to-split-a-big-gdscript-file-static-helper-classes-that). The grid is
## the first argument, and these read or fill its private data directly. The
## structural checks and the snapshot shape stay in BuildGridSnapshot.


## Checks `data`, builds the grid it describes on a fresh BuildGrid and takes
## that grid's state into `grid`. Pushes an error and returns false, leaving
## `grid` unchanged, when anything is missing, malformed or breaks a rule.
static func load_into(grid: BuildGrid, data: Dictionary) -> bool:
	var problem := BuildGridSnapshot.problem(data)
	var loaded: BuildGrid = null
	if problem == "":
		var loaded_size := Vector2i(int(data["width"]), int(data["height"]))
		var at := BuildGrid.centred_origin(loaded_size)
		if data.has("origin"):
			at = Vector3(data["origin"][0], data["origin"][1], data["origin"][2])
		loaded = BuildGrid.new(loaded_size, at)
		problem = _load_cells(loaded, data)
	if problem != "":
		push_error("BuildGrid.from_snapshot: %s" % problem)
		return false
	grid.size = loaded.size
	grid.origin = loaded.origin
	grid._floor = loaded._floor
	grid._zone = loaded._zone
	grid._h_walls = loaded._h_walls
	grid._v_walls = loaded._v_walls
	grid._occupant = loaded._occupant
	grid._reserved = loaded._reserved
	grid._spots = loaded._spots
	grid._objects = loaded._objects
	grid._next_object_id = loaded._next_object_id
	grid._rooms = loaded._rooms
	grid._room_at = loaded._room_at
	grid._next_room_id = loaded._next_room_id
	grid._floor_paid = loaded._floor_paid
	grid._h_paid = loaded._h_paid
	grid._v_paid = loaded._v_paid
	grid._outside = loaded._outside
	grid._built = loaded._built
	grid._enclosure_stale = false
	grid._pathing = loaded._pathing
	grid._staff_pathing = loaded._staff_pathing
	grid._staff_reach_known = false
	grid._lanes = null
	return true


static func to_snapshot(grid: BuildGrid) -> Dictionary:
	var objects := []
	var ids := grid.object_ids()
	ids.sort()
	for object_id in ids:
		var record: Dictionary = grid._objects[object_id]
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
	for room_id in grid.room_ids():
		var area: Rect2i = grid._rooms[room_id]["rect"]
		(
			rooms
			. append(
				{
					"id": room_id,
					"type": str(grid._rooms[room_id]["type"]),
					"rect": [area.position.x, area.position.y, area.size.x, area.size.y],
				}
			)
		)
	return {
		"width": grid.size.x,
		"height": grid.size.y,
		"floor": Array(grid._floor),
		"zone": Array(grid._zone),
		"h_walls": Array(grid._h_walls),
		"v_walls": Array(grid._v_walls),
		"objects": objects,
		"next_object_id": grid._next_object_id,
		"origin": [grid.origin.x, grid.origin.y, grid.origin.z],
		"rooms": rooms,
		"next_room_id": grid._next_room_id,
		"floor_paid": Array(grid._floor_paid),
		"h_walls_paid": Array(grid._h_paid),
		"v_walls_paid": Array(grid._v_paid),
	}


static func clone(grid: BuildGrid) -> BuildGrid:
	var copy := grid._blank_copy()
	copy.size = grid.size
	copy.origin = grid.origin
	copy.check_staff_reach = grid.check_staff_reach
	copy._floor = grid._floor.duplicate()
	copy._zone = grid._zone.duplicate()
	copy._h_walls = grid._h_walls.duplicate()
	copy._v_walls = grid._v_walls.duplicate()
	copy._occupant = grid._occupant.duplicate()
	copy._reserved = grid._reserved.duplicate()
	copy._spots = StaffSpots.new()
	copy._objects = {}
	var ids := grid.object_ids()
	ids.sort()
	for object_id in ids:
		var record: Dictionary = grid._objects[object_id].duplicate(true)
		copy._objects[object_id] = record
		copy._spots.add(
			object_id, StaffSpots.cell_of(record["def"], record["anchor"], record["facing"])
		)
	copy._next_object_id = grid._next_object_id
	copy._rooms = {}
	for room_id in grid.room_ids():
		copy._rooms[room_id] = grid._rooms[room_id].duplicate(true)
	copy._room_at = grid._room_at.duplicate()
	copy._next_room_id = grid._next_room_id
	copy._floor_paid = grid._floor_paid.duplicate()
	copy._h_paid = grid._h_paid.duplicate()
	copy._v_paid = grid._v_paid.duplicate()
	copy._outside = grid._outside.duplicate()
	copy._built = grid._built
	copy._enclosure_stale = grid._enclosure_stale
	copy._staff_reach = grid._staff_reach.duplicate()
	copy._staff_reach_known = grid._staff_reach_known
	return copy


static func cropped(grid: BuildGrid, area: Rect2i) -> BuildGrid:
	var copy := BuildGrid.new(
		area.size, grid.origin + Vector3(area.position.x, 0.0, area.position.y)
	)
	var shift := -area.position
	for id in grid._objects:
		var record: Dictionary = grid._objects[id].duplicate(true)
		var cells := BuildCatalog.get_def(record["def"]).footprint(
			record["anchor"], record["facing"]
		)
		for cell in cells:
			if not area.has_point(cell):
				push_error("BuildGrid.cropped: object %d lies outside %s" % [id, area])
				return null
		record["anchor"] += shift
		copy._objects[id] = record
		copy._spots.add(id, StaffSpots.cell_of(record["def"], record["anchor"], record["facing"]))
	for id in grid._rooms:
		var room: Dictionary = grid._rooms[id].duplicate(true)
		if not area.encloses(room["rect"]):
			push_error("BuildGrid.cropped: room %d lies outside %s" % [id, area])
			return null
		room["rect"] = Rect2i(room["rect"].position + shift, room["rect"].size)
		copy._rooms[id] = room
	var cells := [area.position.x, area.size.x, area.position.y, area.size.y]
	var north_south := [area.position.x, area.size.x, area.position.y, area.size.y + 1]
	var west_east := [area.position.x, area.size.x + 1, area.position.y, area.size.y]
	copy._floor = _window(grid._floor, grid.size.x, cells)
	copy._zone = _window(grid._zone, grid.size.x, cells)
	copy._floor_paid = _window(grid._floor_paid, grid.size.x, cells)
	copy._occupant = _window(grid._occupant, grid.size.x, cells)
	copy._reserved = _window(grid._reserved, grid.size.x, cells)
	copy._room_at = _window(grid._room_at, grid.size.x, cells)
	copy._h_walls = _window(grid._h_walls, grid.size.x, north_south)
	copy._h_paid = _window(grid._h_paid, grid.size.x, north_south)
	copy._v_walls = _window(grid._v_walls, grid.size.x + 1, west_east)
	copy._v_paid = _window(grid._v_paid, grid.size.x + 1, west_east)
	copy._next_object_id = grid._next_object_id
	copy._next_room_id = grid._next_room_id
	copy._built = TerminalEnclosure.built_area(copy.size, copy._floor, copy._h_walls, copy._v_walls)
	copy._outside = TerminalEnclosure.outside_within(
		copy, copy._h_walls, copy._v_walls, copy.flood_area()
	)
	return copy


## The values of `window` [x, width, y, height] out of `values`, a row-major
## packed array `stride` values wide, row by row, in an array of its type.
static func _window(values: Variant, stride: int, window: Array) -> Variant:
	var out: Variant = values.slice(0, 0)
	for y in range(window[2], window[2] + window[3]):
		var start: int = y * stride + window[0]
		out.append_array(values.slice(start, start + window[1]))
	return out


## Fills this fresh grid from a structurally valid snapshot and returns a
## problem string, or "" on success.
static func _load_cells(grid: BuildGrid, data: Dictionary) -> String:
	for i in grid._floor.size():
		grid._floor[i] = int(data["floor"][i])
		grid._zone[i] = int(data["zone"][i])
	for i in grid._h_walls.size():
		grid._h_walls[i] = int(data["h_walls"][i])
	for i in grid._v_walls.size():
		grid._v_walls[i] = int(data["v_walls"][i])
	var door_problem := GridRules.door_walls_problem(grid)
	if door_problem != "":
		return door_problem
	var paid_problem := _load_paid(grid, data)
	if paid_problem != "":
		return paid_problem
	var room_problem := _load_rooms(grid, data)
	if room_problem != "":
		return room_problem
	for entry in data["objects"]:
		var anchor := Vector2i(int(entry["anchor"][0]), int(entry["anchor"][1]))
		var def_id := StringName(entry["def"])
		var problem := _load_object_problem(grid, entry, def_id, anchor)
		if problem != "":
			return problem
		var paid := int(entry.get("paid", 0))
		grid._insert_object(int(entry["id"]), def_id, anchor, int(entry["facing"]), paid)
	grid._next_object_id = int(data["next_object_id"])
	grid._built = TerminalEnclosure.built_area(grid.size, grid._floor, grid._h_walls, grid._v_walls)
	grid._outside = TerminalEnclosure.outside_within(
		grid, grid._h_walls, grid._v_walls, grid.flood_area()
	)
	grid._pathing = GridPathing.new()
	grid._pathing.rebuild(grid)
	grid._staff_pathing = null
	return ""


## Why a snapshot's object entry cannot be loaded, or "".
static func _load_object_problem(
	grid: BuildGrid, entry: Dictionary, def_id: StringName, anchor: Vector2i
) -> String:
	var id := int(entry["id"])
	var check := GridRules.check_place_object(grid, def_id, anchor, int(entry["facing"]))
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
static func _load_paid(grid: BuildGrid, data: Dictionary) -> String:
	if not data.has(BuildGrid.PAID_KEYS[0]):
		return ""
	for i in grid._floor_paid.size():
		grid._floor_paid[i] = int(data["floor_paid"][i])
		var cap := 0 if grid._floor[i] == BuildGrid.FLOOR_NONE else PriceTable.price_of_floor()
		if grid._floor_paid[i] > cap:
			return "floor_paid %d at index %d is more than %d" % [grid._floor_paid[i], i, cap]
	for i in grid._h_paid.size():
		grid._h_paid[i] = int(data["h_walls_paid"][i])
		var problem := _wall_paid_problem("h_walls_paid", i, grid._h_paid[i], grid._h_walls[i])
		if problem != "":
			return problem
	for i in grid._v_paid.size():
		grid._v_paid[i] = int(data["v_walls_paid"][i])
		var problem := _wall_paid_problem("v_walls_paid", i, grid._v_paid[i], grid._v_walls[i])
		if problem != "":
			return problem
	return ""


static func _wall_paid_problem(key: String, i: int, paid: int, kind: int) -> String:
	var cap := 0 if kind == BuildGrid.WallKind.NONE else PriceTable.price_of_wall(kind)
	if paid > cap:
		return "%s %d at index %d is more than %d" % [key, paid, i, cap]
	return ""


## Re-places the snapshot's rooms through the placement rules and returns a
## problem string, or "". The floor must already be loaded.
static func _load_rooms(grid: BuildGrid, data: Dictionary) -> String:
	if not data.has("rooms"):
		return ""
	for entry in data["rooms"]:
		var r: Array = entry["rect"]
		var area := Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
		var type := StringName(entry["type"])
		var check := GridRules.check_place_room(grid, area, type)
		if not check.ok:
			return "room %d refused: %s" % [int(entry["id"]), check.reason_text()]
		grid._insert_room(int(entry["id"]), type, area)
	grid._next_room_id = int(data["next_room_id"])
	return ""


## The most a saved object of `def_id` can have been bought for.
static func _paid_cap(def_id: StringName) -> int:
	if not BuildCatalog.is_belt(def_id):
		return PriceTable.price_of_object(def_id)
	var cap := 0
	for id in BuildCatalog.BELT_IDS:
		cap = maxi(cap, PriceTable.price_of_object(id))
	return cap
