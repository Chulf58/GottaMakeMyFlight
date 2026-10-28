class_name TestDayLedger
extends GdUnitTestSuite
## DayLedger (decision money-hover-design-categorised-wallet-transactions-
## feed-a-sa, points 2 to 4): today's money per wallet category, rolled to the
## day of each transaction's tick and of every clock tick, so a movement lands
## on the day it happened. OPENING never counts as earnings, and the rescue
## grant stays apart from the operating result. Wages against a real
## Settlement are in test_day_ledger_wages.gd; the whole-world save in
## tests/core/test_day_ledger_save.gd.

const C := Wallet.Category

var _clock: SimClock
var _wallet: Wallet
var _ledger: DayLedger
var _changes := [0]


func before_test() -> void:
	_clock = auto_free(SimClock.new())
	_clock.set_paused(true)
	_wallet = Wallet.new()
	_wallet.clock = _clock
	_ledger = auto_free(DayLedger.new())
	_ledger.bind(_wallet, _clock)
	_changes[0] = 0
	var changes := _changes
	_ledger.changed.connect(func() -> void: changes[0] += 1)


## One tick, as the running game takes it.
func _step() -> void:
	_clock.set_paused(false)
	_clock.advance(SimClock.STEP)
	_clock.set_paused(true)


## Moves the clock so the next _step() is the first tick of `day`.
func _to_midnight(day: int) -> void:
	_clock.tick = GameCalendar.day_start(day) - 1


func test_a_new_ledger_is_on_the_clocks_day_with_nothing_recorded() -> void:
	assert_int(_ledger.day()).is_equal(0)
	assert_bool(_ledger.is_since_load()).is_false()
	for category in C.values():
		assert_int(_ledger.amount(category)).is_equal(0)
	assert_int(_ledger.cash_change()).is_equal(0)


func test_each_category_is_recorded_on_todays_totals() -> void:
	assert_bool(_wallet.credit(300, C.FEES)).is_true()
	assert_bool(_wallet.credit(40, C.SHOP)).is_true()
	assert_bool(_wallet.credit(500, C.GRANT)).is_true()
	assert_bool(_wallet.spend(90, C.WAGES)).is_true()
	assert_bool(_wallet.spend(400, C.BUILD)).is_true()
	assert_bool(_wallet.credit(150, C.BUILD)).is_true()
	print("totals %s" % _ledger.to_snapshot())
	assert_int(_ledger.amount(C.FEES)).is_equal(300)
	assert_int(_ledger.amount(C.SHOP)).is_equal(40)
	assert_int(_ledger.amount(C.GRANT)).is_equal(500)
	assert_int(_ledger.wages_paid()).is_equal(90)
	assert_int(_ledger.amount(C.BUILD)).is_equal(-250)
	assert_int(_ledger.operating_result()).is_equal(300 + 40 - 90)
	assert_int(_ledger.cash_change()).is_equal(300 + 40 - 90 - 250 + 500)
	assert_int(_ledger.cash_change()).is_equal(_wallet.balance)
	assert_int(_changes[0]).is_equal(6)


func test_the_opening_budget_is_not_earnings_or_cash_change() -> void:
	assert_bool(_wallet.credit(20000, C.OPENING)).is_true()
	assert_bool(_wallet.credit(25, C.FEES)).is_true()
	assert_int(_ledger.amount(C.OPENING)).is_equal(20000)
	assert_int(_ledger.operating_result()).is_equal(25)
	assert_int(_ledger.cash_change()).is_equal(25)


func test_the_rescue_grant_stays_out_of_the_operating_result() -> void:
	assert_bool(_wallet.credit(1200, C.GRANT)).is_true()
	assert_bool(_wallet.spend(150, C.WAGES)).is_true()
	assert_int(_ledger.operating_result()).is_equal(-150)
	assert_int(_ledger.amount(C.GRANT)).is_equal(1200)
	assert_int(_ledger.cash_change()).is_equal(1050)


func test_wages_a_credit_pays_off_count_as_wages_paid() -> void:
	var debt := [70]
	_wallet.credit_claim = func(amount: int, commit: bool) -> Dictionary:
		var taken := mini(debt[0], amount)
		if commit:
			debt[0] -= taken
		return {Wallet.Category.WAGES: taken} if taken > 0 else {}
	assert_bool(_wallet.credit(100, C.FEES)).is_true()
	assert_int(_ledger.amount(C.FEES)).is_equal(100)
	assert_int(_ledger.wages_paid()).is_equal(70)
	assert_int(_ledger.cash_change()).is_equal(30)
	assert_int(_wallet.balance).is_equal(30)


