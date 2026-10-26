class_name BuildMode
extends Node3D
## The player's build tools over a BuildGrid. Keys 1 to 6 (or the toolbar)
## pick floor, wall, desk, scanner, seats or remove; the toolbar also has
## glass, door, entrance and exit; Esc picks none; R turns the object;
## left-click applies, and a drag paints floors or a wall or glass line. A
## ghost shows the edit under the mouse, tinted by check(), so the preview and
## the click use the same rules. Entrances and exits turn themselves to face
## in from the edge under the mouse until R is pressed (door_facing()).

signal grid_changed

enum Tool { NONE, FLOOR, WALL, DESK, SCANNER, SEATS, REMOVE, GLASS, DOOR, ENTRANCE, EXIT }

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
	Tool.ENTRANCE: &"entrance_door",
	Tool.EXIT: &"exit_door",
}
const TOOL_WALL_KINDS := {
	Tool.WALL: BuildGrid.WallKind.PLAIN,
	Tool.GLASS: BuildGrid.WallKind.GLASS,
	Tool.DOOR: BuildGrid.WallKind.DOOR,
}
## Toolbar order. Glass, door, entrance and exit have no key yet.
const TOOL_LABELS := {
	Tool.FLOOR: "1 Floor",
	Tool.WALL: "2 Wall",
	Tool.GLASS: "Glass",
	Tool.DOOR: "Door",
	Tool.DESK: "3 Desk",
	Tool.SCANNER: "4 Scanner",
	Tool.SEATS: "5 Seats",
	Tool.ENTRANCE: "Entrance",
	Tool.EXIT: "Exit",
	Tool.REMOVE: "6 Remove",
}
## The door tools by the name the status line uses for them.
const DOOR_NAMES := {Tool.ENTRANCE: "entrance", Tool.EXIT: "exit"}
## What the status line tells the player to do when a door tool is refused.
const DOOR_HINTS := {
	BuildResult.Reason.NO_FLOOR: "Put the %s on a floor tile at the outside edge",
	BuildResult.Reason.DOOR_NOT_ON_EDGE: "Put the %s on the outside edge of the floor",
	BuildResult.Reason.INTERACTION_BLOCKED: "Clear the floor in front of the %s",
	BuildResult.Reason.DOOR_WALLED: "Take down the glass or door wall behind the %s",
	BuildResult.Reason.WALL_HOLDS_DOOR: "The wall behind the %s holds a door; pick another spot",
}
const DRAG_TOOLS := [Tool.FLOOR, Tool.WALL, Tool.GLASS]
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

## False once R is pressed, until a tool is picked again. While true, the
## door tools ignore `facing` and use door_facing().
var _auto_facing := true
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
	_auto_facing = true
	_hover_key = ""
	for key in _buttons:
		_buttons[key].set_pressed_no_signal(key == tool)
	_show_status(null)


func rotate_facing() -> void:
	_auto_facing = false
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
		Tool.REMOVE:
			return _removal_at(point, cell, side)
	if TOOL_WALL_KINDS.has(tool):
		return BuildEdit.place_wall(cell, side, TOOL_WALL_KINDS[tool])
	if TOOL_OBJECTS.has(tool):
		var turn := door_facing(point, cell) if _facing_is_auto() else facing
		return BuildEdit.place_object(TOOL_OBJECTS[tool], cell, turn)
	return null


## The facing an entrance or exit at `cell` takes before R is pressed. It
## prefers a facing check() accepts, then one whose back has no floor beyond
## it; among equals, the one whose back edge is nearest `point`. With neither,
## it keeps `facing`, so the refusal says the cell is not on the edge.
func door_facing(point: Vector3, cell: Vector2i) -> int:
	var offset := point - grid.cell_to_world(cell)
	var best := facing
	var best_tier := 2
	var best_distance := INF
	for turn in 4:
		var out := BuildObjectDef.rotate_offset(Vector2i(0, -1), turn)
		var tier := 2
		if check(BuildEdit.place_object(TOOL_OBJECTS[tool], cell, turn)).ok:
			tier = 0
		elif grid.floor_at(cell + out) == BuildGrid.FLOOR_NONE:
			tier = 1
		var distance := 0.5 - (offset.x * out.x + offset.z * out.y)
		if tier < best_tier or (tier == best_tier and tier < 2 and distance < best_distance):
			best = turn
			best_tier = tier
			best_distance = distance
	return best


## Applies the current tool at a ground point and redraws on success. A drag
## applies once per target. Returns null when nothing was attempted.
func apply_at(point: Vector3) -> BuildResult:
	var edit := edit_at(point)
	if edit == null or (_dragging and _edit_key(edit) == _last_applied_key):
		return null
	_last_applied_key = _edit_key(edit)
	var result := check(edit)
	if result.ok:
		result = _apply_checked(edit)
	if result.ok:
		_view.refresh(grid)
		_hover_key = ""
		grid_changed.emit()
	_show_status(result)
	return result


