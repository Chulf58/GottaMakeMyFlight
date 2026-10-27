class_name BuildMode
extends Node3D
## The player's build tools over a BuildGrid. Keys 1 to 9 and 0 (or
## BuildMenu's cards) pick floor, wall, desk, scanner, seats, remove, glass,
## door, entrance and exit; Esc picks none; R turns the object;
## left-click applies, a drag along an edge lays a wall or glass line, and a
## drag with Floor or Remove fills or clears a rectangle (AreaDrag; Esc or
## right-click cancels it, a single click acts as it always did). A
## ghost shows the edit under the mouse, tinted by check(), so the preview and
## the click use the same rules. Entrances and exits turn themselves to face
## in from the edge under the mouse until R is pressed (DoorPlacement.auto_facing()).
## Inside a terminal shell they snap to its Toon doors instead (ShellDefinition).
## The Cafe tool drags a rectangle that marks floor as a cafe room (RoomTool);
## the counter and table tools furnish it, and RoomView shows what it needs.
## Every edit is paid from `finances` through BuildTransaction.

signal grid_changed
## Emitted by every set_tool(), NONE included, so the menu can follow it.
signal tool_changed(new_tool: Tool)
## Emitted when the status line's text changes.
signal status_changed(text: String)
## Emitted when the room under the pointer changes, 0 for none
## (update_room_focus()).
signal room_focus_changed(room_id: int)

enum Tool {
	NONE,
	FLOOR,
	WALL,
	DESK,
	SCANNER,
	SEATS,
	REMOVE,
	GLASS,
	DOOR,
	ENTRANCE,
	EXIT,
	CAFE_ROOM,
	COUNTER,
	TABLE,
}

