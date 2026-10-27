class_name TestStaffWalk
extends GdUnitTestSuite
## Idle staff walk from the entrance to the nearest unstaffed station of their
## role and go on duty there; a removed station frees its member.

const CHECKIN := StaffMember.Role.CHECKIN
const SECURITY := StaffMember.Role.SECURITY
const LIMIT_TICKS := 600

var _w: PassengerTestWorld
var _other: PassengerTestWorld
var _ids: Dictionary


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_w = PassengerTestWorld.reference_world()
	_w.auto_staff = false
	_ids = ReferenceTerminal.object_ids(_w.grid)


func after_test() -> void:
	for world in [_w, _other]:
		if world != null:
			world.free_all()
	_w = null
	_other = null


## Steps until the member is on duty; returns the ticks it took, or -1.
func _until_on_duty(member: int) -> int:
	var start := _w.clock.tick
	while _w.clock.tick - start < LIMIT_TICKS:
		_w.step()
		if _w.staff.get_member(member).state == StaffMember.State.ON_DUTY:
			return _w.clock.tick - start
	return -1


func test_a_hired_agent_walks_from_the_entrance_to_the_nearest_desk() -> void:
	# The second desk (x 14) is nearer the entrance at (18, 17) than the first.
	var desk: int = _ids["desks"][1]
	var id := _w.staff.hire(CHECKIN)
	_w.step()
	var m := _w.staff.get_member(id)
	assert_int(m.state).is_equal(StaffMember.State.TO_STATION)
	assert_int(m.station).is_equal(desk)
	assert_that(m.path[0]).is_equal(ReferenceTerminal.ENTRANCE_CELL)
	assert_bool(_w.staff.is_staffed(desk)).is_false()
	var ticks := _until_on_duty(id)
	print("agent on duty after %d ticks at %s" % [ticks, m.at])
	assert_int(ticks).is_greater(0)
	assert_that(m.at).is_equal(_w.sim.layout.lanes[desk][0])
	assert_bool(_w.staff.is_staffed(desk)).is_true()
	assert_int(_w.staff.on_duty_count(CHECKIN)).is_equal(1)


func test_a_second_agent_takes_the_desk_still_without_staff() -> void:
	var first := _w.staff.hire(CHECKIN)
	var second := _w.staff.hire(CHECKIN)
	_w.step()
	assert_int(_w.staff.get_member(first).station).is_equal(_ids["desks"][1])
	assert_int(_w.staff.get_member(second).station).is_equal(_ids["desks"][0])
	assert_int(_until_on_duty(second)).is_greater(0)
	assert_bool(_w.staff.is_staffed(_ids["desks"][0])).is_true()
	assert_bool(_w.staff.is_staffed(_ids["desks"][1])).is_true()


func test_an_officer_walks_to_a_scanner_never_a_desk() -> void:
	var id := _w.staff.hire(SECURITY)
	_w.step()
	# Both scanners are equally far: the tie goes to the lower id.
	assert_int(_w.staff.get_member(id).station).is_equal(_ids["scanners"][0])
	assert_int(_until_on_duty(id)).is_greater(0)
	assert_bool(_w.staff.is_staffed(_ids["scanners"][0])).is_true()
	assert_int(_w.staff.on_duty_count(SECURITY)).is_equal(1)


func test_staff_with_no_unstaffed_station_stay_idle_in_the_pool() -> void:
	var ids: Array[int] = []
	for i in 3:
		ids.append(_w.staff.hire(SECURITY))
	_w.run_to(_w.clock.tick + 40)
	var last := _w.staff.get_member(ids[2])
	assert_int(last.state).is_equal(StaffMember.State.IDLE)
	assert_bool(last.in_pool()).is_true()
	assert_int(last.station).is_equal(0)


