class_name TestSettlementWagesSave
extends GdUnitTestSuite
## Saving and loading staff wages: the last charged day is saved with the owed
## wages, so a load never charges a day twice and never skips one, and a save
## from before wages still loads.

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


## Loads `data` into a fresh session, as a restart and a load would.
func _load_into_new_session(data: Dictionary) -> void:
	_kit.remake()
	_kit.hire(CHECKIN)
	_kit.load_save(data)


func test_a_save_taken_mid_day_loads_without_a_charge() -> void:
	_kit.hire(CHECKIN)
	_kit.cross(1)
	_load_into_new_session(_kit.save())
	var balance := _kit.world.sim.wallet.balance
	for i in 20:
		_kit.world.step()
	assert_int(_kit.world.sim.wallet.balance).is_equal(balance)
	assert_array(_kit.charges).is_empty()
	assert_int(_kit.settlement.wages_paid_today()).is_equal(0)


func test_a_save_taken_before_the_charge_tick_charges_the_day_once_after_loading() -> void:
	_kit.hire(CHECKIN)
	_kit.near_midnight(1, 40)
	_kit.world.step()
	_load_into_new_session(_kit.save())
	for i in 80:
		_kit.world.step()
	assert_int(_kit.world.sim.wallet.balance).is_equal(1000 - 60)
	assert_array(_kit.charges).is_equal([[0, 60, 0]])


## Saved on the very tick before the charge: the load charges it, once.
func test_a_save_taken_one_tick_before_the_charge_tick_charges_it_once() -> void:
	_kit.hire(CHECKIN)
	_kit.near_midnight(1, 3)
	_kit.world.step()
	assert_bool(GameCalendar.is_last_tick_of_day(_kit.world.clock.tick)).is_false()
	_load_into_new_session(_kit.save())
	for i in 20:
		_kit.world.step()
	assert_int(_kit.world.sim.wallet.balance).is_equal(1000 - 60)
	assert_array(_kit.charges).is_equal([[0, 60, 0]])
	assert_int(_kit.settlement.wages_paid_today()).is_equal(0)


## Saved on the charge tick itself: the load keeps the charge and its paid
## total, charges nothing again, and starts the next day over at 0.
func test_loading_a_save_taken_on_the_charge_tick_never_charges_that_day_twice() -> void:
	_kit.hire(CHECKIN)
	_kit.charge(1)
	assert_int(_kit.world.sim.wallet.balance).is_equal(1000 - 60)
	var saved := _kit.save()
	_load_into_new_session(saved)
	assert_int(_kit.settlement.wages_paid_today()).is_equal(60)
	assert_str(_kit.settlement.to_snapshot()["wages_day"]).is_equal("0")
	_kit.world.step()
	assert_int(_kit.settlement.wages_paid_today()).is_equal(0)
	for i in 20:
		_kit.world.step()
	assert_int(_kit.world.sim.wallet.balance).is_equal(1000 - 60)
	assert_array(_kit.charges).is_empty()


## Loading an earlier save into the running session rewinds the clock, the
## wallet and the settlement together, so the midnight is charged once more.
func test_rewinding_to_a_save_before_midnight_charges_it_once_more() -> void:
	_kit.hire(CHECKIN)
	_kit.near_midnight(1, 40)
	_kit.world.step()
	var earlier := _kit.save()
	for i in 80:
		_kit.world.step()
	assert_int(_kit.world.sim.wallet.balance).is_equal(1000 - 60)
	_kit.load_save(earlier)
	for i in 80:
		_kit.world.step()
	assert_int(_kit.world.sim.wallet.balance).is_equal(1000 - 60)
	assert_array(_kit.charges).has_size(2)


func test_owed_wages_and_the_paid_total_survive_a_save() -> void:
	_kit.hire(CHECKIN, 2)
	assert_bool(_kit.world.sim.wallet.spend(950, Wallet.Category.BUILD)).is_true()
	_kit.charge(1)
	assert_int(_kit.settlement.wages_owed()).is_equal(70)
	var saved := Settlement.new()
	assert_bool(saved.from_snapshot(_kit.save()["settlement"])).is_true()
	assert_int(saved.wages_owed()).is_equal(70)
	assert_int(saved.wages_paid_today()).is_equal(50)
	saved.free()


func test_a_save_from_before_wages_loads_with_no_debt_and_charges_from_the_next_midnight() -> void:
	_kit.hire(CHECKIN)
	_kit.near_midnight(3, 2000)
	assert_bool(_kit.settlement.from_snapshot({"owed": ["37"]})).is_true()
	assert_int(_kit.settlement.wages_owed()).is_equal(0)
	assert_int(_kit.settlement.wages_paid_today()).is_equal(0)
	assert_array(_kit.settlement.owed()).is_equal([37])
	for i in 10:
		_kit.world.step()
	assert_int(_kit.world.sim.wallet.balance).is_equal(1000 + 37)
	assert_array(_kit.charges).is_empty()
	_kit.cross(3)
	assert_int(_kit.world.sim.wallet.balance).is_equal(1000 + 37 - 60)
	assert_array(_kit.charges).is_equal([[2, 60, 0]])


