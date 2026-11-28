class_name BuildGhost
extends RefCounted
## The ghost BuildMode draws under the pointer: the tinted boxes, slabs and
## pieces of one edit, a Belt line, a Wall row or a dragged rectangle. Static
## helpers over the BuildMode `mode` that owns the ghost node, its materials and
## the hover key; BuildMode keeps one-line delegates for what tests call.

## The bar on the wall that refuses a Belt line lies on the floor along the wall
## line, in the form of the roof's wall-gap bar (GapMarkers). It is as tall as a
## cut-away wall stub, the height an interior wall is drawn at, so it never
## stands over the room, and this deep across the wall line.
const WALL_BLOCK_HEIGHT := InteriorKit.STUB_HEIGHT
const WALL_BLOCK_DEPTH := 0.5


## A tinted ghost material; `through` draws it over what stands in front of it.
static func material(tint: Color, through := false) -> StandardMaterial3D:
	var standard := StandardMaterial3D.new()
	standard.albedo_color = tint
	standard.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	standard.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if through:
		standard.no_depth_test = true
		standard.render_priority = 10
	return standard


## Hides the rectangle's slab and size while the pointer is over the HUD; the
## cleared hover key makes draw_area() draw both again on the way back.
static func hide_area(mode: BuildMode) -> void:
	mode._pointer_on_grid = false
	mode._hover_point = null
	mode._ghost.visible = false
	mode._hover_key = ""
	mode._set_status(BuildWords.status(BuildMode.DRAG_OVER_UI))


## The Belt ghost for the one cell under the pointer, or none off the grid.
static func hover_belt(mode: BuildMode, point: Variant) -> void:
	mode._hover_edit = null
	if not mode._pointer_on_grid:
		mode._belt_plan = null
		mode._ghost.visible = false
		if mode._hover_key != "":
			mode._hover_key = ""
			mode._show_status(null)
		return
	var cell := mode.grid.world_to_cell(point)
	draw_belt(mode, cell, cell)


## The shaped pieces a Belt line from `from` to `to` would lay or reshape,
## tinted by whether it can be laid; a refused line tints its cells instead.
## A line a wall refuses also draws a red bar, seen through other pieces, on
## the wall edge the plan says blocked it (decision
## a-belt-refused-by-a-wall-draws-a-red-bar-on-the-blocking-wal).
static func draw_belt(mode: BuildMode, from: Vector2i, to: Vector2i) -> void:
	var key := "belt:%s:%s:%d" % [from, to, mode.facing]
	if key == mode._hover_key:
		return
	mode._hover_key = key
	mode._belt_plan = BeltShaper.plan_line(mode.grid, from, to, mode.facing)
	var result := mode._belt_plan.result
	if result.ok:
		result = BuildTransaction.check(mode.grid, mode._belt_plan.edits, mode.wallet())
	clear(mode)
	var tint := mode._valid_material if result.ok else mode._invalid_material
	if mode._belt_plan.result.ok:
		for piece in mode._belt_plan.shapes:
			object(mode, piece[0], piece[1], piece[2], tint)
	else:
		for cell in mode._belt_plan.cells:
			if mode.grid.in_bounds(cell):
				tile(mode, cell, tint)
		if mode._belt_plan.wall_side >= 0:
			wall_block(mode, mode._belt_plan.wall_cell, mode._belt_plan.wall_side)
	mode._show_status(result)


## The whole row a Wall or Glass drag would lay, one box per edge tinted by
## whether it would be placed, with its length and cost on the status line.
static func draw_row(mode: BuildMode) -> void:
	var cells := mode._row.cells()
	var purse := mode.wallet()
	var key := "row:%s:%s:%d:%d" % [cells.front(), cells.back(), mode._row.side, mode.tool]
	if purse != null:
		key += ":%d" % purse.balance
	if key == mode._hover_key:
		return
	mode._hover_key = key
	mode._hover_edit = null
	var plan := WallRowDrag.preview(mode.grid, BuildDrags.row_edits(mode), mode.check, purse)
	clear(mode)
	for i in plan.edits.size():
		var tint := mode._valid_material if plan.valid[i] else mode._invalid_material
		wall(mode, plan.edits[i].cell, plan.edits[i].side, tint)
	mode._row_label = (
		"%s row of %d" % ["Glass" if mode.tool == BuildMode.Tool.GLASS else "Wall", cells.size()]
	)
	mode._row_label += ", cost %d" % plan.cost
	if plan.blocked > 0:
		mode._row_label += ", %d blocked: %s" % [plan.blocked, plan.first_reason]
	mode._show_status(null)


