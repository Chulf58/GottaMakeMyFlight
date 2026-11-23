class_name TestStaffLifeOverhaul
extends GdUnitTestSuite
## Regression tests for user ruling 073e599b (staff life overhaul):
## - Full-body Hips/Quad/Shin/Clavicle/Spine engagement across all poses
## - Continuous ambient head-tracking, shorter settle (24 ticks), role micro-idles
## - Empty-air Gate & Shop trigger fixes
## - Cleaner broom/rag & Ramp dual glowing marshalling wands in StaffHandProps
## - Idle Cleaner corridor/bin patrol with instant mess preemption & save determinism
## - Visible airside staging for idle Role.RAMP agents

const SITE := preload("res://build/terminal_site.tres")

var _world: PassengerTestWorld
var _views: StaffCharacters
var _gate_world: GateWalkWorld
var _dispatch: RampDispatch
var _finances: Finances
var _rating: AirportRating


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _views != null:
		_views.free()
		_views = null
	if _gate_world != null:
		_gate_world.world.free_all()
		_gate_world = null
	if _world != null:
		_world.free_all()
		_world = null
	_dispatch = null
	_finances = null
	_rating = null


func _skeleton_of(node: Node3D) -> Skeleton3D:
	return node.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D


func _skeleton_tick(node: Node3D, skeleton: Skeleton3D) -> void:
	var player := node.get_node("AnimationPlayer") as AnimationPlayer
	if player.current_animation != "idle":
		player.play("idle")
		player.seek(0.0, true)
	player.speed_scale = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	await skeleton.skeleton_updated


func test_full_body_hips_legs_clavicle_and_spine_engage_across_modes() -> void:
	var chars := auto_free(StaffCharacters.new()) as StaffCharacters
	add_child(chars)
	var agent := chars._take(StaffMember.Role.CHECKIN)
	var sk := _skeleton_of(agent)
	var full_bones: Array[String] = [
		"Hips",
		"Quad.L",
		"Quad.R",
		"Shin.L",
		"Shin.R",
		"Clavicle.L",
		"Clavicle.R",
		"Spine_01",
		"Spine_02",
		"Spine_03",
	]

	var mod := StaffStationPose._of(agent)
	mod.active = false
	await _skeleton_tick(agent, sk)
	var rest := {}
	for b in full_bones:
		rest[b] = sk.get_bone_global_pose(sk.find_bone(b))

	var modes := [
		[StaffStationPose.Mode.CHECKIN, StaffStationPose.SubMode.NONE],
		[StaffStationPose.Mode.SECURITY_SCAN, StaffStationPose.SubMode.SEC_CLEAN],
		[StaffStationPose.Mode.SECURITY_REPACK, StaffStationPose.SubMode.NONE],
		[StaffStationPose.Mode.SHOP, StaffStationPose.SubMode.SHOP_CAFE],
		[StaffStationPose.Mode.GATE, StaffStationPose.SubMode.NONE],
		[StaffStationPose.Mode.RAMP_MARSHAL, StaffStationPose.SubMode.NONE],
		[StaffStationPose.Mode.IDLE_FIDGET, StaffStationPose.SubMode.NONE],
	]
	for entry: Array in modes:
		var m_mode: StaffStationPose.Mode = entry[0]
		var m_sub: StaffStationPose.SubMode = entry[1]
		var tick := 60.0
		var idle_since := 0.0
		if m_mode == StaffStationPose.Mode.IDLE_FIDGET:
			tick = float(StaffStationPose.IDLE_SETTLE_TICKS + 12)
		(
			StaffStationPose
			. pose(
				agent,
				m_mode,
				1.0,
				tick,
				Vector2.ZERO,
				1,
				m_sub,
				idle_since,
				StaffStationPose.Mode.NONE,
				StaffStationPose.SubMode.NONE,
				0.0,
				StaffMember.Role.SHOP,
			)
		)
		await _skeleton_tick(agent, sk)
		var hips_now := sk.get_bone_global_pose(sk.find_bone("Hips"))
		var hips_rest := rest["Hips"] as Transform3D
		var hips_angle := hips_rest.basis.get_rotation_quaternion().angle_to(
			hips_now.basis.get_rotation_quaternion()
		)
		var hips_shift := hips_rest.origin.distance_to(hips_now.origin)
		assert_float(hips_angle + hips_shift).is_greater(0.005)
		for b in ["Quad.L", "Shin.L", "Clavicle.L", "Spine_01", "Spine_02", "Spine_03"]:
			var q_now := sk.get_bone_global_pose(sk.find_bone(b)).basis.get_rotation_quaternion()
			var q_rest := (rest[b] as Transform3D).basis.get_rotation_quaternion()
			(
				assert_float(q_rest.angle_to(q_now))
				. override_failure_message("mode %s bone %s unchanged" % [m_mode, b])
				. is_greater(0.005)
			)


