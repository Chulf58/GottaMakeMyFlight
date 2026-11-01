class_name TestSharedGroundHolds
extends GdUnitTestSuite
## The shared RUNWAY and LANE reservations (decision gates-technical-design-
## gate-desks-link-to-north-exits-one-st, point 4) cover every tick any part of
## an aircraft is on them. The plane's footprint (StandPlacement's rectangle:
## nose, tail and wingtips about its origin) is posed exactly as PlaneView
## draws it, every half tick from APPROACH to DEPARTED, for stands across the
## whole site, and compared with StandPlacement.runway_zone() and lane_zone().
## Every occupied sample must fall inside one of the flight's holds on that
## zone (FlightTimetable.flight_holds). The measured first and last ticks are
## printed beside the holds, and the phase-boundary cuts the design rejected
## are shown to be short.

const MAIN_SCENE := "res://main/main.tscn"
const SITE := preload("res://build/terminal_site.tres")
const FIRST := 3000
## Grid columns between sampled door lines; both edge columns are always in.
const COLUMN_STEP := 6
## Site wall rows sampled, from the north row (the deepest stand) to the
## southmost.
const ROWS: Array[int] = [0, 1, 2, 4, 9, 20, 45, 90, 149]
## An overlap smaller than this (m²) is two shapes sharing an edge, not a plane
## on the zone: a plane on the runway has its wingtips on the lane zone's edge,
## and single-precision poses put them up to a few hundredths of a millimetre
## over it. 0.01 m² is 0.3 mm along the plane's whole length.
const TOUCH_M2 := 0.01

var _airside: Airside
var _view: PlaneView
var _grid: BuildGrid


func before() -> void:
	_airside = scene_airside()
	add_child(_airside)
	_view = PlaneView.new()
	_view.airside = _airside
	_grid = BuildGrid.new(SITE.grid_size, SITE.grid_origin)


func after() -> void:
	_view.free()
	_airside.free()


## main.tscn's Airside markers and links, built from the saved scene state
## without instantiating the scene.
static func scene_airside() -> Airside:
	var state: SceneState = (load(MAIN_SCENE) as PackedScene).get_state()
	var airside := Airside.new()
	for i in state.get_node_count():
		var props := {}
		for k in state.get_node_property_count(i):
			props[state.get_node_property_name(i, k)] = state.get_node_property_value(i, k)
		var parent := String(state.get_node_path(i, true))
		if parent == "./Airside" and state.get_node_type(i) == &"Marker3D":
			var marker := Marker3D.new()
			marker.name = state.get_node_name(i)
			marker.transform = props.get(&"transform", Transform3D.IDENTITY)
			airside.add_child(marker)
		elif String(state.get_node_path(i)) == "./Airside":
			airside.links = props[&"links"]
	return airside


## The plane's plan-view rectangle at `pose`: nose NOSE_M ahead, tail TAIL_M
## behind, wingtips HALF_SPAN_M out, turned to its heading.
static func footprint(pose: Transform3D) -> PackedVector2Array:
	var nose := Vector2(pose.basis.z.x, pose.basis.z.z).normalized()
	var side := Vector2(nose.y, -nose.x)
	var at := Vector2(pose.origin.x, pose.origin.z)
	var ahead := nose * StandPlacement.NOSE_M
	var behind := -nose * StandPlacement.TAIL_M
	var out := side * StandPlacement.HALF_SPAN_M
	return PackedVector2Array(
		[at + ahead + out, at + ahead - out, at + behind - out, at + behind + out]
	)


static func on_zone(shape: PackedVector2Array, zone: Rect2) -> bool:
	var box := Rect2(shape[0], Vector2.ZERO)
	for point in shape:
		box = box.expand(point)
	if not box.intersects(zone):
		return false
	var low := zone.position
	var high := zone.end
	var square := PackedVector2Array([low, Vector2(high.x, low.y), high, Vector2(low.x, high.y)])
	var area := 0.0
	for piece: PackedVector2Array in Geometry2D.intersect_polygons(shape, square):
		area += absf(_area(piece))
	return area > TOUCH_M2


