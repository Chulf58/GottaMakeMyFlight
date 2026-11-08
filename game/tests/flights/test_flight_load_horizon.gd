class_name TestFlightLoadHorizon
extends GdUnitTestSuite
## A flight save loads only if every request the game will fly plans (decision
## runway-and-taxi-technical-design-movement-plan-analytic-bookings-planned-
## pauses, section 8): FlightSim re-plans FlightPlans.horizon(), the live and
## landed flights and every running or reserving contract's days, not only the
## live flights. So a quiet-night or closed save with no live flight, a
## reserving contract, and a landed occurrence all refuse a plan that fails; and
## a gate too small for a live flight or a running contract refuses the save.
##
## The saving sim stands gates A and B on their own stands (FlightGround
## fallbacks); the loading sim stands B on A's, so two flights of A and B that
## overlap in time meet on one stand.

const GATES: Array[String] = ["A", "B"]
## X departs at 10:00 from A and N 40 minutes later from B (the runway takes both).
const X_MINUTE := 600
const N_MINUTE := 640
const FAR_MINUTE := 900


## A sim on gates A and B, on `grounds` ({} for the fallback stands).
func _sim(grounds := {}) -> FlightSim:
	var sim := auto_free(FlightSim.new()) as FlightSim
	sim.gate_source = func() -> Array[String]: return GATES
	if not grounds.is_empty():
		sim.stand_source = func() -> Dictionary: return grounds
	return sim


## Gate B on gate A's stand.
static func _shared() -> Dictionary:
	var a: Dictionary = FlightGround.fallback("A")["stand"]
	return {
		"A": {"stand": a, "max_class": PlaneClasses.LARGE},
		"B": {"stand": a.duplicate(), "max_class": PlaneClasses.LARGE},
	}


## The snapshot of a sim (open unless `closed`) holding X at A and N at B,
## run to tick `until`, through JSON.
func _saved(n_minute: int, until: int, closed := false) -> Dictionary:
	var sim := _sim()
	if not closed:
		sim.open_airport()
	for terms in [
		TestFlightContracts.terms("X", X_MINUTE), TestFlightContracts.terms("N", n_minute)
	]:
		assert_str(sim.accept_problem(terms)).is_empty()
		assert_bool(sim.accept_contract(terms)).is_true()
	for t in range(1, until + 1):
		sim.on_tick(t)
	return JSON.parse_string(JSON.stringify(sim.to_snapshot()))


## The quiet night after day 0: nothing live or landed.
func _quiet_night(n_minute: int) -> Dictionary:
	var data := _saved(n_minute, GameCalendar.tick_at(1, 0))
	assert_array(data["flights"]).is_empty()
	assert_array(data["landed"]).is_empty()
	return data


func test_a_quiet_night_save_whose_contracts_collide_is_refused_and_a_clear_one_loads() -> void:
	var colliding := _quiet_night(N_MINUTE)
	var problem := _sim(_shared()).load_problem(colliding)
	print("quiet night, colliding: '%s'" % problem)
	assert_str(problem).contains("has no taxi plan")
	var refusing := _sim(_shared())
	var load_it := func() -> void: refusing.from_snapshot(colliding.duplicate(true))
	await assert_error(load_it).is_push_error("FlightSim.from_snapshot: %s" % problem)
	assert_array(refusing.contract_ids()).is_empty()
	# Controls: the same save on the stands it was made on, and a pair far apart.
	assert_str(_sim().load_problem(colliding)).is_empty()
	var clear := _quiet_night(FAR_MINUTE)
	assert_str(_sim(_shared()).load_problem(clear)).is_empty()
	var loaded := _sim(_shared())
	assert_bool(loaded.from_snapshot(clear)).is_true()
	assert_array(loaded.contract_ids()).is_equal(["X", "N"])


func test_a_closed_save_whose_contracts_collide_is_refused() -> void:
	var colliding := _saved(N_MINUTE, 1, true)
	assert_int(int(colliding["opened_tick"])).is_equal(-1)
	assert_array(colliding["flights"]).is_empty()
	var problem := _sim(_shared()).load_problem(colliding)
	print("closed, colliding: '%s'" % problem)
	assert_str(problem).contains("has no taxi plan")
	assert_str(_sim().load_problem(colliding)).is_empty()
	var clear := _saved(FAR_MINUTE, 1, true)
	assert_str(_sim(_shared()).load_problem(clear)).is_empty()


