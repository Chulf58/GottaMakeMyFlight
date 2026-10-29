class_name TestToiletTuning
extends GdUnitTestSuite
## Toilet tuning (decision toilet-design-queue-free-reservable-stalls-per-
## stall-daily-u, point 5): the need's start range, rise and threshold are set
## so that on a scheduled flight a fair share of the passengers who arrive
## early use a toilet, and no passenger who set off for one misses the
## flight. Measured like test_cafe_tuning: the reference terminal with two
## toilet rooms of two stalls each (ToiletTestLayout), DEFAULT_PASSENGERS on
## the default timing, scheduled from the sim RNG as in play, over several
## seeds pooled. Early means spawned before boarding opens; using a toilet
## means reaching TOILET_USE.

const SEEDS: Array[int] = [11, 22, 33, 44, 55, 66]
## The band in whole percent of early arrivals: 25% to 33%. Need 30-90 at
## spawn, +1 a second, high from 70 gives 29% (25 of 86) on these seeds; with
## every passenger in need from spawn (60-100) this layout caps it at 37% (32
## of 86), and 0-60 gives only 8%.
const SHARE_MIN := 25
const SHARE_MAX := 33

var _spawned: Dictionary = {}
var _went: Dictionary = {}
var _used: Dictionary = {}
var _missed: Dictionary = {}


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


## One flight: {"early", "early_used", "early_went", "late", "late_used",
## "went_missed"}.
func _flight(seed: int) -> Dictionary:
	_spawned.clear()
	_went.clear()
	_used.clear()
	_missed.clear()
	var grid := BuildGrid.new()
	ToiletTestLayout.build(grid)
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), seed)
	var sim := world.sim
	sim.passenger_spawned.connect(func(id: int) -> void: _spawned[id] = sim.tick)
	sim.stage_changed.connect(
		func(id: int, stage: Passenger.Stage) -> void:
			if stage == Passenger.Stage.TOILET_WALK:
				_went[id] = true
			elif stage == Passenger.Stage.TOILET_USE:
				_used[id] = true
	)
	sim.outcome.connect(func(id: int, made: bool) -> void: _missed[id] = not made)
	var count := PassengerSim.DEFAULT_PASSENGERS
	assert_bool(sim.schedule_flight(PassengerTestWorld.FLIGHT, count)).is_true()
	var boarding := world.flights.boarding_window(PassengerTestWorld.FLIGHT).x
	world.run_to(world.flights.doors_close_tick(PassengerTestWorld.FLIGHT) + 1)
	var out := {
		"early": 0, "early_used": 0, "early_went": 0, "late": 0, "late_used": 0, "went_missed": 0
	}
	for id: int in _spawned:
		var side := "early" if int(_spawned[id]) < boarding else "late"
		out[side] += 1
		if _used.has(id):
			out[side + "_used"] += 1
		if _went.has(id):
			out["went_missed"] += int(_missed.get(id, true))
			if side == "early":
				out["early_went"] += 1
	return out


func test_a_fair_share_of_early_arrivals_use_a_toilet_and_all_who_go_make_it() -> void:
	var total := {
		"early": 0, "early_used": 0, "early_went": 0, "late": 0, "late_used": 0, "went_missed": 0
	}
	for seed in SEEDS:
		var flight := _flight(seed)
		print("seed %d: %s" % [seed, flight])
		for key: String in total:
			total[key] += flight[key]
	@warning_ignore("integer_division")
	var share: int = total["early_used"] * 100 / maxi(total["early"], 1)
	print(
		(
			"pooled: %s; early share %d%% (need start %d-%d, +%d a second, high at %d)"
			% [
				total,
				share,
				ToiletSim.NEED_START_MIN,
				ToiletSim.NEED_START_MAX,
				ToiletSim.NEED_RISE,
				ToiletSim.NEED_AT
			]
		)
	)
	# The flights spawned their passengers, and enough of them arrived early.
	assert_int(total["early"]).is_greater(SEEDS.size() * 8)
	assert_int(share).is_between(SHARE_MIN, SHARE_MAX)
	# A detour never cost a passenger its flight.
	assert_int(total["went_missed"]).is_equal(0)
