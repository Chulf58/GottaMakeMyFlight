class_name TestSettlementUpkeep
extends GdUnitTestSuite
## Toilet upkeep (decision toilet-design-queue-free-reservable-stalls-per-stall-
## daily-u, point 2): on the last tick of each day, next to the wages, every
## ready toilet room is charged PriceTable.TOILET_STALL_UPKEEP per stall. What the
## wallet cannot pay is owed upkeep, kept apart from owed wages. Money coming in
## pays owed wages first, then owed upkeep (decision owed-wages-paid-
## synchronously-on-every-credit-rescue-grant-clears-wage-debt), and the
## DayLedger books each on its own line.

const C := Wallet.Category
const CHECKIN := SettlementWagesKit.CHECKIN
const RATE := PriceTable.TOILET_STALL_UPKEEP

var _kit: SettlementWagesKit
var _ledger: DayLedger
var _upkeep_changes: Array = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_kit = SettlementWagesKit.new(self)
	_watch()


func after_test() -> void:
	_kit.free_all()


## Follows the current kit's wallet and settlement with a fresh ledger.
func _watch() -> void:
	_kit.world.sim.wallet.clock = _kit.world.clock
	_ledger = auto_free(DayLedger.new())
	_ledger.bind(_kit.world.sim.wallet, _kit.world.clock)
	_upkeep_changes = []
	_kit.settlement.upkeep_owed_changed.connect(
		func(owed: int) -> void: _upkeep_changes.append(owed)
	)


## A toilet room three rows deep on the kit's grid with `stalls` 1x2 stalls
## along its top and a sink after them, each with its approach cell in the room;
## `with_sink` false leaves it not ready. Returns its room id.
func _toilet(stalls: int, top := 1, with_sink := true) -> int:
	var grid := _kit.world.grid
	var area := Rect2i(1, top, stalls + 1, 3)
	var room := grid.apply(BuildEdit.place_room(area, &"toilet"))
	assert_bool(room.ok).is_true()
	for i in stalls:
		PassengerTestWorld.place(grid, &"toilet_stall", Vector2i(1 + i, top), 0)
	if with_sink:
		PassengerTestWorld.place(grid, &"toilet_sink", Vector2i(1 + stalls, top), 0)
	return room.room_id


func _empty_wallet() -> void:
	var wallet := _kit.world.sim.wallet
	assert_bool(wallet.spend(wallet.balance, C.BUILD)).is_true()


func test_midnight_charges_each_stall_of_a_ready_toilet() -> void:
	assert_int(RATE).is_greater(0)
	var room_id := _toilet(3)
	assert_bool(RoomRules.status(_kit.world.grid, room_id).ok).is_true()
	_kit.charge(1)
	print("balance %d ledger %s" % [_kit.world.sim.wallet.balance, _ledger.to_snapshot()])
	assert_int(_kit.world.sim.wallet.balance).is_equal(1000 - 3 * RATE)
	assert_int(_ledger.upkeep_paid()).is_equal(3 * RATE)
	assert_int(_ledger.amount(C.UPKEEP)).is_equal(-3 * RATE)
	assert_int(_ledger.wages_paid()).is_equal(0)
	assert_int(_kit.settlement.upkeep_owed()).is_equal(0)
	for i in 50:
		_kit.world.step()
	assert_int(_kit.world.sim.wallet.balance).is_equal(1000 - 3 * RATE)


func test_nothing_is_charged_for_a_toilet_before_midnight() -> void:
	_toilet(2)
	_kit.near_midnight(1, 40)
	for i in 30:
		_kit.world.step()
	assert_int(_kit.world.sim.wallet.balance).is_equal(1000)


func test_a_toilet_that_is_not_ready_is_not_charged() -> void:
	var room_id := _toilet(2, 1, false)
	assert_bool(RoomRules.status(_kit.world.grid, room_id).ok).is_false()
	_kit.charge(1)
	assert_int(_kit.world.sim.wallet.balance).is_equal(1000)
	assert_int(_ledger.upkeep_paid()).is_equal(0)


