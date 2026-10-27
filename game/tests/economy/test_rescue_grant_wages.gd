class_name TestRescueGrantWages
extends GdUnitTestSuite
## Owed wages and the rescue grant (rulings staff-wages-charged-daily-at-
## midnight-unpaid-wages-carried-as-owed and going-broke-a-one-off-rescue-
## grant-when-the-airport-is-stuck): wages are paid out of every credit the
## moment it lands, so the grant adds the wage debt on top of the repair's
## shortfall. It clears the debt and still leaves the repair funded.

var _world: PassengerTestWorld
var _grant: RescueGrant
var _settlement: Settlement
var _granted: Array = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(100000))
	_world.auto_staff = false
	_settlement = auto_free(Settlement.new())
	_settlement.staff = _world.staff
	_settlement.bind(_world.sim, _world.sim.wallet)
	_grant = auto_free(RescueGrant.new())
	_grant.bind(_world.clock, _world.sim, _world.sim.wallet)
	_grant.settlement = _settlement
	_grant.granted.connect(func(amount: int, text: String) -> void: _granted.append([amount, text]))


func after_test() -> void:
	_granted.clear()
	_world.free_all()
	_world = null


## Hires `count` agents, empties the wallet and lets a midnight charge them, so
## their wages are all owed.
func _owe_wages(count: int) -> void:
	for i in count:
		_world.staff.hire(StaffMember.Role.CHECKIN)
	_world.step()
	var data := _world.clock.to_snapshot()
	data["tick"] = str(GameCalendar.day_start(1) - 2)
	assert_bool(_world.clock.from_snapshot(data)).is_true()
	_world.step()
	_world.step()


func _remove_scanners() -> void:
	var ids := ReferenceTerminal.object_ids(_world.grid)
	for id in ids["scanners"]:
		assert_bool(_world.grid.apply(BuildEdit.remove_object(id)).ok).is_true()


func test_a_stuck_airport_in_debt_gets_the_repair_and_the_debt() -> void:
	_owe_wages(2)
	_remove_scanners()
	assert_int(_settlement.wages_owed()).is_equal(120)
	assert_int(_world.sim.wallet.balance).is_equal(0)
	assert_bool(_grant.has_working_path()).is_false()
	var repair := BuildTransaction.needed(_world.grid, _grant.repair_plan().edits)
	_world.step()
	print(
		(
			"repair %d balance %d owed %d grants %s"
			% [repair, _world.sim.wallet.balance, _settlement.wages_owed(), _granted]
		)
	)
	assert_int(_granted.size()).is_equal(1)
	assert_int(_granted[0][0]).is_equal(repair + 120)
	assert_str(_granted[0][1]).contains("120")
	assert_int(_settlement.wages_owed()).is_equal(0)
	assert_int(_world.sim.wallet.balance).is_equal(repair)
	(
		assert_bool(
			BuildTransaction.check(_world.grid, _grant.repair_plan().edits, _world.sim.wallet).ok
		)
		. is_true()
	)


func test_without_debt_the_grant_is_the_shortfall_alone() -> void:
	_remove_scanners()
	var repair := BuildTransaction.needed(_world.grid, _grant.repair_plan().edits)
	_world.step()
	assert_array(_granted).has_size(1)
	assert_int(_granted[0][0]).is_equal(repair)
	assert_str(_granted[0][1]).not_contains("owed wages")
	assert_int(_world.sim.wallet.balance).is_equal(repair)


## The grant is more than the wallet can hold when the debt is near the limit;
## only what is left after the debt has to fit.
func test_a_debt_near_the_wallet_limit_does_not_stop_the_rescue() -> void:
	_world.step()
	var debt := Wallet.MAX_BALANCE - 100
	var data := _settlement.to_snapshot()
	data["wages_owed"] = str(debt)
	assert_bool(_settlement.from_snapshot(data)).is_true()
	_remove_scanners()
	var repair := BuildTransaction.needed(_world.grid, _grant.repair_plan().edits)
	assert_int(repair + debt).is_greater(Wallet.MAX_BALANCE)
	_world.step()
	assert_array(_granted).has_size(1)
	assert_int(_granted[0][0]).is_equal(repair + debt)
	assert_int(_settlement.wages_owed()).is_equal(0)
	assert_int(_world.sim.wallet.balance).is_equal(repair)
