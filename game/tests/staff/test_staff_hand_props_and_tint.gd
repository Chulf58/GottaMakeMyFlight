class_name TestStaffHandPropsAndTint
extends GdUnitTestSuite
## Regression tests for runtime SHOP burgundy uniform cloth tinting,
## BoneAttachment3D hand props on Hand.R / Hand.L, multi-variant bone delta
## differences across roles, pool reuse cleanup, and snap/load reset (6d949060).

var _views: StaffCharacters
var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _views != null:
		_views.free()
		_views = null
	if _world != null:
		_world.free_all()
		_world = null


func _skeleton_tick(node: Node3D, skeleton: Skeleton3D) -> void:
	var player := node.get_node("AnimationPlayer") as AnimationPlayer
	if player.current_animation != "idle":
		player.play("idle")
		player.seek(0.0, true)
	player.speed_scale = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	await skeleton.skeleton_updated


func _snapshot_bones(sk: Skeleton3D, bones: Array[String]) -> Dictionary:
	var out := {}
	for b in bones:
		out[b] = sk.get_bone_global_pose(sk.find_bone(b)).basis.get_rotation_quaternion()
	return out


func _max_bone_diff(a: Dictionary, b: Dictionary) -> float:
	var worst := 0.0
	for k in a:
		worst = maxf(worst, (a[k] as Quaternion).angle_to(b[k]))
	return worst


func test_shop_uniform_tint_differs_from_checkin_gate_and_ramp_with_burgundy_cloth() -> void:
	var chars := auto_free(StaffCharacters.new()) as StaffCharacters
	add_child(chars)
	var ci := chars._take(StaffMember.Role.CHECKIN)
	var shop := chars._take(StaffMember.Role.SHOP)
	var shop_two := chars._take(StaffMember.Role.SHOP)
	var gate := chars._take(StaffMember.Role.GATE)
	var ramp := chars._take(StaffMember.Role.RAMP)

	var ci_mesh := PassengerLooks.body_mesh(ci).mesh
	var shop_mi := PassengerLooks.body_mesh(shop)
	var shop_two_mi := PassengerLooks.body_mesh(shop_two)
	var shop_mesh := shop_mi.mesh
	var gate_mesh := PassengerLooks.body_mesh(gate).mesh
	var ramp_mesh := PassengerLooks.body_mesh(ramp).mesh

	assert_object(shop_mesh).is_not_same(ci_mesh)
	assert_object(shop_mesh).is_not_same(gate_mesh)
	assert_object(shop_mesh).is_not_same(ramp_mesh)
	assert_int(shop_mesh.get_surface_count()).is_equal(2)

	var shop_mat := shop_mi.get_active_material(1) as ShaderMaterial
	var shop_two_mat := shop_two_mi.get_active_material(1) as ShaderMaterial
	var gate_mat := gate_mesh.surface_get_material(1) as ShaderMaterial
	var ramp_mat := ramp_mesh.surface_get_material(1) as ShaderMaterial
	assert_object(shop_mat).is_not_null()
	assert_object(shop_mat).is_same(shop_two_mat)
	assert_object(shop_mat).is_not_same(gate_mat)
	assert_object(shop_mat).is_not_same(ramp_mat)

	var img := (shop_mat.get_shader_parameter("albedo_texture") as Texture2D).get_image()
	var burgundy_pixels := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var c := img.get_pixel(x, y)
			if c.s > 0.45 and c.v >= 0.30 and (c.h >= 0.90 or c.h <= 0.02):
				burgundy_pixels += 1
	print("SHOP uniform burgundy cloth samples: %d" % burgundy_pixels)
	assert_int(burgundy_pixels).is_greater(20)

	# Mutating SHOP's cached cloth material leaves GATE, RAMP, and tcp_atlas_toon.tres untouched.
	var source_mat := load("res://assets/materials/tcp_atlas_toon.tres") as ShaderMaterial
	shop_mat.set_shader_parameter("albedo_tint", Color(0.1, 0.9, 0.2, 1.0))
	assert_bool(gate_mat.get_shader_parameter("albedo_tint") == Color.WHITE).is_true()
	assert_bool(ramp_mat.get_shader_parameter("albedo_tint") == Color.WHITE).is_true()
	assert_bool(source_mat.get_shader_parameter("albedo_tint") == Color.WHITE).is_true()
	assert_object(source_mat.get_shader_parameter("albedo_texture")).is_not_same(
		shop_mat.get_shader_parameter("albedo_texture")
	)
	shop_mat.set_shader_parameter("albedo_tint", Color.WHITE)


