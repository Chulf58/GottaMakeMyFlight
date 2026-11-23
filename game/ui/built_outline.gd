class_name BuiltOutline
extends Node3D
## The gold outline on the floor around the selected built item (decision
## select-placed-items-design-click-order-gold-footprint-highlight-...): a flat
## frame in the passenger selection ring's gold, outside an object's footprint
## and inside a room's floor or a car park's footprint. A view only, redrawn
## when the selection or its rectangle changes.

## The passenger ring's gold (PassengerViews).
const GOLD := Color(1.0, 0.85, 0.3)
## The frame's width on the grid, and on the landside, whose spots are far larger.
const GRID_WIDTH_M := 0.12
const LANDSIDE_WIDTH_M := 0.6
## Lift over the floor top: above the room tint (RoomView.TINT_Y), which would
## otherwise cover the frame of a room or of a piece standing in one.
const LIFT_M := RoomView.TINT_Y + 0.02
## A car park's slab and kerb stand above the ground (LandsidePlacement.SLAB_HEIGHT), so
## its frame sits higher.
const LANDSIDE_LIFT_M := LandsidePlacement.SLAB_HEIGHT + 0.15
const HANDLE_SIZE := Vector3(0.36, 0.14, 0.36)
const HANDLE_COLOR := Color(0.95, 0.92, 0.80)

var selection: BuiltSelection
var build_mode: BuildMode

var _mesh := MeshInstance3D.new()
var _handles := Node3D.new()
var _handle_nodes: Array[MeshInstance3D] = []
var _drawn := ""


func _init() -> void:
	name = "BuiltOutline"
	var material := StandardMaterial3D.new()
	material.albedo_color = GOLD
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh.material_override = material
	_mesh.visible = false
	add_child(_mesh)
	var handle_mat := StandardMaterial3D.new()
	handle_mat.albedo_color = HANDLE_COLOR
	handle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_handles.name = "ResizeHandles"
	_handles.visible = false
	add_child(_handles)
	var handle_names := ["HandleNorth", "HandleEast", "HandleSouth", "HandleWest"]
	var handle_box := BoxMesh.new()
	handle_box.size = HANDLE_SIZE
	for hname in handle_names:
		var node := MeshInstance3D.new()
		node.name = hname
		node.mesh = handle_box
		node.material_override = handle_mat
		_handles.add_child(node)
		_handle_nodes.append(node)


func _process(_delta: float) -> void:
	refresh()


## Redraws for the current selection; hides with none.
func refresh() -> void:
	if selection == null or build_mode == null or not selection.is_selected():
		_mesh.visible = false
		_handles.visible = false
		_drawn = ""
		return
	var grid := build_mode.grid
	var rect := selection.outline_rect(grid, build_mode.landside_placement())
	var key := "%s:%s" % [selection.key(), rect]
	_mesh.visible = rect.has_area()
	if not _mesh.visible:
		_handles.visible = false
		return
	_refresh_handles(grid)
	if key == _drawn:
		return
	_drawn = key
	var on_landside := selection.kind == BuiltSelection.Kind.LANDSIDE
	var width := LANDSIDE_WIDTH_M if on_landside else GRID_WIDTH_M
	var outside := selection.kind == BuiltSelection.Kind.OBJECT
	_mesh.mesh = frame_mesh(rect, width, outside)
	_mesh.position.y = LANDSIDE_LIFT_M if on_landside else grid.origin.y + LIFT_M


func _refresh_handles(grid: BuildGrid) -> void:
	var show := (
		selection.kind == BuiltSelection.Kind.ROOM
		and build_mode.tool == BuildMode.Tool.NONE
		and not build_mode.templates.is_active()
		and not build_mode.room_mover.active
		and (build_mode.starter_kit == null or not build_mode.starter_kit.is_active())
		and not build_mode.is_dragging()
	)
	if not show:
		_handles.visible = false
		return
	var room := grid.get_room(selection.id)
	if room.is_empty():
		_handles.visible = false
		return
	var positions := RoomResize.handle_positions(grid, room["rect"])
	if positions.size() != 4:
		_handles.visible = false
		return
	_handles.visible = true
	for i in 4:
		_handle_nodes[i].position = positions[i] + Vector3(0.0, LIFT_M + HANDLE_SIZE.y * 0.5, 0.0)


func handles_visible() -> bool:
	return _handles.visible


func handle_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	if not _handles.visible:
		return out
	for node in _handle_nodes:
		out.append(node.position)
	return out


## The outline is showing.
func is_showing() -> bool:
	return _mesh.visible


## The frame in world space, an empty box when hidden.
func frame_aabb() -> AABB:
	if not _mesh.visible:
		return AABB()
	return _mesh.global_transform * _mesh.mesh.get_aabb()


## A flat frame `width` wide around `rect` on the xz plane at y = 0: grown out
## from the rectangle's edge when `outside`, else drawn inside it.
static func frame_mesh(rect: Rect2, width: float, outside: bool) -> ArrayMesh:
	var outer := rect.grow(width) if outside else rect
	var inner := rect if outside else rect.grow(-width)
	var corners_outer := _corners(outer)
	var corners_inner := _corners(inner)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in 4:
		var next := (side + 1) % 4
		var quad: Array[Vector3] = [
			corners_outer[side], corners_outer[next], corners_inner[next], corners_inner[side]
		]
		for i in [0, 1, 2, 0, 2, 3]:
			surface.add_vertex(quad[i])
	return surface.commit()


static func _corners(rect: Rect2) -> Array[Vector3]:
	var end := rect.end
	return [
		Vector3(rect.position.x, 0.0, rect.position.y),
		Vector3(end.x, 0.0, rect.position.y),
		Vector3(end.x, 0.0, end.y),
		Vector3(rect.position.x, 0.0, end.y),
	]
