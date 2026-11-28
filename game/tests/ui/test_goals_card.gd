class_name TestGoalsCard
extends GdUnitTestSuite
## UI layout, LeftColumn yielding, compact auto-collapse, and zero-overlap tests
## for AirportGoalsCard (`game/ui/goals_card.gd`).

const SEED := 50_202_612
const LAYOUTS := [Vector2i(1920, 1080), Vector2i(1536, 864), Vector2i(1280, 720)]

var _port: SubViewport
var _main: Node
var _hud: PassengerHud
var _alert_path := SaveTestKit.run_path("goals_card_alerts")
var _departures_path := SaveTestKit.run_path("goals_card_departures")
var _mood_path := SaveTestKit.run_path("goals_card_mood")
var _shown_before := false


func before() -> void:
	_shown_before = IntroDialogue.shown_this_session
	IntroDialogue.shown_this_session = true
	_port = SubViewport.new()
	_port.size = LAYOUTS[1]
	add_child(_port)
	_main = load(SaveTestKit.MAIN).instantiate()
	(_main.get_node("SimClock") as SimClock).seed_rng(SEED)
	(_main.get_node("SimClock") as SimClock).set_paused(true)
	_hud = _main.get_node("PassengerHud") as PassengerHud
	_hud.alert_settings_path = _alert_path
	_hud.departures_settings_path = _departures_path
	(_main.get_node("MoodOverlay") as MoodOverlay).settings_path = _mood_path
	_port.add_child(_main)
	await _settle()


func after() -> void:
	IntroDialogue.shown_this_session = _shown_before
	if _port != null:
		_port.free()
		_port = null
	_main = null
	_hud = null
	for path in [_alert_path, _departures_path, _mood_path]:
		for suffix in ["", ".tmp"]:
			if FileAccess.file_exists(path + suffix):
				DirAccess.remove_absolute(path + suffix)


func _settle(frames := 4) -> void:
	for _i in frames:
		await get_tree().process_frame


func _prepare_open_without_checklist() -> void:
	var flights := _main.get_node("FlightSim") as FlightSim
	var mode := _main.get_node("BuildMode") as BuildMode
	var unlocks := _main.get_node("BuildUnlocks") as BuildUnlocks
	var staff := _main.get_node("Staff") as StaffSim
	_hud.press_starter_terminal()
	StaffTestKit.staff_all(staff)
	for _i in 2000:
		SaveTestKit.step(_main)
		if flights.opened_tick >= 0:
			break
	assert_int(flights.opened_tick).is_greater_equal(0)
	# Clear the Tier-2 milestone + starter cue + gaps so ChecklistCard hides.
	mode.require_unlocks = false
	var sp := _main.get_node("StaffPanel") as StaffPanel
	sp._open_cue = ""
	sp._gaps.clear()
	unlocks.set_unlock_all(true)
	sp.refresh()
	await _settle()


func test_hidden_while_closed_or_checklist_visible_and_yields_cleanly() -> void:
	var card := _hud.find_child("AirportGoalsCard", false, false) as AirportGoalsCard
	var flights := _main.get_node("FlightSim") as FlightSim
	var sp := _main.get_node("StaffPanel") as StaffPanel
	assert_object(card).is_not_null()

	# 1. Airport closed -> hidden.
	assert_int(flights.opened_tick).is_less(0)
	assert_bool(card.is_visible_in_tree()).is_false()

	# 2. Airport opens while ChecklistCard is visible -> still hidden.
	flights.open_airport()
	sp.refresh()
	await _settle()
	assert_bool(sp.is_checklist_visible()).is_true()
	assert_bool(card.is_visible_in_tree()).is_false()

	# 3. In Tier 1 with AirportGoals mounted, the passive Tier-2 milestone line is suppressed
	# so AirportGoalsCard takes the LeftColumn slot immediately once opening lines/gaps clear.
	_hud.press_starter_terminal()
	StaffTestKit.staff_all(_main.get_node("Staff"))
	for _i in 2000:
		SaveTestKit.step(_main)
		if flights.opened_tick >= 0:
			break
	assert_int(flights.opened_tick).is_greater_equal(0)
	var unlocks := _main.get_node("BuildUnlocks") as BuildUnlocks
	assert_int(unlocks.tier()).is_equal(1)
	sp._open_cue = ""
	sp._gaps.clear()
	sp.refresh()
	await _settle()
	assert_str(sp.checklist().milestone_label().text).is_empty()
	assert_bool(sp.checklist().milestone_label().visible).is_false()
	assert_bool(sp.is_checklist_visible()).is_false()
	assert_bool(card.is_visible_in_tree()).is_true()
	assert_int(card.row_count()).is_equal(3)
	assert_str(card.title_label().text).is_equal("Airport Goals")

	# 4. If ChecklistCard re-shows (e.g. a new gap / hint), AirportGoalsCard yields cleanly.
	sp.checklist().show_lines("Your airport needs", [Checklist.line("Need a gate", false)])
	sp._hint_box.visible = true
	card.sync()
	await _settle()
	assert_bool(card.is_visible_in_tree()).is_false()

	sp.checklist().show_lines("", [])
	sp._open_cue = ""
	sp._gaps.clear()
	sp.refresh()
	await _settle()
	assert_bool(card.is_visible_in_tree()).is_true()


