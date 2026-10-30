class_name TestStaffArchTuck
extends GdUnitTestSuite
## A staff member tucks its arms in through a security lane's arch
## (StaffArchTuck): which members count as in the arch's passage, and the tuck
## weight easing in and out over TUCK_TICKS.

var _grid: BuildGrid
var _lane: Dictionary


func before() -> void:
	_grid = LaneStaffWorld.two_lanes()[0]
	_lane = SecurityLanes.geometry(LaneStaffWorld.ARCH_A, 0, SecurityLanes.RIGHT)


## A member on the lane's passage line, from the queue entry to the exit,
## that has walked `cells` whole cells and `mm` into the next.
func _walker(cells: int, mm := 0) -> StaffMember:
	var m := StaffMember.new()
	var path: Array[Vector2i] = [
		_lane["queue_entry"], _lane["unpack"], _lane["arch"], _lane["pickup"], _lane["exit"]
	]
	m.at = path[0]
	m.set_path(path)
	m.walk(cells * 1000 + mm)
	return m


func test_the_lane_is_built_where_the_walker_goes() -> void:
	var arch := _grid.object_at(_lane["arch"])
	print("arch cell %s holds %s" % [_lane["arch"], _grid.get_object(arch).get("def", "")])
	assert_str(String(_grid.get_object(arch).get("def", ""))).is_equal(String(SecurityLanes.ARCH))


func test_walking_toward_the_cell_before_the_arch_is_not_in_the_passage() -> void:
	var m := _walker(0, 500)
	print("at %s next %s" % [m.at, m.path[m.path_index + 1]])
	assert_bool(StaffArchTuck.in_arch_passage(_grid, m)).is_false()


func test_walking_into_the_arch_is_in_the_passage() -> void:
	var m := _walker(1, 10)
	print("at %s (unpack) next %s (arch)" % [m.at, m.path[m.path_index + 1]])
	assert_that(m.at).is_equal(_lane["unpack"])
	assert_bool(StaffArchTuck.in_arch_passage(_grid, m)).is_true()


func test_standing_in_the_arch_and_leaving_it_is_in_the_passage() -> void:
	for mm in [0, 500, 990]:
		var m := _walker(2, mm)
		assert_that(m.at).is_equal(_lane["arch"])
		assert_bool(StaffArchTuck.in_arch_passage(_grid, m)).is_true()


func test_arrived_past_the_arch_is_out_of_the_passage() -> void:
	var m := _walker(3, 10)
	print("at %s (pickup)" % m.at)
	assert_that(m.at).is_equal(_lane["pickup"])
	assert_bool(StaffArchTuck.in_arch_passage(_grid, m)).is_false()


func test_a_member_standing_still_before_the_arch_or_in_the_pool_is_not_in_it() -> void:
	var still := StaffMember.new()
	still.at = _lane["unpack"]
	still.clear_path()
	assert_bool(StaffArchTuck.in_arch_passage(_grid, still)).is_false()
	assert_bool(StaffArchTuck.in_arch_passage(_grid, StaffMember.new())).is_false()


func test_a_new_record_starts_settled() -> void:
	var outside := {}
	StaffArchTuck.update(outside, false, 5.0)
	var inside := {}
	StaffArchTuck.update(inside, true, 5.0)
	var weights := [StaffArchTuck.weight(outside, 5.0), StaffArchTuck.weight(inside, 5.0)]
	print("new outside, new inside: %s" % [weights])
	assert_float(weights[0]).is_equal(0.0)
	assert_float(weights[1]).is_equal(1.0)


func test_the_tuck_eases_in_then_out() -> void:
	var t := StaffArchTuck.TUCK_TICKS
	var record := {}
	StaffArchTuck.update(record, false, 0.0)
	StaffArchTuck.update(record, true, 10.0)
	var going_in := [
		StaffArchTuck.weight(record, 10.0),
		StaffArchTuck.weight(record, 10.0 + t * 0.5),
		StaffArchTuck.weight(record, 10.0 + t),
		StaffArchTuck.weight(record, 10.0 + t * 3.0),
	]
	StaffArchTuck.update(record, false, 30.0)
	var going_out := [
		StaffArchTuck.weight(record, 30.0),
		StaffArchTuck.weight(record, 30.0 + t * 0.5),
		StaffArchTuck.weight(record, 30.0 + t),
	]
	print("in %s, out %s over %f ticks" % [going_in, going_out, t])
	assert_float(going_in[0]).is_equal(0.0)
	# Eased out: past half way at half the time, short of the end.
	assert_float(going_in[1]).is_between(0.6, 0.9)
	assert_float(going_in[2]).is_equal(1.0)
	assert_float(going_in[3]).is_equal(1.0)
	assert_float(going_out[0]).is_equal(1.0)
	assert_float(going_out[1]).is_between(0.1, 0.4)
	assert_float(going_out[2]).is_equal(0.0)


func test_turning_back_mid_turn_starts_where_the_arms_are() -> void:
	var t := StaffArchTuck.TUCK_TICKS
	var record := {}
	StaffArchTuck.update(record, false, 0.0)
	StaffArchTuck.update(record, true, 10.0)
	var reached := StaffArchTuck.weight(record, 10.0 + t * 0.5)
	StaffArchTuck.update(record, false, 10.0 + t * 0.5)
	var after := StaffArchTuck.weight(record, 10.0 + t * 0.5)
	print("reached %f, then turned back from %f" % [reached, after])
	assert_float(reached).is_greater(0.0)
	assert_float(after).is_equal_approx(reached, 0.0001)
	assert_float(StaffArchTuck.weight(record, 10.0 + t * 1.5)).is_equal(0.0)
