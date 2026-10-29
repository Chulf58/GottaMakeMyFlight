class_name TestScreenTuning
extends GdUnitTestSuite
## Screen tuning (Boredom 4/5; decision boredom-and-shops-design-boredom-need-
## while-waiting-kiosk-sh, point 3), measured like test_shop_tuning: the
## reference terminal with the floor east of it (ShopTestLayout),
## DEFAULT_PASSENGERS scheduled from the sim RNG as in play, the flight's first
## state FIRST_STATE ticks after the schedule, over several seeds pooled. Each
## seed is played four ways on the same floor: nothing, a kiosk on each side of
## security (shops), two screen stands at the gate (screens), and both (mixed).
## Per arrival type it counts the passengers still in the terminal the tick
## before boarding opens ("waiting"), how many of them are bored and their
## mood, and per flight the kiosk visits and takings and the flights made and
## missed.
##
## The relief rate is set so that screens help (fewer bored, better mood at
## boarding than with nothing) while a kiosk stays the faster relief: one
## browse clears boredom, a screen takes it down RELIEF every RELIEF_BEATS
## seconds. With both, the kiosks keep a share of their takings
## (MIXED_TAKINGS_MIN to MIXED_TAKINGS_MAX) and nobody misses the flight.

const SEEDS: Array[int] = [11, 22, 33, 44, 55, 66]
const FIRST_STATE := 1700
const CONFIGS: Array[String] = ["none", "shops", "screens", "mixed"]
## The gate's two screens: on the airside row south of the seat rows, facing
## north over them, clear of the scanners' exits at x 17 and 19.
const SCREENS: Array[Vector2i] = [Vector2i(12, 8), Vector2i(15, 8)]
const SCREEN_FACING := 2
## The band in whole percent of their takings alone that the kiosks keep with
## the gate screens as well. A screen stops the rise for everyone it covers,
## so the passengers who get bored waiting at the gate, most of a kiosk's
## custom, no longer detour; the kiosks keep the ones who arrive bored and the
## spare-time browsers. Measured on these seeds with relief 1 every 2 beats:
## nothing 35 of 99 bored at boarding, mean mood 68; shops 8 bored, mood 77,
## 42 visits taking 702; screens 0 bored, mood 80; mixed 0 bored, mood 79, 8
## visits taking 127 (18%). Every flight made by all 144 in every setup.
const MIXED_TAKINGS_MIN := 10
const MIXED_TAKINGS_MAX := 40

var _type_of: Dictionary = {}
var _went: Dictionary = {}
var _made: Dictionary = {}


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func _empty() -> Dictionary:
	var out := {"visits": 0, "spend": 0, "made": 0, "missed": 0, "went_missed": 0}
	for type: String in ArrivalTypes.Type.keys():
		out[type] = {"waiting": 0, "bored": 0, "mood": 0, "made": 0, "missed": 0}
	return out


## One flight's counts (_empty()'s keys) for one of CONFIGS.
func _flight(seed: int, config: String) -> Dictionary:
	for map in [_type_of, _went, _made]:
		map.clear()
	var grid := BuildGrid.new()
	var kiosks := config == "shops" or config == "mixed"
	ShopTestLayout.build(grid, ["air", "land"] if kiosks else [])
	if config == "screens" or config == "mixed":
		for cell in SCREENS:
			PassengerTestWorld.place(grid, ScreenCoverage.SCREEN_ID, cell, SCREEN_FACING)
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(FIRST_STATE), seed)
	var sim := world.sim
	var out := _empty()
	sim.passenger_spawned.connect(
		func(id: int) -> void:
			_type_of[id] = ArrivalTypes.Type.keys()[sim.get_passenger(id).arrival_type]
	)
	sim.stage_changed.connect(
		func(id: int, stage: Passenger.Stage) -> void:
			if stage == Passenger.Stage.SHOP_WALK:
				_went[id] = true
	)
	sim.shops.paid.connect(
		func(_id: int, _room: int, amount: int) -> void:
			out["visits"] += 1
			out["spend"] += amount
	)
	sim.outcome.connect(func(id: int, made: bool) -> void: _made[id] = made)
	var count := PassengerSim.DEFAULT_PASSENGERS
	assert_bool(sim.schedule_flight(PassengerTestWorld.FLIGHT, count)).is_true()
	# The tick before boarding opens, while the gate is still waiting.
	world.run_to(world.flights.boarding_window(PassengerTestWorld.FLIGHT).x - 1)
	for id: int in _type_of:
		var p := sim.get_passenger(id)
		if p == null or p.is_done():
			continue
		var row: Dictionary = out[_type_of[id]]
		row["waiting"] += 1
		row["bored"] += int(BoredomSim.is_bored(p))
		row["mood"] += p.mood
	world.run_to(world.flights.doors_close_tick(PassengerTestWorld.FLIGHT) + 1)
	for id: int in _type_of:
		var made: bool = _made.get(id, false)
		var key := "made" if made else "missed"
		out[key] += 1
		out[_type_of[id]][key] += 1
		out["went_missed"] += int(_went.has(id) and not made)
	return out


