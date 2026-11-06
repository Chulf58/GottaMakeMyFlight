class_name BuildDrags
extends RefCounted
## The drags of BuildMode: beginning, stretching and applying a Floor, Remove or
## room rectangle, a room resize, a Wall or Glass row and a Belt line, and the
## belt reshape after an edit. Static helpers over the BuildMode `mode` that owns
## the drag state. The undo brackets (begin_action and end_action) stay in
## BuildMode, so one player action is still one receipt.


## Starts a Floor or Remove rectangle on the cell under a ground point. A press
## outside the grid is a plain click, which the grid refuses with its reason.
static func begin_area(mode: BuildMode, point: Vector3) -> void:
	# A room tool pressed in the outer band of a room of its type grabs that
	# room's edge to resize it instead of marking a new room (RoomResize).
	if (
		BuildMode.TOOL_ROOMS.has(mode.tool)
		and mode._resize.begin(mode.grid, point, BuildMode.TOOL_ROOMS[mode.tool])
	):
		mode._status_note = ""
		mode._hover_key = ""
		return
	if (
		BuildMode.TOOL_ROOMS.has(mode.tool)
		and mode.room_mover.pick_up(point, BuildMode.TOOL_ROOMS[mode.tool])
	):
		return
	var cell := mode.grid.world_to_cell(point)
	if not mode.grid.in_bounds(cell):
		if mode.tool == BuildMode.Tool.BELT:
			mode._show_status(BuildResult.refused(BuildResult.Reason.OUT_OF_BOUNDS))
			return
		mode.apply_at(point)
		return
	mode._status_note = ""
	mode._area.begin(cell, point, mode.grid.size)
	mode._hover_key = ""


## Starts a Wall or Glass row on the cell under a ground point, on the edge side
## nearest the point. A press outside the grid is a plain click, which the grid
## refuses with its reason.
static func begin_row(mode: BuildMode, point: Vector3) -> void:
	if not BuildMode.DRAG_TOOLS.has(mode.tool):
		return
	var cell := mode.grid.world_to_cell(point)
	if not mode.grid.in_bounds(cell):
		mode.apply_at(point)
		return
	mode._status_note = ""
	mode._row.begin(cell, mode.grid.nearest_side(point), mode.grid.size)
	mode._hover_key = ""


## Stretches the row to the cell under a ground point.
static func move_row(mode: BuildMode, point: Vector3) -> void:
	if mode._row.active:
		mode._row.move(mode.grid.world_to_cell(point))


## Lays the row (WallRowDrag.apply()) inside the undo bracket BuildMode.finish_row()
## holds open: every edge the rules accept, stopping where the money runs out.
static func lay_row(mode: BuildMode) -> AreaDrag.Outcome:
	mode._row.cancel()
	mode._hover_key = ""
	var dirty: Array[Vector2i] = []
	var outcome := WallRowDrag.apply(mode.grid, row_edits(mode), mode.check, mode.wallet(), dirty)
	if outcome.placed > 0:
		reshape_belts(mode, dirty)
		mode._redraw()
		mode.grid_changed.emit()
	return outcome


## The status line after the row was laid, outside the undo bracket: how many
## edges were placed, what they cost and why any was skipped.
static func report_row(mode: BuildMode, outcome: AreaDrag.Outcome) -> void:
	mode._status_note = outcome.message()
	mode._note_cell = mode._row.end_cell()
	mode._show_status(null)


static func row_edits(mode: BuildMode) -> Array[BuildEdit]:
	return mode._row.edits(BuildMode.TOOL_WALL_KINDS[mode.tool])


## Stretches the rectangle to the cell under a ground point, or moves the grabbed
## room edge to the nearest grid line (RoomResize).
static func move_area(mode: BuildMode, point: Vector3) -> void:
	if mode._resize.active:
		mode._resize.move(mode.grid, point)
	elif mode._area.active:
		mode._area.move(mode.grid.world_to_cell(point))


