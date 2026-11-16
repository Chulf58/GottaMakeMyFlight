class_name SpurTrial
extends RefCounted
## The build check for the side spurs (decision side-spur-move-design-s7-stands-
## carry-lane-x-the-wanted-spur, slice S7b): before an edit commits, GateDesks'
## site guard works out each side's wanted spur x as the edit would leave it
## (wanted_after()) and the gates' grounds on it, and FlightSim checks the whole
## horizon with the release forecast again (FlightSim.spur_refusal()). An edit
## that would strand a flight is refused with SPUR_STRANDS, naming the flight;
## nothing else about a spur refuses a build.
##
## The edit is never applied: a placement's cells read as built and a removal's
## as cleared where nothing else stands there (SideSpurs.built_edges()). A desk
## placed brings the stand of the exit it would link to, and an exit door the
## stand out from it while a desk with no gate is in reach (a door the desk
## cannot use is counted all the same, so the check may look farther out than
## the link). A removal that ends a gate leaves its stand out. The grounds'
## classes after a placement are the largest whose envelope the edit leaves
## clear, as GateDesks.edit_warning() works them out.
##
## Not guaranteed: a gate removal's moved contracts are checked by FlightSim.
## move_plan() on the spurs as they are, not on the ones the removal leaves.

const REMOVALS: Array[BuildEdit.Kind] = [
	BuildEdit.Kind.REMOVE_FLOOR,
	BuildEdit.Kind.REMOVE_WALL,
	BuildEdit.Kind.REMOVE_OBJECT,
	BuildEdit.Kind.REMOVE_ROOM,
]


## A SPUR_STRANDS refusal naming the flight `edit` on `on_grid` would strand
## through `gates`' side spurs, or null. Nothing is checked while the edit
## leaves the wanted spurs as they are and no side waits (or it is a removal).
static func problem(gates: GateDesks, on_grid: BuildGrid, edit: BuildEdit) -> BuildResult:
	if gates.flights == null:
		return null
	var after := wanted_after(gates, on_grid, edit)
	var moves := false
	var same := true
	for side in SideSpurs.SIDES:
		moves = moves or not is_equal_approx(after[side], gates.spur_x[side])
		same = same and is_equal_approx(after[side], gates.spur_wanted[side])
	if same and (not moves or REMOVALS.has(edit.kind)):
		return null
	var grounds := GateDesks.grounds_on(on_grid, _staying(gates, edit), gates.spur_x, after)
	if not REMOVALS.has(edit.kind):
		var built := StandEnvelope.edit_cells(edit)
		for gate: String in grounds:
			_lower(on_grid, grounds[gate], built)
			if grounds[gate].has("next"):
				_lower(on_grid, grounds[gate]["next"], built)
	var stranded := gates.flights.spur_refusal(grounds, SideSpurs.spurs_at(gates.spur_x, after))
	if stranded.is_empty():
		return null
	var refusal := BuildResult.refused(BuildResult.Reason.SPUR_STRANDS)
	refusal.detail = flight_words(gates.flights, stranded["id"])
	return refusal


## The player's words for flight `id`, live or a contract's day not yet issued.
static func flight_words(sim: FlightSim, id: String) -> String:
	if sim.state_of(id) >= 0:
		return FlightLabel.of(sim, true, id)
	var parts := FlightTimetable.parse_occurrence(id)
	return FlightLabel.of(sim, false, parts["contract"]) if not parts.is_empty() else id


## Each side's wanted spur x once `edit` is applied to `on_grid` (see the class
## notes).
static func wanted_after(gates: GateDesks, on_grid: BuildGrid, edit: BuildEdit) -> Dictionary:
	var gone := {}
	var added: Array[Vector2i] = []
	var extra: Array[Dictionary] = []
	match edit.kind:
		BuildEdit.Kind.REMOVE_FLOOR:
			_clear_after(on_grid, edit, [edit.cell], gone)
		BuildEdit.Kind.REMOVE_WALL:
			_clear_after(
				on_grid, edit, [edit.cell, edit.cell + BuildGrid.SIDE_STEP[edit.side]], gone
			)
		BuildEdit.Kind.REMOVE_OBJECT:
			var record := on_grid.get_object(edit.object_id)
			if not record.is_empty():
				var def := BuildCatalog.get_def(record["def"])
				_clear_after(on_grid, edit, def.footprint(record["anchor"], record["facing"]), gone)
		BuildEdit.Kind.REMOVE_ROOM:
			pass
		_:
			added = StandEnvelope.edit_cells(edit)
			extra = _new_stands(gates, on_grid, edit)
	var exits := []
	for binding in _staying(gates, edit):
		exits.append(binding["exit"])
	return SideSpurs.wanted(on_grid, exits, SideSpurs.built_edges(on_grid, gone, added), extra)