const TOOL_ACTIONS := {
	&"build_tool_floor": Tool.FLOOR,
	&"build_tool_wall": Tool.WALL,
	&"build_tool_desk": Tool.DESK,
	&"build_tool_scanner": Tool.SCANNER,
	&"build_tool_seats": Tool.SEATS,
	&"build_tool_remove": Tool.REMOVE,
	&"build_tool_glass": Tool.GLASS,
	&"build_tool_door": Tool.DOOR,
	&"build_tool_entrance": Tool.ENTRANCE,
	&"build_tool_exit": Tool.EXIT,
	&"build_tool_none": Tool.NONE,
}
const TOOL_OBJECTS := {
	Tool.DESK: &"checkin_desk",
	Tool.SCANNER: &"security_scanner",
	Tool.SEATS: &"seat_row",
	Tool.ENTRANCE: &"entrance_door",
	Tool.EXIT: &"exit_door",
	Tool.COUNTER: &"cafe_counter",
	Tool.TABLE: &"cafe_table",
}
## Tools that mark a dragged rectangle as a room of a RoomTypes id.
const TOOL_ROOMS := {Tool.CAFE_ROOM: &"cafe"}
## Tools under which the room under the pointer is followed for its panel.
const ROOM_FOCUS_TOOLS := [Tool.NONE, Tool.CAFE_ROOM, Tool.COUNTER, Tool.TABLE]
const TOOL_WALL_KINDS := {
	Tool.WALL: BuildGrid.WallKind.PLAIN,
	Tool.GLASS: BuildGrid.WallKind.GLASS,
	Tool.DOOR: BuildGrid.WallKind.DOOR,
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
## The status line for a door tool refused with DOOR_NOT_AT_SHELL_DOOR.
const SHELL_DOOR_HINTS := {
	Tool.ENTRANCE: "Put the entrance on one of the building's landside doors",
	Tool.EXIT: "Put the exit on one of the building's gate doors",
}
## Tools whose drag repeats along an edge line.
const DRAG_TOOLS := [Tool.WALL, Tool.GLASS]
## Tools whose drag marks a rectangle that is applied on release.
const AREA_TOOLS := [Tool.FLOOR, Tool.REMOVE, Tool.CAFE_ROOM]
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
## The terminal shell the player builds inside. When set, the grid takes its
## frame (grid_size, grid_centred and grid_origin are not used), the Entrance
## and Exit tools snap to its doors and load_snapshot() checks a save fits it.
@export var shell: ShellDefinition
## Where building is paid from (BuildTransaction): a click or door costs its
## price, a Floor rectangle is all or nothing, a wall stroke stops when the
## money runs out, and removals refund a share of the saved price. main.tscn
## sets it. Without it the tools build for free and save no prices, the
## non-spending path tests and probes use.
@export var finances: Finances

var grid: BuildGrid
var tool := Tool.FLOOR
var facing := 0

## False once R is pressed, until a tool is picked again. While true, the
## door tools ignore `facing` and use DoorPlacement.auto_facing().
var _auto_facing := true
var _view := BuildView.new()
var _room_view := RoomView.new()
var _focus_room := 0
var _ghost := Node3D.new()
var _valid_material := _ghost_material(VALID_TINT)
var _invalid_material := _ghost_material(INVALID_TINT)
var _marker_material := _ghost_material(MARKER_TINT)
var _area_remove_material := _ghost_material(AREA_REMOVE_TINT)
var _status := ""
var _hover_key := ""
var _dragging := false
var _drag_side := -1
var _last_applied_key := ""
## True once a segment of the current wall stroke was refused for money; the
## rest of the stroke is refused too, until the next press.
var _stroke_out_of_money := false
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
	if shell != null:
		grid = BuildGrid.new(shell.grid_size, shell.grid_origin)
	else:
		grid = BuildGrid.new(grid_size, null if grid_centred else grid_origin)
	_view.name = "BuildView"
	add_child(_view)
	_view.refresh(grid)
	_room_view.name = "RoomView"
	add_child(_room_view)
	_room_view.watch(grid)
	_ghost.name = "Ghost"
	add_child(_ghost)
	if finances != null:
		finances.wallet.changed.connect(_on_balance_changed)
	set_tool(tool)


func _process(_delta: float) -> void:
	var point: Variant = _mouse_ground()
	_update_ghost(point)
	update_room_focus(point)


## A rectangle in progress is dropped when the window loses focus, because
## the release will not reach it.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		cancel_area()


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
	_show_status(null)
	tool_changed.emit(tool)


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
		var def_id: StringName = TOOL_OBJECTS[tool]
		if shell != null and DOOR_NAMES.has(tool):
			var door := shell.nearest(grid, def_id, point)
			if door != null:
				return BuildEdit.place_object(def_id, door.cell, door.facing)
		var turn := facing
		if _facing_is_auto():
			turn = DoorPlacement.auto_facing(grid, def_id, point, facing)
		return BuildEdit.place_object(def_id, cell, turn)
	return null


## Applies the current tool at a ground point, paid through BuildTransaction,
## and redraws on success. A drag applies once per target; once a segment of a
## wall stroke cannot be paid for, the rest of the stroke is refused for
## money too. Returns null when nothing was attempted.
func apply_at(point: Vector3) -> BuildResult:
	var edit := edit_at(point)
	if edit == null or (_dragging and _edit_key(edit) == _last_applied_key):
		return null
	_last_applied_key = _edit_key(edit)
	var result := check(edit)
	if result.ok and _dragging and _stroke_out_of_money:
		result = BuildResult.refused(BuildResult.Reason.CANT_AFFORD)
	if _dragging and result.reason == BuildResult.Reason.CANT_AFFORD:
		_stroke_out_of_money = true
	var refused_by_check := not result.ok
	if result.ok:
		result = BuildTransaction.commit_plan(grid, DoorPlacement.edits_for(grid, edit), wallet())
	if result.ok:
		_view.refresh(grid)
		_hover_key = ""
		grid_changed.emit()
	_show_status(result)
	# A refusal from the grid or the transaction (inside commit_plan()) was
	# emitted there.
	if refused_by_check:
		grid.edit_refused.emit(edit, result)
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
## single click it is, at the press point (which marks no room). Returns what
## a Floor or Remove rectangle did, or null when there was no rectangle, it
## was a click or it marked a room.
func finish_area() -> AreaDrag.Outcome:
	if not _area.active:
		return null
	_area.cancel()
	_hover_key = ""
	if _area.is_single_cell():
		apply_at(_area.press_point)
		return null
	if TOOL_ROOMS.has(tool):
		_finish_room()
		return null
	var outcome: AreaDrag.Outcome
	if tool == Tool.REMOVE:
		outcome = AreaDrag.clear(grid, _area.rect(), wallet())
	else:
		outcome = AreaDrag.fill_floor(grid, _area.rect(), TERMINAL_ZONE, wallet())
	if outcome.placed > 0:
		_view.refresh(grid)
		grid_changed.emit()
	_status_note = outcome.message()
	_note_cell = _area.end_cell()
	_show_status(null)
	return outcome


## Marks the released rectangle as a room of the current room tool's type.
func _finish_room() -> void:
	var type: StringName = TOOL_ROOMS[tool]
	var result := RoomTool.mark(grid, _area.rect(), type, wallet())
	if result.ok:
		grid_changed.emit()
	_status_note = RoomTool.message(grid, result, type)
	_note_cell = _area.end_cell()
	_show_status(null)


## Follows the room under a ground point (null for none) while a room-focus
## tool is picked; any other tool follows no room. Emits room_focus_changed
## when the room changes, including when the followed room is removed.
func update_room_focus(point: Variant) -> void:
	var room_id := 0
	if point != null and ROOM_FOCUS_TOOLS.has(tool) and not _pointer_over_ui():
		room_id = grid.room_at(grid.world_to_cell(point))
	if room_id != _focus_room:
		_focus_room = room_id
		room_focus_changed.emit(room_id)


## The room the info panel shows, 0 for none.
func focused_room() -> int:
	return _focus_room


## Drops the rectangle with nothing applied.
func cancel_area() -> void:
	if not _area.active:
		return
	_area.cancel()
	_hover_key = ""
	_show_status(null)


## The text on the status line.
func status_text() -> String:
	return _status


## The wallet building is paid from, or null when the tools build for free.
func wallet() -> Wallet:
	return finances.wallet if finances != null else null


## BuildGrid.validate() plus the entrance and exit rules (DoorPlacement.check()),
## then whether the wallet can pay for the edits it takes
## (BuildTransaction.check(), CANT_AFFORD).
func check(edit: BuildEdit) -> BuildResult:
	var result := DoorPlacement.check(grid, edit, shell)
	if not result.ok:
		return result
	return BuildTransaction.check(grid, DoorPlacement.edits_for(grid, edit), wallet())


## Restores a BuildGrid.to_snapshot() dictionary into the grid and redraws.
## With a shell, a save that does not fit it is refused first
## (ShellDefinition.snapshot_problem()). Pushes an error and returns false,
## leaving the grid as it was, on any refusal. A load never spends or
## credits: it bypasses BuildTransaction and keeps the saved purchase prices.
func load_snapshot(data: Dictionary) -> bool:
	var problem := shell.snapshot_problem(data) if shell != null else ""
	if problem != "":
		push_error("BuildMode.load_snapshot: %s" % problem)
		return false
	if not grid.from_snapshot(data):
		return false
	_view.refresh(grid)
	_hover_key = ""
	grid_changed.emit()
	return true


## A changed balance can change whether the ghost's edit is affordable, so the
## ghost is checked again.
func _on_balance_changed(_balance: int) -> void:
	_hover_key = ""


func _cancels_area(event: InputEvent) -> bool:
	if event.is_action_pressed("build_tool_none"):
		return true
	var click := event as InputEventMouseButton
	return click != null and click.pressed and click.button_index == MOUSE_BUTTON_RIGHT


## A door tool picks its own facing until R is pressed; inside a shell, always.
func _facing_is_auto() -> bool:
	return (_auto_facing or shell != null) and DOOR_NAMES.has(tool)


func _start_drag(point: Vector3) -> void:
	_dragging = true
	_last_applied_key = ""
	_stroke_out_of_money = false
	_drag_side = grid.nearest_side(point) if TOOL_WALL_KINDS.has(tool) else -1


func _removal_at(point: Vector3, cell: Vector2i, side: int) -> BuildEdit:
	var object_id := grid.object_at(cell)
	if object_id != 0:
		return BuildEdit.remove_object(object_id)
	var offset := point - grid.cell_to_world(cell)
	var to_edge := 0.5 - maxf(absf(offset.x), absf(offset.z))
	if grid.has_wall(cell, side) and to_edge <= WALL_PICK_DISTANCE:
		return BuildEdit.remove_wall(cell, side)
	if grid.room_at(cell) != 0:
		return BuildEdit.remove_room(grid.room_at(cell))
	return BuildEdit.remove_floor(cell)


## Whether the pointer is over a HUD control, which hides the world under it.
func _pointer_over_ui() -> bool:
	return get_viewport().gui_get_hovered_control() != null


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
	if TOOL_ROOMS.has(tool) and not RoomTool.check(grid, area, TOOL_ROOMS[tool]).ok:
		material = _invalid_material
	_ghost_slab(area, material)
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
		BuildEdit.Kind.REMOVE_ROOM:
			_ghost_slab(grid.get_room(edit.room_id)["rect"], material)


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


## One tinted slab over a rectangle of cells.
func _ghost_slab(area: Rect2i, material: Material) -> void:
	var slab := _ghost_box(Vector3(area.size.x - 0.04, 0.08, area.size.y - 0.04), material)
	slab.position = (
		grid.cell_to_world(area.position)
		+ Vector3((area.size.x - 1) / 2.0, 0.06, (area.size.y - 1) / 2.0)
	)


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


func _show_status(result: BuildResult) -> void:
	if _area.active and TOOL_ROOMS.has(tool):
		_set_status(RoomTool.drag_label(grid, _area.rect(), TOOL_ROOMS[tool]))
		return
	if _area.active:
		_set_status(_area.size_label())
		return
	if _status_note != "":
		_set_status(_status_note)
		return
	var text := RoomTool.hint(TOOL_ROOMS[tool]) if TOOL_ROOMS.has(tool) else ""
	if TOOL_OBJECTS.has(tool):
		text = "Facing auto" if _facing_is_auto() else "Facing %d" % facing
	if result != null and not result.ok:
		var reason := result.reason_text()
		if DOOR_NAMES.has(tool) and result.reason == BuildResult.Reason.DOOR_NOT_AT_SHELL_DOOR:
			reason = SHELL_DOOR_HINTS[tool]
		elif DOOR_NAMES.has(tool) and DOOR_HINTS.has(result.reason):
			reason = DOOR_HINTS[result.reason] % DOOR_NAMES[tool]
		text += ("  " if text != "" else "") + reason
	_set_status(text)


func _set_status(text: String) -> void:
	if text == _status:
		return
	_status = text
	status_changed.emit(text)
