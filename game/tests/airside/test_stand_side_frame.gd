class_name TestStandSideFrame
extends GdUnitTestSuite
## Stands on west and east walls (StandPlacement's side frame; decision
## airside-all-around-technical-design-one-route-source-per-con, slice S3): a
## west or east stand is the north stand turned a quarter turn about its sill,
## never mirrored, so the port door stays on the plane's left. Each case takes
## a north stand and a west and an east one whose sills stand as far from their
## side lanes as the north one's does from the taxi lane (186 m), and compares
## every point and rectangle with the north one's turned by this file's own
## quarter turns.

## A north stand: sill x -22.5 on the wall line z -98, 186 m south of the lane.
const NORTH := {"exit": 2, "x": -22.5, "wall_z": -98.0}
## Sills 186 m east of the west lane (x -124) and west of the east lane (x 124).
const SILLS := {"W": Vector2(62.0, -150.0), "E": Vector2(-62.0, -150.0)}
const SIDES: Array[String] = ["W", "E"]
const EPS := 0.0001


## `offset` (world xz) turned from a north stand's frame to `side`'s: west
## takes (x, z) to (z, -x), east to (-z, x). Both have determinant +1, so
## neither is a mirror.
static func _turned(side: String, offset: Vector2) -> Vector2:
	if side == "W":
		return Vector2(offset.y, -offset.x)
	return Vector2(-offset.y, offset.x)


static func _stand(side: String) -> Dictionary:
	var sill: Vector2 = SILLS[side]
	return StandPlacement.make(2, sill.x, sill.y, side)


## Where `north_point` of the NORTH stand lands at `side`'s stand.
static func _point(side: String, north_point: Vector3) -> Vector3:
	var from := Vector2(NORTH["x"], NORTH["wall_z"])
	var at: Vector2 = SILLS[side] + _turned(side, Vector2(north_point.x, north_point.z) - from)
	return Vector3(at.x, north_point.y, at.y)


static func _rects(side: String, north_rects: Array[Rect2]) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for rect in north_rects:
		var a := _point(side, Vector3(rect.position.x, 0.0, rect.position.y))
		var b := _point(side, Vector3(rect.end.x, 0.0, rect.end.y))
		out.append(Rect2(Vector2(a.x, a.z), Vector2.ZERO).expand(Vector2(b.x, b.z)))
	return out


func _assert_rects(got: Array[Rect2], want: Array[Rect2]) -> void:
	assert_int(got.size()).is_equal(want.size())
	for i in want.size():
		assert_vector(got[i].position).is_equal_approx(want[i].position, Vector2.ONE * EPS)
		assert_vector(got[i].size).is_equal_approx(want[i].size, Vector2.ONE * EPS)


func test_the_stand_points_are_the_north_stand_s_turned_about_the_sill() -> void:
	for side in SIDES:
		var stand := _stand(side)
		var pairs := [
			[StandPlacement.stand_point(stand), StandPlacement.stand_point(NORTH)],
			[StandPlacement.door_point(stand), StandPlacement.door_point(NORTH)],
			[
				StandPlacement.door_point(stand, "tp_plane_04a"),
				StandPlacement.door_point(NORTH, "tp_plane_04a")
			],
			[StandPlacement.pushback_end(stand), StandPlacement.pushback_end(NORTH)],
			[StandPlacement.lane_join(stand), StandPlacement.lane_join(NORTH)],
		]
		for pair: Array in pairs:
			var want := _point(side, pair[1])
			print("%s: %s, north %s turned %s" % [side, pair[0], pair[1], want])
			assert_vector(pair[0]).is_equal_approx(want, Vector3.ONE * EPS)


