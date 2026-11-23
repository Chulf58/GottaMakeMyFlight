class_name TestPassengerFidgetPose
extends GdUnitTestSuite
## Coverage for view-only PassengerFidgetPose (Package B Part 2/3):
## modifier stack ordering, sibling yielding, security alarm/liquids reactions,
## queue impatience/watch-check with carry-hand safety, seated variants,
## close-call boarding relief, and snap/clock-backwards load reset (6d949060).

var _worlds: Array = []
var _nodes: Array[Node] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	_cleanup()
	PassengerTestWorld.tracker = null


func after_test() -> void:
	_cleanup()


func _cleanup() -> void:
	for n in _nodes:
		if n != null and is_instance_valid(n):
			n.free()
	_nodes.clear()
	for w in _worlds:
		if w != null:
			w.free_all()
	_worlds.clear()


func _track_world(w: PassengerTestWorld) -> PassengerTestWorld:
	_worlds.append(w)
	return w


func _track_views(world: PassengerTestWorld) -> PassengerViews:
	var views := PassengerTestWorld.views()
	views.clock = world.clock
	views.sim = world.sim
	add_child(views)
	_nodes.append(views)
	return views


func _skeleton(node: Node3D) -> Skeleton3D:
	return node.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D


func _fidget_of(node: Node3D) -> PassengerFidgetPose:
	return (
		node.get_meta(&"fidget_pose") as PassengerFidgetPose
		if node.has_meta(&"fidget_pose")
		else null
	)


func _bone_quats(sk: Skeleton3D, names: Array[String]) -> Dictionary:
	var out := {}
	for bname in names:
		var idx := sk.find_bone(bname)
		out[bname] = sk.get_bone_global_pose(idx).basis.get_rotation_quaternion()
	return out


func _max_bone_delta(sk: Skeleton3D, before_q: Dictionary) -> float:
	var best := 0.0
	for bname: String in before_q:
		var idx := sk.find_bone(bname)
		var q := sk.get_bone_global_pose(idx).basis.get_rotation_quaternion()
		best = maxf(best, (before_q[bname] as Quaternion).angle_to(q))
	return best


func _sample_delta(
	views: PassengerViews,
	sk: Skeleton3D,
	mod: PassengerFidgetPose,
	names: Array[String],
	set_active := true,
) -> float:
	var was_proc := views.is_processing() if views != null else false
	if views != null:
		views.set_process(false)
	var prev := mod.active
	mod.active = false
	await get_tree().process_frame
	await sk.skeleton_updated
	var base := _bone_quats(sk, names)
	mod.active = set_active
	await get_tree().process_frame
	await sk.skeleton_updated
	var delta := _max_bone_delta(sk, base)
	mod.active = prev
	if views != null:
		views.set_process(was_proc)
	return delta


func test_modifier_stack_order_and_sibling_yielding() -> void:
	var body := PassengerLooks.SCENES[0].instantiate() as Node3D
	add_child(body)
	_nodes.append(body)
	var sk := _skeleton(body)
	var fade := ClipCrossfade.new()
	fade.name = "ClipCrossfade"
	sk.add_child(fade)
	sk.move_child(fade, 0)
	var stoop := CarryStoop.new()
	var arm0 := CarryArm.new()
	arm0.side = 0
	arm0.active = false
	var arm1 := CarryArm.new()
	arm1.side = 1
	arm1.active = false
	sk.add_child(stoop)
	sk.add_child(arm0)
	sk.add_child(arm1)

	PassengerFidgetPose.apply(body, PassengerFidgetPose.Mode.QUEUE, 1.0, 1.0, 0, 1, true, true)
	var mod := _fidget_of(body)
	assert_object(mod).is_not_null()
	assert_int(fade.get_index()).is_equal(0)
	assert_int(mod.get_index()).is_greater(fade.get_index())
	assert_int(mod.get_index()).is_less(stoop.get_index())
	assert_int(mod.get_index()).is_less(arm0.get_index())

	# Yielding when sibling modifiers (PodRecline, DiningPose, RepackPose, CarryStoop) are active.
	var player := body.get_node("AnimationPlayer") as AnimationPlayer
	player.play("idle")
	player.speed_scale = 0.0
	var bones: Array[String] = ["Spine_01", "Head", "Arm.L", "Arm.R"]

	var recline := PodRecline.new()
	recline.amount = 1.0
	sk.add_child(recline)
	sk.move_child(recline, 1)
	assert_float(await _sample_delta(null, sk, mod, bones)).is_less(0.001)
	sk.remove_child(recline)
	recline.free()

	var dining := DiningPose.new()
	dining.kind = DiningPose.Kind.TABLE
	dining.amount = 1.0
	sk.add_child(dining)
	sk.move_child(dining, 1)
	assert_float(await _sample_delta(null, sk, mod, bones)).is_less(0.001)
	sk.remove_child(dining)
	dining.free()

	var repack := RepackPose.new()
	repack.amount = 1.0
	sk.add_child(repack)
	sk.move_child(repack, 1)
	assert_float(await _sample_delta(null, sk, mod, bones)).is_less(0.001)
	sk.remove_child(repack)
	repack.free()

	stoop.targets = [Vector3(0.2, 0.1, 0.3)]
	stoop.sides = [0]
	stoop.weights = [1.0]
	assert_float(await _sample_delta(null, sk, mod, bones)).is_less(0.001)
	stoop.targets.clear()

	# Unblocked baseline applies pose cleanly.
	assert_float(await _sample_delta(null, sk, mod, bones)).is_greater(0.2)

	# Shower room yields completely in PassengerViews.
	var grid := BuildGrid.new()
	ActivityTestLayout.build(grid, &"shower")
	var world := _track_world(PassengerTestWorld.make(grid, FlightSim.schedule_starts(0)))
	world.auto_staff_roles = [StaffMember.Role.CHECKIN, StaffMember.Role.SECURITY]
	world.run_to(10)
	var views := _track_views(world)
	var p := ShopTestLayout.airside_guest(world, 80, ShopTestLayout.AIRSIDE_CELL)
	while p.stage != Passenger.Stage.SHOP_BROWSE and world.clock.tick < 2000:
		world.step()
		views.draw()
	while (
		ActivityPoses.kind(world.sim, p) == ActivityPoses.Kind.SHOWER
		and not ActivityPoses.washing(world.sim, p)
		and world.clock.tick < 2000
	):
		world.step()
		views.draw()
	assert_bool(ActivityPoses.washing(world.sim, p)).is_true()
	var smod := _fidget_of(views.node_for(p.id))
	if smod != null:
		assert_bool(smod.active).is_false()
		assert_float(smod.weight).is_equal(0.0)


