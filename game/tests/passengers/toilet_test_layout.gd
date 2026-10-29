class_name ToiletTestLayout
extends RefCounted
## The reference terminal with two toilet rooms beside it, for the toilet
## tests, on the same floor as CafeTestLayout: floor east of the terminal (x
## 22-27, y 3-16), the security divider carried across it, openings in the
## terminal's east wall, an airside toilet room (x 22-27, y 3-8) and a
## landside one (x 22-27, y 10-15). Each has its stalls along its north side,
## facing south, from x 23, and a sink at x 26.

const AIRSIDE_ROOM := Rect2i(22, 3, 6, 6)
const LANDSIDE_ROOM := Rect2i(22, 10, 6, 6)
const FLOOR := Rect2i(22, 3, 6, 14)
const STALL_X := 23
const SINK_X := 26


## A grid holding the reference terminal and both toilet rooms with `stalls`
## stalls each, and their ids: {"air_room", "land_room", "air_stalls",
## "land_stalls" (object ids, west first), "air_sink", "land_sink"}.
static func build(grid: BuildGrid, stalls := 2) -> Dictionary:
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
		assert(result.ok, "toilet layout edit refused: %s" % result.reason_text())
	var ids := {
		"air_room": _apply(grid, BuildEdit.place_room(AIRSIDE_ROOM, &"toilet")).room_id,
		"land_room": _apply(grid, BuildEdit.place_room(LANDSIDE_ROOM, &"toilet")).room_id,
		"air_stalls": [],
		"land_stalls": [],
	}
	for i in stalls:
		ids["air_stalls"].append(_place(grid, &"toilet_stall", Vector2i(STALL_X + i, 3)))
		ids["land_stalls"].append(_place(grid, &"toilet_stall", Vector2i(STALL_X + i, 10)))
	ids["air_sink"] = _place(grid, &"toilet_sink", Vector2i(SINK_X, 3))
	ids["land_sink"] = _place(grid, &"toilet_sink", Vector2i(SINK_X, 10))
	return ids


## Leaves `p` with no need of its own: it starts no toilet or cafe visit on
## its beat, so a test decides when it goes.
static func calm(p: Passenger) -> void:
	p.hunger = 0
	p.cafe_cooldown = 1000000
	p.toilet_need = 0
	p.toilet_cooldown = 1000000


static func _place(grid: BuildGrid, def_id: StringName, anchor: Vector2i) -> int:
	return _apply(grid, BuildEdit.place_object(def_id, anchor, 0)).object_id


static func _apply(grid: BuildGrid, edit: BuildEdit) -> BuildResult:
	var result := grid.apply(edit)
	assert(result.ok, "toilet layout edit refused: %s" % result.reason_text())
	return result