func test_ambient_head_tracking_brisk_settle_and_role_micro_idles() -> void:
	assert_int(StaffStationPose.IDLE_SETTLE_TICKS).is_less_equal(30)
	var duty_cycle := (
		float(StaffStationPose.FIDGET_ACTIVE_TICKS) / float(StaffStationPose.FIDGET_PERIOD_TICKS)
	)
	assert_float(duty_cycle).is_greater_equal(0.65)

	# Continuous ambient head-tracking during Mode.NONE toward a passing passenger.
	var grid := BuildGrid.new()
	CafeTestLayout.build(grid, false, &"cafe", true)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(3000, 6000), 11)
	_world.auto_staff = false
	StaffTestKit.staff_all(_world.staff)
	_views = StaffCharacters.new()
	_views.clock = _world.clock
	_views.staff = _world.staff
	_views.flights = _world.flights
	add_child(_views)

	var desk: int = _world.sim.layout.desks[0]
	var ci_id := _world.staff.staff_at(desk)
	var ci_node := _views.node_for(ci_id)
	if ci_node == null:
		_views.sync(true)
		_views.draw()
		ci_node = _views.node_for(ci_id)

	# Spawn a moving passenger just in front of the check-in agent.
	var pid := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var pax := _world.passenger(pid)
	ToiletTestLayout.calm(pax)
	var front_cell := _world.grid.interaction_cell(desk)
	var path: Array[Vector2i] = []
	for delta in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
		var cand := _world.grid.find_path(front_cell, front_cell + delta)
		if cand.size() >= 2:
			path = cand
			break
	assert_int(path.size()).is_greater_equal(2)
	pax.at = path[0]
	pax.set_path(path)
	pax.stage = Passenger.Stage.TO_CHECKIN
	_views.sync(true)
	_views.draw()
	assert_int(_views.station_pose_mode(ci_id)).is_equal(StaffStationPose.Mode.NONE)
	var mod := ci_node.get_meta(&"station_pose") as StaffStationPose
	assert_bool(mod.active).is_true()
	assert_float(absf(mod.look_yaw_deg) + absf(mod.look_pitch_deg)).is_greater(1.0)

	# Distinct SHOP vs CHECKIN micro-idle variant 3 poses.
	var chars := auto_free(StaffCharacters.new()) as StaffCharacters
	add_child(chars)
	var shop_body := chars._take(StaffMember.Role.SHOP)
	var sk := _skeleton_of(shop_body)
	var stagger := float(posmod(1 * 47, 100))
	var v3_tick := 0.0
	for s in range(1, 20):
		var cand := (
			float(StaffStationPose.IDLE_SETTLE_TICKS + s * StaffStationPose.FIDGET_PERIOD_TICKS)
			- stagger
			+ float(StaffStationPose.FIDGET_ACTIVE_TICKS) * 0.5
		)
		if StaffStationPose.idle_fidget_variant(1, cand) == 3:
			v3_tick = cand
			break
	assert_float(v3_tick).is_greater(0.0)
	(
		StaffStationPose
		. pose(
			shop_body,
			StaffStationPose.Mode.IDLE_FIDGET,
			1.0,
			v3_tick,
			Vector2.ZERO,
			1,
			StaffStationPose.SubMode.NONE,
			0.0,
			StaffStationPose.Mode.NONE,
			StaffStationPose.SubMode.NONE,
			0.0,
			StaffMember.Role.SHOP,
		)
	)
	await _skeleton_tick(shop_body, sk)
	var pose_bones: Array[String] = ["Arm.L", "Forearm.L", "Arm.R", "Forearm.R"]
	var shop_pose := {}
	for b in pose_bones:
		shop_pose[b] = sk.get_bone_global_pose(sk.find_bone(b)).basis.get_rotation_quaternion()
	(
		StaffStationPose
		. pose(
			shop_body,
			StaffStationPose.Mode.IDLE_FIDGET,
			1.0,
			v3_tick,
			Vector2.ZERO,
			1,
			StaffStationPose.SubMode.NONE,
			0.0,
			StaffStationPose.Mode.NONE,
			StaffStationPose.SubMode.NONE,
			0.0,
			StaffMember.Role.CHECKIN,
		)
	)
	await _skeleton_tick(shop_body, sk)
	var max_diff := 0.0
	for b in pose_bones:
		var q_ci := sk.get_bone_global_pose(sk.find_bone(b)).basis.get_rotation_quaternion()
		max_diff = maxf(max_diff, (shop_pose[b] as Quaternion).angle_to(q_ci))
	assert_float(max_diff).is_greater(0.2)


