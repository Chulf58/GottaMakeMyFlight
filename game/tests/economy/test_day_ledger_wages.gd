class_name TestDayLedgerWages
extends GdUnitTestSuite
## DayLedger against a real Settlement (decision money-hover-design-
## categorised-wallet-transactions-feed-a-sa): the wage charge is made on the
## last tick of the day and lands on that day (decision daily-wages-are-
## charged-on-the-last-tick-of-the-game-day-and, which revised the first design's
## "lands on the new day"), the next day starts at 0 wages, and a credit that owed
## wages take whole is still recorded as income and as wages paid, and still
## refreshes the money card, though the wallet's balance (and so
## Wallet.changed) does not move.

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


## The reverse of the first design (the charge used to land on the new day): the
# ledger's own day gets the wages, so its card shows them all day-end.
func test_the_midnight_wage_charge_lands_on_the_day_it_was_earned() -> void:
	_kit.hire(CHECKIN)
	assert_bool(_kit.world.sim.wallet.credit(200, C.FEES)).is_true()
	assert_int(_ledger.amount(C.FEES)).is_equal(200)
	assert_int(_ledger.wages_paid()).is_equal(0)
	_kit.charge(1)
	print("day %d ledger %s charges %s" % [_ledger.day(), _ledger.to_snapshot(), _kit.charges])
	assert_array(_kit.charges).is_equal([[0, 60, 0]])
	assert_int(_ledger.day()).is_equal(0)
	assert_int(_ledger.amount(C.FEES)).is_equal(200)
	assert_int(_ledger.wages_paid()).is_equal(60)
	assert_int(_ledger.operating_result()).is_equal(140)
	assert_int(_ledger.wages_paid()).is_equal(_kit.settlement.wages_paid_today())


func test_the_next_day_starts_at_0_wages() -> void:
	_kit.hire(CHECKIN)
	_kit.charge(1)
	_kit.world.step()
	print("day %d ledger %s" % [_ledger.day(), _ledger.to_snapshot()])
	assert_int(_ledger.day()).is_equal(1)
	assert_int(_ledger.wages_paid()).is_equal(0)
	assert_int(_kit.settlement.wages_paid_today()).is_equal(0)
	for i in 30:
		_kit.world.step()
	assert_int(_ledger.wages_paid()).is_equal(0)
	assert_array(_kit.charges).has_size(1)


## Owed wages paid by a credit land on the day of the credit, not the day they
## were charged for.
func test_owed_wages_paid_on_a_credit_book_to_the_day_they_are_paid() -> void:
	var wallet := _kit.world.sim.wallet
	_kit.hire(CHECKIN)
	assert_bool(wallet.spend(wallet.balance, C.BUILD)).is_true()
	_kit.charge(1)
	assert_int(_ledger.day()).is_equal(0)
	assert_int(_ledger.wages_paid()).is_equal(0)
	assert_int(_kit.settlement.wages_owed()).is_equal(60)
	_kit.world.step()
	assert_bool(wallet.credit(50, C.FEES)).is_true()
	assert_int(_ledger.day()).is_equal(1)
	assert_int(_ledger.wages_paid()).is_equal(50)
	assert_int(_ledger.wages_paid()).is_equal(_kit.settlement.wages_paid_today())
	assert_array(_kit.payments).is_equal([[50, 10]])


## A save just before the charge tick and one just after it both reload to the
## same ledger and settlement, and the booking stays on day 0.
func test_a_save_across_the_charge_tick_keeps_the_booking() -> void:
	_kit.hire(CHECKIN)
	assert_bool(_kit.world.sim.wallet.credit(200, C.FEES)).is_true()
	_kit.near_midnight(1, 3)
	_kit.world.step()
	var before := _save_all()
	_kit.world.step()
	var after := _save_all()
	assert_str(before["ledger"]["wages"]).is_equal("0")
	assert_str(after["ledger"]["wages"]).is_equal("-60")
	assert_str(after["ledger"]["day"]).is_equal("0")
	assert_str(_link_problem(after)).is_empty()
	_kit.world.step()
	var next_day := _save_all()
	assert_str(next_day["ledger"]["day"]).is_equal("1")
	assert_str(next_day["ledger"]["wages"]).is_equal("0")
	assert_str(_link_problem(next_day)).is_empty()
	_load_all(before)
	_kit.world.step()
	assert_dict(_save_all()).is_equal(after)
	_kit.world.step()
	assert_dict(_save_all()).is_equal(next_day)
	_load_all(after)
	_kit.world.step()
	assert_dict(_save_all()).is_equal(next_day)
	assert_int(_kit.world.sim.wallet.balance).is_equal(1000 + 200 - 60)


func _save_all() -> Dictionary:
	var data := _kit.save()
	data["ledger"] = _ledger.to_snapshot()
	return JSON.parse_string(JSON.stringify(data)) as Dictionary


func _load_all(data: Dictionary) -> void:
	_kit.load_save(data)
	assert_bool(_ledger.from_snapshot(data["ledger"])).is_true()


func _link_problem(data: Dictionary) -> String:
	return DayLedger.wages_link_problem(data["ledger"], data["settlement"])


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
