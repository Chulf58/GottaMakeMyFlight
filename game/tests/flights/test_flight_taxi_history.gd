class_name TestFlightTaxiHistory
extends GdUnitTestSuite
## A contract's taxi pair is its current assignment; what it already issued is
## history and keeps the starts it was issued with (ruling taxi-time-follows-
## each-gate-s-route-length-far-side-gates-ta, board airside-all-around-s2-per-
## contract-taxi-time-each-contract-c). So a move never shifts an issue, an
## occurrence prunes after its own DEPARTED, landed stays in timetable order,
## runway works stay held for a long flight after its contract ends, and a save
## holding mixed pairs loads while a tampered one does not. Gates C (today's
## pair) and D (a long route) are TestFlightTaxiPairs.grounds().

## 14:00: day 0 is issued after the game starts (tick 0 is 06:00), not at once.
const DEPARTS := 840
const BOTH: Array[String] = ["C", "D"]


func _open(gates: Array[String]) -> FlightSim:
	var sim := auto_free(FlightSim.new()) as FlightSim
	sim.gate_source = func() -> Array[String]: return gates
	sim.stand_source = func() -> Dictionary: return TestFlightTaxiPairs.grounds()
	assert_bool(sim.open_airport()).is_true()
	return sim


func _reload_problem(sim: FlightSim, gates: Array[String]) -> String:
	var data: Dictionary = JSON.parse_string(JSON.stringify(sim.to_snapshot()))
	var loaded := auto_free(FlightSim.new()) as FlightSim
	loaded.gate_source = func() -> Array[String]: return gates
	loaded.stand_source = func() -> Dictionary: return TestFlightTaxiPairs.grounds()
	var problem := loaded.load_problem(data)
	if problem == "":
		assert_bool(loaded.from_snapshot(data)).is_true()
		assert_str(JSON.stringify(loaded.to_snapshot())).is_equal(JSON.stringify(sim.to_snapshot()))
	return problem


## X runs at gate C; 100 ticks before day 0's issue it moves to the long gate,
## whose first state is earlier. Issuing is anchored to the departure, so the
## day is not overdue: it is issued at the same tick, with the long pair, and a
## save taken in between loads.
func test_a_move_across_an_issue_boundary_issues_nothing_early() -> void:
	var sim := _open(BOTH)
	assert_bool(sim.accept_contract(TestFlightContracts.terms("X", DEPARTS))).is_true()
	var issue := FlightTimetable.issue_tick(sim.contract_of("X"), 0)
	var long := FlightTimetable.starts_for(_with(sim.contract_of("X"), _long()), 0)
	# Were issuing anchored to the first state, day 0 would be overdue at the move.
	assert_int(long[0] - FlightTimetable.ISSUE_LEAD_TICKS).is_less(issue - 100)
	TestFlightTaxiPairs.run_to(sim, issue - 100)
	assert_bool(sim.reassign_gate("X", "D")).is_true()
	TestFlightTaxiPairs.run_to(sim, issue - 1)
	assert_array(sim.flight_ids()).is_empty()
	assert_int(int(sim.to_snapshot()["next_day"]["X"])).is_equal(0)
	assert_str(_reload_problem(sim, BOTH)).is_empty()
	TestFlightTaxiPairs.run_to(sim, issue)
	assert_array(sim.flight_ids()).is_equal(["X-d0"])
	assert_str(sim.flight_gate("X-d0")).is_equal("D")
	for state in FlightSim.STATE_COUNT:
		assert_int(sim.state_start("X-d0", state)).is_equal(long[state])
	assert_int(long[0]).is_greater_equal(issue)
	# Back to C after the issue: the issued day keeps gate D and its long times.
	assert_bool(sim.reassign_gate("X", "C")).is_true()
	assert_array(sim.contract_of("X")["taxi"]).is_equal(TaxiTimes.BASE)
	assert_int(sim.state_start("X-d0", FlightSim.State.SCHEDULED)).is_equal(long[0])
	assert_str(_reload_problem(sim, BOTH)).is_empty()


