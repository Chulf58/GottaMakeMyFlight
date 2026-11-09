class_name TestTaxiPavingJunctions
extends GdUnitTestSuite
## Where a link meets the taxi lane's edge, the lane under it is mitred
## (TaxiPaving.junctions(), board 1d61370e), so the link's asphalt band runs on
## into the lane instead of its light middle butting the lane's dark edge. Two
## links closer than a strip is wide (gates may stand 19 m apart) share the lane
## and their strips' overlap at their midpoint. The shade is read the way the
## GPU reads it: the band position t (0 to 1 across ASPHALT_V_FROM to
## ASPHALT_V_TO) interpolated over the triangle under a point. The band is
## symmetric about its middle, so |t - 0.5| is the shade.

## The starter's lane and links as built on main.tscn: two stubs from the runway
## meet the lane's north edge at its ends, the stand's link meets its south edge.
const LANE := Rect2(-139, -299, 278, 30)
const STUB_WEST := {"rect": Rect2(-139, -338, 30, 39), "across_x": true}
const STUB_EAST := {"rect": Rect2(109, -338, 30, 39), "across_x": true}
const STAND_LINK := {"rect": Rect2(-41, -269, 30, 154), "across_x": true}
## A second gate's link 19 m east of the stand's, the closest two gates may be
## (test_gate_envelopes.gd, test_exits_19_m_apart_make_two_gates).
const GATE_B_LINK := {"rect": Rect2(-22, -269, 30, 154), "across_x": true}
## How far apart two shade samples are, and the most their shades may differ:
## the band changes by at most 1/15 of its range per metre across a 30 m strip.
## The sample chains run STEP_M apart along one axis and ROW_M apart across it.
const STEP_M := 0.1
const ROW_M := 1.1
const MAX_SHADE_STEP := 0.01


func _lane_strip() -> Dictionary:
	return {"rect": LANE, "across_x": false}


func _starter() -> Array[Dictionary]:
	return [_lane_strip(), STUB_WEST, STAND_LINK, STUB_EAST]


func _two_gates() -> Array[Dictionary]:
	return [_lane_strip(), STUB_WEST, STAND_LINK, GATE_B_LINK, STUB_EAST]


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


func test_close_links_are_all_junctions_and_one_on_both_edges_is_one() -> void:
	var strip_list := _two_gates()
	# A second link at the stand's x, from the runway: one junction, both edges.
	strip_list.append({"rect": Rect2(-41, -338, 30, 39), "across_x": true})
	# A strip that overlaps the lane without ending on an edge is no junction.
	strip_list.append({"rect": Rect2(40, -290, 30, 60), "across_x": true})
	var got := TaxiPaving.junctions(LANE, strip_list)
	print("junctions %s" % [got])
	assert_int(got.size()).is_equal(4)
	assert_float(got[1]["x"]).is_equal_approx(-26.0, 0.001)
	assert_bool(got[1]["north"]).is_true()
	assert_bool(got[1]["south"]).is_true()
	# Gate B's link, 19 m east, is kept.
	assert_float(got[2]["x"]).is_equal_approx(-7.0, 0.001)
	assert_bool(got[2]["south"]).is_true()


func test_paving_covers_its_ground_once_and_faces_up() -> void:
	var arrays := TaxiPaving.mesh_of([_lane_strip()] as Array[Dictionary]).surface_get_arrays(0)
	var plain_verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	assert_int(plain_verts.size()).is_equal(4)
	# The two gates' links overlap 11 m wide along their whole length.
	var overlap := 11.0 * 154.0
	var layouts := [[_starter(), 0.0], [_two_gates(), overlap]]
	for layout: Array in layouts:
		var strip_list: Array[Dictionary] = layout[0]
		var ground := -float(layout[1])
		for strip in strip_list:
			ground += (strip["rect"] as Rect2).get_area()
		var area := 0.0
		for tri in _triangles(TaxiPaving.mesh_of(strip_list)):
			var a: Vector3 = tri[0]
			var cross: Vector3 = (tri[1] - a).cross(tri[2] - a)
			# Clockwise seen from above: the right-handed cross product points down.
			assert_float(cross.y).is_less(0.0)
			area += -cross.y / 2.0
		# Drawn area equal to the ground covered: no gap and nothing drawn twice.
		print("strips=%d drawn area=%.2f ground=%.2f" % [strip_list.size(), area, ground])
		assert_float(area).is_equal_approx(ground, 0.01)


