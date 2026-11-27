class_name ObjectMoveTool
extends Node3D
## Picking up a single placed object (inside a room or loose on the floor),
## turning it with R, and setting it down atomically at $0 net cost as one
## undo step. A child of BuildMode, created in _ready().

signal status_changed(text: String)
signal active_changed

const DIM_TINT := Color(0.0, 0.0, 0.0, 0.4)
const IN_SERVICE_TEXT := "Can't move while in use"

var active := false
var object_id := 0
var turns := 0

var _mode: BuildMode
var _sim_ref: PassengerSim
var _ghost := Node3D.new()
var _status := ""
var _revision := 0
var _key := ""
var _def_id: StringName = &""
var _from_anchor := Vector2i.ZERO
var _from_facing := 0
var _from_paid := 0
var _held := {}
var _has_plan := false
var _plan_anchor := Vector2i.ZERO
var _plan_edits: Array[BuildEdit] = []
var _plan_result: BuildResult = null
var _dimmed := {}
var _valid_material := _tint(BuildMode.VALID_TINT)
var _invalid_material := _tint(BuildMode.INVALID_TINT)
var _dim_material := _tint(DIM_TINT)
var _coverage_material := _tint(BuildMode.COVERAGE_TINT)


static func _tint(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


func _ready() -> void:
	name = "ObjectMoveTool"
	_mode = get_parent() as BuildMode
	if _mode == null:
		push_error("ObjectMoveTool: must be a child of BuildMode")
		return
	_ghost.name = "ObjectMoveGhost"
	add_child(_ghost)
	_mode.tool_changed.connect(func(_tool: BuildMode.Tool) -> void: cancel())
	_mode.grid.edit_applied.connect(func(_e: BuildEdit, _r: BuildResult) -> void: _revision += 1)
	_mode.grid.graph_changed.connect(func(_cells: Array[Vector2i]) -> void: _revision += 1)


func _process(_delta: float) -> void:
	if active:
		hover_at(_pointer_point())


func _unhandled_input(event: InputEvent) -> void:
	if not active:
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
		var point: Variant = _pointer_point()
		if point != null:
			set_down(point)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_tool_none"):
		cancel()
		get_viewport().set_input_as_handled()


static func is_unmovable_def(def_id: StringName) -> bool:
	return (
		def_id == &"checkin_desk"
		or def_id == &"security_scanner"
		or def_id == SecurityLanes.ARCH
		or SecurityLanes.is_part(def_id)
		or BuildCatalog.is_any_door(def_id)
	)


## Reason object `id` cannot be picked up to move, or null when it can.
static func never_moves_refusal(grid: BuildGrid, id: int) -> BuildResult:
	if grid == null:
		return BuildResult.refused(BuildResult.Reason.NO_OBJECT)
	var record := grid.get_object(id)
	if record.is_empty():
		return BuildResult.refused(BuildResult.Reason.NO_OBJECT)
	var def_id := StringName(record["def"])
	if is_unmovable_def(def_id):
		return BuildResult.refused(BuildResult.Reason.MOVE_UNMOVABLE, id)
	if def_id == GateDesks.DESK or def_id == GateDesks.BUS_DESK or def_id == RemoteStands.STAND_ID:
		var removal := grid.validate(BuildEdit.remove_object(id))
		if not removal.ok:
			return removal
	return null


## Non-empty translated reason when `id` is actively serving or occupied, else "".
static func in_service_reason(grid: BuildGrid, id: int, sim: PassengerSim = null) -> String:
	if grid == null or sim == null or id <= 0:
		return ""
	if _object_busy(grid, id, sim):
		return TranslationServer.translate("Can't move while in use")
	return ""


static func _object_busy(grid: BuildGrid, id: int, sim: PassengerSim) -> bool:
	if (
		sim.cafes.serving_at(id) != 0
		or not sim.cafes.queue_of(id).is_empty()
		or sim.info_desks.helping_at(id)
		or StaffPosts.in_service(sim, id)
		or (GateDesks.is_desk(grid, id) and StaffBreaks._gate_desk_active(sim, id))
	):
		return true
	for pid in sim.passenger_ids():
		var p := sim.get_passenger(pid)
		if (
			p != null
			and not p.is_done()
			and (p.station == id or p.seat_object == id or sim.info_desks.desk_of(p) == id)
		):
			return true
	return _visit_busy(grid, id, sim)


static func _visit_busy(grid: BuildGrid, id: int, sim: PassengerSim) -> bool:
	var counter_room := ShopCounters.room_of(grid, id) if ShopCounters.is_counter(grid, id) else 0
	for vid in sim.shops.visit_ids():
		var visit := sim.shops.visit_of(vid)
		if (
			visit != null
			and (visit.display == id or (counter_room > 0 and visit.room == counter_room))
		):
			return true
	for vid in sim.toilets.visit_ids():
		var visit := sim.toilets.visit_of(vid)
		if visit != null and visit.stall_id == id:
			return true
	for vid in sim.cafes.visit_ids():
		var visit := sim.cafes.visit_of(vid)
		if visit != null and (visit.counter == id or int(visit.seat.get("object_id", 0)) == id):
			return true
	return false


func pick_up(id: int, sim: PassengerSim = null) -> bool:
	if _mode == null or _mode.grid == null:
		return false
	var refusal_res := never_moves_refusal(_mode.grid, id)
	if refusal_res != null:
		var msg := refusal_res.reason_text()
		_set_status(msg)
		_mode.notify_refusal(msg)
		return false
	var active_sim := sim if sim != null else _find_sim()
	var busy := in_service_reason(_mode.grid, id, active_sim)
	if busy != "":
		_set_status(busy)
		_mode.notify_refusal(busy)
		return false
	if _mode.room_mover.active:
		_mode.room_mover.cancel()
	_mode.templates.disarm()
	if _mode.starter_kit != null and _mode.starter_kit.is_active():
		_mode.starter_kit.disarm()
	if _mode.tool != BuildMode.Tool.NONE:
		_mode.set_tool(BuildMode.Tool.NONE)
	var record := _mode.grid.get_object(id)
	active = true
	object_id = id
	_sim_ref = active_sim
	_def_id = StringName(record["def"])
	_from_anchor = record["anchor"]
	_from_facing = posmod(int(record["facing"]), 4)
	_from_paid = int(record.get("paid", 0))
	turns = _from_facing
	_held = record.duplicate()
	_has_plan = false
	_plan_edits.clear()
	_plan_result = null
	_key = ""
	_dim_original()
	_set_status(_hint())
	active_changed.emit()
	return true


func rotate_turns() -> void:
	if not active:
		return
	turns = (turns + 1) % 4
	_key = ""
	active_changed.emit()


func cancel() -> void:
	if not active:
		return
	active = false
	object_id = 0
	turns = 0
	_sim_ref = null
	_def_id = &""
	_held.clear()
	_has_plan = false
	_plan_edits.clear()
	_plan_result = null
	_key = ""
	_clear_ghost()
	_clear_dim()
	_set_status(_mode.status_text())
	active_changed.emit()


func plan_at(target: Variant) -> Dictionary:
	var grid := _mode.grid
	var anchor := _target_anchor(target)
	var norm_turns := posmod(turns, 4)
	var remove_edit := BuildEdit.remove_object(object_id)
	var place_edit := BuildEdit.place_object(_def_id, anchor, norm_turns)
	place_edit.object_id = object_id
	place_edit.paid = _from_paid
	var edits: Array[BuildEdit] = [remove_edit, place_edit]
	var keep_clear := _kept_clear(grid)
	var rule := func(on: BuildGrid, edit: BuildEdit) -> BuildResult:
		return _rule_problem(on, edit, keep_clear)
	var scratch := BuildUndo.trial_copy_of(grid)
	var result := scratch.apply_sequence(edits, rule)
	if result.ok:
		var touched := _touched_cells(anchor, norm_turns)
		var reshapes := BeltShaper.reshape_edits(scratch, BeltShaper.around(touched))
		if not reshapes.is_empty():
			var reshape_result := scratch.apply_sequence(reshapes, Callable())
			if not reshape_result.ok:
				result = reshape_result
			else:
				edits.append_array(reshapes)
	return {"anchor": anchor, "edits": edits, "result": result}


func hover_at(target: Variant) -> void:
	if not active:
		return
	if _held_changed():
		cancel()
		return
	var anchor: Variant = null if target == null else _target_anchor(target)
	var key := "%s:%d:%d" % [anchor, turns, _revision]
	if key == _key:
		return
	_key = key
	_clear_ghost()
	_has_plan = false
	_plan_edits.clear()
	_plan_result = null
	if anchor == null:
		return
	var planned := plan_at(anchor)
	_has_plan = true
	_plan_anchor = planned["anchor"]
	_plan_edits = planned["edits"]
	_plan_result = planned["result"]
	var ok := _plan_result.ok
	var material := _valid_material if ok else _invalid_material
	_draw_ghost(_plan_anchor, posmod(turns, 4), material)
	var text := _hint() if ok else "%s  %s" % [_item_name(), _plan_result.reason_text()]
	var changed := text != _status
	_set_status(text)
	if not ok and changed:
		_mode.refusal_shown.emit(text)


func set_down(target: Variant = null) -> BuildResult:
	if not active or _held_changed():
		if active:
			cancel()
		return null
	var use_target: Variant = _pointer_point() if target == null else target
	if use_target == null:
		return null
	var anchor := _target_anchor(use_target)
	var norm_turns := posmod(turns, 4)
	if anchor == _from_anchor and norm_turns == _from_facing:
		cancel()
		return null
	var busy := in_service_reason(_mode.grid, object_id, _find_sim())
	if busy != "":
		cancel()
		_set_status(busy)
		_mode.notify_refusal(busy)
		return null
	var planned := plan_at(anchor)
	var result: BuildResult = planned["result"]
	var edits: Array[BuildEdit] = planned["edits"]
	if result.ok:
		result = _commit_move(edits)
	if not result.ok:
		_apply_refusal(anchor, edits[1], result)
		return result
	_finish_move(anchor, norm_turns)
	return result


func refusal() -> BuildResult:
	if not active or not _has_plan or _plan_result == null or _plan_result.ok:
		return null
	return _plan_result


func ghost_node() -> Node3D:
	return _ghost


func status_text() -> String:
	return _status


func footprint_cells() -> Array[Vector2i]:
	if not active or not _has_plan:
		return []
	var def := BuildCatalog.get_def(_def_id)
	return def.footprint(_plan_anchor, posmod(turns, 4)) if def != null else [_plan_anchor]


func _commit_move(edits: Array[BuildEdit]) -> BuildResult:
	var grid := _mode.grid
	var keep_clear := _kept_clear(grid)
	var rule := func(on: BuildGrid, edit: BuildEdit) -> BuildResult:
		return _rule_problem(on, edit, keep_clear)
	var history := _mode.undo_history()
	history.begin_action()
	var snapshot := grid.to_snapshot()
	var receipt := grid.recorder
	var recorded := receipt.inverses.size() if receipt != null else 0
	var mark := grid.hold_signals()
	grid.begin_batch()
	var result := grid.apply_sequence(edits, rule)
	if not result.ok:
		grid.recorder = null
		var restored := grid.from_snapshot(snapshot)
		grid.recorder = receipt
		if restored:
			if receipt != null:
				receipt.inverses.resize(recorded)
			grid.release_signals(mark)
		else:
			push_error("ObjectMoveTool: restoring the grid failed")
			grid.release_signals()
		grid.end_batch()
		history.end_action()
		return result
	grid.end_batch()
	grid.release_signals()
	history.end_action()
	return result


func _apply_refusal(anchor: Vector2i, place_edit: BuildEdit, result: BuildResult) -> void:
	hover_at(anchor)
	_mode.grid.edit_refused.emit(place_edit, result)
	var msg := "%s  %s" % [_item_name(), result.reason_text()]
	_set_status(msg)
	_mode.notify_refusal(msg)


func _finish_move(anchor: Vector2i, norm_turns: int) -> void:
	var moved_id := object_id
	var item_name := _item_name()
	var def := BuildCatalog.get_def(_def_id)
	var moved_cells: Array[Vector2i] = (
		def.footprint(anchor, norm_turns) if def != null else ([anchor] as Array[Vector2i])
	)
	active = false
	object_id = 0
	turns = 0
	_sim_ref = null
	_def_id = &""
	_held.clear()
	_has_plan = false
	_plan_edits.clear()
	_plan_result = null
	_key = ""
	_clear_ghost()
	_clear_dim()
	_mode._redraw()
	_set_status(tr("Moved {item}", "object move").format({"item": item_name}))
	active_changed.emit()
	_mode.grid_changed.emit()
	_mode.emit_player_commit(&"object_move", moved_cells, [moved_id], 0)


static func _kept_clear(grid: BuildGrid) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var exits: Callable = grid.get_meta(RoomMove.EXIT_CELLS_META, Callable())
	if exits.is_valid():
		for cell: Vector2i in exits.call():
			if not out.has(cell):
				out.append(cell)
	return out


static func _rule_problem(
	grid: BuildGrid, edit: BuildEdit, keep_clear: Array[Vector2i]
) -> BuildResult:
	if edit.kind == BuildEdit.Kind.PLACE_OBJECT and not keep_clear.is_empty():
		var def := BuildCatalog.get_def(edit.def_id)
		if def != null:
			for cell in def.footprint(edit.cell, edit.facing):
				if keep_clear.has(cell):
					return BuildResult.refused(BuildResult.Reason.MOVE_EXIT_BLOCKED, edit.object_id)
	var problem := DoorPlacement.edge_problem(grid, edit)
	if problem == null:
		problem = BeltShaper.crossing_problem(grid, edit)
	if problem == null:
		problem = LaneWall.problem(grid, edit)
	return problem


func _find_sim() -> PassengerSim:
	if _sim_ref != null and is_instance_valid(_sim_ref):
		return _sim_ref
	if _mode == null or not _mode.is_inside_tree():
		return null
	var parent := _mode.get_parent()
	if parent == null:
		return null
	var named := parent.get_node_or_null("PassengerSim") as PassengerSim
	if named != null:
		return named
	for child in parent.get_children():
		if child is PassengerSim:
			return child as PassengerSim
	return null


func _target_anchor(target: Variant) -> Vector2i:
	if target is Vector2i:
		return target
	return BuildMode.object_anchor(_mode.grid, _def_id, target as Vector3, posmod(turns, 4))


func _touched_cells(new_anchor: Vector2i, new_facing: int) -> Array[Vector2i]:
	var def := BuildCatalog.get_def(_def_id)
	if def == null:
		return [_from_anchor, new_anchor]
	var cells := def.footprint(_from_anchor, _from_facing)
	cells.append_array(def.footprint(new_anchor, new_facing))
	return cells


func _held_changed() -> bool:
	return _mode.grid.get_object(object_id) != _held


func _item_name() -> String:
	var def := BuildCatalog.get_def(_def_id)
	return DisplayWords.item(def.display_name) if def != null else ""


func _hint() -> String:
	return tr("{item}: click to set down, right-click cancels", "object move").format(
		{"item": _item_name()}
	)


func _pointer_point() -> Variant:
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
	return point if _mode.grid.in_bounds(cell) else null


func _dim_original() -> void:
	_clear_dim()
	var node := _mode.object_node(object_id)
	if node == null:
		return
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		_dimmed[mesh] = (mesh as MeshInstance3D).material_override
		(mesh as MeshInstance3D).material_override = _dim_material


func _clear_dim() -> void:
	for mesh in _dimmed:
		if is_instance_valid(mesh):
			(mesh as MeshInstance3D).material_override = _dimmed[mesh]
	_dimmed.clear()


func _draw_ghost(anchor: Vector2i, facing: int, material: Material) -> void:
	var def := BuildCatalog.get_def(_def_id)
	if def == null:
		return
	var node := BuildView.make_object_node(def, material)
	node.name = "Object"
	node.transform = BuildView.object_transform(_mode.grid, def.footprint(anchor, facing), facing)
	node.scale = Vector3.ONE * 1.02
	_ghost.add_child(node)
	StationUseCells.draw(_ghost, _mode.grid, _def_id, anchor, facing)
	if _def_id == ScreenCoverage.SCREEN_ID:
		for cell in ScreenCoverage.covered_cells(_mode.grid, anchor, facing):
			var box_mesh := BoxMesh.new()
			box_mesh.size = Vector3(0.96, 0.08, 0.96)
			var tile := MeshInstance3D.new()
			tile.name = "Coverage"
			tile.mesh = box_mesh
			tile.material_override = _coverage_material
			tile.position = _mode.grid.cell_to_world(cell) + Vector3(0.0, 0.06, 0.0)
			_ghost.add_child(tile)


func _clear_ghost() -> void:
	for child in _ghost.get_children():
		_ghost.remove_child(child)
		child.queue_free()


func _set_status(text: String) -> void:
	if text == _status:
		return
	_status = text
	status_changed.emit(text)
