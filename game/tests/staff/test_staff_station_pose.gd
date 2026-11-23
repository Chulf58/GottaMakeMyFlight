class_name TestStaffStationPose
extends GdUnitTestSuite
## Procedural SkeletonModifier3D station-interaction poses (StaffStationPose,
## StaffCharacters): CHECKIN, SECURITY, SHOP, GATE, and RAMP marshal activate
## non-zero bone deltas while actively serving/marshalling and cleanly zero back
## to rest when idle, walking, pooled, or snapped on load.

const CHECKIN_CELL := Vector2i(13, 13)
const SITE := preload("res://build/terminal_site.tres")

var _world: PassengerTestWorld
var _gate_world: GateWalkWorld
var _views: StaffCharacters
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


func _attach_views(world: PassengerTestWorld) -> void:
	_views = StaffCharacters.new()
	_views.clock = world.clock
	_views.staff = world.staff
	_views.flights = world.flights
	add_child(_views)
	_views.sync(true)
	_views.draw()


func _skeleton_of(node: Node3D) -> Skeleton3D:
	return node.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D


func _skeleton_tick(skeleton: Skeleton3D) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await skeleton.skeleton_updated


## Measures max rotation angle (rad) across `bones` between modifier off and on
## on `node` with AnimationPlayer paused at its current frame.
func _measure_pose_delta(node: Node3D, bones: Array[String]) -> float:
	var sk := _skeleton_of(node)
	var player := node.get_node("AnimationPlayer") as AnimationPlayer
	var prev_speed := player.speed_scale
	player.speed_scale = 0.0
	_views.set_process(false)
	var mod: StaffStationPose = node.get_meta(&"station_pose")
	mod.active = false
	await _skeleton_tick(sk)
	var rest := {}
	for bone in bones:
		rest[bone] = sk.get_bone_global_pose(sk.find_bone(bone)).basis.get_rotation_quaternion()
	mod.active = true
	await _skeleton_tick(sk)
	var worst := 0.0
	for bone in bones:
		var q_now := sk.get_bone_global_pose(sk.find_bone(bone)).basis.get_rotation_quaternion()
		worst = maxf(worst, (rest[bone] as Quaternion).angle_to(q_now))
	_views.set_process(true)
	player.speed_scale = prev_speed
	return worst


func _pose_delta_from_rest(node: Node3D, bones: Array[String], rest: Dictionary) -> float:
	var sk := _skeleton_of(node)
	var player := node.get_node("AnimationPlayer") as AnimationPlayer
	var prev_speed := player.speed_scale
	player.play("idle")
	player.seek(0.0, true)
	player.speed_scale = 0.0
	await _skeleton_tick(sk)
	var worst := 0.0
	for bone in bones:
		var q_now := sk.get_bone_global_pose(sk.find_bone(bone)).basis.get_rotation_quaternion()
		worst = maxf(worst, (rest[bone] as Quaternion).angle_to(q_now))
	player.speed_scale = prev_speed
	return worst


func _capture_idle_baseline(node: Node3D, bones: Array[String]) -> Dictionary:
	var player := node.get_node("AnimationPlayer") as AnimationPlayer
	player.play("idle")
	player.seek(0.0, true)
	player.speed_scale = 0.0
	var sk := _skeleton_of(node)
	await _skeleton_tick(sk)
	var out := {}
	for bone in bones:
		var idx := sk.find_bone(bone)
		out[bone] = sk.get_bone_global_pose(idx).basis.get_rotation_quaternion()
	return out


