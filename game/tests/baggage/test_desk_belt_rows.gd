class_name TestDeskBeltRows
extends GdUnitTestSuite
## Desk belts behind a row of desks (decision
## desk-belts-run-one-row-back-desk-then-the-agent-row-then-the, user-ruled
## "Walkway row"): desk, agent row, walkway row, then the collector three rows
## back, fed by a two-cell riser from each desk's outlet cell. A belt along
## the agent row is refused with the staff-spot reason, and so is a collector
## right behind the agent row, which would box in the middle agent.

const SPOT := BuildResult.Reason.STAFF_SPOT

var _world: BagTestWorld


func before_test() -> void:
	_world = BagTestWorld.make(self)


func test_a_belt_along_the_agent_row_is_refused() -> void:
	var desk_id := _world.desk(Vector2i(4, 8))
	var spot := StaffSpots.spot_of(_world.grid, desk_id)
	assert_that(spot).is_equal(Vector2i(4, 7))
	var plan := BeltShaper.plan_line(_world.grid, Vector2i(2, 7), Vector2i(8, 7), 0)
	print("agent-row belt: %s" % plan.result.reason_text())
	assert_bool(plan.result.ok).is_false()
	assert_int(plan.result.reason).is_equal(SPOT)
	assert_int(plan.result.blocking_object_id).is_equal(desk_id)
	assert_int(_world.grid.object_at(spot)).is_equal(0)
	# The outlet cell beside the spot takes a belt.
	_world.lay(Vector2i(5, 7), Vector2i(5, 7))
	(
		assert_bool(
			BuildCatalog.is_belt(
				_world.grid.get_object(_world.grid.object_at(Vector2i(5, 7)))["def"]
			)
		)
		. is_true()
	)


## The refusal the ruling expects: three desks side by side with the
## collector two rows behind them (row 6), no walkway row. The middle agent's
## spot (4, 7) would be boxed in by the two outlet belts beside it and the
## collector behind, so the collector is refused with the staff-spot reason.
func test_a_collector_without_a_walkway_row_is_refused() -> void:
	for x in [2, 4, 6]:
		_world.desk(Vector2i(x, 8))
	for x in [3, 5, 7]:
		_world.lay(Vector2i(x, 7), Vector2i(x, 7))
	var plan := BeltShaper.plan_line(_world.grid, Vector2i(3, 6), Vector2i(10, 6), 0)
	var result := plan.result
	print(
		(
			"collector two rows back: %s, blocker %d"
			% [result.reason_text(), result.blocking_object_id]
		)
	)
	assert_bool(result.ok).is_false()
	assert_int(result.reason).is_equal(SPOT)
	assert_int(result.blocking_object_id).is_equal(_world.grid.object_at(Vector2i(4, 8)))


## The ruled layout: three desks side by side on row 9, the agent row 8, the
## walkway row 7 and the collector on row 6, each outlet cell feeding a
## two-cell riser into it. Every agent keeps a way to its spot and every bag
## reaches the bag room.
func test_the_ruled_layout_feeds_three_side_by_side_desks_into_one_collector() -> void:
	_world.room(BagTestWorld.ROOM)
	var desks: Array[int] = []
	for x in [2, 4, 6]:
		desks.append(_world.desk(Vector2i(x, 9)))
	_world.lay(Vector2i(3, 6), Vector2i(10, 6))
	for x in [3, 5, 7]:
		_world.lay(Vector2i(x, 8), Vector2i(x, 7))
	for desk_id in desks:
		assert_bool(StaffSpots.blocked(_world.grid, desk_id)).is_false()
	var pieces := []
	for cell in [Vector2i(3, 8), Vector2i(3, 6), Vector2i(5, 6), Vector2i(7, 6), Vector2i(10, 6)]:
		pieces.append(str(_world.grid.get_object(_world.grid.object_at(cell))["def"]))
	print("pieces: %s" % [pieces])
	assert_array(pieces).is_equal(
		[
			"baggage_belt",
			"baggage_belt_corner",
			"baggage_belt_feed",
			"baggage_belt_feed",
			"baggage_belt_end"
		]
	)
	var routes := BagRoutes.build(_world.grid)
	for i in desks.size():
		assert_that(routes.entry_of(desks[i])["cell"]).is_equal(Vector2i(3 + 2 * i, 8))
	var bags: Array = []
	for i in desks.size():
		bags.append(_world.sim.check_in(i + 1, BagTestWorld.FLIGHT, desks[i]))
	_world.run_to(400)
	for bag in bags:
		print("bag %d state %d at %s" % [bag.id, bag.state, bag.cell])
		assert_int(bag.state).is_equal(Bag.State.IN_ROOM)
