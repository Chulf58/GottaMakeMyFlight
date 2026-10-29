class_name TestLandsideGeometry
extends GdUnitTestSuite
## The authored landside geometry is compared with the converted assets
## (decision landside-assets-the-curb-is-an-authored-paint-only-drop-off) and
## the baked road. The .glb files are loaded and measured here: the curb bay's
## Mount_Berth markers and slab, the surface lot's slab, barrier arms and the
## stall paint on its ground, the multi-storey's bounds. A lane sits on the
## road baked into the shell (x -43 to 43, tp_airport_shell.glb's Road node,
## the shell standing at x 0).

const STARTER := preload("res://landside/starter_landside.tres")
const BAY_SCENE := preload("res://assets/landside/tp_curb_bay_01a.glb")
const LOT_SCENE := preload("res://assets/landside/tp_parking_01a.glb")
const MULTI_SCENE := preload("res://assets/landside/tc_parking_2a.glb")
const ROAD_EAST := 43.0
const ROAD_WEST := -43.0
## The near kerb line in the main scene (measured on tp_airport_shell.glb, the
## shell at z -80): the curb bay asset's origin stands on it, +z into the road.
const KERB_Z := -58.7
## The lot asset is turned -90 degrees about y so its entrance faces the road
## (-z): its local (x, z) is the world offset (-z, x) from its origin.
const LOT_YAW := -PI / 2.0
const TOLERANCE := 0.01


func _scene(packed: PackedScene) -> Node3D:
	var root: Node3D = auto_free(packed.instantiate())
	add_child(root)
	return root


## A mesh node's bounds in its asset's own frame.
func _bounds(root: Node3D, mesh_name: String) -> AABB:
	var node := root.find_child(mesh_name, true, false) as MeshInstance3D
	assert_object(node).override_failure_message(mesh_name).is_not_null()
	return node.global_transform * node.get_aabb()


## A mesh node's vertices in its asset's own frame.
func _vertices(root: Node3D, mesh_name: String) -> Array[Vector3]:
	var node := root.find_child(mesh_name, true, false) as MeshInstance3D
	var out: Array[Vector3] = []
	for vertex in node.mesh.get_faces():
		out.append(node.global_transform * vertex)
	return out


func test_every_lane_stays_inside_the_baked_road_or_the_lots_beside_it() -> void:
	for lane in [STARTER.road_in, STARTER.road_out]:
		for point in lane:
			assert_float(point.x).is_between(ROAD_WEST, ROAD_EAST)
	assert_float(STARTER.road_in[0].x).is_equal(ROAD_EAST)
	assert_float(STARTER.road_out[STARTER.road_out.size() - 1].x).is_equal(ROAD_WEST)
	for lot in STARTER.lots:
		# A lot's exit lane ends on the road's east end, where its cars vanish.
		assert_float(lot.exit[lot.exit.size() - 1].x).is_equal(ROAD_EAST)
		for point in lot.access:
			assert_float(point.x).is_between(ROAD_WEST, ROAD_EAST)
		for point in lot.exit:
			assert_float(point.x).is_between(ROAD_WEST, ROAD_EAST)


