class_name TestStandEnvelope
extends GdUnitTestSuite
## Per-class stand envelopes (StandEnvelope; decision runway-and-taxi-
## technical-design-movement-plan-analytic-bookings-planned-pauses, section 3):
## small exits need 19 m between them, medium 42 m and large 66 m; the medium
## envelope is the sweep StandPlacement has always used; every class member
## parked on the stand lies inside its class's swing square; and max_class()
## is the largest class whose envelope is clear, dropping as the player builds
## into the larger ones.
##
## The starter shell's exit at (20, 112) on the airport site: its stand point is
## at x -26, z -114.9. The test cells lie north of the shell, in row 100.

const SITE := preload("res://build/terminal_site.tres")
const EXIT := Vector2i(20, 112)
## Inside the small swing square (x -25.5).
const SMALL_CELL := Vector2i(17, 100)
## In the medium swing square but not the small one (x -10.5).
const MEDIUM_CELL := Vector2i(32, 100)
## In the large swing square but not the medium one (x 2.5).
const LARGE_CELL := Vector2i(45, 100)
## Under the small way north to the lane, north of every swing square.
const WAY_CELL := Vector2i(17, 20)
## East of every envelope (x 17.5).
const FREE_CELL := Vector2i(60, 100)

var _grid: SiteGrid
var _stand: Dictionary


func before_test() -> void:
	_grid = SiteGrid.new(SITE)
	assert_bool(StarterShell.place(_grid, SITE.starter_offset)).is_true()
	_stand = StandPlacement.for_cell(_grid, EXIT)


func _floor(cell: Vector2i) -> void:
	assert_bool(_grid.apply(BuildEdit.paint_floor(cell, BuildGrid.FLOOR_TILE, 1)).ok).is_true()


func test_exit_spacing_is_19_m_small_42_m_medium_66_m_large() -> void:
	var spacing := []
	for plane_class in PlaneClasses.ORDER:
		spacing.append(StandEnvelope.spacing_cells(plane_class))
	print(
		(
			"radius %.2f %.2f %.2f spacing %s"
			% [
				StandEnvelope.radius(PlaneClasses.SMALL),
				StandEnvelope.radius(PlaneClasses.MEDIUM),
				StandEnvelope.radius(PlaneClasses.LARGE),
				spacing
			]
		)
	)
	assert_array(spacing).is_equal([19, 42, 66])
	# The stand-overlap refusal names the small spacing.
	assert_int(StandPlacement.EXIT_SPACING_CELLS).is_equal(19)


func test_the_medium_envelope_is_the_sweep_stand_placement_has_always_used() -> void:
	assert_float(StandEnvelope.radius(PlaneClasses.MEDIUM)).is_equal_approx(
		StandPlacement.SWING_RADIUS_M, 0.0001
	)
	assert_float(StandEnvelope.half_span(PlaneClasses.MEDIUM)).is_equal_approx(
		StandPlacement.HALF_SPAN_M, 0.0001
	)
	for north_of in [INF, -130.0, -200.0]:
		var old := StandPlacement.swept_rects(_stand, north_of)
		var now := StandEnvelope.rects(_stand, PlaneClasses.MEDIUM, north_of)
		print("north of %s: %s / %s" % [north_of, old, now])
		assert_int(now.size()).is_equal(old.size())
		for i in old.size():
			assert_vector(now[i].position).is_equal_approx(old[i].position, Vector2.ONE * 0.0001)
			assert_vector(now[i].size).is_equal_approx(old[i].size, Vector2.ONE * 0.0001)


