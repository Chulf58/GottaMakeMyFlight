class_name TestStaffCharactersLane
extends GdUnitTestSuite
## A security lane's officers face their work, not the arch's front: the
## primary officer the X-ray belt it stands beside, the helper the repack berth
## it stands beside. A desk or scanner officer still faces the station's front.

const PRIMARY := StaffMember.Slot.PRIMARY
const HELPER := StaffMember.Slot.HELPER

var _w: PassengerTestWorld
var _views: StaffCharacters
var _arches: Array


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_arches = LaneStaffWorld.two_lanes()
	_w = PassengerTestWorld.make(_arches[0], PassengerTestWorld.starts_with(3000, 6000), 7)
	_w.auto_staff = false
	_views = StaffCharacters.new()
	_views.clock = _w.clock
	_views.staff = _w.staff
	add_child(_views)


func after_test() -> void:
	_views.free()
	_w.free_all()


## The yaw that looks from cell `from` to cell `to` (grid y is world z).
func _look(from: Vector2i, to: Vector2i) -> float:
	var ahead := to - from
	return atan2(ahead.x, ahead.y)


func test_the_primary_officer_faces_the_xray_belt_on_either_side() -> void:
	var yaws := []
	for arch: int in [_arches[1], _arches[2]]:
		var lane := LaneStaffWorld.lane_of(_w, arch)
		var expected := _look(lane["primary_spot"], lane["xray_belt"])
		yaws.append(_views.post_yaw(arch, PRIMARY))
		assert_float(_views.post_yaw(arch, PRIMARY)).is_equal_approx(expected, 0.0001)
		# The default slot is the primary one.
		assert_float(_views.post_yaw(arch)).is_equal_approx(expected, 0.0001)
	print("primary yaws (lane A, lane B): %s" % [yaws])
	# Lane A is RIGHT of its arch (belt to the officer's west), lane B LEFT
	# (belt to the east), both facing 0: the officers look in opposite ways
	# along x, never at the arch's front (+z, yaw 0).
	assert_float(yaws[0]).is_equal_approx(-PI / 2.0, 0.0001)
	assert_float(yaws[1]).is_equal_approx(PI / 2.0, 0.0001)


func test_the_helper_officer_faces_the_repack_berth() -> void:
	for arch: int in [_arches[1], _arches[2]]:
		var lane := LaneStaffWorld.lane_of(_w, arch)
		var expected := _look(lane["helper_spot"], lane["berth"])
		print(
			(
				"lane %d helper %s berth %s yaw %f"
				% [arch, lane["helper_spot"], lane["berth"], expected]
			)
		)
		assert_float(_views.post_yaw(arch, HELPER)).is_equal_approx(expected, 0.0001)
		# The berth lies a step from the helper spot, so the yaw is a
		# quarter turn and not the primary's.
		assert_float(_views.post_yaw(arch, HELPER)).is_not_equal(_views.post_yaw(arch, PRIMARY))


func test_a_drawn_lane_officer_is_turned_to_its_work() -> void:
	var arch: int = _arches[1]
	var primary := StaffTestKit.seat(_w.staff, arch, PRIMARY)
	var helper := StaffTestKit.seat(_w.staff, arch, HELPER)
	_views.sync(true)
	var lane := LaneStaffWorld.lane_of(_w, arch)
	var drawn_primary := _views.node_for(primary)
	var drawn_helper := _views.node_for(helper)
	print("drawn yaws: primary %f, helper %f" % [drawn_primary.rotation.y, drawn_helper.rotation.y])
	assert_float(drawn_primary.rotation.y).is_equal_approx(
		_look(lane["primary_spot"], lane["xray_belt"]), 0.0001
	)
	assert_float(drawn_helper.rotation.y).is_equal_approx(
		_look(lane["helper_spot"], lane["berth"]), 0.0001
	)
