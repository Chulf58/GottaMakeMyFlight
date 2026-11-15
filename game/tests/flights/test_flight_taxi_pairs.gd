class_name TestFlightTaxiPairs
extends GdUnitTestSuite
## Each contract flies the taxi pair of its gate's route (ruling taxi-time-
## follows-each-gate-s-route-length-far-side-gates-ta). Gate C stands on the
## scene's stand and keeps 1000 / 920; gate D's stand, a stubbed long route,
## has gate E's fallback x (84 m east of C, clear of C's stand and swing) and
## its wall at DEEP_WALL_Z, 400 m south of C's, so its pair is longer both ways
## ([1460, 1620]). The departure stays at PUSHBACK: a longer TAXI_IN moves only
## the first state, a longer TAXI_OUT only DEPARTED, and issuing stays where it
## was.

## The long gate's wall line: a whole number, so it is exact through JSON.
const DEEP_WALL_Z := 302.0
const TEN := 600


## Gate letter -> ground: C on the scene's stand, D on the long gate's stand.
static func grounds() -> Dictionary:
	var deep: Dictionary = FlightGround.fallback("E")["stand"].duplicate()
	deep["wall_z"] = DEEP_WALL_Z
	return {
		"C": FlightGround.fallback("C"),
		"D": {"stand": deep, "max_class": PlaneClasses.LARGE},
	}


## The long gate's pair.
static func long_pair() -> Array[int]:
	return TaxiTimes.for_stand(grounds()["D"]["stand"])


## An open sim at tick 0 on `gates` of grounds().
func open_sim(gates: Array[String]) -> FlightSim:
	var sim := auto_free(FlightSim.new()) as FlightSim
	sim.gate_source = func() -> Array[String]: return gates
	sim.stand_source = func() -> Dictionary: return grounds()
	assert_bool(sim.open_airport()).is_true()
	return sim


## Ticks `sim` one tick at a time up to `target`.
static func run_to(sim: FlightSim, target: int) -> void:
	for t in range(sim.tick + 1, target + 1):
		sim.on_tick(t)


## The sim's snapshot through JSON, loaded into a new sim on the same gates:
## "" when it loads, else the refusal.
func reload_problem(sim: FlightSim, gates: Array[String]) -> String:
	var data: Dictionary = JSON.parse_string(JSON.stringify(sim.to_snapshot()))
	var loaded := auto_free(FlightSim.new()) as FlightSim
	loaded.gate_source = func() -> Array[String]: return gates
	loaded.stand_source = func() -> Dictionary: return grounds()
	var problem := loaded.load_problem(data)
	if problem == "":
		assert_bool(loaded.from_snapshot(data)).is_true()
		assert_str(JSON.stringify(loaded.to_snapshot())).is_equal(JSON.stringify(sim.to_snapshot()))
	return problem


func test_the_long_gate_s_pair_is_longer_both_ways_and_c_keeps_today_s() -> void:
	print("long gate pair %s" % [long_pair()])
	assert_array(TaxiTimes.for_stand(grounds()["C"]["stand"])).is_equal(TaxiTimes.BASE)
	assert_int(long_pair()[0]).is_greater(TaxiTimes.BASE[0])
	assert_int(long_pair()[1]).is_greater(TaxiTimes.BASE[1])
	var north := open_sim(["C"] as Array[String])
	var far := open_sim(["D"] as Array[String])
	for sim: FlightSim in [north, far]:
		assert_bool(sim.accept_contract(TestFlightContracts.terms("T", TEN))).is_true()
	assert_array(north.contract_of("T")["taxi"]).is_equal(TaxiTimes.BASE)
	assert_array(far.contract_of("T")["taxi"]).is_equal(long_pair())
	assert_bool((far.contract_of("T")["taxi"] as Array).is_read_only()).is_true()
	assert_array(far.gate_taxi("D")).is_equal(long_pair())