func test_every_curb_is_a_whole_number_of_bays_with_berths_on_the_asset_markers() -> void:
	var asset := _scene(BAY_SCENE)
	var first: Vector3 = (asset.find_child("Mount_Berth_1", true, false) as Node3D).global_position
	var second: Vector3 = (asset.find_child("Mount_Berth_2", true, false) as Node3D).global_position
	var slab := _bounds(asset, "TP_Curb_Bay_01A")
	var pitch := absf(second.x - first.x)
	print("bay markers %s %s slab %s" % [first, second, slab])
	assert_float(pitch).is_equal_approx(6.5, TOLERANCE)
	# The starter curb is two bays: berths pair up at the markers' spacing.
	assert_int(STARTER.curb.berths.size()).is_equal(4)
	var starter_xs: Array[float] = []
	for berth in STARTER.curb.berths:
		starter_xs.append(berth.x)
	starter_xs.sort()
	var bay_centres: Array[float] = []
	for i in range(0, starter_xs.size(), 2):
		assert_float(starter_xs[i + 1] - starter_xs[i]).is_equal_approx(pitch, TOLERANCE)
		bay_centres.append((starter_xs[i] + starter_xs[i + 1]) / 2.0)
	for spot in STARTER.curb_spots:
		assert_int(spot.berths.size()).is_equal(2)
		assert_vector(spot.footprint).is_equal(Vector2(slab.size.x, slab.size.z))
		# The slab is centred on the asset's origin in x and runs 0 to 3 in z.
		assert_float(slab.position.x + slab.size.x / 2.0).is_equal_approx(0.0, TOLERANCE)
		assert_float(spot.centre.z).is_equal_approx(
			KERB_Z + slab.position.z + slab.size.z / 2.0, TOLERANCE
		)
		bay_centres.append(spot.centre.x)
		for marker in [first, second]:
			var at := Vector3(spot.centre.x + marker.x, 0.0, KERB_Z + marker.z)
			var found := false
			for berth in spot.berths:
				found = (
					found or (absf(berth.x - at.x) < TOLERANCE and absf(berth.z - at.z) < TOLERANCE)
				)
			assert_bool(found).override_failure_message("marker %s" % marker).is_true()
	for berth in STARTER.curb.berths:
		assert_float(berth.z).is_equal_approx(KERB_Z + first.z, TOLERANCE)
	# Bays do not overlap, and all stand on the baked road.
	bay_centres.sort()
	for i in range(1, bay_centres.size()):
		assert_float(bay_centres[i] - bay_centres[i - 1]).is_greater_equal(slab.size.x - TOLERANCE)
	assert_float(bay_centres[0] - slab.size.x / 2.0).is_greater_equal(ROAD_WEST)
	assert_float(bay_centres[bay_centres.size() - 1] + slab.size.x / 2.0).is_less_equal(ROAD_EAST)
	# Every get-out point is on the kerb side of its berth.
	for i in STARTER.curb.berths.size():
		assert_float(STARTER.curb.get_out[i].z).is_less(STARTER.curb.berths[i].z)
		assert_float(STARTER.curb.get_out[i].x).is_equal(STARTER.curb.berths[i].x)


func test_the_surface_lot_matches_the_assets_slab_barriers_and_stalls() -> void:
	var asset := _scene(LOT_SCENE)
	var lot := STARTER.lots[0]
	assert_int(lot.kind).is_equal(LandsideLotSpot.Kind.SURFACE)
	var slab := _bounds(asset, "TP_Parking_01A")
	var entry_arm := _bounds(asset, "TP_Parking_01A_Entry_Barrier")
	var exit_arm := _bounds(asset, "TP_Parking_01A_Exit_Barrier")
	# The lot's own frame stands in the world turned LOT_YAW, its origin on the
	# lot's axis (the spot's centre x) and 7 m (the barrier line) past the gate.
	var gate := lot.access[lot.access.size() - 1]
	var at := Transform3D(Basis(Vector3.UP, LOT_YAW), Vector3(lot.centre.x, 0.0, gate.z + 7.0))
	var world_slab := at * slab
	print("lot slab %s arms %s %s -> world slab %s" % [slab, entry_arm, exit_arm, world_slab])
	# The slab is the footprint, and the spot's centre is its middle.
	assert_vector(lot.footprint).is_equal_approx(Vector2(24.0, 32.3), Vector2(0.01, 0.01))
	assert_float(world_slab.size.x).is_equal_approx(lot.footprint.x, 0.01)
	assert_float(world_slab.size.z).is_equal_approx(lot.footprint.y, 0.01)
	assert_float(world_slab.get_center().x).is_equal_approx(lot.centre.x, 0.01)
	assert_float(world_slab.get_center().z).is_equal_approx(lot.centre.z, 0.01)
	# Entry and exit lanes run through the middle of the barrier arms, the
	# barrier line at the gate; the entry is on the right of a car heading in.
	var entry_at := at * entry_arm.get_center()
	var exit_at := at * exit_arm.get_center()
	assert_float(entry_at.x).is_equal_approx(gate.x, 0.2)
	assert_float(entry_at.z).is_equal_approx(gate.z, 0.2)
	assert_float(exit_at.x).is_equal_approx(lot.exit[0].x, 0.2)
	assert_float(exit_at.z).is_equal_approx(lot.exit[0].z, 0.2)
	assert_float(entry_at.x).is_less(exit_at.x)
	_assert_stalls_follow_the_paint(asset, lot, at)


