class_name TestShellCutaway
extends GdUnitTestSuite
## ShellCutaway: the roof fade target and its hysteresis, the fade steps,
## which facade sides the camera heading cuts, the roof gate, the stub
## mapping and how pieces are given a side.

const NORTH := ShellCutaway.Side.NORTH
const SOUTH := ShellCutaway.Side.SOUTH
const EAST := ShellCutaway.Side.EAST
const WEST := ShellCutaway.Side.WEST

var _cut: ShellCutaway


func before_test() -> void:
	_cut = ShellCutaway.new()


## The rig's direction toward the eye for a TycoonCamera yaw (yaw 0 looks
## from +z). The rig itself does not pitch.
func _eye(yaw_degrees: float) -> Vector3:
	return Basis(Vector3.UP, deg_to_rad(yaw_degrees)) * Vector3.BACK


func test_snap_sets_the_roof_from_the_distance_with_no_fade() -> void:
	_cut.snap(300.0, _eye(0.0))
	assert_float(_cut.roof_target).is_equal(0.0)
	assert_float(_cut.roof_level).is_equal(0.0)
	_cut.snap(50.0, _eye(0.0))
	assert_float(_cut.roof_target).is_equal(1.0)
	assert_float(_cut.roof_level).is_equal(1.0)


func test_snap_inside_the_band_draws_the_roof() -> void:
	_cut.snap(50.0, _eye(0.0))
	_cut.snap(110.0, _eye(0.0))
	assert_float(_cut.roof_target).is_equal(0.0)
	assert_float(_cut.roof_level).is_equal(0.0)


func test_thresholds_are_strict() -> void:
	_cut.snap(100.0, _eye(0.0))
	assert_float(_cut.roof_target).is_equal(0.0)
	_cut.snap(99.9, _eye(0.0))
	assert_float(_cut.roof_target).is_equal(1.0)
	_cut.step(120.0, _eye(0.0), 0.01)
	assert_float(_cut.roof_target).is_equal(1.0)
	_cut.step(120.1, _eye(0.0), 0.01)
	assert_float(_cut.roof_target).is_equal(0.0)


func test_the_band_keeps_the_last_target_both_ways() -> void:
	_cut.snap(50.0, _eye(0.0))
	_cut.step(110.0, _eye(0.0), 0.1)
	assert_float(_cut.roof_target).is_equal(1.0)
	assert_float(_cut.roof_level).is_equal(1.0)
	_cut.snap(300.0, _eye(0.0))
	_cut.step(110.0, _eye(0.0), 0.1)
	assert_float(_cut.roof_target).is_equal(0.0)
	assert_float(_cut.roof_level).is_equal(0.0)


func test_the_roof_fades_at_a_constant_rate_and_lands_exactly() -> void:
	_cut.snap(300.0, _eye(0.0))
	var seen: Array[float] = []
	for i in 5:
		_cut.step(50.0, _eye(0.0), 0.1)
		seen.append(_cut.roof_level)
	assert_float(seen[0]).is_equal_approx(0.1 / _cut.roof_fade_seconds, 1e-6)
	assert_float(seen[1]).is_equal_approx(0.2 / _cut.roof_fade_seconds, 1e-6)
	assert_float(seen[4]).is_equal(1.0)


func test_a_reversal_mid_fade_continues_from_where_it_is() -> void:
	_cut.snap(300.0, _eye(0.0))
	_cut.step(50.0, _eye(0.0), 0.2)
	var mid := _cut.roof_level
	assert_float(mid).is_greater(0.0)
	assert_float(mid).is_less(1.0)
	_cut.step(200.0, _eye(0.0), 0.1)
	assert_float(_cut.roof_target).is_equal(0.0)
	assert_float(_cut.roof_level).is_equal_approx(mid - 0.1 / _cut.roof_fade_seconds, 1e-6)


func test_approach_saturates_on_a_long_frame() -> void:
	assert_float(ShellCutaway.approach(0.3, 1.0, 5.0, 0.4)).is_equal(1.0)
	assert_float(ShellCutaway.approach(0.3, 0.0, 5.0, 0.4)).is_equal(0.0)
	assert_float(ShellCutaway.approach(0.5, 0.5, 0.1, 0.4)).is_equal(0.5)


func test_the_heading_picks_the_camera_sides() -> void:
	var expected := {
		0.0: [SOUTH],
		180.0: [NORTH],
		90.0: [EAST],
		-90.0: [WEST],
		45.0: [SOUTH, EAST],
		-135.0: [NORTH, WEST],
	}
	for yaw in expected:
		var cut := ShellCutaway.new()
		cut.snap(50.0, _eye(yaw))
		var sides: Array = []
		for side in [NORTH, SOUTH, EAST, WEST]:
			if cut.side_levels[side] == 1.0:
				sides.append(side)
			else:
				assert_float(cut.side_levels[side]).is_equal(0.0)
		var want: Array = expected[yaw]
		want.sort()
		sides.sort()
		assert_array(sides).override_failure_message("yaw %s" % yaw).is_equal(want)


