class_name TestStallDoors
extends GdUnitTestSuite
## Stateless outward bi-fold door animation for toilet_stall (StallDoors,
## board ac734ad8): doors stay closed while unoccupied and during SITTING_DOWN /
## USE / early STANDING_UP, open over the last 0.55 m of TOILET_WALK, stay open
## through TOILET_ENTER 0..9 then close 9..12, open across STANDING_UP 20..24
## without ever sweeping inward into floor bags (z_min >= 0.875 > 0.861 m), stay
## open across TOILET_EXIT 0..10 (covering the k = 0..1 bag pick-up) then close
## 10..12, stack compactly outward (z_max <= 1.115 m, clear doorway >= 0.81 m),
## handle relocation / removal cleanly, and draw deterministically on load.

const MOVED_ANCHOR := Vector2i(25, 10)
const EPS := 1e-4

var _base_grid: BuildGrid
var _base_ids: Dictionary = {}
var _world: PassengerTestWorld
var _build_view: BuildView
var _views: PassengerViews
var _ids: Dictionary = {}


func before() -> void:
	PassengerTestWorld.tracker = self
	_base_grid = BuildGrid.new()
	_base_ids = ToiletTestLayout.build(_base_grid, 1)


func after() -> void:
	_teardown_world()
	_base_grid = null
	_base_ids = {}
	PassengerTestWorld.tracker = null


func after_test() -> void:
	_teardown_world()


func _teardown_world() -> void:
	if _views != null:
		_views.free()
		_views = null
	if _build_view != null:
		_build_view.free()
		_build_view = null
	if _world != null:
		_world.free_all()
		_world = null
	_ids = {}


func _setup_world(seed_val := 1) -> void:
	_teardown_world()
	var grid := _base_grid.clone()
	_ids = _base_ids.duplicate(true)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), seed_val)
	_build_view = BuildView.new()
	add_child(_build_view)
	_build_view.refresh(grid)
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	_views.build_view = _build_view
	add_child(_views)
	_world.run_to(10)


func _stall_id() -> int:
	return int(_ids["land_stalls"][0])


func _spawn_visitor(carry_count := 1) -> Passenger:
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	p.carry_on = carry_count
	p.liquids = false
	p.alarm = false
	p.stage = Passenger.Stage.TO_SECURITY
	p.stage_tick = _world.clock.tick
	p.at = Vector2i(20, 14) + ReferenceTerminal.offset_on(_world.grid)
	p.clear_path()
	p.toilet_need = 90
	assert_bool(_world.sim.toilets.try_visit(p)).is_true()
	return p


func _step_to_stage(p: Passenger, stage: Passenger.Stage, max_steps := 1500) -> void:
	var limit := _world.clock.tick + max_steps
	while p.stage != stage and _world.clock.tick < limit:
		_world.step()
	assert_int(p.stage).is_equal(stage)


func _door_angles(stall_node: Node3D) -> Vector4:
	var left := stall_node.find_child(StallDoors.LEAF_LEFT, true, false) as Node3D
	var right := stall_node.find_child(StallDoors.LEAF_RIGHT, true, false) as Node3D
	var fold_l := stall_node.find_child(StallDoors.FOLD_LEFT, true, false) as Node3D
	var fold_r := stall_node.find_child(StallDoors.FOLD_RIGHT, true, false) as Node3D
	return Vector4(left.rotation.y, right.rotation.y, fold_l.rotation.y, fold_r.rotation.y)


func _part_bounds_in_stall(
	stall_node: Node3D, part_name: String, recursive := true, z_band := Vector2(-INF, INF)
) -> AABB:
	var part := stall_node.find_child(part_name, true, false) as Node3D
	assert_object(part).is_not_null()
	var box := AABB()
	var has_point := false
	for mesh_inst: MeshInstance3D in part.find_children("*", "MeshInstance3D", recursive, false):
		var rel := Transform3D.IDENTITY
		var cur: Node = mesh_inst
		while cur != null and cur != stall_node:
			rel = (cur as Node3D).transform * rel
			cur = cur.get_parent()
		for v: Vector3 in mesh_inst.mesh.get_faces():
			var pt := rel * v
			if pt.z < z_band.x or pt.z > z_band.y:
				continue
			if not has_point:
				box = AABB(pt, Vector3.ZERO)
				has_point = true
			else:
				box = box.expand(pt)
	assert_bool(has_point).is_true()
	return box