func test_checkin_security_and_shop_poses_activate_and_zero_cleanly() -> void:
	var grid := BuildGrid.new()
	CafeTestLayout.build(grid, false, &"cafe", true)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(3000, 6000), 11)
	_world.auto_staff = false
	StaffTestKit.staff_all(_world.staff)
	_attach_views(_world)

	var bones: Array[String] = ["Head", "Arm.R", "Forearm.R"]
	# Idle before any passenger arrives: zero weight, zero modifier activity, capture rest pose.
	await get_tree().process_frame
	var rest_baselines := {}
	for sid in _world.staff.member_ids():
		assert_float(_views.station_pose_weight(sid)).is_equal(0.0)
		assert_int(_views.station_pose_mode(sid)).is_equal(StaffStationPose.Mode.NONE)
		var node := _views.node_for(sid)
		assert_bool(node.has_meta(&"station_pose")).is_false()
		rest_baselines[sid] = await _capture_idle_baseline(node, bones)
	_views.sync(true)
	_views.draw()

	var pid := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var pax := _world.passenger(pid)
	ToiletTestLayout.calm(pax)
	pax.cafe_cooldown = 1000000
	pax.hunger = 0
	pax.carry_on = 1
	pax.liquids = false
	pax.alarm = true
	var saw := {
		"checkin": 0.0,
		"scan": 0.0,
		"repack": 0.0,
		"shop": 0.0,
	}
	var used_ids := {}
	var cafe_started := false
	var guard := 0
	while guard < 1500:
		_world.step()
		_views.draw()
		if not cafe_started and pax.stage == Passenger.Stage.TO_GATE:
			cafe_started = true
			pax.hunger = CafeSim.HUNGRY_AT + 10
			assert_bool(_world.sim.cafes.try_visit(pax)).is_true()
		for sid in _world.staff.member_ids():
			var mode := _views.station_pose_mode(sid)
			var w := _views.station_pose_weight(sid)
			if w < 0.99 or mode == StaffStationPose.Mode.NONE:
				continue
			if mode == StaffStationPose.Mode.CHECKIN and saw["checkin"] == 0.0:
				used_ids["checkin"] = sid
				saw["checkin"] = await _measure_pose_delta(_views.node_for(sid), bones)
			elif mode == StaffStationPose.Mode.SECURITY_SCAN and saw["scan"] == 0.0:
				used_ids["scan"] = sid
				saw["scan"] = await _measure_pose_delta(_views.node_for(sid), bones)
			elif mode == StaffStationPose.Mode.SECURITY_REPACK and saw["repack"] == 0.0:
				used_ids["repack"] = sid
				saw["repack"] = await _measure_pose_delta(_views.node_for(sid), bones)
			elif mode == StaffStationPose.Mode.SHOP and saw["shop"] == 0.0:
				used_ids["shop"] = sid
				saw["shop"] = await _measure_pose_delta(_views.node_for(sid), bones)
		if (
			saw["shop"] > 0.0
			and _views.station_pose_weight(used_ids["shop"]) == 0.0
			and pax.stage == Passenger.Stage.CAFE_SEATED
		):
			break
		guard += 1

	print("station pose bone deltas (rad): %s" % [saw])
	assert_float(saw["checkin"]).is_greater(0.15)
	assert_float(saw["scan"]).is_greater(0.15)
	assert_float(saw["repack"]).is_greater(0.15)
	assert_float(saw["shop"]).is_greater(0.15)

	# After serving ends, the latest station rests naturally in Mode.NONE and
	# older ones are NONE or IDLE_FIDGET (never a station mode).
	_world.clock.set_paused(true)
	_views.draw()
	var shop_sid: int = used_ids["shop"]
	assert_int(_views.station_pose_mode(shop_sid)).is_equal(StaffStationPose.Mode.NONE)
	var shop_node := _views.node_for(shop_sid)
	var shop_mod: StaffStationPose = shop_node.get_meta(&"station_pose")
	assert_bool(shop_mod.active).is_false()
	assert_float(shop_mod.weight).is_equal(0.0)
	assert_float(await _pose_delta_from_rest(shop_node, bones, rest_baselines[shop_sid])).is_less(
		0.001
	)

	for key in used_ids:
		var sid: int = used_ids[key]
		assert_float(_views.station_pose_weight(sid)).is_equal(0.0)
		var mode_after := _views.station_pose_mode(sid)
		(
			assert_bool(
				(
					mode_after == StaffStationPose.Mode.NONE
					or mode_after == StaffStationPose.Mode.IDLE_FIDGET
				)
			)
			. is_true()
		)

	# Step naturally until every used staff member enters an inactive fidget
	# window (Mode.NONE) without mutating modifier state, then verify rest.
	_world.clock.set_paused(false)
	for key in used_ids:
		var sid: int = used_ids[key]
		for _t in StaffStationPose.FIDGET_PERIOD_TICKS + 20:
			if _views.station_pose_mode(sid) == StaffStationPose.Mode.NONE:
				break
			_world.step()
			_views.draw()
		assert_int(_views.station_pose_mode(sid)).is_equal(StaffStationPose.Mode.NONE)
		assert_float(_views.idle_fidget_weight(sid)).is_equal(0.0)
		var node := _views.node_for(sid)
		var mod: StaffStationPose = node.get_meta(&"station_pose")
		assert_bool(mod.active).is_false()
		assert_float(mod.weight).is_equal(0.0)
		_world.clock.set_paused(true)
		assert_float(await _pose_delta_from_rest(node, bones, rest_baselines[sid])).is_less(0.001)
		_world.clock.set_paused(false)


