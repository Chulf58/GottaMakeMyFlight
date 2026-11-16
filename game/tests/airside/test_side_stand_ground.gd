class_name TestSideStandGround
extends GdUnitTestSuite
## West and east stands on the site sit at one ground height (board 0793554d,
## Airside all around S8a). The S5 plates (2026-11-16) showed west planes at
## y 0.0 and an east plane at y 0.2: PlaneView.ground_height_at() then paved
## only the first 86 m site (SiteDefinition.centre_rect()), so the west stand
## there was off it. S7c (decision side-land-open-as-built-s7c-whole-grid-
## paved-stands-reach-their-lane) paves the whole grid. These cases pin that
## the plane, its pad, the strip under it and the jet bridge all share one
## height at both sides, and that a side gate's envelope outline is its north
## twin's turned (GateLinksView.envelope_outline()).

## The S5 probe's gates: the starter's west and east exits.
const WEST_SILL := Vector2(-33.0, -91.5)
const EAST_SILL := Vector2(-21.0, -95.5)

var _airside: Airside


func before() -> void:
	_airside = TestStandLaneClearance.scene_airside()
	add_child(_airside)


func after() -> void:
	_airside.free()


func after_test() -> void:
	_airside.set_gate_stands({})
	_airside.set_gate_classes({})


func _west() -> Dictionary:
	return StandPlacement.make(0, WEST_SILL.x, WEST_SILL.y, StandPlacement.WEST)


func _east() -> Dictionary:
	return StandPlacement.make(1, EAST_SILL.x, EAST_SILL.y, StandPlacement.EAST)


func test_west_and_east_planes_and_bridges_share_the_site_height() -> void:
	var site: SiteDefinition = PlaneView.SITE
	for stand in [_west(), _east()]:
		var at := StandPlacement.stand_point(stand)
		var ground := PlaneView.ground_height_at(at)
		print(
			(
				"%s stand point %s ground %.3f bridge %.3f"
				% [StandPlacement.side_of(stand), at, ground, JetBridgePose.ground_y(stand)]
			)
		)
		assert_float(ground).is_equal_approx(site.ground_height, 0.0001)
		assert_float(JetBridgePose.ground_y(stand)).is_equal_approx(ground, 0.0001)
		# Every corner of the parked plane of every model stands at that height.
		for model: String in PlaneModels.PLANES:
			var twin := StandPlacement.stand_point(StandPlacement.north_twin(stand))
			var box := TaxiPaving.parked_footprint(twin, model)
			for rect in StandPlacement.rects_to_world(stand, [box] as Array[Rect2]):
				for corner in [rect.position, rect.end, Vector2(rect.position.x, rect.end.y)]:
					var p := Vector3(corner.x, 0.0, corner.y)
					assert_float(PlaneView.ground_height_at(p)).is_equal_approx(ground, 0.0001)


func test_west_and_east_pads_and_strips_lie_at_one_height() -> void:
	var classes := {"A": PlaneClasses.LARGE, "B": PlaneClasses.LARGE}
	_airside.set_gate_classes(classes)
	assert_bool(_airside.set_gate_stands({"A": _east(), "B": _west()})).is_true()
	assert_int(_airside.stand_pads().size()).is_equal(2)
	var tris := _triangles(_airside.paving.mesh)
	var lift := TaxiPavingSite.lift_at(StandPlacement.stand_point(_west()))
	var pad_y := lift + TaxiPaving.HEIGHT_M - TaxiPaving.PAD_DROP_M
	var strip_y := lift + TaxiPaving.HEIGHT_M
	print("lift %.4f pad_y %.4f strip_y %.4f" % [lift, pad_y, strip_y])
	assert_float(lift).is_greater(0.18)
	for stand in [_west(), _east()]:
		var twin_point := StandPlacement.stand_point(StandPlacement.north_twin(stand))
		var samples := 0
		var off := 0
		var on_strip := 0
		# Under every model's parked plane, on a 1 m grid, the paving drawn is
		# the pad and the strip over it, at those two heights only.
		for model: String in PlaneModels.PLANES:
			var box := TaxiPaving.parked_footprint(twin_point, model)
			var rect := StandPlacement.rects_to_world(stand, [box] as Array[Rect2])[0]
			var x := rect.position.x + 0.3
			while x < rect.end.x:
				var z := rect.position.y + 0.4
				while z < rect.end.y:
					var heights := _heights_under(tris, Vector2(x, z))
					samples += 1
					off += int(not heights.has(snappedf(pad_y, 0.001)))
					on_strip += int(heights.has(snappedf(strip_y, 0.001)))
					for y: float in heights:
						off += int(absf(y - pad_y) > 0.0005 and absf(y - strip_y) > 0.0005)
					z += 1.0
				x += 1.0
		print(
			(
				"%s samples %d off %d on strip %d"
				% [StandPlacement.side_of(stand), samples, off, on_strip]
			)
		)
		assert_int(samples).is_greater(1000)
		assert_int(on_strip).is_greater(100)
		assert_int(off).is_equal(0)
	# Both sides lie at the same lift.
	var east_lift := TaxiPavingSite.lift_at(StandPlacement.stand_point(_east()))
	assert_float(east_lift).is_equal_approx(lift, 0.0001)


