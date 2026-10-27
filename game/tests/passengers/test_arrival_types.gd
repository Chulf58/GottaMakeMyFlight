class_name TestArrivalTypes
extends GdUnitTestSuite
## Arrival types (decision passengers-get-an-arrival-type-rushed-typical-or-relaxed):
## each scheduled passenger draws rushed, typical or relaxed from the sim RNG.
## Typical ones arrive in the flight's usual window, rushed ones late in it,
## and relaxed ones before the flight's first state, up to two game hours
## before departure. The flight timeline and contracts do not change.

## The flight's first state, late enough that every window is still ahead.
const FIRST := 4400
const COUNT := 60

var _worlds: Array[PassengerTestWorld] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for world in _worlds:
		world.free_all()
	_worlds.clear()


## The reference terminal, one flight first at `first`, COUNT passengers
## scheduled and every one of them spawned.
func _flight(seed: int, first := FIRST) -> PassengerTestWorld:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(first), seed)
	_worlds.append(world)
	assert_bool(world.sim.schedule_flight(PassengerTestWorld.FLIGHT, COUNT)).is_true()
	world.run_to(_last(world) + 1)
	assert_int(world.sim.passenger_ids().size()).is_equal(COUNT)
	return world


func _last(world: PassengerTestWorld) -> int:
	var doors := world.flights.doors_close_tick(PassengerTestWorld.FLIGHT)
	return doors - PassengerSim.LAST_SPAWN_LEAD_TICKS


## [spawn tick, variant, arrival type] per passenger, in id order.
func _arrivals(world: PassengerTestWorld) -> Array:
	var out := []
	for id in world.sim.passenger_ids():
		var p := world.passenger(id)
		out.append([p.spawn_tick, p.variant, int(p.arrival_type)])
	return out


## Spawn ticks by arrival type.
func _ticks_by_type(world: PassengerTestWorld) -> Dictionary:
	var out := {}
	for type in ArrivalTypes.Type.values():
		out[type] = []
	for id in world.sim.passenger_ids():
		var p := world.passenger(id)
		out[p.arrival_type].append(p.spawn_tick)
	print("spawn ticks by type: %s" % out)
	return out


func test_the_arrival_type_is_drawn_from_the_seed() -> void:
	var a := _flight(5)
	var b := _flight(5)
	var c := _flight(6)
	print("seed 5: %s" % [_arrivals(a)])
	assert_array(_arrivals(a)).is_equal(_arrivals(b))
	assert_array(_arrivals(a)).is_not_equal(_arrivals(c))
	var by_type := _ticks_by_type(a)
	for type in ArrivalTypes.Type.values():
		assert_int((by_type[type] as Array).size()).is_greater(0)


func test_shares_follow_the_split_constant() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var counts := [0, 0, 0]
	var draws := 6000
	for i in draws:
		counts[ArrivalTypes.draw(rng)] += 1
	print("draws %d: %s against shares %s" % [draws, counts, ArrivalTypes.SHARES])
	var total := 0
	for share in ArrivalTypes.SHARES:
		total += share
	assert_int(total).is_equal(100)
	for type in ArrivalTypes.Type.values():
		@warning_ignore("integer_division")
		var percent: int = counts[type] * 100 / draws
		var share: int = ArrivalTypes.SHARES[type]
		assert_int(percent).is_between(share - 2, share + 2)


func test_relaxed_passengers_arrive_before_the_first_state_up_to_2_h_before_departure() -> void:
	var world := _flight(7)
	var departure := world.flights.state_start(PassengerTestWorld.FLIGHT, FlightSim.State.PUSHBACK)
	var relaxed: Array = _ticks_by_type(world)[ArrivalTypes.Type.RELAXED]
	print("first state %d, departure %d, relaxed %s" % [FIRST, departure, relaxed])
	assert_int(ArrivalTypes.RELAXED_LEAD_TICKS).is_equal(2 * 60 * GameCalendar.TICKS_PER_MINUTE)
	assert_int(relaxed.min()).is_greater_equal(departure - ArrivalTypes.RELAXED_LEAD_TICKS)
	assert_int(relaxed.max()).is_less_equal(FIRST)
	# They come ahead of the window today's passengers arrive in.
	assert_int(relaxed.min()).is_less(FIRST + 1 - 200)


func test_rushed_passengers_spawn_late_in_the_window_and_typical_ones_in_all_of_it() -> void:
	var world := _flight(8)
	var last := _last(world)
	var by_type := _ticks_by_type(world)
	var rushed: Array = by_type[ArrivalTypes.Type.RUSHED]
	var typical: Array = by_type[ArrivalTypes.Type.TYPICAL]
	assert_int(rushed.min()).is_greater_equal(last - ArrivalTypes.RUSHED_SPAN_TICKS)
	assert_int(rushed.max()).is_less_equal(last)
	assert_int(typical.min()).is_greater(FIRST)
	assert_int(typical.max()).is_less_equal(last)
	# Typical arrivals spread over the whole window, early part included.
	assert_int(typical.min()).is_less(last - ArrivalTypes.RUSHED_SPAN_TICKS)


func test_a_window_already_behind_the_clock_falls_back_to_the_typical_window() -> void:
	# The flight's first state is tick 0, so no relaxed arrival can come early.
	var world := _flight(9, 0)
	var by_type := _ticks_by_type(world)
	var relaxed: Array = by_type[ArrivalTypes.Type.RELAXED]
	assert_int(relaxed.size()).is_greater(0)
	assert_int(relaxed.min()).is_greater_equal(1)
	assert_int(relaxed.max()).is_less_equal(_last(world))
	# Spread over the window, not piled on the first tick.
	assert_int(relaxed.max()).is_greater(relaxed.min() + 100)


## Spawn window per type, against the flight's own ticks.
func test_windows_are_read_from_the_flight() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(6, 6))
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(FIRST))
	_worlds.append(world)
	var id := PassengerTestWorld.FLIGHT
	var last := FIRST + 1900 - PassengerSim.LAST_SPAWN_LEAD_TICKS
	var departure := FIRST + 1960
	var now := world.clock.tick
	var typical := ArrivalTypes.window(ArrivalTypes.Type.TYPICAL, world.flights, id, now)
	var rushed := ArrivalTypes.window(ArrivalTypes.Type.RUSHED, world.flights, id, now)
	var relaxed := ArrivalTypes.window(ArrivalTypes.Type.RELAXED, world.flights, id, now)
	assert_object(typical).is_equal(Vector2i(FIRST + 1, last))
	assert_object(rushed).is_equal(Vector2i(last - ArrivalTypes.RUSHED_SPAN_TICKS, last))
	assert_object(relaxed).is_equal(Vector2i(departure - ArrivalTypes.RELAXED_LEAD_TICKS, FIRST))
	# Half of the relaxed window behind the clock: only what is ahead is used.
	var mid := departure - ArrivalTypes.RELAXED_LEAD_TICKS + 100
	assert_object(ArrivalTypes.window(ArrivalTypes.Type.RELAXED, world.flights, id, mid)).is_equal(
		Vector2i(mid + 1, FIRST)
	)