static func finish_area(mode: BuildMode) -> AreaDrag.Outcome:
	if mode._resize.active:
		finish_resize(mode)
		return null
	if not mode._area.active:
		return null
	mode._area.cancel()
	mode._hover_key = ""
	if mode.tool == BuildMode.Tool.BELT:
		mode.lay_belt(mode._area.start_cell(), mode._area.end_cell())
		return null
	if mode._area.is_single_cell():
		mode.apply_at(mode._area.press_point)
		return null
	if BuildMode.TOOL_ROOMS.has(mode.tool):
		finish_room(mode)
		return null
	var outcome: AreaDrag.Outcome
	if mode.tool == BuildMode.Tool.REMOVE:
		var touched := cells_a_clear_touches(mode, mode._area.rect())
		mode.grid.hold_signals()
		outcome = AreaDrag.clear(mode.grid, mode._area.rect(), mode.wallet())
		if outcome.placed > 0:
			reshape_belts(mode, touched)
		mode.grid.release_signals()
	else:
		outcome = AreaDrag.fill_floor(
			mode.grid, mode._area.rect(), BuildMode.TERMINAL_ZONE, mode.wallet()
		)
	if outcome.placed > 0:
		mode._redraw()
		mode.grid_changed.emit()
	mode._status_note = outcome.message()
	mode._note_cell = mode._area.end_cell()
	mode._show_status(null)
	return outcome


## Gives the room its dragged rectangle (RoomResize.finish()).
static func finish_resize(mode: BuildMode) -> void:
	var before := mode._resize.original()
	mode._hover_key = ""
	mode.grid.hold_signals()
	var result := mode._resize.finish(mode.grid, mode.wallet())
	if result != null and result.ok:
		reshape_belts(mode, rect_cells(before.merge(mode._resize.rect())))
	mode.grid.release_signals()
	if result != null and result.ok:
		mode.grid_changed.emit()
	mode._status_note = mode._resize.note
	mode._note_cell = mode._resize.pointer_cell
	mode._show_status(null)


## Marks the released rectangle as a room of the current room tool's type.
static func finish_room(mode: BuildMode) -> void:
	var type: StringName = BuildMode.TOOL_ROOMS[mode.tool]
	mode.grid.hold_signals()
	var result := RoomTool.mark(mode.grid, mode._area.rect(), type, mode.wallet())
	if result.ok:
		reshape_belts(mode, rect_cells(mode._area.rect()))
	mode.grid.release_signals()
	if result.ok:
		mode.grid_changed.emit()
	mode._status_note = RoomTool.message(mode.grid, result, type)
	mode._note_cell = mode._area.end_cell()
	mode._show_status(null)


static func lay_belt(mode: BuildMode, from: Vector2i, to: Vector2i) -> BuildResult:
	var plan := BeltShaper.plan_line(mode.grid, from, to, mode.facing)
	var result := plan.result
	if result.ok and not plan.edits.is_empty():
		result = BuildTransaction.commit_plan(mode.grid, plan.edits, mode.wallet())
	if result.ok and not plan.edits.is_empty():
		mode._redraw()
		mode.grid_changed.emit()
	mode._belt_plan = null
	mode._hover_key = ""
	mode._show_status(result)
	if not plan.result.ok:
		mode.grid.edit_refused.emit(
			BuildEdit.place_object(BuildMode.BELT_PRICE_ID, to, mode.facing), result
		)
	return result


## Reshapes the belts on and next to `cells` to fit their links (BeltShaper):
## free RESHAPE_BELT edits, committed through BuildTransaction so they reach
## listeners like any edit.
static func reshape_belts(mode: BuildMode, cells: Array[Vector2i]) -> void:
	var edits := BeltShaper.reshape_edits(mode.grid, BeltShaper.around(cells))
	if edits.is_empty():
		return
	BuildTransaction.commit_plan(mode.grid, edits, mode.wallet())
	mode._redraw()


## The cells a Remove rectangle over `area` can change the belts next to, read
## before it clears: the rectangle, the whole footprint of each object reaching
## into it (a desk's outlet sits beside its far cell) and every bag room that
## reaches into or touches it.
static func cells_a_clear_touches(mode: BuildMode, area: Rect2i) -> Array[Vector2i]:
	var cells := rect_cells(area)
	var seen := {}
	for cell in rect_cells(area):
		var object_id := mode.grid.object_at(cell) if mode.grid.in_bounds(cell) else 0
		if object_id == 0 or seen.has(object_id):
			continue
		seen[object_id] = true
		var record := mode.grid.get_object(object_id)
		var def := BuildCatalog.get_def(record["def"])
		cells.append_array(def.footprint(record["anchor"], record["facing"]))
	for room_id in mode.grid.room_ids():
		var room := mode.grid.get_room(room_id)
		if room["type"] == &"bag_room" and (room["rect"] as Rect2i).intersects(area.grow(1)):
			cells.append_array(rect_cells(room["rect"]))
	return cells


static func rect_cells(area: Rect2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			cells.append(Vector2i(x, y))
	return cells
