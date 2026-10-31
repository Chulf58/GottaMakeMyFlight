class_name TestLandsideMultiStoreyRampAndWalk
extends GdUnitTestSuite
## Board ef2fd76d. Part 1 (decision car-park-slab-step-cars-climb-a-ramp-in-the-
## access-lane-data): a car climbs from the road onto the multi-storey's 0.30 m
## slab on ramp points in the access lane, none of them a step. Part 2: a
## passenger who parks on the ground floor walks out through the opening in the
## front wall, never through the wall.

const STARTER := preload("res://landside/starter_landside.tres")
const MULTI_SCENE := preload("res://assets/landside/tc_parking_2a.glb")
## The most a lane climbs between two of its points, and over 0.25 m of
## travel (the clearance test's per-step rise limit for the ground floor).
const MAX_STEP := 0.04
const SAMPLE := 0.25
const EPS := 0.0001
## The road top the lanes are authored on (starter_landside.tres).
const ROAD_Y := 0.1
## The ground-floor front wall's middle line in the asset's own frame, as in
## TestLandsideMultiStoreyClearance.
const FRONT_WALL_Z := -22.55
## Heights over the floor of the lines a walker's path is checked at: a
## wall stands over 1 m, so a line at 1 m meets it anywhere along its length.
const WALL_CHECK_HEIGHT := 1.0

var _spot: LandsideLotSpot
var _paths: LandsidePaths
## World-space triangles [a, b, c] of the walls (faces more than 25 degrees
## off level) with their bounds, and of the level faces.
var _upright := []
var _upright_box: Array[AABB] = []
var _level := []


func before() -> void:
	_spot = STARTER.lots[1]
	_paths = LandsidePaths.new(STARTER)
	var asset: Node3D = MULTI_SCENE.instantiate()
	add_child(asset)
	var at := Transform3D(Basis(), _spot.centre)
	for mi: MeshInstance3D in asset.find_children("*", "MeshInstance3D", true, false):
		var to_world := at * mi.global_transform
		var f := mi.mesh.get_faces()
		for i in range(0, f.size(), 3):
			var a: Vector3 = to_world * f[i]
			var b: Vector3 = to_world * f[i + 1]
			var c: Vector3 = to_world * f[i + 2]
			var n := (b - a).cross(c - a)
			if n.length() < 1e-6:
				continue
			if absf(n.normalized().y) > 0.9:
				_level.append([a, b, c])
			else:
				_upright.append([a, b, c])
				_upright_box.append(AABB(a, Vector3.ZERO).expand(b).expand(c))
	asset.free()


## From the apron's foot, where the lane is back at road height past the
## sidewalk (board 0b82b7e4 gave the lane a bump over the sidewalk, checked
## against the surface in TestLandsideCarParkSurfaces), up to the slab.
func test_the_access_lane_climbs_from_the_road_to_the_slab_in_small_steps() -> void:
	var foot := _spot.access.size() - 1
	while foot > 0 and _spot.access[foot].y > ROAD_Y + EPS:
		foot -= 1
	# A control: the slice starts on the apron, behind the sidewalk, with the
	# whole climb ahead of it.
	assert_float(_spot.access[foot].z).is_greater(-39.0)
	assert_int(_spot.access.size() - foot).is_greater_equal(6)
	_assert_ramp(_spot.access.slice(foot), 1.0, "access")


## The way out mirrors it: the slab's height to the front edge, then down to the
## road in the same steps, so a leaving car never dips under the slab top.
func test_the_way_out_comes_down_from_the_slab_edge_in_small_steps() -> void:
	# From the way out's point at the entrance's first depth (the first point is
	# inside the building) on to the exit lane's first two points.
	var lane := PackedVector3Array(_spot.way_out.slice(1))
	lane.append(_spot.exit[0])
	lane.append(_spot.exit[1])
	_assert_ramp(lane, -1.0, "way out")
	# The exit lane then runs on at road height.
	assert_float(_spot.exit[0].y).is_equal_approx(ROAD_Y, EPS)
	assert_float(_spot.exit[1].y).is_equal_approx(ROAD_Y, EPS)


## Checks a lane over the apron between the slab and the road: `way` +1 climbs
## road to slab, -1 comes down slab to road; no step more than MAX_STEP, per point
## and per 0.25 m of travel, never the wrong way, and at slab height at and past
## the slab's front edge (so no wheel sinks into it).
func _assert_ramp(lane: PackedVector3Array, way: float, what: String) -> void:
	var slab_y := _spot.entrance[0].y
	var road := ROAD_Y if way > 0.0 else lane[lane.size() - 1].y
	var low := lane[0] if way > 0.0 else lane[lane.size() - 1]
	var high := lane[lane.size() - 1] if way > 0.0 else lane[0]
	# The slab's front edge, from the spot's centre and footprint.
	var edge_z := _spot.centre.z - _spot.footprint.y / 2.0
	var slopes := 0
	var worst := 0.0
	for i in range(1, lane.size()):
		var rise := (lane[i].y - lane[i - 1].y) * way
		worst = maxf(worst, absf(rise))
		(
			assert_float(absf(rise))
			. override_failure_message(
				"%s %s to %s rises %.3f m" % [what, lane[i - 1], lane[i], rise]
			)
			. is_less_equal(MAX_STEP + EPS)
		)
		assert_float(rise).is_greater_equal(-EPS)
		if rise > EPS:
			slopes += 1
	# Also per 0.25 m of travel, whatever the spacing of the points.
	var length := LandsideDefinition.length_mm(lane) / 1000.0
	var d := 0.0
	var before_y := lane[0].y
	while d < length:
		d = minf(d + SAMPLE, length)
		var y := LandsideDefinition.point_on(lane, roundi(d * 1000.0)).y
		worst = maxf(worst, absf(y - before_y))
		assert_float(absf(y - before_y)).is_less_equal(MAX_STEP + EPS)
		before_y = y
	print(
		(
			"%s %d points, %d sloping, worst step %.3f m, %.2f -> %.2f, slab edge z %.2f"
			% [what, lane.size(), slopes, worst, lane[0].y, lane[lane.size() - 1].y, edge_z]
		)
	)
	# A control: the lane does slope, the whole way between road and slab.
	assert_float(low.y).is_equal_approx(road, EPS)
	assert_float(high.y).is_equal_approx(slab_y, EPS)
	assert_float(slab_y - road).is_greater(2.0 * MAX_STEP)
	assert_int(slopes).is_greater_equal(ceili((slab_y - road) / MAX_STEP - EPS))
	for point in lane:
		if point.z >= edge_z:
			assert_float(point.y).is_equal_approx(slab_y, EPS)


