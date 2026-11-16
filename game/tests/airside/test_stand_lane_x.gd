class_name TestStandLaneX
extends GdUnitTestSuite
## A west or east stand carries lane_x, the world x of its own side spur
## (decision side-spur-move-design-s7-stands-carry-lane-x-the-wanted-spur,
## slice S7a). make() writes it, x -124 / +124 (StandPlacement.SIDE_LANE_X)
## unless given; it is never inside that floor. The stand's frame reads it: the
## north twin's sill is as far from the taxi lane as the stand's is from its
## own spur, and the way out joins the spur at lane_x. A save's side stand
## must carry it, and two stands on different spurs are different stands. A
## north stand has none.

## A west and an east sill 62 m inside the spurs at x -124 / +124.
const WEST_SILL := Vector2(-62.0, -150.0)
const EAST_SILL := Vector2(62.0, -150.0)
const WIDE := 174.0
const EPS := 0.0001


static func _west(lane_x := NAN) -> Dictionary:
	return StandPlacement.make(3, WEST_SILL.x, WEST_SILL.y, StandPlacement.WEST, lane_x)


static func _east(lane_x := NAN) -> Dictionary:
	return StandPlacement.make(4, EAST_SILL.x, EAST_SILL.y, StandPlacement.EAST, lane_x)


func test_make_writes_the_floor_lane_x_on_side_stands_only() -> void:
	var north := StandPlacement.make(2, -22.5, -98.0)
	print("north %s, west %s, east %s" % [north, _west(), _east()])
	assert_dict(north).is_equal({"exit": 2, "x": -22.5, "wall_z": -98.0})
	assert_float(float(_west()["lane_x"])).is_equal(-StandPlacement.SIDE_LANE_X)
	assert_float(float(_east()["lane_x"])).is_equal(StandPlacement.SIDE_LANE_X)
	assert_float(float(_west(-WIDE)["lane_x"])).is_equal(-WIDE)
	assert_float(float(_east(WIDE)["lane_x"])).is_equal(WIDE)
	assert_float(StandPlacement.lane_x_of(_west(-WIDE))).is_equal(-WIDE)


## Inside the floor, on the other side, or on a north stand there is no spur.
func test_make_refuses_a_lane_x_inside_the_floor_or_on_a_north_stand() -> void:
	assert_dict(_west(-100.0)).is_empty()
	assert_dict(_west(WIDE)).is_empty()
	assert_dict(_east(100.0)).is_empty()
	assert_dict(_east(-WIDE)).is_empty()
	assert_dict(StandPlacement.make(2, 0.0, -98.0, StandPlacement.NORTH, -WIDE)).is_empty()
	# Control: the floor itself is a spur.
	assert_dict(_west(-StandPlacement.SIDE_LANE_X)).is_equal(_west())


## The twin's sill is TAXI_LANE_Z + |x - lane_x|: 62 m at the floor, 112 m
## with the spur at 174, and the way out joins the spur at its lane_x, on the
## sill's row.
func test_north_twin_and_lane_join_follow_lane_x() -> void:
	for lane in [StandPlacement.SIDE_LANE_X, WIDE]:
		var west := _west(-lane)
		var east := _east(lane)
		var depth: float = lane - 62.0
		var west_twin := StandPlacement.north_twin(west)
		var east_twin := StandPlacement.north_twin(east)
		var west_join := StandPlacement.lane_join(west)
		var east_join := StandPlacement.lane_join(east)
		print(
			(
				"lane %.0f: twins %s %s, joins %s %s"
				% [lane, west_twin, east_twin, west_join, east_join]
			)
		)
		assert_float(float(west_twin["wall_z"])).is_equal(StandPlacement.TAXI_LANE_Z + depth)
		assert_float(float(east_twin["wall_z"])).is_equal(StandPlacement.TAXI_LANE_Z + depth)
		assert_float(float(west_twin["x"])).is_equal(0.0)
		assert_float(west_join.x).is_equal_approx(-lane, EPS)
		assert_float(east_join.x).is_equal_approx(lane, EPS)
		# The join is on the plane's row, DOOR_SIDE_M off the sill's (port side).
		assert_float(west_join.z).is_equal_approx(WEST_SILL.y + StandPlacement.DOOR_SIDE_M, EPS)
		assert_float(east_join.z).is_equal_approx(EAST_SILL.y - StandPlacement.DOOR_SIDE_M, EPS)


