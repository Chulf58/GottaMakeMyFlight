class_name TestVf1CarryPoseRegressions
extends GdUnitTestSuite
## Regression coverage for the 8 VF1 carry-on pose, animation, doorway, and
## carry_backpack strap fixes (board 7bf98329, findings ddb2e346/991f2fe0).

const TOL := 0.002

var _male: Node3D
var _female: Node3D


func before() -> void:
	_male = PassengerLooks.SCENES[0].instantiate() as Node3D
	_female = PassengerLooks.SCENES[PassengerLooks.PER_VARIANT].instantiate() as Node3D
	for node: Node3D in [_male, _female]:
		add_child(node)
		node.position = Vector3.ZERO
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null
	for node: Node3D in [_male, _female]:
		if node != null and is_instance_valid(node):
			node.free()
	_male = null
	_female = null


func _body_skeleton(body: Node3D, clip: String) -> Array:
	var skel := body.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	for child in skel.get_children():
		if child is CarryStoop or child is CarryArm:
			skel.remove_child(child)
			child.free()
	var player := body.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.play(clip)
	player.seek(0.0, true)
	return [skel, player]


## 1. CarryStoop.turn(): deep floor lateral targets pitch forward within
## MAX_SIDE_DEGREES instead of rolling 45+ deg sideways, counter-rotate Neck,
## relax inactive arms downward, and preserve shallow tray cross-body reach.
func test_carry_stoop_pitches_forward_with_neck_counter_and_free_arm_hang() -> void:
	var pivot := Vector3(0.0, 1.0, 0.0)
	var deep_side := CarryStoop.turn(pivot, Vector3(0.45, 0.25, 0.05), 0.7)
	var side_roll_y := absf(deep_side.y.x)
	var forward_pitch_y := absf(deep_side.y.z)
	assert_float(forward_pitch_y).is_greater(side_roll_y)
	assert_float(atan2(side_roll_y, forward_pitch_y)).is_less_equal(
		deg_to_rad(CarryStoop.MAX_SIDE_DEGREES) + 0.001
	)
	# Waist/tray cross-body targets remain free to lean sideways toward the tray.
	var tray_side := CarryStoop.turn(pivot, Vector3(0.55, 0.85, 0.15), 0.4)
	assert_float(absf(tray_side.y.x)).is_greater(absf(tray_side.y.z))
	# With CarryStoop before CarryArm: Neck counter-rotates and free arm hangs.
	var pair := _body_skeleton(_male, "idle")
	var skel := pair[0] as Skeleton3D
	var stoop := CarryStoop.new()
	var free_arm := CarryArm.new()
	free_arm.side = 1
	free_arm.active = false
	free_arm.holds = false
	skel.add_child(stoop)
	skel.add_child(free_arm)
	stoop.targets = [Vector3(0.45, 0.1, 0.2)]
	stoop.sides = [0]
	stoop.weights = [1.0]
	var arm_l := skel.find_bone("Arm.L")
	var neck := skel.find_bone("Neck")
	var spine := skel.find_bone("Spine_01")
	var snap := {}
	var cb := func() -> void:
		snap["spine"] = skel.get_bone_global_pose(spine)
		snap["neck"] = skel.get_bone_global_pose(neck)
		snap["arm_l"] = skel.get_bone_global_pose(arm_l)
	skel.skeleton_updated.connect(cb)
	await get_tree().process_frame
	await get_tree().process_frame
	skel.skeleton_updated.disconnect(cb)
	var neck_pose: Transform3D = snap["neck"]
	var spine_pose: Transform3D = snap["spine"]
	var upper_arm := (snap["arm_l"] as Transform3D).basis.y.normalized()
	assert_float(stoop.bent).is_greater(0.3)
	assert_float(neck_pose.basis.y.dot(Vector3.UP)).is_greater(spine_pose.basis.y.dot(Vector3.UP))
	assert_float(upper_arm.y).is_less(-0.7)
	skel.remove_child(stoop)
	skel.remove_child(free_arm)
	stoop.free()
	free_arm.free()


