class_name TestSmallTurnaround
extends GdUnitTestSuite
## Small-plane gate turnaround compression (P3, decision f29b7fbf): small
## contracts hold their gate over [AT_STAND - lead_in, DEPARTED) (2,620 ticks /
## 131 min at TaxiTimes.BASE) while medium and large contracts keep [SCHEDULED,
## DEPARTED) (3,900 ticks / 195 min), fitting 6-7 small flights/day on 1 starter
## gate with zero TAXI_BUSY misclassifications and deterministic concurrent-gate
## guards.


func _small_terms(id: String, minute: int) -> Dictionary:
	var terms := TestFlightFit.terms(id, minute, PlaneClasses.SMALL)
	return terms


func _medium_terms(id: String, minute: int, size := PlaneClasses.MEDIUM) -> Dictionary:
	var terms := TestFlightContracts.terms(id, minute)
	terms["plane_size"] = size
	terms["booked_passengers"] = 30 if size == PlaneClasses.MEDIUM else 60
	return terms


func _run_to(sim: FlightSim, target: int) -> void:
	for t in range(sim.tick + 1, target + 1):
		sim.on_tick(t)


func test_six_to_seven_small_flights_fit_on_one_starter_gate_in_one_day() -> void:
	var sim := auto_free(FlightSim.new()) as FlightSim
	sim.open_airport()
	var slots := [420, 555, 690, 825, 960, 1095, 1230]
	for i in slots.size():
		assert_bool(sim.accept_contract(_small_terms("S%d" % i, slots[i]))).is_true()
		assert_str(sim.contract_of("S%d" % i)["gate"]).is_equal("C")
	assert_int(sim.contract_ids().size()).is_equal(7)
	var day_one := GameCalendar.day_start(1, 0)
	_run_to(sim, day_one)
	for i in slots.size():
		var fid := FlightTimetable.occurrence_id("S%d" % i, 1)
		_run_to(sim, GameCalendar.tick_at(1, slots[i], 0))
		var win := sim.boarding_window(fid)
		assert_int(win.y - win.x).is_equal(1200)
	_run_to(sim, day_one + GameCalendar.TICKS_PER_DAY)
	for i in slots.size():
		var fid := FlightTimetable.occurrence_id("S%d" % i, 1)
		assert_int(sim.state_of(fid)).is_equal(FlightSim.State.DEPARTED)


func test_no_taxi_busy_misclassifications_across_stand_positions() -> void:
	for gate: String in ["A", "C", "F"]:
		var sim := auto_free(FlightSim.new()) as FlightSim
		sim.gate_source = func() -> Array[String]: return [gate] as Array[String]
		sim.stand_source = func() -> Dictionary: return {gate: FlightGround.fallback(gate)}
		sim.open_airport()
		assert_bool(sim.accept_contract(_small_terms("ANCHOR", 600))).is_true()
		for slot in range(OfferBoard.DEPARTURE_SLOTS + 1):
			var minute := OfferBoard.DEPARTURE_FIRST_MINUTE + slot * OfferBoard.DEPARTURE_STEP
			var offer := _small_terms("X%d" % minute, minute)
			var assessment := FlightFit.assess(sim, offer)
			if not assessment["fits"] and assessment["blocker"] == FlightSim.BLOCKER_TAXI:
				(
					assert_str(sim.trial_assignment(offer, [], true, gate)["gate"])
					. override_failure_message(
						"gate %s minute %d misclassified as BLOCKER_TAXI" % [gate, minute]
					)
					. is_empty()
				)
	# Outer side stand W clears consecutive small flights right past its gate hold too.
	var west_sim := auto_free(FlightSim.new()) as FlightSim
	var west_stand := StandPlacement.make(
		3, -62.0, -150.0, StandPlacement.WEST, -StandPlacement.SIDE_LANE_X
	)
	west_sim.gate_source = func() -> Array[String]: return ["W"] as Array[String]
	west_sim.stand_source = func() -> Dictionary:
		return {"W": {"stand": west_stand, "max_class": PlaneClasses.LARGE}}
	west_sim.open_airport()
	assert_bool(west_sim.accept_contract(_small_terms("ANCHOR", 600))).is_true()
	assert_str(west_sim.accept_problem(_small_terms("TIGHT", 720))).contains("clashes with ANCHOR")
	assert_str(west_sim.accept_problem(_small_terms("CLEAR", 740))).is_empty()


