class_name TestFlightPose
extends GdUnitTestSuite

const L_PATH: Array[Vector3] = [Vector3(0, 0, 0), Vector3(40, 0, 0), Vector3(40, 0, 30)]


func _path() -> PackedVector3Array:
	return PackedVector3Array(L_PATH)


func test_path_length_and_point_at() -> void:
	var path := _path()
	assert_float(FlightPose.path_length(path)).is_equal_approx(70.0, 0.001)
	assert_that(FlightPose.point_at(path, 0.0)).is_equal(Vector3.ZERO)
	assert_that(FlightPose.point_at(path, 20.0)).is_equal(Vector3(20, 0, 0))
	assert_that(FlightPose.point_at(path, 55.0)).is_equal(Vector3(40, 0, 15))
	assert_that(FlightPose.point_at(path, 999.0)).is_equal(Vector3(40, 0, 30))
	assert_that(FlightPose.point_at(path, -5.0)).is_equal(Vector3.ZERO)


func test_exit_dir_is_the_last_segment() -> void:
	assert_that(FlightPose.exit_dir(_path())).is_equal(Vector3.BACK)


func test_taxi_pose_starts_and_ends_on_the_path_with_the_nose_forward() -> void:
	var path := _path()
	var first := FlightPose.pose(FlightSim.State.TAXI_IN, 0.0, path, Vector3.RIGHT)
	var last := FlightPose.pose(FlightSim.State.TAXI_IN, 1.0, path, Vector3.RIGHT)
	assert_that(first.origin).is_equal(Vector3.ZERO)
	assert_that(last.origin).is_equal(Vector3(40, 0, 30))
	assert_float(first.basis.z.dot(Vector3.RIGHT)).is_equal_approx(1.0, 0.001)
	assert_float(last.basis.z.dot(Vector3.BACK)).is_equal_approx(1.0, 0.001)


func test_pose_is_continuous_across_a_phase_join() -> void:
	var path := _path()
	var end_pose := FlightPose.pose(FlightSim.State.TAXI_IN, 1.0, path, Vector3.RIGHT)
	var next_path := PackedVector3Array([Vector3(40, 0, 30), Vector3(40, 0, 60)])
	var start_pose := FlightPose.pose(
		FlightSim.State.PUSHBACK, 0.0, next_path, FlightPose.exit_dir(path)
	)
	assert_float(end_pose.origin.distance_to(start_pose.origin)).is_less(0.001)
	assert_float(end_pose.basis.z.dot(start_pose.basis.z)).is_equal_approx(1.0, 0.001)


func test_taxi_eases_in_and_out() -> void:
	var path := _path()
	var early := FlightPose.pose(FlightSim.State.TAXI_IN, 0.1, path, Vector3.RIGHT)
	var middle := FlightPose.pose(FlightSim.State.TAXI_IN, 0.5, path, Vector3.RIGHT)
	assert_float(FlightPose.path_length(path)).is_greater(0.0)
	assert_float(early.origin.x).is_less(7.0)
	assert_float(middle.origin.x).is_equal_approx(35.0, 0.001)
	assert_float(middle.origin.z).is_equal_approx(0.0, 0.001)


## A taxi pose with a pause stands at the hold, nose on the route, for the
## pause's share of the phase, and still ends where the phase without one does.
## The L path is 70 m; held 40 m along (the corner) for 20 of 220 ticks, the
## 200 moving ticks split 40 m / 70 m: T1 114.29, so the hold is 114.29..134.29.
func test_a_taxi_pose_with_a_pause_stands_at_the_hold() -> void:
	var path := _path()
	var pause := {"hold_s": 40.0, "ticks": 20}
	var budget := 220.0
	var arrive := FlightPose.pose(
		FlightSim.State.TAXI_IN, 115.0 / budget, path, Vector3.RIGHT, pause, budget
	)
	var leave := FlightPose.pose(
		FlightSim.State.TAXI_IN, 134.0 / budget, path, Vector3.RIGHT, pause, budget
	)
	var moving := FlightPose.pose(
		FlightSim.State.TAXI_IN, 140.0 / budget, path, Vector3.RIGHT, pause, budget
	)
	var unpaused := FlightPose.pose(FlightSim.State.TAXI_IN, 115.0 / budget, path, Vector3.RIGHT)
	var last := FlightPose.pose(FlightSim.State.TAXI_IN, 1.0, path, Vector3.RIGHT, pause, budget)
	print(
		(
			"held at %s and %s, moving %s, unpaused %s"
			% [arrive.origin, leave.origin, moving.origin, unpaused.origin]
		)
	)
	assert_float(arrive.origin.distance_to(Vector3(40, 0, 0))).is_less(1e-4)
	assert_float(leave.origin.distance_to(Vector3(40, 0, 0))).is_less(1e-4)
	assert_float(arrive.basis.z.dot(leave.basis.z)).is_equal_approx(1.0, 1e-6)
	assert_float(moving.origin.z).is_greater(0.01)
	assert_float(unpaused.origin.distance_to(Vector3(40, 0, 0))).is_greater(1.0)
	assert_float(last.origin.distance_to(Vector3(40, 0, 30))).is_less(1e-4)


