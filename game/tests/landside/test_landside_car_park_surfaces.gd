class_name TestLandsideCarParkSurfaces
extends GdUnitTestSuite
## Board 0b82b7e4: in front of the multi-storey car park, a car's wheels stand on
## the surface drawn under them (the road, the sidewalk, whose top is 0.1 m over
## the road, the paved apron and the slab), and a ground-floor passenger walks
## from the gate to the road crossing on paving, never over the lawn. The
## surfaces are read from the meshes as main.tscn places them: the airport
## site (its Road mesh carries the road and the sidewalk) at z -80, and
## tc_parking_2a.glb on the lot spot's centre. Where there is neither, the lawn
## (main.tscn's Ground plane) is at y -0.1.

const STARTER := preload("res://landside/starter_landside.tres")
const SITE_SCENE := preload("res://assets/buildings/tp_airport_site.glb")
const MULTI_SCENE := preload("res://assets/landside/tc_parking_2a.glb")
const CAR_SCENE := preload("res://assets/vehicles/tp_suv_01b.glb")
## main.tscn's Airside/Terminal.
const SITE_AT := Vector3(0.0, 0.0, -80.0)
const ROAD_Y := 0.1
const SIDEWALK_Y := 0.2
const SAMPLE_MM := 50
## The multi-storey meshes are Parking_2A, Parking_2A_Apron and Parking_1B_Logo; the
## site's are Lot and Road.
const CAR_PARK_MESH := "Parking_"
## The part of the map the meshes are read for (x and z).
const AREA := Rect2(-15.0, -62.0, 30.0, 82.0)
## A walker's radius, and how much higher than the sidewalk's top a surface by its
## feet may stand (paint and joints are under 1 cm; the planter bed's rim is 2 cm
## at its edge and 6 cm on top).
const WALKER_RADIUS := 0.25
const RAISED := 0.01

var _spot: LandsideLotSpot
var _paths: LandsidePaths
var _axles: Vector2
var _map: LandsideSurfaceMap


func before() -> void:
	_spot = STARTER.lots[1]
	_paths = LandsidePaths.new(STARTER)
	_map = LandsideSurfaceMap.new(AREA)
	_map.add_scene(SITE_SCENE, Transform3D(Basis(), SITE_AT))
	_map.add_scene(MULTI_SCENE, Transform3D(Basis(), _spot.centre))
	var car: Node3D = CAR_SCENE.instantiate()
	_axles = LandsideViews.axles_of(car)
	car.free()


## The lanes cross the sidewalk on its top: the access lane in, and the way
## out down to the exit lane and along it to the far carriageway.
func test_the_multi_storey_lanes_run_on_the_sidewalk_top_and_the_apron() -> void:
	var out := PackedVector3Array(_spot.way_out.slice(1))
	out.append_array(_spot.exit.slice(0, _spot.exit.size() - 1))
	for lane: PackedVector3Array in [_spot.access, out]:
		var found := _lane_off_surface(lane)
		print("lane %s..%s: %s" % [lane[0], lane[lane.size() - 1], found])
		assert_array(found["off"]).is_empty()
		# Controls: the lane was checked on the sidewalk's top and on the apron.
		assert_int(found["sidewalk"]).is_greater_equal(20)
		assert_int(found["lot"]).is_greater_equal(60)


## The control for the check itself: the lanes as they were, flat at road
## height over the sidewalk, are found sunk into it.
func test_a_lane_flat_at_road_height_over_the_sidewalk_is_found_sunk() -> void:
	var flat := PackedVector3Array(
		[
			Vector3(3.5, ROAD_Y, -45.0),
			Vector3(3.5, ROAD_Y, -38.0),
			_spot.access[_spot.access.size() - 1]
		]
	)
	var found := _lane_off_surface(flat)
	print("flat lane: %d off, first %s" % [found["off"].size(), found["off"].slice(0, 1)])
	assert_int(found["off"].size()).is_greater_equal(10)


