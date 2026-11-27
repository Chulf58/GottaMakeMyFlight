class_name TestCharterFlights
extends GdUnitTestSuite
## End-to-end charter contract flight lifecycle: compact ~90 min gate hold,
## 0% RELAXED arrival mix, check-in/security/boarding, clean departure with
## zero TAXI_BUSY, payout, zero recurrence on day+1, and SaveGame round-trip.

const SEED := 441_902

var _main: Node
var _save_path := SaveTestKit.run_path("test_charter_flights_save")
var _e2e := {}


func before() -> void:
	_main = SaveTestKit.boot(self, SEED)
	SaveTestKit.start_airport(_main)
	var flights: FlightSim = _main.get_node("FlightSim")
	var clock: SimClock = _main.get_node("SimClock")
	var sim: PassengerSim = _main.get_node("PassengerSim")
	var desk: OfferDesk = _main.get_node("OfferDesk")
	var wallet: Wallet = (_main.get_node("Finances") as Finances).wallet

	# Run until airport opens and starter GMF101 has departed so a quiet afternoon gap is open.
	for i in 4500:
		SaveTestKit.step(_main)
		if flights.opened_tick >= 0 and flights.state_of("GMF101-d0") == FlightSim.State.DEPARTED:
			break
	_e2e["opened"] = flights.opened_tick >= 0

	# Ensure a same-day charter is open (or step to next charter check tick).
	for i in 350:
		if not desk.board.open_charters().is_empty():
			break
		SaveTestKit.step(_main)
	var charters := desk.board.open_charters()
	_e2e["charter_opened"] = charters.size() == 1
	if charters.is_empty():
		return
	var charter: Dictionary = charters[0]
	var cid: String = charter["id"]
	_e2e["charter_id"] = cid
	_e2e["charter_day"] = int(charter["day"])
	_e2e["expected_payout"] = int(charter["booked_passengers"]) * int(charter["fee_per_passenger"])

	# Track arrival types spawned for this charter flight.
	var occ_id := FlightTimetable.occurrence_id(cid, int(charter["day"]))
	var spawned_arrivals: Array[int] = []
	var on_spawn := func(pid: int) -> void:
		var p := sim.get_passenger(pid)
		if p != null and p.is_departing() and p.flight_id == occ_id:
			spawned_arrivals.append(p.arrival_type)
	sim.passenger_spawned.connect(on_spawn)

	var balance_before := wallet.balance
	_e2e["accepted"] = desk.board.accept(cid, flights)
	_e2e["issued_immediately"] = flights.state_of(occ_id) >= 0

	# Step until boarding starts, take a SaveGame snapshot, and verify round-trip load.
	var boarding_start := flights.state_start(occ_id, FlightSim.State.BOARDING)
	while clock.tick < boarding_start and clock.tick < boarding_start + 50:
		SaveTestKit.step(_main)
	_e2e["saved_ok"] = SaveTestKit.save_game(_main).save_to_file(_save_path)
	var loaded_main := SaveTestKit.boot(self, SEED + 1)
	_e2e["loaded_ok"] = SaveTestKit.save_game(loaded_main).load_from_file(_save_path)
	var loaded_flights: FlightSim = loaded_main.get_node("FlightSim")
	_e2e["loaded_has_charter"] = not loaded_flights.contract_of(cid).is_empty()
	_e2e["loaded_flight_state"] = loaded_flights.state_of(occ_id)
	loaded_main.free()

	# Continue main simulation until charter departs and finishes settling.
	var depart_tick := flights.state_start(occ_id, FlightSim.State.DEPARTED)
	while clock.tick <= depart_tick + 20:
		SaveTestKit.step(_main)
	_e2e["departed_state"] = flights.state_of(occ_id)
	_e2e["taxi_plan_error"] = flights._reported.has(occ_id)
	_e2e["spawned_count"] = spawned_arrivals.size()
	_e2e["booked_count"] = int(charter["booked_passengers"])
	_e2e["relaxed_count"] = spawned_arrivals.count(ArrivalTypes.Type.RELAXED)
	_e2e["made_count"] = int(sim.flight_results.get(occ_id, {}).get("made", 0))
	_e2e["balance_delta"] = wallet.balance - balance_before

	# Step across midnight into day + 1 and check zero recurrence.
	var day1_end := GameCalendar.day_start(int(charter["day"]) + 1, clock.epoch) + 200
	while clock.tick <= day1_end:
		SaveTestKit.step(_main)
	_e2e["day1_flight_state"] = flights.state_of(FlightTimetable.occurrence_id(cid, 1))
	_e2e["day1_departure_rows"] = (
		DepartureList
		. rows_for_day(flights, 1)
		. filter(func(r: Dictionary) -> bool: return r["contract"] == cid)
		. size()
	)
	_e2e["day1_planner_bars"] = (
		FlightPlannerModel
		. bars_for_day(flights, 1)
		. filter(func(b: Dictionary) -> bool: return b["contract"] == cid)
		. size()
	)
	sim.passenger_spawned.disconnect(on_spawn)


