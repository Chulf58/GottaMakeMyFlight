class_name TestSettlementWagesPaid
extends GdUnitTestSuite
## The Settlement.wages_paid signal behind the "Wages paid: N" message: one
## emission for each wage payment (the charge on a day's last tick, and owed
## wages paid later from a credit or the balance), never for 0.

const CHECKIN := SettlementWagesKit.CHECKIN

var _kit: SettlementWagesKit


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_kit = SettlementWagesKit.new(self)


func after_test() -> void:
	_kit.free_all()


func test_wages_paid_is_announced_once_per_payment() -> void:
	var wallet := _kit.world.sim.wallet
	_kit.hire(CHECKIN)
	_kit.near_midnight(1, 40)
	for i in 30:
		_kit.world.step()
	assert_array(_kit.payments).is_empty()
	_kit.charge(1)
	assert_array(_kit.payments).is_equal([[60, 0]])
	for i in 50:
		_kit.world.step()
	assert_array(_kit.payments).has_size(1)
	assert_bool(wallet.spend(wallet.balance, Wallet.Category.BUILD)).is_true()
	_kit.charge(2)
	print("payments %s charges %s" % [_kit.payments, _kit.charges])
	assert_array(_kit.payments).has_size(1)
	assert_int(_kit.settlement.wages_owed()).is_equal(60)
	assert_bool(wallet.credit(50, Wallet.Category.FEES)).is_true()
	assert_array(_kit.payments).is_equal([[60, 0], [50, 10]])
	assert_bool(wallet.credit(100, Wallet.Category.FEES)).is_true()
	assert_array(_kit.payments).is_equal([[60, 0], [50, 10], [10, 0]])
	assert_bool(wallet.credit(100, Wallet.Category.FEES)).is_true()
	assert_array(_kit.payments).has_size(3)


## Owed wages the balance already holds the money for are paid on the next tick.
func test_wages_paid_from_the_balance_are_announced_too() -> void:
	var wallet := _kit.world.sim.wallet
	_kit.hire(CHECKIN)
	assert_bool(wallet.spend(wallet.balance, Wallet.Category.BUILD)).is_true()
	_kit.charge(1)
	assert_array(_kit.payments).is_empty()
	assert_bool(wallet.from_snapshot({"balance": "100"})).is_true()
	_kit.world.step()
	assert_array(_kit.payments).is_equal([[60, 0]])
