class_name TestFlightPlannerWiring
extends GdUnitTestSuite
## Runway R7: FlightSim plans every flight on GroundPlanner through FlightPlans
## (decision runway-and-taxi-technical-design-movement-plan-analytic-bookings-
## planned-pauses, sections 3, 5, 6 and 8; user ruling a-gate-has-no-size-planes-
## use-any-stand-they-fit-neighbours-share-apron-space). More than three gates
## can be busy at once; an offer no pause fits, or one that would leave an
## existing occurrence with none, is refused with "taxi lane busy at that time";
## reassigning and moving contracts go through the planner and never change an
## issued occurrence; a save re-plans identically and a load whose plan fails is
## refused; PlaneView stands at the hold line for the planned pause.
##
## With no stand_source FlightSim stands each gate on FlightGround.fallback():
## gate C on main.tscn's stand and the others 42 m apart along its row.

const GATES: Array[String] = ["A", "B", "C", "D", "E", "F"]

var _sim: FlightSim


func before_test() -> void:
	_sim = auto_free(FlightSim.new()) as FlightSim
	_sim.open_airport()


func _gates(gates: Array[String]) -> void:
	_sim.gate_source = func() -> Array[String]: return gates


static func _small(id: String, minute: int) -> Dictionary:
	var terms := TestFlightContracts.terms(id, minute)
	terms["plane_size"] = PlaneClasses.SMALL
	terms["booked_passengers"] = 12
	return terms


func _run_to(target: int) -> void:
	for t in range(_sim.tick + 1, target + 1):
		_sim.on_tick(t)


## Every live flight's id -> [gate, taxi plan].
func _live_plans(sim: FlightSim) -> Dictionary:
	var out := {}
	for id in sim.flight_ids():
		out[id] = [sim.flight_gate(id), sim.taxi_plan(id)]
	return out


static func _paused(plan: Dictionary) -> bool:
	for pause: Dictionary in plan.values():
		if not pause.is_empty():
			return true
	return false


## Six gates and small offers every 15 minutes from 07:00 to 21:00, each
## accepted when FlightSim takes it: on day 1 more than three gates hold a
## flight at one tick, and some flight takes a planned pause.
func test_more_than_three_gates_are_busy_at_once() -> void:
	_gates(GATES)
	var accepted := 0
	var began := Time.get_ticks_msec()
	for minute in range(420, 1261, 15):
		var terms := _small("S%d" % minute, minute)
		if _sim.accept_problem(terms) == "":
			assert_bool(_sim.accept_contract(terms)).is_true()
			accepted += 1
	var accept_ms := Time.get_ticks_msec() - began
	var day_one := GameCalendar.day_start(1)
	_run_to(day_one)
	var most := 0
	var paused := {}
	for t in range(day_one, day_one + GameCalendar.TICKS_PER_DAY, 20):
		_sim.on_tick(t)
		var busy := 0
		for gate_id in GATES:
			busy += 1 if _sim.flight_at_gate(gate_id) != "" else 0
		most = maxi(most, busy)
		for id in _sim.flight_ids():
			if _paused(_sim.taxi_plan(id)):
				paused[id] = true
	print(
		(
			"%d of 57 offers accepted in %d ms; at most %d gates busy at once; %d flights paused"
			% [accepted, accept_ms, most, paused.size()]
		)
	)
	assert_int(most).is_greater(3)
	assert_int(paused.size()).is_greater(0)


## The first minute in `minutes` at which `id` departing then is refused for
## `reason` on the shared ground, with the refused flight's id matching
## `flight_of(id)`; -1 for none.
func _refused_minute(id: String, minutes: Array, refused_flight: Callable) -> int:
	for minute: int in minutes:
		var refusal := _sim.accept_refusal(TestFlightContracts.terms(id, minute))
		if refusal.get("reason", "") == GroundPlanner.TAXI_BUSY and refused_flight.call(refusal):
			return minute
	return -1