func test_gate_and_shop_do_not_trigger_into_empty_air() -> void:
	# 1. GATE during BOARDING with 0 approaching passengers stays Mode.NONE.
	_gate_world = GateWalkWorld.make(self, true)
	_world = _gate_world.world
	_world.flights._flights = _world.flights._flights.filter(
		func(f: Dictionary) -> bool: return String(f.get("id", "")) == GateWalkWorld.FLIGHT
	)
	StaffTestKit.staff_all(_world.staff, [StaffMember.Role.GATE])
	var gate_sid := _world.staff.staff_at(_gate_world.desk)
	_views = StaffCharacters.new()
	_views.clock = _world.clock
	_views.staff = _world.staff
	_views.flights = _world.flights
	add_child(_views)
	_world.run_to(GateWalkWorld.BOARDING + 20)
	_views.sync(true)
	_views.draw()
	assert_int(_views.station_pose_mode(gate_sid)).is_equal(StaffStationPose.Mode.NONE)
	assert_int(_views.hand_prop_of(gate_sid)).is_equal(StaffHandProps.PropKind.NONE)
	_views.free()
	_views = null
	_gate_world.world.free_all()
	_gate_world = null
	_world = null

	# 2. SHOP browser 12 m away from counter does not trigger Mode.SHOP coffee pour / ring-up.
	var grid := BuildGrid.new()
	var shop_ids := ShopTestLayout.build(grid, ["air"])
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(3000, 6000), 25)
	_world.auto_staff = false
	var counter: int = shop_ids["air_counter"]
	var server_id := StaffTestKit.seat_server(_world.staff, counter)
	var server := _world.staff.get_member(server_id)
	var staff_pos := _world.staff.world_position(server)
	var far_browser := staff_pos + Vector3(12.0, StaffStationPose.PASSENGER_EYE_M, 0.0)
	var ctx := {
		"checkin": {},
		"info": {},
		"shop_rooms": {ShopCounters.room_of(grid, counter): [far_browser]},
		"gate_pax": {},
		"ambient_pax": [],
	}
	var eval := StaffStationPose.evaluate(server, _world.staff, staff_pos, ctx)
	assert_int(eval[0]).is_equal(StaffStationPose.Mode.NONE)