## The stall paint is seven lines 4 m apart (each an edge pair 0.16 m either
## side of its middle) over two rows of ground; the slots are the stalls
## between them, in the middle of each row.
func _assert_stalls_follow_the_paint(asset: Node3D, lot: LandsideLotSpot, at: Transform3D) -> void:
	var paint: Array[Vector3] = []
	for vertex in _vertices(asset, "TP_Parking_01A"):
		if vertex.y < 0.3 and absf(vertex.z) > 4.3 and absf(vertex.z) < 9.7:
			paint.append(vertex)
	var lines: Array[float] = []
	for i in 7:
		var middle := -2.0 + 4.0 * i
		var low := 0
		var high := 0
		for vertex in paint:
			low += int(absf(vertex.x - (middle - 0.16)) < 0.02)
			high += int(absf(vertex.x - (middle + 0.16)) < 0.02)
		(
			assert_bool(low >= 2 and high >= 2)
			. override_failure_message("line at %s" % middle)
			. is_true()
		)
		lines.append(middle)
	# No line past the seventh: the slab ends at x 25.
	for vertex in paint:
		assert_bool(vertex.x > 22.5 and vertex.x < 24.9).is_false()
	var rows := {}
	for vertex in paint:
		if absf(vertex.x - (lines[0] - 0.16)) < 0.02:
			var side := signf(vertex.z)
			rows[side] = rows.get(side, []) + [absf(vertex.z)]
	assert_int(rows.size()).is_equal(2)
	var row_middles: Array[float] = []
	for side in rows:
		row_middles.append((rows[side].min() + rows[side].max()) / 2.0)
	# Twelve stalls: six between the seven lines, in each of the two rows.
	assert_int(lot.slots.size()).is_equal((lines.size() - 1) * 2)
	var inverse := at.affine_inverse()
	for slot in lot.slots:
		var local := inverse * Vector3(slot.x, 0.0, slot.z)
		var column := (local.x - lines[0]) / 4.0 - 0.5
		assert_float(column).is_equal_approx(roundf(column), 0.01)
		assert_bool(column > -0.1 and column < 5.1).is_true()
		var near_row := false
		for middle in row_middles:
			near_row = near_row or absf(absf(local.z) - middle) < 0.3
		assert_bool(near_row).override_failure_message("slot %s at %s" % [slot, local]).is_true()


func test_the_multi_storey_stands_on_its_assets_footprint() -> void:
	var asset := _scene(MULTI_SCENE)
	var bounds := _bounds(asset, "Parking_2A")
	var spot := STARTER.lots[1]
	print("multi-storey bounds %s" % [bounds])
	assert_int(spot.kind).is_equal(LandsideLotSpot.Kind.MULTI_STOREY)
	# Vendor heading, no rotation, the asset's origin in the middle of its
	# footprint: the spot's centre is where the origin stands.
	assert_float(bounds.get_center().x).is_equal_approx(0.0, 0.01)
	assert_float(bounds.get_center().z).is_equal_approx(0.0, 0.01)
	assert_vector(spot.footprint).is_equal_approx(
		Vector2(bounds.size.x, bounds.size.z), Vector2(0.01, 0.01)
	)
	var rect := Rect2(
		spot.centre.x - spot.footprint.x / 2.0,
		spot.centre.z - spot.footprint.y / 2.0,
		spot.footprint.x,
		spot.footprint.y
	)
	# Every slot is on a deck inside the building.
	for slot in spot.slots:
		assert_bool(rect.has_point(Vector2(slot.x, slot.z))).is_true()
		assert_float(slot.y).is_between(0.0, bounds.size.y)
	assert_bool(rect.intersects(_lot_rect(STARTER.lots[0]))).is_false()


func _lot_rect(lot: LandsideLotSpot) -> Rect2:
	return Rect2(
		lot.centre.x - lot.footprint.x / 2.0,
		lot.centre.z - lot.footprint.y / 2.0,
		lot.footprint.x,
		lot.footprint.y
	)
