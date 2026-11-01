class_name TestCarryStallCaseGrip
extends GdUnitTestSuite
## A hard case standing in a toilet stall is on its grip when the hand holds it
## by the middle of its top end, and as it tips into the carry with the palm on
## its top, over the top front edge to the handle (decision toilet-stall-bag-
## moves-are-hand-led-as-built-a-hard-case-is; board item e845dfe8: the probes'
## GRIP_ON check knew only the handle face and read that grip 0.137 m off). The
## top end counts only in a stall move (conductor ruling 2026-11-01): a side
## carry with the palm on the case's top end is off. The check reads the case's
## grip from its drawn body mesh (FloatCheck.case_handle_points()), never from
## the placement. Controls: a hand beside the case's side face, one lifted off
## its top and one beside its back face (away from the handle) read off.

const FloatCheck := preload("res://spike/carry_float_check.gd")
const OFF_M := 0.10
## A body drawn smaller and larger than the default, as passengers are.
const SCALES: Array[float] = [0.9, 1.1]
## Turned off the axes and moved off the origin, so a frame mix-up shows.
const YAW := 0.7
const AT := Vector3(3.0, 0.2, -98.0)

var _case: Node3D


func before_test() -> void:
	_case = InteriorKit.instantiate(SecurityLooks.KIND_PIECES[SecurityLooks.Kind.CASE]) as Node3D
	add_child(_case)


func after_test() -> void:
	_case.free()
	_case = null


## The case standing on its end in a stall: its own z (its length) up.
func _upright() -> Basis:
	return Basis(Vector3.RIGHT, -PI / 2.0).rotated(Vector3.UP, YAW)


## Lying flat in the front carry: its handle face (own y) up.
func _flat() -> Basis:
	return Basis(Vector3.UP, YAW)


## The case drawn with `basis` at `scale_by`.
func _place(basis: Basis, scale_by: float) -> void:
	_case.global_transform = Transform3D(basis.scaled(Vector3.ONE * scale_by), AT)


func _limit() -> float:
	return FloatCheck.GRIP_ON_M + CarryOnProps.FRONT_PALM_M


## The highest point of the case's body mesh as drawn now (world).
func _top_y() -> float:
	var body := _case.find_child("CarryOnBag_Body", true, false) as MeshInstance3D
	var top := -INF
	for v: Vector3 in body.mesh.get_faces():
		top = maxf(top, (body.global_transform * v).y)
	return top


func test_the_stall_top_hold_is_on_the_grip() -> void:
	for s in SCALES:
		_place(_upright(), s)
		var top := CarryLead.stall_top(SecurityLooks.Kind.CASE, Vector3.ZERO, s)
		var grip := _case.global_transform * top
		# The palm on the case's top end: the grip FRONT_PALM_M over it.
		var over := grip.y - _top_y()
		var gap := FloatCheck.case_grip_gap(_case, grip, true)
		print(
			(
				"scale %.1f stall top: %.4f m over the case, gap %.4f m, limit %.4f m"
				% [s, over, gap, _limit()]
			)
		)
		assert_float(over).is_equal_approx(CarryOnProps.FRONT_PALM_M, 0.002)
		assert_float(gap).is_less_equal(_limit())
		# A real distance, not a default.
		assert_float(gap).is_greater(0.0)


## The tip as CarryLead.plan() draws it: the case turned from standing to flat
## (path(): its basis blended by stall_tip()), the grip from case_tip_grip()
## with the palm's world up in the case's frame. Every step the grip is on the
## case's own grip (a stall move) and over the case's highest point by at most
## FRONT_PALM_M and at least 1.5 cm: the palm on its top, never beside it.
func test_the_tip_keeps_the_palm_on_the_cases_top() -> void:
	var palm_up := Vector3.UP * CarryOnProps.FRONT_PALM_M
	for s in SCALES:
		var start := _upright().scaled(Vector3.ONE * s)
		var want := _flat().scaled(Vector3.ONE * s)
		var from := CarryLead.stall_top(SecurityLooks.Kind.CASE, Vector3.ZERO, s)
		var to := Vector3(0.0, CarryOnProps.bag_box().end.y + CarryOnProps.FRONT_PALM_M / s, 0.0)
		var worst := 0.0
		var lowest := INF
		var highest := -INF
		for n in 21:
			var w := n / 20.0
			var basis := Transform3D(start, AT).interpolate_with(Transform3D(want, AT), w).basis
			_case.global_transform = Transform3D(basis, AT)
			var local := CarryLead.case_tip_grip(
				from,
				to,
				w,
				basis.inverse() * palm_up,
				start.inverse() * palm_up,
				want.inverse() * palm_up
			)
			var grip := _case.global_transform * local
			worst = maxf(worst, FloatCheck.case_grip_gap(_case, grip, true))
			var over := grip.y - _top_y()
			lowest = minf(lowest, over)
			highest = maxf(highest, over)
			if n == 0:
				assert_vector(local).is_equal_approx(from, Vector3.ONE * 0.0001)
			if n == 20:
				assert_vector(local).is_equal_approx(to, Vector3.ONE * 0.0001)
		print(
			(
				"scale %.1f tip: largest gap %.4f m (limit %.4f), grip %.4f to %.4f m over the case"
				% [s, worst, _limit(), lowest, highest]
			)
		)
		assert_float(worst).is_less_equal(_limit())
		assert_float(lowest).is_greater_equal(0.015)
		assert_float(highest).is_less_equal(CarryOnProps.FRONT_PALM_M + 0.002)


