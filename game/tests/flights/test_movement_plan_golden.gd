class_name TestMovementPlanGolden
extends GdUnitTestSuite
## With no pause, MovementPlan and FlightPose put a taxiing plane where the old
## FlightPose did, within 1e-4 m and 1e-4 on the nose vector, at every half
## tick. taxi_pose_golden.bin holds the old values: built at commit 7ab97c7,
## before MovementPlan existed, from main.tscn's airside, for TAXI_IN, PUSHBACK
## and TAXI_OUT on every stand layout the airside tests use (the starter stand,
## exit 7 at x 10.5, the four site corners of the peak speed test, and gates A
## and B together). Each route keeps its own points, entry direction and tick
## count, so later airside moves do not change what this pins.

const GOLDEN := "res://tests/flights/taxi_pose_golden.bin"
const TOLERANCE := 1e-4
## Routes and half-tick samples the table was built with: 8 stands x 3 phases,
## each 2 * ticks + 1 samples (600, 120 and 720 ticks).
const ROUTES := 24
const SAMPLES := 23064
## The TAXI_IN and TAXI_OUT samples: 8 x (1201 + 1441).
const HEADINGS := 21136

var _routes: Array = []


func before() -> void:
	var file := FileAccess.open_compressed(GOLDEN, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	assert_object(file).is_not_null()
	var table: Dictionary = file.get_var()
	file.close()
	_routes = table["routes"]


func test_the_table_holds_every_route_and_sample() -> void:
	var samples := 0
	for route: Dictionary in _routes:
		samples += (route["origins"] as PackedVector3Array).size()
	print("golden: %d routes, %d samples" % [_routes.size(), samples])
	assert_int(_routes.size()).is_equal(ROUTES)
	assert_int(samples).is_equal(SAMPLES)


func test_flight_pose_matches_the_old_pose_every_half_tick() -> void:
	var worst_origin := 0.0
	var worst_nose := 0.0
	var checked := 0
	for route: Dictionary in _routes:
		var ticks: int = route["ticks"]
		var origins: PackedVector3Array = route["origins"]
		var noses: PackedVector3Array = route["noses"]
		for k in origins.size():
			var pose := FlightPose.pose(
				route["state"], k / (2.0 * ticks), route["points"], route["entry"]
			)
			worst_origin = maxf(worst_origin, pose.origin.distance_to(origins[k]))
			worst_nose = maxf(worst_nose, pose.basis.z.distance_to(noses[k]))
			checked += 1
	print(
		(
			"FlightPose: %d samples, worst origin %.7f m, worst nose %.7f"
			% [checked, worst_origin, worst_nose]
		)
	)
	assert_int(checked).is_equal(SAMPLES)
	assert_float(worst_origin).is_less_equal(TOLERANCE)
	assert_float(worst_nose).is_less_equal(TOLERANCE)


## The plan itself, in ticks rather than progress: its point, and its heading
## on the routes that do not swing (pushback turns the nose on its own).
func test_a_plan_with_no_pause_matches_the_old_pose_every_half_tick() -> void:
	var worst_origin := 0.0
	var worst_nose := 0.0
	var headings := 0
	for route: Dictionary in _routes:
		var points: PackedVector3Array = route["points"]
		var plan := MovementPlan.taxi(points, route["ticks"])
		var origins: PackedVector3Array = route["origins"]
		var noses: PackedVector3Array = route["noses"]
		for k in origins.size():
			var distance := MovementPlan.distance_at(plan, k * 0.5)
			var at := MovementPlan.position_at(plan, k * 0.5)
			worst_origin = maxf(worst_origin, at.distance_to(origins[k]))
			if route["state"] != FlightSim.State.PUSHBACK:
				var nose := MovementPlan.heading_at(points, distance, route["entry"])
				worst_nose = maxf(worst_nose, nose.distance_to(noses[k]))
				headings += 1
	print(
		(
			"MovementPlan: worst origin %.7f m, worst nose %.7f over %d headings"
			% [worst_origin, worst_nose, headings]
		)
	)
	assert_int(headings).is_equal(HEADINGS)
	assert_float(worst_origin).is_less_equal(TOLERANCE)
	assert_float(worst_nose).is_less_equal(TOLERANCE)
