class_name TestLandsideGeometry
extends GdUnitTestSuite
## The authored landside geometry matches the converted assets and the baked
## road (decision landside-assets-the-curb-is-an-authored-paint-only-drop-off):
## lanes stay inside the road baked into the shell (x -43 to 43), every berth
## stands on a Mount_Berth marker of a 16 x 3 m curb bay, and a surface lot's
## slots are the 12 stalls of tp_parking_01a with its entry and exit lanes
## through the barrier arms, the lot turned to face the road.

const STARTER := preload("res://landside/starter_landside.tres")
## tp_airport_shell.glb's Road node: x -43 to 43 (the shell stands at x 0).
const ROAD_EAST := 43.0
const ROAD_WEST := -43.0
## tp_curb_bay_01a.glb: Mount_Berth_1 and _2 at local x -3.25 and 3.25, z 1.5
## from the kerb line at z -58.7.
const BERTH_OFFSET := 3.25
const BERTH_Z := -57.2
## tp_parking_01a.glb: stall paint lines every 4 m from local x -2, rows at
## local z +-6.85; the barrier arms span local z 0.35 to 7 and -7 to -0.35.
const STALL_PITCH := 4.0
const STALL_ROW := 6.85
const LANE_OFFSET := 3.7


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


func test_every_curb_is_a_whole_number_of_bays_with_berths_on_the_markers() -> void:
	# The starter curb is two bays, so four berths.
	assert_int(STARTER.curb.berths.size()).is_equal(4)
	var groups := [STARTER.curb.berths]
	for spot in STARTER.curb_spots:
		groups.append(spot.berths)
		assert_int(spot.berths.size()).is_equal(2)
		assert_vector(spot.footprint).is_equal(Vector2(16.0, 3.0))
		assert_float(spot.centre.z).is_equal_approx(BERTH_Z, 0.001)
		# Both berths on the bay's two markers.
		var xs := [spot.berths[0].x, spot.berths[1].x]
		xs.sort()
		assert_float(xs[0]).is_equal_approx(spot.centre.x - BERTH_OFFSET, 0.001)
		assert_float(xs[1]).is_equal_approx(spot.centre.x + BERTH_OFFSET, 0.001)
	for berths: PackedVector3Array in groups:
		assert_int(berths.size() % 2).is_equal(0)
		for berth in berths:
			assert_float(berth.z).is_equal_approx(BERTH_Z, 0.001)
			assert_float(berth.x).is_between(ROAD_WEST, ROAD_EAST)
	# The starter bays tile the kerb from the stop west: 16 m each, side by side.
	var starter_xs: Array[float] = []
	for berth in STARTER.curb.berths:
		starter_xs.append(berth.x)
	starter_xs.sort()
	var expected := [-31.25, -24.75, -15.25, -8.75]
	for i in expected.size():
		assert_float(starter_xs[i]).is_equal_approx(expected[i], 0.001)
	# Every get-out point is on the kerb side of its berth.
	for i in STARTER.curb.berths.size():
		assert_float(STARTER.curb.get_out[i].z).is_less(STARTER.curb.berths[i].z)
		assert_float(STARTER.curb.get_out[i].x).is_equal(STARTER.curb.berths[i].x)


func test_a_surface_lot_has_the_assets_twelve_stalls_and_lanes_through_its_barriers() -> void:
	var lot := STARTER.lots[0]
	assert_int(lot.kind).is_equal(LandsideLotSpot.Kind.SURFACE)
	assert_vector(lot.footprint).is_equal(Vector2(24.0, 32.3))
	assert_int(lot.slots.size()).is_equal(12)
	# Turned to face the road: the entry lane (local z +3.7) is on the west, the
	# right of a car driving south, the exit lane (local z -3.7) on the east.
	var axis := lot.centre.x
	var entry := lot.access[lot.access.size() - 1]
	var exit := lot.exit[0]
	assert_float(entry.x).is_equal_approx(axis - LANE_OFFSET, 0.001)
	assert_float(exit.x).is_equal_approx(axis + LANE_OFFSET, 0.001)
	# Both lanes stand on the barrier line, local x -7 = 7 m before the origin.
	assert_float(entry.z).is_equal_approx(exit.z, 0.001)
	var origin_z := entry.z + 7.0
	# Two rows of six stalls, 4 m apart along the lot's depth, local z +-6.85
	# (the entry side first).
	var west: Array[float] = []
	var east: Array[float] = []
	for slot in lot.slots:
		var side := west if slot.x < axis else east
		side.append(slot.z)
		assert_float(absf(slot.x - axis)).is_equal_approx(STALL_ROW, 0.001)
	assert_int(west.size()).is_equal(6)
	assert_int(east.size()).is_equal(6)
	for zs in [west, east]:
		for i in zs.size():
			assert_float(zs[i]).is_equal_approx(origin_z + i * STALL_PITCH, 0.001)
	# The lot's slab ends where the entrance edge (local x -7.3) is.
	assert_float(lot.centre.z - lot.footprint.y / 2.0).is_equal_approx(origin_z - 7.3, 0.001)


func test_the_lots_do_not_overlap_each_other_or_the_curb_bays() -> void:
	var rects: Array[Rect2] = []
	for lot in STARTER.lots:
		rects.append(
			Rect2(
				lot.centre.x - lot.footprint.x / 2.0,
				lot.centre.z - lot.footprint.y / 2.0,
				lot.footprint.x,
				lot.footprint.y
			)
		)
	assert_bool(rects[0].intersects(rects[1])).is_false()
	for spot in STARTER.curb_spots:
		var bay := Rect2(spot.centre.x - 8.0, spot.centre.z - 1.5, 16.0, 3.0)
		for rect in rects:
			assert_bool(rect.intersects(bay)).is_false()
	var bays: Array[Rect2] = []
	for spot in STARTER.curb_spots:
		bays.append(Rect2(spot.centre.x - 8.0, spot.centre.z - 1.5, 16.0, 3.0))
	assert_bool(bays[0].intersects(bays[1])).is_false()
