class_name TestCafeHunger
extends GdUnitTestSuite
## Hunger and browsing (decision cafe-visit-design-forecast-the-whole-
## itinerary-abandon-by-a, point 5; rulings passenger-needs-are-hunger-toilet-
## and-boredom-met-by-food-st and a-passenger-with-a-high-need-detours-to-the-
## nearest-facility): hunger starts at 10-40 from the sim RNG, rises once a
## simulated second, sends a hungry passenger to the nearest reachable cafe
## when the forecast allows and costs mood when it cannot; a walking passenger
## passing a cafe with time to spare drops in, with a cooldown.

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


## With `roomy`, a flight that boards at 1500 and closes at 4000.
func _make_with_cafes(roomy := false) -> void:
	var grid := BuildGrid.new()
	_ids = CafeTestLayout.build(grid)
	var starts := FlightSim.schedule_starts(0)
	if roomy:
		starts = PassengerTestWorld.starts_with(1500, 4000)
	_world = PassengerTestWorld.make(grid, starts)


## Spawns a passenger and runs until it reaches `stage`, with no cafe visit on
## the way (its cooldown holds until then).
func _spawn_to(stage: Passenger.Stage, hunger: int, limit := 900) -> Passenger:
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.hunger = hunger
	p.cafe_cooldown = 1000000
	while p.stage != stage and _world.clock.tick < limit:
		_world.step()
	assert_int(p.stage).is_equal(stage)
	p.cafe_cooldown = 0
	return p


## Steps until `p` has a visit, up to `ticks`; returns the ticks it took or -1.
func _ticks_to_visit(p: Passenger, ticks: int) -> int:
	for i in ticks:
		if _world.sim.cafes.visit_of(p.id) != null:
			return i
		_world.step()
	return -1


func _hungers(seed: int) -> Array[int]:
	var world := PassengerTestWorld.reference_world(seed)
	var out: Array[int] = []
	for i in 12:
		out.append(world.passenger(world.sim.spawn_now(PassengerTestWorld.FLIGHT)).hunger)
	world.free_all()
	return out


func test_starting_hunger_is_10_to_40_from_the_sim_rng() -> void:
	var first := _hungers(31)
	assert_array(first).is_equal(_hungers(31))
	var distinct := {}
	for value in first:
		assert_int(value).is_between(CafeSim.HUNGER_START_MIN, CafeSim.HUNGER_START_MAX)
		distinct[value] = true
	print("hungers %s" % [first])
	assert_int(distinct.size()).is_greater(3)


func test_hunger_rises_one_a_second_up_to_100() -> void:
	_world = PassengerTestWorld.reference_world()
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.hunger = 20
	_world.run_to(_world.clock.tick + 10 * PassengerSim.BEAT_TICKS)
	assert_int(p.hunger).is_equal(30)
	p.hunger = CafeSim.HUNGER_MAX - 1
	_world.run_to(_world.clock.tick + 3 * PassengerSim.BEAT_TICKS)
	assert_int(p.hunger).is_equal(CafeSim.HUNGER_MAX)


func test_unmet_hunger_costs_a_mood_point_every_few_seconds() -> void:
	_world = PassengerTestWorld.reference_world()
	var hungry := Passenger.new()
	hungry.id = 1000
	hungry.hunger = CafeSim.HUNGRY_AT + 5
	var fed := Passenger.new()
	fed.id = 1001
	fed.hunger = 0
	var beats := CafeSim.HUNGRY_MOOD_BEATS * 4
	for i in beats:
		_world.run_to((i + 1) * PassengerSim.BEAT_TICKS)
		_world.sim.cafes.beat(hungry)
		_world.sim.cafes.beat(fed)
	print("mood hungry %d fed %d" % [hungry.mood, fed.mood])
	assert_int(hungry.mood).is_equal(Passenger.MOOD_START - 4)
	assert_int(fed.mood).is_equal(Passenger.MOOD_START)


func test_a_hungry_passenger_heading_for_the_gate_detours_to_the_airside_cafe() -> void:
	_make_with_cafes()
	var p := _spawn_to(Passenger.Stage.TO_GATE, 0)
	p.hunger = CafeSim.HUNGRY_AT
	var took := _ticks_to_visit(p, PassengerSim.BEAT_TICKS + 1)
	print("detour after %d ticks" % took)
	assert_int(took).is_between(0, PassengerSim.BEAT_TICKS)
	assert_int(_world.sim.cafes.visit_of(p.id).room).is_equal(_ids["air_room"])


