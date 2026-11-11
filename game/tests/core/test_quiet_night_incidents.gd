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


func test_on_incidents_stop_ahead_of_the_next_day_boundary() -> void:
	_director.set_enabled(true)
	var boundary := GameCalendar.day_start(1)
	print("stop=%d boundary=%d flight stop=%d" % [_quiet.stop_tick(), boundary, _flight_stop()])
	assert_int(boundary).is_less(_flight_stop())
	assert_int(_quiet.stop_tick()).is_equal(boundary - QuietNight.LEAD_TICKS)