## Toilet upkeep (decision toilet-design-queue-free-reservable-stalls-per-
## stall-daily-u, point 2) is its own line, a cost in the operating result.
func test_upkeep_is_its_own_line_and_a_cost_in_the_operating_result() -> void:
	assert_bool(_wallet.credit(300, C.FEES)).is_true()
	assert_bool(_wallet.spend(60, C.WAGES)).is_true()
	assert_bool(_wallet.spend(40, C.UPKEEP)).is_true()
	assert_int(_ledger.amount(C.UPKEEP)).is_equal(-40)
	assert_int(_ledger.upkeep_paid()).is_equal(40)
	assert_int(_ledger.wages_paid()).is_equal(60)
	assert_int(_ledger.operating_result()).is_equal(300 - 60 - 40)
	assert_int(_ledger.cash_change()).is_equal(_wallet.balance)


func test_a_credit_that_pays_both_debts_books_each_on_its_own_line() -> void:
	var debts := {C.WAGES: 70, C.UPKEEP: 50}
	_wallet.credit_claim = func(amount: int, commit: bool) -> Dictionary:
		var wages := mini(debts[C.WAGES], amount)
		var upkeep := mini(debts[C.UPKEEP], amount - wages)
		if commit:
			debts[C.WAGES] -= wages
			debts[C.UPKEEP] -= upkeep
		return {C.WAGES: wages, C.UPKEEP: upkeep}
	assert_bool(_wallet.credit(100, C.FEES)).is_true()
	assert_int(_ledger.amount(C.FEES)).is_equal(100)
	assert_int(_ledger.wages_paid()).is_equal(70)
	assert_int(_ledger.upkeep_paid()).is_equal(30)
	assert_int(_ledger.cash_change()).is_equal(0)
	assert_int(_wallet.balance).is_equal(0)


## A ledger saved before upkeep existed has no "upkeep" total; it loads with 0.
func test_a_saved_ledger_from_before_upkeep_loads_with_none() -> void:
	assert_bool(_wallet.credit(300, C.FEES)).is_true()
	var saved: Dictionary = JSON.parse_string(JSON.stringify(_ledger.to_snapshot()))
	assert_str(saved["upkeep"]).is_equal("0")
	saved.erase("upkeep")
	var other: DayLedger = auto_free(DayLedger.new())
	assert_bool(other.from_snapshot(saved)).is_true()
	assert_int(other.amount(C.UPKEEP)).is_equal(0)
	assert_int(other.amount(C.FEES)).is_equal(300)
	assert_bool(other.is_since_load()).is_false()


func test_a_failed_spend_or_a_restore_records_nothing() -> void:
	assert_bool(_wallet.spend(1, C.BUILD)).is_false()
	assert_bool(_wallet.from_snapshot({"balance": "5000"})).is_true()
	assert_int(_ledger.cash_change()).is_equal(0)
	assert_int(_ledger.amount(C.BUILD)).is_equal(0)
	assert_int(_changes[0]).is_equal(0)


func test_the_first_tick_of_a_day_starts_a_new_day_with_none_recorded() -> void:
	assert_bool(_wallet.credit(300, C.FEES)).is_true()
	_to_midnight(1)
	_step()
	assert_int(_ledger.day()).is_equal(1)
	assert_int(_ledger.amount(C.FEES)).is_equal(0)
	assert_int(_ledger.cash_change()).is_equal(0)
	assert_int(_changes[0]).is_equal(2)


func test_a_movement_stamped_with_a_new_days_tick_lands_on_that_day() -> void:
	assert_bool(_wallet.credit(300, C.FEES)).is_true()
	# The clock has moved to the next day but no tick reached the ledger yet.
	_clock.tick = GameCalendar.day_start(1)
	assert_bool(_wallet.spend(60, C.WAGES)).is_true()
	assert_int(_ledger.day()).is_equal(1)
	assert_int(_ledger.amount(C.FEES)).is_equal(0)
	assert_int(_ledger.wages_paid()).is_equal(60)


func test_ticks_within_the_day_keep_the_totals() -> void:
	assert_bool(_wallet.credit(300, C.FEES)).is_true()
	for i in 20:
		_step()
	assert_int(_ledger.day()).is_equal(0)
	assert_int(_ledger.amount(C.FEES)).is_equal(300)
	assert_int(_changes[0]).is_equal(1)


func test_a_snapshot_round_trips_through_json() -> void:
	assert_bool(_wallet.credit(300, C.FEES)).is_true()
	assert_bool(_wallet.spend(400, C.BUILD)).is_false()
	assert_bool(_wallet.spend(120, C.BUILD)).is_true()
	assert_bool(_wallet.spend(60, C.WAGES)).is_true()
	var saved: Dictionary = JSON.parse_string(JSON.stringify(_ledger.to_snapshot()))
	var other: DayLedger = auto_free(DayLedger.new())
	assert_bool(other.from_snapshot(saved)).is_true()
	assert_dict(other.to_snapshot()).is_equal(_ledger.to_snapshot())
	assert_int(other.amount(C.BUILD)).is_equal(-120)
	assert_int(other.wages_paid()).is_equal(60)
	assert_bool(other.is_since_load()).is_false()