func test_security_alarm_reaction_and_yield_to_repack_and_walk() -> void:
	var sec := SecurityTestWorld.make(false, 7)
	_worlds.append(sec.world)
	var views := _track_views(sec.world)
	var id := sec.send(0, false, true)
	var p := sec.world.passenger(id)

	while p.security_phase != SecurityRuntime.Phase.SCAN and sec.world.clock.tick < 1500:
		sec.world.step()
		views.draw()
	assert_int(p.security_phase).is_equal(SecurityRuntime.Phase.SCAN)
	assert_bool(p.is_moving()).is_true()
	var node := views.node_for(id)
	var mod := _fidget_of(node)
	if mod != null:
		assert_bool(mod.active).is_false()
		assert_float(mod.weight).is_equal(0.0)

	# Stationary SCAN alarm activates once the drawn body settles in the booth.
	while (
		p.security_phase == SecurityRuntime.Phase.SCAN
		and not views._fidgets.get(id, {}).has("react_since")
		and sec.world.clock.tick < 1500
	):
		sec.world.step()
		views.draw()
	assert_int(p.security_phase).is_equal(SecurityRuntime.Phase.SCAN)
	assert_bool(views._fidgets.get(id, {}).has("react_since")).is_true()
	for _i in 4:
		sec.world.step()
		views.draw()
	mod = _fidget_of(node)
	assert_object(mod).is_not_null()
	assert_bool(mod.active).is_true()
	assert_int(mod.mode).is_equal(PassengerFidgetPose.Mode.ALARM)
	assert_float(mod.weight).is_greater(0.5)

	# Walking transition yields immediately (both direct moving=true and exit walk in SCAN).
	var walk_rec: Dictionary = views._fidgets[id].duplicate(true)
	(
		PassengerFidgetPose
		. sync_passenger(
			sec.world.sim,
			views.carry_on_props(),
			node,
			p,
			walk_rec,
			float(sec.world.clock.tick),
			true,
			"walk",
			StageKinds.Pose.UPRIGHT,
			ActivityPoses.Kind.NONE,
			false,
			false,
			0.0,
			0.0,
			false,
		)
	)
	assert_bool(mod.active).is_false()
	assert_float(mod.weight).is_equal(0.0)

	while (
		p.security_phase == SecurityRuntime.Phase.SCAN
		and p.security_work > SecurityLooks.BASIC_EXIT_WALK_TICKS - 2
		and sec.world.clock.tick < 1500
	):
		sec.world.step()
		views.draw()
	assert_int(p.security_phase).is_equal(SecurityRuntime.Phase.SCAN)
	assert_bool(views._fidgets.get(id, {}).get("moving", false)).is_true()
	assert_bool(mod.active).is_false()
	assert_float(mod.weight).is_equal(0.0)

	while p.security_phase != SecurityRuntime.Phase.REPACK and sec.world.clock.tick < 1500:
		sec.world.step()
		views.draw()
	assert_int(p.security_phase).is_equal(SecurityRuntime.Phase.REPACK)

	# Early REPACK ticks (before RepackPose eases in): hands-up + step-back lean.
	for _i in 6:
		sec.world.step()
		views.draw()
	assert_bool(mod.active).is_true()
	assert_int(mod.mode).is_equal(PassengerFidgetPose.Mode.ALARM)
	assert_float(mod.weight).is_greater(0.5)
	assert_float(RepackPose.weight_for(p)).is_equal(0.0)

	var sk := _skeleton(node)
	var player := node.get_node("AnimationPlayer") as AnimationPlayer
	var prev_speed := player.speed_scale
	player.speed_scale = 0.0
	var arm_delta := await _sample_delta(views, sk, mod, ["Arm.L", "Arm.R"])
	var spine_delta := await _sample_delta(views, sk, mod, ["Spine_01", "Spine_02"])
	player.speed_scale = prev_speed
	assert_float(arm_delta).is_greater(0.8)
	assert_float(spine_delta).is_greater(0.05)

	# Mid-REPACK: PassengerFidgetPose yields cleanly to RepackPose.
	while p.security_work > 40 and sec.world.clock.tick < 1500:
		sec.world.step()
		views.draw()
	assert_float(RepackPose.weight_for(p)).is_equal(1.0)
	assert_bool(mod.active).is_false()
	assert_float(mod.weight).is_equal(0.0)

	# Post-REPACK walking exit to TO_GATE keeps PassengerFidgetPose yielded.
	while p.stage != Passenger.Stage.TO_GATE and sec.world.clock.tick < 1500:
		sec.world.step()
		views.draw()
	assert_int(p.stage).is_equal(Passenger.Stage.TO_GATE)
	assert_bool(p.is_moving()).is_true()
	assert_bool(mod.active).is_false()
	assert_float(mod.weight).is_equal(0.0)