static func _area(points: PackedVector2Array) -> float:
	var twice := 0.0
	for i in points.size():
		twice += points[i].cross(points[(i + 1) % points.size()])
	return twice / 2.0


static func held(holds: Array, zone: String, tick: int) -> bool:
	for hold in holds:
		if hold[0] == zone and hold[1] <= tick and tick < hold[2]:
			return true
	return false


## Door lines across the site (every COLUMN_STEP-th column and both edges),
## plus the two that put the stand on TaxiWest's and TaxiEast's x: the
## shortest taxi out and in any stand can have, which are the latest the
## arrival leaves the runway and the earliest the departure reaches it. With
## those the bounds hold however wide the site grows.
func _door_xs() -> Array[float]:
	var xs: Array[float] = []
	for column in range(0, SITE.grid_size.x, COLUMN_STEP):
		xs.append(SITE.grid_origin.x + column + 0.5)
	xs.append(SITE.grid_origin.x + SITE.grid_size.x - 0.5)
	for waypoint in [&"TaxiWest", &"TaxiEast"]:
		xs.append(_airside.graph.position_of(waypoint).x + StandPlacement.DOOR_SIDE_M)
	return xs


## Wall lines: the site's ROWS, the north row first.
func _wall_zs() -> Array[float]:
	var zs: Array[float] = []
	for row in ROWS:
		zs.append(SITE.grid_origin.z + row)
	return zs


## Every half tick from APPROACH to DEPARTED; the three parked states hold one
## pose, so each is sampled at its first and last half tick only.
static func sample_times(starts: Array[int]) -> Array[float]:
	var parked := [FlightSim.State.AT_STAND, FlightSim.State.BOARDING, FlightSim.State.DOORS_CLOSED]
	var times: Array[float] = []
	for state in range(FlightSim.State.APPROACH, FlightSim.State.DEPARTED):
		var start := starts[state]
		var end := starts[state + 1]
		if parked.has(state):
			times.append_array([float(start), end - 0.5])
			continue
		for half in range(2 * start, 2 * end):
			times.append(half / 2.0)
	return times


func test_the_shared_zones_sit_on_the_scene_runway_and_taxi_lane() -> void:
	var runway := StandPlacement.runway_zone()
	var lane := StandPlacement.lane_zone()
	print("runway zone %s, lane zone %s" % [runway, lane])
	for waypoint in [&"Touchdown", &"RunwayExit", &"RunwayEntry", &"Liftoff"]:
		var at := _airside.graph.position_of(waypoint)
		assert_float(at.z).is_equal(StandPlacement.RUNWAY_Z)
		assert_bool(runway.has_point(Vector2(at.x, at.z))).is_true()
	for waypoint in [&"TaxiEast", &"TaxiWest"]:
		var at := _airside.graph.position_of(waypoint)
		assert_bool(lane.has_point(Vector2(at.x, at.z))).is_true()
	# The lane reaches from the runway band to the band lane traffic sweeps.
	assert_float(lane.position.y).is_equal_approx(runway.end.y, 0.001)
	assert_float(lane.end.y).is_equal_approx(
		StandPlacement.TAXI_LANE_Z + StandPlacement.HALF_SPAN_M, 0.001
	)


## A plane parked on the site's north row keeps its tail 0.05 m clear of the
## lane traffic's band (StandPlacement.NOSE_GAP_M 2.2 m), so it does not hold
## the lane for its turnaround. Control: at the old 2.3 m gap its tail reached
## 0.05 m into the band.
func test_the_north_row_parked_tail_clears_the_lane() -> void:
	var north := StandPlacement.make(1, 0.5, SITE.grid_origin.z)
	var at := StandPlacement.stand_point(north)
	var old := at + Vector3(0.0, 0.0, StandPlacement.NOSE_GAP_M - 2.3)
	var edge := StandPlacement.lane_zone().end.y
	var tail := at.z - StandPlacement.TAIL_M
	print(
		(
			"north row tail z %.3f (old gap %.3f), lane band edge z %.3f, clearance %.3f m"
			% [tail, old.z - StandPlacement.TAIL_M, edge, tail - edge]
		)
	)
	var lane := StandPlacement.lane_zone()
	assert_bool(on_zone(footprint(Transform3D(Basis.IDENTITY, at)), lane)).is_false()
	assert_bool(StandPlacement.clears_lane(north)).is_true()
	assert_float(tail - edge).is_between(0.04, 0.06)
	assert_bool(on_zone(footprint(Transform3D(Basis.IDENTITY, old)), lane)).is_true()