func test_unoccupied_and_non_door_phases_keep_doors_closed() -> void:
	_setup_world()
	var sid := _stall_id()
	assert_float(StallDoors.open_weight(null, sid, 0.5)).is_equal(0.0)
	assert_float(StallDoors.open_weight(_world.sim, 0, 0.5)).is_equal(0.0)
	assert_float(StallDoors.open_weight(_world.sim, sid, 0.0)).is_equal(0.0)
	# L5: sim with null toilets / grid stays null-safe.
	var bare_sim := auto_free(PassengerSim.new()) as PassengerSim
	bare_sim.toilets = null
	assert_float(StallDoors.open_weight(bare_sim, sid, 0.5)).is_equal(0.0)
	(
		assert_float(
			StallDoors.ghost_open_weight(bare_sim, {"id": sid, "def": &"toilet_stall"}, 0.5)
		)
		. is_equal(0.0)
	)
	var p := _spawn_visitor(0)
	assert_int(p.stage).is_equal(Passenger.Stage.TOILET_WALK)
	assert_int(p.remaining_mm()).is_greater(1000)
	assert_float(StallDoors.open_weight(_world.sim, sid, 0.5)).is_equal(0.0)
	_step_to_stage(p, Passenger.Stage.TOILET_SITTING_DOWN)
	for tick_in_sit in [0, 12, 23]:
		p.stage_tick = _world.sim.tick - tick_in_sit
		assert_float(StallDoors.open_weight(_world.sim, sid, 0.5)).is_equal(0.0)
	_step_to_stage(p, Passenger.Stage.TOILET_USE)
	for tick_in_use in [0, 50, 99]:
		p.stage_tick = _world.sim.tick - tick_in_use
		assert_float(StallDoors.open_weight(_world.sim, sid, 0.5)).is_equal(0.0)
	_step_to_stage(p, Passenger.Stage.TOILET_STANDING_UP)
	assert_float(StallDoors.open_weight(_world.sim, sid, 0.0)).is_equal(0.0)
	p.stage_tick = _world.sim.tick - 19
	assert_float(StallDoors.open_weight(_world.sim, sid, 1.0)).is_equal(0.0)
	p.stage_tick = _world.sim.tick - 20
	assert_float(StallDoors.open_weight(_world.sim, sid, 0.0)).is_equal(0.0)


func test_walk_approach_ramps_smoothly_over_last_550mm() -> void:
	_setup_world()
	var sid := _stall_id()
	var p := _spawn_visitor(0)
	var visit := _world.sim.toilets.visit_of(p.id)
	var approach: Vector2i = visit.stall["approach"]
	var prev_cell := approach + Vector2i(0, 1)
	p.at = prev_cell
	p.set_path([prev_cell, approach])
	p.seg_mm = 450
	assert_int(p.remaining_mm()).is_equal(550)
	assert_float(StallDoors.open_weight(_world.sim, sid, 0.0)).is_equal_approx(0.0, EPS)
	# Sub-tick alpha interpolates remaining walk (570 - 0.5 * 98 = 521 mm < 550 mm).
	p.seg_mm = 430
	assert_float(StallDoors.open_weight(_world.sim, sid, 0.0)).is_equal_approx(0.0, EPS)
	var w_alpha := StallDoors.open_weight(_world.sim, sid, 0.5)
	assert_float(w_alpha).is_greater(0.0)
	p.seg_mm = 600
	var w_400 := StallDoors.open_weight(_world.sim, sid, 0.0)
	p.seg_mm = 725
	var w_275 := StallDoors.open_weight(_world.sim, sid, 0.0)
	p.seg_mm = 900
	var w_100 := StallDoors.open_weight(_world.sim, sid, 0.0)
	assert_float(w_400).is_greater(0.0)
	assert_float(w_275).is_equal_approx(0.5, EPS)
	assert_float(w_100).is_greater(w_275)
	assert_float(w_100).is_less(1.0)
	# Arrived on approach cell waiting 1 tick for TOILET_ENTER: strictly 1.0.
	p.at = approach
	p.clear_path()
	assert_float(StallDoors.open_weight(_world.sim, sid, 0.0)).is_equal(1.0)
	# Unrouted walker off approach (e.g. relocation hand-over tick) stays 0.0.
	p.at = prev_cell
	p.clear_path()
	assert_float(StallDoors.open_weight(_world.sim, sid, 0.5)).is_equal(0.0)


