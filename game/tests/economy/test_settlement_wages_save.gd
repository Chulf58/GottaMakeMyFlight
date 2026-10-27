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
	assert_int(_kit.settlement.wages_paid_today()).is_equal(60)


func test_a_save_taken_before_midnight_charges_the_new_day_once_after_loading() -> void:
	_kit.hire(CHECKIN)
	_kit.near_midnight(1, 40)
	_kit.world.step()
	_load_into_new_session(_kit.save())
	for i in 80:
		_kit.world.step()
	assert_int(_kit.world.sim.wallet.balance).is_equal(1000 - 60)
	assert_array(_kit.charges).is_equal([[1, 60, 0]])


func test_loading_a_save_taken_just_after_midnight_never_charges_that_day_twice() -> void:
	_kit.hire(CHECKIN)
	_kit.near_midnight(1, 1)
	_kit.world.step()
	_kit.world.step()
	assert_int(_kit.world.sim.wallet.balance).is_equal(1000 - 60)
	_load_into_new_session(_kit.save())
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
	assert_bool(_kit.world.sim.wallet.spend(950)).is_true()
	_kit.cross(1)
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
	assert_array(_kit.charges).is_equal([[3, 60, 0]])


func test_a_snapshot_holds_the_wage_state_as_decimal_strings() -> void:
	_kit.hire(CHECKIN)
	_kit.cross(1)
	var data := _kit.settlement.to_snapshot()
	assert_str(data["wages_owed"]).is_equal("0")
	assert_str(data["wages_day"]).is_equal("1")
	assert_str(data["wages_paid_today"]).is_equal("60")


func test_a_malformed_wage_key_is_refused_and_changes_nothing() -> void:
	_kit.hire(CHECKIN)
	_kit.cross(1)
	var good := _kit.settlement.to_snapshot()
	var too_big := str(Wallet.MAX_BALANCE + 1)
	var bad_values := {
		"wages_owed": [5, "-1", too_big, "x"],
		"wages_paid_today": [5, "-1", too_big, "x"],
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