func test_every_ready_toilet_is_charged_and_wages_with_it() -> void:
	_toilet(1, 0)
	_toilet(2, 3)
	_kit.hire(CHECKIN)
	_kit.charge(1)
	var wages := PriceTable.wage_of(CHECKIN)
	print("balance %d ledger %s" % [_kit.world.sim.wallet.balance, _ledger.to_snapshot()])
	assert_int(_kit.world.sim.wallet.balance).is_equal(1000 - wages - 3 * RATE)
	assert_int(_ledger.wages_paid()).is_equal(wages)
	assert_int(_ledger.upkeep_paid()).is_equal(3 * RATE)
	assert_int(_ledger.operating_result()).is_equal(-wages - 3 * RATE)
	assert_int(_ledger.cash_change()).is_equal(-wages - 3 * RATE)


func test_a_short_wallet_pays_wages_first_and_owes_the_upkeep() -> void:
	_toilet(2)
	_kit.hire(CHECKIN)
	var wages := PriceTable.wage_of(CHECKIN)
	var wallet := _kit.world.sim.wallet
	assert_bool(wallet.spend(wallet.balance - (wages + 5), C.BUILD)).is_true()
	_kit.charge(1)
	print(
		(
			"balance %d wages owed %d upkeep owed %d"
			% [wallet.balance, _kit.settlement.wages_owed(), _kit.settlement.upkeep_owed()]
		)
	)
	assert_int(wallet.balance).is_equal(0)
	assert_int(_kit.settlement.wages_owed()).is_equal(0)
	assert_int(_kit.settlement.upkeep_owed()).is_equal(2 * RATE - 5)
	assert_int(_ledger.wages_paid()).is_equal(wages)
	assert_int(_ledger.upkeep_paid()).is_equal(5)
	assert_array(_upkeep_changes).is_equal([2 * RATE - 5])


func test_an_empty_wallet_owes_both_and_a_credit_pays_wages_then_upkeep() -> void:
	_toilet(2)
	_kit.hire(CHECKIN)
	var wages := PriceTable.wage_of(CHECKIN)
	_empty_wallet()
	_kit.charge(1)
	assert_int(_kit.settlement.wages_owed()).is_equal(wages)
	assert_int(_kit.settlement.upkeep_owed()).is_equal(2 * RATE)
	_kit.world.step()
	var wallet := _kit.world.sim.wallet
	# Less than the wages: all of it goes to the wages, the upkeep waits.
	assert_bool(wallet.credit(wages - 10, C.FEES)).is_true()
	assert_int(_kit.settlement.wages_owed()).is_equal(10)
	assert_int(_kit.settlement.upkeep_owed()).is_equal(2 * RATE)
	assert_int(wallet.balance).is_equal(0)
	# The rest of the wages, then part of the upkeep.
	assert_bool(wallet.credit(15, C.SHOP)).is_true()
	assert_int(_kit.settlement.wages_owed()).is_equal(0)
	assert_int(_kit.settlement.upkeep_owed()).is_equal(2 * RATE - 5)
	assert_int(wallet.balance).is_equal(0)
	# The rest of the upkeep, and the balance gets what is left.
	assert_bool(wallet.credit(2 * RATE + 7, C.FEES)).is_true()
	assert_int(_kit.settlement.upkeep_owed()).is_equal(0)
	assert_int(wallet.balance).is_equal(12)
	print("ledger %s" % [_ledger.to_snapshot()])
	assert_int(_ledger.wages_paid()).is_equal(wages)
	assert_int(_ledger.upkeep_paid()).is_equal(2 * RATE)
	assert_int(_ledger.cash_change()).is_equal(12)
	assert_int(_ledger.wages_paid()).is_equal(_kit.settlement.wages_paid_today())


func test_a_credit_carries_its_wage_and_upkeep_claims_apart() -> void:
	_toilet(2)
	_kit.hire(CHECKIN)
	var wages := PriceTable.wage_of(CHECKIN)
	_empty_wallet()
	_kit.charge(1)
	var seen: Array = []
	_kit.world.sim.wallet.transaction.connect(
		func(amount: int, category: int, claimed: Dictionary, _tick: int) -> void:
			seen.append([amount, category, claimed])
	)
	assert_bool(_kit.world.sim.wallet.credit(wages + 2 * RATE + 1, C.FEES)).is_true()
	assert_array(seen).is_equal(
		[[wages + 2 * RATE + 1, C.FEES, {C.WAGES: wages, C.UPKEEP: 2 * RATE}]]
	)


