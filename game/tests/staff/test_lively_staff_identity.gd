class_name TestLivelyStaffIdentity
extends GdUnitTestSuite
## Acceptance tests for Lively Staff 1/3 (board 4f055dac, decision 94ec8fbe):
## deterministic real names, 1-2 cozy quirks, contextual live thoughts,
## StaffSnapshot v11 / SaveGame v45 round-trip + validation, StaffPanel
## clickable real-name rows, bottom-right StaffInspect card, and in-world
## staff hover + click selection.

const SEED := 4_070_093
const LAYOUTS := [Vector2i(1920, 1080), Vector2i(1536, 864), Vector2i(1280, 720)]

var _port: SubViewport
var _main: Node
var _hud: PassengerHud
var _mode: BuildMode
var _sim: PassengerSim
var _staff: StaffSim
var _staff_views: StaffCharacters
var _views: PassengerViews
var _hover: HoverTarget
var _rig: TycoonCamera
var _eye: Camera3D
var _menu: BuildMenu
var _staff_panel: StaffPanel
var _pax_inspect: PassengerInspect
var _staff_inspect: StaffInspect
var _game_menu: GameMenu
var _clock: SimClock
var _shown_before := false

var _alert_path := SaveTestKit.run_path("lively_staff_alerts")
var _departures_path := SaveTestKit.run_path("lively_staff_departures")
var _mood_path := SaveTestKit.run_path("lively_staff_mood")
var _camera_path := SaveTestKit.run_path("lively_staff_camera")

var _w: PassengerTestWorld
var _other: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self
	_shown_before = IntroDialogue.shown_this_session
	IntroDialogue.shown_this_session = true
	_port = SubViewport.new()
	_port.size = LAYOUTS[0]
	add_child(_port)
	_main = load(SaveTestKit.MAIN).instantiate()
	_clock = _main.get_node("SimClock") as SimClock
	_clock.seed_rng(SEED)
	_clock.set_paused(true)
	_hud = _main.get_node("PassengerHud") as PassengerHud
	_hud.alert_settings_path = _alert_path
	_hud.departures_settings_path = _departures_path
	(_main.get_node("MoodOverlay") as MoodOverlay).settings_path = _mood_path
	(_main.get_node("TycoonCamera") as TycoonCamera).settings_path = _camera_path
	(_main.get_node("IncidentDirector") as IncidentDirector).set_enabled(false)
	_port.add_child(_main)
	_mode = _main.get_node("BuildMode") as BuildMode
	_sim = _main.get_node("PassengerSim") as PassengerSim
	_staff = _main.get_node("Staff") as StaffSim
	_staff_views = _main.get_node("StaffCharacters") as StaffCharacters
	_views = _main.get_node("PassengerViews") as PassengerViews
	_hover = _main.get_node("HoverTarget") as HoverTarget
	_rig = _main.get_node("TycoonCamera") as TycoonCamera
	_eye = _main.get_node("TycoonCamera/Camera3D") as Camera3D
	_menu = _main.get_node("BuildMenu") as BuildMenu
	_staff_panel = _main.get_node("StaffPanel") as StaffPanel
	_game_menu = _main.get_node("GameMenu") as GameMenu
	_pax_inspect = _hud.find_child("PassengerInspect", true, false) as PassengerInspect
	_staff_inspect = _hud.find_child("StaffInspect", true, false) as StaffInspect
	_hud.press_starter_terminal()
	await _settle()


func after() -> void:
	PassengerTestWorld.tracker = null
	IntroDialogue.shown_this_session = _shown_before
	PseudoLocale.disable()
	if _port != null:
		_port.free()
		_port = null
	_main = null
	for path in [_alert_path, _departures_path, _mood_path, _camera_path]:
		for suffix in ["", ".tmp"]:
			if FileAccess.file_exists(path + suffix):
				DirAccess.remove_absolute(path + suffix)


