class_name ReferenceTerminal
extends RefCounted
## The one terminal layout the tests, the boarding-window measurement and the
## plate probe share, on the default 64x64 grid. Cells x 10-21, y 2-17 (world
## x -22 to -10, z -30 to -14): a landside hall with two desks and the
## entrance on the south edge, a wall across y = 9 with two scanners in it,
## and an airside gate with four seat rows and the exit on the north edge.

const FLOOR_MIN := Vector2i(10, 2)
const FLOOR_MAX := Vector2i(21, 17)
## The wall runs along the north edge of this row.
const DIVIDER_Y := 9
const AIRSIDE_MAX_Y := 8
const ENTRANCE_CELL := Vector2i(18, 17)
const EXIT_CELL := Vector2i(20, 2)
const SCANNER_XS: Array[int] = [17, 19]


static func edits() -> Array[BuildEdit]:
	var out: Array[BuildEdit] = []
	for y in range(FLOOR_MIN.y, FLOOR_MAX.y + 1):
		for x in range(FLOOR_MIN.x, FLOOR_MAX.x + 1):
			out.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	for x in range(FLOOR_MIN.x, FLOOR_MAX.x + 1):
		if x != EXIT_CELL.x:
			out.append(BuildEdit.place_wall(Vector2i(x, FLOOR_MIN.y), BuildGrid.Side.NORTH))
		if not SCANNER_XS.has(x):
			out.append(BuildEdit.place_wall(Vector2i(x, DIVIDER_Y), BuildGrid.Side.NORTH))
	for y in range(FLOOR_MIN.y, FLOOR_MAX.y + 1):
		out.append(BuildEdit.place_wall(Vector2i(FLOOR_MIN.x, y), BuildGrid.Side.WEST))
		out.append(BuildEdit.place_wall(Vector2i(FLOOR_MAX.x, y), BuildGrid.Side.EAST))
	out.append(BuildEdit.place_object(&"checkin_desk", Vector2i(11, 11), 0))
	out.append(BuildEdit.place_object(&"checkin_desk", Vector2i(14, 11), 0))
	for x in SCANNER_XS:
		out.append(BuildEdit.place_object(&"security_scanner", Vector2i(x, DIVIDER_Y - 1), 0))
	for anchor in [Vector2i(11, 3), Vector2i(14, 3), Vector2i(11, 6), Vector2i(14, 6)]:
		out.append(BuildEdit.place_object(&"seat_row", anchor, 0))
	out.append(BuildEdit.place_object(&"entrance_door", ENTRANCE_CELL, 2))
	out.append(BuildEdit.place_object(&"exit_door", EXIT_CELL, 0))
	return out


## Applies edits() to a fresh default grid. Pushes an error and returns false
## at the first refused edit.
static func build(grid: BuildGrid) -> bool:
	for edit in edits():
		var result := grid.apply(edit)
		if not result.ok:
			push_error(
				(
					"ReferenceTerminal: edit %d at %s refused: %s"
					% [edit.kind, edit.cell, result.reason_text()]
				)
			)
			return false
	return true


## The grid's object ids by kind, each list in id order.
static func object_ids(grid: BuildGrid) -> Dictionary:
	var out := {"desks": [], "scanners": [], "seats": [], "entrances": [], "exits": []}
	var kinds := {
		&"checkin_desk": "desks",
		&"security_scanner": "scanners",
		&"seat_row": "seats",
		&"entrance_door": "entrances",
		&"exit_door": "exits",
	}
	var ids := grid.object_ids()
	ids.sort()
	for id in ids:
		(out[kinds[StringName(grid.get_object(id)["def"])]] as Array).append(id)
	return out