func test_the_tick_sweep_pays_owed_upkeep_after_owed_wages() -> void:
	var data := _kit.settlement.to_snapshot()
	data["wages_owed"] = "30"
	data["upkeep_owed"] = "40"
	assert_bool(_kit.settlement.from_snapshot(data)).is_true()
	assert_int(_kit.world.sim.wallet.balance).is_equal(1000)
	_kit.world.step()
	assert_int(_kit.settlement.wages_owed()).is_equal(0)
	assert_int(_kit.settlement.upkeep_owed()).is_equal(0)
	assert_int(_kit.world.sim.wallet.balance).is_equal(930)
	assert_int(_ledger.wages_paid()).is_equal(30)
	assert_int(_ledger.upkeep_paid()).is_equal(40)


func test_a_short_sweep_pays_the_wages_and_leaves_the_upkeep_owed() -> void:
	assert_bool(_kit.world.sim.wallet.from_snapshot({"balance": "25"})).is_true()
	var data := _kit.settlement.to_snapshot()
	data["wages_owed"] = "20"
	data["upkeep_owed"] = "40"
	assert_bool(_kit.settlement.from_snapshot(data)).is_true()
	_kit.world.step()
	assert_int(_kit.settlement.wages_owed()).is_equal(0)
	assert_int(_kit.settlement.upkeep_owed()).is_equal(35)
	assert_int(_kit.world.sim.wallet.balance).is_equal(0)


func test_owed_upkeep_survives_a_save_and_load() -> void:
	_toilet(2)
	_empty_wallet()
	_kit.charge(1)
	assert_int(_kit.settlement.upkeep_owed()).is_equal(2 * RATE)
	var saved := _kit.save()
	assert_str(saved["settlement"]["upkeep_owed"]).is_equal(str(2 * RATE))
	_kit.remake()
	_watch()
	_empty_wallet()
	_kit.load_save(saved)
	assert_int(_kit.settlement.upkeep_owed()).is_equal(2 * RATE)
	assert_array(_upkeep_changes).is_equal([2 * RATE])
	var s: Dictionary = saved["settlement"]
	assert_str(Settlement.wages_link_problem(s, saved["clock"], saved["wallet"])).is_empty()


func test_a_save_from_before_upkeep_loads_with_none_owed() -> void:
	var data := _kit.settlement.to_snapshot()
	data["upkeep_owed"] = "25"
	assert_bool(_kit.settlement.from_snapshot(data)).is_true()
	assert_int(_kit.settlement.upkeep_owed()).is_equal(25)
	data.erase("upkeep_owed")
	assert_bool(_kit.settlement.from_snapshot(data)).is_true()
	assert_int(_kit.settlement.upkeep_owed()).is_equal(0)
	# Older still: no wage keys either.
	assert_bool(_kit.settlement.from_snapshot({"owed": []})).is_true()
	assert_int(_kit.settlement.upkeep_owed()).is_equal(0)


func test_a_bad_saved_upkeep_is_refused_and_changes_nothing() -> void:
	var data := _kit.settlement.to_snapshot()
	data["upkeep_owed"] = "25"
	assert_bool(_kit.settlement.from_snapshot(data)).is_true()
	for bad in [5, "-1", "x", str(Settlement.MAX_UPKEEP + 1)]:
		data["upkeep_owed"] = bad
		assert_bool(_kit.settlement.from_snapshot(data)).is_false()
	assert_int(_kit.settlement.upkeep_owed()).is_equal(25)


func test_upkeep_owed_while_the_wallet_holds_money_is_a_broken_link() -> void:
	var owed := {"upkeep_owed": "5"}
	assert_str(Settlement.upkeep_debt_problem(owed, {"balance": "0"})).is_empty()
	assert_str(Settlement.upkeep_debt_problem(owed, {"balance": "1"})).contains("upkeep")
	assert_str(Settlement.upkeep_debt_problem({"upkeep_owed": "0"}, {"balance": "9"})).is_empty()
	assert_str(Settlement.upkeep_debt_problem({"owed": []}, {"balance": "9"})).is_empty()
	var saved := _kit.save()
	var s: Dictionary = saved["settlement"]
	s["upkeep_owed"] = "5"
	assert_str(Settlement.wages_link_problem(s, saved["clock"], saved["wallet"])).contains("upkeep")


func test_each_day_is_charged_its_upkeep() -> void:
	_toilet(1)
	_kit.charge(1)
	_kit.world.step()
	assert_int(_kit.world.sim.wallet.balance).is_equal(1000 - RATE)
	_kit.charge(2)
	assert_int(_kit.world.sim.wallet.balance).is_equal(1000 - 2 * RATE)