## Preview of a repeatable item row drag: valid candidates in green, blocked/unaffordable
## candidates in red, plus exact total cost for the valid affordable subset.
static func draw_item_row(mode: BuildMode) -> void:
	var edits := mode._item_row.edits()
	var purse := mode.wallet()
	var bal := purse.balance if purse != null else -1
	var key := (
		"item_row:%s:%s:%d:%d:%d"
		% [edits.front().cell, edits.back().cell, mode.tool, mode.facing, bal]
	)
	if key == mode._hover_key:
		return
	mode._hover_key = key
	mode._hover_edit = null
	var plan := ItemRowDrag.preview(
		mode.grid, edits, mode.check, purse, mode.unlocks, mode.require_unlocks
	)
	clear(mode)
	for i in plan.edits.size():
		var tint := mode._valid_material if plan.valid[i] else mode._invalid_material
		var edit := plan.edits[i]
		object(mode, edit.def_id, edit.cell, edit.facing, tint)
	var def := BuildCatalog.get_def(BuildMode.tool_object(mode.tool))
	var item_name := DisplayWords.item(def.display_name) if def != null else ""
	mode._row_label = BuildWords.item_row_drag(
		item_name, plan.edits.size(), plan.cost, plan.blocked, plan.first_reason
	)
	mode._show_status(null)


## One tinted slab over the room's dragged rectangle, plus planned perimeter walls.
static func draw_resize(mode: BuildMode) -> void:
	var area := mode._resize.rect()
	var purse := mode.wallet()
	var key := "resize:%s:%d" % [area, purse.balance if purse != null else 0]
	if key == mode._hover_key:
		return
	mode._hover_key = key
	clear(mode)
	var fits := RoomResize.check(mode.grid, mode._resize.room_id, area, purse).ok
	var tint := mode._valid_material if fits else mode._invalid_material
	slab(mode, area, tint)
	for edit in RoomResize.plan(mode.grid, mode._resize.room_id, area):
		if edit.kind == BuildEdit.Kind.PLACE_WALL:
			wall(mode, edit.cell, edit.side, tint)
	mode._show_status(null)


## One tinted slab over the whole rectangle, with its size on the status line.
static func draw_area(mode: BuildMode) -> void:
	if mode._wall_remove.active:
		draw_wall_remove(mode)
		return
	if mode._resize.active:
		draw_resize(mode)
		return
	if mode.tool == BuildMode.Tool.BELT:
		draw_belt(mode, mode._area.start_cell(), mode._area.end_cell())
		return
	var area := mode._area.rect()
	var purse := mode.wallet()
	var key := "area:%s" % area
	if (mode.tool == BuildMode.Tool.FLOOR or BuildMode.TOOL_ROOMS.has(mode.tool)) and purse != null:
		key += ":%d" % purse.balance
	if key == mode._hover_key:
		return
	mode._hover_key = key
	clear(mode)
	var tint := (
		mode._area_remove_material if mode.tool == BuildMode.Tool.REMOVE else mode._valid_material
	)
	if BuildMode.TOOL_ROOMS.has(mode.tool):
		var room_type: StringName = BuildMode.TOOL_ROOMS[mode.tool]
		var extend := RoomResize.auto_extend(mode.grid, area, room_type)
		if not extend.is_empty():
			var ext_id := int(extend["room_id"])
			var ext_rect: Rect2i = extend["rect"]
			var ext_fits := RoomResize.check(mode.grid, ext_id, ext_rect, purse).ok
			tint = mode._valid_material if ext_fits else mode._invalid_material
			slab(mode, ext_rect, tint)
			for edit in RoomResize.plan(mode.grid, ext_id, ext_rect):
				if edit.kind == BuildEdit.Kind.PLACE_WALL:
					wall(mode, edit.cell, edit.side, tint)
			mode._show_status(null)
			return
		if not (
			RoomTool.check(mode.grid, area, room_type, purse, mode.unlocks, mode.require_unlocks).ok
		):
			tint = mode._invalid_material
		for edit in RoomTool.plan(mode.grid, area, room_type):
			if edit.kind == BuildEdit.Kind.PLACE_WALL:
				wall(mode, edit.cell, edit.side, tint)
	# A floor rectangle the wallet cannot pay for lays nothing (CANT_AFFORD).
	if (
		mode.tool == BuildMode.Tool.FLOOR
		and purse != null
		and AreaDrag.floor_cost(mode.grid, area) > purse.balance
	):
		tint = mode._invalid_material
	slab(mode, area, tint)
	mode._show_status(null)


