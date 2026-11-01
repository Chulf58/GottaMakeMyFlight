class_name TestStaffPanelCleaner
extends GdUnitTestSuite
## The hiring panel's cleaner column: Hire and Fire go through StaffSim, the
## second count is how many are cleaning now, and no hint line asks for a
## cleaner (they have no station).

const CLEANER := StaffMember.Role.CLEANER

var _w: PassengerTestWorld
var _panel: StaffPanel


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_w = MessTestKit.open_world()
	_panel = auto_free(StaffPanel.new())
	_panel.staff = _w.staff
	add_child(_panel)


func after_test() -> void:
	_w.free_all()
	_w = null


func test_the_panel_has_a_cleaner_column_and_hires_and_fires_through_it() -> void:
	assert_array(StaffPanel.ROLES).contains([CLEANER])
	assert_str(_panel.hire_button(CLEANER).name).is_equal("HireCleaner")
	assert_str(_panel.fire_button(CLEANER).name).is_equal("FireCleaner")
	assert_bool(_panel.fire_button(CLEANER).disabled).is_true()
	var hint_before := _panel.hint_text()
	_panel.hire_button(CLEANER).pressed.emit()
	var hired := _panel.counts_text(CLEANER)
	_w.sim.messes.add(MessSim.Kind.LITTER, Vector2i(4, 17))
	var cleaning := func() -> bool: return _w.staff.on_duty_count(CLEANER) == 1
	assert_bool(CleanerTestKit.step_until(_w, cleaning)).is_true()
	var at_work := _panel.counts_text(CLEANER)
	print("hint '%s'; counts '%s' then '%s'" % [hint_before, hired, at_work])
	assert_str(hint_before).is_empty()
	assert_str(hired).is_equal("1 hired, 0 cleaning")
	assert_str(at_work).is_equal("1 hired, 1 cleaning")
	assert_bool(_panel.fire_button(CLEANER).disabled).is_false()
	_panel.fire_button(CLEANER).pressed.emit()
	assert_int(_w.staff.count(CLEANER)).is_equal(0)
	assert_str(_panel.counts_text(CLEANER)).is_equal("0 hired, 0 cleaning")
