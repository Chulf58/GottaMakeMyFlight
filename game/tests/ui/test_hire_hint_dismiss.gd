class_name TestHireHintDismiss
extends GdUnitTestSuite
## Regression tests for immediate hire-hint dismissal (board item ff0e7dbe):
## hiring via StaffSim.hire() dismisses Hints (SECOND_HIRE, CLEANERS) and
## StaffPanel's post-open SECOND_HIRE gap immediately while the staff member is
## still IDLE / TO_STATION, and pre-open "on the way" rows do not pulse Hire.

const CHECKIN := StaffMember.Role.CHECKIN
const SECURITY := StaffMember.Role.SECURITY
const CLEANER := StaffMember.Role.CLEANER
const LIMIT_TICKS := 4000

var _port: SubViewport
var _w: PassengerTestWorld
var _hud: PassengerHud
var _hints: Hints
var _path: String
var _alert_path: String
var _dep_path: String


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_path = SaveTestKit.run_path("hire_hint_dismiss")
	_alert_path = SaveTestKit.run_path("hire_hint_dismiss_alerts")
	_dep_path = SaveTestKit.run_path("hire_hint_dismiss_deps")
	DirAccess.remove_absolute(_path)


func after_test() -> void:
	if _hints != null:
		_hints.set_process(false)
		_hints.free()
		_hints = null
	if _hud != null:
		_hud.free()
		_hud = null
	if _port != null:
		_port.free()
		_port = null
	if _w != null:
		_w.free_all()
		_w = null
	for p in [_path, _path + ".tmp", _alert_path, _dep_path]:
		DirAccess.remove_absolute(p)


func _seat_one(role: StaffMember.Role) -> void:
	_w.staff.hire(role)
	_w.step()
	while _w.staff.on_duty_count(role) == 0 and _w.clock.tick < LIMIT_TICKS:
		_w.step()
	assert_int(_w.staff.on_duty_count(role)).is_greater(0)


func _bound_hints(panel: StaffPanel) -> Hints:
	_hud = PassengerHud.new()
	_hud.sim = _w.sim
	_hud.flights = _w.flights
	_hud.clock = _w.clock
	_hud.alert_settings_path = _alert_path
	_hud.departures_settings_path = _dep_path
	add_child(_hud)
	_hints = Hints.new()
	_hints.forced_mode = Hints.Mode.PROFILE
	_hints.settings_path = _path
	_hints.hud = _hud
	_hints.staff_panel = panel
	add_child(_hints)
	# First frame binds _sim and starts grace; advance past grace and baseline.
	_hints._process(0.0)
	var world := HintRules.read_world(_w.sim, panel.hiring_hint_roles())
	_hints.advance(Hints.GRACE_S + 0.1, world, [])
	return _hints


func _run_bound(hints: Hints, panel: StaffPanel, seconds: float, open: Array = []) -> void:
	var left := seconds
	while left > 0.0:
		var step := minf(0.25, left)
		var world := HintRules.read_world(_w.sim, panel.hiring_hint_roles())
		world["airport_open"] = _w.flights.opened_tick >= 0
		hints.advance(step, world, open)
		left -= step


func test_second_hire_hint_dismisses_immediately_on_hire_while_walking() -> void:
	_w = PassengerTestWorld.reference_world()
	_w.auto_staff = false
	_seat_one(CHECKIN)
	var panel := auto_free(StaffPanel.new()) as StaffPanel
	panel.staff = _w.staff
	add_child(panel)
	var hints := _bound_hints(panel)
	hints._seen[HintRules.PLACE_GATE_DESK] = true
	hints._seen[HintRules.PLACE_SEATS] = true
	_run_bound(hints, panel, HintRules.HOLD_S + 0.5, [HintRules.STAFF_CARD])
	assert_str(hints.shown_id()).is_equal(HintRules.SECOND_HIRE)
	assert_bool(hints.card().visible).is_true()
	# Hiring while paused (IDLE) dismisses synchronously on staff_changed without MIN_SHOW_S.
	var second_id := _w.staff.hire(CHECKIN)
	assert_int(_w.staff.get_member(second_id).state).is_equal(StaffMember.State.IDLE)
	assert_bool(hints.is_showing()).is_false()
	assert_bool(hints.card().visible).is_false()
	# Stepping so the new agent walks to the desk keeps the hint dismissed.
	_w.step()
	assert_int(_w.staff.get_member(second_id).state).is_equal(StaffMember.State.TO_STATION)
	hints._process(Hints.READ_EVERY_S + 0.01)
	assert_bool(hints.is_showing()).is_false()


