class_name TestIncidentMajors
extends MajorTestBase
## What the inspector, the holiday rush and the airline favour do (IncidentMajors,
## board 03e71ed7). The inspector pays INCIDENT money on a pass and adds a
## rating penalty on a fail; the rush books capped extra passengers on
## tomorrow's flights and its card says the same counts; the favour stays within
## the flight's headroom; a declined offer changes nothing; and the director
## never draws from SimClock.rng. The VIP is TestIncidentMajorsVip's.


func test_an_inspector_is_announced_a_day_ahead_with_a_visit_inside_the_window() -> void:
	var incident := _presented_major(IncidentCatalogue.INSPECTOR)
	var plan: Dictionary = incident["plan"]
	print("inspector plan: %s" % [plan])
	assert_str(incident["state"]).is_equal(IncidentCatalogue.ANNOUNCED)
	assert_int(_presented.size()).is_equal(1)
	assert_int(GameCalendar.day_of(plan["visit_tick"])).is_equal(2)
	assert_int(plan["visit_tick"]).is_between(plan["window_from"], plan["window_to"])
	assert_int(_director.next_event_tick(0)).is_equal(plan["visit_tick"])


func test_an_inspector_pass_pays_incident_money_and_costs_no_rating() -> void:
	var incident := _presented_major(IncidentCatalogue.INSPECTOR)
	var before := _balance()
	var credited: Array[int] = []
	_world.sim.wallet.transaction.connect(
		func(amount: int, category: int, _claimed: Dictionary, _tick: int) -> void:
			if category == Wallet.Category.INCIDENT:
				credited.append(amount)
	)
	_director.on_tick(incident["plan"]["visit_tick"])
	print("balance %d -> %d, incident credits %s" % [before, _balance(), credited])
	assert_int(_balance()).is_equal(before + IncidentTuning.INSPECTOR_PASS_MONEY)
	assert_array(credited).is_equal([IncidentTuning.INSPECTOR_PASS_MONEY])
	assert_str(_record(incident["id"])["outcome"]).is_equal(IncidentMajors.PASSED)
	assert_str(_record(incident["id"])["state"]).is_equal(IncidentCatalogue.DONE)
	assert_array(_rating.active_adjustments()).is_empty()


func test_an_inspector_fail_for_messes_adds_a_rating_penalty_and_pays_nothing() -> void:
	var incident := _presented_major(IncidentCatalogue.INSPECTOR)
	_add_messes(IncidentTuning.INSPECTOR_MAX_MESSES + 1)
	var before := _balance()
	var visit: int = incident["plan"]["visit_tick"]
	_director.on_tick(visit)
	var adjustments := _rating.active_adjustments()
	print("adjustments: %s" % [adjustments])
	assert_int(_balance()).is_equal(before)
	assert_int(adjustments.size()).is_equal(1)
	assert_int(adjustments[0]["half_star_delta"]).is_equal(
		-IncidentTuning.INSPECTOR_FAIL_HALF_STARS
	)
	assert_int(adjustments[0]["outcome_tick"]).is_equal(visit)
	assert_str(_record(incident["id"])["outcome"]).is_equal(IncidentMajors.FAILED)


func test_an_inspector_fail_for_a_full_queue_and_the_visit_scores_only_once() -> void:
	var incident := _presented_major(IncidentCatalogue.INSPECTOR)
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.sim.get_passenger(id).stuck = Passenger.Stuck.QUEUE_FULL
	var visit: int = incident["plan"]["visit_tick"]
	_director.on_tick(visit)
	_director.on_tick(visit + 1)
	_director.on_tick(visit + 100)
	assert_int(_rating.active_adjustments().size()).is_equal(1)
	assert_str(_record(incident["id"])["outcome"]).is_equal(IncidentMajors.FAILED)


func test_the_inspector_penalty_is_inside_the_rating_limits() -> void:
	assert_int(IncidentTuning.INSPECTOR_FAIL_HALF_STARS).is_between(
		1, RatingAdjustments.MAX_HALF_STAR_DELTA
	)
	assert_int(IncidentTuning.VIP_MISS_HALF_STARS).is_between(
		1, RatingAdjustments.MAX_HALF_STAR_DELTA
	)


func test_a_rush_books_capped_extra_passengers_and_the_card_says_the_same_counts() -> void:
	var incident := _presented_major(IncidentCatalogue.RUSH)
	var plan: Dictionary = incident["plan"]
	print("rush plan: %s" % [plan])
	assert_str(incident["state"]).is_equal(IncidentCatalogue.ANNOUNCED)
	var booked := 0
	for flight: Dictionary in plan["flights"]:
		assert_int(GameCalendar.day_of(flight["departs"])).is_equal(2)
		assert_int(flight["extra"]).is_equal(_world.sim.booking_override_of(flight["flight"]))
		assert_int(flight["extra"]).is_between(1, mini(IncidentTuning.RUSH_EXTRA, HEADROOM))
		booked += flight["extra"]
	# Capped by the plane class maximum: 6 were asked, 4 fit.
	assert_int(booked).is_equal(HEADROOM)
	assert_int(plan["total"]).is_equal(booked)
	var words := IncidentCopy.fill(
		IncidentCatalogue.panel_copy("rush"), incident, _world.clock.tick
	)
	var text: String = words["body"]
	assert_str(text).contains("%d extra passengers" % plan["total"])
	assert_str(text).contains("08:00 +%d" % HEADROOM)
	assert_str(text).contains("Reward:")
	assert_str(text).contains("If it fails:")
	assert_int(_world.sim.booking_override_of("AM-d1")).is_equal(0)