## Outside a stall move the top end is not a grip: a side-carried case (upright,
## its handle face to the body, CarryOnProps.carried()) with the palm on its top
## end is off, though the same grip is on in a stall move.
func test_a_palm_on_the_top_end_outside_a_stall_move_is_off() -> void:
	for s in SCALES:
		var centre := AT + Basis(Vector3.UP, YAW) * Vector3(-0.3, 0.0, 0.0)
		var side := CarryOnProps.carried(AT, centre, YAW, s)
		_case.global_transform = side
		var middle := CarryOnProps.bag_box().get_center()
		var on_top := (
			side * Vector3(middle.x, middle.y, CarryOnProps.bag_box().end.z)
			+ Vector3.UP * CarryOnProps.FRONT_PALM_M
		)
		var off := FloatCheck.case_grip_gap(_case, on_top)
		var in_stall := FloatCheck.case_grip_gap(_case, on_top, true)
		# Control: the side carry's own grip (the handle edge at the hand) is on.
		var held := FloatCheck.case_grip_gap(_case, AT)
		print(
			(
				(
					"scale %.1f side carry: palm on the top end %.4f m (in a stall move %.4f m),"
					+ " at the handle %.4f m, limit %.4f m"
				)
				% [s, off, in_stall, held, _limit()]
			)
		)
		assert_float(off).is_greater(_limit())
		assert_float(in_stall).is_less_equal(_limit())
		assert_float(held).is_less_equal(_limit())


func test_a_hand_off_the_top_end_or_beside_the_case_is_off() -> void:
	for s in SCALES:
		_place(_upright(), s)
		var xf := _case.global_transform
		var box := CarryOnProps.bag_box(SecurityLooks.Kind.CASE)
		var middle := box.get_center()
		var top := xf * CarryLead.stall_top(SecurityLooks.Kind.CASE, Vector3.ZERO, s)
		var lifted := top + Vector3.UP * OFF_M
		var side := xf * Vector3(box.end.x, middle.y, middle.z) + (xf.basis.x.normalized() * OFF_M)
		var back := xf * Vector3(middle.x, box.position.y, box.end.z - 0.05)
		for at: Vector3 in [lifted, side, back]:
			var gap := FloatCheck.case_grip_gap(_case, at, true)
			print("scale %.1f off: gap %.4f m, limit %.4f m" % [s, gap, _limit()])
			assert_float(gap).is_greater(_limit())


## CarryLead's case measures match the drawn mesh: its body's top front edge is
## cut off STALL_CASE_CHAMFER_M both ways from STALL_CASE_DEPTH_M deep.
func test_the_case_measures_match_its_mesh() -> void:
	var body := _case.find_child("CarryOnBag_Body", true, false) as MeshInstance3D
	var end := CarryOnProps.bag_box().end.z
	var depth := CarryLead.STALL_CASE_DEPTH_M
	var cut := CarryLead.STALL_CASE_CHAMFER_M
	var on_end := false
	var on_face := false
	for v: Vector3 in body.mesh.get_faces():
		var p := body.transform * v
		on_end = on_end or (absf(p.y - (depth - cut)) < 0.002 and absf(p.z - end) < 0.002)
		on_face = on_face or (absf(p.y - depth) < 0.002 and absf(p.z - (end - cut)) < 0.002)
	assert_bool(on_end).is_true()
	assert_bool(on_face).is_true()