## A pause with no budget plans over the state's PHASE_TICKS (600 for
## TAXI_IN), not over one tick: 60 ticks in, the plane is still on its way to
## the hold (T1 = 580 * 40 / 70 = 331.4), and 340 ticks in it stands there.
func test_a_pause_with_no_budget_plans_over_the_state_ticks() -> void:
	var path := _path()
	var pause := {"hold_s": 40.0, "ticks": 20}
	var ticks := float(FlightSim.PHASE_TICKS[FlightSim.State.TAXI_IN])
	var early := FlightPose.pose(FlightSim.State.TAXI_IN, 60.0 / ticks, path, Vector3.RIGHT, pause)
	var explicit := FlightPose.pose(
		FlightSim.State.TAXI_IN, 60.0 / ticks, path, Vector3.RIGHT, pause, ticks
	)
	var held := FlightPose.pose(FlightSim.State.TAXI_IN, 340.0 / ticks, path, Vector3.RIGHT, pause)
	print(
		(
			"no budget: 60 ticks in %s, explicit %s, 340 in %s"
			% [early.origin, explicit.origin, held.origin]
		)
	)
	assert_float(early.origin.x).is_greater(1.0).is_less(39.0)
	assert_float(early.origin.distance_to(explicit.origin)).is_less(1e-6)
	assert_float(held.origin.distance_to(Vector3(40, 0, 0))).is_less(1e-4)


## A pause that does not fit its budget (20 ticks in 10) is reported, and the
## plane is drawn without it rather than stuck at the hold.
func test_a_pause_that_does_not_fit_is_reported_and_left_out() -> void:
	var path := _path()
	var pause := {"hold_s": 40.0, "ticks": 20}
	var out: Array[Transform3D] = []
	var draw := func() -> void:
		out.append(FlightPose.pose(FlightSim.State.TAXI_IN, 0.3, path, Vector3.RIGHT, pause, 10.0))
	await assert_error(draw).is_push_error(
		"FlightPose: pause %s does not fit 10 ticks; drawn without it" % pause
	)
	var unpaused := FlightPose.pose(FlightSim.State.TAXI_IN, 0.3, path, Vector3.RIGHT)
	print("unfit pause drawn at %s, unpaused %s" % [out[0].origin, unpaused.origin])
	assert_int(out.size()).is_equal(1)
	assert_float(out[0].origin.distance_to(unpaused.origin)).is_less(1e-6)
	assert_float(unpaused.origin.distance_to(Vector3(40, 0, 0))).is_greater(1.0)


func test_pitch_is_light_and_signed_by_phase() -> void:
	var path := PackedVector3Array([Vector3(0, 40, 0), Vector3(200, 0, 0)])
	var approach := FlightPose.pose(FlightSim.State.APPROACH, 0.5, path, Vector3.RIGHT)
	var takeoff := FlightPose.pose(FlightSim.State.TAKEOFF, 1.0, path, Vector3.RIGHT)
	var taxi := FlightPose.pose(FlightSim.State.TAXI_IN, 0.5, path, Vector3.RIGHT)
	# The plane's local +Z is its nose, so nose-down has a negative world y.
	assert_float(approach.basis.z.y).is_between(-0.15, -0.01)
	assert_float(takeoff.basis.z.y).is_between(0.05, 0.3)
	assert_float(taxi.basis.z.y).is_equal_approx(0.0, 0.001)
	assert_float(approach.basis.y.y).is_greater(0.95)