func test_medium_and_large_contracts_keep_full_scheduled_to_departed_hold() -> void:
	for size: String in [PlaneClasses.MEDIUM, PlaneClasses.LARGE]:
		var sim := auto_free(FlightSim.new()) as FlightSim
		sim.open_airport()
		assert_bool(sim.accept_contract(_medium_terms("M1", 600, size))).is_true()
		var span := FlightTimetable.gate_hold_span(
			FlightTimetable.starts_for(sim.contract_of("M1"), 0, 0), size
		)
		var expected_span := 3980 if size == PlaneClasses.MEDIUM else 4040
		var clear_gap := 199 if size == PlaneClasses.MEDIUM else 202
		assert_int(span[1] - span[0]).is_equal(expected_span)
		assert_str(sim.accept_problem(_medium_terms("M2", 600 + clear_gap - 1, size))).contains(
			"clashes with M1"
		)
		assert_bool(sim.accept_contract(_medium_terms("M3", 600 + clear_gap, size))).is_true()


func test_concurrent_small_flights_gate_priority_and_list() -> void:
	var sim := auto_free(FlightSim.new()) as FlightSim
	sim.open_airport()
	assert_bool(sim.accept_contract(_small_terms("A", 600))).is_true()
	assert_bool(sim.accept_contract(_small_terms("B", 735))).is_true()
	var push_a := GameCalendar.tick_at(1, 600, 0)
	# A in PUSHBACK (stand hold) while B is in SCHEDULED -> A wins.
	_run_to(sim, push_a + 10)
	assert_int(sim.state_of("A-d1")).is_equal(FlightSim.State.PUSHBACK)
	assert_int(sim.state_of("B-d1")).is_equal(FlightSim.State.SCHEDULED)
	assert_array(sim.flights_at_gate("C")).is_equal(["A-d1", "B-d1"])
	assert_str(sim.flight_at_gate("C")).is_equal("A-d1")
	# A in TAXI_OUT while B is in LANDING -> A (TAXI_OUT) beats B (LANDING).
	_run_to(sim, push_a + 200)
	assert_int(sim.state_of("A-d1")).is_equal(FlightSim.State.TAXI_OUT)
	assert_int(sim.state_of("B-d1")).is_equal(FlightSim.State.LANDING)
	assert_str(sim.flight_at_gate("C")).is_equal("A-d1")
	# A still in TAXI_OUT while B enters TAXI_IN -> B (TAXI_IN) beats A (TAXI_OUT).
	_run_to(sim, push_a + 400)
	assert_int(sim.state_of("A-d1")).is_equal(FlightSim.State.TAXI_OUT)
	assert_int(sim.state_of("B-d1")).is_equal(FlightSim.State.TAXI_IN)
	assert_array(sim.flights_at_gate("C")).is_equal(["A-d1", "B-d1"])
	assert_str(sim.flight_at_gate("C")).is_equal("B-d1")


