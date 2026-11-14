class_name TestSettlementTraitPayouts
extends GdUnitTestSuite
## Miss fine and Signing bonus are paid at Settlement (decision airline-offer-
## traits-each-offer-pairs-an-upside-with-a-downs). Miss fine charges its level
## for each passenger of the contract's flight who missed it, in the terminal
## (PassengerSim.outcome) or on the road (ArrivalBookings.missed), down to a
## balance of 0, the rest recorded as unpaid. Signing bonus is paid once, when
## the contract's first flight departs, and a save remembers that it was paid.

const CONTRACT := "OCC"
const OCCURRENCE := "OCC-d0"
const MINUTE := 518
const FEE := 30
const FINE := {"up": "top_fare", "down": "miss_fine", "level": 2}
const BONUS := {"up": "signing_bonus", "down": "rush_crowd", "level": 1}

var _world: PassengerTestWorld
var _settlement: Settlement
var _ledger: DayLedger


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
		_world = null


func _make(traits: Dictionary, balance := 0) -> void:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(100000))
	_world.flights.open_airport()
	_world.sim.wallet = Wallet.new(balance)
	_world.sim.wallet.clock = _world.clock
	_ledger = auto_free(DayLedger.new())
	_ledger.bind(_world.sim.wallet, _world.clock)
	_settlement = _new_settlement()
	var terms := TestFlightContracts.terms(CONTRACT, MINUTE)
	terms["plane_size"] = "small"
	terms["booked_passengers"] = 8
	terms["fee_per_passenger"] = FEE
	terms["traits"] = traits
	assert_bool(_world.flights.accept_contract(terms)).is_true()
	_world.run_to(1)


func _new_settlement() -> Settlement:
	var settlement: Settlement = auto_free(Settlement.new())
	settlement.bind(_world.sim, _world.sim.wallet)
	return settlement


## A passenger of the occurrence who finished, making it or not.
func _finish(made: bool) -> Passenger:
	var p := _world.passenger(_world.sim.spawn_now(OCCURRENCE))
	p.stage = Passenger.Stage.MADE if made else Passenger.Stage.MISSED
	_world.sim.outcome.emit(p.id, made)
	return p


func _depart(flight_id: String) -> void:
	_world.flights.state_changed.emit(flight_id, FlightSim.State.DEPARTED)


func test_each_missed_passenger_is_fined_the_level_once() -> void:
	_make(FINE, 100)
	var p := _finish(false)
	_finish(false)
	assert_int(_world.sim.wallet.balance).is_equal(60)
	# A repeated signal for a passenger the sim still holds is not fined again.
	_world.sim.outcome.emit(p.id, false)
	assert_int(_world.sim.wallet.balance).is_equal(60)
	assert_int(_ledger.amount(Wallet.Category.FINES)).is_equal(-40)
	assert_int(_ledger.fines_unpaid()).is_equal(0)


func test_a_road_miss_is_fined_like_a_terminal_miss() -> void:
	_make(FINE, 100)
	_world.sim.arrivals.missed.emit(OCCURRENCE)
	assert_int(_world.sim.wallet.balance).is_equal(80)
	assert_int(_ledger.amount(Wallet.Category.FINES)).is_equal(-20)


func test_a_made_passenger_and_a_contract_without_the_trait_are_never_fined() -> void:
	_make(FINE, 100)
	_finish(true)
	assert_int(_world.sim.wallet.balance).is_equal(100 + FEE)
	after_test()
	_make(BONUS, 100)
	_finish(false)
	_world.sim.arrivals.missed.emit(OCCURRENCE)
	assert_int(_world.sim.wallet.balance).is_equal(100)
	assert_int(_ledger.amount(Wallet.Category.FINES)).is_equal(0)


func test_a_fine_the_wallet_cannot_pay_takes_it_to_zero_and_the_rest_is_unpaid() -> void:
	_make(FINE, 15)
	_finish(false)
	assert_int(_world.sim.wallet.balance).is_equal(0)
	_world.sim.arrivals.missed.emit(OCCURRENCE)
	assert_int(_world.sim.wallet.balance).is_equal(0)
	assert_int(_ledger.amount(Wallet.Category.FINES)).is_equal(-15)
	assert_int(_ledger.fines_unpaid()).is_equal(25)
	# Nothing is owed: the next fee lands in the wallet whole.
	_finish(true)
	assert_int(_world.sim.wallet.balance).is_equal(FEE)


