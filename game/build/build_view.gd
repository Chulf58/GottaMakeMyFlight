class_name BuildView
extends Node3D
## Draws a BuildGrid with placeholder meshes: floor tiles and walls as
## multimeshes, one node per placed object. A view only; it holds no state
## the grid does not have, and refresh() redraws from the grid.

const TILE_GAP := 0.04
const TILE_THICKNESS := 0.04
const WALL_HEIGHT := 2.0
const WALL_THICKNESS := 0.12
const FLOOR_COLOR := Color(0.78, 0.76, 0.7)
const WALL_COLOR := Color(0.92, 0.9, 0.84)
const AREA_COLOR := Color(0.3, 0.42, 0.27)

var _floor_mesh := MultiMeshInstance3D.new()
var _wall_mesh := MultiMeshInstance3D.new()
var _area := MeshInstance3D.new()
var _object_nodes: Dictionary = {}


## A placeholder node for an object type, centred on its footprint at facing
## 0. A scanner is an arch open along its own z axis; the rest are boxes.
static func make_object_node(def: BuildObjectDef, material: Material) -> Node3D:
	var root := Node3D.new()
	root.name = str(def.id)
	var extent := Vector3(def.size.x, def.height, def.size.y)
	if def.walk_through:
		var post := Vector3(0.16, def.height, extent.z)
		for x in [-0.42, 0.42]:
			root.add_child(_box(post, Vector3(x, def.height / 2.0, 0.0), material))
		var beam := Vector3(extent.x, 0.25, extent.z)
		root.add_child(_box(beam, Vector3(0.0, def.height - 0.125, 0.0), material))
	else:
		extent.x -= 0.1
		extent.z -= 0.1
		root.add_child(_box(extent, Vector3(0.0, def.height / 2.0, 0.0), material))
	return root


## Where an object node goes: the middle of its footprint, turned by facing.
static func object_transform(grid: BuildGrid, cells: Array[Vector2i], facing: int) -> Transform3D:
	var centre := Vector3.ZERO
	for cell in cells:
		centre += grid.cell_to_world(cell)
	centre /= cells.size()
	return Transform3D(Basis(Vector3.UP, -facing * PI / 2.0), centre)


## The transform of a wall box on an edge, for a box WALL_THICKNESS deep.
static func wall_transform(grid: BuildGrid, cell: Vector2i, side: int) -> Transform3D:
	var step := BuildGrid.SIDE_STEP[side]
	var centre := grid.cell_to_world(cell) + Vector3(step.x * 0.5, WALL_HEIGHT / 2.0, step.y * 0.5)
	var turn := PI / 2.0 if step.x != 0 else 0.0
	return Transform3D(Basis(Vector3.UP, turn), centre)


static func _box(extent: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = extent
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.material_override = material
	return instance


static func _solid(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material


func _ready() -> void:
	_floor_mesh.name = "Floors"
	_floor_mesh.multimesh = _multimesh(
		Vector3(1.0 - TILE_GAP, TILE_THICKNESS, 1.0 - TILE_GAP), FLOOR_COLOR
	)
	add_child(_floor_mesh)
	_wall_mesh.name = "Walls"
	_wall_mesh.multimesh = _multimesh(Vector3(1.0, WALL_HEIGHT, WALL_THICKNESS), WALL_COLOR)
	add_child(_wall_mesh)
	_area.name = "BuildArea"
	_area.mesh = PlaneMesh.new()
	_area.material_override = _solid(AREA_COLOR)
	add_child(_area)


func object_node_count() -> int:
	return _object_nodes.size()


func refresh(grid: BuildGrid) -> void:
	(_area.mesh as PlaneMesh).size = Vector2(grid.size)
	_area.position = Vector3(0.0, 0.005, 0.0)
	_draw_floors(grid)
	_draw_walls(grid)
	_sync_objects(grid)


func _draw_floors(grid: BuildGrid) -> void:
	var transforms: Array[Transform3D] = []
	for y in grid.size.y:
		for x in grid.size.x:
			var cell := Vector2i(x, y)
			if grid.floor_at(cell) != BuildGrid.FLOOR_NONE:
				var at := grid.cell_to_world(cell) + Vector3(0.0, TILE_THICKNESS / 2.0, 0.0)
				transforms.append(Transform3D(Basis.IDENTITY, at))
	_fill(_floor_mesh.multimesh, transforms)


func _draw_walls(grid: BuildGrid) -> void:
	var transforms: Array[Transform3D] = []
	for y in grid.size.y:
		for x in grid.size.x:
			var cell := Vector2i(x, y)
			var sides := [BuildGrid.Side.NORTH, BuildGrid.Side.WEST]
			if y == grid.size.y - 1:
				sides.append(BuildGrid.Side.SOUTH)
			if x == grid.size.x - 1:
				sides.append(BuildGrid.Side.EAST)
			for side in sides:
				if grid.has_wall(cell, side):
					transforms.append(wall_transform(grid, cell, side))
	_fill(_wall_mesh.multimesh, transforms)


func _sync_objects(grid: BuildGrid) -> void:
	var live := grid.object_ids()
	for object_id in _object_nodes.keys():
		var node: Node3D = _object_nodes[object_id]
		if not live.has(object_id) or node.get_meta("record") != grid.get_object(object_id):
			node.queue_free()
			_object_nodes.erase(object_id)
	for object_id in live:
		if _object_nodes.has(object_id):
			continue
		var record := grid.get_object(object_id)
		var def := BuildCatalog.get_def(record["def"])
		var created := make_object_node(def, _solid(def.color))
		created.set_meta("record", record)
		created.transform = object_transform(
			grid, def.footprint(record["anchor"], record["facing"]), record["facing"]
		)
		add_child(created)
		_object_nodes[object_id] = created


func _multimesh(extent: Vector3, color: Color) -> MultiMesh:
	var mesh := BoxMesh.new()
	mesh.size = extent
	mesh.material = _solid(color)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	return multimesh


func _fill(multimesh: MultiMesh, transforms: Array[Transform3D]) -> void:
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