## A car drawn along the lanes (LandsideViews.on_path, the SUV's axles) has both
## wheels on the surface at every step, over the sidewalk and up the apron to the gate.
func test_a_car_on_the_lanes_has_both_wheels_on_the_surface() -> void:
	var checked := 0
	var pitched := 0
	var worst := 0.0
	var off: Array[String] = []
	# Two slot paths (through the gate) and the access lane alone (a car on it near
	# the gate looks past its end for its front wheels).
	for path: PackedVector3Array in [_paths.slot_path[1][0], _paths.slot_path[1][9], _spot.access]:
		# Up to the entrance, or the lane's own end (a car there is on its slot path).
		var gate := mini(
			LandsideDefinition.mm_along(path, _spot.entrance[0]), LandsideDefinition.length_mm(path)
		)
		var start := LandsideDefinition.mm_along(path, Vector3(3.5, ROAD_Y, -45.0))
		for mm in range(start, gate, SAMPLE_MM):
			var pose := LandsideViews.on_path(path, mm, Vector3(0, 0, 1), _axles)
			pitched += int(absf(pose.basis.z.y) > 0.01)
			for axle in [_axles.x, _axles.y]:
				var wheel := pose * Vector3(0.0, 0.0, axle)
				var gap := _map.gap(wheel)
				checked += 1
				if not is_nan(gap):
					worst = maxf(worst, absf(gap))
					if absf(gap) > LandsideSurfaceMap.ON:
						off.append("%s gap %.3f" % [wheel, gap])
	print(
		(
			"wheels checked %d, pitched poses %d, worst gap %.3f, off %s"
			% [checked, pitched, worst, off.slice(0, 4)]
		)
	)
	assert_array(off).is_empty()
	assert_int(checked).is_greater(400)
	# A control: the car did pitch, going over the sidewalk and up the apron.
	assert_int(pitched).is_greater(60)


## Inside, up the ramps to the top deck: both wheels on the ramp's own mesh.
func test_a_car_up_the_inside_ramps_has_both_wheels_on_the_ramp() -> void:
	var path: PackedVector3Array = _paths.slot_path[1][20]
	var inside := LandsideDefinition.mm_along(path, _spot.entrance[1])
	var stand: int = _paths.slot_stand[1][20]
	var checked := 0
	var pitched := 0
	var worst := 0.0
	var worst_at := Vector3.ZERO
	var off: Array[String] = []
	for mm in range(inside, stand, SAMPLE_MM * 4):
		var dir := LandsideDefinition.heading_at(path, mm)
		var pose := LandsideViews.on_path(path, mm, dir, _axles)
		pitched += int(absf(pose.basis.z.y) > 0.05)
		for axle in [_axles.x, _axles.y]:
			var wheel := pose * Vector3(0.0, 0.0, axle)
			var gap := _map.gap(wheel)
			checked += 1
			if not is_nan(gap) and absf(gap) > absf(worst):
				worst = gap
				worst_at = wheel
			if not is_nan(gap) and absf(gap) > LandsideSurfaceMap.ON:
				off.append("%s gap %.3f" % [wheel, gap])
	print(
		(
			"ramp wheels checked %d, pitched %d, worst %.3f at %s, off %d: %s"
			% [checked, pitched, worst, worst_at, off.size(), off.slice(0, 6)]
		)
	)
	assert_array(off).is_empty()
	assert_float(LandsideDefinition.point_at(path, stand).y).is_greater(10.0)
	assert_int(pitched).is_greater(40)


## On the way out: from the entrance down the way-out ramp to the exit lane, a
## car leaving a ground-floor and a first-deck slot, and one turning round at
## the gate, then along the exit lane over the sidewalk to the far carriageway,
## has both wheels on the surface. On the exit lane's first metres its rear
## wheels are still on the ramp (LandsidePaths.lead_in()).
func test_a_car_on_the_way_out_has_both_wheels_on_the_surface() -> void:
	var found := _way_out_off(_paths.lead_in(LandsideVehicle.Lane.LOT_EXIT, 1))
	print(
		(
			"way out: checked %d, pitched %d, off %s"
			% [found["checked"], found["pitched"], found["off"]]
		)
	)
	assert_array(found["off"]).is_empty()
	assert_int(found["checked"]).is_greater(300)
	# A control: the car did pitch on the way down and over the sidewalk.
	assert_int(found["pitched"]).is_greater(40)