func after_test() -> void:
	PseudoLocale.disable()
	for w in [_w, _other]:
		if w != null:
			w.free_all()
	_w = null
	_other = null
	if _main == null:
		return
	_game_menu.close()
	_mode.set_tool(BuildMode.Tool.NONE)
	_mode.pointer_override = Vector2(-1.0, -1.0)
	_hover.pointer_override = null
	_rig.set_process(true)
	_rig.stop_follow()
	if _menu.staff_open:
		_menu.press_staff()
	if _menu.is_tray_open():
		_menu.press_category(_menu.open_category())
	_views.select(0)
	_hud._built.clear()
	_staff_inspect.press_close()
	_hud.set_debug_open(false)
	for id in _staff.member_ids():
		var m := _staff.get_member(id)
		if m != null:
			_staff.fire(m.role)
	(
		_staff
		. from_snapshot(
			{
				"save_version": StaffSim.SAVE_VERSION,
				"next_id": _staff.member_ids().size() + 1,
				"members": [],
				"closed": [],
				"faults": [],
			}
		)
	)
	_staff_views.sync(true)
	var stack := _hud.find_child("AlertStack", false, false) as AlertStack
	if stack != null:
		stack.reset()
	_port.size = LAYOUTS[0]
	await _settle(2)


func _settle(frames := 3) -> void:
	for _i in frames:
		await get_tree().process_frame


func _ref_world(world_seed := 12345) -> PassengerTestWorld:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	var w := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	w.auto_staff = false
	w.clock.seed_rng(world_seed)
	return w


func test_names_quirks_determinism_and_contextual_live_thoughts() -> void:
	# 1. Deterministic real names & no duplicates across early hires.
	var seen_names := {}
	for i in range(1, 35):
		var name_a := StaffNames.display_name_for(i, 777)
		var name_b := StaffNames.display_name_for(i, 777)
		assert_str(name_a).is_not_empty()
		assert_str(name_a).contains(" ")
		assert_str(name_a).is_equal(name_b)
		assert_bool(seen_names.has(name_a)).is_false()
		seen_names[name_a] = true
		var quirks := StaffNames.quirks_for(i, 777)
		assert_int(quirks.size()).is_between(1, 2)
		for q in quirks:
			assert_str(q).is_not_empty()

	_w = _ref_world(9001)
	var id_ci := _w.staff.hire(StaffMember.Role.CHECKIN)
	var m := _w.staff.get_member(id_ci)
	assert_str(m.display_name).is_equal(StaffNames.display_name_for(id_ci, 9001))
	assert_int(m.quirks.size()).is_between(1, 2)

	# 2. Contextual live thoughts across states.
	var t_idle := StaffNames.live_thought(_w.sim, m)
	assert_str(t_idle).is_equal("Ready and waiting for a station assignment.")

	# Walking to station.
	m.state = StaffMember.State.TO_STATION
	assert_str(StaffNames.live_thought(_w.sim, m)).is_equal("Heading over to my check-in desk.")

	# On duty waiting (L1) vs newly trained L2 / L3.
	var desk := _w.sim.layout.desks[0]
	m.station = desk
	m.at = _w.staff.spot_of(desk)
	m.state = StaffMember.State.ON_DUTY
	assert_str(StaffNames.live_thought(_w.sim, m)).is_equal(
		"Desk is open, ready for the next flyer."
	)
	assert_bool(_w.staff.train(m.id)).is_true()
	assert_str(StaffNames.live_thought(_w.sim, m)).is_equal(
		"Loving the new skills from Level 2 training."
	)
	assert_bool(_w.staff.train(m.id)).is_true()
	assert_str(StaffNames.live_thought(_w.sim, m)).is_equal(
		"Mastered the station, Level 3 feels effortless."
	)

	# Low energy needing a break.
	m.energy = StaffMember.TIRED_THRESHOLD
	assert_str(StaffNames.live_thought(_w.sim, m)).is_equal(
		"Running low on steam, hoping for a break soon."
	)

	# Walking to Break Room & resting in Break Room.
	m.state = StaffMember.State.TO_BREAK
	assert_str(StaffNames.live_thought(_w.sim, m)).is_equal(
		"Could really use a coffee in the Break Room."
	)
	m.state = StaffMember.State.ON_BREAK
	m.energy = 50
	assert_str(StaffNames.live_thought(_w.sim, m)).is_equal("Putting my feet up for a minute.")

	# Fired / leaving mid-service and walking out.
	m.leaving = true
	assert_str(StaffNames.live_thought(_w.sim, m)).is_equal(
		"Finishing up this last one before I head out."
	)
	m.leaving = false
	m.state = StaffMember.State.WALKING_OUT
	assert_str(StaffNames.live_thought(_w.sim, m)).is_equal(
		"Heading for the exit. Good luck, team!"
	)

	# Cleaner cleaning mess vs bin.
	var cleaner := _w.staff.get_member(_w.staff.hire(StaffMember.Role.CLEANER))
	cleaner.state = StaffMember.State.ON_DUTY
	cleaner.job = 1
	cleaner.job_bin = false
	assert_str(StaffNames.live_thought(_w.sim, cleaner)).is_equal(
		"Cleaning up this mess, spotless in a jiffy."
	)
	cleaner.job_bin = true
	assert_str(StaffNames.live_thought(_w.sim, cleaner)).is_equal(
		"Emptying this full bin before it overflows."
	)

	# Ramp patrolling apron vs shuttle.
	var ramp := _w.staff.get_member(_w.staff.hire(StaffMember.Role.RAMP))
	assert_str(StaffNames.live_thought(_w.sim, ramp)).is_equal(
		"Patrolling the apron, checking stands and cones."
	)
	ramp.ramp_job = StaffMember.RampJob.SHUTTLE
	assert_str(StaffNames.live_thought(_w.sim, ramp)).is_equal(
		"Cart's loaded, heading across the apron."
	)

	# Translation wrapping check under PseudoLocale.
	PseudoLocale.enable(0.4)
	for q in StaffNames.quirks_for(id_ci, 9001):
		assert_str(q).starts_with("[")
	assert_str(StaffNames.live_thought(_w.sim, ramp)).starts_with("[")
	PseudoLocale.disable()


