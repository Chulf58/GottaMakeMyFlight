class_name TestDayLedgerWages
extends GdUnitTestSuite
## DayLedger against a real Settlement (decision money-hover-design-
## categorised-wallet-transactions-feed-a-sa): the midnight wage charge lands
## on the new day, and a credit that owed wages take whole is still recorded
## as income and as wages paid, and still refreshes the money card, though the
## wallet's balance (and so Wallet.changed) does not move.

const C := Wallet.Category
const CHECKIN := SettlementWagesKit.CHECKIN

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


func test_the_midnight_wage_charge_lands_on_the_new_day() -> void:
	_kit.hire(CHECKIN)
	assert_bool(_kit.world.sim.wallet.credit(200, C.FEES)).is_true()
	assert_int(_ledger.amount(C.FEES)).is_equal(200)
	_kit.cross(1)
	print("day %d ledger %s charges %s" % [_ledger.day(), _ledger.to_snapshot(), _kit.charges])
	assert_array(_kit.charges).is_equal([[1, 60, 0]])
	assert_int(_ledger.day()).is_equal(1)
	assert_int(_ledger.amount(C.FEES)).is_equal(0)
	assert_int(_ledger.wages_paid()).is_equal(60)
	assert_int(_ledger.wages_paid()).is_equal(_kit.settlement.wages_paid_today())


func test_a_credit_owed_wages_take_whole_is_income_and_wages_paid() -> void:
	var wallet := _kit.world.sim.wallet
	_kit.hire(CHECKIN)
	assert_bool(wallet.spend(wallet.balance, C.BUILD)).is_true()
	_kit.cross(1)
	assert_int(_kit.settlement.wages_owed()).is_equal(60)
	var slot: MoneySlot = auto_free(MoneySlot.new())
	slot.watch(_ledger, _kit.settlement)
	assert_str(slot.card_text()).contains("Owed wages  60")
	var changes := [0]
	wallet.changed.connect(func(_balance: int) -> void: changes[0] += 1)
	assert_bool(wallet.credit(50, C.FEES)).is_true()
	print("balance %d ledger %s" % [wallet.balance, _ledger.to_snapshot()])
	assert_int(wallet.balance).is_equal(0)
	assert_int(changes[0]).is_equal(0)
	assert_int(_ledger.amount(C.FEES)).is_equal(50)
	assert_int(_ledger.wages_paid()).is_equal(50)
	assert_int(_kit.settlement.wages_owed()).is_equal(10)
	assert_str(slot.card_text()).contains("Airline fees  +50")
	assert_str(slot.card_text()).contains("Wages paid  -50")
	assert_str(slot.card_text()).contains("Owed wages  10")
	assert_str(slot.tooltip_text).is_equal(slot.card_text())


func test_paying_owed_wages_from_the_balance_is_wages_paid() -> void:
	var wallet := _kit.world.sim.wallet
	_kit.hire(CHECKIN)
	assert_bool(wallet.spend(wallet.balance, C.BUILD)).is_true()
	_kit.cross(1)
	# A balance set up beside a debt (as a load could) is paid on the next tick.
	assert_bool(wallet.from_snapshot({"balance": "100"})).is_true()
	_kit.world.step()
	assert_int(_kit.settlement.wages_owed()).is_equal(0)
	assert_int(_ledger.wages_paid()).is_equal(60)
