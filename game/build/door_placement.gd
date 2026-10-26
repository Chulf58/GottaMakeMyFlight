class_name DoorPlacement
extends RefCounted
## The build tools' rules for entrance and exit door objects. BuildGrid allows
## a door object anywhere; these rules keep one on the terminal's edge with
## its way out open, pick its facing when the player has not turned it, and
## let it take the place of a plain wall. BuildMode calls them for the ghost
## and the click alike.


## The grid step from a door's cell out through its back edge.
static func back_step(facing: int) -> Vector2i:
	return BuildObjectDef.rotate_offset(Vector2i(0, -1), facing)


## BuildGrid.validate(), plus the edge rule for entrances and exits: a new one
## stands on the terminal's edge facing in (outside_door_problem()), and a
## standing one keeps its way out open: no wall of any kind on its back edge
## and no floor on the cell beyond.
static func check(grid: BuildGrid, edit: BuildEdit) -> BuildResult:
	var result := grid.validate(edit)
	if not result.ok:
		return result
	match edit.kind:
		BuildEdit.Kind.PLACE_OBJECT:
			if BuildCatalog.is_door(edit.def_id):
				return outside_door_problem(grid, edit.cell, edit.facing)
		BuildEdit.Kind.PLACE_WALL:
			if on_a_way_out(grid, edit.cell, edit.side):
				return BuildResult.refused(BuildResult.Reason.DOOR_WALLED)
		BuildEdit.Kind.PAINT_FLOOR:
			if beyond_a_door(grid, edit.cell):
				return BuildResult.refused(BuildResult.Reason.DOOR_NOT_ON_EDGE)
	return result


## Whether an entrance or exit door object at `anchor` and `facing` stands on
## the terminal's edge: its back edge (the way out) has no floor beyond it and
## no wall on it, the same test TerminalLayout.is_exit_open() makes. A plain
## wall there is allowed when the wall could be removed on its own (it holds
## no door wall), because placing the door takes it down (edits_for()).
## Glass and door walls still refuse.
static func outside_door_problem(grid: BuildGrid, anchor: Vector2i, facing: int) -> BuildResult:
	var out := back_step(facing)
	if grid.floor_at(anchor + out) != BuildGrid.FLOOR_NONE:
		return BuildResult.refused(BuildResult.Reason.DOOR_NOT_ON_EDGE)
	var side := BuildGrid.SIDE_STEP.find(out)
	match grid.wall_kind(anchor, side):
		BuildGrid.WallKind.NONE:
			return BuildResult.accepted()
		BuildGrid.WallKind.PLAIN:
			return grid.validate(BuildEdit.remove_wall(anchor, side))
	return BuildResult.refused(BuildResult.Reason.DOOR_WALLED)


## The facing a `def_id` door at the cell under `point` takes when the player
## has not turned it. It prefers a facing check() accepts, then one whose back
## has no floor beyond it; among equals, the one whose back edge is nearest
## `point`. With neither, it returns `fallback`, so the refusal says the cell
## is not on the edge.
static func auto_facing(grid: BuildGrid, def_id: StringName, point: Vector3, fallback: int) -> int:
	var cell := grid.world_to_cell(point)
	var offset := point - grid.cell_to_world(cell)
	var best := fallback
	var best_tier := 2
	var best_distance := INF
	for turn in 4:
		var out := back_step(turn)
		var tier := 2
		if check(grid, BuildEdit.place_object(def_id, cell, turn)).ok:
			tier = 0
		elif grid.floor_at(cell + out) == BuildGrid.FLOOR_NONE:
			tier = 1
		var distance := 0.5 - (offset.x * out.x + offset.z * out.y)
		if tier < best_tier or (tier == best_tier and tier < 2 and distance < best_distance):
			best = turn
			best_tier = tier
			best_distance = distance
	return best


## The edits that carry out an edit check() accepted, in order. An entrance or
## exit with a plain wall on its back edge first removes that wall, which
## cannot make the door's own placement invalid. Any other edit is itself.
static func edits_for(grid: BuildGrid, edit: BuildEdit) -> Array[BuildEdit]:
	var plan: Array[BuildEdit] = [edit]
	if edit.kind != BuildEdit.Kind.PLACE_OBJECT or not BuildCatalog.is_door(edit.def_id):
		return plan
	var side := BuildGrid.SIDE_STEP.find(back_step(edit.facing))
	if grid.wall_kind(edit.cell, side) == BuildGrid.WallKind.PLAIN:
		plan.push_front(BuildEdit.remove_wall(edit.cell, side))
	return plan


## Each standing entrance or exit as [anchor, outward step].
static func ways_out(grid: BuildGrid) -> Array:
	var out := []
	for object_id in grid.object_ids():
		var record := grid.get_object(object_id)
		if BuildCatalog.is_door(record["def"]):
			out.append([record["anchor"], back_step(record["facing"])])
	return out


## Whether the edge (from either cell beside it) is a door's back edge.
static func on_a_way_out(grid: BuildGrid, cell: Vector2i, side: int) -> bool:
	var step := BuildGrid.SIDE_STEP[side]
	for way in ways_out(grid):
		if (cell == way[0] and step == way[1]) or (cell == way[0] + way[1] and step == -way[1]):
			return true
	return false


## Whether `cell` is the cell beyond a standing door's back edge.
static func beyond_a_door(grid: BuildGrid, cell: Vector2i) -> bool:
	for way in ways_out(grid):
		if cell == way[0] + way[1]:
			return true
	return false