## The control for the check: the exit lane's start with no way in behind it (a
## rear wheel held at the lane's start height while it is still on the ramp, as
## before the fix round) is found sunk into the ramp.
func test_a_car_starting_the_exit_lane_with_no_way_in_is_found_sunk() -> void:
	var found := _way_out_off(PackedVector3Array())
	print("way out, no way in: %d off, first %s" % [found["off"].size(), found["off"].slice(0, 2)])
	assert_int(found["off"].size()).is_greater_equal(3)


## Every SAMPLE_MM of the way out, both wheels against the surface; the exit
## lane is drawn with `lead` behind its start.
func _way_out_off(lead: PackedVector3Array) -> Dictionary:
	var legs: Array = []
	for path: PackedVector3Array in [
		_paths.slot_path[1][0], _paths.slot_path[1][9], _paths.turn_path[1]
	]:
		var from := LandsideDefinition.mm_along(path, _spot.way_out[1])
		legs.append([path, from, LandsideDefinition.length_mm(path), PackedVector3Array()])
	var exit := _spot.exit
	legs.append([exit, 0, LandsideDefinition.mm_along(exit, Vector3(6.5, ROAD_Y, -45.0)), lead])
	var off: Array[String] = []
	var checked := 0
	var pitched := 0
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
				if not is_nan(gap) and absf(gap) > LandsideSurfaceMap.ON:
					off.append("%s gap %.3f" % [wheel, gap])
	return {"off": off, "checked": checked, "pitched": pitched}


## A ground-floor passenger's walk from the gate to the far side of the road is
## on paving all the way: the apron, the sidewalk, then the road.
func test_a_ground_floor_walk_stays_on_paving_from_the_gate_to_the_crossing() -> void:
	var walk := _paths.lot_walk(1, 0)
	var gate := walk.find(_spot.access[_spot.access.size() - 1])
	assert_int(gate).is_greater(0)
	var route := PackedVector3Array(walk.slice(gate))
	var found := _walk_off_paving(route)
	print("walk %d points from the gate: %s" % [route.size(), found])
	assert_array(found["off"]).is_empty()
	assert_int(found["sidewalk"]).is_greater_equal(100)
	# It reaches the road and crosses it.
	assert_float(route[route.size() - 1].z).is_less(-58.0)


## The control: the walk as it was, from the gate straight to (-6, 0.1, -36),
## is found over the lawn.
func test_the_old_walk_from_the_gate_over_the_lawn_is_found_off_paving() -> void:
	var old := PackedVector3Array(
		[
			_spot.access[_spot.access.size() - 1],
			Vector3(-6, 0.1, -36),
			Vector3(-6, 0.1, -39.5),
			Vector3(-6, 0.1, -60.5)
		]
	)
	var found := _walk_off_paving(old)
	print("old walk: %d off, first %s" % [found["off"].size(), found["off"].slice(0, 2)])
	assert_int(found["off"].size()).is_greater_equal(50)


## Board 00291df0 point 3: the planter bed on the sidewalk west of the car park
## (the site Road mesh raised up to 0.26 m over x -4..-3, z -41..-40) is never
## under a ground-floor walker's feet or within a walker's radius of them: the
## walk crosses the road east of the bed.
func test_a_ground_floor_walk_keeps_clear_of_the_planter_bed() -> void:
	var walk := _paths.lot_walk(1, 0)
	var gate := walk.find(_spot.access[_spot.access.size() - 1])
	var found := _near_raised(PackedVector3Array(walk.slice(gate)))
	print("walk from the gate: %s" % found)
	assert_array(found["near"]).is_empty()
	# Control: the walk was checked along the sidewalk's top.
	assert_int(found["sidewalk"]).is_greater_equal(60)