## X-d0 was issued at the long gate (TAXI_OUT longer than today's) and X then
## moved to gate C. The occurrence is pruned an hour after its own DEPARTED,
## not the contract's times now, a save between the two loads, and once pruned
## it still answers with the gate and times it flew.
func test_an_occurrence_prunes_by_its_own_starts_after_its_taxi_out_shortened() -> void:
	var sim := _open(BOTH)
	assert_bool(sim.accept_contract(TestFlightContracts.terms("X", DEPARTS))).is_true()
	assert_bool(sim.reassign_gate("X", "D")).is_true()
	TestFlightTaxiPairs.run_to(sim, FlightTimetable.issue_tick(sim.contract_of("X"), 0))
	assert_bool(sim.reassign_gate("X", "C")).is_true()
	var own := sim.state_start("X-d0", FlightSim.State.DEPARTED)
	var by_contract := FlightTimetable.starts_for(sim.contract_of("X"), 0)
	var own_prune := own + FlightTimetable.PRUNE_AFTER_TICKS
	var contract_prune := FlightTimetable.prune_tick(by_contract)
	print("prunes at %d by its own starts, %d by the contract's now" % [own_prune, contract_prune])
	assert_int(own_prune).is_greater(contract_prune)
	TestFlightTaxiPairs.run_to(sim, contract_prune)
	assert_array(sim.flight_ids()).is_equal(["X-d0"])
	assert_str(_reload_problem(sim, BOTH)).is_empty()
	TestFlightTaxiPairs.run_to(sim, own_prune - 1)
	assert_array(sim.flight_ids()).is_equal(["X-d0"])
	TestFlightTaxiPairs.run_to(sim, own_prune)
	assert_array(sim.flight_ids()).is_empty()
	var landed: Array = sim.to_snapshot()["landed"]
	assert_int(landed.size()).is_equal(1)
	assert_str(landed[0]["id"]).is_equal("X-d0")
	assert_int(sim.state_of("X-d0")).is_equal(FlightSim.State.DEPARTED)
	assert_str(sim.flight_gate("X-d0")).is_equal("D")
	assert_int(sim.state_start("X-d0", FlightSim.State.DEPARTED)).is_equal(own)
	assert_str(_reload_problem(sim, BOTH)).is_empty()
	# Still landed the next day, so a save after midnight knows it was pruned.
	TestFlightTaxiPairs.run_to(sim, GameCalendar.tick_at(1, 30))
	assert_str((sim.to_snapshot()["landed"] as Array)[0]["id"]).is_equal("X-d0")
	assert_str(_reload_problem(sim, BOTH)).is_empty()


## X (long gate, 13:52) and Y (gate C, 14:00): X starts first but departs,
## and is pruned, after Y. Landed keeps timetable order, so the save loads.
func test_landed_keeps_timetable_order_when_prunes_come_in_another() -> void:
	var sim := _open(BOTH)
	assert_bool(sim.accept_contract(TestFlightContracts.terms("Y", DEPARTS))).is_true()
	assert_str(sim.accept_problem(TestFlightContracts.terms("X", DEPARTS - 8))).is_empty()
	assert_bool(sim.accept_contract(TestFlightContracts.terms("X", DEPARTS - 8))).is_true()
	assert_str(sim.contract_of("Y")["gate"]).is_equal("C")
	assert_str(sim.contract_of("X")["gate"]).is_equal("D")
	var x := FlightTimetable.starts_for(sim.contract_of("X"), 0)
	var y := FlightTimetable.starts_for(sim.contract_of("Y"), 0)
	assert_int(x[0]).is_less(y[0])
	assert_int(FlightTimetable.prune_tick(x)).is_greater(FlightTimetable.prune_tick(y))
	TestFlightTaxiPairs.run_to(sim, FlightTimetable.prune_tick(y))
	assert_array(sim.flight_ids()).is_equal(["X-d0"])
	TestFlightTaxiPairs.run_to(sim, FlightTimetable.prune_tick(x))
	var ids := []
	for entry: Dictionary in sim.to_snapshot()["landed"]:
		ids.append(entry["id"])
	assert_array(ids).is_equal(["X-d0", "Y-d0"])
	assert_str(_reload_problem(sim, BOTH)).is_empty()