## X departs gate A at 10:00. An offer at gate B landing while X lands or takes
## off cannot pause on the runway, so it is refused with the ruled text and
## changes nothing; the same offer at a free time is accepted.
func test_an_offer_no_pause_fits_is_refused_taxi_busy() -> void:
	_gates(["A", "B"] as Array[String])
	assert_bool(_sim.accept_contract(TestFlightContracts.terms("X", 600))).is_true()
	var own := func(refusal: Dictionary) -> bool: return refusal["flight"].begins_with("N-")
	var minute := _refused_minute("N", range(601, 760), own)
	print("N is refused TAXI_BUSY at minute %d" % minute)
	assert_int(minute).is_greater(0)
	var terms := TestFlightContracts.terms("N", minute)
	assert_str(_sim.accept_problem(terms)).is_equal("taxi lane busy at that time")
	assert_str(_sim.accept_gate(terms)).is_equal("")
	assert_bool(_sim.accept_contract(terms)).is_false()
	assert_array(_sim.contract_ids()).is_equal(["X"])
	assert_bool(_sim.accept_contract(TestFlightContracts.terms("N", 900))).is_true()


## An offer that would plan first (it starts earlier) but leave X's
## occurrence with no plan is refused (conductor ruling a for R7), though its
## own plan fits; at a free time the same offer is accepted.
func test_an_offer_that_would_leave_an_existing_occurrence_busy_is_refused() -> void:
	_gates(["A", "B"] as Array[String])
	assert_bool(_sim.accept_contract(TestFlightContracts.terms("X", 600))).is_true()
	var existing := func(refusal: Dictionary) -> bool: return refusal["flight"].begins_with("X-")
	var minute := _refused_minute("N", range(599, 440, -1), existing)
	print("N at minute %d would leave X with no plan" % minute)
	assert_int(minute).is_greater(0)
	var terms := TestFlightContracts.terms("N", minute)
	var refusal := _sim.accept_refusal(terms)
	assert_str(_sim.accept_problem(terms)).is_equal(FlightSim.TAXI_BUSY_TEXT)
	# Its own occurrence plans: alone (X planned after it), N fits.
	var alone := auto_free(FlightSim.new()) as FlightSim
	alone.gate_source = func() -> Array[String]: return ["A", "B"] as Array[String]
	alone.open_airport()
	assert_str(alone.accept_problem(terms)).is_empty()
	assert_str(refusal["flight"]).starts_with("X-")
	assert_bool(_sim.accept_contract(terms)).is_false()
	assert_bool(_sim.accept_contract(TestFlightContracts.terms("N", 900))).is_true()
	assert_array(_sim.contract_ids()).is_equal(["X", "N"])


## Gates A and B stand on one stand, C and F on their own, D small-only.
func _shared_stands() -> void:
	var a: Dictionary = FlightGround.fallback("A")["stand"]
	var grounds := {
		"A": {"stand": a, "max_class": PlaneClasses.LARGE},
		"B": {"stand": a.duplicate(), "max_class": PlaneClasses.LARGE},
		"C": FlightGround.fallback("C"),
		"D": {"stand": FlightGround.fallback("E")["stand"], "max_class": PlaneClasses.SMALL},
		"F": FlightGround.fallback("F"),
	}
	_gates(["A", "B", "C", "D", "F"] as Array[String])
	_sim.stand_source = func() -> Dictionary: return grounds


