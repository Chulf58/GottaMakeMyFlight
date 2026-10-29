class_name TestToiletViews
extends GdUnitTestSuite
## How a toilet visit is drawn, through the views' existing seated poses
## (decision toilet-stall-kit-piece-1x2-footprint-side-partitions-out-to): the
## passenger walks in from the approach cell to Mount_Turn, sits down with the
## sit clips at Mount_Use facing out of the door, and walks back out.

var _world: PassengerTestWorld
var _views: PassengerViews


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := BuildGrid.new()
	ToiletTestLayout.build(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_world.run_to(10)
	_views = PassengerViews.new()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)


func after_test() -> void:
	_views.free()
	_world.free_all()


func _run_to_stage(p: Passenger, stage: Passenger.Stage) -> void:
	while p.stage != stage and _world.clock.tick < 2000:
		_world.step()
	assert_int(p.stage).is_equal(stage)


func _clip(id: int) -> String:
	return _views.node_for(id).get_meta(&"clip", "")


func test_a_visitor_walks_in_sits_at_mount_use_facing_out_and_walks_out() -> void:
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	p.carry_on = 0
	p.liquids = false
	p.alarm = false
	p.stage = Passenger.Stage.TO_SECURITY
	p.at = Vector2i(20, 14)
	p.clear_path()
	assert_bool(_world.sim.toilets.try_visit(p)).is_true()
	var stall := _world.sim.toilets.visit_of(p.id).stall
	_run_to_stage(p, Passenger.Stage.TOILET_ENTER)
	_world.step()
	var stepping_in := _clip(p.id)
	_run_to_stage(p, Passenger.Stage.TOILET_SITTING_DOWN)
	var sitting := _clip(p.id)
	var turn_gap := _world.sim.world_position(p).distance_to(stall["turn"])
	_run_to_stage(p, Passenger.Stage.TOILET_USE)
	var node := _views.node_for(p.id)
	var out: Vector2i = stall["front"]
	print(
		(
			"stepping in %s, sitting down %s %.3f m from the turn spot, seated %s at %s yaw %.3f"
			% [stepping_in, sitting, turn_gap, _clip(p.id), node.position, node.rotation.y]
		)
	)
	assert_str(stepping_in).is_equal("walk")
	assert_str(sitting).is_equal("sit_down")
	assert_float(turn_gap).is_less(0.001)
	assert_str(_clip(p.id)).is_equal("sit_idle")
	assert_float(_world.sim.world_position(p).distance_to(stall["use"])).is_less(0.001)
	assert_float(node.rotation.y).is_equal_approx(atan2(out.x, out.y), 0.001)
	# The views turn it to face out, from wherever it was turned.
	node.rotation.y = 1.234
	_world.step()
	assert_float(node.rotation.y).is_equal_approx(atan2(out.x, out.y), 0.001)
	_views.draw()
	assert_float(node.rotation.y).is_equal_approx(atan2(out.x, out.y), 0.001)
	_run_to_stage(p, Passenger.Stage.TOILET_STANDING_UP)
	assert_str(_clip(p.id)).is_equal("stand_up")
	_run_to_stage(p, Passenger.Stage.TOILET_EXIT)
	_world.step()
	assert_str(_clip(p.id)).is_equal("walk")
