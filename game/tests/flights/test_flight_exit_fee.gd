class_name TestFlightExitFee
extends GdUnitTestSuite
## Exit fee (decision odd-hours-and-exit-fee-offer-traits-odd-hours-widens-the-
## dep): FlightSim.end_fee is $60 (small) or $120 (big) for an Exit fee contract
## on its first day and the 6 days after, and 0 from its eighth day, for any
## other contract and once it has ended. Only the player's End
## (end_contract_by_player) fires ended_by_player with the fee; the game's own
## end_contract fires contract_ended alone.
##
## Tick 0 is 06:00 on day 0; a 10:00 contract accepted then first flies on day 0.

const SMALL := {"up": "top_fare", "down": "exit_fee", "level": 1}
const BIG := {"up": "full_flight", "down": "exit_fee", "level": 2}
const OTHER := {"up": "top_fare", "down": "miss_fine", "level": 2}

var _ended_by_player: Array = []
var _ended: Array[String] = []


func before_test() -> void:
	_ended_by_player.clear()
	_ended.clear()


func _sim() -> FlightSim:
	var sim := auto_free(FlightSim.new()) as FlightSim
	sim.gate_source = func() -> Array[String]: return ["A", "B", "C", "D"] as Array[String]
	sim.ended_by_player.connect(
		func(id: String, fee: int) -> void: _ended_by_player.append([id, fee])
	)
	sim.contract_ended.connect(func(id: String) -> void: _ended.append(id))
	sim.open_airport()
	return sim


func _accept(sim: FlightSim, id: String, minute: int, traits: Dictionary) -> void:
	var terms := TestFlightContracts.terms(id, minute)
	terms["traits"] = traits
	assert_bool(sim.accept_contract(terms)).is_true()


func test_the_fee_is_60_small_and_120_big_through_day_7_and_gone_on_day_8() -> void:
	var sim := _sim()
	# 4 hours apart, so each departs after the last has left its gate; all
	# first fly on day 0.
	_accept(sim, "S", 660, SMALL)
	_accept(sim, "B", 900, BIG)
	_accept(sim, "N", 1140, OTHER)
	for id in ["S", "B", "N"]:
		assert_int(sim.contract_of(id)["first_day"]).is_equal(0)
	var fees := []
	for day in range(0, 9):
		sim.tick = GameCalendar.tick_at(day, 1380, 0)
		fees.append([sim.end_fee("S"), sim.end_fee("B"), sim.end_fee("N")])
	print("fees by day: %s" % [fees])
	for day in OfferTraits.EXIT_FEE_DAYS:
		assert_array(fees[day]).is_equal([60, 120, 0])
	assert_array(fees[7]).is_equal([0, 0, 0])
	assert_array(fees[8]).is_equal([0, 0, 0])
	assert_int(sim.end_fee("NOPE")).is_equal(0)


## The term counts from the contract's first day: one accepted after its
## departure today first flies tomorrow, so its seventh day is a day later.
func test_the_term_counts_from_the_first_day() -> void:
	var sim := _sim()
	sim.tick = GameCalendar.tick_at(0, 900, 0)
	_accept(sim, "S", 600, SMALL)
	assert_int(sim.contract_of("S")["first_day"]).is_equal(1)
	sim.tick = GameCalendar.tick_at(7, 300, 0)
	assert_int(sim.end_fee("S")).is_equal(60)
	sim.tick = GameCalendar.tick_at(8, 300, 0)
	assert_int(sim.end_fee("S")).is_equal(0)


func test_only_the_players_end_reports_the_fee() -> void:
	var sim := _sim()
	_accept(sim, "S", 600, SMALL)
	_accept(sim, "B", 720, BIG)
	_accept(sim, "P", 960, {})
	assert_bool(sim.end_contract_by_player("B")).is_true()
	assert_bool(sim.end_contract_by_player("P")).is_true()
	# The game's own end (low rating) reports no fee.
	assert_bool(sim.end_contract("S")).is_true()
	assert_array(_ended).is_equal(["B", "P", "S"])
	assert_array(_ended_by_player).is_equal([["B", 120], ["P", 0]])
	# Once ended, no fee is due any more.
	assert_int(sim.end_fee("B")).is_equal(0)


func test_a_refused_player_end_reports_nothing() -> void:
	var sim := _sim()
	_accept(sim, "S", 600, SMALL)
	assert_bool(sim.end_contract_by_player("S")).is_true()
	await (
		assert_error(func() -> void: sim.end_contract_by_player("S"))
		. is_push_error("FlightSim.end_contract: contract 'S' already ended")
	)
	assert_array(_ended_by_player).is_equal([["S", 60]])