func test_gate_agent_poses_during_boarding_and_zeros_on_snap() -> void:
	_gate_world = GateWalkWorld.make(self, true)
	_world = _gate_world.world
	_world.flights._flights = _world.flights._flights.filter(
		func(f: Dictionary) -> bool: return String(f.get("id", "")) == GateWalkWorld.FLIGHT
	)
	StaffTestKit.staff_all(_world.staff, [StaffMember.Role.GATE])
	var gate_staff := _world.staff.staff_at(_gate_world.desk)
	assert_int(gate_staff).is_greater(0)
	_attach_views(_world)

	var bones: Array[String] = ["Head", "Arm.R", "Forearm.R"]
	await get_tree().process_frame
	assert_float(_views.station_pose_weight(gate_staff)).is_equal(0.0)

	var pid := _gate_world.send()
	assert_bool(_gate_world.run_until_stage(pid, Passenger.Stage.SEATED, 2000)).is_true()
	_world.run_to(GateWalkWorld.BOARDING - 1)
	_views.draw()
	assert_float(_views.station_pose_weight(gate_staff)).is_equal(0.0)

	var saved_clock: Variant = JSON.parse_string(JSON.stringify(_world.clock.to_snapshot()))
	var saved_flights: Variant = JSON.parse_string(JSON.stringify(_world.flights.to_snapshot()))
	var saved_staff: Variant = JSON.parse_string(JSON.stringify(_world.staff.to_snapshot()))
	var saved_pax: Variant = JSON.parse_string(JSON.stringify(_world.sim.to_snapshot()))

	_world.run_to(GateWalkWorld.BOARDING + 40)
	_views.draw()
	assert_int(_views.station_pose_mode(gate_staff)).is_equal(StaffStationPose.Mode.GATE)
	assert_float(_views.station_pose_weight(gate_staff)).is_equal(1.0)
	var gate_node := _views.node_for(gate_staff)
	var delta := await _measure_pose_delta(gate_node, bones)
	print("gate pose delta: %.3f rad" % delta)
	assert_float(delta).is_greater(0.15)

	# Snap/load back before boarding resets pose weight to 0 immediately.
	assert_bool(_world.clock.from_snapshot(saved_clock)).is_true()
	assert_bool(_world.flights.from_snapshot(saved_flights)).is_true()
	assert_bool(_world.staff.from_snapshot(saved_staff)).is_true()
	assert_bool(_world.sim.from_snapshot(saved_pax)).is_true()
	_views.sync(true)
	_views.draw()
	assert_float(_views.station_pose_weight(gate_staff)).is_equal(0.0)
	var mod: StaffStationPose = gate_node.get_meta(&"station_pose")
	assert_bool(mod.active).is_false()
	var rest := await _capture_idle_baseline(gate_node, bones)
	assert_float(await _pose_delta_from_rest(gate_node, bones, rest)).is_less(0.001)


func test_ramp_marshal_raises_arms_during_taxi_in_and_clears_on_release() -> void:
	var grid := SiteGrid.new(SITE)
	StarterShell.place(grid, SITE.starter_offset)
	ReferenceTerminal.fill_interior(grid, SITE.starter_offset)
	var starts := FlightSim.schedule_starts(0)
	_world = PassengerTestWorld.make(grid, starts, 17)
	_world.sim.site = SITE
	_world.auto_staff = false
	_world.flights._flights.clear()
	_world.flights._contracts.clear()
	_finances = auto_free(Finances.new()) as Finances
	_finances.clock = _world.clock
	_finances.start_new_game()
	_world.sim.wallet = _finances.wallet
	_rating = auto_free(AirportRating.new()) as AirportRating
	_rating.bind(_world.clock, _world.flights, _world.sim)
	_dispatch = auto_free(RampDispatch.new()) as RampDispatch
	_dispatch.bind(_world.clock, _world.staff, null, _world.flights, _finances, _rating)

	_world.flights.runway.size = PlaneClasses.MEDIUM
	var terms := {
		"id": "M1",
		"airline": "Nordic Jet",
		"destination": "Bergen",
		"departure_minute": 480,
		"plane_size": PlaneClasses.MEDIUM,
		"booked_passengers": 30,
		"fee_per_passenger": 30,
	}
	_world.flights._contracts.append(
		_world.flights._candidate(terms, "C", _world.flights.gate_grounds())
	)
	var fid := "M1-d0"
	_world.flights._insert(_world.flights._record(fid, starts, "C", "M1", 0))
	_world.flights._changed()

	var ramp_id := _world.staff.hire(StaffMember.Role.RAMP)
	_attach_views(_world)
	var taxi_in := _world.flights.state_start(fid, FlightSim.State.TAXI_IN)
	_world.run_to(taxi_in + 10)
	_views.draw()

	var m := _world.staff.get_member(ramp_id)
	assert_int(m.ramp_job).is_equal(StaffMember.RampJob.MARSHAL)
	var node := _views.node_for(ramp_id)
	assert_object(node).is_not_null()
	assert_int(_views.station_pose_mode(ramp_id)).is_equal(StaffStationPose.Mode.RAMP_MARSHAL)
	assert_float(_views.station_pose_weight(ramp_id)).is_equal(1.0)

	_world.clock.set_paused(true)
	_views.draw()
	var sk := _skeleton_of(node)
	(node.get_node("AnimationPlayer") as AnimationPlayer).speed_scale = 0.0
	await _skeleton_tick(sk)
	var arm_l := sk.get_bone_global_pose(sk.find_bone("Arm.L"))
	var forearm_l := sk.get_bone_global_pose(sk.find_bone("Forearm.L"))
	var raised_dir := (forearm_l.origin - arm_l.origin).normalized()
	print("marshal raised Arm.L->Forearm.L dir: %s" % raised_dir)
	# Overhead marshal arm points upward (+y) and slightly forward (+z).
	assert_float(raised_dir.y).is_greater(0.4)
	assert_float(raised_dir.z).is_greater(0.0)
	_world.clock.set_paused(false)

	# Once plane arrives AT_STAND, marshal returns to pool with modifier off.
	var at_stand := _world.flights.state_start(fid, FlightSim.State.AT_STAND)
	_world.run_to(at_stand + 1)
	_views.draw()
	assert_int(m.ramp_job).is_equal(StaffMember.RampJob.NONE)
	assert_object(_views.node_for(ramp_id)).is_null()
	assert_bool(node.visible).is_false()
	var mod: StaffStationPose = node.get_meta(&"station_pose")
	assert_bool(mod.active).is_false()
	assert_float(mod.weight).is_equal(0.0)


