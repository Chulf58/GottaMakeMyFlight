class_name TestTaxiPavingSideMitres
extends GdUnitTestSuite
## Two junctions the side stands brought (board 0793554d, Airside all around
## S8a), on Airside's real paving: a north stand whose lane join lies 14 m from
## the west spur, whose link runs south beside the spur, overlapping it (the S4
## residual), and a west spur moved out to x -160, so the runway stub at x -124
## meets the lane mid-span from the north (decision 2eea090f). Each must cover
## its ground once and show no shade step (anti_pattern perpendicular-paving-
## strips-that-each-map-a-dark-edge-light). The shade is read as the GPU reads
## it, as test_taxi_paving_junctions.gd does.

## The S5 probe's west gate: the starter's west exit.
const WEST_SILL := Vector2(-33.0, -91.5)
## The north stand whose join is 14 m inside the west spur at x -124.
const NEAR_JOIN_X := -110.0
const NEAR_WALL_Z := -200.0
const MOVED_LANE_X := -160.0
const STEP_M := 0.1
const ROW_M := 1.1
const MAX_SHADE_STEP := 0.01
const HALF := TaxiPaving.WIDTH_M / 2.0

var _airside: Airside


func before() -> void:
	_airside = TestStandLaneClearance.scene_airside()
	add_child(_airside)


func after() -> void:
	_airside.free()


func after_test() -> void:
	_airside.set_gate_stands({})
	_airside.set_gate_classes({})


func _west(lane_x := -StandPlacement.SIDE_LANE_X) -> Dictionary:
	return StandPlacement.make(0, WEST_SILL.x, WEST_SILL.y, StandPlacement.WEST, lane_x)


func _near() -> Dictionary:
	return StandPlacement.make(1, NEAR_JOIN_X + StandPlacement.DOOR_SIDE_M, NEAR_WALL_Z)


func _lane() -> Rect2:
	for strip in _airside.paving.shown:
		if not strip["across_x"] and not strip.get("row", false):
			return strip["rect"]
	fail("no lane strip")
	return Rect2()


func test_a_link_beside_the_spur_is_a_junction_of_the_lane() -> void:
	assert_bool(_airside.set_gate_stands({"A": _near(), "B": _west()})).is_true()
	var lane := _lane()
	print("lane %s" % lane)
	# The lane stops at the spur's inner edge, east of the link's centre.
	assert_float(lane.position.x).is_equal_approx(-109.0, 0.001)
	var got := TaxiPaving.junctions(lane, _airside.paving.shown)
	print("junctions %s" % [got])
	var near := got.filter(func(j: Dictionary) -> bool: return absf(j["x"] - NEAR_JOIN_X) < 0.01)
	assert_int(near.size()).is_equal(1)
	assert_bool(near[0]["south"]).is_true()


func test_a_link_beside_the_spur_covers_its_ground_once() -> void:
	assert_bool(_airside.set_gate_stands({"A": _near(), "B": _west()})).is_true()
	var shown := _airside.paving.shown
	var tris := _triangles(TaxiPaving.mesh_of(shown))
	_assert_covered_once(shown, tris, Rect2(-145.0, -305.0, 60.0, 115.0))


func test_a_link_beside_the_spur_has_no_step() -> void:
	assert_bool(_airside.set_gate_stands({"A": _near(), "B": _west()})).is_true()
	var tris := _triangles(TaxiPaving.mesh_of(_airside.paving.shown))
	# Spur, link and lane share the ground by the nearest centre line: no step,
	# down to the link's end on its wall line (z -200). There the spur runs on
	# at full width beside the north stand's wall, a step this test does not
	# cover (as test_taxi_paving_junctions.gd's unequal links).
	_assert_no_step(tris, Rect2(-142.0, -302.0, 60.0, 100.0))
	# South of the lane, the link's own band runs from the midpoint with the
	# spur (x -117) east; just inside the lane's south edge it is still the
	# link's band (the lane is mitred under it).
	for x: float in [-116.5, -112.0, -104.0, -97.0]:
		var link_t := (x - (NEAR_JOIN_X - HALF)) / TaxiPaving.WIDTH_M
		assert_float(_t_at(tris, Vector2(x, -268.95))).is_equal_approx(link_t, 0.01)
		assert_float(_t_at(tris, Vector2(x, -240.0))).is_equal_approx(link_t, 0.01)
	# West of the midpoint the spur's band runs on, south of the lane.
	var spur_t := (-118.0 - (-StandPlacement.SIDE_LANE_X - HALF)) / TaxiPaving.WIDTH_M
	assert_float(_t_at(tris, Vector2(-118.0, -240.0))).is_equal_approx(spur_t, 0.01)


func test_a_moved_spur_meets_the_stub_mid_span_with_a_mitre() -> void:
	assert_bool(_airside.set_gate_stands({"B": _west(MOVED_LANE_X)})).is_true()
	var lane := _lane()
	print("moved lane %s" % lane)
	assert_float(lane.position.x).is_equal_approx(MOVED_LANE_X + HALF, 0.001)
	var got := TaxiPaving.junctions(lane, _airside.paving.shown)
	var stub := got.filter(
		func(j: Dictionary) -> bool: return absf(j["x"] + StandPlacement.SIDE_LANE_X) < 0.01
	)
	assert_int(stub.size()).is_equal(1)
	assert_bool(stub[0]["north"]).is_true()
	var tris := _triangles(TaxiPaving.mesh_of(_airside.paving.shown))
	# The stub's band runs on into the lane's north half up to the diagonals.
	for x: float in [-136.0, -130.0, -118.0, -112.0]:
		var stub_t := (x - (-StandPlacement.SIDE_LANE_X - HALF)) / TaxiPaving.WIDTH_M
		assert_float(_t_at(tris, Vector2(x, -298.95))).is_equal_approx(stub_t, 0.01)
	var area := Rect2(MOVED_LANE_X - HALF - 2.0, -320.0, 80.0, 60.0)
	_assert_covered_once(_airside.paving.shown, tris, area)
	_assert_no_step(tris, area)


