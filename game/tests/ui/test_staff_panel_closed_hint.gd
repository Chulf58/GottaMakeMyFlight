class_name TestStaffPanelClosedHint
extends GdUnitTestSuite
## While the airport is closed the staff panel's hint names what keeps it
## closed (decision airport-opening-design-stays-open-once-opened-starter-
## flight-placed-after-opening): no working path, no check-in agent at a desk
## or no security officer at a scanner or lane. The line goes once the airport opens.

const CHECKIN := StaffMember.Role.CHECKIN
const SECURITY := StaffMember.Role.SECURITY

var _w: PassengerTestWorld
var _gate: AirportGate
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
	_gate = auto_free(AirportGate.new())
	_gate.bind(_w.flights, _w.staff)
	_panel = auto_free(StaffPanel.new())
	_panel.staff = _w.staff
	_panel.gate = _gate
	add_child(_panel)


func _until_on_duty(role: StaffMember.Role) -> void:
	while _w.staff.on_duty_count(role) == 0 and _w.clock.tick < 3000:
		_w.step()
	assert_int(_w.staff.on_duty_count(role)).is_equal(1)


func test_with_no_working_path_the_hint_names_the_path() -> void:
	_make(false)
	assert_str(_panel.hint_text()).is_equal(StaffPanel.CLOSED_HINTS[AirportGate.Blocker.NO_PATH])
	assert_str(_panel.hint_text()).is_equal(
		(
			"Airport closed: passengers need a way from an entrance through check-in"
			+ " and security to an exit"
		)
	)
	assert_bool(_panel.hint_label().visible).is_true()


func test_the_hint_follows_the_blocker_until_the_airport_opens() -> void:
	_make()
	assert_str(_panel.hint_text()).is_equal(
		(
			"Airport closed: no check-in agent at a desk\n"
			+ "Hire a check-in agent\nHire a security officer"
		)
	)
	_panel.hire_button(CHECKIN).pressed.emit()
	assert_str(_panel.hint_text()).is_equal(
		"Airport closed: no check-in agent at a desk\nHire a security officer"
	)
	_until_on_duty(CHECKIN)
	assert_str(_panel.hint_label().text).is_equal(
		"Airport closed: no security officer at a scanner or lane\nHire a security officer"
	)
	_panel.hire_button(SECURITY).pressed.emit()
	assert_str(_panel.hint_label().text).is_equal(
		"Airport closed: no security officer at a scanner or lane"
	)
	_until_on_duty(SECURITY)
	_w.step()
	assert_bool(_gate.is_open()).is_true()
	assert_str(_panel.hint_label().text).is_equal("")
	assert_bool(_panel.hint_label().visible).is_false()


## Loading an open save refreshes the hint with no staff or grid event.
func test_loading_an_open_save_clears_the_closed_line() -> void:
	_make()
	assert_str(_panel.hint_label().text).starts_with("Airport closed: ")
	var data := _w.flights.to_snapshot()
	data["opened_tick"] = 0
	assert_bool(_w.flights.from_snapshot(data)).is_true()
	assert_str(_panel.hint_label().text).is_equal("Hire a check-in agent\nHire a security officer")


## Without a gate (the panel on its own) only the hiring lines show.
func test_a_panel_without_a_gate_shows_only_the_hiring_hint() -> void:
	_make()
	_panel.gate = null
	assert_str(_panel.hint_text()).is_equal("Hire a check-in agent\nHire a security officer")
