class_name TestCafeChairs
extends GdUnitTestSuite
## A cafe guest is drawn on its chair by the view (CafeChairs): the sim keeps
## the seat's root, and the view adds the body's own step towards the table and
## up (PassengerLooks.CAFE_SEAT_SHIFT_M), blended in over the shuffle from the
## approach cell, so the guest starts at the chair front where SitHold holds a
## roller sitter.

var _world: PassengerTestWorld
var _views: PassengerViews


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := BuildGrid.new()
	CafeTestLayout.build(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)


func after_test() -> void:
	_views.free()
	_world.free_all()


func _guest() -> Passenger:
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.hunger = 0
	p.cafe_cooldown = 1000000
	while p.stage != Passenger.Stage.TO_GATE and _world.clock.tick < 900:
		_world.step()
	assert_bool(_world.sim.cafes.try_visit(p)).is_true()
	return p


func _run_to_stage(p: Passenger, stage: Passenger.Stage) -> void:
	while p.stage != stage and _world.clock.tick < 1400:
		_world.step()
	assert_int(p.stage).is_equal(stage)


## The body's whole step at `seat`: towards the table along the seat's facing,
## and up.
func _step(p: Passenger, seat: Dictionary) -> Vector3:
	var shift := PassengerLooks.CAFE_SEAT_SHIFT_M[PassengerLooks.body_of(p.id, p.variant)]
	var facing: Vector2i = seat["facing"]
	return Vector3(facing.x, 0.0, facing.y) * shift.x + Vector3.UP * shift.y


func test_a_seated_guest_is_drawn_its_body_s_step_towards_the_table() -> void:
	var p := _guest()
	var seat := _world.sim.cafes.visit_of(p.id).seat
	_run_to_stage(p, Passenger.Stage.CAFE_SEATED)
	var root := BuildObjectDef.seat_root_world(_world.grid, seat)
	var table := _world.grid.cell_to_world(seat["cell"] + (seat["facing"] as Vector2i))
	var own := p.variant
	# Male and female bodies in turn: each is drawn with its own step.
	for variant in 2:
		p.variant = variant
		var drawn := _views.draw_position(p)
		var step := _step(p, seat)
		print("variant %d root %s drawn %s step %s" % [variant, root, drawn, step])
		# The sim keeps the seat's root; only the drawing moves.
		assert_float(_world.sim.world_position(p).distance_to(root)).is_less(0.001)
		assert_vector(drawn - root).is_equal_approx(step, Vector3.ONE * 0.001)
		# Towards the table, never away from it.
		var flat := Vector2(drawn.x, drawn.z)
		var root_flat := Vector2(root.x, root.z)
		var table_flat := Vector2(table.x, table.z)
		assert_float(flat.distance_to(table_flat)).is_less(root_flat.distance_to(table_flat))
	p.variant = own


func test_the_step_blends_in_from_the_chair_front_and_out_again() -> void:
	var p := _guest()
	var seat := _world.sim.cafes.visit_of(p.id).seat
	_run_to_stage(p, Passenger.Stage.CAFE_SITTING_DOWN)
	var approach := _world.grid.cell_to_world(seat["approach"])
	var step := _step(p, seat)
	var tick := _world.sim.tick
	# The first tick of the sit-down: at the chair front with no step, where
	# SitHold.chair_front() holds a roller sitter.
	p.stage_tick = tick
	assert_vector(CafeChairs.offset(_world.sim, p)).is_equal_approx(
		Vector3.ZERO, Vector3.ONE * 0.001
	)
	assert_vector(_views.draw_position(p)).is_equal_approx(approach, Vector3.ONE * 0.001)
	# Half way through the shuffle: half the step.
	p.stage_tick = tick - CafeSim.SHUFFLE_TICKS / 2
	var half := CafeChairs.offset(_world.sim, p)
	print("half %s step %s" % [half, step])
	assert_vector(half).is_equal_approx(step * 0.5, Vector3.ONE * 0.001)
	# Shuffle done: the whole step.
	p.stage_tick = tick - CafeSim.SHUFFLE_TICKS
	assert_vector(CafeChairs.offset(_world.sim, p)).is_equal_approx(step, Vector3.ONE * 0.001)
	# The last tick of the stand-up: back at the chair front with no step.
	p.stage = Passenger.Stage.CAFE_STANDING_UP
	p.stage_tick = tick - PassengerSim.STAND_UP_TICKS
	assert_vector(CafeChairs.offset(_world.sim, p)).is_equal_approx(
		Vector3.ZERO, Vector3.ONE * 0.001
	)
	assert_vector(_views.draw_position(p)).is_equal_approx(approach, Vector3.ONE * 0.001)


