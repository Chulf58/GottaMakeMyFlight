class_name TestStaffPanelAndChecklistClarity
extends GdUnitTestSuite
## Regression tests for StaffPanel layout cleanup (12c64b23, e0d063c3),
## Checklist leg diagnosis and cleaner gap awareness (ac99698e, 540c9680),
## and DirtyAlert Tier-1 toilet mess threshold (540c9680).

const CHECKIN := StaffMember.Role.CHECKIN
const SECURITY := StaffMember.Role.SECURITY
const CLEANER := StaffMember.Role.CLEANER

var _port: SubViewport
var _mode: BuildMode
var _menu: BuildMenu
var _w: PassengerTestWorld
var _gate: AirportGate
var _panel: StaffPanel


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _port != null:
		_port.free()
		_port = null
	if _w != null:
		_w.free_all()
		_w = null
	_mode = null
	_menu = null
	_gate = null
	_panel = null


func _setup_hud(world: PassengerTestWorld) -> void:
	_w = world
	_w.auto_staff = false
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(30, 20)
	_mode.grid = _w.grid
	_mode.require_unlocks = false
	_port.add_child(_mode)
	_menu = BuildMenu.new()
	_menu.build_mode = _mode
	_port.add_child(_menu)
	_gate = AirportGate.new()
	_gate.flights = _w.flights
	_gate.staff = _w.staff
	_port.add_child(_gate)
	_panel = StaffPanel.new()
	_panel.staff = _w.staff
	_panel.gate = _gate
	_panel.menu = _menu
	_port.add_child(_panel)


func _settle(frames := 3) -> void:
	for i in frames:
		await get_tree().process_frame


func test_staff_panel_shows_all_members_and_aligns_buttons_at_top() -> void:
	_setup_hud(PassengerTestWorld.reference_world())
	_menu.press_staff()
	await _settle()

	for i in 5:
		_w.staff.hire(CHECKIN)
	_w.staff.hire(CLEANER)
	await _settle()

	var energy_box := _panel.card().find_child("CheckinEnergy", true, false) as VBoxContainer
	var energy_scroll := (
		_panel.card().find_child("CheckinEnergyScroll", true, false) as ScrollContainer
	)
	assert_object(energy_box).is_not_null()
	assert_object(energy_scroll).is_not_null()
	assert_int(energy_box.get_child_count()).is_equal(5)
	for child in energy_box.find_children("*", "Label", true, false):
		var lbl := child as Label
		assert_str(lbl.text).not_contains("more")

	var expected_hire_y := _panel.hire_button(CHECKIN).get_global_rect().position.y
	var expected_fire_y := _panel.fire_button(CHECKIN).get_global_rect().position.y
	for role in StaffPanel.ROLES:
		if not _panel.is_role_visible(role):
			continue
		var hire_rect := _panel.hire_button(role).get_global_rect()
		var fire_rect := _panel.fire_button(role).get_global_rect()
		assert_float(hire_rect.position.y).is_equal_approx(expected_hire_y, 0.5)
		assert_float(fire_rect.position.y).is_equal_approx(expected_fire_y, 0.5)
		var col := _panel.role_column(role)
		var title := col.get_child(0) as Label
		var counts := (
			_panel.card().find_child("%sCounts" % StaffPanel.ROLE_KEYS[role], true, false) as Label
		)
		assert_int(title.get_line_count()).is_equal(1)
		assert_int(counts.get_line_count()).is_equal(1)

	assert_float(expected_fire_y + _panel.fire_button(CHECKIN).size.y).is_less_equal(
		energy_scroll.get_global_rect().position.y + 0.5
	)


