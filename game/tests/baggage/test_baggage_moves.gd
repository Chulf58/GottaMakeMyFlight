class_name TestBaggageMoves
extends GdUnitTestSuite
## Bags ride the belt (BaggageSim; decision baggage-bag-sim-design-route-
## field-belt-capacity-cutoff): exact timing, one bag per belt cell, desk
## queues, and merges going to the longest wait, then the lower id.

var _world: BagTestWorld


func before_test() -> void:
	_world = BagTestWorld.make(self)


## Runs to `target`, failing on the first tick two bags share a cell.
func _run_checked(target: int) -> void:
	while _world.clock.tick < target:
		_world.step()
		var found := _world.overlap()
		if found != "":
			fail(found)
			return


## Steps until bag `id` is in the room, at most `limit` ticks; its rest tick.
func _rest_tick(id: int, limit := 1000) -> int:
	var stop := _world.clock.tick + limit
	while _world.bag(id).state != Bag.State.IN_ROOM and _world.clock.tick < stop:
		_world.step()
		var found := _world.overlap()
		if found != "":
			fail(found)
			return -1
	return _world.bag(id).rest_tick


func test_a_bag_enters_half_a_cell_out_and_rests_on_the_exact_tick() -> void:
	var desk_id := _world.line()
	var bag := _world.sim.check_in(7, BagTestWorld.FLIGHT, desk_id)
	assert_int(bag.state).is_equal(Bag.State.AT_DESK)
	assert_int(bag.passenger).is_equal(7)
	assert_int(bag.cutoff_tick).is_equal(3800)
	_world.step()
	assert_int(bag.state).is_equal(Bag.State.RIDING)
	assert_that(bag.cell).is_equal(BagTestWorld.ENTRY)
	assert_that(bag.from_step).is_equal(Vector2i(0, -1))
	assert_int(bag.remain_mm).is_equal(450)
	_world.run_to(10)
	assert_int(bag.remain_mm).is_equal(0)
	_world.step()
	assert_that(bag.cell).is_equal(Vector2i(4, 7))
	assert_int(bag.remain_mm).is_equal(950)
	assert_int(_rest_tick(bag.id)).is_equal(BagTestWorld.ARRIVAL)
	assert_that(bag.cell).is_equal(BagTestWorld.END)


func test_a_bag_checked_in_mid_tick_first_moves_on_the_next_tick() -> void:
	var desk_id := _world.line()
	_world.run_to(5)
	var bag := _world.sim.check_in(1, BagTestWorld.FLIGHT, desk_id)
	assert_int(bag.created_tick).is_equal(5)
	_world.step()
	assert_int(bag.remain_mm).is_equal(450)
	assert_int(_rest_tick(bag.id)).is_equal(5 + BagTestWorld.ARRIVAL)


func test_a_desk_queues_its_bags_and_a_belt_cell_holds_one() -> void:
	var desk_id := _world.line()
	var first := _world.sim.check_in(1, BagTestWorld.FLIGHT, desk_id)
	var second := _world.sim.check_in(2, BagTestWorld.FLIGHT, desk_id)
	_run_checked(20)
	# The first bag's body leaves the entry cell after tick 20.
	assert_int(second.state).is_equal(Bag.State.AT_DESK)
	_world.step()
	assert_int(second.state).is_equal(Bag.State.RIDING)
	assert_that(second.cell).is_equal(BagTestWorld.ENTRY)
	assert_int(_rest_tick(first.id)).is_equal(BagTestWorld.ARRIVAL)
	# Behind a moving bag, a bag waits half a cell each cell: 30 ticks a cell.
	assert_int(_rest_tick(second.id)).is_equal(BagTestWorld.ARRIVAL + 30)