func test_security_liquids_reaction_head_shake_and_shrug() -> void:
	var sec := SecurityTestWorld.make(true, 11)
	_worlds.append(sec.world)
	var views := _track_views(sec.world)
	var id := sec.send(1, true, false)
	var p := sec.world.passenger(id)

	while p.security_phase != SecurityRuntime.Phase.REPACK and sec.world.clock.tick < 1500:
		sec.world.step()
		views.draw()
	assert_int(p.security_phase).is_equal(SecurityRuntime.Phase.REPACK)

	# With 1 bag, wait past the 6-tick floor set-down into the pre-repack reaction window.
	for _i in 10:
		sec.world.step()
		views.draw()
	var node := views.node_for(id)
	var mod := _fidget_of(node)
	assert_object(mod).is_not_null()
	assert_bool(mod.active).is_true()
	assert_int(mod.mode).is_equal(PassengerFidgetPose.Mode.LIQUIDS)
	assert_float(mod.weight).is_greater(0.5)
	assert_float(RepackPose.weight_for(p)).is_equal(0.0)

	var sk := _skeleton(node)
	var player := node.get_node("AnimationPlayer") as AnimationPlayer
	var prev_speed := player.speed_scale
	player.speed_scale = 0.0
	var head_delta := await _sample_delta(views, sk, mod, ["Head", "Neck"])
	var arm_delta := await _sample_delta(views, sk, mod, ["Arm.L", "Arm.R"])
	player.speed_scale = prev_speed
	assert_float(head_delta).is_greater(0.1)
	assert_float(arm_delta).is_greater(0.25)

	# Alarm takes priority if both flags are set.
	var both_id := sec.send(1, true, true)
	var bp := sec.world.passenger(both_id)
	while bp.security_phase != SecurityRuntime.Phase.BODY_CHECK and sec.world.clock.tick < 3000:
		sec.world.step()
		views.draw()
	for _i in 6:
		sec.world.step()
		views.draw()
	var bmod := _fidget_of(views.node_for(both_id))
	assert_object(bmod).is_not_null()
	assert_int(bmod.mode).is_equal(PassengerFidgetPose.Mode.ALARM)


func test_queue_fidgets_settle_delay_variants_and_carry_hand_safety() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(10, 8))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 7), 3)
	PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(6, 2), 0)
	var world := _track_world(
		PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(20, 600))
	)
	var views := _track_views(world)

	# Two blockers hold the desk busy so subject stands still in CHECKIN_QUEUE past settle delay.
	for _k in 2:
		var blk := world.sim.spawn_now(PassengerTestWorld.FLIGHT)
		world.passenger(blk).carry_on = 0
		for _t in 12:
			world.step()
	var id := world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var p := world.passenger(id)
	p.carry_on = 1
	while SecurityLooks.bag_kind(p, 0) != SecurityLooks.Kind.CASE:
		p.stage = Passenger.Stage.MADE
		id = world.sim.spawn_now(PassengerTestWorld.FLIGHT)
		p = world.passenger(id)
		p.carry_on = 1

	while (
		not (p.stage == Passenger.Stage.CHECKIN_QUEUE and not p.is_moving())
		and world.clock.tick < 600
	):
		world.step()
		views.draw()
	assert_int(p.stage).is_equal(Passenger.Stage.CHECKIN_QUEUE)

	# Sim RNG state must never change during views.sync() / draw().
	var rng_view_before := world.clock.rng.state
	views.sync()
	views.draw()
	assert_int(world.clock.rng.state).is_equal(rng_view_before)

	# Before settle delay: no queue fidget yet.
	var node := views.node_for(id)
	var mod := _fidget_of(node)
	if mod != null:
		assert_float(mod.weight).is_equal(0.0)

	# Advance past settle + ease into active queue fidget; verify sim RNG untouched by views.
	for _i in int(PassengerFidgetPose.QUEUE_SETTLE_TICKS + PassengerFidgetPose.EASE_TICKS + 12):
		world.step()
		views.draw()
	assert_int(p.stage).is_equal(Passenger.Stage.CHECKIN_QUEUE)
	mod = _fidget_of(node)
	assert_object(mod).is_not_null()
	assert_bool(mod.active).is_true()
	assert_int(mod.mode).is_equal(PassengerFidgetPose.Mode.QUEUE)
	assert_float(mod.weight).is_greater(0.5)
	assert_bool(mod.free_right).is_false()
	assert_bool(mod.free_left).is_true()

	# Force sub_variant = 0 (watch-check on free left arm); right arm & bag stay locked.
	var sk := _skeleton(node)
	var player := node.get_node("AnimationPlayer") as AnimationPlayer
	var prev_speed := player.speed_scale
	player.speed_scale = 0.0
	var prev_sub := mod.sub_variant
	mod.sub_variant = 0
	var right_delta := await _sample_delta(views, sk, mod, ["Arm.R", "Forearm.R", "Hand.R"])
	var left_delta := await _sample_delta(views, sk, mod, ["Arm.L", "Forearm.L"])
	mod.sub_variant = prev_sub
	player.speed_scale = prev_speed
	assert_float(right_delta).is_less(0.0005)
	assert_float(left_delta).is_greater(0.3)

	var props := views.carry_on_props()
	assert_float(props.held_point(id, 0).distance_to(props.grip_of(node, 0))).is_less(0.002)

	# Verify deterministic coverage of all 3 queue variants across time buckets.
	var seen_subs := {}
	for b in 30:
		var s := PassengerFidgetPose._pick_sub(PassengerFidgetPose.Mode.QUEUE, p.id, b, true, true)
		seen_subs[s] = true
	assert_int(seen_subs.size()).is_equal(3)

	# Verify 2-bag passenger keeps BOTH carrying hands untouched even if sub 0 requested.
	p.carry_on = 2
	world.step()
	views.draw()
	assert_bool(mod.free_right).is_false()
	assert_bool(mod.free_left).is_false()
	player.speed_scale = 0.0
	mod.sub_variant = 0
	var both_delta := await _sample_delta(
		views, sk, mod, ["Arm.R", "Forearm.R", "Arm.L", "Forearm.L"]
	)
	player.speed_scale = prev_speed
	assert_float(both_delta).is_less(0.0005)


