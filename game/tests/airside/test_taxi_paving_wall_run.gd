class_name TestTaxiPavingWallRun
extends GdUnitTestSuite
## A link's asphalt band runs on over its stand pad to the wall line (user ruling
## "Run the band on", board 72617e4b), so it ends under the site's paving and
## never shows a strip end on the pad's flat edge shade. The centre line still
## stops at the stand point. A stand whose stand point already lies under the
## site's paving changes only there, where nothing shows.

const SITE := preload("res://build/terminal_site.tres")
const LANE_Z := StandPlacement.TAXI_LANE_Z
## Gate A of the taxi seams probe's --unequal layout: its stand point (z -215.9)
## lies north of the site's paving (z -210), so its strip end shows.
const NORTH_STAND := {"exit": 2, "x": -22.5, "wall_z": -199.0}
## The starter's stand, whose stand point (z -114.9) lies under the site's paving.
const SOUTH_STAND := {"exit": 3, "x": -22.5, "wall_z": -98.0}


## The route from the lane to `stand` (lane join, pushback end, stand point), as
## Airside.taxi_routes() gives a stand's lead-in.
func _lead_in(stand: Dictionary) -> PackedVector3Array:
	return PackedVector3Array(
		[
			StandPlacement.lane_join(stand),
			StandPlacement.pushback_end(stand),
			StandPlacement.stand_point(stand)
		]
	)


func _link(strip_list: Array[Dictionary], x: float) -> Rect2:
	for strip in strip_list:
		var rect: Rect2 = strip["rect"]
		if strip["across_x"] and absf(rect.get_center().x - x) < TaxiPaving.SAME_M:
			return rect
	return Rect2()


func _shown(stand: Dictionary) -> TaxiPaving:
	var paving := auto_free(TaxiPaving.new()) as TaxiPaving
	var pad := TaxiPaving.stand_pad(StandPlacement.stand_point(stand))
	paving.show_routes([_lead_in(stand)] as Array[PackedVector3Array], LANE_Z, [pad])
	return paving


func test_the_band_reaches_the_wall_line_for_a_stand_north_of_the_site_paving() -> void:
	var at := StandPlacement.stand_point(NORTH_STAND)
	var site_north := SITE.grid_origin.z
	print("stand point z %.2f, site paving from z %.2f" % [at.z, site_north])
	# Control: the stand point lies north of the site's paving, where a strip end shows.
	assert_float(at.z).is_less(site_north)
	var paving := _shown(NORTH_STAND)
	var link := _link(paving.shown, at.x)
	print("link %s pad %s" % [link, paving.pads[0]])
	assert_float(link.position.y).is_equal_approx(LANE_Z + TaxiPaving.WIDTH_M / 2.0, 0.001)
	assert_float(link.end.y).is_equal_approx(float(NORTH_STAND["wall_z"]), 0.001)
	assert_float(link.end.y).is_equal_approx(paving.pads[0].end.y, 0.001)
	# The wall line lies on the site, so the band's end is under its paving.
	assert_float(link.end.y).is_greater_equal(site_north)
	# Ground between the stand point and the site's paving is on the strip.
	assert_bool(TaxiPaving.covers(paving.shown, Vector3(at.x + 4.0, 0.0, at.z + 3.0))).is_true()
	# The mesh carries the band to the wall line: a vertex there with a band
	# position other than the edge shade the pad has.
	var arrays := paving.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var band_at_wall := 0
	for i in verts.size():
		var v := verts[i]
		if absf(v.z - link.end.y) < 0.001 and is_equal_approx(v.y, TaxiPaving.HEIGHT_M):
			if uvs[i] != Vector2(TaxiPaving.ASPHALT_U, TaxiPaving.ASPHALT_V_FROM):
				band_at_wall += 1
	print("band vertices on the wall line: %d" % band_at_wall)
	assert_int(band_at_wall).is_greater(0)