func test_enter_standing_up_and_exit_ramps_cover_bag_pickup() -> void:
	_setup_world()
	var sid := _stall_id()
	var stall_node := _build_view.object_node(sid)
	var p := _spawn_visitor(1)
	_step_to_stage(p, Passenger.Stage.TOILET_ENTER)
	for spent in range(0, 9):
		assert_float(StallDoors.open_weight(_world.sim, sid, 0.5)).is_equal(1.0)
		_world.step()
	# spent == 9: 1.0 at alpha 0, 0.5 at 10.5, 0.0 at 12.0.
	assert_float(StallDoors.open_weight(_world.sim, sid, 0.0)).is_equal_approx(1.0, EPS)
	_world.step()
	assert_float(StallDoors.open_weight(_world.sim, sid, 0.5)).is_equal_approx(0.5, EPS)
	_world.step()
	assert_float(StallDoors.open_weight(_world.sim, sid, 1.0)).is_equal_approx(0.0, EPS)
	_step_to_stage(p, Passenger.Stage.TOILET_STANDING_UP)
	for i in 20:
		_world.step()
	assert_float(StallDoors.open_weight(_world.sim, sid, 0.0)).is_equal_approx(0.0, EPS)
	_world.step()
	_world.step()
	assert_float(StallDoors.open_weight(_world.sim, sid, 0.0)).is_equal_approx(0.5, EPS)
	_world.step()
	assert_float(StallDoors.open_weight(_world.sim, sid, 1.0)).is_equal_approx(1.0, EPS)
	# Draw once while the bag is still on Home.FLOOR so TOILET_EXIT stamps FLOOR->HAND.
	var props := _views.carry_on_props()
	_views.draw()
	props._unposed()
	# Step into TOILET_EXIT tick 0: bag pick-up k runs 0..1 across ticks 0..6,
	# and doors stay strictly 1.0 across ticks 0..10 before closing on 10..12.
	_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.TOILET_EXIT)
	var mid_pickup_samples := 0
	var settled_samples := 0
	while p.stage == Passenger.Stage.TOILET_EXIT and _world.sim.tick - p.stage_tick <= 9:
		var spent_exit := _world.sim.tick - p.stage_tick
		for sub in [0.0, 0.5]:
			_world.clock._accumulator = sub * SimClock.STEP
			_views.draw()
			props._unposed()
			var k := props.transfer_progress(p.id, 0)
			if spent_exit < 6 and sub > 0.0:
				mid_pickup_samples += 1
				assert_float(k).is_greater(0.0)
				assert_float(k).is_less(1.0)
			elif spent_exit >= 6:
				settled_samples += 1
				assert_float(k).is_equal_approx(1.0, EPS)
			assert_float(StallDoors.open_weight(_world.sim, sid, sub)).is_equal(1.0)
			var angles := _door_angles(stall_node)
			assert_float(angles.x).is_equal_approx(-StallDoors.OPEN_RAD, EPS)
			assert_float(angles.y).is_equal_approx(StallDoors.OPEN_RAD, EPS)
			assert_float(angles.z).is_equal_approx(StallDoors.FOLD_RAD, EPS)
			assert_float(angles.w).is_equal_approx(-StallDoors.FOLD_RAD, EPS)
		_world.clock._accumulator = 0.0
		_world.step()
	assert_int(mid_pickup_samples).is_equal(6)
	assert_int(settled_samples).is_greater(0)
	# spent == 10 -> closes 1.0 -> 0.0 over 10..12, then releases cleanly to 0.0.
	assert_float(StallDoors.open_weight(_world.sim, sid, 0.0)).is_equal_approx(1.0, EPS)
	_world.step()
	assert_float(StallDoors.open_weight(_world.sim, sid, 0.0)).is_equal_approx(0.5, EPS)
	assert_float(StallDoors.open_weight(_world.sim, sid, 1.0)).is_equal_approx(0.0, EPS)
	_world.step()
	assert_int(_world.sim.toilets.stall_holder(sid)).is_equal(0)
	_views.draw()
	assert_float(_door_angles(stall_node).length()).is_less(EPS)


