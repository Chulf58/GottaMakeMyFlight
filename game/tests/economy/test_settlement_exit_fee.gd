class_name TestSettlementExitFee
extends GdUnitTestSuite
## Settlement charges the Exit fee (decision odd-hours-and-exit-fee-offer-traits-
## odd-hours-widens-the-dep) when the player ends an Exit fee contract within its
## 7-day term (FlightSim.end_contract_by_player): $60 small, $120 big, as an
## airline fine through Wallet.charge, so a fee larger than the balance takes it
## to 0 and the rest is unpaid, never owed. From day 8, for any other contract
## and for the game's own end (end_contract) nothing is charged.

const CONTRACT := "EXT"
const MINUTE := 518
const SMALL := {"up": "top_fare", "down": "exit_fee", "level": 1}
const BIG := {"up": "full_flight", "down": "exit_fee", "level": 2}
const OTHER := {"up": "top_fare", "down": "miss_fine", "level": 2}

var _world: PassengerTestWorld
var _ledger: DayLedger


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
		_world = null


func _make(traits: Dictionary, balance: int) -> void:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(100000))
	_world.flights.open_airport()
	_world.sim.wallet = Wallet.new(balance)
	_world.sim.wallet.clock = _world.clock
	_ledger = auto_free(DayLedger.new())
	_ledger.bind(_world.sim.wallet, _world.clock)
	var settlement: Settlement = auto_free(Settlement.new())
	settlement.bind(_world.sim, _world.sim.wallet)
	var terms := TestFlightContracts.terms(CONTRACT, MINUTE)
	terms["traits"] = traits
	assert_bool(_world.flights.accept_contract(terms)).is_true()
	_world.run_to(1)


## Puts the flights on `day` of the contract's term (1 is its first day).
func _on_term_day(day: int) -> void:
	var first: int = _world.flights.contract_of(CONTRACT)["first_day"]
	_world.flights.tick = GameCalendar.tick_at(first + day - 1, 1380)


func test_the_player_ending_within_the_term_pays_60_small_or_120_big() -> void:
	for spec: Array in [[SMALL, 60], [BIG, 120]]:
		_make(spec[0], 500)
		_on_term_day(OfferTraits.EXIT_FEE_DAYS)
		assert_bool(_world.flights.end_contract_by_player(CONTRACT)).is_true()
		assert_int(_world.sim.wallet.balance).is_equal(500 - spec[1])
		assert_int(_ledger.amount(Wallet.Category.FINES)).is_equal(-spec[1])
		after_test()


func test_day_8_another_contract_and_the_games_own_end_are_free() -> void:
	_make(BIG, 500)
	_on_term_day(OfferTraits.EXIT_FEE_DAYS + 1)
	assert_bool(_world.flights.end_contract_by_player(CONTRACT)).is_true()
	assert_int(_world.sim.wallet.balance).is_equal(500)
	after_test()
	_make(OTHER, 500)
	assert_bool(_world.flights.end_contract_by_player(CONTRACT)).is_true()
	assert_int(_world.sim.wallet.balance).is_equal(500)
	after_test()
	# The game's own end of an Exit fee contract on its first day.
	_make(BIG, 500)
	assert_bool(_world.flights.end_contract(CONTRACT)).is_true()
	assert_int(_world.sim.wallet.balance).is_equal(500)
	assert_int(_ledger.amount(Wallet.Category.FINES)).is_equal(0)


## The wallet's existing pattern for a charge it cannot cover (Wallet.charge):
## it pays down to 0 and the rest is unpaid, not owed; End is never refused.
func test_a_fee_larger_than_the_balance_takes_it_to_zero_and_the_rest_is_unpaid() -> void:
	_make(BIG, 45)
	var unpaid := []
	_world.sim.wallet.unpaid.connect(
		func(amount: int, category: int, _tick: int) -> void: unpaid.append([amount, category])
	)
	assert_bool(_world.flights.end_contract_by_player(CONTRACT)).is_true()
	assert_int(_world.sim.wallet.balance).is_equal(0)
	assert_array(unpaid).is_equal([[75, Wallet.Category.FINES]])
	assert_int(_ledger.amount(Wallet.Category.FINES)).is_equal(-45)
	assert_int(_ledger.fines_unpaid()).is_equal(75)
	assert_array(_world.flights.active_contract_ids()).is_empty()
