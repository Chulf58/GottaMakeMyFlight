class_name TestLeftColumn
extends GdUnitTestSuite
## The top-left column (decisions hud-grid-and-rails-one-spacing-grid-centred-
## top-row-right-ra part 4 and checklist-card-moves-to-the-top-left-column-
## slim-at-304-px-t): Mood, Departures and Hints are equal toggles stacked on
## the 16 px margin under the money row, the departures list opens under them,
## and the checklist card and the first-time hint card sit under that, 304 px
## wide, with ticked lines folded away. Templates sits on the same margin.
## The layout is 1536x864 for any 16:9 window (canvas_items stretch 1.25).

const SEED := 4_070_093
## The money row: on the margin, BUTTON_H high.
const MONEY_ROW_BOTTOM := HudLayout.MARGIN + HudLayout.BUTTON_H

var _settings_path := SaveTestKit.run_path("left_column_alerts")
var _hints_path := SaveTestKit.run_path("left_column_hints")
var _mood_path := SaveTestKit.run_path("left_column_mood")
var _departures_path := SaveTestKit.run_path("left_column_departures")

var _main: Node
var _hud: PassengerHud
var _staff: StaffPanel
var _sim: PassengerSim


func before() -> void:
	_main = load(SaveTestKit.MAIN).instantiate()
	(_main.get_node("SimClock") as SimClock).seed_rng(SEED)
	(_main.get_node("SimClock") as SimClock).set_paused(true)
	# Isolated settings, set before the scene enters the tree and reads them, so
	# the player's own Departures and Mood choices never reach the test.
	(_main.get_node("PassengerHud") as PassengerHud).alert_settings_path = _settings_path
	(_main.get_node("PassengerHud") as PassengerHud).departures_settings_path = _departures_path
	(_main.get_node("MoodOverlay") as MoodOverlay).settings_path = _mood_path
	add_child(_main)
	_hud = _main.get_node("PassengerHud")
	_staff = _main.get_node("StaffPanel")
	_sim = _main.get_node("PassengerSim")


func after() -> void:
	_main.free()
	DirAccess.remove_absolute(_settings_path)
	DirAccess.remove_absolute(_hints_path)
	DirAccess.remove_absolute(_hints_path + ".tmp")
	DirAccess.remove_absolute(_mood_path)
	DirAccess.remove_absolute(_mood_path + ".tmp")
	DirAccess.remove_absolute(_departures_path)
	DirAccess.remove_absolute(_departures_path + ".tmp")


func before_test() -> void:
	_staff.set_hint_yielded(false)


func _settle() -> void:
	for i in 4:
		await get_tree().process_frame
	_hud.refresh()
	await get_tree().process_frame


func _control(node_name: String) -> Control:
	return _main.find_child(node_name, true, false) as Control


func _rect(node_name: String) -> Rect2:
	var control := _control(node_name)
	assert_object(control).is_not_null()
	return control.get_global_rect()


## A first-time hint showing on the HUD, in the banner's slot.
func _showing_hint() -> Hints:
	# A hint shows once per memory file, so each call starts it afresh.
	DirAccess.remove_absolute(_hints_path)
	var hints := Hints.new()
	hints.forced_mode = Hints.Mode.PROFILE
	hints.settings_path = _hints_path
	hints.hud = _hud
	hints.scene_root = _main
	_hud.add_child(hints)
	auto_free(hints)
	hints._process(0.0)
	hints.advance(Hints.GRACE_S + 0.1, HintRules.read_world(_sim, []), [])
	for i in 8:
		hints.advance(0.25, HintRules.read_world(_sim, []), ["Check-in"])
	assert_bool(hints.is_showing()).is_true()
	return hints


