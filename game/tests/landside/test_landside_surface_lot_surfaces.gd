class_name TestLandsideSurfaceLotSurfaces
extends GdUnitTestSuite
## Board 297c9eb8: in front of the surface car park (lot spot 0), a car's wheels
## stand on the surface drawn under them (the road, the sidewalk, whose top is
## 0.1 m over the road, the paved apron TP_Parking_01A_Apron and the lot's own
## floor), and a passenger walks from the stall over the road to the far
## sidewalk on paving, never over the lawn and clear of the barrier posts. The
## surfaces are read from the meshes as main.tscn places them: the airport site
## (its Road mesh carries the road and both sidewalks) at z -80, and
## tp_parking_01a.glb where LandsidePlaces puts it (lot_transform).

const STARTER := preload("res://landside/starter_landside.tres")
const SITE_SCENE := preload("res://assets/buildings/tp_airport_site.glb")
const LOT_SCENE := preload("res://assets/landside/tp_parking_01a.glb")
const CAR_SCENE := preload("res://assets/vehicles/tp_suv_01b.glb")
## main.tscn's Airside/Terminal.
const SITE_AT := Vector3(0.0, 0.0, -80.0)
const LOT := 0
const ROAD_Y := 0.1
const SIDEWALK_Y := 0.2
const APRON := "TP_Parking_01A_Apron"
const SAMPLE_MM := 50
## The barrier posts' bases are 0.6 m square round the barrier arms' pivots; a
## walker (0.25 m radius) keeps this far from a post's middle.
const POST_CLEAR := 0.3 + 0.25
## The part of the map the meshes are read for (x and z).
const AREA := Rect2(14.0, -62.0, 34.0, 58.0)

var _spot: LandsideLotSpot
var _paths: LandsidePaths
var _axles: Vector2
var _map: LandsideSurfaceMap
var _posts: Array[Vector3] = []


func before() -> void:
	_spot = STARTER.lots[LOT]
	_paths = LandsidePaths.new(STARTER)
	_map = LandsideSurfaceMap.new(AREA)
	_map.add_scene(SITE_SCENE, Transform3D(Basis(), SITE_AT))
	var at := LandsidePlaces.lot_transform(_spot)
	_map.add_scene(LOT_SCENE, at)
	var lot: Node3D = LOT_SCENE.instantiate()
	for arm in ["TP_Parking_01A_Entry_Barrier", "TP_Parking_01A_Exit_Barrier"]:
		var pivot := LandsideSurfaceMap.to_root(lot, lot.find_child(arm, true, false)).origin
		_posts.append(at * Vector3(pivot.x, 0.0, pivot.z))
	lot.free()
	var car: Node3D = CAR_SCENE.instantiate()
	_axles = LandsideViews.axles_of(car)
	car.free()


func test_the_surface_lot_is_a_surface_lot_with_its_apron() -> void:
	assert_int(_spot.kind).is_equal(LandsideLotSpot.Kind.SURFACE)
	# The apron is in front of the gate and under the lanes' foot behind the sidewalk.
	for at in [Vector3(28, ROAD_Y, -38.0), Vector3(35.4, ROAD_Y, -39.0)]:
		var top := _map.top(at)
		print("under %s: %s" % [at, top])
		assert_str(str(top[1])).is_equal(APRON)
		assert_float(float(top[0])).is_equal_approx(ROAD_Y, 0.001)
	# The posts stand on it.
	for post in _posts:
		var top := _map.top(post)
		print("post %s: %s" % [post, top])
		assert_float(float(top[0])).is_greater(ROAD_Y - 0.001)


## The lanes cross the sidewalk on its top: the access lane in, and the exit
## lane out to the far carriageway.
func test_the_surface_lot_lanes_run_on_the_sidewalk_top_and_the_apron() -> void:
	for lane: PackedVector3Array in [_spot.access, _spot.exit]:
		var found := _lane_off_surface(lane)
		print("lane %s..%s: %s" % [lane[0], lane[lane.size() - 1], found])
		assert_array(found["off"]).is_empty()
		# Controls: the lane was checked on the sidewalk's top and on the apron.
		assert_int(found["sidewalk"]).is_greater_equal(20)
		assert_int(found["apron"]).is_greater_equal(30)