## A longer TAXI_IN moves the first state earlier and a longer TAXI_OUT moves
## DEPARTED later; the departure, the doors and the issue tick stay, and the
## gate is held longer by both.
func test_a_long_route_moves_the_first_state_earlier_and_keeps_the_departure() -> void:
	var north := open_sim(["C"] as Array[String])
	var far := open_sim(["D"] as Array[String])
	for sim: FlightSim in [north, far]:
		assert_bool(sim.accept_contract(TestFlightContracts.terms("T", TEN))).is_true()
	var base := FlightTimetable.starts_for(north.contract_of("T"), 0)
	var long := FlightTimetable.starts_for(far.contract_of("T"), 0)
	var extra_in := long_pair()[0] - TaxiTimes.BASE[0]
	var extra_out := long_pair()[1] - TaxiTimes.BASE[1]
	print("base %s\nlong %s" % [base, long])
	assert_int(long[0]).is_equal(base[0] - extra_in)
	for state in [FlightSim.State.BOARDING, FlightSim.State.DOORS_CLOSED]:
		assert_int(long[state]).is_equal(base[state])
	assert_int(long[FlightSim.State.PUSHBACK]).is_equal(GameCalendar.tick_at(0, TEN))
	assert_int(base[FlightSim.State.PUSHBACK]).is_equal(GameCalendar.tick_at(0, TEN))
	assert_int(long[FlightSim.State.DEPARTED]).is_equal(base[FlightSim.State.DEPARTED] + extra_out)
	var held := long[FlightSim.State.DEPARTED] - long[0]
	assert_int(held).is_equal(FlightTimetable.reserved_ticks(long_pair()))
	assert_int(held).is_equal(FlightTimetable.reserved_ticks() + extra_in + extra_out)
	var issue := FlightTimetable.issue_tick(far.contract_of("T"), 0)
	assert_int(issue).is_equal(FlightTimetable.issue_tick(north.contract_of("T"), 0))
	assert_int(issue).is_less_equal(long[0])
	# The sim issues it then, and holds gate D from the earlier first state.
	run_to(far, issue)
	assert_array(far.flight_ids()).is_equal(["T-d0"])
	assert_int(far.state_start("T-d0", FlightSim.State.SCHEDULED)).is_equal(long[0])
	run_to(far, long[0] - 1)
	assert_str(far.flight_at_gate("D")).is_equal("")
	run_to(far, long[0])
	assert_str(far.flight_at_gate("D")).is_equal("T-d0")
	run_to(far, long[FlightSim.State.DEPARTED] - 1)
	assert_str(far.flight_at_gate("D")).is_equal("T-d0")


## B departs 13:20, so with today's pair its gate hold starts 100 ticks after
## A (10:00, today's pair) departs, and with the long pair 140 ticks before.
func test_a_clash_at_a_gate_counts_each_contract_s_own_gate_hold() -> void:
	var a := {"id": "A", "gate": "D", "departure_minute": TEN, "first_day": 0, "taxi": [1000, 920]}
	var b := {"id": "B", "gate": "D", "departure_minute": 800, "first_day": 0, "taxi": [1000, 920]}
	assert_bool(FlightTimetable.contracts_share_gate(a, b)).is_false()
	b["taxi"] = [1240, 920]
	assert_bool(FlightTimetable.contracts_share_gate(a, b)).is_true()
	assert_bool(FlightTimetable.contracts_share_gate(b, a)).is_true()
	assert_bool(FlightTimetable.contract_meets(b, "D", FlightTimetable.starts_for(a, 3))).is_true()
	b["taxi"] = [1000, 920]
	assert_bool(FlightTimetable.contract_meets(b, "D", FlightTimetable.starts_for(a, 3))).is_false()
	# A longer TAXI_OUT on A reaches B's base hold the same way.
	a["taxi"] = [1000, 1060]
	assert_bool(FlightTimetable.contracts_share_gate(a, b)).is_true()


## In the sim: a later contract is refused at the long gate for the clash its
## longer hold makes, and the same two fit gate C.
func test_the_sim_refuses_a_clash_that_only_the_long_pair_makes() -> void:
	# With today's pair A's hold after departure and B's before it fit the gap.
	var gap := (800 - TEN) * GameCalendar.TICKS_PER_MINUTE
	var reach := 320 + TaxiTimes.BASE[1] + 1660 + TaxiTimes.BASE[0]
	print("gap %d ticks, today's holds need %d" % [gap, reach])
	assert_int(gap).is_greater(reach)
	var north := open_sim(["C"] as Array[String])
	var far := open_sim(["D"] as Array[String])
	for sim: FlightSim in [north, far]:
		assert_bool(sim.accept_contract(TestFlightContracts.terms("A", TEN))).is_true()
	assert_str(north.accept_problem(TestFlightContracts.terms("B", 800))).is_empty()
	assert_str(far.accept_problem(TestFlightContracts.terms("B", 800))).contains("clashes with A")


