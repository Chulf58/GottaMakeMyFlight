class_name TestRollerStandClearance
extends GdUnitTestSuite
## A roller stood up in a queue (RollerPark.queue_park()) stands clear of its
## walker's own body, for every body type (board 03454587: a male file waiter
## had 4 of his body points inside his stood roller, which was drawn over his
## near leg). Geometric: each body's idle clip is posed at PHASES points of its
## length and skinned by hand here (a headless bake has no skin, anti-pattern
## a-headless-count-of-body-points-inside-a-carried-bag-reads-0), and no vertex
## may lie inside the roller shell's box (its meshes but the rods, grown by
## MARGIN_M) parked for either hand. The box holds the rounded shell, so it is
## the stricter test; the windowed BODY_IN_STOOD_BAG count (spike/
## roller_queue_probe.gd) is the drawn one. The seat park's side
## (RollerPark.SEAT_SIDE_M, board 8a6068aa) is derived and checked the same
## way; the windowed food_seats_probe BODY_IN_BAG count is its drawn one.

const PHASES := 8
const MARGIN_M := 0.01
## The side distances test_print_the_seat_side_each_body_needs() scans.
const SCAN_FROM_M := 0.25
const SCAN_TO_M := 0.6
const SCAN_STEP_M := 0.005
## The most idle vertices of a male body the capped roller at a booth end panel
## may hold, in the shell box not grown (MARGIN_M would make the panel the limit:
## grown, 12 to 20 vertices, 316 for male_08, at a 1 cm panel gap).
const CAPPED_MAX := 0

## Per body (PassengerLooks.BODIES): its idle poses, each the body's vertices
## in its own frame (facing +z).
var _poses: Array = []
## The roller shell's box in the roller's own frame (its rods left out).
var _shell := AABB()


func before() -> void:
	var roller := InteriorKit.instantiate("carry_roller")
	add_child(roller)
	var rods: Array = CarryOnProps.REACH_NODES[SecurityLooks.Kind.ROLLER]
	var first := true
	for mi: MeshInstance3D in roller.find_children("*", "MeshInstance3D", true, false):
		var in_rods := false
		var at: Node = mi
		while at != roller:
			in_rods = in_rods or at.name in rods
			at = at.get_parent()
		if in_rods or mi.mesh == null:
			continue
		var part := (
			roller.global_transform.affine_inverse() * mi.global_transform * mi.mesh.get_aabb()
		)
		_shell = part if first else _shell.merge(part)
		first = false
	roller.free()
	for b in PassengerLooks.BODIES.size():
		var node := PassengerLooks.SCENES[b].instantiate() as Node3D
		add_child(node)
		var player := node.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		player.play("idle")
		var poses: Array[PackedVector3Array] = []
		for n in PHASES:
			player.seek(player.current_animation_length * n / PHASES, true)
			poses.append(_skinned(node))
		_poses.append(poses)
		node.free()


## Every body type, either hand, one bag or two (TWO_BAG_SCALE): no vertex of
## the idle body inside the stood roller's shell box. Control: the same box
## parked on the body's centre line holds many of its vertices.
func test_a_stood_roller_clears_every_body() -> void:
	print("shell box %s, grown %.2f m" % [_shell, MARGIN_M])
	assert_float(_shell.size.x).is_greater(0.2)
	var hits := 0
	for b in _poses.size():
		var worst := [0, 0]
		var centred := 0
		for scale_by in [1.0, SecurityLooks.TWO_BAG_SCALE]:
			for hand in 2:
				var parked := RollerPark.queue_park(Transform3D.IDENTITY, hand, scale_by, b)
				for points: PackedVector3Array in _poses[b]:
					worst[hand] = maxi(worst[hand], _inside(points, parked, scale_by))
		var centre := RollerPark.park(Transform3D.IDENTITY, 0, 1.0, RollerPark.PARK_AHEAD_M, 0.0)
		centred = _inside(_poses[b][0], centre, 1.0)
		print(
			(
				"body %d %s: vertices inside the stood roller right %d left %d (0); centred %d (> 0)"
				% [b, PassengerLooks.BODIES[b], worst[0], worst[1], centred]
			)
		)
		hits += worst[0] + worst[1]
		assert_int(centred).is_greater(0)
	assert_int(hits).is_equal(0)


