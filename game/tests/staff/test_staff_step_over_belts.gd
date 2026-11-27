class_name TestStaffStepOverBelts
extends GdUnitTestSuite
## Staff step over baggage belts as a high-cost pathing fallback with smooth
## 0.355 m vertical step-up lift (decision
## staff-step-over-belts-high-cost-fallback-with-step-up-lift, 76c5cc1a).

const CHECKIN := StaffMember.Role.CHECKIN
const CLEANER := StaffMember.Role.CLEANER
const LIMIT_TICKS := 800

var _w: PassengerTestWorld
var _views: StaffCharacters


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _views != null:
		_views.free()
		_views = null
	if _w != null:
		_w.free_all()
		_w = null


func _closed_grid(size: Vector2i) -> BuildGrid:
	var grid := PassengerTestWorld.floored(size)
	EnclosureKit.close_floor(grid)
	return grid


func _lay_belt(grid: BuildGrid, from: Vector2i, to: Vector2i) -> BuildResult:
	var plan := BeltShaper.plan_line(grid, from, to, 0)
	if not plan.result.ok:
		return plan.result
	for res in grid.apply_batch(plan.edits):
		if not res.ok:
			return res
	return plan.result


func test_staff_prefer_open_aisle_over_stepping_across_belt() -> void:
	var grid := _closed_grid(Vector2i(12, 10))
	assert_bool(_lay_belt(grid, Vector2i(4, 4), Vector2i(6, 4)).ok).is_true()
	var detour := grid.find_staff_path(Vector2i(5, 2), Vector2i(5, 6))
	assert_array(detour).is_not_empty()
	for cell in detour:
		assert_bool(grid.is_belt_cell(cell)).is_false()
	assert_bool(_lay_belt(grid, Vector2i(0, 4), Vector2i(11, 4)).ok).is_true()
	var across := grid.find_staff_path(Vector2i(5, 2), Vector2i(5, 6))
	assert_array(across).is_not_empty()
	var stepped_belt := false
	for cell in across:
		if grid.is_belt_cell(cell):
			stepped_belt = true
			break
	assert_bool(stepped_belt).is_true()


func test_belt_removal_resets_staff_graph_weight() -> void:
	var grid := _closed_grid(Vector2i(12, 10))
	assert_bool(_lay_belt(grid, Vector2i(4, 4), Vector2i(6, 4)).ok).is_true()
	var detour := grid.find_staff_path(Vector2i(5, 2), Vector2i(5, 6))
	assert_array(detour).is_not_empty()
	assert_bool(detour.has(Vector2i(5, 4))).is_false()
	assert_bool(grid.apply(BuildEdit.remove_object(grid.object_at(Vector2i(5, 4)))).ok).is_true()
	var opened := grid.find_staff_path(Vector2i(5, 2), Vector2i(5, 6))
	assert_array(opened).is_equal(
		[Vector2i(5, 2), Vector2i(5, 3), Vector2i(5, 4), Vector2i(5, 5), Vector2i(5, 6)]
	)


func test_enclosed_checkin_desk_spot_is_reachable_and_staffed_over_belt() -> void:
	var grid := _closed_grid(Vector2i(12, 12))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(5, 11), 2)
	var desks: Array[int] = []
	for x in [3, 5, 7]:
		desks.append(PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(x, 6), 0))
	var middle_desk := desks[1]
	var middle_spot := StaffSpots.spot_of(grid, middle_desk)
	assert_that(middle_spot).is_equal(Vector2i(5, 5))
	for x in [4, 6, 8]:
		assert_bool(_lay_belt(grid, Vector2i(x, 5), Vector2i(x, 5)).ok).is_true()
	assert_bool(_lay_belt(grid, Vector2i(4, 4), Vector2i(9, 4)).ok).is_true()
	assert_bool(StaffSpots.blocked(grid, middle_desk)).is_false()
	assert_bool(StaffSpots.unreachable(grid, middle_desk)).is_false()
	assert_bool(grid.staff_reach().has(middle_spot)).is_true()
	_w = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_w.auto_staff = false
	for _i in 3:
		_w.staff.hire(CHECKIN)
	var ticks := 0
	while ticks < LIMIT_TICKS and not _w.staff.is_staffed(middle_desk):
		_w.step()
		ticks += 1
	assert_bool(_w.staff.is_staffed(middle_desk)).is_true()
	var worker := _w.staff.get_member(_w.staff.staff_at(middle_desk))
	assert_int(worker.state).is_equal(StaffMember.State.ON_DUTY)
	assert_that(worker.at).is_equal(middle_spot)


