class_name TestBoredomTuning
extends GdUnitTestSuite
## Boredom tuning (decision boredom-and-shops-design-boredom-need-while-
## waiting-kiosk-sh, point 1; Astra's balance risk: a gate seat gives +1 mood
## a beat while an unmet need costs a point every five beats). The start
## range, rise and threshold are set so that a fair share of the passengers
## who arrive early are bored by the time boarding opens, most of them relaxed
## arrivals, who wait longest; the mood effect (no seat bonus while bored, and
## a point every BoredomSim.MOOD_BEATS beats) makes a bored passenger on a gate
## seat lose mood instead of gaining it. Measured like test_toilet_tuning: the
## reference terminal with its toilet rooms (ToiletTestLayout),
## DEFAULT_PASSENGERS scheduled from the sim RNG as in play, over several seeds
## pooled, but with the flight's first state FIRST_STATE ticks after the
## schedule, so relaxed arrivals get their whole window (the default test
## timing starts the flight at tick 0, which leaves them none). Early means
## spawned before boarding opens; bored means boredom at or over
## BoredomSim.BORED_AT on the tick boarding opens.

const SEEDS: Array[int] = [11, 22, 33, 44, 55, 66]
## The band in whole percent of early arrivals bored at boarding: 26% to 33%.
## Start 0-30, +1 a waiting second, bored from 50 gives 29% (29 of 99) on
## these seeds, every one relaxed; bored from 40 gives 35%, from 60 25% and
## from 70 16%. Relaxed early arrivals wait 4 to 83 seconds before boarding.
const SHARE_MIN := 26
const SHARE_MAX := 33
## As FlightTimetable issues an occurrence well before its first state, the
## earliest relaxed arrival (RELAXED_LEAD_TICKS before departure, 1640 ticks
## before the first state) is still ahead of the clock.
const FIRST_STATE := 1700

var _spawned: Dictionary = {}


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func _empty() -> Dictionary:
	return {
		"early": 0,
		"early_bored": 0,
		"relaxed": 0,
		"relaxed_bored": 0,
		"bored_seated_beats": 0,
		"bored_seated_mood": 0,
		"calm_seated_beats": 0,
		"calm_seated_mood": 0,
	}


## One flight's counts (_empty()'s keys).
func _flight(seed: int) -> Dictionary:
	_spawned.clear()
	var grid := BuildGrid.new()
	ToiletTestLayout.build(grid)
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(FIRST_STATE), seed)
	var sim := world.sim
	sim.passenger_spawned.connect(func(id: int) -> void: _spawned[id] = sim.tick)
	(
		assert_bool(sim.schedule_flight(PassengerTestWorld.FLIGHT, PassengerSim.DEFAULT_PASSENGERS))
		. is_true()
	)
	var boarding := world.flights.boarding_window(PassengerTestWorld.FLIGHT).x
	var doors := world.flights.doors_close_tick(PassengerTestWorld.FLIGHT)
	var out := _empty()
	while world.clock.tick <= doors:
		var next := world.clock.tick + 1
		# The seated passengers whose beat is on the next tick, and their
		# boredom and mood before it.
		var watched := {}
		for id in sim.passenger_ids():
			var p := sim.get_passenger(id)
			var on_beat := (
				posmod(next, PassengerSim.BEAT_TICKS) == posmod(id, PassengerSim.BEAT_TICKS)
			)
			if on_beat and p.stage == Passenger.Stage.SEATED:
				watched[id] = [p.boredom >= BoredomSim.BORED_AT, p.mood]
		world.step()
		for id: int in watched:
			var p := sim.get_passenger(id)
			if p == null or p.stage != Passenger.Stage.SEATED:
				continue
			var side := "bored" if watched[id][0] else "calm"
			out[side + "_seated_beats"] += 1
			out[side + "_seated_mood"] += p.mood - int(watched[id][1])
		if world.clock.tick == boarding:
			for id: int in _spawned:
				var p := sim.get_passenger(id)
				if p == null or int(_spawned[id]) >= boarding:
					continue
				var bored := int(p.boredom >= BoredomSim.BORED_AT)
				out["early"] += 1
				out["early_bored"] += bored
				if p.arrival_type == ArrivalTypes.Type.RELAXED:
					out["relaxed"] += 1
					out["relaxed_bored"] += bored
	world.free_all()
	return out


func test_a_fair_share_of_early_arrivals_are_bored_and_bored_seats_cost_mood() -> void:
	var total := _empty()
	for seed in SEEDS:
		var flight := _flight(seed)
		print("seed %d: %s" % [seed, flight])
		for key: String in total:
			total[key] += flight[key]
	@warning_ignore("integer_division")
	var share: int = total["early_bored"] * 100 / maxi(total["early"], 1)
	print(
		(
			(
				"pooled: %s; early bored %d%% (start %d-%d, +%d a waiting second, bored at %d,"
				+ " -1 mood every %d beats while bored)"
			)
			% [
				total,
				share,
				BoredomSim.START_MIN,
				BoredomSim.START_MAX,
				BoredomSim.RISE,
				BoredomSim.BORED_AT,
				BoredomSim.MOOD_BEATS
			]
		)
	)
	assert_int(total["early"]).is_greater(SEEDS.size() * 8)
	assert_int(share).is_between(SHARE_MIN, SHARE_MAX)
	# Relaxed arrivals, who wait longest, are most of the bored ones.
	assert_int(total["relaxed_bored"] * 2).is_greater(total["early_bored"])
	# A bored passenger on a gate seat loses mood; a calm one gains it.
	assert_int(total["bored_seated_beats"]).is_greater(SEEDS.size() * 20)
	assert_int(total["bored_seated_mood"]).is_less(0)
	assert_int(total["calm_seated_mood"]).is_greater(0)