func test_seated_fidgets_gate_and_lounge_vs_cafe_pod_toilet() -> void:
	# 1. Lounge sofa (ActivityPoses.Kind.SEAT).
	var lgrid := BuildGrid.new()
	ActivityTestLayout.build(lgrid, &"lounge")
	var lworld := _track_world(PassengerTestWorld.make(lgrid, FlightSim.schedule_starts(0)))
	lworld.auto_staff_roles = [StaffMember.Role.CHECKIN, StaffMember.Role.SECURITY]
	lworld.run_to(10)
	var lviews := _track_views(lworld)
	var lp := ShopTestLayout.airside_guest(lworld, 80, ShopTestLayout.AIRSIDE_CELL)
	while (
		not (
			lp.stage == Passenger.Stage.SHOP_BROWSE
			and ActivityPoses.pose(lworld.sim, lp) == StageKinds.Pose.SEATED
		)
		and lworld.clock.tick < 2000
	):
		lworld.step()
		lviews.draw()
	assert_int(ActivityPoses.kind(lworld.sim, lp)).is_equal(ActivityPoses.Kind.SEAT)

	for _i in int(PassengerFidgetPose.SEATED_SETTLE_TICKS + PassengerFidgetPose.EASE_TICKS + 12):
		lworld.step()
		lviews.draw()
	var lnode := lviews.node_for(lp.id)
	var lmod := _fidget_of(lnode)
	assert_object(lmod).is_not_null()
	assert_bool(lmod.active).is_true()
	assert_int(lmod.mode).is_equal(PassengerFidgetPose.Mode.SEATED)
	assert_float(lmod.weight).is_greater(0.5)

	# Verify all 3 seated variants deform cleanly (phone glance, stretch, drowsy head-bob).
	var lsk := _skeleton(lnode)
	var lplayer := lnode.get_node("AnimationPlayer") as AnimationPlayer
	var prev_speed := lplayer.speed_scale
	lplayer.speed_scale = 0.0
	var orig_t := lmod.phase_t
	lmod.phase_t = 1.7
	lmod.sub_variant = 0
	var phone_delta := await _sample_delta(
		lviews, lsk, lmod, ["Arm.R", "Arm.L", "Forearm.R", "Forearm.L", "Head"]
	)
	assert_float(phone_delta).is_greater(0.25)
	lmod.sub_variant = 1
	assert_float(await _sample_delta(lviews, lsk, lmod, ["Spine_01", "Head", "Arm.L"])).is_greater(
		0.15
	)
	lmod.sub_variant = 2
	assert_float(await _sample_delta(lviews, lsk, lmod, ["Head", "Neck"])).is_greater(0.15)
	lmod.phase_t = orig_t
	lplayer.speed_scale = prev_speed

	# 2. Gate chair (Stage.SEATED) activates Mode.SEATED cleanly.
	var ggrid := PassengerTestWorld.floored(Vector2i(10, 8))
	PassengerTestWorld.place(ggrid, &"entrance_door", Vector2i(0, 7), 3)
	PassengerTestWorld.place(ggrid, &"seat_row", Vector2i(4, 3), 0)
	var gworld := _track_world(
		PassengerTestWorld.make(ggrid, PassengerTestWorld.starts_with(500, 900))
	)
	var gviews := _track_views(gworld)
	var gp := gworld.passenger(gworld.sim.spawn_now(PassengerTestWorld.FLIGHT))
	gp.hunger = 0
	gp.toilet_need = 0
	gp.boredom = 0
	gp.stage = Passenger.Stage.TO_GATE
	gp.cleared = true
	while gp.stage != Passenger.Stage.SEATED and gworld.clock.tick < 400:
		gworld.step()
		gviews.draw()
	assert_int(gp.stage).is_equal(Passenger.Stage.SEATED)
	for _i in int(PassengerFidgetPose.SEATED_SETTLE_TICKS + PassengerFidgetPose.EASE_TICKS + 12):
		gworld.step()
		gviews.draw()
	var gmod := _fidget_of(gviews.node_for(gp.id))
	assert_object(gmod).is_not_null()
	assert_bool(gmod.active).is_true()
	assert_int(gmod.mode).is_equal(PassengerFidgetPose.Mode.SEATED)

	# 3. Nap pod (PodRecline) yields completely.
	var pgrid := BuildGrid.new()
	ActivityTestLayout.build(pgrid, &"nap_pod")
	var pworld := _track_world(PassengerTestWorld.make(pgrid, FlightSim.schedule_starts(0)))
	pworld.auto_staff_roles = [StaffMember.Role.CHECKIN, StaffMember.Role.SECURITY]
	pworld.run_to(10)
	var pviews := _track_views(pworld)
	var pp := ShopTestLayout.airside_guest(pworld, 80, ShopTestLayout.AIRSIDE_CELL)
	while ActivityPoses.recline(pworld.sim, pp) < 0.9 and pworld.clock.tick < 2000:
		pworld.step()
		pviews.draw()
	assert_float(ActivityPoses.recline(pworld.sim, pp)).is_greater_equal(0.9)
	var pmod := _fidget_of(pviews.node_for(pp.id))
	if pmod != null:
		assert_bool(pmod.active).is_false()
		assert_float(pmod.weight).is_equal(0.0)

	# 4. Cafe guest (DiningPose) yields completely.
	var cgrid := BuildGrid.new()
	CafeTestLayout.build(cgrid)
	var cworld := _track_world(PassengerTestWorld.make(cgrid, FlightSim.schedule_starts(0)))
	var cviews := _track_views(cworld)
	var cp := cworld.passenger(cworld.sim.spawn_now(PassengerTestWorld.FLIGHT))
	cp.hunger = 0
	while cp.stage != Passenger.Stage.TO_GATE and cworld.clock.tick < 900:
		cworld.step()
	assert_bool(cworld.sim.cafes.try_visit(cp)).is_true()
	while cp.stage != Passenger.Stage.CAFE_SEATED and cworld.clock.tick < 1500:
		cworld.step()
		cviews.draw()
	for _i in 15:
		cworld.step()
		cviews.draw()
	var cmod := _fidget_of(cviews.node_for(cp.id))
	if cmod != null:
		assert_bool(cmod.active).is_false()
		assert_float(cmod.weight).is_equal(0.0)

	# 5. Toilet stall (TOILET_USE) yields completely.
	var tgrid := BuildGrid.new()
	ToiletTestLayout.build(tgrid)
	var tworld := _track_world(PassengerTestWorld.make(tgrid, FlightSim.schedule_starts(0)))
	var tviews := _track_views(tworld)
	var tp := tworld.passenger(tworld.sim.spawn_now(PassengerTestWorld.FLIGHT))
	tp.toilet_need = 0
	while tp.stage != Passenger.Stage.TO_GATE and tworld.clock.tick < 900:
		tworld.step()
	tp.toilet_need = ToiletSim.NEED_AT + 10
	assert_bool(tworld.sim.toilets.try_visit(tp)).is_true()
	while tp.stage != Passenger.Stage.TOILET_USE and tworld.clock.tick < 1500:
		tworld.step()
		tviews.draw()
	for _i in 15:
		tworld.step()
		tviews.draw()
	var tmod := _fidget_of(tviews.node_for(tp.id))
	if tmod != null:
		assert_bool(tmod.active).is_false()
		assert_float(tmod.weight).is_equal(0.0)