func test_hand_props_attach_to_hand_bones_exclusively_and_hide_on_walk_tuck_and_pool() -> void:
	var chars := auto_free(StaffCharacters.new()) as StaffCharacters
	add_child(chars)
	var officer := chars._take(StaffMember.Role.SECURITY)
	var agent := chars._take(StaffMember.Role.CHECKIN)
	var shop := chars._take(StaffMember.Role.SHOP)

	# 1. Security scan -> Wand on Hand.R, visible and exclusive.
	(
		StaffStationPose
		. pose(
			officer,
			StaffStationPose.Mode.SECURITY_SCAN,
			1.0,
			20.0,
			Vector2.ZERO,
			1,
			StaffStationPose.SubMode.SEC_ALARM,
		)
	)
	(
		StaffHandProps
		. update(
			officer,
			StaffStationPose.Mode.SECURITY_SCAN,
			StaffStationPose.SubMode.SEC_ALARM,
			1.0,
			20.0,
			1,
			false,
			false,
		)
	)
	var sk_o := officer.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	await _skeleton_tick(officer, sk_o)
	assert_int(StaffHandProps.active_prop(officer)).is_equal(StaffHandProps.PropKind.WAND)
	var wand := StaffHandProps.prop_node(officer, StaffHandProps.PropKind.WAND)
	assert_bool(wand.visible).is_true()
	assert_str((wand.get_parent() as BoneAttachment3D).bone_name).is_equal("Hand.R")
	var hand_r := sk_o.get_bone_global_pose(sk_o.find_bone("Hand.R"))
	var hand_world := sk_o.global_transform * hand_r.origin
	assert_float(wand.global_position.distance_to(hand_world)).is_less(0.25)

	# Walking hides Wand immediately.
	(
		StaffHandProps
		. update(
			officer,
			StaffStationPose.Mode.SECURITY_SCAN,
			StaffStationPose.SubMode.SEC_ALARM,
			1.0,
			20.0,
			1,
			true,
			false,
		)
	)
	assert_int(StaffHandProps.active_prop(officer)).is_equal(StaffHandProps.PropKind.NONE)
	assert_bool(wand.visible).is_false()

	# Re-show when stationary, then verify arch tuck (tucked == true) hides Wand immediately.
	(
		StaffHandProps
		. update(
			officer,
			StaffStationPose.Mode.SECURITY_SCAN,
			StaffStationPose.SubMode.SEC_ALARM,
			1.0,
			20.0,
			1,
			false,
			false,
		)
	)
	assert_int(StaffHandProps.active_prop(officer)).is_equal(StaffHandProps.PropKind.WAND)
	assert_bool(wand.visible).is_true()
	(
		StaffHandProps
		. update(
			officer,
			StaffStationPose.Mode.SECURITY_SCAN,
			StaffStationPose.SubMode.SEC_ALARM,
			1.0,
			20.0,
			1,
			false,
			true,
		)
	)
	assert_int(StaffHandProps.active_prop(officer)).is_equal(StaffHandProps.PropKind.NONE)
	assert_bool(wand.visible).is_false()

	# 2. Gate -> BoardingPass on Hand.R.
	StaffStationPose.pose(agent, StaffStationPose.Mode.GATE, 1.0, 20.0, Vector2.ZERO, 2)
	StaffHandProps.update(
		agent, StaffStationPose.Mode.GATE, StaffStationPose.SubMode.NONE, 1.0, 20.0, 2, false, false
	)
	assert_int(StaffHandProps.active_prop(agent)).is_equal(StaffHandProps.PropKind.BOARDING_PASS)
	var pass_node := StaffHandProps.prop_node(agent, StaffHandProps.PropKind.BOARDING_PASS)
	assert_str((pass_node.get_parent() as BoneAttachment3D).bone_name).is_equal("Hand.R")

	# 3. Info Desk -> Clipboard on Hand.L; Cafe -> CoffeeCup on Hand.R.
	(
		StaffHandProps
		. update(
			shop,
			StaffStationPose.Mode.SHOP,
			StaffStationPose.SubMode.SHOP_INFO_DESK,
			1.0,
			20.0,
			1,
			false,
			false,
		)
	)
	assert_int(StaffHandProps.active_prop(shop)).is_equal(StaffHandProps.PropKind.CLIPBOARD)
	var clipboard := StaffHandProps.prop_node(shop, StaffHandProps.PropKind.CLIPBOARD)
	assert_str((clipboard.get_parent() as BoneAttachment3D).bone_name).is_equal("Hand.L")

	var pour_t := 20.0
	for step in 6:
		var cand := float(step) * StaffStationPose.SHOP_CYCLE_SEC * float(SimClock.TICK_RATE) + 20.0
		if StaffStationPose.cafe_cup_active(cand, 1):
			pour_t = cand
			break
	(
		StaffHandProps
		. update(
			shop,
			StaffStationPose.Mode.SHOP,
			StaffStationPose.SubMode.SHOP_CAFE,
			1.0,
			pour_t,
			1,
			false,
			false,
		)
	)
	assert_int(StaffHandProps.active_prop(shop)).is_equal(StaffHandProps.PropKind.COFFEE_CUP)
	assert_bool(clipboard.visible).is_false()
	var cup := StaffHandProps.prop_node(shop, StaffHandProps.PropKind.COFFEE_CUP)
	assert_str((cup.get_parent() as BoneAttachment3D).bone_name).is_equal("Hand.R")

	# Pool _release() hides props and _take() reuses the pooled node cleanly hidden.
	chars._nodes[101] = shop
	chars._prev[101] = Vector3.ZERO
	chars._cur[101] = Vector3.ZERO
	chars._release(101)
	assert_object(chars.node_for(101)).is_null()
	assert_bool(shop.visible).is_false()
	assert_int(StaffHandProps.active_prop(shop)).is_equal(StaffHandProps.PropKind.NONE)
	assert_bool(cup.visible).is_false()

	var reused := chars._take(StaffMember.Role.SHOP)
	assert_object(reused).is_same(shop)
	assert_bool(reused.visible).is_true()
	assert_int(StaffHandProps.active_prop(reused)).is_equal(StaffHandProps.PropKind.NONE)
	assert_bool(cup.visible).is_false()

	# Freeing a prop-owning character cleans up BoneAttachment3D and props with zero orphans.
	var att_r := wand.get_parent()
	assert_bool(is_instance_valid(att_r)).is_true()
	officer.queue_free()
	await get_tree().process_frame
	assert_bool(is_instance_valid(officer)).is_false()
	assert_bool(is_instance_valid(att_r)).is_false()
	assert_bool(is_instance_valid(wand)).is_false()