## 2. CarryHand.swap_transform() + CarryLead.hand_pull_path():
## swap_transform() keeps stall-safe SWAP_OUT_M beside toilet stalls, widens to
## OPEN_SWAP_OUT_M in open space away from trailing calves, and CarryLead.hand_pull_path()
## flares bottom wheels outward away from the receiving calf.
func test_hand_pull_swap_flares_wheels_outward_and_security_narrow_stays_apart() -> void:
	assert_float(CarryHand.SWAP_OUT_M).is_less_equal(0.10)
	var scale := 1.0
	var roller := InteriorKit.instantiate(SecurityLooks.KIND_PIECES[SecurityLooks.Kind.ROLLER])
	add_child(roller)
	var props := CarryOnProps.new()
	add_child(props)
	_male.set_meta(&"body", 0)
	_body_skeleton(_male, "idle")

	# Near a toilet stall: swap stays stall-partition safe (0.0 m overlap with stall partitions).
	var stall_grid := BuildGrid.new()
	ToiletTestLayout.build(stall_grid)
	var stall_world := PassengerTestWorld.make(stall_grid, FlightSim.schedule_starts(0))
	stall_world.sim.toilets.refresh()
	props.sim = stall_world.sim
	var stall := stall_world.sim.toilets.layout.stalls[0]
	var out_dir := SecurityLooks.world_dir(stall["front"])
	var across := out_dir.cross(Vector3.UP)
	_male.global_position = (
		stall_grid.cell_to_world(stall["approach"]) + out_dir * 0.35 + across * 0.15
	)
	_male.rotation.y = atan2(across.x, across.z)
	var stall_held := {
		"scale": scale,
		"hands": [0],
		"security": false,
		"in_stall": false,
		"stall": stall,
		"bags":
		[{"node": roller, "kind": SecurityLooks.Kind.ROLLER, "carry": SecurityLooks.Carry.PULL}],
	}
	var grip_s := props.grip_of(_male, 0)
	var hung_s := CarryHand.hung_axle(props, stall_held["bags"][0], grip_s, scale)
	var trail_s := _male.global_position - Basis(Vector3.UP, _male.rotation.y).z * 0.95
	trail_s.y = hung_s.y
	stall_held["bags"][0]["axle_now"] = trail_s
	var stall_res := CarryHand.swap_transform(props, stall_held, _male, 0, 0.5)
	var stall_box := PullSide._box(stall_res[0], CarryOnProps.bag_box(SecurityLooks.Kind.ROLLER))
	for piece: Array in PullSide.pieces_near(stall_grid, _male.global_position):
		assert_float(PullSide._overlap(stall_box, piece)).is_equal(0.0)

	# In open terminal space: swap_transform() swings wide past trailing calves.
	var open_grid := BuildGrid.new()
	var open_edits: Array[BuildEdit] = []
	for x in range(4, 10):
		for y in range(4, 10):
			open_edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	for res in open_grid.apply_batch(open_edits):
		assert_bool(res.ok).is_true()
	var open_world := PassengerTestWorld.make(open_grid, FlightSim.schedule_starts(0))
	props.sim = open_world.sim
	_male.global_position = open_grid.cell_to_world(Vector2i(7, 7))
	_male.rotation.y = 0.0
	var grip_o := props.grip_of(_male, 0)
	var hung_o := CarryHand.hung_axle(props, stall_held["bags"][0], grip_o, scale)
	var trailing_o := _male.global_position + Vector3(-0.30, 0.03, -0.95)
	var open_held := {
		"scale": scale,
		"hands": [0],
		"security": false,
		"in_stall": false,
		"stall": {},
		"bags":
		[
			{
				"node": roller,
				"kind": SecurityLooks.Kind.ROLLER,
				"carry": SecurityLooks.Carry.PULL,
				"axle_now": trailing_o,
			}
		],
	}
	var open_res := CarryHand.swap_transform(props, open_held, _male, 0, 0.5)
	var open_axle := (open_res[0] as Transform3D) * CarryOnProps.ROLLER_AXLE
	var base_mid := hung_o.lerp(trailing_o, 0.5)
	assert_float(absf(open_axle.x - base_mid.x)).is_greater_equal(0.20)
	_male.global_position = Vector3.ZERO
	props.sim = null
	open_world.free_all()
	stall_world.free_all()
	props.free()
	roller.free()
	_male.remove_meta(&"carry_rig")

	var frame := Transform3D.IDENTITY
	var bar_to := CarryLead.anchor(SecurityLooks.Kind.ROLLER, CarryOnProps.REACH_BUILT_M)
	var bar_from := CarryOnProps.ROLLER_HANDLE
	var start := CarryHand.carried(
		Vector3(-0.29, 1.02, 0.0), frame.origin, 0.0, scale, SecurityLooks.Kind.ROLLER
	)
	var want := RollerPull.pulled(Vector3(0.28, 0.94, 0.0), Vector3(0.30, 0.03, -1.0), scale)
	var swung := CarryLead.hand_pull_path(
		start, start, want, frame, 0.75, bar_from, bar_to, bar_to, 1.58, 0
	)
	var axle := swung * CarryOnProps.ROLLER_AXLE
	# Receiving left hip is +X; outward flare keeps trailing axle cleanly outside calf.
	assert_float(axle.x).is_greater(0.25)
	var start_l := CarryHand.carried(
		Vector3(0.29, 1.02, 0.0), frame.origin, 0.0, scale, SecurityLooks.Kind.ROLLER
	)
	var want_r := RollerPull.pulled(Vector3(-0.28, 0.94, 0.0), Vector3(-0.30, 0.03, -1.0), scale)
	var swung_r := CarryLead.hand_pull_path(
		start_l, start_l, want_r, frame, 0.75, bar_from, bar_to, bar_to, 1.58, 1
	)
	assert_float((swung_r * CarryOnProps.ROLLER_AXLE).x).is_less(-0.25)


