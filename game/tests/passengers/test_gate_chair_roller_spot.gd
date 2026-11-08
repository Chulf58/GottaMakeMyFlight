extends GdUnitTestSuite
## A roller laid down at a gate chair (RollerPark.floor_spot(), GateRoller.spot())
## lies clear of the legs of its walker standing at the chair front, of the
## same walker seated, and of a male guest at the neighbouring chair front
## (board 1fe04f01: at BESIDE_FEET_M 0.34 m the shell took in the near leg of
## every male body). Geometric, as test_roller_stand_clearance: each body's idle
## and sit_idle clips posed at PHASES points and skinned by hand
## (TestRollerStandClearance._skinned()), and no vertex may lie in the roller
## shell's box (its meshes but the rods) grown by MARGIN_M. Everything is in
## the chair front's frame of a seat row at facing 0: the front cell's centre
## at the origin, out of the chair +z, the row along x, cells 1 m apart.

const PHASES := 8
const MARGIN_M := 0.01
## The gate chair spot before board 1fe04f01, for the control.
const OLD_SIDE_M := 0.34
## How far apart two neighbouring chair fronts are (one cell).
const CELL_M := 1.0

## Per body (PassengerLooks.BODIES): its idle and its sit_idle poses, each the
## body's vertices in its own frame (facing +z).
var _idle: Array = []
var _sit: Array = []
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
		for clip in ["idle", "sit_idle"]:
			player.play(clip)
			var poses: Array[PackedVector3Array] = []
			for n in PHASES:
				player.seek(player.current_animation_length * n / PHASES, true)
				poses.append(TestRollerStandClearance._skinned(node))
			(_idle if clip == "idle" else _sit).append(poses)
		node.free()


## Every body, either hand, one bag or two (TWO_BAG_SCALE): no idle vertex of
## the walker standing at the chair front inside the lying roller's shell box,
## and the nearest one at least MARGIN_M off the box (printed per body and side
## with the side it lies at).
func test_a_lying_roller_clears_every_body_s_legs() -> void:
	print("shell box %s, grown %.2f m" % [_shell, MARGIN_M])
	assert_float(_shell.size.x).is_greater(0.2)
	var hits := 0
	var least := INF
	for b in _idle.size():
		var line := "body %d %s" % [b, PassengerLooks.BODIES[b]]
		for hand in 2:
			var side := GateRoller.side(b, hand)
			var lying := _lying(hand, side)
			for scale_by in [1.0, SecurityLooks.TWO_BAG_SCALE]:
				hits += _inside(_idle[b], Transform3D.IDENTITY, lying, scale_by)
			var gap := _gap(_idle[b], Transform3D.IDENTITY, lying)
			least = minf(least, gap)
			line += " %s: side %.3f gap %.3f m" % [["right", "left"][hand], side, gap]
		print(line)
	print("vertices inside %d (0), least gap %.3f m (>= %.2f)" % [hits, least, MARGIN_M])
	assert_int(hits).is_equal(0)
	assert_float(least).is_greater_equal(MARGIN_M)


## Discriminating control: at the old spot (OLD_SIDE_M on either side) the
## shell box takes in vertices of every male body on both sides and of a
## female body on her right, so the count above sees the defect.
func test_the_old_spot_fails_for_the_male_bodies() -> void:
	var counts := [[0, 0], [0, 0]]
	for b in _idle.size():
		var line := "body %d %s at %.2f m:" % [b, PassengerLooks.BODIES[b], OLD_SIDE_M]
		for hand in 2:
			var n := _inside(_idle[b], Transform3D.IDENTITY, _lying(hand, OLD_SIDE_M), 1.0)
			line += " %s %d" % [["right", "left"][hand], n]
			if n > 0:
				counts[b / PassengerLooks.PER_VARIANT][hand] += 1
		print(line)
	print("bodies with vertices inside [variant][hand]: %s" % [counts])
	assert_int(counts[0][0]).is_equal(PassengerLooks.PER_VARIANT)
	assert_int(counts[0][1]).is_equal(PassengerLooks.PER_VARIANT)
	assert_int(counts[1][0]).is_greater(0)


## The same walker seated on its chair (sit_idle, drawn where GateChairs.offset()
## and PassengerSim.SIT_FORWARD_M put it, PassengerLooks.SEAT_SHIFT_M ahead and
## up) on any of a row's three chairs has no vertex in its lying roller. Control:
## the roller moved under the seated knees (on the chair's line, ahead of the
## pan) holds many.
func test_a_lying_roller_clears_the_seated_body() -> void:
	var hits := 0
	for b in _sit.size():
		var own := 0
		for chair in GateChairs.CHAIR_OFFSET_M.size():
			for hand in 2:
				own += _inside(
					_sit[b], _seated(b, chair), _lying(hand, GateRoller.side(b, hand)), 1.0
				)
		hits += own
		var under := Transform3D(
			Basis.IDENTITY, _seated(b, 1).origin * Vector3(1, 0, 0) + Vector3(0, 0, -0.4)
		)
		var control := _inside(_sit[b], _seated(b, 1), under, 1.0)
		print(
			(
				"body %d %s seated: inside the lying roller %d (0), under the knees %d (> 0)"
				% [b, PassengerLooks.BODIES[b], own, control]
			)
		)
		assert_int(control).is_greater(0)
	assert_int(hits).is_equal(0)


