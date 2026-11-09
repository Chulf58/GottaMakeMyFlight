class_name TestTaxiPavingJunctions
extends GdUnitTestSuite
## Where a link meets the taxi lane's edge, the lane's square under it is mitred
## (TaxiPaving.junctions(), board 1d61370e), so the link's asphalt band runs on
## into the lane instead of its light middle butting the lane's dark edge. The
## shade is read the way the GPU reads it: the band position t (0 to 1 across
## ASPHALT_V_FROM to ASPHALT_V_TO) interpolated over the triangle under a point.

## The starter's lane and links as built on main.tscn: two stubs from the runway
## meet the lane's north edge at its ends, the stand's link meets its south edge.
const LANE := Rect2(-139, -299, 278, 30)
const STUB_WEST := {"rect": Rect2(-139, -338, 30, 39), "across_x": true}
const STUB_EAST := {"rect": Rect2(109, -338, 30, 39), "across_x": true}
const STAND_LINK := {"rect": Rect2(-41, -269, 30, 154), "across_x": true}


func _lane_strip() -> Dictionary:
	return {"rect": LANE, "across_x": false}


func _starter() -> Array[Dictionary]:
	return [_lane_strip(), STUB_WEST, STAND_LINK, STUB_EAST]


func test_junctions_are_the_links_that_meet_the_lane_edges() -> void:
	var got := TaxiPaving.junctions(LANE, _starter())
	print("junctions %s" % [got])
	assert_int(got.size()).is_equal(3)
	assert_float(got[0]["x"]).is_equal_approx(-124.0, 0.001)
	assert_bool(got[0]["north"]).is_true()
	assert_bool(got[0]["south"]).is_false()
	assert_float(got[1]["x"]).is_equal_approx(-26.0, 0.001)
	assert_bool(got[1]["north"]).is_false()
	assert_bool(got[1]["south"]).is_true()
	assert_float(got[2]["x"]).is_equal_approx(124.0, 0.001)
	assert_bool(got[2]["north"]).is_true()


func test_a_link_on_both_edges_is_one_junction_and_a_crowded_one_is_left_out() -> void:
	var strip_list := _starter()
	# A second link at the stand's x, from the runway: one junction, both edges.
	strip_list.append({"rect": Rect2(-41, -338, 30, 39), "across_x": true})
	# A link 20 m east of the stand's: its square would overlap, so it is left out.
	strip_list.append({"rect": Rect2(-21, -269, 30, 50), "across_x": true})
	# A strip that overlaps the lane without ending on an edge is no junction.
	strip_list.append({"rect": Rect2(40, -290, 30, 60), "across_x": true})
	var got := TaxiPaving.junctions(LANE, strip_list)
	print("junctions %s" % [got])
	assert_int(got.size()).is_equal(3)
	assert_float(got[1]["x"]).is_equal_approx(-26.0, 0.001)
	assert_bool(got[1]["north"]).is_true()
	assert_bool(got[1]["south"]).is_true()


func test_mitred_lane_covers_the_lane_once_and_faces_up() -> void:
	var arrays := TaxiPaving.mesh_of([_lane_strip()] as Array[Dictionary]).surface_get_arrays(0)
	var plain_verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	assert_int(plain_verts.size()).is_equal(4)
	var lane_only := _lane_triangles(TaxiPaving.mesh_of(_starter()))
	var area := 0.0
	for tri in lane_only:
		var a: Vector3 = tri[0]
		var cross: Vector3 = (tri[1] - a).cross(tri[2] - a)
		# Clockwise seen from above: the right-handed cross product points down.
		assert_float(cross.y).is_less(0.0)
		area += -cross.y / 2.0
	print("lane triangles=%d area=%.2f lane area=%.2f" % [lane_only.size(), area, LANE.get_area()])
	# Four plain pieces between and beside the three squares (two of them are
	# empty: the stubs' squares sit at the lane's ends) and four per square.
	assert_int(lane_only.size()).is_equal(2 * 2 + 3 * 4)
	assert_float(area).is_equal_approx(LANE.get_area(), 0.01)


func test_link_band_runs_on_into_the_lane_without_a_step() -> void:
	var mesh := TaxiPaving.mesh_of(_starter())
	var tris := _lane_triangles(mesh)
	# Along the lane's edge under each link, the lane's t is the link's t.
	for link: Dictionary in [STUB_WEST, STAND_LINK, STUB_EAST]:
		var rect: Rect2 = link["rect"]
		var edge_z := LANE.position.y if rect.end.y <= LANE.position.y + 0.01 else LANE.end.y
		var inward := 0.05 if edge_z == LANE.position.y else -0.05
		for i in range(1, 10):
			var x := rect.position.x + rect.size.x * i / 10.0
			var got := _t_at(tris, Vector2(x, edge_z + inward))
			var want := (x - rect.position.x) / rect.size.x
			assert_float(got).is_equal_approx(want, 0.01)
	# Across each diagonal of a square the shade matches: the band is symmetric
	# about its middle, so equal distance |t - 0.5| is the same shade.
	for x: float in [-124.0, -26.0, 124.0]:
		for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			for s: float in [0.2, 0.5, 0.8]:
				var on := Vector2(x, LANE.get_center().y) + corner * 15.0 * s
				var along := Vector2(corner.y, -corner.x) * 0.1
				var one := absf(_t_at(tris, on + along) - 0.5)
				var other := absf(_t_at(tris, on - along) - 0.5)
				assert_float(one).is_equal_approx(other, 0.01)
	# Beside each square, the lane's own band runs across z.
	for x: float in [-60.0, 40.0]:
		for i in range(1, 10):
			var z := LANE.position.y + LANE.size.y * i / 10.0
			assert_float(_t_at(tris, Vector2(x, z))).is_equal_approx(i / 10.0, 0.01)


## The triangles of `mesh` inside the lane, each [a, b, c, ta, tb, tc] with t the
## band position read back from the vertex's v.
func _lane_triangles(mesh: ArrayMesh) -> Array[Array]:
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var span := TaxiPaving.ASPHALT_V_TO - TaxiPaving.ASPHALT_V_FROM
	var out: Array[Array] = []
	for t in range(0, index.size(), 3):
		var tri: Array = []
		var inside := true
		for k in 3:
			var v := verts[index[t + k]]
			tri.append(v)
			inside = inside and LANE.grow(0.01).has_point(Vector2(v.x, v.z))
		if not inside:
			continue
		for k in 3:
			tri.append((uvs[index[t + k]].y - TaxiPaving.ASPHALT_V_FROM) / span)
		out.append(tri)
	return out


## The band position t interpolated at `at` (world x and z) over the triangle of
## `tris` under it; fails the test when no triangle lies under it.
func _t_at(tris: Array[Array], at: Vector2) -> float:
	for tri in tris:
		var a := Vector2(tri[0].x, tri[0].z)
		var b := Vector2(tri[1].x, tri[1].z)
		var c := Vector2(tri[2].x, tri[2].z)
		var den := (b - a).cross(c - a)
		var wb := (at - a).cross(c - a) / den
		var wc := (b - a).cross(at - a) / den
		var wa := 1.0 - wb - wc
		if wa >= -0.0001 and wb >= -0.0001 and wc >= -0.0001:
			return wa * tri[3] + wb * tri[4] + wc * tri[5]
	fail("no lane triangle under %s" % at)
	return -1.0