func test_close_call_relief_on_late_boarding_before_despawn() -> void:
	for parity: int in [0, 1]:
		var grid := PassengerTestWorld.floored(Vector2i(12, 8))
		PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 4), 3)
		PassengerTestWorld.place(grid, &"exit_door", Vector2i(11, 4), 1)
		var world := _track_world(
			PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(50, 90))
		)
		var views := _track_views(world)
		var id := world.sim.spawn_now(PassengerTestWorld.FLIGHT)
		var p := world.passenger(id)
		var match_case: bool = parity == 0
		while (
			posmod(p.id, 2) != parity
			or (match_case and SecurityLooks.bag_kind(p, 0) != SecurityLooks.Kind.CASE)
		):
			p.stage = Passenger.Stage.MADE
			id = world.sim.spawn_now(PassengerTestWorld.FLIGHT)
			p = world.passenger(id)
		p.carry_on = 1 if match_case else 0
		p.stage = Passenger.Stage.TO_GATE
		p.cleared = true
		p.late = true
		world.step()
		views.draw()

		# Transition to TO_EXIT (late boarding clearance) triggers close-call relief before despawn.
		world.sim._set_stage(p, Passenger.Stage.TO_EXIT)
		p.at = Vector2i(3, 4)
		p.set_path([Vector2i(3, 4), Vector2i(4, 4), Vector2i(5, 4), Vector2i(11, 4)])
		for _i in 7:
			p.late = true
			world.step()
			views.draw()
		var node := views.node_for(id)
		assert_object(node).is_not_null()
		var mod := _fidget_of(node)
		assert_object(mod).is_not_null()
		assert_bool(mod.active).is_true()
		assert_int(mod.mode).is_equal(PassengerFidgetPose.Mode.CLOSE_CALL)
		assert_float(mod.weight).is_greater(0.8)

		var sk := _skeleton(node)
		var player := node.get_node("AnimationPlayer") as AnimationPlayer
		var prev_speed := player.speed_scale
		player.speed_scale = 0.0
		if parity == 0:
			# Right arm carries hard case; left arm celebrates without disturbing right arm!
			assert_float(await _sample_delta(views, sk, mod, ["Arm.R", "Forearm.R"])).is_less(0.002)
			assert_float(await _sample_delta(views, sk, mod, ["Arm.L", "Forearm.L"])).is_greater(
				0.4
			)
			var props := views.carry_on_props()
			assert_float(props.held_point(id, 0).distance_to(props.grip_of(node, 0))).is_less(0.002)
		else:
			assert_float(await _sample_delta(views, sk, mod, ["Arm.R", "Forearm.R"])).is_greater(
				0.4
			)
		player.speed_scale = prev_speed

		# Transitioning onward to APRON does not retrigger a duplicate cycle; expires cleanly.
		world.sim._set_stage(p, Passenger.Stage.APRON)
		p.apron = [Vector3(11.5, 0.0, 4.5), Vector3(11.5, 0.0, -30.0)]
		p.apron_mm = 0
		for _i in int(PassengerFidgetPose.CLOSE_CALL_TICKS + 4):
			world.step()
			views.draw()
		assert_bool(mod.active).is_false()
		assert_float(mod.weight).is_equal(0.0)


