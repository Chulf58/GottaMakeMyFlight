class_name TestStaffPool
extends GdUnitTestSuite
## Hiring puts staff in the pool by role; firing takes the member whose loss
## closes the fewest stations.

const CHECKIN := StaffMember.Role.CHECKIN
const SECURITY := StaffMember.Role.SECURITY

var _w: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_w = PassengerTestWorld.reference_world()
	_w.auto_staff = false


func after_test() -> void:
	_w.free_all()
	_w = null


func test_a_new_staff_pool_is_empty() -> void:
	assert_int(_w.staff.count(CHECKIN)).is_equal(0)
	assert_int(_w.staff.count(SECURITY)).is_equal(0)
	assert_array(_w.staff.member_ids()).is_empty()


func test_hire_adds_an_idle_member_of_its_role_to_the_pool() -> void:
	var changed := [0]
	_w.staff.staff_changed.connect(func() -> void: changed[0] += 1)
	var id := _w.staff.hire(CHECKIN)
	assert_int(id).is_greater(0)
	assert_int(_w.staff.count(CHECKIN)).is_equal(1)
	assert_int(_w.staff.count(SECURITY)).is_equal(0)
	assert_int(_w.staff.on_duty_count(CHECKIN)).is_equal(0)
	var m := _w.staff.get_member(id)
	assert_int(m.role).is_equal(CHECKIN)
	assert_int(m.state).is_equal(StaffMember.State.IDLE)
	assert_int(m.station).is_equal(0)
	assert_bool(m.in_pool()).is_true()
	assert_int(changed[0]).is_equal(1)
	var second := _w.staff.hire(SECURITY)
	assert_int(second).is_greater(id)
	assert_int(_w.staff.count(SECURITY)).is_equal(1)
	assert_array(_w.staff.member_ids()).is_equal([id, second])


func test_fire_takes_an_idle_member_then_a_walking_one_then_one_on_duty() -> void:
	var first := _w.staff.hire(CHECKIN)
	var second := _w.staff.hire(CHECKIN)
	var third := _w.staff.hire(CHECKIN)
	# Two desks: the first two hires walk to one each, the third stays idle.
	_w.step()
	assert_int(_w.staff.get_member(third).state).is_equal(StaffMember.State.IDLE)
	assert_bool(_w.staff.fire(CHECKIN)).is_true()
	assert_array(_w.staff.member_ids()).is_equal([first, second])
	while _w.staff.on_duty_count(CHECKIN) == 0:
		_w.step()
	var walking := second
	if _w.staff.get_member(first).state == StaffMember.State.TO_STATION:
		walking = first
	var on_duty := first + second - walking
	assert_int(_w.staff.get_member(walking).state).is_equal(StaffMember.State.TO_STATION)
	assert_bool(_w.staff.fire(CHECKIN)).is_true()
	# The walking one walks out: still drawn and saved, no longer staff.
	assert_int(_w.staff.get_member(walking).state).is_equal(StaffMember.State.WALKING_OUT)
	assert_int(_w.staff.count(CHECKIN)).is_equal(1)
	var station := _w.staff.get_member(on_duty).station
	assert_bool(_w.staff.is_staffed(station)).is_true()
	assert_bool(_w.staff.fire(CHECKIN)).is_true()
	assert_bool(_w.staff.is_staffed(station)).is_false()
	assert_int(_w.staff.staff_at(station)).is_equal(0)
	assert_int(_w.staff.count(CHECKIN)).is_equal(0)


func test_fire_with_nobody_of_the_role_changes_nothing() -> void:
	_w.staff.hire(SECURITY)
	assert_bool(_w.staff.fire(CHECKIN)).is_false()
	assert_int(_w.staff.count(SECURITY)).is_equal(1)
