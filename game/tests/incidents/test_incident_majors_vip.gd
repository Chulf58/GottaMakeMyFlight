class_name TestIncidentMajorsVip
extends MajorTestBase
## The VIP incident (IncidentMajors, board 03e71ed7): the offer names a flight not
## yet issued; accepted, the first passenger spawned for that flight is marked;
## a good arrival pays the bonus once, a bad mood changes nothing, a miss adds a
## rating penalty once, and a flight that leaves unmarked drops the VIP.


func test_a_vip_offer_names_a_flight_not_yet_issued_and_marks_nobody_until_accepted() -> void:
	var incident := _presented_major(IncidentCatalogue.VIP)
	var plan: Dictionary = incident["plan"]
	assert_str(incident["state"]).is_equal(IncidentCatalogue.OFFERED)
	assert_int(_world.flights.state_of(plan["flight"])).is_less(0)
	assert_int(plan["target"]).is_equal(0)
	assert_bool(_director.answer(incident["id"], true)).is_true()
	assert_str(_record(incident["id"])["state"]).is_equal(IncidentCatalogue.ACCEPTED)
	assert_int(_record(incident["id"])["plan"]["target"]).is_equal(0)


func test_the_first_passenger_spawned_for_the_vip_flight_is_marked() -> void:
	var id := _accepted_vip(VIP_FLIGHT)
	var other := _world.sim.spawn_now(OTHER_FLIGHT)
	assert_int(_record(id)["plan"]["target"]).is_equal(0)
	var first := _world.sim.spawn_now(VIP_FLIGHT)
	var second := _world.sim.spawn_now(VIP_FLIGHT)
	print(
		(
			"other %d first %d second %d marked %d"
			% [other, first, second, _record(id)["plan"]["target"]]
		)
	)
	assert_int(_record(id)["plan"]["target"]).is_equal(first)
	assert_int(first).is_not_equal(other)
	assert_int(first).is_not_equal(second)


func test_a_vip_who_makes_it_in_a_good_mood_earns_the_bonus_once() -> void:
	var id := _accepted_vip(VIP_FLIGHT)
	var vip := _world.sim.spawn_now(VIP_FLIGHT)
	var p := _world.sim.get_passenger(vip)
	p.mood = IncidentTuning.VIP_GOOD_MOOD
	var before := _balance()
	var made := _world.sim.made_count()
	PassengerLifecycle.finish(_world.sim, p, true)
	assert_int(_balance()).is_equal(before + IncidentTuning.VIP_BONUS_MONEY)
	assert_str(_record(id)["outcome"]).is_equal(IncidentMajors.BONUS)
	# The ordinary outcome is the sim's own, counted once; the director adds none.
	assert_int(_world.sim.made_count()).is_equal(made + 1)
	assert_array(_rating.active_adjustments()).is_empty()
	_world.sim.outcome.emit(vip, true)
	assert_int(_balance()).is_equal(before + IncidentTuning.VIP_BONUS_MONEY)


func test_a_vip_who_makes_it_in_a_bad_mood_changes_nothing() -> void:
	var id := _accepted_vip(VIP_FLIGHT)
	var vip := _world.sim.spawn_now(VIP_FLIGHT)
	var p := _world.sim.get_passenger(vip)
	p.mood = IncidentTuning.VIP_GOOD_MOOD - 1
	var before := _balance()
	PassengerLifecycle.finish(_world.sim, p, true)
	assert_int(_balance()).is_equal(before)
	assert_array(_rating.active_adjustments()).is_empty()
	assert_str(_record(id)["outcome"]).is_equal(IncidentMajors.NEUTRAL)


func test_a_vip_who_misses_the_flight_adds_a_rating_penalty_once() -> void:
	var id := _accepted_vip(VIP_FLIGHT)
	var vip := _world.sim.spawn_now(VIP_FLIGHT)
	var other := _world.sim.spawn_now(VIP_FLIGHT)
	var before := _balance()
	var missed := _world.sim.missed_count()
	PassengerLifecycle.finish(_world.sim, _world.sim.get_passenger(other), false)
	assert_array(_rating.active_adjustments()).is_empty()
	PassengerLifecycle.finish(_world.sim, _world.sim.get_passenger(vip), false)
	_world.sim.outcome.emit(vip, false)
	var adjustments := _rating.active_adjustments()
	print("adjustments: %s" % [adjustments])
	assert_int(adjustments.size()).is_equal(1)
	assert_int(adjustments[0]["half_star_delta"]).is_equal(-IncidentTuning.VIP_MISS_HALF_STARS)
	assert_int(_balance()).is_equal(before)
	assert_int(_world.sim.missed_count()).is_equal(missed + 2)
	assert_str(_record(id)["outcome"]).is_equal(IncidentMajors.PENALTY)


func test_a_vip_whose_flight_leaves_unmarked_is_dropped() -> void:
	var id := _accepted_vip(VIP_FLIGHT)
	var closed := _world.flights.state_start(VIP_FLIGHT, FlightSim.State.PUSHBACK)
	_world.run_to(closed + 1)
	assert_bool(_world.flights.is_doors_closed(VIP_FLIGHT)).is_true()
	assert_str(_record(id)["outcome"]).is_equal(IncidentMajors.NOT_HELD)
