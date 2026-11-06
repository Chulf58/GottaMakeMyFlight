class_name GridReach
extends RefCounted
## The staff reach rule of a BuildGrid: whether a list of edits would cut a
## staff spot off from every entrance. Static helpers split out of
## build_grid.gd (decision
## how-to-split-a-big-gdscript-file-static-helper-classes-that); the grid is
## the first argument, and these write its data directly, then put it back
## (_reach_after()). BuildGrid.staff_reach_problem(), apply_batch() and
## apply_sequence() call them.


static func staff_reach_problem(grid: BuildGrid, edits: Array[BuildEdit]) -> BuildResult:
	grid._last_after_known = false
	if not grid.check_staff_reach or grid._reach_cleared:
		return null
	var fresh: Array[Vector2i] = []
	var narrows := false
	var parts := false
	for edit in edits:
		match edit.kind:
			BuildEdit.Kind.PLACE_OBJECT:
				narrows = true
				parts = parts or SecurityLanes.is_part(edit.def_id)
				var spot := StaffSpots.cell_of(edit.def_id, edit.cell, edit.facing)
				if spot != BuildObjectDef.NO_CELL:
					fresh.append(spot)
			BuildEdit.Kind.REMOVE_FLOOR, BuildEdit.Kind.PLACE_WALL:
				narrows = true
			BuildEdit.Kind.REMOVE_OBJECT:
				narrows = narrows or _is_entrance(grid, edit.object_id)
	if not narrows:
		return null
	var before := grid.staff_reach()
	if before.is_empty() or not (parts or _any_spot_reached(grid, before, fresh)):
		return null
	var lane_spots := {}
	grid._last_after = _reach_after(grid, edits, lane_spots)
	grid._last_after_known = true
	return _reach_problem(grid, before, grid._last_after, fresh, lane_spots)


## Whether applying all of `edits` leaves every staff spot staff reach now
## (and every spot an edit places whose cell they reach now) still reached,
## judged with one flood: then no edit in the batch can break the reach rule,
## since the batch only takes cells away and each step leaves at least what
## the whole batch leaves. False, so each edit is checked on its own, when
## the batch places or removes an entrance, or places an object the grid
## refuses as it stands or on a cell an earlier placement in it takes. Edits
## that only add cells (floor, wall removals, rooms, belt reshapes) are left
## out of the trial; a spot that only they bring into reach is judged with the
## batch as one action.
static func batch_keeps_reach(grid: BuildGrid, edits: Array[BuildEdit]) -> bool:
	var trial: Array[BuildEdit] = []
	var fresh: Array[Vector2i] = []
	var claimed := {}
	var parts := false
	for edit in edits:
		match edit.kind:
			BuildEdit.Kind.REMOVE_FLOOR, BuildEdit.Kind.PLACE_WALL:
				if not grid.in_bounds(edit.cell) or edit.side < 0 or edit.side > 3:
					return false
				trial.append(edit)
			BuildEdit.Kind.REMOVE_OBJECT:
				if _is_entrance(grid, edit.object_id):
					return false
			BuildEdit.Kind.PLACE_OBJECT:
				if not _trial_placement(grid, edit, claimed):
					return false
				trial.append(edit)
				parts = parts or SecurityLanes.is_part(edit.def_id)
				var spot := StaffSpots.cell_of(edit.def_id, edit.cell, edit.facing)
				if spot != BuildObjectDef.NO_CELL:
					fresh.append(spot)
	if trial.is_empty():
		return true
	var before := grid.staff_reach()
	if before.is_empty() or not (parts or _any_spot_reached(grid, before, fresh)):
		return true
	var lane_spots := {}
	var after := _reach_after(grid, trial, lane_spots)
	return _reach_problem(grid, before, after, fresh, lane_spots) == null


## Whether staff reach (`before`) some staff spot now: a station's, a whole
## lane's officer spot, or one of the `fresh` spots of stations being placed.
static func _any_spot_reached(grid: BuildGrid, before: Dictionary, fresh: Array[Vector2i]) -> bool:
	return grid._spots.any_reached(before, fresh) or grid._recognised_lanes().any_reached(before)


