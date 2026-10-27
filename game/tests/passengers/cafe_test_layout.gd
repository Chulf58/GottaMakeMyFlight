class_name CafeTestLayout
extends RefCounted
## The reference terminal with two cafes beside it, for the cafe tests: floor
## east of the terminal (x 22-27, y 3-16), the security divider carried
## across it, openings in the terminal's east wall, an airside cafe room
## (x 22-27, y 3-8) and a landside one (x 22-27, y 10-15). Each has a counter
## along its north side with a 4-cell lane south from its order spot, and one
## table (two seats) to the east of the lane.

const AIRSIDE_ROOM := Rect2i(22, 3, 6, 6)
const LANDSIDE_ROOM := Rect2i(22, 10, 6, 6)
const FLOOR := Rect2i(22, 3, 6, 14)
const AIR_COUNTER := Vector2i(23, 3)
const AIR_TABLE := Vector2i(24, 6)
const LAND_COUNTER := Vector2i(23, 10)
const LAND_TABLE := Vector2i(24, 13)
## A second table per cafe, for queue tests that need more than two seats.
const AIR_TABLE_2 := Vector2i(24, 4)
const LAND_TABLE_2 := Vector2i(24, 11)


## A grid holding the reference terminal and both cafes, and their ids:
## {"air_room", "land_room", "air_counter", "land_counter", "air_table",
## "land_table"} (and "air_table_2", "land_table_2" with `extra_tables`).
static func build(grid: BuildGrid, extra_tables := false) -> Dictionary:
	var built := ReferenceTerminal.build(grid)
	assert(built, "reference terminal refused")
	var edits: Array[BuildEdit] = []
	for y in range(FLOOR.position.y, FLOOR.end.y):
		for x in range(FLOOR.position.x, FLOOR.end.x):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	for x in range(FLOOR.position.x, FLOOR.end.x):
		var cell := Vector2i(x, ReferenceTerminal.DIVIDER_Y)
		edits.append(BuildEdit.place_wall(cell, BuildGrid.Side.NORTH))
	for y in [4, 5, 6, 7, 11, 12, 13, 14, 15]:
		edits.append(BuildEdit.remove_wall(Vector2i(21, y), BuildGrid.Side.EAST))
	for result in grid.apply_batch(edits):
		assert(result.ok, "cafe layout edit refused: %s" % result.reason_text())
	var ids := {
		"air_room": _apply(grid, BuildEdit.place_room(AIRSIDE_ROOM, &"cafe")).room_id,
		"land_room": _apply(grid, BuildEdit.place_room(LANDSIDE_ROOM, &"cafe")).room_id,
		"air_counter": _place(grid, &"cafe_counter", AIR_COUNTER),
		"land_counter": _place(grid, &"cafe_counter", LAND_COUNTER),
		"air_table": _place(grid, &"cafe_table", AIR_TABLE),
		"land_table": _place(grid, &"cafe_table", LAND_TABLE),
	}
	if extra_tables:
		ids["air_table_2"] = _place(grid, &"cafe_table", AIR_TABLE_2)
		ids["land_table_2"] = _place(grid, &"cafe_table", LAND_TABLE_2)
	return ids


static func _place(grid: BuildGrid, def_id: StringName, anchor: Vector2i) -> int:
	return _apply(grid, BuildEdit.place_object(def_id, anchor, 0)).object_id


static func _apply(grid: BuildGrid, edit: BuildEdit) -> BuildResult:
	var result := grid.apply(edit)
	assert(result.ok, "cafe layout edit refused: %s" % result.reason_text())
	return result