func test_the_holds_cover_every_tick_the_footprint_is_on_the_runway_or_lane() -> void:
	var starts := FlightSim.schedule_starts(FIRST)
	var holds := FlightTimetable.flight_holds(starts)
	var zones := {
		FlightTimetable.RUNWAY: StandPlacement.runway_zone(),
		FlightTimetable.LANE: StandPlacement.lane_zone(),
	}
	var times := sample_times(starts)
	var push := starts[FlightSim.State.PUSHBACK]
	# [zone, arrival?] -> [first tick, last tick] over every stand.
	var seen := {}
	var stands := 0
	var occupied := 0
	var uncovered: Array[String] = []
	for door_x in _door_xs():
		for wall_z in _wall_zs():
			var stand := StandPlacement.make(1, door_x, wall_z)
			assert_bool(StandPlacement.clears_lane(stand)).is_true()
			assert_bool(_airside.set_stand(stand)).is_true()
			stands += 1
			for time in times:
				var shape := footprint(_view.pose_at(starts, time)["transform"])
				var tick := floori(time)
				for zone: String in zones:
					if not on_zone(shape, zones[zone]):
						continue
					occupied += 1
					var key := [zone, tick < push]
					var span: Array = seen.get(key, [tick, tick])
					seen[key] = [mini(span[0], tick), maxi(span[1], tick)]
					if not held(holds, zone, tick) and uncovered.size() < 10:
						uncovered.append("%s at tick %d, stand %s" % [zone, tick, stand])
	_print_measured(starts, holds, seen)
	print("%d stands, %d samples, %d on a zone" % [stands, stands * times.size(), occupied])
	print("uncovered: %s" % [uncovered])
	assert_int(stands).is_greater(100)
	assert_int(occupied).is_greater(1000)
	for key in [
		[FlightTimetable.RUNWAY, true],
		[FlightTimetable.LANE, true],
		[FlightTimetable.LANE, false],
		[FlightTimetable.RUNWAY, false]
	]:
		assert_bool(seen.has(key)).override_failure_message("never on %s" % [key]).is_true()
	assert_array(uncovered).is_empty()
	# The cuts at phase boundaries the design rejected are short: the arriving
	# plane is still on the runway after TAXI_IN starts, and the departing one
	# is on the lane before TAXI_OUT + 120.
	var taxi_in := starts[FlightSim.State.TAXI_IN]
	var taxi_out := starts[FlightSim.State.TAXI_OUT]
	assert_int(seen[[FlightTimetable.RUNWAY, true]][1]).is_greater_equal(taxi_in)
	assert_int(seen[[FlightTimetable.LANE, false]][0]).is_less(taxi_out + 120)


func _print_measured(starts: Array[int], holds: Array, seen: Dictionary) -> void:
	var names := FlightSim.State.keys()
	for key: Array in seen:
		var span: Array = seen[key]
		print(
			(
				"%s %s: on it from tick %d (%s+%d) to %d (%s+%d)"
				% [
					key[0],
					"arrival" if key[1] else "departure",
					span[0],
					names[FlightTimetable.state_at(starts, span[0])],
					span[0] - starts[FlightTimetable.state_at(starts, span[0])],
					span[1],
					names[FlightTimetable.state_at(starts, span[1])],
					span[1] - starts[FlightTimetable.state_at(starts, span[1])],
				]
			)
		)
	for hold in holds:
		print(
			(
				"hold %s [%d (%s+%d), %d (%s+%d))"
				% [
					hold[0],
					hold[1],
					names[FlightTimetable.state_at(starts, hold[1])],
					hold[1] - starts[FlightTimetable.state_at(starts, hold[1])],
					hold[2],
					names[FlightTimetable.state_at(starts, hold[2])],
					hold[2] - starts[FlightTimetable.state_at(starts, hold[2])],
				]
			)
		)
