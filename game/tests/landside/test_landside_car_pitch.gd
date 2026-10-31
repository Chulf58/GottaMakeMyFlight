class_name TestLandsideCarPitch
extends GdUnitTestSuite
## Board 0b82b7e4: a car on a slope pitches so both axles stand on the path's
## height where each wheel is (LandsideViews.on_path), not level with one
## wheel in the air and the other sunk. The axles come from each model's wheel
## meshes (LandsideViews.axles_of).

const MODELS := [
	"res://assets/vehicles/tp_taxi_01a.glb",
	"res://assets/vehicles/tp_suv_01b.glb",
	"res://assets/vehicles/tp_van_01a.glb",
]
## 10 m flat at y 0, then 10 m climbing 1 m (10%), then 10 m flat at y 1, along +z.
const SLOPE := 0.1
const EPS := 0.002

var _path := PackedVector3Array(
	[Vector3(0, 0, -10), Vector3(0, 0, 0), Vector3(0, 1, 10), Vector3(0, 1, 20)]
)
var _axles := Vector2(1.6, -1.5)


func test_every_vehicle_model_has_a_front_and_a_rear_axle_from_its_wheels() -> void:
	for path: String in MODELS:
		var model: Node3D = (load(path) as PackedScene).instantiate()
		var axles := LandsideViews.axles_of(model)
		print("%s axles %s" % [path.get_file(), axles])
		# The Toon cars' wheelbase is about 3 m, front ahead of the origin.
		assert_float(axles.x).is_between(0.8, 2.2)
		assert_float(axles.y).is_between(-2.2, -0.8)
		assert_float(axles.x - axles.y).is_between(2.5, 3.6)
		model.free()


func test_on_a_slope_both_wheels_are_on_the_path_and_the_nose_points_up_it() -> void:
	var mm := 15000
	var pose := LandsideViews.on_path(_path, mm, Vector3(0, 0, 1), _axles)
	var front := pose * Vector3(0, 0, _axles.x)
	var rear := pose * Vector3(0, 0, _axles.y)
	print("slope pose %s front %s rear %s" % [pose, front, rear])
	assert_float(front.y).is_equal_approx(_height_at(front.z), EPS)
	assert_float(rear.y).is_equal_approx(_height_at(rear.z), EPS)
	assert_float(pose.basis.z.y).is_equal_approx(SLOPE / sqrt(1.0 + SLOPE * SLOPE), 0.01)
	# Over the path point, along the flat way.
	assert_float(pose.origin.x).is_equal_approx(0.0, EPS)
	assert_float(pose.origin.z).is_equal_approx(LandsideDefinition.point_at(_path, mm).z, EPS)
	# The model stays upright: its up has no sideways lean.
	assert_float(pose.basis.y.x).is_equal_approx(0.0, EPS)
	assert_float(pose.basis.x.y).is_equal_approx(0.0, EPS)


## The control: on the flat the car is level and on the path, as before.
func test_on_the_flat_the_car_is_level_on_the_path() -> void:
	var pose := LandsideViews.on_path(_path, 25000, Vector3(0, 0, 1), _axles)
	assert_vector(pose.basis.z).is_equal_approx(Vector3(0, 0, 1), Vector3.ONE * EPS)
	assert_vector(pose.origin).is_equal_approx(
		LandsideDefinition.point_at(_path, 25000), Vector3.ONE * EPS
	)


## Over the top of the slope the front wheels are on the flat and the rear
## wheels still on the slope: both on the path, the car pitched between.
func test_over_a_change_of_slope_both_wheels_follow_the_path() -> void:
	for mm in range(8000, 23000, 250):
		var pose := LandsideViews.on_path(_path, mm, Vector3(0, 0, 1), _axles)
		var front := pose * Vector3(0, 0, _axles.x)
		var rear := pose * Vector3(0, 0, _axles.y)
		assert_float(front.y).is_equal_approx(_height_at(front.z), 0.01)
		assert_float(rear.y).is_equal_approx(_height_at(rear.z), 0.01)


## Backing down the path (nose facing back along it), the front wheels are
## behind on the path: the nose points up the slope, both wheels on it.
func test_backing_down_a_slope_the_nose_points_up_it_with_both_wheels_on() -> void:
	var pose := LandsideViews.on_path(_path, 15000, Vector3(0, 0, -1), _axles)
	var front := pose * Vector3(0, 0, _axles.x)
	var rear := pose * Vector3(0, 0, _axles.y)
	print("backing pose front %s rear %s nose %s" % [front, rear, pose.basis.z])
	assert_float(front.z).is_less(rear.z)
	assert_float(front.y).is_equal_approx(_height_at(front.z), EPS)
	assert_float(rear.y).is_equal_approx(_height_at(rear.z), EPS)
	# Facing -z down a slope that climbs to +z: the nose points down.
	assert_float(pose.basis.z.y).is_less(-0.05)


## A path that ends on a slope (the access lane ends climbing at the gate, and
## the entrance carries on flat): a front wheel past the end takes the end's
## height, so it does not float over the flat beyond.
func test_a_wheel_past_the_end_of_a_climbing_path_takes_the_ends_height() -> void:
	var climbing := PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 1, 10)])
	var end := LandsideDefinition.length_mm(climbing)
	var pose := LandsideViews.on_path(climbing, end - 500, Vector3(0, 0, 1), _axles)
	var front := pose * Vector3(0, 0, _axles.x)
	print("past the end: front %s" % front)
	assert_float(front.y).is_equal_approx(1.0, EPS)


## Up a real deck ramp of the multi-storey (the slot path to a top-deck slot),
## both wheels stay on the path at every step, and the car pitches there.
func test_up_the_multi_storey_ramps_both_wheels_stay_on_the_slot_path() -> void:
	var starter: LandsideDefinition = load("res://landside/starter_landside.tres")
	var paths := LandsidePaths.new(starter)
	var path: PackedVector3Array = paths.slot_path[1][20]
	var stand: int = paths.slot_stand[1][20]
	var steepest := 0.0
	for mm in range(0, stand, 250):
		var dir := LandsideDefinition.heading_at(path, mm)
		var pose := LandsideViews.on_path(path, mm, dir, _axles)
		steepest = maxf(steepest, pose.basis.z.y)
		for axle in [_axles.x, _axles.y]:
			var wheel := pose * Vector3(0, 0, axle)
			var on := LandsideDefinition.point_at(path, mm + roundi(axle * 1000.0))
			(
				assert_float(wheel.y)
				. override_failure_message("mm %d axle %.2f %s on %s" % [mm, axle, wheel, on])
				. is_equal_approx(on.y, 0.02)
			)
	print("top-deck slot path %d mm, steepest nose %.3f" % [stand, steepest])
	assert_float(steepest).is_greater(0.1)


## The height of _path at z.
func _height_at(z: float) -> float:
	return clampf(z * SLOPE, 0.0, 1.0)
