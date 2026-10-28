class_name TestRescueGrantUpkeep
extends GdUnitTestSuite
## Owed upkeep and the rescue grant (decisions owed-wages-paid-synchronously-on-
## every-credit-rescue-grant-clears-wage-debt and toilet-design-queue-free-
## reservable-stalls-per-stall-daily-u): every credit pays owed wages and then
## owed upkeep before the balance sees it, so the grant adds both debts
## (Settlement.claimed_debt()) to the repair's shortfall. It clears both and
## still leaves the repair fully funded.

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
	_world.step()


func after_test() -> void:
	_granted.clear()
	_world.free_all()
	_world = null


## Sets the owed debts through a snapshot, as a load would; the wallet is empty.
func _owe(wages: int, upkeep: int) -> void:
	assert_int(_world.sim.wallet.balance).is_equal(0)
	var data := _settlement.to_snapshot()
	data["wages_owed"] = str(wages)
	data["upkeep_owed"] = str(upkeep)
	assert_bool(_settlement.from_snapshot(data)).is_true()
	assert_int(_settlement.claimed_debt()).is_equal(wages + upkeep)


func _remove_scanners() -> void:
	var ids := ReferenceTerminal.object_ids(_world.grid)
	for id in ids["scanners"]:
		assert_bool(_world.grid.apply(BuildEdit.remove_object(id)).ok).is_true()


## Grants once and returns [repair, granted amount, message].
func _rescue() -> Array:
	_remove_scanners()
	assert_bool(_grant.has_working_path()).is_false()
	var repair := BuildTransaction.needed(_world.grid, _grant.repair_plan().edits)
	_world.step()
	assert_array(_granted).override_failure_message(str(_granted)).has_size(1)
	return [repair, _granted[0][0], _granted[0][1]]


func test_a_stuck_airport_owing_wages_and_upkeep_gets_both_and_the_repair() -> void:
	_owe(120, 40)
	var got := _rescue()
	var repair: int = got[0]
	var state := (
		"repair %d granted %d balance %d wages %d upkeep %d"
		% [
			repair,
			got[1],
			_world.sim.wallet.balance,
			_settlement.wages_owed(),
			_settlement.upkeep_owed()
		]
	)
	assert_int(got[1]).override_failure_message(state).is_equal(repair + 160)
	assert_int(_settlement.wages_owed()).override_failure_message(state).is_equal(0)
	assert_int(_settlement.upkeep_owed()).override_failure_message(state).is_equal(0)
	assert_int(_world.sim.wallet.balance).override_failure_message(state).is_equal(repair)
	var edits := _grant.repair_plan().edits
	assert_bool(BuildTransaction.check(_world.grid, edits, _world.sim.wallet).ok).is_true()
	assert_str(got[2]).contains("A further 160 clears the owed wages (120) and upkeep (40).")


func test_owed_upkeep_alone_is_added_and_named() -> void:
	_owe(0, 25)
	var got := _rescue()
	assert_int(got[1]).is_equal(got[0] + 25)
	assert_int(_settlement.upkeep_owed()).is_equal(0)
	assert_int(_world.sim.wallet.balance).is_equal(got[0])
	assert_str(got[2]).contains("A further 25 clears the owed upkeep.")
	assert_str(got[2]).not_contains("wages")


func test_owed_wages_alone_keep_their_message() -> void:
	_owe(60, 0)
	var got := _rescue()
	assert_int(got[1]).is_equal(got[0] + 60)
	assert_int(_world.sim.wallet.balance).is_equal(got[0])
	assert_str(got[2]).contains("A further 60 clears the owed wages.")
	assert_str(got[2]).not_contains("upkeep")
