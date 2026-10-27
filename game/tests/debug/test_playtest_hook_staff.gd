class_name TestPlaytestHookStaff
extends GdUnitTestSuite
## A playtest can staff the airport through the hook (hire_staff), and the
## snapshot reports the staff counts, on the real main scene.

const MAIN := "res://main/main.tscn"
const HOOK := preload("res://debug/playtest_hook.gd")
const DIR := "user://playtest_staff_test"

var _main: Node
var _hook: Node


func before() -> void:
	_main = load(MAIN).instantiate()
	add_child(_main)
	(_main.get_node("SimClock") as SimClock).set_paused(true)
	_hook = HOOK.new()
	_hook.configure(true, DIR)
	add_child(_hook)
	assert_bool(_hook.attach(_main)).is_true()


func after() -> void:
	_hook.detach()
	_hook.free()
	_main.free()
	for name in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute("%s/%s" % [DIR, name])
	DirAccess.remove_absolute(DIR)


func test_a_new_game_snapshot_shows_no_staff() -> void:
	var staff: Dictionary = _hook.snapshot()["staff"]
	assert_dict(staff).is_equal(
		{"checkin": {"hired": 0, "on_duty": 0}, "security": {"hired": 0, "on_duty": 0}}
	)


func test_hire_staff_hires_by_role_name() -> void:
	var pool := _main.get_node("Staff") as StaffSim
	var id: int = _hook.hire_staff("checkin")
	assert_int(id).is_greater(0)
	assert_int(pool.get_member(id).role).is_equal(StaffMember.Role.CHECKIN)
	assert_int(_hook.hire_staff("security")).is_greater(id)
	var staff: Dictionary = _hook.snapshot()["staff"]
	assert_int(staff["checkin"]["hired"]).is_equal(1)
	assert_int(staff["security"]["hired"]).is_equal(1)


func test_an_unknown_role_hires_nobody() -> void:
	var pool := _main.get_node("Staff") as StaffSim
	var before_count := pool.member_ids().size()
	assert_int(_hook.hire_staff("cook")).is_equal(0)
	assert_int(pool.member_ids().size()).is_equal(before_count)