## Discriminating control: the old spot (PARK_SIDE_M, 0.32 m out, as every
## queue stand parked before board 03454587) takes in male_08's near leg, so
## the shell box count above sees the defect it was written for.
func test_the_old_park_side_fails_for_male_08() -> void:
	var b := PassengerLooks.BODIES.find("tcp_male_character_08")
	assert_int(b).is_greater_equal(0)
	var hits := 0
	for hand in 2:
		# queue_park() at an upright frame, with the old side.
		var parked := RollerPark.park(
			Transform3D.IDENTITY, hand, 1.0, RollerPark.PARK_AHEAD_M, RollerPark.PARK_SIDE_M
		)
		for points: PackedVector3Array in _poses[b]:
			hits += _inside(points, parked, 1.0)
	print(
		(
			"body %d %s at PARK_SIDE_M %.2f: %d vertices inside (> 0)"
			% [b, PassengerLooks.BODIES[b], RollerPark.PARK_SIDE_M, hits]
		)
	)
	assert_int(hits).is_greater(0)


## park() keeps PARK_SIDE_M as its default and its ahead (decisions e4e88745
## and 211c0142 pin the spot beside the feet); the side a seat park takes is
## the body's (SEAT_SIDE_M, board 8a6068aa): wider for a male body, the same
## for a female one, and a queue stand's is its own. Changed from "the seat
## parks keep PARK_SIDE_M" when the male seat side was found in the near leg
## at booth 13-3 (BODY_IN_BAG up to 112 points).
func test_the_seat_park_side_is_the_body_s() -> void:
	var seat := RollerPark.park(Transform3D.IDENTITY, 0, 1.0)
	var axle := seat * CarryOnProps.ROLLER_AXLE
	print(
		(
			"seat park axle %s, seat sides %s, queue sides %s"
			% [axle, RollerPark.SEAT_SIDE_M, RollerPark.QUEUE_SIDE_M]
		)
	)
	assert_float(axle.x).is_equal_approx(-RollerPark.PARK_SIDE_M, 0.0001)
	assert_float(axle.z).is_equal_approx(RollerPark.PARK_AHEAD_M, 0.0001)
	for hand in 2:
		assert_float(RollerPark.seat_side(0, hand)).is_greater(RollerPark.PARK_SIDE_M)
		assert_float(RollerPark.seat_side(PassengerLooks.PER_VARIANT, hand)).is_equal(
			RollerPark.PARK_SIDE_M
		)
	for b in [0, PassengerLooks.PER_VARIANT]:
		var queue := RollerPark.queue_park(Transform3D.IDENTITY, 1, 1.0, b)
		assert_float((queue * CarryOnProps.ROLLER_AXLE).x).is_greater(RollerPark.PARK_SIDE_M)