## The staff reach rule on a station's spot (StaffSpots.reach_problem()), on
## a whole lane's officer spots (SecurityLanes.reach_problem()), then on the
## officer spots of lanes the edits complete (`lane_spots`, spot -> arch, from
## _reach_after()): one staff reach now that `after` loses is refused, naming
## the arch when it already stands, as a placed station's spot names none.
static func _reach_problem(
	grid: BuildGrid,
	before: Dictionary,
	after: Dictionary,
	fresh: Array[Vector2i],
	lane_spots: Dictionary
) -> BuildResult:
	var problem := grid._spots.reach_problem(before, after, fresh)
	if problem == null:
		problem = grid._recognised_lanes().reach_problem(before, after)
	if problem != null:
		return problem
	for spot: Vector2i in lane_spots:
		if before.has(spot) and not after.has(spot):
			var arch: int = lane_spots[spot]
			return BuildResult.refused(
				BuildResult.Reason.STAFF_SPOT, arch if grid._objects.has(arch) else 0
			)
	return null


## Whether a placement can join batch_keeps_reach()'s trial: not an
## entrance, accepted on the grid as it stands, and on cells (footprint and
## interaction cell) no earlier placement in `claimed` takes. Claims its cells.
static func _trial_placement(grid: BuildGrid, edit: BuildEdit, claimed: Dictionary) -> bool:
	if edit.def_id == StaffSpots.ENTRANCE:
		return false
	if not GridRules.check_place_object(grid, edit.def_id, edit.cell, edit.facing).ok:
		return false
	var def := BuildCatalog.get_def(edit.def_id)
	var cells := def.footprint(edit.cell, edit.facing)
	var front := def.interaction_cell(edit.cell, edit.facing)
	if front != BuildObjectDef.NO_CELL:
		cells.append(front)
	if cells.any(func(cell: Vector2i) -> bool: return claimed.has(cell)):
		return false
	for cell in cells:
		claimed[cell] = true
	return true


static func _is_entrance(grid: BuildGrid, object_id: int) -> bool:
	return grid._objects.has(object_id) and grid._objects[object_id]["def"] == StaffSpots.ENTRANCE


## StaffSpots.reach() of the grid as `edits` would leave it. Each edit that can
## take cells away is written into the grid data (an object under an unused
## id), the flood runs, and every write is undone in reverse order, so the
## grid is exactly as it was. Nothing is emitted and the A* graph is untouched.
## When an edit places a lane part, the lanes are recognised on the written
## grid too, and the officer spots of lanes whole there and not as the grid
## stands go into `lane_spots` (spot -> arch).
static func _reach_after(
	grid: BuildGrid, edits: Array[BuildEdit], lane_spots: Dictionary
) -> Dictionary:
	var standing := grid._recognised_lanes()
	var parts := false
	var undo := []
	var trial_id := grid._next_object_id
	for edit in edits:
		match edit.kind:
			BuildEdit.Kind.REMOVE_FLOOR:
				undo.append([edit, grid._floor[grid._index(edit.cell)]])
				grid._floor[grid._index(edit.cell)] = BuildGrid.FLOOR_NONE
			BuildEdit.Kind.PLACE_WALL:
				undo.append([edit, grid._wall_value(edit.cell, edit.side)])
				grid._set_wall(edit.cell, edit.side, edit.wall_kind)
			BuildEdit.Kind.PLACE_OBJECT:
				undo.append([edit, trial_id])
				grid._insert_object(trial_id, edit.def_id, edit.cell, edit.facing)
				trial_id += 1
				parts = parts or SecurityLanes.is_part(edit.def_id)
			BuildEdit.Kind.REMOVE_OBJECT:
				# Only an entrance's removal takes cells away; it has no spot.
				if _is_entrance(grid, edit.object_id):
					undo.append([edit, grid._objects[edit.object_id]])
					grid._erase_object(edit.object_id)
	var reach := StaffSpots.reach(grid)
	if parts:
		var trial_lanes := SecurityLanes.new()
		trial_lanes.rebuild(grid)
		lane_spots.merge(trial_lanes.new_officer_spots(standing))
	for i in range(undo.size() - 1, -1, -1):
		var edit: BuildEdit = undo[i][0]
		match edit.kind:
			BuildEdit.Kind.REMOVE_FLOOR:
				grid._floor[grid._index(edit.cell)] = undo[i][1]
			BuildEdit.Kind.PLACE_WALL:
				grid._set_wall(edit.cell, edit.side, undo[i][1])
			BuildEdit.Kind.PLACE_OBJECT:
				grid._erase_object(undo[i][1])
			BuildEdit.Kind.REMOVE_OBJECT:
				var record: Dictionary = undo[i][1]
				grid._insert_object(
					edit.object_id, record["def"], record["anchor"], record["facing"]
				)
				grid._objects[edit.object_id] = record
	return reach
