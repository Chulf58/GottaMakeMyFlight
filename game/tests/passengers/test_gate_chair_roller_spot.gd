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
## Steps of the shuffle from the chair front onto the chair measured.
const SHUFFLE_STEPS := 10

## Per body (PassengerLooks.BODIES): its idle and its sit_idle poses, each the
## body's vertices in its own frame (facing +z).
var _idle: Array = []
var _sit: Array = []
## Per body: its sit_down clip from start to end (PHASES + 1 poses), the pose
## drawn at the chair front once the roller is down and through the shuffle
## onto the chair (the probe's HIT rows: clip sit_down at its end).
var _sit_down: Array = []
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
		for clip in ["idle", "sit_idle", "sit_down"]:
			player.play(clip)
			var poses: Array[PackedVector3Array] = []
			for n in PHASES + 1:
				if n == PHASES and clip != "sit_down":
					break
				player.seek(player.current_animation_length * n / PHASES, true)
				poses.append(TestRollerStandClearance._skinned(node))
			{"idle": _idle, "sit_idle": _sit, "sit_down": _sit_down}[clip].append(poses)
		node.free()


## Every body, either hand, one bag or two (TWO_BAG_SCALE, at its own side
## GateRoller.TWO_BAG_SIDE_M): no idle vertex of the walker standing at the
## chair front inside the lying roller's shell box, and the nearest one at least
## MARGIN_M off the box (printed per body, side and scale with the side it lies
## at).
func test_a_lying_roller_clears_every_body_s_legs() -> void:
	print("shell box %s, grown %.2f m" % [_shell, MARGIN_M])
	assert_float(_shell.size.x).is_greater(0.2)
	var hits := 0
	var least := INF
	for b in _idle.size():
		var line := "body %d %s" % [b, PassengerLooks.BODIES[b]]
		for hand in 2:
			for scale_by: float in [1.0, SecurityLooks.TWO_BAG_SCALE]:
				var side := GateRoller.side(b, hand, scale_by)
				var lying := _lying(hand, side)
				hits += _inside(_idle[b], Transform3D.IDENTITY, lying, scale_by)
				var gap := _gap(_idle[b], Transform3D.IDENTITY, lying, scale_by)
				least = minf(least, gap)
				line += (
					" %s x%.2f: side %.3f gap %.3f m"
					% [["right", "left"][hand], scale_by, side, gap]
				)
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
## up) on any of a row's three chairs has no vertex in its lying roller, one bag
## or two (each at its own side). Control:
## the roller moved under the seated knees (on the chair's line, ahead of the
## pan) holds many.
func test_a_lying_roller_clears_the_seated_body() -> void:
	var hits := 0
	for b in _sit.size():
		var own := 0
		for chair in GateChairs.CHAIR_OFFSET_M.size():
			for hand in 2:
				for scale_by: float in [1.0, SecurityLooks.TWO_BAG_SCALE]:
					var lying := _lying(hand, GateRoller.side(b, hand, scale_by))
					own += _inside(_sit[b], _seated(b, chair), lying, scale_by)
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


## The walker's feet through the whole shuffle from the chair front onto a
## chair whose seat lies to one side (board 4da2e8ff; GateChairs.offset() moves
## the body that far across as it goes back): no vertex in its lying roller,
## for every body, both ways of shuffle and both chair offsets
## (GateChairs.CHAIR_OFFSET_M 0.08 and 0.36), one bag or two, the roller on
## either side (ParkSide.gap_hand() lays it away from the shuffle first, but a
## taken gap or a two-bag guest's bag hand can put it on the shuffle side), at
## GateRoller.shuffle_side(). Poses: sit_down
## from start to end at the front, and sit_down's end and sit_idle at every
## SHUFFLE_STEPS share of the way. Control: on the shuffle side at
## GateRoller.side() (the spot before), the far slide takes in many vertices
## (the probe's 264 for pair1_b).
func test_a_lying_roller_clears_the_shuffle_onto_an_offset_chair() -> void:
	var hits := 0
	var control := 0
	for b in _sit.size():
		var line := "body %d %s shuffle:" % [b, PassengerLooks.BODIES[b]]
		for offset: float in [0.08, 0.36]:
			for way: float in [1.0, -1.0]:
				var slide := offset * way
				for scale_by: float in [1.0, SecurityLooks.TWO_BAG_SCALE]:
					for hand: int in [0, 1]:
						var side := GateRoller.shuffle_side(b, hand, scale_by, slide)
						var n := _shuffle_inside(b, slide, _lying(hand, side), scale_by)
						hits += n
						if n > 0:
							line += (
								" %+.2f %s x%.2f side %.3f: %d"
								% [slide, ["right", "left"][hand], scale_by, side, n]
							)
				if offset > 0.3:
					var toward := 1 if slide > 0.0 else 0
					var old := _lying(toward, GateRoller.side(b, toward))
					control += _shuffle_inside(b, slide, old, 1.0)
		print(line + (" none" if line.ends_with(":") else ""))
	print(
		"shuffle vertices inside %d (0); far slide on its side at side() %d (> 0)" % [hits, control]
	)
	assert_int(control).is_greater(0)
	assert_int(hits).is_equal(0)