## Highlights every wall along the active wall-remove drag in red (or invalid
## if blocked) and updates the status line with count and refund.
static func draw_wall_remove(mode: BuildMode) -> void:
	var edge_list := mode._wall_remove.edges(mode.grid)
	var purse := mode.wallet()
	var bal := purse.balance if purse != null else -1
	var key := "wall_remove:%s:%d:%d" % [edge_list, mode.grid.wall_version(), bal]
	if key == mode._hover_key:
		return
	mode._hover_key = key
	mode._hover_edit = null
	var plan := WallRowDrag.RemoveDrag.preview(mode.grid, edge_list, mode.check, purse)
	clear(mode)
	for i in plan.edits.size():
		var tint := mode._wall_remove_material if plan.valid[i] else mode._invalid_material
		wall(mode, plan.edits[i].cell, plan.edits[i].side, tint, 2.0)
	var valid_count := plan.edits.size() - plan.blocked
	var label := "Remove %d wall%s" % [valid_count, "" if valid_count == 1 else "s"]
	if plan.cost > 0:
		label += ", refund %d" % plan.cost
	if plan.blocked > 0:
		label += ", %d blocked: %s" % [plan.blocked, plan.first_reason]
	mode._row_label = label
	mode._show_status(null)


## Highlights a hovered room resize edge unmistakably along its full edge plus
## visible handle grips on all four edges.
static func draw_resize_hover(mode: BuildMode, hover: Dictionary) -> void:
	var rect: Rect2i = hover["rect"]
	var side: int = hover["side"]
	var key := "resize_hover:%s:%s:%d:%d" % [hover["room_id"], rect, side, mode.tool]
	if key == mode._hover_key:
		return
	mode._hover_key = key
	clear(mode)
	var ox := mode.grid.origin.x
	var oz := mode.grid.origin.z
	var y := mode.grid.origin.y + 0.10
	var bar_extent: Vector3
	var bar_pos: Vector3
	match side:
		BuildGrid.Side.NORTH:
			bar_extent = Vector3(rect.size.x, 0.16, 0.24)
			bar_pos = Vector3(ox + rect.position.x + rect.size.x * 0.5, y, oz + rect.position.y)
		BuildGrid.Side.SOUTH:
			bar_extent = Vector3(rect.size.x, 0.16, 0.24)
			bar_pos = Vector3(ox + rect.position.x + rect.size.x * 0.5, y, oz + rect.end.y)
		BuildGrid.Side.WEST:
			bar_extent = Vector3(0.24, 0.16, rect.size.y)
			bar_pos = Vector3(ox + rect.position.x, y, oz + rect.position.y + rect.size.y * 0.5)
		_:
			bar_extent = Vector3(0.24, 0.16, rect.size.y)
			bar_pos = Vector3(ox + rect.end.x, y, oz + rect.position.y + rect.size.y * 0.5)
	var bar := box(mode, bar_extent, mode._resize_hover_material)
	bar.position = bar_pos
	var positions := RoomResize.handle_positions(mode.grid, rect)
	for i in positions.size():
		var is_hovered := i == side
		var grip_size := Vector3(0.46, 0.24, 0.46) if is_hovered else Vector3(0.32, 0.14, 0.32)
		var grip_mat := mode._resize_hover_material if is_hovered else mode._resize_handle_material
		var grip := box(mode, grip_size, grip_mat)
		grip.position = positions[i] + Vector3(0.0, grip_size.y * 0.5 + 0.02, 0.0)


static func clear(mode: BuildMode) -> void:
	for child in mode._ghost.get_children():
		child.queue_free()
	mode._ghost.visible = true


static func draw(mode: BuildMode, edit: BuildEdit, tint: Material) -> void:
	clear(mode)
	match edit.kind:
		BuildEdit.Kind.PAINT_FLOOR, BuildEdit.Kind.REMOVE_FLOOR:
			tile(mode, edit.cell, tint)
		BuildEdit.Kind.PLACE_WALL, BuildEdit.Kind.REMOVE_WALL:
			# A wall about to be removed is drawn bigger, so it reads at range.
			wall(
				mode, edit.cell, edit.side, tint, 2.0 if mode.tool == BuildMode.Tool.REMOVE else 1.0
			)
		BuildEdit.Kind.PLACE_OBJECT:
			object(mode, edit.def_id, edit.cell, edit.facing, tint)
			for cell in coverage_preview(mode.grid, edit):
				tile(mode, cell, mode._coverage_material).name = "Coverage"
		BuildEdit.Kind.REMOVE_OBJECT:
			var record := mode.grid.get_object(edit.object_id)
			object(mode, record["def"], record["anchor"], record["facing"], tint)
		BuildEdit.Kind.REMOVE_ROOM:
			slab(mode, mode.grid.get_room(edit.room_id)["rect"], tint)


