class_name TestTaxiTimes
extends GdUnitTestSuite
## TaxiTimes, the taxi pair a gate's routes need (ruling taxi-time-follows-each-
## gate-s-route-length-far-side-gates-ta): max(1000, ceil20(1.875 D + 160)) in
## and max(920, ceil20(1.875 D + 160)) out. Every stand of the first site keeps
## exactly today's 1000 and 920, and the longest route the north lane can give
## on the whole site grid keeps the quiet night empty and the issue before the
## first state, so no distance cap is needed.

const SITE := preload("res://build/terminal_site.tres")


func test_base_is_today_s_phase_ticks_and_the_speed_factor_is_the_cap_s() -> void:
	assert_int(TaxiTimes.BASE[0]).is_equal(FlightSim.PHASE_TICKS[FlightSim.State.TAXI_IN])
	assert_int(TaxiTimes.BASE[1]).is_equal(FlightSim.PHASE_TICKS[FlightSim.State.TAXI_OUT])
	assert_float(TaxiTimes.TICKS_PER_M).is_equal_approx(1.5 / MovementPlan.MAX_PEAK_SPEED, 1e-9)
	assert_int(TaxiTimes.MAX_IN).is_equal(TaxiTimes.BASE[0] + FlightTimetable.ISSUE_LEAD_TICKS)
	assert_int(TaxiTimes.phase_ticks([1240, 1100])[FlightSim.State.TAXI_IN]).is_equal(1240)
	assert_int(TaxiTimes.phase_ticks([1240, 1100])[FlightSim.State.TAXI_OUT]).is_equal(1100)


## 448 m and 405 m are today's limits with the full pause; one metre more takes
## the next whole 20 ticks.
func test_the_formula_rounds_up_to_whole_steps_and_never_goes_below_base() -> void:
	var cases := [
		[0.0, 0.0, [1000, 920]],
		[448.0, 405.0, [1000, 920]],
		[449.0, 406.0, [1020, 940]],
		[573.1, 492.1, [1240, 1100]],
	]
	for case: Array in cases:
		var pair := TaxiTimes.for_lengths(case[0], case[1])
		print("%.1f m in, %.1f m out -> %s" % [case[0], case[1], pair])
		assert_array(pair).is_equal(case[2])
		assert_str(TaxiTimes.problem(pair)).is_empty()


func test_a_pair_outside_its_bounds_or_steps_is_refused() -> void:
	assert_str(TaxiTimes.problem([1000.0, 920.0])).is_empty()
	assert_str(TaxiTimes.problem([TaxiTimes.MAX_IN, TaxiTimes.MAX_OUT])).is_empty()
	for bad: Variant in [
		[980, 920],
		[1000, 900],
		[TaxiTimes.MAX_IN + 20, 920],
		[1000, TaxiTimes.MAX_OUT + 20],
		[1010, 920],
		[1000.5, 920],
		[1000],
		"1000 920",
	]:
		assert_str(TaxiTimes.problem(bad)).override_failure_message(str(bad)).is_not_empty()


## The stands test_airside_stand.gd checks the speed cap on: every corner of the
## first site's ground, from its north edge to its southmost wall line.
func test_every_stand_of_the_first_site_keeps_1000_and_920() -> void:
	var centre: Rect2 = SITE.centre_rect()
	var low := Vector2(centre.position.x, centre.position.y)
	var high := low + centre.size
	var engaged := 0.0
	for door_x in [low.x + 0.5, high.x - 0.5]:
		for wall_z in [low.y, high.y - 1.0]:
			var stand := StandPlacement.make(1, door_x, wall_z)
			var routes := FlightGround.routes(stand, PlaneClasses.SMALL)
			engaged = maxf(engaged, MovementPlan.path_length(routes[FlightSim.State.TAXI_IN]))
			assert_array(TaxiTimes.for_stand(stand)).is_equal(TaxiTimes.BASE)
	print("longest first-site taxi in: %.1f m" % engaged)
	assert_float(engaged).is_greater(400.0)
	assert_array(TaxiTimes.for_stand(FlightGround.scene_stand())).is_equal([1000, 920])


