class_name TestCarryStallCaseGrip
extends GdUnitTestSuite
## A hard case standing in a toilet stall is on its grip when the hand holds it
## by the middle of its top end, and as it tips into the carry with the palm
## going over the top end's edge to the handle (decision toilet-stall-bag-moves-
## are-hand-led-as-built-a-hard-case-is; board item e845dfe8: the probes'
## GRIP_ON check knew only the handle face and read that grip 0.137 m off).
## The check reads the case's grip from its drawn body mesh
## (FloatCheck.case_handle_points()), never from the placement. Controls: a hand
## beside the case's side face, one lifted off its top and one beside its back
## face (away from the handle) read off.

const FloatCheck := preload("res://spike/carry_float_check.gd")
const OFF_M := 0.10
## A body drawn smaller and larger than the default, as passengers are.
const SCALES: Array[float] = [0.9, 1.1]

var _case: Node3D


func before_test() -> void:
	_case = InteriorKit.instantiate(SecurityLooks.KIND_PIECES[SecurityLooks.Kind.CASE]) as Node3D
	add_child(_case)


func after_test() -> void:
	_case.free()
	_case = null


## The case standing on its end in a stall at `scale_by`: its own z (its
## length) up, turned and moved off the origin so a frame mix-up shows.
func _stand(scale_by: float) -> void:
	var upright := Basis(Vector3.RIGHT, -PI / 2.0).rotated(Vector3.UP, 0.7)
	_case.global_transform = Transform3D(
		upright.scaled(Vector3.ONE * scale_by), Vector3(3.0, 0.2, -98.0)
	)


func _limit() -> float:
	return FloatCheck.GRIP_ON_M + CarryOnProps.FRONT_PALM_M


func test_the_stall_top_hold_is_on_the_grip() -> void:
	for s in SCALES:
		_stand(s)
		var top := CarryLead.stall_top(SecurityLooks.Kind.CASE, Vector3.ZERO, s)
		var grip := _case.global_transform * top
		# The case's own z is world up: the grip is over the top end.
		var end_y := _case.global_position.y + CarryOnProps.bag_box().end.z * s
		assert_float(grip.y).is_greater(end_y)
		var gap := FloatCheck.case_grip_gap(_case, grip)
		print("scale %.1f stall top: gap %.4f m, limit %.4f m" % [s, gap, _limit()])
		assert_float(gap).is_less_equal(_limit())
		# A real distance, not a default: the palm is FRONT_PALM_M over the top.
		assert_float(gap).is_greater(0.0)


func test_the_tip_from_the_top_to_the_handle_stays_on_the_grip() -> void:
	for s in SCALES:
		_stand(s)
		var from := CarryLead.stall_top(SecurityLooks.Kind.CASE, Vector3.ZERO, s)
		var to := CarryOnProps.grip_anchor(SecurityLooks.Kind.CASE)
		var worst := 0.0
		for n in 21:
			var w := n / 20.0
			var grip := _case.global_transform * CarryLead.case_tip_grip(from, to, w)
			worst = maxf(worst, FloatCheck.case_grip_gap(_case, grip))
		print("scale %.1f tip: largest gap %.4f m, limit %.4f m" % [s, worst, _limit()])
		assert_float(worst).is_less_equal(_limit())


func test_a_hand_off_the_top_end_or_beside_the_case_is_off() -> void:
	for s in SCALES:
		_stand(s)
		var xf := _case.global_transform
		var box := CarryOnProps.bag_box(SecurityLooks.Kind.CASE)
		var middle := box.get_center()
		var top := xf * CarryLead.stall_top(SecurityLooks.Kind.CASE, Vector3.ZERO, s)
		var lifted := top + Vector3.UP * OFF_M
		var side := xf * Vector3(box.end.x, middle.y, middle.z) + (xf.basis.x.normalized() * OFF_M)
		var back := xf * Vector3(middle.x, box.position.y, box.end.z - 0.05)
		for at: Vector3 in [lifted, side, back]:
			var gap := FloatCheck.case_grip_gap(_case, at)
			print("scale %.1f off: gap %.4f m, limit %.4f m" % [s, gap, _limit()])
			assert_float(gap).is_greater(_limit())