func test_checklist_diagnoses_missing_leg_and_selects_matching_tool() -> void:
	# Pure unit check across each missing leg.
	var no_entrance := (
		Checklist
		. opening_lines(
			[AirportGate.Blocker.NO_PATH],
			{
				"entrances": 0,
				"desks": 1,
				"scanners": 1,
				"exits": 1,
				"seats": 1,
				"checkin_staying": 1,
				"security_staying": 1,
			}
		)
	)
	assert_str(no_entrance[0]["text"]).is_equal("Place an entrance door")
	assert_int(int(no_entrance[0]["action"]["tool"])).is_equal(BuildMode.Tool.ENTRANCE)

	var no_desk := (
		Checklist
		. opening_lines(
			[AirportGate.Blocker.NO_PATH],
			{
				"entrances": 1,
				"desks": 0,
				"scanners": 1,
				"exits": 1,
				"seats": 1,
				"checkin_staying": 1,
				"security_staying": 1,
			}
		)
	)
	assert_str(no_desk[0]["text"]).is_equal("Place a check-in desk")
	assert_int(int(no_desk[0]["action"]["tool"])).is_equal(BuildMode.Tool.DESK)

	var no_scanner := (
		Checklist
		. opening_lines(
			[AirportGate.Blocker.NO_PATH],
			{
				"entrances": 1,
				"desks": 1,
				"scanners": 0,
				"exits": 1,
				"seats": 1,
				"checkin_staying": 1,
				"security_staying": 1,
			}
		)
	)
	assert_str(no_scanner[0]["text"]).is_equal("Place a security scanner")
	assert_int(int(no_scanner[0]["action"]["tool"])).is_equal(BuildMode.Tool.SCANNER)

	var no_exit := (
		Checklist
		. opening_lines(
			[AirportGate.Blocker.NO_PATH],
			{
				"entrances": 1,
				"desks": 1,
				"scanners": 1,
				"exits": 0,
				"exit_doors": 0,
				"seats": 1,
				"checkin_staying": 1,
				"security_staying": 1,
			}
		)
	)
	assert_str(no_exit[0]["text"]).is_equal("Place an Exit to the plane")
	assert_str(no_exit[0]["why"]).is_equal("Passengers board planes through an Exit door.")
	assert_str(no_exit[0]["text"].to_lower()).not_contains("airside exit")
	assert_int(int(no_exit[0]["action"]["tool"])).is_equal(BuildMode.Tool.EXIT)

	var unlinked_exit := (
		Checklist
		. opening_lines(
			[AirportGate.Blocker.NO_PATH],
			{
				"entrances": 1,
				"desks": 1,
				"scanners": 1,
				"exits": 0,
				"exit_doors": 1,
				"seats": 1,
				"checkin_staying": 1,
				"security_staying": 1,
			}
		)
	)
	assert_str(unlinked_exit[0]["text"]).is_equal(
		"Connect Gate Desk to an Exit to the plane with a clear path"
	)
	assert_str(unlinked_exit[0]["text"].to_lower()).not_contains("airside exit")
	assert_int(int(unlinked_exit[0]["action"]["tool"])).is_equal(BuildMode.Tool.GATE_DESK)

	var blocked_before_gate := (
		Checklist
		. opening_lines(
			[AirportGate.Blocker.NO_GATE, AirportGate.Blocker.NO_PATH],
			{
				"entrances": 1,
				"desks": 1,
				"scanners": 1,
				"exits": 0,
				"exit_doors": 1,
				"seats": 1,
				"checkin_staying": 1,
				"security_staying": 1,
			}
		)
	)
	assert_str(blocked_before_gate[0]["text"]).is_equal(
		"Connect entrance, check-in, security and exit with open floor"
	)
	assert_int(int(blocked_before_gate[0]["action"]["tool"])).is_equal(BuildMode.Tool.FLOOR)

	# Real grid with entrance + desk + scanner but NO exit: clicking row 0 pulses Tool.EXIT.
	var grid_no_exit := BuildGrid.new()
	ReferenceTerminal.build(grid_no_exit)
	for exit_id: int in ReferenceTerminal.object_ids(grid_no_exit)["exits"]:
		assert_bool(grid_no_exit.apply(BuildEdit.remove_object(exit_id)).ok).is_true()
	(
		assert_bool(
			(
				grid_no_exit
				. apply(BuildEdit.place_wall(ReferenceTerminal.EXIT_CELL, BuildGrid.Side.NORTH))
				. ok
			)
		)
		. is_true()
	)
	_setup_hud(PassengerTestWorld.make(grid_no_exit, FlightSim.schedule_starts(0)))
	await _settle()
	var rows_no_exit := _panel.checklist().row_texts()
	assert_str(rows_no_exit[0]).is_equal("Place an Exit to the plane")
	assert_str(rows_no_exit[0].to_lower()).not_contains("airside exit")
	assert_bool(_panel.checklist().press_row(0)).is_true()
	assert_int(_menu.pulsed_tool()).is_equal(BuildMode.Tool.EXIT)
	assert_int(_menu.pulsed_tool()).is_not_equal(BuildMode.Tool.ENTRANCE)
	after_test()

	# Real grid with all 4 pieces placed but disconnected by an airside wall: pulses Tool.FLOOR.
	var grid_blocked := BuildGrid.new()
	ReferenceTerminal.build(grid_blocked)
	for x in range(ReferenceTerminal.FLOOR_MIN.x, ReferenceTerminal.FLOOR_MAX.x + 1):
		(
			assert_bool(
				grid_blocked.apply(BuildEdit.place_wall(Vector2i(x, 4), BuildGrid.Side.NORTH)).ok
			)
			. is_true()
		)
	_setup_hud(PassengerTestWorld.make(grid_blocked, FlightSim.schedule_starts(0)))
	await _settle()
	var rows_blocked := _panel.checklist().row_texts()
	assert_str(rows_blocked[0]).is_equal(
		"Connect entrance, check-in, security and exit with open floor"
	)
	assert_bool(_panel.checklist().press_row(0)).is_true()
	assert_int(_menu.pulsed_tool()).is_equal(BuildMode.Tool.FLOOR)
	assert_int(_menu.pulsed_tool()).is_not_equal(BuildMode.Tool.ENTRANCE)