## 3. CarryArm._grip_fingers(): holding a handle curls fingers/thumb at rest
## and still curls child fingertips/thumb at full IK reach without shifting grip_of().
func test_carry_arm_grip_curl_closes_digits_without_shifting_reach_grip() -> void:
	for body: Node3D in [_male, _female]:
		var pair := _body_skeleton(body, "walk")
		var skel := pair[0] as Skeleton3D
		var grip_at := BoneAttachment3D.new()
		grip_at.bone_name = CarryOnProps.GRIP_BONES[0]
		skel.add_child(grip_at)
		var arm := CarryArm.new()
		arm.side = 0
		arm.holds = true
		arm.grip_curl = 1.0
		arm.active = true
		skel.add_child(arm)
		var tip := skel.find_bone("Fingertips.R")
		var fingers := skel.find_bone("Fingers.R")
		var rest_tip := skel.get_bone_rest(tip).basis.get_rotation_quaternion()
		var open_fingers := skel.get_bone_rest(fingers).basis.get_rotation_quaternion()
		var grip_snap := {}
		var gcb := func() -> void:
			grip_snap["tip"] = skel.get_bone_pose_rotation(tip)
			grip_snap["fingers"] = skel.get_bone_pose_rotation(fingers)
		skel.skeleton_updated.connect(gcb)
		arm.reach_weight = 0.0
		await get_tree().process_frame
		await get_tree().process_frame
		var tip_q: Quaternion = grip_snap["tip"]
		var fingers_q: Quaternion = grip_snap["fingers"]
		var tip_ang := tip_q.angle_to(rest_tip)
		var fingers_ang := fingers_q.angle_to(open_fingers)
		assert_float(tip_ang).is_greater(0.4)
		assert_float(fingers_ang).is_greater(0.4)
		# At full IK reach, child fingertips stay curled while Fingers aligns for grip_of().
		arm.reach_weight = 1.0
		arm.reach_target = skel.global_transform * Vector3(-0.22, 1.05, 0.25)
		await get_tree().process_frame
		await get_tree().process_frame
		skel.skeleton_updated.disconnect(gcb)
		var reach_tip_q: Quaternion = grip_snap.get("tip", skel.get_bone_pose_rotation(tip))
		assert_float(reach_tip_q.angle_to(rest_tip)).is_greater(0.4)
		var grip_world := grip_at.global_transform * (Vector3.UP * CarryOnProps.GRIP_ALONG_M)
		assert_float(grip_world.distance_to(arm.reach_target)).is_less(0.025)
		skel.remove_child(arm)
		skel.remove_child(grip_at)
		arm.free()
		grip_at.free()


