class_name TestCafePieces
extends GdUnitTestSuite
## The cafe pieces in BuildCatalog: the counter's order spot and the table's
## seat descriptors (decision cafe-visit-design-forecast-the-whole-itinerary-
## abandon-by-a, point 4: seat id, approach cell, seated root and facing,
## rotated together). At every facing they agree with the Mount_* empties in
## the .glb pieces, and a passenger can walk to the order spot and to each
## seat's approach cell on open floor.

const GRID := Vector2i(16, 16)
## Far from the pieces, so a path to them is a real walk.
const START := Vector2i(1, 1)
const ANCHOR := Vector2i(7, 7)
## Mount positions are authored to the millimetre.
const EPS := 0.002

var _table_mounts: Dictionary = {}
var _counter_mounts: Dictionary = {}


func before() -> void:
	_table_mounts = _mounts("res://assets/interior/cafe_table.glb")
	_counter_mounts = _mounts("res://assets/interior/cafe_counter.glb")


## Mount name -> its transform relative to the piece root.
func _mounts(path: String) -> Dictionary:
	var root := (load(path) as PackedScene).instantiate() as Node3D
	var out := {}
	for node in root.find_children("Mount_*", "Node3D", true, false):
		var local := (node as Node3D).transform
		var parent := node.get_parent()
		while parent != root:
			local = (parent as Node3D).transform * local
			parent = parent.get_parent()
		out[node.name] = local
	root.free()
	return out


func _floored() -> BuildGrid:
	var grid := BuildGrid.new(GRID)
	var edits: Array[BuildEdit] = []
	for y in GRID.y:
		for x in GRID.x:
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	grid.apply_batch(edits)
	return grid


func _place(grid: BuildGrid, def_id: StringName, facing: int) -> int:
	var result := grid.apply(BuildEdit.place_object(def_id, ANCHOR, facing))
	assert_bool(result.ok).is_true()
	return result.object_id


func _piece_transform(grid: BuildGrid, def_id: StringName, facing: int) -> Transform3D:
	var def := BuildCatalog.get_def(def_id)
	return BuildView.object_transform(grid, def.footprint(ANCHOR, facing), facing)


func test_the_table_has_two_seats_named_after_its_mounts() -> void:
	var def := BuildCatalog.get_def(&"cafe_table")
	assert_int(def.seats.size()).is_equal(2)
	assert_int(def.seats.size()).is_equal(RoomTypes.get_type(&"cafe").seats_per_piece)
	assert_array(_table_mounts.keys()).contains(["Mount_SitRoot_L", "Mount_SitRoot_R"])
	assert_array(BuildCatalog.get_def(&"cafe_counter").seats).is_empty()


func test_seat_roots_and_facings_match_the_table_mounts_at_every_facing() -> void:
	var grid := _floored()
	var def := BuildCatalog.get_def(&"cafe_table")
	for facing in 4:
		var piece := _piece_transform(grid, &"cafe_table", facing)
		var seats := def.seat_descriptors(ANCHOR, facing)
		for i in seats.size():
			var mount_name: String = ["Mount_SitRoot_L", "Mount_SitRoot_R"][i]
			var mount: Transform3D = piece * _table_mounts[mount_name]
			var root := BuildObjectDef.seat_root_world(grid, seats[i])
			var mount_facing := mount.basis.z.normalized()
			var seat_facing: Vector2i = seats[i]["facing"]
			var facing_3d := Vector3(seat_facing.x, 0.0, seat_facing.y)
			var info := "facing %d seat %d root %s mount %s" % [facing, i, root, mount.origin]
			assert_float(root.distance_to(mount.origin)).override_failure_message(info).is_less(EPS)
			assert_float(mount_facing.distance_to(facing_3d)).is_less(EPS)
			assert_int(seats[i]["index"]).is_equal(i)


func test_each_seat_sits_in_its_chair_cell_and_faces_the_table_cell() -> void:
	var def := BuildCatalog.get_def(&"cafe_table")
	for facing in 4:
		var footprint := def.footprint(ANCHOR, facing)
		var middle := footprint[1]
		for seat in def.seat_descriptors(ANCHOR, facing):
			var cell: Vector2i = seat["cell"]
			var approach: Vector2i = seat["approach"]
			assert_bool(footprint.has(cell)).is_true()
			assert_vector(cell + (seat["facing"] as Vector2i)).is_equal(middle)
			assert_bool(footprint.has(approach)).is_false()
			# The approach cell is beside the chair, not across the table.
			assert_int(absi(approach.x - cell.x) + absi(approach.y - cell.y)).is_equal(1)


func test_the_counter_order_spot_matches_its_mount_at_every_facing() -> void:
	var grid := _floored()
	var def := BuildCatalog.get_def(&"cafe_counter")
	for facing in 4:
		var piece := _piece_transform(grid, &"cafe_counter", facing)
		var mount: Transform3D = piece * _counter_mounts["Mount_Order"]
		var spot := def.interaction_cell(ANCHOR, facing)
		var centre := grid.cell_to_world(spot)
		var mount_at := Vector2(mount.origin.x, mount.origin.z)
		assert_float(Vector2(centre.x, centre.z).distance_to(mount_at)).is_less(EPS)
		# Standing on the spot, the passenger faces the counter.
		var ahead := mount.basis.z.normalized()
		var counter_cell := spot + Vector2i(roundi(ahead.x), roundi(ahead.z))
		assert_bool(def.footprint(ANCHOR, facing).has(counter_cell)).is_true()


func test_a_passenger_can_walk_to_the_order_spot_and_every_seat_at_every_facing() -> void:
	for def_id in [&"cafe_counter", &"cafe_table"]:
		for facing in 4:
			var grid := _floored()
			var id := _place(grid, def_id, facing)
			var def := BuildCatalog.get_def(def_id)
			var targets: Array[Vector2i] = []
			if def.has_interaction:
				targets.append(grid.interaction_cell(id))
			for seat in def.seat_descriptors(ANCHOR, facing):
				targets.append(seat["approach"])
			assert_int(targets.size()).is_greater(0)
			for target in targets:
				assert_bool(grid.is_walkable(target)).is_true()
				var path := grid.find_path(START, target)
				var info := "%s facing %d target %s" % [def_id, facing, target]
				assert_int(path.size()).override_failure_message(info).is_greater(1)
				assert_vector(path[path.size() - 1]).is_equal(target)