func test_ramp_shuttle_unloading_and_pushback_hookup_poses() -> void:
	var bag_world := BagTestWorld.make(self, 600)
	PassengerTestWorld.place(bag_world.grid, &"baggage_cart", Vector2i(11, 7), 0)
	var staff := auto_free(StaffSim.new()) as StaffSim
	var pax := auto_free(PassengerSim.new()) as PassengerSim
	pax.clock = bag_world.clock
	pax.flights = bag_world.flights
	pax.grid = bag_world.grid
	pax.layout = TerminalLayout.new()
	pax.staff = staff
	staff.bind(pax)
	var dispatch := auto_free(RampDispatch.new()) as RampDispatch
	dispatch.bind(bag_world.clock, staff, bag_world.sim, bag_world.flights)
	var chars := StaffCharacters.new()
	chars.clock = bag_world.clock
	chars.staff = staff
	chars.baggage = bag_world.sim
	chars.flights = bag_world.flights
	add_child(chars)
	_views = chars

	var shuttle_worker := staff.hire(StaffMember.Role.RAMP)
	var bag := bag_world.sim.check_in(1, BagTestWorld.FLIGHT, bag_world.line())
	bag_world.run_to(bag.cutoff_tick)
	var shuttle := bag_world.sim.shuttles()[0]
	chars.sync(true)
	chars.draw()
	assert_int(chars.station_pose_mode(shuttle_worker)).is_equal(StaffStationPose.Mode.NONE)

	bag_world.run_to(shuttle.arrive_tick)
	chars.sync(true)
	chars.draw()
	assert_int(chars.station_pose_mode(shuttle_worker)).is_equal(StaffStationPose.Mode.RAMP_SHUTTLE)
	assert_float(chars.station_pose_weight(shuttle_worker)).is_equal(1.0)
	var s_node := chars.node_for(shuttle_worker)
	var s_delta := await _measure_pose_delta(s_node, ["Spine_01", "Arm.R", "Forearm.R"])
	assert_float(s_delta).is_greater(0.15)
	await get_tree().process_frame
	_views.free()
	_views = null

	# Pushback worker shows RAMP_HOOKUP in DOORS_CLOSED and RAMP_GUIDE in PUSHBACK.
	var grid := SiteGrid.new(SITE)
	StarterShell.place(grid, SITE.starter_offset)
	ReferenceTerminal.fill_interior(grid, SITE.starter_offset)
	var starts := FlightSim.schedule_starts(0)
	_world = PassengerTestWorld.make(grid, starts, 19)
	_world.sim.site = SITE
	_world.auto_staff = false
	_world.flights._flights.clear()
	_world.flights._contracts.clear()
	_finances = auto_free(Finances.new()) as Finances
	_finances.clock = _world.clock
	_finances.start_new_game()
	_world.sim.wallet = _finances.wallet
	_rating = auto_free(AirportRating.new()) as AirportRating
	_rating.bind(_world.clock, _world.flights, _world.sim)
	_dispatch = auto_free(RampDispatch.new()) as RampDispatch
	_dispatch.bind(_world.clock, _world.staff, null, _world.flights, _finances, _rating)
	_world.flights.runway.size = PlaneClasses.MEDIUM
	var terms := {
		"id": "M2",
		"airline": "Nordic Jet",
		"destination": "Oslo",
		"departure_minute": 480,
		"plane_size": PlaneClasses.MEDIUM,
		"booked_passengers": 30,
		"fee_per_passenger": 30,
	}
	_world.flights._contracts.append(
		_world.flights._candidate(terms, "C", _world.flights.gate_grounds())
	)
	var fid := "M2-d0"
	_world.flights._insert(_world.flights._record(fid, starts, "C", "M2", 0))
	_world.flights._changed()

	var pb_id := _world.staff.hire(StaffMember.Role.RAMP)
	_attach_views(_world)
	_world.run_to(_world.flights.state_start(fid, FlightSim.State.DOORS_CLOSED))
	_views.draw()
	assert_int(_views.station_pose_mode(pb_id)).is_equal(StaffStationPose.Mode.RAMP_PUSHBACK)
	assert_int(_views.station_pose_sub_mode(pb_id)).is_equal(StaffStationPose.SubMode.RAMP_HOOKUP)
	var pb_node := _views.node_for(pb_id)
	assert_str(String(pb_node.get_meta(&"clip", ""))).is_equal("idle")
	var pb_delta := await _measure_pose_delta(pb_node, ["Spine_01", "Arm.L", "Forearm.L"])
	assert_float(pb_delta).is_greater(0.15)

	_world.run_to(_world.flights.state_start(fid, FlightSim.State.PUSHBACK))
	_views.draw()
	assert_int(_views.station_pose_sub_mode(pb_id)).is_equal(StaffStationPose.SubMode.RAMP_GUIDE)
	assert_str(String(pb_node.get_meta(&"clip", ""))).is_equal("walk")