func test_deadline_cut_short_and_turn_back_continuity() -> void:
	_setup_world()
	var sid := _stall_id()
	var p := _spawn_visitor(1)
	_step_to_stage(p, Passenger.Stage.TOILET_USE)
	var visit := _world.sim.toilets.visit_of(p.id)
	visit.resume_stage = Passenger.Stage.TO_GATE
	visit.deadline = _world.sim.tick
	_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.TOILET_STANDING_UP)
	_step_to_stage(p, Passenger.Stage.TOILET_EXIT)
	assert_float(StallDoors.open_weight(_world.sim, sid, 0.0)).is_equal(1.0)
	# Cut-short mid-SITTING_DOWN (_turn_back into STANDING_UP): derive expected
	# weight from constants rather than a hardcoded literal, then reach 1.0 at EXIT.
	_setup_world(2)
	var sid2 := _stall_id()
	var p2 := _spawn_visitor(1)
	_step_to_stage(p2, Passenger.Stage.TOILET_SITTING_DOWN)
	_world.step()
	_world.step()
	var visit2 := _world.sim.toilets.visit_of(p2.id)
	visit2.resume_stage = Passenger.Stage.TO_GATE
	visit2.deadline = _world.sim.tick
	_world.step()
	assert_int(p2.stage).is_equal(Passenger.Stage.TOILET_STANDING_UP)
	var stand_elapsed := float(_world.sim.tick - p2.stage_tick)
	var span := float(PassengerSim.STAND_UP_TICKS) - StallDoors.STAND_OPEN_START
	var want_w := smoothstep(
		0.0, 1.0, clampf((stand_elapsed - StallDoors.STAND_OPEN_START) / span, 0.0, 1.0)
	)
	var got_w := StallDoors.open_weight(_world.sim, sid2, 0.0)
	assert_float(got_w).is_equal_approx(want_w, EPS)
	assert_float(StallDoors.open_weight(_world.sim, sid2, 0.5)).is_greater(got_w)
	_step_to_stage(p2, Passenger.Stage.TOILET_EXIT)
	assert_float(StallDoors.open_weight(_world.sim, sid2, 0.0)).is_equal(1.0)
	# Cut-short (_turn_back) during TOILET_ENTER at enter_spent = 2 -> exit_spent = 10:
	# continuous 1.0 -> 1.0 across the reversal, then closes smoothly over 10..12.
	_setup_world(3)
	var sid3 := _stall_id()
	var p3 := _spawn_visitor(0)
	_step_to_stage(p3, Passenger.Stage.TOILET_ENTER)
	_world.step()
	var before_rev := StallDoors.open_weight(_world.sim, sid3, 0.0)
	var visit3 := _world.sim.toilets.visit_of(p3.id)
	visit3.resume_stage = Passenger.Stage.TO_GATE
	visit3.deadline = _world.sim.tick
	_world.step()
	assert_int(p3.stage).is_equal(Passenger.Stage.TOILET_EXIT)
	assert_float(before_rev).is_equal(1.0)
	assert_float(StallDoors.open_weight(_world.sim, sid3, 0.0)).is_equal_approx(before_rev, EPS)
	assert_float(StallDoors.open_weight(_world.sim, sid3, 0.5)).is_less(1.0)