func test_a_rush_ends_after_its_day_and_never_books_twice() -> void:
	var incident := _presented_major(IncidentCatalogue.RUSH)
	var plan: Dictionary = incident["plan"]
	_director.on_tick(plan["until"] - 1)
	assert_str(_record(incident["id"])["state"]).is_equal(IncidentCatalogue.ANNOUNCED)
	_director.on_tick(plan["until"])
	assert_str(_record(incident["id"])["state"]).is_equal(IncidentCatalogue.DONE)
	assert_int(_world.sim.booking_override_of(plan["flights"][0]["flight"])).is_equal(HEADROOM)


func test_a_favour_offer_names_extra_passengers_within_the_headroom() -> void:
	var incident := _presented_major(IncidentCatalogue.FAVOUR)
	var plan: Dictionary = incident["plan"]
	print("favour plan: %s" % [plan])
	assert_str(incident["state"]).is_equal(IncidentCatalogue.OFFERED)
	assert_int(plan["extra"]).is_equal(HEADROOM)
	assert_bool(IncidentTuning.FAVOUR_EXTRA > HEADROOM).is_true()
	assert_int(_world.sim.booking_override_of(plan["flight"])).is_equal(0)
	var copy := IncidentCopy.fill(
		IncidentCatalogue.panel_copy("favour"), incident, _world.clock.tick
	)
	assert_str(copy["body"]).contains("%d more passengers" % HEADROOM)
	assert_str(copy["reward"]).contains("%d money" % IncidentTuning.FAVOUR_BONUS_MONEY)
	assert_str(copy["failure"]).contains("lower your rating")


func test_accepting_a_favour_books_the_passengers_and_pays_once() -> void:
	var incident := _presented_major(IncidentCatalogue.FAVOUR)
	var plan: Dictionary = incident["plan"]
	var before := _balance()
	assert_bool(_director.answer(incident["id"], true)).is_true()
	assert_bool(_director.answer(incident["id"], true)).is_false()
	assert_int(_world.sim.booking_override_of(plan["flight"])).is_equal(HEADROOM)
	assert_int(_balance()).is_equal(before + IncidentTuning.FAVOUR_BONUS_MONEY)
	assert_str(_record(incident["id"])["state"]).is_equal(IncidentCatalogue.DONE)
	assert_str(_record(incident["id"])["outcome"]).is_equal(IncidentMajors.APPLIED)


func test_declining_an_offer_has_no_effect() -> void:
	for kind in [IncidentCatalogue.FAVOUR, IncidentCatalogue.VIP]:
		var incident := _presented_major(kind)
		var before := _balance()
		var plan: Dictionary = incident["plan"]
		assert_bool(_director.answer(incident["id"], false)).is_true()
		assert_str(_record(incident["id"])["state"]).is_equal(IncidentCatalogue.DECLINED)
		assert_int(_balance()).is_equal(before)
		assert_int(_world.sim.booking_override_of(plan["flight"])).is_equal(0)
		assert_array(_rating.active_adjustments()).is_empty()
		# A fresh director for the next kind.
		_director = auto_free(IncidentDirector.new()) as IncidentDirector
		_director.rating = _rating
		_director.bind(_world.clock, _world.flights, _world.sim)


func test_the_majors_never_draw_from_the_clock_rng() -> void:
	var state := _world.clock.rng.state
	var start := _balance()
	var flight := ""
	for kind: String in [
		IncidentCatalogue.INSPECTOR, IncidentCatalogue.VIP, IncidentCatalogue.FAVOUR
	]:
		_director = auto_free(IncidentDirector.new()) as IncidentDirector
		_director.rating = _rating
		_director.bind(_world.clock, _world.flights, _world.sim)
		var incident := _presented_major(kind)
		assert_str(incident["state"]).is_not_equal(IncidentCatalogue.SCHEDULED)
		if IncidentCatalogue.is_offer(kind):
			_director.answer(incident["id"], true)
			flight = incident["plan"]["flight"]
		else:
			_director.on_tick(incident["plan"]["visit_tick"])
		assert_int(_world.clock.rng.state).is_equal(state)
	# The control: the majors did work (money paid, passengers booked) and the
	# clock's RNG stood still.
	print(
		(
			"balance %d -> %d, override %d"
			% [start, _balance(), _world.sim.booking_override_of(flight)]
		)
	)
	var paid := IncidentTuning.INSPECTOR_PASS_MONEY + IncidentTuning.FAVOUR_BONUS_MONEY
	assert_int(_balance()).is_equal(start + paid)
	assert_int(_world.sim.booking_override_of(flight)).is_equal(HEADROOM)
