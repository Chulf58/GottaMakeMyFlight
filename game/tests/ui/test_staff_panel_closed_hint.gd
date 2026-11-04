class_name TestStaffPanelClosedHint
extends GdUnitTestSuite
## While the airport is closed the staff panel's hint names what keeps it
## closed (decision airport-opening-design-stays-open-once-opened-starter-
## flight-placed-after-opening): no working path, no check-in agent at a desk
## or no security officer at a scanner or lane. The closed line is replaced by
## the starter contract line once the airport opens (test_staff_panel_open_cue.gd).

const CHECKIN := StaffMember.Role.CHECKIN
const SECURITY := StaffMember.Role.SECURITY
## The checklist card's staff lines (Checklist.NEXT).
const CI_HIRE := "Check-in desk and an agent: hire an agent on Staff"
const SEC_HIRE := "Security scanner and an officer: hire an officer on Staff"

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
	# The checklist card lists every need still open, the path first.
	assert_str(_panel.hint_text()).is_equal(
		(
			"Entrance with a way through check-in and security to an exit\n"
			+ "Check-in desk and an agent: place a desk\n"
			+ "Security scanner and an officer: place a scanner\n"
			+ "Seats near the gate"
		)
	)
	assert_str(_panel.hint_label().text).is_equal(Checklist.TITLE_CLOSED)
	assert_bool(_panel.hint_label().visible).is_true()


func test_the_hint_follows_the_blocker_until_the_airport_opens() -> void:
	_make()
	assert_str(_panel.hint_text()).is_equal(CI_HIRE + "\n" + SEC_HIRE)
	_panel.hire_button(CHECKIN).pressed.emit()
	assert_str(_panel.hint_text()).is_equal(
		"Check-in desk and an agent: the agent is on the way\n" + SEC_HIRE
	)
	_until_on_duty(CHECKIN)
	assert_str(_panel.hint_text()).is_equal(
		"Security scanner and an officer: hire an officer on Staff"
	)
	_panel.hire_button(SECURITY).pressed.emit()
	assert_str(_panel.hint_text()).is_equal(
		"Security scanner and an officer: the officer is on the way"
	)
	_until_on_duty(SECURITY)
	_w.step()
	assert_bool(_gate.is_open()).is_true()
	assert_str(_panel.hint_label().text).is_equal(
		"Open! Starter contract: Gotta Air to Oslo, daily"
	)
	assert_bool(_panel.hint_label().visible).is_true()


## Loading an open save refreshes the hint with no staff or grid event.
func test_loading_an_open_save_clears_the_closed_line() -> void:
	_make()
	assert_str(_panel.hint_label().text).is_equal(Checklist.TITLE_CLOSED)
	var data := _w.flights.to_snapshot()
	data["opened_tick"] = 0
	assert_bool(_w.flights.from_snapshot(data)).is_true()
	assert_str(_panel.hint_text()).is_equal("Hire a check-in agent\nHire a security officer")
	assert_str(_panel.hint_label().text).is_equal(Checklist.TITLE_OPEN)


## Without a gate (the panel on its own) only the hiring lines show.
func test_a_panel_without_a_gate_shows_only_the_hiring_hint() -> void:
	_make()
	_panel.gate = null
	assert_str(_panel.hint_text()).is_equal("Hire a check-in agent\nHire a security officer")
