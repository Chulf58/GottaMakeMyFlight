class_name BuildEdit
extends RefCounted
## One build edit as data. BuildGrid.validate() and BuildGrid.apply() take
## these, so the ghost preview, the click and a snapshot load all run the same
## checks. Undo commands can later be built from the same records.

enum Kind { PAINT_FLOOR, REMOVE_FLOOR, PLACE_WALL, REMOVE_WALL, PLACE_OBJECT, REMOVE_OBJECT }

var kind: Kind = Kind.PAINT_FLOOR
var cell := Vector2i.ZERO
## A BuildGrid.Side, for wall edits.
var side: int = 0
## A BuildGrid.WallKind, for PLACE_WALL.
var wall_kind: int = BuildGrid.WallKind.PLAIN
var floor_type: int = 0
var zone_id: int = 0
var def_id: StringName = &""
var facing: int = 0
var object_id: int = 0


static func paint_floor(at: Vector2i, type: int, zone: int) -> BuildEdit:
	var edit := _make(Kind.PAINT_FLOOR, at)
	edit.floor_type = type
	edit.zone_id = zone
	return edit


static func remove_floor(at: Vector2i) -> BuildEdit:
	return _make(Kind.REMOVE_FLOOR, at)


## A wall of `kind` (a BuildGrid.WallKind) on an edge. On an edge that has a
## wall of another kind, the new kind replaces it.
static func place_wall(
	at: Vector2i, edge_side: int, kind: int = BuildGrid.WallKind.PLAIN
) -> BuildEdit:
	var edit := _make(Kind.PLACE_WALL, at)
	edit.side = edge_side
	edit.wall_kind = kind
	return edit


static func remove_wall(at: Vector2i, edge_side: int) -> BuildEdit:
	var edit := _make(Kind.REMOVE_WALL, at)
	edit.side = edge_side
	return edit


static func place_object(id: StringName, anchor: Vector2i, turn: int) -> BuildEdit:
	var edit := _make(Kind.PLACE_OBJECT, anchor)
	edit.def_id = id
	edit.facing = turn
	return edit


static func remove_object(id: int) -> BuildEdit:
	var edit := _make(Kind.REMOVE_OBJECT, Vector2i.ZERO)
	edit.object_id = id
	return edit


static func _make(edit_kind: Kind, at: Vector2i) -> BuildEdit:
	var edit := BuildEdit.new()
	edit.kind = edit_kind
	edit.cell = at
	return edit