func test_hand_prop_waits_for_crossfade_blend_in() -> void:
	var clock := auto_free(SimClock.new()) as SimClock
	clock.paused = true
	clock.tick = 250
	var chars := auto_free(StaffCharacters.new()) as StaffCharacters
	chars.clock = clock
	add_child(chars)
	var agent := chars._take(StaffMember.Role.GATE)
	chars._nodes[102] = agent
	chars._prev[102] = Vector3.ZERO
	chars._cur[102] = Vector3.ZERO
	var rec := {}
	StaffStationPose.update(
		rec, StaffStationPose.Mode.NONE, Vector2.ZERO, 100.0, StaffStationPose.SubMode.NONE, true, 1
	)
	(
		StaffStationPose
		. update(
			rec,
			StaffStationPose.Mode.NONE,
			Vector2.ZERO,
			220.0,
			StaffStationPose.SubMode.NONE,
			true,
			1,
		)
	)
	(
		StaffStationPose
		. update(
			rec,
			StaffStationPose.Mode.GATE,
			Vector2.ZERO,
			250.0,
			StaffStationPose.SubMode.NONE,
			false,
			1,
		)
	)
	chars._poses[102] = rec
	chars.draw()
	assert_int(chars.hand_prop_of(102)).is_equal(StaffHandProps.PropKind.NONE)
	clock.tick = 250 + int(StaffStationPose.TRANSITION_TICKS)
	chars.draw()
	assert_int(chars.hand_prop_of(102)).is_equal(StaffHandProps.PropKind.BOARDING_PASS)