## A tinted box over the wall edge of `cell` on `side`; `grow` thickens it.
static func wall(mode: BuildMode, cell: Vector2i, side: int, tint: Material, grow := 1.0) -> void:
	var extent := Vector3(1.0, BuildView.WALL_HEIGHT, BuildView.WALL_THICKNESS * 1.5 * grow)
	if grow > 1.0:
		extent += Vector3(0.04, 0.1, 0.0)
	var box_node := box(mode, extent, tint)
	box_node.transform = BuildView.wall_transform(mode.grid, cell, side).translated_local(
		Vector3(0.0, extent.y / 2.0, 0.0)
	)


## The low see-through red bar on the wall edge of `cell` on `side` that refuses a
## Belt line, standing on the floor.
static func wall_block(mode: BuildMode, cell: Vector2i, side: int) -> void:
	var extent := Vector3(1.04, WALL_BLOCK_HEIGHT, WALL_BLOCK_DEPTH)
	var bar := box(mode, extent, mode._wall_block_material)
	bar.transform = BuildView.wall_transform(mode.grid, cell, side).translated_local(
		Vector3(0.0, extent.y / 2.0, 0.0)
	)


static func object(
	mode: BuildMode, def_id: StringName, anchor: Vector2i, turn: int, tint: Material
) -> void:
	var def := BuildCatalog.get_def(def_id)
	var node := BuildView.make_object_node(def, tint)
	node.transform = BuildView.object_transform(mode.grid, def.footprint(anchor, turn), turn)
	node.scale = Vector3.ONE * 1.02
	mode._ghost.add_child(node)
	StationUseCells.draw(mode._ghost, mode.grid, def_id, anchor, turn)


## The cells the ghost tints as covered while `edit` places a screen stand or
## departure board: ScreenCoverage.covered_cells() where it would stand; empty
## for any other edit.
static func coverage_preview(on_grid: BuildGrid, edit: BuildEdit) -> Array[Vector2i]:
	if edit.kind != BuildEdit.Kind.PLACE_OBJECT:
		return []
	if edit.def_id != ScreenCoverage.SCREEN_ID and edit.def_id != ScreenCoverage.INFO_SCREEN_ID:
		return []
	return ScreenCoverage.covered_cells(on_grid, edit.cell, edit.facing)


static func tile(mode: BuildMode, cell: Vector2i, tint: Material) -> MeshInstance3D:
	var tile_node := box(mode, Vector3(0.96, 0.08, 0.96), tint)
	tile_node.position = mode.grid.cell_to_world(cell) + Vector3(0.0, 0.06, 0.0)
	return tile_node


## One tinted slab over a rectangle of cells.
static func slab(mode: BuildMode, area: Rect2i, tint: Material) -> void:
	var slab_node := box(mode, Vector3(area.size.x - 0.04, 0.08, area.size.y - 0.04), tint)
	slab_node.position = (
		mode.grid.cell_to_world(area.position)
		+ Vector3((area.size.x - 1) / 2.0, 0.06, (area.size.y - 1) / 2.0)
	)


