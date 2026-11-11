class_name TestQuietNight
extends GdUnitTestSuite
## The quiet-night detector (decision quiet-nights-fast-forward-automatically-
## when-nothing-is-due): quiet means the airport is open, nobody is in the
## terminal, no spawn is pending, no flight is moving and the clock is not
## paused (every panel hold pauses it). While quiet, the clock fast-forwards to
## LEAD_TICKS before the next flight event and stops there for good.

## The one-off flight's first state: far enough ahead that tick 0 is quiet.
const FIRST := 20_000
const FRAME := 1.0 / 60.0

var _world: PassengerTestWorld
var _quiet: QuietNight


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(8, 6))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 5), 3)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(FIRST))
	_quiet = auto_free(QuietNight.new()) as QuietNight
	_quiet.bind(_world.clock, _world.flights, _world.sim)


func after_test() -> void:
	_world.free_all()


## LEAD_TICKS before the one-off flight's next state (APPROACH).
func _expected_stop() -> int:
	return FlightSim.schedule_starts(FIRST)[FlightSim.State.APPROACH] - QuietNight.LEAD_TICKS


func test_an_open_empty_airport_is_quiet_and_stops_ahead_of_the_next_event() -> void:
	_world.flights.open_airport()
	print("quiet=%s stop=%d want=%d" % [_quiet.is_quiet(), _quiet.stop_tick(), _expected_stop()])
	assert_bool(_quiet.is_quiet()).is_true()
	assert_int(_quiet.stop_tick()).is_equal(_expected_stop())
	assert_bool(_world.clock.fast_forward_source.is_valid()).is_true()


func test_a_closed_airport_is_not_quiet() -> void:
	assert_bool(_quiet.is_quiet()).is_false()
	assert_int(_quiet.stop_tick()).is_equal(-1)
	_world.flights.open_airport()
	assert_bool(_quiet.is_quiet()).is_true()


func test_a_paused_clock_is_not_quiet() -> void:
	_world.flights.open_airport()
	_world.clock.set_paused(true)
	assert_bool(_quiet.is_quiet()).is_false()
	assert_int(_quiet.stop_tick()).is_equal(-1)


func test_a_pending_spawn_is_not_quiet() -> void:
	_world.flights.open_airport()
	assert_bool(_world.sim.schedule_flight(PassengerTestWorld.FLIGHT, 3)).is_true()
	print("pending=%d" % _world.sim.pending_spawns())
	assert_int(_world.sim.pending_spawns()).is_greater(0)
	assert_bool(_quiet.is_quiet()).is_false()


func test_a_passenger_in_the_terminal_is_not_quiet() -> void:
	_world.flights.open_airport()
	assert_int(_world.sim.spawn_now(PassengerTestWorld.FLIGHT)).is_greater(0)
	print("active=%d" % _world.sim.active_count())
	assert_int(_world.sim.active_count()).is_equal(1)
	assert_bool(_quiet.is_quiet()).is_false()


func test_a_moving_flight_is_not_quiet() -> void:
	_world.flights.open_airport()
	var starts := FlightSim.schedule_starts(0)
	assert_bool(_world.flights.add_flight("GA1", starts)).is_true()
	_world.run_to(starts[FlightSim.State.APPROACH])
	print("GA1 state=%d" % _world.flights.state_of("GA1"))
	assert_bool(_world.flights.has_moving_flight()).is_true()
	assert_bool(_quiet.is_quiet()).is_false()


func test_nothing_due_never_fast_forwards() -> void:
	# A world whose only flight has departed: quiet, but no event to stop at.
	var grid := PassengerTestWorld.floored(Vector2i(8, 6))
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	var quiet := auto_free(QuietNight.new()) as QuietNight
	quiet.bind(world.clock, world.flights, world.sim)
	world.flights.open_airport()
	world.run_to(FlightSim.schedule_starts(0)[FlightSim.State.DEPARTED])
	var state := world.flights.state_of(PassengerTestWorld.FLIGHT)
	print("state=%d next=%d" % [state, world.flights.next_event_tick()])
	assert_int(state).is_equal(FlightSim.State.DEPARTED)
	assert_bool(quiet.is_quiet()).is_true()
	assert_int(world.flights.next_event_tick()).is_equal(-1)
	assert_int(quiet.stop_tick()).is_equal(-1)
	var before_frame := world.clock.tick
	world.clock.advance(FRAME)
	assert_bool(world.clock.is_fast_forwarding()).is_false()
	assert_int(world.clock.tick - before_frame).is_less_equal(1)


func test_the_clock_fast_forwards_to_the_stop_and_stays_at_player_speed_after() -> void:
	_world.flights.open_airport()
	_world.clock.set_speed(2)
	var frames := 0
	while _world.clock.tick < _expected_stop():
		_world.clock.advance(FRAME)
		frames += 1
		if _world.clock.tick < _expected_stop():
			assert_bool(_world.clock.is_fast_forwarding()).is_true()
	print("stop=%d tick=%d frames=%d" % [_expected_stop(), _world.clock.tick, frames])
	assert_int(_world.clock.tick).is_equal(_expected_stop())
	var fewest := _expected_stop() / float(SimClock.MAX_STEPS_PER_FRAME)
	assert_float(float(frames)).is_less(fewest + 2.0)
	# Inside the lead window the airport is still quiet, but nothing restarts it.
	var event := _expected_stop() + QuietNight.LEAD_TICKS
	while _world.clock.tick < event:
		var before_frame := _world.clock.tick
		_world.clock.advance(FRAME)
		assert_bool(_world.clock.is_fast_forwarding()).is_false()
		assert_int(_world.clock.tick - before_frame).is_less_equal(1)
	assert_int(_world.clock.speed).is_equal(2)


func test_a_build_hold_stops_it_and_gives_back_the_held_speed() -> void:
	_world.flights.open_airport()
	_world.clock.set_speed(3)
	_world.clock.advance(FRAME)
	assert_bool(_world.clock.is_fast_forwarding()).is_true()
	var session := auto_free(BuildSession.new()) as BuildSession
	session.clock = _world.clock
	session.set_building(true)
	session.sync()
	assert_bool(_world.clock.paused).is_true()
	assert_bool(_quiet.is_quiet()).is_false()
	var held := _world.clock.tick
	_world.clock.advance(FRAME)
	assert_int(_world.clock.tick).is_equal(held)
	assert_bool(_world.clock.is_fast_forwarding()).is_false()
	# The hold ends with the player's own clock: running, at 3x.
	session.set_building(false)
	assert_bool(_world.clock.paused).is_false()
	assert_int(_world.clock.speed).is_equal(3)
	_world.clock.advance(FRAME)
	assert_bool(_world.clock.is_fast_forwarding()).is_true()
	assert_int(_world.clock.speed).is_equal(3)