func test_staff_snapshot_and_save_game_round_trip_and_refusals() -> void:
	assert_int(StaffSim.SAVE_VERSION).is_greater_equal(11)
	assert_int(SaveGame.SAVE_VERSION).is_greater_equal(45)

	_w = _ref_world(54321)
	var id1 := _w.staff.hire(StaffMember.Role.CHECKIN)
	var id2 := _w.staff.hire(StaffMember.Role.SECURITY)
	var m1 := _w.staff.get_member(id1)
	var m2 := _w.staff.get_member(id2)
	var expected_name1 := m1.display_name
	var expected_quirks1 := m1.quirks.duplicate()
	var expected_name2 := m2.display_name
	var expected_quirks2 := m2.quirks.duplicate()
	_w.run_to(80)

	# Save/load preserves display_name and quirks deterministically.
	var saved_text := StaffTestKit.save_text(_w)
	_other = StaffTestKit.load_world(saved_text)
	assert_object(_other).is_not_null()
	var lm1 := _other.staff.get_member(id1)
	var lm2 := _other.staff.get_member(id2)
	assert_str(lm1.display_name).is_equal(expected_name1)
	assert_array(lm1.quirks).is_equal(expected_quirks1)
	assert_str(lm2.display_name).is_equal(expected_name2)
	assert_array(lm2.quirks).is_equal(expected_quirks2)

	# Rejects previous save_version and malformed display_name / quirks atomically.
	var good: Dictionary = JSON.parse_string(JSON.stringify(_w.staff.to_snapshot()))
	var before_sig := StaffTestKit.signature(_w.staff)

	var old_ver := good.duplicate(true)
	old_ver["save_version"] = StaffSim.SAVE_VERSION - 1
	assert_bool(_w.staff.from_snapshot(old_ver)).is_false()

	for bad_name in ["", "   ", 123, null]:
		var bad := good.duplicate(true)
		bad["members"][0]["display_name"] = bad_name
		assert_bool(_w.staff.from_snapshot(bad)).is_false()

	var missing_name := good.duplicate(true)
	missing_name["members"][0].erase("display_name")
	assert_bool(_w.staff.from_snapshot(missing_name)).is_false()

	var bad_quirks_cases: Array = [
		[],
		["Early bird", "Neat freak", "Fast walker"],
		[42],
		[""],
		"Early bird",
		["Hates passengers"],
		[" Early bird "],
		["Early bird", "Early bird"],
	]
	for bad_quirks in bad_quirks_cases:
		var bad := good.duplicate(true)
		bad["members"][0]["quirks"] = bad_quirks
		assert_bool(_w.staff.from_snapshot(bad)).is_false()

	var missing_quirks := good.duplicate(true)
	missing_quirks["members"][0].erase("quirks")
	assert_bool(_w.staff.from_snapshot(missing_quirks)).is_false()

	# Live state for ALL members remained untouched after all refusals.
	assert_str(StaffTestKit.signature(_w.staff)).is_equal(before_sig)
	assert_str(_w.staff.get_member(id1).display_name).is_equal(expected_name1)
	assert_array(_w.staff.get_member(id1).quirks).is_equal(expected_quirks1)
	assert_str(_w.staff.get_member(id2).display_name).is_equal(expected_name2)
	assert_array(_w.staff.get_member(id2).quirks).is_equal(expected_quirks2)

	# Full SaveGame snapshot / load_world round-trip and v44 refusal.
	SaveTestKit.step(_main)
	var save := _main.get_node("SaveGame") as SaveGame
	var g1 := _staff.hire(StaffMember.Role.CHECKIN)
	var g2 := _staff.hire(StaffMember.Role.SECURITY)
	var gm1 := _staff.get_member(g1)
	var gm2 := _staff.get_member(g2)
	var g_name1 := gm1.display_name
	var g_quirks1 := gm1.quirks.duplicate()
	var g_name2 := gm2.display_name
	var g_quirks2 := gm2.quirks.duplicate()
	var game_snap: Dictionary = JSON.parse_string(JSON.stringify(save.snapshot(), "", true, true))
	assert_int(int(game_snap["save_version"])).is_equal(SaveGame.SAVE_VERSION)
	var g3 := _staff.hire(StaffMember.Role.CLEANER)
	var g_name3 := _staff.get_member(g3).display_name
	var g_quirks3 := _staff.get_member(g3).quirks.duplicate()

	var v44 := game_snap.duplicate(true)
	v44["save_version"] = 44
	assert_bool(save.load_world(v44)).is_false()
	assert_int(_staff.member_ids().size()).is_equal(3)
	assert_str(_staff.get_member(g1).display_name).is_equal(g_name1)
	assert_array(_staff.get_member(g1).quirks).is_equal(g_quirks1)
	assert_str(_staff.get_member(g3).display_name).is_equal(g_name3)
	assert_array(_staff.get_member(g3).quirks).is_equal(g_quirks3)

	assert_bool(save.load_world(game_snap)).is_true()
	assert_int(_staff.member_ids().size()).is_equal(2)
	assert_str(_staff.get_member(g1).display_name).is_equal(g_name1)
	assert_array(_staff.get_member(g1).quirks).is_equal(g_quirks1)
	assert_str(_staff.get_member(g2).display_name).is_equal(g_name2)
	assert_array(_staff.get_member(g2).quirks).is_equal(g_quirks2)


