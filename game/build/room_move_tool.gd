class_name RoomMoveTool
extends Node3D
## Picking up a built room, turning it and setting it down (decision
## move-rooms-technical-design-roommove-plan-of-existing-edits; the moves
## themselves are RoomMove's). A child of BuildMode, which makes it in
## _ready().
##
## Pick up: a press inside a room of the picked room tool's type, away from the
## band of its edge (the edge resizes, RoomResize), lifts the room. That press
## could only have started a new room on top of it, which ROOM_OVERLAP always
## refuses, so the gesture was free. Then the ghost (the room's slab and its
## pieces) follows the pointer, green or red, the status line and the card
## beside the ghost say why a spot is refused, and R turns it a quarter. The
## original room stays drawn, dimmed, until it is set down.
##
## Set down: a click commits RoomMove.commit() as one undo step. A refused
## spot changes nothing and the room stays in hand. Esc, a right-click or any
## tool change drops it with no change, and so does a click on the spot it
## was lifted from. The cost line shows only the new floor the spot needs.
##
## Not done here: the cells that must stay clear for passengers leaving the
## room (RoomMove's keep_clear, passed empty until the passenger slice).

signal status_changed(text: String)
## Emitted when a room is picked up, dropped or turned.
signal active_changed

const DIM_TINT := Color(0.0, 0.0, 0.0, 0.4)
const HINT := "%s: click to set down, right-click cancels"
const MOVED := "Moved %s"
const MOVED_PAID := "Moved %s for %d"

## True while a room is in hand.
var active := false
## The room in hand, 0 for none.
var room_id := 0
## Quarter turns of the room in hand (R).
var turns := 0

var _mode: BuildMode
var _ghost := Node3D.new()
var _dim := Node3D.new()
var _status := ""
var _revision := 0
var _key := ""
var _from := Rect2i()
## The plan under the pointer, or null while the pointer is off the grid.
var _plan: RoomMove = null
var _valid_material := _tint(BuildMode.VALID_TINT)
var _invalid_material := _tint(BuildMode.INVALID_TINT)
var _dim_material := _tint(DIM_TINT)