func test_live_counters_completion_toast_and_manual_collapse() -> void:
	await _prepare_open_without_checklist()
	var card := _hud.find_child("AirportGoalsCard", false, false) as AirportGoalsCard
	var sim := _main.get_node("PassengerSim") as PassengerSim
	var stack := _hud.find_child("AlertStack", false, false) as AlertStack

	# Progress counter updates live.
	var p1 := Passenger.new()
	p1.id = 7701
	p1.flight_id = "F"
	p1.stage = Passenger.Stage.MADE
	sim._passengers.append(p1)
	sim._by_id[p1.id] = p1
	sim.outcome.emit(p1.id, true)
	await _settle()
	var row0 := card.rows_container().get_child(0)
	var counter0 := row0.find_child("GoalCounter", true, false) as Label
	assert_str(counter0.text).is_equal("1/10")

	# Manual collapse / expand.
	card.toggle_button().pressed.emit()
	await _settle()
	assert_bool(card.is_collapsed()).is_true()
	assert_bool(card.rows_container().visible).is_false()
	assert_str(card.title_label().text).is_equal("Goals (3)")
	card.toggle_button().pressed.emit()
	await _settle()
	assert_bool(card.is_collapsed()).is_false()
	assert_bool(card.rows_container().visible).is_true()

	# Completing a goal posts non-modal green AlertStack notice.
	for i in 9:
		var p := Passenger.new()
		p.id = 7710 + i
		p.flight_id = "F"
		p.stage = Passenger.Stage.MADE
		sim._passengers.append(p)
		sim._by_id[p.id] = p
		sim.outcome.emit(p.id, true)
	await _settle()
	var toast := stack.notice_card(&"goal_board_10_pax")
	assert_object(toast).is_not_null()
	assert_bool(toast.is_visible_in_tree()).is_true()


func test_compact_viewport_auto_collapse_and_zero_overlaps_across_layouts() -> void:
	await _prepare_open_without_checklist()
	var card := _hud.find_child("AirportGoalsCard", false, false) as AirportGoalsCard
	var board := _hud.find_child("DeparturesBoard", false, false) as DeparturesBoard
	var depart_panel := _hud.find_child("DeparturesPanel", true, false) as Control
	var money := _main.find_child("MoneySlot", true, false) as Control
	var build_menu := _main.get_node("BuildMenu") as BuildMenu
	var bar := build_menu.bar()

	# Compact viewport (1024x576 = 1280x720 @ 1.25): opening DeparturesBoard auto-collapses card.
	_port.size = Vector2i(1024, 576)
	board.set_shown(false)
	await _settle()
	assert_bool(card.is_collapsed()).is_false()
	var expanded_h := card.get_combined_minimum_size().y
	assert_float(expanded_h).is_greater(LeftColumn.CARD_RESERVE)

	board.set_shown(true)
	await _settle()
	assert_bool(board.is_panel_visible()).is_true()
	assert_bool(card.is_auto_collapsed()).is_true()
	assert_bool(card.is_collapsed()).is_true()
	assert_bool(card.get_global_rect().intersects(depart_panel.get_global_rect())).is_false()
	assert_float(card.get_global_rect().position.y).is_greater_equal(
		depart_panel.get_global_rect().end.y + float(HudLayout.GAP) - 1.0
	)
	assert_float(card.get_global_rect().end.y).is_less_equal(
		bar.get_global_rect().position.y - float(HudLayout.GAP) + 1.0
	)

	# Closing DeparturesBoard expands back automatically when not manually collapsed.
	board.set_shown(false)
	await _settle()
	assert_bool(card.is_auto_collapsed()).is_false()
	assert_bool(card.is_collapsed()).is_false()

	# Zero overlaps at 1280x720, 1536x864, 1920x1080 with DeparturesBoard, Tray, and TopRow sheets.
	var runway_card := _main.get_node("RunwayCard") as RunwayCard
	for layout: Vector2i in LAYOUTS:
		_port.size = layout
		board.set_shown(true)
		build_menu.press_category(0)
		await _settle()
		var card_rect := card.get_global_rect()
		assert_bool(Rect2(Vector2.ZERO, Vector2(layout)).encloses(card_rect)).is_true()
		assert_bool(card_rect.intersects(money.get_global_rect())).is_false()
		assert_bool(card_rect.intersects(depart_panel.get_global_rect())).is_false()
		assert_bool(card_rect.intersects(bar.get_global_rect())).is_false()
		assert_bool(card_rect.intersects(build_menu.tray().get_global_rect())).is_false()
		runway_card.open()
		await _settle()
		var sheet := _main.find_child("RunwaySheet", true, false) as Control
		assert_bool(card_rect.intersects(sheet.get_global_rect())).is_false()
		runway_card.close()
		build_menu.press_category(0)
		board.set_shown(false)
		await _settle()