## Whether an entrance or exit door object at `anchor` and `facing` stands on
## the terminal's edge: its back edge (the way out) has no floor beyond it and
## no wall on it, the same test TerminalLayout.is_exit_open() makes. A plain
## wall there is allowed when the wall could be removed on its own (it holds
## no door wall), because placing the door takes it down (_apply_checked()).
## Glass and door walls still refuse. The grid allows a door object anywhere;
## the tools add this check.
static func outside_door_problem(on: BuildGrid, anchor: Vector2i, facing: int) -> BuildResult:
	var out := BuildObjectDef.rotate_offset(Vector2i(0, -1), facing)
	if on.floor_at(anchor + out) != BuildGrid.FLOOR_NONE:
		return BuildResult.refused(BuildResult.Reason.DOOR_NOT_ON_EDGE)
	var side := BuildGrid.SIDE_STEP.find(out)
	match on.wall_kind(anchor, side):
		BuildGrid.WallKind.NONE:
			return BuildResult.accepted()
		BuildGrid.WallKind.PLAIN:
			return on.validate(BuildEdit.remove_wall(anchor, side))
	return BuildResult.refused(BuildResult.Reason.DOOR_WALLED)


## BuildGrid.validate(), plus the edge rule for entrances and exits: a new one
## stands on the terminal's edge facing in (outside_door_problem()), and a
## standing one keeps its way out open: no wall of any kind on its back edge
## and no floor on the cell beyond.
func check(edit: BuildEdit) -> BuildResult:
	var result := grid.validate(edit)
	if not result.ok:
		return result
	match edit.kind:
		BuildEdit.Kind.PLACE_OBJECT:
			if BuildCatalog.is_door(edit.def_id):
				return outside_door_problem(grid, edit.cell, edit.facing)
		BuildEdit.Kind.PLACE_WALL:
			if _on_a_way_out(edit.cell, edit.side):
				return BuildResult.refused(BuildResult.Reason.DOOR_WALLED)
		BuildEdit.Kind.PAINT_FLOOR:
			if _beyond_a_door(edit.cell):
				return BuildResult.refused(BuildResult.Reason.DOOR_NOT_ON_EDGE)
	return result


## Applies an edit check() accepted. An entrance or exit takes the place of a
## plain wall on its back edge: the wall comes down first, in the same click.
## Removing that wall cannot make the door's own placement invalid.
func _apply_checked(edit: BuildEdit) -> BuildResult:
	if edit.kind != BuildEdit.Kind.PLACE_OBJECT or not BuildCatalog.is_door(edit.def_id):
		return grid.apply(edit)
	var out := BuildObjectDef.rotate_offset(Vector2i(0, -1), edit.facing)
	var side := BuildGrid.SIDE_STEP.find(out)
	if grid.wall_kind(edit.cell, side) != BuildGrid.WallKind.PLAIN:
		return grid.apply(edit)
	var removed := grid.apply(BuildEdit.remove_wall(edit.cell, side))
	if not removed.ok:
		return removed
	var result := grid.apply(edit)
	result.dirty_cells.append_array(removed.dirty_cells)
	return result


func _facing_is_auto() -> bool:
	return _auto_facing and DOOR_NAMES.has(tool)


## Each standing entrance or exit as [anchor, outward step].
func _ways_out() -> Array:
	var out := []
	for object_id in grid.object_ids():
		var record := grid.get_object(object_id)
		if BuildCatalog.is_door(record["def"]):
			var step := BuildObjectDef.rotate_offset(Vector2i(0, -1), record["facing"])
			out.append([record["anchor"], step])
	return out


## Whether the edge (from either cell beside it) is a door's back edge.
func _on_a_way_out(cell: Vector2i, side: int) -> bool:
	var step := BuildGrid.SIDE_STEP[side]
	for way in _ways_out():
		if (cell == way[0] and step == way[1]) or (cell == way[0] + way[1] and step == -way[1]):
			return true
	return false


func _beyond_a_door(cell: Vector2i) -> bool:
	for way in _ways_out():
		if cell == way[0] + way[1]:
			return true
	return false


func _start_drag(point: Vector3) -> void:
	_dragging = true
	_last_applied_key = ""
	_drag_side = grid.nearest_side(point) if TOOL_WALL_KINDS.has(tool) else -1


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
	var result := check(edit)
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
			wall.transform = BuildView.wall_transform(grid, edit.cell, edit.side).translated_local(
				Vector3(0.0, BuildView.WALL_HEIGHT / 2.0, 0.0)
			)
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
	return (
		"%d:%s:%d:%d:%d:%s"
		% [edit.kind, edit.cell, edit.side, edit.wall_kind, edit.facing, edit.object_id]
	)


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
	var text := ""
	if TOOL_OBJECTS.has(tool):
		text = "Facing auto" if _facing_is_auto() else "Facing %d" % facing
	if result != null and not result.ok:
		var reason := result.reason_text()
		if DOOR_NAMES.has(tool) and DOOR_HINTS.has(result.reason):
			reason = DOOR_HINTS[result.reason] % DOOR_NAMES[tool]
		text += ("  " if text != "" else "") + reason
	_status.text = text
