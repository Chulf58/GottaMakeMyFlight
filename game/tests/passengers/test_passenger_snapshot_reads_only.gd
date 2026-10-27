class_name TestPassengerSnapshotReadsOnly
extends GdUnitTestSuite
## PassengerSim.to_snapshot() only reads (board item economy-8-8-whole-world-
## save-and-save-files-design-decision, the carried cafe residual). Between a
## grid edit and the next tick it refuses, leaving the cafe, the guest and the
## wallet as they were, so a saved game never settles the cafe a tick earlier
## than a game that was never saved. The next tick settles it, and the save
## is taken then.

const HUNGRY := 59

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
	_world = null


func test_a_save_between_an_edit_and_the_next_tick_changes_nothing() -> void:
	var grid := BuildGrid.new()
	CafeTestLayout.build(grid, true)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), 4242)
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.hunger = HUNGRY
	while p.stage != Passenger.Stage.CAFE_SEATED and _world.clock.tick < 1400:
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.CAFE_SEATED)
	var visit := _world.sim.cafes.visit_of(p.id)
	var table := int(visit.seat_key.split(":")[0])
	assert_bool(_world.grid.apply(BuildEdit.remove_object(table)).ok).is_true()
	assert_bool(_world.sim.cafes.deadlines_stale).is_true()
	var balance := _world.sim.wallet.balance
	assert_bool(_world.sim.to_snapshot().is_empty()).is_true()
	# Nothing was settled: the guest still sits at the cafe, unpaid.
	assert_bool(_world.sim.cafes.deadlines_stale).is_true()
	assert_int(p.stage).is_equal(Passenger.Stage.CAFE_SEATED)
	assert_object(_world.sim.cafes.visit_of(p.id)).is_same(visit)
	assert_int(_world.sim.wallet.balance).is_equal(balance)
	# The next tick settles the cafe: the guest pays the short share.
	_world.step()
	assert_bool(_world.sim.cafes.deadlines_stale).is_false()
	assert_object(_world.sim.cafes.visit_of(p.id)).is_null()
	assert_int(_world.sim.wallet.balance).is_greater(balance)
	assert_bool(_world.sim.to_snapshot().is_empty()).is_false()
