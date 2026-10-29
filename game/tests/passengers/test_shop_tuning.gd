class_name TestShopTuning
extends GdUnitTestSuite
## Kiosk tuning (Boredom 2/5; decision boredom-and-shops-design-boredom-need-
## while-waiting-kiosk-sh, point 2), measured like test_boredom_tuning: the
## reference terminal with the floor east of it (ShopTestLayout),
## DEFAULT_PASSENGERS scheduled from the sim RNG as in play, the flight's first
## state FIRST_STATE ticks after the schedule so relaxed arrivals get their
## whole window, over several seeds pooled. Each seed is played twice: with a
## kiosk on each side of security, and on the same floor with none. The dwell
## and base spend are set so that a kiosk takes a fair share of the early
## arrivals, cuts how many are bored when boarding opens, earns a readable sum
## a flight, and never costs a passenger the flight.

const SEEDS: Array[int] = [11, 22, 33, 44, 55, 66]
const FIRST_STATE := 1700
## The band in whole percent of early arrivals who finish a browse: 25% to
## 40%. Browsing 120 ticks (the cafe's dwell) at base spend 12 gives, on these
## seeds, 33% (33 of 99), 42 visits at 16 a visit (117 a flight), and 8 early
## arrivals bored at boarding against 35 with no kiosk; nobody who went
## missed the flight.
const SHARE_MIN := 25
const SHARE_MAX := 40

var _spawned: Dictionary = {}
var _went: Dictionary = {}
var _browsed: Dictionary = {}
var _missed: Dictionary = {}


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func _empty() -> Dictionary:
	return {
		"early": 0,
		"early_bored": 0,
		"early_browsed": 0,
		"visits": 0,
		"spend": 0,
		"went_missed": 0,
	}


## One flight's counts (_empty()'s keys), with kiosks or without.
func _flight(seed: int, kiosks: bool) -> Dictionary:
	for map in [_spawned, _went, _browsed, _missed]:
		map.clear()
	var grid := BuildGrid.new()
	ShopTestLayout.build(grid, ["air", "land"] if kiosks else [])
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(FIRST_STATE), seed)
	var sim := world.sim
	sim.passenger_spawned.connect(func(id: int) -> void: _spawned[id] = sim.tick)
	sim.stage_changed.connect(
		func(id: int, stage: Passenger.Stage) -> void:
			if stage == Passenger.Stage.SHOP_WALK:
				_went[id] = true
	)
	var out := _empty()
	sim.shops.paid.connect(
		func(id: int, _room: int, amount: int) -> void:
			_browsed[id] = true
			out["visits"] += 1
			out["spend"] += amount
	)
	sim.outcome.connect(func(id: int, made: bool) -> void: _missed[id] = not made)
	var count := PassengerSim.DEFAULT_PASSENGERS
	assert_bool(sim.schedule_flight(PassengerTestWorld.FLIGHT, count)).is_true()
	var boarding := world.flights.boarding_window(PassengerTestWorld.FLIGHT).x
	world.run_to(boarding)
	for id: int in _spawned:
		var p := sim.get_passenger(id)
		if p == null or int(_spawned[id]) >= boarding:
			continue
		out["early"] += 1
		out["early_bored"] += int(p.boredom >= BoredomSim.BORED_AT)
		out["early_browsed"] += int(_browsed.has(id))
	world.run_to(world.flights.doors_close_tick(PassengerTestWorld.FLIGHT) + 1)
	for id: int in _went:
		out["went_missed"] += int(_missed.get(id, true))
	return out


func test_a_kiosk_takes_a_fair_share_cuts_boredom_and_costs_no_flight() -> void:
	var with := _empty()
	var without := _empty()
	for seed in SEEDS:
		var a := _flight(seed, true)
		var b := _flight(seed, false)
		print("seed %d: kiosk %s; none %s" % [seed, a, b])
		for key: String in with:
			with[key] += a[key]
			without[key] += b[key]
	@warning_ignore("integer_division")
	var share: int = with["early_browsed"] * 100 / maxi(with["early"], 1)
	@warning_ignore("integer_division")
	var per_visit: int = with["spend"] / maxi(with["visits"], 1)
	@warning_ignore("integer_division")
	var per_flight: int = with["spend"] / SEEDS.size()
	print(
		(
			(
				"pooled kiosk %s; none %s; early browsed %d%%, %d a visit, %d a flight"
				+ " (browse %d ticks, base spend %d)"
			)
			% [
				with,
				without,
				share,
				per_visit,
				per_flight,
				ShopSim.BROWSE_TICKS,
				RoomTypes.get_type(&"kiosk").base_spend
			]
		)
	)
	assert_int(with["early"]).is_greater(SEEDS.size() * 8)
	assert_int(share).is_between(SHARE_MIN, SHARE_MAX)
	# Boredom at boarding drops when a kiosk is reachable: at most half as many.
	assert_int(without["early_bored"]).is_greater(SEEDS.size())
	assert_int(with["early_bored"] * 2).is_less_equal(without["early_bored"])
	# Nobody who set off for the kiosk missed the flight.
	assert_int(with["went_missed"]).is_equal(0)
	assert_int(without["visits"]).is_equal(0)
