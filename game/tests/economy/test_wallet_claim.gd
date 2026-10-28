class_name TestWalletClaim
extends GdUnitTestSuite
## Wallet.credit_claim: a debt that takes its share of a credit before the
## balance sees it. Room is checked on what is left after the debt, and a
## refused credit leaves the debt as it was.

var _debt := [0]
var _wallet: Wallet


func before_test() -> void:
	_debt[0] = 0
	_wallet = Wallet.new()
	var debt := _debt
	_wallet.credit_claim = func(amount: int, commit: bool) -> int:
		var taken := mini(debt[0], amount)
		if commit:
			debt[0] -= taken
		return taken


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
