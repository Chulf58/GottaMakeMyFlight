class_name TestWishTuning
extends GdUnitTestSuite
## Shopping wish tuning (ruling store-variety-passengers-have-a-shopping-
## wish-weighted-by-arrival-type-unmet-settles-for-less; WishTable weights,
## ShopSim.FALLBACK_SHARE and FALLBACK_MOOD), measured like test_shop_tuning:
## DEFAULT_PASSENGERS scheduled from the sim RNG as in play, the flight's
## first state FIRST_STATE ticks after the schedule so relaxed arrivals get
## their whole window, over several seeds pooled, with the wishes WishTable
## gives. The reference layout is an airside kiosk and fashion store
## (WishTestLayout); each seed is played again with a duty free store added,
## the kind most relaxed wishers miss there. Per arrival type it prints the
## bored relief visits started, how many were by passengers with no wish, of
## the wished kind (fulfilled) and settling for another kind (fallbacks), and
## the shop revenue, spare-time browses included. Adding the missing kind
## turns fallbacks into fulfilled visits and raises the revenue. On these
## seeds every relief visit is a relaxed arrival's (they wait longest, as in
## test_boredom_tuning), so the rushed and typical rows hold none.

const SEEDS: Array[int] = [11, 22, 33, 44, 55, 66]
const FIRST_STATE := 1700
const REFERENCE: Array[StringName] = [&"kiosk", &"fashion"]
const WITH_DUTY_FREE: Array[StringName] = [&"kiosk", &"fashion", &"duty_free"]

## Passenger id -> the ShopVisit already counted for it.
var _counted: Dictionary = {}


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func _empty() -> Dictionary:
	var out := {}
	for name in ArrivalTypes.NAMES:
		out[name] = {"relief": 0, "no_wish": 0, "fulfilled": 0, "fallbacks": 0, "revenue": 0}
	return out


## One flight's counts per arrival type name (_empty()'s keys).
func _flight(seed: int, types: Array[StringName]) -> Dictionary:
	_counted.clear()
	var grid := BuildGrid.new()
	WishTestLayout.build(grid, types)
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(FIRST_STATE), seed)
	var sim := world.sim
	var out := _empty()
	sim.stage_changed.connect(
		func(id: int, _stage: Passenger.Stage) -> void:
			var visit := sim.shops.visit_of(id)
			if visit == null or _counted.get(id) == visit:
				return
			_counted[id] = visit
			var p := sim.get_passenger(id)
			if not BoredomSim.is_bored(p):
				return
			var row: Dictionary = out[ArrivalTypes.NAMES[p.arrival_type]]
			row["relief"] += 1
			if sim.shops.wish_of(p) == WishTable.NONE:
				row["no_wish"] += 1
			else:
				row["fallbacks" if visit.fallback else "fulfilled"] += 1
	)
	sim.shops.paid.connect(
		func(id: int, _room: int, amount: int) -> void:
			var p := sim.get_passenger(id)
			out[ArrivalTypes.NAMES[p.arrival_type]]["revenue"] += amount
	)
	var count := PassengerSim.DEFAULT_PASSENGERS
	assert_bool(sim.schedule_flight(PassengerTestWorld.FLIGHT, count)).is_true()
	world.run_to(world.flights.doors_close_tick(PassengerTestWorld.FLIGHT) + 1)
	world.free_all()
	return out


func _add(total: Dictionary, flight: Dictionary) -> void:
	for name: String in total:
		for key: String in total[name]:
			total[name][key] += flight[name][key]


func _sum(total: Dictionary, key: String) -> int:
	var sum := 0
	for name: String in total:
		sum += int(total[name][key])
	return sum


func test_a_missing_kind_costs_revenue_that_adding_it_wins_back() -> void:
	var reference := _empty()
	var added := _empty()
	for seed in SEEDS:
		_add(reference, _flight(seed, REFERENCE))
		_add(added, _flight(seed, WITH_DUTY_FREE))
	for name in ArrivalTypes.NAMES:
		print("%s: kiosk+fashion %s; +duty free %s" % [name, reference[name], added[name]])
	print(
		(
			(
				"pooled over %d flights: kiosk+fashion relief %d, no wish %d, fulfilled %d,"
				+ " fallbacks %d, revenue %d; +duty free relief %d, no wish %d, fulfilled %d,"
				+ " fallbacks %d, revenue %d (fallback share %.2f, mood %d)"
			)
			% [
				SEEDS.size(),
				_sum(reference, "relief"),
				_sum(reference, "no_wish"),
				_sum(reference, "fulfilled"),
				_sum(reference, "fallbacks"),
				_sum(reference, "revenue"),
				_sum(added, "relief"),
				_sum(added, "no_wish"),
				_sum(added, "fulfilled"),
				_sum(added, "fallbacks"),
				_sum(added, "revenue"),
				ShopSim.FALLBACK_SHARE,
				ShopSim.FALLBACK_MOOD,
			]
		)
	)
	# Bored passengers did visit, some of the wished kind and some settling.
	assert_int(_sum(reference, "relief")).is_greater(SEEDS.size() * 3)
	assert_int(_sum(reference, "fulfilled")).is_greater(0)
	assert_int(_sum(reference, "fallbacks")).is_greater(0)
	# The duty free store turns fallbacks into wished visits and earns more.
	assert_int(_sum(added, "fallbacks")).is_less(_sum(reference, "fallbacks"))
	assert_int(_sum(added, "revenue")).is_greater(_sum(reference, "revenue"))