func after() -> void:
	if _main != null:
		_main.free()
	DirAccess.remove_absolute(_save_path)
	DirAccess.remove_absolute(_save_path + ".tmp")


func test_charter_compact_gate_hold_is_90_min_while_regular_remains_unchanged() -> void:
	assert_int(FlightSim.PHASE_TICKS[FlightSim.State.BOARDING]).is_equal(1200)
	assert_int(FlightSim.CHARTER_BOARDING_TICKS).is_equal(380)
	var sim := auto_free(FlightSim.new()) as FlightSim
	sim.open_airport()
	var terms := TestFlightFit.terms("CH0N1", 720, PlaneClasses.SMALL)
	terms[FlightContract.ONE_OFF_DAY_KEY] = 0
	assert_bool(sim.accept_contract(terms)).is_true()
	var contract := sim.contract_of("CH0N1")
	assert_bool(FlightContract.is_charter(contract)).is_true()
	assert_int(sim.end_fee("CH0N1")).is_equal(0)
	assert_bool(sim.active_contract_ids().has("CH0N1")).is_false()
	var starts := FlightTimetable.starts_for(contract, 0, 0)
	var hold := FlightTimetable.gate_hold_span(starts, PlaneClasses.SMALL)
	assert_int(hold[1] - hold[0]).is_equal(1840)
	# FlightFit agrees with accept_problem and has zero BLOCKER_TAXI regressions.
	var assessment := FlightFit.assess(sim, TestFlightFit.terms("REG", 720, PlaneClasses.SMALL))
	assert_bool(assessment["fits"]).is_false()
	# Next day has zero gate clash against yesterday's one-off charter.
	sim.tick = GameCalendar.day_start(1, 0)
	var reg_next := TestFlightFit.terms("REG2", 720, PlaneClasses.SMALL)
	assert_bool(sim.accept_contract(reg_next)).is_true()


