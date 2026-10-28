class_name TestSettlementWagesWorld
extends GdUnitTestSuite
## Staff wages on the real main scene: the nodes are wired, and a whole-world
## save whose settlement was last charged for a day after the clock's day is
## refused (SaveLinks), while a save from before wages and a save with no day
## charged yet still load. One boot of main.tscn for the file.

const SEED := 27_102_026

var _main: Node
var _save: SaveGame


func before() -> void:
	_main = SaveTestKit.boot(self, SEED)
	_save = SaveTestKit.save_game(_main)


func after() -> void:
	_main.free()


func _taken() -> Dictionary:
	return JSON.parse_string(JSON.stringify(_save.snapshot(), "", true, true))


func test_the_scene_wires_staff_into_settlement_and_the_grant() -> void:
	var settlement: Settlement = _main.get_node("Settlement")
	assert_object(settlement.staff).is_same(_main.get_node("Staff"))
	assert_object((_main.get_node("RescueGrant") as RescueGrant).settlement).is_same(settlement)
	var wallet := (_main.get_node("Finances") as Finances).wallet
	assert_bool(wallet.credit_claim.is_valid()).is_true()


func test_a_save_charged_for_a_day_after_the_clock_day_is_refused_and_changes_nothing() -> void:
	var data := _taken()
	var before_text := JSON.stringify(_taken())
	data["settlement"]["wages_day"] = "9"
	assert_bool(_save.load_world(data)).is_false()
	assert_str(_save.message_text()).contains("wages were last charged for day 9")
	assert_str(JSON.stringify(_taken())).is_equal(before_text)


func test_a_save_owing_wages_while_the_wallet_holds_money_is_refused() -> void:
	var data := _taken()
	var before_text := JSON.stringify(_taken())
	data["settlement"]["wages_owed"] = "5"
	data["wallet"]["balance"] = "10"
	assert_bool(_save.load_world(data)).is_false()
	assert_str(_save.message_text()).contains("wages are owed while the wallet holds money")
	assert_str(JSON.stringify(_taken())).is_equal(before_text)
	data["wallet"]["balance"] = "0"
	assert_bool(_save.load_world(data)).is_true()


func test_a_save_with_no_day_charged_yet_loads() -> void:
	var data := _taken()
	data["settlement"]["wages_day"] = str(Settlement.NO_DAY)
	assert_bool(_save.load_world(data)).is_true()


func test_a_save_from_before_wages_loads() -> void:
	var data := _taken()
	var settlement: Dictionary = data["settlement"]
	for key in Settlement.OPTIONAL_SNAPSHOT_KEYS:
		settlement.erase(key)
	settlement.erase(Settlement.WAGE_TIMING_KEY)
	# The day ledger came after wages, so a save from before them has none.
	data.erase("day_ledger")
	assert_bool(_save.load_world(data)).is_true()
	assert_int((_main.get_node("Settlement") as Settlement).wages_owed()).is_equal(0)
