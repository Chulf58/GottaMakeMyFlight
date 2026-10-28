class_name TestDayLedgerSave
extends GdUnitTestSuite
## The DayLedger on the real main scene and in the whole-world save (decision
## money-hover-design-categorised-wallet-transactions-feed-a-sa, points 3 and
## 5): main.tscn wires the ledger to the scene's wallet and clock and the money
## slot to the ledger; a save holds the ledger as the "day_ledger" part, a load
## mid-day keeps today's totals, an older save without the part loads with the
## ledger counting since the load, and a ledger saved on another day than the
## clock is refused. One boot of main.tscn for the file.

const SEED := 28_102_026
const C := Wallet.Category

var _main: Node
var _save: SaveGame
var _ledger: DayLedger
var _wallet: Wallet


func before() -> void:
	_main = SaveTestKit.boot(self, SEED)
	_save = SaveTestKit.save_game(_main)
	_ledger = _main.get_node("DayLedger")
	_wallet = (_main.get_node("Finances") as Finances).wallet
	for i in 20:
		SaveTestKit.step(_main)


func after() -> void:
	_main.free()


## A save taken now, through JSON as a file holds it.
func _taken() -> Dictionary:
	var data := _save.snapshot()
	assert_bool(data.is_empty()).is_false()
	return JSON.parse_string(JSON.stringify(data, "", true, true))


func _slot() -> MoneySlot:
	return _main.get_node("BuildMenu").find_child("MoneySlot", true, false) as MoneySlot


func test_main_wires_the_ledger_to_the_scenes_wallet_and_clock() -> void:
	var clock: SimClock = _main.get_node("SimClock")
	assert_object(_ledger.clock).is_same(clock)
	assert_object(_ledger.finances).is_same(_main.get_node("Finances"))
	assert_object(_wallet.clock).is_same(clock)
	assert_bool(_wallet.transaction.is_connected(_ledger.record)).is_true()
	assert_bool(clock.ticked.is_connected(_ledger.on_tick)).is_true()
	var menu: BuildMenu = _main.get_node("BuildMenu")
	assert_object(menu.day_ledger).is_same(_ledger)
	assert_object(menu.settlement).is_same(_main.get_node("Settlement"))
	assert_object(_slot()).is_not_null()
	assert_object(_slot().ledger).is_same(_ledger)


func test_a_new_game_records_the_opening_budget_apart_from_earnings() -> void:
	assert_int(_ledger.amount(C.OPENING)).is_equal(PriceTable.STARTING_BUDGET)
	assert_int(_ledger.operating_result()).is_equal(0)
	assert_str(_slot().tooltip_text.get_slice("\n", 0)).is_equal("Today")


func test_a_save_holds_the_ledger_part() -> void:
	var data := _taken()
	assert_bool(data.has("day_ledger")).is_true()
	assert_dict(data["day_ledger"]).is_equal(
		JSON.parse_string(JSON.stringify(_ledger.to_snapshot()))
	)


func test_a_load_mid_day_keeps_todays_totals() -> void:
	assert_bool(_wallet.credit(70, C.SHOP)).is_true()
	assert_bool(_wallet.spend(30, C.BUILD)).is_true()
	var saved := _taken()
	var kept := _ledger.to_snapshot()
	assert_bool(_wallet.credit(500, C.FEES)).is_true()
	for i in 10:
		SaveTestKit.step(_main)
	assert_dict(_ledger.to_snapshot()).is_not_equal(kept)
	assert_bool(_save.load_world(saved)).is_true()
	assert_dict(_ledger.to_snapshot()).is_equal(kept)
	assert_int(_ledger.amount(C.SHOP)).is_greater_equal(70)
	assert_bool(_ledger.is_since_load()).is_false()
	assert_str(_slot().tooltip_text).contains("Shops  +%d" % _ledger.amount(C.SHOP))


func test_an_older_save_without_the_ledger_loads_since_the_load() -> void:
	assert_bool(_wallet.credit(40, C.SHOP)).is_true()
	var old := _taken()
	old.erase("day_ledger")
	var clock: SimClock = _main.get_node("SimClock")
	var saved_day := GameCalendar.day_of(str(old["clock"]["tick"]).to_int())
	assert_int(_ledger.amount(C.SHOP)).is_greater(0)
	assert_bool(_save.load_world(old)).is_true()
	assert_bool(_ledger.is_since_load()).is_true()
	assert_int(_ledger.day()).is_equal(saved_day)
	assert_int(_ledger.day()).is_equal(GameCalendar.day_of(clock.tick))
	assert_int(_ledger.amount(C.SHOP)).is_equal(0)
	assert_str(_slot().tooltip_text.get_slice("\n", 0)).is_equal("Since load")
	# The next save holds the ledger again, still marked since the load.
	assert_bool(_taken()["day_ledger"]["since_load"]).is_true()


func test_a_ledger_saved_on_another_day_than_the_clock_is_refused() -> void:
	var bad := _taken()
	var good_day := str(bad["day_ledger"]["day"]).to_int()
	bad["day_ledger"]["day"] = str(good_day + 1)
	assert_bool(_wallet.credit(11, C.SHOP)).is_true()
	var before := SaveTestKit.checksum(_main)
	assert_bool(_save.load_world(bad)).is_false()
	assert_str(_save.message_text()).contains("day_ledger")
	assert_str(SaveTestKit.checksum(_main)).is_equal(before)


func test_a_bad_ledger_part_is_refused_and_changes_nothing() -> void:
	var bad := _taken()
	bad["day_ledger"]["fees"] = "-1"
	var before := SaveTestKit.checksum(_main)
	assert_bool(_save.load_world(bad)).is_false()
	assert_str(SaveTestKit.checksum(_main)).is_equal(before)
