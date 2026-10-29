class_name TestWalletClaim
extends GdUnitTestSuite
## Wallet.credit_claim: debts that take their share of a credit before the
## balance sees it, each under its Wallet.Category. Room is checked on what is
## left after the debts, a refused credit leaves the debts as they were, and a
## claim that asks for more than the credit or for an unknown category refuses
## the credit loudly.

var _debt := [0]
var _wallet: Wallet


func before_test() -> void:
	_debt[0] = 0
	_wallet = Wallet.new()
	var debt := _debt
	_wallet.credit_claim = func(amount: int, commit: bool) -> Dictionary:
		var taken := mini(debt[0], amount)
		if commit:
			debt[0] -= taken
		return {Wallet.Category.WAGES: taken}


func test_a_credit_pays_the_debt_first_and_the_balance_gets_the_rest() -> void:
	_debt[0] = 70
	assert_bool(_wallet.credit(100, Wallet.Category.FEES)).is_true()
	assert_int(_debt[0]).is_equal(0)
	assert_int(_wallet.balance).is_equal(30)


func test_a_credit_smaller_than_the_debt_all_goes_to_the_debt() -> void:
	_debt[0] = 70
	assert_bool(_wallet.credit(50, Wallet.Category.FEES)).is_true()
	assert_int(_debt[0]).is_equal(20)
	assert_int(_wallet.balance).is_equal(0)


func test_room_is_checked_on_what_is_left_after_the_debt() -> void:
	_debt[0] = Wallet.MAX_BALANCE - 100
	assert_bool(_wallet.credit(Wallet.MAX_BALANCE + 50, Wallet.Category.FEES)).is_true()
	assert_int(_debt[0]).is_equal(0)
	assert_int(_wallet.balance).is_equal(150)


func test_a_credit_that_does_not_fit_after_the_debt_is_refused_and_the_debt_stays() -> void:
	_debt[0] = 40
	assert_bool(_wallet.credit(Wallet.MAX_BALANCE - 10, Wallet.Category.FEES)).is_true()
	var balance := _wallet.balance
	assert_int(balance).is_equal(Wallet.MAX_BALANCE - 50)
	_debt[0] = 5
	assert_bool(_wallet.credit(Wallet.MAX_BALANCE, Wallet.Category.FEES)).is_false()
	assert_int(_debt[0]).is_equal(5)
	assert_int(_wallet.balance).is_equal(balance)


func test_without_a_claim_the_whole_credit_lands() -> void:
	_wallet.credit_claim = Callable()
	assert_bool(_wallet.credit(100, Wallet.Category.FEES)).is_true()
	assert_int(_wallet.balance).is_equal(100)
	assert_bool(_wallet.credit(Wallet.MAX_BALANCE, Wallet.Category.FEES)).is_false()
	assert_int(_wallet.balance).is_equal(100)


func test_two_debts_each_take_their_share() -> void:
	var debts := [30, 50]
	_wallet.credit_claim = func(amount: int, commit: bool) -> Dictionary:
		var wages := mini(debts[0], amount)
		var upkeep := mini(debts[1], amount - wages)
		if commit:
			debts[0] -= wages
			debts[1] -= upkeep
		return {Wallet.Category.WAGES: wages, Wallet.Category.UPKEEP: upkeep}
	assert_bool(_wallet.credit(60, Wallet.Category.FEES)).is_true()
	assert_array(debts).is_equal([0, 20])
	assert_int(_wallet.balance).is_equal(0)
	assert_bool(_wallet.credit(25, Wallet.Category.FEES)).is_true()
	assert_array(debts).is_equal([0, 0])
	assert_int(_wallet.balance).is_equal(5)


func test_a_claim_for_more_than_the_credit_is_refused() -> void:
	var commits := [0]
	_wallet.credit_claim = func(amount: int, commit: bool) -> Dictionary:
		if commit:
			commits[0] += 1
		return {Wallet.Category.WAGES: amount, Wallet.Category.UPKEEP: 1}
	assert_bool(_wallet.credit(10, Wallet.Category.FEES)).is_false()
	assert_int(commits[0]).is_equal(0)
	assert_int(_wallet.balance).is_equal(0)


func test_a_claim_with_a_negative_share_or_an_unknown_category_is_refused() -> void:
	for claims in [{Wallet.Category.WAGES: -1}, {99: 5}, {Wallet.Category.WAGES: "5"}]:
		var shares: Dictionary = claims
		_wallet.credit_claim = func(_amount: int, _commit: bool) -> Dictionary: return shares
		(
			assert_bool(_wallet.credit(10, Wallet.Category.FEES))
			. override_failure_message(str(shares))
			. is_false()
		)
	assert_int(_wallet.balance).is_equal(0)


## can_credit() answers what credit() would do, room counted after the debt,
## and changes neither the balance nor the debt.
func test_can_credit_counts_the_debt_and_changes_nothing() -> void:
	assert_bool(_wallet.from_snapshot({"balance": str(Wallet.MAX_BALANCE - 5)})).is_true()
	assert_bool(_wallet.can_credit(10, Wallet.Category.BUILD)).is_false()
	_debt[0] = 5
	assert_bool(_wallet.can_credit(10, Wallet.Category.BUILD)).is_true()
	assert_bool(_wallet.can_credit(11, Wallet.Category.BUILD)).is_false()
	assert_bool(_wallet.can_credit(-1, Wallet.Category.BUILD)).is_false()
	assert_int(_debt[0]).is_equal(5)
	assert_int(_wallet.balance).is_equal(Wallet.MAX_BALANCE - 5)
	assert_bool(_wallet.credit(10, Wallet.Category.BUILD)).is_true()
	assert_int(_debt[0]).is_equal(0)
	assert_int(_wallet.balance).is_equal(Wallet.MAX_BALANCE)