## The gates `edit` leaves standing: all but those whose desk or exit it removes.
static func _staying(gates: GateDesks, edit: BuildEdit) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for binding in gates.bindings:
		if edit.kind != BuildEdit.Kind.REMOVE_OBJECT:
			out.append(binding)
		elif binding["desk"] != edit.object_id and binding["exit"] != edit.object_id:
			out.append(binding)
	return out


## Puts in `gone` each of `cells` that the removal `edit` leaves with no floor,
## object or wall.
static func _clear_after(
	on_grid: BuildGrid, edit: BuildEdit, cells: Array[Vector2i], gone: Dictionary
) -> void:
	for cell in cells:
		if not on_grid.in_bounds(cell):
			continue
		var floor_left := on_grid.floor_at(cell) != BuildGrid.FLOOR_NONE
		if edit.kind == BuildEdit.Kind.REMOVE_FLOOR and cell == edit.cell:
			floor_left = false
		var object := on_grid.object_at(cell)
		if edit.kind == BuildEdit.Kind.REMOVE_OBJECT and object == edit.object_id:
			object = 0
		var wall_left := false
		for side in 4:
			if not on_grid.has_wall(cell, side):
				continue
			var removed := (
				edit.kind == BuildEdit.Kind.REMOVE_WALL
				and (
					(cell == edit.cell and side == edit.side)
					or (
						cell == edit.cell + BuildGrid.SIDE_STEP[edit.side]
						and side == (edit.side + 2) % 4
					)
				)
			)
			wall_left = wall_left or not removed
		if not floor_left and object == 0 and not wall_left:
			gone[cell] = true


## The side stands a placement brings: the stand of the exit a desk would link
## to, or the stand out from a west or east exit door while a desk with no gate
## is in reach of it.
static func _new_stands(gates: GateDesks, on_grid: BuildGrid, edit: BuildEdit) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if edit.kind != BuildEdit.Kind.PLACE_OBJECT:
		return out
	if edit.def_id == GateDesks.DESK:
		var footprint := BuildCatalog.get_def(GateDesks.DESK).footprint(edit.cell, edit.facing)
		var taken := {}
		var stands: Array[Dictionary] = []
		for link in GateDesks.links_on(on_grid, gates.bindings):
			taken[link["exit"]] = true
			stands.append(SideSpurs.link_stand(on_grid, link["exit"]))
		var exit := GateDesks.nearest_exit(on_grid, footprint, taken, stands)
		if exit != 0:
			out.append(StandPlacement.for_exit(on_grid, exit))
	elif edit.def_id == &"exit_door":
		var side := StandPlacement.side_of_step(DoorPlacement.back_step(edit.facing))
		if side in SideSpurs.SIDES and _desk_in_reach(gates, on_grid, edit.cell):
			out.append(StandPlacement.for_cell(on_grid, edit.cell, 0, side))
	return out


static func _desk_in_reach(gates: GateDesks, on_grid: BuildGrid, cell: Vector2i) -> bool:
	for desk: int in GateDesks.unlinked_on(on_grid, gates.bindings):
		for at in GateDesks.desk_footprint(on_grid, desk):
			if maxi(absi(at.x - cell.x), absi(at.y - cell.y)) <= GateDesks.LINK_CELLS:
				return true
	return false


## Lowers `ground`'s max_class to the largest whose envelope at its stand the
## cells `built` leave clear.
static func _lower(on_grid: BuildGrid, ground: Dictionary, built: Array[Vector2i]) -> void:
	var now: String = ground["max_class"]
	if now == "":
		return
	for plane_class in StandEnvelope.LARGEST_FIRST:
		if PlaneClasses.ORDER.find(plane_class) > PlaneClasses.ORDER.find(now):
			continue
		var under := StandEnvelope.cells(on_grid, ground["stand"], plane_class)
		if not built.any(func(cell: Vector2i) -> bool: return under.has(cell)):
			ground["max_class"] = plane_class
			return
	ground["max_class"] = ""
