class_name TestFlightFitCache
extends GdUnitTestSuite
## The day plans FlightSim caches, live (_day_plans) and for trials
## (_trial_day_plans), describe the world as it is now: opening the airport
## moves contracts' start days and so empties both caches, and days that have
## passed leave the trial cache as they leave the live one.


func _closed_sim() -> FlightSim:
	var sim := auto_free(FlightSim.new()) as FlightSim
	sim.gate_source = func() -> Array[String]: return ["C", "D"] as Array[String]
	return sim


## Accepts 08:20 and 14:20 while closed, so their first day is day 0 until the
## opening at tick 0 (06:00) moves 08:20 to day 1: its day-0 issue time passed.
func _accept_closed(sim: FlightSim) -> void:
	assert_bool(sim.accept_contract(TestFlightFit.terms("K0820", 500))).is_true()
	assert_bool(sim.accept_contract(TestFlightFit.terms("K1420", 860))).is_true()


## A cache warmed while closed answers exactly as a cold one after the opening:
## the day-0 plans, the assessment and accept_problem. Control: the opening did
## change the day-0 plan, so a stale cache would show.
func test_opening_the_airport_empties_the_warm_day_plan_caches() -> void:
	var offer := TestFlightFit.terms("X", 700)
	var warm := _closed_sim()
	_accept_closed(warm)
	var closed_assessment := FlightFit.assess(warm, offer)
	var closed_problem := warm.accept_problem(offer)
	var closed_plan := warm._day_plan(0).duplicate(true)
	warm._trial_day_plan(0)
	assert_bool(warm.open_airport()).is_true()
	var cold := _closed_sim()
	_accept_closed(cold)
	assert_bool(cold.open_airport()).is_true()
	print(
		(
			"closed day 0 plans %s, open day 0 plans %s"
			% [closed_plan.keys(), cold._day_plan(0).keys()]
		)
	)
	assert_dict(cold._day_plan(0)).is_not_equal(closed_plan)
	assert_dict(warm._day_plan(0)).is_equal(cold._day_plan(0))
	assert_dict(warm._trial_day_plan(0)).is_equal(cold._trial_day_plan(0))
	assert_dict(FlightFit.assess(warm, offer)).is_equal(FlightFit.assess(cold, offer))
	assert_str(warm.accept_problem(offer)).is_equal(cold.accept_problem(offer))
	print("closed: %s '%s'" % [closed_assessment, closed_problem])


## Ten days of ticking with a daily contract and a trial each day, revision
## unchanged: the trial cache holds only today's and later days.
func test_the_trial_day_plan_cache_drops_past_days() -> void:
	var sim := _closed_sim()
	assert_bool(sim.open_airport()).is_true()
	assert_bool(sim.accept_contract(TestFlightFit.terms("K1000", 600))).is_true()
	var revision := sim._revision
	var largest := 0
	for day in range(1, 11):
		for hour in 24:
			sim.on_tick(GameCalendar.day_start(day) + hour * 60 * GameCalendar.TICKS_PER_MINUTE)
		FlightFit.assess(sim, TestFlightFit.terms("X", 900))
		largest = maxi(largest, sim._trial_day_plans.size())
		for cached: int in sim._trial_day_plans:
			assert_int(cached).is_greater_equal(day)
	print("trial cache at most %d days; revision %d -> %d" % [largest, revision, sim._revision])
	assert_int(sim._revision).is_equal(revision)
	assert_int(largest).is_greater(0)
	assert_int(largest).is_less_equal(3)
