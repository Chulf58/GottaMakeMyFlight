class_name TestSettlementWages
extends GdUnitTestSuite
## Staff wages (ruling staff-wages-charged-daily-at-midnight-unpaid-wages-
## carried-as-owed): at each midnight every roster member is charged their
## role's daily wage; what the wallet cannot pay is owed and paid first when
## money comes in. Saving and loading is in test_settlement_wages_save.gd.

const CHECKIN := SettlementWagesKit.CHECKIN
const SECURITY := SettlementWagesKit.SECURITY

var _kit: SettlementWagesKit


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_kit = SettlementWagesKit.new(self)


func after_test() -> void:
	_kit.free_all()


func test_every_role_has_a_wage() -> void:
	for role in StaffMember.Role.values():
		assert_int(PriceTable.wage_of(role)).is_greater(0)
	assert_int(PriceTable.wage_of(CHECKIN)).is_equal(60)
	assert_int(PriceTable.wage_of(SECURITY)).is_equal(90)
	assert_int(PriceTable.WAGES.size()).is_equal(StaffMember.Role.values().size())


func test_midnight_charges_each_member_the_wage_of_their_role_once() -> void:
	_kit.hire(CHECKIN, 2)
	_kit.hire(SECURITY)
	_kit.cross(1)
	print("balance %d charges %s" % [_kit.world.sim.wallet.balance, _kit.charges])
	assert_int(_kit.world.sim.wallet.balance).is_equal(1000 - (2 * 60 + 90))
	assert_array(_kit.charges).is_equal([[1, 210, 0]])
	assert_int(_kit.settlement.wages_paid_today()).is_equal(210)
	assert_int(_kit.settlement.wages_owed()).is_equal(0)
	for i in 50:
		_kit.world.step()
	assert_int(_kit.world.sim.wallet.balance).is_equal(1000 - 210)
	assert_array(_kit.charges).has_size(1)


func test_nothing_is_charged_before_midnight() -> void:
	_kit.hire(CHECKIN)
	_kit.near_midnight(1, 40)
	for i in 30:
		_kit.world.step()
	assert_int(_kit.world.sim.wallet.balance).is_equal(1000)
	assert_array(_kit.charges).is_empty()


func test_each_new_day_charges_again() -> void:
	_kit.hire(CHECKIN)
	_kit.cross(1)
	_kit.cross(2)
	assert_array(_kit.charges).is_equal([[1, 60, 0], [2, 60, 0]])
	assert_int(_kit.world.sim.wallet.balance).is_equal(1000 - 120)


## A member fired mid-service stays on the roster until the service ends, and
## midnight falls inside that service.
func test_a_member_leaving_after_a_service_is_still_charged() -> void:
	_kit.remake(PassengerTestWorld.reference_world(5))
	var world := _kit.world
	for i in 4:
		world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var m := world.staff.get_member(world.staff.hire(CHECKIN))
	for i in 1500:
		world.step()
		if m.state == StaffMember.State.ON_DUTY and _in_service(world, m.station):
			break
	assert_bool(_in_service(world, m.station)).is_true()
	assert_bool(world.staff.fire(CHECKIN)).is_true()
	assert_int(world.staff.leaving_count(CHECKIN)).is_equal(1)
	var before := world.sim.wallet.balance
	_kit.near_midnight(1, 1)
	world.step()
	print(
		(
			"leaving %d balance %d charges %s"
			% [world.staff.leaving_count(CHECKIN), world.sim.wallet.balance, _kit.charges]
		)
	)
	assert_int(world.staff.count(CHECKIN)).is_equal(1)
	assert_int(world.sim.wallet.balance).is_equal(before - 60)
	assert_array(_kit.charges).is_equal([[1, 60, 0]])


func _in_service(world: PassengerTestWorld, station: int) -> bool:
	for id in world.sim.passenger_ids():
		var p := world.passenger(id)
		if p.station == station and p.stage == Passenger.Stage.CHECKIN:
			return true
	return false


func test_a_midnight_with_nobody_hired_charges_nothing_and_announces_nothing() -> void:
	_kit.cross(1)
	assert_int(_kit.world.sim.wallet.balance).is_equal(1000)
	assert_array(_kit.charges).is_empty()
	assert_int(_kit.settlement.wages_paid_today()).is_equal(0)


func test_wages_paid_today_starts_over_at_each_midnight() -> void:
	_kit.hire(CHECKIN)
	_kit.cross(1)
	assert_int(_kit.settlement.wages_paid_today()).is_equal(60)
	assert_bool(_kit.world.staff.fire(CHECKIN)).is_true()
	_kit.cross(2)
	assert_int(_kit.settlement.wages_paid_today()).is_equal(0)


func test_what_the_wallet_cannot_pay_is_owed() -> void:
	_kit.hire(CHECKIN, 2)
	_kit.hire(SECURITY)
	assert_bool(_kit.world.sim.wallet.spend(900)).is_true()
	_kit.cross(1)
	print(
		(
			"balance %d owed %d charges %s"
			% [_kit.world.sim.wallet.balance, _kit.settlement.wages_owed(), _kit.charges]
		)
	)
	assert_int(_kit.world.sim.wallet.balance).is_equal(0)
	assert_int(_kit.settlement.wages_owed()).is_equal(110)
	assert_array(_kit.charges).is_equal([[1, 100, 110]])
	assert_int(_kit.settlement.wages_paid_today()).is_equal(100)