func test_multi_variant_cycles_produce_distinct_skeleton_poses_per_role() -> void:
	var chars := auto_free(StaffCharacters.new()) as StaffCharacters
	add_child(chars)
	var agent := chars._take(StaffMember.Role.CHECKIN)
	var sk := agent.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var bones: Array[String] = ["Head", "Arm.R", "Forearm.R", "Arm.L", "Forearm.L"]

	# Check-in variants 0, 1, 2 at mid-cycle (phase ~ 0.65) produce pairwise distinct bone poses.
	var snaps := []
	for target_v in 3:
		var sample_t := 0.0
		for step in 24:
			var cand := (
				float(step) * StaffStationPose.CHECKIN_CYCLE_SEC * float(SimClock.TICK_RATE) + 52.0
			)
			if StaffStationPose.checkin_variant(cand, 1) == target_v:
				sample_t = cand
				break
		StaffStationPose.pose(agent, StaffStationPose.Mode.CHECKIN, 1.0, sample_t, Vector2.ZERO, 1)
		await _skeleton_tick(agent, sk)
		snaps.append(_snapshot_bones(sk, bones))
	assert_float(_max_bone_diff(snaps[0], snaps[1])).is_greater(0.15)
	assert_float(_max_bone_diff(snaps[1], snaps[2])).is_greater(0.15)
	assert_float(_max_bone_diff(snaps[0], snaps[2])).is_greater(0.15)

	# Idle fidget variants 0..3 produce distinct bone poses at active beat (u = 0.30).
	var by_variant := {}
	for sid in range(1, 5):
		var stagger := float(posmod(sid * 47, 100))
		var elapsed := (
			float(StaffStationPose.IDLE_SETTLE_TICKS + StaffStationPose.FIDGET_PERIOD_TICKS)
			- stagger
			+ 24.0
		)
		var v := StaffStationPose.idle_fidget_variant(sid, elapsed)
		(
			StaffStationPose
			. pose(
				agent,
				StaffStationPose.Mode.IDLE_FIDGET,
				1.0,
				elapsed,
				Vector2.ZERO,
				sid,
				StaffStationPose.SubMode.NONE,
				0.0,
			)
		)
		await _skeleton_tick(agent, sk)
		by_variant[v] = _snapshot_bones(sk, ["Head", "Spine_01", "Arm.L", "Forearm.L"])
	assert_int(by_variant.size()).is_equal(4)
	for i in 4:
		for j in range(i + 1, 4):
			assert_float(_max_bone_diff(by_variant[i], by_variant[j])).is_greater(0.15)


