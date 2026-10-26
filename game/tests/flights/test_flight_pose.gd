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


func test_heading_follows_segments_and_blends_around_the_corner() -> void:
	var path := _path()
	var entry := Vector3.RIGHT
	assert_float(FlightPose.heading_at(path, 10.0, entry).dot(Vector3.RIGHT)).is_equal_approx(
		1.0, 0.001
	)
	assert_float(FlightPose.heading_at(path, 60.0, entry).dot(Vector3.BACK)).is_equal_approx(
		1.0, 0.001
	)
	var at_corner := FlightPose.heading_at(path, 40.0, entry)
	assert_float(at_corner.dot(Vector3.RIGHT)).is_between(0.6, 0.8)
	assert_float(at_corner.dot(Vector3.BACK)).is_between(0.6, 0.8)


func test_heading_starts_on_the_entry_direction() -> void:
	var start := FlightPose.heading_at(_path(), 0.0, Vector3.BACK)
	assert_float(start.dot(Vector3.BACK)).is_equal_approx(1.0, 0.001)


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