## Accepting, reassigning and moving go through the planner. Y, an hour after
## X, cannot take gate A (X holds it) nor B (its stand is the one X is parked
## on), so it gets C. Moving Y onto B is refused TAXI_BUSY, onto the small gate
## D for its plane; a move that fits changes no issued occurrence's gate or
## plan, and a gate removal's moves (move_plan, move_contracts) do the same.
func test_reassign_and_moves_go_through_the_planner_and_keep_issued_plans() -> void:
	_shared_stands()
	assert_bool(_sim.accept_contract(TestFlightContracts.terms("X", 600))).is_true()
	assert_str(_sim.contract_of("X")["gate"]).is_equal("A")
	assert_bool(_sim.accept_contract(TestFlightContracts.terms("Y", 660))).is_true()
	assert_str(_sim.contract_of("Y")["gate"]).is_equal("C")
	_run_to(1000)
	var before := _live_plans(_sim)
	assert_array(before.keys()).is_equal(["X-d0", "Y-d0"])
	assert_str(_sim.reassign_problem("Y", "A")).is_equal("contract Y clashes with X at gate A")
	assert_str(_sim.reassign_problem("Y", "B")).is_equal(FlightSim.TAXI_BUSY_TEXT)
	assert_str(_sim.reassign_problem("Y", "D")).is_equal("gate D takes no medium plane")
	assert_str(_sim.reassign_problem("Y", "F")).is_empty()
	assert_bool(_sim.reassign_gate("Y", "F")).is_true()
	assert_dict(_live_plans(_sim)).is_equal(before)
	var plan := _sim.move_plan(["F"] as Array[String], ["A", "B", "C", "D"] as Array[String])
	print("moves off F: %s" % plan)
	assert_dict(plan["moves"]).is_equal({"Y": "C"})
	assert_bool(_sim.move_contracts(plan)).is_true()
	assert_dict(_live_plans(_sim)).is_equal(before)
	assert_str(_sim.flight_gate("Y-d0")).is_equal("C")
	_run_to(FlightTimetable.issue_tick(_sim.contract_of("Y"), 1))
	assert_str(_sim.flight_gate("Y-d1")).is_equal("C")


## A day of six gates with pauses saves through JSON and loads into a sim that
## re-plans every live flight exactly; a save whose re-plan fails (two gates
## made to share one stand under live flights) and a version 6 save are refused.
func test_a_save_re_plans_identically_and_a_failing_plan_is_refused() -> void:
	_gates(GATES)
	for minute in range(420, 1261, 15):
		var terms := _small("S%d" % minute, minute)
		if _sim.accept_problem(terms) == "":
			_sim.accept_contract(terms)
	var noon := GameCalendar.tick_at(1, 12 * 60)
	_run_to(noon)
	var plans := _live_plans(_sim)
	var paused := plans.values().filter(func(p: Array) -> bool: return _paused(p[1]))
	print("%d live flights at noon, %d paused" % [plans.size(), paused.size()])
	assert_int(plans.size()).is_greater(3)
	var data: Dictionary = JSON.parse_string(JSON.stringify(_sim.to_snapshot()))
	assert_array(data["landed"]).is_not_empty()
	var loaded := auto_free(FlightSim.new()) as FlightSim
	loaded.gate_source = func() -> Array[String]: return GATES
	assert_bool(loaded.from_snapshot(data.duplicate(true))).is_true()
	assert_dict(_live_plans(loaded)).is_equal(plans)
	assert_str(JSON.stringify(loaded.to_snapshot())).is_equal(JSON.stringify(_sim.to_snapshot()))
	# Two live flights at different gates, moved onto one stand.
	var flights: Array = data["flights"]
	var first: Dictionary = flights[0]
	var other: Dictionary = {}
	for entry: Dictionary in flights:
		var overlap: bool = entry["starts"][0] < first["starts"][10]
		if entry["gate"] != first["gate"] and overlap and entry["state"] < FlightSim.State.TAKEOFF:
			other = entry
			break
	assert_dict(other).is_not_empty()
	var shared := data.duplicate(true)
	for entry: Dictionary in shared["flights"]:
		if entry["gate"] == other["gate"]:
			entry["stand"] = first["stand"].duplicate()
	var on_one := {}
	for gate_id in GATES:
		on_one[gate_id] = FlightGround.fallback(gate_id)
	var stand: Dictionary = first["stand"]
	on_one[other["gate"]] = {
		"stand": StandPlacement.make(int(stand["exit"]), float(stand["x"]), float(stand["wall_z"])),
		"max_class": PlaneClasses.LARGE,
	}
	var refusing := auto_free(FlightSim.new()) as FlightSim
	refusing.gate_source = func() -> Array[String]: return GATES
	refusing.stand_source = func() -> Dictionary: return on_one
	var load_it := func() -> void: refusing.from_snapshot(shared)
	await assert_error(load_it).is_push_error(
		(
			"FlightSim.from_snapshot: flight %s has no taxi plan: %s"
			% [_first_unplanned(shared, on_one), FlightSim.TAXI_BUSY_TEXT]
		)
	)
	assert_array(refusing.flight_ids()).is_empty()
	var old := data.duplicate(true)
	old["save_version"] = 6
	assert_bool(loaded.from_snapshot(old)).is_false()


