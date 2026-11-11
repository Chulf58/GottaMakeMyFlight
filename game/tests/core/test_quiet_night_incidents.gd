class_name TestQuietNightIncidents
extends GdUnitTestSuite
## The quiet-night stop also comes LEAD_TICKS before the incidents' next event
## (IncidentDirector.next_event_tick): a scheduled spill's fire tick, or the
## next day boundary while incidents are on. Off, only the flights count.

## The one-off flight's first state: after day 1 starts (tick 21600), so the
## day boundary comes first.
const FIRST := 30_000
const FRAME := 1.0 / 60.0

var _world: PassengerTestWorld
var _director: IncidentDirector
var _quiet: QuietNight


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(8, 6))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 5), 3)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(FIRST))
	_director = auto_free(IncidentDirector.new()) as IncidentDirector
	_director.bind(_world.clock, _world.flights, _world.sim)
	_quiet = auto_free(QuietNight.new()) as QuietNight
	_quiet.bind(_world.clock, _world.flights, _world.sim, _director)
	_world.flights.open_airport()


func after_test() -> void:
	_world.free_all()


func _flight_stop() -> int:
	return FlightSim.schedule_starts(FIRST)[FlightSim.State.APPROACH] - QuietNight.LEAD_TICKS


## A scheduled spill as a roll leaves it, put in through the save path.
func _schedule_spill(fire_tick: int) -> void:
	var data := _director.to_snapshot()
	data["next_id"] = 2
	data["incidents"] = [
		{
			"id": 1,
			"kind": IncidentCatalogue.SPILL,
			"roll_day": 0,
			"state": IncidentCatalogue.SCHEDULED,
			"fire_tick": fire_tick,
			"cell": [-1, -1],
			"mess_id": 0,
			"place": "",
		}
	]
	assert_bool(_director.from_snapshot(data)).is_true()


func test_off_incidents_leave_the_flight_stop() -> void:
	print("stop=%d flight stop=%d" % [_quiet.stop_tick(), _flight_stop()])
	assert_int(_quiet.stop_tick()).is_equal(_flight_stop())


func test_the_stop_comes_before_a_spill_fire_ahead_of_the_flight() -> void:
	var fire := 6000
	_schedule_spill(fire)
	print("stop=%d fire=%d flight stop=%d" % [_quiet.stop_tick(), fire, _flight_stop()])
	assert_int(_quiet.stop_tick()).is_equal(fire - QuietNight.LEAD_TICKS)
	# The clock fast-forwards to that stop and no further.
	_world.clock.set_speed(3)
	while _world.clock.tick < fire - QuietNight.LEAD_TICKS:
		_world.clock.advance(FRAME)
	assert_int(_world.clock.tick).is_equal(fire - QuietNight.LEAD_TICKS)
	_world.clock.advance(FRAME)
	assert_bool(_world.clock.is_fast_forwarding()).is_false()


## Fast-forwards frame by frame until the clock passes `until`, and asserts that
## every frame from `from` on ran fast: a slow frame at 1x moves at most 1 tick.
func _fast_through(from: int, until: int) -> int:
	var frames := 0
	while _world.clock.tick < until:
		var before_frame := _world.clock.tick
		_world.clock.advance(FRAME)
		if before_frame >= from and _world.clock.tick < until:
			frames += 1
			assert_bool(_world.clock.is_fast_forwarding()).is_true()
			assert_int(_world.clock.tick - before_frame).is_greater(1)
	return frames


## With incidents on and nothing rolled, midnight is no stop: the night runs
## fast straight through 23:50 and on to the flight's stop.
func test_on_incidents_fast_forward_straight_through_midnight() -> void:
	_director.set_enabled(true)
	var boundary := GameCalendar.day_start(1)
	assert_int(boundary).is_less(_flight_stop())
	assert_int(_quiet.stop_tick()).is_equal(_flight_stop())
	var frames := _fast_through(boundary - 2 * QuietNight.LEAD_TICKS, boundary + 400)
	print("fast frames around midnight=%d tick=%d" % [frames, _world.clock.tick])
	# 800 ticks at MAX_STEPS_PER_FRAME (10) a frame, less the frame at each end.
	assert_int(frames).is_greater_equal(78)
	assert_int(_director.last_rolled_day()).is_equal(1)
	assert_int(_quiet.stop_tick()).is_equal(_flight_stop())


## A spill rolled at that midnight with the earliest fire tick the floor allows
## still gets its full lead: the fast-forward runs on after midnight and stops
## exactly LEAD_TICKS before the fire.
func test_a_spill_rolled_at_midnight_still_stops_lead_before_its_fire() -> void:
	var director := auto_free(FloorWindow.new()) as IncidentDirector
	director.bind(_world.clock, _world.flights, _world.sim)
	director.set_enabled(true)
	director.forced_kind = IncidentCatalogue.SPILL
	_quiet.bind(_world.clock, _world.flights, _world.sim, director)
	var boundary := GameCalendar.day_start(1)
	_fast_through(boundary - 2 * QuietNight.LEAD_TICKS, boundary)
	var rolled := director.incidents()
	assert_int(rolled.size()).is_equal(1)
	var fire: int = rolled[0]["fire_tick"]
	print("boundary=%d fire=%d tick=%d" % [boundary, fire, _world.clock.tick])
	assert_int(fire).is_equal(boundary + IncidentDirector.FIRE_FLOOR_TICKS)
	# The frame that crossed midnight cannot have reached the stop yet.
	assert_int(_world.clock.tick).is_less(fire - QuietNight.LEAD_TICKS)
	_fast_through(boundary, fire - QuietNight.LEAD_TICKS)
	assert_int(_world.clock.tick).is_equal(fire - QuietNight.LEAD_TICKS)
	_world.clock.advance(FRAME)
	assert_bool(_world.clock.is_fast_forwarding()).is_false()


## A director whose busy window is the earliest its floor allows, whatever the
## flights: the worst case for the quiet-night stop.
class FloorWindow:
	extends IncidentDirector

	func busy_window(_day: int, now: int) -> Vector2i:
		var at := now + IncidentDirector.FIRE_FLOOR_TICKS
		return Vector2i(at, at)