func test_overlapping_small_flights_round_trip_snapshot_and_pass_spur_moves() -> void:
	var sim := auto_free(FlightSim.new()) as FlightSim
	sim.open_airport()
	assert_bool(sim.accept_contract(_small_terms("A", 600))).is_true()
	assert_bool(sim.accept_contract(_small_terms("B", 735))).is_true()
	var push_a := GameCalendar.tick_at(1, 600, 0)
	_run_to(sim, push_a + 500)
	assert_array(sim.flight_ids()).is_equal(["A-d1", "B-d1"])
	var data: Dictionary = JSON.parse_string(JSON.stringify(sim.to_snapshot()))
	var loaded := auto_free(FlightSim.new()) as FlightSim
	assert_str(loaded.load_problem(data)).is_empty()
	assert_bool(loaded.from_snapshot(data)).is_true()
	assert_array(loaded.flights_at_gate("C")).is_equal(["A-d1", "B-d1"])
	assert_str(loaded.flight_at_gate("C")).is_equal("B-d1")

	var east_stand := StandPlacement.make(
		4, 62.0, -150.0, StandPlacement.EAST, StandPlacement.SIDE_LANE_X
	)
	var e_taxi := TaxiTimes.for_stand(east_stand)
	var c1 := {
		"id": "A",
		"gate": "E",
		"departure_minute": 600,
		"first_day": 0,
		"plane_size": PlaneClasses.SMALL,
		"taxi": e_taxi,
	}
	var c2 := c1.duplicate()
	c2["id"] = "B"
	c2["departure_minute"] = 760
	var world := {
		"spurs":
		SideSpurs.spurs_at(
			{StandPlacement.EAST: StandPlacement.SIDE_LANE_X},
			{StandPlacement.EAST: StandPlacement.SIDE_LANE_X + 8.0}
		),
		"tick": 0,
		"epoch": 0,
		"open": true,
		"contracts": [c1, c2],
		"start_day": {"A": 0, "B": 0},
		"next_day": {"A": 1, "B": 1},
		"ended": {},
		"reserving": {},
		"flights": [],
		"landed": [],
		"grounds": {"E": {"stand": east_stand, "max_class": PlaneClasses.LARGE}},
	}
	assert_dict(SpurMoves.refusal(world)).is_empty()


