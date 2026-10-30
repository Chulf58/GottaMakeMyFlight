class_name BackOfHouseView
extends RefCounted
## The view penalty of back-of-house pieces (decision back-of-house-view-penalty-
## bins-cost-1-calm-and-bag-rooms-2): a passenger who can see a bin or a bag room
## from within REACH cells of it loses `penalty` calm points, which DecorEffect
## subtracts from the decor calm before the MAX_CALM cap. A bin costs 1 and a
## bag room 2, so a bin cancels a bush but not a fountain.
##
## What the passenger can see is its own test, separate from the one screens and
## decor calm use (ScreenCoverage.sight_clear, walls only): a plain wall blocks
## the view like it does there, and so does a tall piece standing in the way.
## Glass does not block it, and no short piece does. The tall pieces are the
## trees (the tree and the tree bench), the statue and the tall planter; the
## bush, the fountain and the low plant pot are not on the list.

## Penalty per period by catalog id of a placed piece.
const PIECE_PENALTY := {&"trash_can": 1}
## Penalty of a room, by RoomTypes id.
const ROOM_PENALTY := {&"bag_room": 2}
## Cells from the piece's footprint (or the room's rectangle) within which it is
## seen: the reach of a small decor piece.
const REACH := 2
## Catalog ids of the pieces tall enough to hide a back-of-house piece.
const TALL_IDS: Array[StringName] = [
	&"tree_indoor",
	&"bench_2a_indoor",
	&"statue_indoor",
	&"plant_pot_1a",
]
## Sight samples per cell of distance along the line, an even count so no
## sample falls on a cell corner.
const SAMPLES_PER_CELL := 8


## Every cell that sees back-of-house pieces on `grid`, as cell -> summed penalty.
static func penalties(grid: BuildGrid) -> Dictionary:
	var out := {}
	for id in grid.object_ids():
		var record := grid.get_object(id)
		var def_id: StringName = record["def"]
		var def := BuildCatalog.get_def(def_id)
		if PIECE_PENALTY.has(def_id) and def != null:
			var cells := def.footprint(record["anchor"], record["facing"])
			_add_seen(out, grid, cells, PIECE_PENALTY[def_id])
	for room_id in grid.room_ids():
		var room := grid.get_room(room_id)
		if ROOM_PENALTY.has(room["type"]):
			var rect: Rect2i = room["rect"]
			var cells: Array[Vector2i] = []
			for y in range(rect.position.y, rect.end.y):
				for x in range(rect.position.x, rect.end.x):
					cells.append(Vector2i(x, y))
			_add_seen(out, grid, cells, ROOM_PENALTY[room["type"]])
	return out


## Whether a passenger at `to` sees something standing at `from`: no plain wall
## between them (ScreenCoverage.sight_clear) and no tall piece on the line.
static func can_see(grid: BuildGrid, from: Vector2i, to: Vector2i) -> bool:
	return ScreenCoverage.sight_clear(grid, from, to) and not _tall_between(grid, from, to)


## Whether a tall piece stands on a cell the straight line from the centre of
## `from` to the centre of `to` crosses, the two end cells apart.
static func _tall_between(grid: BuildGrid, from: Vector2i, to: Vector2i) -> bool:
	var delta := to - from
	var count := maxi(absi(delta.x), absi(delta.y)) * SAMPLES_PER_CELL
	for i in count:
		var t := (i + 0.5) / count
		var point := Vector2(from) + Vector2(0.5, 0.5) + Vector2(delta) * t
		var cell := Vector2i(floori(point.x), floori(point.y))
		if cell == from or cell == to:
			continue
		var id := grid.object_at(cell)
		if id != 0 and TALL_IDS.has(grid.get_object(id)["def"]):
			return true
	return false


## Adds `penalty` to every floored cell within REACH of `footprint` that sees
## it, the footprint cells themselves apart.
static func _add_seen(
	out: Dictionary, grid: BuildGrid, footprint: Array[Vector2i], penalty: int
) -> void:
	var low := footprint[0]
	var high := footprint[0]
	for cell in footprint:
		low = Vector2i(mini(low.x, cell.x), mini(low.y, cell.y))
		high = Vector2i(maxi(high.x, cell.x), maxi(high.y, cell.y))
	for y in range(low.y - REACH, high.y + REACH + 1):
		for x in range(low.x - REACH, high.x + REACH + 1):
			var cell := Vector2i(x, y)
			if footprint.has(cell) or not grid.in_bounds(cell):
				continue
			if grid.floor_at(cell) == BuildGrid.FLOOR_NONE:
				continue
			if can_see(grid, cell.clamp(low, high), cell):
				out[cell] = int(out.get(cell, 0)) + penalty
