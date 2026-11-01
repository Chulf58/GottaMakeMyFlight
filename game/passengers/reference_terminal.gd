class_name ReferenceTerminal
extends RefCounted
## The one terminal layout the tests, the boarding-window measurement and the
## plate probe share, on the default 64x64 grid. Cells x 10-21, y 2-17 (world
## x -22 to -10, z -30 to -14): a landside hall with two desks and the
## entrance on the south edge, a wall across y = 9 with two scanners in it,
## and an airside gate with four seat rows and the exit on the north edge.
## Walls close it in on every side, the two door objects filling the gaps
## they stand in, so all its floor is indoor (TerminalEnclosure).
## The debug starter button builds it on the airport site too, where its
## entrance has a walk in from the road and its exit one out to the plane.
## Every function that makes edits takes an `offset` added to every cell: on
## the airport site it is SiteDefinition.starter_offset, which keeps the
## layout at its world place on the grown grid. Those that take a grid use the
## grid's own (offset_on()) when given none, so the debug starter button needs
## no offset of its own.

const FLOOR_MIN := Vector2i(10, 2)
const FLOOR_MAX := Vector2i(21, 17)
## The wall runs along the north edge of this row.
const DIVIDER_Y := 9
const AIRSIDE_MAX_Y := 8
const ENTRANCE_CELL := Vector2i(18, 17)
const EXIT_CELL := Vector2i(20, 2)
const SCANNER_XS: Array[int] = [17, 19]


## `offset`, or with null the offset of `grid`: its site's starter_offset on
## the airport site's grid (SiteGrid), else none.
static func offset_on(grid: BuildGrid, offset: Variant = null) -> Vector2i:
	if offset != null:
		return offset
	var site_grid := grid as SiteGrid
	if site_grid != null and site_grid.site != null:
		return site_grid.site.starter_offset
	return Vector2i.ZERO


## The layout's edits, every cell moved by `offset`.
static func edits(offset := Vector2i.ZERO) -> Array[BuildEdit]:
	var out := _edits()
	for edit in out:
		edit.cell += offset
	return out


static func _edits() -> Array[BuildEdit]:
	var out: Array[BuildEdit] = []
	for y in range(FLOOR_MIN.y, FLOOR_MAX.y + 1):
		for x in range(FLOOR_MIN.x, FLOOR_MAX.x + 1):
			out.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	for x in range(FLOOR_MIN.x, FLOOR_MAX.x + 1):
		if x != EXIT_CELL.x:
			out.append(BuildEdit.place_wall(Vector2i(x, FLOOR_MIN.y), BuildGrid.Side.NORTH))
		if x != ENTRANCE_CELL.x:
			out.append(BuildEdit.place_wall(Vector2i(x, FLOOR_MAX.y), BuildGrid.Side.SOUTH))
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


## The starter shell's edits (decision terminal-growth-and-starter-building-
## move-the-airside-north, point 2): the floor, the outer walls and the two
## doors, with no desks, scanners, seats or divider.
static func shell_edits(offset := Vector2i.ZERO) -> Array[BuildEdit]:
	var out: Array[BuildEdit] = []
	for edit in _edits():
		if not _is_interior(edit):
			edit.cell += offset
			out.append(edit)
	return out


## What the debug starter button adds to the shell: the divider wall and the
## check-in desks, scanners and seat rows.
static func interior_edits(offset := Vector2i.ZERO) -> Array[BuildEdit]:
	var out: Array[BuildEdit] = []
	for edit in _edits():
		if _is_interior(edit):
			edit.cell += offset
			out.append(edit)
	return out


## Adds interior_edits() to a grid that already holds the shell, free like
## build() (a debug layout). The edits go onto a copy first, so a refusal (the
## player built over the interior, or it is already there) returns its reason
## and leaves the grid as it was.
static func fill_interior(grid: BuildGrid, offset: Variant = null) -> BuildResult:
	var at := offset_on(grid, offset)
	var trial := BuildUndo.trial_copy_of(grid)
	if trial == null:
		push_error("ReferenceTerminal: the grid could not be copied for a trial fill")
		return BuildResult.refused(BuildResult.Reason.OUT_OF_BOUNDS)
	var trial_result := trial.apply_sequence(interior_edits(at), Callable())
	if not trial_result.ok:
		return trial_result
	return grid.apply_sequence(interior_edits(at), Callable())


## Applies edits() to a fresh grid. Pushes an error and returns false at the
## first refused edit.
static func build(grid: BuildGrid, offset: Variant = null) -> bool:
	for edit in edits(offset_on(grid, offset)):
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


## The grid's object ids by kind, each list in id order. Every baggage belt
## piece (BuildCatalog.is_belt) is listed under "belts".
static func object_ids(grid: BuildGrid) -> Dictionary:
	var out := {"desks": [], "scanners": [], "seats": [], "entrances": [], "exits": [], "belts": []}
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
		var def := StringName(grid.get_object(id)["def"])
		var kind: String = "belts" if BuildCatalog.is_belt(def) else kinds[def]
		(out[kind] as Array).append(id)
	return out


static func _is_interior(edit: BuildEdit) -> bool:
	match edit.kind:
		BuildEdit.Kind.PLACE_WALL:
			return edit.cell.y == DIVIDER_Y and edit.side == BuildGrid.Side.NORTH
		BuildEdit.Kind.PLACE_OBJECT:
			return edit.def_id != &"entrance_door" and edit.def_id != &"exit_door"
	return false
