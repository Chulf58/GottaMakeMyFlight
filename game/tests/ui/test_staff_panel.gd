class_name TestStaffPanel
extends GdUnitTestSuite
## The hiring panel: Hire and Fire per role go through StaffSim, the counts
## follow hiring and members going on duty, and the hint asks for an agent or
## an officer once a desk or scanner stands and nobody of that role is hired.

const CHECKIN := StaffMember.Role.CHECKIN
const SECURITY := StaffMember.Role.SECURITY

var _w: PassengerTestWorld
var _panel: StaffPanel


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _w != null:
		_w.free_all()
	_w = null


func _make(reference := true) -> void:
	if reference:
		_w = PassengerTestWorld.reference_world()
	else:
		_w = PassengerTestWorld.make(
			PassengerTestWorld.floored(Vector2i(12, 12)), FlightSim.schedule_starts(0)
		)
	_w.auto_staff = false
	_panel = auto_free(StaffPanel.new())
	_panel.staff = _w.staff
	add_child(_panel)


func test_the_panel_card_uses_the_hud_theme() -> void:
	_make()
	assert_object(_panel.card().theme).is_same(BuildMenu.HUD_THEME)
	assert_bool(_panel.card().visible).is_true()


func test_hire_adds_a_member_and_the_count_follows_it_on_duty() -> void:
	_make()
	assert_str(_panel.counts_text(CHECKIN)).is_equal("0 hired, 0 on duty")
	_panel.hire_button(CHECKIN).pressed.emit()
	assert_int(_w.staff.count(CHECKIN)).is_equal(1)
	assert_int(_w.staff.count(SECURITY)).is_equal(0)
	assert_str(_panel.counts_text(CHECKIN)).is_equal("1 hired, 0 on duty")
	while _w.staff.on_duty_count(CHECKIN) == 0 and _w.clock.tick < 600:
		_w.step()
	assert_str(_panel.counts_text(CHECKIN)).is_equal("1 hired, 1 on duty")
	assert_str(_panel.counts_text(SECURITY)).is_equal("0 hired, 0 on duty")


func test_fire_is_off_with_nobody_hired_and_lets_one_go() -> void:
	_make()
	assert_bool(_panel.fire_button(SECURITY).disabled).is_true()
	_panel.hire_button(SECURITY).pressed.emit()
	_panel.hire_button(SECURITY).pressed.emit()
	assert_bool(_panel.fire_button(SECURITY).disabled).is_false()
	_panel.fire_button(SECURITY).pressed.emit()
	assert_int(_w.staff.count(SECURITY)).is_equal(1)
	assert_str(_panel.counts_text(SECURITY)).is_equal("1 hired, 0 on duty")
	_panel.fire_button(SECURITY).pressed.emit()
	assert_int(_w.staff.count(SECURITY)).is_equal(0)
	assert_bool(_panel.fire_button(SECURITY).disabled).is_true()


func test_the_hint_asks_for_each_role_and_clears_once_hired() -> void:
	_make()
	assert_str(_panel.hint_text()).is_equal("Hire a check-in agent\nHire a security officer")
	assert_bool(_panel.hint_label().visible).is_true()
	_panel.hire_button(CHECKIN).pressed.emit()
	assert_str(_panel.hint_text()).is_equal("Hire a security officer")
	_panel.hire_button(SECURITY).pressed.emit()
	assert_str(_panel.hint_text()).is_equal("")
	assert_bool(_panel.hint_label().visible).is_false()
	_panel.fire_button(CHECKIN).pressed.emit()
	assert_str(_panel.hint_text()).is_equal("Hire a check-in agent")
	assert_bool(_panel.hint_label().visible).is_true()


func test_the_hint_waits_for_a_desk_and_then_a_scanner() -> void:
	_make(false)
	assert_str(_panel.hint_text()).is_equal("")
	assert_bool(_panel.hint_label().visible).is_false()
	PassengerTestWorld.place(_w.grid, &"checkin_desk", Vector2i(2, 2), 0)
	assert_str(_panel.hint_text()).is_equal("Hire a check-in agent")
	assert_bool(_panel.hint_label().visible).is_true()
	PassengerTestWorld.place(_w.grid, &"security_scanner", Vector2i(8, 2), 0)
	assert_str(_panel.hint_text()).is_equal("Hire a check-in agent\nHire a security officer")


func test_an_agent_fired_mid_service_shows_as_leaving_until_it_goes() -> void:
	_make()
	_panel.hire_button(SECURITY).pressed.emit()
	_panel.hire_button(CHECKIN).pressed.emit()
	while _w.staff.on_duty_count(CHECKIN) == 0 and _w.clock.tick < 600:
		_w.step()
	var p := _w.passenger(_w.sim.spawn_now(PassengerTestWorld.FLIGHT))
	while p.stage != Passenger.Stage.CHECKIN and _w.clock.tick < 1200:
		_w.step()
	assert_int(p.stage).is_equal(Passenger.Stage.CHECKIN)
	_panel.fire_button(CHECKIN).pressed.emit()
	assert_str(_panel.counts_text(CHECKIN)).is_equal("1 hired, 1 on duty, 1 leaving")
	assert_bool(_panel.fire_button(CHECKIN).disabled).is_true()
	assert_str(_panel.hint_text()).is_equal("Hire a check-in agent")
	while _w.staff.count(CHECKIN) > 0 and _w.clock.tick < 1400:
		_w.step()
	assert_str(_panel.counts_text(CHECKIN)).is_equal("0 hired, 0 on duty")
	assert_bool(_panel.fire_button(CHECKIN).disabled).is_true()
	assert_str(_panel.hint_text()).is_equal("Hire a check-in agent")