## A restaurant guest at the dining table or the booth is drawn with that
## piece's own step (PassengerLooks.seat_shift(), board 3405a04b), not the cafe
## chair's: the cafe step put the forearms into the dining table top.
func test_a_restaurant_guest_takes_the_dining_piece_s_own_step() -> void:
	for table: StringName in [&"restaurant_table", &"restaurant_booth"]:
		_views.free()
		_world.free_all()
		var grid := BuildGrid.new()
		CafeTestLayout.build(grid, false, &"restaurant", true, &"cafe_counter", table)
		_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
		_views = PassengerTestWorld.views()
		_views.clock = _world.clock
		_views.sim = _world.sim
		add_child(_views)
		var p := _guest()
		var visit := _world.sim.cafes.visit_of(p.id)
		_run_to_stage(p, Passenger.Stage.CAFE_SEATED)
		assert_str(String(visit.piece.get("def", &""))).is_equal(String(table))
		var root := BuildObjectDef.seat_root_world(_world.grid, visit.seat)
		var facing: Vector2i = visit.seat["facing"]
		var ahead := Vector3(facing.x, 0.0, facing.y)
		var own := p.variant
		for variant in 2:
			p.variant = variant
			var body := PassengerLooks.body_of(p.id, p.variant)
			var shift := PassengerLooks.seat_shift(table, body)
			var cafe := PassengerLooks.CAFE_SEAT_SHIFT_M[body]
			var drawn := _views.draw_position(p) - root
			print(
				(
					"%s body %d drawn step %s, piece step %s, cafe step %s"
					% [table, body, drawn, shift, cafe]
				)
			)
			assert_vector(drawn).is_equal_approx(
				ahead * shift.x + Vector3.UP * shift.y, Vector3.ONE * 0.001
			)
			# The control: the cafe chair's step is further towards the table.
			assert_float(drawn.dot(ahead)).is_less(cafe.x - 0.05)
		p.variant = own


func test_no_step_away_from_a_cafe_seat() -> void:
	var p := _guest()
	_run_to_stage(p, Passenger.Stage.CAFE_ORDER)
	assert_vector(CafeChairs.offset(_world.sim, p)).is_equal(Vector3.ZERO)
	var walker := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	_world.step()
	assert_vector(CafeChairs.offset(_world.sim, walker)).is_equal(Vector3.ZERO)