func test_passengers_remain_strictly_blocked_by_belts() -> void:
	var grid := _closed_grid(Vector2i(12, 10))
	assert_bool(_lay_belt(grid, Vector2i(4, 4), Vector2i(6, 4)).ok).is_true()
	var detour := grid.find_path(Vector2i(5, 2), Vector2i(5, 6))
	assert_array(detour).is_not_empty()
	for cell in detour:
		assert_bool(grid.is_belt_cell(cell)).is_false()
	assert_bool(_lay_belt(grid, Vector2i(0, 4), Vector2i(11, 4)).ok).is_true()
	assert_bool(grid.is_passenger_cell(Vector2i(5, 4))).is_false()
	assert_bool(grid.can_route(Vector2i(5, 3), Vector2i(5, 4))).is_false()
	assert_array(grid.find_path(Vector2i(5, 2), Vector2i(5, 6))).is_empty()


func test_staff_never_idle_break_or_place_belt_on_desk_spot() -> void:
	var grid := _closed_grid(Vector2i(14, 12))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(1, 11), 2)
	var desk := PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(5, 6), 0)
	var spot := StaffSpots.spot_of(grid, desk)
	var on_spot := _lay_belt(grid, spot, spot)
	assert_bool(on_spot.ok).is_false()
	assert_int(on_spot.reason).is_equal(BuildResult.Reason.STAFF_SPOT)
	assert_bool(grid.apply(BuildEdit.place_room(Rect2i(2, 2, 5, 3), &"break_room")).ok).is_true()
	var break_id := grid.room_at(Vector2i(2, 2))
	assert_bool(_lay_belt(grid, Vector2i(3, 3), Vector2i(5, 3)).ok).is_true()
	for rest_cell in StaffBreakRooms.spots_in(grid, break_id):
		assert_bool(grid.is_belt_cell(rest_cell)).is_false()
	_w = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_w.auto_staff = false
	var cleaner := _w.staff.get_member(_w.staff.hire(CLEANER))
	for _i in 200:
		_w.step()
		if cleaner.state == StaffMember.State.IDLE and not cleaner.in_pool():
			if cleaner.is_moving():
				assert_bool(grid.is_belt_cell(cleaner.path_end())).is_false()
			else:
				assert_bool(grid.is_belt_cell(cleaner.at)).is_false()
	var agent := _w.staff.get_member(_w.staff.hire(CHECKIN))
	assert_bool(_lay_belt(grid, Vector2i(0, 8), Vector2i(13, 8)).ok).is_true()
	for _i in 60:
		_w.step()
		if not agent.in_pool() and grid.is_belt_cell(agent.at):
			break
	assert_bool(not agent.in_pool() and grid.is_belt_cell(agent.at)).is_true()
	# Remove the desk while the agent is mid-belt: evacuated immediately, before step().
	var agent_id := agent.id
	assert_bool(grid.apply(BuildEdit.remove_object(desk)).ok).is_true()
	assert_bool(agent.in_pool()).is_true()
	var staff_snap := _w.staff.to_snapshot()
	assert_bool(_w.staff.from_snapshot(staff_snap)).is_true()
	agent = _w.staff.get_member(agent_id)
	assert_bool(agent.in_pool()).is_true()
	var forged: Dictionary = JSON.parse_string(JSON.stringify(staff_snap))
	for entry: Dictionary in forged["members"]:
		if int(entry["id"]) == agent_id:
			entry["at"] = [5, 8]
			entry["path"] = [[5, 8]]
	assert_bool(_w.staff.from_snapshot(forged)).is_false()
	_w.step()
	var loaded := StaffTestKit.load_world(StaffTestKit.save_text(_w))
	assert_object(loaded).is_not_null()
	if loaded != null:
		assert_bool(loaded.staff.get_member(agent_id).in_pool()).is_true()
		loaded.free_all()
	(
		assert_bool(
			(
				agent.state == StaffMember.State.IDLE
				and not agent.is_moving()
				and not agent.in_pool()
				and grid.is_belt_cell(agent.at)
			)
		)
		. is_false()
	)