## Gate A of the test fallbacks stands 84 m west of the scene's stand, past the
## first site: its route in is 471 m (after main.tscn Stand moved 14 m south),
## so it taxis in 60 ticks longer.
func test_a_north_stand_past_the_first_site_taxis_longer() -> void:
	assert_array(TaxiTimes.for_stand(FlightGround.fallback("A")["stand"])).is_equal([1060, 920])
	assert_array(TaxiTimes.for_stand(FlightGround.fallback("B")["stand"])).is_equal([1000, 920])


## The longest routes S0's north lane gives anywhere on the 256 x 150 site grid:
## a join just inside either lane end (TaxiRoutes.joins_lane) and the
## southmost wall line. Their pair stays inside TaxiTimes' bounds, a 06:00
## departure's first state after midnight and a 22:00 departure's DEPARTED by
## the next midnight, so the quiet night stays empty without a distance cap.
func test_the_longest_north_lane_route_keeps_the_quiet_night_empty() -> void:
	var layout := FlightGround.layout()
	var lowest_x := SITE.grid_origin.x + 0.5
	var highest_x := SITE.grid_origin.x + SITE.grid_size.x - 0.5
	var wall_zs := [SITE.grid_origin.z, SITE.grid_origin.z + SITE.grid_size.y - 1.0]
	var longest := [0.0, 0.0]
	var worst: Array[int] = [0, 0]
	for door_x in range(int(lowest_x - 0.5), int(highest_x + 0.5)):
		var stand_x := float(door_x) + 0.5
		var stand := StandPlacement.make(1, stand_x, wall_zs[0])
		if not TaxiRoutes.joins_lane(StandPlacement.lane_join(stand), layout):
			continue
		for wall_z: float in wall_zs:
			stand = StandPlacement.make(1, stand_x, wall_z)
			var routes := FlightGround.routes(stand, PlaneClasses.LARGE)
			longest[0] = maxf(longest[0], MovementPlan.path_length(routes[FlightSim.State.TAXI_IN]))
			longest[1] = maxf(
				longest[1], MovementPlan.path_length(routes[FlightSim.State.TAXI_OUT])
			)
			var pair := TaxiTimes.for_stand(stand)
			worst = [maxi(worst[0], pair[0]), maxi(worst[1], pair[1])]
	var first_state := _starts(6 * 60, worst)[0]
	var departed := _starts(22 * 60, worst)[FlightSim.State.DEPARTED]
	print(
		(
			"MAX_ROUTE in %.1f m out %.1f m -> pair %s; 06:00 first state %s, 22:00 DEPARTED %s"
			% [
				longest[0],
				longest[1],
				worst,
				GameCalendar.clock_text(first_state, 0),
				GameCalendar.clock_text(departed, 0)
			]
		)
	)
	# The subject was engaged: the longest routes are longer than today's limits.
	assert_int(worst[0]).is_greater(TaxiTimes.BASE[0])
	assert_int(worst[1]).is_greater(TaxiTimes.BASE[1])
	assert_str(TaxiTimes.problem(worst)).is_empty()
	assert_int(worst[0]).is_less_equal(5540)
	assert_int(worst[1]).is_less_equal(2080)
	assert_int(first_state).is_greater_equal(GameCalendar.day_start(0, 0))
	assert_int(departed).is_less_equal(GameCalendar.day_start(1, 0))
	# The issue comes at or before the first state at every gate.
	var contract := _contract(6 * 60, worst)
	assert_int(FlightTimetable.issue_tick(contract, 0, 0)).is_less_equal(first_state)


## The starts of day 0 for a contract departing at `minute` with `pair`.
static func _starts(minute: int, pair: Array) -> Array[int]:
	return FlightTimetable.starts_for(_contract(minute, pair), 0, 0)


static func _contract(minute: int, pair: Array) -> Dictionary:
	return {"departure_minute": minute, "first_day": 0, "taxi": pair}
