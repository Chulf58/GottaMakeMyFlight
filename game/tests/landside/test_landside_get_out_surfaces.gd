class_name TestLandsideGetOutSurfaces
extends GdUnitTestSuite
## Board 00291df0 point 2: a passenger who gets out at a curb berth stands on
## the surface drawn there, never sunk into it. The far sidewalk is widened (its
## top 0.2 m, 0.1 m over the road) in front of curb bay 2 and the starter curb's
## west berths, so their get-out points are on its top; the others are on the
## road-level lay-by. The surfaces are read from the airport site's meshes as
## main.tscn places them (its Road mesh carries the road and both sidewalks) at z
## -80. Where there is none, the lawn is at y -0.1.

const STARTER := preload("res://landside/starter_landside.tres")
const SITE_SCENE := preload("res://assets/buildings/tp_airport_site.glb")
## main.tscn's Airside/Terminal.
const SITE_AT := Vector3(0.0, 0.0, -80.0)
const SIDEWALK_Y := 0.2
## The part of the map the meshes are read for (x and z): the whole kerb.
const AREA := Rect2(-43.0, -62.0, 86.0, 8.0)

var _map: LandsideSurfaceMap


func before() -> void:
	_map = LandsideSurfaceMap.new(AREA)
	_map.add_scene(SITE_SCENE, Transform3D(Basis(), SITE_AT))


## Every berth's get-out point, the starter curb's and each curb spot's, stands on
## the surface under it, not the lawn.
func test_every_get_out_point_stands_on_the_surface_under_it() -> void:
	var off: Array[String] = []
	var on_sidewalk := 0
	for i in STARTER.berth_count():
		var at := STARTER.berth_get_out(i)
		var top := _map.top(at)
		var gap := _map.gap(at)
		print("berth %d get out %s: surface %s, gap %.3f" % [i, at, top, gap])
		on_sidewalk += int(absf(float(top[0]) - SIDEWALK_Y) < 0.005)
		if top[1] == LandsideSurfaceMap.LAWN or is_nan(gap) or absf(gap) > LandsideSurfaceMap.ON:
			off.append("berth %d %s gap %.3f" % [i, at, gap])
	assert_array(off).is_empty()
	# Controls: every berth was checked, and some stood on the sidewalk's top.
	assert_int(STARTER.berth_count()).is_equal(8)
	assert_int(on_sidewalk).is_greater_equal(2)


## Curb bay 2 (curb spot 1) in particular: both its passengers get out on the
## sidewalk's top.
func test_curb_bay_2_passengers_get_out_on_the_sidewalk_top() -> void:
	var bay: LandsideCurbSpot = STARTER.curb_spots[1]
	for at in bay.get_out:
		var top := _map.top(at)
		print("bay 2 get out %s: surface %s" % [at, top])
		assert_float(float(top[0])).is_equal_approx(SIDEWALK_Y, 0.005)
		assert_float(at.y).is_equal_approx(float(top[0]), LandsideSurfaceMap.ON)


## The control: a get-out point at road height there, as it was, is found sunk
## 0.1 m into the sidewalk.
func test_a_get_out_at_road_height_on_the_sidewalk_is_found_sunk() -> void:
	var old := Vector3(16.75, 0.1, -59.4)
	var gap := _map.gap(old)
	print("old bay 2 get out %s: gap %.3f" % [old, gap])
	assert_float(gap).is_less(-0.09)