## The parked plane and the pushback do not depend on the spur: only the way
## out to it grows.
func test_the_parked_plane_and_pushback_do_not_move_with_the_spur() -> void:
	for pair in [[_west(), _west(-WIDE)], [_east(), _east(WIDE)]]:
		var near: Dictionary = pair[0]
		var far: Dictionary = pair[1]
		assert_vector(StandPlacement.stand_point(far)).is_equal_approx(
			StandPlacement.stand_point(near), Vector3.ONE * EPS
		)
		assert_vector(StandPlacement.pushback_end(far)).is_equal_approx(
			StandPlacement.pushback_end(near), Vector3.ONE * EPS
		)
		assert_vector(StandPlacement.door_point(far)).is_equal_approx(
			StandPlacement.door_point(near), Vector3.ONE * EPS
		)
		var gain := absf(StandPlacement.lane_join(far).x - StandPlacement.lane_join(near).x)
		assert_float(gain).is_equal_approx(WIDE - StandPlacement.SIDE_LANE_X, EPS)


## A saved side stand must carry lane_x beyond the floor; from_saved keeps it
## through JSON, and same_stand tells two spurs apart.
func test_a_saved_side_stand_needs_lane_x_and_keeps_it() -> void:
	var wide := _west(-WIDE)
	assert_bool(StandPlacement.is_stand(wide)).is_true()
	var through: Dictionary = JSON.parse_string(JSON.stringify(wide))
	assert_dict(StandPlacement.from_saved(through)).is_equal(wide)
	var bare := wide.duplicate()
	bare.erase("lane_x")
	for bad: Variant in ["-174", -100.0, 174.0, null]:
		var odd := wide.duplicate()
		odd["lane_x"] = bad
		assert_bool(StandPlacement.is_stand(odd)).override_failure_message("%s" % [bad]).is_false()
	assert_bool(StandPlacement.is_stand(bare)).is_false()
	assert_bool(ApronStand.same_stand(wide, through)).is_true()
	assert_bool(ApronStand.same_stand(wide, _west())).is_false()
	# A north stand needs none, and one with a lane_x is not a stand.
	var north := StandPlacement.make(2, -22.5, -98.0)
	assert_bool(StandPlacement.is_stand(north)).is_true()
	var odd_north := north.duplicate()
	odd_north["lane_x"] = -WIDE
	assert_bool(StandPlacement.is_stand(odd_north)).is_false()


## with_lane_x() moves a stand onto another spur of its side, keeping its sill;
## a north stand stays as it is.
func test_with_lane_x_moves_only_the_spur() -> void:
	var moved := StandPlacement.with_lane_x(_west(), -WIDE)
	assert_dict(moved).is_equal(_west(-WIDE))
	var north := StandPlacement.make(2, -22.5, -98.0)
	assert_dict(StandPlacement.with_lane_x(north, -WIDE)).is_equal(north)


## SideSpurs, the one source of each side's spur x: at the floor while side
## land is locked. Its stand for an exit is StandPlacement.for_exit's with that
## lane_x.
func test_side_spurs_answer_the_floor_while_side_land_is_locked() -> void:
	assert_float(SideSpurs.lane_x(StandPlacement.WEST)).is_equal(-StandPlacement.SIDE_LANE_X)
	assert_float(SideSpurs.lane_x(StandPlacement.EAST)).is_equal(StandPlacement.SIDE_LANE_X)
	var site: SiteDefinition = load("res://build/terminal_site.tres")
	var grid := BuildGrid.new(site.grid_size, site.grid_origin)
	assert_bool(StarterShell.place(grid, site.starter_offset)).is_true()
	var cell := TestStandSideGrid.WEST_CELL + site.starter_offset
	assert_bool(grid.apply(BuildEdit.remove_wall(cell, BuildGrid.Side.WEST)).ok).is_true()
	var placed := grid.apply(BuildEdit.place_object(&"exit_door", cell, 3))
	assert_bool(placed.ok).is_true()
	var stand := SideSpurs.stand_for_exit(grid, placed.object_id)
	print("west exit stand %s" % stand)
	assert_str(StandPlacement.side_of(stand)).is_equal(StandPlacement.WEST)
	assert_dict(stand).is_equal(StandPlacement.for_exit(grid, placed.object_id))
	assert_float(float(stand["lane_x"])).is_equal(-StandPlacement.SIDE_LANE_X)
