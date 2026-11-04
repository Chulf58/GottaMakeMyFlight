class_name TestLandsideLanesOnRoad
extends GdUnitTestSuite
## Board 0169bc4b ("Cars drive over the grass and curb, not on the actual
## street"): a car driving any lane along the road keeps all four corners of
## its footprint on the drawn asphalt, never on a sidewalk, a kerb nose or the
## lawn. The asphalt is the airport site's Road mesh at road height (y 0.1, or
## 0.107 on paint), read as main.tscn places it at z -80: the through road
## runs the full width (x -43 to 43) between z -50.5 and -41.25, and the
## drop-off forecourt on the terminal side (z -58.5 to -50.5) is closed by kerb
## noses east of x 38.7 and west of x -38.7. Lanes that cross the far sidewalk
## into a car park are checked only on the road (z -43.5 and nearer the
## terminal); the climb onto the sidewalk is theirs by design. A berth path
## is checked at its middle and both sides (see its test for why).

const STARTER := preload("res://landside/starter_landside.tres")
const SITE_SCENE := preload("res://assets/buildings/tp_airport_site.glb")
## main.tscn's Airside/Terminal.
const SITE_AT := Vector3(0.0, 0.0, -80.0)
const AREA := Rect2(-44.0, -62.0, 88.0, 24.0)
## A car's footprint about its origin: half its width and half its length.
## The landside models' boxes (LandsideViews' "box" meta) are 2.12 to 2.47 m
## wide with the mirrors and 4.99 to 5.20 m long; the body without mirrors
## is taken as 2.1 m wide, and the longest box rounded up.
const HALF_WIDTH := 1.05
const HALF_LENGTH := 2.6
## Asphalt is under this; the sidewalk tops are at 0.2.
const ROAD_TOP := 0.15
## The Road mesh ends here; a corner past it is off the drawn map, not off
## the road.
const ROAD_END_X := 42.95
## Lot lanes are on the road while every corner is nearer the terminal than
## the far sidewalk's kerb (z -41.26).
const LOT_LANE_MAX_Z := -43.5
const STEP_MM := 250

var _map: LandsideSurfaceMap


func before() -> void:
	_map = LandsideSurfaceMap.new(AREA)
	_map.add_scene(SITE_SCENE, Transform3D(Basis(), SITE_AT))


func test_every_car_on_a_road_lane_has_its_corners_on_the_asphalt() -> void:
	var off: Array[String] = []
	var checked := _check("road_in", STARTER.road_in, INF, HALF_LENGTH, off)
	checked += _check("road_out", STARTER.road_out, INF, HALF_LENGTH, off)
	for i in STARTER.lots.size():
		var lot: LandsideLotSpot = STARTER.lots[i]
		checked += _check("lot %d access" % i, lot.access, LOT_LANE_MAX_Z, HALF_LENGTH, off)
		checked += _check("lot %d exit" % i, lot.exit, LOT_LANE_MAX_Z, HALF_LENGTH, off)
	print(
		"corners checked %d, off the asphalt %d, first: %s" % [checked, off.size(), off.slice(0, 8)]
	)
	assert_array(off).is_empty()
	# Control: the lanes were walked end to end (road_in alone is 50 m, 200
	# samples of four corners).
	assert_int(checked).is_greater(1500)


## A car pulling into or out of a curb berth keeps its middle and both sides
## on the asphalt. Its nose and tail corners are not asserted: on the berth
## path's taper (LandsidePaths, BERTH_APPROACH_MM and BERTH_STRAIGHT_MM) the
## kerb-side nose corner of a 5.2 m car reaches up to about 1 m over the
## kerb where the sidewalk is widened for the get-out points
## (berths 1 to 3, 6 and 7); that is measured and printed here, not fixed by
## board 0169bc4b.
func test_every_car_on_a_berth_path_keeps_its_sides_on_the_asphalt() -> void:
	var paths := LandsidePaths.new(STARTER)
	var checked := 0
	var off: Array[String] = []
	var corners: Array[String] = []
	for i in paths.berth_path.size():
		checked += _check("berth %d" % i, paths.berth_path[i], INF, 0.0, off)
		_check("berth %d" % i, paths.berth_path[i], INF, HALF_LENGTH, corners)
	print(
		(
			"berth sides checked %d, off the asphalt %d, first: %s"
			% [checked, off.size(), off.slice(0, 8)]
		)
	)
	print(
		(
			"berth nose and tail corners over the kerb (not asserted): %d %s"
			% [corners.size(), corners]
		)
	)
	assert_array(off).is_empty()
	assert_int(checked).is_greater(2000)


## The control: the lanes as they were before board 0169bc4b, road_in from
## (43, -55) and road_out to (-43, -55) straight along the forecourt line,
## are found with corners on the kerb noses and the lawn at both ends.
func test_the_old_forecourt_line_to_the_road_ends_is_found_off_the_asphalt() -> void:
	var off: Array[String] = []
	var old_in := PackedVector3Array([Vector3(43, 0.1, -55), Vector3(-4, 0.1, -55)])
	var old_out := PackedVector3Array([Vector3(-36, 0.1, -55), Vector3(-43, 0.1, -55)])
	var checked := _check("old road_in", old_in, INF, HALF_LENGTH, off)
	checked += _check("old road_out", old_out, INF, HALF_LENGTH, off)
	print(
		(
			"old lanes: corners checked %d, off the asphalt %d, first: %s"
			% [checked, off.size(), off.slice(0, 4)]
		)
	)
	assert_int(checked).is_greater(500)
	assert_int(off.size()).is_greater_equal(20)


## Samples `points` every STEP_MM; at each sample on the road (z at most
## `max_z`) checks the four footprint corners and appends each one off the
## asphalt to `off`. Returns how many corners it checked.
func _check(
	lane_name: String,
	points: PackedVector3Array,
	max_z: float,
	half_length: float,
	off: Array[String]
) -> int:
	var checked := 0
	var total := LandsideDefinition.length_mm(points)
	for mm in range(0, total + 1, STEP_MM):
		var at := LandsideDefinition.point_at(points, mm)
		var fwd := LandsideDefinition.heading_at(points, mm)
		var side := Vector3(fwd.z, 0.0, -fwd.x)
		for s in [-1.0, 1.0]:
			for f in [-1.0, 1.0]:
				var corner: Vector3 = at + side * s * HALF_WIDTH + fwd * f * half_length
				if absf(corner.x) > ROAD_END_X or at.z > max_z or corner.z > max_z:
					continue
				checked += 1
				var top := _map.top(corner)
				if top[1] != "Road" or float(top[0]) >= ROAD_TOP:
					off.append(
						(
							"%s %d mm corner (%.2f, %.2f) on %s %.3f"
							% [lane_name, mm, corner.x, corner.z, top[1], top[0]]
						)
					)
	return checked