## N has ended but still reserves its ground, so its days are planned as if it
## ran; with no reservation the same save loads.
func test_a_reserving_contract_is_planned_and_refused_when_it_collides() -> void:
	var data := _quiet_night(N_MINUTE)
	data["ended"] = {"N": int(data["next_day"]["N"])}
	data["reserving"] = ["N"]
	var problem := _sim(_shared()).load_problem(data)
	print("reserving, colliding: '%s'" % problem)
	assert_str(problem).contains("has no taxi plan")
	assert_str(problem).contains("N-d")
	var released := data.duplicate(true)
	released["reserving"] = []
	assert_str(_sim(_shared()).load_problem(released)).is_empty()


## Both of day 0's flights have landed and been pruned (landed, none live). The
## stands are the sim's own; N's landed entry is moved onto X's stand, where it
## overlaps X's, so only the landed request can fail.
func test_a_landed_occurrence_that_no_longer_plans_is_refused() -> void:
	var data := _saved(N_MINUTE, GameCalendar.tick_at(0, 20 * 60))
	assert_array(data["flights"]).is_empty()
	assert_int((data["landed"] as Array).size()).is_equal(2)
	assert_str(_sim().load_problem(data)).is_empty()
	var moved := data.duplicate(true)
	var x_stand := {}
	for entry: Dictionary in moved["landed"]:
		if entry["contract"] == "X":
			x_stand = entry["stand"]
	for entry: Dictionary in moved["landed"]:
		if entry["contract"] == "N":
			entry["stand"] = x_stand.duplicate()
	var problem := _sim().load_problem(moved)
	print("landed, moved: '%s'" % problem)
	assert_str(problem).contains("has no taxi plan")


## Gate A takes only small planes in the loading sim: X, a medium contract that
## runs there, refuses the save, and with a flight of X live, that flight does.
func test_a_gate_too_small_for_a_contract_or_a_live_flight_refuses_the_save() -> void:
	var small_a := {
		"A": {"stand": FlightGround.fallback("A")["stand"], "max_class": PlaneClasses.SMALL},
		"B": FlightGround.fallback("B"),
	}
	var night := _quiet_night(FAR_MINUTE)
	var problem := _sim(small_a).load_problem(night)
	print("small gate, contract: '%s'" % problem)
	assert_str(problem).is_equal("contract X needs a medium gate, but gate A takes small")
	var live := _saved(FAR_MINUTE, GameCalendar.tick_at(0, 10 * 60 + 5))
	assert_array(live["flights"]).is_not_empty()
	problem = _sim(small_a).load_problem(live)
	print("small gate, live flight: '%s'" % problem)
	assert_str(problem).is_equal("flight X-d0 needs a medium gate, but gate A takes small")
	assert_str(_sim().load_problem(live)).is_empty()


## A reserving contract's next day never advances, so it can lie years behind a
## running contract's. Only the days where the requests change are planned
## (FlightPlans.days_from), not every day between: X reserves from day 1 and N
## runs from day 5000, and on a shared stand their day-5000 flights collide.
func test_a_gap_of_years_between_next_days_plans_only_the_days_that_differ() -> void:
	var data := _quiet_night(N_MINUTE)
	var loaded := FlightSnapshot.load(data, GATES)
	loaded["ended"] = {"X": 1}
	loaded["reserving"] = {"X": true}
	loaded["next_day"] = {"X": 1, "N": 5000}
	loaded["start_day"]["N"] = 5000
	var world := {
		"contracts": loaded["contracts"],
		"start_day": loaded["start_day"],
		"next_day": loaded["next_day"],
		"ended": loaded["ended"],
		"reserving": loaded["reserving"],
		"flights": loaded["flights"],
		"landed": loaded["landed"],
		"grounds": _shared(),
	}
	var days := FlightPlans.horizon(world)
	print("days planned across a 5000 day gap: %s" % [days])
	assert_array(days).is_equal([1, 5000])
	var refusal := FlightPlans.new().refusal(
		world, func(_day: int) -> Dictionary: return {}, days, ["X", "N"]
	)
	print("refusal: %s" % [refusal])
	assert_str(refusal.get("id", "")).ends_with("-d5000")
	# Control: on their own stands the same two contracts plan on every sampled day.
	world["grounds"] = {"A": FlightGround.fallback("A"), "B": FlightGround.fallback("B")}
	(
		assert_dict(
			FlightPlans.new().refusal(
				world, func(_day: int) -> Dictionary: return {}, days, ["X", "N"]
			)
		)
		. is_empty()
	)