func test_hand_props_and_poses_reset_on_snap_load_backward_in_time() -> void:
	var gate_world := GateWalkWorld.make(self, true)
	_world = gate_world.world
	_world.flights._flights = _world.flights._flights.filter(
		func(f: Dictionary) -> bool: return String(f.get("id", "")) == GateWalkWorld.FLIGHT
	)
	StaffTestKit.staff_all(_world.staff, [StaffMember.Role.GATE])
	var gate_sid := _world.staff.staff_at(gate_world.desk)
	_views = StaffCharacters.new()
	_views.clock = _world.clock
	_views.staff = _world.staff
	_views.flights = _world.flights
	add_child(_views)
	_views.sync(true)
	_views.draw()

	var pid := gate_world.send()
	assert_bool(gate_world.run_until_stage(pid, Passenger.Stage.SEATED, 2000)).is_true()
	_world.run_to(GateWalkWorld.BOARDING - 1)
	var saved_clock: Variant = JSON.parse_string(JSON.stringify(_world.clock.to_snapshot()))
	var saved_flights: Variant = JSON.parse_string(JSON.stringify(_world.flights.to_snapshot()))
	var saved_staff: Variant = JSON.parse_string(JSON.stringify(_world.staff.to_snapshot()))
	var saved_pax: Variant = JSON.parse_string(JSON.stringify(_world.sim.to_snapshot()))

	# Advance into boarding when passenger approaches gate -> GATE pose + BOARDING_PASS prop visible.
	_world.run_to(GateWalkWorld.BOARDING)
	for _i in 120:
		_world.step()
		_views.draw()
		if (
			_views.station_pose_mode(gate_sid) == StaffStationPose.Mode.GATE
			and _views.station_pose_weight(gate_sid) >= 0.99
		):
			break
	assert_int(_views.station_pose_mode(gate_sid)).is_equal(StaffStationPose.Mode.GATE)
	assert_int(_views.hand_prop_of(gate_sid)).is_equal(StaffHandProps.PropKind.BOARDING_PASS)

	# Load backward snapshot + snap sync -> prop hidden and pose reset immediately (6d949060).
	assert_bool(_world.clock.from_snapshot(saved_clock)).is_true()
	assert_bool(_world.flights.from_snapshot(saved_flights)).is_true()
	assert_bool(_world.staff.from_snapshot(saved_staff)).is_true()
	assert_bool(_world.sim.from_snapshot(saved_pax)).is_true()
	_views.sync(true)
	_views.draw()
	assert_int(_views.station_pose_mode(gate_sid)).is_equal(StaffStationPose.Mode.NONE)
	assert_float(_views.station_pose_weight(gate_sid)).is_equal(0.0)
	assert_float(_views.idle_fidget_weight(gate_sid)).is_equal(0.0)
	assert_int(_views.hand_prop_of(gate_sid)).is_equal(StaffHandProps.PropKind.NONE)


