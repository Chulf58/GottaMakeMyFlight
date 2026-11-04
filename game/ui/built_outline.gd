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
## Lift over the floor top (ThoughtMarker.SPOT_LIFT_M), so it does not fight it.
const LIFT_M := 0.03
## A car park's slab and kerb stand above the ground (LandsidePlacement.SLAB_HEIGHT), so
## its frame sits higher.
const LANDSIDE_LIFT_M := LandsidePlacement.SLAB_HEIGHT + 0.15

var selection: BuiltSelection
var build_mode: BuildMode

var _mesh := MeshInstance3D.new()
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


func _process(_delta: float) -> void:
	refresh()


## Redraws for the current selection; hides with none.
func refresh() -> void:
	if selection == null or build_mode == null or not selection.is_selected():
		_mesh.visible = false
		_drawn = ""
		return
	var grid := build_mode.grid
	var rect := selection.outline_rect(grid, build_mode.landside_placement())
	var key := "%s:%s" % [selection.key(), rect]
	_mesh.visible = rect.has_area()
	if key == _drawn or not _mesh.visible:
		return
	_drawn = key
	var on_landside := selection.kind == BuiltSelection.Kind.LANDSIDE
	var width := LANDSIDE_WIDTH_M if on_landside else GRID_WIDTH_M
	var outside := selection.kind == BuiltSelection.Kind.OBJECT
	_mesh.mesh = frame_mesh(rect, width, outside)
	_mesh.position.y = LANDSIDE_LIFT_M if on_landside else grid.origin.y + LIFT_M


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