func test_mixed_small_and_medium_gate_ordering_across_timetable_snapshot_and_spurs() -> void:
	# Asymmetric gate hold at BASE: MEDIUM@600 [600, 795) clears SMALL@735 [799, 930),
	# whereas SMALL@600 [664, 795) clashes with MEDIUM@735 [735, 930).
	var m_600 := _medium_terms("M1", 600)
	var s_735 := _small_terms("S2", 735)
	var s_600 := _small_terms("S1", 600)
	var m_735 := _medium_terms("M2", 735)
	var stand_c: Dictionary = FlightGround.fallback("C")["stand"]
	var starts_m600 := FlightTimetable.starts_for(
		FlightContract.assigned(m_600.merged({"first_day": 0}), "C", stand_c), 0, 0
	)
	var starts_s735 := FlightTimetable.starts_for(
		FlightContract.assigned(s_735.merged({"first_day": 0}), "C", stand_c), 0, 0
	)
	var starts_s600 := FlightTimetable.starts_for(
		FlightContract.assigned(s_600.merged({"first_day": 0}), "C", stand_c), 0, 0
	)
	var starts_m735 := FlightTimetable.starts_for(
		FlightContract.assigned(m_735.merged({"first_day": 0}), "C", stand_c), 0, 0
	)
	(
		assert_bool(
			FlightTimetable.shares_gate(
				"C", starts_m600, "C", starts_s735, PlaneClasses.MEDIUM, PlaneClasses.SMALL
			)
		)
		. is_false()
	)
	(
		assert_bool(
			FlightTimetable.shares_gate(
				"C", starts_s600, "C", starts_m735, PlaneClasses.SMALL, PlaneClasses.MEDIUM
			)
		)
		. is_true()
	)

	var sim := auto_free(FlightSim.new()) as FlightSim
	sim.open_airport()
	assert_bool(sim.accept_contract(m_600)).is_true()
	assert_bool(sim.accept_contract(s_735)).is_true()
	assert_str(sim.accept_problem(m_735)).is_not_empty()
	_run_to(sim, GameCalendar.tick_at(1, 600, 0) + 500)
	var data: Dictionary = JSON.parse_string(JSON.stringify(sim.to_snapshot()))
	var loaded := auto_free(FlightSim.new()) as FlightSim
	assert_str(loaded.load_problem(data)).is_empty()
	assert_bool(loaded.from_snapshot(data)).is_true()
	assert_array(loaded.flights_at_gate("C")).is_equal(["M1-d1", "S2-d1"])

	var east_stand := StandPlacement.make(
		4, 62.0, -150.0, StandPlacement.EAST, StandPlacement.SIDE_LANE_X
	)
	var e_taxi := TaxiTimes.for_stand(east_stand)
	var base := {
		"gate": "E",
		"first_day": 0,
		"taxi": e_taxi,
	}
	var c_med := base.merged(
		{"id": "M1", "departure_minute": 600, "plane_size": PlaneClasses.MEDIUM}
	)
	var c_sml := base.merged(
		{"id": "S2", "departure_minute": 740, "plane_size": PlaneClasses.SMALL}
	)
	var clear_world := {
		"spurs":
		SideSpurs.spurs_at(
			{StandPlacement.EAST: StandPlacement.SIDE_LANE_X},
			{StandPlacement.EAST: StandPlacement.SIDE_LANE_X + 8.0}
		),
		"tick": 0,
		"epoch": 0,
		"open": true,
		"contracts": [c_med, c_sml],
		"start_day": {"M1": 0, "S2": 0},
		"next_day": {"M1": 1, "S2": 1},
		"ended": {},
		"reserving": {},
		"flights": [],
		"landed": [],
		"grounds": {"E": {"stand": east_stand, "max_class": PlaneClasses.LARGE}},
	}
	assert_dict(SpurMoves.refusal(clear_world)).is_empty()

	var far_east := StandPlacement.with_lane_x(east_stand, 300.0)
	var c_s600 := base.merged(
		{"id": "S1", "departure_minute": 600, "plane_size": PlaneClasses.SMALL}
	)
	var c_m795 := base.merged(
		{"id": "M2", "departure_minute": 795, "plane_size": PlaneClasses.MEDIUM}
	)
	var clash_world := clear_world.duplicate(true)
	clash_world["spurs"] = SideSpurs.spurs_at(
		{StandPlacement.EAST: StandPlacement.SIDE_LANE_X}, {StandPlacement.EAST: 300.0}
	)
	clash_world["contracts"] = [c_s600, c_m795]
	clash_world["start_day"] = {"S1": 0, "M2": 0}
	clash_world["next_day"] = {"S1": 1, "M2": 1}
	clash_world["grounds"] = {
		"E":
		{
			"stand": east_stand,
			"max_class": PlaneClasses.LARGE,
			"next": {"stand": far_east, "max_class": PlaneClasses.LARGE},
		}
	}
	assert_str(SpurMoves.refusal(clash_world).get("reason", "")).is_equal(SpurMoves.GATE_MEETS)


