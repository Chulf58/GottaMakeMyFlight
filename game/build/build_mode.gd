class_name BuildMode
extends Node3D
## The player's build tools over a BuildGrid. Keys 1 to 6 (or the toolbar)
## pick floor, wall, desk, scanner, seats or remove; Esc picks none; R turns
## the object; left-click applies, and a drag paints floors or a wall line.
## A ghost shows the edit under the mouse, tinted by BuildGrid.validate(), so
## the preview and the click use the same rules.

signal grid_changed

enum Tool { NONE, FLOOR, WALL, DESK, SCANNER, SEATS, REMOVE }

const TOOL_ACTIONS := {
	&"build_tool_floor": Tool.FLOOR,
	&"build_tool_wall": Tool.WALL,
	&"build_tool_desk": Tool.DESK,
	&"build_tool_scanner": Tool.SCANNER,
	&"build_tool_seats": Tool.SEATS,
	&"build_tool_remove": Tool.REMOVE,
	&"build_tool_none": Tool.NONE,
}
const TOOL_OBJECTS := {
	Tool.DESK: &"checkin_desk",
	Tool.SCANNER: &"security_scanner",
	Tool.SEATS: &"seat_row",
}
const TOOL_LABELS := {
	Tool.FLOOR: "1 Floor",
	Tool.WALL: "2 Wall",
	Tool.DESK: "3 Desk",
	Tool.SCANNER: "4 Scanner",
	Tool.SEATS: "5 Seats",
	Tool.REMOVE: "6 Remove",
}
const DRAG_TOOLS := [Tool.FLOOR, Tool.WALL]
## Zone id painted floors get. One terminal zone until zones become a tool.
const TERMINAL_ZONE := 1
## How close to an edge (in metres) the remove tool targets the wall there
## rather than the floor.
const WALL_PICK_DISTANCE := 0.3
const VALID_TINT := Color(0.35, 0.9, 0.45, 0.5)
const INVALID_TINT := Color(0.95, 0.3, 0.25, 0.5)
const MARKER_TINT := Color(1.0, 0.85, 0.3, 0.7)

@export var grid_size := BuildGrid.DEFAULT_SIZE

var grid: BuildGrid
var tool := Tool.FLOOR
var facing := 0

var _view := BuildView.new()
var _ghost := Node3D.new()
var _valid_material := _ghost_material(VALID_TINT)
var _invalid_material := _ghost_material(INVALID_TINT)
var _marker_material := _ghost_material(MARKER_TINT)
var _status := Label.new()
var _buttons: Dictionary = {}
var _hover_key := ""
var _dragging := false
var _drag_side := -1
var _last_applied_key := ""


## Where a ray meets the ground plane y = 0, or null when it never does.
static func ground_point(from: Vector3, direction: Vector3) -> Variant:
	return Plane(Vector3.UP, 0.0).intersects_ray(from, direction)


static func _ghost_material(tint: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


func _ready() -> void:
	grid = BuildGrid.new(grid_size)
	_view.name = "BuildView"
	add_child(_view)
	_view.refresh(grid)
	_ghost.name = "Ghost"
	add_child(_ghost)
	_build_toolbar()
	set_tool(tool)


func _process(_delta: float) -> void:
	_update_ghost(_mouse_ground())


func _unhandled_input(event: InputEvent) -> void:
	for action in TOOL_ACTIONS:
		if event.is_action_pressed(action):
			set_tool(TOOL_ACTIONS[action])
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("build_rotate"):
		rotate_facing()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_apply"):
		var point: Variant = _mouse_ground()
		if point != null:
			_start_drag(point)
			apply_at(point)
	elif event.is_action_released("build_apply"):
		_dragging = false
		_drag_side = -1
	elif event is InputEventMouseMotion and _dragging and DRAG_TOOLS.has(tool):
		var point: Variant = _mouse_ground()
		if point != null:
			apply_at(point)


func set_tool(new_tool: Tool) -> void:
	tool = new_tool
	_hover_key = ""
	for key in _buttons:
		_buttons[key].set_pressed_no_signal(key == tool)
	_show_status(null)


func rotate_facing() -> void:
	facing = (facing + 1) % 4
	_hover_key = ""
	_show_status(null)


## The edit the current tool would make at a ground point, or null for none.
func edit_at(point: Vector3) -> BuildEdit:
	var cell := grid.world_to_cell(point)
	var side: int = grid.nearest_side(point)
	if _dragging and _drag_side >= 0:
		side = _drag_side
	match tool:
		Tool.FLOOR:
			return BuildEdit.paint_floor(cell, BuildGrid.FLOOR_TILE, TERMINAL_ZONE)
		Tool.WALL:
			return BuildEdit.place_wall(cell, side)
		Tool.REMOVE:
			return _removal_at(point, cell, side)
	if TOOL_OBJECTS.has(tool):
		return BuildEdit.place_object(TOOL_OBJECTS[tool], cell, facing)
	return null


## Applies the current tool at a ground point and redraws on success. A drag
## applies once per target. Returns null when nothing was attempted.
func apply_at(point: Vector3) -> BuildResult:
	var edit := edit_at(point)
	if edit == null or (_dragging and _edit_key(edit) == _last_applied_key):
		return null
	_last_applied_key = _edit_key(edit)
	var result := grid.apply(edit)
	if result.ok:
		_view.refresh(grid)
		_hover_key = ""
		grid_changed.emit()
	_show_status(result)
	return result


func _start_drag(point: Vector3) -> void:
	_dragging = true
	_last_applied_key = ""
	_drag_side = grid.nearest_side(point) if tool == Tool.WALL else -1


func _removal_at(point: Vector3, cell: Vector2i, side: int) -> BuildEdit:
	var object_id := grid.object_at(cell)
	if object_id != 0:
		return BuildEdit.remove_object(object_id)
	var offset := point - grid.cell_to_world(cell)
	var to_edge := 0.5 - maxf(absf(offset.x), absf(offset.z))
	if grid.has_wall(cell, side) and to_edge <= WALL_PICK_DISTANCE:
		return BuildEdit.remove_wall(cell, side)
	return BuildEdit.remove_floor(cell)


func _mouse_ground() -> Variant:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	var mouse := get_viewport().get_mouse_position()
	return ground_point(camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))