func test_a_ground_floor_walk_leaves_through_the_opening_not_the_front_wall() -> void:
	var wall_z := _spot.centre.z + FRONT_WALL_Z
	var gate := _spot.access[_spot.access.size() - 1]
	# The opening: the run of x with no wall top over 1 m above the floor,
	# around the gate, scanned on the asset as the clearance test does.
	var lo := gate.x
	var hi := gate.x
	assert_bool(_wall_at(gate.x, wall_z)).is_false()
	while lo > _spot.centre.x - 12.0 and not _wall_at(lo - 0.05, wall_z):
		lo -= 0.05
	while hi < _spot.centre.x + 12.0 and not _wall_at(hi + 0.05, wall_z):
		hi += 0.05
	assert_bool(_wall_at(lo - 0.1, wall_z)).is_true()
	assert_bool(_wall_at(hi + 0.1, wall_z)).is_true()
	var walks := 0
	var crossings := 0
	var lines := 0
	for slot in _spot.slots.size():
		if LandsidePaths.deck_of(_spot, _spot.slots[slot]) != 0:
			continue
		walks += 1
		var walk := _paths.lot_walk(1, slot)
		var crossed := 0
		for i in range(1, walk.size()):
			var a := walk[i - 1]
			var b := walk[i]
			if (a.z - wall_z) * (b.z - wall_z) < 0.0:
				var x := a.x + (b.x - a.x) * (wall_z - a.z) / (b.z - a.z)
				(
					assert_float(x)
					. override_failure_message(
						"slot %d: walk crosses the wall at x %.2f" % [slot, x]
					)
					. is_between(lo + 0.1, hi - 0.1)
				)
				crossed += 1
			lines += _assert_wall_clear(a, b, "slot %d walk" % slot)
		# It goes through the wall line once, out, and ends past the gate.
		assert_int(crossed).is_equal(1)
		crossings += crossed
		assert_float(walk[walk.size() - 1].z).is_less(gate.z)
	# A control: the straight line from a ground-floor slot to the gate (the old
	# walk) does meet the wall, so the check is able to see it.
	var straight_x := _spot.slots[0].x + (gate.x - _spot.slots[0].x) * _wall_fraction(0, gate)
	assert_bool(straight_x < lo + 0.1 or straight_x > hi - 0.1).is_true()
	(
		assert_int(
			_assert_wall_hit(_spot.slots[0] + Vector3.UP * WALL_CHECK_HEIGHT, gate + Vector3.UP)
		)
		. is_equal(1)
	)
	print(
		(
			"opening x %.2f..%.2f at wall z %.2f, walks %d, crossings %d, wall lines %d"
			% [lo, hi, wall_z, walks, crossings, lines]
		)
	)
	assert_int(walks).is_equal(9)
	assert_int(crossings).is_equal(walks)
	assert_int(lines).is_greater(walks * 3)


## Where along the straight line from slot `slot` to `gate` it meets the wall
## line, as a fraction of the way.
func _wall_fraction(slot: int, gate: Vector3) -> float:
	var wall_z := _spot.centre.z + FRONT_WALL_Z
	var from := _spot.slots[slot]
	return (wall_z - from.z) / (gate.z - from.z)


## 1 after checking that no wall face crosses the walker's line at 1 m, from
## `a` to `b` (at floor height).
func _assert_wall_clear(a: Vector3, b: Vector3, what: String) -> int:
	var up := Vector3.UP * WALL_CHECK_HEIGHT
	var hit: Variant = _first_wall_hit(a + up, b + up)
	(
		assert_bool(hit == null)
		. override_failure_message("%s: %s to %s meets a wall at %s" % [what, a, b, hit])
		. is_true()
	)
	return 1


## 1 if a wall face crosses the line from `a` to `b`, else 0 (the control).
func _assert_wall_hit(a: Vector3, b: Vector3) -> int:
	return int(_first_wall_hit(a, b) != null)


func _first_wall_hit(a: Vector3, b: Vector3) -> Variant:
	var box := AABB(a, Vector3.ZERO).expand(b).grow(0.01)
	for i in _upright.size():
		if not box.intersects(_upright_box[i]):
			continue
		var tri: Array = _upright[i]
		var hit: Variant = Geometry3D.segment_intersects_triangle(a, b, tri[0], tri[1], tri[2])
		if hit != null:
			return hit
	return null


## Whether a wall top stands at (x, z): a level face over 1 m above the ground
## floor and under the first deck.
func _wall_at(x: float, z: float) -> bool:
	var at := Vector3(x, 0.0, z)
	for face in _level:
		var y := TestLandsideGeometry._height_on(face, at)
		if not is_nan(y) and y > 1.3 and y < 4.0:
			return true
	return false