## The asphalt triangles of `mesh` (surface 0, centre lines left out), each
## [a, b, c].
func _triangles(mesh: Mesh) -> Array[Array]:
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var out: Array[Array] = []
	for t in range(0, index.size(), 3):
		if not is_equal_approx(uvs[index[t]].x, TaxiPaving.ASPHALT_U):
			continue
		out.append([verts[index[t]], verts[index[t + 1]], verts[index[t + 2]]])
	return out


## The heights (to the millimetre) of every triangle of `tris` under `at`.
func _heights_under(tris: Array[Array], at: Vector2) -> Dictionary:
	var out := {}
	for tri in tris:
		var a := Vector2(tri[0].x, tri[0].z)
		var b := Vector2(tri[1].x, tri[1].z)
		var c := Vector2(tri[2].x, tri[2].z)
		var den := (b - a).cross(c - a)
		if absf(den) < 1e-9:
			continue
		var wb := (at - a).cross(c - a) / den
		var wc := (b - a).cross(at - a) / den
		var wa := 1.0 - wb - wc
		if wa >= -0.0001 and wb >= -0.0001 and wc >= -0.0001:
			out[snappedf(wa * tri[0].y + wb * tri[1].y + wc * tri[2].y, 0.001)] = true
	return out


func test_a_side_envelope_outline_is_its_north_twin_turned() -> void:
	var y := 0.29
	for stand in [_west(), _east()]:
		var outline := GateLinksView.envelope_outline(stand, PlaneClasses.LARGE, y)
		var twin := GateLinksView.envelope_outline(
			StandPlacement.north_twin(stand), PlaneClasses.LARGE, y
		)
		assert_int(outline.size()).is_equal(twin.size())
		assert_bool(outline[0].is_equal_approx(outline[outline.size() - 1])).is_true()
		for i in outline.size():
			var want := StandPlacement.to_world(stand, twin[i])
			assert_bool(outline[i].is_equal_approx(want)).is_true()
		# The loop encloses the union of the swing square and the way to the
		# spur: same area, and the stand point and the lane join lie inside.
		var parts := StandEnvelope.rects(stand, PlaneClasses.LARGE)
		var union_area := (
			parts[0].get_area() + parts[1].get_area() - parts[0].intersection(parts[1]).get_area()
		)
		var flat := PackedVector2Array()
		for p in outline:
			flat.append(Vector2(p.x, p.z))
		var area := absf(_shoelace(flat))
		print("%s outline area %.2f union %.2f" % [StandPlacement.side_of(stand), area, union_area])
		assert_float(area).is_equal_approx(union_area, 0.01)
		var join := StandPlacement.lane_join(stand)
		var inward := StandPlacement.turn(stand, Vector3(0.0, 0.0, 1.0))
		var at := StandPlacement.stand_point(stand)
		for p: Vector3 in [at, join + inward]:
			assert_bool(Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), flat)).is_true()


static func _shoelace(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in points.size():
		var next := points[(i + 1) % points.size()]
		total += points[i].x * next.y - next.x * points[i].y
	return total / 2.0