func _add(into: Dictionary, part: Dictionary) -> void:
	for key: String in part:
		if part[key] is Dictionary:
			_add(into[key], part[key])
		else:
			into[key] += part[key]


## The pooled totals over every arrival type: waiting, bored, mood.
func _waiting(totals: Dictionary) -> Dictionary:
	var out := {"waiting": 0, "bored": 0, "mood": 0}
	for type: String in ArrivalTypes.Type.keys():
		for key: String in out:
			out[key] += totals[type][key]
	return out


func test_screens_help_the_waiting_and_shops_stay_the_faster_relief() -> void:
	var pooled := {}
	for config in CONFIGS:
		pooled[config] = _empty()
	for seed in SEEDS:
		for config in CONFIGS:
			var counts := _flight(seed, config)
			_add(pooled[config], counts)
	for config in CONFIGS:
		var total: Dictionary = pooled[config]
		var waiting := _waiting(total)
		@warning_ignore("integer_division")
		var mood: int = waiting["mood"] / maxi(waiting["waiting"], 1)
		print(
			(
				(
					"%s: waiting at boarding %d, bored %d, mean mood %d; visits %d, takings %d;"
					+ " made %d missed %d (went and missed %d)"
				)
				% [
					config,
					waiting["waiting"],
					waiting["bored"],
					mood,
					total["visits"],
					total["spend"],
					total["made"],
					total["missed"],
					total["went_missed"],
				]
			)
		)
		for type: String in ArrivalTypes.Type.keys():
			print("  %s %s" % [type, total[type]])
	print(
		(
			"relief %d every %d beats; kiosk browse %d ticks; screens at %s facing %d"
			% [
				BoredomSim.RELIEF,
				BoredomSim.RELIEF_BEATS,
				ShopSim.BROWSE_TICKS,
				SCREENS,
				SCREEN_FACING
			]
		)
	)
	var none := _waiting(pooled["none"])
	var screens := _waiting(pooled["screens"])
	var shops := _waiting(pooled["shops"])
	var mixed := _waiting(pooled["mixed"])
	assert_int(none["waiting"]).is_greater(SEEDS.size() * 10)
	assert_int(none["bored"]).is_greater(SEEDS.size())
	# Screens help: fewer bored and a better mood at boarding than with nothing.
	assert_int(screens["bored"]).is_less(none["bored"])
	assert_int(screens["mood"] * none["waiting"]).is_greater(none["mood"] * screens["waiting"])
	# Both together leave no more bored than either alone.
	assert_int(mixed["bored"]).is_less_equal(mini(shops["bored"], screens["bored"]))
	# A kiosk is the faster relief: one browse clears a bored passenger's
	# boredom in BROWSE_TICKS, a screen takes many times longer to do the same.
	@warning_ignore("integer_division")
	var browse_beats := ShopSim.BROWSE_TICKS / PassengerSim.BEAT_TICKS
	var screen_beats := BoredomSim.BORED_AT * BoredomSim.RELIEF_BEATS / BoredomSim.RELIEF
	assert_int(screen_beats).is_greater(4 * browse_beats)
	# Screens take custom from the kiosks but do not empty them, and nobody who
	# went missed the flight.
	@warning_ignore("integer_division")
	var kept: int = pooled["mixed"]["spend"] * 100 / maxi(pooled["shops"]["spend"], 1)
	print("kiosks keep %d%% of their takings with screens as well" % kept)
	assert_int(pooled["shops"]["spend"]).is_greater(0)
	assert_int(kept).is_between(MIXED_TAKINGS_MIN, MIXED_TAKINGS_MAX)
	assert_int(pooled["shops"]["went_missed"]).is_equal(0)
	assert_int(pooled["mixed"]["went_missed"]).is_equal(0)
	# Screens cost no flights.
	assert_int(pooled["screens"]["missed"]).is_less_equal(pooled["none"]["missed"])
	assert_int(pooled["mixed"]["missed"]).is_less_equal(pooled["shops"]["missed"])
	assert_int(pooled["screens"]["visits"]).is_equal(0)
