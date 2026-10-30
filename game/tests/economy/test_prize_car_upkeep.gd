class_name TestPrizeCarUpkeep
extends GdUnitTestSuite
## The prize car's costs (F4-4; decision furniture-set-modelled-on-copenhagen-
## airport-decor-calms-pas, point 2: it costs money to place and run): placing
## the podium charges its price once, and on the last tick of each day every
## podium on the grid is charged PriceTable.PRIZE_CAR_UPKEEP, booked as upkeep
## in the DayLedger, with the screens' upkeep and the same owed-upkeep rule.

const C := Wallet.Category
const RATE := PriceTable.PRIZE_CAR_UPKEEP

var _kit: SettlementWagesKit
var _ledger: DayLedger


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_kit = SettlementWagesKit.new(self)
	# A 6x3 podium needs a bigger floor than the kit's 8x6 room.
	_kit.remake(
		PassengerTestWorld.make(
			PassengerTestWorld.floored(Vector2i(16, 8)), FlightSim.schedule_starts(1000000)
		)
	)
	_kit.world.sim.wallet.clock = _kit.world.clock
	_ledger = auto_free(DayLedger.new())
	_ledger.bind(_kit.world.sim.wallet, _kit.world.clock)


func after_test() -> void:
	_kit.free_all()


func _podium(cell: Vector2i) -> int:
	return PassengerTestWorld.place(_kit.world.grid, PrizeCar.PODIUM_ID, cell, 0)


func test_placing_the_podium_charges_its_price_once() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(10, 6))
	var wallet := Wallet.new(5000)
	var plan: Array[BuildEdit] = [BuildEdit.place_object(PrizeCar.PODIUM_ID, Vector2i(1, 1), 0)]
	var result := BuildTransaction.commit_plan(grid, plan, wallet)
	print(
		(
			"podium price %d, balance %d"
			% [PriceTable.price_of_object(PrizeCar.PODIUM_ID), wallet.balance]
		)
	)
	assert_bool(result.ok).is_true()
	assert_int(PriceTable.price_of_object(PrizeCar.PODIUM_ID)).is_equal(3000)
	assert_int(wallet.balance).is_equal(5000 - 3000)
	assert_int(PrizeCar.podium_ids(grid).size()).is_equal(1)


func test_midnight_charges_each_podium_and_it_shows_in_the_days_costs() -> void:
	_podium(Vector2i(0, 0))
	_podium(Vector2i(8, 0))
	assert_int(PrizeCar.daily_upkeep(_kit.world.grid)).is_equal(2 * RATE)
	_kit.charge(1)
	var seen := str(_ledger.to_snapshot())
	print("two podiums, day 1: %s" % seen)
	assert_int(_kit.world.sim.wallet.balance).override_failure_message(seen).is_equal(
		SettlementWagesKit.START_BALANCE - 2 * RATE
	)
	assert_int(_ledger.upkeep_paid()).is_equal(2 * RATE)
	assert_int(_ledger.amount(C.UPKEEP)).is_equal(-2 * RATE)
	assert_int(_ledger.operating_result()).is_equal(-2 * RATE)
	# Charged once a day, not again before the next midnight.
	for i in 50:
		_kit.world.step()
	assert_int(_kit.world.sim.wallet.balance).is_equal(SettlementWagesKit.START_BALANCE - 2 * RATE)


func test_an_empty_wallet_owes_the_podium_upkeep() -> void:
	_podium(Vector2i(0, 0))
	var wallet := _kit.world.sim.wallet
	assert_bool(wallet.spend(wallet.balance, C.BUILD)).is_true()
	_kit.charge(1)
	assert_int(wallet.balance).is_equal(0)
	assert_int(_kit.settlement.upkeep_owed()).is_equal(RATE)


func test_no_podium_no_charge() -> void:
	_kit.charge(1)
	assert_int(_ledger.upkeep_paid()).is_equal(0)
	assert_int(_kit.world.sim.wallet.balance).is_equal(SettlementWagesKit.START_BALANCE)
