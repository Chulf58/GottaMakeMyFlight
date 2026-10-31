class_name TemplatePaste
extends Node3D
## Saving and pasting room templates (decision room-templates-store-rooms-
## with-their-pieces-kept-in-each-sa). A child of BuildMode, which makes it in
## _ready() and keeps BuildMode.Tool.NONE while it is armed; the Templates page
## (TemplatesPage) arms it.
##
## Save: arm_capture(), then a click on a room adds its RoomTemplate to
## `library`. Paste: arm(index), then the ghost shows the room and its pieces
## centred on the cell under the pointer, green or red, and the status line
## names the room and any refusal; R turns it a quarter. A click pastes it all
## or nothing: the whole plan is first applied to a copy of the grid (as
## BuildUndo checks an undo), then the wallet must pay for every piece at its
## full price (BuildTransaction.check()); only then is it committed through
## BuildTransaction.commit_plan() inside one UndoStack action, so one Ctrl+Z
## removes the room, its pieces and their price. A refused paste changes
## nothing and says why. Any BuildMode tool change (a key, a card, Esc) disarms
## it.
##
## A paste lays the template's floor on cells that have none (at the floor
## price, in the cost shown first) and reshapes the belts on and next to the
## room (BeltShaper), so a pasted bag room's belt ends where it should. Not
## guaranteed: walls are not laid, and a belt that ran out of the saved room
## is not kept, so the player draws the link to check-in again.

signal status_changed(text: String)
## Emitted when it is armed, disarmed or turned.
signal armed_changed

const PICK_ROOM := "Click a room to save it as a template"
const SAVE_ROOM := "Click to save %s as a template"
const SAVED := "Saved template %s"
const PLACED := "Placed %s for %d"
const PLACE_HINT := "%s: click to place, R turns it"

var library := RoomTemplates.new()
## The template a click pastes, or -1.
var armed := -1
## True while a click saves the room under the pointer.
var capturing := false
## Quarter turns of the paste (R).
var turns := 0

var _mode: BuildMode
var _ghost := Node3D.new()
var _status := ""
var _revision := 0
## What the last paste said, kept on the status line while the pointer stays
## on the cell it was pasted on.
var _note := ""
var _note_cell := Vector2i.ZERO
var _key := ""
var _valid_material := _tint(BuildMode.VALID_TINT)
var _invalid_material := _tint(BuildMode.INVALID_TINT)


