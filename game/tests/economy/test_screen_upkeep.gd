class_name TestScreenUpkeep
extends GdUnitTestSuite
## Screen upkeep (Boredom 4/5; decision boredom-and-shops-design-boredom-need-
## while-waiting-kiosk-sh, point 3): on the last tick of each day, with the
## toilet upkeep, every screen stand on the grid is charged
## PriceTable.SCREEN_UPKEEP, whether it stands in a room or not. It is booked
## as upkeep in the DayLedger, and what the wallet cannot pay is owed upkeep.

const C := Wallet.Category
const RATE := PriceTable.SCREEN_UPKEEP

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


func _screen(cell: Vector2i) -> int:
	return PassengerTestWorld.place(_kit.world.grid, ScreenCoverage.SCREEN_ID, cell, 0)


func test_midnight_charges_each_screen_outside_any_room() -> void:
	_screen(Vector2i(1, 1))
	_screen(Vector2i(4, 1))
	assert_int(_kit.world.grid.room_ids().size()).is_equal(0)
	_kit.charge(1)
	var seen := str(_ledger.to_snapshot())
	print("two screens, day 1: %s" % seen)
	assert_int(_kit.world.sim.wallet.balance).override_failure_message(seen).is_equal(
		1000 - 2 * RATE
	)
	assert_int(_ledger.upkeep_paid()).is_equal(2 * RATE)
	assert_int(_ledger.amount(C.UPKEEP)).is_equal(-2 * RATE)
	assert_int(_ledger.operating_result()).is_equal(-2 * RATE)
	# Charged once a day, not again before the next midnight.
	for i in 50:
		_kit.world.step()
	assert_int(_kit.world.sim.wallet.balance).is_equal(1000 - 2 * RATE)


func test_a_screen_in_a_room_is_charged_once_with_the_toilet() -> void:
	var grid := _kit.world.grid
	var room := grid.apply(BuildEdit.place_room(Rect2i(1, 1, 3, 3), &"toilet"))
	assert_bool(room.ok).is_true()
	PassengerTestWorld.place(grid, &"toilet_stall", Vector2i(1, 1), 0)
	PassengerTestWorld.place(grid, &"toilet_sink", Vector2i(2, 1), 0)
	_screen(Vector2i(3, 3))
	_screen(Vector2i(5, 3))
	assert_bool(RoomRules.status(grid, room.room_id).ok).is_true()
	_kit.charge(1)
	var due := PriceTable.TOILET_STALL_UPKEEP + 2 * RATE
	assert_int(_ledger.upkeep_paid()).is_equal(due)
	assert_int(_kit.world.sim.wallet.balance).is_equal(1000 - due)


func test_an_empty_wallet_owes_the_screen_upkeep() -> void:
	_screen(Vector2i(1, 1))
	var wallet := _kit.world.sim.wallet
	assert_bool(wallet.spend(wallet.balance, C.BUILD)).is_true()
	_kit.charge(1)
	assert_int(wallet.balance).is_equal(0)
	assert_int(_kit.settlement.upkeep_owed()).is_equal(RATE)


func test_no_screen_no_charge() -> void:
	_kit.charge(1)
	assert_int(_ledger.upkeep_paid()).is_equal(0)
	assert_int(_kit.world.sim.wallet.balance).is_equal(1000)