func test_the_walk_is_the_same_in_two_worlds_tick_by_tick() -> void:
	_other = PassengerTestWorld.reference_world()
	_other.auto_staff = false
	var differing := 0
	for world in [_w, _other]:
		world.staff.hire(CHECKIN)
		world.staff.hire(SECURITY)
		world.staff.hire(CHECKIN)
	for i in 300:
		_w.step()
		_other.step()
		differing += int(StaffTestKit.signature(_w.staff) != StaffTestKit.signature(_other.staff))
	print("final staff state: %s" % StaffTestKit.signature(_w.staff))
	assert_int(differing).is_equal(0)
	assert_int(_w.staff.on_duty_count(CHECKIN)).is_equal(2)
	assert_int(_w.staff.on_duty_count(SECURITY)).is_equal(1)


func test_removing_a_station_frees_its_staff_to_the_next_unstaffed_one() -> void:
	var id := _w.staff.hire(CHECKIN)
	assert_int(_until_on_duty(id)).is_greater(0)
	var near: int = _ids["desks"][1]
	var far: int = _ids["desks"][0]
	assert_bool(_w.grid.apply(BuildEdit.remove_object(near)).ok).is_true()
	assert_int(_w.staff.staff_at(near)).is_equal(0)
	_w.step()
	var m := _w.staff.get_member(id)
	assert_bool(m.in_pool()).is_false()
	assert_int(m.station).is_equal(far)
	assert_int(_until_on_duty(id)).is_greater(0)
	assert_bool(_w.staff.is_staffed(far)).is_true()


func test_removing_the_only_station_leaves_its_member_idle_on_the_floor() -> void:
	var id := _w.staff.hire(SECURITY)
	assert_int(_until_on_duty(id)).is_greater(0)
	for scanner in _ids["scanners"]:
		assert_bool(_w.grid.apply(BuildEdit.remove_object(scanner)).ok).is_true()
	_w.step()
	var m := _w.staff.get_member(id)
	assert_int(m.state).is_equal(StaffMember.State.IDLE)
	assert_int(m.station).is_equal(0)
	assert_bool(m.in_pool()).is_false()
	assert_int(_w.staff.on_duty_count(SECURITY)).is_equal(0)


## Steps a fresh agent until it is at least 300 mm into a step (a straight one
## when `straight`) with `cells_left` path cells still ahead; returns it.
func _mid_step(cells_left: int, straight: bool) -> StaffMember:
	# An officer: the walk to a scanner is the longest from the entrance.
	var m := _w.staff.get_member(_w.staff.hire(SECURITY))
	while _w.clock.tick < LIMIT_TICKS:
		_w.step()
		# Two cells in, clear of the entrance door's own cell.
		if m.state != StaffMember.State.TO_STATION or m.seg_mm < 300 or m.path_index < 2:
			continue
		if m.path.size() - 1 - m.path_index < cells_left:
			continue
		var step := m.path[m.path_index + 1] - m.at
		if not straight or step.x == 0 or step.y == 0:
			return m
	return null


func test_an_edit_ahead_on_the_path_keeps_the_step_in_progress() -> void:
	var m := _mid_step(4, false)
	assert_object(m).is_not_null()
	var ahead := m.path[m.path_index + 3]
	var placed := false
	for side in 4:
		placed = placed or _w.grid.apply(BuildEdit.place_wall(ahead, side)).ok
	assert_bool(placed).is_true()
	assert_bool(m.needs_replan).is_true()
	var before := m.grid_position()
	_w.step()
	var moved := m.grid_position().distance_to(before)
	print("edit ahead at %s: moved %.3f m on the next tick, seg_mm %d" % [ahead, moved, m.seg_mm])
	assert_float(moved).is_less_equal(0.1)
	assert_int(_until_on_duty(m.id)).is_greater(0)


func test_a_wall_across_the_current_step_turns_the_member_back_without_a_jump() -> void:
	var m := _mid_step(3, true)
	assert_object(m).is_not_null()
	var here := m.at
	var next := m.path[m.path_index + 1]
	var side := BuildGrid.SIDE_STEP.find(next - here)
	assert_bool(_w.grid.apply(BuildEdit.place_wall(here, side)).ok).is_true()
	assert_bool(_w.grid.can_route(here, next)).is_false()
	var before := m.grid_position()
	_w.step()
	var moved := m.grid_position().distance_to(before)
	print("wall across %s -> %s: moved %.3f m, now at %s" % [here, next, moved, m.at])
	assert_float(moved).is_less_equal(0.1)
	assert_int(_until_on_duty(m.id)).is_greater(0)


