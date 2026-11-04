class_name TestStationClosureSave
extends GdUnitTestSuite
## The stations the player closed are saved (staff save version 5): a load
## keeps them closed and an older staff save is refused. The closed set keeps
## the id of a removed desk, so undoing the removal brings the desk back
## closed, while a save writes only the ids still on the grid.

const CHECKIN := StaffMember.Role.CHECKIN

var _w: PassengerTestWorld
var _b: PassengerTestWorld
var _a := 0
var _other := 0


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_w = PassengerTestWorld.reference_world(5)
	_w.auto_staff = false
	var desks := _w.sim.layout.desks.duplicate()
	desks.sort()
	_a = desks[0]
	_other = desks[1]


func after_test() -> void:
	for world in [_w, _b]:
		if world != null:
			world.free_all()
	_w = null
	_b = null


func test_a_load_keeps_the_closure() -> void:
	StaffTestKit.staff_all(_w.staff, [CHECKIN])
	_w.staff.closures.set_closed(_a, true)
	_w.step()
	var data: Dictionary = JSON.parse_string(StaffTestKit.save_text(_w))
	print("saved closed %s, version %s" % [data["staff"]["closed"], data["staff"]["save_version"]])
	(
		assert_array((data["staff"]["closed"] as Array).map(func(v: Variant) -> int: return int(v)))
		. is_equal([_a])
	)
	_b = StaffTestKit.load_world(StaffTestKit.save_text(_w))
	assert_object(_b).is_not_null()
	assert_array(_b.staff.closures.ids()).is_equal([_a])
	assert_bool(_b.staff.is_open(_a)).is_false()
	assert_str(_b.staff.closures.status_text(_a)).is_equal("Closed by you")
	assert_str(StaffTestKit.signature(_b.staff)).is_equal(StaffTestKit.signature(_w.staff))
	for i in 120:
		_w.step()
		_b.step()
	assert_str(StaffTestKit.signature(_b.staff)).is_equal(StaffTestKit.signature(_w.staff))
	assert_int(_b.staff.staff_at(_a)).is_equal(0)


func test_a_version_4_staff_save_and_bad_closed_lists_are_refused() -> void:
	_w.staff.closures.set_closed(_a, true)
	var good: Dictionary = JSON.parse_string(JSON.stringify(_w.staff.to_snapshot()))
	assert_str(str(StaffSnapshot.load(good, _w.sim).get("error", ""))).is_equal("")
	var cases := {
		"version 4": [{"save_version": 4}, "save_version 4 is not 5"],
		"no list": [{"closed": 3}, "closed is not a list"],
		"not whole": [{"closed": [1.5]}, "a closed station is not a whole number"],
		"twice": [{"closed": [_a, _a]}, "closed station %d is out of order or listed twice" % _a],
		"out of order": [{"closed": [_other, _a]}, "is out of order or listed twice"],
		"not on the grid": [{"closed": [9999]}, "closed station 9999 is no object on the grid"],
	}
	var v4 := good.duplicate(true)
	v4.erase("closed")
	v4["save_version"] = 4
	for name: String in cases:
		var bad := good.duplicate(true)
		for key: String in cases[name][0]:
			bad[key] = cases[name][0][key]
		if name == "version 4":
			bad = v4
		var problem := str(StaffSnapshot.load(bad, _w.sim).get("error", ""))
		print("%s: '%s'" % [name, problem])
		assert_str(problem).contains(cases[name][1])


func test_undoing_a_desk_removal_brings_it_back_closed_and_a_save_skips_it() -> void:
	StaffTestKit.staff_all(_w.staff, [CHECKIN])
	_w.staff.closures.set_closed(_a, true)
	_w.step()
	var receipt := BuildReceipt.new()
	_w.grid.recorder = receipt
	var removed := _w.grid.apply(BuildEdit.remove_object(_a))
	_w.grid.recorder = null
	assert_bool(removed.ok).is_true()
	print(
		(
			"after removal: live set %s, saved %s"
			% [_w.staff.closures.ids(), _w.staff.to_snapshot()["closed"]]
		)
	)
	assert_array(_w.staff.closures.ids()).is_equal([_a])
	assert_array(_w.staff.to_snapshot()["closed"]).is_empty()
	var undone := BuildUndo.commit(_w.grid, receipt, null)
	print("undo ok %s; desk %d back: %s" % [undone.ok, _a, _w.sim.layout.desks.has(_a)])
	assert_bool(undone.ok).is_true()
	assert_bool(_w.sim.layout.desks.has(_a)).is_true()
	assert_bool(_w.staff.closures.is_closed(_a)).is_true()
	assert_array(_w.staff.to_snapshot()["closed"]).is_equal([_a])
	_w.run_to(_w.clock.tick + 120)
	assert_bool(_w.staff.is_open(_a)).is_false()
	assert_int(_w.staff.staff_at(_a)).is_equal(0)
	assert_str(MissSignals.closed_reason(_w.sim, _a)).is_equal("Closed by you")
