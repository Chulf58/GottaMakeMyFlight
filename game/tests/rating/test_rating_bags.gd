class_name TestRatingBags
extends GdUnitTestSuite
## Missed bags lower the rating (Baggage B4, decision baggage-rides-a-player-
## built-belt-from-check-in-to-a-bag-roo): every settled bag is recorded on the
## day it settles, in the same three-day window as the passengers.

var _world: PassengerTestWorld
var _bags: BaggageSim
var _rating: AirportRating


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
	_world = null
	_bags = null
	_rating = null


func _fed() -> AirportRating:
	var rating := auto_free(AirportRating.new()) as AirportRating
	for i in 10:
		rating.record_passenger(_noon(0), true, 100)
	return rating


func _noon(day: int) -> int:
	return GameCalendar.tick_at(day, 12 * 60)


## The reference terminal with a ready bag room but no belts, so every bag
## misses at its cutoff.
func _bind_world(with_room := true) -> void:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	if with_room:
		BagRoomKit.add(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), 3)
	_bags = auto_free(BaggageSim.new())
	_bags.bind(_world.clock, _world.flights, _world.grid, _world.sim)
	_rating = auto_free(AirportRating.new()) as AirportRating
	_rating.baggage = _bags
	_rating.bind(_world.clock, _world.flights, _world.sim)


func test_a_bag_is_recorded_on_the_day_it_settles() -> void:
	var rating := _fed()
	rating.record_bag(_noon(1), false)
	rating.record_bag(_noon(1), true)
	assert_int(rating.day_totals(1)["bags"]).is_equal(2)
	assert_int(rating.day_totals(1)["bags_missed"]).is_equal(1)
	assert_int(rating.day_totals(0)["bags"]).is_equal(0)
	var parts := rating.parts()
	assert_int(parts["bags"]).is_equal(2)
	assert_int(parts["bags_missed"]).is_equal(1)
	assert_float(parts["bags_missed_share"]).is_equal(0.5)


func test_recording_a_bag_tells_the_hud_the_rating_changed() -> void:
	var rating := _fed()
	var changes := [0]
	rating.changed.connect(func() -> void: changes[0] += 1)
	rating.record_bag(_noon(0), true)
	assert_int(changes[0]).is_equal(1)


func test_missed_bags_lower_the_stars_and_loaded_bags_do_not() -> void:
	var rating := _fed()
	assert_float(rating.stars()).is_equal(5.0)
	for i in 10:
		rating.record_bag(_noon(0), true)
	assert_float(rating.stars()).is_equal(5.0)
	var missed := _fed()
	for i in 10:
		missed.record_bag(_noon(0), false)
	assert_float(missed.stars()).is_equal(4.0)
	assert_float(missed.stars()).is_less(rating.stars())


func test_a_missed_bag_ages_out_of_the_three_day_window() -> void:
	var rating := _fed()
	for i in 10:
		rating.record_bag(_noon(0), false)
	assert_float(rating.stars()).is_equal(4.0)
	rating.on_tick(_noon(3))
	assert_int(rating.parts()["bags"]).is_equal(0)
	assert_bool(rating.day_totals(0)["bags"] == 0).is_true()


func test_bags_pool_across_the_window_like_passengers() -> void:
	var rating := _fed()
	rating.record_bag(_noon(0), false)
	rating.record_bag(_noon(2), true)
	rating.record_bag(_noon(2), true)
	rating.record_bag(_noon(2), true)
	var parts := rating.parts()
	assert_int(parts["bags"]).is_equal(4)
	assert_int(parts["bags_missed"]).is_equal(1)


func test_the_rating_hears_the_bag_sim_and_counts_each_bag_once() -> void:
	_bind_world()
	_rating.bind(_world.clock, _world.flights, _world.sim)
	_world.sim.schedule_flight(PassengerTestWorld.FLIGHT, 8)
	_world.run_to(1900 + 5)
	var settled := _bags.loaded_total + _bags.missed_total
	print("bags settled %d missed %d" % [settled, _bags.missed_total])
	assert_int(_bags.missed_total).is_greater(0)
	var parts := _rating.parts()
	assert_int(parts["bags"]).is_equal(settled)
	assert_int(parts["bags_missed"]).is_equal(_bags.missed_total)