func test_toilet_stall_glb_bifold_clears_floor_bags_and_stacks_compactly() -> void:
	var def := BuildCatalog.get_def(&"toilet_stall")
	var stall_node := auto_free(BuildView.make_object_node(def, null)) as Node3D
	StallDoors.apply(stall_node, 0.0)
	var closed_l := _part_bounds_in_stall(stall_node, StallDoors.LEAF_LEFT)
	var closed_r := _part_bounds_in_stall(stall_node, StallDoors.LEAF_RIGHT)
	assert_float(closed_l.end.x).is_greater(-0.02)
	assert_float(closed_r.position.x).is_less(0.02)
	var min_z_all := INF
	var max_z_all := -INF
	for sample in [0.0, 0.1, 0.25, 0.5, 0.75, 1.0]:
		StallDoors.apply(stall_node, sample)
		var box_l := _part_bounds_in_stall(stall_node, StallDoors.LEAF_LEFT)
		var box_r := _part_bounds_in_stall(stall_node, StallDoors.LEAF_RIGHT)
		var sample_min_z := minf(box_l.position.z, box_r.position.z)
		var sample_max_z := maxf(box_l.end.z, box_r.end.z)
		min_z_all = minf(min_z_all, sample_min_z)
		max_z_all = maxf(max_z_all, sample_max_z)
		# H1 == 0: never sweeps inward past z = 0.875 m (> STALL_BAG_M = 0.861 m).
		assert_float(sample_min_z).is_greater(0.875)
		assert_float(sample_min_z).is_greater(SecurityLooks.STALL_BAG_M + 0.01)
		# Compact outward stack: z <= 1.115 m (> 0.38 m short of Mount_Approach z = 1.50 m).
		assert_float(sample_max_z).is_less(1.115)
	var open_l := _part_bounds_in_stall(stall_node, StallDoors.LEAF_LEFT)
	var open_r := _part_bounds_in_stall(stall_node, StallDoors.LEAF_RIGHT)
	var outer_only_l := _part_bounds_in_stall(
		stall_node, StallDoors.LEAF_LEFT, false, Vector2(1.0, 1.2)
	)
	var fold_only_l := _part_bounds_in_stall(
		stall_node, StallDoors.FOLD_LEFT, false, Vector2(0.85, 0.95)
	)
	var outer_only_r := _part_bounds_in_stall(
		stall_node, StallDoors.LEAF_RIGHT, false, Vector2(1.0, 1.2)
	)
	var fold_only_r := _part_bounds_in_stall(
		stall_node, StallDoors.FOLD_RIGHT, false, Vector2(0.85, 0.95)
	)
	var clear_width := open_r.position.x - open_l.end.x
	print(
		(
			(
				"toilet_stall bifold: z_range=[%.4f, %.4f] open_L_x=[%.4f, %.4f]"
				+ " open_R_x=[%.4f, %.4f] clear_doorway_m=%.4f"
			)
			% [
				min_z_all,
				max_z_all,
				open_l.position.x,
				open_l.end.x,
				open_r.position.x,
				open_r.end.x,
				clear_width,
			]
		)
	)
	assert_float(clear_width).is_greater(0.81)
	assert_float(absf(open_l.position.x)).is_less(0.445)
	assert_float(absf(open_r.end.x)).is_less(0.445)
	# Folded 180 deg at w = 1.0, inner panel stacks cleanly clear of outer panel.
	assert_float(outer_only_l.end.x).is_less(fold_only_l.position.x)
	assert_float(fold_only_r.end.x).is_less(outer_only_r.position.x)


func test_relocation_and_stall_removal_leave_no_orphaned_open_door() -> void:
	_setup_world()
	var sid := _stall_id()
	var p := _spawn_visitor(0)
	_step_to_stage(p, Passenger.Stage.TOILET_ENTER)
	_views.draw()
	assert_float(_door_angles(_build_view.object_node(sid)).x).is_equal_approx(
		-StallDoors.OPEN_RAD, EPS
	)
	# Move the stall to MOVED_ANCHOR mid-enter: the rebuilt stall at the new spot
	# resets to closed (0.0) while the ghost at the old spot carries the open exit.
	var at := ReferenceTerminal.offset_on(_world.grid)
	var record := _world.grid.get_object(sid)
	var place := BuildEdit.place_object(record["def"], MOVED_ANCHOR + at, record["facing"])
	place.object_id = sid
	for res in _world.grid.apply_batch([BuildEdit.remove_object(sid), place]):
		assert_bool(res.ok).is_true()
	_build_view.refresh(_world.grid)
	_views.draw()
	assert_float(StallDoors.open_weight(_world.sim, sid, 0.0)).is_equal(0.0)
	assert_float(_door_angles(_build_view.object_node(sid)).length()).is_less(EPS)
	var ghosts := Relocation.ghosts(_world.sim)
	assert_int(ghosts.size()).is_equal(1)
	var ghost_node := _views.ghosts.node_of(ghosts[0])
	assert_object(ghost_node).is_not_null()
	var ghost_angles := _door_angles(ghost_node)
	assert_float(ghost_angles.x).is_equal_approx(-StallDoors.OPEN_RAD, EPS)
	assert_float(ghost_angles.z).is_equal_approx(StallDoors.FOLD_RAD, EPS)
	# Finish leaving the old spot and walk to the moved stall: moved stall opens on arrival.
	_step_to_stage(p, Passenger.Stage.TOILET_WALK)
	_step_to_stage(p, Passenger.Stage.TOILET_ENTER)
	_views.draw()
	assert_int(_views.ghosts.count()).is_equal(0)
	assert_float(_door_angles(_build_view.object_node(sid)).x).is_equal_approx(
		-StallDoors.OPEN_RAD, EPS
	)
	# Remove the stall outright: BuildView drops it and open_weight returns 0.0.
	assert_bool(_world.grid.apply(BuildEdit.remove_object(sid)).ok).is_true()
	_build_view.refresh(_world.grid)
	assert_float(StallDoors.open_weight(_world.sim, sid, 0.5)).is_equal(0.0)
	assert_object(_build_view.object_node(sid)).is_null()
	assert_bool(_build_view.stall_ids().has(sid)).is_false()