func test_the_signing_bonus_is_paid_when_the_first_flight_departs_and_only_then() -> void:
	_make(BONUS)
	assert_int(_world.sim.wallet.balance).is_equal(0)
	_world.flights.state_changed.emit(OCCURRENCE, FlightSim.State.TAKEOFF)
	assert_int(_world.sim.wallet.balance).is_equal(0)
	_depart(OCCURRENCE)
	assert_int(_world.sim.wallet.balance).is_equal(150)
	assert_int(_ledger.amount(Wallet.Category.SIGNING_BONUS)).is_equal(150)
	_depart(OCCURRENCE)
	_depart("OCC-d1")
	assert_int(_world.sim.wallet.balance).is_equal(150)


func test_the_bonus_is_never_paid_again_after_a_json_save_and_load() -> void:
	_make(BONUS)
	_depart(OCCURRENCE)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(_settlement.to_snapshot()))
	assert_array(saved["bonuses_paid"]).is_equal([CONTRACT])
	_settlement.free()
	_settlement = _new_settlement()
	assert_bool(_settlement.from_snapshot(saved)).is_true()
	_depart("OCC-d1")
	assert_int(_world.sim.wallet.balance).is_equal(150)
	assert_dict(_settlement.to_snapshot()).is_equal(saved)


func test_a_plain_contract_and_a_one_off_flight_pay_no_bonus() -> void:
	_make({})
	_depart(OCCURRENCE)
	_depart(PassengerTestWorld.FLIGHT)
	assert_int(_world.sim.wallet.balance).is_equal(0)
	assert_array(_settlement.to_snapshot()["bonuses_paid"]).is_empty()


func test_bad_saved_bonuses_are_refused() -> void:
	_make({})
	var base := _settlement.to_snapshot()
	for bad in ["OCC", [1], ["OCC", "OCC"], ["bad-id"], [""]]:
		var data := base.duplicate()
		data["bonuses_paid"] = bad
		assert_bool(_settlement.from_snapshot(data)).override_failure_message(str(bad)).is_false()
	# The key is required: a save without it is refused and changes nothing.
	_depart(OCCURRENCE)
	var paid := _settlement.to_snapshot()
	var without := base.duplicate()
	without.erase("bonuses_paid")
	assert_bool(_settlement.from_snapshot(without)).is_false()
	assert_dict(_settlement.to_snapshot()).is_equal(paid)


## Conductor ruling: a bonus the wallet cannot take at Wallet.MAX_BALANCE is
## forfeited, and the contract is marked paid so it is never paid later.
func test_a_bonus_that_does_not_fit_the_wallet_is_forfeited_and_marked_paid() -> void:
	for start in [Wallet.MAX_BALANCE, Wallet.MAX_BALANCE - 149]:
		_make(BONUS, start)
		_depart(OCCURRENCE)
		assert_int(_world.sim.wallet.balance).override_failure_message(str(start)).is_equal(start)
		assert_array(_settlement.to_snapshot()["bonuses_paid"]).is_equal([CONTRACT])
		assert_bool(_world.sim.wallet.spend(1000, Wallet.Category.BUILD)).is_true()
		_depart("OCC-d1")
		assert_int(_world.sim.wallet.balance).is_equal(start - 1000)
		assert_int(_ledger.amount(Wallet.Category.SIGNING_BONUS)).is_equal(0)
		after_test()


func test_a_bonus_that_just_fits_below_the_cap_is_paid() -> void:
	_make(BONUS, Wallet.MAX_BALANCE - 150)
	_depart(OCCURRENCE)
	assert_int(_world.sim.wallet.balance).is_equal(Wallet.MAX_BALANCE)
	assert_int(_ledger.amount(Wallet.Category.SIGNING_BONUS)).is_equal(150)
