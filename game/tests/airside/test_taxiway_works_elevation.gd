class_name TestTaxiwayWorksElevation
extends GdUnitTestSuite
## Regression test for TaxiwayWorksView prop grounding on side-spur earth pads
## and runway-works earth pads/skirts matching the 0.20 m runway slab.

const Kit := preload("res://tests/airside/airside_props_kit.gd")
const STAND := {"exit": 4, "x": 21.5, "wall_z": -98.0}

var _airside: Airside


func before() -> void:
	_airside = Kit.airside_from_main()
	add_child(_airside)
	assert_bool(_airside.set_gate_stands({FlightSim.DEFAULT_GATE: STAND})).is_true()


func after() -> void:
	_airside.free()


func test_taxiway_works_props_sit_grounded_and_runway_works_match_slab() -> void:
	var view := TaxiwayWorksView.new()
	add_child(view)
	var live := TaxiwayWorks.live_rects(_airside.paving.shown, _airside.paving.pads, Runway.SMALL)
	var side_layout := TaxiwayWorks.side_layout(
		StandPlacement.WEST, -StandPlacement.SIDE_LANE_X - 40.0, Vector2(-306.0, -269.0), live
	)
	view._build(StandPlacement.WEST, side_layout)
	var works_w := view.get_node("Works%s" % StandPlacement.WEST.capitalize()) as Node3D
	var w_ground := works_w.get_node("Ground") as MeshInstance3D
	var w_verts := w_ground.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var w_top := w_verts[0].y
	for item: Dictionary in side_layout["props"]:
		var centre: Vector2 = item["centre"]
		var on_pad := TaxiwayWorksView._on_ground_piece(centre, side_layout["ground"])
		var expected_y := (
			PlaneView.ground_height_at(Vector3(centre.x, 0.0, centre.y))
			+ (TaxiwayWorksView.GROUND_LIFT_M if on_pad else 0.0)
		)
		var matched := false
		for child in works_w.get_children():
			if child.name == "Ground":
				continue
			var p := (child as Node3D).position
			if Vector2(p.x, p.z).distance_to(item["origin"]) < 0.01:
				assert_float(p.y).is_equal_approx(expected_y, 0.001)
				matched = true
				break
		assert_bool(matched).is_true()
	assert_float(w_top).is_greater_equal(TaxiwayWorksView.GROUND_LIFT_M - 0.001)
	var rwy_layout := TaxiwayWorks.runway_layout(Runway.SMALL, Runway.MEDIUM, live)
	view._build(TaxiwayWorksView.RUNWAY, rwy_layout)
	var works_rwy := view.get_node("WorksRunway") as Node3D
	var r_ground := works_rwy.get_node("Ground") as MeshInstance3D
	var r_verts := r_ground.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	assert_int(r_ground.mesh.get_surface_count()).is_equal(2)
	var r_top := r_verts[0].y
	assert_float(r_top).is_equal_approx(
		TaxiwayWorksView.RUNWAY_BASE_Y + TaxiwayWorksView.GROUND_LIFT_M, 0.001
	)
	var rwy_pad_props := 0
	for item: Dictionary in rwy_layout["props"]:
		var centre: Vector2 = item["centre"]
		var on_pad := TaxiwayWorksView._on_ground_piece(centre, rwy_layout["ground"])
		var expected_y := (
			PlaneView.ground_height_at(Vector3(centre.x, 0.0, centre.y))
			+ ((TaxiwayWorksView.RUNWAY_BASE_Y + TaxiwayWorksView.GROUND_LIFT_M) if on_pad else 0.0)
		)
		var matched := false
		for child in works_rwy.get_children():
			if child.name == "Ground":
				continue
			var p := (child as Node3D).position
			if Vector2(p.x, p.z).distance_to(item["origin"]) < 0.01:
				assert_float(p.y).is_equal_approx(expected_y, 0.001)
				if on_pad:
					rwy_pad_props += 1
				matched = true
				break
		assert_bool(matched).is_true()
	assert_int(rwy_pad_props).is_greater(0)
	view.free()