func test_staff_panel_shows_real_names_and_opens_staff_inspect() -> void:
	var id := _staff.hire(StaffMember.Role.CHECKIN)
	var m := _staff.get_member(id)
	_menu.press_staff()
	await _settle()

	var row_btn := _staff_panel.member_button(id)
	assert_object(row_btn).is_not_null()
	assert_str(row_btn.text).is_equal(m.display_name)
	assert_str(row_btn.text).not_contains("Agent #")

	var emitted: Array[int] = []
	_staff_panel.member_selected.connect(func(mid: int) -> void: emitted.append(mid))
	row_btn.pressed.emit()
	await _settle()

	assert_array(emitted).is_equal([id])
	assert_bool(_staff_inspect.visible).is_true()
	assert_str(_staff_inspect.name_text()).is_equal(m.display_name)
	assert_str(_staff_inspect.role_text()).contains("Check-in agent")
	assert_str(_staff_inspect.role_text()).contains("Lv. 1")
	assert_str(_staff_inspect.quirks_text()).contains(StaffNames.translate_quirk(m.quirks[0]))


func test_staff_inspect_docks_bottom_right_switches_updates_focuses_and_esc_closes() -> void:
	var sid := _staff.hire(StaffMember.Role.CHECKIN)
	var m := _staff.get_member(sid)
	var desk := _sim.layout.desks[0]
	m.station = desk
	m.at = _staff.spot_of(desk)
	m.clear_path()
	m.state = StaffMember.State.ON_DUTY
	_staff.rederive()
	_staff_views.sync(true)
	await _settle()

	# Open StaffInspect via StaffPanel click.
	_menu.press_staff()
	await _settle()
	_staff_panel.member_button(sid).pressed.emit()
	await _settle()

	# Zero overlap across all 3 standard HUD layouts (with DebugPanel + AlertStack + StaffCard).
	var stack := _hud.find_child("AlertStack", false, false) as AlertStack
	var notice := OfferPanel.coral_card(&"staff_inspect_overlap", "Notice", "Details")
	stack.post_notice(&"staff_inspect_overlap", notice, 0.0, "Notice", "Details")
	var bar := _menu.bar()
	var left_hint := _staff_panel.hint_card()
	_hud.set_debug_open(true)
	var debug_corner := _hud.find_child("DebugCorner", true, false) as Control
	var debug_panel := _hud.find_child("DebugPanel", true, false) as Control

	for layout: Vector2i in LAYOUTS:
		_port.size = layout
		await _settle()
		var sr := _staff_inspect.get_global_rect()
		assert_bool(_staff_inspect.is_visible_in_tree()).is_true()
		assert_float(sr.end.x).is_equal_approx(float(layout.x - HudLayout.MARGIN), 1.0)
		assert_float(sr.position.x).is_greater_equal(float(layout.x) * 0.5)
		assert_bool(sr.intersects(bar.get_global_rect())).is_false()
		assert_bool(sr.intersects(debug_corner.get_global_rect())).is_false()
		assert_bool(sr.intersects(debug_panel.get_global_rect())).is_false()
		if _staff_panel.card().is_visible_in_tree():
			assert_bool(sr.intersects(_staff_panel.card().get_global_rect())).is_false()
		if left_hint.is_visible_in_tree():
			assert_bool(sr.intersects(left_hint.get_global_rect())).is_false()
		var alert_r := stack.room_rect()
		if alert_r.has_area():
			assert_bool(sr.intersects(alert_r)).is_false()

	_port.size = LAYOUTS[0]
	_menu.press_staff()
	_hud.set_debug_open(false)
	await _settle()

	# Open BuildTray + StatusCard clearance across layouts.
	_menu.focus_tool(BuildMode.Tool.DESK)
	await _settle()
	for layout: Vector2i in LAYOUTS:
		_port.size = layout
		await _settle()
		var sr := _staff_inspect.get_global_rect()
		assert_bool(_staff_inspect.is_visible_in_tree()).is_true()
		assert_bool(_menu.tray().is_visible_in_tree()).is_true()
		assert_bool(sr.intersects(_menu.tray().get_global_rect())).is_false()
		if _menu.status_card().is_visible_in_tree():
			assert_bool(sr.intersects(_menu.status_card().get_global_rect())).is_false()
	_port.size = LAYOUTS[0]
	_mode.set_tool(BuildMode.Tool.NONE)
	_menu.press_category(0)
	await _settle()

	# Live updates: energy, training, and thought update cleanly without flicker.
	assert_str(_staff_inspect.energy_text()).is_equal("Energy 100%")
	m.energy = 20
	_staff.train(sid, null)
	_hud.refresh()
	await _settle()
	assert_str(_staff_inspect.energy_text()).is_equal("Energy 20%")
	assert_str(_staff_inspect.role_text()).contains("Lv. 2")
	assert_str(_staff_inspect.thought_text()).contains(
		"Running low on steam, hoping for a break soon."
	)

	# Focus button engages camera follow on StaffCharacters.follow_anchor.
	_staff_inspect.focus_button().pressed.emit()
	await _settle(2)
	assert_bool(_rig.is_following()).is_true()
	assert_int(_staff_views.selected_id).is_equal(sid)

	# Returning followed staff to pool (view released) closes StaffInspect & stops follow.
	m.station = 0
	m.at = StaffMember.NO_CELL
	m.clear_path()
	m.state = StaffMember.State.IDLE
	_staff.rederive()
	_staff_views.sync(true)
	_hud.refresh()
	await _settle()
	assert_bool(_staff_inspect.visible).is_false()
	assert_int(_staff_views.selected_id).is_equal(0)
	assert_bool(_rig.is_following()).is_false()

	# Re-seat & follow, then go OFF_SHIFT -> closes StaffInspect & stops follow.
	m.station = desk
	m.at = _staff.spot_of(desk)
	m.clear_path()
	m.state = StaffMember.State.ON_DUTY
	_staff.rederive()
	_staff_views.sync(true)
	_hud._on_staff_member_selected(sid)
	_staff_inspect.focus_button().pressed.emit()
	await _settle(2)
	assert_bool(_staff_inspect.visible).is_true()
	assert_bool(_rig.is_following()).is_true()
	m.station = 0
	m.at = StaffMember.NO_CELL
	m.clear_path()
	m.state = StaffMember.State.OFF_SHIFT
	_staff.rederive()
	_staff_views.sync(true)
	_hud.refresh()
	await _settle()
	assert_bool(_staff_inspect.visible).is_false()
	assert_int(_staff_views.selected_id).is_equal(0)
	assert_bool(_rig.is_following()).is_false()

	# Re-seat & follow, then fire mid-service (leaving = true) -> closes StaffInspect & stops follow.
	m.station = desk
	m.at = _staff.spot_of(desk)
	m.clear_path()
	m.state = StaffMember.State.ON_DUTY
	_staff.rederive()
	_staff_views.sync(true)
	_hud._on_staff_member_selected(sid)
	_staff_inspect.focus_button().pressed.emit()
	await _settle(2)
	assert_bool(_staff_inspect.visible).is_true()
	assert_bool(_rig.is_following()).is_true()
	m.leaving = true
	_hud.refresh()
	await _settle()
	assert_bool(_staff_inspect.visible).is_false()
	assert_int(_staff_views.selected_id).is_equal(0)
	assert_bool(_rig.is_following()).is_false()
	m.leaving = false
	_staff_views.sync(true)
	_menu.press_staff()
	await _settle()
	_staff_panel.member_button(sid).pressed.emit()
	await _settle()
	_menu.press_staff()
	await _settle()

	# Mutual exclusivity: selecting a passenger hides StaffInspect and shows PassengerInspect.
	var pid := _sim.spawn_now("GMF101")
	_views.select(pid)
	_hud.refresh()
	await _settle()
	assert_bool(_staff_inspect.visible).is_false()
	assert_bool(_pax_inspect.visible).is_true()
	assert_bool(_pax_inspect.shows_passenger()).is_true()

	# Selecting a built item hides StaffInspect.
	_views.select(0)
	_staff_panel.member_button(sid).pressed.emit()
	await _settle()
	assert_bool(_staff_inspect.visible).is_true()
	_hud._built.select_object(desk)
	_hud.refresh()
	await _settle()
	assert_bool(_staff_inspect.visible).is_false()
	assert_bool(_pax_inspect.built_card.visible).is_true()

	# Esc closes StaffInspect without opening GameMenu.
	_hud._built.clear()
	_staff_panel.member_button(sid).pressed.emit()
	await _settle()
	assert_bool(_staff_inspect.visible).is_true()
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	_port.push_input(esc, true)
	await _settle()
	assert_bool(_staff_inspect.visible).is_false()
	assert_bool(_game_menu.is_open()).is_false()


