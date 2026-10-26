class_name BuildMode
extends Node3D
## The player's build tools over a BuildGrid. Keys 1 to 6 (or the toolbar)
## pick floor, wall, desk, scanner, seats or remove; the toolbar also has
## glass, door, entrance and exit; Esc picks none; R turns the object;
## left-click applies, a drag along an edge lays a wall or glass line, and a
## drag with Floor or Remove fills or clears a rectangle (AreaDrag; Esc or
## right-click cancels it, a single click acts as it always did). A
## ghost shows the edit under the mouse, tinted by check(), so the preview and
## the click use the same rules. Entrances and exits turn themselves to face
## in from the edge under the mouse until R is pressed (DoorPlacement.auto_facing()).

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
## Tools whose drag repeats along an edge line.
const DRAG_TOOLS := [Tool.WALL, Tool.GLASS]
## Tools whose drag marks a rectangle that is applied on release.
const AREA_TOOLS := [Tool.FLOOR, Tool.REMOVE]
## Zone id painted floors get. One terminal zone until zones become a tool.
const TERMINAL_ZONE := 1
## How close to an edge (in metres) the remove tool targets the wall there
## rather than the floor.
const WALL_PICK_DISTANCE := 0.3
const VALID_TINT := Color(0.35, 0.9, 0.45, 0.5)
const INVALID_TINT := Color(0.95, 0.3, 0.25, 0.5)
const MARKER_TINT := Color(1.0, 0.85, 0.3, 0.7)
const AREA_REMOVE_TINT := Color(0.95, 0.55, 0.2, 0.5)

@export var grid_size := BuildGrid.DEFAULT_SIZE
## When true the grid is centred on the world origin at height 0 and
## grid_origin is not used.
@export var grid_centred := true
## World position of the grid's north-west corner, its floor height included.
@export var grid_origin := Vector3.ZERO

var grid: BuildGrid
var tool := Tool.FLOOR
var facing := 0

## False once R is pressed, until a tool is picked again. While true, the
## door tools ignore `facing` and use DoorPlacement.auto_facing().
var _auto_facing := true
var _view := BuildView.new()
var _ghost := Node3D.new()
var _valid_material := _ghost_material(VALID_TINT)
var _invalid_material := _ghost_material(INVALID_TINT)
var _marker_material := _ghost_material(MARKER_TINT)
var _area_remove_material := _ghost_material(AREA_REMOVE_TINT)
var _status := Label.new()
var _buttons: Dictionary = {}
var _hover_key := ""
var _dragging := false
var _drag_side := -1
var _last_applied_key := ""
var _area := AreaDrag.new()
## What the last rectangle did, shown until the pointer leaves its last cell.
var _status_note := ""
var _note_cell := Vector2i.ZERO


## Where a ray meets the level plane y = `height`, or null when it never does.
static func ground_point(from: Vector3, direction: Vector3, height := 0.0) -> Variant:
	return Plane(Vector3.UP, height).intersects_ray(from, direction)