func test_a_bag_waiting_for_space_is_riding_not_blocked() -> void:
	var desk_id := _world.line()
	var first := _world.sim.check_in(1, BagTestWorld.FLIGHT, desk_id)
	var second := _world.sim.check_in(2, BagTestWorld.FLIGHT, desk_id)
	_run_checked(35)
	assert_int(second.remain_mm).is_equal(0)
	assert_that(second.cell).is_equal(BagTestWorld.ENTRY)
	assert_that(first.physical_cell()).is_equal(Vector2i(4, 7))
	assert_int(second.state).is_equal(Bag.State.RIDING)


func test_equal_waits_at_a_merge_go_to_the_lower_id() -> void:
	# Two desks feed (6, 3) from the left and right branches of a T whose
	# stem runs down to a bag room; both bags reach their branch centres on
	# the same tick.
	_world.room(Rect2i(5, 8, 3, 3))
	var left := _world.desk(Vector2i(2, 4))
	var right := _world.desk(Vector2i(9, 4), 0)
	_world.lay(Vector2i(3, 3), Vector2i(10, 3))
	_world.lay(Vector2i(6, 3), Vector2i(6, 9))
	var routes := BagRoutes.build(_world.grid)
	assert_that(routes.entry_of(left)["cell"]).is_equal(Vector2i(3, 3))
	assert_that(routes.entry_of(right)["cell"]).is_equal(Vector2i(10, 3))
	assert_int(routes.dist[Vector2i(3, 3)]).is_equal(routes.dist[Vector2i(10, 3)] - 1)
	# The right bag starts one cell further out, so checked in 20 ticks
	# earlier it reaches its side of the merge on the same tick.
	var b1 := _world.sim.check_in(1, BagTestWorld.FLIGHT, right)
	_world.run_to(20)
	var b2 := _world.sim.check_in(2, BagTestWorld.FLIGHT, left)
	_run_checked(70)
	assert_that(b1.cell).is_equal(Vector2i(7, 3))
	assert_that(b2.cell).is_equal(Vector2i(5, 3))
	assert_int(b1.remain_mm).is_equal(0)
	assert_int(b2.remain_mm).is_equal(0)
	assert_int(b1.wait_tick).is_equal(b2.wait_tick)
	_world.step()
	assert_that(b1.cell).is_equal(Vector2i(6, 3))
	assert_that(b2.cell).is_equal(Vector2i(5, 3))
	assert_int(_rest_tick(b2.id)).is_greater(_rest_tick(b1.id))


func test_the_longer_wait_wins_a_merge_over_the_lower_id() -> void:
	var desk_id := _world.line()
	# A desk feeding (6, 7) from below makes it a merge.
	var side := _world.desk(Vector2i(5, 8))
	assert_that(BagRoutes.build(_world.grid).entry_of(side)["cell"]).is_equal(Vector2i(6, 7))
	var first := _world.sim.check_in(1, BagTestWorld.FLIGHT, desk_id)
	var second := _world.sim.check_in(2, BagTestWorld.FLIGHT, desk_id)
	_run_checked(52)
	# The first bag holds (6, 7) until its body leaves it after tick 80; the
	# side bag waits for it from its check-in on tick 52.
	var waiting := _world.sim.check_in(3, BagTestWorld.FLIGHT, side)
	_run_checked(80)
	assert_int(waiting.state).is_equal(Bag.State.AT_DESK)
	assert_that(second.cell).is_equal(Vector2i(5, 7))
	assert_int(second.remain_mm).is_equal(0)
	assert_int(second.wait_tick).is_equal(80)
	assert_int(waiting.wait_tick).is_equal(52)
	assert_that(first.physical_cell()).is_equal(Vector2i(7, 7))
	_world.step()
	assert_int(waiting.state).is_equal(Bag.State.RIDING)
	assert_that(waiting.cell).is_equal(Vector2i(6, 7))
	assert_that(second.cell).is_equal(Vector2i(5, 7))
	assert_int(_rest_tick(second.id)).is_greater(_rest_tick(waiting.id))
