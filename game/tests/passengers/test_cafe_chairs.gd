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


func test_no_step_away_from_a_cafe_seat() -> void:
	var p := _guest()
	_run_to_stage(p, Passenger.Stage.CAFE_ORDER)
	assert_vector(CafeChairs.offset(_world.sim, p)).is_equal(Vector3.ZERO)
	var walker := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	_world.step()
	assert_vector(CafeChairs.offset(_world.sim, walker)).is_equal(Vector3.ZERO)
