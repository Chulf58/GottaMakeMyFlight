class_name TestBaggageView
extends GdUnitTestSuite
## BuildView draws the baggage pieces with their kit models, not placeholder
## boxes (decision baggage-rides-a-player-built-belt-from-check-in-to-a-bag-roo):
## the 1x2 cart sits centred on its two cells at every facing, a feed drawn
## behind a check-in desk has its inlet on the desk's belt outlet, and the
## desk's own belt runs to that outlet edge.

const GRID := Vector2i(16, 16)
const ANCHOR := Vector2i(7, 7)
const BAGGAGE_IDS: Array[StringName] = [
	&"baggage_belt",
	&"baggage_belt_corner",
	&"baggage_belt_feed",
	&"baggage_belt_end",
	&"baggage_cart",
]
## Kit pieces are authored to the millimetre; export bounds hold to 6 mm.
const EPS := 0.006

var _grid: BuildGrid


func before() -> void:
	_grid = BuildGrid.new(GRID)


## The bounds of a node's meshes in the node's own frame.
func _local_bounds(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var local := mi.transform
		var parent := mi.get_parent()
		while parent != root:
			local = (parent as Node3D).transform * local
			parent = parent.get_parent()
		var part := local * mi.mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box


## The node's transform relative to `root`.
func _relative(root: Node3D, node: Node3D) -> Transform3D:
	var local := node.transform
	var parent := node.get_parent()
	while parent != root:
		local = (parent as Node3D).transform * local
		parent = parent.get_parent()
	return local


func test_every_baggage_piece_draws_its_own_kit_model() -> void:
	for id in BAGGAGE_IDS:
		assert_str(InteriorKit.object_piece(id)).is_equal(str(id))
		var node := auto_free(BuildView.make_object_node(BuildCatalog.get_def(id), null)) as Node3D
		var meshes := node.find_children("*", "MeshInstance3D", true, false)
		assert_int(meshes.size()).override_failure_message("%s meshes" % id).is_greater(0)
		# The node is the piece's own scene, not a box under the def's name.
		assert_str(node.scene_file_path).is_equal(InteriorKit.PIECE_PATH % id)
		for mi in meshes:
			var mesh := (mi as MeshInstance3D).mesh
			# A placeholder is one BoxMesh; a kit piece is an imported ArrayMesh.
			assert_bool(mesh is BoxMesh).override_failure_message("%s is a box" % id).is_false()
			assert_int(mesh.get_surface_count()).is_greater(0)
			for surface in mesh.get_surface_count():
				# The toon materials the importer binds by name, not an empty slot.
				(
					assert_object(mesh.surface_get_material(surface))
					. override_failure_message("%s surface %d" % [id, surface])
					. is_not_null()
				)


func test_the_cart_is_centred_on_its_two_cells_at_every_facing() -> void:
	# One cart per facing, drawn by a real BuildView from the grid.
	var grid := BuildGrid.new(GRID)
	var edits: Array[BuildEdit] = []
	for y in GRID.y:
		for x in GRID.x:
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	grid.apply_batch(edits)
	var anchors := [Vector2i(2, 2), Vector2i(6, 2), Vector2i(2, 8), Vector2i(8, 8)]
	for facing in 4:
		var placed := grid.apply(BuildEdit.place_object(&"baggage_cart", anchors[facing], facing))
		assert_bool(placed.ok).is_true()
	var view := BuildView.new()
	add_child(view)
	view.refresh(grid)
	var def := BuildCatalog.get_def(&"baggage_cart")
	var drawn := 0
	for child in view.get_children():
		if not child.has_meta("record"):
			continue
		var record: Dictionary = child.get_meta("record")
		var facing: int = record["facing"]
		var cells := def.footprint(record["anchor"], facing)
		var centre := (grid.cell_to_world(cells[0]) + grid.cell_to_world(cells[1])) / 2.0
		var world := _world_bounds(child)
		var mid := world.get_center()
		var info := "facing %d cells %s bounds %s centre %s" % [facing, cells, world, centre]
		var off := Vector2(mid.x, mid.z).distance_to(Vector2(centre.x, centre.z))
		assert_float(off).override_failure_message(info).is_less(EPS)
		# The long side lies along the two cells and stays inside them.
		var along := Vector2(cells[1] - cells[0]).abs()
		assert_bool(world.size.x > world.size.z).override_failure_message(info).is_equal(
			along.x > along.y
		)
		assert_float(maxf(world.size.x, world.size.z)).is_greater(1.5)
		assert_float(world.size.x).override_failure_message(info).is_less_equal(along.x + 1.0)
		assert_float(world.size.z).override_failure_message(info).is_less_equal(along.y + 1.0)
		drawn += 1
	assert_int(drawn).is_equal(4)
	view.free()


## The bounds of a node's meshes in world space.
func _world_bounds(root: Node) -> AABB:
	var box := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var part := mi.global_transform * mi.mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box


func test_a_feed_drawn_behind_a_desk_has_its_inlet_on_the_desk_outlet() -> void:
	var feed_def := BuildCatalog.get_def(&"baggage_belt_feed")
	var feed := auto_free(BuildView.make_object_node(feed_def, null)) as Node3D
	var inlet_node := feed.find_child("Mount_Belt_F", true, false) as Node3D
	assert_object(inlet_node).is_not_null()
	var inlet_local := _relative(feed, inlet_node)
	for facing in 4:
		var outlet: Dictionary = BuildCatalog.belt_ports(&"checkin_desk", ANCHOR, facing)[0]
		var anchor: Vector2i = outlet["cell"] + outlet["side"]
		var cells := feed_def.footprint(anchor, facing)
		var inlet := BuildView.object_transform(_grid, cells, facing) * inlet_local
		var side: Vector2i = outlet["side"]
		var edge := _grid.cell_to_world(outlet["cell"]) + Vector3(side.x, 0.0, side.y) * 0.5
		var info := "facing %d inlet %s outlet edge %s" % [facing, inlet.origin, edge]
		(
			assert_float(
				Vector2(inlet.origin.x, inlet.origin.z).distance_to(Vector2(edge.x, edge.z))
			)
			. override_failure_message(info)
			. is_less(0.002)
		)
		# The inlet's +Z points back at the desk, out of the feed.
		var out := inlet.basis.z.normalized()
		assert_float(out.distance_to(-Vector3(side.x, 0.0, side.y))).is_less(0.002)


func test_the_desk_belt_reaches_its_back_edge_with_the_belt_cross_section() -> void:
	var desk := BuildCatalog.get_def(&"checkin_desk")
	var node := auto_free(BuildView.make_object_node(desk, null)) as Node3D
	var box := _local_bounds(node)
	# Facing 0: the front is +Z and the belt outlet is the back edge, z = -0.5.
	assert_float(box.position.z).is_equal_approx(-0.5, EPS)
	assert_float(box.end.z).is_equal_approx(0.42, EPS)
	assert_float(box.size.x).is_equal_approx(1.84, EPS)
	# The vertices on that edge are the belt's end: body and rails x 0.08..0.92,
	# rails up to 0.46, and the belt top at 0.355 between x 0.15 and 0.85 (the
	# belt pieces' cross-section, build_baggage_kit.py).
	var xs: Array[float] = []
	var top_xs: Array[float] = []
	var max_y := 0.0
	for node_mi in node.find_children("*", "MeshInstance3D", true, false):
		var mi := node_mi as MeshInstance3D
		var local := _relative(node, mi)
		for surface in mi.mesh.get_surface_count():
			var verts: PackedVector3Array = mi.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for v in verts:
				var p := local * v
				if p.z > -0.5 + 0.002:
					continue
				xs.append(p.x)
				max_y = maxf(max_y, p.y)
				if absf(p.y - 0.355) < 0.002:
					top_xs.append(p.x)
	assert_int(xs.size()).is_greater(0)
	assert_float(xs.min()).is_equal_approx(0.08, 0.002)
	assert_float(xs.max()).is_equal_approx(0.92, 0.002)
	assert_float(max_y).is_equal_approx(0.46, 0.002)
	assert_float(top_xs.min()).is_equal_approx(0.15, 0.002)
	assert_float(top_xs.max()).is_equal_approx(0.85, 0.002)
