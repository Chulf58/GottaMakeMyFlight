class_name TestStaffSnapshotSlots
extends GdUnitTestSuite
## The staff save holds each member's post (slot). A save missing a slot, or
## with a slot that breaks the post rules, is refused naming the problem, and
## so is a save of an older version (no migration before a release).

const PRIMARY := StaffMember.Slot.PRIMARY
const HELPER := StaffMember.Slot.HELPER
const SCANNER_AT := Vector2i(9, 9)

var _worlds: Array[PassengerTestWorld] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for w in _worlds:
		w.free_all()
	_worlds.clear()


## SecurityTestWorld's lane grid plus a basic scanner, no automatic staffing.
func _world() -> PassengerTestWorld:
	var grid := SecurityTestWorld.build_grid(true)
	PassengerTestWorld.place(grid, &"security_scanner", SCANNER_AT, 0)
	var w := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	w.auto_staff = false
	_worlds.append(w)
	return w


func _arch(w: PassengerTestWorld) -> int:
	return w.sim.layout.security_lanes.complete_arches()[0]


func _scanner(w: PassengerTestWorld) -> int:
	return w.grid.object_at(SCANNER_AT)


## A world with the lane's primary and helper and the scanner's primary on
## duty (members 1, 2 and 3), saved through JSON. With the scanner unstaffed
## the step would recall the helper there.
func _good() -> Dictionary:
	var w := _world()
	StaffTestKit.seat(w.staff, _arch(w), PRIMARY)
	StaffTestKit.seat(w.staff, _arch(w), HELPER)
	StaffTestKit.seat(w.staff, _scanner(w), PRIMARY)
	w.step()
	return JSON.parse_string(JSON.stringify(w.staff.to_snapshot()))


func _error(data: Dictionary) -> String:
	var loaded := StaffSnapshot.load(data, _world().sim)
	return loaded.get("error", "")


func _changed(data: Dictionary, change: Callable) -> Dictionary:
	var out := data.duplicate(true)
	change.call(out)
	return out


func test_a_helper_round_trips_through_a_save() -> void:
	var data := _good()
	assert_int(int(data["save_version"])).is_equal(StaffSim.SAVE_VERSION)
	var b := _world()
	assert_bool(b.staff.from_snapshot(data)).is_true()
	var helper := b.staff.get_member(b.staff.staff_at(_arch(b), HELPER))
	print("loaded helper %d slot %d at %s" % [helper.id, helper.slot, helper.at])
	assert_int(helper.slot).is_equal(HELPER)
	assert_that(helper.at).is_equal(b.staff.spot_of(_arch(b), HELPER))
	assert_bool(b.staff.is_staffed(_arch(b), HELPER)).is_true()
	assert_bool(b.staff.is_open(_arch(b))).is_true()
	assert_dict(JSON.parse_string(JSON.stringify(b.staff.to_snapshot()))).is_equal(data)


func test_a_version_1_save_with_no_slots_is_refused_not_migrated() -> void:
	var w := _world()
	StaffTestKit.seat(w.staff, _arch(w), PRIMARY)
	StaffTestKit.seat(w.staff, _scanner(w), PRIMARY)
	var v1: Dictionary = JSON.parse_string(JSON.stringify(w.staff.to_snapshot()))
	v1["save_version"] = 1
	for record: Dictionary in v1["members"]:
		record.erase("slot")
	var b := _world()
	var problem := str(StaffSnapshot.load(v1, b.sim).get("error", ""))
	print("version 1: '%s'" % problem)
	assert_str(problem).is_equal("save_version 1 is not %d" % StaffSim.SAVE_VERSION)
	assert_bool(b.staff.from_snapshot(v1)).is_false()
	assert_array(b.staff.member_ids()).is_empty()


func test_bad_versions_and_slots_are_refused() -> void:
	var good := _good()
	var helper_at := 1
	assert_int(int(good["members"][helper_at]["slot"])).is_equal(HELPER)
	var cases := {
		"no slot":
		[
			_changed(good, func(d: Dictionary) -> void: d["members"][0].erase("slot")),
			"has no 'slot'"
		],
		"version 1":
		[_changed(good, func(d: Dictionary) -> void: d["save_version"] = 1), "1 is not 5"],
		"version 4":
		[_changed(good, func(d: Dictionary) -> void: d["save_version"] = 4), "4 is not 5"],
		"version 6":
		[_changed(good, func(d: Dictionary) -> void: d["save_version"] = 6), "6 is not 5"],
		"unknown slot":
		[
			_changed(good, func(d: Dictionary) -> void: d["members"][helper_at]["slot"] = 7),
			"unknown slot"
		],
		"a check-in helper":
		[_changed(good, _checkin_helper), "is a helper but not a security officer"],
		"a helper leaving":
		[
			_changed(good, func(d: Dictionary) -> void: d["members"][helper_at]["leaving"] = true),
			"is a helper but leaving"
		],
		"a helper at a basic scanner":
		[
			_changed(
				good,
				func(d: Dictionary) -> void: d["members"][helper_at]["station"] = _scanner_id(good)
			),
			"which is not a whole security lane"
		],
		"a helper slot with no station":
		[_changed(good, _idle_helper), "has no station but a helper slot"],
		"one helper post twice": [_changed(good, _second_helper), "helper post is claimed twice"],
	}
	for name: String in cases:
		var error := _error(cases[name][0])
		print("%s: %s" % [name, error])
		assert_str(error).override_failure_message(name).contains(cases[name][1])
	# Control: the unchanged save loads.
	assert_str(_error(good)).is_empty()


func _checkin_helper(d: Dictionary) -> void:
	d["members"][1]["role"] = StaffMember.Role.CHECKIN


## The basic scanner's id in the layout `_world()` builds.
func _scanner_id(_data: Dictionary) -> int:
	return _scanner(_world())


func _idle_helper(d: Dictionary) -> void:
	var record: Dictionary = d["members"][1]
	record["station"] = 0
	record["state"] = StaffMember.State.IDLE
	record["path"] = [record["at"]]
	record["path_index"] = 0


func _second_helper(d: Dictionary) -> void:
	var copy: Dictionary = (d["members"][1] as Dictionary).duplicate(true)
	copy["id"] = int(d["next_id"])
	d["next_id"] = int(d["next_id"]) + 1
	(d["members"] as Array).append(copy)