func test_staff_characters_lifts_smoothly_over_belt_and_returns_to_floor() -> void:
	var grid := _closed_grid(Vector2i(14, 10))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(1, 5), 2)
	var desk := PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(6, 5), 0)
	assert_bool(_lay_belt(grid, Vector2i(3, 0), Vector2i(3, 9)).ok).is_true()
	assert_bool(_lay_belt(grid, Vector2i(4, 0), Vector2i(4, 9)).ok).is_true()
	_w = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_w.auto_staff = false
	_views = StaffCharacters.new()
	_views.clock = _w.clock
	_views.staff = _w.staff
	add_child(_views)
	var id := _w.staff.hire(CHECKIN)
	var m := _w.staff.get_member(id)
	var max_y := 0.0
	var saw_step_up := false
	var saw_step_down := false
	var saw_belt_to_belt := false
	var saw_floor_before := false
	var step_count := 0
	while step_count < LIMIT_TICKS and m.state != StaffMember.State.ON_DUTY:
		_w.clock.advance(SimClock.STEP * 0.5)
		_views.draw()
		var node := _views.node_for(id)
		if node != null:
			var y := node.position.y
			max_y = maxf(max_y, y)
			if not m.in_pool() and m.at.x <= 1:
				saw_floor_before = true
				assert_float(y).is_equal_approx(0.0, 0.001)
			if not m.in_pool() and m.at.x == 2 and y > 0.02 and y < BaggageViews.BELT_TOP - 0.02:
				saw_step_up = true
			if (
				not m.in_pool()
				and m.at.x == 3
				and m.is_moving()
				and m.path[m.path_index + 1].x == 4
				and m.seg_mm > 0
			):
				saw_belt_to_belt = true
				assert_float(y).is_equal_approx(BaggageViews.BELT_TOP, 0.002)
			if not m.in_pool() and m.at.x == 4 and y > 0.02 and y < BaggageViews.BELT_TOP - 0.02:
				saw_step_down = true
		_w.clock.advance(SimClock.STEP * 0.5)
		_views.draw()
		if _views.node_for(id) != null:
			max_y = maxf(max_y, _views.node_for(id).position.y)
		step_count += 1
	assert_int(m.state).is_equal(StaffMember.State.ON_DUTY)
	assert_int(_w.staff.staff_at(desk)).is_equal(id)
	assert_bool(saw_floor_before).is_true()
	assert_bool(saw_step_up).is_true()
	assert_bool(saw_belt_to_belt).is_true()
	assert_bool(saw_step_down).is_true()
	assert_float(max_y).is_equal_approx(BaggageViews.BELT_TOP, 0.002)
	_w.step()
	_views.draw()
	assert_float(_views.node_for(id).position.y).is_equal_approx(0.0, 0.001)
	# Release mid-belt and verify pooled node reuse clears any prior belt lift.
	var second_id := _w.staff.hire(CHECKIN)
	var second := _w.staff.get_member(second_id)
	var desk2 := PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(8, 5), 0)
	for _i in 80:
		_w.step()
		if not second.in_pool() and grid.is_belt_cell(second.at):
			break
	assert_bool(not second.in_pool() and grid.is_belt_cell(second.at)).is_true()
	_views.draw()
	var pooled_node := _views.node_for(second_id)
	assert_float(pooled_node.position.y).is_greater(0.2)
	assert_bool(grid.apply(BuildEdit.remove_object(desk2)).ok).is_true()
	_views._process(0.0)
	assert_object(_views.node_for(second_id)).is_null()
	assert_bool(pooled_node.visible).is_false()
	var floor_desk := PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(0, 7), 0)
	_w.step()
	_views.draw()
	assert_int(_w.staff.staff_at(floor_desk)).is_equal(second_id)
	assert_object(_views.node_for(second_id)).is_equal(pooled_node)
	assert_float(_views.node_for(second_id).position.y).is_equal_approx(0.0, 0.001)
