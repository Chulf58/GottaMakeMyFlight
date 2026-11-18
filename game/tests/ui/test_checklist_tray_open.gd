class_name TestChecklistTrayOpen
extends GdUnitTestSuite
## The checklist card never collapses to its title alone while it has unmet
## lines (board D3a point 5): however little room it is given, with the Gates
## tray open or not, it shows the title and a "+N more" line for what is folded
## away, and every line again once the room is there.

const SEED := 4_070_094

var _main: Node
var _alerts := SaveTestKit.run_path("checklist_tray_alerts")


func before() -> void:
	_main = load(SaveTestKit.MAIN).instantiate()
	(_main.get_node("SimClock") as SimClock).seed_rng(SEED)
	(_main.get_node("SimClock") as SimClock).set_paused(true)
	(_main.get_node("PassengerHud") as PassengerHud).alert_settings_path = _alerts
	add_child(_main)


func after() -> void:
	_main.free()
	DirAccess.remove_absolute(_alerts)
	DirAccess.remove_absolute(_alerts + ".tmp")


func _settle() -> void:
	for i in 5:
		await get_tree().process_frame


func _shown_rows(card: ChecklistCard) -> int:
	return card.rows().filter(func(row: Node) -> bool: return (row as Control).visible).size()


func _more(card: ChecklistCard) -> Label:
	return card.find_child("ChecklistMore", true, false) as Label


func _lines(count: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in count:
		out.append(Checklist.line("Need number %d that wraps onto a second line" % i, false))
	return out


## For every room from nothing up to plenty: the title shows, and the card shows
## either every line or a "+N more" line that counts exactly the folded ones.
func test_no_room_leaves_the_title_and_a_count_never_the_title_alone() -> void:
	var card: ChecklistCard = auto_free(ChecklistCard.new())
	card.custom_minimum_size.x = float(HudLayout.LIST_W)
	add_child(card)
	card.show_lines("To open the airport", _lines(5))
	await _settle()
	var room := 0.0
	while room <= 400.0:
		card.fit(room)
		var shown := _shown_rows(card)
		var more := _more(card)
		if shown < 5:
			assert_bool(more.visible).override_failure_message("room %.0f" % room).is_true()
			assert_str(more.text).is_equal("+%d more" % (5 - shown))
		else:
			assert_bool(more.visible).is_false()
		assert_bool(card.title_label().visible).is_true()
		room += 10.0
	card.fit(0.0)
	print("ROOM 0 shown=%d more=%s" % [_shown_rows(card), _more(card).text])
	assert_int(_shown_rows(card)).is_equal(0)
	assert_str(_more(card).text).is_equal("+5 more")
	card.fit(400.0)
	assert_int(_shown_rows(card)).is_equal(5)


## The real scene with the Gates tray open and a card standing over the column,
## so the staff panel's checklist is given almost no room: it keeps its title and
## says how many lines it folded, and gets them back when the card goes.
func test_with_the_gates_tray_open_a_tight_room_keeps_the_title_and_a_more_line() -> void:
	await _settle()
	var menu := _main.find_child("BuildMenu", true, false) as BuildMenu
	var panel := _main.find_child("StaffPanel", true, false) as StaffPanel
	var card := panel.checklist()
	var box := panel.hint_card()
	for i in BuildMenu.CATEGORIES.size():
		if BuildMenu.CATEGORIES[i]["name"] == "Gates":
			menu.press_category(i)
	await _settle()
	assert_bool(menu.is_tray_open()).is_true()
	var rows := card.rows().size()
	assert_int(rows).is_greater(1)
	var roomy := _shown_rows(card)
	var floor_card := Control.new()
	floor_card.position = Vector2(HudLayout.MARGIN, box.offset_top + 24.0)
	floor_card.size = Vector2(300.0, 200.0)
	floor_card.add_to_group(LeftColumn.FLOOR_GROUP)
	add_child(floor_card)
	await _settle()
	var tight := _shown_rows(card)
	var more_text := _more(card).text
	var title_visible := card.title_label().is_visible_in_tree()
	var more_visible := _more(card).is_visible_in_tree()
	print("TRAY OPEN rows=%d roomy=%d tight=%d more='%s'" % [rows, roomy, tight, more_text])
	floor_card.free()
	await _settle()
	var back := _shown_rows(card)
	assert_int(roomy).is_equal(rows)
	assert_int(tight).is_less(rows)
	assert_bool(title_visible).is_true()
	assert_bool(more_visible).is_true()
	assert_str(more_text).is_equal("+%d more" % (rows - tight))
	assert_int(back).is_equal(rows)
