class_name TestSettlementWagesTiming
extends GdUnitTestSuite
## Saves from before the wage charge moved to a day's last tick (decision
## daily-wages-are-charged-on-the-last-tick-of-the-game-day-and): their
## wages_day is the day charged at its start, so a load turns it into the day
## earned and the day it is loaded on is charged exactly once.

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


## An old save holds the day charged at its start, which is the clock's own day.
func test_an_old_format_day_is_the_clock_day_and_nothing_else() -> void:
	var clock := {"tick": str(GameCalendar.day_start(4) + 100)}
	var old := {"wages_day": "4"}
	assert_str(Settlement.wages_day_problem(old, clock)).is_empty()
	for day in ["5", "3", "0"]:
		old["wages_day"] = day
		assert_str(Settlement.wages_day_problem(old, clock)).contains("day " + day)


## The old reading of wages_day is migrated on load: a save mid-day D that holds D
## (charged at its start) means days up to D - 1 are paid, so D is charged once,
## at its own last tick.
func test_an_old_format_mid_day_save_charges_that_day_exactly_once() -> void:
	_kit.hire(CHECKIN)
	_kit.cross(1)
	var old := _kit.save()
	var settlement: Dictionary = old["settlement"]
	settlement.erase(Settlement.WAGE_TIMING_KEY)
	settlement["wages_day"] = "1"
	settlement["wages_paid_today"] = "60"
	assert_str(Settlement.wages_link_problem(settlement, old["clock"], old["wallet"])).is_empty()
	_load_into_new_session(old)
	var migrated := _kit.settlement.to_snapshot()
	assert_str(migrated["wages_day"]).is_equal("0")
	assert_str(migrated[Settlement.WAGE_TIMING_KEY]).is_equal(Settlement.WAGE_TIMING_LAST_TICK)
	var balance := _kit.world.sim.wallet.balance
	for i in 20:
		_kit.world.step()
	assert_array(_kit.charges).is_empty()
	_kit.cross(2)
	print("balance %d charges %s" % [_kit.world.sim.wallet.balance, _kit.charges])
	assert_array(_kit.charges).is_equal([[1, 60, 0]])
	assert_int(_kit.world.sim.wallet.balance).is_equal(balance - 60)
	for i in 50:
		_kit.world.step()
	assert_array(_kit.charges).has_size(1)


func test_an_old_format_save_with_no_day_charged_yet_stays_that_way() -> void:
	var data := _kit.settlement.to_snapshot()
	data.erase(Settlement.WAGE_TIMING_KEY)
	data["wages_day"] = str(Settlement.NO_DAY)
	assert_bool(_kit.settlement.from_snapshot(data)).is_true()
	assert_str(_kit.settlement.to_snapshot()["wages_day"]).is_equal(str(Settlement.NO_DAY))


func test_the_wage_timing_key_must_be_the_known_value_and_come_with_the_wage_keys() -> void:
	var good := _kit.settlement.to_snapshot()
	assert_str(good[Settlement.WAGE_TIMING_KEY]).is_equal(Settlement.WAGE_TIMING_LAST_TICK)
	var future := good.duplicate()
	future[Settlement.WAGE_TIMING_KEY] = "2"
	assert_bool(_kit.settlement.from_snapshot(future)).is_false()
	var alone := {"owed": [], Settlement.WAGE_TIMING_KEY: Settlement.WAGE_TIMING_LAST_TICK}
	assert_bool(_kit.settlement.from_snapshot(alone)).is_false()
	assert_bool(_kit.settlement.from_snapshot(good)).is_true()
