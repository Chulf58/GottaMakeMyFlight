class_name TestRescueGrantStaffing
extends GdUnitTestSuite
## Staff are not money: an airport whose stations stand on a working path but
## have nobody on duty is not stuck in the rescue grant's sense, so hiring is
## the way out and no grant is paid, even with an empty wallet and passengers
## waiting at closed desks (rulings going-broke-a-one-off-rescue-grant-when-
## the-airport-is-stuck and staff-a-new-game-starts-with-an-empty-staff-pool-
## and-a-hint).

var _world: PassengerTestWorld
var _grant: RescueGrant


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
		_world = null


func test_closed_stations_on_a_working_path_get_no_grant() -> void:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_world.auto_staff = false
	_grant = auto_free(RescueGrant.new())
	_grant.bind(_world.clock, _world.sim, _world.sim.wallet)
	var paid := [0]
	_grant.granted.connect(func(amount: int, _message: String) -> void: paid[0] += amount)
	var ids: Array[int] = []
	for i in 3:
		ids.append(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	_world.run_to(_world.clock.tick + 300)
	var stuck := 0
	for id in ids:
		stuck += int(_world.passenger(id).stuck == Passenger.Stuck.NO_CHECKIN)
	print(
		(
			"balance %d, stuck at closed desks %d, working path %s, paid %d"
			% [_world.sim.wallet.balance, stuck, _grant.has_working_path(), paid[0]]
		)
	)
	assert_int(_world.sim.wallet.balance).is_equal(0)
	assert_int(stuck).is_equal(3)
	assert_bool(_grant.has_working_path()).is_true()
	assert_bool(_grant.evaluate()).is_false()
	assert_int(paid[0]).is_equal(0)
	assert_int(_world.sim.wallet.balance).is_equal(0)