## How many vertices of body `b` shuffling onto a chair `slide` m across lie in
## the shell box of a roller drawn at `lying` scaled `scale_by` (_inside()): the
## sit_down poses at the front, then its end pose and the sit_idle poses at
## each share of the way.
func _shuffle_inside(b: int, slide: float, lying: Transform3D, scale_by: float) -> int:
	var count := _inside(_sit_down[b], Transform3D.IDENTITY, lying, scale_by)
	var seated: Array = _sit[b].duplicate()
	seated.append(_sit_down[b][-1])
	for step in range(1, SHUFFLE_STEPS + 1):
		count += _inside(seated, _shuffled(b, slide, step / float(SHUFFLE_STEPS)), lying, scale_by)
	return count


## Where body `b` is drawn `share` of the way from the chair front onto a chair
## `slide` m across, in the chair front's frame: GateChairs.offset() at that
## share (the slide and SEAT_SHIFT_M) on the sim's way back to
## PassengerSim.SIT_FORWARD_M off the seat cell.
static func _shuffled(b: int, slide: float, share: float) -> Transform3D:
	var shift: Vector2 = PassengerLooks.SEAT_SHIFT_M[b]
	var back := -CELL_M + CELL_M * PassengerSim.SIT_FORWARD_M + shift.x
	return Transform3D(Basis.IDENTITY, Vector3(slide, shift.y, back) * share)


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


## The rollers of two two-bag guests at neighbouring chair fronts whose bags'
## fixed hands (SecurityLooks.hand_of()) face one gap fit in it at
## GateRoller.TWO_BAG_SIDE_M, for every pair of variants: the left guest's
## shell box, scaled, ends short of the right guest's (printed: the least
## clearance). GateRoller.reach() matches the boxes. Control: at LIE_SIDE_M
## (one-bag sides, the spot before) two male two-bag rollers overlap 0.0304 m.
func test_two_two_bag_rollers_fit_one_gap() -> void:
	var scale_by := SecurityLooks.TWO_BAG_SCALE
	assert_float(GateRoller.SHELL_HALF_M).is_equal_approx(_shell.size.x / 2.0, 0.0005)
	assert_float(_shell.get_center().x).is_equal_approx(0.0, 0.0005)
	var least := INF
	var widest := -INF
	for a in 2:
		for b in 2:
			var look_a := a * PassengerLooks.PER_VARIANT
			var look_b := b * PassengerLooks.PER_VARIANT
			# Guest A at the origin lays left (+x); guest B one front to the left
			# lays right, back toward A.
			var box_a := _box(_lying(1, GateRoller.side(look_a, 1, scale_by)), scale_by)
			var at_b := Transform3D(Basis.IDENTITY, Vector3(CELL_M, 0.0, 0.0))
			var box_b := _box(at_b * _lying(0, GateRoller.side(look_b, 0, scale_by)), scale_by)
			var clear := box_b.position.x - box_a.end.x
			var reached := (
				GateRoller.reach(look_a, 1, scale_by) + GateRoller.reach(look_b, 0, scale_by)
			)
			assert_float(CELL_M - reached).is_equal_approx(clear, 0.001)
			least = minf(least, clear)
			widest = maxf(widest, reached)
	var old := GateRoller.side(0, 0) + GateRoller.side(0, 1) + _shell.size.x * scale_by - CELL_M
	print(
		(
			(
				"two-bag rollers facing one gap: least clearance %.3f m (> 0), widest reach %.3f m;"
				+ " at the one-bag sides two male ones overlap %.4f m (> 0)"
			)
			% [least, widest, old]
		)
	)
	assert_float(old).is_greater(0.0)
	assert_float(least).is_greater(0.0)


## The shell box (not grown) of a roller drawn at `lying` scaled `scale_by`,
## in the frame `lying` is given in.
func _box(lying: Transform3D, scale_by: float) -> AABB:
	return lying.scaled_local(Vector3.ONE * scale_by) * _shell


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
## drawn at `lying` and scaled `scale_by` to a vertex of `poses` (a body drawn
## at `body`) at its height and along its length, in metres; 0 for a vertex
## inside.
func _gap(poses: Array, body: Transform3D, lying: Transform3D, scale_by := 1.0) -> float:
	var to_bag := lying.scaled_local(Vector3.ONE * scale_by).affine_inverse() * body
	var least := INF
	for points: PackedVector3Array in poses:
		for v in points:
			var at := to_bag * v
			if at.y < _shell.position.y or at.y > _shell.end.y:
				continue
			if at.z < _shell.position.z or at.z > _shell.end.z:
				continue
			var across := maxf(_shell.position.x - at.x, at.x - _shell.end.x)
			least = minf(least, maxf(0.0, across) * scale_by)
	return least