## The first live flight of `data` that FlightPlans gives no plan on
## `grounds`, as from_snapshot() looks for one.
static func _first_unplanned(data: Dictionary, grounds: Dictionary) -> String:
	var loaded := FlightSnapshot.load(data, GATES)
	var world := {
		"contracts": loaded["contracts"],
		"start_day": loaded["start_day"],
		"next_day": loaded["next_day"],
		"ended": loaded["ended"],
		"reserving": loaded["reserving"],
		"flights": loaded["flights"],
		"landed": loaded["landed"],
		"grounds": grounds,
	}
	var plans := FlightPlans.new()
	for day in FlightPlans.live_days(world):
		var result := plans.plan_day(world, day)
		for flight: Dictionary in loaded["flights"]:
			if FlightPlans.day_of(flight["starts"]) == day and not result[flight["id"]]["ok"]:
				return flight["id"]
	return ""


## PlaneView plays a planned pause: through the pause's ticks the plane stands
## on the hold line, and before and after it it moves.
func test_plane_view_stands_at_the_hold_line_for_the_pause() -> void:
	var airside := TestStandLaneClearance.scene_airside()
	add_child(airside)
	var view := auto_free(PlaneView.new()) as PlaneView
	view.airside = airside
	var starts := GroundPlannerKit.starts_at(1, 600)
	var req := FlightGround.request("P", PlaneClasses.MEDIUM, FlightGround.scene_stand(), starts)
	var options := FlightGround.planner().phase_options(req, FlightSim.State.TAXI_IN)
	var pause: Dictionary = options[options.size() - 1]
	assert_dict(pause).is_not_empty()
	var route: PackedVector3Array = req["routes"][FlightSim.State.TAXI_IN]
	var budget := float(starts[FlightSim.State.AT_STAND] - starts[FlightSim.State.TAXI_IN])
	var plan := MovementPlan.taxi(route, budget, pause)
	var hold := MovementPlan.point_at(route, pause["hold_s"])
	var start := float(starts[FlightSim.State.TAXI_IN])
	var from := start + float(plan["t1"])
	var to := from + float(plan["pause_ticks"])
	var pauses := {FlightSim.State.TAXI_IN: pause}
	var held := 0
	for tick in range(ceili(from), floori(to) + 1):
		var at: Transform3D = (
			view.pose_at(starts, float(tick), true, PlaneClasses.MEDIUM, pauses)["transform"]
		)
		var flat := Vector2(at.origin.x - hold.x, at.origin.z - hold.z)
		assert_float(flat.length()).override_failure_message("tick %d" % tick).is_less(0.01)
		held += 1
	var before: Transform3D = (
		view.pose_at(starts, from - 40.0, true, PlaneClasses.MEDIUM, pauses)["transform"]
	)
	var after: Transform3D = (
		view.pose_at(starts, to + 40.0, true, PlaneClasses.MEDIUM, pauses)["transform"]
	)
	var unpaused: Transform3D = view.pose_at(starts, (from + to) / 2.0)["transform"]
	print(
		(
			"pause %s: held %d ticks at %s; 40 before %s, 40 after %s, unpaused %s"
			% [pause, held, hold, before.origin, after.origin, unpaused.origin]
		)
	)
	assert_int(held).is_greater_equal(int(pause["ticks"]))
	assert_float(Vector2(before.origin.x - hold.x, before.origin.z - hold.z).length()).is_greater(
		1.0
	)
	assert_float(Vector2(after.origin.x - hold.x, after.origin.z - hold.z).length()).is_greater(1.0)
	(
		assert_float(Vector2(unpaused.origin.x - hold.x, unpaused.origin.z - hold.z).length())
		. is_greater(1.0)
	)
	airside.free()


