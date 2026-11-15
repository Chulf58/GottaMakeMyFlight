extends GdUnitTestSuite
## On the terminal site the taxi paving lies just under the plane's ground
## height (PlaneView.ground_height_at()), so a plane parked or taxiing over
## land the player does not own rolls on asphalt, not on the grass, and neither
## floats nor sinks (decision site-paving-covers-only-the-owned-land-plots-and-
## grows-as-ea; pave-the-taxi-lane-and-the-link-from-each-stand-to-it-so-pla).
## Off the site the paving is as it was. Where it stands over the grass it has
## skirts down into the grass, so it never reads as a floating slab.

const SITE := preload("res://build/terminal_site.tres")
const LANE_Z := -290.0
## How far over the asphalt a plane may ride: the strips lie SITE_DROP_M under
## its ground height, the pads PAD_DROP_M more.
const MAX_FLOAT_M := TaxiPaving.SITE_DROP_M + TaxiPaving.PAD_DROP_M + 0.001


## The asphalt's top under `at` (world x and z): the highest up-facing asphalt
## triangle over it, or -INF where there is none. Centre lines are left out.
static func surface_at(mesh: ArrayMesh, at: Vector3) -> float:
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var best := -INF
	for t in range(0, index.size(), 3):
		if not is_equal_approx(uvs[index[t]].x, TaxiPaving.ASPHALT_U):
			continue
		var a := verts[index[t]]
		var b := verts[index[t + 1]]
		var c := verts[index[t + 2]]
		if (c - a).cross(b - a).normalized().y < 0.5:
			continue
		var w := Geometry2D.point_is_inside_triangle(
			Vector2(at.x, at.z), Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z)
		)
		if not w:
			continue
		var plane := Plane(a, c, b)
		var y: Variant = plane.intersects_ray(Vector3(at.x, 10.0, at.z), Vector3.DOWN)
		if y != null:
			best = maxf(best, (y as Vector3).y)
	return best


## The triangles of `mesh` that face sideways (skirts).
static func _side_triangles(mesh: ArrayMesh) -> Array[PackedVector3Array]:
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var out: Array[PackedVector3Array] = []
	for t in range(0, index.size(), 3):
		var a := verts[index[t]]
		var b := verts[index[t + 1]]
		var c := verts[index[t + 2]]
		if absf((c - a).cross(b - a).normalized().y) < 0.1:
			out.append(PackedVector3Array([a, b, c]))
	return out


func test_inside_the_site_the_asphalt_lies_just_under_the_plane() -> void:
	# A link wholly on the site, over land a new game does not own (x 1..43).
	var strip_list: Array[Dictionary] = [{"rect": Rect2(5, -200, 30, 60), "across_x": true}]
	var mesh := TaxiPaving.on_site(TaxiPaving.mesh_of(strip_list))
	# Off the quad's diagonal, where neither triangle holds the point strictly.
	var at := Vector3(21, 0, -168.2)
	var ground := PlaneView.ground_height_at(at)
	var top := surface_at(mesh, at)
	print("ground %.3f asphalt %.3f" % [ground, top])
	assert_float(ground).is_equal_approx(SITE.ground_height, 0.0001)
	assert_float(top).is_equal_approx(ground - TaxiPaving.SITE_DROP_M, 0.0001)
	# Under the site's own paving (y 0.2), which covers it on owned land.
	assert_float(top).is_less(SITE.ground_height)


func test_off_the_site_the_mesh_is_unchanged() -> void:
	var strip_list: Array[Dictionary] = [
		{"rect": Rect2(-10, -20, 30, 40), "across_x": true},
		{"rect": Rect2(0, -300, 50, 30), "across_x": false},
	]
	var flat := TaxiPaving.mesh_of(
		strip_list, [Rect2(4.75, -20, 0.5, 40)], [Rect2(-20, -10, 50, 30)]
	)
	var lifted := TaxiPaving.on_site(flat)
	var a := flat.surface_get_arrays(0)
	var b := lifted.surface_get_arrays(0)
	print(
		"flat verts %d lifted verts %d" % [a[Mesh.ARRAY_VERTEX].size(), b[Mesh.ARRAY_VERTEX].size()]
	)
	assert_array(b[Mesh.ARRAY_VERTEX]).is_equal(a[Mesh.ARRAY_VERTEX])
	assert_array(b[Mesh.ARRAY_INDEX]).is_equal(a[Mesh.ARRAY_INDEX])
	assert_array(b[Mesh.ARRAY_TEX_UV]).is_equal(a[Mesh.ARRAY_TEX_UV])
	assert_int(_side_triangles(lifted).size()).is_equal(0)
	assert_int(lifted.get_surface_count()).is_equal(1)