func test_snap_and_clock_backwards_load_reset() -> void:
	# 1. Pure timestamp backwards guard clears coupled state (anti-pattern 6d949060).
	var dummy := Passenger.new()
	dummy.id = 42
	dummy.stage = Passenger.Stage.CHECKIN_QUEUE
	var rec := {
		"wait_since": 40.0,
		"wait_mode": PassengerFidgetPose.Mode.QUEUE,
		"stage": Passenger.Stage.CHECKIN_QUEUE,
	}
	var ev := PassengerFidgetPose._evaluate(dummy, rec, 10.0, true, true)
	assert_int(ev["mode"]).is_equal(PassengerFidgetPose.Mode.NONE)
	assert_float(ev["weight"]).is_equal(0.0)
	assert_bool(rec.has("wait_since")).is_false()

	dummy.stage = Passenger.Stage.SECURITY
	dummy.security_phase = SecurityRuntime.Phase.SCAN
	dummy.alarm = true
	var sec_rec := {"react_key": &"alarm_scan", "react_since": 40.0}
	var sev := PassengerFidgetPose._evaluate(dummy, sec_rec, 10.0, true, true)
	assert_int(sev["mode"]).is_equal(PassengerFidgetPose.Mode.NONE)
	assert_bool(sec_rec.has("react_key")).is_false()
	assert_bool(sec_rec.has("react_since")).is_false()

	# 2. Live backward clock without views.snap() resets security react_key + react_since.
	var sec := SecurityTestWorld.make(false, 7)
	_worlds.append(sec.world)
	var sviews := _track_views(sec.world)
	var sid := sec.send(1, false, true)
	var sp := sec.world.passenger(sid)
	while (
		not (
			sp.security_phase == SecurityRuntime.Phase.SCAN
			and sviews._fidgets.get(sid, {}).has("react_since")
		)
		and sec.world.clock.tick < 1500
	):
		sec.world.step()
		sviews.draw()
	assert_int(sp.security_phase).is_equal(SecurityRuntime.Phase.SCAN)
	assert_bool(sviews._fidgets.get(sid, {}).has("react_since")).is_true()
	var sec_early := {
		"clock": sec.world.clock.to_snapshot(),
		"flights": sec.world.flights.to_snapshot(),
		"sim": sec.world.sim.to_snapshot(),
	}
	var sec_early_tick := sec.world.clock.tick

	# Advance past SCAN_REACTION_TICKS so react_since expires while react_key remains set.
	for _i in int(PassengerFidgetPose.SCAN_REACTION_TICKS + 1):
		sec.world.step()
		sviews.draw()
	assert_int(sp.security_phase).is_equal(SecurityRuntime.Phase.SCAN)
	var snode := sviews.node_for(sid)
	var smod := _fidget_of(snode)
	assert_object(smod).is_not_null()
	assert_bool(smod.active).is_false()
	assert_bool(sviews._fidgets.get(sid, {}).has("react_key")).is_true()
	assert_bool(sviews._fidgets.get(sid, {}).has("react_since")).is_false()

	# Load back to sec_early_tick WITHOUT views.snap(): sync_passenger must clear & re-seed.
	assert_bool(sec.world.clock.from_snapshot(sec_early["clock"])).is_true()
	assert_bool(sec.world.flights.from_snapshot(sec_early["flights"])).is_true()
	assert_bool(sec.world.sim.from_snapshot(sec_early["sim"])).is_true()
	sviews.sync()
	sviews.draw()
	assert_int(sec.world.clock.tick).is_equal(sec_early_tick)
	assert_float(sviews._fidgets[sid].get("last_tick", -1.0)).is_equal(float(sec_early_tick))
	assert_float(sviews._fidgets[sid].get("react_since", -1.0)).is_equal(float(sec_early_tick))
	for _i in 5:
		sec.world.step()
		sviews.draw()
	assert_bool(smod.active).is_true()
	assert_int(smod.mode).is_equal(PassengerFidgetPose.Mode.ALARM)
	assert_float(smod.weight).is_greater(0.5)

	# 3. Live backward clock without views.snap() resets queue wait/fade + close-call state.
	var grid := PassengerTestWorld.floored(Vector2i(10, 8))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 7), 3)
	PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(6, 2), 0)
	var world := _track_world(
		PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(20, 600))
	)
	var views := _track_views(world)

	for _k in 2:
		var blk := world.sim.spawn_now(PassengerTestWorld.FLIGHT)
		world.passenger(blk).carry_on = 0
		for _t in 12:
			world.step()
	var id := world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var p := world.passenger(id)
	p.carry_on = 0
	while (
		not (p.stage == Passenger.Stage.CHECKIN_QUEUE and not p.is_moving())
		and world.clock.tick < 600
	):
		world.step()
		views.draw()

	var early_snap := {
		"clock": world.clock.to_snapshot(),
		"flights": world.flights.to_snapshot(),
		"sim": world.sim.to_snapshot(),
	}
	var early_tick := world.clock.tick

	for _i in int(PassengerFidgetPose.QUEUE_SETTLE_TICKS + PassengerFidgetPose.EASE_TICKS + 12):
		world.step()
		views.draw()
	var node := views.node_for(id)
	var mod := _fidget_of(node)
	assert_object(mod).is_not_null()
	assert_bool(mod.active).is_true()
	assert_float(mod.weight).is_greater(0.5)
	views._fidgets[id]["fade_since"] = float(world.clock.tick)
	views._fidgets[id]["fade_from"] = 0.8
	views._fidgets[id]["close_call_since"] = float(world.clock.tick)
	views._fidgets[id]["close_call_done"] = true

	# Load back to early_tick WITHOUT views.snap().
	assert_bool(world.clock.from_snapshot(early_snap["clock"])).is_true()
	assert_bool(world.flights.from_snapshot(early_snap["flights"])).is_true()
	assert_bool(world.sim.from_snapshot(early_snap["sim"])).is_true()
	views.sync()
	views.draw()

	assert_int(world.clock.tick).is_equal(early_tick)
	assert_bool(mod.active).is_false()
	assert_float(mod.weight).is_equal(0.0)
	assert_bool(views._fidgets.get(id, {}).has("fade_since")).is_false()
	assert_bool(views._fidgets.get(id, {}).has("close_call_since")).is_false()
	assert_bool(views._fidgets.get(id, {}).get("close_call_done", false)).is_false()
	assert_float(views._fidgets.get(id, {}).get("wait_since", -1.0)).is_equal(float(early_tick))

	# Re-advancing from early_tick plays queue fidget cleanly, and snap() also resets cleanly.
	for _i in int(PassengerFidgetPose.QUEUE_SETTLE_TICKS + PassengerFidgetPose.EASE_TICKS + 12):
		world.step()
		views.draw()
	assert_bool(mod.active).is_true()
	assert_int(mod.mode).is_equal(PassengerFidgetPose.Mode.QUEUE)
	assert_float(mod.weight).is_greater(0.5)

	assert_bool(world.clock.from_snapshot(early_snap["clock"])).is_true()
	assert_bool(world.flights.from_snapshot(early_snap["flights"])).is_true()
	assert_bool(world.sim.from_snapshot(early_snap["sim"])).is_true()
	views.snap()
	assert_bool(mod.active).is_false()
	assert_float(mod.weight).is_equal(0.0)
	assert_float(views._fidgets.get(id, {}).get("wait_since", -1.0)).is_equal(float(early_tick))

	# 4. Live close-call backward clock without views.snap() clears close_call_done so it retriggers.
	var cgrid := PassengerTestWorld.floored(Vector2i(12, 8))
	PassengerTestWorld.place(cgrid, &"entrance_door", Vector2i(0, 4), 3)
	PassengerTestWorld.place(cgrid, &"exit_door", Vector2i(11, 4), 1)
	var cworld := _track_world(
		PassengerTestWorld.make(cgrid, PassengerTestWorld.starts_with(50, 90))
	)
	var cviews := _track_views(cworld)
	var cid := cworld.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var cp := cworld.passenger(cid)
	cp.carry_on = 0
	cp.stage = Passenger.Stage.TO_GATE
	cp.cleared = true
	cp.late = true
	cworld.step()
	cviews.draw()
	var cc_early := {
		"clock": cworld.clock.to_snapshot(),
		"flights": cworld.flights.to_snapshot(),
		"sim": cworld.sim.to_snapshot(),
	}
	var cc_early_tick := cworld.clock.tick

	cworld.sim._set_stage(cp, Passenger.Stage.TO_EXIT)
	cp.at = Vector2i(3, 4)
	cp.set_path([Vector2i(3, 4), Vector2i(4, 4), Vector2i(5, 4), Vector2i(11, 4)])
	for _i in 7:
		cp.late = true
		cworld.step()
		cviews.draw()
	var cmod := _fidget_of(cviews.node_for(cid))
	assert_object(cmod).is_not_null()
	assert_bool(cmod.active).is_true()
	assert_int(cmod.mode).is_equal(PassengerFidgetPose.Mode.CLOSE_CALL)
	assert_bool(cviews._fidgets[cid].get("close_call_done", false)).is_true()

	assert_bool(cworld.clock.from_snapshot(cc_early["clock"])).is_true()
	assert_bool(cworld.flights.from_snapshot(cc_early["flights"])).is_true()
	assert_bool(cworld.sim.from_snapshot(cc_early["sim"])).is_true()
	cviews.sync()
	cviews.draw()
	assert_int(cworld.clock.tick).is_equal(cc_early_tick)
	assert_bool(cmod.active).is_false()
	assert_bool(cviews._fidgets[cid].has("close_call_since")).is_false()
	assert_bool(cviews._fidgets[cid].get("close_call_done", false)).is_false()

	cp = cworld.passenger(cid)
	cworld.sim._set_stage(cp, Passenger.Stage.TO_EXIT)
	cp.at = Vector2i(3, 4)
	cp.set_path([Vector2i(3, 4), Vector2i(4, 4), Vector2i(5, 4), Vector2i(11, 4)])
	for _i in 7:
		cp.late = true
		cworld.step()
		cviews.draw()
	assert_bool(cmod.active).is_true()
	assert_int(cmod.mode).is_equal(PassengerFidgetPose.Mode.CLOSE_CALL)
	assert_float(cmod.weight).is_greater(0.8)