static func box(mode: BuildMode, extent: Vector3, tint: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = extent
	var box_node := MeshInstance3D.new()
	box_node.mesh = mesh
	box_node.material_override = tint
	mode._ghost.add_child(box_node)
	return box_node


## World XZ footprint the pointer or active drag is hovering or building on
## over `mode`'s grid, for build-mode overlays (GateLinksView clearance zone).
static func clearance_target(mode: BuildMode) -> Dictionary:
	if mode == null or mode.grid == null:
		return {"active": false}
	if mode.is_dragging() and mode._area_over_ui:
		return {"active": false}
	if mode.tool == BuildMode.Tool.BUY_LAND or BuildModeLandside.is_landside_tool(mode):
		return {"active": false}
	if mode._wall_remove.active:
		var wall_cells: Array[Vector2i] = []
		for edge in mode._wall_remove.edges(mode.grid):
			wall_cells.append(Vector2i(edge.x, edge.y))
		return _cells_target(mode.grid, wall_cells, false)
	if mode._resize.active:
		return _area_target(mode, mode._resize.rect(), true)
	if mode._area.active:
		if mode.tool == BuildMode.Tool.BELT:
			var belt_cells: Array[Vector2i] = (
				mode._belt_plan.cells if mode._belt_plan != null else [mode._area.end_cell()]
			)
			return _cells_target(mode.grid, belt_cells, true)
		if BuildMode.TOOL_ROOMS.has(mode.tool):
			var extend := RoomResize.auto_extend(
				mode.grid, mode._area.rect(), BuildMode.TOOL_ROOMS[mode.tool]
			)
			if not extend.is_empty():
				return _area_target(mode, extend["rect"], true)
		return _area_target(mode, mode._area.rect(), mode.tool != BuildMode.Tool.REMOVE)
	if mode._row.active:
		var row_cells: Array[Vector2i] = []
		for edit in BuildDrags.row_edits(mode):
			row_cells.append_array(StandEnvelope.edit_cells(edit))
		return _cells_target(mode.grid, row_cells, true)
	if mode._item_row.active:
		var item_cells: Array[Vector2i] = []
		for edit in mode._item_row.edits():
			item_cells.append_array(StandEnvelope.edit_cells(edit))
		return _cells_target(mode.grid, item_cells, true)
	if mode.room_mover != null and mode.room_mover.active:
		if mode.room_mover._plan == null:
			return {"active": false}
		return _area_target(mode, mode.room_mover._plan.to_rect, true)
	if mode.object_mover != null and mode.object_mover.active:
		var cells := mode.object_mover.footprint_cells()
		return _cells_target(mode.grid, cells, true) if not cells.is_empty() else {"active": false}
	if mode.starter_kit != null and mode.starter_kit.is_active():
		if not mode._pointer_on_grid or mode._hover_point == null:
			return {"active": false}
		var cell := mode.grid.world_to_cell(mode._hover_point)
		return _area_target(
			mode,
			StarterRoomKits.rect_at(mode.starter_kit.armed, cell, mode.starter_kit.turns),
			true
		)
	var active_tpl := mode.templates.active_template() if mode.templates != null else null
	if active_tpl != null:
		if not mode._pointer_on_grid or mode._hover_point == null:
			return {"active": false}
		var cell := mode.grid.world_to_cell(mode._hover_point)
		return _area_target(mode, active_tpl.rect_at(cell, mode.templates.turns), true)
	if not mode._pointer_on_grid or mode._hover_point == null:
		return {"active": false}
	if mode.tool == BuildMode.Tool.BELT:
		var belt_cells: Array[Vector2i] = (
			mode._belt_plan.cells
			if mode._belt_plan != null
			else [mode.grid.world_to_cell(mode._hover_point)]
		)
		return _cells_target(mode.grid, belt_cells, true)
	if mode.tool == BuildMode.Tool.SECURITY_LANE:
		return _cells_target(
			mode.grid,
			SecurityLaneStamp.footprint_cells(
				SecurityLaneStamp.anchor_for(mode.grid, mode._hover_point, mode.facing), mode.facing
			),
			true
		)
	if mode._hover_edit != null and not LandPlots.REMOVALS.has(mode._hover_edit.kind):
		return _cells_target(mode.grid, StandEnvelope.edit_cells(mode._hover_edit), true)
	return _cells_target(mode.grid, [mode.grid.world_to_cell(mode._hover_point)], false)


static func _area_target(mode: BuildMode, area: Rect2i, building: bool) -> Dictionary:
	if not area.has_area():
		return {"active": false}
	var bounds := Rect2(
		Vector2(mode.grid.origin.x + area.position.x, mode.grid.origin.z + area.position.y),
		Vector2(area.size),
	)
	var rects: Array[Rect2] = [bounds]
	return {"active": true, "bounds": bounds, "rects": rects, "building": building}


static func _cells_target(grid: BuildGrid, cells: Array[Vector2i], building: bool) -> Dictionary:
	var rects: Array[Rect2] = []
	var bounds := Rect2()
	for cell in cells:
		var cell_rect := Rect2(Vector2(grid.origin.x + cell.x, grid.origin.z + cell.y), Vector2.ONE)
		bounds = cell_rect if rects.is_empty() else bounds.merge(cell_rect)
		rects.append(cell_rect)
	if rects.is_empty():
		return {"active": false}
	return {"active": true, "bounds": bounds, "rects": rects, "building": building}
