class_name TestStaffArchTuckDrawn
extends GdUnitTestSuite
## Drawn staff tuck their arms in through a security lane's arch
## (StaffCharacters with StaffArchTuck): an officer walking through turns its
## arms in, eased, before the arch, and back out, eased, past it. Every staff
## model has the arm bones the tuck poses (CarryArm does nothing without them).

var _w: PassengerTestWorld
var _views: StaffCharacters
var _arch := 0


func before() -> void:
	PassengerTestWorld.tracker = self
	var built := LaneStaffWorld.two_lanes()
	_arch = built[1]
	_w = PassengerTestWorld.make(built[0], PassengerTestWorld.starts_with(3000, 6000), 7)
	_w.auto_staff = false
	# Both lanes' primaries on duty, so no vacancy recalls the walking helper.
	StaffTestKit.staff_all(_w.staff)
	_views = StaffCharacters.new()
	_views.clock = _w.clock
	_views.staff = _w.staff
	add_child(_views)


func after() -> void:
	_views.free()
	_w.free_all()
	PassengerTestWorld.tracker = null


## An officer sent to the lane's helper spot from two cells before its queue
## entry, along the passage through the arch; returns its id.
func _send_through() -> int:
	var lane := LaneStaffWorld.lane_of(_w, _arch)
	var front: Vector2i = lane["front"]
	var path: Array[Vector2i] = [
		lane["queue_entry"] + front * 2,
		lane["queue_entry"] + front,
		lane["queue_entry"],
		lane["unpack"],
		lane["arch"],
		lane["pickup"],
	]
	var rest := _w.grid.find_staff_path(lane["pickup"], lane["helper_spot"])
	rest.remove_at(0)
	path.append_array(rest)
	var m := _w.staff.get_member(_w.staff.hire(StaffMember.Role.SECURITY))
	m.station = _arch
	m.slot = StaffMember.Slot.HELPER
	m.at = path[0]
	m.set_path(path)
	m.state = StaffMember.State.TO_STATION
	_views.sync(true)
	return m.id


func test_an_officer_walking_through_the_arch_tucks_in_and_out_eased() -> void:
	var id := _send_through()
	var m := _w.staff.get_member(id)
	var arch: Vector2i = LaneStaffWorld.lane_of(_w, _arch)["arch"]
	# Per tick: [in the passage, tuck weight, arms posed (active, weight)].
	var rows: Array = []
	var guard := 0
	while m.state != StaffMember.State.ON_DUTY and guard < 200:
		_w.step()
		_views.draw()
		var node := _views.node_for(id)
		var posed := -1.0
		if node.has_meta(&"tuck_arms"):
			var arm: CarryArm = StaffArchTuck.arms_of(node)[0]
			posed = arm.front_weight if arm.active else 0.0
		var inside := StaffArchTuck.in_arch_passage(_w.grid, m)
		rows.append([inside, _views.tuck_of(id), posed, m.at == arch])
		guard += 1
	print("ticks %d: %s" % [rows.size(), rows])
	assert_int(m.state).is_equal(StaffMember.State.ON_DUTY)
	var first_in := -1
	var first_out := -1
	var at_arch_max := 0.0
	for i in rows.size():
		if rows[i][0] and first_in < 0:
			first_in = i
		if first_in >= 0 and first_out < 0 and not rows[i][0]:
			first_out = i
		if rows[i][3]:
			at_arch_max = maxf(at_arch_max, rows[i][1])
		# The drawn arms carry the weight the views report.
		if rows[i][1] > 0.0:
			assert_float(rows[i][2]).is_equal_approx(rows[i][1], 0.0001)
	assert_int(first_in).is_greater(0)
	assert_int(first_out).is_greater(first_in)
	# Swinging before the passage; eased in from the tick it enters, not
	# snapped (a tick later it is part way).
	assert_float(rows[first_in - 1][1]).is_equal(0.0)
	assert_float(rows[first_in][1]).is_less(0.99)
	assert_float(rows[first_in + 1][1]).is_between(0.01, 0.99)
	# Fully in while standing in the arch.
	assert_float(at_arch_max).is_equal(1.0)
	# Eased out past the arch, then swinging again with the arms let go.
	assert_float(rows[first_out][1]).is_greater(0.01)
	assert_float(rows[first_out + 1][1]).is_between(0.01, 0.99)
	var last: Array = rows[rows.size() - 1]
	assert_float(last[1]).is_equal(0.0)
	assert_float(last[2]).is_equal(0.0)


func test_every_staff_model_has_the_arm_bones_the_tuck_poses() -> void:
	for scene in StaffCharacters.CHARACTERS:
		var body := scene.instantiate() as Node3D
		var skeleton := body.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var missing := []
		for side in 2:
			for bone in [CarryArm.ARM_BONES[side], CarryArm.FOREARMS[side], CarryArm.HANDS[side]]:
				if skeleton.find_bone(bone) < 0:
					missing.append(bone)
		print("%s missing %s" % [scene.resource_path, missing])
		assert_array(missing).is_empty()
		body.free()
