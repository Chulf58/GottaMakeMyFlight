class_name TestBaggageBonus
extends GdUnitTestSuite
## Per-bag handling bonus (ruling 1b70fa33): PriceTable.CHECKED_BAG_BONUS is
## credited under Wallet.Category.FEES when a checked bag settles LOADED, 0 when
## MISSED or unconnected (preserving 17e414be connect-gating).

var _world: BagTestWorld
var _wallet: Wallet
var _txs: Array[Array] = []


func before_test() -> void:
	_world = BagTestWorld.make(self)
	_wallet = Wallet.new()
	_wallet.clock = _world.clock
	_txs.clear()
	_wallet.transaction.connect(
		func(amount: int, category: int, _claimed: Dictionary, _tick: int) -> void:
			_txs.append([amount, category])
	)
	_world.sim._wallet = _wallet


func test_loaded_bag_credits_handling_bonus_under_fees() -> void:
	var desk_id := _world.line()
	_world.cart()
	var bag := _world.sim.check_in(1, BagTestWorld.FLIGHT, desk_id)
	assert_object(bag).is_not_null()
	_world.run_to(BagTestWorld.ARRIVAL)
	assert_int(bag.state).is_equal(Bag.State.IN_ROOM)
	assert_int(_wallet.balance).is_equal(0)
	_world.run_to(bag.cutoff_tick)
	assert_int(_world.sim.shuttles().size()).is_equal(1)
	_world.run_to(_world.sim.shuttles()[0].unload_tick)
	assert_int(bag.state).is_equal(Bag.State.LOADED)
	assert_int(_wallet.balance).is_equal(PriceTable.CHECKED_BAG_BONUS)
	assert_array(_txs).is_equal([[PriceTable.CHECKED_BAG_BONUS, Wallet.Category.FEES]])


func test_missed_bag_credits_no_handling_bonus() -> void:
	var desk_id := _world.line()
	var bag := _world.sim.check_in(1, BagTestWorld.FLIGHT, desk_id)
	assert_object(bag).is_not_null()
	# Cut the route mid-way after check-in so the bag is blocked and misses at cutoff.
	_world.unlay(Vector2i(6, 7))
	_world.run_to(bag.cutoff_tick)
	assert_int(bag.state).is_equal(Bag.State.MISSED)
	assert_int(_wallet.balance).is_equal(0)
	assert_array(_txs).is_empty()


func test_unconnected_bag_room_spawns_no_bags_and_credits_no_bonus() -> void:
	_world.room(BagTestWorld.ROOM)
	PassengerTestWorld.place(_world.grid, &"baggage_belt_end", BagTestWorld.END, 0)
	var desk_id := _world.desk(BagTestWorld.DESK)
	assert_bool(_world.sim.has_ready_bag_room()).is_true()
	assert_bool(_world.sim.has_connected_bag_room()).is_false()
	assert_object(_world.sim.check_in(1, BagTestWorld.FLIGHT, desk_id)).is_null()
	_world.run_to(3900)
	assert_int(_wallet.balance).is_equal(0)
	assert_array(_txs).is_empty()