func test_charter_arrival_mix_has_zero_relaxed() -> void:
	var shares := ArrivalTypes.shares_for({}, true)
	assert_int(shares[ArrivalTypes.Type.RELAXED]).is_equal(0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	for i in 200:
		assert_int(ArrivalTypes.draw(rng, shares)).is_not_equal(ArrivalTypes.Type.RELAXED)


func test_end_to_end_charter_spawns_boards_departs_pays_saves_and_never_recurs() -> void:
	assert_bool(_e2e.get("opened", false)).is_true()
	assert_bool(_e2e.get("charter_opened", false)).is_true()
	assert_bool(_e2e.get("accepted", false)).is_true()
	assert_bool(_e2e.get("issued_immediately", false)).is_true()
	assert_bool(_e2e.get("saved_ok", false)).is_true()
	assert_bool(_e2e.get("loaded_ok", false)).is_true()
	assert_bool(_e2e.get("loaded_has_charter", false)).is_true()
	assert_int(int(_e2e.get("loaded_flight_state", -1))).is_greater_equal(FlightSim.State.SCHEDULED)
	assert_int(int(_e2e.get("departed_state", -1))).is_equal(FlightSim.State.DEPARTED)
	assert_bool(_e2e.get("taxi_plan_error", true)).is_false()
	assert_int(int(_e2e.get("spawned_count", 0))).is_equal(int(_e2e.get("booked_count", -1)))
	assert_int(int(_e2e.get("relaxed_count", -1))).is_equal(0)
	assert_int(int(_e2e.get("made_count", 0))).is_equal(int(_e2e.get("booked_count", -1)))
	assert_int(int(_e2e.get("balance_delta", 0))).is_greater_equal(
		int(_e2e.get("expected_payout", 1))
	)
	assert_int(int(_e2e.get("day1_flight_state", 0))).is_equal(-1)
	assert_int(int(_e2e.get("day1_departure_rows", -1))).is_equal(0)
	assert_int(int(_e2e.get("day1_planner_bars", -1))).is_equal(0)


func test_finished_day0_charter_does_not_block_day1_spur_moves_move_plan_or_gate_removal() -> void:
	# 1. SpurMoves and FlightPlans.runs ignore Day 0 charter once issued.
	var stand := StandPlacement.make(1, -33.0, -93.5, StandPlacement.WEST, -124.0)
	var charter := (
		FlightContract
		. make(
			{
				"id": "CH0N1",
				"airline": "Gotta Air",
				"destination": "Oslo",
				"departure_minute": 720,
				"gate": "A",
				"plane_size": PlaneClasses.SMALL,
				"booked_passengers": 6,
				"fee_per_passenger": 50,
				"first_day": 0,
				"taxi": TaxiTimes.for_stand(stand),
				FlightContract.ONE_OFF_DAY_KEY: 0,
			}
		)
	)
	var regular := (
		FlightContract
		. make(
			{
				"id": "R1",
				"airline": "Blue Fjord",
				"destination": "Rome",
				"departure_minute": 720,
				"gate": "A",
				"plane_size": PlaneClasses.SMALL,
				"booked_passengers": 6,
				"fee_per_passenger": 50,
				"first_day": 1,
				"taxi": TaxiTimes.for_stand(stand),
			}
		)
	)
	var day1_start := GameCalendar.day_start(1, 0)
	var world := {
		"spurs":
		{
			StandPlacement.WEST: {"x": -124.0, "wanted": -150.0},
			StandPlacement.EAST: {"x": 124.0, "wanted": 124.0},
		},
		"tick": day1_start,
		"open": true,
		"epoch": 0,
		"contracts": [charter, regular],
		"start_day": {"CH0N1": 0, "R1": 1},
		"next_day": {"CH0N1": 1, "R1": 1},
		"ended": {},
		"reserving": {},
		"flights": [],
		"landed": [],
		"grounds": {"A": {"stand": stand, "max_class": PlaneClasses.LARGE}},
		"works": [],
	}
	assert_bool(FlightPlans.runs(world, "CH0N1")).is_false()
	assert_int(SpurMoves.release(world, StandPlacement.WEST)).is_equal(day1_start)
	assert_dict(SpurMoves.refusal(world)).is_empty()

	# 2. GateDesks removal + move_plan: unissued blocks; finished Day 0 frees gate.
	var site: SiteGrid = SiteGrid.new(preload("res://build/terminal_site.tres"))
	assert_bool(StarterShell.place(site, site.site.starter_offset)).is_true()
	var sim := auto_free(FlightSim.new()) as FlightSim
	sim.open_airport()
	var gates := auto_free(GateDesks.new()) as GateDesks
	gates.bind(site, sim)
	site.guard = gates.edit_problem
	var desk_cell := ReferenceTerminal.GATE_DESK_CELL + site.site.starter_offset
	var placed := site.apply(BuildEdit.place_object(GateDesks.DESK, desk_cell, 0))
	assert_bool(placed.ok).is_true()
	var gate_id: String = sim.gate_ids()[0]
	var terms := TestFlightFit.terms("CHMOVE", 900, PlaneClasses.SMALL)
	terms[FlightContract.ONE_OFF_DAY_KEY] = 0
	assert_bool(sim.accept_contract(terms)).is_true()

	# Unissued Day 0 charter stays in stuck (matches reassign_problem) and blocks gate removal.
	assert_array(sim.move_plan([gate_id] as Array[String], [] as Array[String])["stuck"]).contains(
		"CHMOVE"
	)
	var before_issue := site.apply(BuildEdit.remove_object(placed.object_id))
	assert_bool(before_issue.ok).is_false()
	assert_int(before_issue.reason).is_equal(BuildResult.Reason.GATE_FLIGHTS_STUCK)

	# After Day 0 issue + prune on Day 1, move_plan and GateDesks removal succeed.
	var depart_end := GameCalendar.tick_at(0, 900, 0) + FlightTimetable.PRUNE_AFTER_TICKS + 10
	sim.on_tick(FlightTimetable.issue_tick(sim.contract_of("CHMOVE"), 0, 0))
	for t in [
		sim.state_start("CHMOVE-d0", FlightSim.State.DEPARTED),
		depart_end,
		GameCalendar.day_start(1, 0),
	]:
		sim.on_tick(t)
	assert_array(sim.move_plan([gate_id] as Array[String], [] as Array[String])["stuck"]).is_empty()
	var after_day0 := site.apply(BuildEdit.remove_object(placed.object_id))
	assert_bool(after_day0.ok).is_true()