static func _tint(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


func _ready() -> void:
	name = "RoomMoveTool"
	_mode = get_parent() as BuildMode
	if _mode == null:
		push_error("RoomMoveTool: must be a child of BuildMode")
		return
	_ghost.name = "RoomMoveGhost"
	add_child(_ghost)
	_dim.name = "RoomMoveDim"
	add_child(_dim)
	_mode.tool_changed.connect(func(_tool: BuildMode.Tool) -> void: cancel())
	_mode.grid.edit_applied.connect(func(_e: BuildEdit, _r: BuildResult) -> void: _revision += 1)
	_mode.grid.graph_changed.connect(func(_cells: Array[Vector2i]) -> void: _revision += 1)


func _process(_delta: float) -> void:
	if active:
		hover_at(_pointer_cell())


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	var click := event as InputEventMouseButton
	if event.is_action_pressed("build_rotate"):
		rotate_turns()
	elif event.is_action_pressed("build_apply"):
		var cell: Variant = _pointer_cell()
		if cell != null:
			set_down(cell)
	elif (
		event.is_action_pressed("build_tool_none")
		or (click != null and click.pressed and click.button_index == MOUSE_BUTTON_RIGHT)
	):
		cancel()
	else:
		return
	get_viewport().set_input_as_handled()


## Lifts the room of `type` under ground `point`, unless the point is outside
## every such room. Returns whether a room is now in hand. A room that cannot
## move at all (a check-in desk or a piece across its edge, whatever the spot)
## stays put and the status line says why.
func pick_up(point: Vector3, type: StringName) -> bool:
	var grid := _mode.grid
	var id := grid.room_at(grid.world_to_cell(point))
	if id == 0 or grid.get_room(id)["type"] != type:
		return false
	var rect: Rect2i = grid.get_room(id)["rect"]
	var whole := RoomMove.plan(grid, id, _centre_of(rect), 0)
	if _never_moves(whole.result):
		_set_status("%s  %s" % [_name_of(id), whole.result.reason_text()])
		return false
	active = true
	room_id = id
	turns = 0
	_from = rect
	_plan = null
	_key = ""
	_dim_original()
	_set_status(HINT % _name_of(id))
	active_changed.emit()
	return true


func rotate_turns() -> void:
	turns = (turns + 1) % 4
	_key = ""
	active_changed.emit()


## Drops the room in hand with no change.
func cancel() -> void:
	if not active:
		return
	active = false
	room_id = 0
	turns = 0
	_plan = null
	_key = ""
	_clear_ghost()
	_clear_dim()
	_set_status(_mode.status_text())
	active_changed.emit()


## The move of the room in hand to centre `centre` under the current turn.
func plan_at(centre: Vector2i) -> RoomMove:
	return RoomMove.plan(_mode.grid, room_id, centre, turns, _mode.wallet())


## Sets the room down centred on `centre` as one undo step. A refusal changes
## nothing, keeps the room in hand and says why. A spot that is the room's own
## place unturned is a cancel. Returns the result, or null for that cancel.
func set_down(centre: Vector2i) -> BuildResult:
	var name_of := _name_of(room_id)
	var move := plan_at(centre)
	if turns == 0 and move.to_rect == _from:
		cancel()
		return null
	var id := room_id
	var result := RoomMove.commit(
		_mode.grid, id, centre, turns, _mode.wallet(), _mode.undo_history()
	)
	if not result.ok:
		_set_status("%s  %s" % [name_of, result.reason_text()])
		return result
	var note := MOVED % name_of if move.cost <= 0 else MOVED_PAID % [name_of, move.cost]
	active = false
	room_id = 0
	turns = 0
	_plan = null
	_key = ""
	_clear_ghost()
	_clear_dim()
	_set_status(note)
	active_changed.emit()
	_mode.grid_changed.emit()
	return result


## The refusal of the move under the pointer, or null when it is allowed or the
## pointer is off the grid (GhostReason shows it beside the ghost).
func refusal() -> BuildResult:
	if not active or _plan == null or _plan.result.ok:
		return null
	return _plan.result


## The cost line's numbers (what the new floor costs, what the wallet must
## hold), zero while nothing is in hand or the pointer is off the grid.
func preview_price() -> Vector2i:
	if not active or _plan == null:
		return Vector2i.ZERO
	return Vector2i(_plan.cost, _plan.cost)


## The node the ghost's meshes hang under (GhostReason reads its bounds).
func ghost_node() -> Node3D:
	return _ghost


func status_text() -> String:
	return _status


## Redraws the ghost and the status line when the cell, the turn, the grid or
## the balance changed. A room another action changed or removed ends the move.
func hover_at(cell: Variant) -> void:
	if not active:
		return
	var room := _mode.grid.get_room(room_id)
	if room.is_empty() or room["rect"] != _from:
		cancel()
		return
	var balance := _mode.wallet().balance if _mode.wallet() != null else 0
	var key := "%s:%d:%d:%d" % [cell, turns, _revision, balance]
	if key == _key:
		return
	_key = key
	_clear_ghost()
	_plan = null
	if cell == null:
		return
	_plan = plan_at(cell)
	var ok := _plan.result.ok
	var material := _valid_material if ok else _invalid_material
	_ghost_slab(_plan.to_rect, material)
	var shaped := {}
	for edit in _plan.edits:
		if edit.kind == BuildEdit.Kind.RESHAPE_BELT:
			shaped[edit.cell] = edit
	for edit in _plan.edits:
		if edit.kind == BuildEdit.Kind.PLACE_OBJECT:
			_ghost_piece(shaped.get(edit.cell, edit), material)
	var text := HINT % _name_of(room_id)
	if not ok:
		text = "%s  %s" % [_name_of(room_id), _plan.result.reason_text()]
	_set_status(text)


## True for a refusal that holds wherever the room goes.
static func _never_moves(result: BuildResult) -> bool:
	return (
		result.reason == BuildResult.Reason.MOVE_UNMOVABLE
		or result.reason == BuildResult.Reason.MOVE_STRADDLES
	)


static func _centre_of(rect: Rect2i) -> Vector2i:
	return rect.position + (rect.size - Vector2i.ONE) / 2


func _name_of(id: int) -> String:
	var room := _mode.grid.get_room(id)
	return RoomTypes.get_type(room["type"]).display_name if not room.is_empty() else ""


## The grid cell under the pointer, or null off the grid or over the HUD.
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


func _dim_original() -> void:
	_clear_dim()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(_from.size.x, 1.0, _from.size.y)
	var box := MeshInstance3D.new()
	box.name = "Dim"
	box.mesh = mesh
	box.material_override = _dim_material
	box.position = (
		_mode.grid.cell_to_world(_from.position)
		+ Vector3((_from.size.x - 1) / 2.0, 0.5, (_from.size.y - 1) / 2.0)
	)
	_dim.add_child(box)


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


func _ghost_piece(edit: BuildEdit, material: Material) -> void:
	var def := BuildCatalog.get_def(edit.def_id)
	var node := BuildView.make_object_node(def, material)
	node.name = "Piece"
	node.transform = BuildView.object_transform(
		_mode.grid, def.footprint(edit.cell, edit.facing), edit.facing
	)
	node.scale = Vector3.ONE * 1.02
	_ghost.add_child(node)


func _clear_ghost() -> void:
	for child in _ghost.get_children():
		_ghost.remove_child(child)
		child.queue_free()


func _clear_dim() -> void:
	for child in _dim.get_children():
		_dim.remove_child(child)
		child.queue_free()


func _set_status(text: String) -> void:
	if text == _status:
		return
	_status = text
	status_changed.emit(text)
