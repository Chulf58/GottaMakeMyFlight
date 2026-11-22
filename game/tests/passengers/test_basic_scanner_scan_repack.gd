class_name TestBasicScannerScanRepack
extends GdUnitTestSuite
## Basic security_scanner scan-hold and passenger RepackPose (board 1c4d3156,
## ruling staff-station-interaction-poses-and-basic-scanner-scan-repac):
## 1. During Phase.SCAN, the drawn body pauses inside the booth rather than
##    walking past EXIT early and idling outside, then steps smoothly to EXIT
##    over BASIC_EXIT_WALK_TICKS as Phase.SCAN completes.
## 2. During Phase.REPACK, RepackPose bends torso and arms into a visible
##    repack motion and clears back to 0 before pickup / exit.
## 3. A snap() / load mid-SCAN draws at the booth centre at once, and a snap()
##    or pool release mid-REPACK leaves zero residual modifier weight.

var _world: SecurityTestWorld
var _views: PassengerViews


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _views != null:
		_views.free()
		_views = null
	if _world != null:
		_world.world.free_all()
		_world = null


func _setup() -> void:
	_world = SecurityTestWorld.make(false, 7)
	_views = PassengerTestWorld.views()
	_views.clock = _world.world.clock
	_views.sim = _world.world.sim
	add_child(_views)


func test_basic_scanner_holds_scan_in_booth_for_walking_and_late_passengers() -> void:
	for late in [false, true]:
		for bags in [0, 2]:
			after_test()
			_setup()
			var id := _world.send(bags, false, false)
			var p := _world.world.passenger(id)
			p.late = late
			var sim := _world.world.sim
			var passage: Array = sim.layout.passages[w_station()]
			var booth_centre := (
				(sim.grid.cell_to_world(passage[1]) + sim.grid.cell_to_world(passage[2])) * 0.5
			)
			var exit_world := sim.grid.cell_to_world(passage[3])

			var held_in_booth := 0
			var tucked_at_exit_cell := 0
			var released_before_exit := 0
			var last_scan_pos := Vector3.ZERO
			var idle_past_exit_ticks := 0
			var guard := 0
			while not _world.cleared.has(id) and guard < 1500:
				if late:
					p.late = true
				_world.world.step()
				_views.draw()
				if (
					p.stage == Passenger.Stage.SECURITY
					and p.security_phase == SecurityRuntime.Phase.SCAN
				):
					last_scan_pos = _views.tick_position(id, true)
					if p.security_work > SecurityLooks.BASIC_EXIT_WALK_TICKS:
						if last_scan_pos.distance_to(booth_centre) < 0.05:
							held_in_booth += 1
						if SecurityLooks.in_booth_passage(sim, p):
							tucked_at_exit_cell += 1
					if (
						not p.is_moving()
						and not SecurityLooks.in_booth(
							sim.grid, sim.grid.world_to_cell(last_scan_pos)
						)
						and not SecurityLooks.in_booth_passage(sim, p)
					):
						released_before_exit += 1
					if not p.is_moving() and last_scan_pos.distance_to(exit_world) < 0.05:
						if p.security_work > 1:
							idle_past_exit_ticks += 1
				guard += 1

			assert_bool(_world.cleared.has(id)).is_true()
			var scan_ticks: int = _world.cleared[id] - _world.admitted[id]
			assert_int(scan_ticks).is_equal(SecurityRuntime.work_for(SecurityRuntime.Phase.SCAN, p))
			print(
				(
					"late=%s bags=%d: held_in_booth=%d tucked=%d released=%d idle_past_exit=%d last_dist_exit=%.3f"
					% [
						late,
						bags,
						held_in_booth,
						tucked_at_exit_cell,
						released_before_exit,
						idle_past_exit_ticks,
						last_scan_pos.distance_to(exit_world),
					]
				)
			)
			assert_int(held_in_booth).is_greater(5)
			assert_int(tucked_at_exit_cell).is_greater(5)
			assert_int(released_before_exit).is_greater_equal(5)
			assert_int(idle_past_exit_ticks).is_equal(0)
			assert_float(last_scan_pos.distance_to(exit_world)).is_less(0.05)


func w_station() -> int:
	return _world.station


func _skeleton_tick(skeleton: Skeleton3D) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await skeleton.skeleton_updated