func test_cleaners_hint_dismisses_immediately_on_hire_before_min_show() -> void:
	_w = MessTestKit.open_world()
	_w.auto_staff = false
	var panel := auto_free(StaffPanel.new()) as StaffPanel
	panel.staff = _w.staff
	add_child(panel)
	var hints := _bound_hints(panel)
	hints._seen[HintRules.PLACE_CHECKIN] = true
	assert_int(_w.sim.messes.add(MessSim.Kind.SPILL, Vector2i(4, 8))).is_greater(0)
	_run_bound(hints, panel, HintRules.HOLD_S + 0.5, [HintRules.STAFF_CARD])
	assert_str(hints.shown_id()).is_equal(HintRules.CLEANERS)
	assert_bool(hints.card().visible).is_true()
	# Hiring a cleaner dismisses immediately without waiting MIN_SHOW_S or READ_EVERY_S.
	var cleaner_id := _w.staff.hire(CLEANER)
	assert_int(_w.staff.get_member(cleaner_id).state).is_equal(StaffMember.State.IDLE)
	assert_bool(hints.is_showing()).is_false()
	assert_bool(hints.card().visible).is_false()


func test_post_open_staff_panel_clears_second_hire_gap_immediately_on_hire() -> void:
	_w = PassengerTestWorld.reference_world()
	_w.auto_staff = false
	_seat_one(CHECKIN)
	_seat_one(SECURITY)
	_seat_one(SECURITY)
	var gate := auto_free(AirportGate.new()) as AirportGate
	gate.bind(_w.flights, _w.staff)
	_w.step()
	assert_bool(gate.is_open()).is_true()
	var panel := auto_free(StaffPanel.new()) as StaffPanel
	panel.staff = _w.staff
	panel.gate = gate
	add_child(panel)
	panel.poll_gaps()
	assert_str(panel.hint_text()).contains(Checklist.GAPS[HintRules.SECOND_HIRE])
	# Hiring the second check-in agent clears the gap line immediately while IDLE and TO_STATION.
	var second_id := _w.staff.hire(CHECKIN)
	assert_int(_w.staff.get_member(second_id).state).is_equal(StaffMember.State.IDLE)
	assert_str(panel.hint_text()).not_contains(Checklist.GAPS[HintRules.SECOND_HIRE])
	_w.step()
	assert_int(_w.staff.get_member(second_id).state).is_equal(StaffMember.State.TO_STATION)
	assert_str(panel.hint_text()).not_contains(Checklist.GAPS[HintRules.SECOND_HIRE])


func test_pre_open_walking_rows_omit_hire_pulse_action() -> void:
	var walking := (
		Checklist
		. opening_lines(
			[
				AirportGate.Blocker.NO_CHECKIN,
				AirportGate.Blocker.NO_SECURITY,
				AirportGate.Blocker.NO_GATE_AGENT,
			],
			{
				"desks": 1,
				"scanners": 1,
				"seats": 1,
				"checkin_staying": 1,
				"security_staying": 1,
				"gate_staying": 1,
			}
		)
	)
	for entry in walking:
		if not entry["done"]:
			assert_str(str(entry["text"])).ends_with("on the way")
			assert_dict(entry["action"]).is_empty()
	# Clicking a walking row on ChecklistCard does not open Staff or pulse Hire.
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_w = PassengerTestWorld.reference_world()
	_w.auto_staff = false
	var gate := AirportGate.new()
	gate.flights = _w.flights
	gate.staff = _w.staff
	_port.add_child(gate)
	var mode := BuildMode.new()
	mode.grid_size = Vector2i(20, 20)
	mode.grid = _w.grid
	_port.add_child(mode)
	var menu := BuildMenu.new()
	menu.build_mode = mode
	_port.add_child(menu)
	var panel := StaffPanel.new()
	panel.staff = _w.staff
	panel.gate = gate
	panel.menu = menu
	_port.add_child(panel)
	_w.staff.hire(CHECKIN)
	_w.step()
	var rows := panel.checklist().row_texts()
	var walking_idx := Array(rows).find("Check-in agent on the way")
	assert_int(walking_idx).is_greater_equal(0)
	assert_bool(panel.checklist().press_row(walking_idx)).is_false()
	assert_bool(menu.staff_open).is_false()
