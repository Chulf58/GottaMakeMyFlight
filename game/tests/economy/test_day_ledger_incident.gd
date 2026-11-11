class_name TestDayLedgerIncident
extends GdUnitTestSuite
## Daily incidents (decision daily-incidents-technical-design-
## incidentdirector-shared-clo): an incident's bonus or cost is the wallet's
## INCIDENT category, its own line in the DayLedger, in the cash change but
## not in the operating result, and saved under "incident". Every category's
## round trip is in test_day_ledger.gd.

const C := Wallet.Category

var _clock: SimClock
var _wallet: Wallet
var _ledger: DayLedger


func before_test() -> void:
	_clock = auto_free(SimClock.new())
	_clock.set_paused(true)
	_wallet = Wallet.new()
	_wallet.clock = _clock
	_ledger = auto_free(DayLedger.new())
	_ledger.bind(_wallet, _clock)


func test_incident_money_is_its_own_line_outside_the_operating_result() -> void:
	assert_bool(_wallet.credit(300, C.FEES)).is_true()
	assert_bool(_wallet.credit(800, C.INCIDENT)).is_true()
	assert_bool(_wallet.spend(250, C.INCIDENT)).is_true()
	print("totals %s" % _ledger.to_snapshot())
	assert_int(_ledger.amount(C.INCIDENT)).is_equal(550)
	assert_str(_ledger.to_snapshot()["incident"]).is_equal("550")
	assert_int(_ledger.operating_result()).is_equal(300)
	assert_int(_ledger.cash_change()).is_equal(850)
	assert_int(_ledger.cash_change()).is_equal(_wallet.balance)


func test_a_saved_ledger_without_incident_money_is_refused() -> void:
	var saved := _ledger.to_snapshot()
	saved.erase("incident")
	var other: DayLedger = auto_free(DayLedger.new())
	assert_bool(other.from_snapshot(saved)).is_false()
