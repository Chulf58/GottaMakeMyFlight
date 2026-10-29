class_name BuildView
extends Node3D
## Draws a BuildGrid with the interior kit (InteriorKit): floor tiles, walls
## and posts as one multimesh per kit mesh, one node per placed object. Walls
## facing the camera are cut down to a stub (WallCutaway), updated as the
## camera turns. A view only: it holds no state the grid does not have, and
## refresh() redraws from the grid. An entrance or exit door's piece stands
## on its back edge and drops with the cutaway like a door wall.

const WALL_HEIGHT := InteriorKit.WALL_HEIGHT
const WALL_THICKNESS := 0.14
const AREA_COLOR := Color(0.3, 0.42, 0.27)
## The build area plane sits under the floor tiles (their top is at 0, their
## underside at -0.04).
const AREA_Y := -0.05
## The kit's kind for each BuildGrid.WallKind that is a wall.
const KIT_WALL_KINDS := {
	BuildGrid.WallKind.PLAIN: InteriorKit.WallKind.PLAIN,
	BuildGrid.WallKind.GLASS: InteriorKit.WallKind.GLASS,
	BuildGrid.WallKind.DOOR: InteriorKit.WallKind.DOOR,
}

## The clear opening of an uncut door wall: half its width, from the jamb
## stubs a cut door keeps (InteriorKit), and the underside of its lintel.
const DOOR_OPENING_HALF := InteriorKit.JAMB_OFFSET - InteriorKit.JAMB_WIDTH / 2.0
const DOOR_OPENING_TOP := 2.24

## Def id -> pick_height(), worked out once from the kit piece.
static var _pick_heights: Dictionary = {}

## Turns walls facing the camera into stubs. Off draws every wall full.
var cutaway_enabled := true:
	set(value):
		cutaway_enabled = value
		_cutaway.reset()
		_draw_walls()
## The InteriorKit.WallKind of the wall on an edge, called as (cell, side)
## with the edge in WallCutaway.wall_edges form, for edges that have a wall.
## By default the grid's own kinds; a caller may supply others.
var wall_kind_source: Callable = grid_wall_kind

var _grid: BuildGrid
var _cutaway := WallCutaway.new()
var _batches: Dictionary = {}
## piece -> the transforms it was last drawn at.
var _drawn: Dictionary = {}
var _wall_edges: Array[Vector3i] = []
var _wall_kinds: Dictionary = {}
var _cut_edges: Dictionary = {}
var _area := MeshInstance3D.new()
var _object_nodes: Dictionary = {}


## How tall an object type stands as drawn: the top of its kit piece's meshes,
## or the def's height when that is taller or the type has no piece. BuildMode
## picks objects up to this height, so a click on the top of a model finds it.
static func pick_height(def: BuildObjectDef) -> float:
	if _pick_heights.has(def.id):
		return _pick_heights[def.id]
	var top := def.height
	var piece := InteriorKit.object_piece(def.id)
	if piece != "":
		var lift := InteriorKit.object_offset(def.id).y
		for part in InteriorKit.meshes(piece):
			var bounds: AABB = (part[1] as Transform3D) * (part[0] as Mesh).get_aabb()
			top = maxf(top, bounds.end.y + lift)
	_pick_heights[def.id] = top
	return top


## How high the wall drawn on an edge (WallCutaway.wall_edges form) hides what
## is behind it: a full plain or door wall its whole height, a cut one its
## stub, a glass wall only its kerb, and an edge with no wall nothing.
func sight_height(edge: Vector3i) -> float:
	if not _wall_kinds.has(edge):
		return 0.0
	if _wall_kinds[edge] == InteriorKit.WallKind.GLASS:
		return InteriorKit.GLASS_KERB_TOP
	if _cut_edges.has(edge):
		return InteriorKit.STUB_HEIGHT
	return WALL_HEIGHT


## Whether the wall drawn on an edge hides a line of sight crossing it `along`
## metres from the wall's middle and `height` metres up. It hides what
## sight_height() says, except that an uncut door wall has a clear opening
## through its middle: DOOR_OPENING_HALF either side of the door axis, up to
## DOOR_OPENING_TOP (wall_door.glb: the leaves park beside it, the lintel is
## above it).
func sight_blocked(edge: Vector3i, along: float, height: float) -> bool:
	if height >= sight_height(edge):
		return false
	var door: bool = _wall_kinds.get(edge, -1) == InteriorKit.WallKind.DOOR
	var open: bool = door and not _cut_edges.has(edge)
	return not (open and absf(along) < DOOR_OPENING_HALF and height < DOOR_OPENING_TOP)