func _update_ghost(point: Variant) -> void:
	var edit: BuildEdit = null if point == null else edit_at(point)
	if edit == null:
		_ghost.visible = false
		_hover_key = ""
		return
	var key := _edit_key(edit)
	if key == _hover_key:
		return
	_hover_key = key
	var result := grid.validate(edit)
	_draw_ghost(edit, _valid_material if result.ok else _invalid_material)
	_show_status(result)


func _draw_ghost(edit: BuildEdit, material: Material) -> void:
	for child in _ghost.get_children():
		child.queue_free()
	_ghost.visible = true
	match edit.kind:
		BuildEdit.Kind.PAINT_FLOOR, BuildEdit.Kind.REMOVE_FLOOR:
			_ghost_tile(edit.cell, material)
		BuildEdit.Kind.PLACE_WALL, BuildEdit.Kind.REMOVE_WALL:
			var wall := _ghost_box(
				Vector3(1.0, BuildView.WALL_HEIGHT, BuildView.WALL_THICKNESS * 1.5), material
			)
			wall.transform = BuildView.wall_transform(grid, edit.cell, edit.side)
		BuildEdit.Kind.PLACE_OBJECT:
			_ghost_object(edit.def_id, edit.cell, edit.facing, material)
		BuildEdit.Kind.REMOVE_OBJECT:
			var record := grid.get_object(edit.object_id)
			_ghost_object(record["def"], record["anchor"], record["facing"], material)


func _ghost_object(def_id: StringName, anchor: Vector2i, turn: int, material: Material) -> void:
	var def := BuildCatalog.get_def(def_id)
	var node := BuildView.make_object_node(def, material)
	node.transform = BuildView.object_transform(grid, def.footprint(anchor, turn), turn)
	node.scale = Vector3.ONE * 1.02
	_ghost.add_child(node)
	var spot := def.interaction_cell(anchor, turn)
	if spot != BuildObjectDef.NO_CELL:
		_ghost_tile(spot, _marker_material)


func _ghost_tile(cell: Vector2i, material: Material) -> void:
	var tile := _ghost_box(Vector3(0.96, 0.08, 0.96), material)
	tile.position = grid.cell_to_world(cell) + Vector3(0.0, 0.06, 0.0)


func _ghost_box(extent: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = extent
	var box := MeshInstance3D.new()
	box.mesh = mesh
	box.material_override = material
	_ghost.add_child(box)
	return box


func _edit_key(edit: BuildEdit) -> String:
	return "%d:%s:%d:%d:%s" % [edit.kind, edit.cell, edit.side, edit.facing, edit.object_id]


func _build_toolbar() -> void:
	var layer := CanvasLayer.new()
	layer.name = "BuildToolbar"
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	layer.add_child(panel)
	var row := HBoxContainer.new()
	panel.add_child(row)
	for key in TOOL_LABELS:
		var button := Button.new()
		button.text = TOOL_LABELS[key]
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(set_tool.bind(key))
		row.add_child(button)
		_buttons[key] = button
	var turn := Button.new()
	turn.text = "R Rotate"
	turn.focus_mode = Control.FOCUS_NONE
	turn.pressed.connect(rotate_facing)
	row.add_child(turn)
	_status.custom_minimum_size = Vector2(360, 0)
	row.add_child(_status)


func _show_status(result: BuildResult) -> void:
	var text := "Facing %d" % facing if TOOL_OBJECTS.has(tool) else ""
	if result != null and not result.ok:
		text += ("  " if text != "" else "") + result.reason_text()
	_status.text = text