## A male body's seat park (RollerPark.seat_side()) holds none of his idle
## vertices for either hand, one bag or two, standing (park()) or lying beside
## his feet at a booth (floor_spot()). At a booth whose end panel is on his
## left (booth 13-3: the seat root 1 m across, the panel's face 0.58 m) the
## left side is capped (BoothRoller.panel_cap()), keeps PANEL_GAP_M off the
## panel's face, and holds no more than CAPPED_MAX of his vertices (box not grown) standing or
## lying, where the old PARK_SIDE_M held hundreds (the control).
func test_a_male_seat_park_clears_his_legs_and_the_booth_end_panel() -> void:
	var hits := 0
	for b in PassengerLooks.PER_VARIANT:
		for scale_by in [1.0, SecurityLooks.TWO_BAG_SCALE]:
			for hand in 2:
				var side := RollerPark.seat_side(b, hand)
				var stood := RollerPark.park(
					Transform3D.IDENTITY, hand, scale_by, RollerPark.PARK_AHEAD_M, side
				)
				var lying := _lying(hand, side, 0.0).scaled_local(Vector3.ONE * scale_by)
				for points: PackedVector3Array in _poses[b]:
					hits += _inside(points, stood, scale_by) + _inside(points, lying, scale_by)
	print("male seat parks: %d vertices inside (0)" % hits)
	assert_int(hits).is_equal(0)
	var cap := BoothRoller.panel_cap(1.0)
	var half := maxf(-_shell.position.x, _shell.end.x)
	var face := 1.0 - BoothRoller.PANEL_FACE_M
	var capped := minf(RollerPark.seat_side(0, 1), cap)
	print(
		(
			"booth end panel face %.3f m, cap %.3f m, male left %.3f m, outer edge %.3f m"
			% [face, cap, capped, capped + half]
		)
	)
	assert_float(capped).is_less(RollerPark.seat_side(0, 1))
	assert_float(capped + half).is_less_equal(face - BoothRoller.PANEL_GAP_M + 0.0001)
	for b in PassengerLooks.PER_VARIANT:
		var at_cap := 0
		var old := 0
		for side_and_count in [[capped, true], [RollerPark.PARK_SIDE_M, false]]:
			var side: float = side_and_count[0]
			var stood := RollerPark.park(
				Transform3D.IDENTITY, 1, 1.0, RollerPark.PARK_AHEAD_M, side
			)
			var n := 0
			for points: PackedVector3Array in _poses[b]:
				n += (
					_inside(points, stood, 1.0, 0.0)
					+ _inside(points, _lying(1, side, 0.0), 1.0, 0.0)
				)
			if side_and_count[1]:
				at_cap = n
			else:
				old = n
		print(
			(
				"body %d %s left at the booth end panel: %d vertices inside (<= %d); at PARK_SIDE_M %d (> 0)"
				% [b, PassengerLooks.BODIES[b], at_cap, CAPPED_MAX, old]
			)
		)
		assert_int(at_cap).is_less_equal(CAPPED_MAX)
		assert_int(old).is_greater(0)


## A seat park (pull>floor, either hand) stands at the side CarryOnProps noted
## for its hand ("side_now", BoothRoller.side_m()) when the move was stamped,
## and a later note does not move it. Control: with no note it stands at
## PARK_SIDE_M.
func test_a_seat_park_stands_at_the_side_its_stamp_kept() -> void:
	var hand_home := SecurityLooks.Home.HAND
	var floor := SecurityLooks.Home.FLOOR
	var pull := SecurityLooks.Carry.PULL
	var noted := [0.40, 0.43]
	var looks := {"scale": 1.0, "bar_z": 0.9, "grips": [Vector3.ZERO, Vector3.ZERO]}
	var start := Transform3D(Basis.IDENTITY, Vector3(0.3, 0.0, -0.5))
	var k := (RollerPark.STAND_END + RollerPark.LAY_END) / 2.0
	for hand in 2:
		var out := -1.0 if hand == 0 else 1.0
		for note in [true, false]:
			var bag := {
				"kind": SecurityLooks.Kind.ROLLER,
				"led": true,
				"from": Transform3D(),
				"was": (hand_home * 2 + hand) * 2,
				"carry_from": pull,
				"place": (floor * 2 + hand) * 2,
				"carry": pull,
			}
			if note:
				bag["side_now"] = noted.duplicate()
			CarryLead.stamp_move(bag, false, floor, Transform3D.IDENTITY)
			bag["home"] = bag["place"]
			bag["side_now"] = [0.25, 0.25]
			var plan := RollerPark.plan(
				bag, k, start, start, Transform3D.IDENTITY, {"to_floor": true}, looks
			)
			var axle := (plan["xf"] as Transform3D) * CarryOnProps.ROLLER_AXLE
			var want: float = noted[hand] if note else RollerPark.PARK_SIDE_M
			print("hand %d noted %s: parked axle x %.3f (%.3f)" % [hand, note, axle.x, out * want])
			assert_float(axle.x).is_equal_approx(out * want, 0.0001)


