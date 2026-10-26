class_name TestWallet
extends GdUnitTestSuite

var _seen: Array[int] = []


func _new_wallet(balance: int = 0) -> Wallet:
	return auto_free(Wallet.new(balance)) as Wallet


func _on_changed(balance: int) -> void:
	_seen.append(balance)


func before_test() -> void:
	_seen.clear()


func test_starts_at_the_given_balance_default_zero() -> void:
	assert_int(_new_wallet().balance).is_equal(0)
	assert_int(_new_wallet(500).balance).is_equal(500)


func test_out_of_range_starting_balance_leaves_a_zero_wallet() -> void:
	assert_int(_new_wallet(-1).balance).is_equal(0)
	assert_int(_new_wallet(Wallet.MAX_BALANCE + 1).balance).is_equal(0)


func test_starting_balance_at_both_bounds_is_kept() -> void:
	assert_int(_new_wallet(0).balance).is_equal(0)
	assert_int(_new_wallet(Wallet.MAX_BALANCE).balance).is_equal(Wallet.MAX_BALANCE)


func test_credit_adds_and_emits_the_new_balance() -> void:
	var wallet := _new_wallet(100)
	wallet.changed.connect(_on_changed)
	assert_bool(wallet.credit(50)).is_true()
	assert_int(wallet.balance).is_equal(150)
	assert_array(_seen).is_equal([150])


func test_can_afford_is_true_up_to_the_exact_balance() -> void:
	var wallet := _new_wallet(100)
	assert_bool(wallet.can_afford(100)).is_true()
	assert_bool(wallet.can_afford(101)).is_false()
	assert_bool(wallet.can_afford(0)).is_true()


func test_spend_deducts_and_emits() -> void:
	var wallet := _new_wallet(100)
	wallet.changed.connect(_on_changed)
	assert_bool(wallet.spend(40)).is_true()
	assert_int(wallet.balance).is_equal(60)
	assert_array(_seen).is_equal([60])


func test_spend_down_to_exactly_zero_is_allowed() -> void:
	var wallet := _new_wallet(100)
	assert_bool(wallet.spend(100)).is_true()
	assert_int(wallet.balance).is_equal(0)


func test_overspend_is_refused_with_no_change_and_no_signal() -> void:
	var wallet := _new_wallet(100)
	wallet.changed.connect(_on_changed)
	assert_bool(wallet.spend(101)).is_false()
	assert_int(wallet.balance).is_equal(100)
	assert_array(_seen).is_empty()


func test_negative_amounts_are_refused() -> void:
	var wallet := _new_wallet(100)
	wallet.changed.connect(_on_changed)
	assert_bool(wallet.spend(-5)).is_false()
	assert_bool(wallet.credit(-5)).is_false()
	assert_bool(wallet.can_afford(-5)).is_false()
	assert_int(wallet.balance).is_equal(100)
	assert_array(_seen).is_empty()


func test_zero_spend_and_credit_succeed_without_a_signal() -> void:
	var wallet := _new_wallet(100)
	wallet.changed.connect(_on_changed)
	assert_bool(wallet.spend(0)).is_true()
	assert_bool(wallet.credit(0)).is_true()
	assert_int(wallet.balance).is_equal(100)
	assert_array(_seen).is_empty()


func test_credit_past_the_cap_is_refused() -> void:
	var wallet := _new_wallet(Wallet.MAX_BALANCE - 10)
	wallet.changed.connect(_on_changed)
	assert_bool(wallet.credit(11)).is_false()
	assert_int(wallet.balance).is_equal(Wallet.MAX_BALANCE - 10)
	assert_array(_seen).is_empty()
	assert_bool(wallet.credit(10)).is_true()
	assert_int(wallet.balance).is_equal(Wallet.MAX_BALANCE)


func test_snapshot_round_trips_through_json() -> void:
	var wallet := _new_wallet(12345)
	var parsed: Variant = JSON.parse_string(JSON.stringify(wallet.to_snapshot()))
	var other := _new_wallet(7)
	assert_bool(other.from_snapshot(parsed)).is_true()
	assert_int(other.balance).is_equal(12345)


func test_snapshot_keeps_a_large_balance_exact() -> void:
	var wallet := _new_wallet(Wallet.MAX_BALANCE)
	var parsed: Variant = JSON.parse_string(JSON.stringify(wallet.to_snapshot()))
	var other := _new_wallet()
	assert_bool(other.from_snapshot(parsed)).is_true()
	assert_int(other.balance).is_equal(Wallet.MAX_BALANCE)


func test_from_snapshot_emits_the_restored_balance() -> void:
	var other := _new_wallet(7)
	other.changed.connect(_on_changed)
	assert_bool(other.from_snapshot({"balance": "900"})).is_true()
	assert_array(_seen).is_equal([900])


func test_from_snapshot_rejects_bad_data_and_leaves_the_wallet_alone() -> void:
	var bad_cases: Array[Dictionary] = [
		{},
		{"balance": 100},
		{"balance": "-1"},
		{"balance": "abc"},
		{"balance": "007"},
		{"balance": str(Wallet.MAX_BALANCE + 1)},
		{"balance": "99999999999999999999"},
		{"balance": "100", "extra": 1},
	]
	var wallet := _new_wallet(7)
	wallet.changed.connect(_on_changed)
	for bad in bad_cases:
		assert_bool(wallet.from_snapshot(bad)).is_false()
		assert_int(wallet.balance).is_equal(7)
	assert_array(_seen).is_empty()
