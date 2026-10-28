class_name TestDeskBeltRows
extends GdUnitTestSuite
## Desk belts behind a row of desks (decision
## desk-belts-run-one-row-back-desk-then-the-agent-row-then-the, v3, user-ruled
## "Gap between desks"): desks in a row keep a one-cell gap, the agent's spot
## sits behind each desk's left half, and each outlet cell (behind the right
## half) feeds a collector two rows behind the desks. A belt along the agent
## row is refused with the staff-spot reason. Tight desks with the collector
## two rows back, and a walkway row crossed by risers, are refused at the edit
## that would close an agent's pocket.

const SPOT := BuildResult.Reason.STAFF_SPOT
const CHECKIN := StaffMember.Role.CHECKIN
## Staff enter here, on the hall's south edge, clear of every desk's lane.
const ENTRANCE := Vector2i(14, 11)
const LIMIT_TICKS := 1500

var _world: BagTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


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


## Three desks side by side with no gap and the collector two rows behind
## them (row 6). The middle agent's spot (4, 7) would be boxed in by the two
## outlet belts beside it and the collector behind, so the collector is
## refused with the staff-spot reason.
func test_a_collector_behind_tight_desks_is_refused() -> void:
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


## The walkway-row layout the ruling dropped: tight desks on row 9, the agent
## row 8, a walkway row 7 and the collector on row 6, fed by two-cell risers.
## The second riser closes the walkway cell beside the middle agent's spot
## into a pocket with no way in from the entrance, so it is refused.
func test_a_walkway_row_crossed_by_risers_is_refused() -> void:
	var desks: Array[int] = []
	for x in [2, 4, 6]:
		desks.append(_world.desk(Vector2i(x, 9)))
	PassengerTestWorld.place(_world.grid, &"entrance_door", ENTRANCE, 2)
	_world.lay(Vector2i(3, 6), Vector2i(10, 6))
	_world.lay(Vector2i(3, 8), Vector2i(3, 7))
	var plan := BeltShaper.plan_line(_world.grid, Vector2i(5, 8), Vector2i(5, 7), 0)
	var result := plan.result
	print("second riser: %s, blocker %d" % [result.reason_text(), result.blocking_object_id])
	assert_bool(result.ok).is_false()
	assert_int(result.reason).is_equal(SPOT)
	assert_int(result.blocking_object_id).is_equal(desks[1])
	for cell in [Vector2i(5, 8), Vector2i(5, 7)]:
		assert_int(_world.grid.object_at(cell)).is_equal(0)
	for desk_id in desks:
		assert_bool(StaffSpots.unreachable(_world.grid, desk_id)).is_false()


## The ruled layout: three desks on row 9 with a one-cell gap between them
## (anchors x 2, 5 and 8), each outlet cell on row 8 laid as one belt into the
## collector on row 7. Hired agents walk in through the gaps and are on duty
## on their spots, and every bag reaches the bag room.
func test_the_ruled_layout_staffs_three_gapped_desks_and_feeds_one_collector() -> void:
	_world.room(BagTestWorld.ROOM)
	var desks: Array[int] = []
	for x in [2, 5, 8]:
		desks.append(_world.desk(Vector2i(x, 9)))
	PassengerTestWorld.place(_world.grid, &"entrance_door", ENTRANCE, 2)
	_world.lay(Vector2i(3, 7), Vector2i(10, 7))
	for x in [3, 6, 9]:
		_world.lay(Vector2i(x, 8), Vector2i(x, 8))
	for desk_id in desks:
		assert_bool(StaffSpots.blocked(_world.grid, desk_id)).is_false()
		assert_bool(StaffSpots.unreachable(_world.grid, desk_id)).is_false()
	var pieces := []
	for cell in [Vector2i(3, 8), Vector2i(3, 7), Vector2i(6, 7), Vector2i(9, 7), Vector2i(10, 7)]:
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
		assert_that(routes.entry_of(desks[i])["cell"]).is_equal(Vector2i(3 + 3 * i, 8))
	_expect_agents_on_duty(desks)
	var bags: Array = []
	for i in desks.size():
		bags.append(_world.sim.check_in(i + 1, BagTestWorld.FLIGHT, desks[i]))
	_world.run_to(400)
	for bag in bags:
		print("bag %d state %d at %s" % [bag.id, bag.state, bag.cell])
		assert_int(bag.state).is_equal(Bag.State.IN_ROOM)


## Hires one agent per desk on the same grid and steps until all are on duty.
func _expect_agents_on_duty(desks: Array[int]) -> void:
	var staffed := PassengerTestWorld.make(_world.grid, FlightSim.schedule_starts(0))
	staffed.auto_staff = false
	var members: Array[StaffMember] = []
	for i in desks.size():
		members.append(staffed.staff.get_member(staffed.staff.hire(CHECKIN)))
	var on_duty := func() -> bool:
		return members.all(
			func(m: StaffMember) -> bool: return m.state == StaffMember.State.ON_DUTY
		)
	while not on_duty.call() and staffed.clock.tick < LIMIT_TICKS:
		staffed.step()
	var stations: Array[int] = []
	for m in members:
		print(
			(
				"agent %d state %d at %s, station %d spot %s, tick %d"
				% [
					m.id,
					m.state,
					m.at,
					m.station,
					StaffSpots.spot_of(_world.grid, m.station),
					staffed.clock.tick
				]
			)
		)
		assert_int(m.state).is_equal(StaffMember.State.ON_DUTY)
		assert_that(m.at).is_equal(StaffSpots.spot_of(_world.grid, m.station))
		stations.append(m.station)
	stations.sort()
	assert_array(stations).is_equal(desks)
