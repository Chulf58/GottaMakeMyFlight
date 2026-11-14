class_name TestDayLedgerFines
extends GdUnitTestSuite
## Airline fines and signing bonuses have their own wallet categories in the
## day's money. Wallet.charge takes what it can of a fine, down to a balance of
## 0, and announces the rest as unpaid, which the ledger adds up for the day.

var _clock: SimClock
var _wallet: Wallet
var _ledger: DayLedger
var _unpaid: Array = []


func before_test() -> void:
	_unpaid.clear()
	_clock = auto_free(SimClock.new()) as SimClock
	_clock.tick = GameCalendar.day_start(2) + 100
	_wallet = Wallet.new(50)
	_wallet.clock = _clock
	_wallet.unpaid.connect(
		func(amount: int, category: int, tick: int) -> void:
			_unpaid.append([amount, category, tick])
	)
	_ledger = auto_free(DayLedger.new()) as DayLedger
	_ledger.bind(_wallet, _clock)


func test_a_charge_the_wallet_holds_is_spent_whole() -> void:
	assert_int(_wallet.charge(20, Wallet.Category.FINES)).is_equal(20)
	assert_int(_wallet.balance).is_equal(30)
	assert_array(_unpaid).is_empty()
	assert_int(_ledger.amount(Wallet.Category.FINES)).is_equal(-20)
	assert_int(_ledger.fines_unpaid()).is_equal(0)


func test_a_charge_past_the_balance_takes_it_to_zero_and_announces_the_rest() -> void:
	assert_int(_wallet.charge(80, Wallet.Category.FINES)).is_equal(50)
	assert_int(_wallet.balance).is_equal(0)
	assert_array(_unpaid).is_equal([[30, Wallet.Category.FINES, _clock.tick]])
	assert_int(_ledger.amount(Wallet.Category.FINES)).is_equal(-50)
	assert_int(_ledger.fines_unpaid()).is_equal(30)
	assert_int(_wallet.charge(10, Wallet.Category.FINES)).is_equal(0)
	assert_int(_ledger.fines_unpaid()).is_equal(40)


func test_a_negative_charge_is_refused() -> void:
	assert_int(_wallet.charge(-5, Wallet.Category.FINES)).is_equal(0)
	assert_int(_wallet.balance).is_equal(50)
	assert_array(_unpaid).is_empty()


func test_fines_are_a_running_cost_and_the_bonus_is_one_off_cash() -> void:
	_wallet.credit(100, Wallet.Category.FEES)
	_wallet.charge(20, Wallet.Category.FINES)
	_wallet.credit(150, Wallet.Category.SIGNING_BONUS)
	assert_int(_ledger.operating_result()).is_equal(80)
	assert_int(_ledger.cash_change()).is_equal(230)
	assert_int(_ledger.amount(Wallet.Category.SIGNING_BONUS)).is_equal(150)


func test_a_new_day_starts_with_no_fines_and_nothing_unpaid() -> void:
	_wallet.charge(80, Wallet.Category.FINES)
	var tick := GameCalendar.day_start(3)
	_clock.tick = tick
	_ledger.on_tick(tick)
	assert_int(_ledger.amount(Wallet.Category.FINES)).is_equal(0)
	assert_int(_ledger.fines_unpaid()).is_equal(0)


func test_the_fines_the_bonus_and_the_unpaid_fines_survive_a_json_save() -> void:
	_wallet.credit(150, Wallet.Category.SIGNING_BONUS)
	_wallet.charge(250, Wallet.Category.FINES)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(_ledger.to_snapshot()))
	assert_str(saved["fines"]).is_equal("-200")
	assert_str(saved["signing_bonus"]).is_equal("150")
	assert_str(saved["fines_unpaid"]).is_equal("50")
	var loaded := auto_free(DayLedger.new()) as DayLedger
	loaded.bind(Wallet.new(), _clock)
	assert_bool(loaded.from_snapshot(saved)).is_true()
	assert_int(loaded.fines_unpaid()).is_equal(50)
	assert_int(loaded.amount(Wallet.Category.FINES)).is_equal(-200)
	for bad in ["-1", "x", 5]:
		var data := saved.duplicate()
		data["fines_unpaid"] = bad
		assert_bool(loaded.from_snapshot(data)).override_failure_message(str(bad)).is_false()
	var without := saved.duplicate()
	without.erase("fines_unpaid")
	assert_bool(loaded.from_snapshot(without)).is_false()
