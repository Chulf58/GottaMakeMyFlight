class_name TestApronStandSide
extends GdUnitTestSuite
## ApronStand with west and east stands (slice S3 of design airside-all-
## around-technical-design-one-route-source-per-con): the guard on a plane
## taxiing out is cut by how far it is along its planned route, in the stand's
## own frame, so at a west stand it lets go of the parked spot that a world z
## cut would keep; and a saved side stand keeps its side through JSON.

const SITE := preload("res://build/terminal_site.tres")
const NORTH := {"exit": 2, "x": -22.5, "wall_z": -98.0}
## 186 m east of the west lane, as NORTH is 186 m south of the taxi lane.
const WEST_SILL := Vector2(62.0, -150.0)
const EPS := 0.0001


static func _west() -> Dictionary:
	return StandPlacement.make(2, WEST_SILL.x, WEST_SILL.y, StandPlacement.WEST)


static func _way_out(stand: Dictionary) -> PackedVector3Array:
	return PackedVector3Array([StandPlacement.pushback_end(stand), StandPlacement.lane_join(stand)])


static func _holds(rects: Array[Rect2], point: Vector3) -> bool:
	return rects.any(func(rect: Rect2) -> bool: return rect.has_point(Vector2(point.x, point.z)))


## The old cut: keep what lies north of the tail's world z.
static func _world_z_cut(rects: Array[Rect2], north_of: float) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for rect in rects:
		var south := minf(rect.end.y, north_of)
		if south > rect.position.y:
			out.append(
				Rect2(rect.position.x, rect.position.y, rect.size.x, south - rect.position.y)
			)
	return out


## At a north stand the route cut is the world z cut it always was, value for
## value.
func test_a_north_stand_s_guard_is_the_world_z_cut_it_was() -> void:
	var path := _way_out(NORTH)
	for t in [0.0, 0.3, 0.7, 1.0]:
		var at := FlightPose.point_at(path, FlightPose.path_length(path) * t)
		var want := StandPlacement.swept_rects(NORTH, at.z + StandPlacement.TAIL_M)
		assert_array(ApronStand.route_rects(NORTH, path, t)).is_equal(want)


## Halfway out of a west stand the plane has gone 70 m west along z -146.5.
## The route cut has let go of the parked spot and still holds the plane; the
## world z cut keeps the parked spot, as the way runs along z, not north.
func test_a_west_stand_s_guard_follows_the_route_where_world_z_would_not() -> void:
	var stand := _west()
	var path := _way_out(stand)
	var t := 0.5
	var at := FlightPose.point_at(path, FlightPose.path_length(path) * t)
	var spot := StandPlacement.stand_point(stand)
	var got := ApronStand.route_rects(stand, path, t)
	var by_z := _world_z_cut(StandPlacement.swept_rects(stand), at.z + StandPlacement.TAIL_M)
	print("plane at %s, spot %s\nroute cut %s\nworld z cut %s" % [at, spot, got, by_z])
	assert_float(at.z).is_equal_approx(spot.z, EPS)
	assert_float(spot.x - at.x).is_greater(20.0)
	assert_bool(_holds(got, at)).is_true()
	assert_bool(_holds(got, spot)).is_false()
	assert_bool(_holds(by_z, spot)).is_true()
	# The north stand at the same distance from its lane, turned: (x, z) from
	# its sill goes to (z, -x) from the west sill.
	var north := ApronStand.route_rects(NORTH, _way_out(NORTH), t)
	assert_int(got.size()).is_equal(north.size())
	for i in north.size():
		var a := north[i].position - Vector2(NORTH["x"], NORTH["wall_z"])
		var b := north[i].end - Vector2(NORTH["x"], NORTH["wall_z"])
		var turned := Rect2(WEST_SILL + Vector2(a.y, -a.x), Vector2.ZERO)
		turned = turned.expand(WEST_SILL + Vector2(b.y, -b.x))
		assert_vector(got[i].position).is_equal_approx(turned.position, Vector2.ONE * EPS)
		assert_vector(got[i].size).is_equal_approx(turned.size, Vector2.ONE * EPS)


func test_saved_side_stands_keep_their_side_through_json() -> void:
	var west := _west()
	var east := StandPlacement.make(5, -62.0, -150.0, StandPlacement.EAST)
	var saved := {"stands": {"A": west, "B": east, "C": NORTH}}
	var data: Dictionary = JSON.parse_string(JSON.stringify(saved))
	var loaded := ApronStand.checked(data, SITE)
	print("loaded %s" % [loaded])
	assert_dict(loaded).not_contains_keys(["error"])
	assert_dict(loaded["stands"]["A"]).is_equal(west)
	assert_dict(loaded["stands"]["B"]).is_equal(east)
	assert_dict(loaded["stands"]["C"]).is_equal(NORTH)
	var one := ApronStand.checked(JSON.parse_string(JSON.stringify({"live": east})), SITE)
	assert_dict(one["live"]).is_equal(east)
	data["stands"]["A"]["side"] = "S"
	assert_dict(ApronStand.checked(data, SITE)).contains_keys(["error"])