func test_save_load_snap_and_late_draw_determinism_and_main_scene_wiring() -> void:
	_setup_world(77)
	var sid := _stall_id()
	var p := _spawn_visitor(1)
	_step_to_stage(p, Passenger.Stage.TOILET_USE)
	var use_clock_snap := _world.clock.to_snapshot()
	var use_sim_snap := _world.sim.to_snapshot()
	# Build a second identical world that never calls draw() until the target frame.
	var grid_late := _base_grid.clone()
	var world_late := PassengerTestWorld.make(grid_late, FlightSim.schedule_starts(0), 77)
	assert_bool(world_late.clock.from_snapshot(use_clock_snap)).is_true()
	assert_bool(world_late.sim.from_snapshot(use_sim_snap)).is_true()
	var bv_late := auto_free(BuildView.new()) as BuildView
	add_child(bv_late)
	bv_late.refresh(grid_late)
	var views_late := auto_free(PassengerTestWorld.views()) as PassengerViews
	views_late.clock = world_late.clock
	views_late.sim = world_late.sim
	views_late.build_view = bv_late
	add_child(views_late)
	while p.stage != Passenger.Stage.TOILET_STANDING_UP:
		_world.step()
		world_late.step()
		_views.draw()
	for i in 22:
		_world.step()
		world_late.step()
		_views.draw()
	_world.clock._accumulator = 0.5 * SimClock.STEP
	world_late.clock._accumulator = 0.5 * SimClock.STEP
	_views.draw()
	views_late.draw()
	var angles_every := _door_angles(_build_view.object_node(sid))
	var angles_late := _door_angles(bv_late.object_node(sid))
	assert_float(absf(angles_every.x)).is_greater(0.2)
	assert_float(angles_every.distance_to(angles_late)).is_less(1e-6)
	# Save mid-ramp, then restore back to USE snapshot (clock backwards) and forward again.
	var ramp_clock := _world.clock.to_snapshot()
	var ramp_sim := _world.sim.to_snapshot()
	assert_bool(_world.clock.from_snapshot(use_clock_snap)).is_true()
	assert_bool(_world.sim.from_snapshot(use_sim_snap)).is_true()
	_views.snap()
	assert_float(_door_angles(_build_view.object_node(sid)).length()).is_less(EPS)
	assert_bool(_world.clock.from_snapshot(ramp_clock)).is_true()
	assert_bool(_world.sim.from_snapshot(ramp_sim)).is_true()
	_views.snap()
	assert_float(_door_angles(_build_view.object_node(sid)).distance_to(angles_every)).is_less(1e-6)
	world_late.free_all()
	# Verify main.tscn wires PassengerViews.build_mode -> ../BuildMode, which resolves BuildView.
	var state := (load("res://main/main.tscn") as PackedScene).get_state()
	var wired_path := NodePath()
	for idx in state.get_node_count():
		if state.get_node_name(idx) == &"PassengerViews":
			for prop in state.get_node_property_count(idx):
				if state.get_node_property_name(idx, prop) == &"build_mode":
					wired_path = state.get_node_property_value(idx, prop)
	assert_str(str(wired_path)).is_equal("../BuildMode")
	var mode := auto_free(BuildMode.new()) as BuildMode
	add_child(mode)
	var wired_views := auto_free(PassengerTestWorld.views()) as PassengerViews
	wired_views.build_mode = mode
	add_child(wired_views)
	assert_object(wired_views.build_view).is_same(mode.get_node("BuildView"))
