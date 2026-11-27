class_name BaggagePortOverlay
extends Node3D
## 3D port and connection overlay for baggage routing (ruling 1b70fa33): shown
## only while BELT or BAG_ROOM is the active build tool, or while a Bag Room is
## selected in BuiltSelection. Highlights every check-in desk back outlet
## (green when routed to a ready bag room, amber when unconnected) and every
## baggage_belt_end inside a bag room. Clean, unshaded, outline-free.

const CONNECTED_COLOR := Color(0.22, 0.85, 0.42, 0.9)
const INBOUND_CONNECTED_COLOR := Color(0.20, 0.78, 0.95, 0.9)
const UNCONNECTED_COLOR := Color(1.0, 0.68, 0.18, 0.9)
## Sits just above belt rail height (0.46 m) so markers stay legible even when
## a belt is already attached to the outlet or end.
const PORT_Y := 0.52
const PAD_Y := 0.04

var build_mode: BuildMode
var selection: BuiltSelection

var _grid: BuildGrid
var _dirty := true
var _markers: Array[Dictionary] = []
var _materials := {}
var _arrow_mesh: ArrayMesh
var _ring_mesh: ArrayMesh


func _init() -> void:
	visible = false


func watch(mode: BuildMode, grid: BuildGrid, with_selection: BuiltSelection = null) -> void:
	build_mode = mode
	_grid = grid
	if with_selection != null:
		selection = with_selection
	if build_mode != null and not build_mode.tool_changed.is_connected(_on_tool_changed):
		build_mode.tool_changed.connect(_on_tool_changed)
	if _grid != null:
		if not _grid.edit_applied.is_connected(_on_edit_applied):
			_grid.edit_applied.connect(_on_edit_applied)
		if not _grid.graph_changed.is_connected(_on_graph_changed):
			_grid.graph_changed.connect(_on_graph_changed)
	_dirty = true
	refresh()


func _process(_delta: float) -> void:
	refresh()


func is_active() -> bool:
	return visible


func markers() -> Array[Dictionary]:
	return _markers.duplicate(true)


func refresh() -> void:
	var show := _should_show()
	if not show:
		if visible or not _markers.is_empty():
			_clear_nodes()
			_markers.clear()
		visible = false
		return
	var was_hidden := not visible
	visible = true
	if _dirty or was_hidden:
		_rebuild()


func _on_tool_changed(_new_tool: BuildMode.Tool) -> void:
	_dirty = true
	refresh()


func _on_edit_applied(_edit: BuildEdit, _result: BuildResult) -> void:
	_dirty = true


func _on_graph_changed(_cells: Array[Vector2i]) -> void:
	_dirty = true


func _should_show() -> bool:
	if _grid == null:
		return false
	if (
		build_mode != null
		and (
			build_mode.tool == BuildMode.Tool.BELT
			or build_mode.tool == BuildMode.Tool.BAG_ROOM
			or build_mode.tool == BuildMode.Tool.BAGGAGE_CLAIM
			or build_mode.tool == BuildMode.Tool.CLAIM_CAROUSEL
		)
	):
		return true
	var sel := _resolve_selection()
	if sel != null and sel.kind == BuiltSelection.Kind.ROOM:
		var room := _grid.get_room(sel.id)
		if room.is_empty():
			return false
		var rtype := StringName(room["type"])
		return rtype == BeltShaper.BAG_ROOM or rtype == BeltShaper.BAGGAGE_CLAIM
	return false


func _resolve_selection() -> BuiltSelection:
	if selection != null:
		return selection
	if not is_inside_tree():
		return null
	var root := get_tree().root
	if root == null:
		return null
	var outline := root.find_child("BuiltOutline", true, false) as BuiltOutline
	return outline.selection if outline != null else null


func _rebuild() -> void:
	_dirty = false
	_clear_nodes()
	_markers.clear()
	if _grid == null:
		return
	var routes := BagRoutes.build(_grid)
	var routed_roots := {}
	for desk_id in routes.connected_desks():
		var entry := routes.entry_of(desk_id)
		if not entry.is_empty():
			routed_roots[routes.root_of(entry["cell"])] = true
	var ids := _grid.object_ids()
	ids.sort()
	for object_id in ids:
		var record := _grid.get_object(object_id)
		var def_id := StringName(record["def"])
		if def_id == BeltShaper.DESK:
			_add_desk_outlet(object_id, record, routes)
		elif def_id == BeltShaper.CLAIM_CAROUSEL:
			_add_carousel_inlet(object_id, record, routes)
		elif def_id == BeltShaper.END:
			_add_belt_end(object_id, record, routed_roots, routes)


func _add_desk_outlet(object_id: int, record: Dictionary, routes: BagRoutes) -> void:
	var ports := BuildCatalog.belt_ports(BeltShaper.DESK, record["anchor"], record["facing"])
	if ports.is_empty():
		return
	var port := ports[0]
	var cell: Vector2i = port["cell"]
	var side: Vector2i = port["side"]
	var connected := routes.desk_connected(object_id)
	var color := CONNECTED_COLOR if connected else UNCONNECTED_COLOR
	var mat := _material(color)
	var arrow := MeshInstance3D.new()
	arrow.name = "OutletMarker_%d" % object_id
	arrow.mesh = _port_arrow()
	arrow.material_override = mat
	arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var world_base := _grid.cell_to_world(cell) + Vector3(side.x, 0.0, side.y) * 0.55
	arrow.position = Vector3(world_base.x, _grid.origin.y + PORT_Y, world_base.z)
	arrow.rotation.y = atan2(-float(side.x), -float(side.y))
	add_child(arrow)
	(
		_markers
		. append(
			{
				"kind": &"desk_outlet",
				"object_id": object_id,
				"cell": cell,
				"connected": connected,
				"color": color,
			}
		)
	)