func test_each_class_grows_and_every_member_parks_inside_its_swing_square() -> void:
	var at := StandPlacement.stand_point(_stand)
	var wall_z := float(_stand["wall_z"])
	var widths := []
	for plane_class in PlaneClasses.ORDER:
		var swing: Rect2 = StandEnvelope.rects(_stand, plane_class)[0]
		widths.append(swing.size.x)
		for model: String in PlaneClasses.CLASSES[plane_class]["models"]:
			var row: Dictionary = PlaneModels.PLANES[model]
			var shift := PlaneClasses.stand_offset(model)
			var nose: float = at.z + shift.z + row["nose"]
			var tail: float = at.z + shift.z - row["tail"]
			var left: float = at.x + shift.x - row["half_span"]
			var right: float = at.x + shift.x + row["half_span"]
			print(
				(
					"%s %s: x %.2f..%.2f in %.2f..%.2f, tail z %.2f >= %.2f, nose %.2f short of the wall by %.2f"
					% [
						plane_class,
						model,
						left,
						right,
						swing.position.x,
						swing.end.x,
						tail,
						swing.position.y,
						nose,
						wall_z - nose
					]
				)
			)
			assert_float(left).is_greater(swing.position.x)
			assert_float(right).is_less(swing.end.x)
			assert_float(tail).is_greater(swing.position.y)
			# The nose stops short of the wall line; the strip between is the
			# passengers' walk, which walk_of() checks.
			assert_float(nose).is_less(wall_z)
	assert_float(widths[0]).is_less(widths[1])
	assert_float(widths[1]).is_less(widths[2])


func test_max_class_drops_as_the_larger_envelopes_are_built_into() -> void:
	var classes := [StandEnvelope.max_class(_grid, SITE, _stand)]
	_floor(FREE_CELL)
	classes.append(StandEnvelope.max_class(_grid, SITE, _stand))
	_floor(LARGE_CELL)
	classes.append(StandEnvelope.max_class(_grid, SITE, _stand))
	_floor(MEDIUM_CELL)
	classes.append(StandEnvelope.max_class(_grid, SITE, _stand))
	_floor(SMALL_CELL)
	classes.append(StandEnvelope.max_class(_grid, SITE, _stand))
	print("max class: empty, free cell, large, medium, small cell built: %s" % [classes])
	# The free cell (the control) changes nothing.
	assert_array(classes).is_equal(["large", "large", "medium", "small", ""])


func test_the_blocked_part_tells_the_swing_from_the_way_north() -> void:
	var small := PlaneClasses.SMALL
	var parts := [StandEnvelope.blocked_part(_grid, SITE, _stand, small)]
	_floor(WAY_CELL)
	parts.append(StandEnvelope.blocked_part(_grid, SITE, _stand, small))
	_floor(SMALL_CELL)
	parts.append(StandEnvelope.blocked_part(_grid, SITE, _stand, small))
	print("blocked parts: %s" % [parts])
	assert_array(parts).is_equal(
		[StandEnvelope.Part.CLEAR, StandEnvelope.Part.WAY, StandEnvelope.Part.SWING]
	)


func test_every_class_parked_on_the_north_row_clears_the_lane_band() -> void:
	var north := StandPlacement.make(1, 0.5, SITE.grid_origin.z)
	for plane_class in PlaneClasses.ORDER:
		assert_bool(StandEnvelope.clears_lane(north, plane_class)).is_true()
	# A control: a stand 10 m further north would put a large tail in the band.
	var too_far := StandPlacement.make(1, 0.5, SITE.grid_origin.z - 10.0)
	print("lane band south edge z %.2f" % StandEnvelope.lane_band_south())
	assert_bool(StandEnvelope.clears_lane(too_far, PlaneClasses.LARGE)).is_false()
	assert_bool(StandEnvelope.clears_lane(too_far, PlaneClasses.SMALL)).is_true()


func test_edit_cells_cover_both_sides_of_a_wall_and_a_whole_room() -> void:
	var wall := BuildEdit.place_wall(Vector2i(5, 5), BuildGrid.Side.NORTH)
	assert_array(StandEnvelope.edit_cells(wall)).contains_exactly_in_any_order(
		[Vector2i(5, 5), Vector2i(5, 4)]
	)
	var room := BuildEdit.place_room(Rect2i(2, 3, 2, 2), &"cafe")
	assert_int(StandEnvelope.edit_cells(room).size()).is_greater_equal(4)
	assert_array(StandEnvelope.edit_cells(room)).contains(
		[Vector2i(2, 3), Vector2i(3, 3), Vector2i(2, 4), Vector2i(3, 4)]
	)