func test_cleaner_broom_rag_and_ramp_dual_wands_in_hand_props() -> void:
	var chars := auto_free(StaffCharacters.new()) as StaffCharacters
	add_child(chars)
	var cleaner := chars._take(StaffMember.Role.CLEANER)
	var ramp := chars._take(StaffMember.Role.RAMP)

	# Cleaner working a mess -> BROOM; patrolling -> BROOM; emptying bin -> RAG; tucked -> NONE.
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
	assert_int(StaffHandProps.active_prop(cleaner)).is_equal(StaffHandProps.PropKind.BROOM)
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
			true,
			true,
			false,
		)
	)
	assert_int(StaffHandProps.active_prop(cleaner)).is_equal(StaffHandProps.PropKind.RAG)
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

	# Ramp dual glowing marshalling wands in BOTH Hand.R and Hand.L for RAMP_MARSHAL & RAMP_GUIDE.
	(
		StaffHandProps
		. update(
			ramp,
			StaffStationPose.Mode.RAMP_MARSHAL,
			StaffStationPose.SubMode.NONE,
			1.0,
			10.0,
			1,
			false,
			false,
			StaffMember.Role.RAMP,
		)
	)
	assert_int(StaffHandProps.active_prop(ramp)).is_equal(StaffHandProps.PropKind.MARSHAL_WANDS)
	var wands := StaffHandProps.prop_nodes(ramp, StaffHandProps.PropKind.MARSHAL_WANDS)
	assert_int(wands.size()).is_equal(2)
	var bones := []
	for w_node in wands:
		assert_bool(w_node.visible).is_true()
		bones.append((w_node.get_parent() as BoneAttachment3D).bone_name)
	assert_array(bones).contains(["Hand.R", "Hand.L"])

	(
		StaffHandProps
		. update(
			ramp,
			StaffStationPose.Mode.RAMP_PUSHBACK,
			StaffStationPose.SubMode.RAMP_GUIDE,
			1.0,
			10.0,
			1,
			true,
			false,
			StaffMember.Role.RAMP,
		)
	)
	assert_int(StaffHandProps.active_prop(ramp)).is_equal(StaffHandProps.PropKind.MARSHAL_WANDS)
	(
		StaffHandProps
		. update(
			ramp,
			StaffStationPose.Mode.RAMP_PUSHBACK,
			StaffStationPose.SubMode.RAMP_HOOKUP,
			1.0,
			10.0,
			1,
			false,
			false,
			StaffMember.Role.RAMP,
		)
	)
	assert_int(StaffHandProps.active_prop(ramp)).is_equal(StaffHandProps.PropKind.NONE)
	StaffHandProps.hide_all(ramp)
	for w_node in wands:
		assert_bool(w_node.visible).is_false()


func test_idle_cleaner_patrols_preempts_on_mess_and_replays_after_load() -> void:
	_world = MessTestKit.open_world(7)
	PassengerTestWorld.place(_world.grid, MessSim.BIN_ID, Vector2i(25, 3), 0)
	_world.step()
	var m := CleanerTestKit.cleaner_at(_world, Vector2i(15, 10))
	m.patrol_wait = 5

	var started_patrol := false
	for _i in 20:
		_world.step()
		if m.state == StaffMember.State.IDLE and m.is_moving():
			started_patrol = true
			break
	assert_bool(started_patrol).is_true()
	assert_int(m.job).is_equal(0)

	# Save mid-patrol and load into a control world -> plays identically tick-for-tick.
	var saved_staff := MessTestKit.through_json(_world.staff.to_snapshot())
	var saved_messes := MessTestKit.through_json(_world.sim.messes.to_snapshot())
	var clone := MessTestKit.open_world(7)
	PassengerTestWorld.place(clone.grid, MessSim.BIN_ID, Vector2i(25, 3), 0)
	clone.step()
	clone.run_to(_world.clock.tick)
	assert_bool(clone.sim.messes.from_snapshot(saved_messes)).is_true()
	assert_bool(clone.staff.from_snapshot(saved_staff)).is_true()
	assert_str(StaffTestKit.signature(clone.staff)).is_equal(StaffTestKit.signature(_world.staff))

	for _i in 15:
		_world.step()
		clone.step()
	assert_str(StaffTestKit.signature(clone.staff)).is_equal(StaffTestKit.signature(_world.staff))
	clone.free_all()

	# Save right after a post-step mess spawn preserves last_unclaimed_sig so
	# the loaded cleaner wakes up on the exact same tick without waiting for a beat.
	m.search_failed = true
	var post_mess := _world.sim.messes.add(MessSim.Kind.SPILL, Vector2i(18, 12))
	var pre_wake_staff := MessTestKit.through_json(_world.staff.to_snapshot())
	var pre_wake_messes := MessTestKit.through_json(_world.sim.messes.to_snapshot())
	assert_bool(pre_wake_staff.has("last_unclaimed_sig")).is_true()
	var wake_clone := MessTestKit.open_world(7)
	PassengerTestWorld.place(wake_clone.grid, MessSim.BIN_ID, Vector2i(25, 3), 0)
	wake_clone.step()
	wake_clone.run_to(_world.clock.tick)
	assert_bool(wake_clone.sim.messes.from_snapshot(pre_wake_messes)).is_true()
	assert_bool(wake_clone.staff.from_snapshot(pre_wake_staff)).is_true()
	_world.step()
	wake_clone.step()
	assert_int(m.job).is_equal(post_mess)
	assert_int(m.state).is_equal(StaffMember.State.TO_STATION)
	assert_int(int(_world.sim.messes.get_mess(post_mess)["claimed_by"])).is_equal(m.id)
	assert_str(StaffTestKit.signature(wake_clone.staff)).is_equal(
		StaffTestKit.signature(_world.staff)
	)
	wake_clone.free_all()