func test_the_three_toggles_are_equal_buttons_stacked_on_the_margin() -> void:
	var hints := _showing_hint()
	await _settle()
	var toggles: Array[Rect2] = [
		_rect("MoodToggle"),
		_rect("DeparturesToggle"),
		hints.find_child("HintsToggle", true, false).get_global_rect(),
	]
	print("TOGGLES %s" % [toggles])
	for i in toggles.size():
		assert_float(toggles[i].size.x).is_equal_approx(HudLayout.TOGGLE_W, 0.5)
		assert_float(toggles[i].size.y).is_equal_approx(HudLayout.BUTTON_H, 0.5)
		assert_float(toggles[i].position.x).is_equal_approx(HudLayout.MARGIN, 0.5)
		assert_float(toggles[i].position.y).is_equal_approx(LeftColumn.slot_top(i), 0.5)
	for i in toggles.size() - 1:
		assert_float(toggles[i + 1].position.y - toggles[i].end.y).is_equal_approx(
			HudLayout.GAP, 0.5
		)
	assert_float(toggles[0].position.y).is_greater_equal(
		MONEY_ROW_BOTTOM + HudLayout.GROUP_GAP - 0.5
	)


func test_the_departures_list_starts_open_on_a_fresh_profile() -> void:
	await _settle()
	var board := _control("DeparturesBoard") as DeparturesBoard
	assert_bool(board.is_shown()).is_true()
	assert_bool(_control("DeparturesPanel").is_visible_in_tree()).is_true()


func test_the_departures_list_opens_under_the_toggles_at_list_width() -> void:
	await _settle()
	var panel := _rect("DeparturesPanel")
	var hints_bottom := LeftColumn.slot_top(LeftColumn.SLOT_HINTS) + HudLayout.BUTTON_H
	print("LIST %s" % [panel])
	assert_float(panel.size.x).is_equal_approx(HudLayout.LIST_W, 0.5)
	assert_float(panel.position.x).is_equal_approx(HudLayout.MARGIN, 0.5)
	assert_float(panel.position.y).is_equal_approx(hints_bottom + HudLayout.GAP, 0.5)


func test_the_checklist_card_sits_under_the_list_at_list_width() -> void:
	await _settle()
	var card := _staff.hint_card().get_global_rect()
	var panel := _rect("DeparturesPanel")
	print("CHECKLIST card=%s list=%s" % [card, panel])
	assert_bool(_staff.hint_card().is_visible_in_tree()).is_true()
	assert_float(card.size.x).is_equal_approx(HudLayout.LIST_W, 0.5)
	assert_float(card.position.x).is_equal_approx(HudLayout.MARGIN, 0.5)
	assert_float(card.position.y).is_greater_equal(panel.end.y)
	assert_float(card.position.y - panel.end.y).is_less_equal(HudLayout.GAP + 1.0)


func test_the_checklist_card_rises_under_the_toggles_when_the_list_is_off() -> void:
	var board := _control("DeparturesBoard") as DeparturesBoard
	board.set_shown(false)
	await _settle()
	var card := _staff.hint_card().get_global_rect()
	var hints_bottom := LeftColumn.slot_top(LeftColumn.SLOT_HINTS) + HudLayout.BUTTON_H
	print("CHECKLIST_NO_LIST card=%s" % [card])
	board.set_shown(true)
	assert_float(card.position.y).is_equal_approx(hints_bottom + HudLayout.GAP, 0.5)


func test_the_checklist_shows_only_unmet_lines() -> void:
	await _settle()
	var unmet := 0
	for line in _staff.card_lines():
		if not line["done"]:
			unmet += 1
	assert_int(unmet).is_greater(0)
	assert_int(_staff.checklist().rows().size()).is_equal(unmet)
	for label in _staff.checklist().row_labels():
		assert_int(label.get_theme_font_size("font_size")).is_equal(HudLayout.CAPTION)


func test_a_ticked_line_is_folded_away_and_an_unmet_one_shows() -> void:
	var card: ChecklistCard = auto_free(ChecklistCard.new())
	var lines: Array[Dictionary] = [
		Checklist.line("ticked", true),
		Checklist.line("unmet", false),
	]
	card.show_lines("Title", lines)
	assert_array(Array(card.row_texts())).contains_exactly(["unmet"])
	assert_int(card.rows().size()).is_equal(1)