func test_pushback_swings_the_nose_while_moving_back() -> void:
	var path := PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 0, -30)])
	var start := FlightPose.pose(FlightSim.State.PUSHBACK, 0.0, path, Vector3.BACK)
	var end := FlightPose.pose(FlightSim.State.PUSHBACK, 1.0, path, Vector3.BACK)
	assert_float(start.basis.z.dot(Vector3.BACK)).is_equal_approx(1.0, 0.001)
	assert_float(end.basis.z.dot(Vector3.BACK)).is_less(0.0)
	assert_that(end.origin).is_equal(Vector3(0, 0, -30))


func _l_track() -> PackedVector3Array:
	var corners := PackedVector3Array(
		[Vector3(0, 50, 0), Vector3(0, 50, 300), Vector3(300, 50, 300)]
	)
	return Airside.round_corners(corners, 100.0, 45.0, 4.0)


## The arc of a 100 m turn starts 200 m along and is 157 m long. The nose turns
## from +Z to +X, a left turn, so the left wing (+X) dips into it.
func test_a_sky_turn_banks_into_the_turn_and_levels_on_the_straights() -> void:
	var track := _l_track()
	var straight := FlightPose.climb_out_pose(track, 60.0)
	var turning := FlightPose.climb_out_pose(track, 200.0 + PI * 100.0 / 4.0)
	var after_turn := FlightPose.climb_out_pose(track, FlightPose.path_length(track) - 50.0)
	assert_float(straight.basis.x.y).is_equal_approx(0.0, 0.001)
	assert_float(turning.basis.x.y).is_between(-0.4, -0.15)
	assert_float(after_turn.basis.x.y).is_equal_approx(0.0, 0.001)
	(
		assert_float(after_turn.basis.z.slide(Vector3.UP).normalized().dot(Vector3.RIGHT))
		. is_equal_approx(1.0, 0.0001)
	)


## The lead-in descends into its last point on the approach pitch; the
## climb-out leaves its first point on the climb pitch; both stay under the
## ceiling.
func test_sky_poses_leave_and_meet_their_join_on_its_pitch() -> void:
	var track := _l_track()
	var length := FlightPose.path_length(track)
	var lead_end := FlightPose.lead_in_pose(track, length)
	var climb_start := FlightPose.climb_out_pose(track, 0.0)
	assert_that(lead_end.origin).is_equal(track[track.size() - 1])
	assert_that(climb_start.origin).is_equal(track[0])
	assert_float(asin(lead_end.basis.z.y)).is_equal_approx(FlightPose.APPROACH_PITCH, 0.0001)
	assert_float(asin(climb_start.basis.z.y)).is_equal_approx(FlightPose.CLIMB_PITCH, 0.0001)
	var far_lead := FlightPose.lead_in_pose(track, 0.0)
	assert_float(far_lead.origin.y).is_greater(70.0).is_less(FlightPose.SKY_CEILING)
	assert_float(far_lead.basis.z.y).is_less(0.0)


func test_flat_speed_is_the_speed_a_sky_phase_joins_at() -> void:
	var path := PackedVector3Array([Vector3(0, 0, 0), Vector3(100, 0, 0), Vector3(400, 40, 0)])
	var length := FlightPose.path_length(path)
	var last := path[1].distance_to(path[2])
	var takeoff := FlightPose.flat_speed(FlightSim.State.TAKEOFF, 1.0, path, 200.0)
	assert_float(takeoff).is_equal_approx(2.0 * length / 200.0 * 300.0 / last, 0.0001)
	var approach := FlightPose.flat_speed(FlightSim.State.APPROACH, 0.0, path, 100.0)
	assert_float(approach).is_equal_approx(length / 100.0, 0.0001)
	# The pose itself moves at that speed over the takeoff's last 0.1%.
	var a := FlightPose.pose(FlightSim.State.TAKEOFF, 0.999, path, Vector3.RIGHT).origin
	var b := FlightPose.pose(FlightSim.State.TAKEOFF, 1.0, path, Vector3.RIGHT).origin
	var flat_step := Vector2(b.x - a.x, b.z - a.z).length() / (0.001 * 200.0)
	assert_float(flat_step).is_equal_approx(takeoff, 0.01)