## The Wallet takes any category in either direction, so a total of either
## sign in any category saves and loads (Sol review of 884a485).
func test_every_category_round_trips_with_either_sign() -> void:
	assert_bool(_wallet.from_snapshot({"balance": "1000"})).is_true()
	for category in C.values():
		assert_bool(_wallet.spend(10 + category, category)).is_true()
	_assert_round_trip(-1)
	for category in C.values():
		assert_bool(_wallet.credit(50 + category, category)).is_true()
	_assert_round_trip(1)


## Saves and loads the ledger through JSON and checks each total has `sign`.
func _assert_round_trip(sign: int) -> void:
	var saved: Dictionary = JSON.parse_string(JSON.stringify(_ledger.to_snapshot()))
	var other: DayLedger = auto_free(DayLedger.new())
	assert_bool(other.from_snapshot(saved)).override_failure_message(str(saved)).is_true()
	assert_dict(other.to_snapshot()).is_equal(_ledger.to_snapshot())
	for category in C.values():
		assert_int(signi(other.amount(category))).is_equal(sign)


func test_a_bad_snapshot_is_refused_and_changes_nothing() -> void:
	assert_bool(_wallet.credit(300, C.FEES)).is_true()
	var before := _ledger.to_snapshot()
	var bad_cases: Array = []
	for key in before.keys():
		if DayLedger.OPTIONAL_CATEGORY_KEYS.has(key):
			continue
		var missing := before.duplicate()
		missing.erase(key)
		bad_cases.append(missing)
	var extra := before.duplicate()
	extra["other"] = "1"
	bad_cases.append(extra)
	for change in [
		["day", "-1"],
		["day", 3],
		["since_load", "no"],
		["fees", str(-DayLedger.MAX_TOTAL - 1)],
		["wages", str(DayLedger.MAX_TOTAL + 1)],
		["build", "1.5"],
		["shop", "x"],
		["opening", str(DayLedger.MAX_TOTAL + 1)],
		["upkeep", "x"],
		["upkeep", 4],
	]:
		var wrong := before.duplicate()
		wrong[change[0]] = change[1]
		bad_cases.append(wrong)
	for data in bad_cases:
		assert_bool(_ledger.from_snapshot(data)).override_failure_message(str(data)).is_false()
	assert_dict(_ledger.to_snapshot()).is_equal(before)


func test_a_load_with_no_saved_ledger_counts_since_the_load() -> void:
	assert_bool(_wallet.credit(300, C.FEES)).is_true()
	_clock.tick = GameCalendar.tick_at(3, 14 * 60)
	_ledger.start_since_load()
	assert_bool(_ledger.is_since_load()).is_true()
	assert_int(_ledger.day()).is_equal(3)
	assert_int(_ledger.amount(C.FEES)).is_equal(0)
	assert_bool(_wallet.credit(25, C.SHOP)).is_true()
	assert_int(_ledger.amount(C.SHOP)).is_equal(25)
	assert_bool(_ledger.is_since_load()).is_true()
	_to_midnight(4)
	_step()
	assert_bool(_ledger.is_since_load()).is_false()
	assert_int(_ledger.amount(C.SHOP)).is_equal(0)


func test_the_saved_day_must_be_the_clocks_day() -> void:
	var clock := {"tick": str(GameCalendar.tick_at(2, 600))}
	var ledger := _ledger.to_snapshot()
	ledger["day"] = "2"
	assert_str(DayLedger.day_link_problem(ledger, clock)).is_empty()
	ledger["day"] = "1"
	assert_str(DayLedger.day_link_problem(ledger, clock)).contains("day 1")
	ledger["day"] = "3"
	assert_str(DayLedger.day_link_problem(ledger, clock)).contains("day 3")


func test_the_saved_wages_paid_must_be_the_settlements_wages_paid_today() -> void:
	var ledger := _ledger.to_snapshot()
	ledger["wages"] = "-150"
	var settlement := {"wages_paid_today": "150"}
	assert_str(DayLedger.wages_link_problem(ledger, settlement)).is_empty()
	settlement["wages_paid_today"] = "90"
	assert_str(DayLedger.wages_link_problem(ledger, settlement)).contains("150")
	ledger["since_load"] = true
	assert_str(DayLedger.wages_link_problem(ledger, settlement)).is_empty()


func test_a_ledger_with_no_settlement_wage_state_is_refused() -> void:
	var ledger := _ledger.to_snapshot()
	assert_str(DayLedger.wages_link_problem(ledger, {"owed": []})).contains("no wages paid")
	ledger["since_load"] = true
	assert_str(DayLedger.wages_link_problem(ledger, {"owed": []})).contains("no wages paid")
