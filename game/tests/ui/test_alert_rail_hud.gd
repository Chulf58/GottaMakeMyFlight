class_name TestAlertRailHud
extends GdUnitTestSuite
## The right rail in PassengerHud (HUD 3/7, decision hud-grid-and-rails-one-
## spacing-grid-centred-top-row-right-ra, parts 1 and 3): the clock panel sits
## on the margin at the top right, RAIL_W wide; the rail starts GROUP_GAP under
## the panel's real bottom however many flights it lists, never overlaps it,
## stops above the build tray, and PanelRoom cuts the rail's rectangle. Layout
## px 1536x864.

const VIEW := Vector2i(1536, 864)

var _port: SubViewport
var _world: PassengerTestWorld
var _hud: PassengerHud


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(8, 6))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 5), 3)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(10, 20))
	_world.flights.open_airport()
	_port = SubViewport.new()
	_port.size = VIEW
	add_child(_port)
	_hud = PassengerHud.new()
	_hud.clock = _world.clock
	_hud.flights = _world.flights
	_hud.sim = _world.sim
	_hud.alert_settings_path = SaveTestKit.run_path("alert_rail_hud_setting")
	_port.add_child(_hud)


func after_test() -> void:
	DirAccess.remove_absolute(_hud.alert_settings_path)
	_port.free()
	_world.free_all()


func _stack() -> AlertStack:
	return _hud.find_child("AlertStack", false, false) as AlertStack


func _panel() -> Rect2:
	return (_hud.find_child("FlightPanel", false, false) as Control).get_global_rect()


## Refreshes and lets the containers lay out, twice, since the rail reads the
## panel's laid-out bottom.
func _settle() -> void:
	for i in 3:
		_hud.refresh()
		await get_tree().process_frame


func _close_doors_with_misses(count: int) -> void:
	for i in count:
		_world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.run_to(21)
	_hud.refresh()


func _accept(count: int) -> void:
	for i in count:
		var terms := TestFlightContracts.terms("C%d" % i, 7 * 60 + (i + 1) * 195)
		assert_bool(_world.flights.accept_contract(terms)).is_true()


func test_the_clock_panel_sits_on_the_margin_at_the_top_right() -> void:
	await _settle()
	var panel := _panel()
	print("RAIL_CLOCK panel=%s" % panel)
	var left := VIEW.x - HudLayout.MARGIN - HudLayout.RAIL_W
	assert_float(panel.position.x).is_equal_approx(left, 0.5)
	assert_float(panel.position.y).is_equal_approx(HudLayout.MARGIN, 0.5)
	assert_float(panel.size.x).is_equal_approx(HudLayout.RAIL_W, 0.5)


func test_the_rail_starts_a_group_gap_under_the_clock_panel_for_one_and_four_flights() -> void:
	await _settle()
	var one := _panel()
	var rail := _stack().get_global_rect()
	print("RAIL_ONE panel=%s rail=%s" % [one, rail])
	assert_float(rail.position.y).is_equal_approx(one.end.y + HudLayout.GROUP_GAP, 0.5)
	assert_float(rail.position.x).is_equal_approx(one.position.x, 0.5)
	assert_float(rail.size.x).is_equal_approx(HudLayout.RAIL_W, 0.5)
	_accept(3)
	await _settle()
	var four := _panel()
	rail = _stack().get_global_rect()
	print("RAIL_FOUR panel=%s rail=%s" % [four, rail])
	# Control: four flights make the panel taller than one does.
	assert_float(four.end.y).is_greater(one.end.y)
	assert_float(rail.position.y).is_equal_approx(four.end.y + HudLayout.GROUP_GAP, 0.5)


func test_the_result_card_sits_on_the_rail_clear_of_the_panel_and_the_tray() -> void:
	_accept(3)
	_close_doors_with_misses(3)
	await _settle()
	assert_bool(_hud.is_result_open()).is_true()
	var card := _stack().notice_card(PassengerHud.RESULT_KEY).get_global_rect()
	var panel := _panel()
	var stop := _stop(false)
	print("RAIL_RESULT card=%s panel=%s stop=%.1f" % [card, panel, stop])
	assert_float(card.size.y).is_greater(HudLayout.BUTTON_H)
	assert_bool(card.intersects(panel)).is_false()
	assert_float(card.position.y).is_greater_equal(panel.end.y + HudLayout.GROUP_GAP)
	assert_float(card.end.y).is_less_equal(stop)
	assert_float(card.size.x).is_equal_approx(HudLayout.RAIL_W, 0.5)