## The control: the walk as it was, along the sidewalk to x -6 before crossing,
## is found over the bed's rim.
func test_the_old_walk_past_x_minus_6_is_found_on_the_planter_bed() -> void:
	var old := PackedVector3Array(
		[
			Vector3(2.35, 0.2, -40.05),
			Vector3(-6, 0.2, -40.05),
			Vector3(-6, 0.2, -41.1),
			Vector3(-6, 0.1, -41.4),
		]
	)
	var found := _near_raised(old)
	print("old walk: %d near the bed, first %s" % [found["near"].size(), found["near"].slice(0, 2)])
	assert_int(found["near"].size()).is_greater_equal(10)


## Samples a walk every SAMPLE_MM: the points on the sidewalk's top (not on the
## car park's meshes) where the surface within WALKER_RADIUS of the feet, or under
## them, stands higher than the sidewalk (a planter bed), and how many were checked.
func _near_raised(walk: PackedVector3Array) -> Dictionary:
	var near: Array[String] = []
	var sidewalk := 0
	for mm in range(0, LandsideDefinition.length_mm(walk) + 1, SAMPLE_MM):
		var at := LandsideDefinition.point_at(walk, mm)
		var top := _map.top(at)
		if str(top[1]).begins_with(CAR_PARK_MESH) or absf(at.y - SIDEWALK_Y) > 0.005:
			continue
		sidewalk += 1
		var highest := float(top[0])
		for k in 8:
			var around := at + Vector3(WALKER_RADIUS, 0.0, 0.0).rotated(Vector3.UP, k * PI / 4.0)
			highest = maxf(highest, float(_map.top(around)[0]))
		if highest > SIDEWALK_Y + RAISED:
			near.append("%s %.3f" % [at, highest])
	return {"near": near, "sidewalk": sidewalk}


## Samples a lane every SAMPLE_MM: the points whose height is off the surface,
## and how many were on the sidewalk's top and on the car park's own mesh.
func _lane_off_surface(lane: PackedVector3Array) -> Dictionary:
	var off: Array[String] = []
	var sidewalk := 0
	var lot := 0
	var length := LandsideDefinition.length_mm(lane)
	for mm in range(0, length + 1, SAMPLE_MM):
		var at := LandsideDefinition.point_at(lane, mm)
		var top := _map.top(at)
		var on_lot := str(top[1]).begins_with(CAR_PARK_MESH)
		sidewalk += int(absf(top[0] - SIDEWALK_Y) < 0.005 and not on_lot)
		lot += int(on_lot)
		var gap := _map.gap(at)
		if not is_nan(gap) and absf(gap) > LandsideSurfaceMap.ON:
			off.append("%s gap %.3f" % [at, gap])
	return {"off": off, "sidewalk": sidewalk, "lot": lot}


## Samples a walk every SAMPLE_MM: the points over the lawn or off the surface,
## and how many were on the sidewalk's top.
func _walk_off_paving(walk: PackedVector3Array) -> Dictionary:
	var off: Array[String] = []
	var sidewalk := 0
	var length := LandsideDefinition.length_mm(walk)
	for mm in range(0, length + 1, SAMPLE_MM):
		var at := LandsideDefinition.point_at(walk, mm)
		var top := _map.top(at)
		sidewalk += int(absf(top[0] - SIDEWALK_Y) < 0.005 and absf(at.y - SIDEWALK_Y) < 0.005)
		if top[0] <= LandsideSurfaceMap.LAWN_Y + 0.001:
			off.append("%s over the lawn" % at)
			continue
		var gap := _map.gap(at)
		if not is_nan(gap) and absf(gap) > LandsideSurfaceMap.ON:
			off.append("%s gap %.3f" % [at, gap])
	return {"off": off, "sidewalk": sidewalk}