## The derivation of RollerPark.SEAT_SIDE_M (printed): per body and hand, the
## least side distance (SCAN_STEP_M apart) at which no idle vertex lies in the
## shell box of the roller parked standing (park(), PARK_AHEAD_M ahead) or
## lying at a booth's approach (BoothRoller: along the guest's line, beside the
## feet) or at a gate chair (RollerPark.floor_spot(): FEET_AHEAD_M ahead).
func test_print_the_seat_side_each_body_needs() -> void:
	var worst := {}
	for b in _poses.size():
		var line := "body %d %s needs" % [b, PassengerLooks.BODIES[b]]
		for hand in 2:
			var stand := _clear_side(
				b,
				hand,
				func(s: float) -> Transform3D:
					return RollerPark.park(
						Transform3D.IDENTITY, hand, 1.0, RollerPark.PARK_AHEAD_M, s
					)
			)
			var booth := _clear_side(
				b, hand, func(s: float) -> Transform3D: return _lying(hand, s, 0.0)
			)
			var gate := _clear_side(
				b,
				hand,
				func(s: float) -> Transform3D: return _lying(hand, s, RollerPark.FEET_AHEAD_M)
			)
			line += (
				" %s: stand %.3f booth %.3f gate %.3f"
				% [["right", "left"][hand], stand, booth, gate]
			)
			var key := "%d %d" % [b / PassengerLooks.PER_VARIANT, hand]
			worst[key] = maxf(float(worst.get(key, 0.0)), maxf(stand, booth))
		print(line)
	print(
		(
			"widest need per [variant hand]: %s; gate chair spot %.2f"
			% [worst, RollerPark.BESIDE_FEET_M]
		)
	)
	assert_int(worst.size()).is_equal(4)


## The least side (from SCAN_FROM_M by SCAN_STEP_M) at which `placed` (a side
## to the roller's transform) holds none of body `b`'s idle vertices in any phase.
func _clear_side(b: int, _hand: int, placed: Callable) -> float:
	var side := SCAN_FROM_M
	while side < SCAN_TO_M:
		var hits := 0
		var xf: Transform3D = placed.call(side)
		for points: PackedVector3Array in _poses[b]:
			hits += _inside(points, xf, 1.0)
		if hits == 0:
			return side
		side += SCAN_STEP_M
	return INF


## A roller lying on its back along the guest's line `side` out on `hand`'s
## side and `ahead`, as RollerPark.floor_spot() lays it at a booth or gate chair.
static func _lying(hand: int, side: float, ahead: float) -> Transform3D:
	var out := -1.0 if hand == 0 else 1.0
	return Transform3D(Basis.IDENTITY, Vector3(out * side, 0.0, ahead))


## How many of `points` lie in the shell box of a roller drawn at `parked`.
func _inside(
	points: PackedVector3Array, parked: Transform3D, scale_by: float, margin := MARGIN_M
) -> int:
	var box := _shell.grow(margin / scale_by)
	var to_bag := parked.affine_inverse()
	var count := 0
	for v in points:
		count += int(box.has_point(to_bag * v))
	return count


## The vertices of `node`'s body mesh in the pose its skeleton holds now,
## skinned by hand (linear blend), in `node`'s frame.
static func _skinned(node: Node3D) -> PackedVector3Array:
	var mi := PassengerLooks.body_mesh(node)
	var skeleton := mi.get_node(mi.skeleton) as Skeleton3D
	var to_node := node.global_transform.affine_inverse() * skeleton.global_transform
	var mats: Array[Transform3D] = []
	for bind in mi.skin.get_bind_count():
		var name := mi.skin.get_bind_name(bind)
		var bone := skeleton.find_bone(name) if name != "" else mi.skin.get_bind_bone(bind)
		mats.append(to_node * skeleton.get_bone_global_pose(bone) * mi.skin.get_bind_pose(bind))
	var out := PackedVector3Array()
	for s in mi.mesh.get_surface_count():
		var arrays := mi.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / verts.size()
		for k in verts.size():
			var v := Vector3.ZERO
			for j in per:
				v += (mats[bones[k * per + j]] * verts[k]) * weights[k * per + j]
			out.append(v)
	return out
