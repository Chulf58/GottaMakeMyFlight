class_name TestCafeHungerGate
extends GdUnitTestSuite
## Hunger waits for the cafe tier (decision build-unlocks-need-stars-and-
## passengers-served-hunger-cafe-a): with CafeSim.hunger_enabled off no
## passenger starts hungry, grows hungry or loses mood to food, and the food
## hint has no cause. A bare sim has hunger off, so a game without the unlock
## controller has no hungry passengers; PassengerTestWorld turns it on for the
## tests that feed them.

var _w: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _w != null:
		_w.free_all()
	_w = null


## A floor with an entrance and no cafe.
func _no_cafe() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(14, 12))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 11), 2)
	_w = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))


func test_a_bare_sim_has_hunger_off_and_the_test_world_has_it_on() -> void:
	var bare: PassengerSim = auto_free(PassengerSim.new())
	assert_bool(bare.cafes.hunger_enabled).is_false()
	_no_cafe()
	assert_bool(_w.sim.cafes.hunger_enabled).is_true()


## The start-hunger draw is taken whether hunger is on or not, so the random
## stream (and every later roll) is the same either way.
func test_the_start_hunger_draw_is_taken_with_hunger_off() -> void:
	var off: PassengerSim = auto_free(PassengerSim.new())
	var on: PassengerSim = auto_free(PassengerSim.new())
	on.cafes.hunger_enabled = true
	var rng_off := RandomNumberGenerator.new()
	var rng_on := RandomNumberGenerator.new()
	rng_off.seed = 77
	rng_on.seed = 77
	assert_int(off.cafes.start_hunger(rng_off)).is_equal(0)
	assert_int(on.cafes.start_hunger(rng_on)).is_between(
		CafeSim.HUNGER_START_MIN, CafeSim.HUNGER_START_MAX
	)
	assert_int(rng_off.randi()).is_equal(rng_on.randi())


func test_with_hunger_off_a_new_passenger_is_not_hungry_and_stays_so() -> void:
	_no_cafe()
	_w.sim.cafes.hunger_enabled = false
	var hungers: Array[int] = []
	for i in 12:
		var p := _w.passenger(_w.sim.spawn_now(PassengerTestWorld.FLIGHT))
		hungers.append(p.hunger)
	_w.run_to(_w.clock.tick + 90 * PassengerSim.BEAT_TICKS)
	for id in _w.sim.passenger_ids():
		hungers.append(_w.sim.get_passenger(id).hunger)
	print("hunger values with the cafe tier shut: %s" % [hungers])
	assert_int(hungers.size()).is_greater(12)
	assert_int(hungers.max()).is_equal(0)


func test_with_hunger_on_the_same_passengers_do_get_hungry() -> void:
	_no_cafe()
	var hungers: Array[int] = []
	for i in 12:
		hungers.append(_w.passenger(_w.sim.spawn_now(PassengerTestWorld.FLIGHT)).hunger)
	print("hunger values with the cafe tier open: %s" % [hungers])
	assert_int(hungers.max()).is_greater_equal(CafeSim.HUNGRY_AT)


func test_hunger_off_costs_no_mood_and_on_does() -> void:
	_no_cafe()
	var off := Passenger.new()
	off.id = 1000
	off.hunger = CafeSim.HUNGRY_AT + 5
	var on := Passenger.new()
	on.id = 1001
	on.hunger = CafeSim.HUNGRY_AT + 5
	var beats := CafeSim.HUNGRY_MOOD_BEATS * 4
	for i in beats:
		_w.run_to((i + 1) * PassengerSim.BEAT_TICKS)
		_w.sim.cafes.hunger_enabled = false
		_w.sim.cafes.beat(off)
		_w.sim.cafes.hunger_enabled = true
		_w.sim.cafes.beat(on)
	print("mood with hunger off %d, on %d" % [off.mood, on.mood])
	assert_int(off.mood).is_equal(Passenger.MOOD_START)
	assert_int(off.hunger).is_equal(0)
	assert_int(on.mood).is_less(Passenger.MOOD_START)


func test_the_food_hint_has_no_cause_before_the_cafe_tier() -> void:
	_no_cafe()
	var p := _w.passenger(_w.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.hunger = CafeSim.HUNGER_MAX
	var open := HintRules.read_world(_w.sim, [])
	assert_int(open["max_hunger"]).is_equal(CafeSim.HUNGER_MAX)
	assert_array(HintRules.causes(open)).contains([HintRules.FOOD])
	_w.sim.cafes.hunger_enabled = false
	var shut := HintRules.read_world(_w.sim, [])
	assert_int(shut["max_hunger"]).is_equal(0)
	assert_array(HintRules.causes(shut)).not_contains([HintRules.FOOD])