## The node for an object type, centred on its footprint at facing 0: the
## kit piece with its own materials, or with `material` on every mesh (for a
## ghost, the carried piece too). A type the kit has no piece for gets a
## placeholder box. A piece with an offset (InteriorKit.object_offset) goes
## under a plain root node.
static func make_object_node(def: BuildObjectDef, material: Material) -> Node3D:
	var piece := InteriorKit.object_piece(def.id)
	if piece == "":
		push_warning("BuildView: no kit piece for '%s', drawing a box" % def.id)
		return _placeholder(def, material if material != null else _solid(def.color))
	var root := InteriorKit.instantiate(piece)
	InteriorKit.attach_mounted(root, def.id)
	var offset := InteriorKit.object_offset(def.id)
	if offset != Vector3.ZERO:
		var holder := Node3D.new()
		root.position = offset
		holder.add_child(root)
		root = holder
	root.name = str(def.id)
	if material != null:
		for mesh in root.find_children("*", "MeshInstance3D", true, false):
			(mesh as MeshInstance3D).material_override = material
	return root


## Where an object node goes: the middle of its footprint, turned by facing.
static func object_transform(grid: BuildGrid, cells: Array[Vector2i], facing: int) -> Transform3D:
	var centre := Vector3.ZERO
	for cell in cells:
		centre += grid.cell_to_world(cell)
	centre /= cells.size()
	return Transform3D(Basis(Vector3.UP, -facing * PI / 2.0), centre)


## The frame of a wall piece on an edge: on the edge's midpoint at height 0,
## its length along the edge.
static func wall_transform(grid: BuildGrid, cell: Vector2i, side: int) -> Transform3D:
	var step := BuildGrid.SIDE_STEP[side]
	var centre := grid.cell_to_world(cell) + Vector3(step.x * 0.5, 0.0, step.y * 0.5)
	var turn := PI / 2.0 if step.x != 0 else 0.0
	return Transform3D(Basis(Vector3.UP, turn), centre)


static func _placeholder(def: BuildObjectDef, material: Material) -> Node3D:
	var root := Node3D.new()
	root.name = str(def.id)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(def.size.x - 0.1, def.height, def.size.y - 0.1)
	var box := MeshInstance3D.new()
	box.mesh = mesh
	box.position = Vector3(0.0, def.height / 2.0, 0.0)
	box.material_override = material
	root.add_child(box)
	return root