func test_a_snapshot_holds_the_wage_state_as_decimal_strings() -> void:
	_kit.hire(CHECKIN)
	_kit.charge(1)
	var data := _kit.settlement.to_snapshot()
	assert_str(data["wages_owed"]).is_equal("0")
	assert_str(data["wages_day"]).is_equal("0")
	assert_str(data["wages_paid_today"]).is_equal("60")


func test_a_malformed_wage_key_is_refused_and_changes_nothing() -> void:
	_kit.hire(CHECKIN)
	_kit.charge(1)
	var good := _kit.settlement.to_snapshot()
	var too_big := str(Settlement.MAX_WAGES + 1)
	var paid_too_big := str(Settlement.MAX_WAGES_PAID_TODAY + 1)
	var bad_values := {
		"wages_owed": [5, "-1", too_big, "x"],
		"wages_paid_today": [5, "-1", paid_too_big, "x"],
		"wages_day": [5, "-2", "x"],
	}
	for key in bad_values:
		for value in bad_values[key]:
			var data := good.duplicate()
			data[key] = value
			assert_bool(_kit.settlement.from_snapshot(data)).is_false()
	var extra := good.duplicate()
	extra["wages_extra"] = "1"
	assert_bool(_kit.settlement.from_snapshot(extra)).is_false()
	assert_int(_kit.settlement.wages_paid_today()).is_equal(60)
	assert_int(_kit.settlement.wages_owed()).is_equal(0)
	_kit.world.step()
	assert_array(_kit.charges).has_size(1)


func test_the_wage_keys_come_as_a_group_and_a_partial_set_is_refused() -> void:
	_kit.hire(CHECKIN)
	_kit.cross(1)
	var good := _kit.settlement.to_snapshot()
	var keys := Settlement.OPTIONAL_SNAPSHOT_KEYS
	for i in range(1, 7):
		var data := {"owed": good["owed"]}
		for k in keys.size():
			if i & (1 << k) != 0:
				data[keys[k]] = good[keys[k]]
		assert_bool(_kit.settlement.from_snapshot(data)).is_false()
		assert_bool(_kit.settlement.from_snapshot(good)).is_true()
	assert_bool(_kit.settlement.from_snapshot({"owed": []})).is_true()


func test_a_day_other_than_the_clock_day_is_a_broken_link() -> void:
	var timed := {"wages_day": "3", Settlement.WAGE_TIMING_KEY: Settlement.WAGE_TIMING_LAST_TICK}
	var mid_day := {"tick": str(GameCalendar.day_start(4) + 100)}
	var last_tick := {"tick": str(GameCalendar.day_start(5) - 1)}
	assert_str(Settlement.wages_day_problem(timed, mid_day)).is_empty()
	# The clock's own day is charged only on its last tick, so it is not a mid-day state.
	timed["wages_day"] = "4"
	assert_str(Settlement.wages_day_problem(timed, mid_day)).contains("day 4")
	assert_str(Settlement.wages_day_problem(timed, last_tick)).is_empty()
	timed["wages_day"] = "3"
	assert_str(Settlement.wages_day_problem(timed, last_tick)).is_empty()
	for day in ["5", "2", "0"]:
		timed["wages_day"] = day
		assert_str(Settlement.wages_day_problem(timed, mid_day)).contains("day " + day)
	timed["wages_day"] = str(Settlement.NO_DAY)
	assert_str(Settlement.wages_day_problem(timed, mid_day)).is_empty()
	assert_str(Settlement.wages_day_problem({"owed": []}, mid_day)).is_empty()


## The link check holds on every tick a save can be taken, the one that starts a
## day and the ones around it included, with a debt standing and without.
func test_every_save_point_agrees_with_the_link_checks() -> void:
	_kit.hire(CHECKIN)
	assert_bool(_kit.world.sim.wallet.spend(1000, Wallet.Category.BUILD)).is_true()
	_kit.near_midnight(1, 4)
	for i in 10:
		_kit.world.step()
		var saved := _kit.save()
		(
			assert_str(
				Settlement.wages_link_problem(saved["settlement"], saved["clock"], saved["wallet"])
			)
			. is_empty()
		)
	assert_int(_kit.settlement.wages_owed()).is_equal(60)
	assert_bool(_kit.world.sim.wallet.credit(100, Wallet.Category.FEES)).is_true()
	var after_pay := _kit.save()
	(
		assert_str(
			Settlement.wages_link_problem(
				after_pay["settlement"], after_pay["clock"], after_pay["wallet"]
			)
		)
		. is_empty()
	)
	assert_int(_kit.world.sim.wallet.balance).is_equal(40)


func test_wages_owed_while_the_wallet_holds_money_is_a_broken_link() -> void:
	var owed := {"wages_owed": "5"}
	assert_str(Settlement.wages_debt_problem(owed, {"balance": "0"})).is_empty()
	assert_str(Settlement.wages_debt_problem(owed, {"balance": "1"})).contains("owed")
	assert_str(Settlement.wages_debt_problem({"wages_owed": "0"}, {"balance": "9"})).is_empty()
	assert_str(Settlement.wages_debt_problem({"owed": []}, {"balance": "9"})).is_empty()
