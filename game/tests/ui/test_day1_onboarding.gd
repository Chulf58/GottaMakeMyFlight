class_name TestDay1Onboarding
extends GdUnitTestSuite
## Regression tests for Day-1 onboarding guidance (decision 853a87db):
## causal "why" sub-lines + folding on done, clickable ChecklistCard tab/Staff
## jumps + card pulse, pre-open prep-time clock note, StaffPanel role tooltips +
## Shop role gating until Tier 2, Flight Planner + Cleaners hints, live Tier-2
## milestone counter, replayable hints, and messages.pot completeness.

const CHECKIN := StaffMember.Role.CHECKIN
const SECURITY := StaffMember.Role.SECURITY
const SHOP := StaffMember.Role.SHOP

var _port: SubViewport
var _w: PassengerTestWorld
var _gate: AirportGate
var _rating: AirportRating
var _unlocks: BuildUnlocks
var _mode: BuildMode
var _menu: BuildMenu
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
	PseudoLocale.disable()


func _setup_hud(reference := false, require_unlocks := true) -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	if reference:
		_w = PassengerTestWorld.reference_world()
	else:
		_w = PassengerTestWorld.make(
			PassengerTestWorld.floored(Vector2i(12, 12)), FlightSim.schedule_starts(0)
		)
	_w.auto_staff = false
	_gate = AirportGate.new()
	_gate.flights = _w.flights
	_gate.staff = _w.staff
	_port.add_child(_gate)
	_rating = AirportRating.new()
	_rating.clock = _w.clock
	_rating.flights = _w.flights
	_rating.passengers = _w.sim
	_port.add_child(_rating)
	_unlocks = BuildUnlocks.new()
	_unlocks.rating = _rating
	_unlocks.passengers = _w.sim
	_unlocks.manual = true
	_port.add_child(_unlocks)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(20, 20)
	_mode.unlocks = _unlocks
	_mode.require_unlocks = require_unlocks
	_port.add_child(_mode)
	_menu = BuildMenu.new()
	_menu.build_mode = _mode
	_port.add_child(_menu)
	_panel = StaffPanel.new()
	_panel.staff = _w.staff
	_panel.gate = _gate
	_panel.menu = _menu
	_panel.unlocks = _unlocks
	_port.add_child(_panel)


func test_checklist_unmet_rows_have_why_sublines_and_completed_rows_fold_them_away() -> void:
	var card: ChecklistCard = auto_free(ChecklistCard.new())
	var lines := Checklist.opening_lines(
		[AirportGate.Blocker.NO_PATH, AirportGate.Blocker.NO_CHECKIN],
		{"desks": 0, "scanners": 1, "seats": 0, "checkin_staying": 0, "security_staying": 1}
	)
	card.show_lines(Checklist.TITLE_CLOSED, lines)
	var rows := card.rows()
	var unmet_count := lines.filter(func(l: Dictionary) -> bool: return not l["done"]).size()
	assert_int(rows.size()).is_equal(unmet_count)
	assert_int(card.why_texts().size()).is_equal(unmet_count)
	(
		assert_array(Array(card.why_texts()))
		. contains(
			[
				"Passengers check in here before security.",
				"Keeps waiting passengers comfortable.",
			]
		)
	)
	# Checking off a row hides/folds both the row and its why sub-line.
	var done_line := Checklist.line("Place Check-in (Operations)", true, "Should be hidden")
	assert_str(done_line["why"]).is_empty()
	card.show_lines(Checklist.TITLE_CLOSED, [done_line])
	assert_int(card.rows().size()).is_equal(0)
	assert_int(card.why_texts().size()).is_equal(0)


func test_clicking_checklist_row_jumps_to_build_tab_or_staff_panel_and_pulses() -> void:
	_setup_hud(false, true)
	await await_idle_frame()
	var rows := _panel.checklist().row_texts()
	var checkin_idx := Array(rows).find("Place Check-in (Operations)")
	assert_int(checkin_idx).is_greater_equal(0)
	assert_bool(_panel.checklist().press_row(checkin_idx)).is_true()
	assert_bool(_menu.is_tray_open()).is_true()
	assert_int(_menu.open_category()).is_equal(BuildMenu.category_of(BuildMode.Tool.DESK))
	assert_int(_menu.pulsed_tool()).is_equal(BuildMode.Tool.DESK)
	# Now place a check-in desk so the checklist advances to Hire Check-in agent (Staff).
	PassengerTestWorld.place(_w.grid, &"checkin_desk", Vector2i(3, 3), 0)
	_panel.refresh()
	await await_idle_frame()
	var hire_idx := Array(_panel.checklist().row_texts()).find("Hire Check-in agent (Staff)")
	assert_int(hire_idx).is_greater_equal(0)
	assert_bool(_panel.checklist().press_row(hire_idx)).is_true()
	assert_bool(_menu.staff_open).is_true()
	assert_bool(_menu.is_tray_open()).is_false()
	assert_bool(_panel.card().visible).is_true()


