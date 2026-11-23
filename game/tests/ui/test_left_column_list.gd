class_name TestLeftColumnList
extends GdUnitTestSuite
## The card under the departures list follows the list's settled bottom (decision
## checklist-card-moves-to-the-top-left-column-slim-at-304-px-t): when rows grow
## (e.g. a doors-close or extra flight row) and later drop out, the PanelContainer
## shrinks back to its minimum and the card top is the list's bottom plus GAP.

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
	_board.set_shown(true)
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


func test_the_list_grows_and_shrinks_back_when_a_flight_is_added_and_drops_out() -> void:
	await _settle()
	_assert_card_under_list("two flights")
	var two := _panel().size.y
	var terms := TestFlightContracts.terms("Z", 15 * 60)
	terms["destination"] = "Paris"
	assert_bool(_sim.accept_contract(terms)).is_true()
	_board.refresh()
	await _settle()
	_assert_card_under_list("three flights")
	assert_float(_panel().size.y).is_greater(two)
	# By 12:00 the 10:00 flight has left, leaving Y (Doors closed) and Z (doors close 14:57).
	for t in range(_sim.tick + 1, GameCalendar.tick_at(0, 12 * 60, 0) + 1):
		_sim.on_tick(t)
	_clock.tick = _sim.tick
	_board.refresh()
	await _settle()
	_assert_card_under_list("after noon")
	assert_float(_panel().size.y).is_equal_approx(two, 0.5)


func test_the_list_shrinks_and_the_card_rises_when_rows_drop_out() -> void:
	await _settle()
	var full := _panel().size.y
	# By 12:00 the 10:00 flight has left, so its row drops out.
	for t in range(_sim.tick + 1, GameCalendar.tick_at(0, 12 * 60, 0) + 1):
		_sim.on_tick(t)
	_clock.tick = _sim.tick
	_board.refresh()
	await _settle()
	print("LIST rows after noon: %s" % [_board.shown_lines()])
	assert_float(_panel().size.y).is_less(full)
	_assert_card_under_list("rows dropped")