func test_security_alarm_liquids_and_clean_poses_differ_in_world() -> void:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(3000, 6000), 13)
	_world.auto_staff = false
	StaffTestKit.staff_all(_world.staff, [StaffMember.Role.SECURITY])
	_attach_views(_world)

	var scanner: int = _world.sim.layout.scanners[0]
	var officer_id := _world.staff.staff_at(scanner)
	var officer_node := _views.node_for(officer_id)
	var sk := _skeleton_of(officer_node)

	var recorded := {}
	for label: String in ["alarm", "liquids", "clean"]:
		var pid := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
		var pax := _world.passenger(pid)
		ToiletTestLayout.calm(pax)
		pax.cafe_cooldown = 1000000
		pax.carry_on = 0
		pax.alarm = label == "alarm"
		pax.liquids = label == "liquids"
		pax.stage = Passenger.Stage.TO_SECURITY
		pax.at = (
			_world.sim.layout.lanes[scanner][0]
			if _world.sim.layout.lanes.has(scanner)
			else _world.grid.interaction_cell(scanner)
		)
		pax.clear_path()
		for _i in 200:
			_world.step()
			_views.draw()
			if (
				_views.station_pose_mode(officer_id) == StaffStationPose.Mode.SECURITY_SCAN
				and _views.station_pose_weight(officer_id) >= 0.99
			):
				(officer_node.get_node("AnimationPlayer") as AnimationPlayer).speed_scale = 0.0
				await _skeleton_tick(sk)
				var sub := _views.station_pose_sub_mode(officer_id)
				var arm_l_q := (
					sk.get_bone_global_pose(sk.find_bone("Arm.L")).basis.get_rotation_quaternion()
				)
				var head_q := (
					sk.get_bone_global_pose(sk.find_bone("Head")).basis.get_rotation_quaternion()
				)
				recorded[label] = {
					"sub": sub,
					"prop": _views.hand_prop_of(officer_id),
					"arm_l": arm_l_q,
					"head": head_q,
				}
				break
		for _i in 250:
			_world.step()
			_views.draw()
			if pax.stage == Passenger.Stage.TO_GATE:
				break

	assert_int(recorded["alarm"]["sub"]).is_equal(StaffStationPose.SubMode.SEC_ALARM)
	assert_int(recorded["liquids"]["sub"]).is_equal(StaffStationPose.SubMode.SEC_LIQUIDS)
	assert_int(recorded["clean"]["sub"]).is_equal(StaffStationPose.SubMode.SEC_CLEAN)
	assert_int(recorded["alarm"]["prop"]).is_equal(StaffHandProps.PropKind.WAND)
	assert_int(recorded["liquids"]["prop"]).is_equal(StaffHandProps.PropKind.WAND)
	assert_int(recorded["clean"]["prop"]).is_equal(StaffHandProps.PropKind.WAND)
	# Alarm raises Arm.L halt distinctly vs clean; liquids points/shakes vs clean.
	(
		assert_float(
			(recorded["alarm"]["arm_l"] as Quaternion).angle_to(recorded["clean"]["arm_l"])
		)
		. is_greater(0.25)
	)
	(
		assert_float(
			(recorded["liquids"]["arm_l"] as Quaternion).angle_to(recorded["clean"]["arm_l"])
		)
		. is_greater(0.25)
	)


