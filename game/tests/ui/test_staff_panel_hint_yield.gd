class_name TestStaffPanelHintYield
extends GdUnitTestSuite
## The status banner yields its slot while a first-time hint shows (decision
## first-time-hints-above-the-build-bar-moment-of-need-per-profile-memory,
## point 1): it is hidden, comes back when the hint ends, and the hint takes
## the banner's place at the top centre.

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


func _make() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(12, 12))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 11), 2)
	PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(5, 3), 0)
	_w = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_w.auto_staff = false
	var gate: AirportGate = auto_free(AirportGate.new())
	gate.bind(_w.flights, _w.staff)
	_panel = auto_free(StaffPanel.new())
	_panel.staff = _w.staff
	_panel.gate = gate
	add_child(_panel)
	await await_idle_frame()
	await await_idle_frame()


func test_the_banner_shows_until_a_hint_takes_its_slot() -> void:
	await _make()
	assert_bool(_panel.hint_card().visible).is_true()
	_panel.set_hint_yielded(true)
	assert_bool(_panel.hint_card().visible).is_false()
	_panel.set_hint_yielded(false)
	assert_bool(_panel.hint_card().visible).is_true()


func test_a_refresh_while_yielded_keeps_the_banner_down() -> void:
	await _make()
	_panel.set_hint_yielded(true)
	_panel.refresh()
	assert_bool(_panel.hint_card().visible).is_false()
	assert_str(_panel.hint_text()).is_not_empty()


func test_a_banner_with_no_text_stays_hidden_when_the_hint_ends() -> void:
	await _make()
	_w.staff.hire(StaffMember.Role.CHECKIN)
	_w.step()
	_panel.set_hint_yielded(true)
	_panel.set_hint_yielded(false)
	assert_bool(_panel.hint_card().visible).is_equal(_panel.hint_text() != "")


func test_the_hiring_roles_are_the_ones_the_banner_asks_for() -> void:
	await _make()
	assert_array(_panel.hiring_hint_roles()).is_equal([StaffMember.Role.CHECKIN])
	_w.staff.hire(StaffMember.Role.CHECKIN)
	assert_array(_panel.hiring_hint_roles()).is_empty()


func test_the_hint_takes_the_place_of_the_banner() -> void:
	await _make()
	var banner := _panel.hint_card().get_global_rect()
	# Changed from the top centre: the banner sits in the top-left column.
	assert_float(banner.position.y).is_equal_approx(StaffPanel.BANNER_TOP, 0.5)
	assert_float(banner.position.x).is_equal_approx(HudLayout.MARGIN, 0.5)
	assert_float(banner.size.x).is_equal_approx(HudLayout.LIST_W, 0.5)
