class_name EnclosureKit
extends RefCounted
## Test support for enclosure (TerminalEnclosure): passengers use only floor
## that walls close in, so a test layout walls its floor in before passengers
## or facility layouts look at it.


## Puts a plain wall on every floor edge that faces a cell with no floor (or
## the grid border) and has no wall yet, except an entrance or exit door
## object's back edge, which the door fills. Asserts every wall is accepted.
## Returns how many walls it placed.
static func close_floor(grid: BuildGrid) -> int:
	var backs := {}
	for way in DoorPlacement.ways_out(grid):
		var anchor: Vector2i = way[0]
		backs[Vector3i(anchor.x, anchor.y, BuildGrid.SIDE_STEP.find(way[1]))] = true
	var edits: Array[BuildEdit] = []
	for y in grid.size.y:
		for x in grid.size.x:
			var cell := Vector2i(x, y)
			if grid.floor_at(cell) == BuildGrid.FLOOR_NONE:
				continue
			for side in 4:
				var beyond: Vector2i = cell + BuildGrid.SIDE_STEP[side]
				if grid.floor_at(beyond) != BuildGrid.FLOOR_NONE:
					continue
				if grid.has_wall(cell, side) or backs.has(Vector3i(x, y, side)):
					continue
				edits.append(BuildEdit.place_wall(cell, side))
	for result in grid.apply_batch(edits):
		assert(result.ok, "enclosing wall refused: %s" % result.reason_text())
	return edits.size()


## Whether every floored cell of `grid` is indoor.
static func all_indoor(grid: BuildGrid) -> bool:
	for y in grid.size.y:
		for x in grid.size.x:
			var cell := Vector2i(x, y)
			if grid.floor_at(cell) != BuildGrid.FLOOR_NONE and not grid.is_indoor(cell):
				return false
	return true


## Puts a plain wall on every grid-border edge that has no wall yet, except an
## entrance or exit door object's back edge, so every floored cell inside the
## border is indoor, floor painted later included (the way the Toon shell's
## facade once closed the border in). Asserts every wall is accepted. Returns
## how many walls it placed.
static func wall_border(grid: BuildGrid) -> int:
	var backs := {}
	for way in DoorPlacement.ways_out(grid):
		var anchor: Vector2i = way[0]
		backs[Vector3i(anchor.x, anchor.y, BuildGrid.SIDE_STEP.find(way[1]))] = true
	var edits: Array[BuildEdit] = []
	for y in grid.size.y:
		for x in grid.size.x:
			var cell := Vector2i(x, y)
			for side in 4:
				if grid.in_bounds(cell + BuildGrid.SIDE_STEP[side]):
					continue
				if grid.has_wall(cell, side) or backs.has(Vector3i(x, y, side)):
					continue
				edits.append(BuildEdit.place_wall(cell, side))
	for result in grid.apply_batch(edits):
		assert(result.ok, "border wall refused: %s" % result.reason_text())
	return edits.size()