func test_the_centre_line_still_stops_at_the_stand_point() -> void:
	var at := StandPlacement.stand_point(NORTH_STAND)
	var paving := _shown(NORTH_STAND)
	var line := Rect2()
	for rect in paving.lines:
		if absf(rect.get_center().x - at.x) < TaxiPaving.SAME_M and rect.size.y > rect.size.x:
			line = rect
	print("link line %s" % line)
	assert_float(line.size.y).is_greater(0.0)
	assert_float(line.end.y).is_equal_approx(at.z, 0.001)


func test_a_stand_under_the_site_paving_changes_only_under_it() -> void:
	var at := StandPlacement.stand_point(SOUTH_STAND)
	var site_north := SITE.grid_origin.z
	assert_float(at.z).is_greater_equal(site_north)
	var before := TaxiPaving.strips([_lead_in(SOUTH_STAND)] as Array[PackedVector3Array], LANE_Z)
	var paving := _shown(SOUTH_STAND)
	assert_int(paving.shown.size()).is_equal(before.size())
	var old := _link(before, at.x)
	var now := _link(paving.shown, at.x)
	print("link before %s now %s" % [old, now])
	# The same strip north of the stand point; what it gains lies south of the
	# stand point, all under the site's paving.
	assert_float(now.position.y).is_equal(old.position.y)
	assert_float(now.position.x).is_equal(old.position.x)
	assert_float(now.size.x).is_equal(old.size.x)
	assert_float(old.end.y).is_equal_approx(at.z, 0.001)
	assert_float(now.end.y).is_equal_approx(float(SOUTH_STAND["wall_z"]), 0.001)
	assert_float(old.end.y).is_greater_equal(site_north)


func test_strips_with_no_end_on_a_pad_are_left_as_they_are() -> void:
	var lane := {"rect": Rect2(-139, -299, 278, 30), "across_x": false}
	var stub := {"rect": Rect2(-139, -338, 30, 39), "across_x": true}
	var pad := TaxiPaving.stand_pad(StandPlacement.stand_point(NORTH_STAND))
	var got := TaxiPaving.run_on_to_walls([lane, stub] as Array[Dictionary], [pad])
	assert_int(got.size()).is_equal(2)
	assert_that(got[0]["rect"]).is_equal(lane["rect"])
	assert_that(got[1]["rect"]).is_equal(stub["rect"])


## Two gates 19 m apart on different wall lines: gate B's pad (wall -180) also
## holds gate A's stand point, and comes first in the list. Each link still runs
## on to its own stand's wall line, the pad whose south edge lies NOSE_GAP_M plus
## NOSE_M south of the stand point.
func test_overlapping_pads_on_other_wall_lines_carry_each_link_to_its_own_wall() -> void:
	var gate_b := {"exit": 3, "x": -3.5, "wall_z": -180.0}
	var at_a := StandPlacement.stand_point(NORTH_STAND)
	var at_b := StandPlacement.stand_point(gate_b)
	var pad_a := TaxiPaving.stand_pad(at_a)
	var pad_b := TaxiPaving.stand_pad(at_b)
	# Control: B's pad holds A's stand point and reaches further south.
	assert_bool(pad_b.has_point(Vector2(at_a.x, at_a.z))).is_true()
	assert_float(pad_b.end.y).is_greater(pad_a.end.y)
	var routes: Array[PackedVector3Array] = [_lead_in(NORTH_STAND), _lead_in(gate_b)]
	var got := TaxiPaving.run_on_to_walls(TaxiPaving.strips(routes, LANE_Z), [pad_b, pad_a])
	print("A %s B %s" % [_link(got, at_a.x), _link(got, at_b.x)])
	assert_float(_link(got, at_a.x).end.y).is_equal_approx(float(NORTH_STAND["wall_z"]), 0.001)
	assert_float(_link(got, at_b.x).end.y).is_equal_approx(float(gate_b["wall_z"]), 0.001)