func test_with_no_bag_room_no_bag_is_checked_in_and_the_rating_is_not_marked_down() -> void:
	_bind_world(false)
	_world.sim.schedule_flight(PassengerTestWorld.FLIGHT, 8)
	_world.run_to(1900 + 5)
	assert_int(_world.sim.made_count()).is_greater(0)
	assert_array(_bags.bag_ids()).is_empty()
	var parts := _rating.parts()
	assert_int(parts["bags"]).is_equal(0)
	assert_int(parts["bags_missed"]).is_equal(0)
	assert_float(parts["bags_missed_share"]).is_equal(0.0)
	var control := RatingFormula.stars(
		parts["made"], parts["missed"], _rating.day_totals(0)["mood_sum"]
	)
	assert_float(_rating.stars()).is_equal(control)


func test_a_bag_sim_set_after_the_first_bind_is_heard_on_the_next_bind() -> void:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	BagRoomKit.add(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), 3)
	_rating = auto_free(AirportRating.new()) as AirportRating
	_rating.bind(_world.clock, _world.flights, _world.sim)
	_bags = auto_free(BaggageSim.new())
	_bags.bind(_world.clock, _world.flights, _world.grid, _world.sim)
	_rating.baggage = _bags
	_rating.bind(_world.clock, _world.flights, _world.sim)
	_world.sim.schedule_flight(PassengerTestWorld.FLIGHT, 4)
	_world.run_to(1900 + 5)
	assert_int(_bags.missed_total).is_greater(0)
	assert_int(_rating.parts()["bags_missed"]).is_equal(_bags.missed_total)


func test_a_rating_without_a_bag_sim_records_no_bags() -> void:
	_world = PassengerTestWorld.reference_world(3)
	_rating = auto_free(AirportRating.new()) as AirportRating
	_rating.bind(_world.clock, _world.flights, _world.sim)
	_world.sim.schedule_flight(PassengerTestWorld.FLIGHT, 4)
	_world.run_to(1900 + 5)
	assert_int(_rating.parts()["bags"]).is_equal(0)


func test_bags_survive_a_json_round_trip() -> void:
	var rating := _fed()
	for i in 4:
		rating.record_bag(_noon(0), i < 1)
	var other := auto_free(AirportRating.new()) as AirportRating
	var data := JSON.parse_string(JSON.stringify(rating.to_snapshot())) as Dictionary
	assert_bool(other.from_snapshot(data)).is_true()
	assert_int(other.parts()["bags"]).is_equal(4)
	assert_int(other.parts()["bags_missed"]).is_equal(3)
	assert_float(other.stars()).is_equal(rating.stars())
	assert_str(JSON.stringify(other.to_snapshot())).is_equal(JSON.stringify(rating.to_snapshot()))


func test_a_save_from_before_bags_loads_with_no_bags() -> void:
	var rating := _fed()
	var data := JSON.parse_string(JSON.stringify(rating.to_snapshot())) as Dictionary
	for entry in data["days"]:
		entry.erase("bags")
		entry.erase("bags_missed")
	var other := auto_free(AirportRating.new()) as AirportRating
	assert_bool(other.from_snapshot(data)).is_true()
	assert_int(other.parts()["bags"]).is_equal(0)
	assert_float(other.stars()).is_equal(rating.stars())


func test_bad_bag_counts_in_a_snapshot_are_refused() -> void:
	var rating := _fed()
	rating.record_bag(_noon(0), false)
	var good := JSON.parse_string(JSON.stringify(rating.to_snapshot())) as Dictionary
	var cases := {
		"only bags": func(d): d["days"][0].erase("bags_missed"),
		"only bags missed": func(d): d["days"][0].erase("bags"),
		"more missed than bags": func(d): d["days"][0]["bags_missed"] = 2,
		"negative bags": func(d): d["days"][0]["bags"] = -1,
		"fractional bags": func(d): d["days"][0]["bags"] = 1.5,
		"huge bags": func(d): d["days"][0]["bags"] = RatingFormula.MAX_DAY_COUNT + 1,
		"string bags": func(d): d["days"][0]["bags"] = "1",
	}
	var other := auto_free(AirportRating.new()) as AirportRating
	var before := JSON.stringify(other.to_snapshot())
	for name in cases:
		var data: Dictionary = good.duplicate(true)
		cases[name].call(data)
		assert_bool(other.from_snapshot(data)).override_failure_message(name).is_false()
		assert_str(JSON.stringify(other.to_snapshot())).override_failure_message(name).is_equal(
			before
		)
	assert_bool(other.from_snapshot(good)).is_true()