## Five wrapped cards arrive while the history tray is open, so none has been
## laid out, and then the tray closes: more than the room above the build tray
## holds. The newest shows, and a card that does not fit is never visible, not
## after the tray closes, not after a refresh and not on any frame, including
## the frame before it is first laid out. The fit rule, not the cap, holds
## them back.
func test_a_card_that_does_not_fit_is_never_visible() -> void:
	await _settle()
	var stack := _stack()
	var cards: Array[Control] = []
	var seen := {}
	stack.set_tray_open(true)
	var long := "Check-in queue full: three desks full, passengers wait outside the hall"
	for i in 5:
		var card := PanelContainer.new()
		var column := VBoxContainer.new()
		card.add_child(column)
		for line in 4:
			var label := Label.new()
			label.text = "%s (%d)" % [long, i]
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			column.add_child(label)
		cards.append(card)
		stack.post_notice(StringName("tall%d" % i), card, 0.0, "Tall %d" % i, long)
	_note_visible(cards, seen)
	assert_bool(seen.is_empty()).is_true()
	stack.set_tray_open(false)
	_note_visible(cards, seen)
	for frame in 4:
		_hud.refresh()
		_note_visible(cards, seen)
		await get_tree().process_frame
		_note_visible(cards, seen)
	var shown := stack.shown_keys()
	print("RAIL_FIT shown=%s more=%d ever_visible=%s" % [shown, stack.more_count(), seen.keys()])
	assert_bool(seen.has(4)).is_true()
	assert_int(shown.size()).is_less(AlertStack.MAX_CARDS)
	assert_int(stack.more_count()).is_equal(cards.size() - shown.size())
	for i in cards.size() - shown.size():
		assert_bool(seen.has(i)).override_failure_message("card %d was visible" % i).is_false()
	var stop := _stop(false)
	assert_float(stack.room_rect().end.y).is_less_equal(stop)


## Two wrapped cards that fit together arrive while the tray is open; once it
## closes both show at once. A card that was never laid out is measured at the
## rail's width, not at the 1 px its wrapped labels have while hidden, which
## would keep it hidden for good.
func test_cards_that_fit_show_as_soon_as_the_tray_closes() -> void:
	await _settle()
	var stack := _stack()
	stack.set_tray_open(true)
	for i in 2:
		var card := PanelContainer.new()
		var label := Label.new()
		label.text = "A short wrapped notice that takes two lines on the rail (%d)" % i
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(label)
		stack.post_notice(StringName("short%d" % i), card, 0.0, "Short %d" % i, "")
	stack.set_tray_open(false)
	print("RAIL_SHORT shown=%s more=%d" % [stack.shown_keys(), stack.more_count()])
	assert_array(stack.shown_keys()).is_equal([&"short1", &"short0"])
	for frame in 3:
		_hud.refresh()
		await get_tree().process_frame
	assert_array(stack.shown_keys()).is_equal([&"short1", &"short0"])
	assert_int(stack.more_count()).is_equal(0)


## The rail's lowest y: GROUP_GAP above the category bar, or above the whole
## build tray stack while the tray is open.
func _stop(tray_open: bool) -> float:
	var below := BuildMenu.tray_stack_top() if tray_open else BuildMenu.MARGIN + BuildMenu.BAR_H
	return VIEW.y - below - HudLayout.GROUP_GAP