func test_across_the_site_edge_the_asphalt_follows_the_plane_down_the_ramp() -> void:
	# A link from the lane, north of the site, on to a stand on the site.
	var strip_list: Array[Dictionary] = [{"rect": Rect2(-41, LANE_Z, 30, 175), "across_x": true}]
	var mesh := TaxiPaving.on_site(TaxiPaving.mesh_of(strip_list))
	var worst_float := 0.0
	var worst_sink := 0.0
	var samples := 0
	var z := LANE_Z + 1.13
	while z < -116.0:
		for x in [-40.5, -26.0, -11.5]:
			var at := Vector3(x, 0, z)
			var ground := PlaneView.ground_height_at(at)
			var top := surface_at(mesh, at)
			assert_float(top).is_greater(-INF)
			worst_float = maxf(worst_float, ground - top)
			worst_sink = maxf(worst_sink, top - ground)
			samples += 1
		z += 0.5
	print("samples %d worst float %.4f worst sink %.4f" % [samples, worst_float, worst_sink])
	assert_int(samples).is_greater(300)
	assert_float(worst_sink).is_less_equal(0.0001)
	assert_float(worst_float).is_less_equal(TaxiPaving.SITE_DROP_M + 0.0001)
	# Control: the ramp was crossed, the ground under it ran from 0 to 0.2.
	assert_float(PlaneView.ground_height_at(Vector3(-26, 0, LANE_Z + 1))).is_equal(0.0)
	assert_float(PlaneView.ground_height_at(Vector3(-26, 0, -120))).is_equal(SITE.ground_height)


func test_a_parked_plane_on_a_pad_over_the_grass_rides_on_it() -> void:
	var strip_list: Array[Dictionary] = [{"rect": Rect2(-41, LANE_Z, 30, 160), "across_x": true}]
	var pad := Rect2(-60, -170, 68, 60)
	var mesh := TaxiPaving.on_site(TaxiPaving.mesh_of(strip_list, [], [pad]))
	var checked := 0
	for at: Vector3 in [Vector3(-40, 0, -165), Vector3(0, 0, -150), Vector3(-26, 0, -115)]:
		var ground := PlaneView.ground_height_at(at)
		var top := surface_at(mesh, at)
		print("pad at %s ground %.3f asphalt %.3f" % [at, ground, top])
		assert_float(ground - top).is_between(0.0, MAX_FLOAT_M)
		checked += 1
	assert_int(checked).is_equal(3)


func test_asphalt_over_the_grass_has_skirts_down_into_it() -> void:
	var strip := Rect2(5, -200, 30, 60)
	var lifted := TaxiPaving.on_site(
		TaxiPaving.mesh_of([{"rect": strip, "across_x": true}] as Array[Dictionary])
	)
	var sides := _side_triangles(lifted)
	# Each of the strip's four edges has a skirt reaching the grass.
	var edges := {"west": false, "east": false, "north": false, "south": false}
	for tri in sides:
		var low := minf(tri[0].y, minf(tri[1].y, tri[2].y))
		var high := maxf(tri[0].y, maxf(tri[1].y, tri[2].y))
		if low > TaxiPaving.GRASS_Y or high < SITE.ground_height - TaxiPaving.SITE_DROP_M - 0.001:
			continue
		var mid := (tri[0] + tri[1] + tri[2]) / 3.0
		if absf(mid.x - strip.position.x) < 0.001:
			edges["west"] = true
		elif absf(mid.x - strip.end.x) < 0.001:
			edges["east"] = true
		elif absf(mid.z - strip.position.y) < 0.001:
			edges["north"] = true
		elif absf(mid.z - strip.end.y) < 0.001:
			edges["south"] = true
	print("side triangles %d edges %s" % [sides.size(), edges])
	assert_dict(edges).is_equal({"west": true, "east": true, "north": true, "south": true})


func test_every_top_triangle_still_faces_up_after_the_cut() -> void:
	var strip_list: Array[Dictionary] = [{"rect": Rect2(-41, LANE_Z, 30, 175), "across_x": true}]
	var arrays := (
		TaxiPaving
		. on_site(TaxiPaving.mesh_of(strip_list, [Rect2(-26.25, LANE_Z, 0.5, 175)]))
		. surface_get_arrays(0)
	)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var up := 0
	var down := 0
	for t in range(0, index.size(), 3):
		var n := (verts[index[t + 2]] - verts[index[t]]).cross(
			verts[index[t + 1]] - verts[index[t]]
		)
		if absf(n.normalized().y) < 0.1:
			continue
		if n.y > 0.0:
			up += 1
		else:
			down += 1
	print("up %d down %d" % [up, down])
	assert_int(up).is_greater(4)
	assert_int(down).is_equal(0)
