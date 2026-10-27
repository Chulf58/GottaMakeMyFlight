class_name TestFinances
extends GdUnitTestSuite
## Finances: the starting budget is credited once when a new game starts, and
## main.tscn hands BuildMode the same Finances node PassengerSim pays into.


func test_entering_the_tree_credits_the_starting_budget_once() -> void:
	var finances: Finances = auto_free(Finances.new())
	assert_int(finances.wallet.balance).is_equal(0)
	add_child(finances)
	assert_int(finances.wallet.balance).is_equal(PriceTable.STARTING_BUDGET)
	assert_bool(finances.start_new_game()).is_false()
	assert_int(finances.wallet.balance).is_equal(PriceTable.STARTING_BUDGET)


func test_a_loaded_wallet_is_not_credited_again() -> void:
	var finances: Finances = auto_free(Finances.new())
	add_child(finances)
	assert_bool(finances.wallet.from_snapshot({"balance": "123"})).is_true()
	assert_bool(finances.start_new_game()).is_false()
	assert_int(finances.wallet.balance).is_equal(123)


func test_a_wallet_restored_before_entering_the_tree_is_not_credited() -> void:
	var finances: Finances = auto_free(Finances.new())
	assert_bool(finances.restore({"balance": "123"})).is_true()
	add_child(finances)
	print("balance after restore then ready %d" % finances.wallet.balance)
	assert_int(finances.wallet.balance).is_equal(123)
	assert_bool(finances.start_new_game()).is_false()
	assert_int(finances.wallet.balance).is_equal(123)


func test_a_refused_restore_changes_nothing() -> void:
	var finances: Finances = auto_free(Finances.new())
	add_child(finances)
	assert_bool(finances.restore({"balance": "-5"})).is_false()
	assert_int(finances.wallet.balance).is_equal(PriceTable.STARTING_BUDGET)
	var fresh: Finances = auto_free(Finances.new())
	assert_bool(fresh.restore({"balance": "-5"})).is_false()
	add_child(fresh)
	assert_int(fresh.wallet.balance).is_equal(PriceTable.STARTING_BUDGET)


func test_main_scene_gives_build_mode_the_finances_node() -> void:
	var state := (load("res://main/main.tscn") as PackedScene).get_state()
	var wired := {}
	for node in state.get_node_count():
		var name := state.get_node_name(node)
		if name != "BuildMode" and name != "PassengerSim":
			continue
		for prop in state.get_node_property_count(node):
			if state.get_node_property_name(node, prop) == "finances":
				wired[name] = state.get_node_property_value(node, prop)
	print("finances wiring %s" % wired)
	assert_that(wired.get("BuildMode")).is_equal(NodePath("../Finances"))
	assert_that(wired.get("PassengerSim")).is_equal(NodePath("../Finances"))