func test_dining_pose_applies_by_piece_during_seated_stage_and_clears_on_exit() -> void:
	assert_int(DiningPose.kind_for(&"cafe_table")).is_equal(DiningPose.Kind.TABLE)
	assert_int(DiningPose.kind_for(&"restaurant_table")).is_equal(DiningPose.Kind.TABLE)
	assert_int(DiningPose.kind_for(&"restaurant_booth")).is_equal(DiningPose.Kind.BOOTH)
	assert_int(DiningPose.kind_for(&"bar_counter")).is_equal(DiningPose.Kind.BAR)
	assert_int(DiningPose.kind_for(&"lounge_sofa")).is_equal(DiningPose.Kind.NONE)
	var cases := [
		[&"restaurant", true, &"cafe_counter", &"restaurant_table", DiningPose.Kind.TABLE],
		[&"restaurant", true, &"cafe_counter", &"restaurant_booth", DiningPose.Kind.BOOTH],
		[&"bar", false, &"bar_counter", &"cafe_table", DiningPose.Kind.BAR],
	]
	for spec: Array in cases:
		for variant in 2:
			_views.free()
			_world.free_all()
			var grid := BuildGrid.new()
			CafeTestLayout.build(grid, false, spec[0], spec[1], spec[2], spec[3])
			_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
			_views = PassengerTestWorld.views()
			_views.clock = _world.clock
			_views.sim = _world.sim
			add_child(_views)
			var p := _guest()
			p.variant = variant
			var expected_kind: DiningPose.Kind = spec[4]
			_run_to_stage(p, Passenger.Stage.CAFE_SITTING_DOWN)
			var node := _views.node_for(p.id)
			assert_bool(node.has_meta(&"dining_pose")).is_false()
			_run_to_stage(p, Passenger.Stage.CAFE_SEATED)
			_world.run_to(_world.clock.tick + DiningPose.EASE_TICKS)
			var pose: DiningPose = (
				node.get_meta(&"dining_pose") if node.has_meta(&"dining_pose") else null
			)
			assert_object(pose).is_not_null()
			assert_int(pose.kind).is_equal(expected_kind)
			assert_float(pose.amount).is_equal_approx(1.0, 0.001)
			var skeleton := node.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
			var player := node.get_node("AnimationPlayer") as AnimationPlayer
			var prev_speed := player.speed_scale
			player.speed_scale = 0.0
			var hand_l := skeleton.find_bone("Hand.L")
			var hand_r := skeleton.find_bone("Hand.R")
			var head_i := skeleton.find_bone("Head")
			var foot_l := skeleton.find_bone("Foot.L")
			pose.kind = DiningPose.Kind.NONE
			await _skeleton_tick(skeleton)
			var rest_hl := skeleton.get_bone_global_pose(hand_l).origin
			var rest_hr := skeleton.get_bone_global_pose(hand_r).origin
			var rest_head := skeleton.get_bone_global_pose(head_i).origin
			var rest_fl := skeleton.get_bone_global_pose(foot_l).origin
			pose.kind = expected_kind
			await _skeleton_tick(skeleton)
			var pose_hl := skeleton.get_bone_global_pose(hand_l).origin
			var pose_hr := skeleton.get_bone_global_pose(hand_r).origin
			var pose_head := skeleton.get_bone_global_pose(head_i).origin
			var pose_fl := skeleton.get_bone_global_pose(foot_l).origin
			player.speed_scale = prev_speed
			print(
				(
					"%s var=%d handL y=%.3f->%.3f z=%.3f->%.3f head z=%.3f->%.3f foot z=%.3f->%.3f"
					% [
						spec[2] if not spec[1] else spec[3],
						variant,
						rest_hl.y,
						pose_hl.y,
						rest_hl.z,
						pose_hl.z,
						rest_head.z,
						pose_head.z,
						rest_fl.z,
						pose_fl.z,
					]
				)
			)
			assert_float(pose_hl.y).is_greater(rest_hl.y + 0.04)
			assert_float(pose_hl.z).is_greater(rest_hl.z + 0.04)
			assert_float(pose_hr.y).is_greater(rest_hr.y + 0.04)
			assert_float(pose_hr.z).is_greater(rest_hr.z + 0.04)
			assert_float(pose_head.z).is_greater(rest_head.z + 0.015)
			if expected_kind == DiningPose.Kind.BAR:
				assert_float(pose_fl.z).is_less(rest_fl.z - 0.05)
			else:
				assert_float(pose_fl.z).is_equal_approx(rest_fl.z, 0.005)
			_run_to_stage(p, Passenger.Stage.CAFE_STANDING_UP)
			await get_tree().process_frame
			assert_bool(node.has_meta(&"dining_pose")).is_false()


func _skeleton_tick(skeleton: Skeleton3D) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await skeleton.skeleton_updated