static func _solid(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material


func _ready() -> void:
	_area.name = "BuildArea"
	_area.mesh = PlaneMesh.new()
	_area.material_override = _solid(AREA_COLOR)
	add_child(_area)


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		update_cutaway(camera.global_basis.z)


## Points the cutaway at a camera whose direction toward the eye is
## `toward_eye`, and redraws the walls when that changes which walls drop.
func update_cutaway(toward_eye: Vector3) -> void:
	if cutaway_enabled and _cutaway.update(toward_eye):
		_draw_walls()


## The kit kind of the grid's wall on an edge that has one.
func grid_wall_kind(cell: Vector2i, side: int) -> int:
	return KIT_WALL_KINDS[_grid.wall_kind(cell, side)]


func object_node_count() -> int:
	return _object_nodes.size()


## The node drawing a placed object, or null.
func object_node(object_id: int) -> Node3D:
	return _object_nodes.get(object_id)


## Edges (WallCutaway.wall_edges form) drawn as stubs right now.
func cut_edges() -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	result.assign(_cut_edges.keys())
	return result


## How many instances of each kit piece are drawn, keyed by piece name.
func piece_counts() -> Dictionary:
	var counts := {}
	for piece in _batches:
		var batch: Array = _batches[piece]
		counts[piece] = (batch[0] as MultiMeshInstance3D).multimesh.instance_count
	return counts


## Where each instance of a piece is drawn, in the piece frame, for checks.
## (Read back from the multimesh, a headless run would give identities.)
func piece_transforms(piece: String) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	result.assign(_drawn.get(piece, []))
	return result


func refresh(grid: BuildGrid) -> void:
	_grid = grid
	(_area.mesh as PlaneMesh).size = Vector2(grid.size)
	_area.position = grid.origin + Vector3(grid.size.x / 2.0, AREA_Y, grid.size.y / 2.0)
	_draw_floors()
	_wall_edges = WallCutaway.wall_edges(grid)
	_wall_kinds.clear()
	for edge in _wall_edges:
		_wall_kinds[edge] = wall_kind_source.call(Vector2i(edge.x, edge.y), edge.z)
	_sync_objects()
	_draw_walls()


func _draw_floors() -> void:
	var transforms: Array[Transform3D] = []
	for y in _grid.size.y:
		for x in _grid.size.x:
			var cell := Vector2i(x, y)
			if _grid.floor_at(cell) != BuildGrid.FLOOR_NONE:
				transforms.append(Transform3D(Basis.IDENTITY, _grid.cell_to_world(cell)))
	_fill({"floor_tile": transforms}, ["floor_tile"])


func _draw_walls() -> void:
	if _grid == null:
		return
	_cut_edges.clear()
	for edge in _wall_edges:
		if _cutaway.is_cut(_grid, Vector2i(edge.x, edge.y), edge.z):
			_cut_edges[edge] = true
	# A door's leaves park over the walls beside it, so it drops with them.
	for edge in _wall_edges:
		if _wall_kinds[edge] == InteriorKit.WallKind.DOOR:
			for beside in WallCutaway.inline_neighbours(edge):
				if _cut_edges.has(beside):
					_cut_edges[edge] = true
	var placed := {}
	_draw_door_objects(placed)
	var full := {}
	for edge in _wall_edges:
		var cut := _cut_edges.has(edge)
		full[edge] = not cut
		var frame := wall_transform(_grid, Vector2i(edge.x, edge.y), edge.z)
		for part in InteriorKit.wall_parts(_wall_kinds[edge], cut):
			_place(placed, part[0], frame * part[1])
	var posts := WallCutaway.posts(_wall_edges, full)
	for vertex in posts:
		var at := _grid.origin + Vector3(vertex.x, 0.0, vertex.y)
		for part in InteriorKit.post_parts(not posts[vertex]):
			_place(placed, part[0], Transform3D(Basis.IDENTITY, at) * part[1])
	_fill(placed, ["wall", "wall_glass", InteriorKit.GLASS_KERB, "wall_door", "wall_post"])


## Entrance and exit doors: their piece hides and two jambs are drawn on the
## back edge when that edge, or a wall in line with it, is cut.
func _draw_door_objects(placed: Dictionary) -> void:
	for object_id in _object_nodes:
		# The record the node was drawn from: the grid may have changed since
		# the last refresh().
		var record: Dictionary = (_object_nodes[object_id] as Node3D).get_meta("record")
		if not BuildCatalog.is_door(record["def"]):
			continue
		var anchor: Vector2i = record["anchor"]
		var out := BuildObjectDef.rotate_offset(Vector2i(0, -1), record["facing"])
		var side := BuildGrid.SIDE_STEP.find(out)
		var edge := _edge_key(anchor, side)
		var cut := _cutaway.is_cut(_grid, anchor, side)
		for beside in WallCutaway.inline_neighbours(edge):
			cut = cut or _cut_edges.has(beside)
		(_object_nodes[object_id] as Node3D).visible = not cut
		if not cut:
			continue
		_cut_edges[edge] = true
		var frame := wall_transform(_grid, anchor, side)
		for part in InteriorKit.wall_parts(InteriorKit.WallKind.DOOR, true):
			_place(placed, part[0], frame * part[1])


## An edge in WallCutaway.wall_edges form: north or west of a cell, or south
## of the last row, east of the last column.
func _edge_key(cell: Vector2i, side: int) -> Vector3i:
	if side == BuildGrid.Side.SOUTH and cell.y + 1 < _grid.size.y:
		return Vector3i(cell.x, cell.y + 1, BuildGrid.Side.NORTH)
	if side == BuildGrid.Side.EAST and cell.x + 1 < _grid.size.x:
		return Vector3i(cell.x + 1, cell.y, BuildGrid.Side.WEST)
	return Vector3i(cell.x, cell.y, side)


func _place(placed: Dictionary, piece: String, at: Transform3D) -> void:
	if not placed.has(piece):
		placed[piece] = []
	placed[piece].append(at)


func _sync_objects() -> void:
	var live := _grid.object_ids()
	for object_id in _object_nodes.keys():
		var node: Node3D = _object_nodes[object_id]
		if not live.has(object_id) or node.get_meta("record") != _grid.get_object(object_id):
			node.queue_free()
			_object_nodes.erase(object_id)
	for object_id in live:
		if _object_nodes.has(object_id):
			continue
		var record := _grid.get_object(object_id)
		var def := BuildCatalog.get_def(record["def"])
		var created := make_object_node(def, null)
		created.set_meta("record", record)
		created.transform = object_transform(
			_grid, def.footprint(record["anchor"], record["facing"]), record["facing"]
		)
		add_child(created)
		_object_nodes[object_id] = created


## Sets the instances of each named piece from `placed` (piece -> transforms
## in the piece's frame); a piece missing from `placed` draws none.
func _fill(placed: Dictionary, pieces: Array) -> void:
	for piece in pieces:
		var transforms: Array = placed.get(piece, [])
		_drawn[piece] = transforms
		var batch := _batch(piece)
		var parts := InteriorKit.meshes(piece)
		for i in parts.size():
			var multimesh := (batch[i] as MultiMeshInstance3D).multimesh
			multimesh.instance_count = transforms.size()
			for k in transforms.size():
				multimesh.set_instance_transform(k, transforms[k] * parts[i][1])


## The multimesh instances of a piece, one per mesh in it, made on first use.
func _batch(piece: String) -> Array:
	if _batches.has(piece):
		return _batches[piece]
	var batch := []
	for part in InteriorKit.meshes(piece):
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = part[0]
		var instance := MultiMeshInstance3D.new()
		instance.name = "%s_%d" % [piece, batch.size()]
		instance.multimesh = multimesh
		add_child(instance)
		batch.append(instance)
	_batches[piece] = batch
	return batch