func test_shop_info_desk_cafe_and_retail_split_distinct_sub_modes() -> void:
	# 1. Info desk helping a stuck passenger -> SHOP_INFO_DESK + CLIPBOARD.
	_world = InfoDeskTestLayout.world(true, [StaffMember.Role.SHOP])
	_world.auto_staff = false
	StaffTestKit.staff_all(_world.staff, [StaffMember.Role.SHOP])
	_attach_views(_world)
	var info_sid := _world.staff.member_ids()[0]
	var p_info := InfoDeskTestLayout.guest(_world, Vector2i(6, 11), 50)
	assert_int(p_info.id).is_greater(0)
	for _i in 200:
		_world.step()
		_views.draw()
		if (
			_views.station_pose_mode(info_sid) == StaffStationPose.Mode.SHOP
			and _views.station_pose_weight(info_sid) > 0.5
		):
			break
	assert_int(_views.station_pose_mode(info_sid)).is_equal(StaffStationPose.Mode.SHOP)
	assert_int(_views.station_pose_sub_mode(info_sid)).is_equal(
		StaffStationPose.SubMode.SHOP_INFO_DESK
	)
	assert_int(_views.hand_prop_of(info_sid)).is_equal(StaffHandProps.PropKind.CLIPBOARD)
	_views.free()
	_views = null
	_world.free_all()
	_world = null

	# 2. Cafe counter serving -> SHOP_CAFE.
	var cafe_grid := BuildGrid.new()
	var cafe_ids := CafeTestLayout.build(cafe_grid, false, &"cafe", true)
	_world = PassengerTestWorld.make(cafe_grid, PassengerTestWorld.starts_with(3000, 6000), 23)
	_world.auto_staff = false
	var cafe_sid := StaffTestKit.seat_server(_world.staff, cafe_ids["air_counter"])
	_attach_views(_world)
	var p_cafe := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p_cafe)
	p_cafe.cleared = true
	p_cafe.stage = Passenger.Stage.TO_GATE
	p_cafe.hunger = CafeSim.HUNGRY_AT + 20
	p_cafe.at = Vector2i(19, 6) + ReferenceTerminal.offset_on(cafe_grid)
	p_cafe.clear_path()
	assert_bool(_world.sim.cafes.try_visit(p_cafe)).is_true()
	for _i in 200:
		_world.step()
		_views.draw()
		if _views.station_pose_mode(cafe_sid) == StaffStationPose.Mode.SHOP:
			break
	assert_int(_views.station_pose_mode(cafe_sid)).is_equal(StaffStationPose.Mode.SHOP)
	assert_int(_views.station_pose_sub_mode(cafe_sid)).is_equal(StaffStationPose.SubMode.SHOP_CAFE)
	_views.free()
	_views = null
	_world.free_all()
	_world = null

	# 3. Kiosk counter with active browser -> SHOP_RETAIL + no prop.
	var shop_grid := BuildGrid.new()
	var shop_ids := ShopTestLayout.build(shop_grid, ["air"])
	_world = PassengerTestWorld.make(shop_grid, PassengerTestWorld.starts_with(3000, 6000), 25)
	_world.auto_staff = false
	var retail_sid := StaffTestKit.seat_server(_world.staff, shop_ids["air_counter"])
	_attach_views(_world)
	var p_kiosk := ShopTestLayout.airside_guest(
		_world, 95, ShopTestLayout.AIRSIDE_CELL + ReferenceTerminal.offset_on(shop_grid)
	)
	var plan := _world.sim.shops.plan_visit(p_kiosk)
	assert_bool(plan.is_empty()).is_false()
	_world.sim.shops.commit_visit(p_kiosk, plan)
	for _i in 200:
		_world.step()
		_views.draw()
		if _views.station_pose_mode(retail_sid) == StaffStationPose.Mode.SHOP:
			break
	assert_int(_views.station_pose_mode(retail_sid)).is_equal(StaffStationPose.Mode.SHOP)
	assert_int(_views.station_pose_sub_mode(retail_sid)).is_equal(
		StaffStationPose.SubMode.SHOP_RETAIL
	)
	assert_int(_views.hand_prop_of(retail_sid)).is_equal(StaffHandProps.PropKind.NONE)


