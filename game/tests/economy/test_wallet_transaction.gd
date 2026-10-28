class_name TestWalletTransaction
extends GdUnitTestSuite
## Wallet.transaction (decision money-hover-design-categorised-wallet-
## transactions-feed-a-sa, point 1): every credit and spend names its category,
## and every committed movement emits one transaction with the gross amount
## (spends negative), the category, the wages a credit paid off and the tick
## of the wallet's clock. Refused movements and snapshot restores emit nothing.

const FEES := Wallet.Category.FEES
const BUILD := Wallet.Category.BUILD

var _clock: SimClock
var _wallet: Wallet
## Every transaction, as [amount, category, wages_claimed, tick].
var _seen: Array = []


func before_test() -> void:
	_clock = auto_free(SimClock.new())
	_clock.tick = 1234
	_wallet = Wallet.new(500)
	_wallet.clock = _clock
	_seen = []
	_wallet.transaction.connect(
		func(amount: int, category: int, claimed: int, tick: int) -> void:
			_seen.append([amount, category, claimed, tick])
	)


func test_a_credit_emits_its_amount_category_and_the_clocks_tick() -> void:
	assert_bool(_wallet.credit(120, FEES)).is_true()
	assert_array(_seen).is_equal([[120, FEES, 0, 1234]])
	assert_int(_wallet.balance).is_equal(620)


func test_a_spend_emits_a_negative_amount() -> void:
	assert_bool(_wallet.spend(80, BUILD)).is_true()
	assert_array(_seen).is_equal([[-80, BUILD, 0, 1234]])


func test_each_category_is_carried_as_given() -> void:
	for category in Wallet.Category.values():
		assert_bool(_wallet.credit(1, category)).is_true()
	assert_int(_seen.size()).is_equal(Wallet.Category.size())
	for i in _seen.size():
		assert_int(_seen[i][1]).is_equal(Wallet.Category.values()[i])


func test_a_failed_spend_or_credit_emits_nothing() -> void:
	assert_bool(_wallet.spend(501, BUILD)).is_false()
	assert_bool(_wallet.spend(-1, BUILD)).is_false()
	assert_bool(_wallet.credit(-1, FEES)).is_false()
	assert_bool(_wallet.credit(Wallet.MAX_BALANCE, FEES)).is_false()
	assert_array(_seen).is_empty()
	assert_int(_wallet.balance).is_equal(500)


func test_an_unknown_category_is_refused_and_emits_nothing() -> void:
	assert_bool(_wallet.credit(10, 99 as Wallet.Category)).is_false()
	assert_bool(_wallet.spend(10, -1 as Wallet.Category)).is_false()
	assert_array(_seen).is_empty()
	assert_int(_wallet.balance).is_equal(500)


func test_a_zero_movement_emits_nothing() -> void:
	assert_bool(_wallet.credit(0, FEES)).is_true()
	assert_bool(_wallet.spend(0, BUILD)).is_true()
	assert_array(_seen).is_empty()


func test_a_snapshot_restore_emits_no_transaction() -> void:
	assert_bool(_wallet.from_snapshot({"balance": "42"})).is_true()
	assert_int(_wallet.balance).is_equal(42)
	assert_array(_seen).is_empty()


func test_a_credit_carries_the_wages_its_claim_took() -> void:
	var debt := [30]
	_wallet.credit_claim = func(amount: int, commit: bool) -> int:
		var taken := mini(debt[0], amount)
		if commit:
			debt[0] -= taken
		return taken
	assert_bool(_wallet.credit(100, FEES)).is_true()
	assert_array(_seen).is_equal([[100, FEES, 30, 1234]])
	assert_int(_wallet.balance).is_equal(570)


func test_a_credit_the_claim_takes_whole_emits_a_transaction_but_no_change() -> void:
	var debt := [300]
	_wallet.credit_claim = func(amount: int, commit: bool) -> int:
		var taken := mini(debt[0], amount)
		if commit:
			debt[0] -= taken
		return taken
	var changes := [0]
	_wallet.changed.connect(func(_balance: int) -> void: changes[0] += 1)
	assert_bool(_wallet.credit(100, FEES)).is_true()
	assert_int(changes[0]).is_equal(0)
	assert_array(_seen).is_equal([[100, FEES, 100, 1234]])
	assert_int(debt[0]).is_equal(200)


func test_a_wallet_with_no_clock_stamps_no_tick() -> void:
	_wallet.clock = null
	assert_bool(_wallet.credit(5, FEES)).is_true()
	assert_array(_seen).is_equal([[5, FEES, 0, Wallet.NO_TICK]])