func test_starter_band_runs_on_into_the_lane_without_a_step() -> void:
	var tris := _triangles(TaxiPaving.mesh_of(_starter()))
	for link: Dictionary in [STUB_WEST, STAND_LINK, STUB_EAST]:
		_assert_band_on_lane_edge(tris, link["rect"], link["rect"])
	# Beside the junctions, the lane's own band runs across z.
	for x: float in [-60.0, 40.0]:
		for i in range(1, 10):
			var z := LANE.position.y + LANE.size.y * i / 10.0
			assert_float(_t_at(tris, Vector2(x, z))).is_equal_approx(i / 10.0, 0.01)
	for x: float in [-124.0, -26.0, 124.0]:
		_assert_no_step(tris, Rect2(x - 17.0, -305.0, 34.0, 44.0))


func test_two_gates_19_m_apart_have_no_step() -> void:
	var tris := _triangles(TaxiPaving.mesh_of(_two_gates()))
	# Each link keeps its own band along its own stretch of the lane's edge, up
	# to the midpoint between the two (x -16.5).
	_assert_band_on_lane_edge(tris, STAND_LINK["rect"], Rect2(-41, -269, 24.5, 1))
	_assert_band_on_lane_edge(tris, GATE_B_LINK["rect"], Rect2(-16.5, -269, 24.5, 1))
	# The lane, both links and the cut between them: no step anywhere.
	_assert_no_step(tris, Rect2(-45, -305, 56, 50))


## Along the lane's edge under `link`, from x `span.position.x` to `span.end.x`,
## the lane's t just inside the edge is the link's own t there.
func _assert_band_on_lane_edge(tris: Array[Array], link: Rect2, span: Rect2) -> void:
	var edge_z := LANE.position.y if link.end.y <= LANE.position.y + 0.01 else LANE.end.y
	var inward := 0.05 if edge_z == LANE.position.y else -0.05
	for i in range(1, 10):
		var x := span.position.x + span.size.x * i / 10.0
		var got := _t_at(tris, Vector2(x, edge_z + inward))
		assert_float(got).is_equal_approx((x - link.position.x) / link.size.x, 0.01)


## Chains of samples STEP_M apart across `area` (world x and z), north to south
## in columns ROW_M apart and west to east in rows ROW_M apart, so every seam
## line is crossed: wherever paving lies under two neighbours in a chain, their
## shades differ by at most MAX_SHADE_STEP. Fails if fewer than a quarter of
## the pairs are paved, so the check cannot pass on bare ground.
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
				var here := _shade_or_nan(tris, at)
				if k > 0:
					pairs += 1
					if not is_nan(here) and not is_nan(last):
						checked += 1
						worst = maxf(worst, absf(here - last))
				last = here
	print("no-step area=%s paved pairs=%d of %d worst=%.4f" % [area, checked, pairs, worst])
	assert_int(checked * 4).is_greater(pairs)
	assert_float(worst).is_less_equal(MAX_SHADE_STEP)


## The triangles of `mesh`, each [a, b, c, ta, tb, tc] with t the band position
## read back from the vertex's v.
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


## The band position t interpolated at `at` (world x and z) over the triangle of
## `tris` under it, or NAN when none is.
func _t_or_nan(tris: Array[Array], at: Vector2) -> float:
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
	return NAN


func _shade_or_nan(tris: Array[Array], at: Vector2) -> float:
	return absf(_t_or_nan(tris, at) - 0.5)


## As _t_or_nan(), failing the test when no triangle lies under `at`.
func _t_at(tris: Array[Array], at: Vector2) -> float:
	var t := _t_or_nan(tris, at)
	if is_nan(t):
		fail("no triangle under %s" % at)
	return t