func test_idle_staff_fidget_in_beats_and_pause_while_walking_or_tucked() -> void:
	var built := LaneStaffWorld.two_lanes()
	var arch: int = built[1]
	_world = PassengerTestWorld.make(built[0], PassengerTestWorld.starts_with(3000, 6000), 7)
	_world.auto_staff = false
	StaffTestKit.staff_all(_w_staff_check(_world))
	_attach_views(_world)

	var idle_id := _world.staff.hire(StaffMember.Role.CHECKIN)
	_world.step()
	_views.draw()
	# No desks free -> walks out? No, check-in desks may already be staffed -> stays in pool if full.
	# Use a seated officer at a quiet scanner to observe settle -> fidget -> snap reset.
	var officer_id := _world.staff.staff_at(arch)
	assert_int(_views.station_pose_mode(officer_id)).is_equal(StaffStationPose.Mode.NONE)
	assert_float(_views.idle_fidget_weight(officer_id)).is_equal(0.0)

	var saw_fidget := false
	for _i in 350:
		_world.step()
		_views.draw()
		if (
			_views.station_pose_mode(officer_id) == StaffStationPose.Mode.IDLE_FIDGET
			and _views.idle_fidget_weight(officer_id) > 0.5
		):
			saw_fidget = true
			break
	assert_bool(saw_fidget).is_true()
	assert_float(_views.station_pose_weight(officer_id)).is_equal(0.0)
	assert_int(_views.hand_prop_of(officer_id)).is_equal(StaffHandProps.PropKind.NONE)

	# Snap/load resets idle fidgets back to Mode.NONE with 0 weight immediately (6d949060).
	_views.sync(true)
	_views.draw()
	assert_int(_views.station_pose_mode(officer_id)).is_equal(StaffStationPose.Mode.NONE)
	assert_float(_views.idle_fidget_weight(officer_id)).is_equal(0.0)

	# Walking through a security arch pauses/zeros idle fidgets completely.
	var walker_id := LaneStaffWorld.send_through_arch(_world, arch)
	var m := _world.staff.get_member(walker_id)
	_views.sync(true)
	var arch_fidgets := 0
	for _i in 200:
		_world.step()
		_views.draw()
		if m.is_moving() or StaffArchTuck.in_arch_passage(_world.grid, m):
			if _views.station_pose_mode(walker_id) == StaffStationPose.Mode.IDLE_FIDGET:
				arch_fidgets += 1
		if m.state == StaffMember.State.ON_DUTY:
			break
	assert_int(arch_fidgets).is_equal(0)
	assert_int(idle_id).is_greater(0)