## The offer card's note reads the pair of the gate the offer gets: between the
## long gate's first state of today's slot and gate C's, only the long gate's
## offer has to wait for tomorrow, and accepting agrees.
func test_the_first_flight_note_uses_the_pair_of_the_gate() -> void:
	var offer := TestFlightContracts.terms("O", TEN)
	var base_first := FlightTimetable.starts_for(_timed(offer, TaxiTimes.BASE), 0)[0]
	var long_first := FlightTimetable.starts_for(_timed(offer, long_pair()), 0)[0]
	var now := long_first + 1
	assert_int(now).is_less(base_first)
	assert_str(OfferPanel.first_flight_note(offer, now, TaxiTimes.BASE)).is_empty()
	assert_str(OfferPanel.first_flight_note(offer, now, long_pair())).is_equal(
		"first flight tomorrow"
	)
	for gates: Array[String] in [["C"] as Array[String], ["D"] as Array[String]]:
		var sim := open_sim(gates)
		sim.tick = now
		var taxi := sim.gate_taxi(gates[0])
		var noted := OfferPanel.first_flight_note(offer, now, taxi) != ""
		assert_bool(sim.accept_contract(offer)).is_true()
		assert_bool(noted).is_equal(int(sim.contract_of("O")["first_day"]) == 1)
	# Accepted while closed, the lead to the first flight is the same at both.
	assert_int(OfferPanel.opening_lead_ticks()).is_equal(FlightTimetable.issue_lead())


## The starter departs issue_lead() after now at any gate: at the long gate it
## is issued at once, today, with its first state still ahead.
func test_the_starter_is_issued_at_once_at_the_long_gate() -> void:
	var sim := open_sim(["D"] as Array[String])
	var now := GameCalendar.tick_at(0, 9 * 60)
	run_to(sim, now)
	var terms := FlightSim.starter_terms(now)
	assert_bool(sim.accept_contract(terms)).is_true()
	assert_array(sim.contract_of(terms["id"])["taxi"]).is_equal(long_pair())
	var id := FlightTimetable.occurrence_id(terms["id"], 0)
	assert_array(sim.flight_ids()).is_equal([id])
	assert_int(sim.state_of(id)).is_equal(FlightSim.State.SCHEDULED)
	assert_int(sim.state_start(id, FlightSim.State.SCHEDULED)).is_greater_equal(now)


## The planner draws an issued flight's hold from its own starts: after its
## contract moved to gate C, day 0's bar keeps the long gate's earlier start. It
## departs 14:00, so day 0 is issued after the move to the long gate.
func test_the_planner_bar_of_an_issued_flight_keeps_its_own_starts() -> void:
	var sim := open_sim(["C", "D"] as Array[String])
	assert_bool(sim.accept_contract(TestFlightContracts.terms("A", 840))).is_true()
	assert_bool(sim.reassign_gate("A", "D")).is_true()
	run_to(sim, FlightTimetable.issue_tick(sim.contract_of("A"), 0))
	var long := sim.state_start("A-d0", FlightSim.State.SCHEDULED)
	assert_bool(sim.reassign_gate("A", "C")).is_true()
	var bars := {}
	for bar: Dictionary in FlightPlannerModel.bars_for_day(sim, 0):
		bars[bar["flight"]] = bar
	for bar: Dictionary in FlightPlannerModel.bars_for_day(sim, 1):
		bars[bar["flight"]] = bar
	assert_int(bars["A-d0"]["start"]).is_equal(long)
	assert_str(bars["A-d0"]["gate"]).is_equal("D")
	var next := FlightTimetable.starts_for(sim.contract_of("A"), 1)
	assert_int(bars["A-d1"]["start"]).is_equal(next[0])
	assert_int(next[0]).is_equal(long + GameCalendar.TICKS_PER_DAY + long_pair()[0] - 1000)


static func _timed(terms: Dictionary, taxi: Array) -> Dictionary:
	var timed := terms.duplicate()
	timed["first_day"] = 0
	timed["taxi"] = taxi
	return timed