func test_an_edge_on_heading_keeps_the_side_it_had() -> void:
	_cut.snap(50.0, _eye(45.0))
	_cut.step(50.0, _eye(92.0), 1.0)
	assert_float(_cut.side_levels[SOUTH]).is_equal(1.0)
	assert_float(_cut.side_levels[EAST]).is_equal(1.0)


func test_a_side_drops_over_the_side_fade() -> void:
	_cut.snap(50.0, _eye(0.0))
	_cut.step(50.0, _eye(180.0), 0.1)
	assert_float(_cut.side_levels[NORTH]).is_equal_approx(0.1 / _cut.side_fade_seconds, 1e-6)
	assert_float(_cut.side_levels[SOUTH]).is_equal_approx(1.0 - 0.1 / _cut.side_fade_seconds, 1e-6)


func test_the_facade_cuts_only_while_the_roof_is_gone() -> void:
	_cut.snap(300.0, _eye(0.0))
	assert_float(_cut.side_levels[SOUTH]).is_equal(1.0)
	assert_float(_cut.cut(SOUTH)).is_equal(0.0)
	_cut.cut_only_without_roof = false
	assert_float(_cut.cut(SOUTH)).is_equal(1.0)
	_cut.cut_only_without_roof = true
	_cut.snap(50.0, _eye(0.0))
	assert_float(_cut.cut(SOUTH)).is_equal(1.0)
	assert_float(_cut.cut(NORTH)).is_equal(0.0)


func test_the_stub_map_keeps_the_floor_and_lowers_the_top() -> void:
	var none := ShellCutaway.stub_transform(0.0)
	assert_bool(none.is_equal_approx(Transform3D.IDENTITY)).is_true()
	var full := ShellCutaway.stub_transform(1.0)
	var floor_y := ShellCutaway.FLOOR_Y
	var top_y := floor_y + ShellCutaway.FACADE_HEIGHT
	assert_float((full * Vector3(3.0, floor_y, -7.0)).y).is_equal_approx(floor_y, 1e-5)
	var top := full * Vector3(3.0, top_y, -7.0)
	assert_float(top.y).is_equal_approx(floor_y + InteriorKit.STUB_HEIGHT, 1e-5)
	assert_float(top.x).is_equal(3.0)
	assert_float(top.z).is_equal(-7.0)


func test_unusable_tuning_is_reported() -> void:
	assert_str(_cut.tuning_error()).is_empty()
	_cut.roof_fade_seconds = 0.0
	assert_str(_cut.tuning_error()).is_not_empty()
	_cut.roof_fade_seconds = 0.4
	_cut.side_fade_seconds = -1.0
	assert_str(_cut.tuning_error()).is_not_empty()
	_cut.side_fade_seconds = 0.25
	_cut.roof_hide_below = 130.0
	assert_str(_cut.tuning_error()).is_not_empty()
	_cut.roof_hide_below = 120.0
	assert_str(_cut.tuning_error()).is_empty()


func test_names_give_the_side() -> void:
	assert_int(ShellCutaway.side_of_name("Facade_N_01")).is_equal(NORTH)
	assert_int(ShellCutaway.side_of_name("Facade_S_22")).is_equal(SOUTH)
	assert_int(ShellCutaway.side_of_name("Lights_E_07")).is_equal(EAST)
	assert_int(ShellCutaway.side_of_name("Facade_W_12")).is_equal(WEST)
	assert_int(ShellCutaway.side_of_name("Lights_Upper")).is_equal(-1)
	assert_int(ShellCutaway.side_of_name("Door_1")).is_equal(-1)


func test_a_box_gets_the_outer_face_it_sits_nearest() -> void:
	var around := AABB(Vector3(-34.2, 0.3, -15.5), Vector3(67.4, 5.2, 31.4))
	var door_north := AABB(Vector3(-27.0, 0.3, -16.0), Vector3(2.2, 3.5, 1.0))
	var porch_south := AABB(Vector3(23.0, 0.1, 15.6), Vector3(4.1, 4.9, 3.9))
	var bay_east := AABB(Vector3(32.7, 0.3, 0.4), Vector3(0.5, 5.2, 2.1))
	var bay_west := AABB(Vector3(-34.2, 0.3, -5.0), Vector3(0.5, 5.2, 3.0))
	assert_int(ShellCutaway.side_of_box(door_north, around)).is_equal(NORTH)
	assert_int(ShellCutaway.side_of_box(porch_south, around)).is_equal(SOUTH)
	assert_int(ShellCutaway.side_of_box(bay_east, around)).is_equal(EAST)
	assert_int(ShellCutaway.side_of_box(bay_west, around)).is_equal(WEST)