func test_cleaner_patrol_and_walk_to_mess_carry_broom_upright_without_arm_swing() -> void:
	var chars := auto_free(StaffCharacters.new()) as StaffCharacters
	add_child(chars)
	var cleaner := chars._take(StaffMember.Role.CLEANER)
	var sk := cleaner.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var player := cleaner.get_node("AnimationPlayer") as AnimationPlayer
	player.play("walk")
	player.speed_scale = 0.0

	# Without broom carry, walk clip swings Arm.R strongly across phases.
	var swing_samples := []
	for phase in [0.1, 0.45]:
		player.seek(phase, true)
		await get_tree().process_frame
		await sk.skeleton_updated
		swing_samples.append(_snapshot_bones(sk, ["Arm.R", "Forearm.R"]))
	assert_float(_max_bone_diff(swing_samples[0], swing_samples[1])).is_greater(0.25)

	# Patrol carry activates BroomCarryArm and keeps Arm.R/Forearm.R steady across walk stride.
	(
		StaffHandProps
		. update(
			cleaner,
			StaffStationPose.Mode.NONE,
			StaffStationPose.SubMode.NONE,
			0.0,
			10.0,
			1,
			true,
			false,
			StaffMember.Role.CLEANER,
			false,
			false,
			true,
		)
	)
	assert_int(StaffHandProps.active_prop(cleaner)).is_equal(StaffHandProps.PropKind.BROOM)
	var broom := StaffHandProps.prop_node(cleaner, StaffHandProps.PropKind.BROOM)
	(
		assert_bool(broom.rotation_degrees.is_equal_approx(StaffHandProps.BROOM_CARRY_ROT_DEG))
		. is_true()
	)
	var carry_arm := StaffHandProps.broom_carry_arm_of(cleaner)
	assert_object(carry_arm).is_not_null()
	assert_bool(carry_arm.active).is_true()

	var carry_samples := []
	var hand_samples := []
	for phase in [0.1, 0.45]:
		player.seek(phase, true)
		await get_tree().process_frame
		await sk.skeleton_updated
		carry_samples.append(_snapshot_bones(sk, ["Arm.R", "Forearm.R"]))
		hand_samples.append(_snapshot_bones(sk, ["Hand.R"]))
	assert_float(_max_bone_diff(carry_samples[0], carry_samples[1])).is_less(
		_max_bone_diff(swing_samples[0], swing_samples[1]) * 0.65
	)
	assert_float(_max_bone_diff(hand_samples[0], hand_samples[1])).is_less(0.10)

	# Broom sits upright and clears floor (y >= 0.05 m) in carry pose.
	var min_y := INF
	for mi: MeshInstance3D in broom.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh != null:
			for v in mi.mesh.get_faces():
				min_y = minf(min_y, (mi.global_transform * v).y)
	assert_float(min_y).is_greater(0.05)

	# Cleaning ON_DUTY disables BroomCarryArm and restores sweep broom angle.
	(
		StaffHandProps
		. update(
			cleaner,
			StaffStationPose.Mode.NONE,
			StaffStationPose.SubMode.NONE,
			0.0,
			10.0,
			1,
			false,
			false,
			StaffMember.Role.CLEANER,
			false,
			true,
			false,
		)
	)
	assert_bool(carry_arm.active).is_false()
	(
		assert_bool(broom.rotation_degrees.is_equal_approx(StaffHandProps.BROOM_SWEEP_ROT_DEG))
		. is_true()
	)

	# Arch tuck and hide_all disable BroomCarryArm and hide BROOM.
	(
		StaffHandProps
		. update(
			cleaner,
			StaffStationPose.Mode.NONE,
			StaffStationPose.SubMode.NONE,
			0.0,
			10.0,
			1,
			true,
			true,
			StaffMember.Role.CLEANER,
			false,
			false,
			true,
		)
	)
	assert_int(StaffHandProps.active_prop(cleaner)).is_equal(StaffHandProps.PropKind.NONE)
	assert_bool(carry_arm.active).is_false()

	# Integration: StaffCharacters shows BROOM + carry arm while patrolling or walking to mess.
	var world := MessTestKit.open_world(7)
	_world = world
	var cid := world.staff.hire(StaffMember.Role.CLEANER)
	assert_int(cid).is_greater(0)
	_views = StaffCharacters.new()
	_views.clock = world.clock
	_views.staff = world.staff
	add_child(_views)
	var m := world.staff.get_member(cid)
	var door := world.sim.layout.door_cell(world.grid, world.sim.layout.entrances[0])
	var way: Array[Vector2i] = []
	for y in world.grid.size.y:
		for x in world.grid.size.x:
			var cand := Vector2i(x, y)
			if (
				world.grid.is_indoor(cand)
				and world.grid.is_walkable(cand)
				and cand.distance_to(door) >= 3.0
			):
				var p := StaffPosts.path_in(world.staff, m, cand)
				if p.size() >= 3:
					way = p
					break
		if not way.is_empty():
			break
	assert_int(way.size()).is_greater_equal(3)
	var dest: Vector2i = way[way.size() - 1]
	world.sim.messes.add(MessSim.Kind.LITTER, dest)
	world.staff._take_job(m, world.sim.messes.mess_ids()[0], false, way)
	_views.sync(true)
	_views.draw()
	assert_int(_views.hand_prop_of(cid)).is_equal(StaffHandProps.PropKind.BROOM)
	var cnode := _views.node_for(cid)
	assert_bool(StaffHandProps.broom_carry_arm_of(cnode).active).is_true()
	StaffHandProps.hide_all(cnode)
	assert_int(_views.hand_prop_of(cid)).is_equal(StaffHandProps.PropKind.NONE)
	assert_bool(StaffHandProps.broom_carry_arm_of(cnode).active).is_false()
