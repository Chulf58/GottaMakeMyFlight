class_name TestCafeViews
extends GdUnitTestSuite
## How a cafe visit looks: guests sit with the sit clips at the seat's
## Mount_SitRoot facing the table, the follow panel shows hunger, and a paid
## visit pops '+$<amount>' over the counter (ruling shops-and-food-stalls-earn-
## per-visit-toilets-and-screens-cos), which rises, fades and is reused.

var _world: PassengerTestWorld
var _views: PassengerViews
var _ids: Dictionary


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := BuildGrid.new()
	_ids = CafeTestLayout.build(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_views = PassengerViews.new()
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


func _clip(id: int) -> String:
	return _views.node_for(id).get_meta(&"clip", "")


func test_a_seated_guest_sits_at_the_seat_root_facing_the_table() -> void:
	var p := _guest()
	var seat := _world.sim.cafes.visit_of(p.id).seat
	_run_to_stage(p, Passenger.Stage.CAFE_SITTING_DOWN)
	assert_str(_clip(p.id)).is_equal("sit_down")
	_run_to_stage(p, Passenger.Stage.CAFE_SEATED)
	assert_str(_clip(p.id)).is_equal("sit_idle")
	var node := _views.node_for(p.id)
	var root := BuildObjectDef.seat_root_world(_world.grid, seat)
	var facing: Vector2i = seat["facing"]
	print(
		"seated at %s root %s facing %s yaw %.3f" % [node.position, root, facing, node.rotation.y]
	)
	assert_float(_world.sim.world_position(p).distance_to(root)).is_less(0.001)
	assert_float(node.rotation.y).is_equal_approx(atan2(facing.x, facing.y), 0.001)
	_views.draw()
	assert_float(node.rotation.y).is_equal_approx(atan2(facing.x, facing.y), 0.001)
	_run_to_stage(p, Passenger.Stage.CAFE_STANDING_UP)
	assert_str(_clip(p.id)).is_equal("stand_up")


func test_sitting_down_moves_from_the_approach_cell_to_the_seat_root() -> void:
	var p := _guest()
	var seat := _world.sim.cafes.visit_of(p.id).seat
	_run_to_stage(p, Passenger.Stage.CAFE_SITTING_DOWN)
	var approach := _world.grid.cell_to_world(seat["approach"])
	var root := BuildObjectDef.seat_root_world(_world.grid, seat)
	assert_float(_world.sim.world_position(p).distance_to(approach)).is_less(0.001)
	for i in CafeSim.SHUFFLE_TICKS:
		_world.step()
	assert_float(_world.sim.world_position(p).distance_to(root)).is_less(0.001)


func test_the_follow_panel_shows_hunger() -> void:
	# In the tree, so the HUD's own labels are its children and freed with it.
	var hud := PassengerHud.new()
	hud.clock = _world.clock
	hud.flights = _world.flights
	hud.sim = _world.sim
	hud.views = _views
	add_child(hud)
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.hunger = 47
	_views.selected_id = p.id
	assert_str(hud.follow_text()).contains("hunger 47")
	hud.free()


func test_a_paid_visit_pops_its_amount_over_the_counter_then_fades() -> void:
	var p := _guest()
	var pops := _views.cafe_pops()
	assert_int(pops.live_count()).is_equal(0)
	_run_to_stage(p, Passenger.Stage.CAFE_STANDING_UP)
	var amount := _world.sim.cafes.visit_of(p.id).amount
	assert_int(amount).is_greater(0)
	assert_int(pops.live_count()).is_equal(1)
	var label := pops.live_labels()[0]
	var counter := _world.grid.get_object(_ids["air_counter"])
	var cells := BuildCatalog.get_def(&"cafe_counter").footprint(
		counter["anchor"], counter["facing"]
	)
	var above := BuildView.object_transform(_world.grid, cells, counter["facing"]).origin
	print("pop '%s' at %s, counter at %s" % [label.text, label.position, above])
	assert_str(label.text).is_equal("+$%d" % amount)
	(
		assert_float(
			Vector2(label.position.x, label.position.z).distance_to(Vector2(above.x, above.z))
		)
		. is_less(0.01)
	)
	assert_float(label.position.y).is_greater(above.y + 1.5)
	var start_y := label.position.y
	pops.advance(CafePops.POP_SECONDS * 0.5)
	assert_float(label.position.y).is_greater(start_y + 0.3)
	assert_float(label.modulate.a).is_less(0.75)
	pops.advance(CafePops.POP_SECONDS)
	assert_int(pops.live_count()).is_equal(0)
	assert_bool(label.visible).is_false()
