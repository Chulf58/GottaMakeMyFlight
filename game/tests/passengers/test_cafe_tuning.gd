class_name TestCafeTuning
extends GdUnitTestSuite
## Cafe tuning (decision cafe-tuning-some-passengers-visit-a-cafe-each-flight):
## in an ordinary flight about a quarter to a third of the passengers who
## arrive early use a cafe, and rushed ones still skip it. Measured on the
## reference flight: the reference terminal with its two cafes and two tables
## in each (CafeTestLayout with `extra_tables`), DEFAULT_PASSENGERS on the
## default timing, scheduled from
## the sim RNG as in play, over several seeds pooled. Early means spawned
## before boarding opens; using a cafe means a visit that paid. No paying
## passenger may miss its flight.

const SEEDS: Array[int] = [11, 22, 44, 55]
## The band in whole percent of early arrivals: 25% to 33%, the target of
## decision cafe-tuning-some-passengers-visit-a-cafe-each-flight once arrival
## types landed. With one table per cafe, relaxed passengers fill both seats
## and the share falls to 11% for typical passengers, so the reference cafe
## has two tables (decision
## cafe-seats-the-reference-cafe-gets-2-tables-so-typical-passe).
const SHARE_MIN := 25
const SHARE_MAX := 33

var _spawned: Dictionary = {}
var _rushed: Dictionary = {}
var _paid: Dictionary = {}
var _missed: Dictionary = {}


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


## One flight: {"early", "early_paid", "non_rushed", "non_rushed_paid",
## "rushed", "rushed_paid", "paid_missed"}.
func _flight(seed: int) -> Dictionary:
	_spawned.clear()
	_rushed.clear()
	_paid.clear()
	_missed.clear()
	var grid := BuildGrid.new()
	CafeTestLayout.build(grid, true)
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), seed)
	var sim := world.sim
	sim.passenger_spawned.connect(
		func(id: int) -> void:
			_spawned[id] = sim.tick
			_rushed[id] = sim.get_passenger(id).arrival_type == ArrivalTypes.Type.RUSHED
	)
	sim.cafes.paid.connect(func(id: int, _room: int, _amount: int) -> void: _paid[id] = true)
	sim.outcome.connect(func(id: int, made: bool) -> void: _missed[id] = not made)
	var count := PassengerSim.DEFAULT_PASSENGERS
	# Scheduled when the arrival window opens, as the flight is issued well ahead
	# of it in the game; passengers are timed against departure.
	var opens := (
		world.flights.state_start(PassengerTestWorld.FLIGHT, FlightSim.State.PUSHBACK)
		- ArrivalTypes.ARRIVAL_OPENS_BEFORE_DEPARTURE_TICKS
	)
	world.run_to(opens)
	assert_bool(sim.schedule_flight(PassengerTestWorld.FLIGHT, count)).is_true()
	var boarding := world.flights.boarding_window(PassengerTestWorld.FLIGHT).x
	var doors := world.flights.doors_close_tick(PassengerTestWorld.FLIGHT)
	while _missed.size() < count and world.clock.tick <= doors:
		world.step()
	var out := {
		"early": 0,
		"early_paid": 0,
		"non_rushed": 0,
		"non_rushed_paid": 0,
		"rushed": 0,
		"rushed_paid": 0,
		"paid_missed": 0,
	}
	for id: int in _spawned:
		if int(_spawned[id]) < boarding:
			out["early"] += 1
			if _paid.has(id):
				out["early_paid"] += 1
		var cohort := "rushed" if bool(_rushed[id]) else "non_rushed"
		out[cohort] += 1
		if _paid.has(id):
			out[cohort + "_paid"] += 1
			out["paid_missed"] += int(_missed.get(id, true))
	world.free_all()
	return out


func test_a_quarter_to_a_third_of_early_arrivals_use_a_cafe_and_all_make_it() -> void:
	var total := {
		"early": 0,
		"early_paid": 0,
		"non_rushed": 0,
		"non_rushed_paid": 0,
		"rushed": 0,
		"rushed_paid": 0,
		"paid_missed": 0,
	}
	for seed in SEEDS:
		var flight := _flight(seed)
		print("seed %d: %s" % [seed, flight])
		for key: String in total:
			total[key] += flight[key]
	@warning_ignore("integer_division")
	var share: int = total["early_paid"] * 100 / maxi(total["early"], 1)
	print(
		(
			"pooled: %s; early share %d%% (hunger start %d-%d, rise every %ds, hungry at %d)"
			% [
				total,
				share,
				CafeSim.HUNGER_START_MIN,
				CafeSim.HUNGER_START_MAX,
				CafeSim.HUNGER_RISE_BEATS,
				CafeSim.HUNGRY_AT,
			]
		)
	)
	# The flights spawned their passengers, and enough of them arrived early.
	assert_int(total["early"]).is_greater(SEEDS.size() * 8)
	assert_int(share).is_between(SHARE_MIN, SHARE_MAX)
	# Rushed passengers mostly skip the cafe: a smaller share than non-rushed ones.
	assert_int(total["rushed"]).is_greater(0)
	assert_int(total["rushed_paid"] * total["non_rushed"]).is_less(
		total["non_rushed_paid"] * total["rushed"]
	)
	# A visit never cost a passenger its flight.
	assert_int(total["paid_missed"]).is_equal(0)