## A FlightPlans that is deliberately not monotone, as greedy planning can be:
## while contract B runs and contract A does not, contract C's occurrences get
## no plan. A sweep of 598 real three-flight worlds (fallback and north-row
## stands, R7 lane) found no such case, so the invariant is shown on this stub.
class NonMonotonePlans:
	extends FlightPlans

	func plan_day(world: Dictionary, day: int) -> Dictionary:
		var out := {}
		var ids := {}
		for req: Dictionary in FlightPlans.requests(world, day):
			ids[FlightTimetable.parse_occurrence(req["id"])["contract"]] = true
		for req: Dictionary in FlightPlans.requests(world, day):
			var contract: String = FlightTimetable.parse_occurrence(req["id"])["contract"]
			var stranded: bool = contract == "C" and ids.has("B") and not ids.has("A")
			out[req["id"]] = {
				"ok": not stranded,
				"reason": GroundPlanner.TAXI_BUSY if stranded else "",
				"pauses": {},
				"bookings": [],
			}
		return out


## Ending a contract must never leave another occurrence with no plan
## (conductor ruling b for R7). Here freeing A's ground would strand C, so A
## keeps reserving it: its days are planned, never flown, and C keeps its plan
## through issue and a save. Ending B strands nobody, so B frees its ground.
func test_ending_a_contract_never_leaves_another_occurrence_unplanned() -> void:
	_gates(["A", "B", "C"] as Array[String])
	_sim._plans = NonMonotonePlans.new()
	for spec: Array in [["A", 600], ["B", 660], ["C", 900]]:
		assert_bool(_sim.accept_contract(TestFlightContracts.terms(spec[0], spec[1]))).is_true()
	_run_to(1000)
	assert_dict(_sim.end_refusal("A")).is_equal({"id": "C-d1", "reason": GroundPlanner.TAXI_BUSY})
	assert_dict(_sim.end_refusal("B")).is_empty()
	assert_bool(_sim.end_contract("A")).is_true()
	assert_bool(_sim.is_reserving("A")).is_true()
	assert_int(_sim.contract_end_day("A")).is_equal(1)
	assert_array(_sim.active_contract_ids()).is_equal(["B", "C"])
	# A's later days are never issued, and C's are issued with a plan.
	_run_to(FlightTimetable.issue_tick(_sim.contract_of("C"), 1))
	assert_bool(_sim.flight_ids().has("A-d1")).is_false()
	assert_bool(_sim.flight_ids().has("C-d1")).is_true()
	await assert_error(func() -> void: _sim.taxi_plan("C-d1")).is_success()
	var data: Dictionary = JSON.parse_string(JSON.stringify(_sim.to_snapshot()))
	assert_array(data["reserving"]).is_equal(["A"])
	var loaded := auto_free(FlightSim.new()) as FlightSim
	loaded.gate_source = func() -> Array[String]: return ["A", "B", "C"] as Array[String]
	loaded._plans = NonMonotonePlans.new()
	assert_bool(loaded.from_snapshot(data)).is_true()
	assert_bool(loaded.is_reserving("A")).is_true()
	await assert_error(func() -> void: loaded.taxi_plan("C-d1")).is_success()
	# Control: freed of the reservation, C-d1 would have no plan.
	var freed := data.duplicate(true)
	freed["reserving"] = []
	var strict := auto_free(FlightSim.new()) as FlightSim
	strict.gate_source = loaded.gate_source
	strict._plans = NonMonotonePlans.new()
	assert_bool(strict.from_snapshot(freed)).is_false()
	# Ending B strands nobody: it frees its ground.
	assert_bool(_sim.end_contract("B")).is_true()
	assert_bool(_sim.is_reserving("B")).is_false()
