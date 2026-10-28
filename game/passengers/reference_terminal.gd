class_name ReferenceTerminal
extends RefCounted
## The one terminal layout the tests, the boarding-window measurement and the
## plate probe share, on the default 64x64 grid. Cells x 10-21, y 2-17 (world
## x -22 to -10, z -30 to -14): a landside hall with two desks and the
## entrance on the south edge, a wall across y = 9 with two scanners in it,
## and an airside gate with four seat rows and the exit on the north edge.
## In a terminal shell (the starter terminal's layout) the same rooms stretch
## from the shell's gate door C on the north edge to its landside door B on the
## south edge, so passengers use the real door routes.

const FLOOR_MIN := Vector2i(10, 2)
const FLOOR_MAX := Vector2i(21, 17)
## The wall runs along the north edge of this row.
const DIVIDER_Y := 9
const AIRSIDE_MAX_Y := 8
const ENTRANCE_CELL := Vector2i(18, 17)
const EXIT_CELL := Vector2i(20, 2)
const SCANNER_XS: Array[int] = [17, 19]
## The Toon doors the shell layout stands on, by their porch sign.
const SHELL_ENTRANCE_LABEL := "B"
const SHELL_EXIT_LABEL := "C"


## The layout's edits. With a `shell`, the entrance and exit stand on its
## doors B and C (their cells and facings) and the floor runs between them;
## empty (with an error) when the shell has no such door.
static func edits(shell: ShellDefinition = null) -> Array[BuildEdit]:
	var floor_min := FLOOR_MIN
	var floor_max := FLOOR_MAX
	var entrance := ENTRANCE_CELL
	var entrance_facing := 2
	var exit_cell := EXIT_CELL
	var exit_facing := 0
	if shell != null:
		var door_in := _door(shell, ShellDoorConnection.Kind.LANDSIDE, SHELL_ENTRANCE_LABEL)
		var door_out := _door(shell, ShellDoorConnection.Kind.AIRSIDE, SHELL_EXIT_LABEL)
		if door_in == null or door_out == null:
			push_error("ReferenceTerminal: the shell has no door B and gate C")
			return []
		entrance = door_in.cell
		entrance_facing = door_in.facing
		exit_cell = door_out.cell
		exit_facing = door_out.facing
		floor_min.y = exit_cell.y
		floor_max.y = entrance.y
	var out: Array[BuildEdit] = []
	for y in range(floor_min.y, floor_max.y + 1):
		for x in range(floor_min.x, floor_max.x + 1):
			out.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	for x in range(floor_min.x, floor_max.x + 1):
		if x != exit_cell.x:
			out.append(BuildEdit.place_wall(Vector2i(x, floor_min.y), BuildGrid.Side.NORTH))
		if not SCANNER_XS.has(x):
			out.append(BuildEdit.place_wall(Vector2i(x, DIVIDER_Y), BuildGrid.Side.NORTH))
	for y in range(floor_min.y, floor_max.y + 1):
		out.append(BuildEdit.place_wall(Vector2i(floor_min.x, y), BuildGrid.Side.WEST))
		out.append(BuildEdit.place_wall(Vector2i(floor_max.x, y), BuildGrid.Side.EAST))
	out.append(BuildEdit.place_object(&"checkin_desk", Vector2i(11, 11), 0))
	out.append(BuildEdit.place_object(&"checkin_desk", Vector2i(14, 11), 0))
	for x in SCANNER_XS:
		out.append(BuildEdit.place_object(&"security_scanner", Vector2i(x, DIVIDER_Y - 1), 0))
	for anchor in [Vector2i(11, 3), Vector2i(14, 3), Vector2i(11, 6), Vector2i(14, 6)]:
		out.append(BuildEdit.place_object(&"seat_row", anchor, 0))
	out.append(BuildEdit.place_object(&"entrance_door", entrance, entrance_facing))
	out.append(BuildEdit.place_object(&"exit_door", exit_cell, exit_facing))
	return out


## Applies edits(shell) to a fresh grid. Pushes an error and returns false
## at the first refused edit, or at once when the shell has no door B and gate C.
static func build(grid: BuildGrid, shell: ShellDefinition = null) -> bool:
	var plan := edits(shell)
	if plan.is_empty():
		return false
	for edit in plan:
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


static func _door(shell: ShellDefinition, kind: int, label: String) -> ShellDoorConnection:
	for connection in shell.connections:
		if connection.kind == kind and connection.label == label:
			return connection
	return null


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
