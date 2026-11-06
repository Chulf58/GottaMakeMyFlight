class_name TestPlaytestHookMoneySnapshot
extends GdUnitTestSuite
## The hook's snapshot reports the wallet balance, the debts and a bag summary,
## so a playtester reads money and bags without replaying events. Real main scene.

const MAIN := "res://main/main.tscn"
const HOOK := preload("res://debug/playtest_hook.gd")
var _dir := SaveTestKit.run_dir("playtest_money_snapshot_test")

var _main: Node
var _hook: Node
var _finances: Finances
var _baggage: BaggageSim


func before() -> void:
	_main = load(MAIN).instantiate()
	add_child(_main)
	(_main.get_node("SimClock") as SimClock).set_paused(true)
	_finances = _main.get_node("Finances")
	_baggage = _main.get_node("BaggageSim")
	_hook = HOOK.new()
	_hook.configure(true, _dir)
	add_child(_hook)
	assert_bool(_hook.attach(_main)).is_true()


func after() -> void:
	_hook.detach()
	_hook.free()
	_main.free()
	for name in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute("%s/%s" % [_dir, name])
	DirAccess.remove_absolute(_dir)


func test_the_snapshot_money_follows_the_wallet() -> void:
	var money: Dictionary = _hook.snapshot()["money"]
	print("money %s wallet %d" % [money, _finances.wallet.balance])
	assert_int(money["balance"]).is_equal(_finances.wallet.balance)
	var before_balance: int = money["balance"]
	assert_bool(_finances.wallet.credit(250, Wallet.Category.GRANT)).is_true()
	var after_money: Dictionary = _hook.snapshot()["money"]
	assert_int(after_money["balance"]).is_equal(before_balance + 250)
	assert_int(after_money["wages_owed"]).is_equal(0)
	assert_int(after_money["upkeep_owed"]).is_equal(0)


func test_the_snapshot_bags_count_loaded_missed_and_in_flight() -> void:
	var bags: Dictionary = _hook.snapshot()["bags"]
	assert_dict(bags).is_equal({"loaded": 0, "missed": 0, "in_flight": 0, "by_state": {}})
	_baggage.loaded_total = 3
	_baggage.missed_total = 2
	var riding := Bag.new()
	riding.id = 91
	riding.state = Bag.State.RIDING
	_baggage.bags().append(riding)
	var settled := Bag.new()
	settled.id = 92
	settled.state = Bag.State.LOADED
	_baggage.bags().append(settled)
	bags = _hook.snapshot()["bags"]
	print("bags %s" % [bags])
	assert_int(bags["loaded"]).is_equal(3)
	assert_int(bags["missed"]).is_equal(2)
	assert_int(bags["in_flight"]).is_equal(1)
	assert_dict(bags["by_state"]).is_equal({"RIDING": 1, "LOADED": 1})
	_baggage.bags().clear()
	_baggage.loaded_total = 0
	_baggage.missed_total = 0


func test_the_new_fields_are_json_safe() -> void:
	var snap: Dictionary = _hook.snapshot()
	var text := JSON.stringify({"money": snap["money"], "bags": snap["bags"]})
	var back: Dictionary = JSON.parse_string(text)
	assert_int(int(back["money"]["balance"])).is_equal(_finances.wallet.balance)
