class_name TestLeftColumnList
extends GdUnitTestSuite
## The card under the departures list follows the list's settled bottom (decision
## checklist-card-moves-to-the-top-left-column-slim-at-304-px-t): the list is a
## child of a plain Control, so its height is its minimum (the control keeps the
## size it was asked for, and a larger minimum only clamps it). After a gate
## picker opens and closes, or rows drop out, the panel is back at its minimum
## and the card top is the list's bottom plus GAP, so the two never overlap.

const GATES: Array[String] = ["C", "A", "B"]

var _sim: FlightSim
var _clock: SimClock
var _board: DeparturesBoard
var _card: PanelContainer
var _path := SaveTestKit.run_path("left_column_list_board")


func before_test() -> void:
	_sim = auto_free(FlightSim.new()) as FlightSim
	_clock = auto_free(SimClock.new()) as SimClock
	_sim.open_airport()
	_sim.gate_source = func() -> Array[String]: return GATES
	for spec: Array in [["X", 600, "Oslo"], ["Y", 660, "Rome"]]:
		var terms := TestFlightContracts.terms(spec[0], spec[1])
		terms["destination"] = spec[2]
		assert_bool(_sim.accept_contract(terms)).is_true()
	_board = DeparturesBoard.new()
	_board.settings_path = _path
	_board.flights = _sim
	_board.clock = _clock
	add_child(_board)
	_card = PanelContainer.new()
	var label := Label.new()
	label.text = "card"
	_card.add_child(label)
	add_child(_card)
	LeftColumn.dock_card(_card)
	_board.refresh()


func after_test() -> void:
	_board.free()
	_card.free()
	DirAccess.remove_absolute(_path)
	DirAccess.remove_absolute(_path + ".tmp")


func _panel() -> Control:
	return _board.find_child("DeparturesPanel", true, false) as Control


## Lets layout settle, then moves the card as its owner does every frame.
func _settle() -> void:
	for i in 3:
		await get_tree().process_frame
	LeftColumn.follow(_card)
	await get_tree().process_frame


## Asserts the panel is at its minimum height and the card is GAP under it.
func _assert_card_under_list(label: String) -> void:
	var panel := _panel()
	var rect := panel.get_global_rect()
	print(
		(
			"LIST %s panel=%s min=%s card_top=%.1f"
			% [label, rect, panel.get_combined_minimum_size(), _card.offset_top]
		)
	)
	assert_float(rect.size.y).is_equal_approx(panel.get_combined_minimum_size().y, 0.5)
	assert_float(_card.get_global_rect().position.y).is_equal_approx(
		rect.end.y + HudLayout.GAP, 0.5
	)


func test_the_list_shrinks_back_and_the_card_follows_when_a_picker_closes() -> void:
	await _settle()
	_assert_card_under_list("closed")
	var closed := _panel().size.y
	_board.gate_button("X", 0).pressed.emit()
	await _settle()
	var opened := _panel().size.y
	_assert_card_under_list("picker open")
	assert_float(opened).is_greater(closed)
	_board.gate_button("X", 0).pressed.emit()
	await _settle()
	_assert_card_under_list("picker closed")
	assert_float(_panel().size.y).is_equal_approx(closed, 0.5)


func test_the_list_shrinks_and_the_card_rises_when_rows_drop_out() -> void:
	await _settle()
	var full := _panel().size.y
	# By 12:00 the 10:00 flight has left, so its row drops out.
	for t in range(_sim.tick + 1, GameCalendar.tick_at(0, 12 * 60) + 1):
		_sim.on_tick(t)
	_clock.tick = _sim.tick
	_board.refresh()
	await _settle()
	print("LIST rows after noon: %s" % [_board.shown_lines()])
	assert_float(_panel().size.y).is_less(full)
	_assert_card_under_list("rows dropped")
