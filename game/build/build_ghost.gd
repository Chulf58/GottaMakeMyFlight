class_name BuildGhost
extends RefCounted
## The ghost BuildMode draws under the pointer: the tinted boxes, slabs and
## pieces of one edit, a Belt line, a Wall row or a dragged rectangle. Static
## helpers over the BuildMode `mode` that owns the ghost node, its materials and
## the hover key; BuildMode keeps one-line delegates for what tests call.


static func material(tint: Color) -> StandardMaterial3D:
	var standard := StandardMaterial3D.new()
	standard.albedo_color = tint
	standard.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	standard.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return standard


## Hides the rectangle's slab and size while the pointer is over the HUD; the
## cleared hover key makes draw_area() draw both again on the way back.
static func hide_area(mode: BuildMode) -> void:
	mode._pointer_on_grid = false
	mode._ghost.visible = false
	mode._hover_key = ""
	mode._set_status(BuildMode.DRAG_OVER_UI)


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


## One tinted slab over the room's dragged rectangle, red when it would be refused.
static func draw_resize(mode: BuildMode) -> void:
	var area := mode._resize.rect()
	var key := "resize:%s" % area
	if key == mode._hover_key:
		return
	mode._hover_key = key
	clear(mode)
	var fits := RoomResize.check(mode.grid, mode._resize.room_id, area).ok
	slab(mode, area, mode._valid_material if fits else mode._invalid_material)
	mode._show_status(null)


## One tinted slab over the whole rectangle, with its size on the status line.
static func draw_area(mode: BuildMode) -> void:
	if mode._resize.active:
		draw_resize(mode)
		return
	if mode.tool == BuildMode.Tool.BELT:
		draw_belt(mode, mode._area.start_cell(), mode._area.end_cell())
		return
	var area := mode._area.rect()
	var purse := mode.wallet()
	var key := "area:%s" % area
	if mode.tool == BuildMode.Tool.FLOOR and purse != null:
		key += ":%d" % purse.balance
	if key == mode._hover_key:
		return
	mode._hover_key = key
	clear(mode)
	var tint := (
		mode._area_remove_material if mode.tool == BuildMode.Tool.REMOVE else mode._valid_material
	)
	if (
		BuildMode.TOOL_ROOMS.has(mode.tool)
		and not RoomTool.check(mode.grid, area, BuildMode.TOOL_ROOMS[mode.tool]).ok
	):
		tint = mode._invalid_material
	# A floor rectangle the wallet cannot pay for lays nothing (CANT_AFFORD).
	if (
		mode.tool == BuildMode.Tool.FLOOR
		and purse != null
		and AreaDrag.floor_cost(mode.grid, area) > purse.balance
	):
		tint = mode._invalid_material
	slab(mode, area, tint)
	mode._show_status(null)


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


static func object(
	mode: BuildMode, def_id: StringName, anchor: Vector2i, turn: int, tint: Material
) -> void:
	var def := BuildCatalog.get_def(def_id)
	var node := BuildView.make_object_node(def, tint)
	node.transform = BuildView.object_transform(mode.grid, def.footprint(anchor, turn), turn)
	node.scale = Vector3.ONE * 1.02
	mode._ghost.add_child(node)
	StationUseCells.draw(mode._ghost, mode.grid, def_id, anchor, turn)


## The cells the ghost tints as covered while `edit` places a screen stand:
## ScreenCoverage.covered_cells() where it would stand; empty for any other edit.
static func coverage_preview(on_grid: BuildGrid, edit: BuildEdit) -> Array[Vector2i]:
	if edit.kind != BuildEdit.Kind.PLACE_OBJECT or edit.def_id != ScreenCoverage.SCREEN_ID:
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