func test_helped_security_lane_repack_reaction_eases_without_snap() -> void:
	for bags: int in [1, 2]:
		var sec := SecurityTestWorld.make(true, 7)
		_worlds.append(sec.world)
		sec.world.auto_staff = false
		StaffTestKit.seat(sec.world.staff, sec.station, StaffMember.Slot.PRIMARY)
		StaffTestKit.seat(sec.world.staff, sec.station, StaffMember.Slot.HELPER)
		var views := _track_views(sec.world)
		var id := sec.send(bags, true, false)
		var p := sec.world.passenger(id)

		while p.security_phase != SecurityRuntime.Phase.REPACK and sec.world.clock.tick < 1500:
			sec.world.step()
			views.draw()
		assert_int(p.security_phase).is_equal(SecurityRuntime.Phase.REPACK)
		assert_int(sec.world.sim.security.rate(sec.station, SecurityRuntime.Phase.REPACK)).is_equal(
			SecurityRuntime.HELPER_RATE
		)

		var node := views.node_for(id)
		var mod := _fidget_of(node)
		var prev_w := mod.weight if mod != null and mod.active else 0.0
		assert_float(prev_w).is_equal(0.0)
		var max_w := 0.0
		var max_jump := 0.0
		var saw_repack_pose := false
		for _f in 60:
			sec.world.clock.advance(SimClock.STEP / 3.0)
			views.draw()
			mod = _fidget_of(node)
			var w := mod.weight if mod != null and mod.active else 0.0
			if RepackPose.weight_for(p) > 0.0:
				assert_float(w).is_equal(0.0)
				saw_repack_pose = true
				break
			max_w = maxf(max_w, w)
			max_jump = maxf(max_jump, absf(w - prev_w))
			prev_w = w
		assert_bool(saw_repack_pose).is_true()
		assert_float(max_w).is_greater(0.1)
		assert_float(max_jump).is_less_equal(0.20)