## 4. CarryArm._reach_wrist(): loop_grip target behind torso keeps wrist outside
## Spine_03 and keeps elbow below shoulder instead of twisting backward over shoulder.
func test_loop_wrist_behind_shoulder_stays_outside_spine_with_downward_elbow() -> void:
	for body: Node3D in [_male, _female]:
		var pair := _body_skeleton(body, "idle")
		var skel := pair[0] as Skeleton3D
		var arm := CarryArm.new()
		arm.side = 1
		arm.holds = true
		arm.loop_grip = true
		arm.loop_roll = 1.0
		arm.reach_weight = 1.0
		arm.active = true
		arm.reach_target = skel.global_transform * Vector3(0.0, 1.45, -0.25)
		skel.add_child(arm)
		await get_tree().process_frame
		await get_tree().process_frame
		var shoulder := skel.get_bone_global_pose(skel.find_bone("Arm.L")).origin
		var elbow := skel.get_bone_global_pose(skel.find_bone("Forearm.L")).origin
		var wrist := skel.get_bone_global_pose(skel.find_bone("Hand.L")).origin
		var scale_x := skel.global_transform.basis.get_scale().x
		assert_float(wrist.x).is_greater_equal(absf(shoulder.x) - 0.001)
		assert_float(wrist.z).is_greater_equal(shoulder.z - 0.055 / scale_x)
		assert_float(elbow.y).is_less(shoulder.y + 0.02 / scale_x)
		skel.remove_child(arm)
		arm.free()