## Two male guests at neighbouring chair fronts: a roller lying on the side
## toward the neighbour clears the neighbour's legs, standing at his front
## or seated on his chair, for every pair of male bodies and every pair of
## neighbouring chairs (in a row, and across the joint of two rows). Printed:
## the least gap to the neighbour's legs, and how far two rollers lying toward
## each other from the two fronts overlap (a bag on a bag, not a leg).
func test_a_lying_roller_clears_the_neighbour_at_the_next_chair() -> void:
	var hits := 0
	var least := INF
	var pairs := [[0, 1], [1, 2], [2, 0]]
	for b in PassengerLooks.PER_VARIANT:
		for n in PassengerLooks.PER_VARIANT:
			for hand in 2:
				var out := -1.0 if hand == 0 else 1.0
				var lying := _lying(hand, GateRoller.side(b, hand))
				var standing := Transform3D(Basis.IDENTITY, Vector3(out * CELL_M, 0.0, 0.0))
				hits += _inside(_idle[n], standing, lying, 1.0)
				least = minf(least, _gap(_idle[n], standing, lying))
				for pair: Array in pairs:
					# Toward +x (the left hand) ours is pair[0] and his pair[1];
					# toward -x ours is pair[1] and his pair[0].
					var theirs: int = pair[1] if hand == 1 else pair[0]
					var seated := (
						Transform3D(Basis.IDENTITY, Vector3(out * CELL_M, 0.0, 0.0))
						* _seated(n, theirs)
					)
					hits += _inside(_sit[n], seated, lying, 1.0)
	var overlap := GateRoller.side(0, 0) + GateRoller.side(0, 1) + _shell.size.x - CELL_M
	print(
		(
			(
				"male neighbours: vertices inside %d (0), least gap to his standing legs"
				+ " %.3f m (>= %.2f); two male rollers lying toward each other overlap %.3f m"
			)
			% [hits, least, MARGIN_M, overlap]
		)
	)
	assert_int(hits).is_equal(0)
	assert_float(least).is_greater_equal(MARGIN_M)


## A roller lying flat at a gate chair `side` out on `hand`'s side,
## RollerPark.FEET_AHEAD_M ahead (GateRoller.spot()).
static func _lying(hand: int, side: float) -> Transform3D:
	var out := -1.0 if hand == 0 else 1.0
	return Transform3D(Basis.IDENTITY, Vector3(out * side, 0.0, RollerPark.FEET_AHEAD_M))


## Where body `b` is drawn seated on chair `chair` (footprint index) of a row
## at facing 0, in the chair front's frame: the sim's seat spot
## (PassengerSim.SIT_FORWARD_M from the seat cell toward the front) plus
## GateChairs.offset() in full (the chair's sideways step and the body's own
## SEAT_SHIFT_M).
static func _seated(b: int, chair: int) -> Transform3D:
	var shift: Vector2 = PassengerLooks.SEAT_SHIFT_M[b]
	var ahead := -CELL_M + CELL_M * PassengerSim.SIT_FORWARD_M + shift.x
	return Transform3D(Basis.IDENTITY, Vector3(GateChairs.CHAIR_OFFSET_M[chair], shift.y, ahead))


## How many vertices of `poses` (a body drawn at `body`) lie in the shell box
## of a roller drawn at `lying` and scaled `scale_by`, grown by MARGIN_M.
func _inside(poses: Array, body: Transform3D, lying: Transform3D, scale_by: float) -> int:
	var box := _shell.grow(MARGIN_M / scale_by)
	var to_bag := lying.scaled_local(Vector3.ONE * scale_by).affine_inverse() * body
	var count := 0
	for points: PackedVector3Array in poses:
		for v in points:
			count += int(box.has_point(to_bag * v))
	return count


## The least distance across (x) from the shell box (not grown) of a roller
## drawn at `lying` to a vertex of `poses` (a body drawn at `body`) at its
## height and along its length; 0 for a vertex inside.
func _gap(poses: Array, body: Transform3D, lying: Transform3D) -> float:
	var to_bag := lying.affine_inverse() * body
	var least := INF
	for points: PackedVector3Array in poses:
		for v in points:
			var at := to_bag * v
			if at.y < _shell.position.y or at.y > _shell.end.y:
				continue
			if at.z < _shell.position.z or at.z > _shell.end.z:
				continue
			least = minf(least, maxf(0.0, maxf(_shell.position.x - at.x, at.x - _shell.end.x)))
	return least