func test_checklist_surfaces_cleaner_gap_when_mess_exists_with_zero_cleaners() -> void:
	_setup_hud(MessTestKit.open_world())
	assert_bool(_w.flights.open_airport()).is_true()
	await _settle()
	var cleaner_text: String = Checklist.GAPS.get(
		HintRules.CLEANERS, "Messes need cleaning: hire a cleaner (Staff)"
	)
	_panel.poll_gaps()
	assert_str(_panel.hint_text()).not_contains(cleaner_text)

	assert_int(_w.sim.messes.add(MessSim.Kind.TOILET, Vector2i(6, 8))).is_greater(0)
	_panel.poll_gaps()
	assert_str(_panel.hint_text()).contains(cleaner_text)

	var rows := _panel.checklist().row_texts()
	var cleaner_idx := Array(rows).find(cleaner_text)
	assert_int(cleaner_idx).is_greater_equal(0)
	assert_bool(_panel.checklist().press_row(cleaner_idx)).is_true()
	assert_bool(_menu.staff_open).is_true()

	_w.staff.hire(CLEANER)
	assert_str(_panel.hint_text()).not_contains(cleaner_text)


func test_dirty_alert_triggers_at_dirt_two_for_tier1_messy_toilets() -> void:
	_w = MessTestKit.open_world()
	var alert := DirtyAlert.new()
	alert.sim = _w.sim
	assert_int(_w.sim.messes.add(MessSim.Kind.TOILET, Vector2i(4, 8))).is_greater(0)
	alert.refresh()
	assert_int(_w.sim.messes.total_dirt()).is_equal(1)
	assert_bool(alert.is_shown()).is_false()

	assert_int(_w.sim.messes.add(MessSim.Kind.TOILET, Vector2i(8, 8))).is_greater(0)
	alert.refresh()
	assert_int(_w.sim.messes.total_dirt()).is_equal(2)
	assert_bool(alert.is_shown()).is_true()
	assert_str(alert.card_text()).is_equal(DirtyAlert.HIRE_TEXT)