func test_pre_open_prep_time_note_shows_on_checklist_and_clock_and_clears_on_open() -> void:
	_setup_hud(false, true)
	var hud := PassengerHud.new()
	hud.clock = _w.clock
	hud.flights = _w.flights
	hud.sim = _w.sim
	hud.build_mode = _mode
	hud.debug_tools = false
	hud.alert_settings_path = SaveTestKit.run_path("day1_prep_alerts")
	hud.departures_settings_path = SaveTestKit.run_path("day1_prep_departures")
	_port.add_child(hud)
	await await_idle_frame()
	var prep_msg := "Prep time — clock starts when staff reach stations"
	assert_int(_w.flights.opened_tick).is_less(0)
	assert_bool(_panel.checklist().prep_note_label().visible).is_true()
	assert_str(_panel.checklist().prep_note_label().text).is_equal(prep_msg)
	assert_str((hud.find_child("Clock", true, false) as Label).tooltip_text).is_equal(prep_msg)
	assert_str((hud.find_child("FlightPanel", true, false) as Control).tooltip_text).is_equal(
		prep_msg
	)
	# Opening the airport clears both the checklist prep note and the clock tooltip.
	assert_bool(_w.flights.open_airport()).is_true()
	_gate.changed.emit()
	hud.refresh()
	assert_bool(_panel.checklist().prep_note_label().visible).is_false()
	assert_str(_panel.checklist().prep_note_label().text).is_empty()
	assert_str((hud.find_child("Clock", true, false) as Label).tooltip_text).is_empty()
	assert_str((hud.find_child("FlightPanel", true, false) as Control).tooltip_text).is_empty()
	DirAccess.remove_absolute(hud.alert_settings_path)
	DirAccess.remove_absolute(hud.departures_settings_path)


func test_staff_panel_role_tooltips_and_shop_role_hidden_until_tier2() -> void:
	_setup_hud(false, true)
	await await_idle_frame()
	for role in StaffPanel.ROLES:
		assert_str(_panel.hire_button(role).tooltip_text).is_not_empty()
		assert_str(_panel.role_tooltip(role)).is_equal(_panel.hire_button(role).tooltip_text)
	# At Tier 1 with unlocks required and no cafe/shop built, SHOP and RAMP are hidden.
	assert_int(_unlocks.tier()).is_equal(BuildUnlocks.START_TIER)
	assert_bool(_panel.is_role_visible(SHOP)).is_false()
	assert_bool(_panel.is_role_visible(CHECKIN)).is_true()
	# Unlocking Tier 2 reveals SHOP cleanly.
	var need_pax := int(BuildUnlocks.TIERS[BuildUnlocks.CAFE_TIER - 1]["passengers"])
	(
		assert_bool(
			(
				_unlocks
				. from_snapshot(
					{
						"tier": BuildUnlocks.CAFE_TIER,
						"made": need_pax,
						"shown": [],
						"seen": [],
						"firsts": [],
					}
				)
			)
		)
		. is_true()
	)
	assert_int(_unlocks.tier()).is_equal(BuildUnlocks.CAFE_TIER)
	assert_bool(_panel.is_role_visible(SHOP)).is_true()
	assert_bool(_panel.is_role_visible(StaffMember.Role.RAMP)).is_true()


func test_shop_role_stays_visible_when_unlocks_not_required() -> void:
	_setup_hud(false, false)
	await await_idle_frame()
	assert_bool(_panel.is_role_visible(SHOP)).is_true()


