class_name TestSecurityLaneView
extends GdUnitTestSuite
## BuildView draws the four security lane parts with their kit models, not
## placeholder boxes (Security 3/8), and a whole lane reads as one conveyor:
## at every facing and both mirrors the tray mounts of the tray table, X-ray
## belt and pickup table lie on one line at belt height in flow order (the
## queue side first), and the parts' belt ends meet with no gap. Lane cells
## come from SecurityLanes.geometry() (the contract at the top of
## game/build/security_lanes.gd).

const GRID := Vector2i(9, 9)
const ANCHOR := Vector2i(4, 4)
const PART_IDS: Array[StringName] = [
	SecurityLanes.ARCH,
	SecurityLanes.TRAY_TABLE,
	SecurityLanes.XRAY_BELT,
	SecurityLanes.PICKUP_TABLE
]
## Tray mount per conveyor part, in flow order.
const MOUNTS := {
	SecurityLanes.TRAY_TABLE: "Mount_TrayIn",
	SecurityLanes.XRAY_BELT: "Mount_TrayScan",
	SecurityLanes.PICKUP_TABLE: "Mount_TrayOut",
}
const BELT_TOP := 0.74
## Kit pieces are authored to the millimetre; export bounds hold to 6 mm.
const EPS := 0.006


func test_every_lane_part_draws_its_own_kit_model() -> void:
	for id in PART_IDS:
		assert_str(InteriorKit.object_piece(id)).is_equal(str(id))
		var node := auto_free(BuildView.make_object_node(BuildCatalog.get_def(id), null)) as Node3D
		var meshes := node.find_children("*", "MeshInstance3D", true, false)
		assert_int(meshes.size()).override_failure_message("%s meshes" % id).is_greater(0)
		assert_str(node.scene_file_path).is_equal(InteriorKit.PIECE_PATH % id)
		for mi in meshes:
			var mesh := (mi as MeshInstance3D).mesh
			assert_bool(mesh is BoxMesh).override_failure_message("%s is a box" % id).is_false()
			for surface in mesh.get_surface_count():
				(
					assert_object(mesh.surface_get_material(surface))
					. override_failure_message("%s surface %d" % [id, surface])
					. is_not_null()
				)


func test_each_part_fits_its_cell_and_only_belt_ends_reach_the_edge() -> void:
	# Facing 0, local frame: front is +Z. [x half, -z reach, +z reach] per part.
	var reach := {
		# The arch's posts reach 0.495 m across (Security 7/8: a 0.91 m clear
		# passage for the 2 m Toon passengers' arm swing); still inside the cell.
		SecurityLanes.ARCH: [0.495, 0.42, 0.42],
		SecurityLanes.TRAY_TABLE: [0.38, 0.5, 0.42],
		SecurityLanes.XRAY_BELT: [0.405, 0.5, 0.5],
		SecurityLanes.PICKUP_TABLE: [0.36, 0.42, 0.5],
	}
	for id in PART_IDS:
		var node := auto_free(BuildView.make_object_node(BuildCatalog.get_def(id), null)) as Node3D
		var box := _local_bounds(node)
		var want: Array = reach[id]
		var info := "%s bounds %s" % [id, box]
		assert_float(box.position.x).override_failure_message(info).is_equal_approx(-want[0], EPS)
		assert_float(box.end.x).override_failure_message(info).is_equal_approx(want[0], EPS)
		assert_float(box.position.z).override_failure_message(info).is_equal_approx(-want[1], EPS)
		assert_float(box.end.z).override_failure_message(info).is_equal_approx(want[2], EPS)
		assert_float(box.position.y).override_failure_message(info).is_equal_approx(0.0, EPS)


