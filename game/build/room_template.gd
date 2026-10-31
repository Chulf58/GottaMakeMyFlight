class_name RoomTemplate
extends RefCounted
## A saved store room (decision room-templates-store-rooms-with-their-pieces-
## kept-in-each-sa): its RoomTypes id, its size and every piece inside it, each
## piece's anchor relative to the room's north-west cell, and the room's floor.
## A paste is a PAINT_FLOOR edit for each of its cells the grid has no floor
## on, the PLACE_ROOM edit and one PLACE_OBJECT edit per piece (plan()), turned a
## quarter turn per `turns`: the room's cells and every piece's cells and
## facing turn together, the way BuildObjectDef.rotate_offset() turns a piece.
##
## Only pieces whose whole footprint lies inside the room are kept, so a belt
## running out of the room keeps only its cells inside. Desks, scanners,
## security lane parts and doors are never kept (their paste would have to
## pass staff-reach and lane rules; the ruling defers them). A belt piece is
## kept as a plain belt with its facing: TemplatePaste reshapes it after the
## paste (BeltShaper), as the Belt tool does.

## Room sizes and piece counts a saved template may have, so a save cannot ask
## for a room larger than any grid.
const MAX_SIDE := 256
const MAX_PIECES := 1024

var name := ""
var room_type: StringName = &""
var size := Vector2i.ZERO
## Each {"def": StringName, "anchor": Vector2i, "facing": int}, anchors
## relative to the room's north-west cell.
var pieces: Array[Dictionary] = []
## The floor of each cell, row by row from the north-west cell: Vector2i(floor
## type, zone id).
var floors: Array[Vector2i] = []


## Whether a piece of `def_id` may be kept in a template.
static func keeps_piece(def_id: StringName) -> bool:
	if BuildCatalog.get_def(def_id) == null:
		return false
	return not (
		def_id == &"checkin_desk"
		or BuildCatalog.is_security(def_id)
		or BuildCatalog.is_door(def_id)
		or SecurityLanes.is_part(def_id)
	)


## The template of room `room_id` on `grid`, or null when there is no such room.
static func capture(grid: BuildGrid, room_id: int) -> RoomTemplate:
	var room := grid.get_room(room_id)
	if room.is_empty():
		return null
	var rect: Rect2i = room["rect"]
	var template := RoomTemplate.new()
	template.room_type = room["type"]
	template.size = rect.size
	var type_name := RoomTypes.get_type(template.room_type).display_name
	template.name = "%s %dx%d" % [type_name, rect.size.x, rect.size.y]
	for y in rect.size.y:
		for x in rect.size.x:
			var at := rect.position + Vector2i(x, y)
			template.floors.append(Vector2i(grid.floor_at(at), grid.zone_at(at)))
	var ids := grid.object_ids()
	ids.sort()
	for object_id in ids:
		var record := grid.get_object(object_id)
		var def_id: StringName = record["def"]
		if not keeps_piece(def_id):
			continue
		var anchor: Vector2i = record["anchor"]
		var facing: int = record["facing"]
		if _inside(BuildCatalog.get_def(def_id).footprint(anchor, facing), rect):
			template.pieces.append(
				{"def": _kept_def(def_id), "anchor": anchor - rect.position, "facing": facing}
			)
	return template


## The room's size after `turns` quarter turns.
func turned_size(turns: int) -> Vector2i:
	return Vector2i(size.y, size.x) if posmod(turns, 2) == 1 else size


## The room's rectangle when pasted with its centre cell on `centre` after
## `turns` quarter turns.
func rect_at(centre: Vector2i, turns: int) -> Rect2i:
	var turned := turned_size(turns)
	return Rect2i(centre - (turned - Vector2i.ONE) / 2, turned)


## The paste as edits: with `grid`, PAINT_FLOOR for each of the room's cells
## it has no floor on (none where floor already lies), then PLACE_ROOM on
## rect_at(centre, turns), then each piece turned with the room.
func plan(centre: Vector2i, turns: int, grid: BuildGrid = null) -> Array[BuildEdit]:
	var rect := rect_at(centre, turns)
	var shift := rect.position + _turn_offset(turns)
	var edits: Array[BuildEdit] = []
	for y in size.y if grid != null else 0:
		for x in size.x:
			var at := shift + BuildObjectDef.rotate_offset(Vector2i(x, y), turns)
			var laid := floors[y * size.x + x]
			if not grid.in_bounds(at) or grid.floor_at(at) == BuildGrid.FLOOR_NONE:
				edits.append(BuildEdit.paint_floor(at, laid.x, laid.y))
	edits.append(BuildEdit.place_room(rect, room_type))
	for piece in pieces:
		var anchor: Vector2i = piece["anchor"]
		var edit := BuildEdit.place_object(
			piece["def"],
			shift + BuildObjectDef.rotate_offset(anchor, turns),
			posmod(int(piece["facing"]) + turns, 4)
		)
		edits.append(edit)
	return edits


## What a paste on bare ground costs: the pieces at their catalog prices and
## the floor of every cell, PriceTable.NO_PRICE when a piece has none. The
## room itself is free; floor already laid is not charged (plan()).
func price() -> int:
	var total := floors.size() * PriceTable.price_of_floor()
	for piece in pieces:
		var each := PriceTable.price_of_object(piece["def"])
		if each == PriceTable.NO_PRICE:
			return PriceTable.NO_PRICE
		total += each
	return total


