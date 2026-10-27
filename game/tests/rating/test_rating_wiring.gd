class_name TestRatingWiring
extends GdUnitTestSuite
## The rating hears the real sims: each passenger's outcome with the mood they
## leave with, and a closed flight's no-shows, recorded before FlightSim and
## PassengerSim prune what they know about the flight.

var _world: PassengerTestWorld
var _rating: AirportRating
var _made_moods: Array[int] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_made_moods.clear()


func after_test() -> void:
	if _world != null:
		_world.free_all()
	_world = null
	_rating = null


func _on_outcome(id: int, made: bool) -> void:
	if made:
		_made_moods.append(_world.sim.get_passenger(id).mood)


func _bind(world: PassengerTestWorld) -> void:
	_world = world
	_rating = auto_free(AirportRating.new()) as AirportRating
	_rating.bind(world.clock, world.flights, world.sim)
	world.sim.outcome.connect(_on_outcome)


## A floored room with no entrance: every scheduled passenger is a no-show.
func _room_without_entrance() -> PassengerTestWorld:
	var grid := PassengerTestWorld.floored(Vector2i(8, 6))
	return PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(10, 20))


func test_outcomes_are_recorded_with_the_mood_at_exit() -> void:
	_bind(PassengerTestWorld.reference_world(3))
	_world.sim.schedule_flight(PassengerTestWorld.FLIGHT, 8)
	_world.run_to(1900 + 5)
	var parts := _rating.parts()
	assert_int(_world.sim.made_count()).is_greater(0)
	assert_int(parts["made"]).is_equal(_world.sim.made_count())
	assert_int(parts["missed"]).is_equal(_world.sim.missed_count())
	var expected := 0
	for mood in _made_moods:
		expected += mood
	assert_int(_made_moods.size()).is_equal(parts["made"])
	assert_int(_rating.day_totals(0)["mood_sum"]).is_equal(expected)


func test_no_shows_are_counted_as_missed_one_tick_after_the_doors_close() -> void:
	_bind(_room_without_entrance())
	_world.sim.schedule_flight(PassengerTestWorld.FLIGHT, 5)
	# The doors close on tick 20; PassengerSim finalizes the no-shows that tick.
	_world.run_to(20)
	assert_int(_world.sim.no_shows[PassengerTestWorld.FLIGHT]["no_entrance"]).is_equal(5)
	assert_int(_rating.parts()["missed"]).is_equal(0)
	_world.run_to(21)
	assert_int(_rating.parts()["missed"]).is_equal(5)
	assert_int(_rating.parts()["made"]).is_equal(0)
	assert_float(_rating.stars()).is_equal(1.0)
	assert_bool(_rating.warning()).is_true()
	# Later ticks add nothing more.
	_world.run_to(400)
	assert_int(_rating.parts()["missed"]).is_equal(5)


func test_the_rating_keeps_its_numbers_after_the_sims_prune_the_flight() -> void:
	_bind(_room_without_entrance())
	_world.sim.schedule_flight(PassengerTestWorld.FLIGHT, 5)
	_world.run_to(21)
	var before := _rating.parts()
	assert_int(before["missed"]).is_equal(5)
	_world.sim.no_shows.clear()
	_world.sim.flight_results.clear()
	_world.run_to(200)
	assert_dict(_rating.parts()).is_equal(before)


func test_a_flight_with_nobody_booked_leaves_the_rating_without_data() -> void:
	_bind(_room_without_entrance())
	_world.run_to(30)
	assert_bool(_rating.has_data()).is_false()
	assert_float(_rating.stars()).is_equal(RatingFormula.STARTING_STARS)


func test_pending_flights_survive_a_save_taken_on_the_closing_tick() -> void:
	_bind(_room_without_entrance())
	_world.sim.schedule_flight(PassengerTestWorld.FLIGHT, 5)
	_world.run_to(20)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(_rating.to_snapshot()))
	assert_int((saved["pending"] as Array).size()).is_equal(1)
	var other := auto_free(AirportRating.new()) as AirportRating
	assert_bool(other.from_snapshot(saved)).is_true()
	other.bind(_world.clock, _world.flights, _world.sim)
	_world.run_to(21)
	assert_int(other.parts()["missed"]).is_equal(5)
