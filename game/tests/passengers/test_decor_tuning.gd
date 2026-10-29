class_name TestDecorTuning
extends GdUnitTestSuite
## Decor tuning (decision furniture-set-modelled-on-copenhagen-airport-decor-
## calms-pas). The numbers are pinned in TABLE_PINS and the constants below,
## each with its reason in DecorEffect, so a change to one is a change to this
## test. Then the reference terminal is flown through SEEDS with and without
## decor in its gate, as in test_screen_tuning: the mood of the passengers who
## make their flight is what AirportRating records, so decor must raise its
## mean a little, never past the ceiling's reach, and must cost no flight.

const SEEDS: Array[int] = [11, 22, 33]
## Catalog id -> [calm per period, radius in cells].
const TABLE_PINS := {
	&"fountain_indoor": [3, 4],
	&"statue_indoor": [2, 4],
	&"tree_indoor": [2, 3],
	&"bench_2a_indoor": [2, 2],
	&"plant_pot_2a": [1, 2],
	&"plant_pot_1a": [1, 2],
	&"bench_1a": [1, 1],
	&"bush": [1, 1],
	&"trash_can": [0, 0],
	&"metal_pole": [0, 0],
	&"metal_pole_chain": [0, 0],
}
## The decor in the reference terminal's airside gate (x 10-21, y 2-8), on free
## floor clear of the seat rows, the scanners' exits and the exit door.
const GATE_DECOR := [
	[&"fountain_indoor", Vector2i(17, 4)],
	[&"statue_indoor", Vector2i(21, 6)],
	[&"plant_pot_1a", Vector2i(21, 3)],
]
## The mean mood of those who made it, with decor, may rise this much over none
## (whole points, pooled): measured on SEEDS, see the printed line.
const MEAN_GAIN_MIN := 1
const MEAN_GAIN_MAX := 10


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


## One flight's {"made", "missed", "mood_sum"} with or without GATE_DECOR.
func _flight(seed: int, with_decor: bool) -> Dictionary:
	var grid := BuildGrid.new()
	assert_bool(ReferenceTerminal.build(grid)).is_true()
	if with_decor:
		for piece: Array in GATE_DECOR:
			PassengerTestWorld.place(grid, piece[0], piece[1], 0)
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), seed)
	var sim := world.sim
	var out := {"made": 0, "missed": 0, "mood_sum": 0}
	sim.outcome.connect(
		func(id: int, made: bool) -> void:
			if made:
				out["made"] += 1
				out["mood_sum"] += sim.get_passenger(id).mood
			else:
				out["missed"] += 1
	)
	(
		assert_bool(sim.schedule_flight(PassengerTestWorld.FLIGHT, PassengerSim.DEFAULT_PASSENGERS))
		. is_true()
	)
	world.run_to(world.flights.doors_close_tick(PassengerTestWorld.FLIGHT) + 1)
	return out


func test_the_table_is_pinned() -> void:
	assert_array(DecorEffect.TABLE.keys()).contains_exactly_in_any_order(TABLE_PINS.keys())
	for def_id: StringName in TABLE_PINS:
		var pin: Array = TABLE_PINS[def_id]
		assert_int(DecorEffect.calm_of(def_id)).override_failure_message(str(def_id)).is_equal(
			pin[0]
		)
		assert_int(DecorEffect.radius_of(def_id)).override_failure_message(str(def_id)).is_equal(
			pin[1]
		)
		assert_object(BuildCatalog.get_def(def_id)).is_not_null()
	# Anything else in the catalog gives nothing.
	assert_int(DecorEffect.calm_of(&"seat_row")).is_equal(0)
	assert_int(DecorEffect.radius_of(&"seat_row")).is_equal(0)


func test_bigger_pieces_calm_more_and_reach_further() -> void:
	for big: StringName in [&"fountain_indoor", &"statue_indoor", &"tree_indoor"]:
		for small: StringName in [&"plant_pot_1a", &"plant_pot_2a", &"bench_1a", &"bush"]:
			assert_int(DecorEffect.calm_of(big)).is_greater_equal(DecorEffect.calm_of(small))
			assert_int(DecorEffect.radius_of(big)).is_greater(DecorEffect.radius_of(small))
	assert_int(DecorEffect.calm_of(&"bush")).is_greater(0)


func test_the_constants_are_pinned() -> void:
	assert_int(DecorEffect.PERIOD_BEATS).is_equal(10)
	assert_int(DecorEffect.MAX_CALM).is_equal(4)
	assert_int(DecorEffect.CEILING).is_equal(85)
	# The slowest a single fountain's calm is paid is still far gentler than a
	# queue (-1 a beat) or a gate seat (+1 a beat).
	assert_int(DecorEffect.MAX_CALM).is_less(DecorEffect.PERIOD_BEATS)
	assert_int(DecorEffect.CEILING).is_less(PassengerSim.MOOD_MAX)
	assert_int(DecorEffect.CEILING).is_greater(Passenger.MOOD_START)


func test_decor_in_the_gate_raises_the_mood_the_rating_sees_and_costs_no_flight() -> void:
	var none := {"made": 0, "missed": 0, "mood_sum": 0}
	var decor := {"made": 0, "missed": 0, "mood_sum": 0}
	for seed in SEEDS:
		for key: String in none:
			none[key] += _flight(seed, false)[key]
			decor[key] += _flight(seed, true)[key]
	@warning_ignore("integer_division")
	var none_mean: int = none["mood_sum"] / maxi(none["made"], 1)
	@warning_ignore("integer_division")
	var decor_mean: int = decor["mood_sum"] / maxi(decor["made"], 1)
	print(
		(
			"none: made %d missed %d mean mood %d; decor %s: made %d missed %d mean mood %d"
			% [
				none["made"],
				none["missed"],
				none_mean,
				GATE_DECOR.map(func(piece: Array) -> String: return str(piece[0])),
				decor["made"],
				decor["missed"],
				decor_mean
			]
		)
	)
	assert_int(none["made"]).is_greater(SEEDS.size() * 10)
	assert_int(decor["mood_sum"] * none["made"]).is_greater(none["mood_sum"] * decor["made"])
	assert_int(decor_mean - none_mean).is_between(MEAN_GAIN_MIN, MEAN_GAIN_MAX)
	assert_int(decor["missed"]).is_less_equal(none["missed"])
