class_name TestPassengerThoughtsSim
extends GdUnitTestSuite
## Thoughts are recorded where the sim decides an outcome (decision
## passenger-inspect-thoughts-recorded-at-sim-outcomes-saved-pin-marks-where):
## a meal paid in full, food given up before service, a toilet use that resets
## the need, a long check-in queue, and decor whose net effect is positive. A
## meal cut short is neither a meal nor food given up.

const DECOR_SIZE := Vector2i(30, 20)
const GUEST_CELL := Vector2i(12, 8)
const STATUE_CELL := Vector2i(12, 6)

var _world: PassengerTestWorld
var _ids: Dictionary


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
		_world = null


func _kinds(p: Passenger) -> Array:
	var out := []
	for entry in PassengerThoughts.entries(p):
		out.append(PassengerThoughts.Kind.keys()[entry["kind"]])
	return out


func _cafe_guest() -> Passenger:
	var grid := BuildGrid.new()
	_ids = CafeTestLayout.build(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.hunger = 0
	p.cafe_cooldown = 1000000
	while p.stage != Passenger.Stage.TO_GATE and _world.clock.tick < 900:
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.TO_GATE)
	assert_bool(_world.sim.cafes.try_visit(p)).is_true()
	return p


func _run_until_resumed(p: Passenger, limit: int) -> void:
	while _world.sim.cafes.visit_of(p.id) != null and _world.clock.tick < limit:
		_world.step()


func test_a_passenger_with_no_event_on_its_journey_has_no_thoughts() -> void:
	_world = PassengerTestWorld.reference_world()
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	var seen := false
	while not p.is_done() and _world.clock.tick < PassengerTestWorld.doors_tick():
		_world.step()
		seen = seen or p.stage == Passenger.Stage.TO_GATE
	print("stage %s at tick %d, thoughts %s" % [p.stage, _world.clock.tick, _kinds(p)])
	assert_bool(seen).is_true()
	assert_array(_kinds(p)).is_empty()


func test_a_meal_paid_in_full_is_recorded_at_the_cafe() -> void:
	var p := _cafe_guest()
	var visit := _world.sim.cafes.visit_of(p.id)
	assert_array(_kinds(p)).is_empty()
	_run_until_resumed(p, 1400)
	print("outcome %d, thoughts %s" % [visit.outcome, PassengerThoughts.entries(p)])
	assert_int(visit.outcome).is_equal(CafeVisit.Outcome.COMPLETE)
	assert_array(_kinds(p)).is_equal(["MEAL"])
	assert_int(PassengerThoughts.entries(p)[0]["facility"]).is_equal(visit.room)


func test_food_given_up_before_service_is_recorded() -> void:
	var p := _cafe_guest()
	var visit := _world.sim.cafes.visit_of(p.id)
	visit.deadline = _world.clock.tick + 1
	_world.step()
	_world.step()
	print("served %s, thoughts %s" % [visit.served, PassengerThoughts.entries(p)])
	assert_object(_world.sim.cafes.visit_of(p.id)).is_null()
	assert_bool(visit.served).is_false()
	assert_array(_kinds(p)).is_equal(["FOOD_GIVEN_UP"])
	assert_int(PassengerThoughts.entries(p)[0]["facility"]).is_equal(visit.room)


func test_a_meal_cut_short_is_no_meal_and_no_food_given_up() -> void:
	var p := _cafe_guest()
	var visit := _world.sim.cafes.visit_of(p.id)
	while p.stage != Passenger.Stage.CAFE_SEATED and _world.clock.tick < 1400:
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.CAFE_SEATED)
	visit.deadline = _world.clock.tick + 1
	_run_until_resumed(p, 1400)
	print("outcome %d, thoughts %s" % [visit.outcome, _kinds(p)])
	assert_int(visit.outcome).is_equal(CafeVisit.Outcome.SHORT)
	assert_array(_kinds(p)).is_empty()


func test_a_toilet_use_that_resets_the_need_is_relief() -> void:
	var grid := BuildGrid.new()
	_ids = ToiletTestLayout.build(grid, 2)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_world.run_to(10)
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	p.carry_on = 0
	p.liquids = false
	p.alarm = false
	p.stage = Passenger.Stage.TO_SECURITY
	p.stage_tick = _world.clock.tick
	p.at = Vector2i(20, 14)
	p.clear_path()
	p.toilet_need = 90
	assert_bool(_world.sim.toilets.try_visit(p)).is_true()
	var visit := _world.sim.toilets.visit_of(p.id)
	while _world.sim.toilets.visit_of(p.id) != null and _world.clock.tick < 3000:
		_world.step()
	print("need %d, thoughts %s" % [p.toilet_need, PassengerThoughts.entries(p)])
	assert_array(_kinds(p)).is_equal(["TOILET_RELIEF"])
	assert_int(PassengerThoughts.entries(p)[0]["facility"]).is_equal(visit.room)


func test_a_long_check_in_queue_is_recorded_by_the_sim() -> void:
	_world = PassengerTestWorld.reference_world()
	var ids: Array[int] = []
	for i in 12:
		ids.append(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	var limit := PassengerTestWorld.doors_tick()
	var queued: Array[int] = []
	while _world.clock.tick < limit:
		_world.step()
		for id in ids:
			var p := _world.passenger(id)
			if p != null and not queued.has(id) and _kinds(p).has("LONG_QUEUE"):
				queued.append(id)
		if not queued.is_empty():
			break
	print("tick %d, long queues for %s" % [_world.clock.tick, queued])
	assert_array(queued).is_not_empty()
	var entry: Dictionary = PassengerThoughts.entries(_world.passenger(queued[0]))[0]
	assert_int(entry["value"]).is_greater_equal(10)
	assert_int(entry["facility"]).is_greater(0)


func test_decor_with_a_positive_net_effect_is_nice_decor_and_none_without_it() -> void:
	var grid := PassengerTestWorld.floored(DECOR_SIZE)
	PassengerTestWorld.place(grid, &"exit_door", Vector2i(2, 0), 0)
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(2, 19), 2)
	PassengerTestWorld.place(grid, &"seat_row", Vector2i(3, 14), 0)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(5000, 6000))
	_world.sim.apron_waypoints = PackedVector3Array()
	_world.run_to(10)
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	p.cleared = true
	p.stage = Passenger.Stage.STANDING
	p.stage_tick = _world.clock.tick
	p.at = GUEST_CELL
	p.clear_path()
	_world.sim.decor.beat(p)
	print("bare floor net %d" % _world.sim.decor.net_calm_at(GUEST_CELL))
	assert_array(_kinds(p)).is_empty()
	PassengerTestWorld.place(_world.grid, &"statue_indoor", STATUE_CELL, 0)
	_world.sim.decor.beat(p)
	print("net %d, thoughts %s" % [_world.sim.decor.net_calm_at(GUEST_CELL), _kinds(p)])
	assert_int(_world.sim.decor.net_calm_at(GUEST_CELL)).is_greater(0)
	assert_array(_kinds(p)).is_equal(["NICE_DECOR"])
	assert_that(PassengerThoughts.entries(p)[0]["cell"]).is_equal(GUEST_CELL)