func test_off_lane_north_spare_stand_is_never_synthesized_or_accepted() -> void:
	var f_stand: Dictionary = FlightGround.fallback("F")["stand"]
	var east_off := f_stand.duplicate()
	east_off["x"] = float(f_stand["x"]) + FlightGround.FALLBACK_SPACING_M
	assert_str(FlightContract.assignment_problem("G", east_off)).contains("does not join")
	var a_stand: Dictionary = FlightGround.fallback("A")["stand"]
	var west_off := a_stand.duplicate()
	west_off["x"] = float(a_stand["x"]) - FlightGround.FALLBACK_SPACING_M
	assert_str(FlightContract.assignment_problem("H", west_off)).contains("does not join")

	var sim_f := auto_free(FlightSim.new()) as FlightSim
	sim_f.gate_source = func() -> Array[String]: return ["F"] as Array[String]
	sim_f.stand_source = func() -> Dictionary: return {"F": FlightGround.fallback("F")}
	sim_f.open_airport()
	var with_spare := sim_f._with_spare_gate(sim_f.gate_grounds(), PlaneClasses.SMALL)
	assert_int(with_spare.size()).is_equal(2)
	var spare_stand: Dictionary = with_spare["A"]["stand"]
	var joins := TaxiRoutes.joins_lane(StandPlacement.lane_join(spare_stand), FlightGround.layout())
	assert_bool(joins).is_true()
	assert_float(float(spare_stand["x"])).is_equal(
		float(f_stand["x"]) - FlightGround.FALLBACK_SPACING_M
	)

	var sim_both := auto_free(FlightSim.new()) as FlightSim
	sim_both.gate_source = func() -> Array[String]: return ["A", "F"] as Array[String]
	sim_both.stand_source = func() -> Dictionary:
		return {"A": FlightGround.fallback("A"), "F": FlightGround.fallback("F")}
	sim_both.open_airport()
	var no_spare := sim_both._with_spare_gate(sim_both.gate_grounds(), PlaneClasses.SMALL)
	assert_int(no_spare.size()).is_equal(2)

	var sim_bad := auto_free(FlightSim.new()) as FlightSim
	sim_bad.gate_source = func() -> Array[String]: return ["G"] as Array[String]
	sim_bad.stand_source = func() -> Dictionary:
		return {"G": {"stand": east_off, "max_class": PlaneClasses.LARGE}}
	sim_bad.open_airport()
	assert_str(sim_bad.accept_problem(_small_terms("BAD", 600))).contains("does not join")
	assert_bool(sim_bad.accept_contract(_small_terms("BAD", 600))).is_false()

	var west_stand := StandPlacement.make(
		3, -62.0, -150.0, StandPlacement.WEST, -StandPlacement.SIDE_LANE_X
	)
	var sim_west := auto_free(FlightSim.new()) as FlightSim
	sim_west.gate_source = func() -> Array[String]: return ["W"] as Array[String]
	sim_west.stand_source = func() -> Dictionary:
		return {"W": {"stand": west_stand, "max_class": PlaneClasses.LARGE}}
	sim_west.open_airport()
	var west_spare := sim_west._with_spare_gate(sim_west.gate_grounds(), PlaneClasses.SMALL)
	assert_int(west_spare.size()).is_equal(2)
	var west_spare_stand: Dictionary = west_spare["A"]["stand"]
	assert_str(StandPlacement.side_of(west_spare_stand)).is_equal(StandPlacement.NORTH)
	assert_dict(west_spare_stand).is_equal(FlightGround.scene_stand())

	var sim_mixed := auto_free(FlightSim.new()) as FlightSim
	sim_mixed.gate_source = func() -> Array[String]: return ["C", "W"] as Array[String]
	sim_mixed.stand_source = func() -> Dictionary:
		return {
			"C": FlightGround.fallback("C"),
			"W": {"stand": west_stand, "max_class": PlaneClasses.LARGE},
		}
	sim_mixed.open_airport()
	var mixed_spare := sim_mixed._with_spare_gate(sim_mixed.gate_grounds(), PlaneClasses.SMALL)
	assert_int(mixed_spare.size()).is_equal(3)
	var mixed_stand: Dictionary = mixed_spare["A"]["stand"]
	assert_str(StandPlacement.side_of(mixed_stand)).is_equal(StandPlacement.NORTH)
	assert_float(float(mixed_stand["x"])).is_equal(
		float(FlightGround.fallback("C")["stand"]["x"]) + FlightGround.FALLBACK_SPACING_M
	)

	var overlap_west := StandPlacement.make(
		4, -10.0, -100.0, StandPlacement.WEST, -StandPlacement.SIDE_LANE_X
	)
	var sim_overlap := auto_free(FlightSim.new()) as FlightSim
	sim_overlap.gate_source = func() -> Array[String]: return ["W"] as Array[String]
	sim_overlap.stand_source = func() -> Dictionary:
		return {"W": {"stand": overlap_west, "max_class": PlaneClasses.LARGE}}
	sim_overlap.open_airport()
	var no_overlap_spare := sim_overlap._with_spare_gate(
		sim_overlap.gate_grounds(), PlaneClasses.SMALL
	)
	assert_int(no_overlap_spare.size()).is_equal(1)