## The control for the check itself: the access lane as it was, flat at road
## height over the sidewalk, is found sunk into it.
func test_the_old_flat_access_lane_is_found_sunk_in_the_sidewalk() -> void:
	var flat := PackedVector3Array(
		[Vector3(28, ROAD_Y, -55), Vector3(28, ROAD_Y, -45), Vector3(28, ROAD_Y, -37.5)]
	)
	var found := _lane_off_surface(flat)
	print("flat lane: %d off, first %s" % [found["off"].size(), found["off"].slice(0, 1)])
	assert_int(found["off"].size()).is_greater_equal(10)


## A car drawn on its way in (LandsideViews.on_path, the SUV's axles), from the
## road over the sidewalk and the apron through the gate to a stall, and on a
## car turning round at the gate, has both wheels on the surface at every step.
func test_a_car_on_its_way_in_has_both_wheels_on_the_surface() -> void:
	var legs: Array = []
	var from := LandsideDefinition.mm_along(_spot.access, Vector3(28, ROAD_Y, -45.0))
	for k in [0, 11]:
		legs.append(
			[_paths.slot_path[LOT][k], from, _paths.slot_stand[LOT][k], PackedVector3Array()]
		)
	legs.append([_paths.turn_path[LOT], from, _paths.turn_end[LOT], PackedVector3Array()])
	legs.append(
		[_spot.access, from, LandsideDefinition.length_mm(_spot.access), PackedVector3Array()]
	)
	var found := _wheels_off(legs)
	print(
		(
			"way in: checked %d, pitched %d, worst %.3f, off %s"
			% [found["checked"], found["pitched"], found["worst"], found["off"].slice(0, 4)]
		)
	)
	assert_array(found["off"]).is_empty()
	assert_int(found["checked"]).is_greater(800)
	# A control: the car did pitch going over the sidewalk.
	assert_int(found["pitched"]).is_greater(20)


## On the way out: from a stall (and the turn round) back to the exit lane, then
## along it over the sidewalk to the far carriageway, both wheels on the surface.
func test_a_car_on_its_way_out_has_both_wheels_on_the_surface() -> void:
	var legs: Array = []
	for k in [0, 6]:
		var path: PackedVector3Array = _paths.slot_path[LOT][k]
		legs.append([path, _paths.slot_back[LOT][k], _paths.slot_end[LOT][k], PackedVector3Array()])
	var exit := _spot.exit
	legs.append(
		[
			exit,
			0,
			LandsideDefinition.mm_along(exit, Vector3(35.4, ROAD_Y, -45.0)),
			_paths.lead_in(LandsideVehicle.Lane.LOT_EXIT, LOT)
		]
	)
	var found := _wheels_off(legs)
	print(
		(
			"way out: checked %d, pitched %d, worst %.3f, off %s"
			% [found["checked"], found["pitched"], found["worst"], found["off"].slice(0, 4)]
		)
	)
	assert_array(found["off"]).is_empty()
	assert_int(found["checked"]).is_greater(400)
	assert_int(found["pitched"]).is_greater(20)


## Every passenger's walk out of the lot, from each stall to the far sidewalk,
## is on paving all the way: the lot's floor, the apron, the sidewalk, the road
## and the far sidewalk, never the lawn, and it keeps clear of the barrier posts.
func test_every_walk_from_the_surface_lot_stays_on_paving() -> void:
	var off: Array[String] = []
	var sidewalk := 0
	var apron := 0
	var nearest_post := INF
	for slot in _spot.slots.size():
		var walk := PackedVector3Array(_paths.lot_walk(LOT, slot))
		var found := _walk_off_paving(walk)
		off.append_array(found["off"])
		sidewalk += found["sidewalk"]
		apron += found["apron"]
		nearest_post = minf(nearest_post, found["post"])
		# It crosses the road and ends on the far sidewalk.
		assert_float(walk[walk.size() - 1].z).is_less(-60.0)
	print(
		(
			"walks: off %d %s, sidewalk %d, apron %d, nearest post %.2f m"
			% [off.size(), off.slice(0, 4), sidewalk, apron, nearest_post]
		)
	)
	assert_array(off).is_empty()
	assert_float(nearest_post).is_greater_equal(POST_CLEAR)
	# Controls: the walks were checked on both sidewalks' tops and on the apron.
	assert_int(sidewalk).is_greater_equal(12 * 20)
	assert_int(apron).is_greater_equal(12 * 20)