func test_tier2_milestone_counter_reads_build_unlocks_and_hides_at_tier2() -> void:
	_setup_hud(true, true)
	await await_idle_frame()
	# Hidden while closed; visible once airport opens at Tier 1.
	assert_bool(_panel.checklist().milestone_label().visible).is_false()
	assert_bool(_w.flights.open_airport()).is_true()
	_panel.refresh()
	var need_pax := int(BuildUnlocks.TIERS[BuildUnlocks.CAFE_TIER - 1]["passengers"])
	assert_bool(_panel.checklist().milestone_label().visible).is_true()
	assert_str(_panel.checklist().milestone_label().text).is_equal(
		"Serve 0/%d passengers to unlock Cafe & Baggage" % need_pax
	)
	for i in 7:
		var p := _w.passenger(_w.sim.spawn_now(PassengerTestWorld.FLIGHT))
		_w.sim.outcome.emit(p.id, true)
	assert_str(_panel.checklist().milestone_label().text).is_equal(
		"Serve 7/%d passengers to unlock Cafe & Baggage" % need_pax
	)
	# Reaching Tier 2 hides the Tier-2 milestone line.
	(
		assert_bool(
			(
				_unlocks
				. from_snapshot(
					{
						"tier": BuildUnlocks.CAFE_TIER,
						"made": need_pax,
						"shown": [],
						"seen": [],
						"firsts": [],
					}
				)
			)
		)
		. is_true()
	)
	assert_int(_unlocks.tier()).is_equal(BuildUnlocks.CAFE_TIER)
	assert_bool(_panel.checklist().milestone_label().visible).is_false()


func test_post_opening_hints_and_replayable_hints() -> void:
	var path := SaveTestKit.run_path("day1_hints_replay")
	DirAccess.remove_absolute(path)
	var hints := Hints.new()
	hints.forced_mode = Hints.Mode.PROFILE
	hints.settings_path = path
	add_child(hints)
	auto_free(hints)
	var world := {
		"desks": 1,
		"scanners": 1,
		"arches": 0,
		"shortage_roles": [],
		"hiring_roles": [],
		"max_toilet_need": 0,
		"max_hunger": 0,
		"stalls": 1,
		"cafes": 1,
		"airport_open": false,
		"offers_opened": true,
		"has_scheduled_flights": true,
		"planner_opened": false,
		"mess_count": 0,
		"cleaners_hired": 0,
	}
	hints.advance(Hints.GRACE_S + 0.1, world, [])
	world["airport_open"] = true
	var t := 0.0
	while t < HintRules.HOLD_S + 0.5:
		hints.advance(0.25, world, [])
		t += 0.25
	assert_str(hints.shown_id()).is_equal(HintRules.FLIGHT_PLANNER)
	assert_bool(hints.is_seen(HintRules.FLIGHT_PLANNER)).is_true()
	# Opening planner clears it; then a mess triggers Cleaners hint after MIN_GAP_S.
	world["planner_opened"] = true
	hints.advance(0.25, world, [])
	assert_bool(hints.is_showing()).is_false()
	world["mess_count"] = 1
	t = 0.0
	while t < Hints.MIN_GAP_S + HintRules.HOLD_S + 0.5:
		hints.advance(0.25, world, [])
		t += 0.25
	assert_str(hints.shown_id()).is_equal(HintRules.CLEANERS)
	# Replayable hints: Reset hints is moved to GameMenu Settings, and reset_hints()
	# re-enables and clears seen.
	assert_bool(hints.settings_row().visible).is_true()
	assert_object(hints.find_child("HintsReset", true, false)).is_null()
	hints.set_enabled(false)
	hints.reset_hints()
	assert_bool(hints.is_enabled()).is_true()
	assert_bool(hints.is_seen(HintRules.FLIGHT_PLANNER)).is_false()
	assert_bool(hints.is_seen(HintRules.CLEANERS)).is_false()
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + ".tmp")


func test_all_new_onboarding_strings_are_in_messages_pot_once() -> void:
	PseudoLocale.disable()
	var entries := PotEntries.parse(FileAccess.get_file_as_string("res://locale/messages.pot"))
	var expected := [
		"Passengers walk from the entrance through security to the exit.",
		"Passengers check in here before security.",
		"Clears passengers and bags for the gate.",
		"Opens boarding for your first flight.",
		"Keeps waiting passengers comfortable.",
		"Stations stay closed until an agent is hired.",
		"Prep time — clock starts when staff reach stations",
		"Serve {done}/{need} passengers to unlock Cafe & Baggage",
		"Works check-in desks to tag bags and print boarding passes. Hire 1 per open desk.",
		"Runs cafe, bar, restaurant, and shop counters. Hire once you build a cafe or shop.",
		"Open Planner (P) to view today's schedule or move flights between gates.",
		"Terminal messes lower passenger mood. Hire a Cleaner on the Staff card to keep things tidy.",
	]
	for msg in expected:
		assert_int(PotEntries.complete(entries, "", msg)).override_failure_message(msg).is_equal(1)