func test_variant_cycles_meet_at_neutral_boundary_and_submodes_crossfade_smoothly() -> void:
	var chars := auto_free(StaffCharacters.new()) as StaffCharacters
	add_child(chars)
	var agent := chars._take(StaffMember.Role.GATE)
	var ramp := chars._take(StaffMember.Role.RAMP)
	var bones: Array[String] = [
		"Spine_01", "Spine_02", "Head", "Arm.L", "Forearm.L", "Arm.R", "Forearm.R"
	]

	# 1. All cycled variants meet at a shared neutral pose when env == 0 (no pop across cycle).
	var cases := [
		[
			StaffStationPose.Mode.GATE,
			StaffStationPose.SubMode.NONE,
			StaffStationPose.GATE_CYCLE_SEC
		],
		[
			StaffStationPose.Mode.CHECKIN,
			StaffStationPose.SubMode.NONE,
			StaffStationPose.CHECKIN_CYCLE_SEC
		],
		[
			StaffStationPose.Mode.SECURITY_SCAN,
			StaffStationPose.SubMode.SEC_CLEAN,
			StaffStationPose.SECURITY_CYCLE_SEC
		],
		[
			StaffStationPose.Mode.SECURITY_REPACK,
			StaffStationPose.SubMode.NONE,
			StaffStationPose.REPACK_CYCLE_SEC
		],
		[
			StaffStationPose.Mode.SHOP,
			StaffStationPose.SubMode.SHOP_CAFE,
			StaffStationPose.SHOP_CYCLE_SEC
		],
		[
			StaffStationPose.Mode.SHOP,
			StaffStationPose.SubMode.SHOP_INFO_DESK,
			StaffStationPose.SHOP_CYCLE_SEC
		],
		[
			StaffStationPose.Mode.SHOP,
			StaffStationPose.SubMode.SHOP_RETAIL,
			StaffStationPose.SHOP_CYCLE_SEC
		],
		[StaffStationPose.Mode.RAMP_MARSHAL, StaffStationPose.SubMode.NONE, 3.6],
	]
	var sk_a := _skeleton_of(agent)
	var player_a := agent.get_node("AnimationPlayer") as AnimationPlayer
	player_a.play("idle")
	player_a.seek(0.0, true)
	player_a.speed_scale = 0.0
	for c in cases:
		var m_mode: StaffStationPose.Mode = c[0]
		var m_sub: StaffStationPose.SubMode = c[1]
		var cycle_sec := float(c[2])
		var offset := float(posmod(1, 13)) * 0.43
		var boundary_tick := (cycle_sec * 2.0 - offset) * float(SimClock.TICK_RATE)
		StaffStationPose.pose(agent, m_mode, 1.0, boundary_tick - 0.01, Vector2.ZERO, 1, m_sub)
		await _skeleton_tick(sk_a)
		var before_q := _snapshot_bones(sk_a, bones)
		StaffStationPose.pose(agent, m_mode, 1.0, boundary_tick + 0.01, Vector2.ZERO, 1, m_sub)
		await _skeleton_tick(sk_a)
		var after_q := _snapshot_bones(sk_a, bones)
		assert_float(_max_bone_diff(before_q, after_q)).is_less(0.02)

	# 2. Sub-mode switch RAMP_HOOKUP -> RAMP_GUIDE crossfades over TRANSITION_TICKS and
	# resets cleanly on backward tick (6d949060).
	var sk_r := _skeleton_of(ramp)
	var player_r := ramp.get_node("AnimationPlayer") as AnimationPlayer
	player_r.play("idle")
	player_r.seek(0.0, true)
	player_r.speed_scale = 0.0

	var rec := {}
	(
		StaffStationPose
		. update(
			rec,
			StaffStationPose.Mode.RAMP_PUSHBACK,
			Vector2.ZERO,
			100.0,
			StaffStationPose.SubMode.RAMP_HOOKUP,
			false,
			1,
		)
	)
	(
		StaffStationPose
		. pose(
			ramp,
			StaffStationPose.mode_of(rec),
			StaffStationPose.weight_of(rec, 110.0),
			110.0,
			Vector2.ZERO,
			1,
			StaffStationPose.sub_mode_of(rec),
		)
	)
	await _skeleton_tick(sk_r)
	var hookup_pose := _snapshot_bones(sk_r, bones)

	(
		StaffStationPose
		. pose(
			ramp,
			StaffStationPose.Mode.RAMP_PUSHBACK,
			1.0,
			110.0,
			Vector2.ZERO,
			1,
			StaffStationPose.SubMode.RAMP_GUIDE,
		)
	)
	await _skeleton_tick(sk_r)
	var guide_pose := _snapshot_bones(sk_r, bones)
	assert_float(_max_bone_diff(hookup_pose, guide_pose)).is_greater(0.3)

	(
		StaffStationPose
		. update(
			rec,
			StaffStationPose.Mode.RAMP_PUSHBACK,
			Vector2.ZERO,
			110.0,
			StaffStationPose.SubMode.RAMP_GUIDE,
			false,
			1,
		)
	)
	assert_int(StaffStationPose.xfade_mode_of(rec)).is_equal(StaffStationPose.Mode.RAMP_PUSHBACK)
	assert_int(StaffStationPose.xfade_sub_mode_of(rec)).is_equal(
		StaffStationPose.SubMode.RAMP_HOOKUP
	)

	for sample in [
		[110.0, "start"],
		[113.0, "mid"],
		[110.0 + StaffStationPose.TRANSITION_TICKS, "end"],
	]:
		var t_now := float(sample[0])
		var tag := String(sample[1])
		(
			StaffStationPose
			. pose(
				ramp,
				StaffStationPose.mode_of(rec),
				StaffStationPose.weight_of(rec, t_now) * StaffStationPose.crossfade_in(rec, t_now),
				t_now,
				Vector2.ZERO,
				1,
				StaffStationPose.sub_mode_of(rec),
				0.0,
				StaffStationPose.xfade_mode_of(rec),
				StaffStationPose.xfade_sub_mode_of(rec),
				StaffStationPose.crossfade_out(rec, t_now),
			)
		)
		await _skeleton_tick(sk_r)
		var q_now := _snapshot_bones(sk_r, bones)
		if tag == "start":
			assert_float(_max_bone_diff(q_now, hookup_pose)).is_less(0.01)
		elif tag == "mid":
			assert_float(_max_bone_diff(q_now, hookup_pose)).is_greater(0.1)
			assert_float(_max_bone_diff(q_now, guide_pose)).is_greater(0.1)
		else:
			(
				StaffStationPose
				. pose(
					ramp,
					StaffStationPose.Mode.RAMP_PUSHBACK,
					1.0,
					t_now,
					Vector2.ZERO,
					1,
					StaffStationPose.SubMode.RAMP_GUIDE,
				)
			)
			await _skeleton_tick(sk_r)
			var guide_end := _snapshot_bones(sk_r, bones)
			assert_float(_max_bone_diff(q_now, guide_end)).is_less(0.01)

	# Backward tick clears crossfade state immediately without stale blend.
	assert_float(StaffStationPose.crossfade_in(rec, 105.0)).is_equal(1.0)
	assert_float(StaffStationPose.crossfade_out(rec, 105.0)).is_equal(0.0)
	(
		StaffStationPose
		. update(
			rec,
			StaffStationPose.Mode.RAMP_PUSHBACK,
			Vector2.ZERO,
			105.0,
			StaffStationPose.SubMode.RAMP_GUIDE,
			false,
			1,
		)
	)
	assert_bool(rec.has("xfade_since")).is_false()


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


func _w_staff_check(world: PassengerTestWorld) -> StaffSim:
	return world.staff