## With the build tray closed the rail runs down to the bar; opening the tray
## sends the cards that would run into it to '+N more', and closing it brings
## them back.
func test_opening_the_build_tray_sends_cards_that_would_meet_it_to_more() -> void:
	await _settle()
	var stack := _stack()
	var tray := [false]
	stack.build_tray_open = func() -> bool: return tray[0]
	for i in 3:
		var card := PanelContainer.new()
		var label := Label.new()
		label.text = "Notice %d\nwith a second line\nand a third\nand a fourth" % i
		card.add_child(label)
		stack.post_notice(StringName("n%d" % i), card, 0.0, "Notice %d" % i, "")
	await _settle()
	var closed := stack.room_rect()
	print(
		"RAIL_TRAY closed shown=%s rail=%s stop=%.0f" % [stack.shown_keys(), closed, _stop(false)]
	)
	assert_int(stack.shown_keys().size()).is_equal(3)
	assert_float(closed.end.y).is_less_equal(_stop(false))
	# Control: the three cards reach below where the open tray's stack starts.
	assert_float(closed.end.y).is_greater(_stop(true))
	tray[0] = true
	await _settle()
	var opened := stack.room_rect()
	print(
		"RAIL_TRAY open shown=%s more=%d rail=%s" % [stack.shown_keys(), stack.more_count(), opened]
	)
	assert_int(stack.shown_keys().size()).is_less(3)
	assert_int(stack.more_count()).is_equal(3 - stack.shown_keys().size())
	assert_float(opened.end.y).is_less_equal(_stop(true))
	tray[0] = false
	await _settle()
	assert_int(stack.shown_keys().size()).is_equal(3)


func _note_visible(cards: Array[Control], seen: Dictionary) -> void:
	for i in cards.size():
		if cards[i].is_visible_in_tree():
			seen[i] = true


## HUD 4/7 puts the checklist and hint cards in a top-left column (x 16, 304
## wide, from y 216); with the rail on the right, the camera's free room is the
## band between them, the full height, not a strip above or below either.
func test_a_left_column_and_the_rail_leave_the_middle_free() -> void:
	var view := Rect2(Vector2.ZERO, Vector2(VIEW))
	var column := Rect2(HudLayout.MARGIN, 216.0, HudLayout.LIST_W, 200.0)
	var rail_x := VIEW.x - HudLayout.MARGIN - HudLayout.RAIL_W
	var rail := Rect2(rail_x, 260.0, HudLayout.RAIL_W, 240.0)
	var panels: Array[Rect2] = [column, rail]
	var free := PanelRoom.free_rect(view, panels)
	print("RAIL_FREE column=%s rail=%s free=%s" % [column, rail, free])
	assert_float(free.position.x).is_equal_approx(column.end.x, 0.5)
	assert_float(free.end.x).is_equal_approx(rail.position.x, 0.5)
	assert_float(free.size.y).is_equal_approx(VIEW.y, 0.5)


## Measuring a card must not resize what its container laid out: the result
## card's Dismiss button (shrink to the end) keeps its own width inside the card
## frame after frame, as the windowed plate showed when it did not.
func test_measuring_keeps_the_dismiss_button_inside_the_result_card() -> void:
	_close_doors_with_misses(1)
	await _settle()
	var card := _stack().notice_card(PassengerHud.RESULT_KEY)
	var button := card.find_child("DismissResult", true, false) as Button
	var rect := card.get_global_rect()
	var at := button.get_global_rect()
	print("RAIL_DISMISS card=%s button=%s min=%s" % [rect, at, button.get_combined_minimum_size()])
	assert_float(at.size.x).is_equal_approx(button.get_combined_minimum_size().x, 0.5)
	assert_bool(rect.encloses(at)).is_true()


func test_panel_room_cuts_the_rail_rect_with_the_result_card_in_it() -> void:
	_close_doors_with_misses(1)
	await _settle()
	var room := _hud.get_node("PanelRoom") as PanelRoom
	var rail := _stack().room_rect()
	var card := _stack().notice_card(PassengerHud.RESULT_KEY).get_global_rect()
	print("RAIL_ROOM rail=%s card=%s rects=%s" % [rail, card, room.open_rects()])
	assert_bool(rail.encloses(card)).is_true()
	assert_bool(room.open_rects().has(rail)).is_true()
	_hud.dismiss_result()
	await _settle()
	assert_bool(_stack().room_rect().has_area()).is_false()
	assert_bool(room.open_rects().has(rail)).is_false()