func test_a_lane_is_one_conveyor_at_every_facing_and_mirror() -> void:
	var lanes := 0
	for facing in 4:
		for mirror in SecurityLanes.MIRRORS:
			var grid := BuildGrid.new(GRID)
			var edits: Array[BuildEdit] = []
			for y in GRID.y:
				for x in GRID.x:
					edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
			grid.apply_batch(edits)
			var ids := SecurityLaneBuilder.build(grid, ANCHOR, facing, mirror)
			var recognised := SecurityLaneBuilder.recognise(grid)
			var info := "facing %d mirror %d" % [facing, mirror]
			var arch_id: int = ids[SecurityLanes.ARCH]
			assert_int(recognised.status(arch_id)).override_failure_message(info).is_equal(
				SecurityLanes.Status.COMPLETE
			)
			var view := BuildView.new()
			add_child(view)
			view.refresh(grid)
			var nodes := {}
			for child in view.get_children():
				if child.has_meta("record"):
					nodes[StringName(child.get_meta("record")["def"])] = child
			assert_int(nodes.size()).override_failure_message(info).is_equal(4)
			_check_conveyor(grid, nodes, facing, mirror, info)
			view.free()
			lanes += 1
	assert_int(lanes).is_equal(8)


func _check_conveyor(
	grid: BuildGrid, nodes: Dictionary, facing: int, mirror: int, info: String
) -> void:
	var lane := SecurityLanes.geometry(ANCHOR, facing, mirror)
	var front: Vector2i = lane["front"]
	var forward := Vector3(front.x, 0.0, front.y)
	# Tray mounts: belt height, on one line along the lane, queue side first.
	var points: Array[Vector3] = []
	for id in MOUNTS:
		var mount := (nodes[id] as Node3D).find_child(MOUNTS[id], true, false) as Node3D
		assert_object(mount).override_failure_message("%s %s" % [info, MOUNTS[id]]).is_not_null()
		if mount == null:
			return
		points.append(mount.global_position)
		assert_float(mount.global_position.y).override_failure_message(info).is_equal_approx(
			BELT_TOP, 0.001
		)
	var scan := points[1]
	var part_cell: Vector2i = lane[SecurityLanes.XRAY_BELT]
	var centre := grid.cell_to_world(part_cell)
	var msg := "%s mounts %s xray cell centre %s" % [info, points, centre]
	(
		assert_float(Vector2(scan.x, scan.z).distance_to(Vector2(centre.x, centre.z)))
		. override_failure_message(msg)
		. is_less(0.001)
	)
	for i in [0, 2]:
		var offset: Vector3 = points[i] - scan
		var along := offset.dot(forward)
		var across := (offset - forward * along).length()
		assert_float(across).override_failure_message(msg).is_less(0.001)
		# The tray table is on the queue side (+front), the pickup table beyond.
		if i == 0:
			assert_float(along).override_failure_message(msg).is_greater(0.5)
		else:
			assert_float(along).override_failure_message(msg).is_less(-0.5)
	# Belt ends meet: tray table to X-ray and X-ray to pickup table, no gap.
	var tray := _along(_world_bounds(nodes[SecurityLanes.TRAY_TABLE]), forward)
	var xray := _along(_world_bounds(nodes[SecurityLanes.XRAY_BELT]), forward)
	var pickup := _along(_world_bounds(nodes[SecurityLanes.PICKUP_TABLE]), forward)
	var joins := "%s tray %s xray %s pickup %s" % [info, tray, xray, pickup]
	assert_float(tray.x - xray.y).override_failure_message(joins).is_equal_approx(0.0, 0.002)
	assert_float(xray.x - pickup.y).override_failure_message(joins).is_equal_approx(0.0, 0.002)


## [min, max] of a box projected on a horizontal unit axis.
func _along(box: AABB, axis: Vector3) -> Vector2:
	var lo := INF
	var hi := -INF
	for i in 8:
		var d := box.get_endpoint(i).dot(axis)
		lo = minf(lo, d)
		hi = maxf(hi, d)
	return Vector2(lo, hi)


func _world_bounds(root: Node) -> AABB:
	var box := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var part := mi.global_transform * mi.mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box


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