static func _tint(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


func _ready() -> void:
	name = "TemplatePaste"
	_mode = get_parent() as BuildMode
	if _mode == null:
		push_error("TemplatePaste: must be a child of BuildMode")
		return
	_ghost.name = "TemplateGhost"
	add_child(_ghost)
	_mode.tool_changed.connect(func(_tool: BuildMode.Tool) -> void: disarm())
	_mode.grid.edit_applied.connect(func(_e: BuildEdit, _r: BuildResult) -> void: _revision += 1)
	_mode.grid.graph_changed.connect(func(_cells: Array[Vector2i]) -> void: _revision += 1)
	library.changed.connect(_on_library_changed)


func _process(_delta: float) -> void:
	if not is_active():
		return
	_hover(_pointer_cell())


func _unhandled_input(event: InputEvent) -> void:
	if not is_active():
		return
	if event.is_action_pressed("build_rotate") and armed >= 0:
		rotate_turns()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_apply"):
		var cell: Variant = _pointer_cell()
		if cell != null:
			click(cell)
		get_viewport().set_input_as_handled()


func is_active() -> bool:
	return armed >= 0 or capturing


## Arms the paste of template `index`, unturned.
func arm(index: int) -> void:
	if index < 0 or index >= library.size():
		push_error("TemplatePaste.arm: no template %d" % index)
		return
	armed = index
	capturing = false
	turns = 0
	_key = ""
	_set_status(PLACE_HINT % library.get_template(index).name)
	armed_changed.emit()


## Arms saving: the next click on a room saves it.
func arm_capture() -> void:
	armed = -1
	capturing = true
	_key = ""
	_set_status(PICK_ROOM)
	armed_changed.emit()


func disarm() -> void:
	if not is_active():
		return
	armed = -1
	capturing = false
	_clear_ghost()
	_key = ""
	_set_status(_mode.status_text())
	armed_changed.emit()


func rotate_turns() -> void:
	turns = (turns + 1) % 4
	_key = ""
	armed_changed.emit()


## A click on `cell`: saves the room there or pastes the armed template.
## Returns the paste's result, or null for a save.
func click(cell: Vector2i) -> BuildResult:
	if capturing:
		save_room(_mode.grid.room_at(cell))
		return null
	return paste_at(cell)


## Saves room `room_id` as a template and ends saving. Returns the template,
## or null (the status line asks again) when there is no such room.
func save_room(room_id: int) -> RoomTemplate:
	var template := RoomTemplate.capture(_mode.grid, room_id)
	if template == null:
		_set_status(PICK_ROOM)
		return null
	library.add(template)
	capturing = false
	_clear_ghost()
	_key = ""
	_set_status(SAVED % template.name)
	armed_changed.emit()
	return template


## The armed template's paste centred on `cell` and whether it may go there:
## {"edits": the plan with its belt reshapes, "result": a BuildResult}. The
## whole plan (floor, room, pieces) runs on a copy of the grid with the belt
## crossing rule (BeltShaper.crossing_problem()); then the belts on and next to
## the room are reshaped there, refused with BELT_CROSSING where a cell would
## have four links; then the wallet must pay for all of it at full price.
func plan_at(cell: Vector2i) -> Dictionary:
	var grid := _mode.grid
	var edits := library.get_template(armed).plan(cell, turns, grid)
	var scratch := BuildGrid.new(grid.size, grid.origin)
	if not scratch.from_snapshot(grid.to_snapshot()):
		push_error("TemplatePaste.plan_at: the grid could not be copied to check the paste")
		return {"edits": edits, "result": BuildResult.refused(BuildResult.Reason.NONE)}
	var result := scratch.apply_sequence(edits, BeltShaper.crossing_problem)
	if result.ok:
		var near := BeltShaper.around(_cells(library.get_template(armed).rect_at(cell, turns)))
		result = _four_links(scratch, near)
		if result.ok:
			var reshapes := BeltShaper.reshape_edits(scratch, near)
			result = scratch.apply_sequence(reshapes, Callable())
			edits.append_array(reshapes)
	if result.ok:
		result = BuildTransaction.check(grid, edits, _mode.wallet())
	return {"edits": edits, "result": result}


## Whether the armed template can be pasted centred on `cell` (plan_at()).
func check_at(cell: Vector2i) -> BuildResult:
	return plan_at(cell)["result"]


## Pastes the armed template centred on `cell`, all or nothing, as one undo
## step, and reshapes the belts it touches. Returns the result; a refusal
## changes nothing.
func paste_at(cell: Vector2i) -> BuildResult:
	var template := library.get_template(armed)
	var planned := plan_at(cell)
	var result: BuildResult = planned["result"]
	if not result.ok:
		_mode.grid.edit_refused.emit(planned["edits"][0], result)
		_set_status("%s  %s" % [template.name, result.reason_text()])
		return result
	# Fresh edits for the live grid: the check applied its own to the copy.
	var edits := template.plan(cell, turns, _mode.grid)
	for edit in planned["edits"]:
		if edit.kind == BuildEdit.Kind.RESHAPE_BELT:
			edits.append(edit)
	var history := _mode.undo_history()
	var before := _balance()
	history.begin_action()
	result = BuildTransaction.commit_plan(_mode.grid, edits, _mode.wallet())
	history.end_action()
	if not result.ok:
		push_error("TemplatePaste.paste_at: the grid refused a paste its copy accepted")
		_set_status("%s  %s" % [template.name, result.reason_text()])
		return result
	_note = PLACED % [template.name, before - _balance()]
	_note_cell = cell
	_set_status(_note)
	_key = ""
	_mode.grid_changed.emit()
	return result


## The armed paste's cost under the pointer as BuildMenu's cost line takes it
## (what it costs, what the wallet must hold), or zero when nothing is armed or
## the pointer is off the grid.
func preview_price() -> Vector2i:
	var cell: Variant = _pointer_cell() if armed >= 0 else null
	if cell == null:
		return Vector2i.ZERO
	var edits := library.get_template(armed).plan(cell, turns, _mode.grid)
	var needed := BuildTransaction.needed(_mode.grid, edits)
	return Vector2i(needed, needed)


func status_text() -> String:
	return _status


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


## Redraws the ghost and the status line when the cell, the turn, the grid or
## the balance changed.
func _hover(cell: Variant) -> void:
	var key := "%s:%d:%s:%d:%d:%d" % [cell, armed, capturing, turns, _revision, _balance()]
	if key == _key:
		return
	_key = key
	_clear_ghost()
	if cell == null:
		return
	if capturing:
		var room := _mode.grid.get_room(_mode.grid.room_at(cell))
		if room.is_empty():
			_set_status(PICK_ROOM)
			return
		_ghost_slab(room["rect"], _valid_material)
		_set_status(SAVE_ROOM % RoomTemplate.capture(_mode.grid, _mode.grid.room_at(cell)).name)
		return
	var template := library.get_template(armed)
	var planned := plan_at(cell)
	var checked: BuildResult = planned["result"]
	var material := _valid_material if checked.ok else _invalid_material
	# A belt cell is drawn in the shape its reshape gives it.
	var shaped := {}
	for edit in planned["edits"]:
		if edit.kind == BuildEdit.Kind.RESHAPE_BELT:
			shaped[edit.cell] = edit
	for edit in planned["edits"]:
		if edit.kind == BuildEdit.Kind.PLACE_ROOM:
			_ghost_slab(Rect2i(edit.cell, edit.room_size), material)
		elif edit.kind == BuildEdit.Kind.PLACE_OBJECT:
			_ghost_piece(shaped.get(edit.cell, edit), material)
	var text := PLACE_HINT % template.name
	if not checked.ok:
		text = "%s  %s" % [template.name, checked.reason_text()]
	if _note != "" and cell == _note_cell:
		text = _note
	else:
		_note = ""
	_set_status(text)


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


## Belt cells among `cells` that would have four links: BELT_CROSSING, else
## accepted.
static func _four_links(grid: BuildGrid, cells: Array[Vector2i]) -> BuildResult:
	var scene := BeltShaper.Scene.new(grid)
	for at in cells:
		if scene.is_belt(at) and scene.links(at).size() > 3:
			return BuildResult.refused(BuildResult.Reason.BELT_CROSSING)
	return BuildResult.accepted()


static func _cells(area: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			out.append(Vector2i(x, y))
	return out


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


## A load replaced the list: a paste armed past its end is dropped.
func _on_library_changed() -> void:
	if armed >= library.size():
		disarm()