func test_in_world_staff_hover_and_click_without_blocking_tools_or_passengers() -> void:
	var sid := _staff.hire(StaffMember.Role.CHECKIN)
	var m := _staff.get_member(sid)
	var desk := _sim.layout.desks[0]
	var spot := _staff.spot_of(desk)
	m.station = desk
	m.at = spot
	m.clear_path()
	m.state = StaffMember.State.ON_DUTY
	_staff.rederive()
	_staff.staff_changed.emit()
	_staff_views.sync(true)
	_staff_views.draw()
	await _settle()

	var staff_world := _mode.grid.cell_to_world(spot)
	_rig.set_process(false)
	_eye.look_at_from_position(staff_world + Vector3(0.0, 26.0, 4.0), staff_world)
	await _settle(2)

	var click_pos := _eye.unproject_position(staff_world + Vector3(0.0, 0.9, 0.0))

	# 1. Hovering staff in Tool.NONE shows caption and sets hovered_staff().
	_mode.set_tool(BuildMode.Tool.NONE)
	_hover.pointer_override = click_pos
	_hover.refresh()
	assert_int(_hover.hovered_staff()).is_equal(sid)
	assert_bool(_hover.tooltip().visible).is_true()
	assert_str(_hover.tooltip().text()).is_equal(StaffNames.hover_caption(_sim, m))

	# 2. Clicking staff in Tool.NONE selects them and opens StaffInspect.
	_push_click(click_pos)
	await _settle(2)
	assert_bool(_staff_inspect.visible).is_true()
	assert_str(_staff_inspect.name_text()).is_equal(m.display_name)
	assert_int(_staff_views.selected_id).is_equal(sid)

	# 3. Clicking with an active build tool does NOT select staff or clear the tool.
	_staff_inspect.press_close()
	await _settle()
	_mode.set_tool(BuildMode.Tool.WALL)
	_hover.refresh()
	assert_int(_hover.hovered_staff()).is_equal(0)
	_push_click(click_pos)
	await _settle()
	assert_bool(_staff_inspect.visible).is_false()
	assert_int(_mode.tool).is_equal(BuildMode.Tool.WALL)

	# 4. Passenger clicking still takes priority over staff when a passenger stands there.
	_mode.set_tool(BuildMode.Tool.NONE)
	var pid := _sim.spawn_now("GMF101")
	_views.sync()
	var p_node := _views.node_for(pid)
	assert_object(p_node).is_not_null()
	_views._prev[pid] = staff_world
	_views._cur[pid] = staff_world
	p_node.position = staff_world
	_views.draw()
	_hover.pointer_override = click_pos
	_hover.refresh()
	assert_int(_hover.hovered_passenger()).is_equal(pid)
	assert_int(_hover.hovered_staff()).is_equal(0)
	_push_click(click_pos)
	await _settle(2)
	assert_int(_views.selected_id).is_equal(pid)
	assert_bool(_pax_inspect.visible).is_true()
	assert_bool(_staff_inspect.visible).is_false()


func _push_click(screen: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = screen
	motion.global_position = screen
	_mode.pointer_override = screen
	_port.push_input(motion, true)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = screen
	click.global_position = screen
	_port.push_input(click, true)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = screen
	release.global_position = screen
	_port.push_input(release, true)