func _add_carousel_inlet(object_id: int, record: Dictionary, routes: BagRoutes) -> void:
	var ports := BuildCatalog.belt_ports(
		BeltShaper.CLAIM_CAROUSEL, record["anchor"], record["facing"]
	)
	if ports.is_empty():
		return
	var port := ports[0]
	var cell: Vector2i = port["cell"]
	var side: Vector2i = port["side"]
	var connected := routes.connected_carousels().has(object_id)
	var color := INBOUND_CONNECTED_COLOR if connected else UNCONNECTED_COLOR
	var mat := _material(color)
	var arrow := MeshInstance3D.new()
	arrow.name = "CarouselInletMarker_%d" % object_id
	arrow.mesh = _port_arrow()
	arrow.material_override = mat
	arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var world_base := _grid.cell_to_world(cell) + Vector3(side.x, 0.0, side.y) * 0.55
	arrow.position = Vector3(world_base.x, _grid.origin.y + PORT_Y, world_base.z)
	arrow.rotation.y = atan2(float(side.x), float(side.y))
	add_child(arrow)
	(
		_markers
		. append(
			{
				"kind": &"carousel_inlet",
				"object_id": object_id,
				"cell": cell,
				"connected": connected,
				"color": color,
			}
		)
	)


func _add_belt_end(
	object_id: int, record: Dictionary, routed_roots: Dictionary, routes: BagRoutes
) -> void:
	var cell: Vector2i = record["anchor"]
	var room_id := _grid.room_at(cell)
	if room_id == 0:
		return
	var room := _grid.get_room(room_id)
	if room.is_empty() or StringName(room["type"]) != BeltShaper.BAG_ROOM:
		return
	var is_inbound := routes.inbound_component.has(cell)
	var connected := routes.has_inbound_route(cell) if is_inbound else routed_roots.has(cell)
	var color := (
		(INBOUND_CONNECTED_COLOR if connected else UNCONNECTED_COLOR)
		if is_inbound
		else (CONNECTED_COLOR if connected else UNCONNECTED_COLOR)
	)
	var mat := _material(color)
	var ring := MeshInstance3D.new()
	ring.name = "BeltEndMarker_%d" % object_id
	ring.mesh = _cell_ring()
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var world_cell := _grid.cell_to_world(cell)
	ring.position = Vector3(world_cell.x, _grid.origin.y + PAD_Y, world_cell.z)
	add_child(ring)
	var ports := BuildCatalog.belt_ports(BeltShaper.END, record["anchor"], record["facing"])
	if not ports.is_empty():
		var side: Vector2i = ports[0]["side"]
		var arrow := MeshInstance3D.new()
		arrow.name = "BeltEndArrow_%d" % object_id
		arrow.mesh = _port_arrow()
		arrow.material_override = mat
		arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var port_world := world_cell + Vector3(side.x, 0.0, side.y) * 0.55
		arrow.position = Vector3(port_world.x, _grid.origin.y + PORT_Y, port_world.z)
		arrow.rotation.y = (
			atan2(-float(side.x), -float(side.y))
			if is_inbound
			else atan2(float(side.x), float(side.y))
		)
		add_child(arrow)
	(
		_markers
		. append(
			{
				"kind": &"belt_end",
				"flow": &"inbound" if is_inbound else &"outbound",
				"object_id": object_id,
				"cell": cell,
				"connected": connected,
				"color": color,
			}
		)
	)


func _clear_nodes() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()


func _material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials[color] = mat
	return _materials[color]


## Flat arrow pointing along -Z, centred on the origin.
func _port_arrow() -> ArrayMesh:
	if _arrow_mesh != null:
		return _arrow_mesh
	var shaft := 0.1
	var head := 0.28
	var outline: Array[Vector2] = [
		Vector2(0.0, -0.34),
		Vector2(head, -0.04),
		Vector2(shaft, -0.04),
		Vector2(shaft, 0.34),
		Vector2(-shaft, 0.34),
		Vector2(-shaft, -0.04),
		Vector2(-head, -0.04),
	]
	var triangles := [[0, 1, 6], [2, 3, 4], [2, 4, 5]]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for tri in triangles:
		for i: int in tri:
			surface.add_vertex(Vector3(outline[i].x, 0.0, outline[i].y))
	_arrow_mesh = surface.commit()
	return _arrow_mesh


## Flat 1x1 m cell border frame on the XZ plane around y = 0.
func _cell_ring() -> ArrayMesh:
	if _ring_mesh != null:
		return _ring_mesh
	var half := 0.48
	var inner := 0.34
	var outer_pts := [
		Vector2(-half, -half),
		Vector2(half, -half),
		Vector2(half, half),
		Vector2(-half, half),
	]
	var inner_pts := [
		Vector2(-inner, -inner),
		Vector2(inner, -inner),
		Vector2(inner, inner),
		Vector2(-inner, inner),
	]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in 4:
		var next := (side + 1) % 4
		var quad := [
			outer_pts[side],
			outer_pts[next],
			inner_pts[next],
			inner_pts[side],
		]
		for i in [0, 1, 2, 0, 2, 3]:
			surface.add_vertex(Vector3(quad[i].x, 0.0, quad[i].y))
	_ring_mesh = surface.commit()
	return _ring_mesh