static func _ghost_material(tint: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


func _ready() -> void:
	grid = BuildGrid.new(grid_size, null if grid_centred else grid_origin)
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
	if _area.active and _cancels_area(event):
		cancel_area()
		get_viewport().set_input_as_handled()
		return
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
		if point != null and AREA_TOOLS.has(tool):
			begin_area(point)
		elif point != null:
			_start_drag(point)
			apply_at(point)
	elif event.is_action_released("build_apply"):
		finish_area()
		_dragging = false
		_drag_side = -1
	elif event is InputEventMouseMotion and (_area.active or _dragging):
		var point: Variant = _mouse_ground()
		if point == null:
			return
		if _area.active:
			move_area(point)
		elif DRAG_TOOLS.has(tool):
			apply_at(point)


func set_tool(new_tool: Tool) -> void:
	cancel_area()
	tool = new_tool
	_auto_facing = true
	_hover_key = ""
	for key in _buttons:
		_buttons[key].set_pressed_no_signal(key == tool)
	_show_status(null)


func rotate_facing() -> void:
	cancel_area()
	_auto_facing = false
	facing = (facing + 1) % 4
	_hover_key = ""
	_show_status(null)


## Where a ray meets this grid's floor (its origin's height), or null.
func grid_point(from: Vector3, direction: Vector3) -> Variant:
	return ground_point(from, direction, grid.origin.y)


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
		var turn := facing
		if _facing_is_auto():
			turn = DoorPlacement.auto_facing(grid, TOOL_OBJECTS[tool], point, facing)
		return BuildEdit.place_object(TOOL_OBJECTS[tool], cell, turn)
	return null


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


## Starts a Floor or Remove rectangle on the cell under a ground point. A press
## outside the grid is a plain click, which the grid refuses with its reason.
func begin_area(point: Vector3) -> void:
	var cell := grid.world_to_cell(point)
	if not grid.in_bounds(cell):
		apply_at(point)
		return
	_status_note = ""
	_area.begin(cell, point, grid.size)
	_hover_key = ""


## Stretches the rectangle to the cell under a ground point.
func move_area(point: Vector3) -> void:
	if _area.active:
		_area.move(grid.world_to_cell(point))


## Applies the rectangle. A drag that never left its cell is applied as the
## single click it is, at the press point. Returns what a rectangle did, or
## null when there was no rectangle or it was a click.
func finish_area() -> AreaDrag.Outcome:
	if not _area.active:
		return null
	_area.cancel()
	_hover_key = ""
	if _area.is_single_cell():
		apply_at(_area.press_point)
		return null
	var outcome: AreaDrag.Outcome
	if tool == Tool.REMOVE:
		outcome = AreaDrag.clear(grid, _area.rect())
	else:
		outcome = AreaDrag.fill_floor(grid, _area.rect(), TERMINAL_ZONE)
	if outcome.placed > 0:
		_view.refresh(grid)
		grid_changed.emit()
	_status_note = outcome.message()
	_note_cell = _area.end_cell()
	_show_status(null)
	return outcome


## Drops the rectangle with nothing applied.
func cancel_area() -> void:
	if not _area.active:
		return
	_area.cancel()
	_hover_key = ""
	_show_status(null)


## The text on the status line.
func status_text() -> String:
	return _status.text


## BuildGrid.validate() plus the entrance and exit rules (DoorPlacement.check()).
func check(edit: BuildEdit) -> BuildResult:
	return DoorPlacement.check(grid, edit)


## Applies an edit check() accepted, through the edits DoorPlacement.edits_for()
## plans: an entrance or exit first takes down the plain wall on its back edge.
## Each grid edit emits graph_changed on its own; every state in between is a
## valid grid.
func _apply_checked(edit: BuildEdit) -> BuildResult:
	var plan := DoorPlacement.edits_for(grid, edit)
	var cleared: Array[Vector2i] = []
	for i in plan.size() - 1:
		var before := grid.apply(plan[i])
		if not before.ok:
			return before
		cleared.append_array(before.dirty_cells)
	var result := grid.apply(plan.back())
	if result.ok:
		result.dirty_cells.append_array(cleared)
	return result


func _cancels_area(event: InputEvent) -> bool:
	if event.is_action_pressed("build_tool_none"):
		return true
	var click := event as InputEventMouseButton
	return click != null and click.pressed and click.button_index == MOUSE_BUTTON_RIGHT


func _facing_is_auto() -> bool:
	return _auto_facing and DOOR_NAMES.has(tool)


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
	return grid_point(camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))


func _update_ghost(point: Variant) -> void:
	if _area.active:
		_draw_area()
		return
	if _status_note != "" and (point == null or grid.world_to_cell(point) != _note_cell):
		_status_note = ""
		_hover_key = ""
		_show_status(null)
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


## One tinted slab over the whole rectangle, with its size on the status line.
func _draw_area() -> void:
	var area := _area.rect()
	var key := "area:%s" % area
	if key == _hover_key:
		return
	_hover_key = key
	_clear_ghost()
	var material := _area_remove_material if tool == Tool.REMOVE else _valid_material
	var slab := _ghost_box(Vector3(area.size.x - 0.04, 0.08, area.size.y - 0.04), material)
	slab.position = (
		grid.cell_to_world(area.position)
		+ Vector3((area.size.x - 1) / 2.0, 0.06, (area.size.y - 1) / 2.0)
	)
	_show_status(null)


func _clear_ghost() -> void:
	for child in _ghost.get_children():
		child.queue_free()
	_ghost.visible = true


func _draw_ghost(edit: BuildEdit, material: Material) -> void:
	_clear_ghost()
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
	if _area.active:
		_status.text = _area.size_label()
		return
	if _status_note != "":
		_status.text = _status_note
		return
	var text := ""
	if TOOL_OBJECTS.has(tool):
		text = "Facing auto" if _facing_is_auto() else "Facing %d" % facing
	if result != null and not result.ok:
		var reason := result.reason_text()
		if DOOR_NAMES.has(tool) and DOOR_HINTS.has(result.reason):
			reason = DOOR_HINTS[result.reason] % DOOR_NAMES[tool]
		text += ("  " if text != "" else "") + reason
	_status.text = text
