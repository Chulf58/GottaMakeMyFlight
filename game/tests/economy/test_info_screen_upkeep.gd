class_name TestInfoScreenUpkeep
extends GdUnitTestSuite
## Info screen upkeep (decision shops-and-food-stalls-earn-per-visit-toilets-
## and-screens-cos: a display costs upkeep): on the last tick of each day every
## info screen on the grid is charged PriceTable.INFO_SCREEN_UPKEEP, booked as
## upkeep in the DayLedger, and what the wallet cannot pay is owed upkeep. The
## info screen is a different piece from the boredom screen stand, so a stand
## is charged SCREEN_UPKEEP and an info screen INFO_SCREEN_UPKEEP, never both.

const C := Wallet.Category
const RATE := PriceTable.INFO_SCREEN_UPKEEP
const INFO_SCREEN := &"info_screen"

var _kit: SettlementWagesKit
var _ledger: DayLedger


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_kit = SettlementWagesKit.new(self)
	_kit.world.sim.wallet.clock = _kit.world.clock
	_ledger = auto_free(DayLedger.new())
	_ledger.bind(_kit.world.sim.wallet, _kit.world.clock)


func after_test() -> void:
	_kit.free_all()


func _info_screen(cell: Vector2i) -> int:
	return PassengerTestWorld.place(_kit.world.grid, INFO_SCREEN, cell, 0)


func test_midnight_charges_each_info_screen_once_a_day_as_upkeep() -> void:
	_info_screen(Vector2i(1, 1))
	_info_screen(Vector2i(4, 1))
	_kit.charge(1)
	var seen := str(_ledger.to_snapshot())
	print("two info screens, day 1: %s" % seen)
	assert_int(_kit.world.sim.wallet.balance).override_failure_message(seen).is_equal(
		SettlementWagesKit.START_BALANCE - 2 * RATE
	)
	assert_int(_ledger.upkeep_paid()).is_equal(2 * RATE)
	assert_int(_ledger.amount(C.UPKEEP)).is_equal(-2 * RATE)
	# Charged once a day, not again before the next midnight.
	for i in 50:
		_kit.world.step()
	assert_int(_kit.world.sim.wallet.balance).is_equal(SettlementWagesKit.START_BALANCE - 2 * RATE)


func test_an_info_screen_and_a_screen_stand_are_each_charged_their_own_rate() -> void:
	_info_screen(Vector2i(1, 1))
	PassengerTestWorld.place(_kit.world.grid, ScreenCoverage.SCREEN_ID, Vector2i(4, 1), 0)
	_kit.charge(1)
	assert_int(_ledger.upkeep_paid()).is_equal(RATE + PriceTable.SCREEN_UPKEEP)


func test_an_empty_wallet_owes_the_info_screen_upkeep() -> void:
	_info_screen(Vector2i(1, 1))
	var wallet := _kit.world.sim.wallet
	assert_bool(wallet.spend(wallet.balance, C.BUILD)).is_true()
	_kit.charge(1)
	assert_int(wallet.balance).is_equal(0)
	assert_int(_kit.settlement.upkeep_owed()).is_equal(RATE)


func test_no_info_screen_no_charge() -> void:
	_kit.charge(1)
	assert_int(_ledger.upkeep_paid()).is_equal(0)
	assert_int(_kit.world.sim.wallet.balance).is_equal(SettlementWagesKit.START_BALANCE)
