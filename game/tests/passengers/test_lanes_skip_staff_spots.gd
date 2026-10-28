class_name TestLanesSkipStaffSpots
extends GdUnitTestSuite
## Queue lanes never use a staff spot as a waiting slot (passengers may still
## walk across one), and a station closed because an old save blocked its
## staff spot says so (decision
## staff-spot-design-a-derived-staff-spot-behind-each-desk-and, points 3-4).

const DESK := &"checkin_desk"

var _w: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _w != null:
		_w.free_all()
	_w = null


func _spots(grid: BuildGrid) -> Dictionary:
	var out := {}
	for id in grid.object_ids():
		var spot := StaffSpots.spot_of(grid, id)
		if spot != BuildObjectDef.NO_CELL:
			out[spot] = id
	return out


func _lanes_on_spots(world: PassengerTestWorld) -> int:
	var spots := _spots(world.grid)
	var hits := 0
	for station: int in world.sim.layout.lanes:
		for cell: Vector2i in world.sim.layout.lanes[station]:
			hits += int(spots.has(cell))
	return hits


func test_a_lane_stops_before_another_desk_spot() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(12, 10))
	var front := PassengerTestWorld.place(grid, DESK, Vector2i(3, 1), 0)
	var behind := PassengerTestWorld.place(grid, DESK, Vector2i(3, 5), 0)
	assert_that(StaffSpots.spot_of(grid, behind)).is_equal(Vector2i(3, 4))
	_w = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	var lane: Array = _w.sim.layout.lanes[front]
	print("front desk lane %s" % [lane])
	assert_array(lane).is_equal([Vector2i(3, 2), Vector2i(3, 3)])
	assert_bool(_w.sim.layout.is_usable(front)).is_true()
	# Passengers still route across the spot.
	assert_bool(grid.can_route(Vector2i(2, 4), Vector2i(3, 4))).is_true()
	assert_int(_lanes_on_spots(_w)).is_equal(0)


func test_no_reference_terminal_lane_holds_a_spot() -> void:
	_w = PassengerTestWorld.reference_world()
	var slots := 0
	for station: int in _w.sim.layout.lanes:
		slots += (_w.sim.layout.lanes[station] as Array).size()
	print("reference lanes: %d slots" % slots)
	assert_int(slots).is_greater(8)
	assert_int(_lanes_on_spots(_w)).is_equal(0)


func test_a_station_closed_by_a_blocked_spot_says_why() -> void:
	var source := BuildGrid.new()
	ReferenceTerminal.build(source)
	var data := source.to_snapshot()
	var next: int = data["next_object_id"]
	(data["objects"] as Array).append(
		{"id": next, "def": "seat_row", "anchor": [11, 10], "facing": 0}
	)
	data["next_object_id"] = next + 1
	var grid := BuildGrid.new()
	assert_bool(grid.from_snapshot(JSON.parse_string(JSON.stringify(data)))).is_true()
	_w = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_w.step()
	var desks: Array = ReferenceTerminal.object_ids(grid)["desks"]
	var blocked: int = desks[0]
	var closed := MissSignals.closed_stations(_w.sim)
	var reason := MissSignals.closed_reason(_w.sim, blocked)
	print("closed %s, reason '%s'" % [closed, reason])
	assert_array(closed).contains([blocked])
	assert_str(reason).is_equal(MissSignals.SPOT_BLOCKED_REASON)
	assert_str(MissSignals.closed_reason(_w.sim, desks[1])).is_empty()
	_w.staff.fire(StaffMember.Role.CHECKIN)
	assert_str(MissSignals.closed_reason(_w.sim, desks[1])).is_equal(MissSignals.NO_STAFF_REASON)
