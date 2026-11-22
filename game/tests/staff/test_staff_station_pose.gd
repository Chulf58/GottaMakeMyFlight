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

	# Idle before any passenger arrives: zero weight and zero modifier activity.
	await get_tree().process_frame
	for sid in _world.staff.member_ids():
		assert_float(_views.station_pose_weight(sid)).is_equal(0.0)
		assert_int(_views.station_pose_mode(sid)).is_equal(StaffStationPose.Mode.NONE)
		var node := _views.node_for(sid)
		assert_bool(node.has_meta(&"station_pose")).is_false()

	var pid := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var pax := _world.passenger(pid)
	ToiletTestLayout.calm(pax)
	pax.cafe_cooldown = 1000000
	pax.hunger = 0
	pax.carry_on = 1
	pax.liquids = false
	pax.alarm = true

	var bones: Array[String] = ["Head", "Arm.R", "Forearm.R"]
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

	# After serving ends, every used station returns cleanly to rest (0 weight, 0 residual).
	_world.clock.set_paused(true)
	_views.draw()
	for key in used_ids:
		var sid: int = used_ids[key]
		assert_float(_views.station_pose_weight(sid)).is_equal(0.0)
		var node := _views.node_for(sid)
		var mod: StaffStationPose = node.get_meta(&"station_pose")
		assert_bool(mod.active).is_false()
		assert_float(mod.weight).is_equal(0.0)
		var rest := await _capture_idle_baseline(node, bones)
		assert_float(await _pose_delta_from_rest(node, bones, rest)).is_less(0.001)


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