func to_dict() -> Dictionary:
	var floor_saved: Array = []
	for cell in floors:
		floor_saved.append([cell.x, cell.y])
	var saved: Array = []
	for piece in pieces:
		var anchor: Vector2i = piece["anchor"]
		saved.append(
			{"def": String(piece["def"]), "anchor": [anchor.x, anchor.y], "facing": piece["facing"]}
		)
	return {
		"name": name,
		"type": String(room_type),
		"size": [size.x, size.y],
		"pieces": saved,
		"floor": floor_saved,
	}


## A template from a to_dict() dictionary, including one that went through
## JSON, or {"error": reason}: {"template": RoomTemplate} on success.
static func from_dict(data: Variant) -> Dictionary:
	if typeof(data) != TYPE_DICTIONARY:
		return {"error": "a template must be a dictionary"}
	for key in ["name", "type", "size", "pieces", "floor"]:
		if not (data as Dictionary).has(key):
			return {"error": "a template needs '%s'" % key}
	if (data as Dictionary).size() != 5:
		return {"error": "a template has an unknown key"}
	if typeof(data["name"]) != TYPE_STRING or typeof(data["type"]) != TYPE_STRING:
		return {"error": "a template's name and type must be text"}
	if RoomTypes.get_type(StringName(data["type"])) == null:
		return {"error": "unknown room type '%s'" % data["type"]}
	var size_value: Variant = _cell(data["size"], 1, MAX_SIDE)
	if size_value == null:
		return {"error": "a template's size must be two whole numbers from 1 to %d" % MAX_SIDE}
	if typeof(data["pieces"]) != TYPE_ARRAY or (data["pieces"] as Array).size() > MAX_PIECES:
		return {"error": "a template's pieces must be a list of at most %d" % MAX_PIECES}
	var floor_problem := _floor_problem(data["floor"], size_value)
	if floor_problem != "":
		return {"error": floor_problem}
	var template := RoomTemplate.new()
	template.name = data["name"]
	for entry in data["floor"]:
		template.floors.append(Vector2i(int(entry[0]), int(entry[1])))
	template.room_type = StringName(data["type"])
	template.size = size_value
	for entry in data["pieces"]:
		var piece: Variant = _piece(entry, template.size)
		if typeof(piece) == TYPE_STRING:
			return {"error": piece}
		template.pieces.append(piece)
	return {"template": template}


## One saved piece as a pieces entry, or the reason it is refused.
static func _piece(entry: Variant, room_size: Vector2i) -> Variant:
	if typeof(entry) != TYPE_DICTIONARY or (entry as Dictionary).size() != 3:
		return "a piece must be a dictionary of def, anchor and facing"
	if not (entry.has("def") and entry.has("anchor") and entry.has("facing")):
		return "a piece must be a dictionary of def, anchor and facing"
	if typeof(entry["def"]) != TYPE_STRING or not keeps_piece(StringName(entry["def"])):
		return "a template cannot hold the piece '%s'" % str(entry["def"])
	var anchor: Variant = _cell(entry["anchor"], -MAX_SIDE, MAX_SIDE)
	if anchor == null or not WholeNumber.is_whole(entry["facing"]):
		return "a piece's anchor and facing must be whole numbers"
	var facing := int(entry["facing"])
	if facing < 0 or facing > 3:
		return "a piece's facing must be 0 to 3"
	var def := BuildCatalog.get_def(StringName(entry["def"]))
	if not _inside(def.footprint(anchor, facing), Rect2i(Vector2i.ZERO, room_size)):
		return "a piece of '%s' lies outside its room" % entry["def"]
	return {"def": _kept_def(StringName(entry["def"])), "anchor": anchor, "facing": facing}


## Why a saved floor list does not fit a room of `room_size`, or "".
static func _floor_problem(value: Variant, room_size: Vector2i) -> String:
	var count := room_size.x * room_size.y
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != count:
		return "a template's floor must be a list of %d cells" % count
	for entry in value:
		var cell: Variant = _cell(entry, 0, BuildGrid.MAX_ZONE_ID)
		if cell == null or cell.x < 1 or cell.x > BuildGrid.MAX_FLOOR_TYPE:
			return "a template's floor cells must be [floor type, zone]"
	return ""


## A belt piece is kept as a plain belt (its shape comes from its links).
static func _kept_def(def_id: StringName) -> StringName:
	return BeltShaper.BELT if BuildCatalog.is_belt(def_id) else def_id


## A [x, y] pair of whole numbers from `low` to `high` as a Vector2i, or null.
static func _cell(value: Variant, low: int, high: int) -> Variant:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 2:
		return null
	for n in value:
		if not WholeNumber.is_whole(n) or int(n) < low or int(n) > high:
			return null
	return Vector2i(int(value[0]), int(value[1]))


static func _inside(cells: Array[Vector2i], rect: Rect2i) -> bool:
	for cell in cells:
		if not rect.has_point(cell):
			return false
	return true


## What moves a turned room's cells back to start at (0, 0): a cell (x, y) of
## the room turned by BuildObjectDef.rotate_offset() lands this far from the
## turned rectangle's north-west cell.
func _turn_offset(turns: int) -> Vector2i:
	var low := Vector2i(MAX_SIDE, MAX_SIDE)
	var far := size - Vector2i.ONE
	for corner in [Vector2i.ZERO, Vector2i(far.x, 0), Vector2i(0, far.y), far]:
		var turned := BuildObjectDef.rotate_offset(corner, turns)
		low = Vector2i(mini(low.x, turned.x), mini(low.y, turned.y))
	return -low
