class_name StarterKitTool
extends Node3D
## Previews, rotates, and places Furnished Starter Room Kits (StarterRoomKits)
## as one atomic composite transaction through BuildTransaction.commit_composite()
## and one UndoStack entry. A child of BuildMode, keeping Tool.NONE while armed.

signal status_changed(text: String)
signal armed_changed

var armed: StringName = &""
var turns := 0

var _mode: BuildMode
var _ghost := Node3D.new()
var _status := ""
var _revision := 0
var _note := ""
var _note_cell := Vector2i.ZERO
var _key := ""
var _preview_key: Array = []
var _cached_preview := {}
var _plan_builds := 0
var _ghost_builds := 0
var _valid_material := _tint(BuildMode.VALID_TINT)
var _invalid_material := _tint(BuildMode.INVALID_TINT)
var _wall_block_material := BuildGhost.material(BuildMode.WALL_BLOCK_TINT, true)


static func _tint(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


func _ready() -> void:
	name = "StarterKitTool"
	_mode = get_parent() as BuildMode
	if _mode == null:
		push_error("StarterKitTool: must be a child of BuildMode")
		return
	_ghost.name = "StarterKitGhost"
	add_child(_ghost)
	_mode.tool_changed.connect(_on_tool_changed)
	_mode.grid.edit_applied.connect(_on_grid_edit)
	_mode.grid.graph_changed.connect(_on_grid_graph)
	if _mode.grid is SiteGrid and (_mode.grid as SiteGrid).land != null:
		(_mode.grid as SiteGrid).land.changed.connect(_on_grid_changed)


func _exit_tree() -> void:
	_invalidate_cache()


func _process(_delta: float) -> void:
	if not is_active():
		return
	_hover(_pointer_cell())


func _unhandled_input(event: InputEvent) -> void:
	if not is_active():
		return
	if event.is_action_pressed("build_rotate"):
		rotate_turns()
		get_viewport().set_input_as_handled()
	elif (
		event.is_action_pressed("build_apply")
		and not (
			event is InputEventWithModifiers and (event as InputEventWithModifiers).alt_pressed
		)
	):
		var cell: Variant = _pointer_cell()
		if cell != null:
			place_at(cell)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_tool_none"):
		disarm()
		get_viewport().set_input_as_handled()


func is_active() -> bool:
	return armed != &""


func lock_text(kit_id: StringName) -> String:
	if _mode == null or not StarterRoomKits.has_kit(kit_id):
		return ""
	return StarterRoomKits.lock_text(kit_id, _mode.unlocks, _mode.require_unlocks)


func try_arm(kit_id: StringName) -> bool:
	if not StarterRoomKits.has_kit(kit_id):
		push_error("StarterKitTool.try_arm: unknown kit '%s'" % kit_id)
		return false
	var locked := lock_text(kit_id)
	if locked != "":
		armed = &""
		_clear_ghost()
		_invalidate_cache()
		_set_status(locked)
		armed_changed.emit()
		_mode.notify_refusal(locked)
		return false
	arm(kit_id)
	return true


func arm(kit_id: StringName) -> void:
	if not StarterRoomKits.has_kit(kit_id):
		push_error("StarterKitTool.arm: unknown kit '%s'" % kit_id)
		return
	if _mode != null:
		_mode.templates.disarm()
		if _mode.room_mover.active:
			_mode.room_mover.cancel()
		if _mode.object_mover.active:
			_mode.object_mover.cancel()
		if _mode.tool != BuildMode.Tool.NONE:
			_mode.set_tool(BuildMode.Tool.NONE)
	armed = kit_id
	turns = 0
	_note = ""
	_invalidate_cache()
	_set_status(
		tr("{kit}: click to place", "build status").format(
			{"kit": BuildMenuCatalog.shown(StarterRoomKits.display_name(kit_id))}
		)
	)
	armed_changed.emit()


func disarm() -> void:
	if not is_active():
		return
	armed = &""
	_note = ""
	_clear_ghost()
	_invalidate_cache()
	_set_status(_mode.status_text() if _mode != null else "")
	armed_changed.emit()


func rotate_turns() -> void:
	turns = (turns + 1) % 4
	_invalidate_cache()
	armed_changed.emit()


func plan_at(cell: Vector2i) -> Dictionary:
	var cached := _preview_at(cell)
	var wallet := _mode.wallet()
	var net: int = 0 if wallet == null else int(cached["net"])
	return {"edits": cached["edits"], "result": _result_for_wallet(cached), "net": net}


func check_at(cell: Vector2i) -> BuildResult:
	return plan_at(cell)["result"]


func place_at(cell: Vector2i) -> BuildResult:
	var kit_name := BuildMenuCatalog.shown(StarterRoomKits.display_name(armed))
	var edits := StarterRoomKits.plan(_mode.grid, armed, cell, turns)
	var rule := StarterRoomKits.placement_rule(armed, cell, turns)
	var history := _mode.undo_history()
	var before := _balance()
	history.begin_action()
	var result := BuildTransaction.commit_composite(
		_mode.grid, edits, _mode.wallet(), _mode.unlocks, _mode.require_unlocks, rule
	)
	if result.ok:
		var rect := StarterRoomKits.rect_at(armed, cell, turns)
		BuildDrags.reshape_belts(_mode, BuildDrags.rect_cells(rect))
	history.end_action()
	if not result.ok:
		var msg := "%s  %s" % [kit_name, result.reason_text()]
		_set_status(msg)
		_mode.notify_refusal(msg)
		return result
	var spent := before - _balance()
	_note = tr("Placed {kit} for {cost}", "build status").format({"kit": kit_name, "cost": spent})
	_note_cell = cell
	_set_status(_note)
	_invalidate_cache()
	_mode._redraw()
	_mode.grid_changed.emit()
	var rect := StarterRoomKits.rect_at(armed, cell, turns)
	var placed_ids: Array[int] = []
	for edit: BuildEdit in edits:
		if edit.kind == BuildEdit.Kind.PLACE_OBJECT:
			var oid := _mode.grid.object_at(edit.cell)
			if oid != 0 and not placed_ids.has(oid):
				placed_ids.append(oid)
	_mode.emit_player_commit(&"starter_kit", BuildDrags.rect_cells(rect), placed_ids, spent)
	return result


func preview_price() -> Vector2i:
	var cell: Variant = _pointer_cell() if is_active() else null
	if cell == null:
		return Vector2i.ZERO
	return preview_price_at(cell)


func preview_price_at(cell: Vector2i) -> Vector2i:
	if not is_active() or _mode == null or _mode.grid == null:
		return Vector2i.ZERO
	var cached := _preview_at(cell)
	if not (cached["result"] as BuildResult).ok:
		return Vector2i.ZERO
	var net := maxi(0, int(cached["net"]))
	return Vector2i(net, net)


func status_text() -> String:
	return _status


func _on_tool_changed(new_tool: BuildMode.Tool) -> void:
	if new_tool != BuildMode.Tool.NONE:
		disarm()


func _pointer_cell() -> Variant:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	var override := _mode.pointer_override
	if override.x < 0.0 and get_viewport().gui_get_hovered_control() != null:
		return null
	var at := override if override.x >= 0.0 else get_viewport().get_mouse_position()
	var point: Variant = _mode.grid_point(
		camera.project_ray_origin(at), camera.project_ray_normal(at)
	)
	if point == null:
		return null
	var cell := _mode.grid.world_to_cell(point)
	return cell if _mode.grid.in_bounds(cell) else null


func _hover(cell: Variant) -> void:
	if cell == null:
		var empty_key := "null:%s:%d:%d" % [armed, turns, _revision]
		if empty_key == _key:
			return
		_key = empty_key
		_clear_ghost()
		return
	var cached := _preview_at(cell)
	var checked := _result_for_wallet(cached)
	var note_flag := 1 if (_note != "" and cell == _note_cell) else 0
	var key := (
		"%s:%s:%d:%d:%s:%d:%s:%d"
		% [cell, armed, turns, _revision, checked.ok, checked.reason, checked.detail, note_flag]
	)
	if not checked.ok:
		key += ":" + str(checked.detail_args)
	if key == _key:
		return
	_key = key
	_clear_ghost()
	_ghost_builds += 1
	var kit_name := BuildMenuCatalog.shown(StarterRoomKits.display_name(armed))
	var material := _valid_material if checked.ok else _invalid_material
	for edit: BuildEdit in cached["edits"]:
		if edit.kind == BuildEdit.Kind.PLACE_ROOM:
			_ghost_slab(Rect2i(edit.cell, edit.room_size), material)
		elif edit.kind == BuildEdit.Kind.PLACE_WALL:
			_ghost_wall(edit.cell, edit.side, edit.wall_kind, material)
		elif edit.kind == BuildEdit.Kind.PLACE_OBJECT:
			_ghost_piece(edit, material)
	_ghost_door_entry(cell)
	var text := tr("{kit}: click to place", "build status").format({"kit": kit_name})
	var is_refusal := not checked.ok
	if not checked.ok:
		text = "%s  %s" % [kit_name, checked.reason_text()]
	if _note != "" and cell == _note_cell:
		text = _note
		is_refusal = false
	else:
		_note = ""
	var changed := text != _status
	_set_status(text)
	if is_refusal and changed:
		_mode.refusal_shown.emit(text)


func _ghost_slab(area: Rect2i, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(area.size.x - 0.04, 0.08, area.size.y - 0.04)
	var slab := MeshInstance3D.new()
	slab.name = "Room"
	slab.mesh = mesh
	slab.material_override = material
	slab.position = (
		_mode.grid.cell_to_world(area.position)
		+ Vector3((area.size.x - 1) / 2.0, 0.06, (area.size.y - 1) / 2.0)
	)
	_ghost.add_child(slab)


func _ghost_wall(cell: Vector2i, side: int, wall_kind: int, material: Material) -> void:
	var extent := Vector3(
		1.0,
		BuildView.WALL_HEIGHT * (0.55 if wall_kind == BuildGrid.WallKind.DOOR else 1.0),
		BuildView.WALL_THICKNESS * 1.5
	)
	var mesh := BoxMesh.new()
	mesh.size = extent
	var wall_node := MeshInstance3D.new()
	wall_node.name = "DoorWall" if wall_kind == BuildGrid.WallKind.DOOR else "Wall"
	wall_node.mesh = mesh
	wall_node.material_override = material
	wall_node.transform = BuildView.wall_transform(_mode.grid, cell, side).translated_local(
		Vector3(0.0, extent.y / 2.0, 0.0)
	)
	_ghost.add_child(wall_node)


func _ghost_piece(edit: BuildEdit, material: Material) -> void:
	var def := BuildCatalog.get_def(edit.def_id)
	var node := BuildView.make_object_node(def, material)
	node.name = "Piece"
	node.transform = BuildView.object_transform(
		_mode.grid, def.footprint(edit.cell, edit.facing), edit.facing
	)
	node.scale = Vector3.ONE * 1.02
	_ghost.add_child(node)
	StationUseCells.draw(_ghost, _mode.grid, edit.def_id, edit.cell, edit.facing)


func _ghost_door_entry(cell: Vector2i) -> void:
	var door := StarterRoomKits.door_edge(armed, cell, turns)
	if door.is_empty():
		return
	var door_cell: Vector2i = door["cell"]
	var door_side: int = door["side"]
	var outside: Vector2i = door["outside"]
	var blocked := StarterRoomKits.door_problem(_mode.grid, armed, cell, turns) != null
	StationUseCells.draw_door_entry(_ghost, _mode.grid, outside, door_cell, door_side, blocked)
	if blocked:
		_ghost_wall_block(door_cell, door_side)


func _ghost_wall_block(cell: Vector2i, side: int) -> void:
	var extent := Vector3(1.04, BuildGhost.WALL_BLOCK_HEIGHT, BuildGhost.WALL_BLOCK_DEPTH)
	var mesh := BoxMesh.new()
	mesh.size = extent
	var bar := MeshInstance3D.new()
	bar.name = "DoorBlockBar"
	bar.mesh = mesh
	bar.material_override = _wall_block_material
	bar.transform = BuildView.wall_transform(_mode.grid, cell, side).translated_local(
		Vector3(0.0, extent.y / 2.0, 0.0)
	)
	bar.set_meta("role", "DoorBlockBar")
	bar.set_meta("cell", cell)
	bar.set_meta("side", side)
	_ghost.add_child(bar)


func _clear_ghost() -> void:
	for child in _ghost.get_children():
		_ghost.remove_child(child)
		child.queue_free()


func _balance() -> int:
	return _mode.wallet().balance if _mode.wallet() != null else 0


func _set_status(text: String) -> void:
	if text == _status:
		return
	_status = text
	status_changed.emit(text)


func _invalidate_cache() -> void:
	_key = ""
	_preview_key = []
	_cached_preview = {}


func _on_grid_edit(_edit: BuildEdit, _result: BuildResult) -> void:
	_on_grid_changed()


func _on_grid_graph(_cells: Array[Vector2i]) -> void:
	_on_grid_changed()


func _on_grid_changed() -> void:
	_revision += 1
	_invalidate_cache()


func _preview_key_for(cell: Vector2i) -> Array:
	var grid_id := _mode.grid.get_instance_id() if _mode.grid != null else 0
	var unlocks := _mode.unlocks
	var unlocks_id := unlocks.get_instance_id() if unlocks != null else 0
	var tier := unlocks.tier() if unlocks != null else -1
	var made := unlocks.made_total() if unlocks != null else 0
	var quality := (
		AirportRating.quality_percent(unlocks.rating.stars())
		if unlocks != null and unlocks.rating != null
		else -1
	)
	return [
		cell,
		armed,
		turns,
		_revision,
		grid_id,
		_mode.require_unlocks,
		unlocks_id,
		tier,
		made,
		quality,
		DemoMode.is_demo(),
	]


func _preview_at(cell: Vector2i) -> Dictionary:
	var key := _preview_key_for(cell)
	if key == _preview_key and not _cached_preview.is_empty():
		return _cached_preview
	_plan_builds += 1
	var grid := _mode.grid
	var edits := StarterRoomKits.plan(grid, armed, cell, turns)
	var rule := StarterRoomKits.placement_rule(armed, cell, turns)
	var staged := BuildTransaction.preview_composite(
		grid, edits, _mode.unlocks, _mode.require_unlocks, rule
	)
	_preview_key = key
	_cached_preview = {
		"edits": edits,
		"result": staged["result"],
		"net": staged["net"],
	}
	return _cached_preview


func _result_for_wallet(cached: Dictionary) -> BuildResult:
	var result: BuildResult = cached["result"]
	var wallet := _mode.wallet()
	if not result.ok or wallet == null:
		return result
	var net := int(cached["net"])
	if net > 0 and not wallet.can_afford(net):
		return BuildResult.refused(BuildResult.Reason.CANT_AFFORD)
	if net < 0 and not wallet.can_credit(-net, Wallet.Category.BUILD):
		return BuildResult.refused(BuildResult.Reason.WALLET_FULL)
	return result