## The control: the walk as it was, from the gate to (25, 0.1, -37.5) by the
## entry post, over the lawn and flat across both sidewalks, is found off paving
## and too close to the post.
func test_the_old_walk_over_the_lawn_is_found_off_paving() -> void:
	var old := PackedVector3Array(
		[
			_spot.access[_spot.access.size() - 1],
			Vector3(25, ROAD_Y, -37.5),
			Vector3(25, ROAD_Y, -39.5),
			Vector3(25, ROAD_Y, -60.5)
		]
	)
	var found := _walk_off_paving(old)
	print(
		(
			"old walk: %d off, first %s, nearest post %.2f m"
			% [found["off"].size(), found["off"].slice(0, 2), found["post"]]
		)
	)
	assert_int(found["off"].size()).is_greater_equal(40)
	assert_float(found["post"]).is_less(POST_CLEAR)


## Each leg [path, from mm, to mm, way in]: both wheels of a car drawn on it
## every SAMPLE_MM, against the surface.
func _wheels_off(legs: Array) -> Dictionary:
	var off: Array[String] = []
	var checked := 0
	var pitched := 0
	var worst := 0.0
	for leg: Array in legs:
		var path: PackedVector3Array = leg[0]
		for mm in range(leg[1], leg[2], SAMPLE_MM):
			var dir := LandsideDefinition.heading_at(path, mm)
			var pose := LandsideViews.on_path(path, mm, dir, _axles, leg[3])
			pitched += int(absf(pose.basis.z.y) > 0.01)
			for axle in [_axles.x, _axles.y]:
				var wheel := pose * Vector3(0.0, 0.0, axle)
				var gap := _map.gap(wheel)
				checked += 1
				if is_nan(gap):
					continue
				worst = maxf(worst, absf(gap))
				if absf(gap) > LandsideSurfaceMap.ON:
					off.append("%s gap %.3f" % [wheel, gap])
	return {"off": off, "checked": checked, "pitched": pitched, "worst": worst}


## Samples a lane every SAMPLE_MM: the points whose height is off the surface,
## and how many were on the sidewalk's top and on the apron.
func _lane_off_surface(lane: PackedVector3Array) -> Dictionary:
	var off: Array[String] = []
	var sidewalk := 0
	var apron := 0
	for mm in range(0, LandsideDefinition.length_mm(lane) + 1, SAMPLE_MM):
		var at := LandsideDefinition.point_at(lane, mm)
		var top := _map.top(at)
		sidewalk += int(absf(float(top[0]) - SIDEWALK_Y) < 0.005)
		apron += int(top[1] == APRON)
		var gap := _map.gap(at)
		if not is_nan(gap) and absf(gap) > LandsideSurfaceMap.ON:
			off.append("%s gap %.3f" % [at, gap])
	return {"off": off, "sidewalk": sidewalk, "apron": apron}


## Samples a walk every SAMPLE_MM: the points over the lawn or off the surface,
## how many were on a sidewalk's top and on the apron, and the nearest a point
## came to a barrier post (flat distance).
func _walk_off_paving(walk: PackedVector3Array) -> Dictionary:
	var off: Array[String] = []
	var sidewalk := 0
	var apron := 0
	var post := INF
	for mm in range(0, LandsideDefinition.length_mm(walk) + 1, SAMPLE_MM):
		var at := LandsideDefinition.point_at(walk, mm)
		var top := _map.top(at)
		for p in _posts:
			post = minf(post, Vector2(at.x - p.x, at.z - p.z).length())
		sidewalk += int(
			absf(float(top[0]) - SIDEWALK_Y) < 0.005 and absf(at.y - SIDEWALK_Y) < 0.005
		)
		apron += int(top[1] == APRON)
		if top[1] == LandsideSurfaceMap.LAWN:
			off.append("%s over the lawn" % at)
			continue
		var gap := _map.gap(at)
		if not is_nan(gap) and absf(gap) > LandsideSurfaceMap.ON:
			off.append("%s gap %.3f" % [at, gap])
	return {"off": off, "sidewalk": sidewalk, "apron": apron, "post": post}