func test_the_swept_ground_and_every_envelope_are_the_north_ones_turned() -> void:
	for side in SIDES:
		var stand := _stand(side)
		# The twin's wall line is NORTH's, so a cut z means the same at both.
		assert_float(float(StandPlacement.north_twin(stand)["wall_z"])).is_equal(NORTH["wall_z"])
		for north_of in [INF, -150.0]:
			var got := StandPlacement.swept_rects(stand, north_of)
			print("%s swept north of %s: %s" % [side, north_of, got])
			_assert_rects(got, _rects(side, StandPlacement.swept_rects(NORTH, north_of)))
		for plane_class in PlaneClasses.ORDER:
			_assert_rects(
				StandEnvelope.rects(stand, plane_class),
				_rects(side, StandEnvelope.rects(NORTH, plane_class))
			)
			assert_bool(StandEnvelope.clears_lane(stand, plane_class)).is_equal(
				StandEnvelope.clears_lane(NORTH, plane_class)
			)
		var private := GateDesks.private_rects(stand)
		print("%s private %s" % [side, private])
		assert_int(private.size()).is_greater(0)
		_assert_rects(private, _rects(side, GateDesks.private_rects(NORTH)))
		assert_bool(StandPlacement.clears_lane(stand)).is_true()


## The plane faces its wall and its door is on its left, 3.5 m from its
## origin and 10.5 m behind the nose; it parks 16.9 m out from the wall, pushes
## back 29 m further, and its way out ends on its side's lane in line with it.
## Left of a nose heading n is (n.z, -n.x), as +x is left of a nose to +z.
func test_the_door_stays_on_the_port_side_and_the_way_ends_on_the_side_lane() -> void:
	var lane_x := {"W": -124.0, "E": 124.0}
	var steps := {"W": Vector2i(-1, 0), "E": Vector2i(1, 0)}
	for side in SIDES:
		var stand := _stand(side)
		var sill := Vector3(SILLS[side].x, 0.0, SILLS[side].y)
		var out := Vector3(steps[side].x, 0.0, steps[side].y)
		var nose := -out
		var left := Vector3(nose.z, 0.0, -nose.x)
		var at := StandPlacement.stand_point(stand)
		var door := StandPlacement.door_point(stand) - at
		print("%s: stand %s door offset %s left %s" % [side, at, door, left])
		assert_vector(StandPlacement.out_step(stand)).is_equal(steps[side])
		assert_float(door.dot(left)).is_equal_approx(StandPlacement.DOOR_SIDE_M, EPS)
		assert_float(door.dot(nose)).is_equal_approx(
			StandPlacement.NOSE_M - StandPlacement.DOOR_AFT_M, EPS
		)
		assert_float((at - sill).dot(out)).is_equal_approx(
			StandPlacement.NOSE_GAP_M + StandPlacement.NOSE_M, EPS
		)
		var back := StandPlacement.pushback_end(stand)
		assert_float((back - at).dot(out)).is_equal_approx(StandPlacement.PUSHBACK_M, EPS)
		var join := StandPlacement.lane_join(stand)
		assert_float(join.x).is_equal_approx(lane_x[side], EPS)
		assert_float(join.z).is_equal_approx(at.z, EPS)
	# A west plane faces east, so its door is north of it; an east one's south.
	assert_float(StandPlacement.door_point(_stand("W")).z).is_less(
		StandPlacement.stand_point(_stand("W")).z
	)
	assert_float(StandPlacement.door_point(_stand("E")).z).is_greater(
		StandPlacement.stand_point(_stand("E")).z
	)


func test_the_side_is_kept_in_the_stand_and_its_equality() -> void:
	var north := StandPlacement.make(2, -22.5, -98.0)
	assert_dict(north).is_equal(NORTH)
	assert_str(StandPlacement.side_of(north)).is_equal(StandPlacement.NORTH)
	var west := _stand("W")
	assert_str(west["side"]).is_equal("W")
	assert_bool(StandPlacement.is_stand(west)).is_true()
	var through: Dictionary = JSON.parse_string(JSON.stringify(west))
	assert_dict(StandPlacement.from_saved(through)).is_equal(west)
	for bad: Variant in ["S", "", 3]:
		var odd := west.duplicate()
		odd["side"] = bad
		assert_bool(StandPlacement.is_stand(odd)).is_false()
	# The same numbers on another side are another stand.
	var east := StandPlacement.make(2, west["x"], west["wall_z"], StandPlacement.EAST)
	var bare := StandPlacement.make(2, west["x"], west["wall_z"])
	assert_bool(ApronStand.same_stand(west, west.duplicate())).is_true()
	assert_bool(ApronStand.same_stand(west, east)).is_false()
	assert_bool(ApronStand.same_stand(west, bare)).is_false()
