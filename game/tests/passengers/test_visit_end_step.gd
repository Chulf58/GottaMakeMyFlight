class_name TestVisitEndStep
extends GdUnitTestSuite
## The tick an ordinary toilet or cafe visit ends moves the visitor no further
## than a walking step (board a791eb90). The last step out of the stall or off
## the seat is drawn from the facility, and the journey's own walk (to the
## scanners or to the gate) must start on the tick after it, not on the same
## tick, which drew 0.137 m (toilet) and 0.159 m (cafe) against a 0.098 m step.
##
## Steps are measured on the drawn position a PassengerViews records each tick
## (tick_position()), as in test_room_move_toilet.gd and test_room_move_cafe.gd,
## from the start of the visit to a few ticks after it ends.

const MAX_STEP_M := PassengerSim.WALK_MM / 1000.0 + 0.002
## Ticks measured after the visit has ended, past the hand-over.
const AFTER_TICKS := 10

var _world: PassengerTestWorld
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
		_world.free_all()
		_world = null


func _views_on_world() -> void:
	_views = PassengerViews.new()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)


func _at() -> Vector2i:
	return ReferenceTerminal.offset_on(_world.grid)


## Steps until `has_visit` is false, then AFTER_TICKS more, and returns
## [largest drawn step of any tick, "tick N stage S step X" for that tick].
func _largest_step(p: Passenger, has_visit: Callable) -> Array:
	# One tick first, so a passenger the test placed is not measured jumping
	# from where the views last saw it.
	_world.step()
	var last := _views.tick_position(p.id, true)
	var largest := 0.0
	var worst := ""
	var until := _world.clock.tick + 3000
	var after := -1
	while _world.clock.tick < until and after < AFTER_TICKS:
		_world.step()
		var now := _views.tick_position(p.id, true)
		if now.distance_to(last) > largest:
			largest = now.distance_to(last)
			worst = "tick %d stage %d step %.3f" % [_world.clock.tick, p.stage, largest]
		last = now
		if after >= 0 or not has_visit.call():
			after += 1
	assert_int(after).is_equal(AFTER_TICKS)
	return [largest, worst]


func test_a_toilet_visit_ends_with_no_step_over_a_walking_step() -> void:
	var grid := BuildGrid.new()
	ToiletTestLayout.build(grid, 1)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_views_on_world()
	_world.run_to(10)
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	p.carry_on = 0
	p.liquids = false
	p.alarm = false
	p.stage = Passenger.Stage.TO_SECURITY
	p.stage_tick = _world.clock.tick
	p.at = Vector2i(20, 14) + _at()
	p.clear_path()
	p.toilet_need = 90
	assert_bool(_world.sim.toilets.try_visit(p)).is_true()
	var toilets := _world.sim.toilets
	var result := _largest_step(p, func() -> bool: return toilets.visit_of(p.id) != null)
	assert_float(result[0]).override_failure_message(result[1]).is_less(MAX_STEP_M)
	# The visit ran its whole course: the use reset the need.
	assert_int(p.toilet_need).is_less(10)


func test_a_cafe_visit_ends_with_no_step_over_a_walking_step() -> void:
	var grid := BuildGrid.new()
	CafeTestLayout.build(grid)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(1500, 4000))
	_views_on_world()
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.hunger = 0
	p.cafe_cooldown = 1000000
	var started := false
	while not started and _world.clock.tick < 1400:
		_world.step()
		if p.stage == Passenger.Stage.TO_GATE:
			started = _world.sim.cafes.try_visit(p)
	assert_bool(started).is_true()
	var cafes := _world.sim.cafes
	var result := _largest_step(p, func() -> bool: return cafes.visit_of(p.id) != null)
	assert_float(result[0]).override_failure_message(result[1]).is_less(MAX_STEP_M)
	assert_int(_world.sim.wallet.balance).is_greater(0)
