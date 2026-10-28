class_name TestBuildMenuWages
extends GdUnitTestSuite
## The "Wages paid: N" message (decision daily-wages-are-charged-on-the-last-
## tick-of-the-game-day-and): BuildMenu shows it on the status line each time the
## Settlement pays wages, held like a rescue grant's message, with the debt left
## when there is one. Driven by real wage charges and credits, not by the signal.

const CHECKIN := SettlementWagesKit.CHECKIN

var _kit: SettlementWagesKit
var _port: SubViewport
var _menu: BuildMenu


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_kit = SettlementWagesKit.new(self)
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_menu = BuildMenu.new()
	_menu.settlement = _kit.settlement
	_port.add_child(_menu)


func after_test() -> void:
	_port.free()
	_kit.free_all()


func _text() -> String:
	return _menu.status_label().text


func test_one_wage_charge_shows_one_message_with_the_amount() -> void:
	_kit.hire(CHECKIN)
	assert_str(_text()).is_empty()
	_kit.charge(1)
	assert_array(_kit.payments).is_equal([[60, 0]])
	assert_str(_text()).is_equal("Wages paid: 60")
	assert_bool(_menu.status_label().visible).is_true()
	for i in 20:
		_kit.world.step()
	assert_array(_kit.payments).has_size(1)
	assert_str(_text()).is_equal("Wages paid: 60")


func test_no_message_when_nothing_is_paid() -> void:
	_kit.charge(1)
	assert_array(_kit.payments).is_empty()
	assert_str(_text()).is_empty()
	# A charge the empty wallet cannot pay at all pays 0, and shows nothing.
	var wallet := _kit.world.sim.wallet
	_kit.hire(CHECKIN)
	assert_bool(wallet.spend(wallet.balance, Wallet.Category.BUILD)).is_true()
	_kit.charge(2)
	assert_int(_kit.settlement.wages_owed()).is_equal(60)
	assert_array(_kit.payments).is_empty()
	assert_str(_text()).is_empty()


func test_a_part_payment_shows_the_owed_amount() -> void:
	var wallet := _kit.world.sim.wallet
	_kit.hire(CHECKIN)
	assert_bool(wallet.spend(wallet.balance, Wallet.Category.BUILD)).is_true()
	_kit.charge(1)
	assert_bool(wallet.credit(50, Wallet.Category.FEES)).is_true()
	assert_array(_kit.payments).is_equal([[50, 10]])
	assert_str(_text()).is_equal("Wages paid: 50 (10 owed)")
	assert_bool(wallet.credit(100, Wallet.Category.FEES)).is_true()
	assert_str(_text()).is_equal("Wages paid: 10")


func test_the_message_holds_then_gives_the_status_line_back() -> void:
	_kit.hire(CHECKIN)
	_kit.charge(1)
	assert_str(_text()).is_equal("Wages paid: 60")
	_menu.end_grant_hold()
	assert_str(_text()).is_empty()