## Owed wages take each credit the moment it lands: nothing can spend it
## first, and no tick has to pass.
func test_money_that_comes_in_pays_owed_wages_first() -> void:
	var wallet := _kit.world.sim.wallet
	_kit.hire(CHECKIN, 2)
	_kit.hire(SECURITY)
	assert_bool(wallet.spend(1000)).is_true()
	_kit.cross(1)
	assert_int(_kit.settlement.wages_owed()).is_equal(210)
	assert_bool(wallet.credit(150)).is_true()
	assert_int(wallet.balance).is_equal(0)
	assert_bool(wallet.spend(1)).is_false()
	assert_int(_kit.settlement.wages_owed()).is_equal(60)
	assert_int(_kit.settlement.wages_paid_today()).is_equal(150)
	assert_bool(wallet.credit(100)).is_true()
	assert_int(wallet.balance).is_equal(40)
	assert_int(_kit.settlement.wages_owed()).is_equal(0)
	assert_int(_kit.settlement.wages_paid_today()).is_equal(210)


## A refund is a credit like any other: the build transaction's own signal
## handlers already see the debt paid from it.
func test_a_build_refund_goes_to_the_debt_before_anything_can_spend_it() -> void:
	_kit.hire(CHECKIN)
	var grid := BuildGrid.new(Vector2i(4, 4))
	var wallet := _kit.world.sim.wallet
	var laid := BuildEdit.paint_floor(Vector2i(0, 0), BuildGrid.FLOOR_TILE, 1)
	var plan: Array[BuildEdit] = [laid]
	assert_bool(BuildTransaction.commit_plan(grid, plan, wallet).ok).is_true()
	assert_bool(wallet.spend(wallet.balance)).is_true()
	_kit.cross(1)
	assert_int(_kit.settlement.wages_owed()).is_equal(60)
	var seen: Array[int] = []
	grid.edit_applied.connect(
		func(_edit: BuildEdit, _result: BuildResult) -> void: seen.append(wallet.balance)
	)
	var removal: Array[BuildEdit] = [BuildEdit.remove_floor(Vector2i(0, 0))]
	assert_bool(BuildTransaction.commit_plan(grid, removal, wallet).ok).is_true()
	var refund := PriceTable.refund_of(PriceTable.FLOOR_PRICE)
	print("refund %d balance %d owed %d" % [refund, wallet.balance, _kit.settlement.wages_owed()])
	assert_array(seen).is_equal([0])
	assert_int(wallet.balance).is_equal(0)
	assert_int(_kit.settlement.wages_owed()).is_equal(60 - refund)


func test_a_fee_arriving_while_wages_are_owed_goes_to_the_wages() -> void:
	_kit.hire(CHECKIN)
	assert_bool(_kit.world.sim.wallet.spend(1000)).is_true()
	_kit.cross(1)
	assert_int(_kit.settlement.wages_owed()).is_equal(60)
	var data := _kit.settlement.to_snapshot()
	data["owed"] = ["40"]
	assert_bool(_kit.settlement.from_snapshot(data)).is_true()
	_kit.world.step()
	assert_int(_kit.world.sim.wallet.balance).is_equal(0)
	assert_int(_kit.settlement.wages_owed()).is_equal(20)
	assert_array(_kit.settlement.owed()).is_empty()


## Wages go before fees so that paying them frees the room a fee waits for.
func test_owed_wages_are_paid_before_owed_fees_so_a_full_wallet_has_room() -> void:
	var wallet := _kit.world.sim.wallet
	assert_bool(wallet.credit(Wallet.MAX_BALANCE - wallet.balance)).is_true()
	var data := _kit.settlement.to_snapshot()
	data["owed"] = ["50"]
	data["wages_owed"] = "100"
	assert_bool(_kit.settlement.from_snapshot(data)).is_true()
	_kit.world.step()
	assert_int(wallet.balance).is_equal(Wallet.MAX_BALANCE - 100 + 50)
	assert_int(_kit.settlement.wages_owed()).is_equal(0)
	assert_array(_kit.settlement.owed()).is_empty()


## The debt is not a balance: it is kept whole past Wallet.MAX_BALANCE.
func test_owed_wages_are_kept_whole_beyond_the_wallet_limit() -> void:
	_kit.hire(CHECKIN)
	assert_bool(_kit.world.sim.wallet.spend(1000)).is_true()
	var data := _kit.settlement.to_snapshot()
	data["wages_owed"] = str(Wallet.MAX_BALANCE - 10)
	assert_bool(_kit.settlement.from_snapshot(data)).is_true()
	_kit.cross(1)
	assert_int(_kit.settlement.wages_owed()).is_equal(Wallet.MAX_BALANCE - 10 + 60)
	var wallet := _kit.world.sim.wallet
	assert_bool(wallet.credit(Wallet.MAX_BALANCE)).is_true()
	assert_int(wallet.balance).is_equal(0)
	assert_int(_kit.settlement.wages_owed()).is_equal(50)
	assert_bool(wallet.credit(100)).is_true()
	assert_int(wallet.balance).is_equal(50)
	assert_int(_kit.settlement.wages_owed()).is_equal(0)


func test_owed_wages_stop_at_the_overflow_guard() -> void:
	_kit.hire(CHECKIN)
	assert_bool(_kit.world.sim.wallet.spend(1000)).is_true()
	var data := _kit.settlement.to_snapshot()
	data["wages_owed"] = str(Settlement.MAX_WAGES - 10)
	assert_bool(_kit.settlement.from_snapshot(data)).is_true()
	_kit.cross(1)
	assert_int(_kit.settlement.wages_owed()).is_equal(Settlement.MAX_WAGES)


func test_without_a_staff_pool_no_wage_is_charged() -> void:
	_kit.settlement.staff = null
	_kit.hire(CHECKIN)
	_kit.cross(1)
	assert_int(_kit.world.sim.wallet.balance).is_equal(1000)
	assert_array(_kit.charges).is_empty()