func test_repack_pose_activates_mid_repack_and_clears_before_pickup() -> void:
	_setup()
	var id := _world.send(1, false, true)
	var p := _world.world.passenger(id)
	var bones: Array[String] = ["Spine_01", "Arm.L", "Arm.R"]

	while p.security_phase != SecurityRuntime.Phase.REPACK and _world.world.clock.tick < 1500:
		_world.world.step()
		_views.draw()
	assert_int(p.security_phase).is_equal(SecurityRuntime.Phase.REPACK)

	var body := _views.node_for(id)
	var player := body.get_node("AnimationPlayer") as AnimationPlayer
	var sk := body.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var max_weight := 0.0
	var max_delta := 0.0
	var end_weight := -1.0
	while p.security_phase == SecurityRuntime.Phase.REPACK and _world.world.clock.tick < 1500:
		_world.world.step()
		_views.draw()
		var w := RepackPose.weight_for(p)
		max_weight = maxf(max_weight, w)
		if p.security_work == 40:
			_world.world.clock.set_paused(true)
			_views.draw()
			var prev_speed := player.speed_scale
			player.speed_scale = 0.0
			var mod: RepackPose = body.get_meta(&"repack_pose")
			mod.active = false
			await _skeleton_tick(sk)
			var base := {}
			for bone in bones:
				base[bone] = (
					sk.get_bone_global_pose(sk.find_bone(bone)).basis.get_rotation_quaternion()
				)
			mod.active = true
			await _skeleton_tick(sk)
			for bone in bones:
				var q := sk.get_bone_global_pose(sk.find_bone(bone)).basis.get_rotation_quaternion()
				max_delta = maxf(max_delta, (base[bone] as Quaternion).angle_to(q))
			player.speed_scale = prev_speed
			_world.world.clock.set_paused(false)
		if p.security_work <= 4:
			end_weight = w

	print(
		(
			"repack pose: max_weight=%.2f max_delta=%.3f rad end_weight=%.2f"
			% [max_weight, max_delta, end_weight]
		)
	)
	assert_float(max_weight).is_equal(1.0)
	assert_float(max_delta).is_greater(0.15)
	assert_float(end_weight).is_equal(0.0)
	var mod: RepackPose = body.get_meta(&"repack_pose")
	assert_bool(mod.active).is_false()
	assert_float(mod.amount).is_equal(0.0)


func test_snap_mid_scan_and_mid_repack_resets_cleanly() -> void:
	_setup()
	var id := _world.send(2, false, true)
	var p := _world.world.passenger(id)
	var sim := _world.world.sim
	var passage: Array = sim.layout.passages[_world.station]
	var booth_centre := (
		(sim.grid.cell_to_world(passage[1]) + sim.grid.cell_to_world(passage[2])) * 0.5
	)

	var dir := Vector2(passage[passage.size() - 1] - passage[0])
	var expected_yaw := atan2(dir.x, dir.y)
	assert_float(absf(expected_yaw)).is_greater(0.5)

	# Step until sim reached EXIT cell while SCAN work still pauses in booth.
	while (
		not (
			p.security_phase == SecurityRuntime.Phase.SCAN
			and p.at == passage[3]
			and p.security_work > SecurityLooks.BASIC_EXIT_WALK_TICKS
		)
		and _world.world.clock.tick < 1500
	):
		_world.world.step()
		_views.draw()
	assert_int(p.security_phase).is_equal(SecurityRuntime.Phase.SCAN)
	var body := _views.node_for(id)
	body.rotation.y = 0.0
	_views.snap()
	assert_float(body.position.distance_to(booth_centre)).is_less(0.05)
	assert_float(absf(angle_difference(body.rotation.y, expected_yaw))).is_less(0.01)

	# Step into mid-REPACK, verify modifier active and snap preserves heading, then release.
	while (
		not (p.security_phase == SecurityRuntime.Phase.REPACK and p.security_work == 40)
		and _world.world.clock.tick < 1500
	):
		_world.world.step()
		_views.draw()
	assert_float(RepackPose.weight_for(p)).is_equal(1.0)
	body.rotation.y = 0.0
	_views.snap()
	assert_float(absf(angle_difference(body.rotation.y, expected_yaw))).is_less(0.01)
	var mod: RepackPose = body.get_meta(&"repack_pose")
	assert_bool(mod.active).is_true()

	p.stage = Passenger.Stage.MADE
	_views.snap()
	assert_object(_views.node_for(id)).is_null()
	assert_bool(body.visible).is_false()
	assert_bool(mod.active).is_false()
	assert_float(mod.amount).is_equal(0.0)