## 5. Step-off walk heading convergence, RollerPark.ROLL_RODS, and PullSide.desks_near():
## walking off a cafe chair turns off the table heading smoothly while RollerPark uses
## ROLL_RODS >= 0.60 and desks_near isolates GateDesks.DESK from cafe counters.
func test_step_off_turns_onto_walk_and_desks_near_isolates_gate_desks() -> void:
	assert_float(RollerPark.ROLL_RODS).is_greater_equal(0.60)
	var desk_grid := BuildGrid.new()
	var floor_edits: Array[BuildEdit] = []
	for x in range(10, 15):
		for y in range(10, 15):
			floor_edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	floor_edits.append(
		BuildEdit.place_object(GateDesks.DESK, Vector2i(11, 11), BuildGrid.Side.NORTH)
	)
	for res in desk_grid.apply_batch(floor_edits):
		assert_bool(res.ok).override_failure_message(res.reason_text()).is_true()
	(
		assert_int(PullSide.desks_near(desk_grid, desk_grid.cell_to_world(Vector2i(11, 11))).size())
		. is_greater(0)
	)

	var grid := BuildGrid.new()
	var layout := CafeTestLayout.build(grid)
	var ctr_cell: Vector2i = grid.get_object(layout["air_counter"])["anchor"]
	assert_int(PullSide.desks_near(grid, grid.cell_to_world(ctr_cell)).size()).is_equal(0)

	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	var views := PassengerTestWorld.views()
	views.clock = world.clock
	views.sim = world.sim
	add_child(views)
	var p := world.passenger(world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.carry_on = 1
	while SecurityLooks.bag_kind(p, 0) != SecurityLooks.Kind.ROLLER:
		p.carry_on = 0
		p.hunger = 0
		p.cafe_cooldown = 1000000
		p = world.passenger(world.sim.spawn_now(PassengerTestWorld.FLIGHT))
		p.carry_on = 1
	p.hunger = 0
	p.cafe_cooldown = 1000000
	while p.stage != Passenger.Stage.TO_GATE and world.clock.tick < 3000:
		world.step()
	assert_bool(world.sim.cafes.try_visit(p)).is_true()
	while p.stage != Passenger.Stage.CAFE_STANDING_UP and world.clock.tick < 3000:
		world.step()
	var props := views.carry_on_props()
	var roller_aabb := CarryOnProps.bag_box(SecurityLooks.Kind.ROLLER)
	var furniture := PullSide.piece_boxes(grid, layout["air_counter"])
	furniture.append_array(PullSide.piece_boxes(grid, layout["land_counter"]))
	var air_table_boxes := PullSide.piece_boxes(grid, layout["air_table"])
	var hip_heights: Array[float] = []
	var walk_hips: Array[float] = []
	var walked := 0
	var max_settled_deg := 0.0
	var last_diff := INF
	var worst_counter_overlap := 0.0
	var worst_cleared_table_overlap := 0.0
	for i in 260:
		world.clock.advance(SimClock.STEP / 3.0)
		await get_tree().process_frame
		await get_tree().create_timer(0.0, true, false, true).timeout
		var body := views.node_for(p.id)
		var skel := body.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var hip_y := (
			(skel.global_transform * skel.get_bone_global_pose(skel.find_bone("Hips"))).origin.y
		)
		var bags: Array = props.props_of(p.id).get("bags", [])
		if p.stage == Passenger.Stage.CAFE_STANDING_UP and not bags.is_empty():
			var bag := bags[0] as Node3D
			var bar_y := bag.global_transform.origin.y
			if bar_y > 0.20:
				hip_heights.append(hip_y)
		if p.stage != Passenger.Stage.TO_GATE:
			continue
		var step := views.tick_position(p.id, true) - views.tick_position(p.id, false)
		step.y = 0.0
		if step.length() > 0.02:
			walk_hips.append(hip_y)
			var walk_yaw := atan2(step.x, step.z)
			var diff_deg := rad_to_deg(absf(angle_difference(body.rotation.y, walk_yaw)))
			last_diff = diff_deg
			walked += 1
			if walked >= 24:
				max_settled_deg = maxf(max_settled_deg, diff_deg)
			if not bags.is_empty():
				var r_box := PullSide._box((bags[0] as Node3D).global_transform, roller_aabb)
				for box: Array in furniture:
					worst_counter_overlap = maxf(
						worst_counter_overlap, PullSide._overlap(r_box, box)
					)
				if walked >= 15:
					for box: Array in air_table_boxes:
						worst_cleared_table_overlap = maxf(
							worst_cleared_table_overlap, PullSide._overlap(r_box, box)
						)
			if walked >= 36:
				break
	assert_int(walked).is_greater(24)
	assert_float(last_diff).is_less(12.0)
	assert_float(max_settled_deg).is_less(15.0)
	assert_bool(hip_heights.is_empty()).is_false()
	assert_bool(walk_hips.is_empty()).is_false()
	var walk_hip_base := walk_hips[walk_hips.size() - 1]
	assert_float(hip_heights[hip_heights.size() - 1] / walk_hip_base).is_greater_equal(0.92)
	assert_float(worst_counter_overlap).is_equal(0.0)
	assert_float(worst_cleared_table_overlap).is_equal(0.0)
	views.free()
	world.free_all()


## 6. PullSide doorway tuck: holds hand while tucked_now, tucks stationary in door,
## and keeps pulled roller box + telescopic rods clear of doorway jambs across traversal.
func test_pull_side_holds_hand_while_tucked_and_tucks_stationary_in_door() -> void:
	var grid := BuildGrid.new()
	var edits: Array[BuildEdit] = []
	for x in range(9, 12):
		for y in range(9, 12):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	edits.append(BuildEdit.place_wall(Vector2i(9, 10), BuildGrid.Side.NORTH))
	edits.append(BuildEdit.place_wall(Vector2i(11, 10), BuildGrid.Side.NORTH))
	edits.append(
		BuildEdit.place_wall(Vector2i(10, 10), BuildGrid.Side.NORTH, BuildGrid.WallKind.DOOR)
	)
	for res in grid.apply_batch(edits):
		assert_bool(res.ok).override_failure_message(res.reason_text()).is_true()
	var frame := Transform3D(Basis(), grid.cell_to_world(Vector2i(10, 10)))
	var hand_r := (SecurityLooks.Home.HAND * 2 + 0) * 2
	var bag := {"was": hand_r, "place": hand_r, "tuck_on": false}
	assert_int(PullSide.pick(bag, grid, frame, [], 0.0, 1, 100.0)).is_equal(1)
	RollerPull.tuck(bag, true, 90.0)
	assert_int(PullSide.pick(bag, grid, frame, [], 0.0, 1, 100.0)).is_equal(0)
	var static_bag := {}
	PullSide.tuck(static_bag, grid, frame, [], 0.0, 1, 100.0)
	assert_bool(static_bag.get("tuck_on", false)).is_true()

	# Traversal across doorway plane: tucked roller & telescopic rods clear both jambs.
	var door_mid := BuildView.wall_transform(grid, Vector2i(10, 10), BuildGrid.Side.NORTH).origin
	var jambs := PullSide.walls_near(grid, door_mid)
	var roller_aabb := CarryOnProps.bag_box(SecurityLooks.Kind.ROLLER)
	var hand_l := (SecurityLooks.Home.HAND * 2 + 1) * 2
	var trav_bag := {"was": hand_l, "place": hand_l}
	var sim_t := 0.0
	var steps := 0
	for z_off: float in [1.2, 1.0, 0.8, 0.6, 0.4, 0.2, 0.0, -0.2, -0.4, -0.6, -0.8, -1.0]:
		var walk_frame := Transform3D(Basis(Vector3.UP, PI), door_mid + Vector3(0.0, 0.0, z_off))
		var ahead := [
			door_mid + Vector3(0.0, 0.0, z_off - 0.6), door_mid + Vector3(0.0, 0.0, z_off - 1.2)
		]
		var hand := PullSide.pick(trav_bag, grid, walk_frame, ahead, 0.2, 1, sim_t)
		PullSide.tuck(trav_bag, grid, walk_frame, ahead, 0.2, hand, sim_t)
		var tuck_w := RollerPull.tuck_weight(trav_bag, sim_t + 6.0)
		var settled := RollerPull.settle(
			Vector3((1.0 if hand == 1 else -1.0) * 0.30, 0.03, -1.0), hand, tuck_w, 0.0
		)
		var grip := walk_frame * Vector3((1.0 if hand == 1 else -1.0) * 0.24, 0.90, 0.02)
		var axle := walk_frame * settled
		var bag_xf := RollerPull.pulled(grip, axle, 1.0)
		var bag_box := PullSide._box(bag_xf, roller_aabb)
		for wall: Array in jambs:
			assert_float(PullSide._overlap(bag_box, wall)).is_equal(0.0)
		for rx: float in [-0.06, 0.06]:
			var rod_a := bag_xf * Vector3(rx, 0.03, CarryOnProps.ROLLER_AXLE.z)
			var rod_b := grip + bag_xf.basis.x.normalized() * rx
			for s in 5:
				var pt := rod_a.lerp(rod_b, float(s) / 4.0)
				var seg_box := [
					pt, [Vector3.RIGHT, Vector3.UP, Vector3.BACK], Vector3(0.01, 0.01, 0.01)
				]
				for wall: Array in jambs:
					assert_float(PullSide._overlap(seg_box, wall)).is_equal(0.0)
		sim_t += 2.0
		steps += 1
	assert_int(steps).is_equal(12)

	# Discriminating control: untucked pull across doorway plane hits jamb.
	var untucked_hits := 0
	for z_off: float in [0.2, 0.0, -0.2, -0.4, -0.6, -0.8, -1.0]:
		var untucked_frame := Transform3D(
			Basis(Vector3.UP, PI), door_mid + Vector3(0.0, 0.0, z_off)
		)
		var untucked_grip := untucked_frame * Vector3(0.24, 0.90, 0.02)
		var untucked_axle := untucked_frame * Vector3(0.30, 0.03, -0.95)
		var untucked_box := PullSide._box(
			RollerPull.pulled(untucked_grip, untucked_axle, 1.0), roller_aabb
		)
		for wall: Array in jambs:
			if PullSide._overlap(untucked_box, wall) > 0.0:
				untucked_hits += 1
	assert_int(untucked_hits).is_greater(0)


## 7. CarryArmPose: Arm.FREE beside a front-carried hard case relaxes downward instead
## of holding a horizontal zombie pose, while Arm.FREE with beside == 0 stays raised.
func test_free_arm_beside_front_case_relaxes_down_without_zombie_reach() -> void:
	var pair := _body_skeleton(_male, "idle")
	var skel := pair[0] as Skeleton3D
	var arm_r := CarryArm.new()
	var arm_l := CarryArm.new()
	arm_r.side = 0
	arm_l.side = 1
	skel.add_child(arm_r)
	skel.add_child(arm_l)
	var rig := {"arms": [arm_r, arm_l]}
	_male.set_meta(&"carry_rig", rig)
	var props := CarryOnProps.new()
	var case_held := {
		"bags": [{"kind": SecurityLooks.Kind.CASE, "carry": SecurityLooks.Carry.HAND}],
		"homes": [SecurityLooks.Home.HAND],
		"hands": [0],
		"weight": 1.0,
		"tuck_weight": 0.0,
		"tuck": false,
		"reach_on": [false, false],
		"outs": [12.0, 12.0],
	}
	CarryArmPose.pose_arms(props, case_held, _male, 100.0)
	assert_float(arm_l.front_upper_degrees).is_less(0.0)
	assert_float(arm_l.front_up_degrees).is_less_equal(-45.0)
	var booth_tuck_held := {
		"bags":
		[{"kind": SecurityLooks.Kind.ROLLER, "carry": SecurityLooks.Carry.HAND, "by_bar": true}],
		"homes": [SecurityLooks.Home.HAND],
		"hands": [1],
		"weight": 0.0,
		"tuck_weight": 1.0,
		"tuck": true,
		"reach_on": [false, false],
		"outs": [12.0, 12.0],
	}
	CarryArmPose.pose_arms(props, booth_tuck_held, _male, 100.0)
	assert_float(arm_r.front_up_degrees).is_equal(-10.0)
	props.free()
	_male.remove_meta(&"carry_rig")
	skel.remove_child(arm_r)
	skel.remove_child(arm_l)
	arm_r.free()
	arm_l.free()


## 8. carry_backpack.glb: retains original foot/torso clearance AABB while
## containing multi-surface contoured shoulder strap geometry along the flanks.
func test_carry_backpack_glb_has_straps_within_clearance_bounds() -> void:
	var pack := InteriorKit.instantiate("carry_backpack")
	add_child(pack)
	var mesh := pack.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var box := mesh.mesh.get_aabb()
	assert_vector(box.position).is_equal_approx(Vector3(-0.124, 0.0, -0.210), Vector3.ONE * TOL)
	assert_vector(box.end).is_equal_approx(Vector3(0.124, 0.177, 0.235), Vector3.ONE * TOL)
	var flank_strap_verts := 0
	var arrays := mesh.mesh.surface_get_arrays(0)
	var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	for v: Vector3 in verts:
		if absf(v.x) >= 0.088 and v.y <= 0.05 and v.z >= 0.0:
			flank_strap_verts += 1
	assert_int(verts.size()).is_greater(500)
	assert_int(flank_strap_verts).is_greater(40)
	pack.free()