func test_a_hungry_passenger_after_check_in_detours_to_the_landside_cafe() -> void:
	_make_with_cafes()
	var p := _spawn_to(Passenger.Stage.TO_SECURITY, 0)
	p.hunger = CafeSim.HUNGRY_AT
	assert_int(_ticks_to_visit(p, PassengerSim.BEAT_TICKS + 1)).is_between(
		0, PassengerSim.BEAT_TICKS
	)
	assert_int(_world.sim.cafes.visit_of(p.id).room).is_equal(_ids["land_room"])


func test_a_hungry_passenger_queuing_for_check_in_waits_its_turn() -> void:
	_make_with_cafes()
	var p := _spawn_to(Passenger.Stage.CHECKIN_QUEUE, CafeSim.HUNGRY_AT)
	assert_int(_ticks_to_visit(p, 2 * PassengerSim.BEAT_TICKS)).is_equal(-1)


func test_a_hungry_passenger_without_time_retries_later_and_loses_mood() -> void:
	_make_with_cafes()
	_world.run_to(1000)
	var p := _spawn_to(Passenger.Stage.TO_SECURITY, CafeSim.HUNGRY_AT, 1600)
	var mood := p.mood
	assert_int(_ticks_to_visit(p, PassengerSim.BEAT_TICKS + 1)).is_equal(-1)
	assert_int(p.cafe_cooldown).is_greater(_world.clock.tick)
	assert_int(p.cafe_cooldown).is_less_equal(_world.clock.tick + CafeSim.HUNGER_RETRY_TICKS)
	_world.run_to(_world.clock.tick + CafeSim.HUNGRY_MOOD_BEATS * PassengerSim.BEAT_TICKS)
	print("mood %d -> %d" % [mood, p.mood])
	assert_int(p.mood).is_less(mood)


func test_a_walking_passenger_passing_a_cafe_with_time_to_spare_drops_in() -> void:
	_make_with_cafes()
	# Just out of the scanner, walking west to the gate seats: the airside
	# cafe's order spot is within the airside reach only for these first steps,
	# so its beat is run here rather than waited for.
	var p := _spawn_to(Passenger.Stage.TO_GATE, 0)
	assert_bool(p.is_moving()).is_true()
	var counter: Array = _world.sim.cafes.layout.cafe(_ids["air_room"])["counters"]
	var away := Passenger.octile_mm(p.at, counter[0]["lane"][0])
	print("browse from %s: %d mm, hunger %d" % [p.at, away, p.hunger])
	assert_int(away).is_less_equal(CafeSim.AIRSIDE_BROWSE_REACH_MM)
	assert_int(away).is_greater(CafeSim.BROWSE_REACH_MM)
	_world.sim.cafes.beat(p)
	assert_int(p.hunger).is_less(CafeSim.HUNGRY_AT)
	assert_object(_world.sim.cafes.visit_of(p.id)).is_not_null()
	assert_int(_world.sim.cafes.visit_of(p.id).room).is_equal(_ids["air_room"])


func test_browsing_only_looks_at_cafes_within_reach() -> void:
	_make_with_cafes()
	# Just checked in at a desk, well beyond the landside reach of the cafe.
	var p := _spawn_to(Passenger.Stage.TO_SECURITY, 0)
	var counter: Array = _world.sim.cafes.layout.cafe(_ids["land_room"])["counters"]
	var away := Passenger.octile_mm(p.at, counter[0]["lane"][0])
	print("from %s: %d mm" % [p.at, away])
	assert_int(away).is_greater(CafeSim.BROWSE_REACH_MM)
	assert_bool(_world.sim.cafes.try_visit(p, true)).is_false()
	assert_bool(_world.sim.cafes.try_visit(p)).is_true()


func test_a_refused_browse_waits_out_its_cooldown() -> void:
	_make_with_cafes(true)
	var walkers: Array[Passenger] = []
	for i in 3:
		var walker := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
		walker.hunger = 0
		walker.cafe_cooldown = 1000000
		walkers.append(walker)
	# The first two to head for the gate take both airside seats; the third
	# passes the cafe with nowhere to sit.
	var arrived: Array[Passenger] = []
	while arrived.size() < 3 and _world.clock.tick < 900:
		_world.step()
		for walker in walkers:
			if walker.stage == Passenger.Stage.TO_GATE and not arrived.has(walker):
				arrived.append(walker)
				if arrived.size() < 3:
					assert_bool(_world.sim.cafes.try_visit(walker)).is_true()
				else:
					walker.cafe_cooldown = 0
	assert_int(arrived.size()).is_equal(3)
	var p: Passenger = arrived[2]
	_world.run_to(_world.clock.tick + PassengerSim.BEAT_TICKS + 1)
	print("cooldown %d at %d" % [p.cafe_cooldown, _world.clock.tick])
	assert_object(_world.sim.cafes.visit_of(p.id)).is_null()
	assert_int(p.cafe_cooldown).is_greater(_world.clock.tick + CafeSim.HUNGER_RETRY_TICKS)
