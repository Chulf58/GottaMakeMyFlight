class_name TestCarryWornShoulder
extends GdUnitTestSuite
## CarryWorn.shoulder() stepped through a hand-led floor>shoulder move
## (CarryLead.plan()): the worn end keeps the strap bar on the joint, upright
## and leaning. Pure, no scene. (The rig-level check that runs against main
## too is TestCarryWornRig.)


## A tote picked up off the floor onto the left shoulder (floor>shoulder.L,
## outside a stall), stepped through CarryLead.plan() over k 0 to 1 (0.01
## apart) with the shoulder joint where it stands upright and where it was
## drawn leaning in (stall_float_probe, seed 2486925799, passenger 3114: the
## other hand reaching low drew the left Arm bone 0.09 m from the centre line,
## CarryWorn.shoulder() given that shift as the stoop's):
## at every k the bag rests at its start, is placed from the holding hand, or is
## worn, its drawn strap bar (Strap_Top, the strap stretched as CarryOnProps
## stretches it) within the FLOAT check's 0.2 m of the joint. Worn by a joint
## leaning in, it tilts about its strap's root with its bottom no nearer the
## hip than upright. Control: the worn end is reached and checked.
func test_a_tote_put_on_the_shoulder_from_the_floor_is_worn_at_every_k() -> void:
	var kind := SecurityLooks.Kind.SHOULDER
	var node := InteriorKit.instantiate(SecurityLooks.KIND_PIECES[kind])
	var reach_node := node.find_child("Strap_Reach", true, false) as Node3D
	var top_node := node.find_child("Strap_Top", true, false) as Node3D
	var base := reach_node.position
	var top_base := CarryOnProps._in_piece(top_node, node).origin
	node.free()
	var box := CarryOnProps.bag_box(kind)
	var bag := {
		"kind": kind,
		"was": (SecurityLooks.Home.FLOOR * 2 + 1) * 2,
		"home": (SecurityLooks.Home.HAND * 2 + 1) * 2,
		"carry": SecurityLooks.Carry.SHOULDER,
		"carry_from": SecurityLooks.Carry.SHOULDER,
		"from": Transform3D(),
	}
	var flags := {
		"in_stall": false,
		"hand_carry": false,
		"from_floor": true,
		"to_floor": false,
		"hand": 1,
		"clear": CarryOnProps.TRANSFER_CLEAR_M,
		"yaw": 0.0,
	}
	var start := Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(0.2, 0.0, 0.55))
	var upright_inner := 0.0
	var worn := 0
	var upright_joint := Vector3(0.206, 1.644, -0.06)
	for joint: Vector3 in [upright_joint, Vector3(0.0896, 1.5005, -0.107)]:
		# The stoop drew the leaning joint in from where it stood upright.
		var shift := joint - upright_joint
		var hung := CarryWorn.shoulder(joint, Vector3.ZERO, 0.0, 1, 1.0, base, shift)
		var want: Transform3D = hung[0]
		var length: float = hung[1]
		# Strap_Top as CarryOnProps._set_reach moves it.
		var bar := top_base + Vector3(0.0, 0.0, length - CarryOnProps.REACH_BUILT_M)
		var body := {
			"hand": 1,
			"grips": [Vector3(-0.25, 0.8, 0.05), Vector3(0.25, 0.8, 0.05)],
			"shoulders_y": [joint.y, joint.y],
			"bar_z": 0.0,
			"scale": 1.0,
			"strap_top": bar,
		}
		var gaps := []
		for step in 101:
			var k := step / 100.0
			var plan := CarryLead.plan(bag, k, start, want, Transform3D(), flags, body)
			if plan["holder"] >= 0:
				continue
			var xf: Transform3D = plan["xf"]
			if xf.is_equal_approx(start):
				continue
			assert_bool(xf.is_equal_approx(want)).is_true()
			var gap := maxf(0.0, (xf * bar).distance_to(joint) - 0.2)
			gaps.append(snappedf(gap, 0.001))
			assert_float(gap).is_equal(0.0)
			worn += 1
		var inner := (want * Vector3(0.0, 0.0, box.position.z)).x
		if joint.x > 0.2:
			upright_inner = inner
		print(
			(
				"joint %s: bar %s, worn gaps %s, inner bottom at %.3f"
				% [joint, want * bar, gaps, inner]
			)
		)
		assert_float(inner).is_greater_equal(upright_inner - 0.0001)
	assert_int(worn).is_greater(20)