## Every sample on a 0.5 m grid over `area` that `strip_list` covers has exactly
## one triangle of `tris` under it, and every other sample none. Fails when
## fewer than 2000 samples are covered, so it cannot pass on bare ground.
func _assert_covered_once(strip_list: Array[Dictionary], tris: Array[Array], area: Rect2) -> void:
	var covered := 0
	var bare := 0
	var twice := 0
	var stray := 0
	var x := area.position.x + 0.23
	while x < area.end.x:
		var z := area.position.y + 0.27
		while z < area.end.y:
			# A sample on a shared edge lies on both triangles: bare counts
			# edges as on, twice counts insides only.
			var on := _count_under(tris, Vector2(x, z), -0.0001)
			var inside := _count_under(tris, Vector2(x, z), 0.001)
			if TaxiPaving.covers(strip_list, Vector3(x, 0.0, z)):
				covered += 1
				bare += int(on == 0)
				twice += int(inside > 1)
			else:
				stray += int(inside > 0)
			z += 0.5
		x += 0.5
	print("covered=%d bare=%d twice=%d stray=%d" % [covered, bare, twice, stray])
	assert_int(covered).is_greater(2000)
	assert_int(bare).is_equal(0)
	assert_int(twice).is_equal(0)
	assert_int(stray).is_equal(0)


## As test_taxi_paving_junctions.gd: chains of samples STEP_M apart across
## `area`, along z and along x, ROW_M apart; neighbours on paving differ in
## shade by at most MAX_SHADE_STEP. Fails if under a quarter of pairs are paved.
func _assert_no_step(all_tris: Array[Array], area: Rect2) -> void:
	var tris: Array[Array] = []
	for tri in all_tris:
		var box := Rect2(Vector2(tri[0].x, tri[0].z), Vector2.ZERO)
		box = box.expand(Vector2(tri[1].x, tri[1].z)).expand(Vector2(tri[2].x, tri[2].z))
		if box.grow(0.01).intersects(area):
			tris.append(tri)
	var checked := 0
	var pairs := 0
	var worst := 0.0
	var worst_at := Vector2.ZERO
	for along_z in [true, false]:
		var rows := area.size.x if along_z else area.size.y
		var length := area.size.y if along_z else area.size.x
		for r in int(rows / ROW_M):
			var last := NAN
			for k in int(length / STEP_M):
				var at := (
					Vector2(area.position.x + r * ROW_M, area.position.y + k * STEP_M)
					if along_z
					else Vector2(area.position.x + k * STEP_M, area.position.y + r * ROW_M)
				)
				var here := absf(_t_or_nan(tris, at) - 0.5)
				if k > 0:
					pairs += 1
					if not is_nan(here) and not is_nan(last):
						checked += 1
						if absf(here - last) > worst:
							worst = absf(here - last)
							worst_at = at
				last = here
	var counts := "paved pairs=%d of %d" % [checked, pairs]
	print("no-step area=%s %s worst=%.4f at %s" % [area, counts, worst, worst_at])
	assert_int(checked * 4).is_greater(pairs)
	assert_float(worst).is_less_equal(MAX_SHADE_STEP)


## The triangles of `mesh`'s asphalt, each [a, b, c, ta, tb, tc].
func _triangles(mesh: ArrayMesh) -> Array[Array]:
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var span := TaxiPaving.ASPHALT_V_TO - TaxiPaving.ASPHALT_V_FROM
	var out: Array[Array] = []
	for t in range(0, index.size(), 3):
		var tri: Array = []
		for k in 3:
			tri.append(verts[index[t + k]])
		for k in 3:
			tri.append((uvs[index[t + k]].y - TaxiPaving.ASPHALT_V_FROM) / span)
		out.append(tri)
	return out


## How many triangles of `tris` lie under `at`: those whose every barycentric
## weight there exceeds `margin`.
func _count_under(tris: Array[Array], at: Vector2, margin: float) -> int:
	var count := 0
	for tri in tris:
		var w := _weights(tri, at)
		if w.x > margin and w.y > margin and w.z > margin:
			count += 1
	return count


func _weights(tri: Array, at: Vector2) -> Vector3:
	var a := Vector2(tri[0].x, tri[0].z)
	var b := Vector2(tri[1].x, tri[1].z)
	var c := Vector2(tri[2].x, tri[2].z)
	var den := (b - a).cross(c - a)
	var wb := (at - a).cross(c - a) / den
	var wc := (b - a).cross(at - a) / den
	return Vector3(1.0 - wb - wc, wb, wc)


func _t_or_nan(tris: Array[Array], at: Vector2) -> float:
	for tri in tris:
		var w := _weights(tri, at)
		if w.x >= -0.0001 and w.y >= -0.0001 and w.z >= -0.0001:
			return w.x * tri[3] + w.y * tri[4] + w.z * tri[5]
	return NAN


func _t_at(tris: Array[Array], at: Vector2) -> float:
	var t := _t_or_nan(tris, at)
	if is_nan(t):
		fail("no triangle under %s" % at)
	return t