func test_a_floor_removed_under_the_next_cell_turns_the_member_back_without_a_jump() -> void:
	var m := _mid_step(3, true)
	assert_object(m).is_not_null()
	var here := m.at
	var next := m.path[m.path_index + 1]
	var seg := m.seg_mm
	assert_bool(_w.grid.apply(BuildEdit.remove_floor(next)).ok).is_true()
	assert_bool(_w.grid.is_walkable(next)).is_false()
	var before := m.grid_position()
	_w.step()
	var moved := m.grid_position().distance_to(before)
	print(
		(
			"floor gone at %s: was %d mm in from %s, moved %.3f m, now at %s"
			% [next, seg, here, moved, m.at]
		)
	)
	assert_bool(m.in_pool()).is_false()
	assert_int(m.state).is_equal(StaffMember.State.TO_STATION)
	assert_float(moved).is_less_equal(0.1)
	assert_bool(m.backing_out).is_true()
	# It reaches the cell it left, clears the mark and walks on to its post
	# (the terminal has another way round).
	var ticks := _until_on_duty(m.id)
	print("on duty after %d more ticks at %s" % [ticks, m.at])
	assert_int(ticks).is_greater(0)
	assert_bool(m.backing_out).is_false()
	assert_int(m.state).is_equal(StaffMember.State.ON_DUTY)
	assert_that(m.at).is_equal(_w.sim.layout.lanes[m.station][0])


func test_an_edit_during_a_reversal_reroutes_the_rest_without_going_back_to_the_gone_cell() -> void:
	var m := _mid_step(3, true)
	assert_object(m).is_not_null()
	assert_bool(_w.grid.apply(BuildEdit.remove_floor(m.path[m.path_index + 1])).ok).is_true()
	_w.step()
	assert_bool(m.backing_out).is_true()
	var gone := m.at
	var tail := m.path[2]
	var placed := false
	for side in 4:
		placed = placed or _w.grid.apply(BuildEdit.place_wall(tail, side)).ok
	assert_bool(placed).is_true()
	assert_bool(m.needs_replan).is_true()
	var before := m.grid_position()
	_w.step()
	var moved := m.grid_position().distance_to(before)
	print("wall at %s during the reversal from %s: moved %.3f m" % [tail, gone, moved])
	assert_float(moved).is_less_equal(0.1)
	assert_bool(m.in_pool()).is_false()
	assert_bool(m.backing_out or m.at != gone).is_true()
	assert_int(_until_on_duty(m.id)).is_greater(0)
	assert_bool(m.backing_out).is_false()


func test_a_cell_built_over_in_the_first_step_of_a_path_still_sends_the_member_to_the_pool(
) -> void:
	# After a replan ahead the path starts afresh at the member's cell, so it is
	# on the first step of a path with a cell behind it that is not backing out.
	var m := _mid_step(4, false)
	assert_object(m).is_not_null()
	var ahead := m.path[m.path_index + 3]
	var placed := false
	for side in 4:
		placed = placed or _w.grid.apply(BuildEdit.place_wall(ahead, side)).ok
	assert_bool(placed).is_true()
	_w.step()
	assert_int(m.state).is_equal(StaffMember.State.TO_STATION)
	assert_int(m.path_index).is_equal(0)
	assert_int(m.seg_mm).is_greater(0)
	assert_bool(m.backing_out).is_false()
	var cell := m.at
	assert_bool(_w.grid.is_walkable(m.path[1])).is_true()
	assert_bool(_w.grid.apply(BuildEdit.remove_floor(cell)).ok).is_true()
	print("first step from %s, floor removed: member in pool %s" % [cell, m.in_pool()])
	assert_bool(m.in_pool()).is_true()
	assert_int(m.state).is_equal(StaffMember.State.IDLE)
	assert_int(m.station).is_equal(0)