## A long flight met the runway works: its first state comes before they end,
## and it departs after the HOLD_TICKS a flight at today's times needs. The
## booking stays held until it has departed, even though its contract ended,
## and a flight at gate C releases it at HOLD_TICKS as before.
func test_works_stay_held_for_a_long_flight_after_its_contract_ends() -> void:
	var cases := [["D", true], ["C", false]]
	for case: Array in cases:
		var gates: Array[String] = [case[0]]
		var sim := _open(gates)
		sim.runway.size = PlaneClasses.MEDIUM
		assert_bool(sim.accept_contract(TestFlightContracts.terms("L", DEPARTS))).is_true()
		TestFlightTaxiPairs.run_to(sim, FlightTimetable.issue_tick(sim.contract_of("L"), 0))
		var first := sim.state_start("L-d0", FlightSim.State.SCHEDULED)
		var departs := sim.state_start("L-d0", FlightSim.State.DEPARTED)
		# Works that end 50 ticks into the flight's first state, before its approach.
		var works := sim.runway.works
		works.begin(PlaneClasses.LARGE, first + 50 - RunwayWorks.ticks(PlaneClasses.LARGE))
		TestFlightTaxiPairs.run_to(sim, works.finish)
		assert_str(sim.runway.size).is_equal(PlaneClasses.LARGE)
		assert_bool(sim.end_contract("L")).is_true()
		assert_array(sim.flight_ids()).is_equal(["L-d0"])
		var released := works.finish + RunwayWorks.HOLD_TICKS
		print("gate %s: departs %d, HOLD_TICKS releases at %d" % [case[0], departs, released])
		assert_bool(departs > released).is_equal(case[1])
		TestFlightTaxiPairs.run_to(sim, released)
		assert_bool(works.start != RunwayWorks.NO_TICK).is_equal(case[1])
		TestFlightTaxiPairs.run_to(sim, maxi(departs, released))
		assert_int(works.start).is_equal(RunwayWorks.NO_TICK)


## A save with a long and a short pair loads; changing a saved pair so that it
## no longer matches its gate or its flight is refused.
func test_a_save_with_mixed_pairs_loads_and_a_tampered_pair_is_refused() -> void:
	var sim := _open(BOTH)
	assert_bool(sim.accept_contract(TestFlightContracts.terms("Y", DEPARTS))).is_true()
	assert_str(sim.accept_problem(TestFlightContracts.terms("X", DEPARTS - 8))).is_empty()
	assert_bool(sim.accept_contract(TestFlightContracts.terms("X", DEPARTS - 8))).is_true()
	assert_str(sim.contract_of("X")["gate"]).is_equal("D")
	TestFlightTaxiPairs.run_to(sim, GameCalendar.tick_at(0, 13 * 60))
	assert_int(sim.flight_ids().size()).is_equal(2)
	assert_str(_reload_problem(sim, BOTH)).is_empty()
	var good: Dictionary = JSON.parse_string(JSON.stringify(sim.to_snapshot()))
	var x_at := 0 if good["contracts"][0]["id"] == "X" else 1
	var x_flight := 0 if good["flights"][0]["id"] == "X-d0" else 1
	var short_contract := good.duplicate(true)
	short_contract["contracts"][x_at]["taxi"] = [1000, 920]
	var short_flight := good.duplicate(true)
	var base := FlightTimetable.starts_for(_with(sim.contract_of("X"), TaxiTimes.BASE), 0)
	short_flight["flights"][x_flight]["starts"] = base
	var odd_pair := good.duplicate(true)
	odd_pair["contracts"][x_at]["taxi"] = [1250, 1100]
	var no_pair := good.duplicate(true)
	no_pair["contracts"][x_at].erase("taxi")
	var cases := {
		"short contract": short_contract,
		"short flight": short_flight,
		"odd pair": odd_pair,
		"no pair": no_pair,
	}
	for name: String in cases:
		var loaded := auto_free(FlightSim.new()) as FlightSim
		loaded.gate_source = func() -> Array[String]: return BOTH
		loaded.stand_source = func() -> Dictionary: return TestFlightTaxiPairs.grounds()
		var problem := loaded.load_problem(cases[name])
		print("%s: '%s'" % [name, problem])
		assert_str(problem).override_failure_message(name).is_not_empty()
		assert_bool(loaded.from_snapshot(cases[name])).is_false()


## A version 8 save had contracts without a taxi pair: refused, with no
## migration, as version 8 and as a relabelled version 9.
func test_a_version_8_save_without_taxi_pairs_is_refused() -> void:
	var sim := _open(BOTH)
	assert_bool(sim.accept_contract(TestFlightContracts.terms("Y", DEPARTS))).is_true()
	var old: Dictionary = JSON.parse_string(JSON.stringify(sim.to_snapshot()))
	for contract: Dictionary in old["contracts"]:
		contract.erase("taxi")
	old["save_version"] = 8
	var relabelled := old.duplicate(true)
	relabelled["save_version"] = FlightSim.SAVE_VERSION
	for data: Dictionary in [old, relabelled]:
		var loaded := auto_free(FlightSim.new()) as FlightSim
		loaded.gate_source = func() -> Array[String]: return BOTH
		assert_str(loaded.load_problem(data)).is_not_empty()
	assert_str(_reload_problem(sim, BOTH)).is_empty()


static func _long() -> Array[int]:
	return TestFlightTaxiPairs.long_pair()


static func _with(contract: Dictionary, taxi: Array) -> Dictionary:
	var fields := contract.duplicate()
	fields["taxi"] = taxi
	return fields