func test_seated_spine_guarded_when_arm_held_and_clock_null_snap_moving() -> void:
	# 1. Seated variants 1 and 2 keep Spine_01/Spine_02 untouched when an arm is held.
	var body := PassengerLooks.SCENES[0].instantiate() as Node3D
	add_child(body)
	_nodes.append(body)
	var sk := _skeleton(body)
	var player := body.get_node("AnimationPlayer") as AnimationPlayer
	player.play("sit_idle")
	player.speed_scale = 0.0
	PassengerFidgetPose.apply(body, PassengerFidgetPose.Mode.SEATED, 1.0, 1.2, 1, 1, false, true)
	var mod := _fidget_of(body)
	assert_object(mod).is_not_null()
	for sub: int in [1, 2]:
		mod.sub_variant = sub
		var spine_delta := await _sample_delta(null, sk, mod, ["Spine_01", "Spine_02"])
		var head_delta := await _sample_delta(null, sk, mod, ["Head", "Neck"])
		assert_float(spine_delta).is_less(0.0005)
		assert_float(head_delta).is_greater(0.1)

	# 2. Consistent _now() fallback when clock == null and sim.tick > 0, plus snap() stationary check.
	var grid := PassengerTestWorld.floored(Vector2i(10, 8))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 7), 3)
	PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(6, 2), 0)
	var world := _track_world(
		PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(20, 600))
	)
	var views := _track_views(world)
	for _k in 2:
		var blk := world.sim.spawn_now(PassengerTestWorld.FLIGHT)
		world.passenger(blk).carry_on = 0
		for _t in 12:
			world.step()
	var id := world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var p := world.passenger(id)
	p.carry_on = 0
	while (
		not (p.stage == Passenger.Stage.CHECKIN_QUEUE and not p.is_moving())
		and world.clock.tick < 600
	):
		world.step()
		views.draw()
	assert_int(p.stage).is_equal(Passenger.Stage.CHECKIN_QUEUE)
	assert_int(world.clock.tick).is_greater(0)

	# Snapshot stationary passenger, move cell, restore, and verify snap() keeps moving=false.
	var saved_sim := world.sim.to_snapshot()
	var saved_tick := world.clock.tick
	var shifted_node := views.node_for(id)
	shifted_node.position += Vector3(2.0, 0.0, 0.0)
	views._cur[id] += Vector3(2.0, 0.0, 0.0)
	assert_bool(world.sim.from_snapshot(saved_sim)).is_true()
	views.snap()
	assert_bool(views._fidgets.get(id, {}).get("moving", true)).is_false()
	assert_float(views._fidgets.get(id, {}).get("wait_since", -1.0)).is_equal(float(saved_tick))

	# With views.clock = null and sim.tick > 0, sync() + draw() never wipe last_tick/wait_since.
	views.clock = null
	views.sync()
	views.draw()
	assert_float(views._fidgets.get(id, {}).get("last_tick", -1.0)).is_equal(float(saved_tick))
	assert_float(views._fidgets.get(id, {}).get("wait_since", -1.0)).is_equal(float(saved_tick))


func test_fidget_survives_3x_frame_hitch_and_non_integer_frame_steps() -> void:
	# 1. Active queue fidget survives a 3x frame hitch (MAX_STEPS_PER_FRAME clamp).
	var grid := PassengerTestWorld.floored(Vector2i(10, 8))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 7), 3)
	PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(6, 2), 0)
	var world := _track_world(
		PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(20, 600))
	)
	var views := _track_views(world)
	for _k in 2:
		var blk := world.sim.spawn_now(PassengerTestWorld.FLIGHT)
		world.passenger(blk).carry_on = 0
		for _t in 12:
			world.step()
	var id := world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var p := world.passenger(id)
	p.carry_on = 0
	while (
		not (p.stage == Passenger.Stage.CHECKIN_QUEUE and not p.is_moving())
		and world.clock.tick < 600
	):
		world.step()
		views.draw()
	for _i in int(PassengerFidgetPose.QUEUE_SETTLE_TICKS + PassengerFidgetPose.EASE_TICKS + 12):
		world.step()
		views.draw()
	var mod := _fidget_of(views.node_for(id))
	assert_object(mod).is_not_null()
	assert_bool(mod.active).is_true()
	assert_float(mod.weight).is_greater(0.5)
	var wait_since := float(views._fidgets.get(id, {}).get("wait_since", -1.0))
	assert_float(wait_since).is_greater_equal(0.0)

	world.clock.speed = 3
	world.clock.advance(0.25)
	views.draw()
	world.clock.speed = 1
	assert_int(p.stage).is_equal(Passenger.Stage.CHECKIN_QUEUE)
	assert_float(float(views._fidgets.get(id, {}).get("wait_since", -1.0))).is_equal(wait_since)
	assert_bool(mod.active).is_true()
	assert_float(mod.weight).is_greater(0.5)

	# 2. Helped-lane REPACK at non-integer frame dt (0.0213 s / ~47 FPS) keeps exact repack_span.
	var sec := SecurityTestWorld.make(true, 7)
	_worlds.append(sec.world)
	sec.world.auto_staff = false
	StaffTestKit.seat(sec.world.staff, sec.station, StaffMember.Slot.PRIMARY)
	StaffTestKit.seat(sec.world.staff, sec.station, StaffMember.Slot.HELPER)
	var sviews := _track_views(sec.world)
	var sid := sec.send(1, true, false)
	var sp := sec.world.passenger(sid)
	while sp.security_phase != SecurityRuntime.Phase.REPACK and sec.world.clock.tick < 1500:
		sec.world.step()
		sviews.draw()
	assert_int(sp.security_phase).is_equal(SecurityRuntime.Phase.REPACK)
	sec.world.step()
	sviews.draw()
	while not sviews._fidgets.get(sid, {}).has("repack_span") and sec.world.clock.tick < 1500:
		sec.world.step()
		sviews.draw()
	var smod := _fidget_of(sviews.node_for(sid))
	var first_span := float(sviews._fidgets.get(sid, {}).get("repack_span", -1.0))
	assert_float(first_span).is_greater(0.0)
	var prev_w := smod.weight if smod != null and smod.active else 0.0
	var max_w := prev_w
	var max_jump := 0.0
	var saw_repack := false
	for _f in 50:
		sec.world.clock.advance(0.0213)
		sviews.draw()
		smod = _fidget_of(sviews.node_for(sid))
		var w := smod.weight if smod != null and smod.active else 0.0
		if RepackPose.weight_for(sp) > 0.0:
			assert_float(w).is_equal(0.0)
			saw_repack = true
			break
		if sviews._fidgets.get(sid, {}).has("repack_span"):
			assert_float(float(sviews._fidgets[sid]["repack_span"])).is_equal(first_span)
		max_w = maxf(max_w, w)
		max_jump = maxf(max_jump, absf(w - prev_w))
		prev_w = w
	assert_bool(saw_repack).is_true()
	assert_float(max_w).is_greater(0.1)
	assert_float(max_jump).is_less_equal(0.25)