func test_idle_ramp_agents_stage_visibly_airside_with_distinct_slots() -> void:
	var grid := SiteGrid.new(SITE)
	StarterShell.place(grid, SITE.starter_offset)
	ReferenceTerminal.fill_interior(grid, SITE.starter_offset)
	var starts := FlightSim.schedule_starts(0)
	_world = PassengerTestWorld.make(grid, starts, 17)
	_world.sim.site = SITE
	_world.auto_staff = false
	_finances = auto_free(Finances.new()) as Finances
	_finances.clock = _world.clock
	_finances.start_new_game()
	_world.sim.wallet = _finances.wallet
	_rating = auto_free(AirportRating.new()) as AirportRating
	_rating.bind(_world.clock, _world.flights, _world.sim)
	_dispatch = auto_free(RampDispatch.new()) as RampDispatch
	_dispatch.bind(_world.clock, _world.staff, null, _world.flights, _finances, _rating)

	var r1 := _world.staff.hire(StaffMember.Role.RAMP)
	var r2 := _world.staff.hire(StaffMember.Role.RAMP)
	_views = StaffCharacters.new()
	_views.clock = _world.clock
	_views.staff = _world.staff
	_views.flights = _world.flights
	add_child(_views)
	_views.sync(true)
	_views.draw()

	var n1 := _views.node_for(r1)
	var n2 := _views.node_for(r2)
	assert_object(n1).is_not_null()
	assert_object(n2).is_not_null()
	assert_bool(n1.visible).is_true()
	assert_bool(n2.visible).is_true()
	assert_float(n1.position.distance_to(n2.position)).is_greater(1.0)
	assert_int(_views.hand_prop_of(r1)).is_equal(StaffHandProps.PropKind.NONE)

	# Dispatching r1 keeps idle r2 in its exact airside slot without shifting laterally.
	var r2_pos_before := n2.position
	_world.staff._set_ramp_job(_world.staff.get_member(r1), StaffMember.RampJob.MARSHAL, 0, "X1")
	_views.sync(false)
	_views.draw()
	assert_vector(_views.node_for(r2).position).is_equal(r2_pos_before)
	_world.staff._set_ramp_job(_world.staff.get_member(r1), StaffMember.RampJob.NONE)
	_views.sync(false)
	_views.draw()
	assert_vector(_views.node_for(r2).position).is_equal(r2_pos_before)

	# Idle Ramp Agents enter IDLE_FIDGET after settle window.
	var saw_fidget := false
	for _i in 150:
		_world.step()
		_views.draw()
		if _views.station_pose_mode(r1) == StaffStationPose.Mode.IDLE_FIDGET:
			saw_fidget = true
			break
	assert_bool(saw_fidget).is_true()
