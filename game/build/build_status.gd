class_name BuildStatus
extends RefCounted
## What BuildMode's status line says: the hover key of an edit, the line for the
## current tool and drag, the lane hint under the pointer and the warning for an
## item whose front falls outside its room. Static helpers over the BuildMode
## `mode` that owns the status state; BuildMode keeps one-line delegates.


static func edit_key(edit: BuildEdit) -> String:
	return (
		"%d:%s:%d:%d:%d:%s:%s"
		% [
			edit.kind,
			edit.cell,
			edit.side,
			edit.wall_kind,
			edit.facing,
			edit.object_id,
			edit.room_id
		]
	)


static func show_status(mode: BuildMode, result: BuildResult) -> void:
	if mode._row.active:
		mode._set_status(mode._row_label)
		return
	if mode._resize.active:
		mode._set_status(mode._resize.label(mode.grid))
		return
	if mode._area.active and BuildMode.TOOL_ROOMS.has(mode.tool):
		mode._set_status(
			RoomTool.drag_label(mode.grid, mode._area.rect(), BuildMode.TOOL_ROOMS[mode.tool])
		)
		return
	# An undo's note shows under the Belt tool too.
	if mode._status_note != "" and not mode._area.active:
		mode._set_status(mode._status_note)
		return
	if mode.tool == BuildMode.Tool.BELT:
		var text := BuildMode.BELT_HINT
		if mode._area.active and mode._belt_plan != null:
			text = "Belt %d cells" % mode._belt_plan.cells.size()
		if result != null and not result.ok:
			text += "  " + result.reason_text()
		mode._set_status(text)
		return
	if mode._area.active:
		mode._set_status(mode._area.size_label())
		return
	var text := (
		RoomTool.hint(BuildMode.TOOL_ROOMS[mode.tool])
		if BuildMode.TOOL_ROOMS.has(mode.tool)
		else ""
	)
	var refused := result != null and not result.ok
	# The facing is for an item that can be placed; a refusal shows its reason alone.
	if BuildMode.tool_object(mode.tool) != &"" and not refused:
		text = "Facing auto" if mode._facing_is_auto() else "Facing %d" % mode.facing
	if refused:
		var reason := result.reason_text()
		if BuildMode.DOOR_NAMES.has(mode.tool) and BuildMode.DOOR_HINTS.has(result.reason):
			reason = BuildMode.DOOR_HINTS[result.reason] % BuildMode.DOOR_NAMES[mode.tool]
		text += ("  " if text != "" else "") + reason
	if mode._front_warning != "" and not refused:
		text += ("  " if text != "" else "") + mode._front_warning
	if mode._lane_hint != "":
		text += ("  " if text != "" else "") + mode._lane_hint
	mode._set_status(text)


## What the status line says about the lane part at `cell`: the first thing
## the arch lacks
## (SecurityLanes.status_text) for an incomplete arch or a part of an
## incomplete lane, NOT_IN_LANE for a part no arch counts, and "" for a whole
## lane, any other object and empty floor. The lanes are recognised afresh
## from the grid, and only when the cell holds a lane part.
static func lane_hint(on_grid: BuildGrid, cell: Vector2i) -> String:
	if not on_grid.in_bounds(cell):
		return ""
	var id := on_grid.object_at(cell)
	if id == 0 or not SecurityLanes.is_part(StringName(on_grid.get_object(id)["def"])):
		return ""
	var lanes := SecurityLanes.new()
	lanes.rebuild(on_grid)
	if lanes.is_complete(id) or lanes.lane_of_piece(id) != 0:
		return ""
	if lanes.arches.has(id):
		return lanes.status_text(id)
	for arch in lanes.arches:
		if (lanes.candidate(arch)["parts"] as Dictionary).values().has(id):
			return lanes.status_text(arch)
	return BuildMode.NOT_IN_LANE


## BuildMode.FRONT_OUTSIDE_ROOM for an object edit whose footprint lies wholly in
## a room but whose interaction (front) cell does not: the room would not count
## it (FacilitySlots.piece_inside), so a toilet stall placed so reads "Needs a
## toilet stall". Without one, on the airport site, the site grid's gate
## warning (SiteGrid.edit_warning: "Gate A will then take planes up to
## medium"). "" for any other edit.
static func front_warning(on_grid: BuildGrid, edit: BuildEdit) -> String:
	var room := _room_front_warning(on_grid, edit)
	if room == "" and edit != null and on_grid is SiteGrid:
		return (on_grid as SiteGrid).edit_warning(edit)
	return room


static func _room_front_warning(on_grid: BuildGrid, edit: BuildEdit) -> String:
	if edit == null or edit.kind != BuildEdit.Kind.PLACE_OBJECT:
		return ""
	var def := BuildCatalog.get_def(edit.def_id)
	if def == null or not def.has_interaction:
		return ""
	var room_id := on_grid.room_at(edit.cell)
	if room_id == 0:
		return ""
	var area: Rect2i = on_grid.get_room(room_id)["rect"]
	for cell in def.footprint(edit.cell, edit.facing):
		if not area.has_point(cell):
			return ""
	if area.has_point(def.interaction_cell(edit.cell, edit.facing)):
		return ""
	return BuildMode.FRONT_OUTSIDE_ROOM


## lane_hint() for the cell under the pointer, kept until the pointer moves to
## another cell or the grid changes.
static func lane_hint_at(mode: BuildMode, cell: Vector2i) -> String:
	if not mode._hint_cached or cell != mode._hint_cell:
		mode.lane_hint_scans += 1
		mode._hint_cell = cell
		mode._hint_cache = lane_hint(mode.grid, cell)
		mode._hint_cached = true
	return mode._hint_cache