func test_a_card_with_every_line_ticked_has_no_rows() -> void:
	var card: ChecklistCard = auto_free(ChecklistCard.new())
	var lines: Array[Dictionary] = [Checklist.line("ticked", true)]
	card.show_lines("Title", lines)
	assert_int(card.rows().size()).is_equal(0)


func test_the_hint_card_takes_the_same_slot() -> void:
	var hints := _showing_hint()
	_staff.set_hint_yielded(true)
	await _settle()
	var card := hints.card().get_global_rect()
	var panel := _rect("DeparturesPanel")
	print("HINT card=%s list=%s" % [card, panel])
	assert_bool(hints.card().is_visible_in_tree()).is_true()
	assert_float(card.size.x).is_equal_approx(HudLayout.LIST_W, 0.5)
	assert_float(card.position.x).is_equal_approx(HudLayout.MARGIN, 0.5)
	assert_float(card.position.y).is_greater_equal(panel.end.y)
	assert_float(card.position.y - panel.end.y).is_less_equal(HudLayout.GAP + 1.0)
	_staff.set_hint_yielded(false)


func test_nothing_in_the_column_reaches_the_money_row() -> void:
	var hints := _showing_hint()
	await _settle()
	var rects: Array[Rect2] = [
		_rect("MoodToggle"),
		_rect("DeparturesToggle"),
		hints.find_child("HintsToggle", true, false).get_global_rect(),
		_rect("DeparturesPanel"),
		_staff.hint_card().get_global_rect(),
		hints.card().get_global_rect(),
	]
	var money_row := Rect2(
		HudLayout.MARGIN,
		HudLayout.MARGIN,
		get_viewport().get_visible_rect().size.x,
		HudLayout.BUTTON_H
	)
	for rect in rects:
		assert_float(rect.position.y).is_greater_equal(money_row.end.y + HudLayout.GROUP_GAP - 0.5)
		assert_bool(rect.intersects(money_row)).is_false()
	var money := _control("MoneySlot")
	if money != null and money.is_visible_in_tree():
		for rect in rects:
			assert_bool(rect.intersects(money.get_global_rect())).is_false()


func test_the_templates_panel_sits_on_the_margin() -> void:
	await _settle()
	var dock := _rect("TemplatesDock")
	print("TEMPLATES %s" % [dock])
	assert_float(dock.position.x).is_equal_approx(HudLayout.MARGIN, 0.5)


## The legend is on a card of its own (plate d_mood_1920: bare 14 px text over
## the dark ground was unreadable), level with the toggle and one gap right of it,
## and it shows only while the overlay is on.
func test_the_mood_legend_sits_on_a_card_beside_the_toggle() -> void:
	var mood := _main.get_node("MoodOverlay") as MoodOverlay
	var legend := _control("MoodLegend") as Label
	var card := legend.get_parent() as PanelContainer
	assert_object(card).is_not_null()
	await _settle()
	assert_bool(card.is_visible_in_tree()).is_false()
	mood.set_shown(true)
	await _settle()
	var toggle := _rect("MoodToggle")
	var rect := card.get_global_rect()
	print("LEGEND toggle=%s card=%s" % [toggle, rect])
	assert_bool(card.is_visible_in_tree()).is_true()
	assert_float(rect.position.x - toggle.end.x).is_equal_approx(HudLayout.GAP, 0.5)
	assert_float(rect.position.y).is_equal_approx(toggle.position.y, 0.5)
	assert_float(rect.size.y).is_equal_approx(HudLayout.BUTTON_H, 0.5)
	assert_bool(rect.encloses(legend.get_global_rect())).is_true()
	mood.set_shown(false)
	await _settle()
	assert_bool(card.is_visible_in_tree()).is_false()
